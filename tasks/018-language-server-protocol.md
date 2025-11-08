# Task 018: Language Server Protocol (LSP) Implementation

**Priority:** CRITICAL (Essential for IDE support and adoption)
**Dependencies:** None
**Estimated Effort:** Very Large (20-30 hours)
**Status:** ✅ Phase 2 COMPLETE - VS Code Integration (v1.65)

## Goal
Implement a Language Server Protocol (LSP) server for N# to provide rich IDE support in VS Code, Visual Studio, Vim, Emacs, and other editors.

## Why This Matters
**This is THE feature that will make N# production-ready and widely adopted.**
- Modern developers expect IDE support
- IntelliSense, go-to-definition, refactoring are essential
- Without LSP, N# is a toy language
- With LSP, N# is a professional tool

## Current Status (v1.64)

### ✅ Completed
1. **Project Structure**
   - Created src/LanguageServer/ project
   - Added OmniSharp.Extensions.LanguageServer dependency (v0.19.9)
   - Added Serilog logging for debugging
   - Proper directory structure (Services/, Handlers/, Models/)

2. **Core Services**
   - **DocumentManager** - Tracks open documents, manages compilation state
   - **DocumentState** - Represents document state with tokens, AST, diagnostics

3. **Handlers Implemented**
   - **TextDocumentHandler** - Document sync (open, change, save, close)
   - **CompletionHandler** - Auto-completion for keywords, types, symbols
   - **HoverHandler** - Type information on hover
   - **Main Program.cs** - LSP server entry point with logging setup

4. **Features**
   - Full document synchronization
   - Real-time parsing and analysis
   - Diagnostic publishing (errors/warnings)
   - Completion items for keywords, primitives, user-defined types
   - Hover information for types and keywords

### ✅ Phase 1 MVP - Complete! (v1.64)

All API compatibility issues resolved:

1. **DocumentManager.cs** - ✅ FIXED:
   - ✅ Updated to use `Parser.ParseCompilationUnit()` (correct method name)
   - ✅ Fixed `Analyzer` constructor - uses parameterless constructor
   - ✅ Fixed `Analyze()` call - passes `uri` and `projectRoot` parameters
   - ✅ Fixed `AnalysisResult` - access via `.Errors` property (List<CompilerError>)
   - ✅ Fixed `CompilerError` creation - uses `CompilerError.Create()` factory method
   - ✅ Updated error code to `ErrorCode.InvalidSyntax`

2. **TextDocumentHandler.cs** - ✅ FIXED:
   - ✅ Version parameter - added null coalescing `?? 0` for int? to int conversion
   - ✅ Removed dependency on DocumentSelector, TextDocumentSyncKind, SaveOptions (not in OmniSharp 0.19.9)
   - ✅ Simplified registration options to use defaults

3. **HoverHandler.cs, CompletionHandler.cs** - ✅ FIXED:
   - ✅ Removed dependency on DocumentSelector (not available in current package version)
   - ✅ Using default registration options

4. **Build Status**:
   - ✅ LSP server builds successfully with 0 errors
   - ✅ All 482 compiler tests passing
   - ✅ Only warnings (async methods, VSTHRD threading suggestions)

### ✅ Phase 2 - VS Code Integration - Complete! (v1.65)

**VS Code Extension with LSP Client**:
1. ✅ Created TypeScript extension code (src/extension.ts)
   - Launches LSP server via dotnet command
   - Auto-detects server path from workspace
   - Supports custom server path configuration
   - Proper activation on .nl files

2. ✅ Updated package.json with LSP support
   - Added vscode-languageclient dependency (v9.0.1)
   - Added main entry point (./out/extension.js)
   - Added activation events (onLanguage:nsharp)
   - Added configuration settings

3. ✅ Configuration Settings
   - nsharp.languageServer.path - custom server path
   - nsharp.trace.server - LSP communication tracing

4. ✅ TypeScript Build System
   - Created tsconfig.json
   - Added compile scripts to package.json
   - Successful compilation to out/extension.js

5. ✅ Extension Packaging
   - Successfully packaged as nsharp-0.2.0.vsix
   - Ready for installation and testing

6. ✅ Documentation Updated
   - Updated README.md with LSP features and installation instructions
   - Updated CHANGELOG.md with v0.2.0 release notes
   - Clear instructions for prerequisites and configuration

**Testing Status**:
- ✅ Extension compiles successfully
- ✅ Extension packages successfully
- ✅ All 482 compiler tests still passing
- ⏳ Manual VS Code testing pending (install and test .vsix)

### 📋 TODO - Phase 3 (Advanced Handlers)
- [ ] Add DefinitionHandler (go-to-definition)
- [ ] Add FindReferencesHandler (find all references)
- [ ] Add RenameHandler (rename symbol)
- [ ] Add SignatureHelpHandler (parameter hints)

### 📋 TODO - Phase 4 (Advanced Features)
- [ ] Semantic tokens (better syntax highlighting)
- [ ] Code actions (quick fixes)
- [ ] Signature help (parameter hints)
- [ ] Document symbols (outline view)
- [ ] Folding ranges
- [ ] Formatting

### 📋 TODO - Phase 5 (Premium Features)
- [ ] Code lens (show references inline)
- [ ] Inlay hints (type hints for inferred types)
- [ ] Call hierarchy
- [ ] Code analysis

## Architecture

### LSP Server Structure
```
src/LanguageServer/
├── LanguageServer.csproj      # LSP server project
├── Program.cs                  # Entry point ✅
├── Handlers/
│   ├── TextDocumentHandler.cs     # Document sync ✅
│   ├── CompletionHandler.cs       # Auto-completion ✅
│   ├── HoverHandler.cs            # Hover info ✅
│   ├── DefinitionHandler.cs       # Go to definition ⏳
│   ├── FindReferencesHandler.cs   # Find references ⏳
│   └── RenameHandler.cs           # Symbol renaming ⏳
├── Services/
│   └── DocumentManager.cs         # Track open documents ✅
└── Models/
    └── DocumentState.cs            # In-memory document state ✅
```

### Technology Stack
- **OmniSharp.Extensions.LanguageServer** - Battle-tested LSP library for C#
- **Serilog** - Logging to ~/.nsharp/lsp.log
- **System.Reactive** - For reactive programming patterns

## Benefits (When Complete)
- **Professional IDE experience** - N# feels like a real language
- **Increased adoption** - Developers won't use a language without IDE support
- **Better developer experience** - Catch errors as you type
- **Cross-editor support** - LSP works in VS Code, Vim, Emacs, etc.
- **Competitive advantage** - Most new languages lack good tooling

## Notes
- This is a KILLER FEATURE that will set N# apart
- LSP is the industry standard for editor integration
- OmniSharp library makes this feasible (don't reinvent the wheel)
- Start with MVP (diagnostics + completion), iterate from there
- All 482 existing compiler tests still passing ✅

## Resources
- [LSP Specification](https://microsoft.github.io/language-server-protocol/)
- [OmniSharp LSP Library](https://github.com/OmniSharp/csharp-language-server-protocol)
- [VS Code Language Extensions Guide](https://code.visualstudio.com/api/language-extensions/overview)
