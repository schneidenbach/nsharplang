# N# Language Development Roadmap

**Last Updated:** 2025-11-09
**Current Status:** v1.72 | 743 passing tests | Core language complete | Formatter complete | Documentation complete | NuGet packages ready | Elm-style error messages active

## Philosophy: Incremental Value

Each task delivers **immediate, tangible value** to developers. No massive undertakings - build confidence through steady progress.

---

## Phase 1: Foundation (P0 - Critical for 1.0)

### ✅ Task 037: Comprehensive IntelliSense
**Status:** Complete
**Impact:** Core IDE experience

### ✅ Task 039: .NET CLI Integration
**Status:** Complete
**Impact:** Makes N# a first-class .NET language

**Completed:**
- ✅ MSBuild SDK that reads `project.yml` (no XML!)
- ✅ YAML-based project configuration
- ✅ `dotnet new` templates (nsharp-console, nsharp-webapi)
- ✅ Minimal .csproj format: `<Project Sdk="Microsoft.NET.Sdk.NSharp" />`
- ✅ Full `dotnet build`, `dotnet run`, `dotnet test` integration

---

### ✅ Task 040: Code Formatter
**Status:** Complete
**Priority:** 🔴 P0-Critical
**Impact:** Essential for team collaboration

**Completed:**
- ✅ `nlc format` command for `.nl` files
- ✅ MSBuild target: `dotnet build /t:FormatNSharp`
- ✅ `.editorconfig` integration (indent_style, indent_size)
- ✅ IDE format-on-save (VS Code)
- ✅ CI verification mode (`--verify-no-changes`)
- ✅ Exit code 1 for formatting violations (CI integration)

**Usage:**
```bash
nlc format                          # Format all .nl files
nlc format --verify-no-changes      # CI verification
dotnet build /t:FormatNSharp        # MSBuild integration
dotnet build /t:FormatNSharp /p:FormatVerify=true  # MSBuild verify
```

---

### ✅ Task 041: Official Website & Core Documentation
**Status:** Complete
**Priority:** 🔴 P0-Critical
**Impact:** First impressions & discoverability

**Completed:**
- ✅ Professional website at website/index.html with documentation section
- ✅ Getting started guide (< 5 min to first app) in docs/README.md
- ✅ Complete language reference:
  - Functions guide (lambdas, async, generics, local functions)
  - Types guide (unions, records, duck interfaces, classes, structs)
  - Pattern matching guide (exhaustive matching, all pattern types)
