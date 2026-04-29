#!/usr/bin/env python3
"""
convert_rom.py — converts a .gb ROM binary into chunked Rez string resources.

Usage:
    python3 tools/convert_rom.py resources/rom/tetris.bin resources/rom_chunks.xml

The output XML file should be included in resources/resources.xml via:
    <resources>
      ... (paste generated content here, or use a build system include)
    </resources>

Each byte is stored as a Latin-1 character in a <string> resource.
Chunks are 4096 bytes each. 32KB ROM = 8 chunks.
"""

import sys
import os

CHUNK_SIZE = 4096

def convert(input_path, output_path):
    with open(input_path, "rb") as f:
        rom_data = f.read()

    print(f"ROM size: {len(rom_data)} bytes")

    if len(rom_data) != 32768:
        print(f"WARNING: Expected 32768 bytes for MBC0 ROM, got {len(rom_data)}")

    chunks = []
    for i in range(0, len(rom_data), CHUNK_SIZE):
        chunk = rom_data[i:i + CHUNK_SIZE]
        chunks.append(chunk)

    print(f"Generated {len(chunks)} chunks of {CHUNK_SIZE} bytes each")

    with open(output_path, "w", encoding="latin-1") as out:
        out.write('<?xml version="1.0" encoding="utf-8"?>\n')
        out.write('<resources>\n')
        for idx, chunk in enumerate(chunks):
            # Encode each byte as its Unicode code point (Latin-1 = U+0000..U+00FF)
            # XML-safe: escape &, <, >, and " but preserve all byte values
            chars = []
            for b in chunk:
                if b == ord('&'):
                    chars.append('&amp;')
                elif b == ord('<'):
                    chars.append('&lt;')
                elif b == ord('>'):
                    chars.append('&gt;')
                elif b == ord('"'):
                    chars.append('&quot;')
                elif b == 0:
                    # Null bytes: XML doesn't allow &#0; — use a workaround
                    # Store 0x00 as U+0100 (256) and decode in Rom.mc with & 0xFF
                    chars.append('Ā')
                elif b < 0x20 and b not in (0x09, 0x0A, 0x0D):
                    # Non-printable control chars not valid in XML — use numeric ref
                    chars.append(f'&#{b};')
                else:
                    chars.append(chr(b))
            content = ''.join(chars)
            out.write(f'    <string id="RomChunk{idx}">{content}</string>\n')
        out.write('</resources>\n')

    print(f"Written to {output_path}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.gb> <output.xml>")
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])
