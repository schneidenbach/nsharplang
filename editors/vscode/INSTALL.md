# Install N# VS Code Extension (FIXED)

## The Issue Was Fixed

**Problem:** The extension was missing `vscode-languageclient/node` module
**Fix:** Rebuilt VSIX to include node_modules
**New Size:** 2.8 MB (was 2.6 MB)

---

## Installation Steps

### 1. Uninstall Old Version (If Installed)

```bash
code --uninstall-extension nsharp.nsharp
rm -rf ~/.vscode/extensions/nsharp.*
```

### 2. Install New VSIX

```bash
code --install-extension /Users/claude/Repos/NewCLILang/editors/vscode/nsharp-0.6.0.vsix --force
```

### 3. Reload VS Code

Press `Cmd+Shift+P` → Type "Reload Window" → Press Enter

---

## Verify Installation

### Step 1: Check Extension is Installed

```bash
code --list-extensions | grep nsharp
# Should show: nsharp.nsharp
```

### Step 2: Open a .nl File

Create test file:
```bash
cat > /tmp/test.nl << 'EOF'
using System

func main() {
    Console.WriteLine("Hello N#!")
}
EOF

code /tmp/test.nl
```

### Step 3: Verify Language Server Started

1. In VS Code, press `Cmd+Shift+U` (View → Output)
2. Click dropdown at top right
3. Select **"N# Language Server"**

**Should see:**
```
N# Language Server starting... (log: ~/.nsharp/lsp.log)
N# Language Server initialized successfully
```

**If you see the error about 'vscode-languageclient/node':**
- You're still using the old VSIX
- Run the uninstall/install steps above again

---

## Test IntelliSense

In your `test.nl` file, try this:

```nsharp
using System

func main() {
    Console.
    //      ^ Put cursor here and press Ctrl+Space
}
```

**Expected Result:**
- Dropdown appears with completions
- Shows: `WriteLine`, `ReadLine`, `Clear`, `Write`, etc.
- Each has a description and type info

**Test hover:**
```nsharp
Console.WriteLine("test")
//      ^^^^^^^^^ Hover mouse here
```

Should show method signature and documentation.

---

## What's Included in This VSIX

✅ **Runtime Dependencies (191 files, 1.01 MB)**
- vscode-languageclient (LSP client library)
- All required npm packages

✅ **Language Server (62 files, 7.01 MB)**
- LanguageServer.dll (compiled .NET 9.0)
- All .NET dependencies

✅ **Extension Code**
- Compiled TypeScript (extension.js)
- Syntax highlighting grammar
- Language configuration

✅ **Documentation**
- README.md - Overview
- QUICKSTART.md - Step-by-step setup
- DEBUG.md - Troubleshooting guide
- INTELLISENSE.md - How it works

**Total:** 267 files, 2.8 MB

---

## Troubleshooting

### Issue: Still getting "Cannot find module" error

**Solution:**
```bash
# Nuclear option - complete clean reinstall
code --uninstall-extension nsharp.nsharp
rm -rf ~/.vscode/extensions/nsharp.*
rm -rf ~/.nsharp/

# Kill any VS Code instances
killall "Visual Studio Code" || true

# Reinstall
code --install-extension /Users/claude/Repos/NewCLILang/editors/vscode/nsharp-0.6.0.vsix --force

# Start VS Code fresh
code /tmp/test.nl
```

### Issue: Server not starting

Check dotnet version:
```bash
dotnet --version
# Must be >= 9.0
```

Test server manually:
```bash
EXT_DIR=$(ls -d ~/.vscode/extensions/nsharp.* | head -1)
cd "$EXT_DIR/server"
dotnet LanguageServer.dll
# Should print: "N# Language Server starting..."
# Press Ctrl+C to exit
```

### Issue: No completions appearing

1. Verify server is running (check Output panel)
2. Make sure you have `using System` at top of file
3. Try manual trigger: `Ctrl+Space`
4. Check log: `tail -f ~/.nsharp/lsp.log`

---

## Success Checklist

After installation, verify these work:

- [ ] Extension shows in Extensions view (Cmd+Shift+X)
- [ ] .nl files show "N#" in bottom-right status bar
- [ ] Output panel has "N# Language Server" option
- [ ] Server log shows "initialized successfully"
- [ ] `Console.` triggers completions automatically
- [ ] Completions include `WriteLine`, `ReadLine`, etc.
- [ ] Hover on `Console` shows documentation
- [ ] String methods work: `str.ToUpper()` shows completions

---

## Building from Source

If you want to rebuild the VSIX yourself:

```bash
cd /Users/claude/Repos/NewCLILang/editors/vscode

# Clean previous builds
rm -rf node_modules out server *.vsix

# Install dependencies
npm install

# Build everything (server + extension + package)
npm run package

# Install
code --install-extension nsharp-0.6.0.vsix --force
```

---

## What Was Fixed

**Old VSIX (broken):**
- Excluded all node_modules
- Extension code couldn't load vscode-languageclient
- Activation failed with "Cannot find module" error

**New VSIX (working):**
- Includes runtime dependencies in node_modules
- Excludes only test files and docs from node_modules
- Extension activates successfully
- IntelliSense works

**Change made:** Updated `.vscodeignore` to selectively exclude files instead of excluding all node_modules.

---

**Ready to install!** Use the commands at the top of this file.
