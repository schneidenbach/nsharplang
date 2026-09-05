namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

func SourceInterfaceMethodRegister(
    table: ColumnarStructuralTypeReferenceTable,
    definition: ColumnarStructDef
) {
    table.RegisterSourceDefinition(
        definition.DeclaredTypeName,
        definition.Builder,
        false
    )
}

func SourceInterfaceMethodRequiredBinding(
    definition: ColumnarStructDef,
    memberName: string,
    returnType: Type,
    parameterTypes: Type[],
    table: ColumnarStructuralTypeReferenceTable
): ColumnarSourceInterfaceMethodBinding {
    binding: ColumnarSourceInterfaceMethodBinding? = null
    if !ColumnarSourceInterfaceMethodResolver.TryFind(
        definition,
        memberName,
        returnType,
        parameterTypes,
        table,
        out binding
    ) || binding == null {
        throw new InvalidOperationException(
            "The source-interface method fixture did not resolve its required binding."
        )
    }
    return binding
}

func SourceInterfaceMethodRequiredKey(
    selected: ColumnarSelectedTypeReference
): ColumnarStructuralTypeKey {
    key := selected.Key
    if key == null {
        throw new InvalidOperationException(
            "The source-interface method fixture did not select a structural key."
        )
    }
    return key
}

func SourceInterfaceMethodSingleType(value: Type): Type[] {
    values := new Type[](1)
    values[0] = value
    return values
}

func SourceInterfaceMethodSingleString(value: string): string[] {
    values := new string[](1)
    values[0] = value
    return values
}

func SourceInterfaceMethodEmitVoid(method: MethodBuilder) {
    TypeOfMethodBuilderIL(method).Emit(OpCodes.Ret)
}

func SourceInterfaceMethodPut(values: object?[], index: int, value: object?) {
    values[index] = value
}

func SourceInterfaceMethodMapTargets(owner: Type, interfaceType: Type): IList {
    getInterfaceMap := typeof(Type).GetMethod("GetInterfaceMap")
    if getInterfaceMap == null {
        throw new InvalidOperationException("Type.GetInterfaceMap was not found.")
    }
    arguments := new object?[](1)
    SourceInterfaceMethodPut(arguments, 0, interfaceType)
    mapping := getInterfaceMap.Invoke(owner, arguments)
    if mapping == null {
        throw new InvalidOperationException("Type.GetInterfaceMap returned null.")
    }
    targetMethodsField := mapping.GetType().GetField("TargetMethods")
    if targetMethodsField == null {
        throw new InvalidOperationException("InterfaceMapping.TargetMethods was not found.")
    }
    targetMethods := targetMethodsField.GetValue(mapping) as IList
    if targetMethods == null {
        throw new InvalidOperationException("InterfaceMapping.TargetMethods was not an IList.")
    }
    return targetMethods
}

func SourceInterfaceMethodRequiredMethod(value: object?): MethodInfo {
    method := value as MethodInfo
    if method == null {
        throw new InvalidOperationException("InterfaceMapping target was not a MethodInfo.")
    }
    return method
}

