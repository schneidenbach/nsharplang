namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit

enum ColumnarBoundIdentifierKind {
    None,
    BoxedCapture,
    LiftedLocal,
    Local,
    Parameter,
    CurrentField,
    CurrentProperty
}

class ColumnarBoundIdentifierSelection {
    Kind: ColumnarBoundIdentifierKind
    ResultType: Type
    Ordinal: int
    Local: LocalBuilder?
    FirstField: FieldInfo?
    ValueField: FieldInfo?
    Getter: MethodInfo?
    DeclaringType: Type?
    CurrentInstanceType: Type?
    CurrentInstanceIsAddress: bool

    constructor(
        kind: ColumnarBoundIdentifierKind,
        resultType: Type,
        ordinal: int,
        local: LocalBuilder?,
        firstField: FieldInfo?,
        valueField: FieldInfo?,
        getter: MethodInfo?,
        declaringType: Type?,
        currentInstanceType: Type?,
        currentInstanceIsAddress: bool) {
        Kind = kind
        ResultType = resultType
        Ordinal = ordinal
        Local = local
        FirstField = firstField
        ValueField = valueField
        Getter = getter
        DeclaringType = declaringType
        CurrentInstanceType = currentInstanceType
        CurrentInstanceIsAddress = currentInstanceIsAddress
    }
}

// Sole code-plan owner for lexical identifier-value reads. Exact live maps preserve definite
// binding; N# validates their relationships, chooses the storage tier, and emits every load row.
class ColumnarBoundIdentifierPlanner {
    public static func MayPlanRoot(nodes: ColumnarNodeTable, node: int): bool {
        if nodes == null || node < 0 || node >= nodes.Kinds.Length {
            return false
        }
        candidate := UnwrapParentheses(nodes, node)
        return candidate >= 0
            && nodes.Kind(candidate) == ColumnarExpressionNodeKind.IdentifierExpression()
    }

    public static func ClaimsRoot(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings): bool {
        if nodes == null || source == null || bindings == null {
            return false
        }
        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0 || candidate >= nodes.Kinds.Length
            || nodes.Kind(candidate) != ColumnarExpressionNodeKind.IdentifierExpression()
            || nodes.ChildCount(candidate) != 0 {
            return false
        }
        if ColumnarExpressionSyntaxFacts.IsExplicitThisIdentifier(
            nodes, source, candidate) {
            return true
        }
        name := nodes.Text(source, candidate)
        if name.Length == 0 {
            return false
        }
        if bindings.BoxedCaptures.ContainsKey(name)
            || bindings.LiftedLocals.ContainsKey(name)
            || bindings.Locals.ContainsKey(name)
            || bindings.IsBlocked(name) {
            return true
        }
        hasOrdinal := bindings.ParameterOrdinals.ContainsKey(name)
        hasParameterType := bindings.ParameterTypes.ContainsKey(name)
        if hasOrdinal != hasParameterType {
            return true
        }
        if hasOrdinal {
            parameterType := bindings.ParameterTypes[name]
            return parameterType == null || !parameterType.get_IsByRef()
        }
        selection := EmptySelection()
        return TryResolveCurrentInstance(name, bindings, out selection)
    }

    public static func TryEmit(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        plan: ColumnarCodePlan,
        il: ILGenerator,
        out resultType: Type): bool {
        if Plan(nodes, source, node, bindings, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
            return false
        }
        ColumnarCodePlanExecutor.Execute(plan, il)
        resultType = RequiredResultType(plan)
        return true
    }

    public static func TryGetType(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        plan: ColumnarCodePlan,
        out resultType: Type): bool {
        if Plan(nodes, source, node, bindings, plan) != ColumnarFragmentPlanStatus.Planned {
            resultType = typeof(int)
            return false
        }
        resultType = RequiredResultType(plan)
        return true
    }

    public static func Plan(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        plan: ColumnarCodePlan): ColumnarFragmentPlanStatus {
        ValidateInputs(nodes, source, node, bindings, plan)
        plan.PrepareV3()
        candidate := UnwrapParentheses(nodes, node)
        if candidate < 0
            || nodes.Kind(candidate) != ColumnarExpressionNodeKind.IdentifierExpression() {
            return plan.Status
        }

        checkpoint := plan.CreateCheckpoint()
        try {
            resultType := typeof(int)
            fragment := plan.BeginFragment(
                -1, ColumnarExpressionNodeKind.IdentifierExpression(), candidate)
            if !TryAppend(nodes, source, candidate, bindings, plan, out resultType) {
                plan.Rollback(checkpoint)
                return plan.Status
            }
            plan.CompleteFragment(fragment, resultType)
            plan.CompleteV3(resultType)
            return plan.Status
        } catch ex: Exception {
            plan.Rollback(checkpoint)
            throw ex
        }
    }

