/**
 * Loads and displays the benchmark results from JSON files.
 *
 * Usage:
 *   node scripts/compare_results.js
 *
 * Simulation results come from scripts/run_sim.js (make sim). Hardware results come from scripts/measure_hw.sh (make measure-arm)
 */
const fs = require('fs');
const path = require('path');

const RESULTS_DIR = path.join(__dirname, '..', 'results');

const ARCH_LABELS = { arm: 'ARM', riscv: 'RISC-V' };
const ARCH_ORDER = ['ARM', 'RISC-V'];
const OPT_ORDER = ['O0', 'O1', 'O2', 'O3', 'Os', 'Oz', 'Og', 'Ofast'];

const BENCHMARKS = [
  ['Arithmetic', 'arithmetic'],
  ['Array processing', 'array'],
  ['Bitwise operations', 'bitwise'],
  ['Float (soft-float)', 'float'],
];

function loadResults(environment) {
  if (!fs.existsSync(RESULTS_DIR)) return [];

  const pattern = new RegExp(`^${environment}_([a-z0-9]+)_([A-Za-z0-9]+)\\.json$`);
  const results = [];

  for (const file of fs.readdirSync(RESULTS_DIR)) {
    const match = file.match(pattern);
    if (!match) continue;

    const [, archSlug, optSlug] = match;
    const result = JSON.parse(fs.readFileSync(path.join(RESULTS_DIR, file), 'utf8'));

    if (result.environment !== environment || !result.measurements) {
      throw new Error(`Invalid ${environment} result: ${file}`);
    }

    results.push({
      arch: ARCH_LABELS[archSlug] || archSlug.toUpperCase(),
      opt: `-${optSlug}`,
      result,
    });
  }

  const archRank = (arch) => {
    const index = ARCH_ORDER.indexOf(arch);
    return index === -1 ? ARCH_ORDER.length : index;
  };
  const optRank = (opt) => {
    const index = OPT_ORDER.indexOf(opt.replace('-', ''));
    return index === -1 ? OPT_ORDER.length : index;
  };

  results.sort((a, b) =>
    a.arch === b.arch ? optRank(a.opt) - optRank(b.opt) : archRank(a.arch) - archRank(b.arch)
  );

  return results;
}

function printTable(title, note, results) {
  const format = (measurement) => {
    if (!measurement) return 'N/A';
    return measurement.value.toLocaleString('en-US');
  };

  console.log(`Environment: ${title}`);
  if (note) console.log(note);
  console.log();

  console.log(
    'Benchmark'.padEnd(22) +
    results.map((r) => `${r.arch} ${r.opt}`.padStart(13)).join('')
  );

  console.log('-'.repeat(22 + results.length * 13));

  for (const [label, key] of BENCHMARKS) {
    console.log(
      label.padEnd(22) +
      results
        .map((r) => format(r.result?.measurements?.[key]).padStart(13))
        .join('')
    );
  }
}

function main() {
  const simulation = loadResults('simulation');
  if (simulation.length > 0) {
    printTable('Simulation', null, simulation);
  } else {
    console.log('Environment: Simulation');
    console.log('No simulation results yet - run: make sim');
  }

  console.log();

  const hardware = loadResults('hardware');
  if (hardware.length > 0) {
    const clockHz = hardware.find((r) => r.result.clock_hz)?.result.clock_hz;
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