test "source interface lookup is own-first and then depth-first in declared base order" {
    noParameters := new Type[](0)
    noModifiers := new int[](0)
    root := SourceCallInterfaceDefinition("SourceMemberOrderRoot")
    left := SourceCallInterfaceDefinition("SourceMemberOrderLeft")
    right := SourceCallInterfaceDefinition("SourceMemberOrderRight")
    own := SourceCallInterfaceDefinition("SourceMemberOrderOwn")
    mismatch := SourceCallInterfaceDefinition("SourceMemberOrderMismatch")

    rootMethod := SourceCallDefineInstance(
        root,
        "Read",
        noParameters,
        noModifiers,
        typeof(string),
        (MethodAttributes)1478
    )
    leftMethod := SourceCallDefineInstance(
        left,
        "Read",
        noParameters,
        noModifiers,
        typeof(string),
        (MethodAttributes)1478
    )
    rightMethod := SourceCallDefineInstance(
        right,
        "Read",
        noParameters,
        noModifiers,
        typeof(string),
        (MethodAttributes)1478
    )
    ownMethod := SourceCallDefineInstance(
        own,
        "Read",
        noParameters,
        noModifiers,
        typeof(string),
        (MethodAttributes)1478
    )
    _mismatchMethod := SourceCallDefineInstance(
        mismatch,
        "Read",
        noParameters,
        noModifiers,
        typeof(bool),
        (MethodAttributes)1478
    )

    left.InterfaceBases.Add(root)
    own.InterfaceBases.Add(left)
    own.InterfaceBases.Add(right)
    mismatch.InterfaceBases.Add(left)
    mismatch.InterfaceBases.Add(right)

    table := new ColumnarStructuralTypeReferenceTable()
    SourceInterfaceMethodRegister(table, root)
    SourceInterfaceMethodRegister(table, left)
    SourceInterfaceMethodRegister(table, right)
    SourceInterfaceMethodRegister(table, own)
    SourceInterfaceMethodRegister(table, mismatch)

    ownBinding := SourceInterfaceMethodRequiredBinding(
        own,
        "Read",
        typeof(string),
        noParameters,
        table
    )
    assert Object.ReferenceEquals(ownBinding.Target, ownMethod.Builder)
    assert ownBinding.Descriptor.DeclaringType.SourceProvenanceName == "SourceMemberOrderOwn"

    inheritedBinding := SourceInterfaceMethodRequiredBinding(
        mismatch,
        "Read",
        typeof(string),
        noParameters,
        table
    )
    assert Object.ReferenceEquals(inheritedBinding.Target, leftMethod.Builder)
    assert !Object.ReferenceEquals(inheritedBinding.Target, rootMethod.Builder)
    assert !Object.ReferenceEquals(inheritedBinding.Target, rightMethod.Builder)
    assert inheritedBinding.Descriptor.DeclaringType.SourceProvenanceName == "SourceMemberOrderLeft"
    inheritedDeclaringType := inheritedBinding.Descriptor.DeclaringType
    inheritedRuntimeType: Type = inheritedDeclaringType.RuntimeType
    leftRuntimeType: Type = left.Builder
    assert inheritedRuntimeType == leftRuntimeType
}

test "source interface lookup keeps the first Methods row and admits default-body declarations" {
    noParameters := new Type[](0)
    noModifiers := new int[](0)
    overloadOwner := SourceCallInterfaceDefinition("SourceMemberFirstOnly")
    first := SourceCallDefineInstance(
        overloadOwner,
        "Choose",
        noParameters,
        noModifiers,
        typeof(bool),
        (MethodAttributes)1478
    )
    second := SourceCallDefineInstance(
        overloadOwner,
        "Choose",
        noParameters,
        noModifiers,
        typeof(string),
        (MethodAttributes)1478
    )
    defaultOwner := SourceCallInterfaceDefinition("SourceMemberDefaultBody")
    defaultMethod := SourceCallDefineInstance(
        defaultOwner,
        "Describe",
        noParameters,
        noModifiers,
        typeof(string),
        (MethodAttributes)454
    )
    defaultOwner.DefaultInterfaceMethodNames.Add("Describe")

    table := new ColumnarStructuralTypeReferenceTable()
    SourceInterfaceMethodRegister(table, overloadOwner)
    SourceInterfaceMethodRegister(table, defaultOwner)

    ignoredLater: ColumnarSourceInterfaceMethodBinding? = null
    assert !ColumnarSourceInterfaceMethodResolver.TryFind(
        overloadOwner,
        "Choose",
        typeof(string),
        noParameters,
        table,
        out ignoredLater
    )
    assert ignoredLater == null
    assert overloadOwner.MethodOverloads["Choose"].Count == 2
    firstMethodsRow := overloadOwner.Methods["Choose"]
    assert Object.ReferenceEquals(firstMethodsRow, first)
    assert !Object.ReferenceEquals(firstMethodsRow, second)

    defaultBinding := SourceInterfaceMethodRequiredBinding(
        defaultOwner,
        "Describe",
        typeof(string),
        noParameters,
        table
    )
    assert Object.ReferenceEquals(defaultBinding.Target, defaultMethod.Builder)

    missing: ColumnarSourceInterfaceMethodBinding? = null
    assert !ColumnarSourceInterfaceMethodResolver.TryFind(
        defaultOwner,
        "Missing",
        typeof(string),
        noParameters,
        table,
        out missing
    )
    assert missing == null

    mismatched: ColumnarSourceInterfaceMethodBinding? = null
    assert !ColumnarSourceInterfaceMethodResolver.TryFind(
        defaultOwner,
        "Describe",
        typeof(bool),
        noParameters,
        table,
        out mismatched
    )
    assert mismatched == null
}

