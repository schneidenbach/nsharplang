namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// THE CONSTRUCTORS OF AN EXTERNAL BASE, WHATEVER SHAPE THAT BASE IS.
//
// A source type may derive from a type this compilation did not write, and that base may be a
// GENERIC closed over a type this compilation IS writing: `class Catalogue: Collection<Item>` where
// `Item` is a source class. Reflection.Emit represents such a base as a `TypeBuilderInstantiation`,
// and every member query on one throws — `GetConstructors` answers
// "TypeBuilder generic instantiation does not support resolving members", which used to escape the
// whole `nlc check` as an unhandled exception. A crash is never an answer, and neither is declining
// a shape the CLR can express perfectly well.
//
// THE DEFINITION ANSWERS, AND THE INSTANTIATION IS WHAT IS EMITTED. `Collection<>` is a fully baked
// runtime type: it lists its constructors, their metadata defaults and their accessibility. Each
// candidate's signature is then re-expressed in the instantiation's own type arguments, and its
// handle is rebound onto the instantiation with `TypeBuilder.GetConstructor` — the one legal way to
// name a member of a builder-bound instantiation. A base with no builder-bound argument keeps
// answering directly, so nothing about the ordinary path moves.
//
// A REBOUND HANDLE ANSWERS NO QUESTION OF ITS OWN. `TypeBuilder.GetConstructor` returns a wrapper
// whose `GetParameters()` throws, so every signature fact a caller needs travels beside the handle
// rather than being read back off it.
class ColumnarExternalBaseConstructor {
    readonly handleValue: ConstructorInfo
    readonly parametersValue: ParameterInfo[]
    readonly parameterTypesValue: Type[]

    // The handle to emit `call` against.
    Handle: ConstructorInfo => handleValue

    // The declaring metadata parameters — where a parameter's own default value lives.
    Parameters: ParameterInfo[] => parametersValue

    // The parameter types expressed in the BASE'S OWN type arguments, one per metadata parameter.
    ParameterTypes: Type[] => parameterTypesValue

    constructor(handle: ConstructorInfo, parameters: ParameterInfo[], parameterTypes: Type[]) {
        if handle == null || parameters == null || parameterTypes == null || parameters.Length != parameterTypes.Length {
            throw new InvalidOperationException("An external base constructor must carry one type per metadata parameter.")
        }

        handleValue = handle
        parametersValue = parameters
        parameterTypesValue = parameterTypes
    }
}

class ColumnarExternalBaseConstructors {

    // WHICH TYPE ANSWERS MEMBER QUERIES FOR THIS BASE. Itself, unless it is an instantiation closed
    // over a type this compilation is writing — then its generic definition does.
    static func LookupType(baseType: Type): Type {
        if !IsBuilderBoundInstantiation(baseType) {
            return baseType
        }

        return baseType.GetGenericTypeDefinition()
    }

    static func IsBuilderBoundInstantiation(baseType: Type): bool {
        if baseType == null || !ColumnarTypeOfPlanner.ContainsBuilderBoundType(baseType) {
            return false
        }

        if !baseType.get_IsGenericType() || baseType.get_IsGenericTypeDefinition() {
            return false
        }

        return !(baseType.GetGenericTypeDefinition() is TypeBuilder)
    }

    // EVERY CONSTRUCTOR OF AN EXTERNAL BASE THIS ASSEMBLY MAY CALL. The emitted type lives in another
    // assembly, so `public`, `protected` and `protected internal` permit a derived constructor call
    // while `internal`, `private protected` and `private` do not — the ordinary declared-accessibility
    // relation, asked from a derived type in another assembly.
    static func Resolve(baseType: Type): List<ColumnarExternalBaseConstructor> {
        accessible := new List<ColumnarExternalBaseConstructor>()
        if baseType == null {
            return accessible
        }

        lookupType := LookupType(baseType)
        builderBound := !Object.ReferenceEquals(lookupType, baseType)
        arguments := builderBound ? baseType.GetGenericArguments() : Type.EmptyTypes
        flags := BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance
        constructors := lookupType.GetConstructors(flags)
        constructorIndex := 0
        while constructorIndex < constructors.Length {
            candidate := constructors[constructorIndex]
            constructorIndex = constructorIndex + 1
            if !IsReachableFromDerivedAssembly(candidate) {
                continue
            }

            parameters := candidate.GetParameters()
            parameterTypes := new Type[](parameters.Length)
            parameterIndex := 0
            while parameterIndex < parameters.Length {
                parameterType := parameters[parameterIndex].get_ParameterType()
                if builderBound {
                    parameterType = ColumnarRuntimeInstanceMemberResolver.SubstituteClosedTypeArguments(parameterType, arguments)
                }

                parameterTypes[parameterIndex] = parameterType
                parameterIndex = parameterIndex + 1
            }

            handle: ConstructorInfo = candidate
            if builderBound {
                handle = TypeBuilder.GetConstructor(baseType, candidate)
                if handle == null {
                    continue
                }
            }

            accessible.Add(new ColumnarExternalBaseConstructor(handle, parameters, parameterTypes))
        }

        return accessible
    }

    // The one an implicit `: base()` calls. `MemberAccessibility` owns the relation; the base is in a
    // referenced assembly, so the assembly half of every level is unsatisfiable.
    static func ResolveParameterless(baseType: Type): ConstructorInfo? {
        for candidate in Resolve(baseType) {
            if candidate.ParameterTypes.Length == 0 {
                return candidate.Handle
            }
        }

        return null
    }

    static func IsReachableFromDerivedAssembly(candidate: ConstructorInfo): bool {
        level := MemberAccessibility.LevelOfMethod(candidate)

        return MemberAccessibility.IsAccessible(level, false, true, true, false)
    }
}
