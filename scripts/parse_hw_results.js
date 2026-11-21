/**
 * Converts a captured hardware log into a results JSON file.
 *
 * Usage:
 *   node scripts/parse_hw_results.js <log> [--arch ARM] [--opt -O2]
 *       [--firmware build_arm/arm_O2.uf2] [--clock-hz 12000000]
 *       [--board "Raspberry Pi Pico 2 W"] [--swd-address 0x20000000]
 *
 * Two kinds of log:
 * - UART log (scripts/measure_hw.sh): the firmware (src/main.c) prints one
 *   `CYCLE_<BENCHMARK> <cycles>` line per benchmark and one `CLOCK_HZ <hz>` line.
 * - OpenOCD log (scripts/hardware_swd.sh, with --swd-address): an
 *   `mdw <address> 5` read of the firmware's `bench_results` struct, i.e.
 *   magic, done, then the arithmetic, array and bitwise cycle counts.
 */
const fs = require('fs');
const path = require('path');

const RESULTS_DIR = path.join(__dirname, '..', 'results');
const BENCHMARKS = ['arithmetic', 'array', 'bitwise'];
const BENCH_RESULTS_MAGIC = 0xbe4c0de5;

function parseArgs(argv) {
  const logPath = argv[0];
  if (!logPath || logPath.startsWith('--')) {
    throw new Error(
      'Usage: node scripts/parse_hw_results.js <log> [--arch ARM] [--opt -O2] [--firmware <uf2>] [--clock-hz <hz>] [--board <name>] [--swd-address <hex>]'
    );
  }

  const options = {
    arch: 'ARM',
    opt: '-O2',
    firmware: null,
    clockHz: 12000000,
    board: 'Raspberry Pi Pico 2 W',
    swdAddress: null,
  };

  for (let i = 1; i < argv.length; i += 2) {
    const key = argv[i];
    const value = argv[i + 1];
    if (value === undefined) throw new Error(`Missing value for ${key}`);

    switch (key) {
      case '--arch': options.arch = value; break;
      case '--opt': options.opt = value; break;
      case '--firmware': options.firmware = value; break;
      case '--clock-hz': options.clockHz = Number(value); break;
      case '--board': options.board = value; break;
      case '--swd-address': options.swdAddress = parseInt(value, 16); break;
      default: throw new Error(`Unknown argument: ${key}`);
    }
  }

  return { logPath, options };
}

function parseLog(logPath, defaultClockHz) {
  const text = fs.readFileSync(logPath, 'utf8');
  const measurements = {};
  let clockHz = defaultClockHz;

  for (const line of text.split(/\r?\n/)) {
    const cycle = line.match(/^CYCLE_(ARITHMETIC|ARRAY|BITWISE)\s+(\d+)$/);
    if (cycle) {
      measurements[cycle[1].toLowerCase()] = { value: Number(cycle[2]) };
    }

    const clock = line.match(/^CLOCK_HZ\s+(\d+)$/);
    if (clock) clockHz = Number(clock[1]);
  }

  const missing = BENCHMARKS.filter((name) => !measurements[name]);
  if (missing.length > 0) {
    throw new Error(
      `Missing cycle counts in ${logPath}: ${missing.join(', ')}. ` +
        'Was the board flashed with a current build (make measure-arm)?'
    );
  }

  if (BENCHMARKS.every((name) => measurements[name].value === 0)) {
    throw new Error(
      `All cycle counts in ${logPath} are 0 - the cycle counter did not run.`
    );
  }

  return { measurements, clockHz };
}

// Finds the `mdw` output line for `address` in an OpenOCD log, e.g.
//   0x20000000: be4c0de5 00000001 0000c99b 0004537f 0001b2ca
// and checks the struct before trusting the counts.
function parseSwdLog(logPath, address, clockHz) {
  const text = fs.readFileSync(logPath, 'utf8');
  const hex = `0x${address.toString(16).padStart(8, '0')}`;
  let words = null;

  for (const line of text.split(/\r?\n/)) {
    const match = line.trim().match(/^0x([0-9a-f]+):((?:\s+[0-9a-f]+)+)\s*$/i);
    if (match && parseInt(match[1], 16) === address) {
      words = match[2].trim().split(/\s+/).map((w) => parseInt(w, 16));
    }
  }

  if (!words || words.length < 5) {
    throw new Error(`No 5-word mdw read of ${hex} in ${logPath} - did the halt or read fail?`);
  }

  const [magic, done, ...cycles] = words;
  if (magic !== BENCH_RESULTS_MAGIC) {
    throw new Error(
      `bench_results at ${hex} has magic 0x${magic.toString(16)}, expected 0x${BENCH_RESULTS_MAGIC.toString(16)} - ` +
        'is the flashed image a current build?'
    );
  }
  if (done !== 1) {
    throw new Error(
      `bench_results at ${hex} has done=${done}: the benchmarks had not finished. ` +
        'Try a longer wait (RUN_WAIT=5).'
    );
  }

  const measurements = {};
  BENCHMARKS.forEach((name, i) => {
    measurements[name] = { value: cycles[i] };
  });

  if (BENCHMARKS.every((name) => measurements[name].value === 0)) {
    throw new Error(`All cycle counts at ${hex} are 0 - the cycle counter did not run.`);
  }

  return { measurements, clockHz };
}

function main() {
  const { logPath, options } = parseArgs(process.argv.slice(2));
  const swd = options.swdAddress !== null;
  const { measurements, clockHz } = swd
    ? parseSwdLog(logPath, options.swdAddress, options.clockHz)
    : parseLog(logPath, options.clockHz);

  const archSlug = options.arch.toLowerCase().replace(/[^a-z0-9]/g, '');
  const optSlug = options.opt.replace(/[^a-z0-9]/gi, '');
  const outputPath = path.join(RESULTS_DIR, `hardware_${archSlug}_${optSlug}.json`);

  const result = {
    environment: 'hardware',
    board: options.board,
    architecture: options.arch,
    optimization: options.opt,
    firmware: options.firmware,
    clock_hz: clockHz,
    captured_at: new Date().toISOString(),
    capture: swd ? 'swd' : 'uart',
    measurements,
  };
  const relativeLog = path.relative(path.join(__dirname, '..'), logPath);
  if (swd) {
    result.openocd_log = relativeLog;
    result.swd_address = `0x${options.swdAddress.toString(16).padStart(8, '0')}`;
  } else {
    result.uart_log = relativeLog;
  }

  fs.mkdirSync(RESULTS_DIR, { recursive: true });
  fs.writeFileSync(outputPath, JSON.stringify(result, null, 2) + '\n');
  console.log(`Saved ${outputPath}`);
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
