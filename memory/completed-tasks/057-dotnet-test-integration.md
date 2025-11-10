# Task 057: dotnet test Integration

**Goal**: Make `dotnet test` discover and run tests in `.tests.nl` files

**Deliverable**: Running `dotnet test` in an N# project automatically finds and executes all test functions in `.tests.nl` files

## Background

N# has a built-in testing system where tests are written in `.tests.nl` files using simple `test` functions. Currently these only run via the CLI tool. We need MSBuild/dotnet test integration.

Example `.tests.nl` file:
```
// Calculator.tests.nl
import Calculator

test "add returns sum" {
    result := Calculator.Add(2, 3)
    assert result == 5
}

test "divide by zero throws" {
    assert_throws(() => Calculator.Divide(10, 0))
}
```

## Implementation

### 1. Create MSBuild test discovery task

In `src/Microsoft.NET.Sdk.NSharp/Sdk.targets`:

```xml
<!-- Generate test adapter that discovers .tests.nl files -->
<Target Name="GenerateTestAdapter" BeforeTargets="CoreCompile">
  <ItemGroup>
    <TestFiles Include="**/*.tests.nl" />
  </ItemGroup>

  <!-- Transpile .tests.nl to xUnit test classes -->
  <TranspileTests
    TestFiles="@(TestFiles)"
    OutputPath="$(IntermediateOutputPath)nsharp-tests/"
    ProjectFile="$(ProjectFile)" />
</Target>
```

### 2. Create TranspileTests MSBuild task

```csharp
// src/Microsoft.NET.Sdk.NSharp/TranspileTests.cs
public class TranspileTests : Task
{
    [Required]
    public ITaskItem[] TestFiles { get; set; }

    [Required]
    public string OutputPath { get; set; }

    public override bool Execute()
    {
        foreach (var testFile in TestFiles)
        {
            // Parse .tests.nl file
            // Convert each test "name" { } to [Fact] method
            // Generate xUnit test class
            // Write to OutputPath
        }
        return true;
    }
}
```

### 3. Test transpilation format

Each `test "name" { }` becomes:

```csharp
[Fact]
public void Name()
{
    // test body
}
```

Each `assert_throws(() => expr)` becomes:

```csharp
Assert.Throws<Exception>(() => expr);
```

### 4. Add xUnit reference

The MSBuild SDK should automatically add xUnit package reference when `.tests.nl` files are detected:

```xml
<ItemGroup Condition="'@(TestFiles)' != ''">
  <PackageReference Include="xunit" Version="2.6.2" />
  <PackageReference Include="xunit.runner.visualstudio" Version="2.5.4" />
  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.8.0" />
</ItemGroup>
```

## Success Criteria

- [ ] `dotnet test` discovers tests from `.tests.nl` files
- [ ] Test output shows individual test names
- [ ] Failed assertions show in test results
- [ ] Works with `dotnet test --filter "TestName"`
- [ ] Test results integrate with VS Code Test Explorer
- [ ] Example: TestExample project runs via `dotnet test`

## Effort

**Estimated**: 6-8 hours

## Dependencies

- Requires Task 042 (MSBuild SDK with project.yml) to be complete
- Should work alongside existing xUnit tests in .cs files
