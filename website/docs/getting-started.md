---
sidebar_label: Getting Started
title: Getting Started
---

# Getting Started with N#

This guide takes you from zero to running N# code in under 5 minutes.

## Prerequisites

- [.NET SDK 10.0+](https://dotnet.microsoft.com/download/dotnet/10.0) installed
- macOS/Linux shell with `bash` for the one-line installer
- Optionally, [VS Code](https://code.visualstudio.com/) with the `code` CLI on PATH so the installer can add editor tooling

## Install N#

Use the one public install command:

```bash
curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash && . "$HOME/.nsharp/env"
```

Then verify the installed toolchain:

```bash
nlc --version
nlc doctor
```

`nlc doctor` checks the CLI, the N# package cache of the install it belongs to (`$NSHARP_INSTALL_DIR/packages`, defaulting to `~/.nsharp/packages` — the same feed `nlc new` writes into projects), the template restore path, the language server, and the VS Code extension when the `code` CLI is available. The installer also writes `~/.nsharp/env` and updates common shell profiles so new terminals can find `nlc` and the right .NET root.

Windows gap: the canonical installer is bash-only in this release pass. Use WSL or translate the installer commands to PowerShell until a supported Windows installer exists.

## Create Your First Project

```bash
nlc new MyApp
cd MyApp
```

Your project looks like this:

```
MyApp/
├── NuGet.config       # Package sources
├── global.json        # SDK version pin
├── project.yml        # All project configuration lives here
└── Program.nl         # Your N# code
```

N# fresh projects are csproj-free. `nlc build`/`nlc run` read `project.yml` directly and do not generate MSBuild project files; don't add project settings to a hand-authored `.csproj`.

## Write Hello World

Open `Program.nl`. It already contains:

```n#
func main() {
    print "Hello, N#!"
}
```

That's a complete program. No imports, no class wrappers, no semicolons.

## Build and Run

```bash
nlc build
nlc run
```

Output:

```text
Hello, N#!
```

## Make It Your Own

Edit `Program.nl`:

```n#
func main() {
    name := "World"
    print $"Hello, {name}!"

    numbers := [1, 2, 3, 4, 5]
    for num in numbers {
        print $"  {num}"
    }
}
```

Run it again:

```bash
nlc run
```

```text
Hello, World!
  1
  2
  3
  4
  5
```

## Project Configuration

All configuration lives in `project.yml` — never add build settings to a `.csproj`. The
[project.yml reference](./project-yml.md) lists every key and every dependency kind.

```yaml
name: MyApp
version: 1.0.0
entry: Program.nl
outputType: exe
targetFramework: net10.0
```

To add a NuGet dependency:

```yaml
name: MyApp
version: 1.0.0
entry: Program.nl
outputType: exe
targetFramework: net10.0

# Conditional-compilation symbols available to #if. DEBUG is also defined
# automatically for debug builds (omitted under `nlc build --release`), and
# extra symbols can be passed ad hoc with `nlc build --define FEATURE_X`.
defines:
  - FEATURE_X

dependencies:
  - nuget: Newtonsoft.Json
    version: 13.0.3
```

Dependencies can also be shared frameworks (`framework:`), other N# projects (`project:`) and
prebuilt assemblies (`dll:`); see [Dependencies](./project-yml.md#dependencies). Without any
dependencies, a project compiles against all of `Microsoft.NETCore.App`, the same base library
`dotnet build` uses, so types such as `IServiceProvider` or `ClaimsIdentity` need only their `import`;
see [What a project can see](./project-yml.md#what-a-project-can-see).

Then use it in your code:

```n#
import Newtonsoft.Json

func main() {
    obj := new { Name: "Alice", Age: 30 }
    json := JsonConvert.SerializeObject(obj)
    print json
}
```

### Language settings

The optional `language:` section changes how the compiler reads your code:

```yaml
language:
  profile: default          # or systems — see the Systems Profile guide
  asyncDefaultType: Task    # the task an unannotated async func returns: ValueTask (default) or Task
```

| Key | Values | Default | Effect |
|-----|--------|---------|--------|
| `profile` | `default`, `systems` | `default` | `systems` turns on the allocation and AOT policy checks described in [the Systems Profile](./systems.md). |
| `asyncDefaultType` | `ValueTask`, `Task` | `ValueTask` | The task an `async func` returns when it does not write one. `main`, overrides and interface implementations follow their own rule; see [Implicit Task Wrapping](./functions.md#implicit-task-wrapping). Web projects whose middleware or other convention-based methods must return `Task` usually want `Task`. |

Every `nlc` command, the language server and the MSBuild SDK read the same section, so a hover in
VS Code shows the same task type `nlc build` emits.

There is no `pooledAsync` key. An `async func` that returns `ValueTask` already completes without
allocating, so there is nothing for a pooled builder to recycle, and a `project.yml` that still sets
`pooledAsync` is refused with that reason. See [Implicit Task Wrapping](./functions.md#implicit-task-wrapping).

## VS Code Setup

When the `code` CLI is on PATH, the installer downloads `nsharp.vsix` from the latest GitHub Release, verifies it against the release's `SHA256SUMS`, and installs it with `code --install-extension`. The extension is not published to the VS Code Marketplace yet. If `code` was not available during install, enable it from VS Code with **Shell Command: Install 'code' command in PATH**, then re-run the installer:

```bash
curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash && . "$HOME/.nsharp/env"
nlc doctor --require-vscode
```

You get:
- Syntax highlighting
- IntelliSense (autocomplete, signature help, and overload browsing)
- Real-time error diagnostics
- Format on save

Open your project folder in VS Code and start editing `.nl` files.

## How It Works

When you run `nlc build`:

1. The CLI reads `project.yml` for project settings
2. The compiler resolves project, framework, and NuGet references natively
3. The compiler emits IL directly for the project assembly
4. The CLI writes runtime assets into stable `bin/<configuration>/<targetFramework>/` output paths

## Next Steps

- **[Language Tour](language-tour.md)** — Learn the main implemented language surfaces with runnable examples
- **[For Go Developers](for-go-developers.md)** — How Go concepts map to N#
- **[Examples](/examples)** — Browse curated examples; verify gates before using them as release evidence
