import React, { useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import * as monaco from "monaco-editor/esm/vs/editor/editor.api.js";
import "monaco-editor/esm/vs/editor/contrib/bracketMatching/browser/bracketMatching.js";
import "monaco-editor/esm/vs/editor/contrib/format/browser/formatActions.js";
import "monaco-editor/esm/vs/editor/contrib/hover/browser/hoverContribution.js";
import "monaco-editor/esm/vs/editor/contrib/indentation/browser/indentation.js";
import "monaco-editor/esm/vs/editor/contrib/suggest/browser/suggestController.js";

const PROGRAM_FILE = "Program.nl";
const TESTS_FILE = "Program.tests.nl";
const LSP_OWNER = "nsharp-lsp";
const HTTP_OWNER = "nsharp-http";
const N_SHARP_KEYWORDS = [
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
];
const N_SHARP_BUILTINS = [
  "assert", "bool", "byte", "char", "decimal", "double", "float", "int", "long",
  "object", "print", "sbyte", "short", "string", "uint", "ulong", "ushort", "void"
];

(globalThis as typeof globalThis & { MonacoEnvironment?: monaco.Environment }).MonacoEnvironment = {
  getWorker: () => new Worker("/assets/editor.worker.js", { type: "module", name: "nsharp-editor-worker" })
};

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

type TutorialFile = {
  name: string;
  path: string;
  code: string;
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
  documentation?: string;
};

type QueryDiagnostic = {
  code?: string;
  severity?: string;
  message?: string;
  file?: string;
  line?: number;
  column?: number;
  length?: number;
  explanation?: string;
  suggestion?: string;
  hint?: string;
};

type ProblemItem = {
  uri: string;
  file: string;
  line: number;
  column: number;
  severity: string;
  message: string;
  code?: string;
};

type LspPosition = { line: number; character: number };
type LspRange = { start: LspPosition; end: LspPosition };
type LspDiagnostic = {
  range: LspRange;
  severity?: number;
  code?: string | number;
  message: string;
};
type LspCompletionItem = {
  label: string;
  kind?: number;
  detail?: string;
  documentation?: string | { value?: string };
  insertText?: string;
  insertTextFormat?: number;
  filterText?: string;
  sortText?: string;
  textEdit?: { range?: LspRange; newText: string };
};
type LspHover = {
  contents?: string | { value?: string } | Array<string | { value?: string }>;
  range?: LspRange;
};
type LspTextEdit = {
  range: LspRange;
  newText: string;
};

type LspStatus = "offline" | "connecting" | "ready" | "error" | "disconnected";
type PanelTab = "problems" | "output";

class TutorialLspClient {
  private socket: WebSocket | null = null;
  private nextId = 1;
  private pending = new Map<number, {
    resolve(value: unknown): void;
    reject(reason?: unknown): void;
    timeout: number;
  }>();

  public ready = false;

  constructor(
    private readonly onDiagnostics: (uri: string, diagnostics: LspDiagnostic[]) => void,
    private readonly onStatus: (status: LspStatus) => void
  ) {
  }

  async connect(url: string, rootUri: string) {
    this.onStatus("connecting");
    const socket = new WebSocket(url);
    this.socket = socket;
    socket.onmessage = event => { void this.handleRawMessage(event.data); };
    socket.onerror = () => this.onStatus("error");
    socket.onclose = () => {
      this.ready = false;
      this.rejectPending(new Error("N# language server connection closed."));
      this.onStatus("disconnected");
    };

    await new Promise<void>((resolve, reject) => {
      socket.onopen = () => resolve();
      socket.onerror = () => reject(new Error("Could not open the N# language server WebSocket."));
    });

    await this.request("initialize", {
      processId: null,
      rootUri,
      workspaceFolders: [{ uri: rootUri, name: "nsharp-tutorial" }],
      clientInfo: { name: "nlc tutorial", version: "1.0.0" },
      capabilities: {
        textDocument: {
          synchronization: { dynamicRegistration: false, didSave: true },
          completion: {
            dynamicRegistration: false,
            completionItem: {
              documentationFormat: ["markdown", "plaintext"],
              snippetSupport: true
            }
          },
          hover: {
            dynamicRegistration: false,
            contentFormat: ["markdown", "plaintext"]
          },
          publishDiagnostics: {
            relatedInformation: true
          },
          formatting: {
            dynamicRegistration: false
          }
        },
        workspace: {
          workspaceFolders: true,
          configuration: false
        }
      }
    });

    this.notify("initialized", {});
    this.ready = true;
    this.onStatus("ready");
  }

  shutdown() {
    this.ready = false;
    if (this.socket?.readyState === WebSocket.OPEN) {
      this.socket.close(1000, "Tutorial closed.");
    }
    this.rejectPending(new Error("N# language server connection closed."));
  }

  didOpen(model: monaco.editor.ITextModel) {
    this.notify("textDocument/didOpen", {
      textDocument: {
        uri: model.uri.toString(),
        languageId: "nsharp",
        version: model.getVersionId(),
        text: model.getValue()
      }
    });
  }

  didChange(model: monaco.editor.ITextModel) {
    this.notify("textDocument/didChange", {
      textDocument: {
        uri: model.uri.toString(),
        version: model.getVersionId()
      },
      contentChanges: [{ text: model.getValue() }]
    });
  }

  didClose(model: monaco.editor.ITextModel) {
    this.notify("textDocument/didClose", {
      textDocument: { uri: model.uri.toString() }
    });
  }

  async completion(model: monaco.editor.ITextModel, position: monaco.Position): Promise<LspCompletionItem[]> {
    const result = await this.request("textDocument/completion", {
      textDocument: { uri: model.uri.toString() },
      position: toLspPosition(position)
    });

    if (Array.isArray(result)) {
      return result as LspCompletionItem[];
    }

    if (result && typeof result === "object" && Array.isArray((result as { items?: unknown[] }).items)) {
      return (result as { items: LspCompletionItem[] }).items;
    }

    return [];
  }

  async hover(model: monaco.editor.ITextModel, position: monaco.Position): Promise<LspHover | null> {
    const result = await this.request("textDocument/hover", {
      textDocument: { uri: model.uri.toString() },
      position: toLspPosition(position)
    });
    return result && typeof result === "object" ? result as LspHover : null;
  }

  async formatting(model: monaco.editor.ITextModel, options: monaco.languages.FormattingOptions): Promise<LspTextEdit[]> {
    const result = await this.request("textDocument/formatting", {
      textDocument: { uri: model.uri.toString() },
      options: {
        tabSize: options.tabSize,
        insertSpaces: options.insertSpaces
      }
    });
    return Array.isArray(result) ? result as LspTextEdit[] : [];
  }

  private request(method: string, params: unknown): Promise<unknown> {
    const id = this.nextId++;
    const message = { jsonrpc: "2.0", id, method, params };
    this.send(message);

    return new Promise((resolve, reject) => {
      const timeout = window.setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`N# language server request timed out: ${method}`));
      }, 8000);
      this.pending.set(id, { resolve, reject, timeout });
    });
  }

  private notify(method: string, params: unknown) {
    this.send({ jsonrpc: "2.0", method, params });
  }

  private send(message: unknown) {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
      throw new Error("N# language server is not connected.");
    }

    this.socket.send(JSON.stringify(message));
  }

  private async handleRawMessage(data: unknown) {
    const text = typeof data === "string"
      ? data
      : data instanceof Blob
        ? await data.text()
        : new TextDecoder().decode(data as ArrayBuffer);

    const message = JSON.parse(text) as {
      id?: number;
      method?: string;
      result?: unknown;
      error?: unknown;
      params?: unknown;
    };

    if (message.id !== undefined && !message.method) {
      const pending = this.pending.get(message.id);
      if (!pending) return;

      window.clearTimeout(pending.timeout);
      this.pending.delete(message.id);
      if (message.error) {
        pending.reject(message.error);
      } else {
        pending.resolve(message.result);
      }
      return;
    }

    if (message.method === "textDocument/publishDiagnostics") {
      const params = message.params as { uri?: string; diagnostics?: LspDiagnostic[] };
      if (params.uri) {
        this.onDiagnostics(params.uri, params.diagnostics ?? []);
      }
      return;
    }

    if (message.id !== undefined && message.method) {
      this.send({ jsonrpc: "2.0", id: message.id, result: null });
    }
  }

  private rejectPending(error: Error) {
    for (const [id, pending] of this.pending) {
      window.clearTimeout(pending.timeout);
      pending.reject(error);
      this.pending.delete(id);
    }
  }
}

