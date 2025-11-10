# Task 044: Publish SDK to NuGet

**Effort:** Small (3-4 hours)
**Depends:** Tasks 042, 043
**Ships:** SDK installable via NuGet

## Goal

Package and publish SDK + templates to NuGet.org.

## Deliverable

Published NuGet packages that users can install.

## Packages

1. **NSharpLang.Sdk** - MSBuild SDK
2. **NSharp.Templates** - dotnet new templates

## Implementation

**Pack SDK:**
```bash
cd sdk/NSharpLang.Sdk
dotnet pack -c Release
```

**Pack Templates:**
```bash
cd templates
dotnet pack NSharp.Templates.csproj -c Release
```

**Publish:**
```bash
dotnet nuget push NSharpLang.Sdk.1.0.0.nupkg \
  --api-key $NUGET_API_KEY \
  --source https://api.nuget.org/v3/index.json

dotnet nuget push NSharp.Templates.1.0.0.nupkg \
  --api-key $NUGET_API_KEY \
  --source https://api.nuget.org/v3/index.json
```

## Testing

```bash
# Install templates
dotnet new install NSharp.Templates

# Create new project
dotnet new nsharp-console -o TestApp
cd TestApp

# Build (SDK auto-downloaded)
dotnet build
dotnet run
```

## Done When

- [ ] Packages published to NuGet.org
- [ ] Fresh install works
- [ ] README with install instructions
- [ ] Version badges added
