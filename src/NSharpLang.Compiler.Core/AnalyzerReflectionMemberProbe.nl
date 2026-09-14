namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection


// EVERY REFLECTION READ OVER A TYPE THE PROJECT MERELY REFERENCES, MADE LOAD-TOLERANT.
//
// A REFERENCED ASSEMBLY IS NOT A GUARANTEE THAT ITS WHOLE CLOSURE IS PRESENT. `System.Reactive`
// carries method signatures over WPF types, so its `WindowsBase` reference is real; on macOS that
// assembly does not exist. Nothing about that is a fault in the program being compiled — it is a
// reference the program never uses — but ANY read that materialises such a signature throws
// `FileNotFoundException`, and an exception out of a member walk ends the whole analysis with a
// sentence about an assembly the user never named.
//
// THE RULE IS STATED ONCE, HERE. Every read a scan performs over a type the analyzer does not own
// goes through this owner: enumerating an assembly's types, enumerating a type's methods or
// constructors, reading a method's parameters, reading a parameter's or a return's type, walking a
// base chain or an interface list. Each answers EMPTY or NULL where it cannot answer, and a
// candidate that cannot be read is simply not a candidate.
//
// IT IS NOT A BLANKET `try`. The reads here are the ones whose failure is a fact about the
// REFERENCE SET rather than about the call being resolved; the decisions above them are unchanged,
// and a type whose members read fine is scored exactly as before. Do not route a read of a SOURCE
// declaration through this owner — a failure there is a compiler fault and must not be swallowed.
//
// `ReflectionTypeLoadException` is caught with everything else deliberately. Its `Types` array holds
// the types that DID load, but a partially loaded assembly cannot be scanned consistently — the
// entry that failed may be exactly the extension host being looked for — so the whole assembly
// contributes nothing rather than a subset that depends on load order.
class AnalyzerReflectionMemberProbe {
    static func TypesOrEmpty(assembly: Assembly): Type[] {
        try {
            result := assembly.GetTypes()
            if result == null {
                return new Type[](0)
            }

            return result
        } catch {
            return new Type[](0)
        }
    }

    static func MethodsOrEmpty(owner: Type, memberFlags: BindingFlags): MethodInfo[] {
        try {
            result := owner.GetMethods(memberFlags)
            if result == null {
                return new MethodInfo[](0)
            }

            return result
        } catch {
            return new MethodInfo[](0)
        }
    }

    static func ConstructorsOrEmpty(owner: Type): ConstructorInfo[] {
        try {
            result := owner.GetConstructors()
            if result == null {
                return new ConstructorInfo[](0)
            }

            return result
        } catch {
            return new ConstructorInfo[](0)
        }
    }

    // A named method, or null when the type cannot answer for it. An AMBIGUOUS name is a null too:
    // `GetMethod` throws `AmbiguousMatchException` for an overload set, and this owner's callers all
    // want the single-`Invoke` shape a delegate has.
    static func MethodOrNull(owner: Type, name: string): MethodInfo? {
        try {
            return owner.GetMethod(name)
        } catch {
            return null
        }
    }

    static func ParametersOrNull(method: MethodBase): ParameterInfo[]? {
        try {
            return method.GetParameters()
        } catch {
            return null
        }
    }

    // A parameter's DECLARED type, and this is the read that actually throws: the parameter row
    // exists in metadata whatever its type resolves to, and only materialising it reaches the
    // missing assembly.
    static func ParameterTypeOrNull(parameter: ParameterInfo): Type? {
        try {
            return parameter.get_ParameterType()
        } catch {
            return null
        }
    }

    static func ReturnTypeOrNull(method: MethodInfo): Type? {
        try {
            return method.get_ReturnType()
        } catch {
            return null
        }
    }

    // Every parameter type of one method, or null when ANY of them cannot be read. A signature read
    // in half is not a signature: a candidate whose second parameter is unreadable must not be
    // matched on its first.
    static func ParameterTypesOrNull(method: MethodBase): Type[]? {
        parameters := ParametersOrNull(method)
        if parameters == null {
            return null
        }

        result := new Type[](parameters.Length)
        index := 0
        while index < parameters.Length {
            parameterType := ParameterTypeOrNull(parameters[index])
            if parameterType == null {
                return null
            }

            result[index] = parameterType
            index = index + 1
        }

        return result
    }

    static func InterfacesOrEmpty(candidate: Type): Type[] {
        try {
            result := candidate.GetInterfaces()
            if result == null {
                return new Type[](0)
            }

            return result
        } catch {
            return new Type[](0)
        }
    }

    static func BaseTypeOrNull(candidate: Type): Type? {
        try {
            return candidate.get_BaseType()
        } catch {
            return null
        }
    }

    static func NamespaceOrNull(candidate: Type): string? {
        try {
            return candidate.get_Namespace()
        } catch {
            return null
        }
    }

    // Whether the type is the `sealed abstract` shape a static class has. A type whose flags cannot
    // be read is not one.
    static func IsStaticHostType(candidate: Type): bool {
        try {
            return candidate.get_IsSealed() && candidate.get_IsAbstract()
        } catch {
            return false
        }
    }
}
