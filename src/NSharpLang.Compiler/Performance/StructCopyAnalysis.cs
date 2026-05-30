using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Reflection.Emit;
using System.Runtime.CompilerServices;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.Performance;

/// <summary>
/// Pure analysis that decides when a by-value struct parameter can be lowered to a
/// pass-by-<c>in</c> (a <c>readonly ref</c>) parameter, eliminating the per-call struct
/// copy without changing behavior or breaking C# interop.
///
/// <para>
/// Passing a large value type by value forces the CLR to copy the entire struct onto the
/// callee's argument frame at every call site. For an immutable (<c>readonly</c>) struct
/// the copy is observationally redundant: the callee cannot mutate the argument, so handing
/// it a <c>readonly</c> reference is behaviorally identical while emitting zero copies.
/// </para>
///
/// <para>
/// This is the same transformation the C# compiler performs when a user writes <c>in</c>,
/// and an <c>in</c> parameter is fully C#-natural — external callers continue to pass by
/// value at the source level with no syntax change. We therefore stay ABI-safe while
/// dropping copies.
/// </para>
///
/// <para><b>Safety gates (all must hold):</b></para>
/// <list type="bullet">
///   <item>The parameter has no explicit <c>ref</c>/<c>out</c> modifier (those already pass by reference).</item>
///   <item>The resolved type is a value type that is not a primitive, enum, pointer, or open generic parameter.</item>
///   <item>The struct is provably <b>readonly</b> (an <c>InitOnly</c>/<c>readonly</c> struct), so the callee
///         cannot mutate it and the runtime never needs a hidden defensive copy.</item>
///   <item>The struct is "large" — its estimated size exceeds <see cref="SmallStructWordThreshold"/> pointer-words —
///         so the saved copy is worth the extra indirection.</item>
/// </list>
///
/// <para>
/// Ref-safety: an <c>in</c> parameter only hands the callee a borrow for the duration of the
/// call. The callee never stores or returns the reference (N# has no syntax to do so for an
/// ordinary parameter), so no reference can outlive the caller's storage. See
/// docs/design/performance-compiler-refactor.md "Value Layout".
/// </para>
/// </summary>
public static class StructCopyAnalysis
{
    /// <summary>
    /// Structs whose estimated size is at or below this many pointer-words are considered
    /// "small": for those the register/stack copy is already cheap and adding a layer of
    /// indirection (load address, dereference) would not pay off. Two words matches the
    /// common ABI sweet spot (e.g. a 16-byte struct fits in two registers on 64-bit).
    /// </summary>
    public const int SmallStructWordThreshold = 2;

    /// <summary>
    /// Returns <c>true</c> when the function body contains any closure (lambda expression or
    /// local function). When a function declares no closures, none of its parameters can be
    /// captured, so lowering a parameter to pass-by-<c>in</c> is escape-safe: the readonly
    /// reference never outlives the call frame. This is the conservative escape gate for
    /// struct-copy elimination — a function with any closure keeps its parameters by value.
    /// </summary>
    public static bool BodyContainsClosure(FunctionDeclaration function)
    {
        var visited = new HashSet<object>(ReferenceEqualityComparer.Instance);

        // Both forms must be scanned: a block body (`func f() { ... }`) and an expression body
        // (`func f() => () => x`). An expression-bodied function whose expression is itself a
        // lambda would otherwise slip past the escape gate and have its parameters lowered to
        // byref while still being captured by the closure.
        if (function.Body is { } block && NodeContainsClosure(block, visited))
        {
            return true;
        }

        return function.ExpressionBody is { } expression && NodeContainsClosure(expression, visited);
    }

    /// <summary>
    /// Returns <c>true</c> when the named parameter is the target of an assignment
    /// (<c>p = …</c>, <c>p += …</c>) or an in-place increment/decrement (<c>p++</c>) anywhere in
    /// the function body. A by-value parameter is a mutable local: assigning to it changes only the
    /// callee's copy. Once a parameter is lowered to pass-by-<c>in</c> (a managed reference) such a
    /// store would write <em>through</em> the reference and corrupt the caller's storage, so any
    /// reassigned parameter must keep its by-value ABI.
    /// </summary>
    public static bool ParameterIsAssignedInBody(FunctionDeclaration function, string parameterName)
    {
        var visited = new HashSet<object>(ReferenceEqualityComparer.Instance);

        if (function.Body is { } block && NodeAssignsIdentifier(block, parameterName, visited))
        {
            return true;
        }

        return function.ExpressionBody is { } expression
            && NodeAssignsIdentifier(expression, parameterName, visited);
    }

