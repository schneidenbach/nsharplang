# N# for Visual Studio

This directory contains the Visual Studio 2022 extension for N# language support.

**Status**: Tasks 095 & 096 - Foundation Complete (Windows Required for Final Steps)

## Features

### ✅ Implemented (Code Complete)

- **Syntax highlighting** for `.nl` files
- **Content type definition** for N# code
- **Basic VSPackage** structure
- **Language Server Protocol (LSP) integration** for IntelliSense:
  - Auto-completion (Ctrl+Space)
  - Signature help (Ctrl+Shift+Space)
  - Quick Info (hover tooltips)
  - Go to Definition (F12)
  - Find All References (Shift+F12)
  - Rename refactoring (Ctrl+R, R)
  - Real-time diagnostics (error squiggles)
  - Document symbol outline

### 🚧 Requires Windows Testing

- VSIX packaging and installation
- End-to-end IntelliSense testing
- Project system integration (project.yml)
- Build/Run from toolbar
- Error list integration

## Building the Extension

### On macOS/Linux (Code Development)

```bash
cd editors/visualstudio/NSharp.VisualStudio
dotnet build
```

**Note**: This builds the DLL but does not generate the VSIX package. Full VSIX packaging requires Windows.

### On Windows (Full Build)

See `DEVELOPMENT.md` for complete Windows build instructions.

## Installing the Extension

1. Close all instances of Visual Studio
2. Double-click the `.vsix` file from the build output
3. Follow the installation wizard
4. Restart Visual Studio

## Development

To debug the extension:

1. Open the solution in Visual Studio 2022
2. Set `NSharp.VisualStudio` as the startup project
3. Press F5 to launch the experimental instance
4. The extension will be loaded in the experimental instance

## Requirements

- Visual Studio 2022 (version 17.0 or later)
- .NET 8.0 SDK
- Visual Studio SDK

## Architecture

```
NSharp.VisualStudio/
├── NSharpPackage.cs                  # Main VSPackage
├── Editor/
│   ├── NSharpClassifier.cs           # Syntax highlighting
│   └── NSharpClassifierProvider.cs   # MEF provider
├── LanguageServer/
│   └── NSharpLanguageClient.cs       # LSP client (IntelliSense)
├── ProjectSystem/                    # TODO: Project system integration
├── Resources/                        # Icons and assets (TODO)
└── source.extension.vsixmanifest     # VSIX metadata
```

## How It Works

1. **Syntax Highlighting**: Regex-based tokenization provides basic syntax coloring
2. **LSP Client**: `NSharpLanguageClient` starts the N# Language Server process
3. **Language Server**: Separate process providing semantic analysis, IntelliSense, diagnostics
4. **Communication**: JSON-RPC over stdin/stdout between client and server

## Next Steps

See `DEVELOPMENT.md` for:
- Windows-based VSIX packaging
- Installation and testing procedures
- Project system integration plans
- Debugging support roadmap

## License

Same as the main N# project.
