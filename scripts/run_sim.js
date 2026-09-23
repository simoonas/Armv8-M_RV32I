/**
 * Run a benchmark image on the rp2350js emulator and report executed cycles.
 *
 * Usage:
 *   node scripts/run_sim.js <image.uf2>
 *
 * The image is loaded into flash/SRAM without going through the emulated
 * bootrom (our bare-metal images have no picobin IMAGE_DEF, so the bootrom
 * cannot boot them). Instead we read the initial SP/PC from the vector table
 * (ARM) or jump to the image base (RISC-V) and start stepping directly.
 *
 * Cycle counting: we record the cycle count the moment "START_BENCHMARK\n"
 * and "END_BENCHMARK\n" arrive on UART0 and report the difference, i.e. the
 * cycles spent inside the benchmark workload.
 */
const { RP2350 } = require('../tools/rp2350js/dist/cjs');

const FLASH_BASE = 0x10000000;
// SRAM parking spot for core1, near the top of the 520 KB SRAM but clear of
// the stack (which grows down from __stack_top = 0x20080000).
const PARK_ADDR = 0x2007ffe0;
const MAX_STEPS = 200000000;

function run(imagePath) {
  const arch = /riscv/i.test(imagePath) ? 'riscv' : 'arm';
  const mcu = new RP2350({ coreArch: arch });

  let output = '';
  let startCycles = null;
  let endCycles = null;

  mcu.uart[0].onByte = (byte) => {
    const ch = String.fromCharCode(byte);
    process.stdout.write(ch);
    output += ch;
    if (output.endsWith('START_BENCHMARK\n') && startCycles === null) {
      startCycles = mcu.cycles;
    }
    if (output.endsWith('END_BENCHMARK\n')) {
      endCycles = mcu.cycles;
    }
  };

  const { useSram, loadBase } = mcu.loadFirmware(imagePath, { initChip: false });
  const entryBase = useSram ? loadBase : FLASH_BASE;

  if (arch === 'arm') {
    // ARMv8-M reset state: MSP and reset vector live in the first two words
    // of the vector table. The Thumb bit is masked off the PC.
    const initialSp = mcu.readUint32(entryBase) >>> 0;
    const entryPc = (mcu.readUint32(entryBase + 4) >>> 0) & ~1;

    mcu.core[0].PC = entryPc;
    mcu.core[0].regs.msp = initialSp;
    mcu.core[0].regs.sp = initialSp;

    // Park core1 in a WFI (0xbf30) so it never executes our image.
    mcu.writeUint16(PARK_ADDR, 0xbf30);
    mcu.core[1].PC = PARK_ADDR;
  } else {
    // RISC-V image starts with _reset at the load base (startup sets sp itself).
    mcu.core[0].PC = entryBase;

    // Park core1 in an infinite `jal x0, 0` loop.
    mcu.writeUint32(PARK_ADDR, 0x0000006f);
    mcu.core[1].PC = PARK_ADDR;
  }

  for (let i = 0; i < MAX_STEPS; i++) {
    mcu.step();
    if (endCycles !== null) break;
  }

  if (endCycles === null) {
    console.error(`\n[sim] timeout: 'END_BENCHMARK' not reached within ${MAX_STEPS} steps`);
    process.exit(1);
  }

  const benchCycles = startCycles !== null ? endCycles - startCycles : endCycles;
  console.log(`\n[sim] cycle count START->END_BENCHMARK: ${benchCycles}`);
}

run(process.argv[2]);