    private static bool NodeAssignsIdentifier(object? node, string name, HashSet<object> visited)
    {
        if (node is null || !visited.Add(node))
        {
            return false;
        }

        switch (node)
        {
            case AssignmentExpression { Target: IdentifierExpression target } when target.Name == name:
                return true;
            case UnaryExpression
                {
                    Operator: UnaryOperator.PreIncrement
                        or UnaryOperator.PreDecrement
                        or UnaryOperator.PostIncrement
                        or UnaryOperator.PostDecrement,
                    Operand: IdentifierExpression operand,
                } when operand.Name == name:
                return true;
            case string:
            case Type:
                return false;
        }

        if (node is AstNode astNode)
        {
            foreach (var child in EnumerateChildren(astNode))
            {
                if (NodeAssignsIdentifier(child, name, visited))
                {
                    return true;
                }
            }

            return false;
        }

        if (node is IEnumerable enumerable)
        {
            foreach (var item in enumerable)
            {
                if (item is AstNode or IEnumerable && NodeAssignsIdentifier(item, name, visited))
                {
                    return true;
                }
            }
        }

        return false;
    }

    private static bool NodeContainsClosure(object? node, HashSet<object> visited)
    {
        if (node is null || !visited.Add(node))
        {
            return false;
        }

        switch (node)
        {
            case LambdaExpression:
            case LocalFunctionStatement:
                return true;
            case string:
            case Type:
                return false;
        }

        // Reflection-based descent over the AST keeps this robust as new node shapes are added:
        // we recurse into every AstNode-typed property and every enumerable of nodes, rather
        // than enumerating each concrete record by hand.
        if (node is AstNode astNode)
        {
            foreach (var child in EnumerateChildren(astNode))
            {
                if (NodeContainsClosure(child, visited))
                {
                    return true;
                }
            }

            return false;
        }

        if (node is IEnumerable enumerable)
        {
            foreach (var item in enumerable)
            {
                if (item is AstNode or IEnumerable && NodeContainsClosure(item, visited))
                {
                    return true;
                }
            }
        }

        return false;
    }

    private static IEnumerable<object?> EnumerateChildren(AstNode node)
    {
        foreach (var property in node.GetType().GetProperties(BindingFlags.Public | BindingFlags.Instance))
        {
            if (property.GetIndexParameters().Length != 0)
            {
                continue;
            }

            var propertyType = property.PropertyType;
            if (propertyType.IsPrimitive || propertyType.IsEnum || propertyType == typeof(string))
            {
                continue;
            }

            object? value;
            try
            {
                value = property.GetValue(node);
            }
            catch (TargetInvocationException)
            {
                continue;
            }

            if (value is AstNode or IEnumerable)
            {
                yield return value;
            }
        }
    }

    /// <summary>
    /// Describes one instance field of a struct for analysis purposes. Lets the emitter feed in
    /// the field shape of an in-flight <see cref="TypeBuilder"/> (whose reflection surface is not
    /// yet queryable) via <see cref="FieldBuilder"/> data.
    /// </summary>
    public readonly record struct StructFieldDescriptor(Type FieldType, bool IsInitOnly, bool IsStatic);

    /// <summary>
    /// Returns <c>true</c> when a by-value parameter of the given resolved CLR type should be
    /// lowered to pass-by-<c>in</c>. <paramref name="resolvedType"/> must already be the
    /// non-by-ref element type (no <c>ref</c>/<c>out</c> wrapper).
    ///
    /// <paramref name="declaredFields"/> supplies the struct's instance fields when the type is an
    /// in-flight <see cref="TypeBuilder"/> whose reflection surface cannot yet be queried; pass
    /// <c>null</c> for fully baked runtime types, which describe themselves.
    /// </summary>
    public static bool ShouldPassByReadOnlyReference(
        Type resolvedType,
        IReadOnlyList<StructFieldDescriptor>? declaredFields = null)
    {
        if (resolvedType is null)
        {
            return false;
        }

        // Never touch by-ref, pointer, or open generic-parameter types: those are already
        // references, cannot have their size measured, or are shared across instantiations.
        if (resolvedType.IsByRef || resolvedType.IsPointer || resolvedType.IsGenericParameter)
        {
            return false;
        }

        if (!IsConcreteStruct(resolvedType))
        {
            return false;
        }

        // Only provably-immutable structs are safe. We require that every instance field is
        // InitOnly (constructor-write-only). Such a struct cannot mutate itself through any
        // instance member — a field write is only legal in the constructor — so passing it by
        // `in` can never let a callee observably mutate the caller's storage. (A settable
        // auto-property would emit a non-InitOnly backing field and is therefore excluded here,
        // keeping it by value.) The worst case for a non-`readonly`-marked-but-immutable struct
        // is a redundant CLR defensive copy on a non-readonly instance-method call, which is
        // behavior-preserving, never a correctness bug.
        if (!IsReadOnlyStruct(resolvedType, declaredFields))
        {
            return false;
        }

        return !IsSmall(resolvedType, declaredFields);
    }

    /// <summary>
    /// Returns <c>true</c> when the type is an ordinary value-type struct (not a primitive,
    /// enum, or by-ref-like / ref struct). Ref structs are excluded because they have their
    /// own stricter ref-safety rules and are never large heap-style aggregates.
    /// </summary>
    private static bool IsConcreteStruct(Type type)
    {
        if (!type.IsValueType || type.IsPrimitive || type.IsEnum)
        {
            return false;
        }

        if (Nullable.GetUnderlyingType(type) is not null)
        {
            return false;
        }

        // `ref struct` (IsByRefLike) values are stack-only with bespoke escape rules; leave them
        // alone. IsByRefLike throws on an in-flight TypeBuilder, so only consult it for fully
        // baked runtime types — N# does not emit ref structs as TypeBuilders here.
        if (type is not TypeBuilder && IsByRefLikeSafe(type))
        {
            return false;
        }

        return true;
    }

