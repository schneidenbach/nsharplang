# Publishing N# to NuGet

This document describes how to publish N# SDK and templates to NuGet.org.

## Prerequisites

1. **NuGet API Key**: Get your API key from [nuget.org](https://www.nuget.org/account/apikeys)
2. **NuGet Account**: You need an account on nuget.org
3. **Package ID Ownership**: Ensure you own the package IDs:
   - `Microsoft.NET.Sdk.NSharp`
   - `NSharp.Templates`

## Packages

N# consists of two NuGet packages:

### 1. Microsoft.NET.Sdk.NSharp

MSBuild SDK that enables building N# projects with `dotnet build`.

**Contains:**
- SDK props and targets files
- MSBuild tasks (`NSharp.Build.Tasks.dll`)
- N# compiler (`Compiler.dll`)
- Dependencies (YamlDotNet, MSBuild assemblies)

**Installation:** Automatically downloaded when users build projects with `<Project Sdk="Microsoft.NET.Sdk.NSharp" />`

### 2. NSharp.Templates

Templates for `dotnet new` command.

**Contains:**
- Console app template (`nsharp-console`)
- (Future: webapi, classlib, etc.)

**Installation:** `dotnet new install NSharp.Templates`

## Build Packages Locally

Run the pack script:

```bash
./pack-nuget.sh
```

This will:
1. Build `NSharp.Build.Tasks` in Release mode
2. Pack `Microsoft.NET.Sdk.NSharp` SDK
3. Pack `NSharp.Templates`
4. Output packages to `artifacts/nuget/`

**Output:**
- `artifacts/nuget/Microsoft.NET.Sdk.NSharp.1.0.0.nupkg` (~723KB)
- `artifacts/nuget/NSharp.Templates.1.0.0.nupkg` (~3.4KB)

## Test Packages Locally

Before publishing, test the packages locally:

### 1. Install Templates Locally

```bash
dotnet new uninstall NSharp.Templates  # Uninstall if already installed
dotnet new install artifacts/nuget/NSharp.Templates.1.0.0.nupkg
```

### 2. Add Local Package Source

Create a test directory and add the local NuGet source:

```bash
mkdir -p /tmp/nsharp-test
cd /tmp/nsharp-test

# Add local package source
dotnet nuget add source /Users/claude/Repos/NewCLILang/artifacts/nuget \
  --name NSharpLocal
```

### 3. Create Test Project

```bash
dotnet new nsharp-console -o TestApp
cd TestApp
```

### 4. Update SDK Reference (for local testing)

Edit the `global.json` to use a local path or update the .csproj to reference the local SDK:

```json
{
  "msbuild-sdks": {
    "Microsoft.NET.Sdk.NSharp": "1.0.0"
  }
}
```

Then add the local package source to `NuGet.config`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <packageSources>
    <add key="NSharpLocal" value="/Users/claude/Repos/NewCLILang/artifacts/nuget" />
  </packageSources>
</configuration>
```

### 5. Build and Run

```bash
dotnet build
dotnet run
```

**Expected output:** `Hello, N#!`

### 6. Clean Up

```bash
cd /tmp
rm -rf nsharp-test
dotnet nuget remove source NSharpLocal
```

## Publish to NuGet.org

⚠️ **Warning:** Once published, packages cannot be deleted, only unlisted!

### 1. Set API Key

```bash
export NUGET_API_KEY=your_api_key_here
```

### 2. Run Publish Script

```bash
./publish-nuget.sh
```

This will:
1. Verify packages exist
2. Push `Microsoft.NET.Sdk.NSharp.1.0.0.nupkg` to NuGet.org
3. Push `NSharp.Templates.1.0.0.nupkg` to NuGet.org

### 3. Verify on NuGet.org

Check that packages appear at:
- https://www.nuget.org/packages/Microsoft.NET.Sdk.NSharp
- https://www.nuget.org/packages/NSharp.Templates

**Note:** Packages may take a few minutes to be indexed and searchable.

## Version Updates

To publish a new version:

1. Update version in `.csproj` files:
   - `sdk/Microsoft.NET.Sdk.NSharp/Sdk/Microsoft.NET.Sdk.NSharp/Microsoft.NET.Sdk.NSharp.csproj`
   - `templates/NSharp.Templates.csproj`

2. Update version references in templates:
   - `templates/nsharp-console/global.json`

3. Rebuild packages:
   ```bash
   ./pack-nuget.sh
   ```

4. Test locally

5. Publish:
   ```bash
   ./publish-nuget.sh
   ```

## Manual Publishing (Alternative)

If you prefer not to use the scripts:

```bash
# Pack SDK
cd sdk/Microsoft.NET.Sdk.NSharp/Sdk/Microsoft.NET.Sdk.NSharp
dotnet pack -c Release -o ../../../../artifacts/nuget

# Pack Templates
cd templates
dotnet pack -c Release -o ../artifacts/nuget

# Publish SDK
dotnet nuget push artifacts/nuget/Microsoft.NET.Sdk.NSharp.1.0.0.nupkg \
  --api-key $NUGET_API_KEY \
  --source https://api.nuget.org/v3/index.json

# Publish Templates
dotnet nuget push artifacts/nuget/NSharp.Templates.1.0.0.nupkg \
  --api-key $NUGET_API_KEY \
  --source https://api.nuget.org/v3/index.json
```

## Troubleshooting

### Package already exists

If you get "Package already exists" error, you need to increment the version number.

### SDK not found when building

Ensure:
1. `global.json` specifies correct SDK version
2. NuGet package source includes nuget.org
3. Package has been indexed (wait a few minutes)

### Templates not showing up

```bash
# Clear template cache
dotnet new --debug:reinit

# List installed templates
dotnet new list
```

## Post-Publication

After publishing, update:

1. **README.md** - Add NuGet badges:
   ```markdown
   [![NuGet SDK](https://img.shields.io/nuget/v/Microsoft.NET.Sdk.NSharp.svg)](https://www.nuget.org/packages/Microsoft.NET.Sdk.NSharp/)
   [![NuGet Templates](https://img.shields.io/nuget/v/NSharp.Templates.svg)](https://www.nuget.org/packages/NSharp.Templates/)
   ```

2. **Documentation** - Update installation instructions to use NuGet

3. **GitHub Release** - Create a release tag matching the version

## Support

If you encounter issues:
- Check [NuGet documentation](https://learn.microsoft.com/en-us/nuget/)
- Check [MSBuild SDK documentation](https://learn.microsoft.com/en-us/visualstudio/msbuild/how-to-use-project-sdk)
- Review package contents: `unzip -l package.nupkg`
