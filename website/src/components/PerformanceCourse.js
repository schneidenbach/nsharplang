import React, {Suspense, useCallback, useEffect, useMemo, useState} from 'react';
import BrowserOnly from '@docusaurus/BrowserOnly';
import useBaseUrl from '@docusaurus/useBaseUrl';
import Link from '@docusaurus/Link';
import CodeBlock from '@theme/CodeBlock';
import {
  AlertTriangle,
  ArrowLeft,
  ArrowRight,
  BookOpen,
  CheckCircle2,
  Circle,
  Lightbulb,
  Lock,
  Play,
  RotateCcw,
} from 'lucide-react';
import {
  loadNSharpRuntime,
  registerNSharpLanguage,
  normalizeRunResponse,
  normalizeVersion,
} from '../lib/nsharpRuntime';
import {kernels, moduleKernel, allocationStories} from '../data/perfTelemetry.mjs';
import {renderInline, Markdown} from '../lib/miniMarkdown';
import TelemetryPanel from './TelemetryPanel';
import modules from '../data/perfCourse.json';

const MonacoEditor = React.lazy(() => import('@monaco-editor/react'));
const STORAGE_KEY = 'nsharp-perf-course-progress-v1';
const LANGS = [
  {key: 'nsharp', label: 'N#', prism: 'nsharp'},
  {key: 'csharp', label: 'C#', prism: 'csharp'},
  {key: 'rust', label: 'Rust', prism: 'rust'},
];

function normalizeOutput(value) {
  return (value ?? '').replace(/\r\n/g, '\n').replace(/\r/g, '\n');
}

function validatePuzzle(puzzle, code, runResult) {
  if (!runResult) {
    return {state: 'pending', message: 'Run your program to check the puzzle.'};
  }
  if (!runResult.ok) {
    return {state: 'error', message: runResult.unsupportedReason || 'The program did not run cleanly — fix the errors and run again.'};
  }
  if (puzzle.requiredText && !code.includes(puzzle.requiredText)) {
    return {state: 'error', message: `Keep using \`${puzzle.requiredText}\` in your solution.`};
  }
  if (normalizeOutput(runResult.stdout) !== normalizeOutput(puzzle.expectedOutput)) {
    return {state: 'error', message: 'Close — the output does not match what the puzzle expects yet.'};
  }
  return {state: 'ok', message: puzzle.successMessage};
}

function ModuleEditor({code, onChange}) {
  function beforeMount(monaco) {
    registerNSharpLanguage(monaco);
  }

  // Editable textarea fallback covers SSR, the lazy import of the editor
  // wrapper, AND the window while Monaco's engine loads from its CDN — so the
  // puzzle is always editable even if Monaco is slow or blocked.
  const fallback = (
    <textarea
      className="course-editor__fallback"
      value={code}
      spellCheck={false}
      onChange={(event) => onChange(event.target.value)}
    />
  );

  return (
    <div className="course-editor">
      <div className="course-editor__host">
        <BrowserOnly fallback={fallback}>
          {() => (
            <Suspense fallback={fallback}>
              <MonacoEditor
                beforeMount={beforeMount}
                height="100%"
                language="nsharp"
                loading={fallback}
                onChange={(value) => onChange(value ?? '')}
                options={{
                  automaticLayout: true,
                  detectIndentation: false,
                  fixedOverflowWidgets: true,
                  fontFamily: '"SFMono-Regular", "SF Mono", Menlo, Consolas, monospace',
                  fontSize: 13,
                  insertSpaces: true,
                  lineHeight: 20,
                  minimap: {enabled: false},
                  quickSuggestions: false,
                  renderLineHighlight: 'all',
                  scrollBeyondLastLine: false,
                  tabSize: 4,
                  wordBasedSuggestions: 'off',
                }}
                path="Program.nl"
                theme="nsharp-light"
                value={code}
              />
            </Suspense>
          )}
        </BrowserOnly>
      </div>
    </div>
  );
}

