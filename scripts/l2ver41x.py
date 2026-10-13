"""Legacy Lineage2Ver411 resource format helper.

Format constants derived from acmi/L2crypt (MIT); see third_party/L2crypt/LICENSE.
These are historical resource-format constants, not server credentials.
"""
import zlib, struct, sys
MOD_411=int("8c9d5da87b30f5d7cd9dc88c746eaac5bb180267fa11737358c4c95d9adf59dd37689f9befb251508759555d6fe0eca87bebe0a10712cf0ec245af84cd22eb4cb675e98eaf5799fca62a20a2baa4801d5d70718dcd43283b8428f1387aec6600f937bfc7bb72404d187d3a9c438f1ffce9ce365dccf754232ff6def038a41385",16); EXP_411=0x1d
MOD_ENC=int("75b4d6de5c016544068a1acf125869f43d2e09fc55b8b1e289556daf9b8757635593446288b3653da1ce91c87bb1a5c18f16323495c55d7d72c0890a83f69bfd1fd9434eb1c02f3e4679edfa43309319070129c267c85604d87bb65bae205de3707af1d2108881abb567c3b3d069ae67c3a4c6a3aa93d26413d4c66094ae2039",16)
PUB_ENC=int("30b4c2d798d47086145c75063c8e841e719776e400291d7838d3e6c4405b504c6a07f8fca27f32b86643d2649d1d5f124cdd0bf272f0909dd7352fe10a77b34d831043d9ae541f8263c6fe3d1c14c2f04e43a7253a6dda9a8c1562cbd493c1b631a1957618ad5dfe5ca28553f746e2fc6f2db816c7db223ec91e955081c1de65",16); PRIV_ENC=0x1d
def header(ver): return f"Lineage2Ver{ver}".encode('utf-16le')
def decrypt(data, mod, exp):
    body=data[28:]; nblocks=len(body)//128; out=bytearray()
    for i in range(nblocks):
        blk=int.from_bytes(body[i*128:(i+1)*128],'big'); dec=pow(blk,exp,mod).to_bytes(128,'big')
        size=dec[3]
        if size>124: raise ValueError("bad block size %d"%size)
        start=128-size-((124-size)%4); out+=dec[start:start+size]
    tail=body[nblocks*128:]
    total=struct.unpack('<I',out[:4])[0]; plain=zlib.decompress(bytes(out[4:]))
    assert len(plain)==total, (len(plain),total)
    return plain, tail
def encrypt(plain, ver, mod=MOD_ENC, exp=PUB_ENC, tail=b''):
    stream=struct.pack('<I',len(plain))+zlib.compress(plain)
    out=bytearray(header(ver))
    for i in range(0,len(stream),124):
        chunk=stream[i:i+124]; size=len(chunk); blk=bytearray(128); blk[3]=size
        start=128-size-((124-size)%4); blk[start:start+size]=chunk
        out+=pow(int.from_bytes(blk,'big'),exp,mod).to_bytes(128,'big')
    return bytes(out)+tail
if __name__=="__main__":
    data=open(sys.argv[1],'rb').read(); print("header:",data[:28].decode('utf-16le'))
    for name,mod,exp in (("NCSoft-411",MOD_411,EXP_411),("l2encdec",MOD_ENC,PRIV_ENC)):
        try:
            plain,tail=decrypt(data,mod,exp); print("OK with",name,"| tail",len(tail),"bytes"); open(sys.argv[2],'wb').write(plain); break
        except Exception as e: print("fail",name,":",e)