function App() {
  const [catalog, setCatalog] = useState<Catalog | null>(null);
  const [lessonId, setLessonId] = useState("");
  const [loadedLessonId, setLoadedLessonId] = useState("");
  const [sessionToken, setSessionToken] = useState("");
  const [files, setFiles] = useState<TutorialFile[]>([]);
  const [activeFileName, setActiveFileName] = useState(PROGRAM_FILE);
  const [toolResult, setToolResult] = useState<ToolResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [loadError, setLoadError] = useState("");
  const [lspStatus, setLspStatus] = useState<LspStatus>("offline");
  const [problemItems, setProblemItems] = useState<ProblemItem[]>([]);
  const [panelTab, setPanelTab] = useState<PanelTab>("problems");
  const [editorReady, setEditorReady] = useState(false);

  const editorHostRef = useRef<HTMLDivElement>(null);
  const editorRef = useRef<monaco.editor.IStandaloneCodeEditor | null>(null);
  const modelsRef = useRef<Map<string, monaco.editor.ITextModel>>(new Map());
  const modelDisposablesRef = useRef<monaco.IDisposable[]>([]);
  const modelFileNamesRef = useRef<Map<string, string>>(new Map());
  const openedModelUrisRef = useRef<Set<string>>(new Set());
  const lspClientRef = useRef<TutorialLspClient | null>(null);
  const catalogRef = useRef<Catalog | null>(null);
  const filesRef = useRef<TutorialFile[]>([]);
  const lessonIdRef = useRef("");
  const loadedLessonIdRef = useRef("");
  const activeFileNameRef = useRef(PROGRAM_FILE);
  const sessionTokenRef = useRef("");
  const savedFilesRef = useRef<{ lessonId: string; files: Record<string, string> }>({ lessonId: "", files: {} });
  const saveTimersRef = useRef<Record<string, number>>({});
  const suggestTimerRef = useRef<number | null>(null);
  const problemsByUriRef = useRef<Record<string, ProblemItem[]>>({});

  const hasCatalog = catalog !== null;

  useEffect(() => {
    if (editorRef.current || !editorHostRef.current) {
      return;
    }

    registerNSharpLanguage();
    const editor = monaco.editor.create(editorHostRef.current, {
      automaticLayout: true,
      fontFamily: '"SFMono-Regular", Consolas, "Liberation Mono", monospace',
      fontSize: 14,
      lineHeight: 21,
      minimap: { enabled: false },
      renderLineHighlight: "all",
      scrollBeyondLastLine: false,
      smoothScrolling: true,
      tabSize: 4,
      insertSpaces: true,
      detectIndentation: false,
      quickSuggestions: { other: true, comments: false, strings: false },
      suggestOnTriggerCharacters: true,
      wordBasedSuggestions: "off",
      fixedOverflowWidgets: true,
      theme: "nsharp-tutorial"
    });

    editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () => { void saveAllDirty(); });
    editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.Enter, () => { void runTool("run"); });
    editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyMod.Shift | monaco.KeyCode.KeyB, () => { void runTool("test"); });
    editor.addCommand(monaco.KeyMod.Alt | monaco.KeyMod.Shift | monaco.KeyCode.KeyF, () => {
      void editor.getAction("editor.action.formatDocument")?.run();
    });
    editor.onDidChangeModelContent(event => handleEditorContentChange(event));
    editor.onKeyUp(event => maybeTriggerSuggest(event.browserEvent.key));
    editorRef.current = editor;

    const providerDisposables = registerNSharpProviders({
      getLspClient: () => lspClientRef.current,
      getFileNameForModel: modelFileName,
      requestBackendCompletions,
      requestBackendHover,
      requestBackendFormatting
    });

    setEditorReady(true);

    return () => {
      clearSaveTimers();
      clearSuggestTimer();
      providerDisposables.forEach(disposable => disposable.dispose());
      closeAndDisposeModels();
      editor.dispose();
    };
  }, [hasCatalog]);

  useEffect(() => {
    void loadCatalog();
  }, []);

  useEffect(() => {
    catalogRef.current = catalog;
  }, [catalog]);

  useEffect(() => {
    filesRef.current = files;
  }, [files]);

  useEffect(() => {
    lessonIdRef.current = lessonId;
    if (lessonId) {
      void loadCode(lessonId);
    }
  }, [lessonId]);

  useEffect(() => {
    loadedLessonIdRef.current = loadedLessonId;
  }, [loadedLessonId]);

  useEffect(() => {
    activeFileNameRef.current = activeFileName;
  }, [activeFileName]);

  useEffect(() => {
    sessionTokenRef.current = sessionToken;
  }, [sessionToken]);

  useEffect(() => {
    if (!catalog || !sessionToken) return;

    const client = new TutorialLspClient(
      (uri, diagnostics) => setLspDiagnostics(uri, diagnostics),
      status => setLspStatus(status)
    );
    lspClientRef.current = client;
    openedModelUrisRef.current.clear();

    void client.connect(lspWebSocketUrl(sessionToken), monaco.Uri.file(catalog.workspaceRoot).toString())
      .then(() => openExistingModelsInLsp())
      .catch(error => {
        console.error(error);
        setLspStatus("error");
        void refreshAllDiagnosticsFromBackend();
      });

    return () => {
      client.shutdown();
      lspClientRef.current = null;
      openedModelUrisRef.current.clear();
    };
  }, [catalog?.workspaceRoot, sessionToken]);

  useEffect(() => {
    if (editorReady && files.length > 0) {
      syncMonacoModels(files, activeFileName);
      if (lspClientRef.current?.ready) {
        openExistingModelsInLsp();
      }
    }
  }, [editorReady, loadedLessonId]);

  const selectedLesson = useMemo(
    () => catalog?.lessons.find(lesson => lesson.id === lessonId) ?? null,
    [catalog, lessonId]
  );

  const activeFile = useMemo(
    () => files.find(file => file.name === activeFileName) ?? files[0] ?? null,
    [files, activeFileName]
  );

  async function loadCatalog() {
    setLoadError("");
    try {
      const response = await fetch("/api/lessons");
      if (!response.ok) {
        throw new Error(`Tutorial catalog request failed with HTTP ${response.status}.`);
      }

      const data = await response.json() as Catalog;
      setCatalog(data);
      setSessionToken(data.sessionToken);
      setLessonId(data.lessons[0]?.id ?? "");
    } catch (error) {
      setLoadError(error instanceof Error ? error.message : String(error));
    }
  }

  async function loadCode(id: string) {
    setLoadedLessonId("");
    setToolResult(null);
    setProblemItems([]);
    problemsByUriRef.current = {};
    try {
      const response = await fetch(`/api/lessons/${id}/code`);
      if (!response.ok) {
        throw new Error(`Lesson code request failed with HTTP ${response.status}.`);
      }

      const data = await response.json() as CodeResponse;
      const nextFiles: TutorialFile[] = [
        { name: PROGRAM_FILE, path: data.file, code: data.code }
      ];

      if (data.testsFile && data.tests !== undefined) {
        nextFiles.push({ name: TESTS_FILE, path: data.testsFile, code: data.tests });
      }

      clearSaveTimers();
      savedFilesRef.current = {
        lessonId: id,
        files: Object.fromEntries(nextFiles.map(file => [file.name, file.code]))
      };
      filesRef.current = nextFiles;
      setFiles(nextFiles);
      setActiveFileName(PROGRAM_FILE);
      activeFileNameRef.current = PROGRAM_FILE;
      syncMonacoModels(nextFiles, PROGRAM_FILE);
      setLoadedLessonId(id);
    } catch (error) {
      setLoadError(error instanceof Error ? error.message : String(error));
    }
  }

  async function switchLesson(id: string) {
    if (id === lessonIdRef.current) return;
    await saveAllDirty();
    setLessonId(id);
  }

  function syncMonacoModels(nextFiles: TutorialFile[], nextActiveFileName: string) {
    if (!editorRef.current || nextFiles.length === 0) return;

    closeAndDisposeModels();
    modelFileNamesRef.current.clear();

    for (const file of nextFiles) {
      const uri = monaco.Uri.file(file.path);
      const model = monaco.editor.createModel(file.code, "nsharp", uri);
      modelsRef.current.set(file.name, model);
      modelFileNamesRef.current.set(model.uri.toString(), file.name);
    }

    const activeModel = modelsRef.current.get(nextActiveFileName) ?? modelsRef.current.get(PROGRAM_FILE) ?? null;
    editorRef.current.setModel(activeModel);
    if (activeModel) {
      editorRef.current.focus();
    }
  }

  function closeAndDisposeModels() {
    const client = lspClientRef.current;
    for (const model of modelsRef.current.values()) {
      const uri = model.uri.toString();
      if (client?.ready && openedModelUrisRef.current.has(uri)) {
        client.didClose(model);
      }
      monaco.editor.setModelMarkers(model, LSP_OWNER, []);
      monaco.editor.setModelMarkers(model, HTTP_OWNER, []);
      model.dispose();
    }

    modelDisposablesRef.current.forEach(disposable => disposable.dispose());
    modelDisposablesRef.current = [];
    modelsRef.current.clear();
    modelFileNamesRef.current.clear();
    openedModelUrisRef.current.clear();
  }

  function openExistingModelsInLsp() {
    const client = lspClientRef.current;
    if (!client?.ready) return;

    for (const model of modelsRef.current.values()) {
      const uri = model.uri.toString();
      if (!openedModelUrisRef.current.has(uri)) {
        client.didOpen(model);
        openedModelUrisRef.current.add(uri);
      }
    }
  }

  function handleEditorContentChange(event: monaco.editor.IModelContentChangedEvent) {
    const editor = editorRef.current;
    const model = editor?.getModel();
    if (!editor || !model) return;

    const fileName = modelFileName(model);
    const code = model.getValue();
    filesRef.current = filesRef.current.map(file => file.name === fileName ? { ...file, code } : file);
    setFiles(filesRef.current);
    scheduleSave(fileName, code);

    const client = lspClientRef.current;
    if (client?.ready) {
      client.didChange(model);
      monaco.editor.setModelMarkers(model, HTTP_OWNER, []);
    } else {
      scheduleBackendDiagnostics(fileName, code);
    }

    const lastChange = event.changes[event.changes.length - 1];
    if (lastChange) {
      maybeTriggerSuggest(lastChange.text);
    }
  }

  function changeActiveFile(fileName: string) {
    const model = modelsRef.current.get(fileName);
    if (!model || !editorRef.current) return;

    setActiveFileName(fileName);
    activeFileNameRef.current = fileName;
    editorRef.current.setModel(model);
    editorRef.current.focus();
  }

  function scheduleSave(fileName: string, code: string) {
    const existingTimer = saveTimersRef.current[fileName];
    if (existingTimer !== undefined) {
      window.clearTimeout(existingTimer);
    }

    saveTimersRef.current[fileName] = window.setTimeout(() => {
      delete saveTimersRef.current[fileName];
      void saveLessonFile(fileName, code);
    }, 450);
  }

  function clearSaveTimers() {
    for (const timer of Object.values(saveTimersRef.current)) {
      window.clearTimeout(timer);
    }
    saveTimersRef.current = {};
  }

  function clearSuggestTimer() {
    if (suggestTimerRef.current !== null) {
      window.clearTimeout(suggestTimerRef.current);
      suggestTimerRef.current = null;
    }
  }

  function maybeTriggerSuggest(text: string) {
    const editor = editorRef.current;
    if (!editor?.hasTextFocus()) {
      return;
    }

    if (!/[A-Za-z0-9_.]$/.test(text) || !isSuggestTokenContext(editor)) {
      clearSuggestTimer();
      editor.trigger("nsharp-auto-suggest", "hideSuggestWidget", {});
      return;
    }

    clearSuggestTimer();
    suggestTimerRef.current = window.setTimeout(() => {
      suggestTimerRef.current = null;
      if (editor.hasTextFocus()) {
        editor.trigger("nsharp-auto-suggest", "editor.action.triggerSuggest", {});
      }
    }, 80);
  }

  function isSuggestTokenContext(editor: monaco.editor.IStandaloneCodeEditor) {
    const model = editor.getModel();
    const position = editor.getPosition();
    if (!model || !position) return false;

    const line = model.getLineContent(position.lineNumber);
    const offset = Math.max(position.column - 2, 0);
    if (isInsideLineStringOrComment(line.slice(0, position.column - 1))) {
      return false;
    }

    const tokens = monaco.editor.tokenize(line, "nsharp")[0] ?? [];
    const token = tokens.find((candidate, index) => {
      const next = tokens[index + 1];
      return candidate.offset <= offset && (!next || next.offset > offset);
    });

    const tokenType = token?.type ?? "";
    return !tokenType.includes("string") && !tokenType.includes("comment");
  }

  function isInsideLineStringOrComment(textBeforeCursor: string) {
    let inString = false;
    let escaping = false;

    for (let index = 0; index < textBeforeCursor.length; index += 1) {
      const current = textBeforeCursor[index];
      const next = textBeforeCursor[index + 1];

      if (escaping) {
        escaping = false;
        continue;
      }

      if (inString) {
        if (current === "\\") {
          escaping = true;
        } else if (current === "\"") {
          inString = false;
        }
        continue;
      }

      if (current === "/" && next === "/") {
        return true;
      }

      if (current === "\"") {
        inString = true;
      }
    }

    return inString;
  }

  async function saveAllDirty() {
    const saveTasks: Promise<void>[] = [];
    for (const [fileName, model] of modelsRef.current) {
      const timer = saveTimersRef.current[fileName];
      if (timer !== undefined) {
        window.clearTimeout(timer);
        delete saveTimersRef.current[fileName];
      }
      saveTasks.push(saveLessonFile(fileName, model.getValue()));
    }
    await Promise.all(saveTasks);
  }

  async function saveLessonFile(fileName: string, code: string) {
    const currentLessonId = lessonIdRef.current;
    const token = sessionTokenRef.current;
    if (!currentLessonId || !token || loadedLessonIdRef.current !== currentLessonId) {
      return;
    }

    if (savedFilesRef.current.lessonId === currentLessonId &&
        savedFilesRef.current.files[fileName] === code) {
      return;
    }

    const response = await fetch(`/api/lessons/${currentLessonId}/code`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-nsharp-tutorial-token": token
      },
      body: JSON.stringify({ code, file: fileName })
    });

    if (!response.ok) {
      const message = await response.text();
      setPanelTab("output");
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

    savedFilesRef.current = {
      lessonId: currentLessonId,
      files: {
        ...savedFilesRef.current.files,
        [fileName]: code
      }
    };
  }

  async function postLessonAction(path: string, body: object, showOutput: boolean) {
    const currentLessonId = lessonIdRef.current;
    const token = sessionTokenRef.current;
    if (!currentLessonId || !token) {
      return null;
    }

    const response = await fetch(`/api/lessons/${currentLessonId}/${path}`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-nsharp-tutorial-token": token
      },
      body: JSON.stringify(body)
    });

    const payload = await response.json();
    const result: ToolResult = response.ok
      ? payload as ToolResult
      : {
          ok: false,
          command: path,
          exitCode: response.status,
          timedOut: false,
          durationMs: 0,
          stdout: "",
          stderr: payload?.error ?? `Request failed with HTTP ${response.status}`
        };

    if (showOutput) {
      setPanelTab("output");
      setToolResult(result);
    }

    return result;
  }

  async function runTool(path: string) {
    const editor = editorRef.current;
    const model = editor?.getModel();
    if (!editor || !model) return;

    setBusy(true);
    try {
      await saveAllDirty();
      const position = editor.getPosition() ?? new monaco.Position(1, 1);
      const fileName = modelFileName(model);
      const result = await postLessonAction(path, {
        code: model.getValue(),
        file: fileName,
        line: position.lineNumber,
        column: Math.max(position.column - 1, 0)
      }, true);

      if (!result) return;

      if (path === "format" && result.code !== undefined) {
        applyFormattedCode(model, fileName, result.code);
      }

      if (path === "diagnostics") {
        applyBackendDiagnostics(model, result);
        setPanelTab("problems");
      }
    } finally {
      setBusy(false);
    }
  }

  async function askForCompletions() {
    await runTool("completions");
    const editor = editorRef.current;
    editor?.focus();
    window.setTimeout(() => {
      editor?.trigger("toolbar", "editor.action.triggerSuggest", {});
    }, 0);
  }

  async function askForHover() {
    await runTool("hover");
    const editor = editorRef.current;
    editor?.focus();
    window.setTimeout(() => {
      void editor?.getAction("editor.action.showHover")?.run();
    }, 0);
  }

  function applyFormattedCode(model: monaco.editor.ITextModel, fileName: string, code: string) {
    if (model.getValue() !== code) {
      model.setValue(code);
    }

    savedFilesRef.current = {
      lessonId: lessonIdRef.current,
      files: {
        ...savedFilesRef.current.files,
        [fileName]: code
      }
    };
  }

  async function requestBackendCompletions(model: monaco.editor.ITextModel, position: monaco.Position) {
    const result = await postLessonAction("completions", {
      code: model.getValue(),
      file: modelFileName(model),
      line: position.lineNumber,
      column: Math.max(position.column - 1, 0)
    }, false);

    if (!result?.stdout) return [];

    const parsed = parseJson(result.stdout) as { completions?: Record<string, CompletionItem[]> } | null;
    const groups = parsed?.completions ? Object.values(parsed.completions) : [];
    const word = model.getWordUntilPosition(position);
    const range = new monaco.Range(position.lineNumber, word.startColumn, position.lineNumber, word.endColumn);

    return groups.flatMap(items => items).map(item => ({
      label: item.name,
      kind: backendCompletionKind(item.kind),
      detail: [item.parameters, item.type].filter(Boolean).join(" "),
      documentation: item.documentation,
      insertText: item.name,
      range
    } satisfies monaco.languages.CompletionItem));
  }

  async function requestBackendHover(model: monaco.editor.ITextModel, position: monaco.Position) {
    const result = await postLessonAction("hover", {
      code: model.getValue(),
      file: modelFileName(model),
      line: position.lineNumber,
      column: Math.max(position.column - 1, 0)
    }, false);

    if (!result?.stdout) return null;

    const parsed = parseJson(result.stdout) as {
      ok?: boolean;
      result?: { signature?: string; documentation?: string; kind?: string; definedIn?: string };
    } | null;

    if (!parsed?.ok || !parsed.result) return null;

    const lines = [
      parsed.result.signature ? `\`\`\`nsharp\n${parsed.result.signature}\n\`\`\`` : "",
      parsed.result.kind ? `_${parsed.result.kind}_` : "",
      parsed.result.documentation ?? "",
      parsed.result.definedIn ? `Defined in ${parsed.result.definedIn}` : ""
    ].filter(Boolean);

    return {
      contents: [{ value: lines.join("\n\n") }]
    } satisfies monaco.languages.Hover;
  }

  async function requestBackendFormatting(model: monaco.editor.ITextModel) {
    const result = await postLessonAction("format", {
      code: model.getValue(),
      file: modelFileName(model)
    }, false);

    if (!result?.code || result.code === model.getValue()) return [];

    return [{
      range: fullModelRange(model),
      text: result.code
    } satisfies monaco.languages.TextEdit];
  }

  function scheduleBackendDiagnostics(fileName: string, code: string) {
    const existingTimer = saveTimersRef.current[`diagnostics:${fileName}`];
    if (existingTimer !== undefined) {
      window.clearTimeout(existingTimer);
    }

    saveTimersRef.current[`diagnostics:${fileName}`] = window.setTimeout(() => {
      delete saveTimersRef.current[`diagnostics:${fileName}`];
      const model = modelsRef.current.get(fileName);
      if (model) {
        void refreshDiagnosticsFromBackend(model, code);
      }
    }, 650);
  }

  async function refreshAllDiagnosticsFromBackend() {
    for (const model of modelsRef.current.values()) {
      await refreshDiagnosticsFromBackend(model, model.getValue());
    }
  }

  async function refreshDiagnosticsFromBackend(model: monaco.editor.ITextModel, code: string) {
    const result = await postLessonAction("diagnostics", {
      code,
      file: modelFileName(model)
    }, false);
    if (result) {
      applyBackendDiagnostics(model, result);
    }
  }

  function applyBackendDiagnostics(model: monaco.editor.ITextModel, result: ToolResult) {
    const parsed = parseJson(result.stdout) as { results?: QueryDiagnostic[] } | null;
    const markers = (parsed?.results ?? [])
      .filter(diagnostic => sameFile(diagnostic.file, modelFileName(model)))
      .map(queryDiagnosticToMarker);
    setMarkersForUri(model.uri.toString(), HTTP_OWNER, markers, LSP_OWNER);
  }

  function setLspDiagnostics(uri: string, diagnostics: LspDiagnostic[]) {
    const markers = diagnostics.map(lspDiagnosticToMarker);
    setMarkersForUri(uri, LSP_OWNER, markers, HTTP_OWNER);
  }

  function setMarkersForUri(
    uri: string,
    owner: string,
    markers: monaco.editor.IMarkerData[],
    clearOwner?: string
  ) {
    const model = monaco.editor.getModel(monaco.Uri.parse(uri));
    if (model) {
      monaco.editor.setModelMarkers(model, owner, markers);
      if (clearOwner) {
        monaco.editor.setModelMarkers(model, clearOwner, []);
      }
    }

    problemsByUriRef.current[uri] = markers.map(marker => ({
      uri,
      file: model ? modelFileName(model) : displayFileName(uri),
      line: marker.startLineNumber,
      column: marker.startColumn,
      severity: markerSeverityLabel(marker.severity),
      message: marker.message,
      code: marker.code ? String(marker.code) : undefined
    }));

    const nextProblems = Object.values(problemsByUriRef.current).flat()
      .sort((left, right) =>
        left.file.localeCompare(right.file) ||
        left.line - right.line ||
        left.column - right.column);
    setProblemItems(nextProblems);
  }

  function modelFileName(model: monaco.editor.ITextModel) {
    return modelFileNamesRef.current.get(model.uri.toString()) ?? displayFileName(model.uri.toString());
  }

  if (loadError) {
    return (
      <div className="app">
        <main className="empty error-state">{loadError}</main>
      </div>
    );
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
          <span className={`status-dot ${lspStatus}`} aria-hidden="true" />
          <span>{catalog.workspaceRoot}</span>
          <span className="lsp-status">{lspStatusLabel(lspStatus)}</span>
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
            <span className="tool-status">{busy ? "Running nlc..." : activeFile?.path ?? ""}</span>
          </div>
          <div className="file-tabs" role="tablist" aria-label="Open tutorial files">
            {files.map(file => (
              <button
                key={file.name}
                type="button"
                role="tab"
                aria-selected={file.name === activeFileName}
                className={`file-tab ${file.name === activeFileName ? "active" : ""}`}
                onClick={() => changeActiveFile(file.name)}
              >
                {file.name}
              </button>
            ))}
          </div>
          <div className="editor-wrap">
            <div ref={editorHostRef} className="monaco-host" />
          </div>
          <section className="panel-area">
            <div className="panel-tabs">
              <button
                type="button"
                className={panelTab === "problems" ? "active" : ""}
                onClick={() => setPanelTab("problems")}
              >
                Problems ({problemItems.length})
              </button>
              <button
                type="button"
                className={panelTab === "output" ? "active" : ""}
                onClick={() => setPanelTab("output")}
              >
                Output
              </button>
            </div>
            {panelTab === "problems"
              ? <ProblemsList problems={problemItems} onSelect={openProblem} />
              : <ToolOutput result={toolResult} />}
          </section>
        </section>
      </main>
    </div>
  );

  function openProblem(problem: ProblemItem) {
    const model = monaco.editor.getModel(monaco.Uri.parse(problem.uri));
    if (!model || !editorRef.current) return;

    changeActiveFile(modelFileName(model));
    editorRef.current.setPosition({ lineNumber: problem.line, column: problem.column });
    editorRef.current.revealPositionInCenter({ lineNumber: problem.line, column: problem.column });
    editorRef.current.focus();
  }
}

