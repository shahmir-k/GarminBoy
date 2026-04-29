#!/usr/bin/env python3
"""
convert_rom.py — converts a .gb/.bin ROM into chunked Rez hex-string resources.

Usage:
    python3 tools/convert_rom.py "resources/rom/Tetris (World) (Rev 1).gb" resources/rom_chunks.xml

Each byte is stored as two hex characters (e.g. 0xFF → "FF").
A 4096-byte chunk becomes an 8192-char hex string — fully XML-safe, no
encoding ambiguity, and simple to decode in Monkey C.

32KB MBC0 ROM → 8 chunks × 4096 bytes = 65536 hex chars total in XML.
"""

import sys

CHUNK_SIZE = 4096

HEX_CHARS = "0123456789ABCDEF"

def convert(input_path, output_path):
    with open(input_path, "rb") as f:
        rom_data = f.read()

    print(f"ROM: {input_path}")
    print(f"Size: {len(rom_data)} bytes")

    if len(rom_data) != 32768:
        print(f"WARNING: Expected 32768 bytes for MBC0, got {len(rom_data)}")

    chunks = [rom_data[i:i + CHUNK_SIZE] for i in range(0, len(rom_data), CHUNK_SIZE)]
    print(f"Chunks: {len(chunks)} × {CHUNK_SIZE} bytes")

    with open(output_path, "w", encoding="utf-8") as out:
        out.write('<?xml version="1.0" encoding="utf-8"?>\n')
        out.write('<resources>\n')
        for idx, chunk in enumerate(chunks):
            hex_str = "".join(f"{b:02X}" for b in chunk)
            out.write(f'    <string id="RomChunk{idx}">{hex_str}</string>\n')
        out.write('</resources>\n')

    print(f"Written to {output_path}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.gb> <output.xml>")
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])
