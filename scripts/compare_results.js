/**
 * Loads and displays the benchmark results from JSON files.
 *
 * Usage:
 *   node scripts/compare_results.js
 *
 * Results are read from the /results directory and displayed in a table.
 */
const fs = require('fs');
const path = require('path');

const RESULTS_DIR = path.join(__dirname, '..', 'results');

const EXPECTED_RESULTS = [
  { arch: 'ARM', opt: '-O2', file: 'simulation_arm_O2.json' },
  { arch: 'ARM', opt: '-Os', file: 'simulation_arm_Os.json' },
  { arch: 'RISC-V', opt: '-O2', file: 'simulation_riscv_O2.json' },
  { arch: 'RISC-V', opt: '-Os', file: 'simulation_riscv_Os.json' },
];

function loadResults() {
  return EXPECTED_RESULTS.map((expected) => {
    const filePath = path.join(RESULTS_DIR, expected.file);

    if (!fs.existsSync(filePath)) {
      return { ...expected, measurements: null };
    }

    const result = JSON.parse(fs.readFileSync(filePath, 'utf8'));

    if (
      result.environment !== 'simulation' ||
      !result.measurements
    ) {
      throw new Error(`Invalid simulation result: ${expected.file}`);
    }

    return { ...expected, measurements: result.measurements };
  });
}

function printResults(results) {
  const format = (measurement) => {
    if (!measurement) return 'N/A';
    return measurement.value.toLocaleString('en-US');
  };

  const benchmarks = [
    ['Arithmetic', 'arithmetic'],
    ['Array processing', 'array'],
    ['Bitwise operations', 'bitwise'],
  ];

  console.log('Environment: Simulation\n');

  console.log(
    'Benchmark'.padEnd(22) +
    results.map((r) => `${r.arch} ${r.opt}`.padStart(15)).join('')
  );

  console.log('-'.repeat(22 + results.length * 15));

  for (const [label, key] of benchmarks) {
    console.log(
      label.padEnd(22) +
      results
        .map((r) => format(r.measurements?.[key]).padStart(15))
        .join('')
    );
  }
}

try {
  printResults(loadResults());
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}