export default function PerformanceCourse() {
  const loaderUrl = useBaseUrl('/playground/nsharp-playground.js');
  const [playground, setPlayground] = useState(null);
  const [version, setVersion] = useState(null);
  const [loadError, setLoadError] = useState(null);
  const [isWorking, setIsWorking] = useState(false);

  const [activeIndex, setActiveIndex] = useState(0);
  const [activeLang, setActiveLang] = useState('nsharp');
  const [completed, setCompleted] = useState(() => new Set());
  const [code, setCode] = useState(modules[0].puzzle.starterCode);
  const [runResult, setRunResult] = useState(null);
  const [runMs, setRunMs] = useState(null);

  const activeModule = modules[activeIndex];
  const kernelKey = moduleKernel[activeModule.id];
  const kernel = kernelKey ? kernels[kernelKey] : null;
  const allocationStory = allocationStories[activeModule.id] ?? null;

  // Load persisted progress.
  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY);
      if (raw) {
        setCompleted(new Set(JSON.parse(raw)));
      }
    } catch {
      /* ignore */
    }
  }, []);

  const persist = useCallback((next) => {
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify([...next]));
    } catch {
      /* ignore */
    }
  }, []);

  // Load the WASM compiler runtime.
  useEffect(() => {
    let cancelled = false;
    loadNSharpRuntime(loaderUrl)
      .then((loaded) => {
        if (cancelled) {
          return;
        }
        setPlayground(loaded);
        try {
          setVersion(normalizeVersion(loaded.version()));
        } catch {
          /* ignore */
        }
      })
      .catch((error) => {
        if (!cancelled) {
          setLoadError(error instanceof Error ? error.message : String(error));
        }
      });
    return () => {
      cancelled = true;
    };
  }, [loaderUrl]);

  const validation = useMemo(
    () => validatePuzzle(activeModule.puzzle, code, runResult),
    [activeModule, code, runResult],
  );

  const isUnlocked = useCallback(
    (index) => index === 0 || completed.has(modules[index - 1].id),
    [completed],
  );

  const goToModule = useCallback((index) => {
    if (index < 0 || index >= modules.length) {
      return;
    }
    setActiveIndex(index);
    setActiveLang('nsharp');
    setCode(modules[index].puzzle.starterCode);
    setRunResult(null);
    setRunMs(null);
  }, []);

  async function runProgram() {
    if (!playground?.runProject) {
      return;
    }
    setIsWorking(true);
    const started = (typeof performance !== 'undefined' ? performance.now() : 0);
    try {
      const files = [{name: 'Program.nl', code}];
      const run = normalizeRunResponse(await playground.runProject(files, 'Program.nl'));
      const elapsed = (typeof performance !== 'undefined' ? performance.now() : 0) - started;
      setRunResult(run);
      setRunMs(elapsed);

      const result = validatePuzzle(activeModule.puzzle, code, run);
      if (result.state === 'ok' && !completed.has(activeModule.id)) {
        setCompleted((current) => {
          const next = new Set(current);
          next.add(activeModule.id);
          persist(next);
          return next;
        });
      }
    } catch (error) {
      setLoadError(error instanceof Error ? error.message : String(error));
    } finally {
      setIsWorking(false);
    }
  }

  const canRun = Boolean(playground) && !isWorking;
  const moduleDone = completed.has(activeModule.id);
  const canAdvance = moduleDone && activeIndex < modules.length - 1;
  const progressPct = Math.round((completed.size / modules.length) * 100);
  const langCode = activeModule.languages[activeLang];

  return (
    <div className="learn-page">
      <div className="learn-breadcrumb">
        <Link to="/learn">Learn</Link>
        <span>›</span>
        <span>High Performance from Scratch</span>
      </div>

      <div className="learn-hero">
        <span className="learn-hero__eyebrow"><BookOpen size={12} aria-hidden="true" /> Guided course · {modules.length} modules</span>
        <h1 className="learn-hero__title">High Performance from Scratch</h1>
        <p className="learn-hero__lede">
          Learn what actually makes code fast — memory, allocation, branches, SIMD, dispatch — one idea at a
          time, with N#, C#, and Rust side by side and real measured numbers. Solve each puzzle to unlock the
          next module.
        </p>
      </div>

      {loadError && (
        <div className="course-alert">
          <AlertTriangle size={15} aria-hidden="true" />
          <span>{loadError}</span>
        </div>
      )}

      <div className="course">
        {/* sidebar */}
        <aside className="course-sidebar" aria-label="Course modules">
          <div className="course-progress">
            <div className="course-progress__bar">
              <div className="course-progress__fill" style={{width: `${progressPct}%`}} />
            </div>
            <div className="course-progress__label">{completed.size} of {modules.length} complete</div>
          </div>
          <ul className="course-modulelist">
            {modules.map((module, index) => {
              const done = completed.has(module.id);
              const unlocked = isUnlocked(index);
              const isActive = index === activeIndex;
              return (
                <li key={module.id}>
                  <button
                    type="button"
                    className={[
                      'course-modulelist__item',
                      isActive ? 'course-modulelist__item--active' : '',
                      !unlocked ? 'course-modulelist__item--locked' : '',
                    ].join(' ').trim()}
                    disabled={!unlocked}
                    onClick={() => unlocked && goToModule(index)}>
                    <span className={`course-modulelist__num ${done ? 'course-modulelist__num--done' : ''}`}>
                      {done ? <CheckCircle2 size={12} aria-hidden="true" /> : unlocked ? index + 1 : <Lock size={11} aria-hidden="true" />}
                    </span>
                    <span>{module.title}</span>
                  </button>
                </li>
              );
            })}
          </ul>
        </aside>

        {/* main */}
        <section className="course-main">
          <div>
            <span className="course-module__kicker">Module {activeIndex + 1} · {moduleDone ? 'Complete' : 'In progress'}</span>
            <h2 className="course-module__title">{activeModule.title}</h2>
            <p className="course-module__subtitle">{activeModule.subtitle}</p>
          </div>

          {/* concept */}
          <div className="course-card">
            <div className="course-card__head"><BookOpen size={13} aria-hidden="true" /> The idea</div>
            <div className="course-card__body">
              <div className="course-concept"><Markdown text={activeModule.concept} /></div>
              <ul className="course-takeaways">
                {activeModule.keyTakeaways.map((takeaway, index) => (
                  <li key={index}><CheckCircle2 size={15} aria-hidden="true" /><span>{renderInline(takeaway)}</span></li>
                ))}
              </ul>
            </div>
          </div>

          {/* same kernel in three languages */}
          <div className="course-card">
            <div className="course-card__head">The same kernel in three languages</div>
            <div className="course-langtabs">
              {LANGS.map((lang) => (
                <button
                  key={lang.key}
                  type="button"
                  className={`course-langtab ${activeLang === lang.key ? 'course-langtab--active' : ''}`}
                  onClick={() => setActiveLang(lang.key)}>
                  {lang.label}
                </button>
              ))}
            </div>
            <div className="course-lang__code">
              <CodeBlock language={LANGS.find((l) => l.key === activeLang).prism}>{langCode.code}</CodeBlock>
            </div>
            <div className="course-langnote"><strong>{LANGS.find((l) => l.key === activeLang).label}:</strong> {langCode.note}</div>
          </div>

          {/* telemetry */}
          <div className="course-card">
            <div className="course-card__head">Why it's faster — measured telemetry</div>
            <div className="course-card__body">
              <TelemetryPanel kernel={kernel} allocationStory={allocationStory} />
              <p className="course-memory" style={{marginTop: 14, paddingTop: 14, borderTop: '1px solid var(--line)'}}>
                {renderInline(activeModule.memoryStory)}
              </p>
            </div>
          </div>

          {/* puzzle */}
          <div className="course-card">
            <div className="course-card__head"><Play size={13} aria-hidden="true" /> Puzzle</div>
            <div className="course-card__body">
              <p className="course-puzzle__prompt">{renderInline(activeModule.puzzle.prompt)}</p>
              <div className="course-puzzle__layout">
                <ModuleEditor code={code} onChange={setCode} />
                <div className="course-puzzle__side">
                  <div className="course-output">
                    <div className="course-output__head">
                      <span>Output</span>
                      {runMs != null && (
                        <span className="course-output__timing">
                          ran in {runMs < 1 ? '<1' : runMs.toFixed(0)} ms · in-browser interpreter (illustrative)
                        </span>
                      )}
                    </div>
                    <div className="course-output__body">
                      {runResult ? (
                        runResult.stdout ? (
                          <pre className="course-output__stdout">{runResult.stdout}</pre>
                        ) : (
                          <span className="course-output__empty">No output.</span>
                        )
                      ) : (
                        <span className="course-output__empty">Run your program to see its output here.</span>
                      )}
                      <div className="course-output__expected">
                        Expected:
                        <pre>{activeModule.puzzle.expectedOutput}</pre>
                      </div>
                    </div>
                  </div>

                  <div className={`course-validation course-validation--${validation.state}`}>
                    {validation.state === 'ok' ? <CheckCircle2 size={15} aria-hidden="true" />
                      : validation.state === 'error' ? <AlertTriangle size={15} aria-hidden="true" />
                      : <Circle size={15} aria-hidden="true" />}
                    <span>{renderInline(validation.message)}</span>
                  </div>
                </div>
              </div>

              <div className="course-puzzle__actions" style={{marginTop: 12}}>
                <button type="button" className="course-btn course-btn--primary" disabled={!canRun} onClick={runProgram}>
                  <Play size={14} aria-hidden="true" /> {isWorking ? 'Running…' : 'Run'}
                </button>
                <button type="button" className="course-btn" onClick={() => {
                  setCode(activeModule.puzzle.starterCode);
                  setRunResult(null);
                  setRunMs(null);
                }}>
                  <RotateCcw size={14} aria-hidden="true" /> Reset
                </button>
                {!playground && !loadError && <span className="course-output__empty">Loading the N# compiler…</span>}
              </div>

              <details className="course-hint">
                <summary><Lightbulb size={13} aria-hidden="true" style={{verticalAlign: '-2px'}} /> Stuck? Show a hint</summary>
                <p>{renderInline(activeModule.puzzle.hint)}</p>
              </details>
            </div>
          </div>

          {/* nav */}
          <div className="course-nav">
            <button type="button" className="course-btn" disabled={activeIndex === 0} onClick={() => goToModule(activeIndex - 1)}>
              <ArrowLeft size={14} aria-hidden="true" /> Previous
            </button>
            {activeIndex < modules.length - 1 ? (
              <button type="button" className="course-btn course-btn--primary" disabled={!canAdvance} onClick={() => goToModule(activeIndex + 1)}>
                {moduleDone ? 'Next module' : 'Solve the puzzle to continue'} <ArrowRight size={14} aria-hidden="true" />
              </button>
            ) : (
              <Link className="course-btn course-btn--primary" to="/learn/systems">
                Finish → the Systems Tour <ArrowRight size={14} aria-hidden="true" />
              </Link>
            )}
          </div>
        </section>
      </div>

      {version?.compiler && (
        <p className="telemetry-provenance" style={{marginTop: 24}}>Puzzles run on the N# WebAssembly compiler ({version.compiler}). The in-browser timing is an illustrative interpreter measurement; the telemetry charts above are the real benchmark numbers.</p>
      )}
    </div>
  );
}
