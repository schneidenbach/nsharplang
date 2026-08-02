namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection

// The analyzer's CLR `Type` → `TypeInfo` conversion, and its generic-substitution variant.
//
// This is the opposite direction from `AnalyzerClrTypeConversion`: that owner asks "what CLR type
// does this N# type denote", this one asks "what N# type does this reflected type denote". It is the
// first thing every metadata-facing arm of the analyzer does with a `Type` it has just read off a
// referenced assembly, and it is a TOTAL function — every `Type` converts, with `ReflectionTypeInfo`
// as the catch-all.
//
// THE BUILT-IN TABLE IS KEYED ON `FullName`, NOT ON `typeof`, and that is load-bearing: the analyzer
// reads most types through a MetadataLoadContext, where the projected `System.Int32` is NOT
// `typeof(int)`. The name test is exact in both worlds. The table is also consulted FIRST, ahead of
// the by-ref / array / generic arms, exactly as the C# switch ordered them — a by-ref `int&` has
// `FullName` "System.Int32&" and so falls past the table to the by-ref arm on its own.
//
// THE OVERRIDE IS DATA, NOT A CALLBACK. A conversion that runs while a generic method is being bound
// has to answer some positions with the N# types the call site supplied rather than with the open
// parameter. `AnalyzerReflectionTypeOverride` carries exactly that — the TypeInfo overrides, the CLR
// bindings and which of the two composition rules applies — so the nullability reader can consult it
// at every leaf without a function crossing the boundary. Nothing here reports, records or caches.

// The substitution a reflection conversion carries with it. Two shapes, and the difference is
// measured behaviour rather than convenience:
//   * DIRECT — always compose through the override walk. This is what a delegate signature built
//     from an open type wants: every position is rewritten.
//   * BOUND — compose through the override walk only when there is something to substitute (a
//     TypeInfo override exists, or this position still mentions a type parameter); otherwise apply
//     the CLR bindings to the type itself and convert the RESULT. The two are not interchangeable:
//     the override walk builds a `GenericTypeInfo` over converted arguments, while applying the
//     bindings first yields a closed CLR type that converts as one reflected instantiation.
public class AnalyzerReflectionTypeOverride {

    typeInfoOverridesValue: Dictionary<Type, TypeInfo>
    clrBindingsValue: Dictionary<Type, Type>?
    boundValue: bool
    hasTypeInfoOverridesValue: bool

    constructor(
        typeInfoOverrides: Dictionary<Type, TypeInfo>,
        clrBindings: Dictionary<Type, Type>?,
        bound: bool,
        hasTypeInfoOverrides: bool) {
        typeInfoOverridesValue = typeInfoOverrides
        clrBindingsValue = clrBindings
        boundValue = bound
        hasTypeInfoOverridesValue = hasTypeInfoOverrides
    }

    public static func Direct(
        typeInfoOverrides: Dictionary<Type, TypeInfo>,
        clrBindings: Dictionary<Type, Type>?): AnalyzerReflectionTypeOverride {
        return new AnalyzerReflectionTypeOverride(typeInfoOverrides, clrBindings, false, false)
    }

    public static func Bound(
        typeInfoOverrides: Dictionary<Type, TypeInfo>,
        clrBindings: Dictionary<Type, Type>?,
        hasTypeInfoOverrides: bool): AnalyzerReflectionTypeOverride {
        return new AnalyzerReflectionTypeOverride(
            typeInfoOverrides,
            clrBindings,
            true,
            hasTypeInfoOverrides)
    }

    // The answer for one position. Never null: an override that has nothing to say still answers the
    // plain conversion, which is exactly what the C# lambdas this replaces did.
    public func Answer(clrType: Type): TypeInfo {
        if boundValue && !hasTypeInfoOverridesValue && !clrType.get_ContainsGenericParameters() {
            bindings := clrBindingsValue
            if bindings == null {
                return AnalyzerReflectionTypeConversion.ConvertReflectionType(clrType)
            }

            applied := AnalyzerReflectionTypeConversion.ApplyReflectionBindings(clrType, bindings)
            return AnalyzerReflectionTypeConversion.ConvertReflectionType(applied)
        }

        return AnalyzerReflectionTypeConversion.ConvertReflectionTypeWithOverrides(
            clrType,
            typeInfoOverridesValue,
            clrBindingsValue)
    }
}

public class AnalyzerReflectionTypeConversion {

