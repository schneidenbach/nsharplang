# Debugging N# IntelliSense

## Quick Diagnosis Steps

### 0. Run The Headless VS Code Smoke Tests

```bash
./scripts/test-vscode-headless.sh
```

This launches the real extension in a VS Code extension host, exercises core provider paths through the editor API, and writes a JSON report to `.context/vscode-headless-report.json`. Use this first when you want an LLM to validate editor behavior without screen control.

### 1. Check Language Server is Running

**Open VS Code Output Panel:**
1. Press `Cmd+Shift+U` (View → Output)
2. Select "N# Language Server" from dropdown
3. Look for initialization messages:
   ```
   N# Language Server starting... (log: ~/.nsharp/lsp.log)
   N# Language Server initialized successfully
   ```

**If you don't see "N# Language Server" in the dropdown:**
- Extension didn't activate
- Check Extensions view (`Cmd+Shift+X`) - is "N# Language Support" enabled?

### 2. Check Log File

```bash
tail -f ~/.nsharp/lsp.log
```

Look for:
- ✅ "N# Language Server initialized"
- ✅ "Loaded assembly: System.Console"
- ✅ "Providing X completion items"
- ❌ Any ERROR messages

### 3. Test Basic Completion

Create a test file `test.nl`:
```nsharp
using System

func main() {
    Console.
    //      ^ Put cursor here and press Ctrl+Space
}
```

**Expected:** Should see `WriteLine`, `ReadLine`, `Clear`, etc.

**If nothing appears:**
- Go to step 4 (detailed debugging)

### 4. Enable Verbose Logging

**In VS Code Settings (`Cmd+,`):**
```json
{
    "nsharp.trace.server": "verbose"
}
```

Reload window (`Cmd+Shift+P` → "Reload Window")

Now check Output panel again - you'll see all LSP messages.

---

## Common Issues & Fixes

### Issue 1: "N# Language Server not found"

**Symptoms:**
- Error message on startup
- No IntelliSense at all

**Fix:**
```bash
# Rebuild the Language Server
cd src/NSharpLang.LanguageServer
dotnet publish -c Release -o ../../editors/vscode/server

# Or rebuild the whole VSIX
cd editors/vscode
npm run package
code --install-extension nsharp-0.6.0.vsix --force
```

### Issue 2: Server Crashes on Startup

**Symptoms:**
- Log shows error and exits
- Output panel shows nothing

**Debug:**
```bash
# Test Language Server manually
cd editors/vscode/server
dotnet LanguageServer.dll
# Should say "N# Language Server starting..."
# Press Ctrl+C to exit
```

**Check .NET version:**
```bash
dotnet --version
# Should be >= 9.0
```

### Issue 3: No Completions for External Types

**Symptoms:**
- Completions work for keywords
- No completions for `Console.`, `List.`, etc.

**Debug in log:**
```bash
grep -i "Looking up members" ~/.nsharp/lsp.log
grep -i "Resolved type" ~/.nsharp/lsp.log
```

**If you see "Could not extract identifier":**
- The completion handler isn't parsing the line correctly
- Check that you have a proper identifier before the `.`

**If you see "Resolved type: null":**
- TypeResolver couldn't find the type
- Make sure you have a `using` statement
- Check the log for "Loaded assembly" messages

### Issue 4: Completions Appear but Wrong Items

**Symptoms:**
- Get completions but not the right ones
- Only seeing keywords, not members

**Check:**
1. Is there a `using System` at the top?
2. Did you compile the file with `dotnet build` first?
3. Check that trigger was `.` not something else

---

## Manual Testing Script

