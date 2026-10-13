"""Bounded C2 login/server-selection and game-protocol smoke test."""
import argparse
import os
import socket
import struct
from pathlib import Path
from Crypto.Cipher import Blowfish

HOST = os.environ.get("L2_HOST", "176.53.225.183")
KEY = bytes.fromhex("5b3b272e5d39342d33313d3d2d252640215e2b5d00")


def exact(sock, size):
    out = bytearray()
    while len(out) < size:
        part = sock.recv(size - len(out))
        if not part:
            raise EOFError(f"EOF after {len(out)}/{size} bytes")
        out.extend(part)
    return bytes(out)


def recv_packet(sock):
    size = struct.unpack("<H", exact(sock, 2))[0]
    if not 3 <= size <= 8192:
        raise ValueError(f"Invalid frame length: {size}")
    return exact(sock, size - 2)


def swap_words(data):
    return b"".join(data[i:i + 4][::-1] for i in range(0, len(data), 4))


def crypt(data, decrypt=False):
    cipher = Blowfish.new(KEY, Blowfish.MODE_ECB)
    operation = cipher.decrypt if decrypt else cipher.encrypt
    return swap_words(operation(swap_words(data)))


def pack_auth(data):
    data += b"\0" * (-len(data) % 8)
    checksum = 0
    for value, in struct.iter_unpack("<I", data):
        checksum ^= value
    data += struct.pack("<II", checksum, 0)
    return crypt(data)


def recv_auth(sock, label):
    encrypted = recv_packet(sock)
    data = crypt(encrypted, decrypt=True)
    # EncryptPacket aligns the body, writes its XOR, then reserves 8 bytes:
    # the checksum is at -8; the final DWORD is padding, not the checksum.
    checksum = 0
    for value, in struct.iter_unpack("<I", data[:-8]):
        checksum ^= value
    expected = struct.unpack_from("<I", data, len(data)-8)[0]
    mismatch = checksum ^ expected
    if mismatch:
        if os.environ.get("L2_ALLOW_LEGACY_CHECKSUM") == "1":
            # Explicitly opt into diagnosing old buffers; not a passing test.
            print(f"{label}: WARNING outgoing checksum mismatch {mismatch:08x}")
        else:
            raise ValueError(f"{label}: checksum mismatch {mismatch:08x}")
    print(f"{label}: {data.hex(' ')}")
    return data


def send(sock, data):
    sock.sendall(struct.pack("<H", len(data) + 2) + data)

def record_packet(name, data):
    folder = os.environ.get("L2_PACKET_DUMP_DIR")
    if folder:
        directory = Path(folder)
        directory.mkdir(parents=True, exist_ok=True)
        (directory/name).write_bytes(data)


def test_auth(keep_play=False, agreement_only=False):
    with socket.create_connection((HOST, 2106), timeout=10) as sock:
        sock.settimeout(15)
        init = recv_packet(sock)
        print("INIT:", init.hex(" "))
        assert init[0] == 0 and struct.unpack_from("<I", init, 5)[0] == 30810
        account = os.environ["L2_TEST_USER"].encode("ascii")
        password = os.environ["L2_TEST_PASS"].encode("ascii")
        credentials = account.ljust(14, b"\0") + password.ljust(16, b"\0")
        assert len(credentials) == 30
        send(sock, pack_auth(b"\0" + credentials + struct.pack("<IH", 0, 0)))
        result = recv_auth(sock, "LOGIN")
        if result[0] != 3:
            raise RuntimeError(f"Login rejected: opcode={result[0]} reason={result[1]}")
        uid, session = struct.unpack_from("<II", result, 1)
        # Engine.dll C2 485 RequestServerList uses format 4 after Agree.
        frame_format = int(os.environ.get("L2_LIST_FORMAT", "4"))
        send(sock, pack_auth(b"\x05" + struct.pack("<IIB", uid, session, frame_format)))
        servers = recv_auth(sock, "SERVER_LIST")
        assert servers[0] == 4 and servers[1] > 0, "Server list unavailable"
        # This binary returns the compact frame for format 0:
        # opcode, count, then (id, IPv4, uint32 port), without last-world.
        offset = 2 if frame_format == 0 else 3
        server_id = servers[offset]
        print("ADVERTISED_WORLD:", server_id, socket.inet_ntoa(servers[offset+1:offset+5]),
              struct.unpack_from("<I", servers, offset+5)[0])
        if frame_format == 4:
            # Native C2 parser: count,lastWorld, then cddcchhcdc per world.
            assert len(servers) >= 3 + 21 * servers[1], "Truncated C2 server-list frame"
            online, limit = struct.unpack_from("<HH", servers, offset+11)
            status = servers[offset+15]
            kind = struct.unpack_from("<I", servers, offset+16)[0]
            flags = servers[offset+20]
            print("C2_WORLD_FIELDS:", f"online={online} limit={limit} status={status}",
                  f"kind={kind} flags={flags}")
            assert status == 1, "World is advertised offline"
            # Patched historical AuthD builds may leave the final C2 flag in
            # padding. Do not infer admission policy from it by default.
            if os.environ.get("L2_STRICT_WORLD_FLAGS") == "1":
                assert not flags & 4, "World has a client-filtered flag"
        if agreement_only:
            send(sock, pack_auth(b"\x03" + struct.pack("<II", uid, session)))
            print("C2_AGREEMENT_AND_SERVER_LIST_OK; login cancelled")
            return None
        send(sock, pack_auth(b"\x02" + struct.pack("<IIB", uid, session, server_id)))
        play = recv_auth(sock, "PLAY")
        if play[0] != 7:
            raise RuntimeError(f"World selection rejected: opcode={play[0]} reason={play[1]}")
        print("AUTH_AND_WORLD_SELECTION_OK")
        keys = struct.unpack_from("<II", play, 1)
        if not keep_play:
            # Cancel the synthetic session, without creating a character.
            send(sock, pack_auth(b"\x03" + struct.pack("<II", uid, session)))
        return uid, session, keys


