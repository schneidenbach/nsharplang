import React, {Suspense, useCallback, useEffect, useMemo, useRef, useState} from 'react';
import BrowserOnly from '@docusaurus/BrowserOnly';
import Layout from '@theme/Layout';
import useBaseUrl from '@docusaurus/useBaseUrl';
import {
  AlertTriangle,
  ArrowLeft,
  ArrowRight,
  CheckCircle2,
  Clipboard,
  FileCode2,
  Play,
  RotateCcw,
  Share2,
  Wand2,
} from 'lucide-react';
import {validateTutorialStep} from '../lib/tutorialValidation.mjs';

const MonacoEditor = React.lazy(() => import('@monaco-editor/react'));
const owner = 'nsharp-playground';
const fallbackExample = {
  id: '01-hello-world',
  title: 'Hello World',
  summary: 'Start with a tiny program, a tested function, and print.',
  minutes: 2,
  goal: 'Change the greeting and use diagnostics to keep the program clean.',
  concepts: ['entry point', 'print', 'string interpolation', 'tests'],
  cSharpContrast: 'N# keeps top-level ceremony low: func main() plus print is enough.',
  expectedOutput: 'Hello, N#!\n',
  code: `package Tutorial

func Greeting(name: string): string {
    return $"Hello, {name}!"
}

func main() {
    print Greeting("N#")
}
`,
  testsCode: `package Tutorial

test "greets by name" {
    assert Greeting("N#") == "Hello, N#!"
}
`,
};

function readField(value, camelName, pascalName) {
  return value?.[camelName] ?? value?.[pascalName];
}

function normalizeExample(example) {
  return {
    id: readField(example, 'id', 'Id'),
    title: readField(example, 'title', 'Title'),
    summary: readField(example, 'summary', 'Summary'),
    minutes: readField(example, 'minutes', 'Minutes') ?? 1,
    goal: readField(example, 'goal', 'Goal') ?? '',
    concepts: readField(example, 'concepts', 'Concepts') ?? [],
    cSharpContrast: readField(example, 'cSharpContrast', 'CSharpContrast') ?? '',
    code: readField(example, 'code', 'Code') ?? '',
    testsCode: readField(example, 'testsCode', 'TestsCode'),
    expectedOutput: readField(example, 'expectedOutput', 'ExpectedOutput'),
  };
}

function normalizeTutorialValidation(validation) {
  if (!validation) {
    return null;
  }

  return {
    type: readField(validation, 'type', 'Type') ?? 'output',
    expectedOutput: readField(validation, 'expectedOutput', 'ExpectedOutput'),
    requiredText: readField(validation, 'requiredText', 'RequiredText'),
    successMessage: readField(validation, 'successMessage', 'SuccessMessage') ?? 'Exercise complete.',
  };
}

function normalizeTutorialStep(step) {
  return {
    id: readField(step, 'id', 'Id'),
    title: readField(step, 'title', 'Title'),
    kind: readField(step, 'kind', 'Kind') ?? 'info',
    narration: readField(step, 'narration', 'Narration') ?? '',
    exampleId: readField(step, 'exampleId', 'ExampleId'),
    validation: normalizeTutorialValidation(readField(step, 'validation', 'Validation')),
  };
}

function normalizeSummary(summary) {
  return {
    errors: readField(summary, 'errors', 'Errors') ?? 0,
    warnings: readField(summary, 'warnings', 'Warnings') ?? 0,
    infos: readField(summary, 'infos', 'Infos') ?? 0,
  };
}

function normalizeDiagnostic(diagnostic) {
  return {
    code: readField(diagnostic, 'code', 'Code'),
    severity: readField(diagnostic, 'severity', 'Severity') ?? 'error',
    message: readField(diagnostic, 'message', 'Message'),
    file: readField(diagnostic, 'file', 'File') ?? 'Program.nl',
    line: readField(diagnostic, 'line', 'Line') ?? 1,
    column: readField(diagnostic, 'column', 'Column') ?? 1,
    length: readField(diagnostic, 'length', 'Length') ?? 1,
    sourceSnippet: readField(diagnostic, 'sourceSnippet', 'SourceSnippet'),
    explanation: readField(diagnostic, 'explanation', 'Explanation'),
    suggestion: readField(diagnostic, 'suggestion', 'Suggestion'),
    hint: readField(diagnostic, 'hint', 'Hint'),
  };
}

function normalizeCheckResponse(response) {
  return {
    schemaVersion: readField(response, 'schemaVersion', 'SchemaVersion'),
    ok: readField(response, 'ok', 'Ok') ?? false,
    file: readField(response, 'file', 'File') ?? 'Program.nl',
    diagnostics: (readField(response, 'diagnostics', 'Diagnostics') ?? []).map(normalizeDiagnostic),
    summary: normalizeSummary(readField(response, 'summary', 'Summary')),
  };
}

function normalizeFormatResponse(response) {
  return {
    ...normalizeCheckResponse(response),
    formattedCode: readField(response, 'formattedCode', 'FormattedCode'),
    warnings: readField(response, 'warnings', 'Warnings') ?? [],
  };
}

