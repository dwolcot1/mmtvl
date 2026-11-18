#!/usr/bin/env python3
"""Writes roku/tests/local/support/InflateFixtures.bs: small gzip streams for tests/local/Inflate.test.bs.

Run from anywhere with `python3 -I roku/tools/gen-inflate-fixtures.py`. Standard library only, deterministic
(mtime 0, seeded random), so running it again gives the same file. The fixtures are committed as hex text (a few
KB) so `npm run test:local` needs no Python; each carries the expected output's length and CRC-32 (signed, as
roByteArray.GetCRC32 returns it). The script checks each stream's first block type, so the stored, fixed and
dynamic cases really are those block types.
"""

import gzip
import random
import struct
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "tests" / "local" / "support" / "InflateFixtures.bs"


def gz(data: bytes, level: int) -> bytes:
    return gzip.compress(data, compresslevel=level, mtime=0)


def first_block_type(stream: bytes, header_length: int = 10) -> int:
    return (stream[header_length] >> 1) & 3


def signed_crc(data: bytes) -> int:
    crc = zlib.crc32(data)
    return crc - (1 << 32) if crc >= (1 << 31) else crc


def member_with_every_flag(data: bytes) -> bytes:
    """A member with FTEXT, FHCRC, FEXTRA, FNAME and FCOMMENT set (gzip.compress sets none of them)."""
    flags = 0x01 | 0x02 | 0x04 | 0x08 | 0x10
    header = b"\x1f\x8b\x08" + bytes([flags]) + struct.pack("<I", 0) + b"\x00\x03"
    extra = b"AB\x04\x00test"
    header += struct.pack("<H", len(extra)) + extra
    header += b"guide.xml\x00" + b"a comment\x00"
    header += struct.pack("<H", zlib.crc32(header) & 0xFFFF)
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    body = compressor.compress(data) + compressor.flush()
    return header + body + struct.pack("<II", zlib.crc32(data), len(data) & 0xFFFFFFFF)


def fixtures() -> dict:
    stored_data = b"".join(b"Stored line %03d: <channel id=\"ch%d.example\"/>\n" % (i, i) for i in range(40))
    stored = gz(stored_data, 0)
    assert first_block_type(stored) == 0

    fixed_data = b"hello hello hello, world. abcabcabcabc\n"
    fixed = gz(fixed_data, 9)
    assert first_block_type(fixed) == 1

    # Dynamic: XMLTV-like text (long matches, overlapping copies) and skewed random bytes, whose rare symbols
    # get codes longer than the 9-bit fast table, so the slow decoding path runs too.
    rng = random.Random(12)
    weights = [2 ** (-i / 14) for i in range(256)]
    skewed = bytes(rng.choices(range(256), weights=weights, k=2500))
    text = b"".join(
        b'<programme start="20261118%02d0000 +0000" channel="ch%d.example"><title>Show &amp; Tell %d</title>'
        b"<desc>aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa</desc></programme>\n"
        % (i % 24, i % 7, i)
        for i in range(60)
    )
    dynamic_data = text + skewed + text[:500]
    dynamic = gz(dynamic_data, 9)
    assert first_block_type(dynamic) == 2

    first_part = b"First member \xc3\xa9\n" * 30
    second_part = b"Second member\n" * 25
    multi = member_with_every_flag(first_part) + gz(second_part, 6)
    multi_data = first_part + second_part

    # Large: 256 KB of output in 4 KB chunks over a 4-letter alphabet (2 bits a letter keeps the committed hex small). The first 8 chunks are random; each later
    # one repeats the chunk 5, 6 or 7 places back (20–28 KB earlier, inside zlib's 32,506-byte reach). Without those
    # copies the 256 KB of 2-bit letters would need about 64 KB, so a small stream proves they were used. Output crosses
    # four 64 KB pieces. Only the gzip (a few KB of hex) is committed, with the output's size and CRC.
    letters = b"acgt"
    big_rng = random.Random(20261118)
    chunks = [bytes(big_rng.choice(letters) for _ in range(4096)) for _ in range(8)]
    while len(chunks) < 64:
        chunks.append(chunks[-big_rng.choice([5, 6, 7])])
    large_data = b"".join(chunks)
    large = gz(large_data, 9)
    assert len(large_data) == 262144
    assert len(large) < 16000, len(large)  # the 8 unique chunks alone are about 8 KB compressed

    # A dynamic block cut right after a code-length symbol 18, before its 7 extra bits: BFINAL 1, BTYPE 2,
    # HLIT 0, HDIST 0, HCLEN 0 (4 code-length codes: 16 and 17 unused, 18 and 0 of length 1, so 0 = "0" and
    # 18 = "1"), then one "1" bit. Bits are packed least significant first, like deflate.
    bits = [1, 0, 1] + [0] * 5 + [0] * 5 + [0] * 4 + [0, 0, 0] + [0, 0, 0] + [1, 0, 0] + [1, 0, 0] + [1]
    packed = bytearray((len(bits) + 7) // 8)
    for index, bit in enumerate(bits):
        packed[index // 8] |= bit << (index % 8)
    truncated_18 = b"\x1f\x8b\x08\x00" + b"\x00" * 4 + b"\x00\x03" + bytes(packed)

    return {
        "large": (large, large_data),
        "truncated18": (truncated_18, b"truncated!!!"),
        "stored": (stored, stored_data),
        "fixed": (fixed, fixed_data),
        "dynamic": (dynamic, dynamic_data),
        "multi": (multi, multi_data),
    }


def main() -> None:
    lines = [
        "' Generated by roku/tools/gen-inflate-fixtures.py (python3 -I); don't edit by hand.",
        "' Gzip streams for Inflate.test.bs: hex, the expected output's length and CRC-32 (signed).",
        "namespace InflateFixtures",
        "",
    ]
    for name, (stream, data) in fixtures().items():
        hex_text = stream.hex()
        chunks = [hex_text[i:i + 100] for i in range(0, len(hex_text), 100)]
        lines.append(f"    function {name}() as object")
        lines.append("        hex = []")
        for chunk in chunks:
            lines.append(f'        hex.Push("{chunk}")')
        lines.append(
            f'        return {{ hex: hex.Join(""), size: {len(data)}, crc: {signed_crc(data)}, '
            f'head: "{data[:12].decode("ascii")}" }}'
        )
        lines.append("    end function")
        lines.append("")
    lines.append("end namespace")
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {OUT.name}")


if __name__ == "__main__":
    main()