test "source interface signature matching uses CLR Type equality without structural substitution" {
    owner := SourceCallInterfaceDefinition("SourceMemberTypeEquality")
    table := new ColumnarStructuralTypeReferenceTable()
    SourceInterfaceMethodRegister(table, owner)
    voidType := ExecutorVoidType()
    noModifiers := new int[](0)

    delegatedLeft: Type = new TypeDelegator(typeof(int))
    delegatedRight: Type = new TypeDelegator(typeof(int))
    assert !Object.ReferenceEquals(delegatedLeft, delegatedRight)
    assert delegatedLeft == delegatedRight
    delegatedTarget := owner.Builder.DefineMethod(
        "AcceptDelegated",
        (MethodAttributes)1478,
        voidType,
        SourceInterfaceMethodSingleType(typeof(int))
    )
    delegatedDefinition := new ColumnarInstanceMethodDef(
        delegatedTarget,
        SourceInterfaceMethodSingleType(delegatedLeft),
        noModifiers,
        voidType
    )
    SourceCallAddInstanceFact(owner, "AcceptDelegated", delegatedDefinition)
    delegatedBinding := SourceInterfaceMethodRequiredBinding(
        owner,
        "AcceptDelegated",
        voidType,
        SourceInterfaceMethodSingleType(delegatedRight),
        table
    )
    assert Object.ReferenceEquals(delegatedBinding.Target, delegatedTarget)

    genericDefinition := TypeOfCreateBuilder(
        "SourceMemberExactBox",
        "SourceMemberExactBoxAssembly",
        1
    )
    genericDefinitionType: Type = genericDefinition
    table.RegisterSourceDefinition("SourceMemberExactBox", genericDefinitionType, false)
    arguments := SourceInterfaceMethodSingleType(typeof(int))
    firstClosure := genericDefinitionType.MakeGenericType(arguments)
    secondClosure := genericDefinitionType.MakeGenericType(arguments)
    assert !Object.ReferenceEquals(firstClosure, secondClosure)
    assert firstClosure != secondClosure
    firstSelected := table.SelectRuntimeType(firstClosure)
    secondSelected := table.SelectRuntimeType(secondClosure)
    firstKey := SourceInterfaceMethodRequiredKey(firstSelected)
    secondKey := SourceInterfaceMethodRequiredKey(secondSelected)
    assert ColumnarStructuralTypeKeyFacts.KeysEqual(firstKey, secondKey)

    exactTarget := owner.Builder.DefineMethod(
        "AcceptExact",
        (MethodAttributes)1478,
        voidType,
        SourceInterfaceMethodSingleType(firstClosure)
    )
    exactDefinition := new ColumnarInstanceMethodDef(
        exactTarget,
        SourceInterfaceMethodSingleType(firstClosure),
        noModifiers,
        voidType
    )
    SourceCallAddInstanceFact(owner, "AcceptExact", exactDefinition)
    crossHandle: ColumnarSourceInterfaceMethodBinding? = null
    assert !ColumnarSourceInterfaceMethodResolver.TryFind(
        owner,
        "AcceptExact",
        voidType,
        SourceInterfaceMethodSingleType(secondClosure),
        table,
        out crossHandle
    )
    assert crossHandle == null
    sameHandle := SourceInterfaceMethodRequiredBinding(
        owner,
        "AcceptExact",
        voidType,
        SourceInterfaceMethodSingleType(firstClosure),
        table
    )
    assert Object.ReferenceEquals(sameHandle.Target, exactTarget)
}

