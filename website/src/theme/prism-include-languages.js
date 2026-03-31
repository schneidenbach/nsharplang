import siteConfig from '@generated/docusaurus.config';

export default function prismIncludeLanguages(PrismObject) {
  const {
    themeConfig: {prism},
  } = siteConfig;
  const {additionalLanguages} = prism;

  const PrismBefore = globalThis.Prism;
  globalThis.Prism = PrismObject;
  additionalLanguages.forEach((lang) => {
    if (lang === 'php') {
      require('prismjs/components/prism-markup-templating.js');
    }
    require(`prismjs/components/prism-${lang}`);
  });
  delete globalThis.Prism;
  if (typeof PrismBefore !== 'undefined') {
    globalThis.Prism = PrismObject;
  }

  // Register N# (NSharp) language for syntax highlighting
  PrismObject.languages.nsharp = {
    'comment': [
      { pattern: /\/\*[\s\S]*?\*\//, greedy: true },
      { pattern: /\/\/.*/, greedy: true },
    ],
    'string': [
      {
        pattern: /\$"""[\s\S]*?"""/,
        greedy: true,
        inside: {
          'interpolation': {
            pattern: /\{[^}]*\}/,
            inside: { 'punctuation': /^\{|\}$/ },
          },
        },
      },
      {
        pattern: /\$"(?:[^"\\]|\\.)*"/,
        greedy: true,
        inside: {
          'interpolation': {
            pattern: /\{[^}]*\}/,
            inside: { 'punctuation': /^\{|\}$/ },
          },
        },
      },
      { pattern: /"""[\s\S]*?"""/, greedy: true },
      { pattern: /"(?:[^"\\]|\\.)*"/, greedy: true },
    ],
    'attribute': {
      pattern: /\[[\w.]+(?:\([^\]]*\))?\]/,
      greedy: true,
      inside: {
        'punctuation': /[[\]()]/,
        'attr-name': /[\w.]+/,
      },
    },
    'keyword':
      /\b(?:func|class|struct|record|union|enum|interface|duck|match|if|else|for|foreach|while|return|import|namespace|package|let|const|async|await|test|assert|print|new|type|virtual|override|abstract|sealed|static|partial|required|init|readonly|ref|out|params|yield|throw|try|catch|finally|using|lock|is|as|in|not|and|or|where|when|file|break|continue|constructor|get|set|var|with|null|true|false|this|base)\b/,
    'builtin':
      /\b(?:int|string|bool|double|float|void|byte|short|long|char|decimal|object|dynamic|var)\b/,
    'number':
      /\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\d+\.?\d*(?:[eE][+-]?\d+)?[fFdDmMlL]?)\b/,
    'operator':
      /:=|=>|\.\.|\.|\?\.|\.|\?\?=|\?\?|\+\+|--|[+\-*/%]=?|[<>]=?|&&|\|\||[!~^&|]=?|==|!=/,
    'punctuation': /[{}[\]();,.:]/,
    'class-name': {
      pattern: /\b[A-Z]\w*(?:<[^>]+>)?\b/,
      greedy: false,
    },
    'function': {
      pattern: /\b[a-zA-Z_]\w*(?=\s*(?:<[^>]+>)?\s*\()/,
      greedy: false,
    },
  };

  // Alias
  PrismObject.languages.nl = PrismObject.languages.nsharp;
}