function normalizeRunResponse(response) {
  return {
    ...normalizeCheckResponse(response),
    exitCode: readField(response, 'exitCode', 'ExitCode') ?? 1,
    stdout: readField(response, 'stdout', 'Stdout') ?? '',
    stderr: readField(response, 'stderr', 'Stderr'),
    unsupportedReason: readField(response, 'unsupportedReason', 'UnsupportedReason'),
  };
}

function normalizeCompletionResponse(response) {
  return {
    ...normalizeCheckResponse(response),
    context: readField(response, 'context', 'Context') ?? 'Unknown',
    receiver: readField(response, 'receiver', 'Receiver'),
    receiverType: readField(response, 'receiverType', 'ReceiverType'),
    items: readField(response, 'items', 'Items') ?? [],
  };
}

function normalizeHoverResponse(response) {
  return {
    ...normalizeCheckResponse(response),
    hover: readField(response, 'hover', 'Hover'),
  };
}

function normalizeVersion(response) {
  return {
    compiler: readField(response, 'compiler', 'Compiler'),
    wasmHost: readField(response, 'wasmHost', 'WasmHost'),
  };
}

function filesForExample(example) {
  const files = [{name: 'Program.nl', code: example.code ?? ''}];
  if (example.testsCode) {
    files.push({name: 'Program.tests.nl', code: example.testsCode});
  }
  return files;
}

function encodeState(value) {
  const bytes = new TextEncoder().encode(JSON.stringify(value));
  let binary = '';
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }

  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function decodeState(value) {
  try {
    const padded = value.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(value.length / 4) * 4, '=');
    const binary = atob(padded);
    const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return null;
  }
}

function readSharedFiles() {
  if (typeof window === 'undefined') {
    return null;
  }

  const hash = new URLSearchParams(window.location.hash.replace(/^#/, ''));
  const encoded = hash.get('files') ?? hash.get('code');
  const decoded = encoded ? decodeState(encoded) : null;
  if (Array.isArray(decoded)) {
    return decoded
      .filter((file) => file && typeof file.code === 'string')
      .map((file) => ({name: file.name ?? 'Program.nl', code: file.code}));
  }

  if (typeof decoded === 'string') {
    return [{name: 'Program.nl', code: decoded}];
  }

  return null;
}

function clearSharedHash() {
  if (typeof window === 'undefined' || (!window.location.hash.includes('files=') && !window.location.hash.includes('code='))) {
    return;
  }

  const url = new URL(window.location.href);
  url.hash = '';
  window.history.replaceState(null, '', url);
}

function loadPlaygroundScript(src) {
  if (globalThis.loadNSharpPlayground) {
    return Promise.resolve();
  }

  const existingScript = document.querySelector('script[data-nsharp-playground-loader="true"]');
  if (existingScript) {
    return new Promise((resolve, reject) => {
      existingScript.addEventListener('load', () => resolve(), {once: true});
      existingScript.addEventListener('error', () => reject(new Error('Failed to load the N# playground module.')), {once: true});
    });
  }

  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.type = 'module';
    script.src = src;
    script.dataset.nsharpPlaygroundLoader = 'true';
    script.addEventListener('load', () => resolve(), {once: true});
    script.addEventListener('error', () => reject(new Error('Failed to load the N# playground module.')), {once: true});
    document.head.appendChild(script);
  });
}

