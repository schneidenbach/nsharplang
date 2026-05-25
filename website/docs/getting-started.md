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

`nlc doctor` checks the CLI, SDK/template restore path, language server, and the VS Code extension when the `code` CLI is available. The installer also writes `~/.nsharp/env` and updates common shell profiles so new terminals can find `nlc` and the right .NET root.

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

All configuration lives in `project.yml` — never add build settings to a `.csproj`.

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

dependencies:
  - nuget: Newtonsoft.Json
    version: 13.0.3
```

Then use it in your code:

```n#
import Newtonsoft.Json

func main() {
    obj := new { Name: "Alice", Age: 30 }
    json := JsonConvert.SerializeObject(obj)
    print json
}
```

## VS Code Setup

The installer runs `code --install-extension nsharp.nsharp` when the `code` CLI is on PATH. If `code` was not available during install, enable it from VS Code with **Shell Command: Install 'code' command in PATH**, then run:

```bash
code --install-extension nsharp.nsharp
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

Most project workflows hide intermediate generated artifacts; use explicit export/debug flags when you need to inspect them.

## Next Steps

- **[Language Tour](language-tour.md)** — Learn the main implemented language surfaces with runnable examples
- **[For C# Developers](for-csharp-developers.md)** — Side-by-side syntax comparison
- **[For Go Developers](for-go-developers.md)** — How Go concepts map to N#
- **[Examples](/examples)** — Browse curated examples; verify gates before using them as release evidence
