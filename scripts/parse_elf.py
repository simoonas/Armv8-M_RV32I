import sys
import subprocess
import shutil
from pathlib import Path

# pip install pyelftools
try:
    from elftools.elf.elffile import ELFFile
    from elftools.elf.sections import SymbolTableSection
    USE_PYELFTOOLS = True
except ImportError:
    USE_PYELFTOOLS = False

def parse_elf_pyelftools(filepath):
    with open(filepath, 'rb') as f:
        elffile = ELFFile(f)
        sections = {}
        for section in elffile.iter_sections():
            name = section.name
            size = section['sh_size']
            if name:
                sections[name] = size

        text = sections.get('.text', 0)
        rodata = sections.get('.rodata', 0)
        data = sections.get('.data', 0)
        bss = sections.get('.bss', 0)

        flash = text + rodata + data
        ram = data + bss

        return {
            "file": Path(filepath).name,
            "text": text,
            "rodata": rodata,
            "data": data,
            "bss": bss,
            "flash_bytes": flash,
            "ram_bytes": ram
        }

def pick_size_tool(filepath):
    name = Path(filepath).name.lower()
    candidates = ["llvm-size"]
    if "riscv" in name:
        candidates += ["riscv-none-elf-size", "riscv64-unknown-elf-size"]
    else:
        candidates += ["arm-none-eabi-size"]
    for tool in candidates:
        if shutil.which(tool):
            return tool
    return candidates[0]


def parse_elf_size_tool(filepath, size_tool=None):
    if size_tool is None:
        size_tool = pick_size_tool(filepath)
    res = subprocess.run([size_tool, "-A", filepath], capture_output=True, text=True, check=True)
    lines = res.stdout.splitlines()
    sections = {}
    for line in lines[2:]:
        parts = line.split()
        if len(parts) >= 2:
            sections[parts[0]] = int(parts[1])

    text = sections.get('.text', 0)
    rodata = sections.get('.rodata', 0)
    data = sections.get('.data', 0)
    bss = sections.get('.bss', 0)

    return {
        "file": Path(filepath).name,
        "text": text,
        "rodata": rodata,
        "data": data,
        "bss": bss,
        "flash_bytes": text + rodata + data,
        "ram_bytes": data + bss
    }

def print_markdown_table(data_list):
    print("Binary Name | Arch | Opt Level | .text | .rodata | .data | .bss | Total Flash (Bytes) | Total RAM (Bytes)")
    
    for item in data_list:
        arch = "RISC-V" if "riscv" in item['file'].lower() else "ARM Cortex-M33"
        opt = "Os" if "os" in item['file'].lower() else "O2"
        print(f"{item['file']} | {arch} | {opt} | {item['text']} | {item['rodata']} | {item['data']} | {item['bss']} | {item['flash_bytes']} | {item['ram_bytes']}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python parse_elf.py <path_to_elf_file1> <path_to_elf_file2> ...")
        sys.exit(1)

    results = []
    for filepath in sys.argv[1:]:
        if USE_PYELFTOOLS:
            results.append(parse_elf_pyelftools(filepath))
        else:
            results.append(parse_elf_size_tool(filepath))

    print_markdown_table(results)
