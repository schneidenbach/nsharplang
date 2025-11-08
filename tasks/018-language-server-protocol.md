# Task 018: Language Server Protocol (LSP) Implementation

**Priority:** CRITICAL (Essential for IDE support and adoption)
**Dependencies:** None
**Estimated Effort:** Very Large (20-30 hours)
**Status:** 🔥 NEW TASK - KILLER FEATURE

## Goal
Implement a Language Server Protocol (LSP) server for N# to provide rich IDE support in VS Code, Visual Studio, Vim, Emacs, and other editors.

## Why This Matters
**This is THE feature that will make N# production-ready and widely adopted.**
- Modern developers expect IDE support
- IntelliSense, go-to-definition, refactoring are essential
- Without LSP, N# is a toy language
- With LSP, N# is a professional tool

## Features to Implement

### Phase 1: Core Features (MVP)
1. **Syntax Highlighting** - Token classification
2. **Diagnostics** - Show errors/warnings in real-time
3. **Auto-completion** - Variable names, types, keywords
4. **Hover Information** - Type information on hover
5. **Go to Definition** - Jump to declaration

### Phase 2: Advanced Features
6. **Find All References** - Find all usages
7. **Rename Symbol** - Refactoring support
8. **Document Symbols** - Outline view
9. **Code Actions** - Quick fixes (import missing types, etc.)
10. **Signature Help** - Parameter hints
11. **Formatting** - Code formatting

### Phase 3: Premium Features
12. **Semantic Tokens** - Advanced syntax highlighting
13. **Code Lens** - Show references inline
14. **Inlay Hints** - Type hints for inferred types
15. **Call Hierarchy** - Function call graphs

## Architecture

### LSP Server Structure
```
src/LanguageServer/
├── LanguageServer.csproj      # LSP server project
├── Program.cs                  # Entry point
├── NSharpLanguageServer.cs    # Main LSP implementation
├── Handlers/
│   ├── TextDocumentHandler.cs     # Document sync
│   ├── CompletionHandler.cs       # Auto-completion
│   ├── DefinitionHandler.cs       # Go to definition
│   ├── HoverHandler.cs            # Hover info
│   ├── DiagnosticHandler.cs       # Error/warning diagnostics
│   ├── RenameHandler.cs           # Symbol renaming
│   └── FormattingHandler.cs       # Code formatting
├── Services/
│   ├── DocumentManager.cs         # Track open documents
│   ├── CompletionService.cs       # Generate completions
│   ├── DefinitionService.cs       # Find definitions
│   └── DiagnosticService.cs       # Run analyzer on code
└── Models/
    └── DocumentState.cs            # In-memory document state
```

### Technology Stack
Use **OmniSharp.Extensions.LanguageServer** - battle-tested LSP library for C#:
```xml
<PackageReference Include="OmniSharp.Extensions.LanguageServer" Version="0.19.9" />
```

## Implementation Steps

### 1. Project Setup
Create new project:
```bash
dotnet new console -n LanguageServer -o src/LanguageServer
cd src/LanguageServer
dotnet add package OmniSharp.Extensions.LanguageServer
```

### 2. Basic LSP Server
```csharp
// Program.cs
using OmniSharp.Extensions.LanguageServer.Server;

var server = await LanguageServer.From(options =>
    options
        .WithInput(Console.OpenStandardInput())
        .WithOutput(Console.OpenStandardOutput())
        .WithHandler<TextDocumentHandler>()
        .WithHandler<CompletionHandler>()
        .WithHandler<DefinitionHandler>()
        .WithHandler<HoverHandler>()
        .WithServices(services => {
            services.AddSingleton<DocumentManager>();
            services.AddSingleton<CompilerService>();
        })
);

await server.WaitForExit;
```

