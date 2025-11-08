# Task 031: Automatic Transpilation and Build Cleanup

**Priority:** High (Developer experience - critical usability improvement)
**Dependencies:** None
**Estimated Effort:** Medium (4-6 hours)
**Status:** Not started

## Goal

Improve the build experience so developers don't need to manually transpile each .nl file. The `nsharp build` and `nsharp run` commands should automatically discover and transpile all .nl files in a project.

## Current Problem

From the TaskManagementApi example README:

```bash
# Step 2: Compile N# to C# (ANNOYING!)
nsharp build Program.nl
nsharp build Database.nl
nsharp build Tasks.nl
```

This is tedious, error-prone, and doesn't scale. Users have to remember every .nl file!

## Desired Behavior

### Automatic Discovery
```bash
# Build all .nl files in current directory and subdirectories
nsharp build

# Run a specific entry point (auto-transpiles dependencies)
nsharp run Program.nl
```

### Transpiled File Cleanup
- **Always** clean up generated `*.g.cs` files as part of the build process
- Clean up even if the build fails (temp files should never be left behind)
- Add a `--keep-generated` flag for debugging purposes

## Implementation Steps

### 1. File Discovery
- When `nsharp build` is called without arguments:
  - Search recursively for `*.nl` files in current directory
  - Respect `.nsharpignore` or `.gitignore` patterns
  - Exclude common patterns: `bin/`, `obj/`, `node_modules/`

### 2. Dependency Graph
- For `nsharp run Program.nl`:
  - Parse Program.nl for `import` statements
  - Recursively discover all imported .nl files
  - Build dependency graph
  - Transpile in correct order (dependencies first)

### 3. Transpilation Pipeline
```
1. Discover .nl files
2. Transpile each to .g.cs (in temp location if possible)
3. Invoke dotnet build/run with generated files
4. Clean up .g.cs files (always, even on failure)
```

### 4. Cleanup Strategy
- Option A: Use temp directory (e.g., `obj/nsharp/`)
  - Pros: Clean separation, easy cleanup
  - Cons: Need to update .csproj to include files

- Option B: Generate in-place, always delete
  - Pros: Simpler, works with existing .csproj patterns
  - Cons: More cleanup code needed

### 5. CLI Changes
```bash
# Build all .nl files in project
nsharp build                    # Transpiles all, runs dotnet build, cleans up

# Run entry point (discovers dependencies)
nsharp run Program.nl           # Transpiles deps, runs, cleans up

# Debug mode (keep generated files)
nsharp build --keep-generated   # Useful for debugging transpiler
nsharp run Program.nl --keep-generated
```

### 6. Configuration File Support
Create `nsharp.json` for project configuration:
```json
{
  "entryPoint": "Program.nl",
  "include": ["**/*.nl"],
  "exclude": ["**/*.tests.nl", "tmp/**"],
  "outputDir": "obj/nsharp",
  "cleanupOnBuild": true
}
```

### 7. Error Handling
- If transpilation fails, still clean up partial .g.cs files
- Show clear error messages about which file failed
- Don't stop on first error - report all transpilation errors

### 8. Update Documentation
- Update main README.md with new simpler workflow
- Update TaskManagementApi/README.md example
- Remove manual transpilation steps from all examples

## Success Criteria

- [ ] `nsharp build` transpiles all .nl files without arguments
- [ ] `nsharp run Program.nl` auto-discovers and transpiles dependencies
- [ ] Generated .g.cs files are cleaned up after build (even on failure)
- [ ] `--keep-generated` flag works for debugging
- [ ] Works with multi-file projects (imports)
- [ ] Clear error messages when transpilation fails
- [ ] All example READMEs updated with simpler instructions

## Testing

### Manual Tests
1. Navigate to TaskManagementApi
2. Delete all .g.cs files
3. Run `nsharp build` with no arguments
4. Verify all .nl files transpiled and built
5. Verify .g.cs files cleaned up

### Failure Test
1. Introduce syntax error in one .nl file
2. Run `nsharp build`
3. Verify .g.cs files still cleaned up
4. Verify error message is clear

### Keep Generated Test
1. Run `nsharp build --keep-generated`
2. Verify .g.cs files remain for inspection

## Notes

This is a critical usability improvement. Having to manually list every file is a major friction point that makes N# feel unpolished. After this task, the developer experience should be:

```bash
cd examples/13-aspnet-demo/TaskManagementApi
nsharp run Program.nl    # Just works!
```

Much better than the current 3-command dance.
