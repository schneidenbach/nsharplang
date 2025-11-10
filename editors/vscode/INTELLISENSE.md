# N# IntelliSense - How It Works

## ✅ Member Completion for Objects

The N# VS Code extension provides **full IntelliSense support** for object member access using the Language Server Protocol (LSP).

### How It Works

When you type `.` after an object, the extension:

1. **Detects the trigger** (`CompletionHandler.cs:247` - triggers on `.`, `:`, and space)
2. **Identifies member completion context** (`CompletionHandler.cs:58-66`)
3. **Extracts the identifier** before the dot (`CompletionHandler.cs:172-231`)
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

- ⚡ **Fast:** <100ms completion response time
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
- Ensure proper `using` statements in your .nl file
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
