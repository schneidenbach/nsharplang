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
  sessionToken: string;
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
  const [loadedLessonId, setLoadedLessonId] = useState<string>("");
  const [sessionToken, setSessionToken] = useState("");
  const [code, setCode] = useState("");
  const [file, setFile] = useState("");
  const [toolResult, setToolResult] = useState<ToolResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [completions, setCompletions] = useState<Record<string, CompletionItem[]> | null>(null);
  const editorRef = useRef<HTMLTextAreaElement>(null);
  const highlightRef = useRef<HTMLPreElement>(null);
  const codeRef = useRef("");
  const lessonIdRef = useRef("");
  const sessionTokenRef = useRef("");
  const saveTimerRef = useRef<number | null>(null);
  const savedCodeRef = useRef({ lessonId: "", code: "" });

  useEffect(() => {
    void loadCatalog();
  }, []);

  useEffect(() => {
    if (lessonId) {
      void loadCode(lessonId);
    }
  }, [lessonId]);

  useEffect(() => {
    codeRef.current = code;
    requestAnimationFrame(syncHighlightedScroll);
  }, [code]);

  useEffect(() => {
    lessonIdRef.current = lessonId;
  }, [lessonId]);

  useEffect(() => {
    sessionTokenRef.current = sessionToken;
  }, [sessionToken]);

  useEffect(() => {
    if (!lessonId || !sessionToken || loadedLessonId !== lessonId) {
      return;
    }

    if (savedCodeRef.current.lessonId === lessonId && savedCodeRef.current.code === code) {
      return;
    }

    clearSaveTimer();
    saveTimerRef.current = window.setTimeout(() => {
      saveTimerRef.current = null;
      void saveLessonCode(lessonId, code);
    }, 450);

    return clearSaveTimer;
  }, [code, lessonId, loadedLessonId, sessionToken]);

  const selectedLesson = useMemo(
    () => catalog?.lessons.find(lesson => lesson.id === lessonId) ?? null,
    [catalog, lessonId]
  );

  async function loadCatalog() {
    const response = await fetch("/api/lessons");
    const data = await response.json() as Catalog;
    setCatalog(data);
    setSessionToken(data.sessionToken);
    setLessonId(data.lessons[0]?.id ?? "");
  }

  async function loadCode(id: string) {
    setLoadedLessonId("");
    const response = await fetch(`/api/lessons/${id}/code`);
    const data = await response.json() as CodeResponse;
    setCode(data.code);
    setFile(data.file);
    savedCodeRef.current = { lessonId: id, code: data.code };
    setLoadedLessonId(id);
    setCompletions(null);
    setToolResult(null);
  }

  async function switchLesson(id: string) {
    if (id === lessonId) return;
    await saveCurrentCode();
    setLessonId(id);
  }

  function clearSaveTimer() {
    if (saveTimerRef.current !== null) {
      window.clearTimeout(saveTimerRef.current);
      saveTimerRef.current = null;
    }
  }

  async function saveCurrentCode() {
    const currentLessonId = lessonIdRef.current;
    const currentCode = codeRef.current;
    if (!currentLessonId || loadedLessonId !== currentLessonId) {
      return;
    }

    if (savedCodeRef.current.lessonId === currentLessonId && savedCodeRef.current.code === currentCode) {
      return;
    }

    clearSaveTimer();
    await saveLessonCode(currentLessonId, currentCode);
  }

  async function saveLessonCode(id: string, nextCode: string) {
    const token = sessionTokenRef.current;
    if (!token) {
      return;
    }

    const response = await fetch(`/api/lessons/${id}/code`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-nsharp-tutorial-token": token
      },
      body: JSON.stringify({ code: nextCode })
    });

    if (!response.ok) {
      const message = await response.text();
      setToolResult({
        ok: false,
        command: "save",
        exitCode: response.status,
        timedOut: false,
        durationMs: 0,
        stdout: "",
        stderr: message
      });
      return;
    }

    savedCodeRef.current = { lessonId: id, code: nextCode };
  }

  async function runTool(path: string, body: object = { code }) {
    setBusy(true);
    setCompletions(null);
    try {
      const response = await fetch(`/api/lessons/${lessonId}/${path}`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-nsharp-tutorial-token": sessionToken
        },
        body: JSON.stringify(body)
      });
      const payload = await response.json();
      if (!response.ok) {
        const result: ToolResult = {
          ok: false,
          command: path,
          exitCode: response.status,
          timedOut: false,
          durationMs: 0,
          stdout: "",
          stderr: payload?.error ?? `Request failed with HTTP ${response.status}`
        };
        setToolResult(result);
        return result;
      }

      const result = payload as ToolResult;
      setToolResult(result);
      if (result.code) {
        setCode(result.code);
        savedCodeRef.current = { lessonId, code: result.code };
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
    const replaceStart = start === end ? currentPrefixStart(code, start) : start;
    const next = code.slice(0, replaceStart) + name + code.slice(end);
    setCode(next);
    setCompletions(null);
    requestAnimationFrame(() => {
      editor.focus();
      editor.selectionStart = editor.selectionEnd = replaceStart + name.length;
    });
  }

  function syncHighlightedScroll() {
    const editor = editorRef.current;
    const highlight = highlightRef.current;
    if (!editor || !highlight) return;

    highlight.scrollTop = editor.scrollTop;
    highlight.scrollLeft = editor.scrollLeft;
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
              type="button"
              className={`lesson-button ${lesson.id === lessonId ? "active" : ""}`}
              aria-current={lesson.id === lessonId ? "page" : undefined}
              aria-label={`Lesson ${index + 1}: ${lesson.title}. ${lesson.summary}`}
              onClick={() => void switchLesson(lesson.id)}
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
            <button type="button" className="primary" onClick={() => void runTool("run")} disabled={busy}>Run</button>
            <button type="button" onClick={() => void runTool("diagnostics")} disabled={busy}>Diagnostics</button>
            <button type="button" onClick={() => void askForCompletions()} disabled={busy}>Completions</button>
            <button type="button" onClick={() => void askForHover()} disabled={busy}>Hover</button>
            <button type="button" onClick={() => void runTool("format")} disabled={busy}>Format</button>
            <button type="button" onClick={() => void runTool("test")} disabled={busy || !selectedLesson.hasTests}>Test</button>
            <span className="tool-status">{busy ? "Running nlc..." : file}</span>
          </div>
          <div className="editor-wrap">
            <pre ref={highlightRef} className="code-highlight" aria-hidden="true">
              <code><HighlightedCode code={code} /></code>
            </pre>
            <textarea
              ref={editorRef}
              className="code-editor"
              spellCheck={false}
              wrap="off"
              value={code}
              onChange={event => setCode(event.target.value)}
              onScroll={syncHighlightedScroll}
            />
            {completions && <CompletionPanel completions={completions} onPick={insertCompletion} />}
          </div>
          <ToolOutput result={toolResult} />
        </section>
      </main>
    </div>
  );
}