    // The plain conversion. Total: every `Type` answers, with `ReflectionTypeInfo` as the catch-all.
    public static func ConvertReflectionType(clrType: Type): TypeInfo {
        builtIn := ConvertBuiltInReflectionType(clrType.get_FullName())
        if builtIn != null {
            return builtIn
        }

        if clrType.get_IsByRef() {
            byRefElement := clrType.GetElementType()
            if byRefElement != null {
                return ConvertReflectionType(byRefElement)
            }
        }

        if clrType.get_IsArray() {
            arrayElement := clrType.GetElementType()
            if arrayElement != null {
                array: TypeInfo = new ArrayTypeInfo(ConvertReflectionType(arrayElement))
                return array
            }
        }

        if clrType.get_IsGenericType() {
            name := clrType.Name
            tick := name.IndexOf('`')
            arguments := clrType.GetGenericArguments()
            convertedArguments := new List<TypeInfo>()
            index := 0
            while index < arguments.Length {
                convertedArguments.Add(ConvertReflectionType(arguments[index]))
                index = index + 1
            }

            constructed: TypeInfo = ReflectionTypeInfoFactory.FromConstructedGeneric(
                name.Substring(0, tick),
                convertedArguments,
                clrType)
            return constructed
        }

        reflected: TypeInfo = new ReflectionTypeInfo(clrType)
        return reflected
    }

    // The substitution-aware conversion. With nothing to substitute it IS the plain conversion, and
    // that shortcut is behaviour rather than an optimisation: without it a generic PARAMETER would
    // fall through to the reflected catch-all here too, which is what the plain conversion answers.
    public static func ConvertReflectionTypeWithOverrides(
        clrType: Type,
        typeInfoOverrides: Dictionary<Type, TypeInfo>,
        clrBindings: Dictionary<Type, Type>?): TypeInfo {
        bindingCount := 0
        if clrBindings != null {
            bindingCount = clrBindings.Count
        }

        if typeInfoOverrides.Count == 0 && bindingCount == 0 {
            return ConvertReflectionType(clrType)
        }

        if clrType.get_IsGenericParameter() {
            overridden: TypeInfo? = null
            if typeInfoOverrides.TryGetValue(clrType, out overridden) {
                if overridden != null {
                    return overridden
                }
            }

            if clrBindings != null {
                bound: Type? = null
                if clrBindings.TryGetValue(clrType, out bound) {
                    if bound != null {
                        return ConvertReflectionType(bound)
                    }
                }
            }
        }

        if clrType.get_IsByRef() {
            byRefElement := clrType.GetElementType()
            if byRefElement != null {
                return ConvertReflectionTypeWithOverrides(byRefElement, typeInfoOverrides, clrBindings)
            }
        }

        if clrType.get_IsArray() {
            arrayElement := clrType.GetElementType()
            if arrayElement != null {
                array: TypeInfo = new ArrayTypeInfo(
                    ConvertReflectionTypeWithOverrides(arrayElement, typeInfoOverrides, clrBindings))
                return array
            }
        }

        if clrType.get_IsGenericType() {
            arguments := clrType.GetGenericArguments()
            convertedArguments := new List<TypeInfo>()
            index := 0
            while index < arguments.Length {
                convertedArguments.Add(
                    ConvertReflectionTypeWithOverrides(arguments[index], typeInfoOverrides, clrBindings))
                index = index + 1
            }

            constructed: TypeInfo = ReflectionTypeInfoFactory.FromConstructedGeneric(
                StripGenericArity(clrType.Name),
                convertedArguments,
                clrType)
            return constructed
        }

        return ConvertReflectionType(clrType)
    }

    // Rewrites a CLR type by substituting bound type parameters INTO it, answering a CLR type rather
    // than a TypeInfo. An unchanged composition answers the ORIGINAL instance rather than a
    // reconstructed equal one, which keeps reference identity where nothing was substituted.
    public static func ApplyReflectionBindings(clrType: Type, bindings: Dictionary<Type, Type>): Type {
        if clrType.get_IsGenericParameter() {
            bound: Type? = null
            if bindings.TryGetValue(clrType, out bound) {
                if bound != null {
                    return bound
                }
            }
        }

        if clrType.get_IsByRef() {
            byRefElement := clrType.GetElementType()
            if byRefElement != null {
                appliedElement := ApplyReflectionBindings(byRefElement, bindings)
                return appliedElement.MakeByRefType()
            }
        }

        if clrType.get_IsArray() {
            arrayElement := clrType.GetElementType()
            if arrayElement != null {
                appliedElement := ApplyReflectionBindings(arrayElement, bindings)
                if Object.Equals(appliedElement, arrayElement) {
                    return clrType
                }

                return appliedElement.MakeArrayType()
            }
        }

        if !clrType.get_IsGenericType() {
            return clrType
        }

        arguments := clrType.GetGenericArguments()
        applied := new Type[arguments.Length]
        changed := false
        index := 0
        while index < arguments.Length {
            argument := arguments[index]
            appliedArgument := ApplyReflectionBindings(argument, bindings)
            applied[index] = appliedArgument
            if !Object.Equals(appliedArgument, argument) {
                changed = true
            }

            index = index + 1
        }

        if !changed {
            return clrType
        }

        definition := clrType.GetGenericTypeDefinition()
        return definition.MakeGenericType(applied)
    }

    // The four member-facing entry points. Each composes the nullability reader's walk with an
    // override, so a caller never has to hand a function across a boundary.
    public static func ConvertParameterWithOverrides(
        parameter: ParameterInfo,
        typeInfoOverrides: Dictionary<Type, TypeInfo>,
        clrBindings: Dictionary<Type, Type>?): TypeInfo {
        return NullabilityMetadataReflection.ConvertParameterWithOverride(
            parameter,
            AnalyzerReflectionTypeOverride.Direct(typeInfoOverrides, clrBindings))
    }

