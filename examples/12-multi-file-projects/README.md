# 12. Multi-File Projects

Real applications consist of multiple files. These examples show how to structure N# projects with imports and dependencies.

## What You'll Learn

- Importing other N# files
- Project structure
- Building multi-file applications
- Testing with XUnit

## Projects

### MultiFileProject
A simple multi-file project demonstrating imports and code organization.

### SimpleProject
A minimal project with just the essentials.

### imports
Examples of various import patterns.

### TestExample
Unit testing examples using XUnit.

### WeatherDemo
A complete weather application demonstrating a real-world multi-file structure.

## Project Structure

A typical N# multi-file project:

```
MyProject/
  Program.nl           # Entry point
  Models.nl            # Domain models
  Services.nl          # Business logic
  Utils.nl             # Utility functions
  MyProject.csproj     # .NET project file
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

## Building Multi-File Projects

```bash
cd examples/12-multi-file-projects/WeatherDemo
nsharp build
dotnet run
```

## Testing

```n#
// Math.nl
package MyLib

func Add(a: int, b: int): int {
    return a + b
}

// Math.tests.nl
import Xunit
import MyLib

package MyLib.Tests

class MathTests {
    [Fact]
    func Add_TwoNumbers_ReturnsSum() {
        result := Add(2, 3)
        Assert.Equal(5, result)
    }
}
```

Run tests:
```bash
nsharp build Math.tests.nl
dotnet test
```

## Next Steps

Check out the [13. ASP.NET Core Demo](../13-aspnet-demo/) for a production-quality example!
