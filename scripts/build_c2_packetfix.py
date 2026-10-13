"""Guarded C2 485 compatibility extension for CharSelected, UserInfo and NpcInfo."""
import hashlib
import struct
import argparse
from pathlib import Path
import pefile
from keystone import Ks, KS_ARCH_X86, KS_MODE_32
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32
from unicorn.x86_const import *

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "L2Server483.exe"
parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, default=SOURCE, help="Original L2Server483.exe")
parser.add_argument("--output", type=Path, help="Output EXE (kept private, excluded from Git)")
parser.add_argument("--npc-extension", action="store_true",
                    help="Build optional NpcInfo extension; not part of the GUI-confirmed baseline")
arguments = parser.parse_args()
SOURCE = arguments.source
TARGET = arguments.output or ROOT / ("L2Server_C2_485_packetfix_with_npc.exe" if arguments.npc_extension
                                     else "L2Server_C2_485_packetfix.exe")
if SOURCE.resolve() == TARGET.resolve():
    parser.error("Source and output must be different files")
EXPECTED = "E4AA3F0873A2DC19B2130A6C203C0E11A338C634E84C7CCF747A662F7D9911DA"
HOOK_VA = 0x4DFBCB
RETURN_VA = HOOK_VA + 5

data = bytearray(SOURCE.read_bytes())
assert hashlib.sha256(data).hexdigest().upper() == EXPECTED
pe = pefile.PE(data=data)
base = pe.OPTIONAL_HEADER.ImageBase
assert base == 0x400000 and not pe.OPTIONAL_HEADER.DllCharacteristics & 0x40
hook_offset = pe.get_offset_from_rva(HOOK_VA-base)
assert data[hook_offset:hook_offset+5] == bytes.fromhex("83c41085c0")
protocol_offset = pe.get_offset_from_rva(0x50105C-base)
assert data[protocol_offset:protocol_offset+5] == bytes.fromhex("b8e1010000")
data[protocol_offset+1] = 0xE5

def align(value, step):
    return (value+step-1) // step * step

header_offset = pe.sections[-1].get_file_offset()+40
assert header_offset+40 <= pe.OPTIONAL_HEADER.SizeOfHeaders
assert data[header_offset:header_offset+40] == b"\0"*40
rva = align(max(s.VirtualAddress+max(s.Misc_VirtualSize,s.SizeOfRawData)
                for s in pe.sections), pe.OPTIONAL_HEADER.SectionAlignment)
cave_va = base+rva
npc_branch = """
    cmp byte ptr [esi+0x12], 0x16
    je npc
""" if arguments.npc_extension else ""
npc_code = """
npc:
    lea edx, [esi+eax+0x12]
    mov ecx, 21
zero_npc_tail:
    mov byte ptr [edx], 0
    inc edx
    loop zero_npc_tail
    add eax, 21
    jmp done
""" if arguments.npc_extension else ""
assembly = f"""
    add esp, 0x10
    push ecx
    push edx
    test eax, eax
    jz done
    cmp eax, 0x1f80
    ja done
    cmp byte ptr [esi+0x12], 0x15
    je selected
{npc_branch}
    cmp byte ptr [esi+0x12], 0x04
    jne done
    lea edx, [esi+eax+0x12]
    mov ecx, 47
zero_user_tail:
    mov byte ptr [edx], 0
    inc edx
    loop zero_user_tail
    add eax, 47
    jmp done
{npc_code}
selected:
    cmp eax, 4
    jb done
    mov edx, dword ptr [esi+eax+0x0e]
    mov dword ptr [esi+eax+0x0e], 0
    mov dword ptr [esi+eax+0x12], edx
    mov dword ptr [esi+eax+0x16], 0
    mov dword ptr [esi+eax+0x1a], 0
    mov dword ptr [esi+eax+0x1e], 0
    add eax, 16
done:
    pop edx
    pop ecx
    test eax, eax
    jmp {RETURN_VA}
"""
code = bytes(Ks(KS_ARCH_X86, KS_MODE_32).asm(assembly, addr=cave_va)[0])

