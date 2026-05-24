const state = {
  catalog: null,
  lessonId: "",
  code: "",
  file: "",
  toolResult: null,
  busy: false,
  completions: null
};

const root = document.getElementById("root");

init().catch(error => {
  root.innerHTML = `<main class="empty">Tutorial failed to load: ${escapeHtml(error.message)}</main>`;
});

async function init() {
  const response = await fetch("/api/lessons");
  state.catalog = await response.json();
  state.lessonId = state.catalog.lessons[0]?.id ?? "";
  await loadCode(state.lessonId);
  render();
}

async function loadCode(lessonId) {
  const response = await fetch(`/api/lessons/${lessonId}/code`);
  const data = await response.json();
  state.code = data.code;
  state.file = data.file;
  state.toolResult = null;
  state.completions = null;
}

function selectedLesson() {
  return state.catalog?.lessons.find(lesson => lesson.id === state.lessonId) ?? null;
}

function render() {
  const catalog = state.catalog;
  const lesson = selectedLesson();
  if (!catalog || !lesson) {
    root.innerHTML = `<div class="app"><main class="empty">Loading tutorial...</main></div>`;
    return;
  }

  root.innerHTML = `
    <div class="app">
      <header class="topbar">
        <div class="brand">
          <h1>N# Tutorial</h1>
          <span>${catalog.estimatedMinutes} minute local walkthrough</span>
        </div>
        <div class="status-strip">
          <span class="status-dot" aria-hidden="true"></span>
          <span>${escapeHtml(catalog.workspaceRoot)}</span>
        </div>
      </header>
      <main class="workspace">
        <nav class="lesson-nav" aria-label="Lessons">
          <p class="nav-title">Lessons</p>
          ${catalog.lessons.map((item, index) => lessonButton(item, index)).join("")}
        </nav>
        <section class="lesson-pane">
          <h2>${escapeHtml(lesson.title)}</h2>
          <p class="summary">${escapeHtml(lesson.summary)}</p>
          <p class="goal">${escapeHtml(lesson.goal)}</p>
          <div class="concepts">
            ${lesson.concepts.map(concept => `<span class="chip">${escapeHtml(concept)}</span>`).join("")}
          </div>
          <div class="contrast">${escapeHtml(lesson.cSharpContrast)}</div>
          <a class="source-link" href="/source/app.tsx" target="_blank" rel="noreferrer">View TypeScript source</a>
        </section>
        <section class="editor-pane">
          <div class="toolbar">
            <button class="primary" data-tool="run" ${disabledIfBusy()}>Run</button>
            <button data-tool="diagnostics" ${disabledIfBusy()}>Diagnostics</button>
            <button data-action="completions" ${disabledIfBusy()}>Completions</button>
            <button data-action="hover" ${disabledIfBusy()}>Hover</button>
            <button data-tool="format" ${disabledIfBusy()}>Format</button>
            <button data-tool="test" ${disabledIfBusy() || !lesson.hasTests ? "disabled" : ""}>Test</button>
            <span class="tool-status">${state.busy ? "Running nlc..." : escapeHtml(state.file)}</span>
          </div>
          <div class="editor-wrap">
            <textarea class="code-editor" spellcheck="false">${escapeHtml(state.code)}</textarea>
            ${completionPanel()}
          </div>
          ${toolOutput()}
        </section>
      </main>
    </div>`;

  wireEvents();
}

function lessonButton(lesson, index) {
  const active = lesson.id === state.lessonId ? " active" : "";
  return `
    <button class="lesson-button${active}" data-lesson="${escapeAttr(lesson.id)}">
      <span class="lesson-number">${index + 1}</span>
      <span>
        <span class="lesson-name">${escapeHtml(lesson.title)}</span>
        <span class="lesson-summary">${escapeHtml(lesson.summary)}</span>
      </span>
    </button>`;
}

