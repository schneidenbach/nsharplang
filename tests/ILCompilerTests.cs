using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.ExceptionServices;
using System.Threading.Tasks;
using System.Runtime.Loader;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.ILCompiler;
using NSharpLang.Tests.PerfEvidence;
using Xunit;

namespace NSharpLang.Tests;

public delegate Task ExternalRequestDelegate(object context);

public static class DelegateInteropProbe
{
    public static string Capture(ExternalRequestDelegate handler)
    {
        return handler.GetType().FullName ?? string.Empty;
    }

    public static string CaptureAspNet(RequestDelegate handler)
    {
        return handler.GetType().FullName ?? string.Empty;
    }

    public static string CaptureAspNetFunc(Func<HttpContext, Task> handler)
    {
        return handler.GetType().FullName ?? string.Empty;
    }

    public static string CaptureDelegate(Delegate handler)
    {
        return handler.GetType().FullName ?? string.Empty;
    }

    public static int MaterializeAspNetEndpoints(IEndpointRouteBuilder app)
    {
        return app.DataSources.Sum(dataSource => dataSource.Endpoints.Count);
    }

    public static string CaptureAspNetResponse(RequestDelegate handler)
    {
        var context = new DefaultHttpContext();
        using var responseBody = new MemoryStream();
        context.Response.Body = responseBody;

        handler(context).GetAwaiter().GetResult();

        responseBody.Position = 0;
        using var reader = new StreamReader(responseBody);
        return reader.ReadToEnd();
    }
}

public partial class ILCompilerTests
{
    private static AssemblyLoadContext CreateTestLoadContext()
    {
        var loadContext = new AssemblyLoadContext($"ILCompilerTests_{Guid.NewGuid():N}", isCollectible: true);
        var testAssembly = typeof(ILCompilerTests).Assembly;
        var testAssemblyName = testAssembly.GetName().Name;
        var runtimeAssembly = typeof(NSharpLang.Runtime.Union<,>).Assembly;
        var runtimeAssemblyName = runtimeAssembly.GetName().Name;

        loadContext.Resolving += (_, assemblyName) =>
        {
            if (string.Equals(assemblyName.Name, testAssemblyName, StringComparison.Ordinal))
                return testAssembly;

            if (string.Equals(assemblyName.Name, runtimeAssemblyName, StringComparison.Ordinal))
                return runtimeAssembly;

            return null;
        };

        return loadContext;
    }

    private CompilationUnit Parse(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        var result = parser.ParseCompilationUnit();
        return result.CompilationUnit!; // Tests expect valid syntax
    }

    private object? CompileAndInvoke(string source, string functionName = "main", params object[] args)
    {
        var compilationUnit = Parse(source);
        return CompileAndInvoke(compilationUnit, functionName, args);
    }

    private object? CompileAndInvoke(string source, ProjectConfig config, string functionName = "main", params object[] args)
    {
        var compilationUnit = Parse(source);
        return CompileAndInvoke(compilationUnit, config, functionName, args);
    }

    private object? CompileAndInvoke(CompilationUnit compilationUnit, string functionName = "main", params object[] args)
    {
        return CompileAndInvoke(compilationUnit, null, functionName, args);
    }

    private object? CompileAndInvoke(CompilationUnit compilationUnit, ProjectConfig? config, string functionName = "main", params object[] args)
    {
        var outputPath = Path.Combine(Path.GetTempPath(), $"ILCompilerTest_{Guid.NewGuid():N}.dll");
        var assemblyName = $"ILCompilerTest_{Guid.NewGuid():N}";
        AssemblyLoadContext? loadContext = null;

        try
        {
            var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, assemblyName, outputPath, config);
            compiler.Compile();

            var assemblyBytes = File.ReadAllBytes(outputPath);
            loadContext = CreateTestLoadContext();
            using var stream = new MemoryStream(assemblyBytes);
            var assembly = loadContext.LoadFromStream(stream);

            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);

