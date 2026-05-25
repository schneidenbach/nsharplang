# Building the VS Code Extension

## Full Local Toolset Deploy

To rebuild and redeploy the full local N# toolset in one step, run:

```bash
./scripts/setup-local.sh --with-vscode --no-path-update
```

That refreshes the local N# package cache, installs the `nlc` and `nsharp-lsp`
launchers under `~/.nsharp/bin`, then packages and installs the VS Code
extension without editing shell startup files.

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

# Run headless VS Code smoke tests
../scripts/test-vscode-headless.sh

# Package the extension
npm run package
```

## Build Process

The extension bundles a pre-built .NET language server:

1. **`npm run build-server`** - Publishes `NSharpLang.LanguageServer` to `./server/`
2. **`npm run compile`** - Compiles TypeScript extension code to `./out/`
3. **`npm run package`** - Creates `.vsix` package with both

## Headless VS Code Loop

For a fast editor-level feedback loop without GUI automation, run:

```bash
./scripts/test-vscode-headless.sh
```

That script:

1. Builds the release language server binary
2. Compiles the extension plus the extension-host test harness
3. Launches VS Code in an extension-host test session against a temporary N# workspace
4. Exercises diagnostics, completions, hover, definition, references, and code actions through real VS Code APIs
5. Writes a machine-readable report to `.context/vscode-headless-report.json`

This is the right loop for LLM-driven validation when unit tests pass but the real editor wiring still fails.

## Notes

- The `server/` directory is gitignored (build artifacts)
- Language server is automatically built before packaging
- Use `npm run watch` for TypeScript development (rebuilds on save)
- Language server changes require re-running `npm run build-server`