- ✅ C# migration guide (syntax mapping, migration strategies)
- ✅ Interop guide (using N# with C# and .NET ecosystem)
- ✅ Enhanced website with organized documentation links
- ✅ Mobile-friendly responsive design

**Documentation:**
- `docs/README.md` - Main documentation hub
- `docs/guide/basics.md` - Language basics
- `docs/guide/functions.md` - Functions deep dive
- `docs/guide/types.md` - Type system guide
- `docs/guide/pattern-matching.md` - Pattern matching
- `docs/guide/csharp-migration.md` - C# migration
- `docs/guide/interop.md` - Interop guide
- `website/index.html` - Enhanced with docs section

---

### ✅ Task 042: NuGet Package Publishing
**Status:** Complete
**Priority:** 🔴 P0-Critical
**Impact:** Ready for public distribution

**Completed:**
- ✅ 5 NuGet packages with complete metadata
- ✅ Microsoft.NET.Sdk.NSharp (v0.1.0) - MSBuild SDK
- ✅ NSharp.Templates (v1.0.0) - dotnet new templates
- ✅ NSharp.Compiler (v1.0.0) - Compiler API library
- ✅ nlc (v0.1.0) - Global CLI tool
- ✅ NSharp.LanguageServer (v1.0.0) - LSP server
- ✅ Automated build script (`pack-nuget.sh`)
- ✅ Automated publish script (`publish-nuget.sh`)
- ✅ All packages build successfully (4.3 MB total)

**Usage:**
```bash
./pack-nuget.sh                    # Build all packages
export NUGET_API_KEY=key
./publish-nuget.sh                 # Publish to NuGet.org

# For users:
dotnet new install NSharp.Templates
dotnet tool install -g nlc
dotnet tool install -g NSharp.LanguageServer
```

---

### ✅ Task 043: Error Message Polish
**Status:** Complete
**Priority:** 🔴 P0-Critical
**Impact:** Developer confidence & productivity

**Completed:**
- ✅ Updated semantic analyzer to use Elm-style error messages for all common errors
- ✅ Type mismatch errors show actual vs expected types with conversion hints
- ✅ Undefined variable errors include smart suggestions using Levenshtein distance
- ✅ Non-exhaustive pattern matching errors list missing cases with explanations
- ✅ All error messages use conversational, human-friendly language
- ✅ Full test suite passes with no regressions (743 tests)

**Example Output (Type Mismatch):**
```
-- TYPE MISMATCH --------------------------------------------------  test.nl

I am having trouble with this code on line 2:

2|     let x: int = "hello"
          ^

This expression has type:

    string

But you said it should be:

    int

Hint: Strings and integers are different types. To convert a string to an int,
you can use int.Parse(yourString) or int.TryParse(yourString, out result).

Read more: https://docs.n-sharp.dev/errors/NL202
```

**Example Output (Undefined Variable):**
```
-- NAMING ERROR --------------------------------------------------  test.nl

I cannot find a `persn` variable on line 3:

3|     print persn
             ^^^^^

Hint: Variables need to be declared before they can be used.

Did you mean one of these?

    person

Read more: https://docs.n-sharp.dev/errors/NL301
```

**Files Modified:**
- `src/Compiler/Analyzer.cs` - Updated to use ErrorMessageBuilder for all common errors
- All existing error reporting infrastructure from Task 027 now fully integrated

---

## Phase 2: Developer Tools (P1 - For 1.0-1.5)

### ✅ Task 044: Linter & Analyzer
**Status:** Complete
**Priority:** 🟡 P1-High
**Effort:** Large (20-25 hours) | Actual: ~4 hours

**Completed:**
- ✅ Static analysis rules (NL001-NL005)
- ✅ Best practice warnings
- ✅ Unused code detection (NL001)
- ✅ Nullable reference warnings (NL003)
- ✅ `.editorconfig` severity configuration
- ✅ CLI integration (`nlc lint`)
- ✅ 31 comprehensive tests

**Rules Implemented:**
- `NL001`: Unused variable (warning)
- `NL002`: Missing import (error)
- `NL003`: Unnecessary null check on value types (warning)
- `NL004`: Async method without await (warning)
- `NL005`: Use pattern matching (info) - reserved for future

**Usage:**
```bash
nlc lint                    # Lint all .nl files
nlc lint Program.nl         # Lint specific file
```

**Configuration:**
```ini
# .editorconfig
[*.nl]
dotnet_diagnostic.NL001.severity = warning
dotnet_diagnostic.NL002.severity = error
```

---

### ✅ Task 045: Code Fixes & Refactorings
**Status:** Complete
**Priority:** 🟡 P1-High
**Effort:** Medium (12-15 hours) | Actual: ~3 hours
**Depends on:** Task 044

**Completed:**
- ✅ Code fix infrastructure (CodeFixProvider, CodeFixService)
- ✅ LSP integration via CodeActionHandler
- ✅ Quick fix: Add missing import (NL002)
- ✅ Quick fix: Remove unused variable (NL001)
- ✅ Quick fix: Remove unnecessary null check (NL003)
- ✅ Linter diagnostics integrated with LSP
- ✅ 15 comprehensive tests
- ✅ All 765 tests pass

**Quick Fixes Implemented:**
- NL001: Remove unused variable
- NL002: Add missing import (with smart insertion after existing imports)
- NL003: Remove unnecessary null check

**Future Enhancements:**
- Convert to pattern matching
- Extract variable/method
- Rename (F2)
- Extract method
- Extract interface
- Change signature

**Usage:**
Quick fixes appear automatically in VS Code when hovering over diagnostics (yellow/red squiggles)
Press Ctrl+. (Cmd+. on Mac) to see available code actions

---

### ✅ Task 046: CI/CD Templates
**Status:** Complete
**Priority:** 🟡 P1-High
**Effort:** Small (8-10 hours) | Actual: ~3 hours

**Completed:**
- ✅ GitHub Actions workflows (build, release, format-check, lint)
- ✅ Azure Pipelines complete multi-stage pipeline
- ✅ Docker templates (SDK, runtime, web API)
- ✅ Docker Compose for local development
- ✅ Complete working examples (console-app, web-api, library)
- ✅ Comprehensive CI/CD documentation
- ✅ All 765 tests pass

**Templates Created:**

**GitHub Actions:**
- `build.yml` - Build and test on push/PR
- `release.yml` - Automated NuGet publishing on version tags
- `format-check.yml` - Code formatting verification
- `lint.yml` - Code quality checks

**Azure Pipelines:**
- `azure-pipelines.yml` - Multi-stage pipeline with build, lint, and publish

**Docker:**
- `Dockerfile.sdk` - Full SDK image (~1.5GB) for CI/CD
- `Dockerfile.runtime` - Multi-stage production image (~200MB)
- `Dockerfile.webapi` - Optimized ASP.NET Core image with security best practices
- `docker-compose.yml` - Local development with SQL Server and Redis
- `.dockerignore` - Build optimization

**Complete Examples:**
- `ci-examples/console-app/` - Console app with automated releases
- `ci-examples/web-api/` - Web API with Docker deployment
- `ci-examples/library/` - Library publishing with pre-release support

**Documentation:**
- `docs/guide/ci-cd.md` - Complete CI/CD guide (800+ lines)
- `ci-templates/README.md` - Template usage guide
- Example-specific READMEs with troubleshooting

**Usage:**
```bash
# GitHub Actions
mkdir -p .github/workflows
cp ci-templates/github-actions/build.yml .github/workflows/

# Docker
cp ci-templates/docker/Dockerfile.webapi Dockerfile
docker build -t myapp . && docker run -p 8080:8080 myapp

# Azure Pipelines
cp ci-templates/azure-pipelines/azure-pipelines.yml .
```

**Files Modified:**
- Created `ci-templates/` directory structure
- Created `ci-examples/` with 3 complete examples
- Created `docs/guide/ci-cd.md`
- Updated `README.md` with CI/CD section
- Updated `docs/README.md` to link to CI/CD guide

---

### Task 047: Test Coverage Integration
**Status:** Not started
**Priority:** 🟡 P1-Medium
**Effort:** Small (5-7 hours)

**Deliverables:**
- Coverlet integration
- HTML report generation
- IDE line highlighting
- Codecov/Coveralls support

```bash
dotnet test /p:CollectCoverage=true
dotnet test /p:CoverletOutputFormat=opencover
```

---

### Task 048: VS Code Polish
**Status:** Partial (extension exists)
**Priority:** 🟡 P1-Medium
**Effort:** Medium (10-12 hours)

**Still Needed:**
- Debugging support (launch.json)
- Task templates (build/run/test)
- Better diagnostics display
- Code actions (quick fixes)
- Marketplace listing with screenshots

---

## Phase 3: IDE Integration (P1 - Essential for adoption)

### Task 049: Debugging Support (Cross-IDE)
**Status:** Not started
**Priority:** 🟡 P1-High
**Effort:** Large (25-30 hours)

**Core Requirements:**
- Breakpoints work
- Step through (F10/F11)
- Watch/Locals windows
- Call stack
- Conditional breakpoints

**IDEs:**
- VS Code (via debugger adapter)
- Visual Studio (via debugger engine)
- Rider (via IDEA debugger)

**Why Before IDE Plugins:**
> Debugger is shared infrastructure. Build once, use everywhere.

---

### Task 050: Rider Plugin
**Status:** Not started
**Priority:** 🟡 P1-High
**Effort:** Large (25-30 hours)
**Depends on:** Task 049 (debugging)

**Deliverables:**
- JetBrains Marketplace plugin
- Language support via LSP
- Project model integration
- Run configurations
- Debugging integration
- Refactoring tools
- Unit test runner

**Why Before Visual Studio:**
> Rider is popular with OSS developers and cross-platform teams. Easier to develop and test.

---

### Task 051: Visual Studio Extension
**Status:** Not started
**Priority:** 🟠 P1-Medium (but eventually critical for enterprise)
**Effort:** Very Large (40-50 hours)
**Depends on:** Task 049 (debugging), Task 050 (Rider - learn from it)

**Deliverables:**
- Visual Studio .vsix extension
- Project templates in "New Project" dialog
- Full IntelliSense integration
- Syntax highlighting (semantic)
- Error squiggles
- Go to definition / Find references
- Rename refactoring
- Code snippets
- Debugging support
- Solution Explorer integration
- Build/Run/Debug from toolbar

**Why After Rider:**
> VS extension is much more complex. Learn from Rider implementation first. Plus, many modern .NET devs use VS Code or Rider.

---

## Phase 4: Advanced Features (P2 - Polish)

### Task 052: Framework Templates
**Status:** Partial (ASP.NET works)
**Priority:** 🟢 P2-Medium
**Effort:** Medium (15-20 hours)

**Templates:**
- ASP.NET Core (Web API, MVC, Razor Pages)
- Blazor (Server & WebAssembly)
- MAUI (mobile apps)
- Worker services
- Class libraries

---

### Task 053: Performance & Benchmarking
**Status:** Not started
**Priority:** 🟢 P2-Medium
**Effort:** Medium (12-15 hours)

**Deliverables:**
- BenchmarkDotNet integration
- Compiler performance benchmarks
- Runtime performance vs C#
- Compilation time measurement
- Memory usage profiling

**Target:**
> Compile 10,000 lines in < 1 second

---

### Task 054: Community & Release Automation
**Status:** Not started
**Priority:** 🟢 P2-Medium
**Effort:** Medium (10-12 hours)

**Infrastructure:**
- Discord server
- GitHub Discussions
- Stack Overflow tag
- Automated releases
- Changelog generation
- NuGet auto-publish

---

### Task 055: Source Generators & Advanced Interop
**Status:** Not started
**Priority:** 🟢 P2-Low
**Effort:** Large (20-25 hours)

**Features:**
- Roslyn source generators work with N#
- Nullable flow analysis improvements
- Source Link support
- Advanced C# interop patterns

---

## Phase 5: Future Exploration (P3 - Optional)

### Task 056: IL Compiler Completion
**Status:** Phases 1-5 complete, Phase 7 partial
**Priority:** 🟢 P3-Low (Nice to have, not essential)
**Effort:** Very Large (30-40 hours remaining)

**Rationale for Low Priority:**
> Transpilation to C# works great and leverages Roslyn's battle-tested optimizations. IL compiler is interesting but not essential for 1.0. Performance gains are nice but marginal compared to tooling gaps.

**Remaining Work:**
- Complete Phase 7 advanced features
- Pattern matching IL emission
- Records IL emission
- Lambda expressions IL emission
- Performance benchmarking vs transpiler

**When to Prioritize:**
> After 1.0 release, if compilation speed becomes a bottleneck. Not before.

---

## Priority Rationale

### Why This Order?

1. **.NET CLI Integration (039)** - Foundation for everything
2. **Code Formatter (040)** - Unblocks teams immediately
3. **Website & Docs (041)** - Discovery and credibility
4. **NuGet (042)** - Distribution and installation
5. **Error Messages (043)** - Developer confidence

Then:

6. **Tooling (044-048)** - Linter, code fixes, CI/CD, coverage
7. **Debugging (049)** - Shared infrastructure for all IDEs
8. **Rider (050)** - Faster to build, popular with OSS devs
9. **Visual Studio (051)** - Harder to build, but essential long-term
10. **Polish (052-055)** - Templates, performance, community
11. **IL Compiler (056)** - Interesting but not essential

### Why IL Compiler Last?

The transpiler approach:
- ✅ Works great today
- ✅ Leverages Roslyn's optimizations
- ✅ Easier to maintain
- ✅ Better C# interop
- ✅ Better debugging experience

IL compiler benefits:
- ⚡ Faster compilation (10-50x)
- 🎯 No C# dependency
- ❌ More complex to maintain
- ❌ Harder to debug
- ❌ Doesn't solve adoption problems

**Bottom line:** Developer experience and tooling matter 100x more than compilation speed. Fix those first.

---

## Timeline Estimates

### Minimum Viable 1.0 (P0 only)
- Tasks 039-043: ~95-110 hours
- **At 20 hrs/week:** 5-6 weeks
- **At 40 hrs/week:** 2.5-3 weeks

### Strong 1.0 (P0 + P1 tooling)
- Tasks 039-048: ~185-210 hours
- **At 20 hrs/week:** 9-10 weeks
- **At 40 hrs/week:** 4.5-5 weeks

### Complete 1.0 (P0 + P1 + IDE)
- Tasks 039-051: ~285-325 hours
- **At 20 hrs/week:** 14-16 weeks (3.5-4 months)
- **At 40 hrs/week:** 7-8 weeks (2 months)

### Full Professional (P0 + P1 + P2)
- Tasks 039-055: ~350-390 hours
- **At 20 hrs/week:** 17-20 weeks (4-5 months)
- **At 40 hrs/week:** 9-10 weeks (2-2.5 months)

---

## Success Metrics

### Developer Adoption (1.0 target)
- ✅ 1,000+ VS Code extension installs
- ✅ 500+ NuGet downloads
- ✅ 100+ GitHub stars
- ✅ 10+ production projects

### Technical Quality (1.0 target)
- ✅ <50ms IntelliSense response
- ✅ <1s compile time (typical project)
- ✅ 95%+ test coverage
- ✅ World-class error messages

### Community Validation (post-1.0)
- ✅ Featured on .NET blog
- ✅ Conference talks
- ✅ Positive HackerNews discussion
- ✅ Used by 5+ companies in production

---

## The Path Forward

**Start here:** Task 039 (.NET CLI Integration)
**Then:** Tasks 040-043 (formatter, docs, NuGet, errors)
**Then:** Tasks 044-048 (tooling & polish)
**Then:** Tasks 049-051 (debugging & IDE plugins)
**Later:** Tasks 052-055 (advanced features)
**Maybe:** Task 056 (IL compiler)

**Each task delivers value immediately. No long waits for results.**

---

*"Incremental progress beats perfect plans."*