            var method = programType!.GetMethod(functionName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(method);

            return method!.Invoke(null, args);
        }
        catch (TargetInvocationException ex) when (ex.InnerException != null)
        {
            ExceptionDispatchInfo.Capture(ex.InnerException).Throw();
            throw;
        }
        finally
        {
            if (File.Exists(outputPath))
            {
                File.Delete(outputPath);
            }
        }
    }

    private async Task<object?> CompileAndInvokeTaskResult(string source, string functionName = "main", params object[] args)
    {
        var result = CompileAndInvoke(source, functionName, args);
        var task = Assert.IsAssignableFrom<Task>(result);
        await task;

        var resultProperty = task.GetType().GetProperty("Result", BindingFlags.Public | BindingFlags.Instance);
        return resultProperty?.GetValue(task);
    }

    private T CompileAndInspect<T>(string source, Func<Assembly, T> inspector)
    {
        return CompileAndInspect(source, null, inspector);
    }

    private T CompileAndInspect<T>(string source, ProjectConfig? config, Func<Assembly, T> inspector)
    {
        var outputPath = Path.Combine(Path.GetTempPath(), $"ILCompilerInspect_{Guid.NewGuid():N}.dll");
        var assemblyName = $"ILCompilerInspect_{Guid.NewGuid():N}";
        AssemblyLoadContext? loadContext = null;

        try
        {
            var compilationUnit = Parse(source);
            var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, assemblyName, outputPath, config);
            compiler.Compile();

            var assemblyBytes = File.ReadAllBytes(outputPath);
            loadContext = CreateTestLoadContext();
            using var stream = new MemoryStream(assemblyBytes);
            var assembly = loadContext.LoadFromStream(stream);
            return inspector(assembly);
        }
        finally
        {
            loadContext?.Unload();
            if (File.Exists(outputPath))
            {
                File.Delete(outputPath);
            }
        }
    }

    private static IReadOnlyList<byte> GetNullableAttributeFlags(IEnumerable<CustomAttributeData> attributes)
    {
        var nullableAttribute = attributes.FirstOrDefault(attribute =>
            attribute.AttributeType.FullName == "System.Runtime.CompilerServices.NullableAttribute");
        if (nullableAttribute == null || nullableAttribute.ConstructorArguments.Count == 0)
            return Array.Empty<byte>();

        var argument = nullableAttribute.ConstructorArguments[0];
        if (argument.ArgumentType == typeof(byte) && argument.Value is byte singleFlag)
            return new[] { singleFlag };

        if (argument.Value is IEnumerable<CustomAttributeTypedArgument> array)
            return array.Select(item => (byte)item.Value!).ToArray();

        return Array.Empty<byte>();
    }

    [Fact]
    public void UserDefinedOk_InResultPosition_CallsUserFunction()
    {
        // C1: a user-declared `Ok` returning Result must be invoked even in a Result-typed
        // return position, instead of being lowered as the compiler-known Result factory.
        // User Ok returns Err("user-ok"), so the result must be Err (-> 111), not a success.
        var source = @"
func Ok(n: int): Result<int, string> {
    return Err(""user-ok"")
}

func make(): Result<int, string> {
    return Ok(5)
}

func main(): int {
    r := make()
    if r.IsErr {
        return 111
    }
    return 222
}
";
        Assert.Equal(111, CompileAndInvoke(source, "main"));
    }

    [Fact]
    public void GenuineResultFactory_StillConstructsResult()
    {
        // C1 must not break the real factory: with no user Ok/Err in scope, Ok(7) builds a
        // success Result whose value is 7.
        var source = @"
func make(): Result<int, string> {
    return Ok(7)
}

func main(): int {
    r := make()
    if r.IsOk {
        return r.OkValueUnchecked
    }
    return -1
}
";
        Assert.Equal(7, CompileAndInvoke(source, "main"));
    }

    [Fact]
    public void LibraryImportDeclarationsEmitPInvokeMetadataWithoutManagedBody()
    {
        var source = @"
import System.Runtime.InteropServices

[LibraryImport(""c"", EntryPoint = ""strlen"")]
func StringLength(value: string): int

static class NativeMethods {
    [LibraryImport(""c"", EntryPoint = ""open"")]
    static func Open(path: string, flags: int): int
}
";

        var methods = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);
            var topLevel = programType!.GetMethod("StringLength", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(topLevel);

            var nativeType = assembly.GetType("NativeMethods");
            Assert.NotNull(nativeType);
            var nested = nativeType!.GetMethod("Open", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(nested);

            return new[] { topLevel!, nested! };
        });

        foreach (var method in methods)
        {
            Assert.True(method.IsStatic);
            Assert.Null(method.GetMethodBody());
        }
    }

    private static async Task AwaitTaskLikeResult(object? result)
    {
        switch (result)
        {
            case null:
                return;
            case Task task:
                await task;
                return;
            case ValueTask valueTask:
                await valueTask;
                return;
        }

        var resultType = result.GetType();
        if (resultType.IsGenericType && resultType.GetGenericTypeDefinition() == typeof(ValueTask<>))
        {
            var asTaskMethod = resultType.GetMethod(nameof(ValueTask.AsTask), BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(asTaskMethod);
            await Assert.IsType<Task>(asTaskMethod!.Invoke(result, null));
            return;
        }

        throw new InvalidOperationException($"Expected task-like result but got {resultType.FullName}");
    }

    private static async Task InvokeAndAwaitAsyncMethod(object instance, string methodName)
    {
        var method = instance.GetType().GetMethod(methodName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.NotNull(method);
        await AwaitTaskLikeResult(method!.Invoke(instance, null));
    }

    private static CustomAttributeData GetCustomAttribute(MemberInfo member, string fullName)
    {
        return Assert.Single(member.CustomAttributes.Where(attribute => attribute.AttributeType.FullName == fullName));
    }

    private static object? GetNamedAttributeValue(CustomAttributeData attribute, string memberName)
    {
        return Assert.Single(attribute.NamedArguments.Where(argument => argument.MemberName == memberName)).TypedValue.Value;
    }

    private static object?[] GetAttributeArguments(CustomAttributeData attribute)
    {
        return attribute.ConstructorArguments.Select(UnwrapAttributeValue).ToArray();
    }

    private static object? UnwrapAttributeValue(CustomAttributeTypedArgument argument)
    {
        if (argument.Value is IReadOnlyCollection<CustomAttributeTypedArgument> collection)
        {
            return collection.Select(UnwrapAttributeValue).ToArray();
        }

        return argument.Value;
    }

    private static IReadOnlyList<OpCode> GetMethodOpCodes(MethodInfo method)
    {
        var il = method.GetMethodBody()?.GetILAsByteArray() ?? Array.Empty<byte>();
        var opCodes = new List<OpCode>();

        for (var offset = 0; offset < il.Length;)
        {
            var opCodeValue = il[offset++];
            OpCode opCode;
            if (opCodeValue == 0xfe)
            {
                opCode = MultiByteOpCodes[il[offset++]];
            }
            else
            {
                opCode = SingleByteOpCodes[opCodeValue];
            }

            opCodes.Add(opCode);
            offset += GetOperandSize(opCode.OperandType, il, offset);
        }

        return opCodes;
    }

    private static readonly OpCode[] SingleByteOpCodes = new OpCode[0x100];
    private static readonly OpCode[] MultiByteOpCodes = new OpCode[0x100];

    static ILCompilerTests()
    {
        foreach (var field in typeof(OpCodes).GetFields(BindingFlags.Public | BindingFlags.Static))
        {
            if (field.GetValue(null) is not OpCode opCode)
            {
                continue;
            }

            var value = unchecked((ushort)opCode.Value);
            if (value < 0x100)
            {
                SingleByteOpCodes[value] = opCode;
            }
            else if ((value & 0xff00) == 0xfe00)
            {
                MultiByteOpCodes[value & 0xff] = opCode;
            }
        }
    }

    private static int GetOperandSize(OperandType operandType, byte[] il, int offset) => operandType switch
    {
        OperandType.InlineNone => 0,
        OperandType.ShortInlineBrTarget or OperandType.ShortInlineI or OperandType.ShortInlineVar => 1,
        OperandType.InlineVar => 2,
        OperandType.InlineBrTarget or OperandType.InlineField or OperandType.InlineI or OperandType.InlineMethod
            or OperandType.InlineSig or OperandType.InlineString or OperandType.InlineTok or OperandType.InlineType
            or OperandType.ShortInlineR => 4,
        OperandType.InlineSwitch => 4 + (BitConverter.ToInt32(il, offset) * 4),
        OperandType.InlineI8 or OperandType.InlineR => 8,
        _ => throw new NotSupportedException($"Unsupported IL operand type {operandType}")
    };

    [Fact]
    public void ILCompiler_CanBeConstructed()
    {
        var source = "func main() { }";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        Assert.NotNull(compiler);
    }

    [Fact]
    public void ILCompiler_CanCompileEmptyFunction()
    {
        var source = "func main() { }";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_InterpolatedStringHole_EmitsExpressionValue()
    {
        var result = CompileAndInvoke("""
func main(): string {
    name := "Spencer"
    return $"Hello, {name}!"
}
""");

        Assert.Equal("Hello, Spencer!", result);
    }

    [Fact]
    public void ILCompiler_InterpolatedStringEscapedBraces_EmitLiteralBracesAroundHole()
    {
        var result = CompileAndInvoke("""
func main(): string {
    name := "Spencer"
    return $"{{ {name} }}"
}
""");

        Assert.Equal("{ Spencer }", result);
    }

    [Fact]
    public void ILCompiler_InterpolatedRawStringHole_EmitsExpressionValue()
    {
        var result = CompileAndInvoke(""""
func main(): string {
    name := "Spencer"
    return $"""
Hello, {name}!
"""
}
"""");

        Assert.Contains("Hello, Spencer!", Assert.IsType<string>(result), StringComparison.Ordinal);
    }

    [Fact]
    public void ILCompiler_InterpolatedString_ValueTypeAndStringHoles_MatchesCSharp()
    {
        var result = CompileAndInvoke("""
func main(): string {
    count := 7
    name := "Spencer"
    ratio := 3.14159
    return $"User {name} has {count} items at ratio {ratio}"
}
""");

        // Parity with the equivalent C# interpolated string.
        const int count = 7;
        const string name = "Spencer";
        const double ratio = 3.14159;
        Assert.Equal($"User {name} has {count} items at ratio {ratio}", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_InterpolatedString_FormatClauses_AreCultureCorrect()
    {
        var result = CompileAndInvoke("""
func main(): string {
    count := 255
    ratio := 3.14159
    return $"hex={count:X} pi={ratio:F2}"
}
""");

        const int count = 255;
        const double ratio = 3.14159;
        Assert.Equal($"hex={count:X} pi={ratio:F2}", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_InterpolatedString_LiteralOnly_ReturnsConstant()
    {
        var result = CompileAndInvoke("""
func main(): string {
    return $"just literal text"
}
""");

        Assert.Equal("just literal text", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_InterpolatedString_ReadOnlySpanOfCharHole_MatchesCSharp()
    {
        // ReadOnlySpan<char> is a byref-like ref struct and cannot flow through AppendFormatted<T>;
        // it must route to the dedicated AppendFormatted(ReadOnlySpan<char>) overload like C# does.
        var result = CompileAndInvoke("""
import System

func main(): string {
    text := "hello world"
    span := text.AsSpan()
    count := 42
    return $"[{span}] count={count} hex={count:X}"
}
""");

        var text = "hello world";
        ReadOnlySpan<char> span = text.AsSpan();
        const int count = 42;
        Assert.Equal($"[{span}] count={count} hex={count:X}", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanCompileFunctionWithReturn()
    {
        var source = @"
func add(x: int, y: int): int {
    return x + y
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileVariableDeclaration()
    {
        var source = @"
func myFunc() {
    x := 5
    y := 10
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileBinaryExpression()
    {
        var source = @"
func calculate(): int {
    return 5 + 3
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompilePrintStatement()
    {
        var source = @"
func main() {
    print ""Hello from IL!""
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileIfStatement()
    {
        var source = @"
func checkValue(x: int): int {
    if x > 5 {
        return 10
    } else {
        return 0
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_IfElseBothBranchesReturn_NoTrailingStatement_IsRunnable()
    {
        // Regression: a function whose body is an if/else where BOTH branches return and nothing
        // follows the `if` used to emit a dead `br` over the else-block to an end-label marked at
        // the very end of the method -- i.e. a branch to an offset with no instruction. That IL
        // crashed ilverify (MarkPredecessorWithLowerOffset) and faulted the JIT with
        // InvalidProgramException the moment the method was INVOKED, even though the source is valid
        // (definite return is satisfied by both arms). The prior `ILCompiler_CanCompileIfStatement`
        // coverage only called Compile() and never invoked the method, so the bad IL slipped through;
        // this invokes it. EmitIf now elides the skip-branch when the then-branch can't fall through.
        var max = "func max(a: int, b: int): int {\n    if a > b {\n        return a\n    } else {\n        return b\n    }\n}\n";
        Assert.Equal(5, (int)CompileAndInvoke(max, "max", 3, 5)!);
        Assert.Equal(5, (int)CompileAndInvoke(max, "max", 5, 3)!);
        Assert.Equal(4, (int)CompileAndInvoke(max, "max", 4, 4)!);

        // The same shape one level deeper: a nested if/else whose every arm returns, nothing after.
        var sign = "func sign(a: int): int {\n    if a > 0 {\n        return 1\n    } else {\n        if a < 0 {\n            return 0 - 1\n        } else {\n            return 0\n        }\n    }\n}\n";
        Assert.Equal(1, (int)CompileAndInvoke(sign, "sign", 9)!);
        Assert.Equal(-1, (int)CompileAndInvoke(sign, "sign", -9)!);
        Assert.Equal(0, (int)CompileAndInvoke(sign, "sign", 0)!);
    }

    [Fact]
    public void ILCompiler_CanCompileWhileLoop()
    {
        var source = @"
func countTo10(): int {
    x := 0
    while x < 10 {
        x := x + 1
    }
    return x
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileComplexProgram()
    {
        var source = @"
func fibonacci(n: int): int {
    if n <= 1 {
        return n
    }
    return fibonacci(n - 1) + fibonacci(n - 2)
}

func main() {
    result := fibonacci(10)
    print result
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileVariableAssignment()
    {
        var source = @"
func testAssignment(): int {
    x := 5
    x = 10
    return x
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileCompoundAssignment()
    {
        var source = @"
func testCompoundAssignment(): int {
    x := 5
    x += 3
    x -= 2
    x *= 2
    x /= 3
    return x
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_SavesAssemblyToDisk()
    {
        var outputPath = Path.Combine(Path.GetTempPath(), "ILCompilerTest_" + Guid.NewGuid() + ".dll");
        try
        {
            var source = @"
func add(x: int, y: int): int {
    return x + y
}";
            var compilationUnit = Parse(source);
            var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", outputPath);

            compiler.Compile();

            // Verify that the file was created
            Assert.True(File.Exists(outputPath), $"Assembly file should exist at {outputPath}");

            // Verify that the file has content
            var fileInfo = new FileInfo(outputPath);
            Assert.True(fileInfo.Length > 0, "Assembly file should not be empty");
        }
        finally
        {
            // Clean up
            if (File.Exists(outputPath))
            {
                File.Delete(outputPath);
            }
        }
    }

    [Fact]
    public void ILCompiler_CanCompileSimpleClass()
    {
        var source = @"
class Point {
    X: int
    Y: int
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileClassWithConstructor()
    {
        var source = @"
class Point {
    X: int
    Y: int

    constructor(x: int, y: int) {
        this.X = x
        this.Y = y
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileClassWithMethod()
    {
        var source = @"
class Calculator {
    func Add(x: int, y: int): int {
        return x + y
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileClassInstantiation()
    {
        var source = @"
class Point {
    X: int
    Y: int

    constructor(x: int, y: int) {
        this.X = x
        this.Y = y
    }
}

func main() {
    p := new Point(3, 4)
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileFieldAccess()
    {
        var source = @"
class Point {
    X: int
    Y: int

    constructor(x: int, y: int) {
        this.X = x
        this.Y = y
    }
}

func main() {
    p := new Point(3, 4)
    x := p.X
    y := p.Y
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_EmitsVerifiableIl_ForFieldsNamedLikeIlAsmKeywords()
    {
        // `value` and `method` are reserved words in ILAsm textual syntax but are valid
        // field names in CLR metadata and are NOT N# keywords. They must compile to
        // verifiable IL and round-trip correctly through field load/store (no
        // InvalidProgramException). Regression guard alongside NL109, which rejects the
        // genuinely-reserved N# keywords (base/this/...) at parse time instead.
        var source = @"
class Box {
    value: int
    method: int
    constructor(v: int, m: int) {
        this.value = v
        this.method = m
    }
    func sum(): int { return this.value + this.method }
}

func main(): int {
    b := new Box(7, 3)
    return b.sum()
}";
        Assert.Equal(10, Assert.IsType<int>(CompileAndInvoke(source, "main")));
    }

    [Fact]
    public void ILCompiler_CanCompileInstanceMethodCall()
    {
        var source = @"
class Calculator {
    func Add(x: int, y: int): int {
        return x + y
    }
}

func main(): int {
    calc := new Calculator()
    return calc.Add(5, 3)
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileComplexClassProgram()
    {
        var source = @"
class Point {
    X: int
    Y: int

    constructor(x: int, y: int) {
        this.X = x
        this.Y = y
    }

    func DistanceSquared(): int {
        return this.X * this.X + this.Y * this.Y
    }
}

func main() {
    p := new Point(3, 4)
    dist := p.DistanceSquared()
    print dist
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileStruct()
    {
        // A struct constructed with a user constructor whose body writes `this.`-qualified fields,
        // then read back through a `this.`-qualified instance method. This must produce the real
        // sum (7), not garbage: arg0 of a value-type method/ctor is the receiver's managed pointer,
        // so the receiver address must come straight from arg0, never a spilled copy.
        var source = @"
struct Point {
    X: int
    Y: int

    constructor(x: int, y: int) {
        this.X = x
        this.Y = y
    }

    func Sum(): int {
        return this.X + this.Y
    }
}

func main(): int {
    p := new Point(3, 4)
    return p.Sum()
}";
        Assert.Equal(7, CompileAndInvoke(source, "main"));
    }

    // Regression coverage for a value-type `this.`-qualified field read/write emitting against a
    // throwaway copy instead of the receiver's real storage. Cross every combination of how the
    // struct local is constructed (user constructor vs object initializer) with how its fields are
    // accessed (`this.`-qualified vs bare). All must agree on the same arithmetic result; before the
    // fix the `this.`-qualified READS returned pointer-derived garbage and the `this.`-qualified
    // constructor WRITES were silently dropped (leaving the fields at their zero default).
    [Theory]
    // user constructor (this-qualified writes) + this-qualified read.
    [InlineData("struct Rect {\n    W: int\n    H: int\n    constructor(w: int, h: int) {\n        this.W = w\n        this.H = h\n    }\n    func area(): int {\n        return this.W * this.H\n    }\n}\n\nfunc main(): int {\n    r := new Rect(3, 4)\n    return r.area()\n}\n")]
    // user constructor (this-qualified writes) + bare read.
    [InlineData("struct Rect {\n    W: int\n    H: int\n    constructor(w: int, h: int) {\n        this.W = w\n        this.H = h\n    }\n    func area(): int {\n        return W * H\n    }\n}\n\nfunc main(): int {\n    r := new Rect(3, 4)\n    return r.area()\n}\n")]
    // user constructor (bare writes) + bare read.
    [InlineData("struct Rect {\n    W: int\n    H: int\n    constructor(w: int, h: int) {\n        W = w\n        H = h\n    }\n    func area(): int {\n        return W * H\n    }\n}\n\nfunc main(): int {\n    r := new Rect(3, 4)\n    return r.area()\n}\n")]
    // object-initializer local + this-qualified read.
    [InlineData("struct Rect {\n    W: int\n    H: int\n    func area(): int {\n        return this.W * this.H\n    }\n}\n\nfunc main(): int {\n    r := new Rect { W: 3, H: 4 }\n    return r.area()\n}\n")]
    // object-initializer local + bare read.
    [InlineData("struct Rect {\n    W: int\n    H: int\n    func area(): int {\n        return W * H\n    }\n}\n\nfunc main(): int {\n    r := new Rect { W: 3, H: 4 }\n    return r.area()\n}\n")]
    public void ILCompiler_StructInstanceMethodReceiver_ReadsRealStorage(string source)
    {
        Assert.Equal(12, CompileAndInvoke(source, "main"));
    }

    [Fact]
    public void ILCompiler_StructMethodMutatesReceiverInPlace()
    {
        // A struct instance method that WRITES `this.`-qualified fields must mutate the caller's
        // local in place (the receiver address is the local's slot), so a follow-up read observes
        // the new values. Confirms the write lands in real storage rather than a discarded copy.
        var source = @"
struct Counter {
    N: int

    constructor(start: int) {
        this.N = start
    }

    func bump(): void {
        this.N = this.N + 1
    }

    func get(): int {
        return this.N
    }
}

func main(): int {
    c := new Counter(10)
    c.bump()
    c.bump()
    return c.get()
}";
        Assert.Equal(12, CompileAndInvoke(source, "main"));
    }

    [Fact]
    public void ILCompiler_CanCompileGenericFunction()
    {
        var source = @"
func identity<T>(value: T): T {
    return value
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileGenericFunctionWithConstraint()
    {
        var source = @"
func compare<T>(a: T, b: T): int where T: IComparable<T> {
    return a.CompareTo(b)
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_EmitsSpecialGenericConstraints()
    {
        var source = @"
func referenceOnly<T>(value: T): T where T : class {
    return value
}

func valueOnly<T>(value: T): T where T : struct {
    return value
}

func create<T>(): T where T : new() {
    return new T()
}

func constrained<T>(value: T): T where T : class, IComparable {
    return value
}";

        CompileAndInspect<int>(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);

            var referenceOnly = programType!.GetMethod("referenceOnly", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            var referenceParam = Assert.Single(referenceOnly!.GetGenericArguments());
            Assert.True(referenceParam.GenericParameterAttributes.HasFlag(GenericParameterAttributes.ReferenceTypeConstraint));

            var valueOnly = programType.GetMethod("valueOnly", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            var valueParam = Assert.Single(valueOnly!.GetGenericArguments());
            Assert.True(valueParam.GenericParameterAttributes.HasFlag(GenericParameterAttributes.NotNullableValueTypeConstraint));
            Assert.True(valueParam.GenericParameterAttributes.HasFlag(GenericParameterAttributes.DefaultConstructorConstraint));

            var create = programType.GetMethod("create", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            var createParam = Assert.Single(create!.GetGenericArguments());
            Assert.True(createParam.GenericParameterAttributes.HasFlag(GenericParameterAttributes.DefaultConstructorConstraint));

            var constrained = programType.GetMethod("constrained", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            var constrainedParam = Assert.Single(constrained!.GetGenericArguments());
            Assert.True(constrainedParam.GenericParameterAttributes.HasFlag(GenericParameterAttributes.ReferenceTypeConstraint));
            Assert.Contains(constrainedParam.GetGenericParameterConstraints(), constraint => constraint == typeof(IComparable));

            return 0;
        });
    }

    [Fact]
    public void ILCompiler_EmitsNullableMetadataForPublicApi()
    {
        var source = @"
class Customer {
    Name: string
    Nickname: string?

    func Rename(name: string, nickname: string?): string? {
        return nickname
    }
}";

        CompileAndInspect(source, assembly =>
        {
            var customer = assembly.GetType("Customer");
            Assert.NotNull(customer);

            var context = new NullabilityInfoContext();
            var name = customer!.GetProperty("Name", BindingFlags.Public | BindingFlags.Instance);
            var nickname = customer.GetProperty("Nickname", BindingFlags.Public | BindingFlags.Instance);
            var rename = customer.GetMethod("Rename", BindingFlags.Public | BindingFlags.Instance);

            Assert.NotNull(name);
            Assert.NotNull(nickname);
            Assert.NotNull(rename);

            Assert.Equal(NullabilityState.NotNull, context.Create(name!).ReadState);
            Assert.Equal(NullabilityState.Nullable, context.Create(nickname!).ReadState);
            Assert.Equal(NullabilityState.Nullable, context.Create(rename!.ReturnParameter).ReadState);
            Assert.Equal(NullabilityState.NotNull, context.Create(rename.GetParameters()[0]).ReadState);
            Assert.Equal(NullabilityState.Nullable, context.Create(rename.GetParameters()[1]).ReadState);
            Assert.Equal(new byte[] { 2 }, GetNullableAttributeFlags(rename.ReturnParameter.GetCustomAttributesData()));
            Assert.Equal(new byte[] { 2 }, GetNullableAttributeFlags(rename.GetParameters()[1].GetCustomAttributesData()));

            return 0;
        });
    }

    [Fact]
    public void ILCompiler_CanExecuteGenericNewConstraintConstruction()
    {
        var source = @"
class Widget {
    Value: int
}

func create<T>(): T where T : class, new() {
    return new T()
}

func main(): int {
    widget := create<Widget>()
    return widget.Value
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(0, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanCompileGenericFunctionWithMultipleParameters()
    {
        var source = @"
func swap<T, U>(first: T, second: U): bool {
    return true
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileGenericFunctionWithLocalVariables()
    {
        var source = @"
func process<T>(value: T): T {
    temp := value
    return temp
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileForeachOverArray()
    {
        var source = @"
func sumArray(numbers: int[]): int {
    sum := 0
    foreach num in numbers {
        sum = sum + num
    }
    return sum
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_ForeachOverArray_UsesAllocationFreeIndexLoop()
    {
        // foreach over a T[] must lower to an ldlen + index loop with NO enumerator:
        // no GetEnumerator call (callvirt) and no enumerator allocation (newobj).
        var source = @"
func sumArray(numbers: int[]): int {
    sum := 0
    foreach num in numbers {
        sum = sum + num
    }
    return sum
}";

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var method = assembly.GetType("Program")!
                .GetMethod("sumArray", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(method);
            return GetMethodOpCodes(method!);
        });

        Assert.Contains(OpCodes.Ldlen, opCodes);
        Assert.Contains(OpCodes.Ldelem_I4, opCodes);
        // No enumerator allocation and no GetEnumerator/MoveNext calls.
        Assert.DoesNotContain(OpCodes.Newobj, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
        Assert.DoesNotContain(OpCodes.Call, opCodes);
    }

    [Fact]
    public void ILCompiler_ForeachOverReferenceArray_UsesAllocationFreeIndexLoop()
    {
        // Reference-typed element arrays must also use the index-loop fast path
        // (ldlen + ldelem.ref) with no enumerator allocation.
        var source = @"
func countStrings(values: string[]): int {
    count := 0
    foreach value in values {
        count = count + 1
    }
    return count
}";

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var method = assembly.GetType("Program")!
                .GetMethod("countStrings", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(method);
            return GetMethodOpCodes(method!);
        });

        Assert.Contains(OpCodes.Ldlen, opCodes);
        Assert.Contains(OpCodes.Ldelem_Ref, opCodes);
        Assert.DoesNotContain(OpCodes.Newobj, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_ForeachOverArray_ProducesCorrectSum()
    {
        // Confirm the allocation-free lowering preserves exact semantics.
        var source = @"
func sumArray(): int {
    numbers := [1, 2, 3, 4, 5]
    sum := 0
    foreach num in numbers {
        sum = sum + num
    }
    return sum
}";

        var result = CompileAndInvoke(source, "sumArray");
        Assert.Equal(15, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanCompileForeachWithPrint()
    {
        var source = @"
func printArray(numbers: int[]) {
    foreach num in numbers {
        print num
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileForeachOverList()
    {
        var source = @"
import System.Collections.Generic

func countList(items: List<int>): int {
    count := 0
    foreach item in items {
        count = count + 1
    }
    return count
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileNestedForeach()
    {
        var source = @"
func nestedLoops(matrix: int[][]) {
    foreach row in matrix {
        foreach cell in row {
            print cell
        }
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileTryCatch()
    {
        var source = @"
func safeDivide(x: int, y: int): int {
    try {
        return x + y
    } catch (Exception e) {
        print e
        return 0
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileTryCatchWithoutVariable()
    {
        var source = @"
func safeDivide(x: int, y: int): int {
    try {
        return x + y
    } catch (Exception) {
        return 1
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileTryFinally()
    {
        var source = @"
func doWork(): int {
    x := 0
    try {
        x = 42
        return x
    } finally {
        print ""cleanup""
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileTryCatchFinally()
    {
        var source = @"
func complexOperation(): int {
    try {
        x := 10 + 2
        return x
    } catch (Exception e) {
        print e
        return 1
    } finally {
        print ""done""
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileMultipleCatchClauses()
    {
        var source = @"
func handleErrors(): int {
    try {
        x := 10 + 5
        return x
    } catch (DivideByZeroException) {
        return 1
    } catch (Exception e) {
        print e
        return 2
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileNestedTryCatch()
    {
        var source = @"
func nestedExceptionHandling(): int {
    try {
        try {
            return 10 + 5
        } catch (DivideByZeroException) {
            return 1
        }
    } catch (Exception e) {
        print e
        return 2
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileTryCatchWithLocalVariables()
    {
        var source = @"
func testWithLocals(): int {
    result := 0
    try {
        x := 10
        y := 2
        result = x + y
    } catch (Exception e) {
        print e
        result = 1
    } finally {
        print result
    }
    return result
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    // ==================== Interface Tests ====================

    [Fact]
    public void ILCompiler_CanCompileSimpleInterface()
    {
        var source = @"
interface IReader {
    func Read(): string
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileInterfaceWithMultipleMethods()
    {
        var source = @"
interface IRepository {
    func Get(id: int): string
    func Save(value: string): void
    func Delete(id: int): bool
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileClassImplementingInterface()
    {
        var source = @"
interface IGreeter {
    func Greet(): string
}

class SimpleGreeter : IGreeter {
    func Greet(): string {
        return ""Hello""
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileClassImplementingMultipleInterfaces()
    {
        var source = @"
interface IReader {
    func Read(): string
}

interface IWriter {
    func Write(value: string): void
}

class ReadWriter : IReader, IWriter {
    func Read(): string {
        return ""data""
    }

    func Write(value: string): void {
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_EmitsDuckInterfacesAndAutoImplementsMatchingTypes()
    {
        var source = @"
duck interface IReader {
    func Read(): string
}

class FileReader {
    func Read(): string {
        return ""file contents""
    }
}";
        var duckInfo = CompileAndInspect(source, assembly =>
        {
            var interfaceType = assembly.GetType("IReader");
            var readerType = assembly.GetType("FileReader");
            Assert.NotNull(interfaceType);
            Assert.NotNull(readerType);

            return new
            {
                IsInterface = interfaceType!.IsInterface,
                IsAssignable = interfaceType.IsAssignableFrom(readerType)
            };
        });

        Assert.True(duckInfo.IsInterface);
        Assert.True(duckInfo.IsAssignable);
    }

    // ==================== Virtual Method Tests ====================

    [Fact]
    public void ILCompiler_CanCompileVirtualMethod()
    {
        var source = @"
class Animal {
    virtual func MakeSound(): void {
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileVirtualMethodWithReturn()
    {
        var source = @"
class Base {
    virtual func GetValue(): int {
        return 0
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileOverrideMethod()
    {
        var source = @"
class Animal {
    virtual func MakeSound(): void {
    }
}

class Dog : Animal {
    override func MakeSound(): void {
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileOverrideMethodWithReturnValue()
    {
        var source = @"
class Base {
    virtual func GetValue(): int {
        return 0
    }
}

class Derived : Base {
    override func GetValue(): int {
        return 42
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileInheritanceChainWithVirtualMethods()
    {
        var source = @"
class A {
    virtual func DoWork(): void {
    }
}

class B : A {
    override func DoWork(): void {
    }
}

class C : B {
    override func DoWork(): void {
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileClassWithBaseClass()
    {
        var source = @"
class Animal {
    Name: string

    func GetName(): string {
        return Name
    }
}

class Dog : Animal {
    Breed: string
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    // ==================== Devirtualization (call vs callvirt) Tests ====================

    [Fact]
    public void ILCompiler_VirtualCallOnNewExpression_IsDevirtualizedToCall()
    {
        // Calling a virtual method on a freshly-constructed `new T()` receiver: the runtime
        // type is exactly T and the reference is provably non-null, so the callvirt can be
        // safely lowered to a non-virtual call.
        var source = @"
class Greeter {
    virtual func Greet(): int {
        return 7
    }
}

func main(): int {
    return new Greeter().Greet()
}";

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var method = assembly.GetType("Program")!
                .GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(method);
            return GetMethodOpCodes(method!);
        });

        Assert.Contains(OpCodes.Call, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_VirtualCallOnNewExpression_PreservesBehavior()
    {
        // The devirtualized call must produce identical observable behavior.
        var result = CompileAndInvoke(@"
class Greeter {
    virtual func Greet(): int {
        return 7
    }
}

func main(): int {
    return new Greeter().Greet()
}");

        Assert.Equal(7, result);
    }

    [Fact]
    public void ILCompiler_VirtualCallOnPolymorphicReceiver_StaysCallvirt()
    {
        // The receiver is a parameter of a base type whose runtime type is NOT statically
        // known and which may be null. Virtual dispatch and the null-check must be preserved,
        // so this call must remain a callvirt.
        var source = @"
class Animal {
    virtual func Speak(): int {
        return 1
    }
}

class Dog : Animal {
    override func Speak(): int {
        return 2
    }
}

func sound(a: Animal): int {
    return a.Speak()
}";

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var method = assembly.GetType("Program")!
                .GetMethod("sound", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(method);
            return GetMethodOpCodes(method!);
        });

        Assert.Contains(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_VirtualDispatchThroughBaseReference_PreservesBehavior()
    {
        // End-to-end: dispatching a virtual method through a base-typed reference must still
        // resolve to the most-derived override at runtime (i.e. callvirt was preserved).
        var result = CompileAndInvoke(@"
class Animal {
    virtual func Speak(): int {
        return 1
    }
}

class Dog : Animal {
    override func Speak(): int {
        return 2
    }
}

func sound(a: Animal): int {
    return a.Speak()
}

func main(): int {
    d := new Dog()
    return sound(d)
}");

        Assert.Equal(2, result);
    }

    [Fact]
    public void ILCompiler_NonVirtualCallOnNewExpression_RemainsCall()
    {
        // A non-virtual instance method on a `new T()` receiver was already emitted as `call`;
        // the devirtualization change must not regress this to callvirt.
        var source = @"
class Calculator {
    func Add(x: int, y: int): int {
        return x + y
    }
}

func main(): int {
    return new Calculator().Add(5, 3)
}";

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var method = assembly.GetType("Program")!
                .GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(method);
            return GetMethodOpCodes(method!);
        });

        Assert.Contains(OpCodes.Call, opCodes);
        Assert.DoesNotContain(OpCodes.Callvirt, opCodes);
    }

    [Fact]
    public void ILCompiler_CanCompileClassWithBaseAndInterfaces()
    {
        var source = @"
interface IGreeter {
    func Greet(): string
}

class Animal {
    Name: string
}

class Dog : Animal, IGreeter {
    func Greet(): string {
        return ""Woof""
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanExecuteSimpleUsingStatement()
    {
        var source = @"
class Resource {
    static Disposed: int

    func Dispose(): void {
        Disposed = 42
    }

    static func Create(): Resource => new Resource()
}

func main(): int {
    using r := Resource.Create() {
        Resource.Disposed = 1
    }

    return Resource.Disposed
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanCompileMatchExpressionWithLiteralPatterns()
    {
        var source = @"
func testMatch(x: int): string {
    result := match x {
        0 => ""zero"",
        1 => ""one"",
        2 => ""two"",
        _ => ""other""
    }
    return result
}";

        Assert.Equal("zero", Assert.IsType<string>(CompileAndInvoke(source, "testMatch", 0)));
        Assert.Equal("one", Assert.IsType<string>(CompileAndInvoke(source, "testMatch", 1)));
        Assert.Equal("two", Assert.IsType<string>(CompileAndInvoke(source, "testMatch", 2)));
        Assert.Equal("other", Assert.IsType<string>(CompileAndInvoke(source, "testMatch", 7)));
    }

    [Fact]
    public void ILCompiler_CanCompileMatchExpressionWithStringLiterals()
    {
        var source = @"
func greet(name: string): string {
    message := match name {
        ""Alice"" => ""Hello Alice!"",
        ""Bob"" => ""Hi Bob!"",
        _ => ""Hello stranger!""
    }
    return message
}";

        Assert.Equal("Hello Alice!", Assert.IsType<string>(CompileAndInvoke(source, "greet", "Alice")));
        Assert.Equal("Hi Bob!", Assert.IsType<string>(CompileAndInvoke(source, "greet", "Bob")));
        Assert.Equal("Hello stranger!", Assert.IsType<string>(CompileAndInvoke(source, "greet", "Eve")));
    }

    [Fact]
    public void ILCompiler_CanCompileMatchExpressionWithVariableBinding()
    {
        var source = @"
func processValue(x: int): int {
    result := match x {
        0 => 100,
        n => n * 2
    }
    return result
}";

        Assert.Equal(100, Assert.IsType<int>(CompileAndInvoke(source, "processValue", 0)));
        Assert.Equal(14, Assert.IsType<int>(CompileAndInvoke(source, "processValue", 7)));
    }

    [Fact]
    public void ILCompiler_CanExecuteMustOnNullableValue()
    {
        var source = @"
func main(): int {
    value: int? = 41
    return (must value) + 1
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_MustOnNullNullableValueThrows()
    {
        var source = @"
func main(): int {
    value: int? = null
    return must value
}";

        var ex = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(source));
        Assert.Equal("must unwrap failed: value was null", ex.Message);
    }

    [Fact]
    public void ILCompiler_CanExecuteNullableHasValueAndValueAccess()
    {
        var source = @"
func main(): int {
    value: int? = 41
    if value.HasValue {
        return value.Value + 1
    }
    return 0
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteNullableMatchWithPresentBinding()
    {
        var source = @"
func present(): int {
    value: int? = 41
    return match value {
        null => 0,
        inner => inner + 1
    }
}

func absent(): int {
    value: int? = null
    return match value {
        null => 7,
        inner => inner + 1
    }
}";

        Assert.Equal(42, Assert.IsType<int>(CompileAndInvoke(source, "present")));
        Assert.Equal(7, Assert.IsType<int>(CompileAndInvoke(source, "absent")));
    }

    [Fact]
    public void ILCompiler_CanCompileMatchExpressionWithTypePattern()
    {
        var source = @"
func getTypeName(obj: object): string {
    name := match obj {
        string => ""It's a string"",
        int => ""It's an int"",
        _ => ""Unknown type""
    }
    return name
}";

        Assert.Equal("It's a string", Assert.IsType<string>(CompileAndInvoke(source, "getTypeName", "text")));
        Assert.Equal("It's an int", Assert.IsType<string>(CompileAndInvoke(source, "getTypeName", 42)));
        Assert.Equal("Unknown type", Assert.IsType<string>(CompileAndInvoke(source, "getTypeName", new object())));
    }

    [Fact]
    public void ILCompiler_CanExecuteQualifiedTypePattern()
    {
        var source = @"
func check(obj: object): string {
    result := match obj {
        System.String s => s.ToUpper(),
        _ => ""unknown""
    }
    return result
}";

        Assert.Equal("HELLO", Assert.IsType<string>(CompileAndInvoke(source, "check", "hello")));
        Assert.Equal("unknown", Assert.IsType<string>(CompileAndInvoke(source, "check", 42)));
    }

    [Fact]
    public void ILCompiler_CanExecuteTypePatternWithGuardAndBinding()
    {
        var source = @"
func check(obj: object): string {
    result := match obj {
        string s when s.Length > 5 => ""long"",
        string s => ""short"",
        _ => ""not string""
    }
    return result
}";

        Assert.Equal("long", Assert.IsType<string>(CompileAndInvoke(source, "check", "example")));
        Assert.Equal("short", Assert.IsType<string>(CompileAndInvoke(source, "check", "cat")));
        Assert.Equal("not string", Assert.IsType<string>(CompileAndInvoke(source, "check", 42)));
    }

    [Fact]
    public void ILCompiler_CanCompileMatchExpressionWithGuard()
    {
        var source = @"
func classifyNumber(x: int): string {
    result := match x {
        n when n < 0 => ""negative"",
        0 => ""zero"",
        n when n > 0 => ""positive"",
        _ => ""unknown""
    }
    return result
}";

        Assert.Equal("negative", Assert.IsType<string>(CompileAndInvoke(source, "classifyNumber", -1)));
        Assert.Equal("zero", Assert.IsType<string>(CompileAndInvoke(source, "classifyNumber", 0)));
        Assert.Equal("positive", Assert.IsType<string>(CompileAndInvoke(source, "classifyNumber", 5)));
    }

    [Fact]
    public void ILCompiler_CanCompileMatchExpressionWithRelationalPattern()
    {
        var source = @"
func getRange(x: int): string {
    result := match x {
        < 0 => ""negative"",
        0 => ""zero"",
        > 0 => ""positive""
    }
    return result
}";

        Assert.Equal("negative", Assert.IsType<string>(CompileAndInvoke(source, "getRange", -4)));
        Assert.Equal("zero", Assert.IsType<string>(CompileAndInvoke(source, "getRange", 0)));
        Assert.Equal("positive", Assert.IsType<string>(CompileAndInvoke(source, "getRange", 9)));
    }

    [Fact]
    public void ILCompiler_CanCompileMatchExpressionInReturnStatement()
    {
        var source = @"
func doubleOrZero(x: int): int {
    return match x {
        0 => 0,
        n => n * 2
    }
}";

        Assert.Equal(0, Assert.IsType<int>(CompileAndInvoke(source, "doubleOrZero", 0)));
        Assert.Equal(16, Assert.IsType<int>(CompileAndInvoke(source, "doubleOrZero", 8)));
    }

    [Fact]
    public void ILCompiler_CanCompileNestedMatchExpressions()
    {
        var source = @"
func classify(x: int, y: int): string {
    return match x {
        0 => match y {
            0 => ""both zero"",
            _ => ""x is zero""
        },
        _ => match y {
            0 => ""y is zero"",
            _ => ""neither zero""
        }
    }
}";

        Assert.Equal("both zero", Assert.IsType<string>(CompileAndInvoke(source, "classify", 0, 0)));
        Assert.Equal("x is zero", Assert.IsType<string>(CompileAndInvoke(source, "classify", 0, 1)));
        Assert.Equal("y is zero", Assert.IsType<string>(CompileAndInvoke(source, "classify", 1, 0)));
        Assert.Equal("neither zero", Assert.IsType<string>(CompileAndInvoke(source, "classify", 1, 1)));
    }

    [Fact]
    public void ILCompiler_CanCompileSimpleRecord()
    {
        var source = @"
record Person {
    Name: string
    Age: int
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_EmitsExportedClassAndRecordDataMembersAsProperties()
    {
        var source = @"
import System.Collections.Generic

record HttpRequest {
    Method: string
    Url: string
    Headers: Dictionary<string, string> = new Dictionary<string, string>()
    Body: string
}

class HttpResponse {
    StatusCode: int
    Body: string
}

func main(): string {
    request := new HttpRequest {
        Method: ""GET"",
        Url: ""https://example.test"",
        Headers: new Dictionary<string, string>(),
        Body: """"
    }
    request.Headers[""Accept""] = ""text/plain""
    return request.Headers[""Accept""]
}";

        CompileAndInspect(source, assembly =>
        {
            var requestType = assembly.GetType("HttpRequest");
            Assert.NotNull(requestType);

            foreach (var propertyName in new[] { "Method", "Url", "Headers", "Body" })
            {
                var property = requestType!.GetProperty(propertyName, BindingFlags.Public | BindingFlags.Instance);
                Assert.NotNull(property);
                Assert.Contains(
                    property!.SetMethod!.ReturnParameter.GetRequiredCustomModifiers(),
                    modifier => modifier.FullName == "System.Runtime.CompilerServices.IsExternalInit");
            }

            Assert.DoesNotContain(requestType!.GetFields(BindingFlags.Public | BindingFlags.Instance), field =>
                field.Name is "Method" or "Url" or "Headers" or "Body");

            GetCustomAttribute(requestType, "System.Runtime.CompilerServices.RequiredMemberAttribute");
            foreach (var requiredProperty in new[] { "Method", "Url", "Body" })
            {
                GetCustomAttribute(requestType.GetProperty(requiredProperty)!, "System.Runtime.CompilerServices.RequiredMemberAttribute");
            }
            Assert.DoesNotContain(
                requestType.GetProperty("Headers")!.CustomAttributes,
                attribute => attribute.AttributeType.FullName == "System.Runtime.CompilerServices.RequiredMemberAttribute");

            var responseType = assembly.GetType("HttpResponse");
            Assert.NotNull(responseType);
            Assert.NotNull(responseType!.GetProperty("StatusCode", BindingFlags.Public | BindingFlags.Instance));
            Assert.NotNull(responseType.GetProperty("Body", BindingFlags.Public | BindingFlags.Instance));
            Assert.DoesNotContain(responseType.GetFields(BindingFlags.Public | BindingFlags.Instance), field =>
                field.Name is "StatusCode" or "Body");

            return true;
        });

        var result = CompileAndInvoke(source);
        Assert.Equal("text/plain", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanCompileRecordWithPrimaryConstructor()
    {
        var source = @"
record Point(x: int, y: int) {}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileRecordStruct()
    {
        var source = @"
record struct Point {
    X: int
    Y: int
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileRecordStructWithPrimaryConstructor()
    {
        var source = @"
record struct Vector2D(x: int, y: int) {}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_RecordStructEquals_IsVerifiableAndStructural()
    {
        // Regression: the synthesized Equals(object) on a record struct used to store
        // the boxed `isinst` result straight into a value-type local, producing
        // unverifiable IL (ilverify StackUnexpected: found ref, expected value). The
        // boxed reference must be unboxed back to the value type first. This test
        // guards both the verifiability (Unbox.Any present, no leftover box) and the
        // structural-equality semantics.
        var source = @"
record struct Point(x: int, y: int) {
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var pointType = assembly.GetType("Point");
            Assert.NotNull(pointType);
            Assert.True(pointType!.IsValueType, "Point should be emitted as a value type.");

            var equals = pointType.GetMethod(
                "Equals",
                BindingFlags.Public | BindingFlags.Instance,
                binder: null,
                types: new[] { typeof(object) },
                modifiers: null);
            Assert.NotNull(equals);

            var opCodes = GetMethodOpCodes(equals!);

            var a = Activator.CreateInstance(pointType, 1, 2);
            var sameAsA = Activator.CreateInstance(pointType, 1, 2);
            var differentX = Activator.CreateInstance(pointType, 9, 2);
            var differentY = Activator.CreateInstance(pointType, 1, 9);

            return new
            {
                HasUnboxAny = opCodes.Contains(OpCodes.Unbox_Any),
                EqualToSame = (bool)equals!.Invoke(a, new[] { sameAsA })!,
                NotEqualX = (bool)equals.Invoke(a, new[] { differentX })!,
                NotEqualY = (bool)equals.Invoke(a, new[] { differentY })!,
                NotEqualNull = (bool)equals.Invoke(a, new object?[] { null })!,
                NotEqualOtherType = (bool)equals.Invoke(a, new object?[] { "not a point" })!
            };
        });

        Assert.True(result.HasUnboxAny, "Record struct Equals(object) must unbox the boxed argument before comparison.");
        Assert.True(result.EqualToSame, "Record structs with identical fields should be equal.");
        Assert.False(result.NotEqualX, "Differing fields should not be equal.");
        Assert.False(result.NotEqualY, "Differing fields should not be equal.");
        Assert.False(result.NotEqualNull, "A record struct should never equal null.");
        Assert.False(result.NotEqualOtherType, "A record struct should never equal an unrelated type.");
    }

    [Fact]
    public void ILCompiler_RecordStructEquality_UsesEqualityComparerSemantics()
    {
        var source = @"
record struct Measurement(value: double) {
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var measurementType = assembly.GetType("Measurement");
            Assert.NotNull(measurementType);
            Assert.True(measurementType!.IsValueType, "Measurement should be emitted as a value type.");

            var equality = measurementType.GetMethod(
                "op_Equality",
                BindingFlags.Public | BindingFlags.Static);
            var equals = measurementType.GetMethod(
                "Equals",
                BindingFlags.Public | BindingFlags.Instance,
                binder: null,
                types: new[] { typeof(object) },
                modifiers: null);
            Assert.NotNull(equality);
            Assert.NotNull(equals);

            var left = Activator.CreateInstance(measurementType, double.NaN);
            var right = Activator.CreateInstance(measurementType, double.NaN);

            return new
            {
                OperatorEqual = (bool)equality!.Invoke(null, new[] { left, right })!,
                ObjectEquals = (bool)equals!.Invoke(left, new[] { right })!
            };
        });

        Assert.True(result.OperatorEqual, "Record struct == should match EqualityComparer<double>.Default for NaN.");
        Assert.True(result.ObjectEquals, "Record struct Equals(object) should match EqualityComparer<double>.Default for NaN.");
    }

    [Fact]
    public void ILCompiler_RecordGetHashCode_AllowsNullReferenceFields()
    {
        var source = @"
record Person(name: string) {
}";

        var hashCode = CompileAndInspect(source, assembly =>
        {
            var personType = assembly.GetType("Person");
            Assert.NotNull(personType);

            var person = Activator.CreateInstance(personType!, new object?[] { null });
            var getHashCode = personType!.GetMethod(
                "GetHashCode",
                BindingFlags.Public | BindingFlags.Instance,
                binder: null,
                types: Type.EmptyTypes,
                modifiers: null);
            Assert.NotNull(getHashCode);

            return getHashCode!.Invoke(person, null);
        });

        Assert.IsType<int>(hashCode);
    }

    [Fact]
    public void ILCompiler_RecordStructMethodReturningNewStruct_CoercesLiteralArgsAndIsVerifiable()
    {
        // Regression (ilverify StackUnexpected on Vector2D::Normalize): a record-struct
        // method that returns `new Vector2D(0, 0)` constructed the value via a synthesized
        // primary constructor whose parameters are `double`. Because the primary constructor
        // is not registered as a declared-overload, EmitNewObject fell back to a raw
        // `EmitExpression(arg)` loop that ignored the parameter type, leaving an `Int32`
        // (`ldc.i4.0`) on the stack where the `.ctor(float64, float64)` expected a `Double`.
        // The fix coerces each unbound constructor argument to its parameter type, emitting
        // the required `conv.r8`. Guard both the IL shape (Conv_R8 present) and semantics.
        var source = @"
record struct Vec(x: double, y: double) {
    func Zero(): Vec {
        return new Vec(0, 0)
    }
}";

        var result = CompileAndInspect(source, assembly =>
        {
            var vecType = assembly.GetType("Vec");
            Assert.NotNull(vecType);
            Assert.True(vecType!.IsValueType, "Vec should be emitted as a value type.");

            var zero = vecType.GetMethod(
                "Zero",
                BindingFlags.Public | BindingFlags.Instance,
                binder: null,
                types: Type.EmptyTypes,
                modifiers: null);
            Assert.NotNull(zero);

            var opCodes = GetMethodOpCodes(zero!);

            var instance = Activator.CreateInstance(vecType, 3.0, 4.0)!;
            var produced = zero!.Invoke(instance, Array.Empty<object>())!;

            var xProp = vecType.GetProperty("x")!;
            var yProp = vecType.GetProperty("y")!;

            return new
            {
                // Each integer literal fed to a double parameter must be widened.
                ConvR8Count = opCodes.Count(op => op == OpCodes.Conv_R8),
                // The constructed value must be returned (no dangling address/box).
                EndsWithRet = opCodes.Count > 0 && opCodes[^1] == OpCodes.Ret,
                ReturnsVec = produced.GetType() == vecType,
                X = (double)xProp.GetValue(produced)!,
                Y = (double)yProp.GetValue(produced)!,
            };
        });

        Assert.True(result.ConvR8Count >= 2, "Both integer-literal constructor arguments must be coerced to double (conv.r8).");
        Assert.True(result.EndsWithRet, "The struct-returning method must end with ret.");
        Assert.True(result.ReturnsVec, "Zero() must return a Vec value.");
        Assert.Equal(0.0, result.X);
        Assert.Equal(0.0, result.Y);
    }

    [Fact]
    public void ILCompiler_CanCompileRecordWithMethods()
    {
        var source = @"
record Person(name: string, age: int) {
    func GetInfo(): int {
        return 42
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileRecordWithInterface()
    {
        var source = @"
interface IIdentifiable {
    func GetId(): int
}

record Person(id: int, name: string): IIdentifiable {
    func GetId(): int {
        return 123
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileSimpleLambdaExpression()
    {
        var source = @"
func TestLambda() {
    add := (x, y) => x + y
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileSimpleLambdaBlock()
    {
        var source = @"
func TestLambda() {
    add := (x, y) => {
        return x + y
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileLambdaWithClosure()
    {
        var source = @"
func TestClosure() {
    multiplier := 5
    multiply := (x) => x * multiplier
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileLambdaWithMultipleCapturedVariables()
    {
        var source = @"
func TestMultipleCaptured() {
    a := 10
    b := 20
    add := (x) => x + a + b
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileNestedLambdas()
    {
        var source = @"
func TestNestedLambdas() {
    outer := (x) => {
        inner := (y) => x + y
        return x
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanCompileLambdaWithNoParameters()
    {
        var source = @"
func TestNoParams() {
    getValue := () => 42
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_CanExecuteBlockLambdaWithImplicitReturnType()
    {
        var source = @"
func main(): int {
    getValue := () => {
        return 42
    }

    return getValue()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CapturedStructFieldAssignment_IsObservedAcrossCallBoundary()
    {
        // A local function captures a struct local and writes one of its fields. Because a field
        // write mutates the struct's storage, the local must be lifted into a shared box so the
        // mutation is visible to the enclosing frame. Previously the local was misclassified as
        // not-mutated and the write was lost (or produced invalid IL).
        var result = CompileAndInvoke(@"
struct Counter {
    Value: int
}

func main(): int {
    c := new Counter { Value: 10 }

    func Bump(): void {
        c.Value = c.Value + 5
    }

    Bump()
    return c.Value
}");

        Assert.Equal(15, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CapturedStructFieldCompoundAssignment_AccumulatesAcrossCalls()
    {
        var result = CompileAndInvoke(@"
struct Acc {
    Total: int
}

func main(): int {
    a := new Acc { Total: 0 }

    func Add(n: int): void {
        a.Total += n
    }

    Add(3)
    Add(4)
    Add(5)
    return a.Total
}");

        Assert.Equal(12, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CapturedStructFieldIncrement_IsObserved()
    {
        // `c.Value++` only references `c` through a unary/member target. The capture analysis must
        // both recognize the reference (capture detection) and the mutation (lifting).
        var result = CompileAndInvoke(@"
struct Counter {
    Value: int
}

func main(): int {
    c := new Counter { Value: 10 }

    func Bump(): void {
        c.Value++
    }

    Bump()
    Bump()
    return c.Value
}");

        Assert.Equal(12, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CapturedStructElementMutation_IsObserved()
    {
        // A struct holding an array, captured and mutated through `h.Data[i] = ...`.
        var result = CompileAndInvoke(@"
struct Holder {
    Data: int[]
}

func main(): int {
    h := new Holder { Data: [1, 2, 3] }

    func Mutate(): void {
        h.Data[1] = 50
    }

    Mutate()
    return h.Data[1]
}");

        Assert.Equal(50, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CapturedStructFieldMutation_ViaBlockLambdaLocal()
    {
        var result = CompileAndInvoke(@"
struct P {
    X: int
}

func main(): int {
    p := new P { X: 1 }

    setter := () => {
        p.X = 99
    }

    setter()
    return p.X
}");

        Assert.Equal(99, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CapturedReferenceTypeFieldMutation_StillWorks()
    {
        // Reference-type member mutation already worked (the write goes through the shared heap
        // object). This guards against a regression where it would be needlessly boxed or broken.
        var result = CompileAndInvoke(@"
class Box {
    Value: int
}

func main(): int {
    b := new Box { Value: 100 }

    func Set(): void {
        b.Value = 42
    }

    Set()
    return b.Value
}");

        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CapturedStructMutation_SurvivesEarlierSiblingLambda()
    {
        // Guards the body-context save/restore: a sibling lambda emitted earlier in the function must
        // not clobber the value-type lift set used when a later nested block declares and mutates a
        // captured struct local. Before the fix this returned 10 (mutation lost) instead of 15.
        var result = CompileAndInvoke(@"
struct Counter {
    Value: int
}

func main(): int {
    noise := () => { return 1 }
    n := noise()
    result := 0
    if n == 1 {
        c := new Counter { Value: 10 }

        func Bump(): void {
            c.Value = c.Value + 5
        }

        Bump()
        result = c.Value
    }
    return result
}");

        Assert.Equal(15, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_StructFieldIncrement_WithoutClosure_IsObserved()
    {
        // Regression for a pre-existing emit defect: incrementing a struct local's field needs the
        // struct's ADDRESS as the Stfld receiver. Emitting a copy lost the increment / NRE'd.
        var result = CompileAndInvoke(@"
struct Counter {
    Value: int
}

func main(): int {
    c := new Counter { Value: 10 }
    c.Value++
    return c.Value
}");

        Assert.Equal(11, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanCompileLambdaWithVoidReturn()
    {
        var source = @"
func TestVoidLambda() {
    action := (x) => {
        y := x + 1
    }
}";
        var compilationUnit = Parse(source);
        var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, "TestAssembly", "/tmp/test.dll");

        // Should not throw
        compiler.Compile();
    }

    [Fact]
    public void ILCompiler_TargetTypedExternalDelegateLambda_EmitsConcreteDelegateType()
    {
        var source = @"
import NSharpLang.Tests
import System.Threading.Tasks

func main(): string {
    return DelegateInteropProbe.Capture(context => Task.CompletedTask)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(typeof(ExternalRequestDelegate).FullName, Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_TargetTypedExternalDelegateLambdaAssignedToLocal_EmitsConcreteDelegateType()
    {
        var source = @"
import NSharpLang.Tests
import System.Threading.Tasks

func main(): string {
    handler: ExternalRequestDelegate = context => Task.CompletedTask
    return handler.GetType().FullName
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(typeof(ExternalRequestDelegate).FullName, Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_TargetTypedCapturedExternalDelegateLambdaAssignedToLocal_EmitsConcreteDelegateType()
    {
        var source = @"
import NSharpLang.Tests
import System.Threading.Tasks

class RouteProbe {
    func GetTask(): Task {
        return Task.CompletedTask
    }

    func Run(): string {
        handler: ExternalRequestDelegate = context => GetTask()
        return handler.GetType().FullName
    }
}

func main(): string {
    probe := new RouteProbe()
    return probe.Run()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(typeof(ExternalRequestDelegate).FullName, Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_TargetTypedAspNetRequestDelegateLambdaAssignedToLocal_EmitsRequestDelegate()
    {
        var source = @"
import Microsoft.AspNetCore.Http

func main(): string {
    handler: RequestDelegate = context => context.Response.WriteAsync(""ok"")
    return handler.GetType().FullName
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(typeof(RequestDelegate).FullName, Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_TargetTypedAspNetRequestDelegateCapturedLocalPassedAsDelegate_EmitsRequestDelegate()
    {
        var source = @"
import Microsoft.AspNetCore.Http
import NSharpLang.Tests

class RouteProbe {
    func Handle(context: HttpContext): Task {
        return context.Response.WriteAsync(""ok"")
    }

    func Run(): string {
        handler: RequestDelegate = context => Handle(context)
        return DelegateInteropProbe.CaptureDelegate(handler)
    }
}

func main(): string {
    probe := new RouteProbe()
    return probe.Run()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(typeof(RequestDelegate).FullName, Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_TargetTypedAspNetRequestDelegateLocalMappedOnWebApplication_MaterializesEndpoint()
    {
        var source = @"
import Microsoft.AspNetCore.Builder
import Microsoft.AspNetCore.Http
import NSharpLang.Tests

class RouteProbe {
    func Handle(context: HttpContext): Task {
        return context.Response.WriteAsync(""ok"")
    }

    func Run(): int {
        builder := WebApplication.CreateBuilder()
        app := builder.Build()
        handler: RequestDelegate = context => Handle(context)
        app.MapGet(""/api/health"", handler)
        return DelegateInteropProbe.MaterializeAspNetEndpoints(app)
    }
}

func main(): int {
    probe := new RouteProbe()
    return probe.Run()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(1, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_TargetTypedAspNetRequestDelegateLiftedLocalMappedOnWebApplication_MaterializesEndpoint()
    {
        var source = @"
import Microsoft.AspNetCore.Builder
import Microsoft.AspNetCore.Http
import NSharpLang.Tests

class RouteProbe {
    func Handle(context: HttpContext): Task {
        return context.Response.WriteAsync(""ok"")
    }

    func Run(): int {
        builder := WebApplication.CreateBuilder()
        app := builder.Build()
        healthHandler: RequestDelegate = context => context.Response.WriteAsync(""ok"")
        listHandler: RequestDelegate = context => Handle(context)
        app.MapGet(""/api/health"", healthHandler)
        app.MapGet(""/api/issues"", listHandler)
        return DelegateInteropProbe.MaterializeAspNetEndpoints(app)
    }
}

func main(): int {
    probe := new RouteProbe()
    return probe.Run()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(2, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_TargetTypedAspNetFuncLambda_StillEmitsFuncDelegate()
    {
        var source = @"
import Microsoft.AspNetCore.Http
import NSharpLang.Tests

func main(): string {
    return DelegateInteropProbe.CaptureAspNetFunc(context => context.Response.WriteAsync(""ok""))
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(typeof(Func<HttpContext, Task>).FullName, Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_TargetTypedAspNetRequestDelegateLambda_EmitsValidOptionalStructDefaults()
    {
        var source = @"
import Microsoft.AspNetCore.Http
import NSharpLang.Tests

func main(): string {
    handler: RequestDelegate = context => context.Response.WriteAsync(""ok"")
    return DelegateInteropProbe.CaptureAspNetResponse(handler)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("ok", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteLambdaWithFiveParameters()
    {
        var source = @"
func main(): int {
    sum: Func<int, int, int, int, int, int> = (a, b, c, d, e) => a + b + c + d + e
    return sum(1, 2, 3, 4, 5)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(15, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_NonCapturingLambdaEscapingInLoop_CachesDelegateInStaticField()
    {
        // A non-capturing lambda that escapes (is materialized as a delegate value and
        // stored in a collection) should allocate the delegate at most once, guarded by a
        // static cache field - matching Roslyn's <>9__N caching idiom.
        var source = @"
import System
import System.Collections.Generic

func main(): int {
    handlers := new List<Func<int, int>>()
    for i := 0; i < 3; i = i + 1 {
        handler: Func<int, int> = (x) => x + 1
        handlers.Add(handler)
    }
    return handlers[0](41)
}";

        CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);

            var cacheField = GetDelegateCacheField(programType!);
            Assert.NotNull(cacheField);
            Assert.True(cacheField!.IsStatic);
            Assert.True(cacheField.IsPrivate);

            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);
            AssertDelegateCreationIsCacheGuarded(main!);

            return 0;
        });

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_MethodGroupDelegateEscapingInLoop_CachesDelegateInStaticField()
    {
        // A method-group delegate that escapes inside a loop should also be cached in a
        // static field so the delegate is allocated at most once.
        var source = @"
import System
import System.Collections.Generic

func increment(value: int): int => value + 1

func main(): int {
    handlers := new List<Func<int, int>>()
    for i := 0; i < 3; i = i + 1 {
        handler: Func<int, int> = increment
        handlers.Add(handler)
    }
    return handlers[0](41)
}";

        CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program");
            Assert.NotNull(programType);

            var cacheField = GetDelegateCacheField(programType!);
            Assert.NotNull(cacheField);
            Assert.True(cacheField!.IsStatic);

            var main = programType!.GetMethod("main", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(main);
            AssertDelegateCreationIsCacheGuarded(main!);

            return 0;
        });

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_NonCapturingLambdaEscapingInLoop_AllocatesDelegateOnlyOnce()
    {
        // Behavioral confirmation: because the delegate is cached, every loop iteration
        // observes the same delegate instance.
        var source = @"
import System
import System.Collections.Generic

func main(): bool {
    handlers := new List<Func<int, int>>()
    for i := 0; i < 3; i = i + 1 {
        handler: Func<int, int> = (x) => x + 1
        handlers.Add(handler)
    }
    allSame := true
    for j := 1; j < handlers.Count; j = j + 1 {
        if !handlers[0].Equals(handlers[j]) {
            allSame = false
        }
    }
    return allSame
}";

        var result = CompileAndInvoke(source);
        Assert.True(Assert.IsType<bool>(result));
    }

    private static FieldInfo? GetDelegateCacheField(Type programType)
    {
        return programType
            .GetFields(BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)
            .FirstOrDefault(field => field.Name.StartsWith("<>c__DelegateCache", StringComparison.Ordinal));
    }

    private static void AssertDelegateCreationIsCacheGuarded(MethodInfo method)
    {
        var opCodes = GetMethodOpCodes(method);

        // A delegate construction is a `newobj` immediately preceded by `ldftn`. Each one
        // must be guarded by a static-field load + branch so the delegate is created at
        // most once (Roslyn's <>9__N caching idiom). Other `newobj` sites (e.g. the
        // backing List<>) are unrelated and ignored.
        var delegateNewobjIndexes = opCodes
            .Select((opCode, index) => (opCode, index))
            .Where(entry => entry.opCode == OpCodes.Newobj
                && entry.index >= 1
                && opCodes[entry.index - 1] == OpCodes.Ldftn)
            .Select(entry => entry.index)
            .ToList();

        Assert.NotEmpty(delegateNewobjIndexes);

        foreach (var index in delegateNewobjIndexes)
        {
            // ... ldsfld, dup, brtrue, pop, ldnull, ldftn, newobj, dup, stsfld ...
            Assert.True(index >= 6, "Cache-guarded delegate creation expected preceding opcodes");
            Assert.True(index + 2 < opCodes.Count, "Cache-guarded delegate creation expected trailing opcodes");
            Assert.Equal(OpCodes.Ldftn, opCodes[index - 1]);
            Assert.Equal(OpCodes.Ldnull, opCodes[index - 2]);
            Assert.Equal(OpCodes.Pop, opCodes[index - 3]);
            Assert.True(
                opCodes[index - 4] == OpCodes.Brtrue_S || opCodes[index - 4] == OpCodes.Brtrue,
                "Expected branch-if-already-cached before delegate creation");
            Assert.Equal(OpCodes.Dup, opCodes[index - 5]);
            Assert.Equal(OpCodes.Ldsfld, opCodes[index - 6]);

            // After creating the delegate it is stored back into the cache field.
            Assert.Equal(OpCodes.Dup, opCodes[index + 1]);
            Assert.Equal(OpCodes.Stsfld, opCodes[index + 2]);
        }
    }

    [Fact]
    public void ILCompiler_CanExecuteFieldInitializerOnClass()
    {
        var source = @"
class Counter {
    Count: int = 41
}

func main(): int {
    counter := new Counter()
    return counter.Count
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(41, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_EmitsRequiredAndInitShorthandProperties()
    {
        var source = @"
class User {
    required Name: string
    init Age: int
}

func main(): int {
    user := new User { Name: ""Ada"", Age: 37 }
    return user.Age
}";

        CompileAndInspect(source, assembly =>
        {
            var userType = assembly.GetType("User");
            Assert.NotNull(userType);

            GetCustomAttribute(userType!, "System.Runtime.CompilerServices.RequiredMemberAttribute");

            var nameProperty = userType.GetProperty("Name", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            Assert.NotNull(nameProperty);
            GetCustomAttribute(nameProperty!, "System.Runtime.CompilerServices.RequiredMemberAttribute");
            Assert.DoesNotContain(nameProperty.SetMethod!.ReturnParameter.GetRequiredCustomModifiers(),
                modifier => modifier.FullName == "System.Runtime.CompilerServices.IsExternalInit");

            var ageProperty = userType.GetProperty("Age", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            Assert.NotNull(ageProperty);
            Assert.Contains(ageProperty!.SetMethod!.ReturnParameter.GetRequiredCustomModifiers(),
                modifier => modifier.FullName == "System.Runtime.CompilerServices.IsExternalInit");

            return 0;
        });

        var result = CompileAndInvoke(source);
        Assert.Equal(37, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_EmitsRequiredInitMemberMetadata()
    {
        var source = @"
class Account {
    required init Id: string
    required init Email: string
}";

        CompileAndInspect(source, assembly =>
        {
            var accountType = assembly.GetType("Account");
            Assert.NotNull(accountType);

            GetCustomAttribute(accountType!, "System.Runtime.CompilerServices.RequiredMemberAttribute");

            foreach (var propertyName in new[] { "Id", "Email" })
            {
                var property = accountType.GetProperty(propertyName, BindingFlags.Public | BindingFlags.Instance);
                Assert.NotNull(property);
                GetCustomAttribute(property!, "System.Runtime.CompilerServices.RequiredMemberAttribute");

                var setter = property.SetMethod;
                Assert.NotNull(setter);
                Assert.Contains(
                    setter!.ReturnParameter.GetRequiredCustomModifiers(),
                    modifier => modifier.FullName == "System.Runtime.CompilerServices.IsExternalInit");
            }

            return true;
        });
    }

    [Fact]
    public async Task ILCompiler_CanExecuteAwaitExpression()
    {
        var source = @"
import System.Threading.Tasks
import NSharpLang.Tests

async func GetValue(): Task<int> {
    return await ILCompilerAsyncHelpers.GetValueAsync(42)
}

async func main(): Task<int> {
    return await GetValue()
}";

        var result = await CompileAndInvokeTaskResult(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public async Task ILCompiler_ExplicitAsyncTask_DoesNotRequireReturnValue()
    {
        var source = @"
import System.Threading.Tasks
import NSharpLang.Tests

async func DoWork(): Task {
    await ILCompilerAsyncHelpers.GetValueAsync(0)
}

async func main(): Task<int> {
    await DoWork()
    return 42
}";

        var result = await CompileAndInvokeTaskResult(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public async Task ILCompiler_ExplicitAsyncTaskOfT_ReturnsBareResultValue()
    {
        var source = @"
import System.Threading.Tasks
import NSharpLang.Tests

async func GetValue(): Task<int> {
    await ILCompilerAsyncHelpers.GetValueAsync(0)
    return 42
}

async func main(): Task<int> {
    return await GetValue()
}";

        var result = await CompileAndInvokeTaskResult(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public async Task ILCompiler_ExplicitAsyncValueTask_DoesNotRequireReturnValue()
    {
        var source = @"
import System.Threading.Tasks
import NSharpLang.Tests

async func DoWork(): ValueTask {
    await ILCompilerAsyncHelpers.GetValueAsync(0)
}

async func main(): Task<int> {
    await DoWork()
    return 42
}";

        var result = await CompileAndInvokeTaskResult(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public async Task ILCompiler_ExplicitAsyncValueTaskOfT_ReturnsBareResultValue()
    {
        var source = @"
import System.Threading.Tasks
import NSharpLang.Tests

async func GetValue(): ValueTask<int> {
    await ILCompilerAsyncHelpers.GetValueAsync(0)
    return 42
}

async func main(): Task<int> {
    return await GetValue()
}";

        var result = await CompileAndInvokeTaskResult(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_AsyncWithoutAwait_ThatThrows_ReturnsFaultedTask()
    {
        // C# semantics: an async method that throws surfaces the exception through the returned
        // (faulted) task, NOT synchronously at the call site. N# async is sync-lowered, so this
        // guards the fault-wrapping that preserves that behavior.
        var source = @"
import System.Threading.Tasks

async func boom(): Task<int> {
    throw new System.InvalidOperationException(""boom"")
}";

        var result = CompileAndInvoke(source, "boom");
        var task = Assert.IsAssignableFrom<Task>(result);
        var aggregate = Assert.Throws<AggregateException>(() => task.Wait());
        Assert.IsType<InvalidOperationException>(aggregate.InnerException);
        Assert.Equal("boom", aggregate.InnerException!.Message);
        Assert.True(task.IsFaulted);
    }

    [Fact]
    public void ILCompiler_AsyncWithoutAwait_UnitTask_ThatThrows_ReturnsFaultedTask()
    {
        var source = @"
import System.Threading.Tasks

async func boom(): Task {
    throw new System.InvalidOperationException(""boom"")
}";

        var result = CompileAndInvoke(source, "boom");
        var task = Assert.IsAssignableFrom<Task>(result);
        var aggregate = Assert.Throws<AggregateException>(() => task.Wait());
        Assert.IsType<InvalidOperationException>(aggregate.InnerException);
        Assert.True(task.IsFaulted);
    }

    [Fact]
    public async Task ILCompiler_AsyncWithoutAwait_ValueTaskOfT_ThatThrows_ReturnsFaultedTask()
    {
        var source = @"
import System.Threading.Tasks

async func boom(): ValueTask<int> {
    throw new System.InvalidOperationException(""boom"")
}";

        var result = CompileAndInvoke(source, "boom");
        var asTask = result!.GetType().GetMethod(nameof(ValueTask<int>.AsTask), BindingFlags.Public | BindingFlags.Instance);
        Assert.NotNull(asTask);
        var task = Assert.IsAssignableFrom<Task>(asTask!.Invoke(result, null));
        await Assert.ThrowsAsync<InvalidOperationException>(async () => await task);
        Assert.True(task.IsFaulted);
    }

    [Fact]
    public async Task ILCompiler_AsyncWithoutAwait_UnitValueTask_ThatThrows_ReturnsFaultedTask()
    {
        var source = @"
import System.Threading.Tasks

async func boom(): ValueTask {
    throw new System.InvalidOperationException(""boom"")
}";

        var result = CompileAndInvoke(source, "boom");
        var valueTask = Assert.IsType<ValueTask>(result);
        await Assert.ThrowsAsync<InvalidOperationException>(async () => await valueTask);
    }

    [Fact]
    public async Task ILCompiler_AsyncWithoutAwait_ReturnsCompletedTaskWithResult()
    {
        // Behavioral parity: an await-free async method completes successfully and returns its value.
        var source = @"
import System.Threading.Tasks

async func answer(): Task<int> {
    return 42
}

async func main(): Task<int> {
    return await answer()
}";

        var result = await CompileAndInvokeTaskResult(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public async Task ILCompiler_AsyncWithoutAwait_ThatThrowsAfterSideEffect_PreservesOrdering()
    {
        // The side effect runs before the throw, and the throw still surfaces as a faulted task
        // (the body executes synchronously up to the throw, matching C# async semantics).
        var source = @"
import System.Threading.Tasks
import System.Collections.Generic

async func work(log: List<int>): Task<int> {
    log.Add(1)
    throw new System.InvalidOperationException(""boom"")
}";

        var log = new System.Collections.Generic.List<int>();
        var result = CompileAndInvoke(source, "work", log);
        var task = Assert.IsAssignableFrom<Task>(result);
        await Assert.ThrowsAsync<InvalidOperationException>(async () => await task);
        Assert.Equal(new[] { 1 }, log);
        Assert.True(task.IsFaulted);
    }

    [Fact]
    public void ILCompiler_AsyncWithoutAwait_EmitsNoStateMachineType()
    {
        // IL-shape proof: the await-free async path emits no compiler-generated state-machine /
        // display class. (N# does not emit state machines at all today; this pins that the
        // fault-wrapping change did not introduce one.)
        var source = @"
import System.Threading.Tasks

async func answer(): Task<int> {
    return 42
}";

        CompileAndInspect(source, assembly =>
        {
            ILShapeInspector.AssertNoDisplayClass(assembly);

            var stateMachines = assembly.GetTypes()
                .Where(type => typeof(System.Runtime.CompilerServices.IAsyncStateMachine).IsAssignableFrom(type))
                .ToArray();
            Assert.Empty(stateMachines);
            return 0;
        });
    }

    [Fact]
    public void ILCompiler_CanExecuteGeneratorFunction()
    {
        var source = @"
import System.Collections.Generic

func* GetNumbers(): IEnumerable<int> {
    yield 1
    yield 2
    yield 3
}

func main(): int {
    sum := 0
    for value in GetNumbers() {
        sum += value
    }

    return sum
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(6, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteYieldBreak()
    {
        var source = @"
import System.Collections.Generic

func* GetNumbersUntilNegative(numbers: int[]): IEnumerable<int> {
    for num in numbers {
        if num < 0 {
            yield break
        }

        yield num
    }
}

func main(): int {
    sum := 0
    for value in GetNumbersUntilNegative([1, 2, -1, 4]) {
        sum += value
    }

    return sum
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(3, Assert.IsType<int>(result));
    }

    [Fact]
    public async Task ILCompiler_CanExecuteAwaitForeach()
    {
        var source = @"
import System.Threading.Tasks
import NSharpLang.Tests

async func main(): Task<int> {
    sum := 0
    await foreach value in ILCompilerAsyncHelpers.GetNumbersAsync() {
        sum += value
    }

    return sum
}";

        var result = await CompileAndInvokeTaskResult(source);
        Assert.Equal(6, Assert.IsType<int>(result));
    }

    [Fact]
    public async Task ILCompiler_CanExecuteAsyncGeneratorFunction()
    {
        var source = @"
import System.Collections.Generic
import System.Threading.Tasks
import NSharpLang.Tests

async func* GetNumbers(): IAsyncEnumerable<int> {
    yield 1
    await ILCompilerAsyncHelpers.GetValueAsync(0)
    yield 2
    await ILCompilerAsyncHelpers.GetValueAsync(0)
    yield 3
}

async func main(): Task<int> {
    sum := 0
    await foreach value in GetNumbers() {
        sum += value
    }

    return sum
}";

        var result = await CompileAndInvokeTaskResult(source);
        Assert.Equal(6, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanReturnDelegateWithFiveParameters()
    {
        var source = @"
func build(): Func<int, int, int, int, int, int> {
    return (a, b, c, d, e) => a + b + c + d + e
}

func main(): int {
    sum := build()
    return sum(1, 2, 3, 4, 5)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(15, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteSeventeenParameterLambda()
    {
        var source = @"
func main(): int {
    func sum(
        a1: int, a2: int, a3: int, a4: int, a5: int, a6: int,
        a7: int, a8: int, a9: int, a10: int, a11: int, a12: int,
        a13: int, a14: int, a15: int, a16: int, a17: int
    ): int {
        return a1 + a17
    }

    return sum(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(18, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteLocalFunctionCalls()
    {
        var source = @"
func main(value: int): int {
    func double(input: int): int {
        return input * 2
    }

    return double(value)
}";

        var result = CompileAndInvoke(source, "main", 21);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteGenericLocalFunctionCall()
    {
        var source = @"
func main(): int {
    func identity<T>(value: T): T {
        return value
    }

    return identity(42)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteGenericLocalFunctionWithConstraint()
    {
        var source = @"
func main(): int {
    func compare<T>(left: T, right: T): int where T : IComparable<T> {
        return left.CompareTo(right)
    }

    return compare(40, 42)
}";

        var result = CompileAndInvoke(source);
        Assert.True(Assert.IsType<int>(result) < 0);
    }

    [Fact]
    public void ILCompiler_CanExecuteGenericLocalFunctionUsingOuterTypeParameter()
    {
        var source = @"
func choose<T>(value: T): T {
    func firstOrFallback<U>(first: T, fallback: U): T {
        return first
    }

    return firstOrFallback(value, 0)
}

func main(): int {
    return choose(42)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteCapturedGenericLocalFunction()
    {
        var source = @"
func main(): int {
    total := 1

    func choose<T>(value: T): T {
        total += 1
        return value
    }

    first := choose(40)
    second := choose(41)
    return first + second + total
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(84, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteGenericLocalFunctionInsideClosureLambda()
    {
        var source = @"
func main(): int {
    value := 40
    compute := () => {
        func read<T>(input: T): int {
            return value + 2
        }

        return read(0)
    }

    return compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteGenericLocalFunctionAccessingInstanceState()
    {
        var source = @"
class Counter {
    value: int = 40

    func compute(): int {
        func read<T>(input: T): int {
            return value + 2
        }

        return read(0)
    }
}

func main(): int {
    counter := new Counter()
    return counter.compute()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteForwardReferencedLocalFunction()
    {
        var source = @"
func main(value: int): int {
    return double(value)

    func double(input: int): int => input * 2
}";

        var result = CompileAndInvoke(source, "main", 21);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanPassLocalFunctionAsDelegate()
    {
        var source = @"
func apply(f: Func<int, int>, value: int): int {
    return f(value)
}

func main(value: int): int {
    func double(input: int): int => input * 2
    return apply(double, value)
}";

        var result = CompileAndInvoke(source, "main", 21);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanObserveMutatedCapturedVariable()
    {
        var source = @"
func main(): int {
    value := 1
    get := () => value
    value = 2
    return get()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(2, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanCaptureOuterClosureFieldInNestedLambda()
    {
        var source = @"
func main(): int {
    value := 1
    outer := () => {
        inner := () => value
        value = 3
        return inner()
    }

    return outer()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(3, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteRecursiveLocalFunction()
    {
        var source = @"
func main(value: int): int {
    func factorial(n: int): int {
        if n <= 1 {
            return 1
        }

        return n * factorial(n - 1)
    }

    return factorial(value)
}";

        var result = CompileAndInvoke(source, "main", 5);
        Assert.Equal(120, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteMutuallyRecursiveLocalFunctions()
    {
        var source = @"
func main(value: int): bool {
    func isEven(n: int): bool {
        if n == 0 {
            return true
        }

        return isOdd(n - 1)
    }

    func isOdd(n: int): bool {
        if n == 0 {
            return false
        }

        return isEven(n - 1)
    }

    return isEven(value)
}";

        var result = CompileAndInvoke(source, "main", 6);
        Assert.True(Assert.IsType<bool>(result));
    }

    [Fact]
    public void ILCompiler_CanObserveMutatedCapturedVariableInLocalFunction()
    {
        var source = @"
func main(): int {
    value := 1

    func get(): int => value

    value = 2
    return get()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(2, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_StructClosureMutationIsSharedAcrossCallSites()
    {
        // A captured local mutated by a directly-invoked local function must observe
        // the mutation across multiple invocations and from the enclosing frame. This
        // is the critical aliasing case for the struct-box lowering: passing the box by
        // managed reference must preserve shared-mutation semantics (parity with C#:
        // an int local captured by a local function, incremented twice, reads 2).
        var source = @"
func main(): int {
    counter := 0

    func increment(): int {
        counter = counter + 1
        return counter
    }

    increment()
    increment()

    func readDoubled(): int => counter * 2

    return readDoubled()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(4, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_StructClosureIncrementMutatesSharedCapture()
    {
        // A captured local incremented (counter++) inside a directly-invoked local function
        // must write through the managed reference, not via starg. Regression test: starg on a
        // by-ref capture parameter previously produced invalid IL (NullReferenceException at JIT).
        var source = @"
func main(): int {
    counter := 0

    func bump(): int {
        counter++
        return counter
    }

    bump()
    bump()
    return counter
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(2, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_StructClosureMutationFromEnclosingFrameIsObservedByLocalFunction()
    {
        // Mutating the captured local directly in the enclosing frame after the local
        // function is defined must be observed when the local function later reads it.
        var source = @"
func main(): int {
    total := 5

    func add(n: int): int {
        total = total + n
        return total
    }

    add(10)
    total = total + 100
    add(1)

    return total
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(116, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanInferImplicitReturnTypeForLocalFunction()
    {
        var source = @"
func main(value: int): int {
    func double(input: int) => input * 2
    return double(value)
}";

        var result = CompileAndInvoke(source, "main", 21);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public async Task ILCompiler_CanExecuteAsyncLocalFunction()
    {
        var source = @"
async func main(): Task<int> {
    async func getValue(): Task<int> {
        return await ILCompilerAsyncHelpers.GetValueAsync(42)
    }

    return await getValue()
}";

        var result = await CompileAndInvokeTaskResult(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteGeneratorLocalFunction()
    {
        var source = @"
import System.Collections.Generic

func main(): int {
    func* numbers(): IEnumerable<int> {
        yield 1
        yield 2
        yield 3
    }

    sum := 0
    for value in numbers() {
        sum += value
    }

    return sum
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(6, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanBindNamedAndDefaultArgumentsForLocalFunction()
    {
        var source = @"
func main(): int {
    func score(a: int, b: int = 5, c: int = 7): int {
        return a * 100 + b * 10 + c
    }

    return score(c: 9, a: 1)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(159, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExpandParamsArgumentsForLocalFunction()
    {
        var source = @"
func main(): int {
    func sum(params numbers: int[]): int {
        total := 0
        for number in numbers {
            total += number
        }

        return total
    }

    return sum(1, 2, 3, 4)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(10, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteRefAndOutLocalFunction()
    {
        var source = @"
func main(): int {
    total := 41
    snapshot := 0

    func update(ref value: int, out copy: int) {
        value += 1
        copy = value
    }

    update(ref total, out snapshot)
    return total + snapshot
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(84, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteForLoopWithPostIncrement()
    {
        var source = @"
func main(): int {
    sum := 0
    for i := 0; i < 5; i++ {
        sum += i
    }
    return sum
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(10, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteBreakAndContinue()
    {
        var source = @"
func main(): int {
    sum := 0
    for i := 0; i < 7; i++ {
        if i == 3 {
            continue
        }

        if i == 6 {
            break
        }

        sum += i
    }

    return sum
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(12, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteArrayLiteralAndIndexAccess()
    {
        var source = @"
func main(): int {
    numbers := [4, 8, 15]
    return numbers[1]
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(8, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteSizedArrayAllocation()
    {
        var source = @"
func main(): int {
    numbers := new int[3]
    numbers[0] = 4
    numbers[1] = 8
    numbers[2] = 15
    return numbers.Length + numbers[1]
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(11, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteDiscardAssignment()
    {
        var source = @"
func main(): int {
    values := new int[1]
    values[0] = 42
    _ = values[0]
    return 7
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(7, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteStaticSizedArrayTableRead()
    {
        var source = @"
static class Table {
    static Values: int[] = Build()

    static func Build(): int[] {
        values := new int[4]
        for i := 0; i < values.Length; i++ {
            values[i] = i * 10
        }
        return values
    }
}

func main(): int {
    return Table.Values[3]
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(30, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteTernaryExpression()
    {
        var source = @"
func main(x: int): string {
    return x > 5 ? ""big"" : ""small""
}";

        var result = CompileAndInvoke(source, "main", 8);
        Assert.Equal("big", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteNullCoalesceExpression()
    {
        var source = @"
func choose(value: string): string {
    return value ?? ""fallback""
}";

        var result = CompileAndInvoke(source, "choose", new object[] { null! });
        Assert.Equal("fallback", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteTypeofAndNameof()
    {
        var source = @"
func main(): string {
    value := 42
    typeName := typeof(int).Name
    memberName := nameof(value)
    return typeName + "":"" + memberName
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("Int32:value", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteIsExpressionWithBinding()
    {
        var source = @"
func main(value: object): int {
    if value is string s {
        return s.Length
    }

    return 0
}";

        var result = CompileAndInvoke(source, "main", "hello");
        Assert.Equal(5, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteSafeCast()
    {
        var source = @"
func main(value: object): string {
    text := value as string
    return text ?? ""none""
}";

        var result = CompileAndInvoke(source, "main", "world");
        Assert.Equal("world", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteSwitchStatement()
    {
        var source = @"
func main(value: int): int {
    result := 0
    switch value {
        case 1 => result = 10
        case 2 => result = 20
        default => result = 30
    }
    return result
}";

        var result = CompileAndInvoke(source, "main", 2);
        Assert.Equal(20, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_SwitchAllCasesReturn_AsLastStatement_IsRunnable()
    {
        // Regression (same bug class as ILCompiler_IfElseBothBranchesReturn_...): a switch that is the
        // last statement of a non-void function, where every case body INCLUDING default returns, used
        // to emit a dead `br` to the switch exit-label marked at the very end of the method -- a branch
        // to an offset with no instruction, the unverifiable IL that crashes ilverify
        // (MarkPredecessorWithLowerOffset) and faults the JIT (InvalidProgramException) on invoke.
        // Definite-return is satisfied by the cases so the source compiles; the method must actually
        // run. EmitSwitch now elides the per-case exit-branch when that case body cannot fall through.
        var source = "func classify(value: int): int {\n    switch value {\n        case 1 => return 10\n        case 2 => return 20\n        default => return 30\n    }\n}\n";
        Assert.Equal(10, (int)CompileAndInvoke(source, "classify", 1)!);
        Assert.Equal(20, (int)CompileAndInvoke(source, "classify", 2)!);
        Assert.Equal(30, (int)CompileAndInvoke(source, "classify", 7)!);
    }

    [Fact]
    public void ILCompiler_CanExecuteThrowStatement()
    {
        var source = @"
func main() {
    throw new InvalidOperationException(""boom"")
}";

        var ex = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(source));
        Assert.Equal("boom", ex.Message);
    }

    [Fact]
    public void ILCompiler_CanExecuteTypeAliases()
    {
        var source = @"
type Score = int
type Formatter = Func<int, string>

func main(value: Score): Score {
    return value + 2
}";

        var result = CompileAndInvoke(source, "main", 40);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_EmitsAttributesAndDeclarationModifiers()
    {
        var source = @"
[System.Diagnostics.CodeAnalysis.SuppressMessage(""Usage"", ""CA1000"", Justification = ""global"")]
func Legacy([CLSCompliant(true)] value: int): int {
    return value
}

[Serializable]
internal class LegacyType {
    private readonly cache: int

    [System.Diagnostics.CodeAnalysis.SuppressMessage(""Usage"", ""CA0001"", Justification = ""member"")]
    protected func Run([CLSCompliant(true)] value: int): int {
        return value
    }
}";

        CompileAndInspect(source, assembly =>
        {
            var programMethod = assembly.GetType("Program")!.GetMethod("Legacy", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic);
            Assert.NotNull(programMethod);
            var globalSuppress = GetCustomAttribute(programMethod!, "System.Diagnostics.CodeAnalysis.SuppressMessageAttribute");
            Assert.Equal(new object?[] { "Usage", "CA1000" }, GetAttributeArguments(globalSuppress));
            Assert.Equal("global", Assert.IsType<string>(GetNamedAttributeValue(globalSuppress, "Justification")));
            var globalParameterAttribute = Assert.Single(programMethod.GetParameters()[0].CustomAttributes
                .Where(attribute => attribute.AttributeType.FullName == "System.CLSCompliantAttribute"));
            Assert.Equal(new object?[] { true }, GetAttributeArguments(globalParameterAttribute));

            var legacyType = assembly.GetType("LegacyType");
            Assert.NotNull(legacyType);
            GetCustomAttribute(legacyType!, "System.SerializableAttribute");
            Assert.False(legacyType!.IsPublic);

            var cacheField = legacyType.GetField("cache", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            Assert.NotNull(cacheField);
            Assert.True(cacheField!.IsInitOnly);

            var runMethod = legacyType.GetMethod("Run", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
            Assert.NotNull(runMethod);
            Assert.True(runMethod!.IsFamily);
            var memberSuppress = GetCustomAttribute(runMethod, "System.Diagnostics.CodeAnalysis.SuppressMessageAttribute");
            Assert.Equal(new object?[] { "Usage", "CA0001" }, GetAttributeArguments(memberSuppress));
            Assert.Equal("member", Assert.IsType<string>(GetNamedAttributeValue(memberSuppress, "Justification")));
            var methodParameterAttribute = Assert.Single(runMethod.GetParameters()[0].CustomAttributes
                .Where(attribute => attribute.AttributeType.FullName == "System.CLSCompliantAttribute"));
            Assert.Equal(new object?[] { true }, GetAttributeArguments(methodParameterAttribute));

            return 0;
        });
    }

    [Fact]
    public void ILCompiler_EmitsNegativeNumericAttributeArguments()
    {
        var source = @"
func Adjust([System.ComponentModel.DefaultValue(-1)] value: int): int {
    return value
}";

        CompileAndInspect(source, assembly =>
        {
            var adjustMethod = assembly.GetType("Program")!.GetMethod("Adjust", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic);
            Assert.NotNull(adjustMethod);

            var attribute = Assert.Single(adjustMethod!.GetParameters()[0].CustomAttributes
                .Where(customAttribute => customAttribute.AttributeType.FullName == "System.ComponentModel.DefaultValueAttribute"));
            Assert.Equal(new object?[] { -1 }, GetAttributeArguments(attribute));
            return 0;
        });
    }

    [Fact]
    public void ILCompiler_EmitsEnumAttributeArguments()
    {
        var source = @"
func Use([System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.I4)] value: int): int {
    return value
}";

        CompileAndInspect(source, assembly =>
        {
            var useMethod = assembly.GetType("Program")!.GetMethod("Use", BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic);
            Assert.NotNull(useMethod);

            var attribute = Assert.Single(useMethod!.GetParameters()[0].CustomAttributes
                .Where(customAttribute => customAttribute.AttributeType.FullName == "System.Runtime.InteropServices.MarshalAsAttribute"));
            Assert.Equal(typeof(System.Runtime.InteropServices.UnmanagedType), attribute.ConstructorArguments[0].ArgumentType);
            Assert.Equal(new object?[] { (int)System.Runtime.InteropServices.UnmanagedType.I4 }, GetAttributeArguments(attribute));
            return 0;
        });
    }

    [Fact]
    public void ILCompiler_EmitsBitwiseEnumAttributeArguments()
    {
        var source = @"
[System.AttributeUsage(System.AttributeTargets.Class | System.AttributeTargets.Struct)]
class MarkerAttribute: Attribute {
}";

        CompileAndInspect(source, assembly =>
        {
            var markerAttributeType = assembly.GetType("MarkerAttribute");
            Assert.NotNull(markerAttributeType);

            var attributeUsage = GetCustomAttribute(markerAttributeType!, "System.AttributeUsageAttribute");
            Assert.Equal(typeof(System.AttributeTargets), attributeUsage.ConstructorArguments[0].ArgumentType);
            Assert.Equal(
                new object?[] { (int)(System.AttributeTargets.Class | System.AttributeTargets.Struct) },
                GetAttributeArguments(attributeUsage));
            return 0;
        });
    }

    [Fact]
    public void ILCompiler_CanExecuteTupleDeconstruction()
    {
        var source = @"
func pair(): (int, int) {
    return (20, 22)
}

func main(): int {
    (x, y) := pair()
    return x + y
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteBaseMethodCall()
    {
        var source = @"
class BaseValue {
    func GetValue(): int {
        return 40
    }
}

class DerivedValue : BaseValue {
    func GetValuePlusTwo(): int {
        return base.GetValue() + 2
    }
}

func main(): int {
    value := new DerivedValue()
    return value.GetValuePlusTwo()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanCallInheritedInstanceMethodOnDerivedReceiver()
    {
        // Regression: calling an INHERITED instance method on a derived receiver (without `base.`) was reported as
        // "Method GetX not found on type D" — the instance-method-call resolution looked up only the receiver's own
        // type's methods, never the base-class chain (whereas inherited FIELD/property resolution did walk it). The
        // resolution now walks BaseType, so a derived instance can call a method declared on its base.
        var source = @"
class Base {
    X: int
    constructor(x: int) {
        X = x
    }
    func GetX(): int {
        return X
    }
}

class D: Base {
    constructor(x: int): base(x) {
    }
}

func f(v: int): int {
    d := new D(v)
    return d.GetX()
}";
        Assert.Equal(5, Assert.IsType<int>(CompileAndInvoke(source, "f", 5)));
        Assert.Equal(0, Assert.IsType<int>(CompileAndInvoke(source, "f", 0)));
    }

    [Fact]
    public void ILCompiler_CanCallInheritedMethodAlongsideOwnMembers()
    {
        // A derived class with its OWN field + method, calling an INHERITED method on the derived receiver. The
        // inherited method (GetBase) returns the base field; the derived's own method (Combined) reads both. Both
        // calls go through the (now base-chain-walking) instance-method resolution.
        var source = @"
class Base {
    A: int
    constructor(a: int) {
        A = a
    }
    func GetBase(): int {
        return A
    }
}

class D: Base {
    B: int
    constructor(a: int, b: int): base(a) {
        B = b
    }
    func GetOwn(): int {
        return B
    }
}

func sum(a: int, b: int): int {
    d := new D(a, b)
    return d.GetBase() + d.GetOwn()
}";
        Assert.Equal(8, Assert.IsType<int>(CompileAndInvoke(source, "sum", 5, 3)));
        Assert.Equal(-2, Assert.IsType<int>(CompileAndInvoke(source, "sum", 1, -3)));
    }

    [Fact]
    public void ILCompiler_CanCallInheritedMethodBareInDerivedMethodBody()
    {
        // Regression: a BARE call to an inherited method (`GetX()`, no receiver) inside a derived method body was
        // rejected — implicit-instance call resolution bound only against the enclosing type's own methods and never
        // walked the base-class chain. It now walks BaseType at both the emit and type-inference sites.
        var source = @"
class Base {
    X: int
    constructor(x: int) {
        X = x
    }
    func GetX(): int {
        return X
    }
}

class D: Base {
    Y: int
    constructor(x: int, y: int): base(x) {
        Y = y
    }
    func Sum(): int {
        return GetX() + Y
    }
}

func f(x: int, y: int): int {
    d := new D(x, y)
    return d.Sum()
}";
        Assert.Equal(8, Assert.IsType<int>(CompileAndInvoke(source, "f", 5, 3)));
        Assert.Equal(-4, Assert.IsType<int>(CompileAndInvoke(source, "f", 3, -7)));
    }

    [Fact]
    public void ILCompiler_CanExecuteMultiLevelInheritanceChain()
    {
        // Three-level chain A -> B -> C: every inherited-member lookup must walk the FULL base chain (F1 lives two
        // levels above C), and each constructor chains `: base(...)` upward. The single-level fix alone would miss F1.
        var source = @"
class A {
    F1: int
    constructor(a: int) {
        F1 = a
    }
}

class B: A {
    F2: int
    constructor(a: int, b: int): base(a) {
        F2 = b
    }
}

class C: B {
    F3: int
    constructor(a: int, b: int, c: int): base(a, b) {
        F3 = c
    }
    func Total(): int {
        return F1 + F2 + F3
    }
}

func total(a: int, b: int, c: int): int {
    x := new C(a, b, c)
    return x.Total()
}";
        Assert.Equal(6, Assert.IsType<int>(CompileAndInvoke(source, "total", 1, 2, 3)));
        Assert.Equal(0, Assert.IsType<int>(CompileAndInvoke(source, "total", 5, -2, -3)));
    }

    [Fact]
    public void ILCompiler_CanReadAndWriteInheritedFieldOnDerivedReceiver()
    {
        // Regression: `d.X` where X is declared on the BASE class failed with "Member X not found on type D" — the
        // member-access read/write/inference sites looked up fields only on the receiver's own type. They now walk
        // the base chain, so external reads AND stores of inherited fields work.
        var source = @"
class Base {
    X: int
    constructor(x: int) {
        X = x
    }
}

class D: Base {
    constructor(x: int): base(x) {
    }
}

func readWrite(x: int, v: int): int {
    d := new D(x)
    before := d.X
    d.X = v
    return before + d.X
}";
        Assert.Equal(15, Assert.IsType<int>(CompileAndInvoke(source, "readWrite", 5, 10)));
        Assert.Equal(-3, Assert.IsType<int>(CompileAndInvoke(source, "readWrite", 0, -3)));
    }

    [Fact]
    public void ILCompiler_CanReadInheritedPropertyOnDerivedReceiver()
    {
        // Inherited computed PROPERTY access on a derived receiver: the get_-accessor lookup walks the base chain
        // (same regression class as inherited fields — accessor resolution was own-type-only).
        var source = @"
class Base {
    X: int
    constructor(x: int) {
        X = x
    }
    Doubled: int {
        get {
            return X * 2
        }
    }
}

class D: Base {
    constructor(x: int): base(x) {
    }
}

func f(x: int): int {
    d := new D(x)
    return d.Doubled
}";
        Assert.Equal(10, Assert.IsType<int>(CompileAndInvoke(source, "f", 5)));
        Assert.Equal(-6, Assert.IsType<int>(CompileAndInvoke(source, "f", -3)));
    }

    [Fact]
    public void ILCompiler_EmitsImplicitBaseChainToFieldsOnlyBase()
    {
        // A derived constructor with NO `: base(...)` initializer must chain to the base's synthesized parameterless
        // constructor (NOT object::.ctor) when the base declares no constructors of its own.
        var source = @"
class Base {
    X: int
}

class D: Base {
    constructor(x: int) {
        X = x
    }
}

func f(x: int): int {
    d := new D(x)
    return d.X
}";
        Assert.Equal(3, Assert.IsType<int>(CompileAndInvoke(source, "f", 3)));
    }

    [Fact]
    public void ILCompiler_BaseInitializerConstructorMayLeaveOwnFieldsDefault()
    {
        // Pins the emitted IL shape for a `: base(x)` constructor that assigns NOTHING of its own: the base chain
        // must still run (X = x) and the derived field stays default-initialized (Y == 0).
        var source = @"
class Base {
    X: int
    constructor(x: int) {
        X = x
    }
}

class D: Base {
    Y: int
    constructor(x: int): base(x) {
    }
    func Pair(): int {
        return X * 100 + Y
    }
}

func f(x: int): int {
    d := new D(x)
    return d.Pair()
}";
        Assert.Equal(500, Assert.IsType<int>(CompileAndInvoke(source, "f", 5)));
    }

    [Fact]
    public void ILCompiler_RejectsImplicitBaseChainWhenBaseHasNoParameterlessConstructor()
    {
        // Regression: a derived constructor WITHOUT `: base(...)` whose base has only parameterized constructors
        // used to silently emit a call to object::.ctor() — unverifiable IL with every base field left zero. The
        // compiler must reject it with an actionable diagnostic instead.
        var source = @"
class Base {
    X: int
    constructor(x: int) {
        X = x
    }
}

class D: Base {
    Y: int
    constructor(y: int) {
        Y = y
    }
}

func f(y: int): int {
    d := new D(y)
    return d.Y
}";
        var ex = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(source, "f", 3));
        Assert.Contains("must chain to a base constructor", ex.Message);
        Assert.Contains(": base(...)", ex.Message);
    }

    [Fact]
    public void ILCompiler_RejectsZeroArgBaseInitializerWhenBaseHasOnlyParameterizedConstructors()
    {
        // Regression: `: base()` against a base that declares only parameterized constructors used to fall back to
        // an ARBITRARY declared constructor with no arguments pushed — InvalidProgramException at runtime. The
        // zero-argument fallback now applies only when the base declares no constructors (synthesized parameterless),
        // so this must fail at compile time.
        var source = @"
class Base {
    X: int
    constructor(x: int) {
        X = x
    }
}

class D: Base {
    Y: int
    constructor(y: int): base() {
        Y = y
    }
}

func f(y: int): int {
    d := new D(y)
    return d.Y
}";
        var ex = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(source, "f", 3));
        Assert.Contains("No matching constructor", ex.Message);
    }

    [Fact]
    public void ILCompiler_RejectsClassInheritingFromStruct()
    {
        // Regression: `class D: S` where S is a struct silently DROPPED the base (D extended Object and lost S's
        // members). Only classes and interfaces are valid in a class's base list; anything else is a compile error.
        var source = @"
struct S {
    v: int
}

class D: S {
    constructor() {
    }
}

func f(): int {
    d := new D()
    return 1
}";
        var ex = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(source, "f"));
        Assert.Contains("only classes and interfaces can appear in a base list", ex.Message);
    }

    [Fact]
    public void ILCompiler_CanCallInheritedStaticMethodViaDerivedTypeName()
    {
        // Regression: `Derived.F()` where F is a STATIC method declared on Base failed with "Static method F not
        // found on type Derived" — the static-call resolution looked up only the named type's own methods and never
        // walked the base-class chain (the same defect class as the inherited INSTANCE-member fixes, which already
        // walk it). C# semantics: a static member is accessible through any derived type's name. The 3-level chain
        // exercises a full multi-hop walk (F lives two levels above C).
        var source = @"
class A {
    static func F(): int {
        return 7
    }
}

class B: A {
}

class C: B {
}

func f(): int {
    return C.F() + B.F() + A.F()
}";
        Assert.Equal(21, Assert.IsType<int>(CompileAndInvoke(source, "f")));
    }

    [Fact]
    public void ILCompiler_CanCallInheritedStaticMethodBareInDerivedBody()
    {
        // Regression: a BARE call (`F()`, no type name) inside a derived member body where F is a STATIC method
        // declared on the base failed with "Function call ... not yet fully implemented" — the bare-call own-type
        // static lookup never walked the base-class chain (the instance twin did). Covers both a derived STATIC
        // method body and a derived INSTANCE method body resolving the inherited static bare.
        var source = @"
class Base {
    static func Seven(): int {
        return 7
    }
}

class D: Base {
    Y: int
    constructor(y: int) {
        Y = y
    }
    static func FromStatic(): int {
        return Seven()
    }
    func FromInstance(): int {
        return Seven() + Y
    }
}

func f(y: int): int {
    d := new D(y)
    return D.FromStatic() + d.FromInstance()
}";
        Assert.Equal(17, Assert.IsType<int>(CompileAndInvoke(source, "f", 3)));
    }

    [Fact]
    public void ILCompiler_InfersInheritedStaticCallReturnType()
    {
        // The TYPE-INFERENCE twin of the inherited-static chain walk: `x := Derived.F()` must infer int from the
        // base-declared static so downstream arithmetic binds correctly (not object).
        var source = @"
class Base {
    static func F(): int {
        return 7
    }
}

class Derived: Base {
}

func f(n: int): int {
    x := Derived.F()
    return x * n
}";
        Assert.Equal(21, Assert.IsType<int>(CompileAndInvoke(source, "f", 3)));
    }

    [Fact]
    public void ILCompiler_CanReadAndWriteInheritedStaticFieldViaDerivedTypeName()
    {
        // Regression: `Derived.count` where count is a STATIC FIELD declared on Base failed with "Static member
        // count not found on type Derived" — static field load/store resolution never walked the base-class chain.
        // Read the initializer value through the derived name, store through the derived name, read it back.
        var source = @"
class Base {
    static count: int = 3
}

class Derived: Base {
}

func f(v: int): int {
    before := Derived.count
    Derived.count = v
    return before * 100 + Derived.count
}";
        Assert.Equal(309, Assert.IsType<int>(CompileAndInvoke(source, "f", 9)));
    }

    [Fact]
    public void ILCompiler_CanReadInheritedStaticPropertyViaDerivedTypeName()
    {
        // Regression: `Derived.X` where X is a STATIC PROPERTY declared on Base failed with "Static member X not
        // found on type Derived" — the static getter lookup (get_X) never walked the base-class chain.
        var source = @"
class Base {
    static X: int {
        get {
            return 4
        }
    }
}

class Derived: Base {
}

func f(): int {
    return Derived.X
}";
        Assert.Equal(4, Assert.IsType<int>(CompileAndInvoke(source, "f")));
    }

    [Fact]
    public void ILCompiler_StaticMethodHidingBindsNearestDeclaration()
    {
        // Pin: a derived static method HIDING a base static of the same name must keep binding nearest-first after
        // the chain walk — `Derived.F()` binds Derived's F, `Base.F()` binds Base's, and a bare call inside a
        // Derived member binds Derived's (the walk starts at the named/enclosing type, so hiding is preserved).
        var source = @"
class Base {
    static func F(): int {
        return 1
    }
}

class Derived: Base {
    static func Probe(): int {
        return F()
    }
}

class Derived2: Base {
    static func F(): int {
        return 2
    }
    static func Probe(): int {
        return F()
    }
}

func f(): int {
    return Base.F() * 1000 + Derived2.F() * 100 + Derived.Probe() * 10 + Derived2.Probe()
}";
        Assert.Equal(1212, Assert.IsType<int>(CompileAndInvoke(source, "f")));
    }

    [Fact]
    public void ILCompiler_RejectsThisReadInStaticMethod()
    {
        // Regression: `this.x` inside a STATIC method compiled and died at RUNTIME with InvalidProgramException —
        // the emitter blindly emitted ldarg.0 against a static method (arg 0 is the first parameter, or nothing).
        // It must be a compile-time diagnostic instead.
        var source = @"
class C {
    x: int
    constructor(v: int) {
        x = v
    }
    static func Bad(): int {
        return this.x
    }
}

func f(): int {
    return C.Bad()
}";
        var ex = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(source, "f"));
        Assert.Contains("'this' cannot be used in a static context", ex.Message);
    }

    [Fact]
    public void ILCompiler_RejectsThisWriteInStaticMethod()
    {
        // The WRITE twin: `this.x = v` inside a static method must fail at compile time (it used to emit invalid IL
        // through the addressable-receiver path).
        var source = @"
class C {
    x: int
    constructor(v: int) {
        x = v
    }
    static func Bad() {
        this.x = 5
    }
}

func f(): int {
    C.Bad()
    return 1
}";
        var ex = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(source, "f"));
        Assert.Contains("'this' cannot be used in a static context", ex.Message);
    }

    [Fact]
    public void ILCompiler_RejectsReturnThisInStaticMethod()
    {
        // `return this` in a static method (this as a bare VALUE, no member access) used to compile and run against
        // garbage arg0. Compile-time diagnostic now.
        var source = @"
class C {
    static func Get(): C {
        return this
    }
}

func f(): int {
    c := C.Get()
    return 1
}";
        var ex = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(source, "f"));
        Assert.Contains("'this' cannot be used in a static context", ex.Message);
    }

    [Fact]
    public void ILCompiler_RejectsThisInTopLevelFunction()
    {
        // A top-level function compiles as a static method on the Program type — `this` has no receiver there
        // either and must produce the same compile-time diagnostic.
        var source = @"
class C {
    x: int
    constructor(v: int) {
        x = v
    }
}

func f(): int {
    return this.x
}";
        var ex = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(source, "f"));
        Assert.Contains("'this' cannot be used in a static context", ex.Message);
    }

    [Fact]
    public void ILCompiler_RejectsClassInheritingFromRecord()
    {
        // Regression: `class D: R` where R is a RECORD compiled successfully but produced an assembly that FAILS
        // TO LOAD ("Could not load type 'D' ... because the parent type is sealed") — records are emitted sealed.
        // A sealed base must be a compile-time error, like the struct-base rejection.
        var source = @"
record R {
    y: int
}

class D: R {
    n: int
    constructor(n0: int) {
        n = n0
    }
}

func f(): int {
    d := new D(1)
    return d.n
}";
        var ex = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(source, "f"));
        Assert.Contains("sealed", ex.Message);
    }

    [Fact]
    public void ILCompiler_RunsRecordStaticFieldInitializers()
    {
        // Regression: a RECORD's static-field initializers were silently DROPPED — EmitRecordBodies never called
        // EmitDeclaredStaticFieldInitializers (classes and structs did), so `static label: string = "rc"` read
        // back null and `static start: int = 7` read back 0 at runtime. The record path now emits the same
        // .cctor the class/struct paths do.
        var source = @"
record RC {
    y: int
    static start: int = 7
    static label: string = ""rc""
}

func f(): int {
    return RC.start
}

func g(): string {
    return RC.label
}";
        Assert.Equal(7, Assert.IsType<int>(CompileAndInvoke(source, "f")));
        Assert.Equal("rc", Assert.IsType<string>(CompileAndInvoke(source, "g")));
    }

    [Fact]
    public void ILCompiler_CanAccessStaticPropertyThroughInstanceReceiver()
    {
        // Regression: `c.X` where X is a STATIC property compiled a `callvirt` against the static getter and died
        // at RUNTIME with MissingMethodException (instance-receiver STATIC FIELD access already worked — the CLR
        // tolerates ldfld/stfld on statics by popping the receiver). The accessor paths now mirror the field
        // behavior: discard the receiver, direct `call`. Covers read AND write (the setter spills the value).
        var source = @"
class C {
    static backing: int
    n: int
    constructor(n0: int) {
        n = n0
    }
    static Value: int {
        get {
            return C.backing
        }
        set {
            C.backing = value
        }
    }
}

func f(v: int): int {
    c := new C(2)
    c.Value = v
    return c.Value
}";
        Assert.Equal(9, Assert.IsType<int>(CompileAndInvoke(source, "f", 9)));
        Assert.Equal(-3, Assert.IsType<int>(CompileAndInvoke(source, "f", -3)));
    }

    [Fact]
    public void ILCompiler_ThisRemainsValidInInstanceContexts()
    {
        // Over-firing pin for the static-context `this` guard: constructors, instance methods, and property
        // accessors all keep their implicit receiver — `this.`-qualified reads/writes must keep working everywhere
        // an instance receiver exists.
        var source = @"
class C {
    x: int
    constructor(v: int) {
        this.x = v
    }
    Doubled: int {
        get {
            return this.x * 2
        }
    }
    func Sum(n: int): int {
        return this.x + n
    }
}

func f(v: int, n: int): int {
    c := new C(v)
    return c.Sum(n) * 100 + c.Doubled
}";
        Assert.Equal(810, Assert.IsType<int>(CompileAndInvoke(source, "f", 5, 3)));
    }

    [Fact]
    public void ILCompiler_CanExecuteClassPrimaryConstructor()
    {
        var source = @"
class UserService(message: string) {
    func GetMessage(): string {
        return message
    }
}

func main(): string {
    service := new UserService(""ready"")
    return service.GetMessage()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("ready", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteStructPrimaryConstructor()
    {
        var source = @"
struct Point(x: int, y: int) {
    func Sum(): int {
        return x + y
    }
}

func main(): int {
    point := new Point(20, 22)
    return point.Sum()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteIndexerDeclaration()
    {
        var source = @"
class Buffer {
    values: int[]

    constructor() {
        values = [0, 0, 0]
    }

    func this[index: int]: int {
        get {
            return values[index]
        }
        set {
            values[index] = value
        }
    }
}

func main(): int {
    buffer := new Buffer()
    buffer[1] = 42
    return buffer[1]
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_EmitsNewtypeAsReadonlyValueStruct()
    {
        // A newtype must lower to a `readonly record struct` so it never boxes on the hot path
        // and stays consumable from C#. Verify the emitted type's shape directly.
        var source = @"
type UserId = newtype int";

        var info = CompileAndInspect(source, assembly =>
        {
            var userId = assembly.GetType("UserId");
            Assert.NotNull(userId);

            var valueProperty = userId!.GetProperty("Value", BindingFlags.Public | BindingFlags.Instance);
            return new
            {
                IsValueType = userId.IsValueType,
                IsSealed = userId.IsSealed,
                HasReadOnlyAttribute = userId.GetCustomAttributes(false)
                    .Any(a => a.GetType().FullName == "System.Runtime.CompilerServices.IsReadOnlyAttribute"),
                HasPublicValue = valueProperty != null && valueProperty.GetMethod is { IsPublic: true },
                ValueType = valueProperty?.PropertyType
            };
        });

        // Value type (no boxing as a reference), sealed, and marked readonly struct.
        Assert.True(info.IsValueType, "newtype must be emitted as a value type");
        Assert.True(info.IsSealed, "newtype value struct must be sealed");
        Assert.True(info.HasReadOnlyAttribute, "newtype must carry IsReadOnlyAttribute (readonly struct)");

        // Interop: the public struct exposes a public `Value` member of the underlying type for C#.
        Assert.True(info.HasPublicValue, "newtype must expose a public Value member for C# interop");
        Assert.Equal(typeof(int), info.ValueType);
    }

    [Fact]
    public void ILCompiler_NewtypeInArithmeticLoop_EmitsNoBoxing()
    {
        // Hot path: construct a newtype and read its underlying value inside a loop, doing
        // arithmetic on the result. The IL must contain no `box` opcode.
        var source = @"
type Counter = newtype int

func sum(): int {
    total := 0
    i := 0
    while i < 5 {
        c := new Counter(i)
        total = total + c.Value
        i = i + 1
    }
    return total
}";

        var hasBox = CompileAndInspect(source, assembly =>
        {
            var program = assembly.GetType("Program");
            var method = program!.GetMethod("sum", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            var opCodes = GetMethodOpCodes(method!);
            return opCodes.Any(op => op == OpCodes.Box);
        });

        Assert.False(hasBox, "newtype arithmetic must not emit a box opcode");

        // Behavior check: 0 + 1 + 2 + 3 + 4 == 10.
        Assert.Equal(10, Assert.IsType<int>(CompileAndInvoke(source, "sum")));
    }

    [Fact]
    public void ILCompiler_NewtypePassedByValue_EmitsNoBoxing()
    {
        // Passing a newtype to a function that takes the newtype must pass it by value
        // (no boxing) and the parameter type must be a value type.
        var source = @"
type Counter = newtype int

func addValue(c: Counter): int {
    return c.Value + 1
}

func run(): int {
    return addValue(new Counter(41))
}";

        var info = CompileAndInspect(source, assembly =>
        {
            var program = assembly.GetType("Program");
            var addValue = program!.GetMethod("addValue", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            var run = program!.GetMethod("run", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            return new
            {
                ParameterIsValueType = addValue!.GetParameters()[0].ParameterType.IsValueType,
                AddValueBoxes = GetMethodOpCodes(addValue!).Any(op => op == OpCodes.Box),
                RunBoxes = GetMethodOpCodes(run!).Any(op => op == OpCodes.Box)
            };
        });

        Assert.True(info.ParameterIsValueType, "newtype parameter must be a value type");
        Assert.False(info.AddValueBoxes, "reading newtype Value must not box");
        Assert.False(info.RunBoxes, "passing a newtype by value must not box");

        Assert.Equal(42, Assert.IsType<int>(CompileAndInvoke(source, "run")));
    }

    [Fact]
    public void ILCompiler_CanExecuteNewtypeDeclaration()
    {
        var source = @"
type UserId = newtype int

func main(): int {
    userId := new UserId(42)
    return userId.Value
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteNewtypeCallStyleConstruction()
    {
        // The call-style shorthand `UserId(42)` lowers to `new UserId(42)`. It must construct the
        // newtype, infer the local's type as the wrapper (so `.Value` reads the underlying int),
        // and pass by value into a function that takes the newtype.
        var source = @"
type UserId = newtype int

func unwrap(u: UserId): int {
    return u.Value
}

func main(): int {
    id := UserId(42)
    return id.Value + unwrap(UserId(58))
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(100, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteStringEnumMemberAccess()
    {
        var source = @"
enum Status: string {
    Active = ""active"",
    Inactive = ""inactive""
}

func main(): string {
    return Status.Active
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("active", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_EmitsIntEnumType()
    {
        var source = @"
enum Priority {
    Low,
    Medium,
    High
}";

        var enumInfo = CompileAndInspect(source, assembly =>
        {
            var priorityType = assembly.GetType("Priority");
            Assert.NotNull(priorityType);
            return new
            {
                IsEnum = priorityType!.IsEnum,
                Names = Enum.GetNames(priorityType)
            };
        });

        Assert.True(enumInfo.IsEnum);
        Assert.Equal(new[] { "Low", "Medium", "High" }, enumInfo.Names);
    }

    [Fact]
    public void ILCompiler_CanExecuteStaticMethodCallOnClrType()
    {
        var source = @"
func main(): int {
    return Math.Max(40, 42)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteUnionMatchWithPropertyBinding()
    {
        var source = @"
union Result {
    Success { value: int }
    Failure { error: string }
}

func make(ok: bool): Result {
    if ok {
        return new Result.Success { value: 42 }
    }
    return new Result.Failure { error: ""nope"" }
}

func main(ok: bool): int {
    result := make(ok)
    return match result {
        Result.Success { value } => value,
        Result.Failure { error } => 0
    }
}";

        var result = CompileAndInvoke(source, "main", true);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteUnionMatchBindingWithOuterVariableCollision()
    {
        var source = @"
union CommandResult {
    Success { message: string }
    Error { message: string }
}

func make(ok: bool): CommandResult {
    if ok {
        return new CommandResult.Success { message: ""done"" }
    }
    return new CommandResult.Error { message: ""failed"" }
}

func main(ok: bool): string {
    result := make(ok)
    message := match result {
        CommandResult.Success { message } => message,
        CommandResult.Error { message } => $""Error: {message}""
    }
    return message
}";

        var result = CompileAndInvoke(source, "main", false);
        Assert.Equal("Error: failed", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_InfersUnionMatchBindingTypeForSubsequentMethodCalls()
    {
        var source = @"
union CommandResult {
    Success { message: string }
    Error { message: string }
}

func make(): CommandResult {
    return new CommandResult.Success { message: ""done writing tests"" }
}

func main(): bool {
    result := make()
    text := match result {
        CommandResult.Success { message } => message,
        CommandResult.Error { message } => message
    }
    return text.Contains(""tests"")
}";

        var result = CompileAndInvoke(source);
        Assert.True(Assert.IsType<bool>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteUnionCaseConstructionAndFieldRead()
    {
        var source = @"
union Result {
    Success { value: int }
    Failure { error: string }
}

func main(): int {
    result := new Result.Success { value: 42 }
    return result.value
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteUnionMatchWithoutPropertyBinding()
    {
        var source = @"
union Result {
    Success { value: int }
    Failure { error: string }
}

func make(ok: bool): Result {
    if ok {
        return new Result.Success { value: 42 }
    }
    return new Result.Failure { error: ""nope"" }
}

func main(ok: bool): int {
    result := make(ok)
    return match result {
        Result.Success => 1,
        Result.Failure => 0
    }
}";

        var success = CompileAndInvoke(source, "main", true);
        Assert.Equal(1, Assert.IsType<int>(success));

        var failure = CompileAndInvoke(source, "main", false);
        Assert.Equal(0, Assert.IsType<int>(failure));
    }

    [Fact]
    public void ILCompiler_EmitsNestedUnionCaseTypes()
    {
        var source = @"
union Shape {
    Circle { radius: int }
    Square { side: int }
}";

        var typeNames = CompileAndInspect(source, assembly =>
            assembly.GetTypes().Select(t => t.FullName).Where(n => n != null).OrderBy(n => n).ToArray());

        Assert.Contains("Shape", typeNames);
        Assert.Contains("Shape+Circle", typeNames);
        Assert.Contains("Shape+Square", typeNames);
    }

    [Fact]
    public void ILCompiler_PayloadFreeUnion_IsEmittedAsValueStruct()
    {
        var source = @"
union Color {
    Red
    Green
    Blue
}";

        var isValueType = CompileAndInspect(source, assembly =>
        {
            var unionType = assembly.GetType("Color");
            Assert.NotNull(unionType);
            return unionType!.IsValueType;
        });

        Assert.True(isValueType, "Small, closed, payload-free union should be emitted as a value type.");
    }

    [Fact]
    public void ILCompiler_PayloadFreeUnion_StillEmitsNestedCaseMarkerTypes()
    {
        var source = @"
union Color {
    Red
    Green
    Blue
}";

        var typeNames = CompileAndInspect(source, assembly =>
            assembly.GetTypes().Select(t => t.FullName).Where(n => n != null).OrderBy(n => n).ToArray());

        Assert.Contains("Color", typeNames);
        Assert.Contains("Color+Red", typeNames);
        Assert.Contains("Color+Green", typeNames);
        Assert.Contains("Color+Blue", typeNames);
    }

    [Fact]
    public void ILCompiler_PayloadFreeUnion_ExposesTagToCSharpInterop()
    {
        var source = @"
union Color {
    Red
    Green
    Blue
}";

        var (isValueType, hasTagProperty, redTag, blueTag) = CompileAndInspect(source, assembly =>
        {
            var unionType = assembly.GetType("Color")!;
            var tagProperty = unionType.GetProperty("Tag", BindingFlags.Public | BindingFlags.Instance);

            var red = unionType.GetNestedType("Red")!.GetField("Tag", BindingFlags.Public | BindingFlags.Static);
            var blue = unionType.GetNestedType("Blue")!.GetField("Tag", BindingFlags.Public | BindingFlags.Static);

            return (
                unionType.IsValueType,
                tagProperty != null && tagProperty.PropertyType == typeof(int),
                (int)red!.GetRawConstantValue()!,
                (int)blue!.GetRawConstantValue()!);
        });

        Assert.True(isValueType);
        Assert.True(hasTagProperty, "Value-struct union should expose a public int Tag property for C# consumers.");
        Assert.Equal(0, redTag);
        Assert.Equal(2, blueTag);
    }

    [Fact]
    public void ILCompiler_PayloadFreeUnionConstruction_DoesNotAllocatePerCase()
    {
        var source = @"
union Signal {
    Stop
    Go
}

func choose(go: bool): Signal {
    if go {
        return new Signal.Go
    }
    return new Signal.Stop
}";

        var hasNewobj = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program")!;
            var method = programType.GetMethod("choose", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)!;
            return GetMethodOpCodes(method).Contains(OpCodes.Newobj);
        });

        Assert.False(hasNewobj, "Value-struct union construction must not allocate a per-case object (no newobj).");
    }

    [Fact]
    public void ILCompiler_PayloadFreeUnionMatch_DoesNotUseIsinst()
    {
        var source = @"
union Signal {
    Stop
    Go
}

func describe(go: bool): int {
    s := new Signal.Stop
    if go {
        s = new Signal.Go
    }
    return match s {
        Signal.Stop => 1,
        Signal.Go => 2
    }
}";

        var hasIsinst = CompileAndInspect(source, assembly =>
        {
            var programType = assembly.GetType("Program")!;
            var method = programType.GetMethod("describe", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)!;
            return GetMethodOpCodes(method).Contains(OpCodes.Isinst);
        });

        Assert.False(hasIsinst, "Value-struct union match must dispatch on the integer tag, not isinst.");
    }

    [Fact]
    public void ILCompiler_CanConstructAndMatchPayloadFreeValueStructUnion()
    {
        var source = @"
union Signal {
    Stop
    Go
    Wait
}

func make(code: int): Signal {
    if code == 0 {
        return new Signal.Stop
    }
    if code == 1 {
        return new Signal.Go
    }
    return new Signal.Wait
}

func main(code: int): int {
    s := make(code)
    return match s {
        Signal.Stop => 100,
        Signal.Go => 200,
        Signal.Wait => 300
    }
}";

        Assert.Equal(100, Assert.IsType<int>(CompileAndInvoke(source, "main", 0)));
        Assert.Equal(200, Assert.IsType<int>(CompileAndInvoke(source, "main", 1)));
        Assert.Equal(300, Assert.IsType<int>(CompileAndInvoke(source, "main", 2)));
    }

    [Fact]
    public void ILCompiler_ValueStructUnion_InferredLocalAndArgumentPassing()
    {
        // Exercises (a) direct `:=` inference from `new U.Case`, and (b) passing a
        // value-struct union across a function boundary as an argument — both must
        // round-trip without a spurious box/unbox.
        var source = @"
union Signal {
    Stop
    Go
}

func classify(s: Signal): int {
    return match s {
        Signal.Stop => 7,
        Signal.Go => 9
    }
}

func main(go: bool): int {
    s := new Signal.Stop
    if go {
        s = new Signal.Go
    }
    return classify(s)
}";

        Assert.Equal(7, Assert.IsType<int>(CompileAndInvoke(source, "main", false)));
        Assert.Equal(9, Assert.IsType<int>(CompileAndInvoke(source, "main", true)));
    }

    [Fact]
    public void ILCompiler_ValueStructUnion_IsExpressionUsesTagCompare()
    {
        var source = @"
union Signal {
    Stop
    Go
}

func isStop(go: bool): bool {
    s := new Signal.Stop
    if go {
        s = new Signal.Go
    }
    return s is Signal.Stop
}";

        Assert.True(Assert.IsType<bool>(CompileAndInvoke(source, "isStop", false)));
        Assert.False(Assert.IsType<bool>(CompileAndInvoke(source, "isStop", true)));

        var hasIsinst = CompileAndInspect(source, assembly =>
        {
            var program = assembly.GetType("Program")!;
            var method = program.GetMethod("isStop", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)!;
            return GetMethodOpCodes(method).Contains(OpCodes.Isinst);
        });

        Assert.False(hasIsinst, "is-expression against a value-struct union case must compare the tag, not use isinst.");
    }

    [Fact]
    public void ILCompiler_PayloadCarryingUnion_KeepsClassHierarchyRepresentation()
    {
        // Unions whose cases carry payloads are NOT yet value-struct emittable; they
        // must keep the reference class-hierarchy representation so existing behavior
        // (field reads, isinst matching, C# class interop) is preserved.
        var source = @"
union Result {
    Success { value: int }
    Failure { error: string }
}";

        var isValueType = CompileAndInspect(source, assembly =>
            assembly.GetType("Result")!.IsValueType);

        Assert.False(isValueType, "Payload-carrying union must remain a reference type (class hierarchy).");
    }

    [Fact]
    public void ILCompiler_GenericUnion_ConstructAndMatch()
    {
        // The README flagship: a generic union with a type-parameter payload,
        // constructed with explicit type arguments after the case name and matched
        // with the type arguments inferred from the scrutinee.
        var source = @"
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

func classify(r: Result<int>): string {
    return match r {
        Result.Success { value: x } => $""Got {x}"",
        Result.Failure { error: e } => $""Error: {e}""
    }
}

func main(): string {
    ok := classify(new Result.Success<int> { value: 42 })
    bad := classify(new Result.Failure<int> { error: ""boom"" })
    return $""{ok}|{bad}""
}";

        Assert.Equal("Got 42|Error: boom", Assert.IsType<string>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_GenericUnion_MultipleInstantiationsCoexist()
    {
        // Result<int> and Result<string> are distinct closed types over the same
        // definition; bindings must substitute each instantiation's argument.
        var source = @"
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

func main(): string {
    numeric := new Result.Success<int> { value: 41 }
    text := new Result.Success<string> { value: ""hi"" }

    sum := match numeric {
        Result.Success { value } => value + 1,
        Result.Failure { error } => 0
    }
    greeting := match text {
        Result.Success { value } => value + ""!"",
        Result.Failure { error } => error
    }
    return $""{sum} {greeting}""
}";

        Assert.Equal("42 hi!", Assert.IsType<string>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_GenericUnion_TargetTypedCaseConstruction()
    {
        // A payload-free case has no argument to infer from; the documented form
        // adopts the expected type's arguments (return new Option.None on Option<T>).
        var source = @"
union Option<T> {
    Some { value: T }
    None { }
}

func find(flag: bool): Option<string> {
    if flag {
        return new Option.Some<string> { value: ""found"" }
    }
    return new Option.None
}

func describe(o: Option<string>): string {
    return match o {
        Option.Some { value } => value,
        Option.None => ""missing""
    }
}

func main(): string {
    return $""{describe(find(true))}|{describe(find(false))}""
}";

        Assert.Equal("found|missing", Assert.IsType<string>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_GenericUnion_GuardedMatchAndCatchAll()
    {
        var source = @"
union Result<T> {
    Success { value: T }
    Failure { error: string }
}

func main(): string {
    r := new Result.Success<int> { value: 7 }
    return match r {
        Result.Success { value } when value > 10 => ""big"",
        Result.Success { value } => $""small {value}"",
        _ => ""failure""
    }
}";

        Assert.Equal("small 7", Assert.IsType<string>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_GenericUnion_EmitsGenericBaseAndCaseMetadata()
    {
        // CLR shape: an abstract generic base, with each case a sealed nested class
        // that redeclares the type parameters and derives from the closed base
        // (Result`1+Success<T> : Result<T>), its payload field typed by the parameter.
        var source = @"
union Result<T> {
    Success { value: T }
    Failure { error: string }
}";

        CompileAndInspect(source, assembly =>
        {
            // N# emits generic definitions under their bare declared name (no CLR
            // arity suffix), matching generic classes.
            var baseType = assembly.GetType("Result")!;
            Assert.True(baseType.IsAbstract);
            Assert.True(baseType.IsGenericTypeDefinition);
            Assert.Single(baseType.GetGenericArguments());

            var successCase = baseType.GetNestedType("Success")!;
            Assert.True(successCase.IsSealed);
            Assert.True(successCase.IsGenericTypeDefinition);
            Assert.Equal(baseType, successCase.BaseType!.GetGenericTypeDefinition());

            // camelCase member names emit non-public per N# visibility conventions.
            var valueField = successCase.GetField("value", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)!;
            Assert.True(valueField.FieldType.IsGenericParameter);

            var closedSuccess = successCase.MakeGenericType(typeof(int));
            Assert.True(baseType.MakeGenericType(typeof(int)).IsAssignableFrom(closedSuccess));
            return true;
        });
    }

    [Fact]
    public void ILCompiler_CanExecuteDefaultExpressionInTypedContexts()
    {
        var source = @"
func fallback(): string {
    return default
}

func main(): int {
    count: int = default
    text: string = default
    if text == null && fallback() == null {
        return count + 42
    }
    return 0
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteDefaultExpressionInAssignment()
    {
        var source = @"
func main(): string {
    text: string = ""hello""
    text = default
    return text ?? ""fallback""
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("fallback", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteRefParameter()
    {
        var source = @"
func bump(ref value: int) {
    value += 1
}

func main(): int {
    number := 41
    bump(ref number)
    return number
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteRefParameterOnArrayElement()
    {
        var source = @"
func bump(ref value: int) {
    value += 1
}

func main(): int {
    values := [10, 20, 30]
    bump(ref values[1])
    return values[1]
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(21, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteRefParameterOnInstanceField()
    {
        var source = @"
class Counter {
    Value: int
}

func bump(ref value: int) {
    value += 1
}

func main(): int {
    counter := new Counter { Value: 41 }
    bump(ref counter.Value)
    return counter.Value
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteRefParameterOnByRefStructField()
    {
        var source = @"
struct Counter {
    Value: int
}

func bump(ref value: int) {
    value += 1
}

func touch(counter: &Counter): int {
    bump(ref counter.Value)
    return counter.Value
}

func main(): int {
    counter := new Counter { Value: 41 }
    return touch(ref counter)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteRefParameterOnStaticField()
    {
        var source = @"
class State {
    static Value: int
}

func bump(ref value: int) {
    value += 1
}

func main(): int {
    State.Value = 41
    bump(ref State.Value)
    return State.Value
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteOutParameterOnUserFunction()
    {
        var source = @"
func tryGetValue(out value: int): bool {
    value = 42
    return true
}

func main(): int {
    result := 0
    if tryGetValue(out result) {
        return result
    }
    return 0
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_RejectsInlineOutVarOnClrMethod()
    {
        var source = @"
func main(): int {
        if int.TryParse(""42"", out var value) {
        return value
    }
    return 0
}";

        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl", source);
        var result = parser.ParseCompilationUnit();

        Assert.False(result.Success);
        Assert.Contains(result.Errors, error => error.Message.Contains("Inline out declarations are not supported"));
    }

    [Fact]
    public void ILCompiler_CanExecuteExistingOutVariableOnClrMethod()
    {
        var source = @"
func main(): int {
    value := 0
    if int.TryParse(""42"", out value) {
        return value
    }
    return 0
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteCharLiteralStringSplit()
    {
        var source = @"
func main(): int {
    parts := ""one|two|three"".Split('|')
    return parts.Length
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(3, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_TryCatchAllBranchesReturn()
    {
        var source = @"
import System

func parseId(s: string): int {
    try {
        return Int32.Parse(s)
    } catch ex: FormatException {
        return -1
    }
}

func main(): int {
    return parseId(""not-a-number"")
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(-1, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteAssertStatement()
    {
        var source = @"
func main(): int {
    assert 40 + 2 == 42
    return 42
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_ThrowsForFailedAssertStatement()
    {
        var source = @"
func main() {
    assert false, ""boom""
}";

        var ex = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(source));
        Assert.Equal("boom", ex.Message);
    }

    [Fact]
    public void ILCompiler_CanExecuteAssertThrowsStatement()
    {
        var source = @"
func main(): int {
    assert throws InvalidOperationException {
        throw new InvalidOperationException(""boom"")
    }
    return 42
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteSizeOfExpression()
    {
        var source = @"
func main(): int {
    return sizeof(int) + sizeof(byte)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(5, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteTargetTypedNew()
    {
        var source = @"
class Person {
    Name: string

    constructor(name: string) {
        Name = name
    }
}

func main(): string {
    person: Person = new(""Alice"")
    return person.Name
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("Alice", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteTargetTypedNewWithInitializer()
    {
        var source = @"
class Person {
    Name: string
    Age: int
}

func main(): int {
    person: Person = new { Name: ""Alice"", Age: 42 }
    return person.Age
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteTargetTypedNewInReturn()
    {
        var source = @"
class Person {
    Name: string
}

func create(): Person {
    return new { Name: ""Alice"" }
}

func main(): string {
    return create().Name
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("Alice", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteNullCoalesceAssignOnIdentifier()
    {
        var source = @"
func main(): string {
    text: string = null
    text ??= ""fallback""
    return text
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("fallback", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteNullCoalesceAssignOnMember()
    {
        var source = @"
class Box {
    Text: string
}

func main(): string {
    box := new Box()
    box.Text ??= ""fallback""
    return box.Text
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("fallback", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteNullCoalesceAssignOnIndex()
    {
        var source = @"
class Slots {
    First: string
    Second: string

    func this[index: int]: string {
        get {
            if index == 0 {
                return First
            }
            return Second
        }
        set {
            if index == 0 {
                First = value
            } else {
                Second = value
            }
        }
    }
}

func main(): string {
    slots := new Slots()
    slots[1] = ""ready""
    slots[0] ??= ""fallback""
    slots[1] ??= ""other""
    return slots[0] + "":"" + slots[1]
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("fallback:ready", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteNullConditionalMemberAccess()
    {
        var source = @"
func main(text: string): int {
    return text?.Length ?? 0
}";

        var nullResult = CompileAndInvoke(source, "main", new object[] { null! });
        Assert.Equal(0, Assert.IsType<int>(nullResult));

        var textResult = CompileAndInvoke(source, "main", "hello");
        Assert.Equal(5, Assert.IsType<int>(textResult));
    }

    [Fact]
    public void ILCompiler_CanExecuteNullConditionalIndexAccess()
    {
        var source = @"
func main(values: string[]): string {
    return values?[1] ?? ""none""
}";

        var nullResult = CompileAndInvoke(source, "main", new object[] { null! });
        Assert.Equal("none", Assert.IsType<string>(nullResult));

        var valuesResult = CompileAndInvoke(source, "main", new object[] { new[] { "zero", "one" } });
        Assert.Equal("one", Assert.IsType<string>(valuesResult));
    }

    [Fact]
    public void ILCompiler_CanExecuteDefaultExpressionAsFunctionArgument()
    {
        var source = @"
func bump(value: int): int {
    return value + 2
}

func main(): int {
    return bump(default)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(2, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteIndexFromEndAndRangeAccessOnArrays()
    {
        var source = @"
func main(): int {
    values := [10, 20, 30, 40, 50]
    prefix := values[..2]
    middle := values[1..^1]
    suffix := values[3..]
    clone := values[..]
    return prefix[1] + middle[2] + suffix[1] + clone[^1]
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(160, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteSpreadArrayLiteral()
    {
        var source = @"
func main(): int {
    arr1 := [1, 2]
    arr2 := [...arr1, 3, 4]
    return arr2.Length * 100 + arr2[0] * 10 + arr2[3]
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(414, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteTypedListCollectionExpression()
    {
        var source = @"
import System.Collections.Generic

func main(): int {
    numbers: List<int> = [1, 2, 3]
    return numbers.Count * 100 + numbers[0] * 10 + numbers[2]
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(313, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteRepeatedBlockLocalAfterLinqToListOnUserType()
    {
        var source = @"
import System.Collections.Generic
import System.Linq

record Item {
    Name: string
}

class Service {
    items: List<Item>

    constructor() {
        items = new List<Item>()
        items.Add(new Item { Name: ""first"" })
        items.Add(new Item { Name: ""second"" })
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

func main(): int {
    service := new Service()
    return service.Filter(false, ""SECOND"").Count
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(1, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteHashSetCollectionExpression()
    {
        var source = @"
import System.Collections.Generic

func main(): int {
    unique: HashSet<int> = [1, 1, 2, 3]
    return unique.Count
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(3, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteQueueCollectionExpression()
    {
        var source = @"
import System.Collections.Generic

func main(): string {
    queue: Queue<string> = [""first"", ""second"", ""third""]
    return queue.Dequeue() + "":""
        + queue.Dequeue() + "":""
        + queue.Dequeue()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("first:second:third", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanResolveImportedGenericTypesInFunctionSignatures()
    {
        var source = @"
import System.Collections.Generic

func first(queue: Queue<string>): string {
    return queue.Dequeue()
}

func count(unique: HashSet<int>): int {
    return unique.Count
}

func main(): string {
    queue := new Queue<string>()
    queue.Enqueue(""alpha"")
    queue.Enqueue(""beta"")

    unique := new HashSet<int>()
    unique.Add(1)
    unique.Add(1)
    unique.Add(2)

    return first(queue) + "":""
        + count(unique)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("alpha:2", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteInterfaceTypedCollectionExpressionWithSpread()
    {
        var source = @"
import System.Collections.Generic

func main(): int {
    prefix: List<int> = [1, 2]
    values: IEnumerable<int> = [0, ...prefix, 3]
    result := 0
    for value in values {
        result = result * 10 + value
    }
    return result
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(123, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteSpreadInFunctionCall()
    {
        var source = @"
func second(values: int[]): int {
    return values[1]
}

func main(): int {
    items := [7, 8, 9]
    return second(...items)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(8, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteIndexerObjectInitializer()
    {
        var source = @"
import System.Collections.Generic

func main(): int {
    dict := new Dictionary<string, int> {
        [""a""] = 10,
        [""b""] = 32
    }
    return dict[""a""] + dict[""b""]
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteDictionaryIndexerGetSetAndNestedAccess()
    {
        var source = @"
import System.Collections.Generic

func main(): string {
    headers := new Dictionary<string, string>()
    name := ""Accept""
    headers[name] = ""text/plain""
    value := headers[name]

    nested := new Dictionary<string, Dictionary<string, string>>()
    nested[""outer""] = new Dictionary<string, string>()
    nested[""outer""][""inner""] = value

    return nested[""outer""][""inner""]
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("text/plain", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanBindDictionaryRemoveOverloads()
    {
        var ordinaryRemove = @"
import System.Collections.Generic

func main(): bool {
    headers := new Dictionary<string, string>()
    headers[""Accept""] = ""text/plain""
    removed := headers.Remove(""Accept"")
    return removed && !headers.ContainsKey(""Accept"")
}";

        var ordinaryResult = CompileAndInvoke(ordinaryRemove);
        Assert.True(Assert.IsType<bool>(ordinaryResult));

        var outRemove = @"
import System.Collections.Generic

func main(): string {
    headers := new Dictionary<string, string>()
    headers[""Accept""] = ""text/plain""
    removedValue := """"
    if headers.Remove(""Accept"", out removedValue) {
        return removedValue
    }

    return ""missing""
}";

        var outResult = CompileAndInvoke(outRemove);
        Assert.Equal("text/plain", Assert.IsType<string>(outResult));
    }

    [Fact]
    public void ILCompiler_CanExecutePositionalPattern()
    {
        var source = @"
func main(x: int, y: int): string {
    point := (x, y)
    return match point {
        (0, 0) => ""origin"",
        (0, _) => ""y-axis"",
        _ => ""other""
    }
}";

        var origin = CompileAndInvoke(source, "main", 0, 0);
        Assert.Equal("origin", Assert.IsType<string>(origin));

        var yAxis = CompileAndInvoke(source, "main", 0, 5);
        Assert.Equal("y-axis", Assert.IsType<string>(yAxis));

        var other = CompileAndInvoke(source, "main", 3, 4);
        Assert.Equal("other", Assert.IsType<string>(other));
    }

    [Fact]
    public void ILCompiler_CanExecuteListPatternsWithSliceBinding()
    {
        var source = @"
func main(values: int[]): string {
    return match values {
        [] => ""empty"",
        [1, 2, 3] => ""exact"",
        [single] => $""one:{single}"",
        [first, .. middle, last] => $""{first}:{middle.Length}:{last}"",
        _ => ""other""
    }
}";

        var empty = CompileAndInvoke(source, "main", new object[] { Array.Empty<int>() });
        Assert.Equal("empty", Assert.IsType<string>(empty));

        var exact = CompileAndInvoke(source, "main", new object[] { new[] { 1, 2, 3 } });
        Assert.Equal("exact", Assert.IsType<string>(exact));

        var single = CompileAndInvoke(source, "main", new object[] { new[] { 7 } });
        Assert.Equal("one:7", Assert.IsType<string>(single));

        var slice = CompileAndInvoke(source, "main", new object[] { new[] { 5, 6, 7, 8 } });
        Assert.Equal("5:2:8", Assert.IsType<string>(slice));
    }

    [Fact]
    public void ILCompiler_CanExecuteListPatternsOnList()
    {
        var source = @"
import System.Collections.Generic

func main(values: List<int>): string {
    return match values {
        [] => ""empty"",
        [1, 2, 3] => ""exact"",
        [single] => $""one:{single}"",
        [first, .. middle, last] => $""{first}:{middle.Length}:{last}"",
        _ => ""other""
    }
}";

        var empty = CompileAndInvoke(source, "main", new object[] { new List<int>() });
        Assert.Equal("empty", Assert.IsType<string>(empty));

        var exact = CompileAndInvoke(source, "main", new object[] { new List<int> { 1, 2, 3 } });
        Assert.Equal("exact", Assert.IsType<string>(exact));

        var single = CompileAndInvoke(source, "main", new object[] { new List<int> { 7 } });
        Assert.Equal("one:7", Assert.IsType<string>(single));

        var slice = CompileAndInvoke(source, "main", new object[] { new List<int> { 5, 6, 7, 8 } });
        Assert.Equal("5:2:8", Assert.IsType<string>(slice));
    }

    [Fact]
    public void ILCompiler_CanExecuteWithExpression()
    {
        var source = @"
record Person {
    Name: string
    Age: int
}

func main(): string {
    original := new Person { Name: ""Alice"", Age: 30 }
    updated := original with { Age: 31 }

    if original.Age == 30 && updated.Age == 31 && updated.Name == ""Alice"" {
        return ""ok""
    }

    return ""bad""
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("ok", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_EmitsExecutableTestClassWithSetupAndTeardown()
    {
        var source = @"
setup {
    count := 41
}

teardown {
    count += 1
}

test ""should add one"" {
    assert count == 41
}";

        CompileAndInspect(source, assembly =>
        {
            var testType = assembly.GetType("NSharpTests");
            Assert.NotNull(testType);
            Assert.Contains(typeof(IDisposable), testType!.GetInterfaces());

            var testMethod = testType.GetMethod("ShouldAddOne", BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(testMethod);
            GetCustomAttribute(testMethod!, "Xunit.FactAttribute");

            var traitAttribute = GetCustomAttribute(testMethod!, "Xunit.TraitAttribute");
            Assert.Equal(new object?[] { "NSharpDescription", "should add one" }, GetAttributeArguments(traitAttribute));

            var countField = testType.GetField("count", BindingFlags.NonPublic | BindingFlags.Instance);
            Assert.NotNull(countField);

            var instance = Activator.CreateInstance(testType);
            Assert.NotNull(instance);
            Assert.Equal(41, Assert.IsType<int>(countField!.GetValue(instance)));

            testMethod.Invoke(instance, null);
            testType.GetMethod(nameof(IDisposable.Dispose), BindingFlags.Public | BindingFlags.Instance)!.Invoke(instance, null);

            Assert.Equal(42, Assert.IsType<int>(countField.GetValue(instance)));
            return true;
        });
    }

    [Fact]
    public async Task ILCompiler_EmitsAsyncLifetimeForAsyncSetup()
    {
        var source = @"
setup {
    count := 40
    await Task.CompletedTask
    count += 2
}

test ""should await setup"" {
    assert count == 42
}";

        await CompileAndInspect(source, async assembly =>
        {
            var testType = assembly.GetType("NSharpTests");
            Assert.NotNull(testType);
            Assert.Contains(typeof(Xunit.IAsyncLifetime), testType!.GetInterfaces());

            var countField = testType.GetField("count", BindingFlags.NonPublic | BindingFlags.Instance);
            Assert.NotNull(countField);

            var instance = Activator.CreateInstance(testType);
            Assert.NotNull(instance);

            await InvokeAndAwaitAsyncMethod(instance!, "InitializeAsync");
            Assert.Equal(42, Assert.IsType<int>(countField!.GetValue(instance)));

            testType.GetMethod("ShouldAwaitSetup", BindingFlags.Public | BindingFlags.Instance)!.Invoke(instance, null);
            await InvokeAndAwaitAsyncMethod(instance, "DisposeAsync");
            return true;
        });
    }

    [Fact]
    public async Task ILCompiler_EmitsAsyncLifetimeForAsyncSetupAndTeardown()
    {
        var source = @"
setup {
    count := 40
    await Task.CompletedTask
    count += 1
}

teardown {
    await Task.CompletedTask
    count += 1
}

test ""should await lifecycle"" {
    assert count == 41
}";

        await CompileAndInspect(source, async assembly =>
        {
            var testType = assembly.GetType("NSharpTests");
            Assert.NotNull(testType);
            Assert.Contains(typeof(Xunit.IAsyncLifetime), testType!.GetInterfaces());

            var countField = testType.GetField("count", BindingFlags.NonPublic | BindingFlags.Instance);
            Assert.NotNull(countField);

            var instance = Activator.CreateInstance(testType);
            Assert.NotNull(instance);

            await InvokeAndAwaitAsyncMethod(instance!, "InitializeAsync");
            Assert.Equal(41, Assert.IsType<int>(countField!.GetValue(instance)));

            testType.GetMethod("ShouldAwaitLifecycle", BindingFlags.Public | BindingFlags.Instance)!.Invoke(instance, null);
            await InvokeAndAwaitAsyncMethod(instance, "DisposeAsync");
            Assert.Equal(42, Assert.IsType<int>(countField.GetValue(instance)));
            return true;
        });
    }

    [Fact]
    public async Task ILCompiler_EmitsAsyncLifetimeForAsyncTeardownWithoutSetup()
    {
        var source = @"
teardown {
    await Task.CompletedTask
}

test ""should await teardown"" {
    assert true
}";

        await CompileAndInspect(source, async assembly =>
        {
            var testType = assembly.GetType("NSharpTests");
            Assert.NotNull(testType);
            Assert.Contains(typeof(Xunit.IAsyncLifetime), testType!.GetInterfaces());
            Assert.DoesNotContain(typeof(IDisposable), testType.GetInterfaces());

            var instance = Activator.CreateInstance(testType);
            Assert.NotNull(instance);

            await InvokeAndAwaitAsyncMethod(instance!, "InitializeAsync");
            testType.GetMethod("ShouldAwaitTeardown", BindingFlags.Public | BindingFlags.Instance)!.Invoke(instance, null);
            await InvokeAndAwaitAsyncMethod(instance, "DisposeAsync");
            return true;
        });
    }

    [Fact]
    public void ILCompiler_EmitsNUnitFixtureAndLifecycleMetadata()
    {
        var source = @"
setup {
    count := 41
}

teardown {
    count += 1
}

test ""should query"" {
    assert count == 41
}";

        var config = new ProjectConfig { TestFramework = "nunit" };
        CompileAndInspect(source, config, assembly =>
        {
            var testType = assembly.GetType("NSharpTests");
            Assert.NotNull(testType);
            GetCustomAttribute(testType!, "NUnit.Framework.TestFixtureAttribute");
            Assert.DoesNotContain(typeof(IDisposable), testType.GetInterfaces());
            Assert.DoesNotContain(typeof(Xunit.IAsyncLifetime), testType.GetInterfaces());

            var setupMethod = testType.GetMethod("Setup", BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(setupMethod);
            GetCustomAttribute(setupMethod!, "NUnit.Framework.SetUpAttribute");
            Assert.Equal(typeof(void), setupMethod.ReturnType);

            var teardownMethod = testType.GetMethod("Teardown", BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(teardownMethod);
            GetCustomAttribute(teardownMethod!, "NUnit.Framework.TearDownAttribute");
            Assert.Equal(typeof(void), teardownMethod.ReturnType);

            var testMethod = testType.GetMethod("ShouldQuery", BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(testMethod);
            GetCustomAttribute(testMethod!, "NUnit.Framework.TestAttribute");

            var countField = testType.GetField("count", BindingFlags.NonPublic | BindingFlags.Instance);
            Assert.NotNull(countField);

            var instance = Activator.CreateInstance(testType);
            Assert.NotNull(instance);

            setupMethod.Invoke(instance, null);
            Assert.Equal(41, Assert.IsType<int>(countField!.GetValue(instance)));

            testMethod.Invoke(instance, null);
            teardownMethod.Invoke(instance, null);
            Assert.Equal(42, Assert.IsType<int>(countField.GetValue(instance)));
            return true;
        });
    }

    [Fact]
    public async Task ILCompiler_EmitsAsyncNUnitSetupMethod()
    {
        var source = @"
setup {
    count := 40
    await Task.CompletedTask
    count += 2
}

test ""should await setup"" {
    assert count == 42
}";

        var config = new ProjectConfig { TestFramework = "nunit" };
        await CompileAndInspect(source, config, async assembly =>
        {
            var testType = assembly.GetType("NSharpTests");
            Assert.NotNull(testType);
            GetCustomAttribute(testType!, "NUnit.Framework.TestFixtureAttribute");

            var setupMethod = testType.GetMethod("Setup", BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(setupMethod);
            GetCustomAttribute(setupMethod!, "NUnit.Framework.SetUpAttribute");
            Assert.Equal(typeof(Task), setupMethod.ReturnType);

            var instance = Activator.CreateInstance(testType);
            Assert.NotNull(instance);

            await InvokeAndAwaitAsyncMethod(instance!, "Setup");
            var countField = testType.GetField("count", BindingFlags.NonPublic | BindingFlags.Instance);
            Assert.NotNull(countField);
            Assert.Equal(42, Assert.IsType<int>(countField!.GetValue(instance)));
            return true;
        });
    }

    [Fact]
    public void ILCompiler_EmitsNUnitTestCaseMetadata()
    {
        var source = @"
func add(a: int, b: int): int {
    return a + b
}

test ""should add"" with (a: int, b: int, expected: int) [
    (1, 2, 3),
    (0, 0, 0)
] {
    assert add(a, b) == expected
}";

        var config = new ProjectConfig { TestFramework = "nunit" };
        CompileAndInspect(source, config, assembly =>
        {
            var testType = assembly.GetType("NSharpTests");
            Assert.NotNull(testType);

            var testMethod = testType!.GetMethod("ShouldAdd", BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(testMethod);

            var testCaseAttributes = testMethod!.GetCustomAttributes(inherit: false)
                .OfType<NUnit.Framework.TestCaseAttribute>()
                .ToList();

            Assert.Equal(2, testCaseAttributes.Count);
            Assert.Equal(new object?[] { 1, 2, 3 }, testCaseAttributes[0].Arguments);
            Assert.Equal(new object?[] { 0, 0, 0 }, testCaseAttributes[1].Arguments);
            return true;
        });
    }

    [Fact]
    public void ILCompiler_EmitsTheoryMetadataForTableDrivenTests()
    {
        var source = @"
func add(a: int, b: int): int {
    return a + b
}

test ""should add"" with (a: int, b: int, expected: int) [
    (1, 2, 3),
    (0, 0, 0)
] {
    assert add(a, b) == expected
}";

        CompileAndInspect(source, assembly =>
        {
            var testType = assembly.GetType("NSharpTests");
            Assert.NotNull(testType);

            var testMethod = testType!.GetMethod("ShouldAdd", BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(testMethod);

            GetCustomAttribute(testMethod!, "Xunit.TheoryAttribute");
            var inlineDataAttributes = testMethod.CustomAttributes
                .Where(attribute => attribute.AttributeType.FullName == "Xunit.InlineDataAttribute")
                .ToList();

            Assert.Equal(2, inlineDataAttributes.Count);
            Assert.Equal(new object?[] { new object?[] { 1, 2, 3 } }, GetAttributeArguments(inlineDataAttributes[0]));
            Assert.Equal(new object?[] { new object?[] { 0, 0, 0 } }, GetAttributeArguments(inlineDataAttributes[1]));

            var instance = Activator.CreateInstance(testType);
            Assert.NotNull(instance);

            testMethod.Invoke(instance, new object[] { 1, 2, 3 });
            testMethod.Invoke(instance, new object[] { 0, 0, 0 });
            return true;
        });
    }

    [Fact]
    public void ILCompiler_EmitsTheoryParameterAttributesForTableDrivenTests()
    {
        var source = @"
import NSharpLang.Tests

func add(a: int, b: int): int {
    return a + b
}

test ""should add annotated values"" with ([RuntimeCoverage(7, [""xunit""], Enabled: true)] a: int, b: int, expected: int) [
    (1, 2, 3)
] {
    assert add(a, b) == expected
}";

        CompileAndInspect(source, assembly =>
        {
            var testType = assembly.GetType("NSharpTests");
            Assert.NotNull(testType);

            var testMethod = testType!.GetMethod("ShouldAddAnnotatedValues", BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(testMethod);
            GetCustomAttribute(testMethod!, "Xunit.TheoryAttribute");

            var attribute = Assert.Single(testMethod!.GetParameters()[0].CustomAttributes
                .Where(customAttribute => customAttribute.AttributeType.FullName == "NSharpLang.Tests.RuntimeCoverageAttribute"));
            Assert.Equal(new object?[] { 7, new object?[] { "xunit" } }, GetAttributeArguments(attribute));
            Assert.True(Assert.IsType<bool>(GetNamedAttributeValue(attribute, "Enabled")));
            return true;
        });
    }

    [Fact]
    public void ILCompiler_EmitsSkipMetadataForSkippedTests()
    {
        var source = @"
test ""needs network"" skip ""no network in CI"" {
    assert true
}";

        CompileAndInspect(source, assembly =>
        {
            var testType = assembly.GetType("NSharpTests");
            Assert.NotNull(testType);

            var testMethod = testType!.GetMethod("NeedsNetwork", BindingFlags.Public | BindingFlags.Instance);
            Assert.NotNull(testMethod);

            var factAttribute = GetCustomAttribute(testMethod!, "Xunit.FactAttribute");
            Assert.Equal("no network in CI", Assert.IsType<string>(GetNamedAttributeValue(factAttribute, "Skip")));
            return true;
        });
    }

    [Fact]
    public void ILCompiler_CanExecuteGenericClassWithPrimaryConstructor()
    {
        var source = @"
class Box<T>(value: T) {
    func Get(): T {
        return value
    }
}

func main(): int {
    box := new Box<int>(42)
    return box.Get()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteGenericInterfaceImplementation()
    {
        var source = @"
interface Producer<T> {
    func Produce(): T
}

class IntProducer: Producer<int> {
    func Produce(): int {
        return 42
    }
}

func main(): int {
    producer := new IntProducer()
    return producer.Produce()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanInspectGenericStructAndRecordDefinitions()
    {
        var source = @"
struct Wrapper<T> {
    Value: T
}

record Pair<T>(left: T, right: T)

func main() { }";

        CompileAndInspect(source, assembly =>
        {
            var wrapperType = assembly.GetTypes().FirstOrDefault(type => type.Name.StartsWith("Wrapper", StringComparison.Ordinal));
            Assert.NotNull(wrapperType);
            Assert.True(wrapperType!.IsGenericTypeDefinition);

            var pairType = assembly.GetTypes().FirstOrDefault(type => type.Name.StartsWith("Pair", StringComparison.Ordinal));
            Assert.NotNull(pairType);
            Assert.True(pairType!.IsGenericTypeDefinition);
            return true;
        });
    }

    [Fact]
    public void ILCompiler_IgnoresDirectiveAndImportStatementNodes()
    {
        var compilationUnit = new CompilationUnit(
            Namespace: null,
            Imports: new List<ImportDirective>(),
            FileImports: new List<Statement>(),
            Package: null,
            Declarations: new List<Declaration>
            {
                new FunctionDeclaration(
                    Name: "main",
                    Parameters: new List<Parameter>(),
                    ReturnType: new SimpleTypeReference("int"),
                    Body: new BlockStatement(
                        new List<Statement>
                        {
                            new PreprocessorDirective("#region Test", 1, 1),
                            new NamespaceImport("System", null, 2, 1),
                            new FileImport("./other.nl", null, 3, 1),
                            new ReturnStatement(new IntLiteralExpression("42", 4, 1), 4, 1)
                        },
                        1,
                        1),
                    ExpressionBody: null,
                    TypeParameters: null,
                    Constraints: null,
                    Modifiers: Modifiers.None,
                    Attributes: new List<AttributeNode>(),
                    IsOperatorOverload: false,
                    OperatorSymbol: null,
                    IsConversionOperator: false,
                    IsImplicitConversion: false,
                    Line: 1,
                    Column: 1)
            },
            Line: 1,
            Column: 1);

        var result = CompileAndInvoke(compilationUnit);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteNestedPropertyPattern()
    {
        var source = @"
class Address {
    City: string
}

class Person {
    Address: Address
}

func main(): string {
    person := new Person {
        Address: new Address {
            City: ""NYC""
        }
    }

    return match person {
        { Address: { City: ""NYC"" } } => ""New Yorker"",
        _ => ""Other""
    }
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("New Yorker", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteNestedPropertyPatternWithBinding()
    {
        var source = @"
class Address {
    City: string
    State: string
}

class Person {
    Address: Address
}

func main(): string {
    person := new Person {
        Address: new Address {
            City: ""NYC"",
            State: ""NY""
        }
    }

    return match person {
        { Address: { City: city, State: ""NY"" } } => city,
        _ => ""Other""
    }
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("NYC", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteUnionCaseWithNestedPropertyPattern()
    {
        var source = @"
union Result {
    Success { value: Data }
    Failure
}

class Data {
    Count: int
}

func main(): int {
    result := new Result.Success {
        value: new Data {
            Count: 42
        }
    }

    return match result {
        Result.Success { value: { Count: count } } => count,
        _ => 0
    }
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteDeconstructBasedPositionalPattern()
    {
        var source = @"
class Point {
    X: int
    Y: int

    func Deconstruct(out x: int, out y: int) {
        x = X
        y = Y
    }
}

func main(x: int, y: int): string {
    point := new Point { X: x, Y: y }
    return match point {
        (0, 0) => ""origin"",
        (0, _) => ""y-axis"",
        _ => ""other""
    }
}";

        var origin = CompileAndInvoke(source, "main", 0, 0);
        Assert.Equal("origin", Assert.IsType<string>(origin));

        var yAxis = CompileAndInvoke(source, "main", 0, 7);
        Assert.Equal("y-axis", Assert.IsType<string>(yAxis));

        var other = CompileAndInvoke(source, "main", 3, 4);
        Assert.Equal("other", Assert.IsType<string>(other));
    }

    [Fact]
    public void ILCompiler_CanExecuteTopLevelFunctionOverloads()
    {
        var source = @"
func helper(value: int): int {
    return value
}

func helper(value: int, extra: int): int {
    return value + extra * 10
}

func helper(value: int, extra: int, third: int): int {
    return value + extra * 10 + third * 100
}

func main(): int {
    return helper(1) + helper(2, 3) + helper(4, 5, 6)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(687, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteInstanceMethodOverloads()
    {
        var source = @"
class Processor {
    func process(value: int): int {
        return value + 1
    }

    func process(value: string): int {
        return value.Length + 10
    }
}

func main(): int {
    processor := new Processor()
    return processor.process(5) + processor.process(""abc"")
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(19, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteOverloadedConstructors()
    {
        var source = @"
class Box {
    Value: int

    constructor(value: int) {
        Value = value
    }

    constructor(first: int, second: int) {
        Value = first + second * 10
    }
}

func main(): int {
    one := new Box(4)
    two := new Box(5, 6)
    return one.Value + two.Value
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(69, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteExtensionMethodCalls()
    {
        var source = @"
func scale(this value: int, factor: int): int {
    return value * factor
}

func main(): int {
    return 7.scale(3)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(21, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanBindNamedAndDefaultArguments()
    {
        var source = @"
func score(a: int, b: int = 5, c: int = 7): int {
    return a * 100 + b * 10 + c
}

func main(): int {
    return score(c: 9, a: 1)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(159, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExpandParamsArguments()
    {
        var source = @"
func sum(params numbers: int[]): int {
    total := 0
    for number in numbers {
        total += number
    }

    return total
}

func main(): int {
    return sum(1, 2, 3, 4)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(10, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExpandParamsReadOnlySpanArguments()
    {
        var source = @"
func sum(params numbers: ReadOnlySpan<int>): int {
    return ILCompilerParamsHelpers.SumReadOnlySpan(numbers)
}

func main(): int {
    return sum(1, 2, 3)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(6, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExpandParamsSpanArguments()
    {
        var source = @"
func sum(params numbers: Span<int>): int {
    return ILCompilerParamsHelpers.MutateAndSumSpan(numbers)
}

func main(): int {
    return sum(1, 2, 3)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(9, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExpandParamsEnumerableArguments()
    {
        var source = @"
import System.Collections.Generic

func sum(params numbers: IEnumerable<int>): int {
    return ILCompilerParamsHelpers.SumEnumerable(numbers)
}

func main(): int {
    return sum(1, 2, 3, 4)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(10, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExpandParamsListArguments()
    {
        var source = @"
import System.Collections.Generic

func describe(params values: List<string>): int {
    return ILCompilerParamsHelpers.DescribeList(values)
}

func main(): int {
    return describe(""ab"", ""cde"")
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(25, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExpandParamsReadOnlyListArguments()
    {
        var source = @"
import System.Collections.Generic

func sum(params numbers: IReadOnlyList<int>): int {
    return ILCompilerParamsHelpers.SumReadOnlyList(numbers)
}

func main(): int {
    return sum(4, 5, 6)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(315, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteExplicitGenericFunctionCalls()
    {
        var source = @"
func identity<T>(value: T): T {
    return value
}

func main(): int {
    return identity<int>(42)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanInferGenericFunctionCalls()
    {
        var source = @"
func identity<T>(value: T): T {
    return value
}

func main(): int {
    return identity(42)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanInferGenericExtensionMethodCalls()
    {
        var source = @"
func identity<T>(this value: T): T {
    return value
}

func main(): int {
    return 42.identity()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_PrefersNonGenericOverGenericOverloads()
    {
        var source = @"
func convert(value: int): int {
    return value + 1
}

func convert<T>(value: T): int {
    return 100
}

func main(): int {
    return convert(41)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanResolveClrOverloadSpecificity()
    {
        var source = @"
func main(): int {
    return ILCompilerCallHelpers.Pick(""hello"")
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(2, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanBindClrNamedAndOptionalArguments()
    {
        var source = @"
func main(): int {
    return ILCompilerCallHelpers.Format(c: 5, a: 1)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(125, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExpandClrParamsArguments()
    {
        var source = @"
func main(): int {
    return ILCompilerCallHelpers.Sum(1, 2, 3, 4)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(10, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanInferClrGenericMethodCalls()
    {
        var source = @"
func main(): int {
    return ILCompilerCallHelpers.Identity(42)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteExplicitClrGenericMethodCalls()
    {
        var source = @"
func main(): int {
    return ILCompilerCallHelpers.Identity<int>(42)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanEmitClrLongOptionalDefaults()
    {
        var source = @"
func main(): long {
    return ILCompilerCallHelpers.AddLong(37)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(42L, Assert.IsType<long>(result));
    }

    [Fact]
    public void ILCompiler_CanEmitClrEnumOptionalDefaults()
    {
        var source = @"
func main(): int {
    return ILCompilerCallHelpers.ModeValue()
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(7, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteUserDefinedBinaryOperatorOverloads()
    {
        var source = @"
class Vector {
    X: int
    Y: int

    static func operator +(a: Vector, b: Vector): Vector {
        return new Vector { X: a.X + b.X, Y: a.Y + b.Y }
    }
}

func main(): int {
    left := new Vector { X: 2, Y: 3 }
    right := new Vector { X: 5, Y: 7 }
    sum := left + right
    return sum.X * 100 + sum.Y
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(710, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteUserDefinedComparisonOperators()
    {
        var source = @"
class Money {
    Amount: int

    static func operator ==(a: Money, b: Money): bool {
        return a.Amount == b.Amount
    }

    static func operator !=(a: Money, b: Money): bool {
        return a.Amount != b.Amount
    }
}

func main(): int {
    a := new Money { Amount: 42 }
    b := new Money { Amount: 42 }
    c := new Money { Amount: 99 }

    if a == b && a != c {
        return 1
    }

    return 0
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(1, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteImplicitNumericConversions()
    {
        var source = @"
func addOne(value: double): double {
    return value + 1.0
}

func main(): double {
    value: double = 41
    return addOne(41) + value + 1.0
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(84.0, Assert.IsType<double>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteExplicitNumericCasts()
    {
        var source = @"
func main(): int {
    whole := (int)3.9
    widened := (double)2
    return whole + (int)widened
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(5, Assert.IsType<int>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteImplicitUserDefinedConversions()
    {
        var source = @"
class Celsius {
    Value: double

    implicit operator Fahrenheit(c: Celsius) {
        return new Fahrenheit { Value: c.Value * 9.0 / 5.0 + 32.0 }
    }
}

class Fahrenheit {
    Value: double
}

func main(): double {
    c := new Celsius { Value: 100.0 }
    f: Fahrenheit = c
    return f.Value
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(212.0, Assert.IsType<double>(result));
    }

    [Fact]
    public void ILCompiler_CanExecuteExplicitUserDefinedConversions()
    {
        var source = @"
struct Fraction {
    Value: double

    explicit operator double(f: Fraction) {
        return f.Value
    }
}

func main(): double {
    value := (double)new Fraction { Value: 0.75 }
    return value
}";

        var result = CompileAndInvoke(source);
        Assert.Equal(0.75, Assert.IsType<double>(result));
    }

    [Fact]
    public void ILCompiler_EmitsFileScopedTypeVisibility()
    {
        var source = @"
file class InternalHelper {
}

file struct Point {
    X: int
}

file record Person {
    Name: string
}

file interface IHelper {
    func Run(): void
}

file enum Status {
    Active,
    Inactive
}

file union Result {
    Success { value: int }
    Failure { error: string }
}
";

        CompileAndInspect(source, assembly =>
        {
            foreach (var typeName in new[] { "InternalHelper", "Point", "Person", "IHelper", "Status", "Result" })
            {
                var type = assembly.GetType(typeName);
                Assert.NotNull(type);
                Assert.False(type!.IsPublic);
            }

            return true;
        });
    }

    [Fact]
    public void ILCompiler_CanUseAnonymousUnionParametersAndMatch()
    {
        var source = @"
func Describe(value: int | string): string {
    return match value {
        int number => number.ToString(),
        string text => text
    }
}

func main(): string {
    return Describe(42) + "":"" + Describe(""ready"")
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("42:ready", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanUseAnonymousUnionWithGeneratedTypeArm()
    {
        var source = @"
class PrebakedGreeting {
    Text: string
}

func Hi(greeting: PrebakedGreeting | string): string {
    if greeting is string text {
        return text
    }

    return match greeting {
        PrebakedGreeting prebaked => prebaked.Text,
        string text => text
    }
}

func main(): string {
    return Hi(""hello"") + "":"" + Hi(new PrebakedGreeting { Text: ""ready"" })
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("hello:ready", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanReturnAndCastAnonymousUnionValues()
    {
        var source = @"
func Choose(flag: bool): int | string {
    if flag {
        return 42
    }

    return ""fallback""
}

func main(): string {
    value := Choose(false)
    text := (string)value
    if value is string narrowed {
        return text + "":"" + narrowed
    }

    return ""missing""
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("fallback:fallback", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_CanStoreAnonymousUnionInFieldsAndProperties()
    {
        var source = @"
class Holder {
    Value: int | string
    Current: int | string => Value
}

func main(): string {
    holder := new Holder { Value: ""field"" }
    return (holder.Value as string) + "":"" + (holder.Current as string)
}";

        var result = CompileAndInvoke(source);
        Assert.Equal("field:field", Assert.IsType<string>(result));
    }

    [Fact]
    public void ILCompiler_EmitsPublicOverloadShimsForAnonymousUnionParameters()
    {
        var source = @"
func Describe(value: int | string): string {
    return match value {
        int number => number.ToString(),
        string text => text
    }
}";

        CompileAndInspect(source, assembly =>
        {
            var program = assembly.GetType("Program");
            Assert.NotNull(program);

            var overloads = program!.GetMethods(BindingFlags.Public | BindingFlags.Static)
                .Where(method => method.Name == "Describe")
                .ToArray();

            Assert.Contains(overloads, method => method.GetParameters()[0].ParameterType == typeof(int));
            Assert.Contains(overloads, method => method.GetParameters()[0].ParameterType == typeof(string));
            Assert.Contains(overloads, method => method.GetParameters()[0].ParameterType.FullName!.StartsWith("NSharpLang.Runtime.Union`2", StringComparison.Ordinal));

            var intOverload = overloads.Single(method => method.GetParameters()[0].ParameterType == typeof(int));
            var stringOverload = overloads.Single(method => method.GetParameters()[0].ParameterType == typeof(string));

            Assert.Equal("9", intOverload.Invoke(null, new object[] { 9 }));
            Assert.Equal("ok", stringOverload.Invoke(null, new object[] { "ok" }));

            return true;
        });
    }

    [Fact]
    public void ILCompiler_GenericInterfaceConstraint_DispatchesValueTypeWithoutBoxing()
    {
        var source = @"
interface IShape {
    func Area(): int
}

struct Square : IShape {
    side: int

    func Area(): int {
        return side * side
    }
}

func areaOf<T>(shape: T): int where T : IShape {
    return shape.Area()
}

func main(): int {
    sq := new Square { side: 6 }
    return areaOf(sq)
}";

        // IL shape: dispatch through the generic constraint must use a
        // `constrained.` prefix on the value-type receiver and must NOT box it.
        var opCodes = CompileAndInspect(source, assembly =>
        {
            var program = assembly.GetType("Program")!;
            var areaOf = program.GetMethod("areaOf", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(areaOf);
            return GetMethodOpCodes(areaOf!).Select(opCode => opCode.Name).ToArray();
        });

        Assert.Contains("constrained.", opCodes);
        Assert.Contains("callvirt", opCodes);
        Assert.DoesNotContain("box", opCodes);

        // Behavior is unchanged: 6 * 6 == 36.
        Assert.Equal(36, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_GenericDuckInterfaceConstraint_DispatchesValueTypeWithoutBoxing()
    {
        var source = @"
duck interface ICounter {
    func Count(): int
}

struct Bucket {
    size: int

    func Count(): int {
        return size
    }
}

func total<T>(item: T): int where T : ICounter {
    return item.Count()
}

func main(): int {
    bucket := new Bucket { size: 9 }
    return total(bucket)
}";

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var program = assembly.GetType("Program")!;
            var total = program.GetMethod("total", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(total);
            return GetMethodOpCodes(total!).Select(opCode => opCode.Name).ToArray();
        });

        Assert.Contains("constrained.", opCodes);
        Assert.Contains("callvirt", opCodes);
        Assert.DoesNotContain("box", opCodes);

        Assert.Equal(9, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_GenericConstraintViaBaseInterface_DispatchesValueTypeWithoutBoxing()
    {
        // The called method (Area) is declared on a *base* interface of the named
        // constraint. Constrained dispatch must walk the constraint's interface
        // hierarchy, still emit a `constrained.` prefix on the value-type receiver,
        // and never box it.
        var source = @"
interface HasArea {
    func Area(): int
}

interface Shape : HasArea {
    func Name(): string
}

struct Square : Shape {
    side: int

    func Area(): int {
        return side * side
    }

    func Name(): string {
        return ""square""
    }
}

func totalArea<T>(s: T): int where T : Shape {
    return s.Area()
}

func main(): int {
    sq := new Square { side: 3 }
    return totalArea(sq)
}";

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var program = assembly.GetType("Program")!;
            var totalArea = program.GetMethod("totalArea", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(totalArea);
            return GetMethodOpCodes(totalArea!).Select(opCode => opCode.Name).ToArray();
        });

        Assert.Contains("constrained.", opCodes);
        Assert.Contains("callvirt", opCodes);
        Assert.DoesNotContain("box", opCodes);

        // 3 * 3 == 9, dispatched through the inherited interface method.
        Assert.Equal(9, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_GenericConstraintWithMethodArgument_DispatchesValueTypeWithoutBoxing()
    {
        // A constrained interface method that takes an argument must still dispatch
        // through `constrained.` without boxing the value-type receiver.
        var source = @"
interface Shape {
    func Scaled(factor: int): int
}

struct Square : Shape {
    side: int

    func Scaled(factor: int): int {
        return side * side * factor
    }
}

func scaledArea<T>(s: T, factor: int): int where T : Shape {
    return s.Scaled(factor)
}

func main(): int {
    sq := new Square { side: 3 }
    return scaledArea(sq, 2)
}";

        var opCodes = CompileAndInspect(source, assembly =>
        {
            var program = assembly.GetType("Program")!;
            var scaledArea = program.GetMethod("scaledArea", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static);
            Assert.NotNull(scaledArea);
            return GetMethodOpCodes(scaledArea!).Select(opCode => opCode.Name).ToArray();
        });

        Assert.Contains("constrained.", opCodes);
        Assert.Contains("callvirt", opCodes);
        Assert.DoesNotContain("box", opCodes);

        Assert.Equal(18, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_ClosedGenericFieldAccess_ReadStoreAndTypedLocal()
    {
        // B1: `b.item` on a CLOSED generic (Box<int>) failed with "Member item not found on
        // type Box" — reflection member queries throw on TypeBuilderInstantiation, so the
        // member paths must resolve through the OPEN definition's bookkeeping and rebound
        // tokens, and typing must substitute the closed arguments (x is int, not object).
        var source = @"
class Box<T> {
    item: T

    constructor(v: T) {
        item = v
    }
}

func main(): int {
    b := new Box<int>(5)
    x := b.item
    b.item = x + 2
    return b.item
}";
        Assert.Equal(7, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_ClosedGenericPropertyAccess_ResolvesThroughReboundGetter()
    {
        var source = @"
class Box<T> {
    item: T

    constructor(v: T) {
        item = v
    }

    Current: T {
        get { return item }
    }
}

func main(): int {
    b := new Box<int>(41)
    return b.Current + 1
}";
        Assert.Equal(42, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_GenericTypedConstructorParameter_BindsWithSubstitution()
    {
        // B10: a ctor parameter whose type is ANOTHER generic over the same type parameter
        // (`Holder<T>(i: Box<T>)`) failed to bind because the instantiated ctor still reports
        // the OPEN parameter shapes; the binder must substitute the closed type arguments.
        var source = @"
class Box<T> {
    item: T

    constructor(v: T) {
        item = v
    }
}

class Holder<T> {
    inner: Box<T>

    constructor(i: Box<T>) {
        inner = i
    }
}

func main(): int {
    h := new Holder<int>(new Box<int>(9))
    return h.inner.item
}";
        Assert.Equal(9, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_GenericInstanceMethod_OnPlainType_InfersAndAcceptsExplicitArgs()
    {
        // B12a: generic instance methods were never DEFINED with generic parameters
        // (DeclareMethod resolved U to object and MakeGenericMethod threw
        // InvalidOperationException). Both inference and explicit type arguments must bind.
        var source = @"
class Plain {
    func Echo<U>(v: U): U {
        return v
    }
}

func main(): int {
    p := new Plain()
    a := p.Echo(40)
    b := p.Echo<int>(2)
    return a + b
}";
        Assert.Equal(42, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_GenericRecordObjectInit_RefusesWithClearDiagnostic()
    {
        // B4: generic record object-init previously crashed emit with NotSupportedException.
        // A correct emit is BLOCKED upstream: .NET 10 PersistedAssemblyBuilder drops the
        // modreq(IsExternalInit) from member references rebound via TypeBuilder.GetMethod, so
        // the init-setter call fails at RUNTIME with MissingMethodException (reproduced in a
        // minimal Reflection.Emit spike with no N# code involved). Filed upstream as
        // https://github.com/dotnet/runtime/issues/129234 — until it is resolved, the oracle
        // must refuse with a clear compile error instead of emitting garbage.
        var source = @"
record Pair<T> {
    First: T
    Second: T
}

func main(): int {
    p := new Pair<int> { First: 1, Second: 2 }
    return p.First + p.Second
}";
        var exception = Assert.Throws<InvalidOperationException>(() => CompileAndInvoke(source));
        Assert.Contains("init-only member 'First'", exception.Message);
        Assert.Contains("generic type 'Pair'", exception.Message);
    }

    [Fact]
    public void ILCompiler_ClosedGenericObjectInit_AutoPropertySetter()
    {
        // The closed-generic object-initializer path resolves members through the open
        // definition's bookkeeping with rebound tokens (plain setters carry no modreq and
        // are unaffected by the PersistedAssemblyBuilder issue pinned above).
        var source = @"
class Box<T> {
    Value: T
}

func main(): int {
    b := new Box<int> { Value: 5 }
    return b.Value
}";
        Assert.Equal(5, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_GenericStruct_CtorAndFieldAccess()
    {
        // B5 pin: generic structs failed emit before the closed-generic member-resolution
        // fixes; covered by the same rebinding machinery as classes.
        var source = @"
struct Cell<T> {
    value: T

    constructor(v: T) {
        value = v
    }
}

func main(): int {
    c := new Cell<int>(3)
    return c.value
}";
        Assert.Equal(3, Assert.IsType<int>(CompileAndInvoke(source)));
    }

    [Fact]
    public void ILCompiler_GenericInstanceMethod_OnGenericType_ValueAndReferenceTypeArgs()
    {
        // B12b: `Box<int>.Pair<U>` must rebind onto the closed type BEFORE MakeGenericMethod,
        // and the method body's generic context must include the METHOD's own type parameters
        // — without that, interpolating a U-typed value parameter emitted IL that only
        // verified for reference-type instantiations (bool crashed with InvalidProgram).
        var source = @"
class Box<T> {
    item: T

    constructor(v: T) {
        item = v
    }

    func Pair<U>(other: U): string {
        return $""{item}|{other}""
    }
}

func main(): string {
    b := new Box<int>(5)
    r := b.Pair(""x"")
    v := b.Pair<bool>(true)
    return $""{r};{v}""
}";
        Assert.Equal("5|x;5|True", Assert.IsType<string>(CompileAndInvoke(source)));
    }
}
