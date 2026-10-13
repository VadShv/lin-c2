"""Check captured world packets against the actual Engine.dll 485 read formats."""
import struct
import sys
import zipfile
from pathlib import Path
import pefile
import argparse

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("directory", type=Path, help="Private packet dump directory")
parser.add_argument("--overlay", type=Path, required=True, help="Private ZIP containing system/Engine.dll")
args = parser.parse_args()
directory = args.directory
with zipfile.ZipFile(args.overlay) as archive:
    engine = pefile.PE(data=archive.read("system/Engine.dll"))

def client_format(va):
    return engine.get_data(va-engine.OPTIONAL_HEADER.ImageBase,180).split(b"\0")[0].decode()

class Reader:
    def __init__(self, data):
        self.data, self.pos = data, 1

    def take(self, size):
        if self.pos+size > len(self.data):
            raise ValueError(f"Truncated client field: cursor={self.pos} need={size} packet={len(self.data)}")
        data = self.data[self.pos:self.pos+size]
        self.pos += size
        return data

    def parse(self, fmt):
        values = []
        for kind in fmt:
            if kind == "S":
                data = bytearray()
                while True:
                    character = self.take(2)
                    if character == b"\0\0":
                        break
                    data.extend(character)
                values.append(data.decode("utf-16le"))
            else:
                spec, size = {"d":("<I",4),"h":("<H",2),"c":("<B",1),"f":("<d",8)}[kind]
                values.append(struct.unpack(spec,self.take(size))[0])
        return values

selected = Reader((directory/"char_selected.bin").read_bytes())
values = selected.parse(client_format(0x10735204))
blob_length = values[-1]
selected.take(blob_length)
world_context = selected.parse(client_format(0x107351D8))
assert selected.pos == len(selected.data)
print("CHAR_SELECTED_485_PARSE_OK", "bytes",len(selected.data),"name",values[0],
      "blob_bytes",blob_length,"world_context",world_context)

user = Reader((directory/"user_info.bin").read_bytes())
values = user.parse(client_format(0x1073A060))
for _ in range(values[-1]):
    user.parse("h")
party = user.parse("c")
invisibility_and_flag = user.parse("dc")
user.take(32)
recommendations = user.parse(client_format(0x1073A054))
assert user.pos == len(user.data)
print("USER_INFO_485_PARSE_OK","bytes",len(user.data),"name",values[5],
      "party",party,"visibility",invisibility_and_flag,"tail",recommendations)

if (directory/"npc_info.bin").exists():
    npc = Reader((directory/"npc_info.bin").read_bytes())
    values = npc.parse(client_format(0x1073A26C))
    if npc.pos == len(npc.data):
        print("NPC_INFO_BASE_PARSE_OK","bytes",len(npc.data),"class",values[1],
              "optional C2 extension absent; GUI baseline does not include it")
    else:
        extension = npc.parse(client_format(0x1073A264))
        assert npc.pos == len(npc.data)
        print("NPC_INFO_485_PARSE_OK","bytes",len(npc.data),"class",values[1],
              "extension",extension)
