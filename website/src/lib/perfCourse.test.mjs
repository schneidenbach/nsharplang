import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname, join} from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const dataDir = join(here, '..', 'data');
const repoRoot = join(here, '..', '..', '..');
const modules = JSON.parse(readFileSync(join(dataDir, 'perfCourse.json'), 'utf8'));
const tour = JSON.parse(readFileSync(join(dataDir, 'systemsTour.json'), 'utf8'));
// perfTelemetry is an ESM module; import its named exports.
const {kernels, moduleKernel, allocationStories} = await import(join(dataDir, 'perfTelemetry.mjs'));
const {measuredRun} = await import(join(dataDir, 'measuredSystemsVsNative.mjs'));

test('course has eight well-formed modules', () => {
  assert.equal(modules.length, 8);
  for (const m of modules) {
    assert.ok(m.id && m.title && m.subtitle && m.concept, `module ${m.id} core fields`);
    assert.ok(Array.isArray(m.keyTakeaways) && m.keyTakeaways.length >= 2, `${m.id} takeaways`);
    for (const lang of ['nsharp', 'csharp', 'rust']) {
      assert.ok(m.languages[lang]?.code, `${m.id} ${lang} code`);
      assert.ok(m.languages[lang]?.note, `${m.id} ${lang} note`);
    }
    assert.ok(m.memoryStory, `${m.id} memoryStory`);
    assert.ok(m.puzzle?.prompt && m.puzzle?.hint && m.puzzle?.successMessage, `${m.id} puzzle prose`);
  }
});

