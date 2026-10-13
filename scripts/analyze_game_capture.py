"""Reassemble and decrypt captured C2 TCP frames; never alters server state."""
import collections
import struct
import sys
from scapy.all import Ether, IP, IPv6, TCP, RawPcapReader
from probe_c2 import GameCrypt

path = sys.argv[1]
streams = collections.defaultdict(dict)
first = {}
for raw, meta in RawPcapReader(path):
    packet = Ether(raw)
    if TCP not in packet:
        continue
    tcp = packet[TCP]
    if tcp.sport != 7777 and tcp.dport != 7777:
        continue
    ip = packet[IP] if IP in packet else packet[IPv6]
    flow = (ip.src, tcp.sport, ip.dst, tcp.dport)
    if flow not in first:
        first[flow] = (tcp.seq, str(tcp.flags))
    payload_size = max(0, ip.len - ip.ihl*4 - tcp.dataofs*4) if IP in packet else len(bytes(tcp.payload))
    payload = bytes(tcp.payload)[:payload_size]
    if payload:
        streams[flow][tcp.seq] = payload


def reassemble(segments):
    data = bytearray()
    cursor = None
    for seq, payload in sorted(segments.items()):
        if cursor is None:
            cursor = seq
        if seq > cursor:
            print("WARNING TCP GAP:", cursor, seq)
            break
        overlap = max(0, cursor - seq)
        data.extend(payload[overlap:])
        cursor = max(cursor, seq + len(payload))
    return bytes(data)


def frames(data):
    result = []
    while data:
        if len(data) < 2:
            print("WARNING trailing TCP bytes", data.hex())
            break
        size = struct.unpack_from("<H", data)[0]
        if size < 3 or size > len(data):
            print("WARNING incomplete frame", size, len(data), data[:24].hex())
            break
        result.append(data[2:size])
        data = data[size:]
    return result


seen = set()
for flow in streams:
    server = flow if flow[1] == 7777 else (flow[2], flow[3], flow[0], flow[1])
    if server in seen:
        continue
    seen.add(server)
    client = (server[2], server[3], server[0], server[1])
    outgoing = frames(reassemble(streams[server]))
    incoming = frames(reassemble(streams[client]))
    print("\nSESSION", server, "first", first.get(server), first.get(client))
    if not outgoing or outgoing[0][:2] != b"\x00\x01":
        print("NO INITIAL GAME KEY; RAW PACKETS", len(outgoing), len(incoming))
        continue
    low = struct.unpack_from("<I", outgoing[0], 2)[0]
    print("GAME KEY", outgoing[0].hex(" "))
    for direction, packets in (("CLIENT", incoming), ("SERVER", outgoing)):
        cipher = GameCrypt(low)
        print(direction, "PACKETS", len(packets))
        for index, data in enumerate(packets):
            if index == 0:
                plain = data
            else:
                plain = cipher.apply(data, decrypt=True)
            print(direction, index, f"opcode={plain[0]:02x}", f"len={len(plain)}",
                  plain[:200].hex(" "), "..." if len(plain) > 200 else "")
