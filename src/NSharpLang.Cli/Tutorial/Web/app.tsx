import React, { useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";

type Lesson = {
  id: string;
  title: string;
  summary: string;
  minutes: number;
  goal: string;
  concepts: string[];
  cSharpContrast: string;
  hasTests: boolean;
};

type Catalog = {
  workspaceRoot: string;
  estimatedMinutes: number;
  lessons: Lesson[];
};

type CodeResponse = {
  code: string;
  file: string;
  testsFile?: string;
  tests?: string;
};

type ToolResult = {
  ok: boolean;
  command: string;
  exitCode: number;
  timedOut: boolean;
  durationMs: number;
  stdout: string;
  stderr: string;
  code?: string;
};

type CompletionItem = {
  name: string;
  kind: string;
  type?: string;
  parameters?: string;
};

function App() {
  const [catalog, setCatalog] = useState<Catalog | null>(null);
  const [lessonId, setLessonId] = useState<string>("");
  const [code, setCode] = useState("");
  const [file, setFile] = useState("");
  const [toolResult, setToolResult] = useState<ToolResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [completions, setCompletions] = useState<Record<string, CompletionItem[]> | null>(null);
  const editorRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    void loadCatalog();
  }, []);

  useEffect(() => {
    if (lessonId) {
      void loadCode(lessonId);
    }
  }, [lessonId]);

  const selectedLesson = useMemo(
    () => catalog?.lessons.find(lesson => lesson.id === lessonId) ?? null,
    [catalog, lessonId]
  );

  async function loadCatalog() {
    const response = await fetch("/api/lessons");
    const data = await response.json() as Catalog;
    setCatalog(data);
    setLessonId(data.lessons[0]?.id ?? "");
  }

  async function loadCode(id: string) {
    const response = await fetch(`/api/lessons/${id}/code`);
    const data = await response.json() as CodeResponse;
    setCode(data.code);
    setFile(data.file);
    setCompletions(null);
    setToolResult(null);
  }

  async function runTool(path: string, body: object = { code }) {
    setBusy(true);
    setCompletions(null);
    try {
      const response = await fetch(`/api/lessons/${lessonId}/${path}`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body)
      });
      const result = await response.json() as ToolResult;
      setToolResult(result);
      if (result.code) {
        setCode(result.code);
      }
      return result;
    } finally {
      setBusy(false);
    }
  }

  async function askForCompletions() {
    const position = cursorPosition(editorRef.current);
    const result = await runTool("completions", { code, line: position.line, column: position.column });
    const parsed = parseJson(result.stdout);
    setCompletions(parsed?.completions ?? null);
  }

  async function askForHover() {
    const position = cursorPosition(editorRef.current);
    await runTool("hover", { code, line: position.line, column: position.column });
  }

  function insertCompletion(name: string) {
    const editor = editorRef.current;
    if (!editor) return;

    const start = editor.selectionStart;
    const end = editor.selectionEnd;
    const next = code.slice(0, start) + name + code.slice(end);
    setCode(next);
    setCompletions(null);
    requestAnimationFrame(() => {
      editor.focus();
      editor.selectionStart = editor.selectionEnd = start + name.length;
    });
  }

  if (!catalog || !selectedLesson) {
    return <div className="app"><main className="empty">Loading tutorial...</main></div>;
  }

  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">
          <h1>N# Tutorial</h1>
          <span>{catalog.estimatedMinutes} minute local walkthrough</span>
        </div>
        <div className="status-strip">
          <span className="status-dot" aria-hidden="true" />
          <span>{catalog.workspaceRoot}</span>
        </div>
      </header>
      <main className="workspace">
        <nav className="lesson-nav" aria-label="Lessons">
          <p className="nav-title">Lessons</p>
          {catalog.lessons.map((lesson, index) => (
            <button
              key={lesson.id}
              className={`lesson-button ${lesson.id === lessonId ? "active" : ""}`}
              onClick={() => setLessonId(lesson.id)}
            >
              <span className="lesson-number">{index + 1}</span>
              <span>
                <span className="lesson-name">{lesson.title}</span>
                <span className="lesson-summary">{lesson.summary}</span>
              </span>
            </button>
          ))}
        </nav>
        <section className="lesson-pane">
          <h2>{selectedLesson.title}</h2>
          <p className="summary">{selectedLesson.summary}</p>
          <p className="goal">{selectedLesson.goal}</p>
          <div className="concepts">
            {selectedLesson.concepts.map(concept => <span className="chip" key={concept}>{concept}</span>)}
          </div>
          <div className="contrast">{selectedLesson.cSharpContrast}</div>
          <a className="source-link" href="/source/app.tsx" target="_blank" rel="noreferrer">View TypeScript source</a>
        </section>
        <section className="editor-pane">
          <div className="toolbar">
            <button className="primary" onClick={() => runTool("run")} disabled={busy}>Run</button>
            <button onClick={() => runTool("diagnostics")} disabled={busy}>Diagnostics</button>
            <button onClick={askForCompletions} disabled={busy}>Completions</button>
            <button onClick={askForHover} disabled={busy}>Hover</button>
            <button onClick={() => runTool("format")} disabled={busy}>Format</button>
            <button onClick={() => runTool("test")} disabled={busy || !selectedLesson.hasTests}>Test</button>
            <span className="tool-status">{busy ? "Running nlc..." : file}</span>
          </div>
          <div className="editor-wrap">
            <textarea
              ref={editorRef}
              className="code-editor"
              spellCheck={false}
              value={code}
              onChange={event => setCode(event.target.value)}
            />
            {completions && <CompletionPanel completions={completions} onPick={insertCompletion} />}
          </div>
          <ToolOutput result={toolResult} />
        </section>
      </main>
    </div>
  );
}

function CompletionPanel(props: { completions: Record<string, CompletionItem[]>; onPick(name: string): void }) {
  const groups = Object.entries(props.completions).filter(([, items]) => items.length > 0);
  if (groups.length === 0) return null;

  return (
    <aside className="completion-panel">
      <h3>Completions</h3>
      {groups.map(([group, items]) => (
        <div className="completion-group" key={group}>
          <div className="completion-group-title">{group}</div>
          {items.slice(0, 12).map(item => (
            <button className="completion-item" key={`${group}-${item.name}`} onClick={() => props.onPick(item.name)}>
              <span>{item.name}</span>
              <span className="completion-kind">{item.kind}{item.type ? ` · ${item.type}` : ""}</span>
            </button>
          ))}
        </div>
      ))}
    </aside>
  );
}

function ToolOutput(props: { result: ToolResult | null }) {
  if (!props.result) {
    return (
      <section className="output">
        <div className="output-header"><strong>Output</strong><span>Run a tool to see `nlc` output.</span></div>
        <pre className="output-body empty">No command has run yet.</pre>
      </section>
    );
  }

  const result = props.result;
  const text = [result.stdout, result.stderr].filter(Boolean).join("\n");
  return (
    <section className="output">
      <div className="output-header">
        <strong className={result.ok ? "ok" : "bad"}>{result.ok ? "ok" : "attention"}</strong>
        <span>{result.command} · exit {result.exitCode} · {result.durationMs}ms</span>
      </div>
      <pre className="output-body">{text || "(no output)"}</pre>
    </section>
  );
}

function cursorPosition(editor: HTMLTextAreaElement | null) {
  const value = editor?.value ?? "";
  const selection = editor?.selectionStart ?? value.length;
  const before = value.slice(0, selection);
  const lines = before.split("\n");
  return { line: lines.length, column: lines[lines.length - 1].length };
}

function parseJson(text: string) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

createRoot(document.getElementById("root")!).render(<App />);
