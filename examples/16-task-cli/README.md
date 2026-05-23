# Task CLI

`16-task-cli` is a multi-file command-line task manager that exercises app-shaped N#:

- async file I/O through `Task`
- records, unions, enums, and `with` updates
- typed parsing through normal .NET `out` parameters
- char literals and regular `String.Split` calls
- LINQ projection with lambda inference
- tests in the same project without `.csproj` build knobs

Run it from this directory:

```bash
dotnet run --project ../../src/NSharpLang.Cli/Cli.csproj -- check --project . --text
dotnet run --project ../../src/NSharpLang.Cli/Cli.csproj -- test --project .
dotnet run --project ../../src/NSharpLang.Cli/Cli.csproj -- run --project . -- add "Ship N# examples" --priority high --tag launch
```
