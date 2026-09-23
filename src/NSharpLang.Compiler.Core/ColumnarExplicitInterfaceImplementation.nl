namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// THE BACKEND HALF OF AN EXPLICIT INTERFACE IMPLEMENTATION: WHICH INTERFACE THE QUALIFIER NAMES, AND
// WHICH SLOT THE MEMBER FILLS.
//
// `ExplicitInterfaceMemberFacts` owns the SPELLING — where the qualifier ends and what the CLR name
// is. This owns the two questions the backend has to answer about a real program: the written
// qualifier has to resolve to an interface THIS TYPE IMPLEMENTS, and the member has to be a SLOT of
// that interface. Neither may be guessed: a MethodImpl row naming a method the type does not
// implement emits a type the CLR refuses at LOAD, which is a runtime failure for a source mistake.
//
// **THE QUALIFIER IS RESOLVED AS A TYPE, not matched as a string**, and that is what makes a closed
// generic interface work. `IEnumerable<string>` goes through the same
// `ColumnarCanonicalTypeResolver` every annotation in the language goes through, so the type
// arguments are resolved by the compilation's own rules — including arguments that are SOURCE types —
// and the answer is compared to the implements closure by TYPE IDENTITY rather than by spelling. A
// qualifier that resolves to something this type does not implement is refused with the interface
// named, and so is one that resolves to a class.
//
// **ONLY THE NAMED INTERFACE'S SLOTS ARE OFFERED.** An explicit implementation is a statement about
// ONE interface; feeding the whole implements list to the target resolver would let
// `func IFoo.Ping()` fill `IBar`'s `Ping` slot as well, which is a different program from the one
// that was written.
class ColumnarExplicitInterfaceImplementation {

    // The interface the written qualifier names, resolved and checked against everything this type
    // implements — its external interfaces and their inherited closure, its source interfaces and
    // their bases, and its closed constructions over source interfaces.
    static func TryResolveNamedInterface(
        qualifier: string,
        owner: ColumnarStructDef,
        typeResolution: ColumnarSemanticTypeResolution,
        out namedInterface: Type
    ): bool {
        namedInterface = null
        candidate: Type? = null
        if !ColumnarCanonicalTypeResolver.TryResolveMemberType(qualifier, owner, typeResolution.Enums, typeResolution.Structs, typeResolution.Unions, out candidate) {
            return false
        }

        if candidate == null || !candidate.IsInterface {
            return false
        }

        if !ImplementsInterface(owner, candidate) {
            return false
        }

        namedInterface = candidate
        return true
    }

    static func ImplementsInterface(owner: ColumnarStructDef, candidate: Type): bool {
        for externalInterface in owner.ExternalInterfaces {
            for reachable in ColumnarExternalInterfaceMethodResolver.InterfaceRequirementClosure(externalInterface) {
                if ColumnarTypeEquivalenceFacts.TypesEquivalent(reachable, candidate) {
                    return true
                }
            }
        }

        for implementedInterfaceType in owner.ImplementedInterfaceTypes {
            if ColumnarTypeEquivalenceFacts.TypesEquivalent(implementedInterfaceType, candidate) {
                return true
            }
        }

        for implementedInterface in owner.ImplementedInterfaces {
            if SourceInterfaceReaches(implementedInterface, candidate, 0) {
                return true
            }
        }

        return false
    }

    // A source interface and everything it inherits. The depth bound is the same defence every
    // inheritance walk in this backend carries: a malformed closure must answer rather than recur.
    static func SourceInterfaceReaches(sourceInterface: ColumnarStructDef, candidate: Type, depth: int): bool {
        if depth > 16 {
            return false
        }

        sourceInterfaceBuilder: Type = sourceInterface.Builder
        if ColumnarTypeEquivalenceFacts.TypesEquivalent(sourceInterfaceBuilder, candidate) {
            return true
        }

        for inherited in sourceInterface.InterfaceBases {
            if SourceInterfaceReaches(inherited, candidate, depth + 1) {
                return true
            }
        }

        for externalInherited in sourceInterface.ExternalInterfaces {
            for reachable in ColumnarExternalInterfaceMethodResolver.InterfaceRequirementClosure(externalInherited) {
                if ColumnarTypeEquivalenceFacts.TypesEquivalent(reachable, candidate) {
                    return true
                }
            }
        }

        return false
    }

