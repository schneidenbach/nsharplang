namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection.Emit

// WHAT SHAPE A RUNTIME `Type` HAS WHILE THE ASSEMBLY IS STILL BEING BUILT — asked once.
//
// Half of the emitter's questions about a `Type` cannot be asked of `System.Type` directly, because
// the type may be a `TypeBuilder` or an `EnumBuilder` that is not baked yet: `get_IsEnum()` throws
// `NotSupportedException` on some builders, an `EnumBuilder` is not a `TypeBuilder` and must be
// recognised by walking its own runtime class, and every independent `MakeGenericType` over a
// builder yields a referentially DISTINCT instantiation, so `==` is not identity for them.
//
// Every resolver and planner that needed one of those answers had grown its own copy — two copies
// each of `IsEnumType`, `IsEnumBuilder`, `IsByRefLike` and `HasExactRuntimeTypeIdentity`, four of
// `ContainsBuilderBoundType`, and six of the recursive shape walk. They are owned here.
//
// TWO ANSWERS ARE GENUINELY DIFFERENT AND BOTH ARE KEPT.
//
//  * `ContainsBuilderBoundType` and `ContainsBuilderBoundTypeThroughElements` are not the same
//    predicate. The first treats an unbaked ENUM builder as builder-bound and looks through SZ
//    arrays only; the second looks through any element type (`T[]`, `T&`, `T*`) and does not ask
//    about enum builders at all. Two owners each had one of them, verbatim.
//
//  * `ExactTypeShapeMatches` and `ExactTypeShapeMatchesWithGenericParameterIdentity` differ by one
//    arm: whether two open generic PARAMETERS of the same identity count as the same shape.
//    Reference conversion says yes; instance-member resolution, nullable-argument lowering and
//    `typeof` planning say no. The arm applies at every level of the recursion, not just the top,
//    so it is threaded through the private walk rather than tested once at the entry.
//
// `ColumnarAttributeBlobWriter.IsEnumType` is NOT this `IsEnumType` — it answers for a baked
// attribute blob and refuses unbaked builders — and stays where it is.
static class RuntimeTypeShapeFacts {

    // ── BUILDERS ──────────────────────────────────────────────────────────────
    //
    // `EnumBuilder` does not derive from `TypeBuilder`, and the only reliable way to recognise one
    // across host runtimes is to walk the RUNTIME CLASS of the object itself.
    static func IsEnumBuilder(valueType: Type): bool {
        if valueType == null {
            return false
        }

        candidate := valueType.GetType()
        while candidate != null {
            if candidate.FullName == "System.Reflection.Emit.EnumBuilder" {
                return true
            }

            candidate = candidate.get_BaseType()
        }

        return false
    }

    // `get_IsEnum()` throws on builders that have not been baked, so the base type is read directly
    // for a `TypeBuilder` and every reflection call is guarded.
    static func IsEnumType(valueType: Type): bool {
        if IsEnumBuilder(valueType) {
            return true
        }

        if valueType is TypeBuilder {
            try {
                baseType := valueType.get_BaseType()
                return baseType != null && baseType.FullName == "System.Enum"
            } catch unsupportedBuilderBaseType: NotSupportedException {
                return false
            } catch unimplementedBuilderBaseType: NotImplementedException {
                return false
            }
        }

        try {
            return valueType.get_IsEnum()
        } catch unsupportedEnumQuestion: NotSupportedException {
            return false
        } catch unimplementedEnumQuestion: NotImplementedException {
            return false
        }
    }

    static func IsByRefLike(valueType: Type): bool {
        try {
            return valueType.get_IsByRefLike()
        } catch unsupportedByRefLikeQuestion: NotSupportedException {
            return false
        } catch unimplementedByRefLikeQuestion: NotImplementedException {
            return false
        }
    }

    // A builder-bound candidate has no assembly-qualified identity to compare, so it is refused
    // rather than asked.
    static func HasExactRuntimeTypeIdentity(candidate: Type, runtimeType: Type): bool {
        if candidate is TypeBuilder || IsEnumBuilder(candidate) {
            return false
        }

        identity := runtimeType.get_AssemblyQualifiedName()
        return identity != null && ExternalAssemblyScan.HasExactTypeIdentity(candidate, identity)
    }

