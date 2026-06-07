// Shared N# browser-runtime helpers: the WASM playground loader, the Monaco
// language registration (syntax highlighting + theme), and the response
// normalizers. Used by both the Playground/Tutorial workbench and the
// "High Performance from Scratch" course so the two never drift.

export function readField(value, camelName, pascalName) {
  return value?.[camelName] ?? value?.[pascalName];
}

export function loadPlaygroundScript(src) {
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

// Loads the WASM playground module and returns the runtime object exposing
// getCatalog/checkProject/runProject/format/complete/hover/version.
export async function loadNSharpRuntime(loaderUrl) {
  await loadPlaygroundScript(loaderUrl);
  return globalThis.loadNSharpPlayground();
}

export function registerNSharpLanguage(monaco) {
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
      'hot', 'boundary', 'alloc', 'stackalloc', 'scoped', 'returns', 'ref', 'unsafe',
    ],
    builtins: [
      'int', 'long', 'float', 'double', 'bool', 'string', 'void', 'object',
      'byte', 'short', 'char', 'decimal', 'Span', 'ReadOnlySpan', 'Vector', 'Result',
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

  if (!monaco.editor.__nsharpThemeDefined) {
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
      },
    });
    monaco.editor.__nsharpThemeDefined = true;
  }
}

export function normalizeSummary(summary) {
  return {
    errors: readField(summary, 'errors', 'Errors') ?? 0,
    warnings: readField(summary, 'warnings', 'Warnings') ?? 0,
    infos: readField(summary, 'infos', 'Infos') ?? 0,
  };
}

export function normalizeDiagnostic(diagnostic) {
  return {
    code: readField(diagnostic, 'code', 'Code'),
    severity: readField(diagnostic, 'severity', 'Severity') ?? 'error',
    message: readField(diagnostic, 'message', 'Message'),
    file: readField(diagnostic, 'file', 'File') ?? 'Program.nl',
    line: readField(diagnostic, 'line', 'Line') ?? 1,
    column: readField(diagnostic, 'column', 'Column') ?? 1,
    length: readField(diagnostic, 'length', 'Length') ?? 1,
    explanation: readField(diagnostic, 'explanation', 'Explanation'),
    suggestion: readField(diagnostic, 'suggestion', 'Suggestion'),
    hint: readField(diagnostic, 'hint', 'Hint'),
  };
}

export function normalizeCheckResponse(response) {
  return {
    schemaVersion: readField(response, 'schemaVersion', 'SchemaVersion'),
    ok: readField(response, 'ok', 'Ok') ?? false,
    file: readField(response, 'file', 'File') ?? 'Program.nl',
    diagnostics: (readField(response, 'diagnostics', 'Diagnostics') ?? []).map(normalizeDiagnostic),
    summary: normalizeSummary(readField(response, 'summary', 'Summary')),
  };
}

export function normalizeRunResponse(response) {
  return {
    ...normalizeCheckResponse(response),
    exitCode: readField(response, 'exitCode', 'ExitCode') ?? 1,
    stdout: readField(response, 'stdout', 'Stdout') ?? '',
    stderr: readField(response, 'stderr', 'Stderr'),
    unsupportedReason: readField(response, 'unsupportedReason', 'UnsupportedReason'),
  };
}

export function normalizeVersion(response) {
  return {
    compiler: readField(response, 'compiler', 'Compiler'),
    wasmHost: readField(response, 'wasmHost', 'WasmHost'),
  };
}
