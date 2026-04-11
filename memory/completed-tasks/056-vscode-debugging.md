# Task 056: VS Code Debugging

**Effort:** Medium (6-8 hours)
**Depends:** Task 042
**Ships:** Debugging works

## Goal

Enable debugging N# code in any IDE that's connected to it, starting with VS Code.

## Deliverable

launch.json template that works for N# projects.

## Implementation

Add to VS Code extension, auto-generate `.vscode/launch.json`:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Launch N#",
      "type": "coreclr",
      "request": "launch",
      "preLaunchTask": "build",
      "program": "${workspaceFolder}/bin/Debug/net10.0/YourApp.dll",
      "args": [],
      "cwd": "${workspaceFolder}",
      "console": "internalConsole",
      "stopAtEntry": false
    },
    {
      "name": "Attach to Process",
      "type": "coreclr",
      "request": "attach"
    }
  ]
}
```

**tasks.json:**
```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "build",
      "command": "dotnet",
      "type": "process",
      "args": ["build"],
      "problemMatcher": "$msCompile"
    }
  ]
}
```

## Extension Changes

Add command to generate debug config:

```typescript
vscode.commands.registerCommand('nsharp.generateDebugConfig', () => {
    const config = generateLaunchJson();
    const vscodePath = path.join(vscode.workspace.rootPath, '.vscode');
    fs.mkdirSync(vscodePath, { recursive: true });
    fs.writeFileSync(path.join(vscodePath, 'launch.json'), config);
});
```

## Done When

- [x] Breakpoints work
- [x] Step through works (F10/F11)
- [x] Watch window shows variables
- [x] Call stack visible
