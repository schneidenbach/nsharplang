# Task 034: Fix Full Test Suite Hang

## Problem
When running the ENTIRE test suite with `dotnet test` (all 843 tests), xUnit hangs immediately after test discovery completes. Individual test classes run fine.

### Symptoms
```
Test run for /path/to/Tests.dll (.NETCoreApp,Version=v9.0)
VSTest version 17.12.0 (arm64)

Starting test execution, please wait...
A total of 1 test files matched the specified pattern.
[xUnit.net 00:00:00.15]     NSharpLang.Tests.ILCompilerTests.ILCompiler_CanCompileSimpleUsingStatement [SKIP]
<hangs indefinitely>
```

## Investigation Results

### What Works
- ✅ Individual test classes pass: `dotnet test --filter "FullyQualifiedName~Linter"`
- ✅ Compiler builds successfully
- ✅ Linter tests pass (27/27)
- ✅ Parser tests pass when run alone
- ✅ All other test classes pass individually

### What Fails
- ❌ Running ALL tests together: `dotnet test` hangs
- ❌ Running `./scripts/test-all.sh` hangs at "Run Unit Tests" step

### Previous Fixes Applied
Multiple performance/loop fixes have been applied:
- dc82757: Fix infinite loop bug in Linter AwaitForEachStatement
- ea247b9: Fix async infinite loop in Linter by improving circular reference guard
- 9f674e5: Fix infinite loop bug in Linter caused by circular AST references
- db9e47d: Fix major performance issue in Language Server tests using xUnit Collection Fixture
- df2f81b: Fix critical performance bug in TypeResolver causing tests to hang
- 70a04ca: Fix XmlDocReader performance issue with O(n) member lookups

**Note**: Commit df2f81b mentions "There appears to be a remaining performance issue when running the FULL test suite together."

### Root Cause Hypothesis
The hang occurs during xUnit test initialization, likely when:
1. xUnit discovers ALL 843 tests across 16 test files
2. Collection fixtures are initialized (`LanguageServerFixture`)
3. Some combination of reflection + assembly loading + threading causes a deadlock

The `LanguageServerFixture` initializes:
- `XmlDocReader` - loads XML documentation files
- `TypeResolver` - calls `GetExportedTypes()` on System assemblies

Even with caching in place (added in previous fixes), when ALL tests are discovered together, there may be:
- Race condition in static initialization
- Deadlock in assembly loading
- Thread pool exhaustion
- xUnit parallel execution issue (though parallelization is disabled)

### Attempted Solutions
1. ✅ Disabled test parallelization: `<ParallelizeTestCollections>false</ParallelizeTestCollections>`
2. ✅ Implemented xUnit Collection Fixture for shared resources
3. ✅ Cached `GetExportedTypes()` results in TypeResolver
4. ✅ Indexed XML documentation for O(1) lookups
5. ❌ Full test suite still hangs

## Workaround
Run tests by class/category:
```bash
dotnet test --filter "FullyQualifiedName~Linter"
dotnet test --filter "FullyQualifiedName~Parser"
dotnet test --filter "FullyQualifiedName~Analyzer"
# etc.
```

Or create a script that runs test classes sequentially:
```bash
#!/bin/bash
TEST_CLASSES=("Linter" "Parser" "Analyzer" "Transpiler" "Language" "IL" "Formatter" "Error" "Local" "Code")
for class in "${TEST_CLASSES[@]}"; do
    echo "Running $class tests..."
    dotnet test --filter "FullyQualifiedName~$class" || exit 1
done
```

## Potential Solutions

### Option 1: Lazy Initialization
Convert `LanguageServerFixture` to use lazy initialization:
```csharp
public class LanguageServerFixture : IDisposable
{
    private XmlDocReader? _xmlDocReader;
    private TypeResolver? _typeResolver;

    public XmlDocReader XmlDocReader => _xmlDocReader ??= new XmlDocReader(NullLogger<XmlDocReader>.Instance);
    public TypeResolver TypeResolver => _typeResolver ??= new TypeResolver(NullLogger<TypeResolver>.Instance, XmlDocReader);

    ...
}
```

### Option 2: Split Test Projects
Create separate test projects for different components:
- `NSharpLang.Compiler.Tests` - Lexer, Parser, Analyzer, Transpiler
- `NSharpLang.LanguageServer.Tests` - LSP tests with expensive fixtures
- `NSharpLang.Integration.Tests` - End-to-end tests

### Option 3: Mock/Stub TypeResolver
For tests that don't need real .NET reflection, use a stub TypeResolver that doesn't load assemblies.

### Option 4: Investigate xUnit Internals
- Add verbose logging to xUnit runner
- Profile with dotnet-trace to see where it hangs
- Check if it's specific to macOS ARM64

## References
- xUnit Collection Fixtures: https://xunit.net/docs/shared-context#collection-fixture
- Similar issues: https://github.com/xunit/xunit/issues?q=hang+fixture
- Roslyn test infrastructure for reference

## Priority
MEDIUM - Tests DO pass individually, so compiler is working. This is a test infrastructure issue, not a compiler bug.

## Status
OPEN - Documented workaround, deeper investigation needed

---
*Created: 2025-11-13*
*Last Investigation: 2025-11-13*