    public static func ConvertReturnWithOverrides(
        method: MethodInfo,
        typeInfoOverrides: Dictionary<Type, TypeInfo>,
        clrBindings: Dictionary<Type, Type>?): TypeInfo {
        return NullabilityMetadataReflection.ConvertReturnWithOverride(
            method,
            AnalyzerReflectionTypeOverride.Direct(typeInfoOverrides, clrBindings))
    }

    public static func ConvertBoundParameter(
        parameter: ParameterInfo,
        typeInfoOverrides: Dictionary<Type, TypeInfo>,
        clrBindings: Dictionary<Type, Type>?,
        hasTypeInfoOverrides: bool): TypeInfo {
        return NullabilityMetadataReflection.ConvertParameterWithOverride(
            parameter,
            AnalyzerReflectionTypeOverride.Bound(typeInfoOverrides, clrBindings, hasTypeInfoOverrides))
    }

    public static func ConvertBoundReturn(
        method: MethodInfo,
        typeInfoOverrides: Dictionary<Type, TypeInfo>,
        clrBindings: Dictionary<Type, Type>?,
        hasTypeInfoOverrides: bool): TypeInfo {
        return NullabilityMetadataReflection.ConvertReturnWithOverride(
            method,
            AnalyzerReflectionTypeOverride.Bound(typeInfoOverrides, clrBindings, hasTypeInfoOverrides))
    }

    // The same BOUND rule applied to a bare type rather than to a member.
    public static func ConvertBoundType(
        clrType: Type,
        typeInfoOverrides: Dictionary<Type, TypeInfo>,
        clrBindings: Dictionary<Type, Type>?,
        hasTypeInfoOverrides: bool): TypeInfo {
        substitution := AnalyzerReflectionTypeOverride.Bound(
            typeInfoOverrides,
            clrBindings,
            hasTypeInfoOverrides)
        return substitution.Answer(clrType)
    }

    // The type a written argument is EXPECTED to have, once the candidate's inference is known.
    //
    // THE ONE DECISION IS WHICH SPELLING OF THE PARAMETER TO ASK ABOUT. An EXPANDED params tail
    // records the ELEMENT type as its open parameter type while the `ParameterInfo` still declares
    // the ARRAY, so the tail must be converted from the recorded type; every other position reads
    // the parameter itself, which is what carries the declaration's nullability metadata.
    public static func ConvertSuppliedArgumentType(
        supplied: SuppliedReflectionBoundArgument,
        parameter: ParameterInfo,
        workingBindings: Dictionary<Type, Type>,
        workingTypeInfoBindings: Dictionary<Type, TypeInfo>,
        hasTypeInfoOverrides: bool): TypeInfo {
        if AnalyzerOverloadFacts.IsExpandedReflectionParamsArgument(supplied, parameter) {
            return ConvertBoundType(
                supplied.OpenParameterType,
                workingTypeInfoBindings,
                workingBindings,
                hasTypeInfoOverrides)
        }

        return ConvertBoundParameter(
            parameter,
            workingTypeInfoBindings,
            workingBindings,
            hasTypeInfoOverrides)
    }

    // The generic head's name without its arity suffix. The two conversions differ here on purpose:
    // the plain one indexes the backtick UNGUARDED (a generic type without one is a nested type whose
    // own name carries no arity, and the C# this replaces threw there), while the substituting one
    // answers the bare name.
    static func StripGenericArity(name: string): string {
        tick := name.IndexOf('`')
        if tick >= 0 {
            return name.Substring(0, tick)
        }

        return name
    }

    // The primitive table, keyed on metadata name so it is exact under a MetadataLoadContext.
    static func ConvertBuiltInReflectionType(fullName: string?): TypeInfo? {
        if fullName == null {
            return null
        }

        if fullName == "System.Byte" { return BuiltInTypes.Byte }
        if fullName == "System.SByte" { return BuiltInTypes.SByte }
        if fullName == "System.Int16" { return BuiltInTypes.Short }
        if fullName == "System.UInt16" { return BuiltInTypes.UShort }
        if fullName == "System.Int32" { return BuiltInTypes.Int }
        if fullName == "System.UInt32" { return BuiltInTypes.UInt }
        if fullName == "System.Int64" { return BuiltInTypes.Long }
        if fullName == "System.UInt64" { return BuiltInTypes.ULong }
        if fullName == "System.Char" { return BuiltInTypes.Char }
        if fullName == "System.Single" { return BuiltInTypes.Float }
        if fullName == "System.Double" { return BuiltInTypes.Double }
        if fullName == "System.Decimal" { return BuiltInTypes.Decimal }
        if fullName == "System.Boolean" { return BuiltInTypes.Bool }
        if fullName == "System.String" { return BuiltInTypes.String }
        if fullName == "System.Void" { return BuiltInTypes.Void }
        if fullName == "System.Object" { return BuiltInTypes.Object }

        return null
    }
}