### 3. Document Manager
```csharp
public class DocumentManager {
    private readonly ConcurrentDictionary<string, DocumentState> _documents = new();

    public void UpdateDocument(string uri, string text, int version) {
        var state = new DocumentState(uri, text, version);
        _documents[uri] = state;

        // Parse and analyze on update
        state.CompilationUnit = ParseDocument(text);
        state.Diagnostics = AnalyzeDocument(state.CompilationUnit);
    }

    public DocumentState? GetDocument(string uri) {
        _documents.TryGetValue(uri, out var doc);
        return doc;
    }
}

public record DocumentState {
    public string Uri { get; init; }
    public string Text { get; init; }
    public int Version { get; init; }
    public CompilationUnit? CompilationUnit { get; set; }
    public List<Diagnostic>? Diagnostics { get; set; }
    public SymbolTable? Symbols { get; set; }
}
```

### 4. Diagnostics Handler
```csharp
public class DiagnosticHandler : ITextDocumentSyncHandler {
    private readonly DocumentManager _documentManager;
    private readonly ILanguageServerFacade _languageServer;

    public Task<Unit> Handle(DidChangeTextDocumentParams request, CancellationToken token) {
        var uri = request.TextDocument.Uri.ToString();
        var text = request.ContentChanges.First().Text;

        // Update document
        _documentManager.UpdateDocument(uri, text, request.TextDocument.Version);

        // Get diagnostics
        var doc = _documentManager.GetDocument(uri);
        var diagnostics = ConvertDiagnostics(doc.Diagnostics);

        // Publish diagnostics to client
        _languageServer.TextDocument.PublishDiagnostics(new PublishDiagnosticsParams {
            Uri = request.TextDocument.Uri,
            Diagnostics = diagnostics
        });

        return Unit.Task;
    }

    private Container<Diagnostic> ConvertDiagnostics(List<CompilerError> errors) {
        return errors.Select(e => new Diagnostic {
            Range = new Range(e.Line - 1, e.Column - 1, e.Line - 1, e.Column + 10),
            Severity = e.IsWarning ? DiagnosticSeverity.Warning : DiagnosticSeverity.Error,
            Code = $"NL{(int)e.Code:D3}",
            Source = "N#",
            Message = e.Message
        }).ToArray();
    }
}
```

### 5. Completion Handler
```csharp
public class CompletionHandler : CompletionHandlerBase {
    private readonly DocumentManager _documentManager;

    protected override Task<CompletionList> Handle(CompletionParams request, CancellationToken token) {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        if (doc == null) return Task.FromResult(new CompletionList());

        // Get completions at cursor position
        var completions = GetCompletionsAtPosition(
            doc,
            request.Position.Line,
            request.Position.Character
        );

        return Task.FromResult(new CompletionList(completions));
    }

    private List<CompletionItem> GetCompletionsAtPosition(DocumentState doc, int line, int col) {
        var items = new List<CompletionItem>();

        // Add keywords
        items.AddRange(Keywords.All.Select(k => new CompletionItem {
            Label = k,
            Kind = CompletionItemKind.Keyword,
            Detail = "keyword"
        }));

        // Add variables in scope
        var scope = GetScopeAtPosition(doc, line, col);
        items.AddRange(scope.Variables.Select(v => new CompletionItem {
            Label = v.Name,
            Kind = CompletionItemKind.Variable,
            Detail = v.Type.ToString()
        }));

        // Add types
        items.AddRange(doc.Symbols.Types.Select(t => new CompletionItem {
            Label = t.Name,
            Kind = CompletionItemKind.Class,
            Detail = t.Kind.ToString()
        }));

        return items;
    }
}
```

