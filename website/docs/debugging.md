# Debugging N# Code

The VS Code extension supports project-level run and debug for executable N# projects.

## Requirements

- Install the N# VS Code extension.
- Install a CoreCLR debugger extension for .NET process debugging.
- Open a folder that contains `project.yml`.

## Run

Use **N#: Run Project** from the command palette, or run the `nsharp: run` task. This executes `nlc run` in the project folder and uses the normal IL backend.

## Debug

Press F5 in a `.nl` file, or use **N#: Debug Project** from the command palette.

Debug support is tied to the IL toolchain. Generated-source debug bundles are not a supported product path.

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
