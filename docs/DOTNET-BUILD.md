# Using N# with dotnet build

N# now supports native `dotnet build` integration through an MSBuild SDK.

## Current Status

✅ **MSBuild SDK implemented** - `dotnet build` works with `project.yml`
⏳ **NuGet publishing** - Not yet published (coming soon in Task 044)

## How to Use (Local Development)

### 1. Create a project with project.yml

```bash
mkdir MyApp
cd MyApp
```

**project.yml:**
```yaml
name: MyApp
version: 1.0.0
entry: Program.nl
outputType: exe
targetFramework: net9.0
```

**Program.nl:**
```n#
func main() {
    print "Hello from N#!"
}
```

### 2. Create minimal .csproj file

**MyApp.csproj:**
```xml
<Project Sdk="Microsoft.NET.Sdk.NSharp">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net9.0</TargetFramework>
  </PropertyGroup>
</Project>
```

### 3. Configure local SDK (for now)

**global.json:**
```json
{
  "sdk": {
    "version": "9.0.100"
  },
  "msbuild-sdks": {
    "Microsoft.NET.Sdk.NSharp": "0.1.0"
  }
}
```

**NuGet.config:**
```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <clear />
    <add key="nuget.org" value="https://api.nuget.org/v3/index.json" />
    <add key="local" value="PATH_TO_REPO/src/Microsoft.NET.Sdk.NSharp/bin/Debug" />
  </packageSources>
</configuration>
```

Replace `PATH_TO_REPO` with the actual path to this repository.

### 4. Build and run

```bash
dotnet build
dotnet run
```

Output:
```
Hello from N#!
```

## What Happens Behind the Scenes

1. MSBuild finds the `Microsoft.NET.Sdk.NSharp` SDK
2. SDK auto-detects `project.yml` in the project directory
3. SDK auto-discovers all `.nl` files (excluding `.tests.nl`)
4. N# compiler transpiles `.nl` files to C# in `obj/nsharp/` folder
5. Generated C# files are automatically added to the C# compilation
6. Standard .NET build process takes over

## Future: ONE COMMAND Install (Task 044)

Once we publish to NuGet, users will just:

```bash
# Install N# workload
dotnet workload install nsharp

# Create projects (no global.json/NuGet.config needed!)
dotnet new nsharp-console -o MyApp
cd MyApp
dotnet build
dotnet run
```

No XML config, no manual SDK references - just works!

## Benefits

- ✅ **No XML project files needed** - just `project.yml`
- ✅ **Auto-discovery** - all `.nl` files compiled automatically
- ✅ **Native dotnet CLI** - `dotnet build`, `dotnet run`, `dotnet test` all work
- ✅ **Solution support** - works in multi-project solutions
- ✅ **IDE integration** - Visual Studio, Rider, VS Code (once plugins updated)
- ✅ **CI/CD friendly** - standard .NET build pipelines just work

## Files Structure

```
src/Build/
├── NSharp.Build.Tasks/           # MSBuild task that compiles .nl files
│   ├── NSharpCompile.cs           # The compilation task
│   └── NSharp.Build.targets       # Standalone targets (old approach)
└── Microsoft.NET.Sdk.NSharp/     # MSBuild SDK package
    ├── Sdk/
    │   ├── Sdk.props              # Property defaults
    │   └── Sdk.targets            # Compilation targets
    └── Microsoft.NET.Sdk.NSharp.csproj  # SDK package definition
```

## See Also

- **Task 041** (completed): MSBuild compilation task
- **Task 042** (completed): MSBuild SDK with project.yml
- **Task 043** (next): `dotnet new` templates
- **Task 044** (next): Publish SDK to NuGet
