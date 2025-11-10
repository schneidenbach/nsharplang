# Building the VS Code Extension

## Prerequisites

- Node.js 16+ and npm
- .NET 9 SDK
- vsce (`npm install -g @vscode/vsce`)

## Development

```bash
cd editors/vscode

# Install dependencies
npm install

# Build the language server (creates server/ folder)
npm run build-server

# Compile TypeScript
npm run compile

# Package the extension
npm run package
```

## Build Process

The extension bundles a pre-built .NET language server:

1. **`npm run build-server`** - Publishes `NSharpLang.LanguageServer` to `./server/`
2. **`npm run compile`** - Compiles TypeScript extension code to `./out/`
3. **`npm run package`** - Creates `.vsix` package with both

## Notes

- The `server/` directory is gitignored (build artifacts)
- Language server is automatically built before packaging
- Use `npm run watch` for TypeScript development (rebuilds on save)
- Language server changes require re-running `npm run build-server`
