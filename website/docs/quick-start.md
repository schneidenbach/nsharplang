---
sidebar_label: Quick Start
title: Quick Start
---

# N# Quick Start

**NO XML. NO BULLSHIT. JUST CODE.**

## Install (Local Development)

```bash
curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash
nlc doctor
```

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

Output:
```text
Hello, N#!
```

## How It Works

1. `nlc build` reads `project.yml`
2. `nlc` resolves project, framework, and NuGet references natively
3. The compiler emits IL directly for the project assembly
4. Runtime assets are written to stable `bin/<configuration>/<targetFramework>/` output paths

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

That path is useful for experiments, but the recommended workflow is template-generated projects plus `nlc build`, `nlc run`, and `nlc test`.
