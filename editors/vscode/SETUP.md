# N# Language Server Setup Guide

This guide will help you set up the N# Language Server for VS Code to get IntelliSense, diagnostics, and other IDE features.

## Prerequisites

- **VS Code** installed
- **.NET 9.0 SDK** or later
- **Node.js** and **npm** (for building the extension)

## Quick Setup (3 Steps)

### Step 1: Build the Language Server

```bash
cd /Users/claude/Repos/NewCLILang

# Build the language server
dotnet build src/LanguageServer/LanguageServer.csproj

# Verify it was built
ls -lh src/LanguageServer/bin/Debug/net10.0/LanguageServer.dll
```

Expected output: You should see `LanguageServer.dll` (~10-20 KB)

### Step 2: Install the VS Code Extension

```bash
cd editors/vscode

# Install dependencies (if not already done)
npm install

# Compile the extension
npm run compile

# Install the extension in VS Code
code --install-extension nsharp-0.3.0.vsix
```

### Step 3: Open a N# Project and Test

```bash
# Open the N# workspace in VS Code
code /Users/claude/Repos/NewCLILang

# Or open any folder containing .nl files
code examples/13-aspnet-demo/EmployeeApi
```

The extension will **auto-detect** the Language Server if you're in the N# workspace!

---

## Verify It's Working

### 1. Check Output Channel

In VS Code:
1. Press `Cmd+Shift+U` (macOS) or `Ctrl+Shift+U` (Windows/Linux) to open Output
2. Select **"N# Language Server"** from the dropdown
3. You should see: `N# Language Server started`

### 2. Check Logs

The Language Server logs to:
```
~/.nsharp/lsp.log
```

View the log:
```bash
tail -f ~/.nsharp/lsp.log
```

You should see entries like:
```
N# Language Server initialized
Client: Visual Studio Code 1.x.x
```

### 3. Test Features

Open any `.nl` file and test these features:

#### ✅ **Syntax Highlighting**
Should see colored keywords, strings, types, etc.

#### ✅ **Diagnostics (Errors)**
Try typing invalid code:
```nsharp
func Main() {
    x := "hello"
    y := x + 5  // Error: Type mismatch should appear with red squiggle
}
```

Check the **Problems** panel (`Cmd+Shift+M`) - you should see the error!

#### ✅ **Auto-Completion**
Type `func` and press `Ctrl+Space` - you should see keyword suggestions

#### ✅ **Hover Information**
Hover over a variable or type - you should see type information

---

## Configuration Options

### Custom Language Server Path

If you want to use a different Language Server location:

1. Open VS Code Settings (`Cmd+,`)
2. Search for "nsharp"
3. Set **"N# > Language Server: Path"** to your custom path

Example:
```json
{
  "nsharp.languageServer.path": "/custom/path/to/LanguageServer.dll"
}
```

### Enable Trace Logging

To debug LSP communication:

```json
{
  "nsharp.trace.server": "verbose"
}
```

Options: `"off"` | `"messages"` | `"verbose"`

---

## Troubleshooting

### Problem: "N# Language Server not found"

**Solution:**
1. Make sure you built the Language Server:
   ```bash
   dotnet build src/LanguageServer/LanguageServer.csproj
   ```

2. Check the path exists:
   ```bash
   ls src/LanguageServer/bin/Debug/net10.0/LanguageServer.dll
   ```

3. If using a custom path, verify it in settings

### Problem: Extension not activating

**Check:**
1. File has `.nl` extension
2. Extension is installed: `code --list-extensions | grep nsharp`
3. Reload VS Code: Press `Cmd+Shift+P` → "Developer: Reload Window"

### Problem: No diagnostics appearing

**Debugging steps:**
1. Check Output channel for errors
2. Check log file: `tail -f ~/.nsharp/lsp.log`
3. Try opening/closing the file
4. Check if file has syntax errors that prevent parsing

### Problem: Language Server crashes

**Check the log:**
```bash
cat ~/.nsharp/lsp.log
```

Common issues:
- Missing .NET 9.0 runtime
- File permissions on the DLL
- Port conflicts (shouldn't happen with stdio transport)

---

## Advanced: Development Setup

If you're working on the Language Server itself:

### 1. Rebuild Language Server

```bash
dotnet build src/LanguageServer/LanguageServer.csproj
```

### 2. Reload VS Code

After rebuilding:
- Press `Cmd+Shift+P` → "Developer: Reload Window"
- Or restart VS Code

The extension will pick up the new DLL automatically.

### 3. Debug the Language Server

Add to your VS Code `launch.json`:

```json
{
  "name": "Attach to N# Language Server",
  "type": "coreclr",
  "request": "attach",
  "processName": "dotnet"
}
```

Then:
1. Start debugging in VS Code (`F5`)
2. Select the `dotnet` process running `LanguageServer.dll`
3. Set breakpoints in Language Server code

### 4. Extension Development

To work on the VS Code extension itself:

```bash
cd editors/vscode

# Install dependencies
npm install

# Watch mode (auto-compile on changes)
npm run watch
```

Then press `F5` in VS Code to launch Extension Development Host.

---

## Features Currently Implemented

✅ **Syntax Highlighting** - Full TextMate grammar with all N# features
✅ **Diagnostics** - Real-time error checking as you type
✅ **Hover** - Type information on hover
✅ **Auto-completion** - Keywords and basic types
✅ **Document Management** - Parsing and analysis on file changes

## Features Coming Soon

🚧 **Go to Definition** - Jump to symbol declarations
🚧 **Find All References** - Find where symbols are used
🚧 **Rename Symbol** - Refactor symbol names
🚧 **Signature Help** - Parameter info for function calls
🚧 **Document Symbols** - Outline view
🚧 **Formatting** - Auto-format code

---

## Architecture Overview

```
VS Code Extension (TypeScript)
    ↓ (LSP via stdin/stdout)
Language Server (.NET 9)
    ├─ TextDocumentHandler - File sync
    ├─ CompletionHandler - Auto-complete
    ├─ HoverHandler - Type info
    └─ DocumentManager - Parsing & Analysis
        ├─ Lexer → Tokens
        ├─ Parser → AST
        └─ Analyzer → Errors & Types
```

The Language Server uses your existing N# compiler components (Lexer, Parser, Analyzer) to provide IDE features!

---

## Uninstalling

To remove the extension:

```bash
code --uninstall-extension nsharp.nsharp
```

To clean up:
```bash
rm -rf ~/.nsharp
```

---

## Support

If you encounter issues:
1. Check the log: `~/.nsharp/lsp.log`
2. Check the Output channel in VS Code
3. Open an issue with the log contents

---

## Next Steps

Once setup is complete, try:
1. Opening the ASP.NET demo: `examples/13-aspnet-demo/EmployeeApi/`
2. Editing a `.nl` file and watching diagnostics appear
3. Using auto-completion with `Ctrl+Space`
4. Hovering over variables to see types

Enjoy your N# development experience! 🚀