function HighlightedCode(props: { code: string }) {
  const tokens = tokenizeNSharp(props.code);
  if (tokens.length === 0) {
    return " ";
  }

  return (
    <>
      {tokens.map((token, index) =>
        token.kind
          ? <span className={`tok-${token.kind}`} key={index}>{token.text}</span>
          : token.text)}
    </>
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
            <button type="button" className="completion-item" key={`${group}-${item.name}`} onClick={() => props.onPick(item.name)}>
              <span>{item.name}</span>
              <span className="completion-kind">{item.kind}{item.type ? ` · ${item.type}` : ""}</span>
            </button>
          ))}
        </div>
      ))}
    </aside>
  );
}

type HighlightToken = {
  text: string;
  kind?: string;
};

const nsharpKeywords = new Set([
  "abstract", "as", "async", "await", "base", "break", "case", "catch", "checked",
  "class", "const", "constructor", "continue", "default", "do", "duck", "else",
  "enum", "explicit", "extern", "false", "file", "finally", "for", "foreach",
  "func", "get", "if", "implicit", "import", "in", "init", "interface", "internal",
  "is", "let", "lock", "match", "namespace", "new", "not", "null", "operator",
  "or", "out", "override", "package", "params", "private", "protected", "public",
  "readonly", "record", "ref", "required", "return", "sealed", "set", "setup",
  "skip", "static", "struct", "switch", "teardown", "test", "this", "throw",
  "true", "try", "unchecked", "union", "using", "var", "virtual", "when", "while",
  "with", "yield"
]);

