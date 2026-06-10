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

// Shared compile/invoke/inspect scaffolding for the ILCompiler test classes. These used to be one
// `partial class ILCompilerTests` spread across six files — a single xUnit collection whose ~25s
// serial chain was the suite's longest pole after the toolchain split. Each file (and each half of
// the big one) is now its own class deriving from this base, so the collections run in parallel.
public abstract class ILCompilerTestBase
{
    protected static AssemblyLoadContext CreateTestLoadContext()
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

    protected CompilationUnit Parse(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        var result = parser.ParseCompilationUnit();
        return result.CompilationUnit!; // Tests expect valid syntax
    }

    protected object? CompileAndInvoke(string source, string functionName = "main", params object[] args)
    {
        var compilationUnit = Parse(source);
        return CompileAndInvoke(compilationUnit, functionName, args);
    }

    protected object? CompileAndInvoke(string source, ProjectConfig config, string functionName = "main", params object[] args)
    {
        var compilationUnit = Parse(source);
        return CompileAndInvoke(compilationUnit, config, functionName, args);
    }

    protected object? CompileAndInvoke(CompilationUnit compilationUnit, string functionName = "main", params object[] args)
    {
        return CompileAndInvoke(compilationUnit, null, functionName, args);
    }

    protected object? CompileAndInvoke(CompilationUnit compilationUnit, ProjectConfig? config, string functionName = "main", params object[] args)
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

    protected async Task<object?> CompileAndInvokeTaskResult(string source, string functionName = "main", params object[] args)
    {
        var result = CompileAndInvoke(source, functionName, args);
        var task = Assert.IsAssignableFrom<Task>(result);
        await task;

        var resultProperty = task.GetType().GetProperty("Result", BindingFlags.Public | BindingFlags.Instance);
        return resultProperty?.GetValue(task);
    }

    protected T CompileAndInspect<T>(string source, Func<Assembly, T> inspector)
    {
        return CompileAndInspect(source, null, inspector);
    }

    protected T CompileAndInspect<T>(string source, ProjectConfig? config, Func<Assembly, T> inspector)
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

    protected static IReadOnlyList<byte> GetNullableAttributeFlags(IEnumerable<CustomAttributeData> attributes)
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

    protected static async Task AwaitTaskLikeResult(object? result)
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

    protected static async Task InvokeAndAwaitAsyncMethod(object instance, string methodName)
    {
        var method = instance.GetType().GetMethod(methodName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance);
        Assert.NotNull(method);
        await AwaitTaskLikeResult(method!.Invoke(instance, null));
    }

    protected static CustomAttributeData GetCustomAttribute(MemberInfo member, string fullName)
    {
        return Assert.Single(member.CustomAttributes.Where(attribute => attribute.AttributeType.FullName == fullName));
    }

    protected static object? GetNamedAttributeValue(CustomAttributeData attribute, string memberName)
    {
        return Assert.Single(attribute.NamedArguments.Where(argument => argument.MemberName == memberName)).TypedValue.Value;
    }

    protected static object?[] GetAttributeArguments(CustomAttributeData attribute)
    {
        return attribute.ConstructorArguments.Select(UnwrapAttributeValue).ToArray();
    }

    protected static object? UnwrapAttributeValue(CustomAttributeTypedArgument argument)
    {
        if (argument.Value is IReadOnlyCollection<CustomAttributeTypedArgument> collection)
        {
            return collection.Select(UnwrapAttributeValue).ToArray();
        }

        return argument.Value;
    }

    protected static IReadOnlyList<OpCode> GetMethodOpCodes(MethodInfo method)
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

    protected static readonly OpCode[] SingleByteOpCodes = new OpCode[0x100];
    protected static readonly OpCode[] MultiByteOpCodes = new OpCode[0x100];

    static ILCompilerTestBase()
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

    protected static int GetOperandSize(OperandType operandType, byte[] il, int offset) => operandType switch
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

    protected static FieldInfo? GetDelegateCacheField(Type programType)
    {
        return programType
            .GetFields(BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic)
            .FirstOrDefault(field => field.Name.StartsWith("<>c__DelegateCache", StringComparison.Ordinal));
    }

    protected static void AssertDelegateCreationIsCacheGuarded(MethodInfo method)
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
}