def simulate(body):
    emu = Uc(UC_ARCH_X86, UC_MODE_32)
    emu.mem_map(cave_va & ~0xFFF, 0x1000)
    emu.mem_map(RETURN_VA & ~0xFFF, 0x1000)
    emu.mem_map(0x100000, 0x4000)
    emu.mem_map(0x200000, 0x4000)
    emu.mem_write(cave_va, code)
    emu.mem_write(0x100012, body)
    registers = {UC_X86_REG_ESI:0x100000,UC_X86_REG_ESP:0x201000,
                 UC_X86_REG_ECX:0x12345678,UC_X86_REG_EDX:0x87654321,
                 UC_X86_REG_EAX:len(body)}
    for register,value in registers.items():
        emu.reg_write(register,value)
    emu.emu_start(cave_va,RETURN_VA,count=2000)
    assert emu.reg_read(UC_X86_REG_ESP)==0x201010
    assert emu.reg_read(UC_X86_REG_ECX)==0x12345678
    assert emu.reg_read(UC_X86_REG_EDX)==0x87654321
    assert emu.reg_read(UC_X86_REG_ESI)==0x100000
    size=emu.reg_read(UC_X86_REG_EAX)
    return bytes(emu.mem_read(0x100012,size))

selected = b"\x15"+bytes(238)+struct.pack("<I",930)
assert len(selected)==243
assert simulate(selected)==selected[:-4]+bytes(4)+selected[-4:]+bytes(12)
user_info=b"\x04"+bytes(392)
assert simulate(user_info)==user_info+bytes(47)
npc_info=b"\x16"+bytes(137)
assert simulate(npc_info)==npc_info+(bytes(21) if arguments.npc_extension else b"")
for other in [b"\x13"+bytes(576),b"\x01"+bytes(28),b"\x1b"+bytes(116)]:
    assert simulate(other)==other
assert simulate(b"")==b""
print("EMULATED_TESTS_OK: CharSelected 243->259; UserInfo 393->440;",
      "NpcInfo 138->159;" if arguments.npc_extension else "NpcInfo unchanged;",
      "other opcodes unchanged")

raw_offset=align(len(data),pe.OPTIONAL_HEADER.FileAlignment)
raw_size=align(len(code),pe.OPTIONAL_HEADER.FileAlignment)
data.extend(bytes(raw_offset+raw_size-len(data)))
data[raw_offset:raw_offset+len(code)]=code
section=struct.pack("<8sIIIIIIHHI",b".c2fix\0\0",len(code),rva,raw_size,raw_offset,
                    0,0,0,0,0x60000020)
data[header_offset:header_offset+40]=section
struct.pack_into("<H",data,pe.FILE_HEADER.get_field_absolute_offset("NumberOfSections"),
                 pe.FILE_HEADER.NumberOfSections+1)
struct.pack_into("<I",data,pe.OPTIONAL_HEADER.get_field_absolute_offset("SizeOfImage"),
                 align(rva+len(code),pe.OPTIONAL_HEADER.SectionAlignment))
struct.pack_into("<I",data,pe.OPTIONAL_HEADER.get_field_absolute_offset("SizeOfCode"),
                 pe.OPTIONAL_HEADER.SizeOfCode+raw_size)
data[hook_offset:hook_offset+5]=b"\xe9"+struct.pack("<i",cave_va-(HOOK_VA+5))
checksum_offset=pe.OPTIONAL_HEADER.get_field_absolute_offset("CheckSum")
struct.pack_into("<I",data,checksum_offset,0)
struct.pack_into("<I",data,checksum_offset,pefile.PE(data=data).generate_checksum())
rebuilt=pefile.PE(data=data)
assert rebuilt.sections[-1].Name.startswith(b".c2fix")
assert rebuilt.get_data(rva,len(code))==code
TARGET.write_bytes(data)
print("OUTPUT",TARGET)
print("SECTION",hex(cave_va),"CODE_BYTES",len(code),"HOOK",hex(HOOK_VA))
print("SHA256",hashlib.sha256(data).hexdigest().upper())
