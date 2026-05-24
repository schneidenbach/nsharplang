# N# Quick Start

**Project.yml-first, csproj-free N# projects. `nlc` generates a minimal `*.g.csproj` build artifact when needed.**

## Install N#

```bash
curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash && . "$HOME/.nsharp/env"
nlc doctor
```

For contributor source builds, clone the repo and run `./scripts/setup-local.sh`; public users should use the one-line installer.
The local setup script installs the repo-built `nlc` and `nsharp-lsp` tools from the local feed and adds `~/.dotnet/tools` to future shells through `~/.nsharp/env`.

## Create Your First Project

```bash
nlc new MyApp
cd MyApp
```

**Your project has:**
```
MyApp/
├── NuGet.config
├── global.json
├── project.yml
└── Program.nl
```

## Build and Run

```bash
nlc build
nlc run
```

From a source checkout, `./scripts/setup-local.sh` makes `nlc` the normal path. For compiler debugging before reinstalling the local tool, run the CLI project directly:

```bash
dotnet run --project /path/to/nsharplang/src/NSharpLang.Cli/Cli.csproj -- build
dotnet run --project /path/to/nsharplang/src/NSharpLang.Cli/Cli.csproj -- run
```

Output:
```text
Hello, N#!
```

## How It Works

1. `nlc build` reads `project.yml`
2. The compiler discovers `.nl` files and emits IL directly into the build output assembly
3. `nlc run` launches the emitted assembly and runtime assets
4. VS Code tasks use `nlc build`, `nlc run`, and `nlc test`; verify the extension against the current checkout before treating IDE workflows as launch proof

## What You Can Do

### Simple Console App
```n#
func main() {
    print "Hello!"
}
```

### With Dependencies
**project.yml:**
```yaml
name: MyApp
version: 1.0.0
outputType: exe
targetFramework: net10.0

dependencies:
  - nuget: Newtonsoft.Json
    version: 13.0.3
```

**Program.nl:**
```n#
import Newtonsoft.Json

func main() {
    obj := new { Name = "Alice", Age = 30 }
    json := JsonConvert.SerializeObject(obj)
    print json
}
```

### String Enums
```n#
enum Status {
    Active = "active",
    Pending = "pending",
    Completed = "completed"
}

func main() {
    status := Status.Active
    print status  // Output: active
}
```

### ASP.NET Core Web API
**project.yml:**
```yaml
name: MyApi
version: 1.0.0
outputType: exe
targetFramework: net10.0
sdk: Microsoft.NET.Sdk.Web

dependencies:
  - framework: Microsoft.AspNetCore.App
```

**Program.nl:**
```n#
import Microsoft.AspNetCore.Builder

func main() {
    builder := WebApplication.CreateBuilder([])
    app := builder.Build()

    app.MapGet("/", () => "Hello from N#!")

    app.Run()
}
```

## Single-File CLI Workflow

If you want to compile a loose `.nl` file directly:

```bash
dotnet run --project /path/to/nsharplang/src/NSharpLang.Cli/Cli.csproj -- run Program.nl
```

That path is useful for experiments, but the recommended workflow is template-generated projects plus `nlc build`, `nlc run`, and the VS Code N# tasks after local verification. The extension respects `nsharp.cli.path` when invoking `nlc`. F5/debugging is intentionally hidden until it is backed by a real N# debugger workflow.
