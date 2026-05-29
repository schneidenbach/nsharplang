using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.Loader;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using Xunit;

namespace NSharpLang.Tests.PerfEvidence;

/// <summary>
/// A single decoded IL instruction: its <see cref="OpCode"/> together with the byte
/// offset at which it begins and the metadata token operand (when the operand type is
/// a method, field, type, or signature token).
/// </summary>
public readonly struct ILInstruction
{
    public ILInstruction(int offset, OpCode opCode, int? metadataToken)
    {
        Offset = offset;
        OpCode = opCode;
        MetadataToken = metadataToken;
    }

    /// <summary>Byte offset of the opcode within the method body.</summary>
    public int Offset { get; }

    /// <summary>The decoded opcode.</summary>
    public OpCode OpCode { get; }

    /// <summary>
    /// The 4-byte metadata token operand, when present. Only populated for opcodes whose
    /// operand is an inline method/field/type/token/signature reference.
    /// </summary>
    public int? MetadataToken { get; }

    public override string ToString() =>
        MetadataToken is { } token ? $"IL_{Offset:x4}: {OpCode.Name} (0x{token:x8})" : $"IL_{Offset:x4}: {OpCode.Name}";
}

/// <summary>
/// Reusable IL-shape inspection helper for compiler performance tests. It compiles a small
/// N# program through the same pipeline as <see cref="ILCompilerTests"/>, loads the resulting
/// assembly into a collectible <see cref="AssemblyLoadContext"/>, and decodes method bodies so
/// tests can pin and assert on the emitted IL shape (boxing, virtual dispatch, display classes,
/// delegate allocations, and so on).
///
/// The decoder is self-contained: it walks the raw byte array returned by
/// <see cref="MethodBody.GetILAsByteArray"/> against <see cref="OpCodes"/> with no external
/// dependencies.
/// </summary>
public static class ILShapeInspector
{
    private static readonly OpCode[] SingleByteOpCodes = new OpCode[0x100];
    private static readonly OpCode[] MultiByteOpCodes = new OpCode[0x100];

    static ILShapeInspector()
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

    // ==================== Compilation ====================

