// Prism.js language definition for N# (NSharp)
(function (Prism) {
    Prism.languages.nsharp = {
        'comment': [
            {
                pattern: /\/\*[\s\S]*?\*\//,
                greedy: true
            },
            {
                pattern: /\/\/.*/,
                greedy: true
            }
        ],
        'string': [
            // Raw interpolated strings
            {
                pattern: /\$"""[\s\S]*?"""/,
                greedy: true,
                inside: {
                    'interpolation': {
                        pattern: /\{[^}]*\}/,
                        inside: {
                            'punctuation': /^\{|\}$/,
                            rest: null // filled below
                        }
                    }
                }
            },
            // Interpolated strings
            {
                pattern: /\$"(?:[^"\\]|\\.)*"/,
                greedy: true,
                inside: {
                    'interpolation': {
                        pattern: /\{[^}]*\}/,
                        inside: {
                            'punctuation': /^\{|\}$/,
                            rest: null
                        }
                    }
                }
            },
            // Raw strings
            {
                pattern: /"""[\s\S]*?"""/,
                greedy: true
            },
            // Regular strings
            {
                pattern: /"(?:[^"\\]|\\.)*"/,
                greedy: true
            }
        ],
        'attribute': {
            pattern: /\[[\w.]+(?:\([^\]]*\))?\]/,
            greedy: true,
            inside: {
                'punctuation': /[[\]()]/,
                'attr-name': /[\w.]+/
            }
        },
        'keyword': /\b(?:func|class|struct|record|union|enum|interface|duck|match|if|else|for|foreach|while|return|import|namespace|package|let|const|async|await|test|assert|print|new|type|virtual|override|abstract|sealed|static|partial|required|init|readonly|ref|out|params|yield|throw|try|catch|finally|using|lock|is|as|in|not|and|or|where|when|file|break|continue|constructor|get|set|var|with|null|true|false|this|base)\b/,
        'builtin': /\b(?:int|string|bool|double|float|void|byte|short|long|char|decimal|object|dynamic|var)\b/,
        'number': /\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|\d+\.?\d*(?:[eE][+-]?\d+)?[fFdDmMlL]?)\b/,
        'operator': /:=|=>|\.\.|\.|\?\.|\.|\?\?=|\?\?|\+\+|--|[+\-*/%]=?|[<>]=?|&&|\|\||[!~^&|]=?|==|!=/,
        'punctuation': /[{}[\]();,.:]/,
        'class-name': {
            pattern: /\b[A-Z]\w*(?:<[^>]+>)?\b/,
            greedy: false
        },
        'function': {
            pattern: /\b[a-zA-Z_]\w*(?=\s*(?:<[^>]+>)?\s*\()/,
            greedy: false
        }
    };

    // Self-reference for interpolations
    Prism.languages.nsharp['string'].forEach(function (def) {
        if (def.inside && def.inside.interpolation && def.inside.interpolation.inside) {
            def.inside.interpolation.inside.rest = Prism.languages.nsharp;
        }
    });

    // Alias
    Prism.languages.nl = Prism.languages.nsharp;

}(Prism));
