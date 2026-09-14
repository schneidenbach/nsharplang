namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection


// THE LIVE SEMANTIC FACTS AN ITERATOR BODY NEEDS TO PLAN AN ORDINARY EXPRESSION.
//
// A `func*` body is an ordinary function body. The ONLY thing the state machine changes about it is
// where its name bindings LIVE: a parameter and a local become fields of the machine instead of an
// argument slot and a local slot. Everything else — which overload a call selects, which conversion a
// value needs, what an array literal costs — is the same question an ordinary body asks, and it has
// exactly one owner: `ColumnarRangeIndexPlanner`'s append-mode value cascade and the planners behind
// it — the same owner a call ARGUMENT reaches. This bundle is what the emission host routes so the
// iterator can ASK that owner instead of carrying a second, smaller copy of the answer.
//
// Every field here is the same live map the ordinary body path hands `ColumnarFragmentBindings`; none
// of them is iterator-specific, and none of them is a table of admitted shapes.
class ColumnarIteratorBodyFacts {
    Enums: Dictionary<string, ColumnarEnumDef>
    StructDefinitions: IEnumerable<ColumnarStructDef>
    UnionDefinitions: IEnumerable<ColumnarUnionDef>
    ExactSourceTypes: Dictionary<string, Type>
    SiblingCallables: Dictionary<string, ColumnarSiblingCallFacts>
    SiblingNames: IEnumerable<string>
    EnclosingTypeDefinition: ColumnarStructDef?
    StructuralTypeReferences: ColumnarStructuralTypeReferenceTable

    constructor(
        enums: Dictionary<string, ColumnarEnumDef>,
        structDefinitions: IEnumerable<ColumnarStructDef>,
        unionDefinitions: IEnumerable<ColumnarUnionDef>,
        exactSourceTypes: Dictionary<string, Type>,
        siblingCallables: Dictionary<string, ColumnarSiblingCallFacts>,
        siblingNames: IEnumerable<string>,
        enclosingTypeDefinition: ColumnarStructDef?,
        structuralTypeReferences: ColumnarStructuralTypeReferenceTable
    ) {
        if enums == null || structDefinitions == null || unionDefinitions == null || exactSourceTypes == null || siblingCallables == null || siblingNames == null || structuralTypeReferences == null {
            throw new InvalidOperationException("Iterator body facts cannot be null.")
        }
        Enums = enums
        StructDefinitions = structDefinitions
        UnionDefinitions = unionDefinitions
        ExactSourceTypes = exactSourceTypes
        SiblingCallables = siblingCallables
        SiblingNames = siblingNames
        EnclosingTypeDefinition = enclosingTypeDefinition
        StructuralTypeReferences = structuralTypeReferences
    }

    // The live emission facts of one program, in the shape the fragment-binding contract wants them.
    // Sibling call facts are derived from the same definitions the ordinary body path derives them from,
    // so a call to a top-level function resolves identically inside and outside a `func*`.
    static func FromEmissionFacts(
        enums: Dictionary<string, ColumnarEnumDef>,
        structs: IReadOnlyDictionary<string, ColumnarStructDef>,
        unions: IReadOnlyDictionary<string, ColumnarUnionDef>,
        siblings: IReadOnlyDictionary<string, ColumnarSiblingMethodDefinition>,
        exactSourceTypes: Dictionary<string, Type>,
        enclosingTypeDefinition: ColumnarStructDef?,
        structuralTypeReferences: ColumnarStructuralTypeReferenceTable
    ): ColumnarIteratorBodyFacts {
        structDefinitions := new List<ColumnarStructDef>()
        for entry in structs {
            structDefinitions.Add(entry.Value)
        }
        unionDefinitions := new List<ColumnarUnionDef>()
        for entry in unions {
            unionDefinitions.Add(entry.Value)
        }
        callables := new Dictionary<string, ColumnarSiblingCallFacts>(StringComparer.Ordinal)
        names := new List<string>()
        for entry in siblings {
            sibling := entry.Value
            callables[entry.Key] = new ColumnarSiblingCallFacts(
                sibling.Method,
                sibling.ParamTypes,
                sibling.ParamModifierKinds,
                sibling.ReturnType,
                sibling.TypeParams.Length,
                sibling.ParamNames,
                sibling.ParamDefaultKinds,
                sibling.ParamDefaultTexts
            )
            names.Add(entry.Key)
        }
        return new ColumnarIteratorBodyFacts(
            enums,
            structDefinitions,
            unionDefinitions,
            exactSourceTypes,
            callables,
            names,
            enclosingTypeDefinition,
            structuralTypeReferences
        )
    }

