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
    public void MultiFileCompiler_EmitsConstructorChainsWithLiteralAndNewArguments()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: ConstructorChainArgumentsProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
interface ICache {
    func Get(key: string): string?
}

class MemoryCache: ICache {
    func Get(key: string): string? {
        return null
    }
}

class Person {
    readonly Name: string
    readonly Age: int
    readonly Email: string

    constructor(name: string, age: int, email: string) {
        Name = name
        Age = age
        Email = email
    }

    constructor(name: string, email: string): this(name, 0, email) {
    }

    constructor(name: string): this(name, 0, "") {
    }

    func Info(): string {
        return $"{Name}:{Age}:{Email}"
    }
}

class Service {
    readonly Cache: ICache
    readonly Config: string

    constructor(cache: ICache, config: string) {
        Cache = cache
        Config = config
    }

    constructor(): this(new MemoryCache(), "default") {
    }

    func Info(): string {
        return Config
    }
}

func main() {
    p1 := new Person("Ada", 37, "ada@example.com")
    p2 := new Person("Bob", "bob@example.com")
    p3 := new Person("Cy")
    service := new Service()

    print p1.Info()
    print p2.Info()
    print p3.Info()
    print service.Info()
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "ConstructorChainArgumentsProject.dll");
            var result = compiler.CompileToIlAssembly("ConstructorChainArgumentsProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("Ada:37:ada@example.com\nBob:0:bob@example.com\nCy:0:\ndefault", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsBaseMethodCallsInInterpolatedStrings()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: BaseInterpolationProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
class Person {
    readonly Name: string

    constructor(name: string) {
        Name = name
    }

    func Info(): string {
        return $"person:{Name}"
    }
}

class Employee: Person {
    readonly Id: string

    constructor(name: string, id: string): base(name) {
        Id = id
    }

    func Label(): string {
        return $"{base.Info()}:{Id}"
    }
}

func main() {
    employee := new Employee("Ada", "E-1")
    print employee.Label()
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "BaseInterpolationProject.dll");
            var result = compiler.CompileToIlAssembly("BaseInterpolationProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("person:Ada:E-1", runResult.Stdout.Replace("\r\n", "\n").Trim());
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
    public void MultiFileCompiler_EmitsExplicitNullableGenericCall()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: ExplicitNullableGenericProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System.Collections.Generic
import System.Linq

func CreateList<T>(params items: T[]): List<T> {
    list := new List<T>()
    for item in items {
        list.Add(item)
    }

    return list
}

func main() {
    numbers := CreateList<int?>(1, null, 3)
    present := numbers.Where(n => n != null).ToList()
    print $"{numbers.Count}:{present.Count}"
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "ExplicitNullableGenericProject.dll");
            var result = compiler.CompileToIlAssembly("ExplicitNullableGenericProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("3:2", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsLocalFunctionMethodGroupsInEnumerableCalls()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: LocalFunctionEnumerableProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System.Linq

func main() {
    func IsValid(value: int): bool {
        return value > 0 && value < 100
    }

    static func Transform(value: int): int {
        return value * 2
    }

    numbers := [1, 5, 50, 150]
    filtered := numbers.Where(IsValid).Select(Transform).ToArray()
    for item in filtered {
        print item
    }
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "LocalFunctionEnumerableProject.dll");
            var result = compiler.CompileToIlAssembly("LocalFunctionEnumerableProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("2\n10\n100", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsArrayListPatterns()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: ArrayListPatternProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Describe(values: int[]): string {
    result := match values {
        [] => "empty",
        [single] => $"one:{single}",
        [a, b] => $"pair:{a}:{b}",
        [first, .. middle, last] when first == last => $"same:{middle.Length}",
        [first, .. middle, last] => $"range:{first}:{middle.Length}:{last}",
        _ => "other"
    }

    return result
}

func main() {
    print Describe([])
    print Describe([9])
    print Describe([1, 2])
    print Describe([1, 2, 3, 4])
    print Describe([5, 6, 5])
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "ArrayListPatternProject.dll");
            var result = compiler.CompileToIlAssembly("ArrayListPatternProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("empty\none:9\npair:1:2\nrange:1:2:4\nsame:1", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsArrayAndStringRangeAndIndexValues()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: RangeAndIndexProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
enum Bound {
    Zero = 0,
    One = 1,
    Four = 4
}

func main() {
    values := [10, 20, 30, 40, 50]
    text := "abcdef"
    words := ["zero", "one", "two", "three"]

    print values[^1]
    print values[^3]
    print text[^1]
    print text[^3]

    closed := values[1..4]
    fromStart := values[..3]
    toEnd := values[2..]
    all := values[..]
    fromEnd := values[^4..^1]
    closedFirst := closed[0]
    closedLast := closed[^1]
    fromStartFirst := fromStart[0]
    fromStartLast := fromStart[^1]
    toEndFirst := toEnd[0]
    toEndLast := toEnd[^1]
    allFirst := all[0]
    allLast := all[^1]
    fromEndFirst := fromEnd[0]
    fromEndLast := fromEnd[^1]
    print $"{closedFirst}:{closedLast}:{closed.Length}"
    print $"{fromStartFirst}:{fromStartLast}:{fromStart.Length}"
    print $"{toEndFirst}:{toEndLast}:{toEnd.Length}"
    print $"{allFirst}:{allLast}:{all.Length}"
    print $"{fromEndFirst}:{fromEndLast}:{fromEnd.Length}"

    print text[1..4]
    print text[..3]
    print text[2..]
    print text[..]
    print text[^4..^1]
    middleWords := words[1..^1]
    firstWord := middleWords[0]
    lastWord := middleWords[1]
    print $"{firstWord}:{lastWord}"

    last: Index = ^2
    window: Range = 1..^1
    lastValue := values[last]
    lastChar := text[last]
    print $"{lastValue}:{lastChar}"
    windowValues := values[window]
    windowFirst := windowValues[0]
    windowLast := windowValues[^1]
    textWindow := text[window]
    print $"{windowFirst}:{windowLast}:{textWindow}"

    start: byte = 1
    end: short = 4
    fromEndCount: byte = 2
    smallBounds := values[start..end]
    parenthesizedStart := values[(start)..end]
    smallFirst := smallBounds[0]
    smallLast := smallBounds[^1]
    parenthesizedFirst := parenthesizedStart[0]
    parenthesizedLast := parenthesizedStart[^1]
    fromEndValue := values[^fromEndCount]
    fromEndChar := text[^fromEndCount]
    print $"{smallFirst}:{smallLast}:{fromEndValue}:{fromEndChar}"
    print $"{parenthesizedFirst}:{parenthesizedLast}:{parenthesizedStart.Length}"

    rangeStart: Index = ^4
    rangeEnd: Index = ^1
    indexBounds := values[rangeStart..rangeEnd]
    indexFirst := indexBounds[0]
    indexLast := indexBounds[^1]
    print $"{indexFirst}:{indexLast}:{indexBounds.Length}"

    chooseLast := true
    conditionalValue := values[chooseLast ? ^1 : ^2]
    conditionalRange := values[chooseLast ? (1..^1) : (..)]
    conditionalFirst := conditionalRange[0]
    conditionalLast := conditionalRange[^1]
    print $"{conditionalValue}:{conditionalFirst}:{conditionalLast}"

    enumBounds := values[Bound.One..Bound.Four]
    enumFirst := enumBounds[0]
    enumLast := enumBounds[^1]
    enumFromEnd := values[^Bound.One]
    print $"{enumFirst}:{enumLast}:{enumFromEnd}"
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "RangeAndIndexProject.dll");
            var result = compiler.CompileToIlAssembly("RangeAndIndexProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal(
                "50\n30\nf\nd\n20:40:3\n10:30:3\n30:50:3\n10:50:5\n20:40:3\nbcd\nabc\ncdef\nabcdef\ncde\none:two\n40:e\n20:40:bcde\n20:40:40:e\n20:40:3\n20:40:3\n50:20:40\n20:40:50",
                runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsNestedPropertyPatterns()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: NestedPropertyPatternProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
class Address {
    City: string
    State: string
}

class Person {
    Name: string
    Age: int
    Address: Address
}

union Option {
    Some { value: int }
    None
}

union Response {
    Ok { data: Option }
    Error { message: string }
}

func Classify(person: Person): string {
    return match person {
        { Address: { City: "New York", State: "NY" } } => "ny",
        { Address: { City: city, State: "CA" } } => $"ca:{city}",
        { Age: age, Address: { State: "TX" } } => $"tx:{age}",
        _ => "other"
    }
}

func Extract(response: Response): int {
    return match response {
        Response.Ok { data: Option.Some { value } } => value,
        Response.Ok { data: Option.None } => 0,
        Response.Error { message } => -1
    }
}

func main() {
    ny := new Address { City: "New York", State: "NY" }
    ca := new Address { City: "San Francisco", State: "CA" }
    tx := new Address { City: "Austin", State: "TX" }

    print Classify(new Person { Name: "Ada", Age: 37, Address: ny })
    print Classify(new Person { Name: "Grace", Age: 41, Address: ca })
    print Classify(new Person { Name: "Lin", Age: 12, Address: tx })
    print Extract(new Response.Ok(new Option.Some(7)))
    print Extract(new Response.Ok(new Option.None()))
    print Extract(new Response.Error("bad"))
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "NestedPropertyPatternProject.dll");
            var result = compiler.CompileToIlAssembly("NestedPropertyPatternProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("ny\nca:San Francisco\ntx:12\n7\n0\n-1", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsConcreteTypeBindingPatterns()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: ConcreteTypePatternProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func ClassifyString(value: string): string {
    result := match value {
        string s when s.Length == 0 => "empty",
        string s when s.Length > 10 => "long",
        string s => $"short:{s}"
    }

    return result
}

func ClassifyNumber(value: int): string {
    result := match value {
        int n when n < 0 => "negative",
        int n when n == 0 => "zero",
        int n => $"positive:{n}"
    }

    return result
}

func CheckValue(value: string): string {
    result := match value {
        "special" => "special",
        string s when s.StartsWith("ERR") => "error",
        string s => $"regular:{s}"
    }

    return result
}

func main() {
    print ClassifyString("")
    print ClassifyString("abc")
    print ClassifyString("this is long")
    print ClassifyNumber(-5)
    print ClassifyNumber(0)
    print ClassifyNumber(12)
    print CheckValue("special")
    print CheckValue("ERR42")
    print CheckValue("ok")
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "ConcreteTypePatternProject.dll");
            var result = compiler.CompileToIlAssembly("ConcreteTypePatternProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("empty\nshort:abc\nlong\nnegative\nzero\npositive:12\nspecial\nerror\nregular:ok", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsGenericUnionPayloadFreeCallStyleAdoption()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: GenericUnionAdoptionProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
union Option<T> {
    Some { value: T }
    None
}

func FirstAbove(items: int[], threshold: int): Option<int> {
    for item in items {
        if item > threshold {
            return new Option.Some<int>(item)
        }
    }

    return new Option.None()
}

func main() {
    items := [1, 5, 9]
    found := match FirstAbove(items, 8) {
        Option.Some { value } => $"some:{value}",
        Option.None => "none"
    }
    print found

    missing := match FirstAbove(items, 100) {
        Option.Some { value } => $"some:{value}",
        Option.None => "none"
    }
    print missing
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "GenericUnionAdoptionProject.dll");
            var result = compiler.CompileToIlAssembly("GenericUnionAdoptionProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("some:9\nnone", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsStaticExpandedParamsCall()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: StaticExpandedParamsProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
class Mathy {
    static func Sum(params values: int[]): int {
        total := 0
        for value in values {
            total = total + value
        }
        return total
    }
}

func main() {
    print Mathy.Sum(1, 2, 3)
    print Mathy.Sum(5)
    print Mathy.Sum()
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "StaticExpandedParamsProject.dll");
            var result = compiler.CompileToIlAssembly("StaticExpandedParamsProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("6\n5\n0", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsSpreadArgumentForParamsArrayCall()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: SpreadParamsProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Sum(params values: int[]): int {
    total := 0
    for value in values {
        total = total + value
    }
    return total
}

func Format(prefix: string, suffix: string, params values: int[]): string {
    middle := ""
    for i := 0; i < values.Length; i++ {
        if i > 0 {
            middle += ", "
        }
        middle += values[i].ToString()
    }
    return prefix + middle + suffix
}

func PrintAll<T>(prefix: string, params items: T[]) {
    for item in items {
        print $"{prefix}{item}"
    }
}

func main() {
    numbers: int[] = [1, 2, 3, 4, 5]
    print Sum(...numbers)
    print Format("[", "]", ...numbers)
    PrintAll("v=", ...numbers)
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "SpreadParamsProject.dll");
            var result = compiler.CompileToIlAssembly("SpreadParamsProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("15\n[1, 2, 3, 4, 5]\nv=1\nv=2\nv=3\nv=4\nv=5", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsGenericExpandedParamsArrayCall()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: GenericExpandedParamsProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func PrintAll<T>(prefix: string, params items: T[]) {
    for item in items {
        print $"{prefix}{item}"
    }
}

func main() {
    PrintAll("n=", 1, 2, 3, 4, 5)
    PrintAll("s=", "Alice", "Bob")
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "GenericExpandedParamsProject.dll");
            var result = compiler.CompileToIlAssembly("GenericExpandedParamsProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("n=1\nn=2\nn=3\nn=4\nn=5\ns=Alice\ns=Bob", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsGenericStringJoinForArray()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: GenericStringJoinProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func main() {
    values := new int[3]
    values[0] = 2
    values[1] = 4
    values[2] = 6
    print String.Join(", ", values)
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "GenericStringJoinProject.dll");
            var result = compiler.CompileToIlAssembly("GenericStringJoinProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("2, 4, 6", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsStringJoinOverSelectWithInterpolatedLambda()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: StringJoinSelectProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System.Collections.Generic
import System.Linq

func FormatTags(tags: List<string>): string {
    if tags.Count == 0 {
        return "-"
    }

    return String.Join(" ", tags.Select(tag => $"#{tag}"))
}

func main() {
    tags: List<string> = ["alpha", "beta"]
    print FormatTags(tags)
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "StringJoinSelectProject.dll");
            var result = compiler.CompileToIlAssembly("StringJoinSelectProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("#alpha #beta", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsExplicitGenericJsonSerializerSerialize()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: GenericJsonSerializeProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System.Text.Json

func main() {
    options := new JsonSerializerOptions()
    json := JsonSerializer.Serialize<object>(42, options)
    print json
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "GenericJsonSerializeProject.dll");
            var result = compiler.CompileToIlAssembly("GenericJsonSerializeProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("42", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsExpandedParamsCollections()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: ExpandedParamsCollectionsProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System.Collections.Generic

func SumArray(params numbers: int[]): int {
    total := 0
    for number in numbers {
        total = total + number
    }
    return total
}

func SumReadOnlySpan(params numbers: ReadOnlySpan<int>): int {
    total := 0
    for i := 0; i < numbers.Length; i++ {
        total = total + numbers[i]
    }
    return total
}

func CountAll(params items: IEnumerable<string>): int {
    count := 0
    for item in items {
        count = count + 1
    }
    return count
}

func FormatItems(separator: string, params items: IReadOnlyList<string>): string {
    result := items[0]
    for i := 1; i < items.Count; i++ {
        result = result + separator + items[i]
    }
    return result
}

func BuildList(params items: List<int>): List<int> {
    return items
}

func main() {
    print SumArray(1, 2, 3)
    print SumArray()
    print SumReadOnlySpan(4, 5, 6)
    print CountAll("a", "b", "c")
    print FormatItems("-", "left", "right")
    list := BuildList(10, 20, 30)
    print list.Count
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "ExpandedParamsCollectionsProject.dll");
            var result = compiler.CompileToIlAssembly("ExpandedParamsCollectionsProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("6\n0\n15\n3\nleft-right\n3", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsSpanIndexReadWrite()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: SpanIndexProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
func Modify(values: Span<int>) {
    for i := 0; i < values.Length; i++ {
        values[i] = values[i] * 2
    }
}

func main() {
    values := new int[3]
    values[0] = 1
    values[1] = 2
    values[2] = 3
    Modify(values)
    print $"{values[0]}:{values[1]}:{values[2]}"
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "SpanIndexProject.dll");
            var result = compiler.CompileToIlAssembly("SpanIndexProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("2:4:6", runResult.Stdout.Replace("\r\n", "\n").Trim());
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
    public void MultiFileCompiler_EmitsTargetTypedListLiteral()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: ListLiteralProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System.Collections.Generic

func main() {
    list1: List<int> = [1, 2, 3]
    list2: List<int> = [4, 5]
    lists := new List<List<int>>()
    lists.Add(list1)
    lists.Add(list2)

    print list1.Count
    print list2.Count
    print lists.Count
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "ListLiteralProject.dll");
            var result = compiler.CompileToIlAssembly("ListLiteralProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("3\n2\n2", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsTargetTypedHashSetLiteral()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: HashSetLiteralProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System.Collections.Generic

func main() {
    names: HashSet<string> = ["Alice", "Bob", "Alice"]
    print names.Count
    print names.Contains("Bob")
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "HashSetLiteralProject.dll");
            var result = compiler.CompileToIlAssembly("HashSetLiteralProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("2\nTrue", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsSortedDictionaryIndexerAccess()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: SortedDictionaryProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System.Collections.Generic

func main() {
    sorted := new SortedDictionary<string, string>()
    sorted["zebra"] = "Striped animal"
    sorted["apple"] = "Red fruit"
    sorted.Add("berry", "Small fruit")
    removed := sorted.Remove("zebra")

    print sorted.Count
    print sorted.ContainsKey("berry")
    print removed
    print sorted["apple"]
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "SortedDictionaryProject.dll");
            var result = compiler.CompileToIlAssembly("SortedDictionaryProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("2\nTrue\nTrue\nRed fruit", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsParameterlessValueStructConstruction()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: ParameterlessStructProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
struct Buffer10 {
    element: int
}

func main() {
    buffer := new Buffer10()
    print "created"
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "ParameterlessStructProject.dll");
            var result = compiler.CompileToIlAssembly("ParameterlessStructProject", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("created", runResult.Stdout.Replace("\r\n", "\n").Trim());
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
    public void MultiFileCompiler_EmitsNestedEnumMembersOnClasses()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: NestedEnumClassProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
class Account {
    enum Status {
        Active,
        Frozen,
        Closed
    }

    class Transaction {
        Amount: int
    }

    CurrentStatus: Account.Status

    constructor() {
        CurrentStatus = Account.Status.Active
    }

    func Freeze() {
        CurrentStatus = Account.Status.Frozen
    }

    func Label(): string {
        return $"{CurrentStatus}"
    }
}

func main() {
    account := new Account()
    print account.Label()
    account.Freeze()
    print account.Label()
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "NestedEnumClassProject.dll");
            var result = compiler.CompileToIlAssembly("NestedEnumClassProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("Active\nFrozen", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_EmitsBareInstancePropertyAssignmentInMethods()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: BarePropertyAssignmentProject
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
class Account {
    balance: double

    Balance: double {
        get { return balance }
        set { balance = value }
    }

    constructor(initial: double) {
        balance = initial
    }

    func Deposit(amount: double) {
        Balance = Balance + amount
    }
}

func main() {
    account := new Account(100.0)
    account.Deposit(25.0)
    print account.Balance
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "BarePropertyAssignmentProject.dll");
            var result = compiler.CompileToIlAssembly("BarePropertyAssignmentProject", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("125", runResult.Stdout.Trim());
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
    public void MultiFileCompiler_EmitsMathAtan2StaticCall()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: MathAtan2Project
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System

func main() {
    print Math.Atan2(4.0, 3.0)
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "MathAtan2Project.dll");
            var result = compiler.CompileToIlAssembly("MathAtan2Project", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Contains("0.927", runResult.Stdout.Replace("\r\n", "\n").Trim());
        }
        finally
        {
            Directory.Delete(tempDir, true);
        }
    }

    [Fact]
    public void MultiFileCompiler_AllowsStructPrimaryConstructorParametersInMembers()
    {
        var tempDir = CreateTempDir();
        try
        {
            File.WriteAllText(Path.Combine(tempDir, "project.yml"), """
name: StructPrimaryCtorMembers
backend: il
outputType: exe
targetFramework: net10.0
""");
            File.WriteAllText(Path.Combine(tempDir, "Program.nl"), """
import System

struct Point(x: double, y: double) {
    func Distance(): double {
        return Math.Sqrt(x * x + y * y)
    }

    func Label(): string {
        return $"Point({x}, {y})"
    }
}

func main() {
    point := new Point(3.0, 4.0)
    print point.Distance()
    print point.Label()
}
""");

            var config = ProjectFileParser.Parse(Path.Combine(tempDir, "project.yml"));
            var outputDir = Path.Combine(tempDir, "artifacts");
            Directory.CreateDirectory(outputDir);

            var compiler = new MultiFileCompiler(tempDir, config);
            var outputPath = Path.Combine(outputDir, "StructPrimaryCtorMembers.dll");
            var result = compiler.CompileToIlAssembly("StructPrimaryCtorMembers", outputPath);

            Assert.True(result.Success);
            CompilationArtifacts.WriteRuntimeConfig(config, outputPath);

            var runResult = DotnetRunner.Run($"\"{outputPath}\"", workingDirectory: tempDir);
            Assert.Equal(0, runResult.ExitCode);
            Assert.Equal("5\nPoint(3, 4)", runResult.Stdout.Replace("\r\n", "\n").Trim());
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
