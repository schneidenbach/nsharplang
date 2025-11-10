# N# Quick Start

**NO XML. NO BULLSHIT. JUST CODE.**

## Install (Local Development)

```bash
# Clone the repo
git clone <repo-url>
cd NewCLILang

# Build the CLI
dotnet build src/Cli/Cli.csproj
```

## Create Your First Project

```bash
# Create a directory
mkdir ~/MyApp
cd ~/MyApp

# Create project.yml
cat > project.yml <<'EOF'
name: MyApp
version: 1.0.0
entry: Program.nl
outputType: exe
targetFramework: net9.0
EOF

# Create your code
cat > Program.nl <<'EOF'
func main() {
    print "Hello, N#!"
}
EOF
```

**That's it. Your directory has:**
```
MyApp/
├── project.yml
└── Program.nl
```

## Build and Run

```bash
# Build (generates .csproj, builds, deletes .csproj)
dotnet run --project /path/to/NewCLILang/src/Cli/Cli.csproj -- build

# Run (generates .csproj, builds, runs, deletes .csproj)
dotnet run --project /path/to/NewCLILang/src/Cli/Cli.csproj -- run
```

**After build, your directory STILL only has:**
```
MyApp/
├── project.yml
├── Program.nl
├── bin/           # Build output
└── obj/           # Build artifacts
```

**NO .csproj, NO global.json, NO NuGet.config files remain!**

## How It Works

1. You run `nsharp build` or `nsharp run`
2. CLI auto-generates:
   - `{ProjectName}.csproj` (tells MSBuild to use N# SDK)
   - `global.json` (points to local SDK)
   - `NuGet.config` (points to local packages)
3. Calls `dotnet build` (MSBuild SDK compiles your .nl files)
4. **Deletes ALL generated files** when done

Your source directory stays clean - just `.yml` and `.nl` files!

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

## Future: ONE COMMAND Install

Once we publish to NuGet (Task 044), this becomes even simpler:

```bash
# ONE COMMAND install
dotnet tool install -g nsharp

# Create and run projects
nsharp new MyApp
cd MyApp
nsharp build
nsharp run
```

No path needed, no manual builds - just `nsharp` command globally available.

## Why This Approach?

**You wanted:** Just `project.yml` + `.nl` files, nothing else
**We deliver:** Exactly that - XML files auto-deleted after every build

MSBuild requires a `.csproj` entry point, but you never have to see it or edit it. It's created and destroyed automatically.

**This is "Go for .NET"** - pragmatic, clean, no XML nonsense.