    // A body with no source declarations, no siblings and no enclosing type: the facts a machine that
    // only ever reads its own fields and the BCL needs. Contract sources that exercise the machinery
    // rather than a program's declarations build this rather than a stub registry.
    static func Empty(structuralTypeReferences: ColumnarStructuralTypeReferenceTable): ColumnarIteratorBodyFacts {
        return new ColumnarIteratorBodyFacts(
            new Dictionary<string, ColumnarEnumDef>(StringComparer.Ordinal),
            new ColumnarStructDef[](0),
            new ColumnarUnionDef[](0),
            new Dictionary<string, Type>(StringComparer.Ordinal),
            new Dictionary<string, ColumnarSiblingCallFacts>(StringComparer.Ordinal),
            new string[](0),
            null,
            structuralTypeReferences
        )
    }
}

// THE STATE-MACHINE REWRITE OF A BODY'S NAME BINDINGS, AND THE ONE DOOR ITERATOR LOWERING USES FOR AN
// EXPRESSION.
//
// The rewrite is two lines of the binding contract, not a planner:
//
//   a HOISTED NAME (a captured parameter, a hoisted local, a synthesized loop slot) becomes a FIELD OF
//   `this`, which is the sole identifier owner's CurrentField selection — `ldarg.0; ldfld` — exactly
//   what the machine wants;
//
//   an ENCLOSING-TYPE MEMBER read by an instance machine becomes the CapturedInstanceField selection —
//   `ldarg.0; ldfld <>__this; ldfld <member>` — which is the same two-hop read a closure display does
//   through the box it captured.
//
// With those two published, `ColumnarMethodBodyPlanner.TryAppendValue` plans a call, a `new`, an array
// literal, an indexer, a member access or a binary inside a `func*` body by the SAME rows it appends in
// an ordinary body, and the iterator owns none of that decision.
class ColumnarIteratorBodyScope {
    StateMachineType: Type
    Facts: ColumnarIteratorBodyFacts
    Bindings: ColumnarFragmentBindings
    instanceFacts: ColumnarCurrentInstanceFacts

    constructor(stateMachineType: Type, facts: ColumnarIteratorBodyFacts, bindings: ColumnarFragmentBindings, instanceFacts: ColumnarCurrentInstanceFacts) {
        StateMachineType = stateMachineType
        Facts = facts
        Bindings = bindings
        this.instanceFacts = instanceFacts
    }

    // `stateMachineType` is the SAME handle the MoveNext plan pools as argument 0 — a closed generic
    // instantiation for a generic machine — so the identifier owner's `GetOrAddArgument` reuses that
    // pool row instead of adding a conflicting one.
    static func Create(stateMachineType: Type, facts: ColumnarIteratorBodyFacts, typeParameters: Dictionary<string, Type>?): ColumnarIteratorBodyScope {
        return Create(stateMachineType, facts, typeParameters, new Dictionary<string, int>(StringComparer.Ordinal), new Dictionary<string, Type>(StringComparer.Ordinal))
    }

    // THE SAME SCOPE, FOR A METHOD THAT ALSO HAS ARGUMENTS OF ITS OWN. A lambda in a generator body
    // becomes an INSTANCE METHOD on the state machine — the machine already holds every name the body
    // binds, so it already IS the closure's display — and that method's own parameters are ordinary
    // arguments 1..n beside the machine at argument 0. Nothing else about the body changes: the same
    // fields, the same enclosing members, the same one expression door.
    static func Create(stateMachineType: Type, facts: ColumnarIteratorBodyFacts, typeParameters: Dictionary<string, Type>?, parameterOrdinals: Dictionary<string, int>, parameterTypes: Dictionary<string, Type>): ColumnarIteratorBodyScope {
        if stateMachineType == null || facts == null || parameterOrdinals == null || parameterTypes == null {
            throw new InvalidOperationException("An iterator body scope requires a state-machine type and its body facts.")
        }

        parameters := typeParameters
        if parameters == null {
            parameters = new Dictionary<string, Type>(StringComparer.Ordinal)
        }

        emptyNames := new string[](0)
        bindings := ColumnarFragmentBindings.FromRawFacts(
            parameterOrdinals,
            parameterTypes,
            new Dictionary<string, LocalBuilder>(StringComparer.Ordinal),
            facts.Enums,
            new Dictionary<string, (Box: LocalBuilder, ValueType: Type)>(StringComparer.Ordinal),
            new Dictionary<string, (BoxField: FieldInfo, ValueType: Type)>(StringComparer.Ordinal),
            null,
            facts.StructDefinitions,
            facts.UnionDefinitions,
            new Dictionary<string, string[]>(StringComparer.Ordinal),
            new Dictionary<string, string>(StringComparer.Ordinal),
            emptyNames,
            facts.SiblingNames,
            emptyNames,
            parameters,
            facts.StructuralTypeReferences
        )
        bindings.ExactSourceTypes = facts.ExactSourceTypes
        bindings.SiblingCallables = facts.SiblingCallables
        bindings.SetEnclosingTypeDefinition(facts.EnclosingTypeDefinition)

        // The machine is a CLASS, so the receiver is loaded by value; the runtime-facts mode of the
        // current-instance contract is what a synthesized type uses — there is no `ColumnarStructDef`
        // for a state machine and inventing one would be a second definition of the same fields.
        instanceFacts := new ColumnarCurrentInstanceFacts(stateMachineType, true)
        bindings.CurrentInstance = instanceFacts
        return new ColumnarIteratorBodyScope(stateMachineType, facts, bindings, instanceFacts)
    }

