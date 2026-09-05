namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// The two assignability arms that have to LOOK SOMETHING UP, and are therefore not pure shape facts.
//
// `AnalyzerAssignabilityFacts` holds the arms that are decidable from the two types alone — it
// reports nothing, records nothing and consults nothing outside itself. These two are the exceptions
// and they are kept apart from it deliberately, because keeping that class silent is a property
// worth being able to state:
//
// * THE DUCK-INTERFACE ARM compares member signatures, and comparing them means RESOLVING the
//   references those members were declared with. That resolution walk records every reference it
//   resolves into the semantic model and can report on it, so this arm is the only EFFECTFUL member
//   of the whole assignability closure.
// * THE ACTIONRESULT ARM asks the referenced-assembly probe whether ASP.NET Core's `ActionResult` is
//   even present in this compilation, which depends on the project's references rather than on the
//   two types.
//
// STRUCTURAL, NOT NOMINAL, AND ONE-WAY. A duck interface is satisfied by a type that HAS the right
// methods; it never has to name the interface. Only the interface's FUNCTION members are demanded —
// a duck interface's fields and properties impose nothing — and only the source's function members
// can satisfy them. A source with no declared members at all (a CLR type, a built-in, a union, an
// array) satisfies nothing, including the empty interface, which is the C# behaviour this preserves
// exactly: the member list is consulted before the interface's demands are.
//
// SIGNATURE EQUALITY IS BY RESOLVED SPELLING. Two members match when their names, arities, resolved
// parameter types and resolved return types agree, compared by the resolved type's own display form
// so that two spellings of one type agree and two types that merely print alike do not diverge. A
// member with NO declared return type is `void` — which is what makes `func F()` on a class satisfy
// `func F()` on the interface. The resolution ORDER is load-bearing and preserved: parameters are
// resolved in pairs, left to right, and the first mismatch stops the walk, so a later parameter of a
// member that already failed is never resolved and never recorded.
class AnalyzerStructuralAssignability {
    typeResolverValue: AnalyzerTypeResolver
    externalTypeProbeValue: AnalyzerExternalTypeProbe

    constructor(typeResolver: AnalyzerTypeResolver, externalTypeProbe: AnalyzerExternalTypeProbe) {
        typeResolverValue = typeResolver
        externalTypeProbeValue = externalTypeProbe
    }

    // True when `source` declares a matching function for every function the duck interface demands.
    func ImplementsDuckInterface(source: TypeInfo, duckInterface: InterfaceTypeInfo): bool {
        sourceMembers := GetDeclaredMembers(source)
        if sourceMembers == null {
            return false
        }

        interfaceMembers := duckInterface.DeclaredMembers
        interfaceIndex := 0
        while interfaceIndex < interfaceMembers.Length {
            interfaceMember := interfaceMembers[interfaceIndex]
            if interfaceMember.Kind == DeclaredMemberKind.Function {
                found := false
                sourceIndex := 0
                while sourceIndex < sourceMembers.Length && !found {
                    sourceMember := sourceMembers[sourceIndex]
                    if sourceMember.Kind == DeclaredMemberKind.Function {
                        if MethodSignaturesMatch(sourceMember, interfaceMember) {
                            found = true
                        }
                    }
                    sourceIndex = sourceIndex + 1
                }

                if !found {
                    return false
                }
            }

            interfaceIndex = interfaceIndex + 1
        }

        return true
    }

    // Name, arity, parameter types and return type — every one of them compared by the RESOLVED
    // type's display form, and resolved in the original left-to-right order so the effects of the
    // resolution walk land exactly where they did before.
    func MethodSignaturesMatch(method1: DeclaredMemberInfo, method2: DeclaredMemberInfo): bool {
        if method1.Name != method2.Name {
            return false
        }

        if method1.ParameterCount != method2.ParameterCount {
            return false
        }

        index := 0
        while index < method1.ParameterCount {
            type1 := typeResolverValue.ResolveType(method1.ParameterTypes[index])
            type2 := typeResolverValue.ResolveType(method2.ParameterTypes[index])
            text1 := TypeDisplayText(type1)
            text2 := TypeDisplayText(type2)
            if text1 != text2 {
                return false
            }

            index = index + 1
        }

        returnType1 := ResolveDeclaredReturnType(method1)
        returnType2 := ResolveDeclaredReturnType(method2)
        returnText1 := TypeDisplayText(returnType1)
        returnText2 := TypeDisplayText(returnType2)
        return returnText1 == returnText2
    }

    // ASP.NET Core's `ActionResult<T>` accepts any value the non-generic `ActionResult` accepts. The
    // arm is a no-op unless the target is a one-argument `ActionResult` spelling, the source is a CLR
    // type, and the referenced assemblies actually carry `ActionResult`.
    func IsAspNetActionResultGenericAssignable(target: TypeInfo, source: TypeInfo): bool {
        targetGeneric := target as GenericTypeInfo
        if targetGeneric == null {
            return false
        }

        if targetGeneric.TypeArguments.Count != 1 {
            return false
        }

        name := targetGeneric.Name
        if name != "ActionResult" && name != "Microsoft.AspNetCore.Mvc.ActionResult" {
            return false
        }

        sourceReflection := source as ReflectionTypeInfo
        if sourceReflection == null {
            return false
        }

        probed := externalTypeProbeValue.ResolveExternalType("Microsoft.AspNetCore.Mvc.ActionResult")
        actionResult := probed as ReflectionTypeInfo
        if actionResult == null {
            return false
        }

        return AnalyzerConversionFacts.IsReflectionAssignableFrom(actionResult.Type, sourceReflection.Type)
    }

    // A resolved type's own display form — the comparison key for signature equality. It is read
    // through an `object`-typed local because `ToString` is declared by the BASE of the TypeInfo
    // hierarchy rather than by the hierarchy itself.
    static func TypeDisplayText(resolved: TypeInfo): string {
        boxed: object = resolved
        return boxed.ToString()
    }

    // A declared member's return type, with an ABSENT one meaning `void`.
    func ResolveDeclaredReturnType(method: DeclaredMemberInfo): TypeInfo {
        declared := method.ReturnType
        if declared == null {
            return BuiltInTypes.Void
        }

        return typeResolverValue.ResolveType(declared)
    }

    // The declared-member list of the three declaration families that HAVE one; every other type
    // answers nothing, which is what makes it satisfy no duck interface at all.
    func GetDeclaredMembers(source: TypeInfo): DeclaredMemberInfo[]? {
        classType := source as ClassTypeInfo
        if classType != null {
            return classType.DeclaredMembers
        }

        structType := source as StructTypeInfo
        if structType != null {
            return structType.DeclaredMembers
        }

        recordType := source as RecordTypeInfo
        if recordType != null {
            return recordType.DeclaredMembers
        }

        return null
    }
}