    public static func TryAppend(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        plan: ColumnarCodePlan,
        out resultType: Type): bool {
        resultType = typeof(int)
        if nodes == null || source == null || bindings == null || plan == null
            || node < 0 || node >= nodes.Kinds.Length
            || nodes.Kind(node) != ColumnarExpressionNodeKind.IdentifierExpression() {
            return false
        }
        if plan.SchemaVersion != ColumnarCodePlanContract.ScalarSchemaVersion()
            || plan.Status != ColumnarFragmentPlanStatus.NotOwned
            || plan.Lifecycle != ColumnarCodePlanLifecycle.Building {
            throw new InvalidOperationException(
                "Bound-identifier append requires an open schema-v3 plan.")
        }

        selection := EmptySelection()
        if !TryResolve(nodes, source, node, bindings, out selection) {
            return false
        }

        if selection.Kind == ColumnarBoundIdentifierKind.BoxedCapture {
            currentInstanceType := RequiredType(
                selection.CurrentInstanceType,
                "Boxed-capture selection has no current-instance type.")
            argumentIndex := GetOrAddArgument(
                plan, 0, currentInstanceType, false)
            plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)
            firstFieldIndex := plan.AddField(RequiredField(
                selection.FirstField,
                "Boxed-capture selection has no box field."))
            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), firstFieldIndex)
            valueFieldIndex := plan.AddField(RequiredField(
                selection.ValueField,
                "Boxed-capture selection has no value field."))
            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), valueFieldIndex)
        } else if selection.Kind == ColumnarBoundIdentifierKind.LiftedLocal {
            localIndex := plan.AddAmbientLocal(RequiredLocal(
                selection.Local,
                "Lifted selection has no box local."))
            plan.AppendAmbientLocalInstruction(ColumnarCodePlanContract.Ldloc(), localIndex)
            valueFieldIndex := plan.AddField(RequiredField(
                selection.ValueField,
                "Lifted selection has no value field."))
            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), valueFieldIndex)
        } else if selection.Kind == ColumnarBoundIdentifierKind.Local {
            localIndex := plan.AddAmbientLocal(RequiredLocal(
                selection.Local,
                "Local selection has no local."))
            plan.AppendAmbientLocalInstruction(ColumnarCodePlanContract.Ldloc(), localIndex)
        } else if selection.Kind == ColumnarBoundIdentifierKind.Parameter {
            argumentIndex := GetOrAddArgument(
                plan, selection.Ordinal, selection.ResultType, false)
            plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)
        } else if selection.Kind == ColumnarBoundIdentifierKind.CurrentField {
            currentInstanceType := RequiredType(
                selection.CurrentInstanceType,
                "Current-field selection has no current-instance type.")
            argumentIndex := GetOrAddArgument(
                plan,
                0,
                currentInstanceType,
                selection.CurrentInstanceIsAddress)
            plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)
            fieldIndex := plan.AddField(RequiredField(
                selection.FirstField,
                "Current-field selection has no exact field handle."))
            plan.AppendFieldInstruction(ColumnarCodePlanContract.Ldfld(), fieldIndex)
        } else if selection.Kind == ColumnarBoundIdentifierKind.CurrentProperty {
            currentInstanceType := RequiredType(
                selection.CurrentInstanceType,
                "Current-property selection has no current-instance type.")
            argumentIndex := GetOrAddArgument(
                plan,
                0,
                currentInstanceType,
                selection.CurrentInstanceIsAddress)
            plan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), argumentIndex)
            getter := RequiredMethod(
                selection.Getter,
                "Current-property selection has no exact getter handle.")
            declaringType := RequiredType(
                selection.DeclaringType,
                "Current-property selection has no exact declaring type.")
            methodIndex := plan.AddMethodWithSignature(
                getter,
                declaringType,
                new Type[](0),
                selection.ResultType,
                false,
                getter.get_IsAbstract())
            if selection.CurrentInstanceIsAddress {
                plan.AppendMethodInstruction(ColumnarCodePlanContract.Call(), methodIndex)
            } else {
                plan.AppendMethodInstruction(ColumnarCodePlanContract.Callvirt(), methodIndex)
            }
        } else {
            throw new InvalidOperationException("Bound-identifier selection kind is invalid.")
        }

        resultType = selection.ResultType
        return true
    }

    public static func TryGetBoundType(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        out resultType: Type): bool {
        resultType = typeof(int)
        selection := EmptySelection()
        if !TryResolve(nodes, source, node, bindings, out selection) {
            return false
        }
        resultType = selection.ResultType
        return true
    }

    static func TryResolve(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        out selection: ColumnarBoundIdentifierSelection): bool {
        selection = EmptySelection()
        if nodes == null || source == null || bindings == null
            || node < 0 || node >= nodes.Kinds.Length
            || nodes.Kind(node) != ColumnarExpressionNodeKind.IdentifierExpression()
            || nodes.ChildCount(node) != 0 {
            return false
        }

        name := nodes.Text(source, node)
        if name.Length == 0 {
            return false
        }
        if ColumnarExpressionSyntaxFacts.IsExplicitThisIdentifier(nodes, source, node) {
            return TryResolveCurrentInstance(name, bindings, out selection)
        }

        hasBoxed := bindings.BoxedCaptures.ContainsKey(name)
        hasLifted := bindings.LiftedLocals.ContainsKey(name)
        hasLocal := bindings.Locals.ContainsKey(name)
        hasOrdinal := bindings.ParameterOrdinals.ContainsKey(name)
        hasParameterType := bindings.ParameterTypes.ContainsKey(name)
        if hasOrdinal != hasParameterType {
            throw new InvalidOperationException(
                "Bound-identifier parameter ordinals and types must contain identical names.")
        }
        hasParameter := hasOrdinal

        if hasBoxed {
            if hasLifted || hasLocal || hasParameter {
                throw new InvalidOperationException(
                    "A boxed capture cannot overlap another live value binding.")
            }
            boxed := bindings.BoxedCaptures[name]
            boxField := boxed.Item1
            valueType := boxed.Item2
            if boxField == null || valueType == null {
                throw new InvalidOperationException(
                    "Boxed-capture facts cannot be null.")
            }
            currentInstanceType := boxField.get_DeclaringType()
            if currentInstanceType == null || currentInstanceType.get_IsValueType()
                || boxField.get_IsStatic() {
                throw new InvalidOperationException(
                    "Boxed-capture facts do not identify an exact current-instance field.")
            }
            valueField := ResolveStrongBoxValueField(boxField.get_FieldType(), valueType)
            selection = new ColumnarBoundIdentifierSelection(
                ColumnarBoundIdentifierKind.BoxedCapture,
                valueType,
                -1,
                null,
                boxField,
                valueField,
                null,
                null,
                currentInstanceType,
                false)
            return true
        }

        if hasLifted {
            if hasLocal {
                throw new InvalidOperationException(
                    "A lifted binding cannot also name an ordinary local.")
            }
            lifted := bindings.LiftedLocals[name]
            boxLocal := lifted.Item1
            valueType := lifted.Item2
            if boxLocal == null || valueType == null {
                throw new InvalidOperationException("Lifted-local facts cannot be null.")
            }
            if hasParameter && bindings.ParameterTypes[name] != valueType {
                throw new InvalidOperationException(
                    "A lifted parameter must preserve its declared value type.")
            }
            valueField := ResolveStrongBoxValueField(boxLocal.get_LocalType(), valueType)
            selection = new ColumnarBoundIdentifierSelection(
                ColumnarBoundIdentifierKind.LiftedLocal,
                valueType,
                -1,
                boxLocal,
                null,
                valueField,
                null,
                null,
                null,
                false)
            return true
        }

        if hasLocal {
            if hasParameter {
                throw new InvalidOperationException(
                    "An ordinary local cannot overlap a parameter binding.")
            }
            local := bindings.Locals[name]
            if local == null || local.get_LocalType() == null {
                throw new InvalidOperationException(
                    "Ordinary-local facts must identify a storable local.")
            }
            localType := local.get_LocalType()
            RequireStorableValueType(
                localType,
                "Ordinary-local facts must identify a storable local.")
            selection = new ColumnarBoundIdentifierSelection(
                ColumnarBoundIdentifierKind.Local,
                localType,
                -1,
                local,
                null,
                null,
                null,
                null,
                null,
                false)
            return true
        }

        if hasParameter {
            parameterType := bindings.ParameterTypes[name]
            ordinal := bindings.ParameterOrdinals[name]
            if parameterType == null || ordinal < 0 || ordinal > 32767 {
                throw new InvalidOperationException(
                    "Ordinary-parameter facts must identify a valid type and ordinal.")
            }
            // ref/out reads retain their legacy branch until an address-aware plan schema owns them.
            if parameterType.get_IsByRef() {
                return false
            }
            RequireStorableValueType(
                parameterType,
                "Ordinary-parameter facts must identify a storable value type.")
            selection = new ColumnarBoundIdentifierSelection(
                ColumnarBoundIdentifierKind.Parameter,
                parameterType,
                ordinal,
                null,
                null,
                null,
                null,
                null,
                null,
                false)
            return true
        }

        // A synthesized closure display materializes snapshot captures as exact current-instance
        // fields. Those fields are the storage for names that remain present in the enclosing-name
        // set, so they resolve before the name-only shadow gate.
        if bindings.CurrentInstance != null
            && bindings.CurrentInstance.IsClosureDisplay
            && TryResolveCurrentInstance(name, bindings, out selection) {
            return true
        }

        // Name-only facts represent an enclosing or otherwise blocked binding whose storage is not
        // available in this body. They must not be guessed from an ordinary source member with the
        // same text.
        if bindings.IsBlocked(name) {
            return false
        }
        return TryResolveCurrentInstance(name, bindings, out selection)
    }

    static func TryResolveCurrentInstance(
        name: string,
        bindings: ColumnarFragmentBindings,
        out selection: ColumnarBoundIdentifierSelection): bool {
        selection = EmptySelection()
        root := bindings.CurrentInstance
        if root == null {
            return false
        }
        rootType := root.ExactType
        receiverType := OpenCurrentInstanceType(rootType)
        if rootType.get_IsValueType() == root.IsReference {
            throw new InvalidOperationException(
                "Current-instance facts do not match their exact source type.")
        }

        field: FieldInfo? = null
        declaringType := typeof(object)
        if ColumnarCurrentInstanceFacts.TryFindField(
            root, name, out field, out declaringType) {
            if field == null || field.get_IsStatic()
                || field.get_DeclaringType() != declaringType {
                throw new InvalidOperationException(
                    "Current-instance field facts do not identify exact instance storage.")
            }
            selectedField := field
            selectedDeclaringType := declaringType
            if receiverType != rootType && declaringType == rootType {
                selectedField = RebindField(receiverType, field)
                selectedDeclaringType = receiverType
            }
            fieldType := selectedField.get_FieldType()
            RequireStorableValueType(
                fieldType,
                "Current-instance field facts must identify a storable value type.")
            selection = new ColumnarBoundIdentifierSelection(
                ColumnarBoundIdentifierKind.CurrentField,
                fieldType,
                0,
                null,
                selectedField,
                null,
                null,
                selectedDeclaringType,
                receiverType,
                !root.IsReference)
            return true
        }

        getter: MethodInfo? = null
        propertyType := typeof(object)
        if ColumnarCurrentInstanceFacts.TryFindProperty(
            root,
            name,
            out getter,
            out propertyType,
            out declaringType) {
            if getter == null || propertyType == null
                || getter.get_IsStatic()
                || getter.get_DeclaringType() != declaringType
                || getter.get_ReturnType() != propertyType {
                throw new InvalidOperationException(
                    "Current-instance property facts do not identify an exact getter.")
            }
            RequireStorableValueType(
                propertyType,
                "Current-instance property facts must identify a storable value type.")
            selectedGetter := getter
            selectedDeclaringType := declaringType
            if receiverType != rootType && declaringType == rootType {
                selectedGetter = RebindMethod(receiverType, getter)
                selectedDeclaringType = receiverType
            }
            selection = new ColumnarBoundIdentifierSelection(
                ColumnarBoundIdentifierKind.CurrentProperty,
                propertyType,
                0,
                null,
                null,
                null,
                selectedGetter,
                selectedDeclaringType,
                receiverType,
                !root.IsReference)
            return true
        }
        return false
    }

    static func ResolveStrongBoxValueField(boxType: Type, valueType: Type): FieldInfo {
        if boxType == null || valueType == null || valueType.FullName == "System.Void"
            || valueType.get_IsByRef()
            || valueType.get_IsGenericTypeDefinition()
            || !boxType.get_IsGenericType()
            || boxType.get_IsGenericTypeDefinition() {
            throw new InvalidOperationException(
                "Lifted binding facts must identify a closed StrongBox value type.")
        }
        definition := boxType.GetGenericTypeDefinition()
        arguments := boxType.GetGenericArguments()
        if definition.FullName != "System.Runtime.CompilerServices.StrongBox`1"
            || arguments.Length != 1 || arguments[0] != valueType {
            throw new InvalidOperationException(
                "Lifted binding storage must be StrongBox<T> for its exact value type.")
        }
        valueField := boxType.GetField("Value")
        if valueField == null || valueField.get_IsStatic()
            || valueField.get_DeclaringType() != boxType
            || valueField.get_FieldType() != valueType {
            throw new InvalidOperationException(
                "Lifted binding storage has no exact StrongBox<T>.Value field.")
        }
        return valueField
    }

    static func RequireStorableValueType(valueType: Type, message: string) {
        if valueType == null
            || valueType.FullName == "System.Void"
            || valueType.get_IsByRef()
            || valueType.get_IsGenericTypeDefinition() {
            throw new InvalidOperationException(message)
        }
    }

    static func GetOrAddArgument(
        plan: ColumnarCodePlan,
        ordinal: int,
        valueType: Type,
        isAddress: bool): int {
        index := 0
        while index < plan.ArgumentCount {
            if plan.ArgumentOrdinals[index] == ordinal {
                existingType := plan.Types[plan.ArgumentTypeIndices[index]]
                if existingType != valueType
                    || plan.ArgumentIsAddress[index] != isAddress {
                    throw new InvalidOperationException(
                        "One argument ordinal cannot carry conflicting bound-identifier facts.")
                }
                return index
            }
            index = index + 1
        }
        typeIndex := plan.AddType(valueType)
        return plan.AddArgument(ordinal, typeIndex, isAddress)
    }

    static func RequiredLocal(value: LocalBuilder?, message: string): LocalBuilder {
        if value == null {
            throw new InvalidOperationException(message)
        }
        return value
    }

    static func RequiredField(value: FieldInfo?, message: string): FieldInfo {
        if value == null {
            throw new InvalidOperationException(message)
        }
        return value
    }

    static func RequiredMethod(value: MethodInfo?, message: string): MethodInfo {
        if value == null {
            throw new InvalidOperationException(message)
        }
        return value
    }

    static func OpenCurrentInstanceType(rootType: Type): Type {
        if !rootType.get_IsGenericTypeDefinition() {
            return rootType
        }
        arguments := rootType.GetGenericArguments()
        if arguments.Length == 0 {
            throw new InvalidOperationException(
                "A generic current-instance definition has no exact type parameters.")
        }
        return rootType.MakeGenericType(arguments)
    }

    static func RebindField(receiverType: Type, field: FieldInfo): FieldInfo {
        result := TypeBuilder.GetField(receiverType, field)
        if result == null {
            throw new InvalidOperationException(
                "TypeBuilder.GetField returned no exact rebound field.")
        }
        return (FieldInfo)result
    }

    static func RebindMethod(receiverType: Type, method: MethodInfo): MethodInfo {
        result := TypeBuilder.GetMethod(receiverType, method)
        if result == null {
            throw new InvalidOperationException(
                "TypeBuilder.GetMethod returned no exact rebound method.")
        }
        return (MethodInfo)result
    }

    static func RequiredType(value: Type?, message: string): Type {
        if value == null {
            throw new InvalidOperationException(message)
        }
        return value
    }

    static func EmptySelection(): ColumnarBoundIdentifierSelection {
        return new ColumnarBoundIdentifierSelection(
            ColumnarBoundIdentifierKind.None,
            typeof(int),
            -1,
            null,
            null,
            null,
            null,
            null,
            null,
            false)
    }

    static func ValidateInputs(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        bindings: ColumnarFragmentBindings,
        plan: ColumnarCodePlan) {
        if nodes == null || source == null || bindings == null || plan == null {
            throw new InvalidOperationException(
                "Bound-identifier planning inputs cannot be null.")
        }
        if node < 0 || node >= nodes.Kinds.Length {
            throw new InvalidOperationException(
                "Bound-identifier planning received an invalid root node index.")
        }
    }

    static func UnwrapParentheses(nodes: ColumnarNodeTable, node: int): int {
        depth := 0
        while node >= 0 && node < nodes.Kinds.Length
            && nodes.Kind(node) == ColumnarExpressionNodeKind.ParenthesizedExpression() {
            if depth > 200 || nodes.ChildCount(node) != 1 {
                return -1
            }
            node = nodes.Child(node, 0)
            depth = depth + 1
        }
        return node
    }

    static func RequiredResultType(plan: ColumnarCodePlan): Type {
        resultType := plan.ResultType
        if resultType == null {
            throw new InvalidOperationException(
                "Planned bound-identifier expression has no result type.")
        }
        return resultType
    }
}