    // One hoisted field becomes visible to the body's own code. Publishing happens as the lowering
    // REACHES each declaration, so a name is readable exactly where source scoping says it is.
    func PublishField(name: string, field: FieldInfo) {
        if name == null || name.Length == 0 || field == null {
            throw new InvalidOperationException("A published iterator field requires a name and an exact field handle.")
        }
        instanceFacts.Fields[name] = field
    }

    func HasField(name: string): bool {
        return instanceFacts.Fields.ContainsKey(name)
    }

    func FieldHandle(name: string): FieldInfo {
        field: FieldInfo? = null
        if !instanceFacts.Fields.TryGetValue(name, out field) || field == null {
            throw new InvalidOperationException("The iterator body scope has no published field named '" + name + "'.")
        }
        return field
    }

    // An enclosing-type member an INSTANCE machine reads through its captured receiver. The captured
    // `<>__this` field is the box; the member field is the value — the BoxedCapture selection verbatim.
    func PublishEnclosingMember(name: string, capturedReceiverField: FieldInfo, memberField: FieldInfo) {
        if name == null || name.Length == 0 || capturedReceiverField == null || memberField == null {
            throw new InvalidOperationException("A published enclosing member requires a captured receiver field and the member's exact field handle.")
        }
        Bindings.CapturedInstanceFields[name] = (ReceiverField: capturedReceiverField, MemberField: memberField)
    }

    // THE EXPRESSION DOOR. One call, one owner: `ColumnarRangeIndexPlanner`'s append-mode value
    // cascade — the same entry a CALL ARGUMENT uses, which is the general "any plannable value in a
    // non-root position" owner and the one `ColumnarMethodBodyPlanner`'s own door reaches for every
    // composite it claims. A value inside a `func*` body is exactly that: an ordinary value written at
    // a position with no target-typed pre-pass, so it takes the same cascade and produces the same
    // rows. Literals, identifiers, member access, calls, `new`, object initializers, array and
    // collection literals, indexers, casts, ranges, ternaries and binaries all answer there.
    //
    // A method body plan admits a new ROOT fragment between trees (`ColumnarCodePlan.BeginFragment`),
    // which is what lets the cascade's fragment discipline hold inside a flat v4 stream.
    func TryAppendValue(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan, out resultType: Type): bool {
        return ColumnarRangeIndexPlanner.TryAppendConstructionValue(nodes, source, node, Bindings, ColumnarRangeIndexHandles.Resolve(), plan, -1, 0, out resultType)
    }

    // THE TYPE OF A VALUE, DISCOVERED BY PLANNING IT AND THROWING THE ROWS AWAY. A hoisted local's CLR
    // field cannot be defined until its initializer's type is known, and the initializer's type is
    // whatever the one expression owner says it is — so the scratch is the same append into a plan
    // nobody executes, the pattern `ColumnarDirectCallPlanner` and `ColumnarConstructionPlanner`
    // already use to type an argument before they commit to it.
    func TryDiscoverValueType(nodes: ColumnarNodeTable, source: string, node: int, out resultType: Type): bool {
        resultType = typeof(int)
        scratch := new ColumnarCodePlan()
        scratch.PrepareMethodBody()
        if !TryAppendValue(nodes, source, node, scratch, out resultType) {
            return false
        }
        return !ColumnarCodePlanExecutor.IsVoidType(resultType)
    }

    // A value at a position whose type is known — a hoisted field, the current field a `yield` writes.
    // Target-typed forms (an array literal whose elements only agree because the position says so) are
    // planned against that type by the construction owner; everything else is the ordinary cascade plus
    // the same conversion a call argument takes.
    func TryAppendTargetTypedValue(nodes: ColumnarNodeTable, source: string, node: int, plan: ColumnarCodePlan, targetType: Type): bool {
        return ColumnarConstructionPlanner.TryAppendTargetTypedValue(nodes, source, node, Bindings, ColumnarRangeIndexHandles.Resolve(), plan, -1, 0, targetType)
    }

    // The conversion a value needs to reach a storage location — a hoisted field, the current field a
    // `yield` writes — routed to the ONE argument-conversion owner rather than restated. Identity,
    // reference upcast, boxing, nullable lift, constructed and user-implicit conversions all answer
    // here exactly as they do for a call argument.
    func TryAppendStorageConversion(plan: ColumnarCodePlan, actualType: Type, storageType: Type): bool {
        return ColumnarDirectCallPlanner.AppendArgumentConversion(plan, actualType, storageType, Facts.StructDefinitions)
    }
}
