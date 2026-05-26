# N# IntelliSense - How It Works

## Completion And Auto-Import

The N# VS Code extension provides LSP-backed IntelliSense for identifier completion, auto-import, and supported object member access scenarios.

### How It Works

When you request identifier completion, the language server ranks local and in-scope symbols first, then importable project and framework symbols. Importable items carry LSP `additionalTextEdits` that insert a missing `import` after existing `namespace`, `package`, and `import` declarations without disturbing the header layout.

When duplicate project symbols share a simple name, completion keeps separate entries with their declaring namespace in the detail text and applies the matching import edit for the selected namespace. Existing unaliased imports suppress duplicate import edits; aliased imports do not, because they do not make the simple name available.

When you type `.` after an object, the extension:

1. **Detects the trigger** (`CompletionHandler.cs` registers `.`, `:`, and space)
2. **Identifies member completion context** in the completion handler
3. **Extracts the identifier** before the dot
4. **Resolves the type** using `TypeResolver` service
5. **Loads members** via .NET reflection
6. **Returns completion items** with:
   - Member names (methods, properties, fields, events)
   - Member types and signatures
   - XML documentation (if available)
   - Appropriate icons

### Example

```nsharp
builder := WebApplication.CreateBuilder(args)
builder. // <-- Triggers IntelliSense
```

**Shows:**
- ✅ `Services` (property) - IServiceCollection
- ✅ `Configuration` (property) - IConfiguration
- ✅ `Environment` (property) - IWebHostEnvironment
- ✅ `Build()` (method) - WebApplication
- ✅ All other public members with documentation

### Technical Implementation

**Key Files:**
- `CompletionHandler.cs` - Main completion logic
- `TypeResolver.cs` - Type resolution via reflection
- `XmlDocReader.cs` - XML documentation loading
- `DocumentManager.cs` - Document state management

**Features:**
- ✅ External types (WebApplication, DbContext, Console, etc.)
- ✅ Local variables and fields
- ✅ Local and in-scope symbols ranked before importable suggestions
- ✅ Project-symbol auto-import with duplicate namespace disambiguation
- ✅ Framework type auto-import with duplicate suppression
- ✅ Method signatures with parameters
- ✅ Property types
- ✅ XML documentation tooltips
- ✅ Namespace imports
- ✅ Generic types

### Installation

1. Install the VSIX:
   ```bash
   code --install-extension editors/vscode/nsharp-0.6.0.vsix
   ```

2. Open any `.nl` file

3. Type an object name followed by `.` to trigger IntelliSense

### Supported Scenarios

```nsharp
// ✅ External .NET types
Console.WriteLine("test")
      //^ Shows all Console members

// ✅ Builder patterns
app.UseRouting()
   //^ Shows IApplicationBuilder methods

// ✅ Generic types
List<int>.
        //^ Shows List<T> members

// ✅ LINQ
numbers.Where(x => x > 5)
       //^ Shows IEnumerable<T> extension methods
```

### Configuration

The extension looks for the Language Server in:
1. Bundled with extension (`extension/server/LanguageServer.dll`)
2. Custom path (set in VS Code settings: `nsharp.languageServer.path`)
3. Development workspace (`src/NSharpLang.LanguageServer/bin/...`)

### Performance

- ⚡ **Performance:** Completion paths should be measured with current smoke/performance gates before quoting latency numbers
- 📦 **Cached:** Assembly metadata cached after first load
- 🔄 **Lazy:** XML docs loaded on-demand

## Building from Source

```bash
cd editors/vscode
npm install
npm run package  # Creates nsharp-0.6.0.vsix
```

The package script automatically:
1. Builds the Language Server in Release mode
2. Publishes to `./server/` directory
3. Compiles TypeScript extension code
4. Packages everything into VSIX

## Troubleshooting

**IntelliSense not working?**
1. Check Output panel → "N# Language Server"
2. Look for server startup messages
3. Check log: `~/.nsharp/lsp.log`
4. Verify `dotnet --version` >= 9.0

**No members showing?**
- Ensure proper `import` statements in your .nl file
- Check that assemblies are referenced in project.yml
- Restart VS Code to reload Language Server

## What's Included

The VSIX package (2.6 MB) contains:
- ✅ Syntax highlighting (TextMate grammar)
- ✅ Language Server (7 MB - includes all dependencies)
- ✅ IntelliSense completion
- ✅ Signature help
- ✅ Hover documentation
- ✅ Go to definition
- ✅ Code actions/quick fixes
- ✅ Diagnostics (errors/warnings)
- ✅ Formatting support

---

**Built:** November 10, 2025
**Version:** 0.6.0
**Language Server:** Full LSP implementation with .NET reflection-based IntelliSense
