import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname, join} from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const dataDir = join(here, '..', 'data');
const modules = JSON.parse(readFileSync(join(dataDir, 'perfCourse.json'), 'utf8'));
const tour = JSON.parse(readFileSync(join(dataDir, 'systemsTour.json'), 'utf8'));
// perfTelemetry is an ESM module; import its named exports.
const {kernels, moduleKernel, allocationStories} = await import(join(dataDir, 'perfTelemetry.mjs'));

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

test('systems tour has hero, pillars, and an honest closing', () => {
  assert.ok(tour.hero?.title && tour.hero?.lede);
  assert.ok(Array.isArray(tour.pillars) && tour.pillars.length >= 6);
  for (const p of tour.pillars) {
    assert.ok(p.title && p.opinion && p.body && p.code, `pillar ${p.title}`);
  }
  assert.ok(tour.closing && /Rust|native/.test(tour.closing), 'closing names the honest native gap');
});
