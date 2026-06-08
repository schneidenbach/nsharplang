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
/// conversions this spike does not emit). Statements: <c>:=</c> int locals, a simple <c>local = expr</c>
/// assignment, Return (value required), and an <c>if</c>/<c>else</c> where BOTH branches always return (no
/// fall-through). Value expressions: a parameter, a
/// <c>:=</c> local, an int literal, a parenthesized expr, or an int +/-/* binary. <c>if</c> conditions are an
/// int comparison (<c>&lt; &gt; &lt;= &gt;= == !=</c>) only. Anything else returns false (the adapter declines
/// → the C# path is unaffected).
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
    // `:=` locals declared so far, by name (int-only spike, so every local is typeof(int)).
    private readonly Dictionary<string, LocalBuilder> _locals = new(StringComparer.Ordinal);

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
        // An int function must return on every path (NL305): the body must always return, else the emitted IL
        // would fall off the end with no `ret` (invalid). Decline a non-returning body to the C# analyzer.
        if (!emitter.AlwaysReturns(bodyRoot) || !emitter.EmitStatement(bodyRoot))
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
                    var child = Child(idx, n);
                    if (!EmitStatement(child))
                        return false;
                    // A statement that always returns must be the LAST in its block; any statement after it is
                    // unreachable (an NL312 diagnostic). Decline rather than emit code after a `ret`, keeping the
                    // C# analyzer/codegen authoritative. (AlwaysReturns matches the diagnostics-pass subset.)
                    if (AlwaysReturns(child) && n != _childCount[idx] - 1)
                        return false;
                }

                return true;

            case 20: // Return [value] — the spike is int-only, so a value is REQUIRED (a value-less `return`
                     // would emit `ret` with an empty stack = invalid IL); decline it.
                if (_childCount[idx] == 0 || !EmitExpression(Child(idx, 0)))
                    return false;
                _il.Emit(OpCodes.Ret);
                return true;

            case 24: // VariableDeclaration (`:=`): emit the initializer, declare an int local, store into it.
            {
                var name = Text(idx);
                // Decline a local that shadows a parameter or redeclares a local: N# treats shadowing as a
                // diagnostic (and a same-`:=` redeclaration as an error), which the spike does not model —
                // declining keeps the C# analyzer authoritative rather than silently compiling it.
                if (_paramOrdinals.ContainsKey(name) || _locals.ContainsKey(name))
                    return false;
                if (_childCount[idx] == 0 || !EmitExpression(Child(idx, 0)))
                    return false;
                var local = _il.DeclareLocal(typeof(int));
                _il.Emit(OpCodes.Stloc, local);
                _locals[name] = local;
                return true;
            }

            case 27: // If [condition, then, else] — FIRST CUT: require an else where BOTH branches always return,
            {        // so there is no fall-through (no merge label / trailing-ret subtleties). Decline otherwise.
                if (_childCount[idx] != 3 || !AlwaysReturns(Child(idx, 1)) || !AlwaysReturns(Child(idx, 2)))
                    return false;
                if (!EmitCondition(Child(idx, 0)))
                    return false;
                var elseLabel = _il.DefineLabel();
                _il.Emit(OpCodes.Brfalse, elseLabel);   // condition false -> else branch
                if (!EmitStatement(Child(idx, 1)))       // then (always returns -> ends in `ret`)
                    return false;
                _il.MarkLabel(elseLabel);
                return EmitStatement(Child(idx, 2));      // else (always returns -> ends in `ret`)
            }

            case 23: // ExpressionStatement — FIRST CUT: only a SIMPLE `local = expr` assignment (kind 14, op `=`)
            {        // to an existing `:=` local. Compound ops (`+=`) and non-local targets (param/field/index)
                     // and side-effecting statements (a bare call) decline.
                var expr = Child(idx, 0);
                if (_kinds[expr] != 14 || Text(expr) != "=")
                    return false;
                var target = Child(expr, 0);
                if (_kinds[target] != 6 || !_locals.TryGetValue(Text(target), out var assignTarget))
                    return false;
                if (!EmitExpression(Child(expr, 1)))
                    return false;
                _il.Emit(OpCodes.Stloc, assignTarget);
                return true;
            }

            default: // spike: Block / Return / `:=` declaration / if-else-both-return only.
                return false;
        }
    }

    /// <summary>
    /// Emit an `if` CONDITION as a bool (i4 0/1) on the stack. To keep types honest without a full type checker,
    /// conditions are restricted to an int comparison (<c>&lt; &gt; &lt;= &gt;= == !=</c>) of two int value
    /// expressions — so a comparison (a bool) can never leak into an int value/return position (which would
    /// diverge from the C# type rules). Anything else declines.
    /// </summary>
    private bool EmitCondition(int idx)
    {
        if (_kinds[idx] != 12) // must be a Binary comparison.
            return false;
        if (!EmitExpression(Child(idx, 0)) || !EmitExpression(Child(idx, 1)))
            return false;
        switch (Text(idx))
        {
            case "<": _il.Emit(OpCodes.Clt); return true;
            case ">": _il.Emit(OpCodes.Cgt); return true;
            case "==": _il.Emit(OpCodes.Ceq); return true;
            case "!=": _il.Emit(OpCodes.Ceq); _il.Emit(OpCodes.Ldc_I4_0); _il.Emit(OpCodes.Ceq); return true;
            case "<=": _il.Emit(OpCodes.Cgt); _il.Emit(OpCodes.Ldc_I4_0); _il.Emit(OpCodes.Ceq); return true; // !(a > b)
            case ">=": _il.Emit(OpCodes.Clt); _il.Emit(OpCodes.Ldc_I4_0); _il.Emit(OpCodes.Ceq); return true; // !(a < b)
            default: return false;
        }
    }

    /// <summary>
    /// Whether this statement always exits via a return — the same columnar subset as the diagnostics pass
    /// (Return; a Block whose any statement returns; an If with an else where both branches return). Used to
    /// guarantee the emitted `if` has no fall-through.
    /// </summary>
    private bool AlwaysReturns(int idx)
    {
        switch (_kinds[idx])
        {
            case 20: // Return
                return true;
            case 25: // Block
                for (var n = 0; n < _childCount[idx]; n++)
                {
                    if (AlwaysReturns(Child(idx, n)))
                        return true;
                }

                return false;
            case 27: // If [cond, then, else?]
                return _childCount[idx] == 3 && AlwaysReturns(Child(idx, 1)) && AlwaysReturns(Child(idx, 2));
            default:
                return false;
        }
    }

    private bool EmitExpression(int idx)
    {
        switch (_kinds[idx])
        {
            case 6: // Identifier — a `:=` local (ldloc) or a parameter (ldarg); the two name sets are disjoint
                    // (a local that shadows a param is declined at its declaration).
            {
                var name = Text(idx);
                if (_locals.TryGetValue(name, out var local))
                {
                    _il.Emit(OpCodes.Ldloc, local);
                    return true;
                }

                if (_paramOrdinals.TryGetValue(name, out var ordinal))
                {
                    EmitLoadArgument(ordinal);
                    return true;
                }

                return false;
            }

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
