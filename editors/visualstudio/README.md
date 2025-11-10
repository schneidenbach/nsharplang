# N# for Visual Studio

This directory contains the Visual Studio 2022 extension for N# language support.

**Status**: Task 095 - Foundation Complete (Windows Required for Final Steps)

## Features (Phase 1 - Basic)

- ✅ Syntax highlighting for `.nl` files (implemented, needs Windows testing)
- ✅ Content type definition for N# code
- ✅ Basic VSPackage structure
- 🚧 VSIX packaging (needs Windows environment)
- 🚧 Project system integration (project.yml)
- 🚧 Build/Run from toolbar
- 🚧 Error list integration

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
├── NSharpPackage.cs           # Main VSPackage
├── Editor/
│   ├── NSharpClassifier.cs           # Syntax highlighting
│   └── NSharpClassifierProvider.cs   # MEF provider
├── ProjectSystem/              # TODO: Project system integration
└── source.extension.vsixmanifest     # VSIX metadata
```

## Next Steps (Task 096)

- IntelliSense support via Language Server Protocol
- Auto-completion (Ctrl+Space)
- Signature help (Ctrl+Shift+Space)
- Quick Info (hover)
- Go to Definition (F12)
- Find All References (Shift+F12)
- Rename (Ctrl+R, R)

## License

Same as the main N# project.