test "source interface descriptors snapshot the found owner signature modifiers and target" {
    owner := SourceCallInterfaceDefinition("SourceMemberSnapshotOwner")
    other := SourceCallInterfaceDefinition("SourceMemberSnapshotOther")
    table := new ColumnarStructuralTypeReferenceTable()
    SourceInterfaceMethodRegister(table, owner)
    SourceInterfaceMethodRegister(table, other)

    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(int)
    parameterTypes[1] = typeof(string)
    modifierKinds := new int[](2)
    modifierKinds[0] = 1
    modifierKinds[1] = 2
    definition := SourceCallDefineInstance(
        owner,
        "Transform",
        parameterTypes,
        modifierKinds,
        typeof(bool),
        (MethodAttributes)1478
    )
    originalTarget := definition.Builder
    binding := SourceInterfaceMethodRequiredBinding(
        owner,
        "Transform",
        typeof(bool),
        parameterTypes,
        table
    )
    descriptor := binding.Descriptor

    parameterTypes[0] = typeof(long)
    modifierKinds[0] = 3
    definition.ParamTypes = SourceInterfaceMethodSingleType(typeof(byte))
    definition.ParamModifierKinds = new int[](0)
    definition.ReturnType = typeof(long)
    definition.Builder = owner.Builder.DefineMethod(
        "Replacement",
        (MethodAttributes)1478,
        typeof(long),
        new Type[](0)
    )

    assert descriptor.MemberName == "Transform"
    assert descriptor.DefinitionFamily == ColumnarSourceInterfaceMethodDefinitionFamily.InstanceDefinition
    assert descriptor.MethodGenericArity == 0
    assert descriptor.ParameterCount == 2
    assert descriptor.ParameterModifierCount == 2
    assert descriptor.ParameterType(0).RuntimeType == typeof(int)
    assert descriptor.ParameterType(1).RuntimeType == typeof(string)
    assert descriptor.ParameterModifierKind(0) == 1
    assert descriptor.ParameterModifierKind(1) == 2
    assert descriptor.ReturnType.RuntimeType == typeof(bool)
    assert Object.ReferenceEquals(binding.Target, originalTarget)
    assert descriptor.Validate(table)

    otherDefinition := SourceCallDefineInstance(
        other,
        "Transform",
        new Type[](0),
        new int[](0),
        typeof(bool),
        (MethodAttributes)1478
    )
    assert throws InvalidOperationException {
        _rejected := new ColumnarSourceInterfaceMethodBinding(
            owner,
            "Transform",
            otherDefinition,
            table
        )
    }
}

test "source interface descriptors retain distinct generic source owners" {
    first := SourceCallGenericDefinition("SourceMemberGenericFirst")
    second := SourceCallGenericDefinition("SourceMemberGenericSecond")
    first.IsInterface = true
    second.IsInterface = true
    table := new ColumnarStructuralTypeReferenceTable()
    SourceInterfaceMethodRegister(table, first)
    SourceInterfaceMethodRegister(table, second)
    names := SourceInterfaceMethodSingleString("T")
    table.RegisterTypeGenericParameters(31, first.DeclaredTypeName, names, first.Builder)
    table.RegisterTypeGenericParameters(31, second.DeclaredTypeName, names, second.Builder)
    firstParameter := first.Builder.GetGenericArguments()[0]
    secondParameter := second.Builder.GetGenericArguments()[0]
    firstDefinition := SourceCallDefineInstance(
        first,
        "Map",
        SourceInterfaceMethodSingleType(firstParameter),
        new int[](0),
        firstParameter,
        (MethodAttributes)1478
    )
    secondDefinition := SourceCallDefineInstance(
        second,
        "Map",
        SourceInterfaceMethodSingleType(secondParameter),
        new int[](0),
        secondParameter,
        (MethodAttributes)1478
    )
    firstBinding := SourceInterfaceMethodRequiredBinding(
        first,
        "Map",
        firstParameter,
        firstDefinition.ParamTypes,
        table
    )
    secondBinding := SourceInterfaceMethodRequiredBinding(
        second,
        "Map",
        secondParameter,
        secondDefinition.ParamTypes,
        table
    )
    firstKey := SourceInterfaceMethodRequiredKey(firstBinding.Descriptor.ParameterType(0))
    secondKey := SourceInterfaceMethodRequiredKey(secondBinding.Descriptor.ParameterType(0))
    assert firstKey.Kind == ColumnarStructuralTypeReferenceKind.TypeGenericParameter
    assert secondKey.Kind == ColumnarStructuralTypeReferenceKind.TypeGenericParameter
    assert firstKey.GenericOwnerDeclaringTypeName == "SourceMemberGenericFirst"
    assert secondKey.GenericOwnerDeclaringTypeName == "SourceMemberGenericSecond"
    assert !ColumnarStructuralTypeKeyFacts.KeysEqual(firstKey, secondKey)
}