test('every puzzle is runnable in the browser interpreter subset', () => {
  // The browser runner supports foreach over arrays only — no C-style for,
  // no while, no array indexing. Whole-number, newline-terminated output.
  const cStyleFor = /\bfor\s*\(|\bfor\s+\w+\s*:?=/;
  const whileLoop = /\bwhile\b/;
  const indexing = /[A-Za-z_]\w*\s*\[\s*[A-Za-z_]/; // ident[ident] — array literals are [digits]
  for (const m of modules) {
    for (const which of ['starterCode', 'solutionCode']) {
      const code = m.puzzle[which];
      assert.ok(code.startsWith('package '), `${m.id}.${which} starts with package`);
      assert.ok(code.includes('func main()'), `${m.id}.${which} has main`);
      assert.ok(code.includes('foreach'), `${m.id}.${which} uses foreach`);
      assert.equal(cStyleFor.test(code), false, `${m.id}.${which} must not use C-style for`);
      assert.equal(whileLoop.test(code), false, `${m.id}.${which} must not use while`);
      assert.equal(indexing.test(code), false, `${m.id}.${which} must not index arrays`);
    }
    const out = m.puzzle.expectedOutput;
    assert.ok(out && out.endsWith('\n'), `${m.id} expectedOutput ends with newline`);
    if (m.puzzle.requiredText) {
      assert.ok(m.puzzle.solutionCode.includes(m.puzzle.requiredText), `${m.id} solution has requiredText`);
    }
  }
});

test('every module maps to a known telemetry kernel or null', () => {
  for (const m of modules) {
    assert.ok(m.id in moduleKernel, `${m.id} has a kernel mapping`);
    const key = moduleKernel[m.id];
    if (key !== null) {
      assert.ok(kernels[key], `${m.id} -> kernel ${key} exists`);
    }
  }
  // Modules without a kernel must supply an allocation story instead.
  for (const m of modules) {
    if (moduleKernel[m.id] === null) {
      assert.ok(allocationStories[m.id], `${m.id} (no kernel) has an allocation story`);
    }
  }
});

test('kernels carry complete four-language speed + memory data', () => {
  for (const [key, k] of Object.entries(kernels)) {
    for (const lang of ['nsharp', 'csharp', 'rust', 'c']) {
      assert.equal(typeof k.speed[lang], 'number', `${key}.speed.${lang}`);
      assert.equal(typeof k.memory[lang], 'number', `${key}.memory.${lang}`);
    }
    assert.ok(k.headline && k.blurb, `${key} prose`);
  }
});

test('telemetry numbers come from the checked-in measured-results fixture', () => {
  for (const [key, k] of Object.entries(kernels)) {
    const measured = measuredRun.workloads[key];
    assert.ok(measured, `${key} exists in measuredSystemsVsNative`);
    for (const lang of ['nsharp', 'csharp', 'rust', 'c']) {
      assert.equal(k.speed[lang], measured[k.size][lang], `${key}.speed.${lang}`);
      assert.equal(k.smallSize[lang], measured[k.smallSize.size][lang], `${key}.smallSize.${lang}`);
    }
    assert.equal(
      k.vectorized,
      measuredRun.vectorizedKernels.includes(key),
      `${key}.vectorized matches the fixture's vectorized set`,
    );
  }
  // The load-bearing SIMD facts: the fused min/max AND the shifted-compare
  // count-transitions both vectorize (P-minmax, P-ctrans).
  assert.ok(kernels['min-max-delta'].vectorized, 'min-max-delta is vectorized');
  assert.ok(kernels['count-transitions'].vectorized, 'count-transitions is vectorized');
});

test('measured-results fixture is a verbatim transcription of the design doc', () => {
  // Every fixture value must appear, three decimals as printed, in the authoritative
  // re-run table. A future re-measure that rewrites the doc turns this red, forcing a
  // matching website refresh instead of silent drift.
  const designDoc = readFileSync(join(repoRoot, 'docs', 'design', 'systems-vs-native.md'), 'utf8');
  for (const [workload, sizes] of Object.entries(measuredRun.workloads)) {
    for (const [size, langs] of Object.entries(sizes)) {
      for (const [lang, value] of Object.entries(langs)) {
        assert.ok(
          designDoc.includes(value.toFixed(3)),
          `${workload}@${size}.${lang} = ${value.toFixed(3)} appears in docs/design/systems-vs-native.md`,
        );
      }
    }
  }
});

test('site copy does not resurrect retired perf claims', () => {
  // Claims made stale by dcf56917 (fused MinMax landed) and 79088a58
  // (count-transitions vectorized) must never come back into the data files.
  const sources = {
    'perfTelemetry.mjs': readFileSync(join(dataDir, 'perfTelemetry.mjs'), 'utf8'),
    'systemsTour.json': readFileSync(join(dataDir, 'systemsTour.json'), 'utf8'),
    'perfCourse.json': readFileSync(join(dataDir, 'perfCourse.json'), 'utf8'),
  };
  const retired = [
    /planned follow-up/i, // the fused single-pass min/max shipped
    /Non-vectorizable kernels \(count-transitions/i,
    /does not vectorize cleanly/i,
    /stays scalar in every language/i,
  ];
  for (const [name, text] of Object.entries(sources)) {
    for (const claim of retired) {
      assert.equal(claim.test(text), false, `${name} contains retired claim ${claim}`);
    }
  }
  const countTransitions = kernels['count-transitions'].headline + kernels['count-transitions'].detail;
  assert.match(countTransitions, /shifted/i, 'count-transitions prose names the shifted-compare kernel');
  assert.match(kernels['min-max-delta'].headline, /fused/i, 'min-max-delta headline names the fused single pass');
});

test('current systems performance docs state the measured gate and native bound exactly', () => {
  const sources = {
    'docs/audits/systems-nsharp-verification-summary.md': readFileSync(
      join(repoRoot, 'docs', 'audits', 'systems-nsharp-verification-summary.md'),
      'utf8',
    ),
    'docs/design/systems-vs-native.md': readFileSync(
      join(repoRoot, 'docs', 'design', 'systems-vs-native.md'),
      'utf8',
    ),
    'docs/design/p4-llvm-nativeaot-backend-evaluation.md': readFileSync(
      join(repoRoot, 'docs', 'design', 'p4-llvm-nativeaot-backend-evaluation.md'),
      'utf8',
    ),
    'docs/design/roadmap-to-done.md': readFileSync(
      join(repoRoot, 'docs', 'design', 'roadmap-to-done.md'),
      'utf8',
    ),
    'docs/prompts/self-host-loop.md': readFileSync(join(repoRoot, 'docs', 'prompts', 'self-host-loop.md'), 'utf8'),
  };

  assert.match(
    sources['docs/audits/systems-nsharp-verification-summary.md'],
    /median\s+ratio `<= 1\.05`/,
    'audit summary names the current median 1.05 product gate',
  );
  assert.doesNotMatch(
    sources['docs/audits/systems-nsharp-verification-summary.md'],
    /Current gate:.*`<= 1\.00`/s,
    'audit summary must not call the old parity rule current',
  );

  for (const [name, text] of Object.entries(sources)) {
    assert.doesNotMatch(text, /ZERO-TOLERANCE|zero-tolerance/i, `${name} must not claim a zero-tolerance gate`);
    assert.doesNotMatch(text, /MEASURED ≤2\.0× at 4096/, `${name} must use the exact 2.02× native bound`);
    assert.doesNotMatch(text, /≤2\.0× behind best-native/, `${name} must use the exact 2.02× native bound`);
  }
});

test('systems tour has hero, pillars, and an honest closing', () => {
  assert.ok(tour.hero?.title && tour.hero?.lede);
  assert.ok(Array.isArray(tour.pillars) && tour.pillars.length >= 6);
  for (const p of tour.pillars) {
    assert.ok(p.title && p.opinion && p.body && p.code, `pillar ${p.title}`);
  }
  assert.ok(tour.closing && /Rust|native/.test(tour.closing), 'closing names the honest native gap');
});
