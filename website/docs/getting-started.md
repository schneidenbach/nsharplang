---
sidebar_label: Getting Started
title: Getting Started
---

# Getting Started with N#

This guide takes you from zero to running N# code in under 5 minutes.

## Prerequisites

- [.NET SDK 9.0+](https://dotnet.microsoft.com/download/dotnet/9.0) installed
- A terminal (bash, zsh, PowerShell)
- Optionally, [VS Code](https://code.visualstudio.com/) with the N# extension

Verify your .NET installation:

```bash
dotnet --version
# Should show 9.0.x or higher
```

## Install N# Templates

```bash
dotnet new install NSharpLang.Templates
```

This assumes `NSharpLang.Templates` is available from your configured repo/private package source. Public package availability should be verified for the target release before publishing this as a general install path.

## Create Your First Project

```bash
dotnet new nsharp-console -o MyApp
cd MyApp
```

Your project looks like this:

```
MyApp/
├── MyApp.csproj      # Minimal — just one line, don't edit this
├── NuGet.config       # Package sources
├── global.json        # SDK version pin
├── project.yml        # All project configuration lives here
└── Program.nl         # Your N# code
```

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
dotnet build
dotnet run
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
dotnet run
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

All configuration lives in `project.yml` — never edit the `.csproj` directly.

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

1. Open VS Code
2. Go to Extensions (Cmd+Shift+X / Ctrl+Shift+X)
3. Search for **"nsharp"**
4. Click **Install**

You get:
- Syntax highlighting
- IntelliSense (autocomplete)
- Real-time error diagnostics
- Format on save

Open your project folder in VS Code and start editing `.nl` files.

## How It Works

When you run `dotnet build`:

1. The minimal `.csproj` loads the N# MSBuild SDK
2. The SDK reads `project.yml` for project settings
3. All `.nl` files are transpiled to C# (under `obj/`)
4. The .NET compiler builds the generated C# into an executable

Most project workflows hide intermediate generated artifacts; use explicit export/debug flags when you need to inspect them.

## Next Steps

- **[Language Tour](language-tour.md)** — Learn the main implemented language surfaces with runnable examples
- **[For C# Developers](for-csharp-developers.md)** — Side-by-side syntax comparison
- **[For Go Developers](for-go-developers.md)** — How Go concepts map to N#
- **[Examples](/examples)** — Browse curated examples; verify gates before using them as release evidence