class GameCrypt:
    def __init__(self, low):
        self.key = bytearray(struct.pack("<II", low, 0x87546CA1))

    def apply(self, data, decrypt=False):
        out = bytearray(data)
        previous = 0
        for i, value in enumerate(out):
            out[i] = value ^ self.key[i % 8] ^ previous
            previous = value if decrypt else out[i]
        low = (struct.unpack_from("<I", self.key, 0)[0] + len(out)) & 0xffffffff
        struct.pack_into("<I", self.key, 0, low)
        return bytes(out)


def test_character_list(protocol, enter_world=False):
    uid, login_session, (play_session, play_uid) = test_auth(keep_play=True)
    with socket.create_connection((HOST, 7777), timeout=10) as sock:
        sock.settimeout(15)
        send(sock, b"\0" + struct.pack("<I", protocol))
        key_packet = recv_packet(sock)
        print("GAME_KEY:", key_packet.hex(" "))
        assert key_packet[0:2] == b"\x00\x01", "Game protocol rejected"
        low = struct.unpack_from("<I", key_packet, 2)[0]
        outbound, inbound = GameCrypt(low), GameCrypt(low)
        name = os.environ.get("L2_TEST_USER", "test").encode("utf-16le") + b"\0\0"
        # RequestAuthLogin: name, play key 2, play key 1, login key 1, login key 2.
        packet = b"\x08" + name + struct.pack("<IIII", play_uid, play_session, uid, login_session)
        send(sock, outbound.apply(packet))
        response = inbound.apply(recv_packet(sock), decrypt=True)
        print("GAME_LOGIN_RESPONSE:", response.hex(" "))
        assert response[0] == 0x13, f"Not a character list: opcode={response[0]}"
        count = struct.unpack_from("<I", response, 1)[0]
        print(f"CHARACTER_SELECTION_OK count={count}; no character created")
        if enter_world:
            assert count > 0, "No character to select"
            slot = int(os.environ.get("L2_CHARACTER_SLOT", "0"))
            send(sock, outbound.apply(b"\x0d" + struct.pack("<I", slot)))
            selected = inbound.apply(recv_packet(sock), decrypt=True)
            record_packet("char_selected.bin", selected)
            print("CHAR_SELECTED:", f"len={len(selected)}", selected[:300].hex(" "))
            assert selected[0] == 0x15, f"Not CharSelected: opcode={selected[0]}"
            send(sock, outbound.apply(b"\x63"))
            send(sock, outbound.apply(b"\x03" + struct.pack("<I", 0)))
            sock.settimeout(5)
            got_user_info = False
            packets = 0
            try:
                while packets < 35:
                    packet = inbound.apply(recv_packet(sock), decrypt=True)
                    packets += 1
                    print("WORLD_PACKET:", f"opcode={packet[0]:02x} len={len(packet)}",
                          packet[:160].hex(" "))
                    if packet[0] == 4:
                        got_user_info = True
                        record_packet("user_info.bin", packet)
                    if packet[0] == 0x16:
                        record_packet("npc_info.bin", packet)
            except (EOFError, TimeoutError) as exc:
                print("WORLD_READ_END:", type(exc).__name__, str(exc))
            print("WORLD_USER_INFO:", got_user_info, "packets:", packets)
            # Logout only our diagnostic connection, never move the character.
            send(sock, outbound.apply(b"\x09"))


def test_game(protocol):
    with socket.create_connection((HOST, 7777), timeout=10) as sock:
        sock.settimeout(10)
        send(sock, b"\0" + struct.pack("<I", protocol))
        try:
            data = recv_packet(sock)
            print(f"GAME_PROTOCOL_{protocol}:", data.hex(" "))
            return data
        except (EOFError, TimeoutError) as exc:
            print(f"GAME_PROTOCOL_{protocol}: {type(exc).__name__}: {exc}")
            return None


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--auth", action="store_true")
    parser.add_argument("--protocol", type=int)
    parser.add_argument("--character-list", type=int, metavar="PROTOCOL")
    parser.add_argument("--agreement", action="store_true")
    parser.add_argument("--enter-world", type=int, metavar="PROTOCOL")
    args = parser.parse_args()
    if args.auth or args.agreement or args.character_list is not None or args.enter_world is not None:
        if not os.environ.get("L2_TEST_USER") or not os.environ.get("L2_TEST_PASS"):
            parser.error("Set L2_TEST_USER and L2_TEST_PASS for a separate, offline diagnostic account")
        if os.environ.get("L2_ALLOW_LOGIN_PROBE") != "1":
            parser.error("Login probes may kick a duplicate session; set L2_ALLOW_LOGIN_PROBE=1 explicitly")
    if args.auth:
        test_auth()
    if args.agreement:
        test_auth(agreement_only=True)
    if args.protocol is not None:
        test_game(args.protocol)
    if args.character_list is not None:
        test_character_list(args.character_list)
    if args.enter_world is not None:
        test_character_list(args.enter_world, enter_world=True)