function registerNSharpLanguage(monaco) {
  if (!monaco.languages.getLanguages().some((language) => language.id === 'nsharp')) {
    monaco.languages.register({id: 'nsharp', aliases: ['N#', 'nsharp'], extensions: ['.nl', '.nsharp']});
  }

  monaco.languages.setLanguageConfiguration('nsharp', {
    comments: {lineComment: '//', blockComment: ['/*', '*/']},
    brackets: [['{', '}'], ['[', ']'], ['(', ')']],
    autoClosingPairs: [
      {open: '{', close: '}'},
      {open: '[', close: ']'},
      {open: '(', close: ')'},
      {open: '"', close: '"', notIn: ['string', 'comment']},
      {open: "'", close: "'", notIn: ['string', 'comment']},
    ],
    surroundingPairs: [
      {open: '{', close: '}'},
      {open: '[', close: ']'},
      {open: '(', close: ')'},
      {open: '"', close: '"'},
      {open: "'", close: "'"},
    ],
    indentationRules: {
      increaseIndentPattern: /^((?!\/\/).)*(\{|\[|\()\s*$/,
      decreaseIndentPattern: /^\s*(\}|\]|\))/,
    },
  });

  monaco.languages.setMonarchTokensProvider('nsharp', {
    defaultToken: '',
    tokenPostfix: '.nsharp',
    keywords: [
      'func', 'class', 'struct', 'record', 'interface', 'enum', 'union', 'duck',
      'if', 'else', 'for', 'foreach', 'while', 'return', 'break', 'continue',
      'match', 'when', 'yield', 'await', 'async', 'throw', 'try', 'catch',
      'finally', 'new', 'import', 'package', 'print', 'test', 'assert',
      'true', 'false', 'null', 'is', 'as', 'typeof', 'nameof', 'let', 'const',
      'static', 'pub', 'private', 'protected', 'internal', 'override', 'virtual',
    ],
    builtins: [
      'int', 'long', 'float', 'double', 'bool', 'string', 'void', 'object',
      'byte', 'short', 'char', 'decimal',
    ],
    tokenizer: {
      root: [
        [/\/\/.*$/, 'comment'],
        [/\/\*/, 'comment', '@comment'],
        [/"([^"\\]|\\.)*$/, 'string.invalid'],
        [/"""/, 'string', '@rawString'],
        [/[$]"/, 'string', '@string'],
        [/"/, 'string', '@string'],
        [/'([^'\\]|\\.)'/, 'string'],
        [/[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?/, 'number'],
        [/[A-Z][A-Za-z0-9_]*/, 'type.identifier'],
        [/[a-z_][A-Za-z0-9_]*/, {cases: {'@keywords': 'keyword', '@builtins': 'type.builtin', '@default': 'identifier'}}],
        [/[{}()[\]]/, '@brackets'],
        [/[+\-*\/%=!<>|&?:.,;]/, 'operator'],
      ],
      comment: [
        [/[^/*]+/, 'comment'],
        [/\*\//, 'comment', '@pop'],
        [/[/*]/, 'comment'],
      ],
      string: [
        [/[^\\"]+/, 'string'],
        [/\\./, 'string.escape'],
        [/"/, 'string', '@pop'],
      ],
      rawString: [
        [/[^"]+/, 'string'],
        [/"""/, 'string', '@pop'],
        [/"/, 'string'],
      ],
    },
  });

  monaco.editor.defineTheme('nsharp-light', {
    base: 'vs',
    inherit: true,
    rules: [
      {token: 'keyword', foreground: '155e75', fontStyle: 'bold'},
      {token: 'type.identifier', foreground: '166534'},
      {token: 'type.builtin', foreground: '7c2d12'},
      {token: 'string', foreground: '9a3412'},
      {token: 'number', foreground: '1d4ed8'},
      {token: 'comment', foreground: '6b7280', fontStyle: 'italic'},
      {token: 'operator', foreground: '374151'},
    ],
    colors: {
      'editor.background': '#fbfbfa',
      'editor.foreground': '#111827',
      'editorLineNumber.foreground': '#9ca3af',
      'editorLineNumber.activeForeground': '#374151',
      'editorCursor.foreground': '#111827',
      'editor.selectionBackground': '#c7d2fe',
      'editor.lineHighlightBackground': '#f4f4f5',
      'editorSuggestWidget.background': '#ffffff',
      'editorSuggestWidget.border': '#d4d4d4',
      'editorHoverWidget.background': '#ffffff',
      'editorHoverWidget.border': '#d4d4d4',
    },
  });
}

function completionKind(monaco, kind) {
  switch ((kind ?? '').toLowerCase()) {
    case 'keyword':
      return monaco.languages.CompletionItemKind.Keyword;
    case 'function':
      return monaco.languages.CompletionItemKind.Function;
    case 'method':
      return monaco.languages.CompletionItemKind.Method;
    case 'property':
      return monaco.languages.CompletionItemKind.Property;
    case 'field':
      return monaco.languages.CompletionItemKind.Field;
    case 'variable':
    case 'parameter':
      return monaco.languages.CompletionItemKind.Variable;
    case 'class':
    case 'record':
      return monaco.languages.CompletionItemKind.Class;
    case 'struct':
      return monaco.languages.CompletionItemKind.Struct;
    case 'interface':
      return monaco.languages.CompletionItemKind.Interface;
    case 'enum':
      return monaco.languages.CompletionItemKind.Enum;
    case 'type':
      return monaco.languages.CompletionItemKind.TypeParameter;
    default:
      return monaco.languages.CompletionItemKind.Text;
  }
}

function markerSeverity(monaco, severity) {
  switch (severity) {
    case 'warning':
      return monaco.MarkerSeverity.Warning;
    case 'info':
      return monaco.MarkerSeverity.Info;
    default:
      return monaco.MarkerSeverity.Error;
  }
}

function diagnosticMessage(diagnostic) {
  return [diagnostic.message, diagnostic.explanation, diagnostic.suggestion, diagnostic.hint]
    .filter(Boolean)
    .join('\n\n');
}

function fileNameFromModel(model) {
  const path = model.uri.path || '';
  return path.split('/').filter(Boolean).pop() ?? 'Program.nl';
}

function fullRange(monaco, model) {
  const lastLine = model.getLineCount();
  const lastColumn = model.getLineMaxColumn(lastLine);
  return new monaco.Range(1, 1, lastLine, lastColumn);
}

