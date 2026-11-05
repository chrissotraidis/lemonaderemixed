#!/usr/bin/env python3
"""Unpack the Lemonade Tycoon Deluxe installer (Zone.com edition, 2003).

  unpack_installer.py Setup.exe <outdir>        extract every file
  unpack_installer.py Setup.exe --list          list the files

The installer is a MindVision Installer VISE for Windows program that keeps
its archive in a PE section named _mvdata. Each file record in that archive
holds a 16-bit name length, the name, then (little-endian, from the end of the
name) a zero word, the uncompressed size, the compressed size, a flag word and
the file's offset in _mvdata; the CRC-32 of the unpacked file sits 0x49 bytes
after the name.

Each file's data is an 8-byte header followed by raw deflate whose bytes are
swapped in 16-bit words. The VISE decoder reads 16 bits at a time, so a stored
block starts, and the block after it resumes, on an even byte. zlib cannot
follow that, so files with stored blocks are inflated by the small decoder
below. Every file is checked against its recorded size and CRC-32.
"""
import os
import re
import struct
import sys
import zlib


def mvdata(exe):
    """Return the _mvdata section of a PE file."""
    pe = struct.unpack_from("<I", exe, 0x3C)[0]
    if exe[pe:pe + 4] != b"PE\0\0":
        raise SystemExit("not a Windows program")
    count = struct.unpack_from("<H", exe, pe + 6)[0]
    table = pe + 24 + struct.unpack_from("<H", exe, pe + 20)[0]
    for i in range(count):
        s = table + 40 * i
        if exe[s:s + 8].rstrip(b"\0") == b"_mvdata":
            size, at = struct.unpack_from("<II", exe, s + 16)
            return exe[at:at + size]
    raise SystemExit("no _mvdata section: not the expected installer")


def records(data):
    """Yield (name, offset, compressed size, size, crc) for each file."""
    seen = set()
    for m in re.finditer(rb"\xff\x00([\x01-\x40])\x00", data):
        n = m.group(1)[0]
        start = m.end()
        name = data[start:start + n]
        if not re.fullmatch(rb"[A-Za-z0-9_\-]+\.[A-Za-z0-9]{1,3}", name):
            continue
        end = start + n
        zero, size, csize, _flag, at = struct.unpack_from("<5I", data, end)
        crc = struct.unpack_from("<I", data, end + 0x49)[0]
        if zero or not size or at + csize > len(data) or (name, at) in seen:
            continue
        seen.add((name, at))
        yield name.decode("ascii"), at, csize, size, crc


def unswap(b):
    b = bytearray(b)
    n = len(b) & ~1
    b[0:n:2], b[1:n:2] = b[1:n:2], b[0:n:2]
    return bytes(b)


# --- deflate with 16-bit-aligned stored blocks ------------------------------

LEN_BASE = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43,
            51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
LEN_EXTRA = [0] * 8 + [1] * 4 + [2] * 4 + [3] * 4 + [4] * 4 + [5] * 4 + [0]
DIST_BASE = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257,
             385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289,
             16385, 24577]
DIST_EXTRA = [0, 0, 0, 0] + [i // 2 for i in range(2, 28)]
ORDER = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]


def table(lengths):
    """Canonical Huffman codes as {(length, code): symbol}."""
    code, codes = 0, {}
    for bits in range(1, 16):
        for sym, ln in enumerate(lengths):
            if ln == bits:
                codes[(bits, code)] = sym
                code += 1
        code <<= 1
    return codes


FIXED = (table([8] * 144 + [9] * 112 + [7] * 24 + [8] * 8), table([5] * 30))


def inflate(src):
    out = bytearray()
    pos = bit = 0  # byte position and bit within it

    def bits(n):
        nonlocal pos, bit
        v = 0
        for i in range(n):
            v |= ((src[pos] >> bit) & 1) << i
            bit += 1
            if bit == 8:
                bit, pos = 0, pos + 1
        return v

    def decode(codes):
        code = ln = 0
        while True:
            code = (code << 1) | bits(1)
            ln += 1
            sym = codes.get((ln, code))
            if sym is not None:
                return sym
            if ln > 15:
                raise ValueError("bad Huffman code")

    final = 0
    while not final:
        final, kind = bits(1), bits(2)
        if kind == 0:
            if bit:
                bit, pos = 0, pos + 1
            pos += pos & 1
            size, inverse = struct.unpack_from("<HH", src, pos)
            if size ^ inverse != 0xFFFF:
                raise ValueError("bad stored block")
            out += src[pos + 4:pos + 4 + size]
            pos += 4 + size
            pos += pos & 1
            continue
        if kind == 1:
            lit, dist = FIXED
        elif kind == 2:
            hlit, hdist, hclen = bits(5) + 257, bits(5) + 1, bits(4) + 4
            cl = [0] * 19
            for i in range(hclen):
                cl[ORDER[i]] = bits(3)
            clt = table(cl)
            lens = []
            while len(lens) < hlit + hdist:
                sym = decode(clt)
                if sym < 16:
                    lens.append(sym)
                elif sym == 16:
                    lens += [lens[-1]] * (3 + bits(2))
                elif sym == 17:
                    lens += [0] * (3 + bits(3))
                else:
                    lens += [0] * (11 + bits(7))
            lit, dist = table(lens[:hlit]), table(lens[hlit:])
        else:
            raise ValueError("bad block type")
        while True:
            sym = decode(lit)
            if sym < 256:
                out.append(sym)
            elif sym == 256:
                break
            else:
                sym -= 257
                length = LEN_BASE[sym] + bits(LEN_EXTRA[sym])
                d = decode(dist)
                back = DIST_BASE[d] + bits(DIST_EXTRA[d])
                for _ in range(length):
                    out.append(out[-back])
    return bytes(out)


def unpack(data, at, csize, size):
    stream = unswap(data[at:at + csize + 16])[8:]
    try:
        out = zlib.decompressobj(-15).decompress(stream)
        if len(out) == size:
            return out
    except zlib.error:
        pass
    return inflate(stream)[:size]


def main(argv):
    if len(argv) != 3:
        raise SystemExit(__doc__)
    with open(argv[1], "rb") as f:
        data = mvdata(f.read())
    files = list(records(data))
    if argv[2] == "--list":
        for name, at, csize, size, crc in files:
            print(f"{size:>9}  {crc:08x}  {name}")
        return
    os.makedirs(argv[2], exist_ok=True)
    bad = 0
    for name, at, csize, size, crc in files:
        out = unpack(data, at, csize, size)
        ok = len(out) == size and zlib.crc32(out) == crc
        bad += not ok
        print(f"{'ok ' if ok else 'BAD'} {size:>9}  {name}")
        if ok:
            with open(os.path.join(argv[2], name), "wb") as f:
                f.write(out)
    if bad:
        raise SystemExit(f"{bad} file(s) failed their checks")


if __name__ == "__main__":
    main(sys.argv)
