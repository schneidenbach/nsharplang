using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using NSharpLang.Cli;
using NSharpLang.Cli.Commands;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

[Collection("ProcessState")]
public class CompilationBackendTests
{
    [Fact]
    public void MultiFileCompiler_CanCompileExecutableProjectToIlAndRun()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: IlProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print Greeting()
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Greeting.nl"), """
func Greeting(): string {
    return "hello from il backend"
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "IlProject.dll");
            var result = compiler.CompileToIlAssembly("IlProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            Assert.Equal(outputPath, result.OutputAssemblyPath);
            Assert.True(File.Exists(outputPath));

            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("hello from il backend", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_ExperimentalSoaDoesNotFallbackToIlWhenColumnarRouteDeclines()
    {
        var tempDir = CreateTempDir();
        using var experimentalSoa = SetEnvironmentVariable("NSHARP_EXPERIMENTAL_SOA", "1");

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: SoaFallbackProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
soa record NodeTable {
    kind: int
    start: int
}

func main() {
    nodes := new NodeTable(1)
    row := nodes.add()
    nodes[row].kind = 7
    nodes[row].start = 9
    print nodes[row].kind + nodes[row].start + nodes.length
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "SoaFallbackProject.dll");
            var result = compiler.CompileToIlAssembly("SoaFallbackProject", outputPath);

            Assert.False(result.Success);
            Assert.Null(result.OutputAssemblyPath);
            Assert.False(File.Exists(outputPath));
            Assert.Contains(result.Errors, error =>
                error.Message.Contains("Columnar SoA emission is required", StringComparison.Ordinal));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_CanBuildPackageFirstSourceWithImports()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: PackageFirstIlProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
package PackageFirst

import System

func main() {
    print DateTime.UnixEpoch.Year
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "PackageFirstIlProject.dll");
            var result = compiler.CompileToIlAssembly("PackageFirstIlProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("1970", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_CanBuildPackagedNewtypeCallStyleConstruction()
    {
        // Regression: in a packaged project the merger qualifies the newtype declaration to
        // `NewtypeProject.UserId`, but the call-style callee stays the bare `UserId`. The IL
        // lowering of `UserId(42)` must still recognize the unqualified name, exercised here
        // end-to-end through MultiFileCompiler.
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: NewtypeProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
package NewtypeProject

type UserId = newtype int

func main() {
    id := UserId(42)
    print id.Value
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "NewtypeProject.dll");
            var result = compiler.CompileToIlAssembly("NewtypeProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("42", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_CanConstructNewtypeThroughFileImportAliasWithNew()
    {
        // Regression: `import "ids" as Ids` is a file import (stored in FileImports, not Imports),
        // so the merger never bridged the alias to the imported package's namespace. The IL backend
        // then resolved the alias-qualified type `Ids.UserId` to `object`, and `new Ids.UserId(42)`
        // failed at emission with "No matching constructor found for type Object". The `new` form is
        // the foundation: alias-qualified type references must resolve to the underlying wrapper.
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: AliasNewtypeNewProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "ids.nl"), """
package ids

type UserId = newtype int
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import "ids" as Ids

func main() {
    id := new Ids.UserId(42)
    print id.Value
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "AliasNewtypeNewProject.dll");
            var result = compiler.CompileToIlAssembly("AliasNewtypeNewProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("42", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_CanConstructNewtypeThroughFileImportAliasWithCallStyle()
    {
        // Regression: the call-style shorthand `Ids.UserId(42)` (sugar for `new Ids.UserId(42)`)
        // has a MemberAccessExpression callee rather than a bare identifier, so the earlier
        // identifier-only newtype lowering did not cover it. The member-access dispatch mis-resolved
        // the alias receiver to `object` and failed with "Method UserId not found on type Object".
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: AliasNewtypeCallStyleProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "ids.nl"), """
package ids

type UserId = newtype int
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import "ids" as Ids

func main() {
    id := Ids.UserId(42)
    print id.Value
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "AliasNewtypeCallStyleProject.dll");
            var result = compiler.CompileToIlAssembly("AliasNewtypeCallStyleProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("42", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_CanRunRepeatedBlockLocalWithNamespaceQualifiedType()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: RepeatedLocalIlProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Models.nl"), """
namespace RepeatedLocal.Models

record Item {
    Name: string
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Services.nl"), """
namespace RepeatedLocal.Services

import System.Collections.Generic
import System.Linq
import RepeatedLocal.Models

class ItemService {
    items: List<Item>

    constructor() {
        items = new List<Item>()
        items.Add(new Item { Name: "first" })
        items.Add(new Item { Name: "second" })
    }

    func Filter(firstPass: bool, name: string): List<Item> {
        result := items.ToList()

        if firstPass {
            filtered := new List<Item>()
            for item in result {
                filtered.Add(item)
            }

            result = filtered
        }

        normalized := name.ToLower()
        if normalized.Length > 0 {
            filtered := new List<Item>()
            for item in result {
                if item.Name == normalized {
                    filtered.Add(item)
                }
            }

            result = filtered
        }

        return result
    }
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import RepeatedLocal.Services

func main() {
    service := new ItemService()
    print service.Filter(false, "SECOND").Count
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "RepeatedLocalIlProject.dll");
            var result = compiler.CompileToIlAssembly("RepeatedLocalIlProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("1", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_ReportsBadReflectionCallBeforeIlEmission()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: BadReflectionCall
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    greeting := "hello"
    greeting.CompareTo()
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "BadReflectionCall.dll");
            var result = compiler.CompileToIlAssembly("BadReflectionCall", outputPath);

            Assert.False(result.Success);
            Assert.Contains(result.Errors, error => error.Code == ErrorCode.NoMatchingOverload);
            Assert.DoesNotContain(result.Errors, error => error.Message.Contains("Failed to emit IL assembly"));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsStringCompareToInstanceCall()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: StringCompareProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    greeting := "hello"
    print greeting.CompareTo("hello")
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "StringCompareProject.dll");
            var result = compiler.CompileToIlAssembly("StringCompareProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("0", runResult.Stdout.Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsRawAndInterpolatedRawStringLiterals()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: RawStringProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"),
                "func main() {\n" +
                "    name := \"Ada\"\n" +
                "    raw := \"\"\"quote \" slash \\n\"\"\"\n" +
                "    interp := $\"\"\"Hello {name}\\n{{name}}\"\"\"\n" +
                "    print raw\n" +
                "    print interp\n" +
                "}\n");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "RawStringProject.dll");
            var result = compiler.CompileToIlAssembly("RawStringProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("quote \" slash \\n\nHello Ada\\n{name}", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsTargetTypedNewConstructors()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: TargetTypedNewProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
class Person {
    readonly Name: string
    readonly Age: int

    constructor(name: string, age: int) {
        Name = name
        Age = age
    }

    func Label(): string {
        return $"{Name}:{Age}"
    }
}

class Box<T> {
    readonly Value: T

    constructor(value: T) {
        Value = value
    }

    func GetValue(): T {
        return Value
    }
}

func CreateDefaultPerson(): Person {
    return new("Default", 0)
}

func main() {
    person: Person = new("Alice", 30)
    intBox: Box<int> = new(42)

    print person.Label()
    print CreateDefaultPerson().Label()
    print intBox.GetValue()
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "TargetTypedNewProject.dll");
            var result = compiler.CompileToIlAssembly("TargetTypedNewProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("Alice:30\nDefault:0\n42", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsGenericBodyCollectionConstruction()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: GenericBodyCollectionProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System.Collections.Generic

func CountItems<T>(items: T[]): int {
    list := new List<T>()
    for item in items {
        list.Add(item)
    }

    return list.Count
}

func main() {
    print CountItems<int>(new int[3])
    print CountItems<string>(new string[2])
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "GenericBodyCollectionProject.dll");
            var result = compiler.CompileToIlAssembly("GenericBodyCollectionProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("3\n2", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsGenericParamsArrayInference()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: GenericParamsArrayProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System.Collections.Generic

func CreateList<T>(params items: T[]): List<T> {
    list := new List<T>()
    for item in items {
        list.Add(item)
    }

    return list
}

func main() {
    numbers := CreateList(1, 2, 3)
    words := CreateList("a", "b")
    print numbers.Count
    print words.Count
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "GenericParamsArrayProject.dll");
            var result = compiler.CompileToIlAssembly("GenericParamsArrayProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("3\n2", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsGenericParameterInterpolation()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: GenericInterpolationProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Pair<A, B>(a: A, b: B): string => $"({a}, {b})"

func main() {
    print Pair<int, string>(1, "two")
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "GenericInterpolationProject.dll");
            var result = compiler.CompileToIlAssembly("GenericInterpolationProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("(1, two)", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsExplicitGenericLinqCastAndOfType()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: GenericLinqProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System.Collections.Generic
import System.Linq

func main() {
    numbers: int[] = [1, 2, 3]
    objects := numbers.Cast<object>().ToList()

    mixed := new List<object>()
    mixed.Add(1)
    mixed.Add("two")
    mixed.Add(3)

    justNumbers := mixed.OfType<int>().ToList()
    justStrings := mixed.OfType<string>().ToList()

    print objects.Count
    print justNumbers.Count
    print justStrings.Count
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "GenericLinqProject.dll");
            var result = compiler.CompileToIlAssembly("GenericLinqProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("3\n2\n1", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsTargetTypedArrayLiteralAndForIn()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: ArrayLiteralProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
class Item {
    Value: int
}

func main() {
    items: Item[] = [new Item { Value: 2 }, new Item { Value: 4 }]
    total := 0
    for item in items {
        total = total + item.Value
    }
    print total
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "ArrayLiteralProject.dll");
            var result = compiler.CompileToIlAssembly("ArrayLiteralProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("6", runResult.Stdout.Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsUserDefinedConversionOperators()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: ConversionOperatorProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
class Raw {
    Value: int

    implicit operator Cooked(r: Raw) {
        return new Cooked { Value: r.Value + 10 }
    }

    explicit operator Done(r: Raw) {
        return new Done { Value: r.Value + 20 }
    }

    func Label(): string {
        return $"raw-{Value}"
    }
}

class Cooked {
    Value: int
}

class Done {
    Value: int
}

struct Score {
    Value: int

    explicit operator int(s: Score) {
        return s.Value + 30
    }
}

struct Ratio {
    Numerator: int
    Denominator: int

    explicit operator double(r: Ratio) {
        return r.Numerator / (double)r.Denominator
    }
}

func main() {
    raw := new Raw { Value: 5 }
    cooked: Cooked = raw
    done := (Done)raw
    score := new Score { Value: 7 }
    value := (int)score
    ratio := new Ratio { Numerator: 3, Denominator: 2 }
    ratioValue := (double)ratio

    print cooked.Value
    print done.Value
    print value
    print $"label: {raw.Label()}"
    print ratioValue
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "ConversionOperatorProject.dll");
            var result = compiler.CompileToIlAssembly("ConversionOperatorProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("15\n25\n37\nlabel: raw-5\n1.5", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsFileScopedRecordWithDateTimeField()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: FileScopedDateTimeProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
file record Stamp {
    When: DateTime
}

func main() {
    print "ok"
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "FileScopedDateTimeProject.dll");
            var result = compiler.CompileToIlAssembly("FileScopedDateTimeProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("ok", runResult.Stdout.Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsInterfaceMethodReturningUserStruct()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: InterfaceUserStructProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
file struct ValidationResult {
    IsValid: bool
}

file interface IValidator {
    func Validate(input: string): ValidationResult
}

file class UsernameValidator: IValidator {
    func Validate(input: string): ValidationResult {
        if input.Length > 0 {
            return new ValidationResult { IsValid: true }
        }

        return new ValidationResult { IsValid: false }
    }
}

func main() {
    validator: IValidator = new UsernameValidator()
    result := validator.Validate("abc")
    print result.IsValid
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "InterfaceUserStructProject.dll");
            var result = compiler.CompileToIlAssembly("InterfaceUserStructProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("True", runResult.Stdout.Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsInterpolatedStringCoalesceHole()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: InterpolatedCoalesceProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
class Directory {
    func FindEmail(): string? {
        return null
    }
}

func main() {
    directory := new Directory()
    email := directory.FindEmail()
    missing := "not found"
    print $"Retrieved email: {email ?? missing}"
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "InterpolatedCoalesceProject.dll");
            var result = compiler.CompileToIlAssembly("InterpolatedCoalesceProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("Retrieved email: not found", runResult.Stdout.Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsInterpolatedStringIntegerAdditiveHole()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: InterpolatedIntegerAdditiveProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print $"Expected: {1000 + 1000 - 500}"
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "InterpolatedIntegerAdditiveProject.dll");
            var result = compiler.CompileToIlAssembly("InterpolatedIntegerAdditiveProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("Expected: 1500", runResult.Stdout.Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsStringEnumConstantsAsStrings()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: StringEnumProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
enum Status: string {
    Active = "active",
    Inactive = "inactive",
    Pending = "pending"
}

func GetDefault(): Status {
    return Status.Active
}

func Echo(value: Status): string {
    return value
}

func main() {
    print GetDefault()
    print Echo(Status.Inactive)
    print Status.Pending
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "StringEnumProject.dll");
            var result = compiler.CompileToIlAssembly("StringEnumProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("active\ninactive\npending", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsReadonlyClassFieldsInitializedByConstructor()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: ReadonlyClassFields
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
class Person {
    readonly Name: string
    readonly Age: int

    constructor(name: string, age: int) {
        Name = name
        Age = age
    }

    func GetInfo(): string {
        return $"{Name}:{Age}"
    }
}

func main() {
    person := new Person("Ada", 37)
    print person.GetInfo()
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "ReadonlyClassFields.dll");
            var result = compiler.CompileToIlAssembly("ReadonlyClassFields", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("Ada:37", runResult.Stdout.Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsQualifiedBclExceptionConstruction()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: QualifiedExceptionProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Divide(a: int, b: int): int {
    if b == 0 {
        throw new System.DivideByZeroException("Cannot divide by zero")
    }

    return a / b
}

func main() {
    print Divide(10, 2)
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "QualifiedExceptionProject.dll");
            var result = compiler.CompileToIlAssembly("QualifiedExceptionProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("5", runResult.Stdout.Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsInstanceFieldInitializersWithExplicitConstructor()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: InstanceFieldInitializers
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
class Logger {
    Prefix: string = "[LOG]"
}

class Application {
    logger: Logger = new Logger()
    readonly Name: string

    constructor(name: string) {
        Name = name
    }

    func Describe(): string {
        return $"{logger.Prefix}:{Name}"
    }
}

func main() {
    app := new Application("FileScopedDemo")
    print app.Describe()
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "InstanceFieldInitializers.dll");
            var result = compiler.CompileToIlAssembly("InstanceFieldInitializers", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("[LOG]:FileScopedDemo", runResult.Stdout.Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsDoubleInstanceFieldInitializer()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: DoubleInstanceFieldInitializer
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
class Account {
    balance: double = 0.0

    func GetBalance(): double {
        return balance
    }
}

func main() {
    account := new Account()
    print account.GetBalance()
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "DoubleInstanceFieldInitializer.dll");
            var result = compiler.CompileToIlAssembly("DoubleInstanceFieldInitializer", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("0", runResult.Stdout.Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsCheckedUncheckedArithmetic()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: CheckedUncheckedArithmetic
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    max := 2147483647
    print unchecked(max + 1)

    try {
        overflow := checked(max + 1)
        print overflow
    } catch ex: OverflowException {
        print "overflow"
    }

    print checked((100 + 50) * 2 - 25)
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "CheckedUncheckedArithmetic.dll");
            var result = compiler.CompileToIlAssembly("CheckedUncheckedArithmetic", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("""
-2147483648
overflow
275
""".Trim(), runResult.Stdout.Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_RejectsGenericCollectionFieldInitializerMismatch()
    {
        // Defect regression: this program used to COMPILE through the legacy
        // pipeline — the object-initializer value was never type-checked against the
        // declared field type, and the IL coercion silently no-ops for closed generics
        // over emitted user types — so f() read a type-confused garbage int at runtime.
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: InitializerMismatch
backend: il
outputType: library
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
record Pt {
    X: int
}

record Rs {
    S: string
}

record H {
    Items: List<Pt>
}

func f(): int {
    l := new List<Rs>()
    l.Add(new Rs { S: "abc" })
    h := new H { Items: l }
    return h.Items[0].X
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "InitializerMismatch.dll");
            var result = compiler.CompileToIlAssembly("InitializerMismatch", outputPath);

            Assert.False(result.Success);
            Assert.Contains(result.Errors, error =>
                error.Code == ErrorCode.TypeMismatch
                && error.ExpectedType == "List<Pt>"
                && error.ActualType == "List<Rs>");
            Assert.DoesNotContain(result.Errors, error => error.Message.Contains("Failed to emit IL assembly"));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_CanRunAsyncExecutableProjectEntryPoint()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: AsyncMainIlProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System.Threading.Tasks

async func main() {
    await Task.CompletedTask
    print "async entrypoint works"
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "AsyncMainIlProject.dll");
            var result = compiler.CompileToIlAssembly("AsyncMainIlProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("async entrypoint works", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsTaskRunActionAndExpandedWaitAll()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: TaskRunActionProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System.Threading.Tasks

class Flags {
    First: int = 0
    Second: int = 0

    func SetFirst() {
        First = 1
    }

    func SetSecond() {
        Second = 2
    }

    func Sum(): int {
        return First + Second
    }
}

func main() {
    flags := new Flags()
    t1 := Task.Run(() => {
        flags.SetFirst()
    })
    t2 := Task.Run(() => {
        flags.SetSecond()
    })

    Task.WaitAll(t1, t2)
    print flags.Sum()
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "TaskRunActionProject.dll");
            var result = compiler.CompileToIlAssembly("TaskRunActionProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("3", runResult.Stdout.Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsLockWithBareFieldPostfix()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: LockBareFieldPostfixProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
class Counter {
    count: int = 0
    syncLock: object = new object()

    func Increment() {
        lock syncLock {
            count++
        }
    }

    func GetValue(): int {
        lock syncLock {
            return count
        }
    }
}

func main() {
    counter := new Counter()
    counter.Increment()
    print counter.GetValue()
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "LockBareFieldPostfixProject.dll");
            var result = compiler.CompileToIlAssembly("LockBareFieldPostfixProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("1", runResult.Stdout.Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsIlAssemblyWithSdkCompatibleVersion()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: VersionedIlProject
version: 1.2.0-beta.1
backend: il
outputType: library
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Library.nl"), """
namespace Versioned

class Greeter {
    static func Message(): string {
        return "hello"
    }
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "VersionedIlProject.dll");
            var result = compiler.CompileToIlAssembly("VersionedIlProject", outputPath);

            Assert.True(result.Success);
            Assert.Equal(new Version(1, 2, 0, 0), AssemblyName.GetAssemblyName(outputPath).Version);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsNamespaceQualifiedTypesForIlProjects()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: NamespaceIlProject
backend: il
outputType: library
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "MathUtils.nl"), """
namespace InteropLib

class MathUtils {
    static func Add(a: int, b: int): int {
        return a + b
    }
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Geometry.nl"), """
namespace InteropLib.Geometry

interface IShape {
    func Area(): double
}

class Square : IShape {
    Side: double

    constructor(side: double) {
        Side = side
    }

    func Area(): double {
        return Side * Side
    }
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "NamespaceIlProject.dll");
            var result = compiler.CompileToIlAssembly("NamespaceIlProject", outputPath);

            Assert.True(result.Success);

            using var loadScope = CollectibleAssemblyScope.LoadFromFile(outputPath);
            var assembly = loadScope.Assembly;
            Assert.NotNull(assembly.GetType("InteropLib.MathUtils", throwOnError: false));
            Assert.NotNull(assembly.GetType("InteropLib.Geometry.IShape", throwOnError: false));
            Assert.NotNull(assembly.GetType("InteropLib.Geometry.Square", throwOnError: false));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_AllowsIdentifierCallsToMethodsOnCurrentType()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: CurrentTypeCalls
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
class MathUtils {
    static func Factorial(n: int): long {
        if n <= 1 {
            return 1
        }

        return n * Factorial(n - 1)
    }
}

func main() {
    print MathUtils.Factorial(5)
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "CurrentTypeCalls.dll");
            var result = compiler.CompileToIlAssembly("CurrentTypeCalls", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("120", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_AllowsRecordPrimaryConstructorParametersInMembers()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: RecordPrimaryCtorMembers
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
record Address(street: string, city: string, zip: string) {
    FullAddress: string => $"{street}, {city} {zip}"
}

func main() {
    address := new Address("123 Main St", "Springfield", "62701")
    print address.FullAddress
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "RecordPrimaryCtorMembers.dll");
            var result = compiler.CompileToIlAssembly("RecordPrimaryCtorMembers", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("123 Main St, Springfield 62701", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void CheckCommand_UsesConfiguredIlBackendVerification()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: CheckIl
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "checked"
}
""");

            var (exitCode, stdout, _) = CaptureConsole(() =>
                CheckCommand.Execute(new[] { "--project", tempDir }));

            Assert.Equal(0, exitCode);

            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("check", doc.RootElement.GetProperty("command").GetString());
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BuildCommand_UsesConfiguredIlBackendAndProducesRunnableArtifacts()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: BuildIl
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "built with il"
}
""");

            var outputDir = Path.Combine(tempDir, "dist");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("build", "-o", outputDir));

            Assert.Equal(0, exitCode);
            Assert.Contains("Build successful!", stdout);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            var assemblyPath = Path.Combine(outputDir, "BuildIl.dll");
            Assert.True(File.Exists(assemblyPath));
            Assert.True(File.Exists(Path.Combine(outputDir, "BuildIl.runtimeconfig.json")));
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));

            var runResult = DotnetRunner.Run($"\"{assemblyPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("built with il", runResult.Stdout);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BuildCommand_SingleFileSourceAfterOptions_BuildsWithIlBackend()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            var sourcePath = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(sourcePath, """
func main(): int {
    return 0
}
""");

            var outputDir = Path.Combine(tempDir, "dist");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("build", "--backend", "il", "--output", outputDir, sourcePath));

            Assert.Equal(0, exitCode);
            Assert.Contains("Build successful!", stdout);
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.True(File.Exists(Path.Combine(outputDir, "Program.dll")));
            Assert.True(File.Exists(Path.Combine(outputDir, "Program.runtimeconfig.json")));
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BuildCommand_SingleFileRequiresColumnarEmissionWhenColumnarDeclines()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            var sourcePath = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(sourcePath, """
func CountChars(s: string): int {
    n := 0
    foreach c in s {
        n = n + 1
    }
    return n
}

func main() {
    print CountChars("abc")
}
""");

            var outputDir = Path.Combine(tempDir, "dist");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("build", "--backend", "il", "--output", outputDir, sourcePath));

            Assert.Equal(1, exitCode);
            Assert.Contains("Building", stdout);
            Assert.Contains("requires successful N# columnar emission", stderr);
            Assert.False(File.Exists(Path.Combine(outputDir, "Program.dll")));
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BuildCommand_DefineFlagsDriveConditionalCompilation()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: CliDefineBuild
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    #if FEATURE_X
    print "feature-on"
    #else
    print "feature-off"
    #endif

    #if SECOND
    print "second-on"
    #endif
}
""");

            var outputDir = Path.Combine(tempDir, "dist");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram(
                    "build",
                    "--define",
                    " FEATURE_X , SECOND ; FEATURE_X ",
                    "--backend",
                    "il",
                    "-o",
                    outputDir));

            Assert.Equal(0, exitCode);
            Assert.Contains("Build successful!", stdout);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            var assemblyPath = Path.Combine(outputDir, "CliDefineBuild.dll");
            Assert.True(File.Exists(assemblyPath));

            var runResult = DotnetRunner.Run($"\"{assemblyPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("feature-on", runResult.Stdout);
            Assert.Contains("second-on", runResult.Stdout);
            Assert.DoesNotContain("feature-off", runResult.Stdout);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BuildCommand_StrictLintError_BlocksIlBuild()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: StrictLintBuild
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    unused := 42
}
""");

            var outputDir = Path.Combine(tempDir, "dist");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("build", "-o", outputDir));

            Assert.Equal(1, exitCode);
            Assert.Contains("Build failed", stdout);
            Assert.Contains("NL001", stderr);
            Assert.Contains("Variable 'unused' is declared but never read", stderr);
            Assert.False(File.Exists(Path.Combine(outputDir, "StrictLintBuild.dll")));
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BuildCommand_ReleaseUsesReleaseOutputLayout()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: ReleaseLayout
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "release layout"
}
""");

            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("build", "--release"));

            Assert.Equal(0, exitCode);
            Assert.Contains("Build successful! (il, release)", stdout);
            Assert.Contains(NormalizePath(Path.Combine("bin", "Release", "net10.0", "ReleaseLayout.dll")), NormalizePath(stdout));
            Assert.True(string.IsNullOrWhiteSpace(stderr));
            Assert.True(File.Exists(Path.Combine(tempDir, "bin", "Release", "net10.0", "ReleaseLayout.dll")));
            Assert.True(File.Exists(Path.Combine(tempDir, "bin", "Release", "net10.0", "ReleaseLayout.runtimeconfig.json")));
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BuildCommand_ProjectWithoutBackend_DefaultsToIlAndProducesRunnableArtifacts()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: BuildDefaultIl
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "default backend is il"
}
""");

            var outputDir = Path.Combine(tempDir, "dist");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("build", "-o", outputDir));

            Assert.Equal(0, exitCode);
            Assert.Contains("Build successful!", stdout);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.cs", SearchOption.AllDirectories));

            var assemblyPath = Path.Combine(outputDir, "BuildDefaultIl.dll");
            Assert.True(File.Exists(assemblyPath));
            Assert.True(File.Exists(Path.Combine(outputDir, "BuildDefaultIl.runtimeconfig.json")));

            var runResult = DotnetRunner.Run($"\"{assemblyPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("default backend is il", runResult.Stdout);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void RunCommand_UsesConfiguredIlBackendAndExecutesProject()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: RunIl
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "ran with il"
}
""");

            var cliDll = typeof(CheckCommand).Assembly.Location;
            var runResult = DotnetRunner.Run(
                $"\"{cliDll}\" run",
                workingDirectory: tempDir,
                timeout: TimeSpan.FromMinutes(5));

            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("Running...", runResult.Stdout);
            Assert.Contains("ran with il", runResult.Stdout);
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void RunCommand_SingleFileRequiresColumnarEmissionWhenColumnarDeclines()
    {
        var tempDir = CreateTempDir();
        try
        {
            var sourcePath = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(sourcePath, """
func CountChars(s: string): int {
    n := 0
    foreach c in s {
        n = n + 1
    }
    return n
}

func main() {
    print CountChars("abc")
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("run", "--backend", "il", sourcePath));

            Assert.Equal(1, exitCode);
            Assert.Contains("Running", stdout);
            Assert.Contains("requires successful N# columnar emission", stderr);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TestCommand_UsesConfiguredIlBackendAndRunsExecutableProjectTests()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: TestIl
backend: il
outputType: exe
targetFramework: net10.0
""");
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "testing"
}

func Add(a: int, b: int): int {
    return a + b
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.tests.nl"), """
test "addition works" {
    assert Add(2, 3) == 5
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("test", "--project", tempDir, "--json"));

            Assert.True(exitCode == 0, $"stdout:{Environment.NewLine}{stdout}{Environment.NewLine}stderr:{Environment.NewLine}{stderr}");
            Assert.True(string.IsNullOrWhiteSpace(stderr), stderr);

            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("test", doc.RootElement.GetProperty("command").GetString());
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(1, doc.RootElement.GetProperty("summary").GetProperty("passed").GetInt32());
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TestCommand_CoverageJson_ReturnsUnsupportedErrorBeforeDiscovery()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: CoverageUnavailable
backend: il
outputType: library
targetFramework: net10.0
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("test", "--project", tempDir, "--coverage", "--json"));

            Assert.Equal(1, exitCode);
            Assert.True(string.IsNullOrWhiteSpace(stderr), stderr);

            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("test", doc.RootElement.GetProperty("command").GetString());
            Assert.False(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Contains("Coverage collection is not available in nlc test yet", doc.RootElement.GetProperty("error").GetString());
            Assert.Equal(0, doc.RootElement.GetProperty("summary").GetProperty("total").GetInt32());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void PackCommand_UsesConfiguredIlBackendAndProducesNuGetPackage()
    {
        var tempDir = CreateTempDir();
        try
        {
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: PackIl
backend: il
outputType: exe
targetFramework: net10.0
version: 1.2.3
package:
  description: IL-backed package
  author: NSharp
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main(): int {
    return 0
}
""");

            var outputDir = Path.Combine(tempDir, "artifacts");
            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                PackCommand.Execute(new[] { "--project", tempDir, "--output", outputDir, "--json" }));

            Assert.True(exitCode == 0, $"stdout:{Environment.NewLine}{stdout}{Environment.NewLine}stderr:{Environment.NewLine}{stderr}");
            Assert.True(string.IsNullOrWhiteSpace(stderr), stderr);

            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("pack", doc.RootElement.GetProperty("command").GetString());
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());

            var packagePath = doc.RootElement.GetProperty("packagePath").GetString();
            Assert.False(string.IsNullOrWhiteSpace(packagePath));
            Assert.True(File.Exists(packagePath));

            using var package = ZipFile.OpenRead(packagePath!);
            Assert.Contains(package.Entries, entry => entry.FullName == "lib/net10.0/PackIl.dll");
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BuildCommand_BackendOverrideToIl_UsesSdkProjectReferencesAndRuntimeAssets()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            CreateProjectReferenceFixture(tempDir);
            var outputDir = Path.Combine(tempDir, "dist");

            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("build", "--backend", "il", "-o", outputDir));

            Assert.Equal(0, exitCode);
            Assert.Contains("Build successful!", stdout);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            var assemblyPath = Path.Combine(outputDir, "App.dll");
            Assert.True(File.Exists(assemblyPath));
            Assert.True(File.Exists(Path.Combine(outputDir, "App.runtimeconfig.json")));
            Assert.True(File.Exists(Path.Combine(outputDir, "SharedLib.dll")));
            Assert.True(File.Exists(Path.Combine(outputDir, "Newtonsoft.Json.dll")));
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));
            Assert.Empty(Directory.GetFiles(Path.Combine(tempDir, "Shared"), "*.g.csproj", SearchOption.TopDirectoryOnly));

            var runResult = DotnetRunner.Run($"\"{assemblyPath}\"", workingDirectory: outputDir, timeout: TimeSpan.FromMinutes(3));
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("hello from shared", runResult.Stdout);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void BuildCommand_AotProjectReferenceRequiresColumnarWhenColumnarDeclines()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);

            var sharedDir = Path.Combine(tempDir, "Shared");
            Directory.CreateDirectory(sharedDir);
            TestSdkFeed.WriteVersionedSdkProject(sharedDir, "SharedLib");
            File.WriteAllText(Path.Combine(sharedDir, "project.yml"), """
name: SharedLib
outputType: library
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(sharedDir, "Shared.nl"), """
func CountChars(s: string): int {
    n := 0
    foreach c in s {
        n = n + 1
    }
    return n
}
""");

            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: App
outputType: exe
targetFramework: net10.0
dependencies:
  - project: Shared/project.yml
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "root"
}
""");

            var outputDir = Path.Combine(tempDir, "dist");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("build", "--backend", "il", "--aot", "-o", outputDir));

            Assert.Equal(1, exitCode);
            Assert.Contains("AOT builds require successful N# columnar emission", stdout + stderr);
            Assert.False(File.Exists(Path.Combine(outputDir, "SharedLib.dll")));
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void PublishCommand_BackendOverrideToIl_UsesSdkProjectReferencesAndRuntimeAssets()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            CreateProjectReferenceFixture(tempDir);
            var publishDir = Path.Combine(tempDir, "publish");

            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("publish", "--backend", "il", "--output", publishDir));

            Assert.Equal(0, exitCode);
            Assert.Contains("Publish successful!", stdout);
            Assert.True(string.IsNullOrWhiteSpace(stderr));

            var assemblyPath = Path.Combine(publishDir, "App.dll");
            Assert.True(File.Exists(assemblyPath));
            Assert.True(File.Exists(Path.Combine(publishDir, "App.runtimeconfig.json")));
            Assert.True(File.Exists(Path.Combine(publishDir, "SharedLib.dll")));
            Assert.True(File.Exists(Path.Combine(publishDir, "Newtonsoft.Json.dll")));
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));
            Assert.Empty(Directory.GetFiles(Path.Combine(tempDir, "Shared"), "*.g.csproj", SearchOption.TopDirectoryOnly));

            var runResult = DotnetRunner.Run($"\"{assemblyPath}\"", workingDirectory: publishDir, timeout: TimeSpan.FromMinutes(3));
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("hello from shared", runResult.Stdout);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void PublishCommand_BackendOverrideToIl_SupportsRuntimeSpecificOutput()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();
        var runtimeIdentifier = RuntimeInformation.RuntimeIdentifier;

        try
        {
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: RuntimeSpecificIlPublish
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "runtime-specific il publish"
}
""");

            var publishDir = Path.Combine(tempDir, "publish-runtime");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("publish", "--backend", "il", "--runtime", runtimeIdentifier, "--output", publishDir));

            Assert.True(exitCode == 0, $"stdout:{Environment.NewLine}{stdout}{Environment.NewLine}stderr:{Environment.NewLine}{stderr}");
            Assert.True(string.IsNullOrWhiteSpace(stderr), stderr);
            Assert.Contains("Publish successful!", stdout);

            var publishedApp = GetPublishedAppPath(publishDir, "RuntimeSpecificIlPublish");
            Assert.True(File.Exists(publishedApp), publishedApp);
            Assert.True(File.Exists(Path.Combine(publishDir, "RuntimeSpecificIlPublish.dll")));
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));

            var runResult = DotnetRunner.RunProcess(publishedApp, "", workingDirectory: publishDir, timeout: TimeSpan.FromMinutes(3));
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("runtime-specific il publish", runResult.Stdout);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void PublishCommand_SelfContainedOutput_ReturnsHelpfulUnsupportedMessage()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();
        var runtimeIdentifier = RuntimeInformation.RuntimeIdentifier;

        try
        {
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: SelfContainedIlPublish
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "self-contained il publish"
}
""");

            var publishDir = Path.Combine(tempDir, "publish-self-contained");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram(
                    "publish",
                    "--backend", "il",
                    "--runtime", runtimeIdentifier,
                    "--self-contained",
                    "--output", publishDir));

            Assert.Equal(1, exitCode);
            Assert.Contains("Publishing project in", stdout);
            Assert.Contains("Self-contained publish is not available in nlc publish yet", stderr);
            Assert.Contains("framework-dependent artifacts", stderr);
            Assert.False(Directory.Exists(publishDir));
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void PublishCommand_CrossRuntimeOutput_ReturnsHelpfulUnsupportedMessage()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();
        var requestedRuntime = GetDifferentRuntimeIdentifier();

        try
        {
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: CrossRuntimeIlPublish
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "cross runtime il publish"
}
""");

            var publishDir = Path.Combine(tempDir, "publish-cross-runtime");
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("publish", "--backend", "il", "--runtime", requestedRuntime, "--output", publishDir));

            Assert.Equal(1, exitCode);
            Assert.Contains("Publishing project in", stdout);
            Assert.Contains("Cross-runtime publish is not available in nlc publish yet", stderr);
            Assert.Contains($"Requested runtime '{requestedRuntime}'", stderr);
            Assert.Contains(RuntimeInformation.RuntimeIdentifier, stderr);
            Assert.False(Directory.Exists(publishDir));
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void PublishCommand_NoProjectFile_ReturnsHelpfulMessage()
    {
        var tempDir = CreateTempDir();
        var originalDirectory = Directory.GetCurrentDirectory();

        try
        {
            Directory.SetCurrentDirectory(tempDir);

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("publish", "--backend", "il"));

            Assert.Equal(1, exitCode);
            Assert.Contains("Publishing project in", stdout);
            Assert.Contains("No project.yml found in current directory. Run 'nlc new <name>' to create a project.", stderr);
        }
        finally
        {
            Directory.SetCurrentDirectory(originalDirectory);
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void TestCommand_BackendOverrideToIl_RunsTestsThroughSdkProject()
    {
        var tempDir = CreateTempDir();
        try
        {
            TestSdkFeed.WriteSdkResolutionFiles(tempDir);
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: OverrideIlTests
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    print "override"
}

func Add(a: int, b: int): int {
    return a + b
}
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.tests.nl"), """
test "override il tests" {
    assert Add(4, 5) == 9
}
""");

            var (exitCode, stdout, stderr) = CaptureConsole(() =>
                ExecuteProgram("test", "--project", tempDir, "--backend", "il", "--json"));

            Assert.True(exitCode == 0, $"stdout:{Environment.NewLine}{stdout}{Environment.NewLine}stderr:{Environment.NewLine}{stderr}");
            Assert.True(string.IsNullOrWhiteSpace(stderr), stderr);

            using var doc = JsonDocument.Parse(stdout);
            Assert.Equal("test", doc.RootElement.GetProperty("command").GetString());
            Assert.True(doc.RootElement.GetProperty("ok").GetBoolean());
            Assert.Equal(1, doc.RootElement.GetProperty("summary").GetProperty("passed").GetInt32());
            Assert.Empty(Directory.GetFiles(tempDir, "*.g.csproj", SearchOption.TopDirectoryOnly));
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }


    [Fact]
    public void MultiFileCompiler_CanRunExecutableProjectWithTypeScopedMainEntryPoint()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: TypeMainProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System

class Program {
    static func Main() {
        print DateTime.UnixEpoch.Year
    }
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "TypeMainProject.dll");
            var result = compiler.CompileToIlAssembly("TypeMainProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("1970", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void RecordStruct_EqualityOperators_UseStructuralEquality()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: RecordStructEquality
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
record struct Named(id: int, name: string) {
}

func main(): void {
    a := new Named(1, "x")
    b := new Named(1, "x")
    c := new Named(2, "x")
    print $"a.Equals(c)={a.Equals(c)}"
    print $"a==c={a == c}"
    print $"a==b={a == b}"
    print $"a!=c={a != c}"
    print $"a!=b={a != b}"
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "RecordStructEquality.dll");
            var result = compiler.CompileToIlAssembly("RecordStructEquality", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("a.Equals(c)=False", runResult.Stdout);
            Assert.Contains("a==c=False", runResult.Stdout);
            Assert.Contains("a==b=True", runResult.Stdout);
            Assert.Contains("a!=c=True", runResult.Stdout);
            Assert.Contains("a!=b=False", runResult.Stdout);
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    private static int ExecuteProgram(params string[] args)
    {
        var programType = typeof(CheckCommand).Assembly.GetType("NSharpLang.Cli.Program");
        Assert.NotNull(programType);

        var method = programType!.GetMethod("Execute", BindingFlags.Static | BindingFlags.NonPublic);
        Assert.NotNull(method);

        return (int)(method!.Invoke(null, new object[] { args }) ?? -1);
    }

    private static (int ExitCode, string Stdout, string Stderr) CaptureConsole(Func<int> action)
    {
        var originalOut = Console.Out;
        var originalError = Console.Error;

        using var stdout = new StringWriter();
        using var stderr = new StringWriter();

        Console.SetOut(stdout);
        Console.SetError(stderr);

        try
        {
            var exitCode = action();
            return (exitCode, stdout.ToString(), stderr.ToString());
        }
        finally
        {
            Console.SetOut(originalOut);
            Console.SetError(originalError);
        }
    }

    private static string CreateTempDir()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-backend-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        return tempDir;
    }

    private static IDisposable SetEnvironmentVariable(string name, string? value)
    {
        var previousValue = Environment.GetEnvironmentVariable(name);
        Environment.SetEnvironmentVariable(name, value);
        return new RestoreEnvironmentVariable(name, previousValue);
    }

    private sealed class RestoreEnvironmentVariable(string name, string? previousValue) : IDisposable
    {
        public void Dispose()
        {
            Environment.SetEnvironmentVariable(name, previousValue);
        }
    }

    private static string GetPublishedAppPath(string publishDir, string assemblyName)
    {
        var executableName = RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
            ? $"{assemblyName}.cmd"
            : assemblyName;
        return Path.Combine(publishDir, executableName);
    }

    private static string NormalizePath(string path) => path.Replace('\\', '/');

    private static string GetDifferentRuntimeIdentifier()
    {
        var current = RuntimeInformation.RuntimeIdentifier;
        var candidates = new[] { "linux-x64", "osx-arm64", "win-x64" };
        return candidates.First(candidate => !string.Equals(candidate, current, StringComparison.OrdinalIgnoreCase));
    }

    private static void CreateProjectReferenceFixture(string projectRoot)
    {
        TestSdkFeed.WriteSdkResolutionFiles(projectRoot);

        var sharedDir = Path.Combine(projectRoot, "Shared");
        Directory.CreateDirectory(sharedDir);
        TestSdkFeed.WriteVersionedSdkProject(sharedDir, "SharedLib");

        File.WriteAllText(Path.Combine(sharedDir, "project.yml"), """
name: SharedLib
outputType: library
targetFramework: net10.0
""");
        File.WriteAllText(Path.Combine(sharedDir, "Shared.nl"), """
func Greeting(): string {
    return "hello from shared"
}
""");

        File.WriteAllText(Path.Combine(projectRoot, "project.yml"), """
name: App
outputType: exe
targetFramework: net10.0
dependencies:
  - project: Shared/project.yml
  - nuget: Newtonsoft.Json
    version: 13.0.3
""");
        File.WriteAllText(Path.Combine(projectRoot, "Program.nl"), """
import Newtonsoft.Json

func main() {
    print JsonConvert.SerializeObject(Greeting())
}
""");
    }
}