function installIntelliSense(monaco, contextRef) {
  if (monaco.__nsharpPlaygroundProvidersInstalled) {
    return;
  }

  monaco.__nsharpPlaygroundProvidersInstalled = true;
  monaco.languages.registerCompletionItemProvider('nsharp', {
    triggerCharacters: ['.', ':'],
    provideCompletionItems: async (model, position) => {
      const context = contextRef.current;
      if (!context?.playground) {
        return {suggestions: []};
      }

      const fileName = fileNameFromModel(model);
      const response = normalizeCompletionResponse(await context.playground.complete(
        context.filesForModel(model),
        fileName,
        position.lineNumber,
        Math.max(position.column - 1, 0),
      ));
      context.applyResult(response);

      const word = model.getWordUntilPosition(position);
      const range = new monaco.Range(position.lineNumber, word.startColumn, position.lineNumber, word.endColumn);
      return {
        suggestions: response.items.map((item) => ({
          label: readField(item, 'label', 'Label'),
          kind: completionKind(monaco, readField(item, 'kind', 'Kind')),
          detail: readField(item, 'detail', 'Detail'),
          documentation: readField(item, 'documentation', 'Documentation'),
          insertText: readField(item, 'insertText', 'InsertText') ?? readField(item, 'label', 'Label'),
          range,
        })),
      };
    },
  });

  monaco.languages.registerHoverProvider('nsharp', {
    provideHover: async (model, position) => {
      const context = contextRef.current;
      if (!context?.playground) {
        return null;
      }

      const fileName = fileNameFromModel(model);
      const response = normalizeHoverResponse(await context.playground.hover(
        context.filesForModel(model),
        fileName,
        position.lineNumber,
        Math.max(position.column - 1, 0),
      ));
      context.applyResult(response);

      if (!response.hover) {
        return null;
      }

      const signature = readField(response.hover, 'signature', 'Signature');
      const documentation = readField(response.hover, 'documentation', 'Documentation');
      const kind = readField(response.hover, 'kind', 'Kind');
      const definedIn = readField(response.hover, 'definedIn', 'DefinedIn');
      const lines = [`\`\`\`nsharp\n${signature}\n\`\`\``];
      if (documentation) {
        lines.push(documentation);
      }
      if (definedIn) {
        lines.push(`Defined in ${definedIn}`);
      } else if (kind) {
        lines.push(kind);
      }

      return {contents: lines.map((value) => ({value}))};
    },
  });

  monaco.languages.registerDocumentFormattingEditProvider('nsharp', {
    provideDocumentFormattingEdits: async (model) => {
      const context = contextRef.current;
      if (!context?.playground) {
        return [];
      }

      const fileName = fileNameFromModel(model);
      const response = normalizeFormatResponse(await context.playground.format(model.getValue(), fileName));
      context.applyResult(response);
      if (!response.ok || !response.formattedCode || response.formattedCode === model.getValue()) {
        return [];
      }

      return [{range: fullRange(monaco, model), text: response.formattedCode}];
    },
  });
}

function DiagnosticList({diagnostics, onSelect}) {
  if (!diagnostics.length) {
    return (
      <div className="playground-empty">
        <CheckCircle2 size={16} aria-hidden="true" />
        <span>No problems.</span>
      </div>
    );
  }

  return (
    <div className="playground-diagnostics">
      {diagnostics.map((diagnostic, index) => (
        <button
          className={`playground-diagnostic playground-diagnostic--${diagnostic.severity}`}
          key={`${diagnostic.code}-${diagnostic.file}-${diagnostic.line}-${diagnostic.column}-${index}`}
          type="button"
          onClick={() => onSelect(diagnostic)}>
          <span className="playground-diagnostic__code">{diagnostic.code}</span>
          <span className="playground-diagnostic__message">{diagnostic.message}</span>
          <span className="playground-diagnostic__location">{diagnostic.file}:{diagnostic.line}:{diagnostic.column}</span>
        </button>
      ))}
    </div>
  );
}

function EditorFallback({value, onChange}) {
  return (
    <textarea
      aria-label="N# source"
      className="playground-source-fallback"
      spellCheck={false}
      value={value}
      onChange={(event) => onChange(event.target.value)}
    />
  );
}

