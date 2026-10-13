"""Recover PktMon frame fragments when its ETL converter skips circular buffers."""
import struct
import sys
import argparse
from pathlib import Path
from scapy.all import Ether, IP, TCP, wrpcap

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("destination", type=Path)
parser.add_argument("--mac", required=True, help="Capture NIC MAC, e.g. 02:00:00:00:00:01")
args = parser.parse_args()
source = args.source
destination = args.destination
data = source.read_bytes()
mac = bytes.fromhex(args.mac.replace(":", "").replace("-", ""))
if len(mac) != 6:
    parser.error("MAC must contain six bytes")
packets = []
seen = set()
cursor = 0
while True:
    pos = data.find(mac, cursor)
    if pos < 0:
        break
    cursor = pos + 6
    for start in (pos, pos - 6):
        if start < 4 or start in seen or data[start+12:start+14] != b"\x08\0":
            continue
        full, captured = struct.unpack_from("<HH", data, start-4)
        if not 54 <= captured <= full <= 65535 or start+captured > len(data):
            continue
        raw = bytearray(data[start:start+captured])
        if raw[14] != 0x45 or raw[23] != 6:
            continue
        # Preserve all PktMon fragments, including VirtIO offloaded TCP payload.
        ip_size = struct.unpack_from(">H", raw, 16)[0]
        if captured > 66 and ip_size+14 < captured:
            struct.pack_into(">H", raw, 16, captured-14)
        packet = Ether(bytes(raw))
        if TCP not in packet or (packet[TCP].sport != 7777 and packet[TCP].dport != 7777):
            continue
        seen.add(start)
        packets.append((start, packet))
        print(hex(start), full, captured, packet[IP].src, packet[TCP].sport,
              packet[IP].dst, packet[TCP].dport, str(packet[TCP].flags),
              packet[TCP].seq, len(bytes(packet[TCP].payload)))
packets.sort(key=lambda value: value[0])
wrpcap(str(destination), [packet for _, packet in packets])
print("RECOVERED_PACKETS", len(packets), "OUTPUT", destination)