    // Does this type reach a type the compilation is still WRITING — directly, through an SZ array's
    // element, through an open generic parameter, or through a generic argument or head?
    static func ContainsBuilderBoundType(valueType: Type): bool {
        if valueType is TypeBuilder || IsEnumBuilder(valueType) || valueType.get_IsGenericParameter() {
            return true
        }

        if ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(valueType) {
            elementType := valueType.GetElementType()
            return elementType != null && ContainsBuilderBoundType(elementType)
        }

        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }

        definition := valueType.GetGenericTypeDefinition()
        if definition is TypeBuilder || IsEnumBuilder(definition) {
            return true
        }

        for argument in valueType.GetGenericArguments() {
            if ContainsBuilderBoundType(argument) {
                return true
            }
        }

        return false
    }

    // The same question asked WITHOUT the enum-builder rule and through ANY element type — which is
    // what construction planning and constructed-conversion selection ask, verbatim, today.
    static func ContainsBuilderBoundTypeThroughElements(valueType: Type): bool {
        if valueType is TypeBuilder || valueType.get_IsGenericParameter() {
            return true
        }

        if valueType.get_HasElementType() {
            element := valueType.GetElementType()
            return element != null && ContainsBuilderBoundTypeThroughElements(element)
        }

        if !valueType.get_IsGenericType() || valueType.get_IsGenericTypeDefinition() {
            return false
        }

        for argument in valueType.GetGenericArguments() {
            if ContainsBuilderBoundTypeThroughElements(argument) {
                return true
            }
        }

        return false
    }

    // ── SHAPE ─────────────────────────────────────────────────────────────────
    //
    // Structural identity for types the assembly is still writing: reference equality first, then
    // SZ arrays element-wise, then closed generic instantiations definition-and-arguments-wise.
    static func ExactTypeShapeMatches(left: Type, right: Type): bool {
        return ShapeMatches(left, right, false)
    }

    // The same walk, with two open generic parameters of the same identity counting as one shape.
    static func ExactTypeShapeMatchesWithGenericParameterIdentity(left: Type, right: Type): bool {
        return ShapeMatches(left, right, true)
    }

    // THE ARRAY ARM WAS SPELLED TWO WAYS AND THEY AGREE. Four of the six copies wrote
    // `IsSafeSzArrayType(left) || IsSafeSzArrayType(right)` and then refused a pair that is not both
    // arrays; the fifth wrote `&&` and let a one-sided array fall through to the generic test. An SZ
    // array is never a generic type, so that test refuses it too. `RuntimeTypeShapeFacts.tests.nl`
    // pins that equivalence rather than leaving it to be re-derived.
    private static func ShapeMatches(left: Type, right: Type, matchGenericParameterIdentity: bool): bool {
        if left == right {
            return true
        }

        if matchGenericParameterIdentity && (left.get_IsGenericParameter() || right.get_IsGenericParameter()) {
            return left.get_IsGenericParameter() && right.get_IsGenericParameter() && ColumnarGenericCallBindingPlanner.SameTypeParameterIdentity(left, right)
        }

        if ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(left) || ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(right) {
            if !ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(left) || !ColumnarTypeEquivalenceFacts.IsSafeSzArrayType(right) {
                return false
            }

            leftElement := left.GetElementType()
            rightElement := right.GetElementType()
            return leftElement != null && rightElement != null && ShapeMatches(leftElement, rightElement, matchGenericParameterIdentity)
        }

        if !left.get_IsGenericType() || !right.get_IsGenericType() || left.get_IsGenericTypeDefinition() || right.get_IsGenericTypeDefinition() || left.GetGenericTypeDefinition() != right.GetGenericTypeDefinition() {
            return false
        }

        leftArguments := left.GetGenericArguments()
        rightArguments := right.GetGenericArguments()
        if leftArguments.Length != rightArguments.Length {
            return false
        }

        index := 0
        while index < leftArguments.Length {
            if !ShapeMatches(leftArguments[index], rightArguments[index], matchGenericParameterIdentity) {
                return false
            }

            index = index + 1
        }

        return true
    }
}