function wireEvents() {
  document.querySelectorAll("[data-lesson]").forEach(button => {
    button.addEventListener("click", async () => {
      state.lessonId = button.dataset.lesson;
      await loadCode(state.lessonId);
      render();
    });
  });

  const editor = document.querySelector(".code-editor");
  editor?.addEventListener("input", event => {
    state.code = event.target.value;
  });

  document.querySelectorAll("[data-tool]").forEach(button => {
    button.addEventListener("click", () => runTool(button.dataset.tool));
  });

  document.querySelector("[data-action='completions']")?.addEventListener("click", askForCompletions);
  document.querySelector("[data-action='hover']")?.addEventListener("click", askForHover);

  document.querySelectorAll("[data-completion]").forEach(button => {
    button.addEventListener("click", () => insertCompletion(button.dataset.completion));
  });
}

async function runTool(path, body = { code: state.code }) {
  state.busy = true;
  state.completions = null;
  render();

  const response = await fetch(`/api/lessons/${state.lessonId}/${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body)
  });
  const result = await response.json();
  state.toolResult = result;
  if (result.code) {
    state.code = result.code;
  }
  state.busy = false;
  render();
  return result;
}

async function askForCompletions() {
  const editor = document.querySelector(".code-editor");
  const position = cursorPosition(editor);
  const result = await runTool("completions", { code: state.code, line: position.line, column: position.column });
  const parsed = parseJson(result.stdout);
  state.completions = parsed?.completions ?? null;
  render();
}

async function askForHover() {
  const editor = document.querySelector(".code-editor");
  const position = cursorPosition(editor);
  await runTool("hover", { code: state.code, line: position.line, column: position.column });
}

function insertCompletion(name) {
  const editor = document.querySelector(".code-editor");
  if (!editor) return;

  const start = editor.selectionStart;
  const end = editor.selectionEnd;
  state.code = state.code.slice(0, start) + name + state.code.slice(end);
  state.completions = null;
  render();

  const nextEditor = document.querySelector(".code-editor");
  if (nextEditor) {
    nextEditor.focus();
    nextEditor.selectionStart = nextEditor.selectionEnd = start + name.length;
  }
}

function completionPanel() {
  if (!state.completions) return "";
  const groups = Object.entries(state.completions).filter(([, items]) => items.length > 0);
  if (groups.length === 0) return "";

  return `
    <aside class="completion-panel">
      <h3>Completions</h3>
      ${groups.map(([group, items]) => `
        <div class="completion-group">
          <div class="completion-group-title">${escapeHtml(group)}</div>
          ${items.slice(0, 12).map(item => `
            <button class="completion-item" data-completion="${escapeAttr(item.name)}">
              <span>${escapeHtml(item.name)}</span>
              <span class="completion-kind">${escapeHtml(item.kind)}${item.type ? ` · ${escapeHtml(item.type)}` : ""}</span>
            </button>`).join("")}
        </div>`).join("")}
    </aside>`;
}

function toolOutput() {
  const result = state.toolResult;
  if (!result) {
    return `
      <section class="output">
        <div class="output-header"><strong>Output</strong><span>Run a tool to see \`nlc\` output.</span></div>
        <pre class="output-body empty">No command has run yet.</pre>
      </section>`;
  }

  const text = [result.stdout, result.stderr].filter(Boolean).join("\n") || "(no output)";
  return `
    <section class="output">
      <div class="output-header">
        <strong class="${result.ok ? "ok" : "bad"}">${result.ok ? "ok" : "attention"}</strong>
        <span>${escapeHtml(result.command)} · exit ${result.exitCode} · ${result.durationMs}ms</span>
      </div>
      <pre class="output-body">${escapeHtml(text)}</pre>
    </section>`;
}

function cursorPosition(editor) {
  const value = editor?.value ?? state.code;
  const selection = editor?.selectionStart ?? value.length;
  const before = value.slice(0, selection);
  const lines = before.split("\n");
  return { line: lines.length, column: lines[lines.length - 1].length };
}

function parseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function disabledIfBusy() {
  return state.busy ? "disabled" : "";
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function escapeAttr(value) {
  return escapeHtml(value).replace(/`/g, "&#096;");
}
