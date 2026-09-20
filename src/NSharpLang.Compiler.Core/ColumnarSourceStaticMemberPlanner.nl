namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection.Emit


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
        field: FieldBuilder? = null
        if ColumnarSourceMemberChainResolver.TryFindStaticFieldOnChain(owner, memberName, out fieldOwner, out field) && field != null {
            fieldType := field.get_FieldType()
            literalValue := 0
            if fieldOwner != null && fieldOwner.StaticIntConstants.TryGetValue(memberName, out literalValue) {
                if !TryAppendIntConstant(plan, fieldType, literalValue) {
                    return false
                }
                resultType = fieldType
                return true
            }

            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldsfld(), AddStaticField(plan, fieldOwner, field))
            resultType = fieldType
            return true
        }

        property: ColumnarPropertyDef? = null
        if ColumnarSourceMemberChainResolver.TryFindStaticPropertyOnChain(owner, memberName, out property) && property != null {
            getter := ColumnarSourceSelfInstantiation.Bind(property.Getter)
            plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), plan.AddMethodWithSignature(getter, getter.get_DeclaringType(), Type.EmptyTypes, property.PropertyType, true, false))
            resultType = property.PropertyType
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
        field: FieldBuilder? = null
        fieldOwner: ColumnarStructDef? = null
        property: ColumnarPropertyDef? = null
        if !TryResolveStaticStoreTarget(nodes, source, node, bindings, out fieldOwner, out field, out property) {
            return false
        }
        if field != null {
            storageType = field.get_FieldType()
            return true
        }

        storageType = property.PropertyType
        return true
    }

    // The store row itself, appended over a value already on the stack.
    static func TryAppendStaticStoreRow(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan): bool {
        field: FieldBuilder? = null
        fieldOwner: ColumnarStructDef? = null
        property: ColumnarPropertyDef? = null
        if !TryResolveStaticStoreTarget(nodes, source, node, bindings, out fieldOwner, out field, out property) {
            return false
        }
        if field != null {
            plan.AppendFieldInstruction(ColumnarCodePlanContract.Stsfld(), AddStaticField(plan, fieldOwner, field))
            return true
        }

        bound := ColumnarSourceSelfInstantiation.Bind(property.Setter)
        parameterTypes := new Type[](1)
        parameterTypes[0] = property.PropertyType
        plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), plan.AddMethodWithSignature(bound, bound.get_DeclaringType(), parameterTypes, ColumnarTypeOfPlanner.RequiredVoidType(), true, false))
        return true
    }

    // The one selection both write steps share, so the two can never disagree about what they are
    // writing to. Exactly one of `field` and `property` comes back non-null.
    static func TryResolveStaticStoreTarget(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, out fieldOwner: ColumnarStructDef?, out field: FieldBuilder?, out property: ColumnarPropertyDef?): bool {
        fieldOwner = null
        field = null
        property = null
        owner: ColumnarStructDef? = null
        if !TryResolveOwner(nodes, source, node, bindings, out owner) || owner == null {
            return false
        }

        memberName := nodes.Text(source, node)
        if ColumnarSourceMemberChainResolver.TryFindStaticFieldOnChain(owner, memberName, out fieldOwner, out field) && field != null {
            literalValue := 0
            if fieldOwner != null && fieldOwner.StaticIntConstants.TryGetValue(memberName, out literalValue) {
                field = null
                fieldOwner = null
                return false
            }

            return true
        }

        field = null
        fieldOwner = null
        if ColumnarSourceMemberChainResolver.TryFindStaticPropertyOnChain(owner, memberName, out property) && property != null && property.Setter != null {
            return true
        }

        property = null
        return false
    }

    // THE ADDRESS of a static field of a source type, which is what a `ref`/`out`/`in` argument
    // naming `Counter.Total` needs. A static INT CONSTANT is a literal with no storage, so it is
    // refused here exactly as the write half refuses it; a static PROPERTY has no address either,
    // and declining leaves the caller's own diagnostic in place.
    static func TryAppendStaticFieldAddress(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, plan: ColumnarCodePlan, out elementType: Type): bool {
        elementType = typeof(int)
        fieldOwner: ColumnarStructDef? = null
        field: FieldBuilder? = null
        if !TryFindQualifiedStaticField(nodes, source, node, bindings, out fieldOwner, out field) || field == null {
            return false
        }

        plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldsflda(), AddStaticField(plan, fieldOwner, field))
        elementType = field.get_FieldType()
        return true
    }

    // The type half of the same selection, so the argument type a call binds and the storage it
    // addresses are answered by one relation.
    static func TryGetStaticFieldStorageType(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, out storageType: Type?): bool {
        storageType = null
        fieldOwner: ColumnarStructDef? = null
        field: FieldBuilder? = null
        if !TryFindQualifiedStaticField(nodes, source, node, bindings, out fieldOwner, out field) || field == null {
            return false
        }

        storageType = field.get_FieldType()
        return true
    }

    static func TryFindQualifiedStaticField(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, out fieldOwner: ColumnarStructDef?, out field: FieldBuilder?): bool {
        fieldOwner = null
        field = null
        owner: ColumnarStructDef? = null
        if !TryResolveOwner(nodes, source, node, bindings, out owner) || owner == null {
            return false
        }

        memberName := nodes.Text(source, node)
        selectedOwner: ColumnarStructDef? = null
        selectedField: FieldBuilder? = null
        if !ColumnarSourceMemberChainResolver.TryFindStaticFieldOnChain(owner, memberName, out selectedOwner, out selectedField) || selectedField == null {
            return false
        }

        literalValue := 0
        if selectedOwner != null && selectedOwner.StaticIntConstants.TryGetValue(memberName, out literalValue) {
            return false
        }

        fieldOwner = selectedOwner
        field = selectedField
        return true
    }

    // A `FieldBuilder` carries its declaring type and value type from its own definition, which is
    // what the pool needs: reading them back through reflection off an unbaked type is exactly the
    // question `AddFieldWithSignature` exists to avoid asking.
    static func AddStaticField(plan: ColumnarCodePlan, fieldOwner: ColumnarStructDef?, field: FieldBuilder): int {
        declaringType := field.get_DeclaringType()
        if fieldOwner != null {
            declaringType = fieldOwner.Builder
        }

        return plan.AddFieldWithSignature(field, declaringType, field.get_FieldType(), true)
    }

    // Does this member access name a static of a source type? The receiver is a bare identifier or a
    // dotted name, and its ROOT must not be shadowed by anything nearer — a value binding, a callable
    // or an enum name all win over a type spelling.
    static func TryResolveOwner(nodes: ColumnarNodeTable, source: string, node: int, bindings: ColumnarFragmentBindings, out owner: ColumnarStructDef?): bool {
        owner = null
        if nodes == null || source == null || bindings == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }
        if nodes.Kind(node) != ColumnarExpressionNodeKind.MemberAccessExpression() || nodes.ChildCount(node) != 1 {
            return false
        }

        ownerName := ""
        rootName := ""
        if !ColumnarExternalStaticMemberPlanner.TryGetQualifiedName(nodes, source, nodes.Child(node, 0), 0, out ownerName, out rootName) {
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
