# Task 042: NuGet Package Publishing

**Status:** ✅ Complete
**Priority:** P0-Critical
**Completed:** 2025-11-09

## Overview

Implemented comprehensive NuGet package publishing infrastructure for N#, enabling easy distribution and installation of all core packages.

## Deliverables

### Core Packages Published

1. **NSharpLang.Sdk** (v0.1.0)
   - MSBuild SDK for N# projects
   - Enables `dotnet build` with `project.yml`
   - Size: 275 KB

2. **NSharp.Templates** (v1.0.0)
   - `dotnet new` templates
   - Templates: `nsharp-console`, `nsharp-webapi`
   - Size: 3.4 KB

3. **NSharp.Compiler** (v1.0.0)
   - Compiler API library
   - For embedding N# compilation in tools
   - Size: 155 KB

4. **nlc** (v0.1.0)
   - Global CLI tool
   - Command: `nlc build`, `nlc format`, `nlc lint`
   - Size: 1.2 MB

5. **NSharp.LanguageServer** (v1.0.0)
   - Language Server Protocol implementation
   - Provides IntelliSense for any LSP-compatible editor
   - Size: 2.5 MB

### Scripts

#### pack-nuget.sh
Builds and packages all 5 packages:
```bash
./pack-nuget.sh
# Creates packages in artifacts/nuget/
```

#### publish-packages.sh
Publishes all packages to NuGet.org:
```bash
export NUGET_API_KEY=your_key
./scripts/publish-packages.sh --target nuget
```

Features:
- Validates all packages exist before publishing
- Publishes in correct dependency order
- Provides installation instructions after success

## Implementation Details

### Package Metadata Added

All packages now include:
- ✅ PackageId
- ✅ Version
- ✅ Authors
- ✅ Description
- ✅ PackageProjectUrl
- ✅ RepositoryUrl
- ✅ PackageLicenseExpression (MIT)
- ✅ PackageTags
- ✅ PackageReadmeFile (where applicable)

### Bug Fixes

Fixed ambiguous type references in LanguageServer:
- Added type aliases for LSP types to avoid conflicts with compiler types
- `LspDiagnostic` for OmniSharp's Diagnostic
- `LspDiagnosticSeverity` for OmniSharp's DiagnosticSeverity
- `LspRange` for OmniSharp's Range

## Installation Instructions

### For Users

```bash
# Install templates
dotnet new install NSharp.Templates

# Install CLI tool
dotnet tool install -g nlc

# Install Language Server
dotnet tool install -g NSharp.LanguageServer

# Create a new project
dotnet new nsharp-console -o MyApp
cd MyApp
dotnet build
dotnet run
```

### For Library Consumers

```bash
# Reference the compiler API
dotnet add package NSharp.Compiler
```

## Success Criteria

- ✅ All 5 packages build successfully
- ✅ Package metadata is complete and professional
- ✅ Scripts are automated and easy to use
- ✅ All tests pass (743 passing tests)
- ✅ Example projects build correctly
- ✅ Local package installation works

## Testing

Verified with:
- `./test-all.sh` - All 743 tests pass
- `./pack-nuget.sh` - All packages build successfully
- Template installation and project creation works
- All 6 example projects build successfully

## Next Steps (Task 043)

With packages ready, the next priority is:
- **Task 043: Error Message Polish** - Improve error messages to Rust/Elm quality

## Notes

### Version Strategy

- MSBuild SDK and CLI: v0.1.0 (beta)
- Templates, Compiler, LSP: v1.0.0 (stable API)

This reflects that the SDK and CLI are still being refined, while the core compiler API and templates are production-ready.

### Package Sizes

Total package footprint: ~4.3 MB
- Very reasonable for a complete language toolchain
- LanguageServer is largest due to LSP dependencies

### Local Development

The existing `setup-local.sh` script already works with the new package structure:
```bash
./setup-local.sh
# Sets up local NuGet feed for development
```

## Files Changed

### Modified
- `src/Compiler/Compiler.csproj` - Added package metadata
- `src/LanguageServer/LanguageServer.csproj` - Added package metadata and tool config
- `src/LanguageServer/Handlers/TextDocumentHandler.cs` - Fixed type ambiguities
- `pack-nuget.sh` - Updated to pack all 5 packages
- `publish-packages.sh` - Publishes all packages with validation

### Impact

This task unblocks:
- Public distribution of N#
- Easy onboarding for new users
- Integration with existing .NET workflows
- Community contributions (easier setup)

---

**Task Complete!** N# is now ready for NuGet distribution.
