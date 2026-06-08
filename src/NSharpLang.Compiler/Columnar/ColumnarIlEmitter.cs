using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Reflection.Emit;

namespace NSharpLang.Compiler.Columnar;

/// <summary>
/// COLUMNAR PIPELINE — stage 4 SPIKE (docs/design/roadmap-to-done.md). Proof that the columnar node tables can
/// drive IL emission END-TO-END with no C# AST: for a single trivial function it emits a real .NET assembly
/// (one static method) whose body IL is generated DIRECTLY from the columnar statement/expression tables, then
/// returns the assembly bytes so a caller can load + invoke it. This is the de-risking spike for Stage 4 — the
/// emit primitives (<c>ldarg</c> / <c>ldc.i4</c> / arithmetic / <c>ret</c>) are exactly what the full columnar
/// codegen will emit; later slices grow the supported surface and route through <c>ILCompiler</c> proper.
///
/// Deliberately narrow: top-level <c>func</c> with INT params/return only (mixed-type arithmetic would need
/// conversions this spike does not emit), a body that is a Block of a single Return, whose value is a
/// parameter, an int literal, a parenthesized expr, or an int +/-/* binary of those. Anything else returns
/// false (the adapter declines → the C# path is unaffected).
/// </summary>
public sealed class ColumnarIlEmitter
{
    private readonly int[] _kinds;
    private readonly int[] _valueStarts;
    private readonly int[] _valueLengths;
    private readonly int[] _childStart;
    private readonly int[] _childCount;
    private readonly int[] _childIndices;
    private readonly string _source;
    private readonly Dictionary<string, int> _paramOrdinals;
    private readonly ILGenerator _il;

    private ColumnarIlEmitter(
        int[] kinds, int[] valueStarts, int[] valueLengths,
        int[] childStart, int[] childCount, int[] childIndices, string source,
        Dictionary<string, int> paramOrdinals, ILGenerator il)
    {
        _kinds = kinds;
        _valueStarts = valueStarts;
        _valueLengths = valueLengths;
        _childStart = childStart;
        _childCount = childCount;
        _childIndices = childIndices;
        _source = source;
        _paramOrdinals = paramOrdinals;
        _il = il;
    }

    /// <summary>Canonical N# primitive type name → its CLR <see cref="Type"/>. Non-builtins are unsupported.</summary>
    public static bool TryResolveBuiltin(string canonical, out Type type)
    {
        type = canonical switch
        {
            "int" => typeof(int),
            "long" => typeof(long),
            "uint" => typeof(uint),
            "ulong" => typeof(ulong),
            "short" => typeof(short),
            "ushort" => typeof(ushort),
            "byte" => typeof(byte),
            "sbyte" => typeof(sbyte),
            "bool" => typeof(bool),
            "char" => typeof(char),
            "double" => typeof(double),
            "float" => typeof(float),
            "string" => typeof(string),
            _ => null!,
        };
        return type != null;
    }

