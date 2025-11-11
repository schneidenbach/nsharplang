# N# VS Code Extension - Quick Start & Troubleshooting

## Installation

### Step 1: Install the Extension

```bash
code --install-extension /Users/claude/Repos/NewCLILang/editors/vscode/nsharp-0.6.0.vsix --force
```

### Step 2: Verify Installation

1. Open VS Code
2. Press `Cmd+Shift+X` (Extensions view)
3. Search for "N#"
4. Should see **"N# Language Support"** installed

### Step 3: Activate the Extension

**The extension only activates when you open a .nl file!**

1. Create a test file: `test.nl`
2. Add this code:
   ```nsharp
   using System

   func main() {
       Console.WriteLine("test")
   }
   ```
3. Save it
4. **Open the file in VS Code**

### Step 4: Verify Language Server Started

1. Press `Cmd+Shift+U` (View → Output)
2. Click dropdown at top right
3. Select **"N# Language Server"**

**Expected output:**
```
N# Language Server starting... (log: ~/.nsharp/lsp.log)
N# Language Server initialized successfully
```

---

## If "N# Language Server" is NOT in the dropdown...

### Problem: Extension Not Activating

**Check 1: Is the extension installed?**
```bash
code --list-extensions | grep nsharp
```

Should show: `nsharp.nsharp` or similar

**Check 2: Check VS Code Extension Host log**
1. Help → Toggle Developer Tools
2. Go to Console tab
3. Look for errors about "nsharp"

**Check 3: Is the file recognized as .nl?**
- Look at bottom-right of VS Code
- Should say "N#" not "Plain Text"
- If it says "Plain Text", click it and select "N#"

**Fix: Force reinstall**
```bash
# Uninstall
code --uninstall-extension nsharp.nsharp

# Delete cache
rm -rf ~/.vscode/extensions/nsharp.*

# Reinstall
cd /Users/claude/Repos/NewCLILang/editors/vscode
code --install-extension nsharp-0.6.0.vsix --force

# Reload VS Code
# Cmd+Shift+P → "Developer: Reload Window"
```

---

## If Server is in dropdown but shows errors...

### Problem: Server Can't Start

**Check dotnet is installed:**
```bash
dotnet --version
# Should be >= 9.0
```

**Check server file exists:**
```bash
ls -la ~/.vscode/extensions/nsharp.*/server/LanguageServer.dll
# Should exist
```

**Test server manually:**
```bash
# Find the extension directory
EXT_DIR=$(ls -d ~/.vscode/extensions/nsharp.nsharp-* | head -1)
cd "$EXT_DIR/server"
dotnet LanguageServer.dll
# Should print: "N# Language Server starting..."
# Press Ctrl+C to exit
```

---

## Testing IntelliSense

Once the server is running:

### Test 1: Basic Completion

```nsharp
using System

func main() {
    Console.
    //      ^ Put cursor here and press Ctrl+Space
}
```

**Expected:** Dropdown showing `WriteLine`, `ReadLine`, `Clear`, etc.

### Test 2: Type the dot

```nsharp
using System

func main() {
    Console.WriteLine
    //     ^ Just type the dot - should auto-trigger
}
```

**Expected:** Completions appear automatically

### Test 3: Hover

```nsharp
using System

func main() {
    Console.WriteLine("test")
    //      ^^^^^^^^^ Hover your mouse here
}
```

**Expected:** Tooltip showing method signature and documentation

---

## Common Issues

### Issue: "Command 'dotnet' not found"

**Fix:**
```bash
# Install .NET 9.0
brew install dotnet-sdk

# Or download from: https://dot.net
```

### Issue: Server starts but no completions

**Debug:**
```bash
# Enable verbose logging
# In VS Code settings (Cmd+,):
{
    "nsharp.trace.server": "verbose"
}

# Reload window
# Check Output panel for detailed messages
```

### Issue: Only keyword completions, no Console.* members

**This means:**
- Server is running ✅
- Extension is working ✅
- But TypeResolver can't find the type

**Check:**
1. Do you have `using System` at the top?
2. Is there a proper identifier before the `.`?
3. Check the log: `tail -f ~/.nsharp/lsp.log`

**Look for:**
```
Looking up members for identifier: Console
Resolved type: System.Console
Found 47 members
```

