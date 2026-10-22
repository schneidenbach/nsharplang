namespace NSharpLang.Compiler

import System.Collections.Generic


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
// SIGNATURE EQUALITY IS SEMANTIC. Two members match when their names, arities, resolved parameter
// types and resolved return types have the same canonical TypeInfo identity. A
// member with NO declared return type is `void` — which is what makes `func F()` on a class satisfy
// `func F()` on the interface. The resolution ORDER is load-bearing and preserved: parameters are
// resolved in pairs, left to right, and the first mismatch stops the walk, so a later parameter of a
// member that already failed is never resolved and never recorded.
class AnalyzerStructuralAssignability {
    typeResolverValue: AnalyzerTypeResolver
    externalTypeProbeValue: AnalyzerExternalTypeProbe
    declarationContextValue: AnalyzerDeclarationContext?
    typeSubstitutionValue: AnalyzerTypeSubstitution?

    constructor(typeResolver: AnalyzerTypeResolver, externalTypeProbe: AnalyzerExternalTypeProbe, declarationContext: AnalyzerDeclarationContext? = null, typeSubstitution: AnalyzerTypeSubstitution? = null) {
        typeResolverValue = typeResolver
        externalTypeProbeValue = externalTypeProbe
        declarationContextValue = declarationContext
        typeSubstitutionValue = typeSubstitution
    }

    // True when `source` declares a matching function for every function the duck interface demands.
    func ImplementsDuckInterface(source: TypeInfo, duckInterface: InterfaceTypeInfo): bool {
        return ImplementsDuckInterfaceWithOwner(source, duckInterface, null, null)
    }

    // A constructed source duck interface keeps the open declaration as its generic definition and
    // carries the closed arguments separately. Resolve its contract members under that owner so
    // `IReader<int>` requires `Read(int)` while `IReader<string>` requires `Read(string)`.
    func ImplementsConstructedDuckInterface(source: TypeInfo, constructedInterface: GenericTypeInfo): bool {
        context := declarationContextValue
        substitutionFacts := typeSubstitutionValue
        if context == null || substitutionFacts == null {
            return false
        }

        definition := substitutionFacts.ResolveGenericDefinition(constructedInterface) as InterfaceTypeInfo
        if definition == null || !definition.IsDuckInterface {
            return false
        }

        substitution := context.CreateGenericSubstitution(definition, constructedInterface.TypeArguments)
        return ImplementsDuckInterfaceWithOwner(source, definition, definition, substitution)
    }

    func ImplementsDuckInterfaceWithOwner(source: TypeInfo, duckInterface: InterfaceTypeInfo, interfaceOwner: TypeInfo?, substitution: Dictionary<string, TypeInfo>?): bool {
        sourceMembers := GetDeclaredMembers(source)
        if sourceMembers == null {
            return false
        }

        interfaceMembers := duckInterface.DeclaredMembers
        for interfaceMember in interfaceMembers {
            if interfaceMember.Kind == DeclaredMemberKind.Function {
                found := false
                sourceIndex := 0
                while sourceIndex < sourceMembers.Length && !found {
                    sourceMember := sourceMembers[sourceIndex]
                    if sourceMember.Kind == DeclaredMemberKind.Function {
                        if MethodSignaturesMatchWithOwner(sourceMember, interfaceMember, interfaceOwner, substitution) {
                            found = true
                        }
                    }
                    sourceIndex = sourceIndex + 1
                }

                if !found {
                    return false
                }
            }
        }

        return true
    }

    // Name, arity, parameter types and return type — semantic type identities are compared after the
    // interface owner's closed generic substitution. Resolution remains in the original
    // left-to-right order so the effects of the resolution walk land exactly where they did before.
    func MethodSignaturesMatch(method1: DeclaredMemberInfo, method2: DeclaredMemberInfo): bool {
        return MethodSignaturesMatchWithOwner(method1, method2, null, null)
    }

    func MethodSignaturesMatchWithOwner(method1: DeclaredMemberInfo, method2: DeclaredMemberInfo, interfaceOwner: TypeInfo?, substitution: Dictionary<string, TypeInfo>?): bool {
        if method1.Name != method2.Name {
            return false
        }

        if method1.ParameterCount != method2.ParameterCount {
            return false
        }

        index := 0
        while index < method1.ParameterCount {
            type1 := typeResolverValue.ResolveType(method1.ParameterTypes[index])
            if interfaceOwner == null {
                type2 := typeResolverValue.ResolveType(method2.ParameterTypes[index])
                if !TypeInfoIdentityFacts.AreEqual(type1, type2) {
                    return false
                }
            } else {
                substitutionFacts := typeSubstitutionValue
                if substitutionFacts == null {
                    return false
                }

                type2 := substitutionFacts.ResolveTypeForSourceOwner(method2.ParameterTypes[index], interfaceOwner, substitution)
                if !TypeInfoIdentityFacts.AreEqual(type1, type2) {
                    return false
                }
            }

            index = index + 1
        }

        returnType1 := ResolveDeclaredReturnType(method1)
        if method2.ReturnType == null {
            return TypeInfoIdentityFacts.AreEqual(returnType1, BuiltInTypes.Void)
        }

        if interfaceOwner == null {
            returnType2 := typeResolverValue.ResolveType(method2.ReturnType)
            return TypeInfoIdentityFacts.AreEqual(returnType1, returnType2)
        }

        substitutionFacts := typeSubstitutionValue
        if substitutionFacts == null {
            return false
        }

        returnType2 := substitutionFacts.ResolveTypeForSourceOwner(method2.ReturnType, interfaceOwner, substitution)
        return TypeInfoIdentityFacts.AreEqual(returnType1, returnType2)
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
