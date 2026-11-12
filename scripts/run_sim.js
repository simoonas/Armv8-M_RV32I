/**
 * Runs a benchmark image on the rp2350js emulator and measures bechmark cycles.
 *
 * Usage:
 *   node scripts/run_sim.js <image.uf2> [--verbose]
 *   node scripts/run_sim.js --all [--verbose]
 *
 * The image is loaded into flash/SRAM without running the emulated bootrom.
 * Our images do contain the IMAGE_DEF block that the real bootrom needs, but
 * the simulator skips the bootrom: it reads the initial SP/PC from the vector
 * table (ARM) or jumps to the start of the image, where _reset is (RISC-V),
 * and starts stepping from there.
 *
 * Cycle counting: we record the cycle count the moment each bechmark's START and END markers
 * (e.g. START_ARITHMETIC_BENCHMARK) arrive on UART0 and report the difference, i.e. the
 * cycles spent inside the benchmark workload.
 * 
 * Results: measurements are saved to JSON files under /results for further use.
 */
const { RP2350, ConsoleLogger } = require('../tools/rp2350js/dist/cjs');
const fs = require('fs');
const path = require('path');

const RESULTS_DIR = path.join(__dirname, '..', 'results');
const FLASH_BASE = 0x10000000;

// SRAM parking spot for core1: the start of SRAM9 (0x20081000), a 4 KB scratch
// bank our program never uses. The stack grows DOWN from __stack_top =
// 0x20080000, so anything just below that address gets overwritten by main()'s
// stack frame; anything above it is safe (the simulator's SRAM is 520 KB, up to
// 0x20082000).
const PARK_ADDR = 0x20081000;
const MAX_STEPS = 200000000;

// rp2350js log levels (its LogLevel enum is only exported as a type, so the
// values are copied here). board_init() touches the XOSC and CLK_PERI_CTRL
// registers, which the simulator doesn't implement, and each access prints an
// "Unimplemented peripheral" warning. Normal runs show errors only; --verbose
// shows everything.
const LOG_LEVEL_DEBUG = 0;
const LOG_LEVEL_ERROR = 3;

const FIRMWARE_IMAGES = [
  { path: 'build_arm/arm_O2.uf2', arch: 'ARM', opt: '-O2' },
  { path: 'build_arm/arm_Os.uf2', arch: 'ARM', opt: '-Os' },
  { path: 'build_riscv/riscv_O2.uf2', arch: 'RISC-V', opt: '-O2' },
  { path: 'build_riscv/riscv_Os.uf2', arch: 'RISC-V', opt: '-Os' },
];


function run(image, verbose = false) {
  const arch = image.arch === 'RISC-V' ? 'riscv' : 'arm';
  const mcu = new RP2350({ coreArch: arch });
  mcu.logger = new ConsoleLogger(verbose ? LOG_LEVEL_DEBUG : LOG_LEVEL_ERROR, true);

  let output = '';
  const benchmarks = {
    arithmetic: { start: null, end: null },
    array: { start: null, end: null },
    bitwise: { start: null, end: null },
  }

  mcu.uart[0].onByte = (byte) => {
    const ch = String.fromCharCode(byte);
    if (verbose) process.stdout.write(ch);
    output += ch;

    for (const [name, cycles] of Object.entries(benchmarks)) {
      if (output.endsWith(`START_${name.toUpperCase()}_BENCHMARK\n`)) {
        cycles.start = mcu.cycles;
      }

      if (output.endsWith(`END_${name.toUpperCase()}_BENCHMARK\n`)) {
        cycles.end = mcu.cycles;
      }
    }
  }

  const { useSram, loadBase } = mcu.loadFirmware(image.path, { initChip: false });
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

    if (Object.values(benchmarks).every(({ end }) => end !== null)) {
      break;
    }
  }

  if (Object.values(benchmarks).some(({ end }) => end === null)) {
    console.error(`\n[sim] timeout: end of benchmark not reached within ${MAX_STEPS} steps`);
    process.exit(1);
  }

  return Object.fromEntries(
    Object.entries(benchmarks).map(([name, cycles]) => [
      name,
      cycles.start !== null && cycles.end !== null
        ? cycles.end - cycles.start
        : null,
    ])
  )
}

function saveResult(image, measurements) {
  fs.mkdirSync(RESULTS_DIR, { recursive: true });

  const arch = image.arch.toLowerCase().replace('-', '');
  const optimization = image.opt.replace('-', '');
  const filename = `simulation_${arch}_${optimization}.json`;
  const outputPath = path.join(RESULTS_DIR, filename);

  const result = {
    environment: 'simulation',
    architecture: image.arch,
    optimization: image.opt,
    firmware: image.path,
    measurements: Object.fromEntries(
      Object.entries(measurements).map(([name, value]) => [
        name,
        { value }
      ])
    )
  };

  fs.writeFileSync(outputPath, JSON.stringify(result, null, 2) + '\n');
  console.log(`Saved ${outputPath}`);
}

function runAll(verbose = false) {
  const availableImages = FIRMWARE_IMAGES.filter((image) =>
    fs.existsSync(image.path)
  );

  if (availableImages.length === 0) {
    throw new Error('No firmware images found. Run make first.');
  }

  for (const image of availableImages) {
    console.log(`\nRunning ${image.arch} ${image.opt}: ${image.path}`);
    const measurements = run(image, verbose);
    saveResult(image, measurements);
  }
}

function main() {
  const args = process.argv.slice(2);
  const verbose = args.includes('--verbose');
  const argument = args.find((arg) => arg !== '--verbose');

  try {
    if (argument === '--all') {
      runAll(verbose);
    } else if (argument) {
      const image = FIRMWARE_IMAGES.find((item) => item.path === argument);

      if (!image) {
        throw new Error(`Unknown firmware image: ${argument}`);
      }

      saveResult(image, run(image, verbose));
    } else {
      console.error(
        'Usage: node scripts/run_sim.js <image.uf2> OR node scripts/run_sim.js --all'
      );
      process.exitCode = 1;
    }
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

main();