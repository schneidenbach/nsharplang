namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection


// A STATIC MEMBER OF A TYPE THIS COMPILATION DECLARES, on the plan side.
//
// `ColumnarExternalStaticMemberPlanner` answers `Environment.NewLine` and every other static that
// lives in a REFERENCED assembly; nothing answered `Counter.Total` where `Counter` is a class in the
// same program. The emitter has had that arm since the beginning (`_typeResolutionStructs` plus
// `ColumnarSourceMemberChainResolver`), so a plain body compiled and an ITERATOR body — which plans
// every value through the plan-IR — declined with `an iterator body value (node kind 8) could not
// be lowered`.
//
// The resolution here is the emitter's, through the SAME chain resolver: a static member belongs to
// the type that DECLARES it, so naming a derived type binds the base's declaration rather than
// giving it a second copy. The receiver may be the bare declaration name or the same name written
// with its namespace, and a ROOT shadowed by a value binding or a callable is not a type name at
// all — `models.Person.Default` is member lookup on a local named `models`.
//
// A FIELD BUILDER IS NOT A REFLECTED FIELD. The type it belongs to is still being built while the
// body that reads it is planned, so the handle enters the pool through `AddFieldWithSignature`
// (declaring type, value type and staticness stated by the definition) rather than through the
// reflection-reading `AddField`.
class ColumnarSourceStaticMemberPlanner {

    // Front-door gate: a one-child member access whose receiver spells a source TYPE.
    static func MayPlanRoot(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings): bool {
        owner: ColumnarStructDef? = null
        return TryResolveOwner(nodes, source, node, bindings, out owner)
    }

    // The read. A static INT CONSTANT is loaded as its literal exactly as the emitter loads it — the
    // field exists for metadata, but the value is known — and everything else is `ldsfld` for a field
    // or `call get_X` for a static property.
    static func TryAppendStaticMember(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out resultType: Type): bool {
        resultType = typeof(int)
        owner: ColumnarStructDef? = null
        if !TryResolveOwner(nodes, source, node, bindings, out owner) || owner == null {
            return false
        }

        memberName := nodes.Text(source, node)
        fieldOwner: ColumnarStructDef? = null
        field: FieldInfo? = null
        fieldType := typeof(object)
        if ColumnarSourceGenericStaticMemberFacts.TryBindChainStaticField(owner, memberName, out fieldOwner, out field, out fieldType) && field != null {
            literalValue := 0
            if fieldOwner != null && fieldOwner.StaticIntConstants.TryGetValue(memberName, out literalValue) {
                if !TryAppendIntConstant(plan, fieldType, literalValue) {
                    return false
                }
                resultType = fieldType
                return true
            }

            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldsfld(), AddStaticField(plan, field, fieldType))
            resultType = fieldType
            return true
        }

