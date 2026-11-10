"""Convert a raw binary flash image into RP2350 UF2 format.

Usage:
    python3 elf2uf2.py input.bin output.uf2 [family_id]

The input is the raw binary extracted from an ELF with objcopy (-O binary),
whose first byte maps to the start of XIP flash (0x10000000).

Family IDs (microsoft/uf2 uf2families.json):
    0xe48bff56 = RP2040            (NOT for RP2350!)
    0xe48bff59 = RP2350 ARM-S      (default)
    0xe48bff5a = RP2350 RISC-V
"""
import struct
import sys

# RP2350 family IDs.
FAMILY_ID_DEFAULT = "arm"
FAMILY_IDS = {
    "arm": 0xe48bff59,    # RP2350 ARM-S
    "riscv": 0xe48bff5a,  # RP2350 RISC-V
}

FLASH_START = 0x10000000

UF2_MAGIC_START0 = 0x0A324655  # "UF2\n"
UF2_MAGIC_START1 = 0x9E5D5157
UF2_MAGIC_END = 0x0AB16F30
BLOCK_SIZE = 512
PAYLOAD_SIZE = 256  # canonical pico-style UF2 payload chunk
FLAG_FAMILY_ID_PRESENT = 0x00002000


def convert(bin_path, uf2_path, family_id=FAMILY_ID_DEFAULT):
    if not isinstance(family_id, int):
        family_id = FAMILY_IDS[family_id]
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
                family_id,                       # file size slot holds family ID
            )
            block[32 : 32 + len(chunk)] = chunk
            struct.pack_into("<I", block, 508, UF2_MAGIC_END)

            out.write(block)

    print(f"Converted {bin_path} ({len(data)} bytes) -> {uf2_path} ({num_blocks} block(s))")


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        print(__doc__)
        sys.exit(1)
    family_id = FAMILY_ID_DEFAULT
    if len(sys.argv) == 4:
        key = sys.argv[3]
        family_id = FAMILY_IDS.get(key) or int(key, 0)
    convert(sys.argv[1], sys.argv[2], family_id)