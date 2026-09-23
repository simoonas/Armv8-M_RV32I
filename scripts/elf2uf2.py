"""Convert a raw binary flash image into RP2350 UF2 format.

Usage:
    python3 elf2uf2.py input.bin output.uf2

The input is the raw binary extracted from an ELF with objcopy (-O binary),
whose first byte maps to the start of XIP flash (0x10000000).
"""
import struct
import sys

# RP2350 family ID.
FAMILY_ID = 0xe48bff56
FLASH_START = 0x10000000

UF2_MAGIC_START0 = 0x0A324655  # "UF2\n"
UF2_MAGIC_START1 = 0x9E5D5157  # "QW\xc9^"? fixed magic
UF2_MAGIC_END = 0x0AB16F30
BLOCK_SIZE = 512
PAYLOAD_SIZE = 476
FLAG_FAMILY_ID_PRESENT = 0x00002000


def convert(bin_path, uf2_path):
    with open(bin_path, "rb") as f:
        data = f.read()

    num_blocks = (len(data) + PAYLOAD_SIZE - 1) // PAYLOAD_SIZE
    with open(uf2_path, "wb") as out:
        for block_no in range(num_blocks):
            chunk = data[block_no * PAYLOAD_SIZE : (block_no + 1) * PAYLOAD_SIZE]
            block = bytearray(BLOCK_SIZE)

            struct.pack_into(
                "<IIIIIIII",
                block,
                0,
                UF2_MAGIC_START0,
                UF2_MAGIC_START1,
                FLAG_FAMILY_ID_PRESENT,          # flags
                FLASH_START + block_no * PAYLOAD_SIZE,  # target address
                len(chunk),                      # payload size
                block_no,                        # block index
                num_blocks,                      # total blocks
                FAMILY_ID,                       # file size slot holds family ID
            )
            block[32 : 32 + len(chunk)] = chunk
            struct.pack_into("<I", block, 508, UF2_MAGIC_END)

            out.write(block)

    print(f"Converted {bin_path} ({len(data)} bytes) -> {uf2_path} ({num_blocks} block(s))")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])