function OutputPanel({runResult, activeExample, validationState}) {
  if (!runResult) {
    return (
      <div className="playground-output">
        <div className="playground-empty">
          <Play size={16} aria-hidden="true" />
          <span>Run the active file to see stdout.</span>
        </div>
        {activeExample?.expectedOutput && (
          <div className="playground-expected-output">
            <span>Expected output</span>
            <pre>{activeExample.expectedOutput}</pre>
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="playground-output">
      <div className={`playground-run-summary ${runResult.ok ? 'playground-run-summary--ok' : 'playground-run-summary--error'}`}>
        <span>exit {runResult.exitCode}</span>
        <span>{runResult.ok ? 'completed' : 'failed'}</span>
      </div>
      {runResult.stdout ? (
        <pre className="playground-stdout">{runResult.stdout}</pre>
      ) : (
        <div className="playground-empty">
          <span>No stdout.</span>
        </div>
      )}
      {runResult.stderr && <pre className="playground-stderr">{runResult.stderr}</pre>}
      {runResult.unsupportedReason && (
        <div className="playground-note playground-note--warning">
          <AlertTriangle size={15} aria-hidden="true" />
          <span>{runResult.unsupportedReason}</span>
        </div>
      )}
      {validationState?.message && (
        <div className={`playground-validation ${validationState.complete ? 'playground-validation--ok' : 'playground-validation--pending'}`}>
          {validationState.complete ? <CheckCircle2 size={15} aria-hidden="true" /> : <AlertTriangle size={15} aria-hidden="true" />}
          <span>{validationState.message}</span>
        </div>
      )}
    </div>
  );
}

function GuidePanel({activeExample, activeTutorialStep, validationState, isTutorial}) {
  if (isTutorial && activeTutorialStep) {
    return (
      <div className="playground-lesson-notes">
        <p>{activeTutorialStep.narration}</p>
        {activeTutorialStep.validation && (
          <div className={`playground-validation ${validationState?.complete ? 'playground-validation--ok' : 'playground-validation--pending'}`}>
            {validationState?.complete ? <CheckCircle2 size={15} aria-hidden="true" /> : <AlertTriangle size={15} aria-hidden="true" />}
            <span>{validationState?.message ?? 'Run the exercise to unlock Next.'}</span>
          </div>
        )}
        {activeExample?.cSharpContrast && <p>{activeExample.cSharpContrast}</p>}
      </div>
    );
  }

  return (
    <div className="playground-lesson-notes">
      <p>{activeExample?.summary}</p>
      <p>{activeExample?.cSharpContrast}</p>
      <div className="playground-note">
        <Clipboard size={15} aria-hidden="true" />
        <span>Install nlc for full build, run, test, NuGet, and filesystem workflows.</span>
      </div>
    </div>
  );
}

export function PlaygroundWorkbench({mode = 'playground'}) {
  const isTutorial = mode === 'tutorial';
  const loaderUrl = useBaseUrl('/playground/nsharp-playground.js');
  const contextRef = useRef(null);
  const monacoRef = useRef(null);
  const editorRef = useRef(null);
  const filesRef = useRef([]);
  const activeFileRef = useRef('Program.nl');
  const playgroundRef = useRef(null);

  const [playground, setPlayground] = useState(null);
  const [examples, setExamples] = useState([fallbackExample]);
  const [tutorialSteps, setTutorialSteps] = useState([]);
  const [selectedTutorialStep, setSelectedTutorialStep] = useState(null);
  const [completedSteps, setCompletedSteps] = useState(() => new Set());
  const [selectedExample, setSelectedExample] = useState(fallbackExample.id);
  const [files, setFiles] = useState(filesForExample(fallbackExample));
  const [activeFile, setActiveFile] = useState('Program.nl');
  const [result, setResult] = useState(null);
  const [runResult, setRunResult] = useState(null);
  const [version, setVersion] = useState(null);
  const [status, setStatus] = useState('Loading compiler...');
  const [loadError, setLoadError] = useState(null);
  const [isWorking, setIsWorking] = useState(false);
  const [panel, setPanel] = useState('output');

  filesRef.current = files;
  activeFileRef.current = activeFile;
  playgroundRef.current = playground;

  const activeExample = useMemo(
    () => examples.find((example) => example.id === selectedExample) ?? examples[0],
    [examples, selectedExample],
  );
  const activeTutorialStep = useMemo(
    () => tutorialSteps.find((step) => step.id === selectedTutorialStep) ?? tutorialSteps[0],
    [tutorialSteps, selectedTutorialStep],
  );
  const activeFileModel = useMemo(
    () => files.find((file) => file.name === activeFile) ?? files[0],
    [files, activeFile],
  );
  const diagnostics = result?.diagnostics ?? [];
  const summary = result?.summary ?? {errors: 0, warnings: 0, infos: 0};
  const canWork = playground && !isWorking;
  const validationState = useMemo(() => {
    if (!isTutorial) {
      return null;
    }

    const state = validateTutorialStep(activeTutorialStep, files, runResult);
    if (!state.complete && activeTutorialStep?.validation && completedSteps.has(activeTutorialStep.id)) {
      return {complete: true, message: activeTutorialStep.validation.successMessage};
    }

    return state;
  }, [activeTutorialStep, completedSteps, files, isTutorial, runResult]);
  const tutorialIndex = activeTutorialStep
    ? tutorialSteps.findIndex((step) => step.id === activeTutorialStep.id)
    : -1;
  const canGoBack = isTutorial && tutorialIndex > 0;
  const canGoNext = isTutorial &&
    tutorialIndex >= 0 &&
    tutorialIndex < tutorialSteps.length - 1 &&
    (!activeTutorialStep?.validation || validationState?.complete);
  const statusClass = result || runResult
    ? (summary.errors === 0 && (!runResult || runResult.ok) ? 'playground-status--ok' : 'playground-status--error')
    : '';

  const applyResult = useCallback((nextResult) => {
    setResult(nextResult);
  }, []);

  const filesForModel = useCallback((model) => {
    const fileName = fileNameFromModel(model);
    return filesRef.current.map((file) => (
      file.name === fileName ? {...file, code: model.getValue()} : file
    ));
  }, []);

  contextRef.current = {
    playground,
    filesForModel,
    applyResult,
  };

  useEffect(() => {
    let cancelled = false;

    async function loadPlayground() {
      try {
        await loadPlaygroundScript(loaderUrl);
        const loaded = await globalThis.loadNSharpPlayground();
        const catalog = loaded.getCatalog();
        const catalogExamples = (readField(catalog, 'examples', 'Examples') ?? []).map(normalizeExample);
        const catalogTutorial = (readField(catalog, 'tutorial', 'Tutorial') ?? []).map(normalizeTutorialStep);
        const nextExamples = catalogExamples.length ? catalogExamples : [fallbackExample];
        const initialTutorialStep = catalogTutorial[0] ?? null;
        const tutorialExample = initialTutorialStep?.exampleId
          ? nextExamples.find((example) => example.id === initialTutorialStep.exampleId)
          : null;
        const initialExample = isTutorial ? (tutorialExample ?? nextExamples[0]) : nextExamples[0];
        const sharedFiles = isTutorial ? null : readSharedFiles();
        const initialFiles = sharedFiles?.length ? sharedFiles : filesForExample(initialExample);
        const initialActiveFile = initialFiles[0]?.name ?? 'Program.nl';

        if (cancelled) {
          return;
        }

        setPlayground(loaded);
        setExamples(nextExamples);
        setTutorialSteps(catalogTutorial);
        setSelectedTutorialStep(initialTutorialStep?.id ?? null);
        setSelectedExample(sharedFiles ? 'shared' : initialExample.id);
        setFiles(initialFiles);
        setActiveFile(initialActiveFile);
        setVersion(normalizeVersion(loaded.version()));
        setResult(normalizeCheckResponse(loaded.checkProject(initialFiles, initialActiveFile)));
        setStatus('Ready');
      } catch (error) {
        if (cancelled) {
          return;
        }

        setLoadError(error instanceof Error ? error.message : String(error));
        setStatus('Unavailable');
      }
    }

    loadPlayground();
    return () => {
      cancelled = true;
    };
  }, [isTutorial, loaderUrl]);

  useEffect(() => {
    if (!playground) {
      return;
    }

    const handle = window.setTimeout(() => {
      try {
        const checked = normalizeCheckResponse(playground.checkProject(files, activeFile));
        setResult(checked);
        setStatus(checked.ok ? 'Checked' : 'Needs attention');
      } catch (error) {
        setLoadError(error instanceof Error ? error.message : String(error));
        setStatus('Check failed');
      }
    }, 450);

    return () => window.clearTimeout(handle);
  }, [playground, files, activeFile]);

  useEffect(() => {
    const monaco = monacoRef.current;
    if (!monaco) {
      return;
    }

    for (const model of monaco.editor.getModels()) {
      const fileName = fileNameFromModel(model);
      const markers = diagnostics
        .filter((diagnostic) => diagnostic.file === fileName)
        .map((diagnostic) => ({
          severity: markerSeverity(monaco, diagnostic.severity),
          message: diagnosticMessage(diagnostic),
          code: diagnostic.code,
          startLineNumber: Math.max(diagnostic.line, 1),
          startColumn: Math.max(diagnostic.column, 1),
          endLineNumber: Math.max(diagnostic.line, 1),
          endColumn: Math.max(diagnostic.column + diagnostic.length, diagnostic.column + 1),
        }));
      monaco.editor.setModelMarkers(model, owner, markers);
    }
  }, [diagnostics, activeFile, files]);

  async function runCheck() {
    if (!playground) {
      return;
    }

    setIsWorking(true);
    try {
      const checked = normalizeCheckResponse(playground.checkProject(files, activeFile));
      setResult(checked);
      setStatus(checked.ok ? 'Checked' : 'Needs attention');
      setPanel('problems');
    } catch (error) {
      setLoadError(error instanceof Error ? error.message : String(error));
      setStatus('Check failed');
    } finally {
      setIsWorking(false);
    }
  }

  async function runProject() {
    if (!playground?.runProject) {
      return;
    }

    setIsWorking(true);
    try {
      const run = normalizeRunResponse(await playground.runProject(files, activeFile));
      setRunResult(run);
      setResult(run);
      setStatus(run.ok ? 'Ran' : 'Run failed');
      setPanel('output');

      if (isTutorial && activeTutorialStep?.validation) {
        const nextValidation = validateTutorialStep(activeTutorialStep, files, run);
        if (nextValidation.complete) {
          setCompletedSteps((current) => {
            const next = new Set(current);
            next.add(activeTutorialStep.id);
            return next;
          });
        }
      }
    } catch (error) {
      setLoadError(error instanceof Error ? error.message : String(error));
      setStatus('Run failed');
    } finally {
      setIsWorking(false);
    }
  }

  async function runFormat() {
    if (!playground || !activeFileModel) {
      return;
    }

    setIsWorking(true);
    try {
      const formatted = normalizeFormatResponse(playground.format(activeFileModel.code, activeFileModel.name));
      setResult(formatted);
      if (formatted.ok && formatted.formattedCode) {
        setFiles((current) => current.map((file) => (
          file.name === activeFileModel.name ? {...file, code: formatted.formattedCode} : file
        )));
      }
      setRunResult(null);
      setStatus(formatted.ok ? 'Formatted' : 'Format skipped');
      setPanel('problems');
    } catch (error) {
      setLoadError(error instanceof Error ? error.message : String(error));
      setStatus('Format failed');
    } finally {
      setIsWorking(false);
    }
  }

  async function shareFiles() {
    if (typeof window === 'undefined') {
      return;
    }

    const url = new URL(window.location.href);
    url.hash = `files=${encodeState(files)}`;
    window.history.replaceState(null, '', url);

    try {
      await navigator.clipboard?.writeText(url.toString());
      setStatus('Share link copied');
    } catch {
      setStatus('Share link ready');
    }
  }

  function chooseExample(example) {
    const nextFiles = filesForExample(example);
    setSelectedExample(example.id);
    setSelectedTutorialStep(null);
    setFiles(nextFiles);
    setActiveFile(nextFiles[0].name);
    setResult(null);
    setRunResult(null);
    setStatus('Example loaded');
    setPanel('output');
    clearSharedHash();
  }

  function chooseTutorialStep(step) {
    const example = examples.find((candidate) => candidate.id === step.exampleId) ?? activeExample ?? examples[0];
    const nextFiles = filesForExample(example);
    setSelectedTutorialStep(step.id);
    setSelectedExample(example.id);
    setFiles(nextFiles);
    setActiveFile(nextFiles[0].name);
    setResult(null);
    setRunResult(null);
    setStatus(step.kind === 'exercise' ? 'Exercise loaded' : 'Step loaded');
    setPanel('guide');
    clearSharedHash();
  }

  function moveTutorial(delta) {
    if (tutorialIndex < 0) {
      return;
    }

    const nextStep = tutorialSteps[tutorialIndex + delta];
    if (nextStep) {
      chooseTutorialStep(nextStep);
    }
  }

  function resetExample() {
    if (isTutorial && activeTutorialStep) {
      chooseTutorialStep(activeTutorialStep);
      return;
    }

    if (!activeExample) {
      return;
    }

    chooseExample(activeExample);
  }

  function updateActiveFile(code) {
    setFiles((current) => current.map((file) => (
      file.name === activeFile ? {...file, code: code ?? ''} : file
    )));
    setRunResult(null);
    if (activeTutorialStep?.validation) {
      setCompletedSteps((current) => {
        const next = new Set(current);
        next.delete(activeTutorialStep.id);
        return next;
      });
    }
    setStatus('Edited');
    clearSharedHash();
  }

  function beforeMount(monaco) {
    monacoRef.current = monaco;
    registerNSharpLanguage(monaco);
    installIntelliSense(monaco, contextRef);
  }

  function onMount(editor, monaco) {
    editorRef.current = editor;
    monacoRef.current = monaco;
    editor.focus();
  }

  function selectDiagnostic(diagnostic) {
    setActiveFile(diagnostic.file);
    window.setTimeout(() => {
      const editor = editorRef.current;
      if (!editor) {
        return;
      }

      editor.setPosition({lineNumber: diagnostic.line, column: diagnostic.column});
      editor.revealPositionInCenter({lineNumber: diagnostic.line, column: diagnostic.column});
      editor.focus();
    }, 0);
  }

  return (
    <Layout
      title={isTutorial ? 'Tutorial' : 'Playground'}
      description={isTutorial
        ? 'Follow the guided N# tutorial in the browser playground workbench.'
        : 'Try N# in the browser with WebAssembly compiler diagnostics, formatting, IntelliSense, run output, and syntax highlighting.'}>
      <main className="playground-page">
        <section className="playground-topbar">
          <div>
            <h1>{isTutorial ? 'N# Tutorial' : 'N# Playground'}</h1>
            <p>{isTutorial
              ? 'A guided story that uses the same browser workbench as the playground.'
              : 'Free exploration with browser diagnostics, formatting, IntelliSense, and stdout.'}</p>
          </div>
          <div className="playground-runtime">
            <span className={`playground-status ${statusClass}`}>{status}</span>
            {version && <span>compiler {version.compiler}</span>}
          </div>
        </section>

        {loadError && (
          <div className="playground-alert">
            <AlertTriangle size={16} aria-hidden="true" />
            <span>{loadError}</span>
          </div>
        )}

        <section className="playground-workbench">
          <aside className="playground-lessons" aria-label={isTutorial ? 'Tutorial steps' : 'Samples'}>
            <div className="playground-panel-title">{isTutorial ? 'Tutorial' : 'Samples'}</div>
            <div className="playground-lesson-list">
              {isTutorial ? tutorialSteps.map((step, index) => (
                <button
                  className={`playground-lesson ${activeTutorialStep?.id === step.id ? 'playground-lesson--active' : ''}`}
                  key={step.id}
                  type="button"
                  onClick={() => chooseTutorialStep(step)}>
                  <span className="playground-lesson__number">
                    {completedSteps.has(step.id) ? <CheckCircle2 size={13} aria-hidden="true" /> : index + 1}
                  </span>
                  <span>
                    <span className="playground-lesson__title">{step.title}</span>
                    <span className="playground-lesson__summary">{step.kind === 'exercise' ? 'Exercise' : 'Story'}</span>
                  </span>
                </button>
              )) : examples.map((example, index) => (
                <button
                  className={`playground-lesson ${selectedExample === example.id ? 'playground-lesson--active' : ''}`}
                  key={example.id}
                  type="button"
                  onClick={() => chooseExample(example)}>
                  <span className="playground-lesson__number">{index + 1}</span>
                  <span>
                    <span className="playground-lesson__title">{example.title}</span>
                    <span className="playground-lesson__summary">{example.summary}</span>
                  </span>
                </button>
              ))}
            </div>
          </aside>

          <section className="playground-main">
            <div className="playground-context">
              <div>
                <h2>{isTutorial ? activeTutorialStep?.title : activeExample?.title ?? 'Shared Code'}</h2>
                <p>{isTutorial
                  ? activeTutorialStep?.narration
                  : activeExample?.goal ?? 'Shared playground code.'}</p>
              </div>
              {isTutorial ? (
                <div className="playground-step-nav">
                  <button className="playground-action" disabled={!canGoBack} type="button" onClick={() => moveTutorial(-1)}>
                    <ArrowLeft size={15} aria-hidden="true" />
                    <span>Back</span>
                  </button>
                  <button className="playground-action playground-action--primary" disabled={!canGoNext} type="button" onClick={() => moveTutorial(1)}>
                    <span>Next</span>
                    <ArrowRight size={15} aria-hidden="true" />
                  </button>
                </div>
              ) : (
                <div className="playground-concepts">
                  {(activeExample?.concepts ?? []).map((concept) => (
                    <span key={concept}>{concept}</span>
                  ))}
                </div>
              )}
            </div>

            <div className="playground-editor-panel">
              <div className="playground-toolbar">
                <div className="playground-file-tabs" role="tablist" aria-label="Open files">
                  {files.map((file) => (
                    <button
                      className={`playground-file-tab ${file.name === activeFile ? 'playground-file-tab--active' : ''}`}
                      key={file.name}
                      type="button"
                      role="tab"
                      aria-selected={file.name === activeFile}
                      onClick={() => setActiveFile(file.name)}>
                      <FileCode2 size={14} aria-hidden="true" />
                      <span>{file.name}</span>
                    </button>
                  ))}
                </div>

                <div className="playground-actions">
                  <button className="playground-action playground-action--primary" disabled={!canWork || !playground?.runProject} type="button" onClick={runProject}>
                    <Play size={15} aria-hidden="true" />
                    <span>Run</span>
                  </button>
                  <button className="playground-action" disabled={!canWork} type="button" onClick={runCheck}>
                    <CheckCircle2 size={15} aria-hidden="true" />
                    <span>Check</span>
                  </button>
                  <button className="playground-action" disabled={!canWork} type="button" onClick={runFormat}>
                    <Wand2 size={15} aria-hidden="true" />
                    <span>Format</span>
                  </button>
                  <button className="playground-action" type="button" onClick={shareFiles}>
                    <Share2 size={15} aria-hidden="true" />
                    <span>Share</span>
                  </button>
                  <button className="playground-icon-action" type="button" aria-label="Reset example" title="Reset example" onClick={resetExample}>
                    <RotateCcw size={15} aria-hidden="true" />
                  </button>
                </div>
              </div>

              <div className="playground-editor-host">
                <BrowserOnly fallback={<EditorFallback value={activeFileModel?.code ?? ''} onChange={updateActiveFile} />}>
                  {() => (
                    <Suspense fallback={<EditorFallback value={activeFileModel?.code ?? ''} onChange={updateActiveFile} />}>
                      <MonacoEditor
                        beforeMount={beforeMount}
                        height="100%"
                        language="nsharp"
                        onChange={updateActiveFile}
                        onMount={onMount}
                        options={{
                          automaticLayout: true,
                          detectIndentation: false,
                          fixedOverflowWidgets: true,
                          fontFamily: '"SFMono-Regular", "SF Mono", Menlo, Consolas, monospace',
                          fontSize: 14,
                          insertSpaces: true,
                          lineHeight: 21,
                          minimap: {enabled: false},
                          quickSuggestions: {other: true, comments: false, strings: false},
                          renderLineHighlight: 'all',
                          scrollBeyondLastLine: false,
                          smoothScrolling: true,
                          suggestOnTriggerCharacters: true,
                          tabSize: 4,
                          wordBasedSuggestions: 'off',
                        }}
                        path={activeFile}
                        theme="nsharp-light"
                        value={activeFileModel?.code ?? ''}
                      />
                    </Suspense>
                  )}
                </BrowserOnly>
              </div>
            </div>
          </section>

          <aside className="playground-sidepanel" aria-label="Compiler output">
            <div className="playground-panel-tabs">
              <button className={panel === 'output' ? 'active' : ''} type="button" onClick={() => setPanel('output')}>
                Output
              </button>
              <button className={panel === 'problems' ? 'active' : ''} type="button" onClick={() => setPanel('problems')}>
                Problems
                <span>{summary.errors + summary.warnings}</span>
              </button>
              <button className={panel === 'guide' ? 'active' : ''} type="button" onClick={() => setPanel('guide')}>
                Guide
              </button>
            </div>

            {panel === 'output' ? (
              <OutputPanel runResult={runResult} activeExample={activeExample} validationState={validationState} />
            ) : panel === 'problems' ? (
              <>
                <div className="playground-summary">
                  <span>{summary.errors} errors</span>
                  <span>{summary.warnings} warnings</span>
                </div>
                <DiagnosticList diagnostics={diagnostics} onSelect={selectDiagnostic} />
              </>
            ) : (
              <GuidePanel
                activeExample={activeExample}
                activeTutorialStep={activeTutorialStep}
                validationState={validationState}
                isTutorial={isTutorial}
              />
            )}
          </aside>
        </section>
      </main>
    </Layout>
  );
}

export default function Playground() {
  return <PlaygroundWorkbench mode="playground" />;
}