test "ordinary override rows retain the first source representation across direct and bare duplicates" {
    source := SourceCallInterfaceDefinition("SourceMemberDedup")
    table := new ColumnarStructuralTypeReferenceTable()
    SourceInterfaceMethodRegister(table, source)
    noParameters := new Type[](0)
    voidType := ExecutorVoidType()
    definition := SourceCallDefineInstance(
        source,
        "Run",
        noParameters,
        new int[](0),
        voidType,
        (MethodAttributes)1478
    )
    binding := SourceInterfaceMethodRequiredBinding(
        source,
        "Run",
        voidType,
        noParameters,
        table
    )

    directFirst := DeclarationPlanOverrideDeclaration("Run", "void", false)
    directFirst.AddSourceTarget(binding)
    directFirst.AddSourceTarget(definition.Builder)
    directCompletion := directFirst.Complete(null, voidType, noParameters)
    assert directFirst.SourceTargetCount == 1
    assert directCompletion.Targets.Length == 1
    assert directCompletion.Targets[0].SourceInterfaceBinding != null
    directTargets := directCompletion.Targets
    directTarget := directTargets[0]
    assert Object.ReferenceEquals(directTarget.Target, definition.Builder)

    bareFirst := DeclarationPlanOverrideDeclaration("Run", "void", false)
    bareFirst.AddSourceTarget(definition.Builder)
    bareFirst.AddSourceTarget(binding)
    bareCompletion := bareFirst.Complete(null, voidType, noParameters)
    assert bareFirst.SourceTargetCount == 1
    assert bareCompletion.Targets.Length == 1
    assert bareCompletion.Targets[0].SourceInterfaceBinding == null
    bareTargets := bareCompletion.Targets
    bareTarget := bareTargets[0]
    assert Object.ReferenceEquals(bareTarget.Target, definition.Builder)
}

