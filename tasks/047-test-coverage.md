# Task 047: Test Coverage Integration

**Priority:** 🟡 P1-Medium
**Effort:** Small (5-7 hours)
**Status:** In Progress

## Goal

Integrate code coverage reporting into N# projects using Coverlet, providing developers with clear visibility into test coverage and supporting CI/CD quality gates.

## Why This Matters

- **Quality Assurance**: Teams need to know which code is tested
- **CI/CD Gates**: Block merges below coverage thresholds
- **Developer Feedback**: Visual feedback on what needs testing
- **Professional Standard**: Expected in modern development workflows

## Deliverables

### 1. Coverlet Integration
- ✅ Add Coverlet.MSBuild package to test projects via SDK
- ✅ Configure coverage collection in MSBuild SDK
- ✅ Support multiple output formats (json, lcov, opencover, cobertura)

### 2. CLI Commands
```bash
# Basic coverage
dotnet test /p:CollectCoverage=true

# With threshold enforcement
dotnet test /p:CollectCoverage=true /p:Threshold=80

# Multiple formats
dotnet test /p:CollectCoverage=true /p:CoverletOutputFormat="json,lcov,opencover"

# HTML report
dotnet test /p:CollectCoverage=true
dotnet reportgenerator -reports:coverage.opencover.xml -targetdir:coverage-report
```

### 3. HTML Report Generation
- ✅ ReportGenerator integration
- ✅ Generate browsable HTML reports
- ✅ Line-by-line coverage visualization
- ✅ Branch coverage metrics

### 4. CI/CD Integration
```yaml
# GitHub Actions example
- name: Test with Coverage
  run: dotnet test /p:CollectCoverage=true /p:CoverletOutputFormat=opencover

- name: Upload to Codecov
  uses: codecov/codecov-action@v3
  with:
    files: ./coverage.opencover.xml
```

### 5. Configuration Options

**project.yml:**
```yaml
test:
  coverage:
    enabled: true
    threshold: 80
    thresholdType: line
    formats:
      - opencover
      - lcov
      - cobertura
    exclude:
      - "[*]*.Generated.*"
      - "[*Tests]*"
```

**Alternative (.editorconfig):**
```ini
[*.nl]
# Coverage settings
nsharp.coverage.threshold = 80
nsharp.coverage.format = opencover,lcov
```

## Implementation Plan

1. **Update MSBuild SDK** (2 hours)
   - Add Coverlet.MSBuild package reference
   - Configure default coverage settings
   - Support coverage properties from project.yml

2. **Add CLI Support** (1 hour)
   - `nlc coverage` command
   - Parse and display coverage results
   - Color-coded output (high/medium/low coverage)

3. **HTML Report Generation** (1 hour)
   - Integrate ReportGenerator
   - Auto-generate reports after test runs
   - Open browser option

4. **Documentation** (1 hour)
   - Coverage guide in docs/guide/testing.md
   - CI/CD examples
   - Configuration reference

5. **Testing** (1 hour)
   - Test coverage collection works
   - Test HTML report generation
   - Test threshold enforcement
   - Verify CI/CD integration examples

## Success Criteria

- ✅ `dotnet test /p:CollectCoverage=true` works
- ✅ HTML reports generated with ReportGenerator
- ✅ Threshold enforcement blocks builds when coverage too low
- ✅ Multiple output formats supported
- ✅ CI/CD examples work with Codecov/Coveralls
- ✅ Documentation complete with examples

## Files to Modify

```
src/Build/Microsoft.NET.Sdk.NSharp/
  ├── Sdk/Sdk.targets          # Add Coverlet integration
  └── build/                    # Coverage configuration

docs/guide/
  └── testing.md                # Coverage documentation

ci-templates/
  └── github-actions/
      └── coverage.yml          # Coverage CI template

examples/
  └── coverage-example/         # Example project with coverage
```

## Example Output

```bash
$ dotnet test /p:CollectCoverage=true

Test run for N#.Tests.dll (.NETCoreApp,Version=v9.0)
Passed!  - Failed: 0, Passed: 765, Skipped: 1, Total: 766

Calculating coverage result...

+------------------+--------+--------+--------+
| Module           | Line   | Branch | Method |
+------------------+--------+--------+--------+
| NSharp.Compiler  | 87.2%  | 78.5%  | 85.1%  |
| NSharp.Parser    | 92.1%  | 86.3%  | 90.2%  |
+------------------+--------+--------+--------+

                  | Line   | Branch | Method |
+------------------+--------+--------+--------+
| Total            | 89.4%  | 82.1%  | 87.5%  |
+------------------+--------+--------+--------+

HTML report generated: coverage-report/index.html
```

## Integration with IDE

### VS Code
- CodeLens shows coverage inline
- Gutters show covered/uncovered lines
- Extension: Coverage Gutters

### Rider
- Built-in coverage support
- Run tests with coverage
- Visual indicators in editor

### Visual Studio
- Built-in coverage tools
- Live Unit Testing integration
- Coverage Explorer window

## References

- [Coverlet Documentation](https://github.com/coverlet-coverage/coverlet)
- [ReportGenerator](https://github.com/danielpalme/ReportGenerator)
- [Codecov Integration](https://about.codecov.io/)
- [.NET Test Coverage](https://learn.microsoft.com/en-us/dotnet/core/testing/unit-testing-code-coverage)