    // The MethodImpl targets for one explicit member, taken from the NAMED interface alone. The
    // member's SIMPLE name is what the slot is declared under — the qualification is the language's,
    // not the interface's.
    static func AddNamedInterfaceTargets(
        declaration: ColumnarMethodOverrideDeclaration,
        owner: ColumnarStructDef,
        namedInterface: Type,
        simpleName: string,
        returnType: Type,
        parameterTypes: Type[],
        table: ColumnarStructuralTypeReferenceTable
    ) {
        sourceInterfaceDefinition: ColumnarStructDef? = null
        if TryFindSourceInterface(owner, namedInterface, out sourceInterfaceDefinition) && sourceInterfaceDefinition != null {
            namedInterfaceForArity := namedInterface
            if namedInterfaceForArity.IsGenericType && !namedInterfaceForArity.IsGenericTypeDefinition {
                declaration.TryAddClosedSourceInterfaceTarget(
                    namedInterface,
                    sourceInterfaceDefinition,
                    simpleName,
                    returnType,
                    parameterTypes,
                    table
                )
                return
            }

            declaration.TryAddSourceInterfaceTarget(
                sourceInterfaceDefinition,
                simpleName,
                returnType,
                parameterTypes,
                table
            )
            return
        }

        namedOnly := new List<Type>()
        namedOnly.Add(namedInterface)
        ColumnarExternalInterfaceMethodResolver.AddMatchingTargets(
            declaration,
            namedOnly,
            simpleName,
            returnType,
            parameterTypes,
            table
        )
    }

    // THE INTERFACE'S ACCESSOR SLOT FOR AN EXPLICITLY IMPLEMENTED VALUE MEMBER.
    //
    // A value member is a PROPERTY in metadata and its slot is the accessor, so an explicit
    // implementation of one needs a MethodImpl row per accessor — the accessor's CLR name is
    // `Interface.get_Member`, which does not match the slot's `get_Member`, so nothing binds it by
    // name the way an implicit accessor is bound.
    //
    // A SOURCE interface keeps its value members in `Properties` and not in `Methods` (that is where
    // the value-member slice put them), so the accessor comes from there rather than from a method
    // lookup; a closed construction over one needs the handle rebound with `TypeBuilder.GetMethod`,
    // for the same reason every other closed source target does.
    static func TryResolveValueSlotAccessor(
        owner: ColumnarStructDef,
        namedInterface: Type,
        simpleName: string,
        wantSetter: bool,
        out slot: MethodInfo
    ): bool {
        slot = null
        sourceInterfaceDefinition: ColumnarStructDef? = null
        if TryFindSourceInterface(owner, namedInterface, out sourceInterfaceDefinition) && sourceInterfaceDefinition != null {
            accessors: ColumnarPropertyDef? = null
            if !sourceInterfaceDefinition.Properties.TryGetValue(simpleName, out accessors) || accessors == null {
                return false
            }

            candidate: MethodBuilder? = accessors.Getter
            if wantSetter {
                candidate = accessors.Setter
            }

            if candidate == null {
                return false
            }

            namedInterfaceForGenericCheck := namedInterface
            if namedInterfaceForGenericCheck.IsGenericType && !namedInterfaceForGenericCheck.IsGenericTypeDefinition {
                rebound := TypeBuilder.GetMethod(namedInterface, candidate)
                if rebound == null {
                    return false
                }

                reboundObject: object? = rebound
                slot = (MethodInfo)reboundObject
                return true
            }

            candidateObject: object? = candidate
            slot = (MethodInfo)candidateObject
            return true
        }

        accessorName := "get_" + simpleName
        if wantSetter {
            accessorName = "set_" + simpleName
        }

        reflected := namedInterface.GetMethod(accessorName, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
        if reflected == null {
            return false
        }

        slot = reflected
        return true
    }

    // The SOURCE definition behind a named interface, when the compilation is writing it. A closed
    // construction over a source interface resolves through the same resolver the emitter uses for the
    // implements list, so an open definition and a closed instantiation both find their definition.
    static func TryFindSourceInterface(owner: ColumnarStructDef, namedInterface: Type, out sourceInterface: ColumnarStructDef): bool {
        sourceInterface = null
        for implementedInterface in owner.ImplementedInterfaces {
            implementedInterfaceBuilder: Type = implementedInterface.Builder
            if ColumnarTypeEquivalenceFacts.TypesEquivalent(implementedInterfaceBuilder, namedInterface) {
                sourceInterface = implementedInterface
                return true
            }
        }

        namedInterfaceForGenericCheck := namedInterface
        if !namedInterfaceForGenericCheck.IsGenericType || namedInterfaceForGenericCheck.IsGenericTypeDefinition {
            return false
        }

        for implementedInterfaceType in owner.ImplementedInterfaceTypes {
            if !ColumnarTypeEquivalenceFacts.TypesEquivalent(implementedInterfaceType, namedInterface) {
                continue
            }

            resolvedDefinition: ColumnarStructDef? = null
            if ColumnarSourceDefinitionResolver.TryResolveInterface(implementedInterfaceType, StructDefinitionValues(owner), out resolvedDefinition) && resolvedDefinition != null {
                sourceInterface = resolvedDefinition
                return true
            }
        }

        return false
    }

    // The definitions a closed source interface is resolved against. The owner's own implements list
    // is the reachable set here: a closed construction over a source interface can only be one the
    // declaration wrote, and its definition is the one the declaration resolved.
    static func StructDefinitionValues(owner: ColumnarStructDef): List<ColumnarStructDef> {
        values := new List<ColumnarStructDef>()
        for implementedInterface in owner.ImplementedInterfaces {
            values.Add(implementedInterface)
        }
        return values
    }
}