test "ordinary override execution validates every direct binding before attaching any target" {
    noParameters := new Type[](0)
    voidType := ExecutorVoidType()
    firstInterface := SourceCallInterfaceDefinition("SourceMemberAtomicFirst")
    secondInterface := SourceCallInterfaceDefinition("SourceMemberAtomicSecond")
    firstMethod := SourceCallDefineInstance(
        firstInterface,
        "Run",
        noParameters,
        new int[](0),
        voidType,
        (MethodAttributes)454
    )
    secondMethod := SourceCallDefineInstance(
        secondInterface,
        "Run",
        noParameters,
        new int[](0),
        voidType,
        (MethodAttributes)454
    )
    SourceInterfaceMethodEmitVoid(firstMethod.Builder)
    SourceInterfaceMethodEmitVoid(secondMethod.Builder)

    firstTable := new ColumnarStructuralTypeReferenceTable()
    secondTable := new ColumnarStructuralTypeReferenceTable()
    SourceInterfaceMethodRegister(firstTable, firstInterface)
    SourceInterfaceMethodRegister(firstTable, secondInterface)
    SourceInterfaceMethodRegister(secondTable, secondInterface)
    firstBinding := SourceInterfaceMethodRequiredBinding(
        firstInterface,
        "Run",
        voidType,
        noParameters,
        firstTable
    )
    foreignBinding := SourceInterfaceMethodRequiredBinding(
        secondInterface,
        "Run",
        voidType,
        noParameters,
        secondTable
    )

    owner := TypeOfCreateSourceBuilder("SourceMemberAtomicOwner", false)
    owner.AddInterfaceImplementation(firstInterface.Builder)
    owner.AddInterfaceImplementation(secondInterface.Builder)
    body := owner.DefineMethod(
        "ImplementationBody",
        (MethodAttributes)486,
        voidType,
        noParameters
    )
    SourceInterfaceMethodEmitVoid(body)
    foreignRow := DeclarationPlanOverrideDeclaration("Run", "void", false)
    foreignRow.AddSourceTarget(firstBinding)
    foreignRow.AddSourceTarget(foreignBinding)
    foreignCompletion := foreignRow.Complete(null, voidType, noParameters)

    assert throws InvalidOperationException {
        foreignCompletion.Apply(owner, body)
    }
    assert throws InvalidOperationException {
        foreignCompletion.Apply(owner, body, firstTable)
    }

    malformedBinding := SourceInterfaceMethodRequiredBinding(
        secondInterface,
        "Run",
        voidType,
        noParameters,
        firstTable
    )
    returnTypeField := typeof(ColumnarSourceInterfaceMethodDescriptor).GetField("returnTypeValue")
    if returnTypeField == null {
        throw new InvalidOperationException("Source-interface descriptor return identity field was not found.")
    }
    returnTypeField.SetValue(
        malformedBinding.Descriptor,
        firstTable.SelectRuntimeType(typeof(string))
    )
    assert !malformedBinding.Descriptor.Validate(firstTable)
    malformedRow := DeclarationPlanOverrideDeclaration("Run", "void", false)
    malformedRow.AddSourceTarget(firstBinding)
    malformedRow.AddSourceTarget(malformedBinding)
    malformedCompletion := malformedRow.Complete(null, voidType, noParameters)
    assert throws InvalidOperationException {
        malformedCompletion.Apply(owner, body, firstTable)
    }

    firstRuntime := IdentityBake(firstInterface.Builder)
    _secondRuntime := IdentityBake(secondInterface.Builder)
    ownerRuntime := IdentityBake(owner)
    targetMethods := SourceInterfaceMethodMapTargets(ownerRuntime, firstRuntime)
    assert targetMethods.Count == 1
    mappedTarget := SourceInterfaceMethodRequiredMethod(targetMethods[0])
    assert mappedTarget.get_DeclaringType() == firstRuntime
    assert mappedTarget.get_Name() == "Run"
}

test "ordinary override execution consumes the validated unbaked source binding" {
    noParameters := new Type[](0)
    voidType := ExecutorVoidType()
    source := SourceCallInterfaceDefinition("SourceMemberApplyInterface")
    sourceMethod := SourceCallDefineInstance(
        source,
        "Run",
        noParameters,
        new int[](0),
        voidType,
        (MethodAttributes)1478
    )
    table := new ColumnarStructuralTypeReferenceTable()
    SourceInterfaceMethodRegister(table, source)
    binding := SourceInterfaceMethodRequiredBinding(
        source,
        "Run",
        voidType,
        noParameters,
        table
    )
    owner := TypeOfCreateSourceBuilder("SourceMemberApplyOwner", false)
    owner.AddInterfaceImplementation(source.Builder)
    body := owner.DefineMethod(
        "ImplementationBody",
        (MethodAttributes)486,
        voidType,
        noParameters
    )
    SourceInterfaceMethodEmitVoid(body)
    row := DeclarationPlanOverrideDeclaration("Run", "void", false)
    row.AddSourceTarget(binding)
    completion := row.Complete(null, voidType, noParameters)

    exposed := completion.Targets
    exposed[0] = new ColumnarResolvedMethodOverride(
        ColumnarMethodOverrideDeclaration.ExternalInterfaceTargetKind(),
        0,
        "Changed",
        "void",
        new string[](0),
        sourceMethod.Builder
    )
    assert completion.Targets[0].SourceInterfaceBinding != null
    completion.Apply(owner, body, table)

    sourceRuntime := IdentityBake(source.Builder)
    ownerRuntime := IdentityBake(owner)
    targetMethods := SourceInterfaceMethodMapTargets(ownerRuntime, sourceRuntime)
    assert targetMethods.Count == 1
    mappedTarget := SourceInterfaceMethodRequiredMethod(targetMethods[0])
    assert mappedTarget.get_DeclaringType() == ownerRuntime
    assert mappedTarget.get_Name() == "ImplementationBody"
}
