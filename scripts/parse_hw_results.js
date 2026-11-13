/**
 * Converts a captured hardware UART log into a results JSON file.
 *
 * Usage:
 *   node scripts/parse_hw_results.js <uart.log> [--arch ARM] [--opt -O2]
 *       [--firmware build_arm/arm_O2.uf2] [--clock-hz 12000000]
 *       [--board "Raspberry Pi Pico 2 W"]
 *
 * The firmware (src/main.c) prints one `CYCLE_<BENCHMARK> <cycles>` line per
 * benchmark and one `CLOCK_HZ <hz>` line. The output uses the same schema as
 * the simulator's results/simulation_*.json, so scripts/compare_results.js can
 * show both side by side.
 */
const fs = require('fs');
const path = require('path');

const RESULTS_DIR = path.join(__dirname, '..', 'results');
const BENCHMARKS = ['arithmetic', 'array', 'bitwise'];

function parseArgs(argv) {
  const logPath = argv[0];
  if (!logPath || logPath.startsWith('--')) {
    throw new Error(
      'Usage: node scripts/parse_hw_results.js <uart.log> [--arch ARM] [--opt -O2] [--firmware <uf2>] [--clock-hz <hz>] [--board <name>]'
    );
  }

  const options = {
    arch: 'ARM',
    opt: '-O2',
    firmware: null,
    clockHz: 12000000,
    board: 'Raspberry Pi Pico 2 W',
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

function main() {
  const { logPath, options } = parseArgs(process.argv.slice(2));
  const { measurements, clockHz } = parseLog(logPath, options.clockHz);

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
    uart_log: path.relative(path.join(__dirname, '..'), logPath),
    measurements,
  };

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