    /// <summary>
    /// Compiles N# <paramref name="source"/> to an in-memory assembly, hands it to
    /// <paramref name="inspector"/>, and unloads the assembly afterwards. Mirrors the pipeline
    /// used by the existing <see cref="ILCompilerTests"/> harness.
    /// </summary>
    public static T Compile<T>(string source, Func<Assembly, T> inspector)
    {
        var outputPath = Path.Combine(Path.GetTempPath(), $"ILShapeInspector_{Guid.NewGuid():N}.dll");
        var assemblyName = $"ILShapeInspector_{Guid.NewGuid():N}";
        AssemblyLoadContext? loadContext = null;

        try
        {
            var compilationUnit = ParseOrThrow(source);
            var compiler = new Compiler.ILCompiler.ILCompiler(compilationUnit, assemblyName, outputPath);
            compiler.Compile();

            var assemblyBytes = File.ReadAllBytes(outputPath);
            loadContext = CreateLoadContext();
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

    /// <summary>
    /// Compiles N# <paramref name="source"/> and returns the decoded IL of the named static method
    /// on the <c>Program</c> type. Convenience wrapper around <see cref="Compile{T}"/> for the common
    /// "inspect a top-level function" case.
    /// </summary>
    public static IReadOnlyList<ILInstruction> DecodeProgramMethod(string source, string methodName = "main")
    {
        return Compile(source, assembly =>
        {
            var method = GetProgramMethod(assembly, methodName);
            return Decode(method);
        });
    }

    private static CompilationUnit ParseOrThrow(string source)
    {
        var lexer = new Lexer(source, "test.nl");
        var tokens = lexer.Tokenize();
        var parser = new Parser(tokens, "test.nl");
        var result = parser.ParseCompilationUnit();
        if (result.CompilationUnit is null)
        {
            throw new InvalidOperationException("N# source failed to parse for IL-shape inspection.");
        }

        return result.CompilationUnit;
    }

    private static AssemblyLoadContext CreateLoadContext()
    {
        var loadContext = new AssemblyLoadContext($"ILShapeInspector_{Guid.NewGuid():N}", isCollectible: true);
        var runtimeAssembly = typeof(NSharpLang.Runtime.Union<,>).Assembly;
        var runtimeAssemblyName = runtimeAssembly.GetName().Name;

        loadContext.Resolving += (_, assemblyName) =>
            string.Equals(assemblyName.Name, runtimeAssemblyName, StringComparison.Ordinal) ? runtimeAssembly : null;

        return loadContext;
    }

    /// <summary>Gets a static method (public or not) on the <c>Program</c> type of <paramref name="assembly"/>.</summary>
    public static MethodInfo GetProgramMethod(Assembly assembly, string methodName)
    {
        var programType = assembly.GetType("Program");
        Assert.NotNull(programType);

        var method = programType!.GetMethod(
            methodName,
            BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance);
        Assert.NotNull(method);
        return method!;
    }

    // ==================== Decoding ====================

    /// <summary>
    /// Decodes the IL byte stream of <paramref name="method"/> into a list of
    /// <see cref="ILInstruction"/>. Handles both single-byte opcodes and the two-byte
    /// (<c>0xFE</c>-prefixed) opcodes, and advances past each operand using its declared size.
    /// </summary>
    public static IReadOnlyList<ILInstruction> Decode(MethodBase method)
    {
        var body = method.GetMethodBody();
        var il = body?.GetILAsByteArray() ?? Array.Empty<byte>();
        return Decode(il);
    }

    /// <summary>Decodes a raw IL byte array into a list of <see cref="ILInstruction"/>.</summary>
    public static IReadOnlyList<ILInstruction> Decode(byte[] il)
    {
        var instructions = new List<ILInstruction>();

        for (var offset = 0; offset < il.Length;)
        {
            var instructionOffset = offset;
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

            int? token = TakesMetadataToken(opCode.OperandType) ? BitConverter.ToInt32(il, offset) : null;

            instructions.Add(new ILInstruction(instructionOffset, opCode, token));
            offset += GetOperandSize(opCode.OperandType, il, offset);
        }

        return instructions;
    }

    private static bool TakesMetadataToken(OperandType operandType) => operandType switch
    {
        OperandType.InlineField
            or OperandType.InlineMethod
            or OperandType.InlineSig
            or OperandType.InlineTok
            or OperandType.InlineType => true,
        _ => false
    };

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

    // ==================== Counting / inspection ====================

    /// <summary>Counts how many times <paramref name="opCode"/> appears in <paramref name="method"/>.</summary>
    public static int CountOpcode(MethodBase method, OpCode opCode) => CountOpcode(Decode(method), opCode);

    /// <summary>Counts how many times <paramref name="opCode"/> appears in a decoded instruction stream.</summary>
    public static int CountOpcode(IReadOnlyList<ILInstruction> instructions, OpCode opCode) =>
        instructions.Count(instruction => instruction.OpCode == opCode);

    /// <summary>Counts <c>box</c> instructions in <paramref name="method"/>.</summary>
    public static int CountBoxing(MethodBase method) => CountOpcode(method, OpCodes.Box);

    /// <summary>Counts <c>newobj</c> instructions in <paramref name="method"/>.</summary>
    public static int CountNewObj(MethodBase method) => CountOpcode(method, OpCodes.Newobj);

    /// <summary>Counts <c>callvirt</c> instructions in <paramref name="method"/>.</summary>
    public static int CountCallVirt(MethodBase method) => CountOpcode(method, OpCodes.Callvirt);

    /// <summary>Counts non-virtual <c>call</c> instructions in <paramref name="method"/>.</summary>
    public static int CountCall(MethodBase method) => CountOpcode(method, OpCodes.Call);

    /// <summary>
    /// Counts <c>newobj</c> instructions whose target constructor belongs to a delegate type
    /// (i.e. delegate allocations). <paramref name="method"/> must be a <see cref="MethodInfo"/>
    /// declared on a runtime type so tokens can be resolved via its module.
    /// </summary>
    public static int CountDelegateConstructions(MethodInfo method)
    {
        var module = method.Module;
        var genericTypeArgs = method.DeclaringType?.GetGenericArguments() ?? Type.EmptyTypes;
        var genericMethodArgs = method.IsGenericMethod ? method.GetGenericArguments() : Type.EmptyTypes;

        var count = 0;
        foreach (var instruction in Decode(method))
        {
            if (instruction.OpCode != OpCodes.Newobj || instruction.MetadataToken is not { } token)
            {
                continue;
            }

            var ctor = ResolveConstructor(module, token, genericTypeArgs, genericMethodArgs);
            if (ctor?.DeclaringType is { } declaringType && typeof(Delegate).IsAssignableFrom(declaringType))
            {
                count++;
            }
        }

        return count;
    }

    private static ConstructorInfo? ResolveConstructor(Module module, int token, Type[] typeArgs, Type[] methodArgs)
    {
        try
        {
            return module.ResolveMethod(token, typeArgs, methodArgs) as ConstructorInfo;
        }
        catch (ArgumentException)
        {
            // Token may reference a member of another module / unresolvable in this context.
            return null;
        }
    }

    /// <summary>
    /// Returns the compiler-generated closure / display-class types in <paramref name="assembly"/>.
    /// Detects both the cached-singleton container (<c>&lt;&gt;c</c>) and per-scope display classes
    /// (<c>&lt;&gt;c__DisplayClass...</c>), whether emitted as top-level or nested types.
    /// </summary>
    public static IReadOnlyList<Type> FindDisplayClasses(Assembly assembly) =>
        EnumerateAllTypes(assembly).Where(IsDisplayClass).ToArray();

    /// <summary>Returns the nested compiler-generated display-class types declared inside <paramref name="type"/>.</summary>
    public static IReadOnlyList<Type> FindDisplayClasses(Type type) =>
        EnumerateTypeAndNested(type).Where(candidate => candidate != type && IsDisplayClass(candidate)).ToArray();

    /// <summary>
    /// Returns <c>true</c> when <paramref name="type"/> is a compiler-generated closure container,
    /// recognised by the Roslyn-style naming convention (<c>&lt;&gt;c</c> or <c>&lt;&gt;c__DisplayClass...</c>).
    /// </summary>
    public static bool IsDisplayClass(Type type)
    {
        var name = type.Name;
        return name == "<>c"
            || name.StartsWith("<>c__DisplayClass", StringComparison.Ordinal)
            || name.StartsWith("<>c__", StringComparison.Ordinal);
    }

    private static IEnumerable<Type> EnumerateAllTypes(Assembly assembly)
    {
        foreach (var type in assembly.GetTypes())
        {
            foreach (var nested in EnumerateTypeAndNested(type))
            {
                yield return nested;
            }
        }
    }

    private static IEnumerable<Type> EnumerateTypeAndNested(Type type)
    {
        yield return type;
        foreach (var nested in type.GetNestedTypes(BindingFlags.Public | BindingFlags.NonPublic))
        {
            foreach (var deeper in EnumerateTypeAndNested(nested))
            {
                yield return deeper;
            }
        }
    }

    // ==================== Assertions ====================

    /// <summary>Asserts that <paramref name="method"/> emits no <c>box</c> instructions.</summary>
    public static void AssertNoBoxing(MethodBase method)
    {
        var boxCount = CountBoxing(method);
        Assert.True(
            boxCount == 0,
            $"Expected no boxing in '{Describe(method)}' but found {boxCount} box instruction(s).");
    }

    /// <summary>Asserts that <paramref name="type"/> declares no compiler-generated display classes.</summary>
    public static void AssertNoDisplayClass(Type type)
    {
        var displayClasses = FindDisplayClasses(type);
        Assert.True(
            displayClasses.Count == 0,
            $"Expected no display classes on '{type.FullName}' but found: {DescribeTypes(displayClasses)}.");
    }

    /// <summary>Asserts that <paramref name="assembly"/> emits no compiler-generated display classes.</summary>
    public static void AssertNoDisplayClass(Assembly assembly)
    {
        var displayClasses = FindDisplayClasses(assembly);
        Assert.True(
            displayClasses.Count == 0,
            $"Expected no display classes in assembly but found: {DescribeTypes(displayClasses)}.");
    }

    /// <summary>Asserts that <paramref name="method"/> emits <paramref name="expected"/> instances of <paramref name="opCode"/>.</summary>
    public static void AssertCallCount(MethodBase method, OpCode opCode, int expected)
    {
        var actual = CountOpcode(method, opCode);
        Assert.True(
            actual == expected,
            $"Expected {expected} '{opCode.Name}' instruction(s) in '{Describe(method)}' but found {actual}.");
    }

    private static string Describe(MethodBase method) =>
        $"{method.DeclaringType?.FullName}.{method.Name}";

    private static string DescribeTypes(IReadOnlyList<Type> types) =>
        types.Count == 0 ? "(none)" : string.Join(", ", types.Select(type => type.FullName));
}
