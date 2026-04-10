# N# Quick Start

**NO XML. NO BULLSHIT. JUST CODE.**

## Install (Local Development)

```bash
git clone <repo-url>
cd nsharplang
./scripts/setup-local.sh
```

## Create Your First Project

```bash
dotnet new nsharp-console -o MyApp
cd MyApp
```

**Your project has:**
```
MyApp/
├── MyApp.csproj
├── NuGet.config
├── global.json
├── project.yml
└── Program.nl
```

## Build and Run

```bash
dotnet build
dotnet run
```

Output:
```text
Hello, N#!
```

## How It Works

1. `dotnet build` loads the minimal `.csproj`
2. `NSharpLang.Sdk` reads `project.yml`
3. The SDK discovers `.nl` files and the compiler emits IL directly into the build output assembly
4. The normal .NET toolchain runs the emitted assembly and runtime assets

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
targetFramework: net9.0

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
targetFramework: net9.0
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

That path is useful for experiments, but the recommended workflow is template-generated projects plus `dotnet build` and `dotnet run`.