        getter: MethodInfo? = null
        setter: MethodInfo? = null
        propertyType := typeof(object)
        if ColumnarSourceGenericStaticMemberFacts.TryBindChainStaticProperty(owner, memberName, out getter, out setter, out propertyType) && getter != null {
            plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), plan.AddMethodWithSignature(getter, getter.DeclaringType, Type.EmptyTypes, propertyType, true, false))
            resultType = propertyType
            return true
        }

        return false
    }

    // The WRITE half, which is what `Counter.Total = Counter.Total + 1` inside a generator needs.
    // It is asked in TWO steps because the value comes first on the stack: the caller learns the
    // storage type, appends the value converted to it, and only then appends the store row. A static
    // INT CONSTANT has no storage a body may write, so both steps decline it.
    static func TryGetStaticStorageType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, out storageType: Type): bool {
        storageType = typeof(int)
        field: FieldInfo? = null
        setter: MethodInfo? = null
        if !TryResolveStaticStoreTarget(nodes, source, node, bindings, out field, out setter, out storageType) {
            storageType = typeof(int)
            return false
        }

        return true
    }

    // The store row itself, appended over a value already on the stack.
    static func TryAppendStaticStoreRow(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan): bool {
        field: FieldInfo? = null
        setter: MethodInfo? = null
        storageType := typeof(object)
        if !TryResolveStaticStoreTarget(nodes, source, node, bindings, out field, out setter, out storageType) {
            return false
        }
        if field != null {
            plan.AppendFieldInstruction(ColumnarCodePlanContract.Stsfld(), AddStaticField(plan, field, storageType))
            return true
        }

        bound := must setter
        parameterTypes := new Type[](1)
        parameterTypes[0] = storageType
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), plan.AddMethodWithSignature(bound, bound.DeclaringType, parameterTypes, ColumnarTypeOfPlanner.RequiredVoidType(), true, false))
        return true
    }

    // The one selection both write steps share, so the two can never disagree about what they are
    // writing to. Exactly one of `field` and `setter` comes back non-null, bound through the chain
    // binder, and `storageType` is the member's type as the named owner sees it.
    static func TryResolveStaticStoreTarget(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, out field: FieldInfo?, out setter: MethodInfo?, out storageType: Type): bool {
        field = null
        setter = null
        storageType = typeof(object)
        owner: ColumnarStructDef? = null
        if !TryResolveOwner(nodes, source, node, bindings, out owner) || owner == null {
            return false
        }

        memberName := nodes.Text(source, node)
        fieldOwner: ColumnarStructDef? = null
        if ColumnarSourceGenericStaticMemberFacts.TryBindChainStaticField(owner, memberName, out fieldOwner, out field, out storageType) && field != null {
            literalValue := 0
            if fieldOwner != null && fieldOwner.StaticIntConstants.TryGetValue(memberName, out literalValue) {
                field = null
                return false
            }

            return true
        }

        field = null
        getter: MethodInfo? = null
        if ColumnarSourceGenericStaticMemberFacts.TryBindChainStaticProperty(owner, memberName, out getter, out setter, out storageType) && setter != null {
            return true
        }

        setter = null
        storageType = typeof(object)
        return false
    }

    // THE ADDRESS of a static field of a source type, which is what a `ref`/`out`/`in` argument
    // naming `Counter.Total` needs. A static INT CONSTANT is a literal with no storage, so it is
    // refused here exactly as the write half refuses it; a static PROPERTY has no address either,
    // and declining leaves the caller's own diagnostic in place.
    static func TryAppendStaticFieldAddress(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out elementType: Type): bool {
        elementType = typeof(int)
        field: FieldInfo? = null
        fieldType := typeof(object)
        if !TryFindQualifiedStaticField(nodes, source, node, bindings, out field, out fieldType) || field == null {
            return false
        }

        plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldsflda(), AddStaticField(plan, field, fieldType))
        elementType = fieldType
        return true
    }

    // The type half of the same selection, so the argument type a call binds and the storage it
    // addresses are answered by one relation.
    static func TryGetStaticFieldStorageType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, out storageType: Type?): bool {
        storageType = null
        field: FieldInfo? = null
        fieldType := typeof(object)
        if !TryFindQualifiedStaticField(nodes, source, node, bindings, out field, out fieldType) || field == null {
            return false
        }

        storageType = fieldType
        return true
    }

    static func TryFindQualifiedStaticField(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, out field: FieldInfo?, out fieldType: Type): bool {
        field = null
        fieldType = typeof(object)
        owner: ColumnarStructDef? = null
        if !TryResolveOwner(nodes, source, node, bindings, out owner) || owner == null {
            return false
        }

        return TryBindStorageStaticField(owner, nodes.Text(source, node), out field, out fieldType)
    }

    // A static FIELD with storage, named through `owner`: bound by the chain binder, and refused when
    // it is a `const`, which has a value but no storage to load from, store to or address.
    static func TryBindStorageStaticField(owner: ColumnarStructDef, memberName: string, out field: FieldInfo?, out fieldType: Type): bool {
        fieldOwner: ColumnarStructDef? = null
        if !ColumnarSourceGenericStaticMemberFacts.TryBindChainStaticField(owner, memberName, out fieldOwner, out field, out fieldType) || field == null {
            field = null
            fieldType = typeof(object)
            return false
        }

        literalValue := 0
        if fieldOwner != null && fieldOwner.StaticIntConstants.TryGetValue(memberName, out literalValue) {
            field = null
            fieldType = typeof(object)
            return false
        }

        return true
    }

    // A source field's declaring and value types are stated by the binder, which is what the pool
    // needs: reading them back through reflection off an unbaked type is exactly the question
    // `AddFieldWithSignature` exists to avoid asking. A field bound onto a constructed base names that
    // instantiation as its declaring type and reports the base's substituted member type.
    static func AddStaticField(plan: ColumnarCodePlan, field: FieldInfo, fieldType: Type): int {
        declaringType := field.DeclaringType
        if declaringType == null {
            throw new InvalidOperationException("A source static field has no declaring type.")
        }

        return plan.AddFieldWithSignature(field, declaringType, fieldType, true)
    }

    // Does this member access name a static of a source type? The receiver is a bare identifier or a
    // dotted name, and its ROOT must not be shadowed by anything nearer — a value binding, a callable
    // or an enum name all win over a type spelling.
    static func TryResolveOwner(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, out owner: ColumnarStructDef?): bool {
        owner = null
        if nodes == null || source == null || bindings == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }
        if nodes.Kind(node) != ColumnarExpressionNodeKind.MemberAccessExpression || nodes.ChildCount(node) != 1 {
            return false
        }

        ownerName := ""
        rootName := ""
        if !ColumnarPlannerSupport.TryGetQualifiedName(nodes, source, nodes.Child(node, 0), 0, true, out ownerName, out rootName) {
            return false
        }
        if bindings.IsValueBinding(rootName) || bindings.IsCallable(rootName) || bindings.Enums.ContainsKey(ownerName) || bindings.Enums.ContainsKey(rootName) {
            return false
        }

        return TryFindDefinition(bindings, ownerName, out owner)
    }

    // ONE declaration, selected by name and deduplicated by identity — registry aliases may expose
    // the same definition more than once, and two DIFFERENT declarations sharing a name is an
    // ambiguity this owner refuses rather than guesses at.
    //
    // A declaration's own name may carry its namespace while the SOURCE writes the simple one, so a
    // written name matches a declared name it EQUALS or that ends with `.` + it. That is the same
    // relation an import gives a type reference; it is asked at a dot boundary so `Counter` never
    // matches `RowCounter`.
    static func TryFindDefinition(bindings: ColumnarFragmentBindings, name: string, out owner: ColumnarStructDef?): bool {
        owner = null
        if name == null || name.Length == 0 || bindings.SourceTypeDefinitions == null {
            return false
        }

        found := 0
        for definition in bindings.SourceTypeDefinitions {
            if definition != null && NamesDeclaration(definition.DeclaredTypeName, name) {
                if owner == null {
                    owner = definition
                    found = 1
                } else {
                    if !Object.ReferenceEquals(owner, definition) {
                        found = found + 1
                    }
                }
            }
        }

        if found != 1 {
            owner = null
            return false
        }

        return true
    }

    static func NamesDeclaration(declaredName: string?, writtenName: string): bool {
        if declaredName == null || declaredName.Length == 0 {
            return false
        }
        if declaredName == writtenName {
            return true
        }
        if declaredName.Length <= writtenName.Length + 1 {
            return false
        }

        return declaredName[declaredName.Length - writtenName.Length - 1] == '.' && declaredName.EndsWith(writtenName, StringComparison.Ordinal)
    }

    // A static int constant's LOAD, over the same integral widths the field metadata emitter admits.
    static func TryAppendIntConstant(plan: ColumnarCodePlan, fieldType: Type, value: int): bool {
        if fieldType == typeof(int) || fieldType == typeof(short) || fieldType == typeof(byte) || fieldType == typeof(sbyte) || fieldType == typeof(ushort) || fieldType == typeof(uint) || fieldType == typeof(char) {
            plan.AppendInt32Instruction(ColumnarCodePlanContract.LdcI4(), plan.AddInt32(value))
            return true
        }

        return false
    }
}