**If you see "Could not extract identifier":**
- The parser couldn't find what's before the dot
- Try adding spaces: `Console . ` instead of `Console.`

---

## File Structure Check

Your VSIX should contain:

```
nsharp-0.6.0.vsix/
├── extension/
│   ├── out/
│   │   └── extension.js          ← Compiled TypeScript
│   ├── server/
│   │   ├── LanguageServer.dll    ← The LSP server
│   │   └── (62 other DLL files)  ← Dependencies
│   ├── syntaxes/
│   │   └── nsharp.tmLanguage.json ← Syntax highlighting
│   ├── package.json               ← Extension manifest
│   └── language-configuration.json
```

**Verify:**
```bash
# Check VSIX contents
unzip -l nsharp-0.6.0.vsix | grep -E "(extension.js|LanguageServer.dll)"
```

Should show both files.

---

## Step-by-Step Debug Session

Run these commands in order:

```bash
# 1. Verify extension installed
echo "=== Installed extensions ==="
code --list-extensions | grep nsharp

# 2. Find extension directory
echo "=== Extension directory ==="
EXT_DIR=$(ls -d ~/.vscode/extensions/nsharp.* 2>/dev/null | head -1)
echo $EXT_DIR

# 3. Check extension.js exists
echo "=== Extension code ==="
ls -lh "$EXT_DIR/out/extension.js"

# 4. Check server exists
echo "=== Language Server ==="
ls -lh "$EXT_DIR/server/LanguageServer.dll"

# 5. Test server manually
echo "=== Testing server manually ==="
cd "$EXT_DIR/server"
echo "Starting server (press Ctrl+C after 2 seconds)..."
dotnet LanguageServer.dll

# 6. Check log
echo "=== Server log ==="
cat ~/.nsharp/lsp.log
```

**Share the output of these commands if you need help!**

---

## Working Example

Here's a complete working example to test:

**File: `hello.nl`**
```nsharp
using System
using System.Collections.Generic

func main() {
    // Test 1: Console members
    Console.WriteLine("Hello from N#!")

    // Test 2: String methods
    message := "hello world"
    upper := message.ToUpper()

    // Test 3: List methods
    numbers := List<int>()
    numbers.Add(42)
    numbers.Add(100)

    Console.WriteLine($"Count: {numbers.Count}")
}
```

**Try IntelliSense on:**
- Line 6: `Console.` ← Should show WriteLine, ReadLine, etc.
- Line 10: `message.` ← Should show ToUpper, ToLower, Length, etc.
- Line 14: `numbers.` ← Should show Add, Remove, Count, etc.

---

## Success Checklist

- [ ] Extension shows in Extensions view
- [ ] .nl files show "N#" in bottom-right status bar
- [ ] Output panel has "N# Language Server" option
- [ ] Log file created: `~/.nsharp/lsp.log`
- [ ] `Console.` triggers completions
- [ ] Completions include `WriteLine`
- [ ] Hover on `Console` shows documentation
- [ ] String methods work: `str.ToUpper()`

---

## Still Not Working?

1. **Collect debug info:**
   ```bash
   # Create a debug report
   echo "=== System Info ===" > ~/nsharp-debug.txt
   echo "VS Code: $(code --version | head -1)" >> ~/nsharp-debug.txt
   echo "dotnet: $(dotnet --version)" >> ~/nsharp-debug.txt
   echo "" >> ~/nsharp-debug.txt

   echo "=== Extension ===" >> ~/nsharp-debug.txt
   code --list-extensions | grep nsharp >> ~/nsharp-debug.txt
   echo "" >> ~/nsharp-debug.txt

   echo "=== Log ===" >> ~/nsharp-debug.txt
   cat ~/.nsharp/lsp.log >> ~/nsharp-debug.txt 2>&1

   cat ~/nsharp-debug.txt
   ```

2. **Check VS Code Developer Console:**
   - Help → Toggle Developer Tools
   - Console tab
   - Look for red errors

3. **Try the test script:**
   ```bash
   cd /Users/claude/Repos/NewCLILang/editors/vscode
   ./test-server.sh
   ```

---

**Last updated:** November 10, 2025
**Version:** 0.6.0