    private static bool IsByRefLikeSafe(Type type)
    {
        try
        {
            return type.IsByRefLike;
        }
        catch (NotSupportedException)
        {
            return false;
        }
    }

    /// <summary>
    /// Determines whether a value type is provably immutable, i.e. safe to pass by <c>in</c>.
    /// A struct qualifies when every instance field is <c>InitOnly</c> (constructor-write-only):
    /// no instance member can then mutate it, because a field write outside the constructor is
    /// illegal. This is exactly how N# emits immutable structs/records/newtypes, and a settable
    /// auto-property — whose backing field is <em>not</em> <c>InitOnly</c> — is correctly excluded.
    ///
    /// <para>
    /// For an in-flight <see cref="TypeBuilder"/> the caller supplies the field shape via
    /// <paramref name="declaredFields"/> (its reflection surface is not yet queryable). For a
    /// fully baked runtime type we accept either an explicit <see cref="IsReadOnlyAttribute"/> or
    /// an all-<c>InitOnly</c> field shape read back through reflection.
    /// </para>
    /// </summary>
    public static bool IsReadOnlyStruct(Type type, IReadOnlyList<StructFieldDescriptor>? declaredFields = null)
    {
        if (declaredFields is not null)
        {
            // Caller supplied the in-flight field shape (TypeBuilder). The struct is immutable
            // only when every instance field is InitOnly; a single mutable field keeps the
            // by-value ABI.
            return AllInstanceFieldsAreInitOnly(declaredFields);
        }

        if (type is TypeBuilder)
        {
            // No field data supplied and the TypeBuilder's reflection surface is not yet
            // queryable — stay conservative and keep the by-value ABI.
            return false;
        }

        return type.GetCustomAttributesData()
            .Any(data => data.AttributeType.FullName == "System.Runtime.CompilerServices.IsReadOnlyAttribute")
            || AllInstanceFieldsAreInitOnlyFromReflection(type);
    }

    private static bool AllInstanceFieldsAreInitOnly(IReadOnlyList<StructFieldDescriptor> fields)
    {
        var instanceFields = fields.Where(field => !field.IsStatic).ToList();

        // An empty struct is trivially immutable but also tiny, so it is filtered by size.
        return instanceFields.Count == 0 || instanceFields.All(field => field.IsInitOnly);
    }

    private static bool AllInstanceFieldsAreInitOnlyFromReflection(Type type)
    {
        FieldInfo[] fields;
        try
        {
            fields = type.GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        }
        catch (NotSupportedException)
        {
            return false;
        }

        return fields.Length == 0 || fields.All(field => field.IsInitOnly);
    }

    /// <summary>
    /// Returns <c>true</c> when the struct is small enough that passing it by value is already
    /// cheap. Uses <see cref="SmallStructWordThreshold"/> pointer-words as the cut-off.
    /// </summary>
    public static bool IsSmall(Type type, IReadOnlyList<StructFieldDescriptor>? declaredFields = null)
    {
        var words = declaredFields is not null
            ? EstimateSizeInWords(declaredFields)
            : EstimateSizeInWords(type, depth: 0);
        return words <= SmallStructWordThreshold;
    }

    private static int EstimateSizeInWords(IReadOnlyList<StructFieldDescriptor> fields)
    {
        var total = 0;
        foreach (var field in fields)
        {
            if (field.IsStatic)
            {
                continue;
            }

            total += field.FieldType.IsValueType
                ? EstimateSizeInWords(field.FieldType, depth: 1)
                : 1;
        }

        return total == 0 ? 1 : total;
    }

    /// <summary>
    /// Estimates the size of a value type in pointer-words. We cannot call
    /// <see cref="System.Runtime.InteropServices.Marshal.SizeOf(Type)"/> on a
    /// <see cref="TypeBuilder"/> (or on managed-reference-containing structs), so we sum a
    /// conservative per-field word estimate over the declared instance fields. A reference
    /// or unknown field counts as one word; a nested value type recurses. The estimate only
    /// drives a performance heuristic, so over- or under-counting is never a correctness risk.
    /// </summary>
    private static int EstimateSizeInWords(Type type, int depth)
    {
        // Guard against pathological / cyclic value-type graphs (illegal in the CLR, but a
        // TypeBuilder mid-emit can momentarily look odd). Treat anything too deep as "large".
        if (depth > 8)
        {
            return SmallStructWordThreshold + 1;
        }

        if (!type.IsValueType)
        {
            return 1; // a reference is one word
        }

        FieldInfo[] fields;
        try
        {
            fields = type.GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        }
        catch (NotSupportedException)
        {
            return 1;
        }

        var total = 0;
        foreach (var field in fields)
        {
            var fieldType = field.FieldType;
            total += fieldType.IsValueType && fieldType != type
                ? EstimateSizeInWords(fieldType, depth + 1)
                : 1;
        }

        return total == 0 ? 1 : total;
    }
}
