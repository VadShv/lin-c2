def l2hash(pw: str) -> bytes:
    key = bytearray(16); dst = bytearray(16)
    b = pw.encode('ascii')[:16]
    for i, c in enumerate(b): key[i] = c; dst[i] = c
    def mix(i, m, a):
        r = key[i] + key[i+1]*256 + key[i+2]*65536 + key[i+3]*16777216
        v = (r*m + a) % 4294967296
        k3 = (v // 16777216) & 0xFF
        k2 = (int((v - k3*16777216) // 65535)) & 0xFF
        k1 = (int((v - k3*16777216 - k2*65536) // 256)) & 0xFF
        k0 = int(v - k3*16777216 - k2*65536 - k1*256) & 0xFF
        key[i], key[i+1], key[i+2], key[i+3] = k0, k1, k2, k3
    mix(0, 213119, 2529077); mix(4, 213247, 2529089); mix(8, 213203, 2529589); mix(12, 213821, 2529997)
    dst[0] ^= key[0]
    for i in range(1, 16): dst[i] = dst[i] ^ dst[i-1] ^ key[i]
    for i in range(16):
        if dst[i] == 0: dst[i] = 102
    return bytes(dst)
if __name__ == '__main__':
    import getpass
    print('0x' + l2hash(getpass.getpass('Password to hash (ASCII, first 16 bytes): ')).hex().upper())