function ProblemsList(props: { problems: ProblemItem[]; onSelect(problem: ProblemItem): void }) {
  if (props.problems.length === 0) {
    return <div className="problems-empty">No problems.</div>;
  }

  return (
    <div className="problems-list">
      {props.problems.map((problem, index) => (
        <button
          type="button"
          className={`problem-item ${problem.severity}`}
          key={`${problem.uri}-${problem.line}-${problem.column}-${index}`}
          onClick={() => props.onSelect(problem)}
        >
          <span className="problem-code">{problem.code ?? problem.severity}</span>
          <span className="problem-message">{problem.message}</span>
          <span className="problem-location">{problem.file}:{problem.line}:{problem.column}</span>
        </button>
      ))}
    </div>
  );
}

function ToolOutput(props: { result: ToolResult | null }) {
  if (!props.result) {
    return (
      <div className="output">
        <div className="output-header"><strong>Output</strong><span>Run a tool to see `nlc` output.</span></div>
        <pre className="output-body empty">No command has run yet.</pre>
      </div>
    );
  }

  const result = props.result;
  const text = [result.stdout, result.stderr].filter(Boolean).join("\n");
  return (
    <div className="output">
      <div className="output-header">
        <strong className={result.ok ? "ok" : "bad"}>{result.ok ? "ok" : "attention"}</strong>
        <span>{result.command} · exit {result.exitCode} · {result.durationMs}ms</span>
      </div>
      <pre className="output-body">{text || "(no output)"}</pre>
    </div>
  );
}