Create `test-intellisense.nl`:
```nsharp
using System
using System.Collections.Generic

func TestCompletions() {
    // Test 1: Basic Console completion
    Console.WriteLine("test")
    //      ^ Put cursor after dot, press Ctrl+Space
    //        Expected: WriteLine, ReadLine, Clear, etc.

    // Test 2: String members
    str := "hello"
    str.ToUpper()
    //  ^ Expected: ToUpper, ToLower, Length, etc.

    // Test 3: List<T> members
    numbers := [1, 2, 3]
    numbers.Add(4)
    //     ^ Expected: Add, Remove, Count, etc.

    // Test 4: Builder pattern
    builder := System.Text.StringBuilder()
    builder.Append("test")
    //     ^ Expected: Append, ToString, Length, etc.
}
```

Open in VS Code and test each cursor position.

---

## Advanced Debugging

### Run Language Server in Debug Mode

**In terminal:**
```bash
cd editors/vscode/server
NSHARP_LSP_DEBUG=1 dotnet LanguageServer.dll
```

Then in VS Code:
1. Open Command Palette (`Cmd+Shift+P`)
2. Run "Developer: Restart Extension Host"

### Attach Debugger to Language Server

**In VS Code:**
1. Install C# Dev Kit extension
2. Open `src/NSharpLang.LanguageServer/Program.cs`
3. Set breakpoint in `CompletionHandler.cs:Handle` method
4. Press F5 → "Attach to Process"
5. Find `dotnet LanguageServer.dll` process
6. Trigger completion in a .nl file
7. Debugger should hit breakpoint

### Check TypeResolver State

Add this to `CompletionHandler.cs` temporarily:
```csharp
// In GetMemberCompletionItems method, after resolving type:
if (type != null)
{
    _logger.LogInformation("Resolved type: {TypeName}", type.FullName);
    var members = _typeResolver.GetMembers(type);
    _logger.LogInformation("Found {Count} members", members.Count);
    // ... rest of code
}
else
{
    _logger.LogWarning("Could not resolve type for identifier: {Id}", identifier);
}
```

Rebuild and check log for these messages.

---

## Expected Behavior

### What Should Work

✅ **Console completion:**
```nsharp
Console.WriteLine()
//      ^^^^^^^^^ Should show immediately after typing .
```

✅ **Variable members:**
```nsharp
str := "test"
str.ToUpper()
//  ^^^^^^^ Should show string methods
```

✅ **External types:**
```nsharp
using Microsoft.AspNetCore.Builder

builder := WebApplication.CreateBuilder(args)
builder.Services
//     ^^^^^^^^ Should show IServiceCollection members
```

### What Might Not Work Yet

❌ **Local class members (same file):**
- Need to parse and track local symbols
- Currently only works for external types

❌ **Cross-file references:**
- Need workspace symbol resolution
- Currently only works within same file + external types

---

## Testing Checklist

Run through these tests:

- [ ] Extension shows in Extensions view
- [ ] .nl files recognized (N# icon)
- [ ] Syntax highlighting works
- [ ] Output panel shows "N# Language Server"
- [ ] Log file exists at ~/.nsharp/lsp.log
- [ ] Log shows "initialized successfully"
- [ ] `Console.` triggers completion
- [ ] Completion shows `WriteLine`
- [ ] Hover on `Console` shows documentation
- [ ] String variable members work
- [ ] List methods appear

---

## Getting Help

**Check logs:**
```bash
# Server log
cat ~/.nsharp/lsp.log

# VS Code extension host log
# Help → Toggle Developer Tools → Console tab
```

**Report issue with:**
1. VS Code version
2. N# extension version (from Extensions view)
3. Contents of `~/.nsharp/lsp.log`
4. Sample .nl file that doesn't work
5. What you expected vs what happened

---

## Quick Fix: Nuclear Option

If nothing works, try complete reinstall:

```bash
# 1. Uninstall extension
code --uninstall-extension nsharp.nsharp

# 2. Clean logs
rm -rf ~/.nsharp/

# 3. Rebuild VSIX from scratch
cd editors/vscode
rm -rf node_modules server out *.vsix
npm install
npm run package

# 4. Reinstall
code --install-extension nsharp-0.6.0.vsix --force

# 5. Reload VS Code
# Cmd+Shift+P → "Reload Window"
```

Then open a .nl file and check Output panel.
