/**
 * Loads and displays the benchmark results from JSON files.
 *
 * Usage:
 *   node scripts/compare_results.js
 *
 */
const fs = require('fs');
const path = require('path');

const RESULTS_DIR = path.join(__dirname, '..', 'results');

const TARGETS = [
  { arch: 'ARM', opt: '-O2', slug: 'arm_O2' },
  { arch: 'ARM', opt: '-Os', slug: 'arm_Os' },
  { arch: 'RISC-V', opt: '-O2', slug: 'riscv_O2' },
  { arch: 'RISC-V', opt: '-Os', slug: 'riscv_Os' },
];

const BENCHMARKS = [
  ['Arithmetic', 'arithmetic'],
  ['Array processing', 'array'],
  ['Bitwise operations', 'bitwise'],
];

function loadResults(environment) {
  return TARGETS.map((target) => {
    const filePath = path.join(RESULTS_DIR, `${environment}_${target.slug}.json`);

    if (!fs.existsSync(filePath)) {
      return { ...target, result: null };
    }

    const result = JSON.parse(fs.readFileSync(filePath, 'utf8'));

    if (result.environment !== environment || !result.measurements) {
      throw new Error(`Invalid ${environment} result: ${path.basename(filePath)}`);
    }

    return { ...target, result };
  });
}

function printTable(title, note, results) {
  const format = (measurement) => {
    if (!measurement) return 'N/A';
    return measurement.value.toLocaleString('en-US');
  };

  console.log(`Environment: ${title}`);
  console.log();
  if (note) console.log(note);
  console.log();

  console.log(
    'Benchmark'.padEnd(22) +
    results.map((r) => `${r.arch} ${r.opt}`.padStart(15)).join('')
  );

  console.log('-'.repeat(22 + results.length * 15));

  for (const [label, key] of BENCHMARKS) {
    console.log(
      label.padEnd(22) +
      results
        .map((r) => format(r.result?.measurements?.[key]).padStart(15))
        .join('')
    );
  }
}

function main() {
  printTable('Simulation', null, loadResults('simulation'));
  console.log();

  const hardware = loadResults('hardware');
  if (hardware.some((r) => r.result)) {
    const clockHz = hardware.find((r) => r.result).result.clock_hz;
    const note = clockHz
      ? `Board clock: ${(clockHz / 1e6).toLocaleString('en-US')} MHz (cycle counts, not time)`
      : null;
    printTable('Hardware', note, hardware);
  } else {
    console.log('Environment: Hardware');
    console.log('No hardware results yet - run: make measure-arm');
  }
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
