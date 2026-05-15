# 12. Multi-File Projects

Real applications consist of multiple files. These examples show how to structure N# projects with imports, shared types, and test files.

## What You'll Learn

- Importing other N# files
- Project structure
- Building multi-file applications
- Testing with N# `test` blocks and `dotnet test`

## Projects

### MultiFileProject
A simple multi-file project demonstrating imports and code organization.

### SimpleProject
A minimal project with just the essentials.

### imports
Examples of various import patterns.

### TestExample
Unit testing examples using N# `test` blocks compiled through the SDK.

### WeatherDemo
A complete weather application demonstrating a real-world multi-file structure.

## Project Structure

A typical N# multi-file project:

```text
MyProject/
  Program.nl           # Entry point
  Models.nl            # Domain models
  Services.nl          # Business logic
  Utils.nl             # Utility functions
  MyProject.tests.nl   # Test files
  MyProject.csproj     # Minimal SDK-style project file
```

## Using Imports

```n#
// In Models.nl
package MyProject.Models

class User {
    Id: int
    Name: string
}

// In Program.nl
import MyProject.Models

package MyProject

func Main() {
    user := new User { Id = 1, Name = "Alice" }
    Console.WriteLine(user.Name)
}
```

These example projects already include `global.json` and `NuGet.config` for local repo development.

## Building Multi-File Projects

```bash
cd examples/12-multi-file-projects/WeatherDemo
dotnet build
dotnet run
```

## Testing

```n#
namespace MyLib

class Math {
    static func Add(a: int, b: int): int {
        return a + b
    }
}

test "adds two numbers" {
    result := Math.Add(2, 3)
    assert result == 5
}
```

Run tests:

```bash
cd examples/12-multi-file-projects/TestExample
dotnet test
```

## Next Steps

Check out the [14. Minimal API](../14-minimal-api/) for an ASP.NET Core-shaped project built on the same `dotnet build` workflow.
