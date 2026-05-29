using System;
using System.Reflection;
using System.Reflection.Emit;

namespace NSharpLang.Compiler.Performance;

/// <summary>
/// A coarse, allocation/dispatch-focused summary of a method's IL body. Surfaces the
/// kinds of operations that dominate N# performance — heap allocations (<c>newobj</c>),
/// boxing, virtual dispatch (<c>callvirt</c> vs <c>call</c>), and delegate construction —
/// without a full disassembler.
/// </summary>
public sealed record IlShapeSummary(
    int IlBytes,
    int Newobj,
    int Box,
    int Callvirt,
    int Call,
    int DelegateCtors);

/// <summary>
/// Deterministic IL-shape inspection: the first-class way N# asserts and reports
/// codegen quality (allocation-free hot paths, no boxing, devirtualized calls). Unlike
/// wall-clock benchmarking it needs nothing to run, is noise-free, and is suitable as a
/// CI regression gate. Consumed by <c>nlc build --perf-report</c>, <c>nlc query perf</c>,
/// and the IL-shape evidence tests.
/// </summary>
public static class IlShapeInspector
{
    // Lookup tables mapping IL opcode values to their <see cref="OpCode"/> definitions.
    // Single-byte opcodes are indexed directly; two-byte opcodes share the 0xFE prefix
    // and are indexed by their second byte.
    private static readonly OpCode?[] SingleByteOpCodes = BuildOpCodeTable(twoByte: false);
    private static readonly OpCode?[] TwoByteOpCodes = BuildOpCodeTable(twoByte: true);

    private static OpCode?[] BuildOpCodeTable(bool twoByte)
    {
        var table = new OpCode?[256];
        foreach (var field in typeof(OpCodes).GetFields(BindingFlags.Public | BindingFlags.Static))
        {
            if (field.GetValue(null) is not OpCode opCode)
            {
                continue;
            }

            var value = (ushort)opCode.Value;
            var isTwoByte = (value & 0xFF00) == 0xFE00;
            if (isTwoByte == twoByte)
            {
                table[value & 0xFF] = opCode;
            }
        }

        return table;
    }

    /// <summary>
    /// Decodes a method's IL body and tallies the operations that most influence N#
    /// runtime performance. Resolution of metadata tokens (to detect delegate
    /// construction) must happen while the declaring module is still loaded. Returns
    /// <c>null</c> for abstract/extern/runtime-provided methods with no managed IL body.
    /// </summary>
    public static IlShapeSummary? ComputeIlShape(MethodInfo method)
    {
        byte[]? il;
        try
        {
            il = method.GetMethodBody()?.GetILAsByteArray();
        }
        catch
        {
            // Abstract/extern/runtime-provided methods have no managed IL body.
            il = null;
        }

        if (il == null)
        {
            return null;
        }

        var module = method.Module;
        var genericTypeArgs = method.DeclaringType?.IsGenericType == true
            ? method.DeclaringType.GetGenericArguments()
            : null;
        var genericMethodArgs = method.IsGenericMethod ? method.GetGenericArguments() : null;

        int newobj = 0, box = 0, callvirt = 0, call = 0, delegateCtors = 0;
        var pos = 0;
        while (pos < il.Length)
        {
            var opCode = ReadOpCode(il, ref pos);
            if (opCode == null)
            {
                break;
            }

            var op = opCode.Value;
            int operandToken = 0;
            var hasInlineToken = op.OperandType is OperandType.InlineMethod
                or OperandType.InlineField
                or OperandType.InlineType
                or OperandType.InlineTok
                or OperandType.InlineString
                or OperandType.InlineSig;

            if (hasInlineToken && pos + 4 <= il.Length)
            {
                operandToken = BitConverter.ToInt32(il, pos);
            }

            if (op == OpCodes.Newobj)
            {
                newobj++;
                if (IsDelegateConstructor(module, operandToken, genericTypeArgs, genericMethodArgs))
                {
                    delegateCtors++;
                }
            }
            else if (op == OpCodes.Box)
            {
                box++;
            }
            else if (op == OpCodes.Callvirt)
            {
                callvirt++;
            }
            else if (op == OpCodes.Call)
            {
                call++;
            }

            pos += OperandSize(op.OperandType, il, pos);
        }

        return new IlShapeSummary(il.Length, newobj, box, callvirt, call, delegateCtors);
    }

    private static OpCode? ReadOpCode(byte[] il, ref int pos)
    {
        var first = il[pos++];
        if (first == 0xFE)
        {
            if (pos >= il.Length)
            {
                return null;
            }

            return TwoByteOpCodes[il[pos++]];
        }

        return SingleByteOpCodes[first];
    }

    private static int OperandSize(OperandType operandType, byte[] il, int pos)
    {
        switch (operandType)
        {
            case OperandType.InlineNone:
                return 0;
            case OperandType.ShortInlineBrTarget:
            case OperandType.ShortInlineI:
            case OperandType.ShortInlineVar:
                return 1;
            case OperandType.InlineVar:
                return 2;
            case OperandType.InlineBrTarget:
            case OperandType.InlineField:
            case OperandType.InlineI:
            case OperandType.InlineMethod:
            case OperandType.InlineSig:
            case OperandType.InlineString:
            case OperandType.InlineTok:
            case OperandType.InlineType:
            case OperandType.ShortInlineR:
                return 4;
            case OperandType.InlineI8:
            case OperandType.InlineR:
                return 8;
            case OperandType.InlineSwitch:
                // A 4-byte count N followed by N 4-byte branch targets.
                if (pos + 4 > il.Length)
                {
                    return il.Length - pos;
                }

                var count = BitConverter.ToInt32(il, pos);
                return 4 + (count * 4);
            default:
                return 0;
        }
    }

    private static bool IsDelegateConstructor(
        Module module,
        int token,
        Type[]? genericTypeArgs,
        Type[]? genericMethodArgs)
    {
        if (token == 0)
        {
            return false;
        }

        try
        {
            var resolved = module.ResolveMethod(token, genericTypeArgs, genericMethodArgs);
            if (resolved is not ConstructorInfo ctor)
            {
                return false;
            }

            return typeof(Delegate).IsAssignableFrom(ctor.DeclaringType);
        }
        catch
        {
            // Tokens that cannot be resolved (e.g. across closed generics) are simply
            // not counted as delegate constructions.
            return false;
        }
    }
}