function registerNSharpLanguage() {
  const existing = monaco.languages.getLanguages().some(language => language.id === "nsharp");
  if (!existing) {
    monaco.languages.register({
      id: "nsharp",
      aliases: ["N#", "nsharp"],
      extensions: [".nl", ".nsharp"]
    });
  }

  monaco.languages.setLanguageConfiguration("nsharp", {
    comments: {
      lineComment: "//",
      blockComment: ["/*", "*/"]
    },
    brackets: [
      ["{", "}"],
      ["[", "]"],
      ["(", ")"]
    ],
    autoClosingPairs: [
      { open: "{", close: "}" },
      { open: "[", close: "]" },
      { open: "(", close: ")" },
      { open: "\"", close: "\"", notIn: ["string", "comment"] },
      { open: "'", close: "'", notIn: ["string", "comment"] }
    ],
    surroundingPairs: [
      { open: "{", close: "}" },
      { open: "[", close: "]" },
      { open: "(", close: ")" },
      { open: "\"", close: "\"" },
      { open: "'", close: "'" }
    ],
    indentationRules: {
      increaseIndentPattern: /^((?!\/\/).)*(\{|\[|\()\s*$/,
      decreaseIndentPattern: /^\s*(\}|\]|\))/
    },
    onEnterRules: [
      {
        beforeText: /^.*\{\s*$/,
        afterText: /^\s*\}/,
        action: { indentAction: monaco.languages.IndentAction.IndentOutdent }
      },
      {
        beforeText: /^.*(\{|\[|\()\s*$/,
        action: { indentAction: monaco.languages.IndentAction.Indent }
      }
    ]
  });

  monaco.languages.setMonarchTokensProvider("nsharp", {
    defaultToken: "",
    tokenPostfix: ".nsharp",
    keywords: N_SHARP_KEYWORDS,
    builtins: N_SHARP_BUILTINS,
    tokenizer: {
      root: [
        [/\/\/.*$/, "comment"],
        [/\/\*/, "comment", "@comment"],
        [/"([^"\\]|\\.)*$/, "string.invalid"],
        [/"""/, "string", "@rawString"],
        [/[$]"/, "string", "@string"],
        [/"/, "string", "@string"],
        [/'([^'\\]|\\.)'/, "string"],
        [/[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?/, "number"],
        [/[A-Z][A-Za-z0-9_]*/, "type.identifier"],
        [/[a-z_][A-Za-z0-9_]*/, {
          cases: {
            "@keywords": "keyword",
            "@builtins": "type.builtin",
            "@default": "identifier"
          }
        }],
        [/[{}()[\]]/, "@brackets"],
        [/[+\-*\/%=!<>|&?:.,;]/, "operator"]
      ],
      comment: [
        [/[^/*]+/, "comment"],
        [/\*\//, "comment", "@pop"],
        [/[/*]/, "comment"]
      ],
      string: [
        [/[^\\"]+/, "string"],
        [/\\./, "string.escape"],
        [/"/, "string", "@pop"]
      ],
      rawString: [
        [/[^"]+/, "string"],
        [/"""/, "string", "@pop"],
        [/"/, "string"]
      ]
    }
  });

  monaco.editor.defineTheme("nsharp-tutorial", {
    base: "vs-dark",
    inherit: true,
    rules: [
      { token: "keyword", foreground: "7dcfff", fontStyle: "bold" },
      { token: "type.identifier", foreground: "8bd49c" },
      { token: "type.builtin", foreground: "f3cc71" },
      { token: "string", foreground: "e6c384" },
      { token: "number", foreground: "f3a683" },
      { token: "comment", foreground: "87958f", fontStyle: "italic" },
      { token: "operator", foreground: "c5d1cc" }
    ],
    colors: {
      "editor.background": "#111816",
      "editor.foreground": "#e8f0ec",
      "editorLineNumber.foreground": "#65736f",
      "editorLineNumber.activeForeground": "#c8d5d0",
      "editorCursor.foreground": "#f2f7f4",
      "editor.selectionBackground": "#2b5a55",
      "editor.lineHighlightBackground": "#18221f",
      "editorIndentGuide.background1": "#25312d",
      "editorIndentGuide.activeBackground1": "#52635d",
      "editorSuggestWidget.background": "#17201d",
      "editorSuggestWidget.border": "#3a4742",
      "editorHoverWidget.background": "#17201d",
      "editorHoverWidget.border": "#3a4742"
    }
  });
}

function registerNSharpProviders(args: {
  getLspClient(): TutorialLspClient | null;
  getFileNameForModel(model: monaco.editor.ITextModel): string;
  requestBackendCompletions(model: monaco.editor.ITextModel, position: monaco.Position): Promise<monaco.languages.CompletionItem[]>;
  requestBackendHover(model: monaco.editor.ITextModel, position: monaco.Position): Promise<monaco.languages.Hover | null>;
  requestBackendFormatting(model: monaco.editor.ITextModel): Promise<monaco.languages.TextEdit[]>;
}) {
  return [
    monaco.languages.registerCompletionItemProvider("nsharp", {
      triggerCharacters: [".", ":"],
      provideCompletionItems: async (model, position) => {
        let suggestions: monaco.languages.CompletionItem[] = [];
        const lspClient = args.getLspClient();
        if (lspClient?.ready) {
          try {
            const items = await lspClient.completion(model, position);
            suggestions = items.map(item => lspCompletionToMonaco(item, model, position));
          } catch (error) {
            console.warn(error);
          }
        }

        if (suggestions.length === 0) {
          suggestions = await args.requestBackendCompletions(model, position);
        }

        return { suggestions: suggestions.length > 0 ? suggestions : localCompletionItems(model, position) };
      }
    }),
    monaco.languages.registerHoverProvider("nsharp", {
      provideHover: async (model, position) => {
        const lspClient = args.getLspClient();
        if (lspClient?.ready) {
          try {
            const hover = await lspClient.hover(model, position);
            const monacoHover = lspHoverToMonaco(hover);
            if (monacoHover) {
              return monacoHover;
            }
          } catch (error) {
            console.warn(error);
          }
        }

        return await args.requestBackendHover(model, position);
      }
    }),
    monaco.languages.registerDocumentFormattingEditProvider("nsharp", {
      provideDocumentFormattingEdits: async (model, options) => {
        const lspClient = args.getLspClient();
        if (lspClient?.ready) {
          try {
            const edits = await lspClient.formatting(model, options);
            const monacoEdits = edits.map(lspTextEditToMonaco);
            if (monacoEdits.length > 0) {
              return monacoEdits;
            }
          } catch (error) {
            console.warn(error);
          }
        }

        return await args.requestBackendFormatting(model);
      }
    })
  ];
}

function localCompletionItems(
  model: monaco.editor.ITextModel,
  position: monaco.Position
): monaco.languages.CompletionItem[] {
  const word = model.getWordUntilPosition(position);
  const range = new monaco.Range(position.lineNumber, word.startColumn, position.lineNumber, word.endColumn);
  const seen = new Set<string>();
  const items: monaco.languages.CompletionItem[] = [];

  for (const keyword of N_SHARP_KEYWORDS) {
    if (seen.has(keyword)) continue;
    seen.add(keyword);
    items.push({
      label: keyword,
      kind: monaco.languages.CompletionItemKind.Keyword,
      insertText: keyword,
      sortText: `0_${keyword}`,
      range
    });
  }

  for (const builtin of N_SHARP_BUILTINS) {
    if (seen.has(builtin)) continue;
    seen.add(builtin);
    items.push({
      label: builtin,
      kind: monaco.languages.CompletionItemKind.Function,
      insertText: builtin,
      sortText: `1_${builtin}`,
      range
    });
  }

  for (const match of model.getValue().matchAll(/\b[A-Za-z_][A-Za-z0-9_]*\b/g)) {
    const label = match[0];
    if (seen.has(label) || N_SHARP_KEYWORDS.includes(label) || N_SHARP_BUILTINS.includes(label)) {
      continue;
    }

    seen.add(label);
    items.push({
      label,
      kind: /^[A-Z]/.test(label)
        ? monaco.languages.CompletionItemKind.Class
        : monaco.languages.CompletionItemKind.Variable,
      insertText: label,
      sortText: `2_${label}`,
      range
    });
  }

  return items;
}

function lspCompletionToMonaco(
  item: LspCompletionItem,
  model: monaco.editor.ITextModel,
  position: monaco.Position
): monaco.languages.CompletionItem {
  const word = model.getWordUntilPosition(position);
  const fallbackRange = new monaco.Range(position.lineNumber, word.startColumn, position.lineNumber, word.endColumn);
  const lspRange = item.textEdit?.range ? lspRangeToMonaco(item.textEdit.range) : undefined;
  return {
    label: item.label,
    kind: lspCompletionKind(item.kind),
    detail: item.detail,
    documentation: markdownString(item.documentation),
    insertText: item.textEdit?.newText ?? item.insertText ?? item.label,
    insertTextRules: item.insertTextFormat === 2
      ? monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet
      : undefined,
    filterText: item.filterText,
    sortText: item.sortText,
    range: lspRange ?? fallbackRange
  };
}

function lspHoverToMonaco(hover: LspHover | null): monaco.languages.Hover | null {
  const contents = hoverContents(hover?.contents);
  if (contents.length === 0) return null;

  return {
    contents,
    range: hover?.range ? lspRangeToMonaco(hover.range) : undefined
  };
}

function lspTextEditToMonaco(edit: LspTextEdit): monaco.languages.TextEdit {
  return {
    range: lspRangeToMonaco(edit.range),
    text: edit.newText
  };
}

function toLspPosition(position: monaco.Position): LspPosition {
  return {
    line: position.lineNumber - 1,
    character: Math.max(position.column - 1, 0)
  };
}

function lspRangeToMonaco(range: LspRange) {
  return new monaco.Range(
    range.start.line + 1,
    range.start.character + 1,
    range.end.line + 1,
    range.end.character + 1
  );
}

function lspDiagnosticToMarker(diagnostic: LspDiagnostic): monaco.editor.IMarkerData {
  return {
    severity: lspSeverity(diagnostic.severity),
    message: diagnostic.message,
    code: diagnostic.code === undefined ? undefined : String(diagnostic.code),
    startLineNumber: diagnostic.range.start.line + 1,
    startColumn: diagnostic.range.start.character + 1,
    endLineNumber: diagnostic.range.end.line + 1,
    endColumn: Math.max(diagnostic.range.end.character + 1, diagnostic.range.start.character + 2)
  };
}

function queryDiagnosticToMarker(diagnostic: QueryDiagnostic): monaco.editor.IMarkerData {
  const line = Math.max(diagnostic.line ?? 1, 1);
  const column = Math.max(diagnostic.column ?? 1, 1);
  const length = Math.max(diagnostic.length ?? 1, 1);
  const detail = [
    diagnostic.message ?? "N# diagnostic",
    diagnostic.explanation,
    diagnostic.hint,
    diagnostic.suggestion
  ].filter(Boolean).join("\n\n");

  return {
    severity: querySeverity(diagnostic.severity),
    message: detail,
    code: diagnostic.code,
    startLineNumber: line,
    startColumn: column,
    endLineNumber: line,
    endColumn: column + length
  };
}

function backendCompletionKind(kind: string) {
  switch (kind.toLowerCase()) {
    case "function":
    case "method":
      return monaco.languages.CompletionItemKind.Function;
    case "property":
      return monaco.languages.CompletionItemKind.Property;
    case "field":
      return monaco.languages.CompletionItemKind.Field;
    case "class":
      return monaco.languages.CompletionItemKind.Class;
    case "record":
    case "struct":
      return monaco.languages.CompletionItemKind.Struct;
    case "interface":
    case "duck":
      return monaco.languages.CompletionItemKind.Interface;
    case "keyword":
      return monaco.languages.CompletionItemKind.Keyword;
    case "variable":
      return monaco.languages.CompletionItemKind.Variable;
    default:
      return monaco.languages.CompletionItemKind.Text;
  }
}

function lspCompletionKind(kind?: number) {
  switch (kind) {
    case 2: return monaco.languages.CompletionItemKind.Method;
    case 3: return monaco.languages.CompletionItemKind.Function;
    case 4: return monaco.languages.CompletionItemKind.Constructor;
    case 5: return monaco.languages.CompletionItemKind.Field;
    case 6: return monaco.languages.CompletionItemKind.Variable;
    case 7: return monaco.languages.CompletionItemKind.Class;
    case 8: return monaco.languages.CompletionItemKind.Interface;
    case 9: return monaco.languages.CompletionItemKind.Module;
    case 10: return monaco.languages.CompletionItemKind.Property;
    case 12: return monaco.languages.CompletionItemKind.Value;
    case 13: return monaco.languages.CompletionItemKind.Enum;
    case 14: return monaco.languages.CompletionItemKind.Keyword;
    case 15: return monaco.languages.CompletionItemKind.Snippet;
    case 20: return monaco.languages.CompletionItemKind.EnumMember;
    case 21: return monaco.languages.CompletionItemKind.Constant;
    case 22: return monaco.languages.CompletionItemKind.Struct;
    case 24: return monaco.languages.CompletionItemKind.Operator;
    default: return monaco.languages.CompletionItemKind.Text;
  }
}

function lspSeverity(severity?: number) {
  switch (severity) {
    case 1: return monaco.MarkerSeverity.Error;
    case 2: return monaco.MarkerSeverity.Warning;
    case 3: return monaco.MarkerSeverity.Info;
    case 4: return monaco.MarkerSeverity.Hint;
    default: return monaco.MarkerSeverity.Error;
  }
}

function querySeverity(severity?: string) {
  switch (severity) {
    case "warning": return monaco.MarkerSeverity.Warning;
    case "info": return monaco.MarkerSeverity.Info;
    case "hint": return monaco.MarkerSeverity.Hint;
    default: return monaco.MarkerSeverity.Error;
  }
}

function markerSeverityLabel(severity: monaco.MarkerSeverity) {
  switch (severity) {
    case monaco.MarkerSeverity.Error: return "error";
    case monaco.MarkerSeverity.Warning: return "warning";
    case monaco.MarkerSeverity.Info: return "info";
    case monaco.MarkerSeverity.Hint: return "hint";
    default: return "info";
  }
}

function markdownString(value: LspCompletionItem["documentation"]) {
  if (!value) return undefined;
  if (typeof value === "string") return value;
  return value.value ?? "";
}

function hoverContents(contents: LspHover["contents"]) {
  if (!contents) return [];
  const values = Array.isArray(contents) ? contents : [contents];
  return values
    .map(value => typeof value === "string" ? value : value.value ?? "")
    .filter(Boolean)
    .map(value => ({ value }));
}

function fullModelRange(model: monaco.editor.ITextModel) {
  const lastLine = model.getLineCount();
  return new monaco.Range(1, 1, lastLine, model.getLineMaxColumn(lastLine));
}

function parseJson(text: string) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function sameFile(left?: string, right?: string) {
  if (!left || !right) return true;
  return displayFileName(left) === displayFileName(right);
}

function displayFileName(uriOrPath: string) {
  const normalized = uriOrPath.replace(/\\/g, "/");
  return normalized.slice(normalized.lastIndexOf("/") + 1);
}

function lspStatusLabel(status: LspStatus) {
  switch (status) {
    case "ready": return "LSP ready";
    case "connecting": return "LSP starting";
    case "error": return "LSP unavailable";
    case "disconnected": return "LSP disconnected";
    default: return "LSP offline";
  }
}

function lspWebSocketUrl(token: string) {
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  return `${protocol}//${window.location.host}/lsp?token=${encodeURIComponent(token)}`;
}

createRoot(document.getElementById("root")!).render(<App />);