### 6. Go to Definition Handler
```csharp
public class DefinitionHandler : DefinitionHandlerBase {
    protected override Task<LocationOrLocationLinks> Handle(DefinitionParams request, CancellationToken token) {
        var uri = request.TextDocument.Uri.ToString();
        var doc = _documentManager.GetDocument(uri);

        // Find symbol at position
        var symbol = FindSymbolAtPosition(doc, request.Position.Line, request.Position.Character);

        if (symbol?.DefinitionLocation != null) {
            return Task.FromResult(new LocationOrLocationLinks(new Location {
                Uri = DocumentUri.From(symbol.DefinitionLocation.File),
                Range = new Range(
                    symbol.DefinitionLocation.Line - 1,
                    symbol.DefinitionLocation.Column - 1,
                    symbol.DefinitionLocation.Line - 1,
                    symbol.DefinitionLocation.Column + symbol.Name.Length
                )
            }));
        }

        return Task.FromResult(new LocationOrLocationLinks());
    }
}
```

### 7. VS Code Extension
Create VS Code extension in `editors/vscode/`:
```json
// package.json
{
  "name": "nsharp",
  "displayName": "N# Language Support",
  "description": "Language support for N# (.nl files)",
  "version": "0.1.0",
  "engines": { "vscode": "^1.75.0" },
  "categories": ["Programming Languages"],
  "activationEvents": ["onLanguage:nsharp"],
  "main": "./out/extension.js",
  "contributes": {
    "languages": [{
      "id": "nsharp",
      "aliases": ["N#", "nsharp"],
      "extensions": [".nl"],
      "configuration": "./language-configuration.json"
    }],
    "grammars": [{
      "language": "nsharp",
      "scopeName": "source.nsharp",
      "path": "./syntaxes/nsharp.tmLanguage.json"
    }],
    "configuration": {
      "title": "N#",
      "properties": {
        "nsharp.languageServer.path": {
          "type": "string",
          "default": "",
          "description": "Path to N# language server"
        }
      }
    }
  }
}
```

```typescript
// src/extension.ts
import * as vscode from 'vscode';
import { LanguageClient, LanguageClientOptions, ServerOptions } from 'vscode-languageclient/node';

let client: LanguageClient;

export function activate(context: vscode.ExtensionContext) {
    const serverPath = 'dotnet'; // Or path to language server executable
    const args = ['run', '--project', 'path/to/LanguageServer.csproj'];

    const serverOptions: ServerOptions = {
        command: serverPath,
        args: args
    };

    const clientOptions: LanguageClientOptions = {
        documentSelector: [{ scheme: 'file', language: 'nsharp' }],
        synchronize: {
            fileEvents: vscode.workspace.createFileSystemWatcher('**/.nl')
        }
    };

    client = new LanguageClient(
        'nsharpLanguageServer',
        'N# Language Server',
        serverOptions,
        clientOptions
    );

    client.start();
}

export function deactivate(): Thenable<void> | undefined {
    if (!client) return undefined;
    return client.stop();
}
```

## Testing Strategy

### Unit Tests
- Test each handler independently
- Mock document state
- Verify correct LSP responses

### Integration Tests
- Test full LSP protocol flow
- Use LSP test client
- Verify VS Code integration

### Manual Testing
1. Install VS Code extension
2. Open .nl file
3. Verify:
   - Syntax highlighting works
   - Errors show in Problems panel
   - Auto-completion works (Ctrl+Space)
   - Go to definition works (F12)
   - Hover shows type info
   - Rename works (F2)

## Success Criteria
- [ ] LSP server compiles and runs
- [ ] VS Code extension installs successfully
- [ ] Real-time diagnostics (errors/warnings)
- [ ] Auto-completion for keywords, types, variables
- [ ] Go to definition works for symbols
- [ ] Hover shows type information
- [ ] Find all references works
- [ ] Rename symbol works
- [ ] Code formatting works
- [ ] Published to VS Code marketplace

## Benefits
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
- VS Code extension can be simple at first
- Consider adding syntax highlighting as separate quick win first

## Resources
- [LSP Specification](https://microsoft.github.io/language-server-protocol/)
- [OmniSharp LSP Library](https://github.com/OmniSharp/csharp-language-server-protocol)
- [VS Code Language Extensions Guide](https://code.visualstudio.com/api/language-extensions/overview)