    /// <summary>
    /// Build a one-method assembly for <paramref name="funcName"/> whose body IL is emitted from the columnar
    /// tables. Returns false (no assembly) for any unsupported type or body shape. The emitted type is
    /// <c>ColumnarSpike</c> and the method is static.
    /// </summary>
    public static bool TryEmitSingleFunctionAssembly(
        string funcName, string returnCanonical, string[] paramNames, string[] paramCanonicals,
        int[] kinds, int[] valueStarts, int[] valueLengths, int[] childStart, int[] childCount, int[] childIndices,
        string source, int bodyRoot, out byte[] assembly)
    {
        assembly = Array.Empty<byte>();

        // Spike restriction: INT-ONLY. The expression emitter uses untyped integer `add`/`sub`/`mul` and `ldc.i4`,
        // which is only valid when every operand is `int` — a mixed-type binary (e.g. int + long) would emit
        // `add` on (i4, i8) = invalid IL. Resolve via the builtin map (the type-resolution seam later slices
        // reuse), then require `int` throughout; later slices add type-aware emission for the full builtin set.
        if (!TryResolveBuiltin(returnCanonical, out var returnType) || returnType != typeof(int))
            return false;
        var paramTypes = new Type[paramNames.Length];
        var ordinals = new Dictionary<string, int>(StringComparer.Ordinal);
        for (var i = 0; i < paramNames.Length; i++)
        {
            if (!TryResolveBuiltin(paramCanonicals[i], out var pt) || pt != typeof(int))
                return false;
            paramTypes[i] = pt;
            ordinals[paramNames[i]] = i;
        }

        var builder = new PersistedAssemblyBuilder(new AssemblyName("ColumnarSpike"), typeof(object).Assembly);
        var module = builder.DefineDynamicModule("ColumnarSpike");
        var type = module.DefineType("ColumnarSpike", TypeAttributes.Public | TypeAttributes.Class);
        var method = type.DefineMethod(
            funcName, MethodAttributes.Public | MethodAttributes.Static, returnType, paramTypes);
        var il = method.GetILGenerator();

        var emitter = new ColumnarIlEmitter(
            kinds, valueStarts, valueLengths, childStart, childCount, childIndices, source, ordinals, il);
        if (!emitter.EmitStatement(bodyRoot))
            return false;

        type.CreateType();
        using var stream = new MemoryStream();
        builder.Save(stream);
        assembly = stream.ToArray();
        return true;
    }

    private bool EmitStatement(int idx)
    {
        switch (_kinds[idx])
        {
            case 25: // Block — emit each statement in order.
                for (var n = 0; n < _childCount[idx]; n++)
                {
                    if (!EmitStatement(Child(idx, n)))
                        return false;
                }

                return true;

            case 20: // Return [value] — the spike is int-only, so a value is REQUIRED (a value-less `return`
                     // would emit `ret` with an empty stack = invalid IL); decline it.
                if (_childCount[idx] == 0 || !EmitExpression(Child(idx, 0)))
                    return false;
                _il.Emit(OpCodes.Ret);
                return true;

            default: // spike: only a block of returns is supported.
                return false;
        }
    }

    private bool EmitExpression(int idx)
    {
        switch (_kinds[idx])
        {
            case 6: // Identifier — only parameters are supported in the spike.
                if (_paramOrdinals.TryGetValue(Text(idx), out var ordinal))
                {
                    EmitLoadArgument(ordinal);
                    return true;
                }

                return false;

            case 0: // IntLiteral — plain decimal int only.
                if (int.TryParse(Text(idx), out var value))
                {
                    _il.Emit(OpCodes.Ldc_I4, value);
                    return true;
                }

                return false;

            case 7: // Parenthesized — emit the inner expression.
                return EmitExpression(Child(idx, 0));

            case 12: // Binary [left, right] — int +/-/* only.
            {
                if (!EmitExpression(Child(idx, 0)) || !EmitExpression(Child(idx, 1)))
                    return false;
                switch (Text(idx))
                {
                    case "+": _il.Emit(OpCodes.Add); return true;
                    case "-": _il.Emit(OpCodes.Sub); return true;
                    case "*": _il.Emit(OpCodes.Mul); return true;
                    default: return false;
                }
            }

            default:
                return false;
        }
    }

    private void EmitLoadArgument(int index)
    {
        switch (index)
        {
            case 0: _il.Emit(OpCodes.Ldarg_0); break;
            case 1: _il.Emit(OpCodes.Ldarg_1); break;
            case 2: _il.Emit(OpCodes.Ldarg_2); break;
            case 3: _il.Emit(OpCodes.Ldarg_3); break;
            default:
                if (index <= 255)
                    _il.Emit(OpCodes.Ldarg_S, (byte)index);
                else
                    _il.Emit(OpCodes.Ldarg, index);
                break;
        }
    }

    private int Child(int idx, int n) => _childIndices[_childStart[idx] + n];

    private string Text(int idx) => _source.Substring(_valueStarts[idx], _valueLengths[idx]);
}
