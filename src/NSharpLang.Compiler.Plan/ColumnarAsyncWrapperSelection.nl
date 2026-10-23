namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Threading.Tasks
import NSharpLang.Compiler


// THE TASK AN UNANNOTATED `async` METHOD RETURNS WHEN IT FILLS A .NET SLOT.
//
// `TryComputeAsyncReturnShape` wraps an unannotated async body in the project's
// `language.asyncDefaultType`. A slot is matched by its EXACT return type, so
// `override async func ExecuteAsync(token: CancellationToken)` over `BackgroundService` — whose slot
// returns `Task` — took no slot at all under the `ValueTask` default, and the declaration declined
// with "no overridable base member matches 'ExecuteAsync'". The analyzer types the member with the
// slot's family (`AnalyzerAsyncReturnFamily`); this is the emitter's half of the same rule.
//
// IT ASKS THE SLOT MATCHERS THEMSELVES, NOT A COPY OF THEM. The member is offered to exactly the
// matchers its declaration is about to be registered with — `ColumnarBaseMethodMatch` and
// `ColumnarSourceBaseMethodMatch` for an `override`, the source, closed-source and external interface
// resolvers (through a scratch `ColumnarMethodOverrideDeclaration`) for everything else — first in
// the project's family and then in the other one. The project's family wins whenever any slot takes
// it; the other family is chosen only when a slot takes it AND none takes the default. A member
// neither family fits keeps the default, and its fault is reported where it always was.
class ColumnarAsyncWrapperSelection {
    static func Select(
        definition: ColumnarStructDef,
        memberName: string,
        requestsBaseOverride: bool,
        explicitInterface: Type?,
        inner: Type,
        defaultWrapped: Type,
        parameterTypes: Type[],
        sourceDefinitions: IEnumerable<ColumnarStructDef>,
        table: ColumnarStructuralTypeReferenceTable
    ): Type {
        if SlotAccepts(definition, memberName, requestsBaseOverride, explicitInterface, defaultWrapped, parameterTypes, sourceDefinitions, table) {
            return defaultWrapped
        }

        alternate := ColumnarInterfaceRealization.WrapInFamily(inner, OtherFamily(defaultWrapped))
        if SlotAccepts(definition, memberName, requestsBaseOverride, explicitInterface, alternate, parameterTypes, sourceDefinitions, table) {
            return alternate
        }

        return defaultWrapped
    }

    static func OtherFamily(wrapped: Type): AsyncTaskFamily {
        if wrapped == typeof(Task) {
            return AsyncTaskFamily.ValueTask
        }
        if wrapped.IsGenericType && wrapped.GetGenericTypeDefinition() == typeof(Task<int>).GetGenericTypeDefinition() {
            return AsyncTaskFamily.ValueTask
        }

        return AsyncTaskFamily.Task
    }

    static func SlotAccepts(
        definition: ColumnarStructDef,
        memberName: string,
        requestsBaseOverride: bool,
        explicitInterface: Type?,
        returnType: Type,
        parameterTypes: Type[],
        sourceDefinitions: IEnumerable<ColumnarStructDef>,
        table: ColumnarStructuralTypeReferenceTable
    ): bool {
        if requestsBaseOverride {
            externalBase := new ColumnarBaseMethodMatch(definition.ExactBaseType, memberName, returnType, parameterTypes)
            if externalBase.Matched {
                return true
            }

            sourceBase := new ColumnarSourceBaseMethodMatch(definition.BaseDef, memberName, returnType, parameterTypes)
            return sourceBase.Matched
        }

        probe := new ColumnarMethodOverrideDeclaration(0, false, definition.DeclaredTypeName, memberName, "", new string[](0))
        if explicitInterface != null {
            ColumnarExplicitInterfaceImplementation.AddNamedInterfaceTargets(
                probe,
                definition,
                explicitInterface,
                ExplicitInterfaceMemberFacts.SimpleNameOf(memberName),
                returnType,
                parameterTypes,
                table
            )
        } else {
            AddImplicitInterfaceTargets(probe, definition, memberName, returnType, parameterTypes, sourceDefinitions, table)
        }

        return probe.SourceTargetCount + probe.ExternalTargetCount > 0
    }

    // EVERY INTERFACE SLOT AN IMPLICIT IMPLEMENTATION CAN FILL, in the emitter's registration order:
    // the source interfaces the type implements, the closed constructions of generic source
    // interfaces, then the external interfaces. The declaration walk registers its real targets
    // through this same function, so a probe and a registration cannot see different slots.
    static func AddImplicitInterfaceTargets(
        declaration: ColumnarMethodOverrideDeclaration,
        definition: ColumnarStructDef,
        memberName: string,
        returnType: Type,
        parameterTypes: Type[],
        sourceDefinitions: IEnumerable<ColumnarStructDef>,
        table: ColumnarStructuralTypeReferenceTable
    ) {
        for implementedInterface in definition.ImplementedInterfaces {
            implementedInterfaceBuilder: Type = implementedInterface.Builder
            if implementedInterfaceBuilder.IsGenericTypeDefinition {
                continue
            }
            declaration.TryAddSourceInterfaceTarget(
                implementedInterface,
                memberName,
                returnType,
                parameterTypes,
                table,
                definition.ExplicitInterfaceTargetMethods
            )
        }
        for implementedInterfaceType in definition.ImplementedInterfaceTypes {
            if !implementedInterfaceType.IsGenericType || implementedInterfaceType.IsGenericTypeDefinition {
                continue
            }
            implementedInterfaceDef: ColumnarStructDef? = null
            if !ColumnarSourceDefinitionResolver.TryResolveInterface(implementedInterfaceType, sourceDefinitions, out implementedInterfaceDef) || implementedInterfaceDef == null {
                continue
            }
            declaration.TryAddClosedSourceInterfaceTarget(
                implementedInterfaceType,
                implementedInterfaceDef,
                memberName,
                returnType,
                parameterTypes,
                table,
                definition.ExplicitInterfaceTargetMethods
            )
        }
        ColumnarExternalInterfaceMethodResolver.AddMatchingTargets(
            declaration,
            definition.ExternalInterfaces,
            memberName,
            returnType,
            parameterTypes,
            table,
            ColumnarExternalInterfaceMethodMatch.EmptyTypeParameters(),
            definition.ExplicitInterfaceTargetMethods
        )
    }
}