const nsharpBuiltins = new Set([
  "assert", "bool", "byte", "char", "decimal", "double", "float", "int", "long",
  "object", "print", "sbyte", "short", "string", "uint", "ulong", "ushort", "void"
]);

function tokenizeNSharp(source: string): HighlightToken[] {
  const tokens: HighlightToken[] = [];
  let index = 0;

  while (index < source.length) {
    const char = source[index];
    const next = source[index + 1];

    if (/\s/.test(char)) {
      const start = index++;
      while (index < source.length && /\s/.test(source[index])) index++;
      tokens.push({ text: source.slice(start, index) });
      continue;
    }

    if (char === "/" && next === "/") {
      const start = index;
      index += 2;
      while (index < source.length && source[index] !== "\n") index++;
      tokens.push({ text: source.slice(start, index), kind: "comment" });
      continue;
    }

    if (char === "/" && next === "*") {
      const start = index;
      index += 2;
      while (index < source.length && !(source[index] === "*" && source[index + 1] === "/")) index++;
      index = Math.min(index + 2, source.length);
      tokens.push({ text: source.slice(start, index), kind: "comment" });
      continue;
    }

    if (char === "#" && (index === 0 || source[index - 1] === "\n")) {
      const start = index++;
      while (index < source.length && source[index] !== "\n") index++;
      tokens.push({ text: source.slice(start, index), kind: "directive" });
      continue;
    }

    if (char === "\"" || char === "'" || (char === "$" && next === "\"")) {
      const start = index;
      index = readStringLike(source, index);
      tokens.push({ text: source.slice(start, index), kind: "string" });
      continue;
    }

    if (/[0-9]/.test(char)) {
      const start = index++;
      while (index < source.length && /[A-Za-z0-9_.]/.test(source[index])) index++;
      tokens.push({ text: source.slice(start, index), kind: "number" });
      continue;
    }

    if (/[A-Za-z_]/.test(char)) {
      const start = index++;
      while (index < source.length && /[A-Za-z0-9_]/.test(source[index])) index++;
      const word = source.slice(start, index);
      const kind = nsharpKeywords.has(word)
        ? "keyword"
        : nsharpBuiltins.has(word)
          ? "builtin"
          : /^[A-Z]/.test(word)
            ? "type"
            : undefined;
      tokens.push({ text: word, kind });
      continue;
    }

    const operatorStart = index++;
    while (index < source.length && /[+\-*%=!<>|&?:.,;()[\]{}]/.test(source[index])) {
      if ("()[]{}.,;".includes(source[index - 1])) break;
      index++;
    }
    tokens.push({ text: source.slice(operatorStart, index), kind: "symbol" });
  }

  return tokens;
}

function readStringLike(source: string, start: number) {
  const quote = source[start] === "$" ? source[start + 1] : source[start];
  let index = source[start] === "$" ? start + 2 : start + 1;

  if (quote === "\"" && source.startsWith("\"\"\"", source[start] === "$" ? start + 1 : start)) {
    const rawStart = source[start] === "$" ? start + 1 : start;
    index = rawStart + 3;
    while (index < source.length && !source.startsWith("\"\"\"", index)) index++;
    return Math.min(index + 3, source.length);
  }

  while (index < source.length) {
    if (source[index] === "\\" && quote !== "\"") {
      index += 2;
      continue;
    }

    if (source[index] === "\\" && quote === "\"") {
      index += 2;
      continue;
    }

    if (source[index] === quote) {
      index++;
      break;
    }

    index++;
  }

  return index;
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

function currentPrefixStart(value: string, cursor: number) {
  let index = cursor;
  while (index > 0 && /[A-Za-z0-9_]/.test(value[index - 1])) {
    index--;
  }
  return index;
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
