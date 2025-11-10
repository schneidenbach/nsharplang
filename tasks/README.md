# N# Task List

**Format:** Bite-sized tasks (~150 lines, one clear deliverable)
**Priority:** Low number = do first, high number = low priority

## Active Tasks (Do These First)

### Foundation (041-044)
- **041**: MSBuild Compile Task - 8-10h - `dotnet build` works
- **042**: dotnet build with project.yml - 6-8h - MSBuild SDK reads YAML
- **043**: dotnet new Console - 4-5h - Template works
- **044**: Publish SDK to NuGet - 3-4h - Packages published

### Developer Experience (045-048)
- **045**: Basic Formatter - 6-8h - Fix indentation
- **046**: Format Command - 3-4h - `nsharp format` works
- **047**: .editorconfig Support - 4-5h - Read config files
- **048**: Format on Save (VS Code) - 3-4h - Auto-format

### Documentation (049-050)
- **049**: Website Landing Page - 8-10h - nsharp.dev live
- **050**: Language Guide (Basics) - 6-8h - Core docs

### Quality (051-053)
- **051**: Error Messages (Top 5) - 6-8h - Better errors
- **052**: Basic Linter (3 Rules) - 8-10h - Unused vars, etc.
- **053**: Lint Command - 3-4h - `nsharp lint` works

### Templates & CI (054-055)
- **054**: dotnet new Web API - 5-6h - API template
- **055**: GitHub Actions Template - 3-4h - CI workflow

### Tooling (056)
- **056**: VS Code Debugging - 6-8h - Breakpoints work

## Lower Priority Tasks

### IDE Plugins (090-096)
- **090**: Rider Plugin (Basic) - 25-30h - Syntax + projects
- **091**: Rider LSP Integration - 12-15h - IntelliSense
- **095**: Visual Studio Extension - 40-50h - Basic support
- **096**: Visual Studio IntelliSense - 30-35h - Full LSP

### IL Compiler (097-099)
- **097**: IL Pattern Matching - 20-25h - Match expressions
- **098**: IL Records - 12-15h - Record types
- **099**: IL Lambdas - 25-30h - Lambda + closures

## Total Effort

**High Priority (041-056):** ~100-125 hours
**Medium Priority (090-091):** ~40-45 hours
**Low Priority (095-099):** ~130-160 hours

**Path to 1.0:** Focus on tasks 041-056 first.

## Task Format

Each task file contains:
- Clear goal (1-2 sentences)
- One deliverable
- Implementation snippet
- Success criteria
- ~150 lines max

## Dependencies

```
041 (MSBuild) → 042 (project.yml) → 043 (template) → 044 (NuGet)
                                                       ↓
045 (formatter) → 046 (CLI) → 047 (config) → 048 (VS Code)
                                                       ↓
                                                    049 (website)
                                                       ↓
                                                    050 (docs)

051 (errors), 052 (linter), 053 (lint cmd) - Independent

056 (debugging) depends on 042
090-091 (Rider) depends on 042, 056
095-096 (VS) depends on 042, 056
097-099 (IL) - Independent
```

## Usage

1. Pick lowest-numbered incomplete task
2. Complete it in one session if possible
3. Ship it (commit, test, document)
4. Move to next task

**Each task delivers value immediately!**
