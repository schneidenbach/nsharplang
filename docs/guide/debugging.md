# Debugging N# Code

The VS Code extension supports project-level run and debug for executable N# projects.

## Requirements

- Install the N# VS Code extension.
- Install the Microsoft C# extension (`ms-dotnettools.csharp`). N# uses its CoreCLR debugger for .NET process debugging.
- Open a folder that contains `project.yml`.

## Run

Use **N#: Run Project** from the command palette, or run the `nsharp: run` task. This executes `nlc run` in the project folder and uses the normal IL backend.

## Debug

Press F5 in a `.nl` file, or use **N#: Debug Project** from the command palette.

For debugging, the extension:

1. Exports a temporary C# debug bundle to `.nsharp/debug`.
2. Builds that exported project with `dotnet build`.
3. Starts a CoreCLR debug session against the generated Debug assembly.

The exported C# contains `#line` mappings back to the original `.nl` files, so breakpoints set in `.nl` files can bind through the generated PDB.

The generated files are build artifacts. Do not edit them; edit the `.nl` sources and debug again.

## Launch Configuration

You usually do not need a `launch.json`. If you want one, create a configuration like this:

```json
{
  "type": "nsharp",
  "request": "launch",
  "name": "Launch N# Project",
  "project": "${workspaceFolder}",
  "args": [],
  "cwd": "${workspaceFolder}",
  "console": "integratedTerminal",
  "stopAtEntry": false
}
```

Project configuration still belongs in `project.yml`; do not add build settings to a hand-authored `.csproj`.

## Limits

Libraries are not directly launchable. Open or configure an executable project that references the library.

The debug path depends on the C# export surface. If a project uses a new N# feature before the C# exporter supports it, `nlc run` can still work while F5 fails during the temporary debug export.
