namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit

class SourceDiscoveryTimingOutcome {
    Definition: ColumnarStructDef?
    Result: bool
    ErrorMessage: string?

    constructor(definition: ColumnarStructDef?) {
        Definition = definition
        Result = false
        ErrorMessage = null
    }
}

class SourceDiscoveryTimingInvoker {
    static func Find(
        sequence: IEnumerable<ColumnarStructDef>,
        requestedType: Type,
        outcome: SourceDiscoveryTimingOutcome
    ): bool {
        selected := outcome.Definition
        try {
            outcome.Result = ColumnarSourceDefinitionResolver.TryFindByBuilderIdentity(
                sequence,
                requestedType,
                out selected
            )
        } catch error: InvalidOperationException {
            outcome.ErrorMessage = error.Message
        }
        outcome.Definition = selected
        return true
    }

    static func ResolveStruct(
        sequence: IEnumerable<ColumnarStructDef>,
        requestedType: Type,
        outcome: SourceDiscoveryTimingOutcome
    ): bool {
        selected := outcome.Definition
        try {
            ColumnarSourceDefinitionResolver.TryResolveStruct(
                requestedType,
                sequence,
                out selected
            )
        } catch error: InvalidOperationException {
            outcome.Definition = selected
            return error.Message == "source definition disposal failed"
        }
        outcome.Definition = selected
        return false
    }

    static func ResolveInterface(
        sequence: IEnumerable<ColumnarStructDef>,
        requestedType: Type,
        outcome: SourceDiscoveryTimingOutcome
    ): bool {
        selected := outcome.Definition
        try {
            ColumnarSourceDefinitionResolver.TryResolveInterface(
                requestedType,
                sequence,
                out selected
            )
        } catch error: InvalidOperationException {
            outcome.Definition = selected
            return error.Message == "source definition disposal failed"
        }
        outcome.Definition = selected
        return false
    }
}

func SourceDiscoveryTimingInvoke(
    methodName: string,
    sequence: object,
    requestedType: Type,
    outcome: SourceDiscoveryTimingOutcome
): bool {
    method := typeof(SourceDiscoveryTimingInvoker).GetMethod(methodName)
    if method == null {
        throw new InvalidOperationException("Missing source discovery timing invoker.")
    }
    arguments := new object[](3)
    ExecutorSetObject(arguments, 0, sequence)
    ExecutorSetObject(arguments, 1, requestedType)
    ExecutorSetObject(arguments, 2, outcome)
    value := TypeOfRequiredInvocation(method, null, arguments)
    return Convert.ToBoolean(value)
}

func SourceDiscoveryTimingDefinition(builder: TypeBuilder, name: string, isInterface: bool): ColumnarStructDef {
    definition := new ColumnarStructDef(
        builder,
        new string[](0),
        new Dictionary<string, FieldBuilder>(StringComparer.Ordinal),
        true,
        false,
        false,
        name
    )
    definition.IsInterface = isInterface
    return definition
}

func SourceDiscoveryTimingBuilder(name: string, genericCount: int): TypeBuilder {
    return TypeOfCreateBuilder(name, "ColumnarSourceDefinitionResolver." + name, genericCount)
}

func* SourceDiscoveryTimingRows(
    first: ColumnarStructDef,
    second: ColumnarStructDef
): IEnumerable<ColumnarStructDef> {
    yield first
    yield second
}

func* SourceDiscoveryTimingThrowAfter(first: ColumnarStructDef): IEnumerable<ColumnarStructDef> {
    yield first
    throw new InvalidOperationException("source definition enumeration failed")
}

func SourceDiscoveryTimingIteratorState(sequence: object): int {
    field := sequence.GetType().GetField("<>__state")
    if field == null {
        throw new InvalidOperationException("Missing iterator state field.")
    }
    return Convert.ToInt32(field.GetValue(sequence))
}

func SourceDiscoveryTimingRequiredGetter(owner: Type, propertyName: string): MethodInfo {
    property := owner.GetProperty(propertyName)
    if property == null {
        throw new InvalidOperationException("Missing property '" + propertyName + "'.")
    }
    getter := property.GetGetMethod()
    if getter == null {
        throw new InvalidOperationException("Missing getter for '" + propertyName + "'.")
    }
    return getter
}

func SourceDiscoveryTimingDefineField(
    owner: TypeBuilder,
    fieldName: string,
    fieldType: Type
): FieldBuilder {
    parameterTypes := new Type[](3)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = typeof(Type)
    parameterTypes[2] = typeof(FieldAttributes)
    defineField := ExecutorRequiredMethod(typeof(TypeBuilder), "DefineField", parameterTypes)
    arguments := new object[](3)
    ExecutorSetObject(arguments, 0, fieldName)
    ExecutorSetObject(arguments, 1, fieldType)
    ExecutorSetObject(arguments, 2, (FieldAttributes)6)
    value := TypeOfRequiredInvocation(defineField, owner, arguments)
    field := value as FieldBuilder
    if field == null {
        throw new InvalidOperationException("The source discovery fixture field was not defined.")
    }
    return field
}

func SourceDiscoveryTimingReturnThis(method: MethodBuilder) {
    il := TypeOfMethodBuilderIL(method)
    il.Emit(OpCodes.Ldarg_0)
    il.Emit(OpCodes.Ret)
}

func SourceDiscoveryTimingWrapRows(
    enumerator: IEnumerator<ColumnarStructDef>,
    typeName: string
): object {
    noParameters := new Type[](0)
    elementArguments := new Type[](1)
    elementArguments[0] = typeof(ColumnarStructDef)
    genericEnumerableDefinition := typeof(IEnumerable<int>).GetGenericTypeDefinition()
    genericEnumeratorDefinition := typeof(IEnumerator<int>).GetGenericTypeDefinition()
    genericEnumerable := genericEnumerableDefinition.MakeGenericType(elementArguments)
    genericEnumerator := genericEnumeratorDefinition.MakeGenericType(elementArguments)
    nongenericEnumerable := typeof(System.Collections.IEnumerable)
    nongenericEnumerator := typeof(System.Collections.IEnumerator)

    owner := TypeOfCreateBuilder(
        typeName,
        "ColumnarSourceDefinitionResolver.WrappedRows." + typeName,
        0
    )
    owner.AddInterfaceImplementation(genericEnumerable)
    owner.AddInterfaceImplementation(nongenericEnumerable)
    enumeratorField := SourceDiscoveryTimingDefineField(
        owner,
        "Enumerator",
        genericEnumerator
    )

    constructor := owner.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        noParameters
    )
    constructorIl := constructor.GetILGenerator()
    objectConstructor := ExecutorRequiredConstructor(typeof(object), noParameters)
    constructorIl.Emit(OpCodes.Ldarg_0)
    constructorIl.Emit(OpCodes.Call, objectConstructor)
    constructorIl.Emit(OpCodes.Ret)

    genericGetEnumeratorTarget := ExecutorRequiredMethod(
        genericEnumerable,
        "GetEnumerator",
        noParameters
    )
    genericGetEnumerator := owner.DefineMethod(
        "GenericGetEnumerator",
        (MethodAttributes)481,
        genericEnumerator,
        noParameters
    )
    genericGetEnumeratorIl := TypeOfMethodBuilderIL(genericGetEnumerator)
    genericGetEnumeratorIl.Emit(OpCodes.Ldarg_0)
    genericGetEnumeratorIl.Emit(OpCodes.Ldfld, enumeratorField)
    genericGetEnumeratorIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(genericGetEnumerator, genericGetEnumeratorTarget)

    nongenericGetEnumeratorTarget := ExecutorRequiredMethod(
        nongenericEnumerable,
        "GetEnumerator",
        noParameters
    )
    nongenericGetEnumerator := owner.DefineMethod(
        "NongenericGetEnumerator",
        (MethodAttributes)481,
        nongenericEnumerator,
        noParameters
    )
    nongenericGetEnumeratorIl := TypeOfMethodBuilderIL(nongenericGetEnumerator)
    nongenericGetEnumeratorIl.Emit(OpCodes.Ldarg_0)
    nongenericGetEnumeratorIl.Emit(OpCodes.Ldfld, enumeratorField)
    nongenericGetEnumeratorIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(nongenericGetEnumerator, nongenericGetEnumeratorTarget)

    baked := IdentityBake(owner)
    instanceConstructor := ExecutorRequiredConstructor(baked, noParameters)
    instance := instanceConstructor.Invoke(new object[](0))
    if instance == null {
        throw new InvalidOperationException("The source discovery row wrapper was not constructed.")
    }
    bakedEnumeratorField := baked.GetField("Enumerator")
    if bakedEnumeratorField == null {
        throw new InvalidOperationException("The source discovery row wrapper lost its Enumerator field.")
    }
    enumeratorObject: object = enumerator
    bakedEnumeratorField.SetValue(instance, enumeratorObject)
    return instance
}

func SourceDiscoveryTimingThrowingDisposeRows(
    row: ColumnarStructDef,
    typeName: string,
    hasValue: bool
): object {
    noParameters := new Type[](0)
    elementArguments := new Type[](1)
    elementArguments[0] = typeof(ColumnarStructDef)
    genericEnumerableDefinition := typeof(IEnumerable<int>).GetGenericTypeDefinition()
    genericEnumeratorDefinition := typeof(IEnumerator<int>).GetGenericTypeDefinition()
    genericEnumerable := genericEnumerableDefinition.MakeGenericType(elementArguments)
    genericEnumerator := genericEnumeratorDefinition.MakeGenericType(elementArguments)
    nongenericEnumerable := typeof(System.Collections.IEnumerable)
    nongenericEnumerator := typeof(System.Collections.IEnumerator)
    disposable := typeof(IDisposable)

    owner := TypeOfCreateBuilder(
        typeName,
        "ColumnarSourceDefinitionResolver.ThrowingDispose." + typeName,
        0
    )
    owner.AddInterfaceImplementation(genericEnumerable)
    owner.AddInterfaceImplementation(genericEnumerator)
    owner.AddInterfaceImplementation(nongenericEnumerable)
    owner.AddInterfaceImplementation(nongenericEnumerator)
    owner.AddInterfaceImplementation(disposable)
    rowField := SourceDiscoveryTimingDefineField(owner, "Row", typeof(ColumnarStructDef))

    constructor := owner.DefineConstructor(
        (MethodAttributes)6,
        CallingConventions.Standard,
        noParameters
    )
    constructorIl := constructor.GetILGenerator()
    objectConstructor := ExecutorRequiredConstructor(typeof(object), noParameters)
    constructorIl.Emit(OpCodes.Ldarg_0)
    constructorIl.Emit(OpCodes.Call, objectConstructor)
    constructorIl.Emit(OpCodes.Ret)

    genericGetEnumeratorTarget := ExecutorRequiredMethod(
        genericEnumerable,
        "GetEnumerator",
        noParameters
    )
    genericGetEnumerator := owner.DefineMethod(
        "GenericGetEnumerator",
        (MethodAttributes)481,
        genericEnumerator,
        noParameters
    )
    SourceDiscoveryTimingReturnThis(genericGetEnumerator)
    owner.DefineMethodOverride(genericGetEnumerator, genericGetEnumeratorTarget)

    nongenericGetEnumeratorTarget := ExecutorRequiredMethod(
        nongenericEnumerable,
        "GetEnumerator",
        noParameters
    )
    nongenericGetEnumerator := owner.DefineMethod(
        "NongenericGetEnumerator",
        (MethodAttributes)481,
        nongenericEnumerator,
        noParameters
    )
    SourceDiscoveryTimingReturnThis(nongenericGetEnumerator)
    owner.DefineMethodOverride(nongenericGetEnumerator, nongenericGetEnumeratorTarget)

    genericCurrentTarget := SourceDiscoveryTimingRequiredGetter(genericEnumerator, "Current")
    genericCurrent := owner.DefineMethod(
        "GenericCurrent",
        (MethodAttributes)481,
        typeof(ColumnarStructDef),
        noParameters
    )
    genericCurrentIl := TypeOfMethodBuilderIL(genericCurrent)
    genericCurrentIl.Emit(OpCodes.Ldarg_0)
    genericCurrentIl.Emit(OpCodes.Ldfld, rowField)
    genericCurrentIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(genericCurrent, genericCurrentTarget)

    nongenericCurrentTarget := SourceDiscoveryTimingRequiredGetter(nongenericEnumerator, "Current")
    nongenericCurrent := owner.DefineMethod(
        "NongenericCurrent",
        (MethodAttributes)481,
        typeof(object),
        noParameters
    )
    nongenericCurrentIl := TypeOfMethodBuilderIL(nongenericCurrent)
    nongenericCurrentIl.Emit(OpCodes.Ldstr, "wrong Current slot")
    nongenericCurrentIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(nongenericCurrent, nongenericCurrentTarget)

    moveNextTarget := ExecutorRequiredMethod(nongenericEnumerator, "MoveNext", noParameters)
    moveNext := owner.DefineMethod(
        "MoveNext",
        (MethodAttributes)481,
        typeof(bool),
        noParameters
    )
    moveNextIl := TypeOfMethodBuilderIL(moveNext)
    if hasValue {
        moveNextIl.Emit(OpCodes.Ldc_I4_1)
    } else {
        moveNextIl.Emit(OpCodes.Ldc_I4_0)
    }
    moveNextIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(moveNext, moveNextTarget)

    resetTarget := ExecutorRequiredMethod(nongenericEnumerator, "Reset", noParameters)
    reset := owner.DefineMethod(
        "Reset",
        (MethodAttributes)481,
        ColumnarTypeOfPlanner.RequiredVoidType(),
        noParameters
    )
    resetIl := TypeOfMethodBuilderIL(reset)
    resetIl.Emit(OpCodes.Ret)
    owner.DefineMethodOverride(reset, resetTarget)

    disposeTarget := ExecutorRequiredMethod(disposable, "Dispose", noParameters)
    dispose := owner.DefineMethod(
        "Dispose",
        (MethodAttributes)481,
        ColumnarTypeOfPlanner.RequiredVoidType(),
        noParameters
    )
    disposeIl := TypeOfMethodBuilderIL(dispose)
    messageConstructorParameters := new Type[](1)
    messageConstructorParameters[0] = typeof(string)
    exceptionConstructor := ExecutorRequiredConstructor(
        typeof(InvalidOperationException),
        messageConstructorParameters
    )
    disposeIl.Emit(OpCodes.Ldstr, "source definition disposal failed")
    disposeIl.Emit(OpCodes.Newobj, exceptionConstructor)
    disposeIl.Emit(OpCodes.Throw)
    owner.DefineMethodOverride(dispose, disposeTarget)

    baked := IdentityBake(owner)
    instanceConstructor := ExecutorRequiredConstructor(baked, noParameters)
    instance := instanceConstructor.Invoke(new object[](0))
    if instance == null {
        throw new InvalidOperationException("The source discovery fixture was not constructed.")
    }
    bakedRowField := baked.GetField("Row")
    if bakedRowField == null {
        throw new InvalidOperationException("The source discovery fixture lost its Row field.")
    }
    bakedRowField.SetValue(instance, row)
    return instance
}

test "source definition scan disposes on hit after publishing the winning out value" {
    firstBuilder := SourceDiscoveryTimingBuilder("First", 0)
    secondBuilder := SourceDiscoveryTimingBuilder("Second", 0)
    first := SourceDiscoveryTimingDefinition(firstBuilder, "First", false)
    second := SourceDiscoveryTimingDefinition(secondBuilder, "Second", false)

    hitSequence := SourceDiscoveryTimingRows(first, second)
    hitEnumerator := hitSequence.GetEnumerator()
    hitRows := SourceDiscoveryTimingWrapRows(hitEnumerator, "HitRows")
    hitOutcome := new SourceDiscoveryTimingOutcome(second)
    requestedFirst: Type = firstBuilder
    assert SourceDiscoveryTimingInvoke("Find", hitRows, requestedFirst, hitOutcome)
    assert hitOutcome.Result
    assert hitOutcome.ErrorMessage == null
    assert Object.ReferenceEquals(hitOutcome.Definition, first)
    hitEnumeratorObject: object = hitEnumerator
    assert SourceDiscoveryTimingIteratorState(hitEnumeratorObject) == -2
}

test "source definition scan disposes on a completed miss and clears the out value" {
    firstBuilder := SourceDiscoveryTimingBuilder("MissFirst", 0)
    secondBuilder := SourceDiscoveryTimingBuilder("MissSecond", 0)
    absentBuilder := SourceDiscoveryTimingBuilder("MissAbsent", 0)
    first := SourceDiscoveryTimingDefinition(firstBuilder, "MissFirst", false)
    second := SourceDiscoveryTimingDefinition(secondBuilder, "MissSecond", false)

    missSequence := SourceDiscoveryTimingRows(first, second)
    missEnumerator := missSequence.GetEnumerator()
    missRows := SourceDiscoveryTimingWrapRows(missEnumerator, "MissRows")
    missOutcome := new SourceDiscoveryTimingOutcome(first)
    requestedAbsent: Type = absentBuilder
    assert SourceDiscoveryTimingInvoke("Find", missRows, requestedAbsent, missOutcome)
    assert !missOutcome.Result
    assert missOutcome.ErrorMessage == null
    assert missOutcome.Definition == null
    missEnumeratorObject: object = missEnumerator
    assert SourceDiscoveryTimingIteratorState(missEnumeratorObject) == -2
}

test "source definition scan disposes on MoveNext failure without clearing the out value" {
    firstBuilder := SourceDiscoveryTimingBuilder("ThrowFirst", 0)
    secondBuilder := SourceDiscoveryTimingBuilder("ThrowSecond", 0)
    absentBuilder := SourceDiscoveryTimingBuilder("ThrowAbsent", 0)
    first := SourceDiscoveryTimingDefinition(firstBuilder, "ThrowFirst", false)
    second := SourceDiscoveryTimingDefinition(secondBuilder, "ThrowSecond", false)

    throwingSequence := SourceDiscoveryTimingThrowAfter(first)
    throwingEnumerator := throwingSequence.GetEnumerator()
    throwingRows := SourceDiscoveryTimingWrapRows(throwingEnumerator, "ThrowRows")
    throwingOutcome := new SourceDiscoveryTimingOutcome(second)
    requestedAbsent: Type = absentBuilder
    assert SourceDiscoveryTimingInvoke("Find", throwingRows, requestedAbsent, throwingOutcome)
    assert !throwingOutcome.Result
    assert throwingOutcome.ErrorMessage == "source definition enumeration failed"
    assert Object.ReferenceEquals(throwingOutcome.Definition, second)
    throwingEnumeratorObject: object = throwingEnumerator
    assert SourceDiscoveryTimingIteratorState(throwingEnumeratorObject) == -2
}

test "source definition hit is visible before throwing disposal while interface resolution keeps its local candidate" {
    builder := SourceDiscoveryTimingBuilder("Dispose", 0)
    definition := SourceDiscoveryTimingDefinition(builder, "Dispose", true)
    requested: Type = builder

    directRows := SourceDiscoveryTimingThrowingDisposeRows(definition, "DirectDisposeRows", true)
    directOutcome := new SourceDiscoveryTimingOutcome(null)
    assert SourceDiscoveryTimingInvoke(
        "ResolveStruct",
        directRows,
        requested,
        directOutcome
    )
    assert Object.ReferenceEquals(directOutcome.Definition, definition)

    interfaceRows := SourceDiscoveryTimingThrowingDisposeRows(definition, "InterfaceDisposeRows", true)
    sentinelBuilder := SourceDiscoveryTimingBuilder("Sentinel", 0)
    sentinel := SourceDiscoveryTimingDefinition(sentinelBuilder, "Sentinel", false)
    interfaceOutcome := new SourceDiscoveryTimingOutcome(sentinel)
    assert SourceDiscoveryTimingInvoke(
        "ResolveInterface",
        interfaceRows,
        requested,
        interfaceOutcome
    )
    assert Object.ReferenceEquals(interfaceOutcome.Definition, sentinel)
}

test "source definition disposal failure on miss preserves the caller out value" {
    builder := SourceDiscoveryTimingBuilder("DisposeMiss", 0)
    definition := SourceDiscoveryTimingDefinition(builder, "DisposeMiss", false)
    absentBuilder := SourceDiscoveryTimingBuilder("DisposeMissAbsent", 0)
    requestedAbsent: Type = absentBuilder
    rows := SourceDiscoveryTimingThrowingDisposeRows(
        definition,
        "MissDisposeRows",
        false
    )
    outcome := new SourceDiscoveryTimingOutcome(definition)

    assert SourceDiscoveryTimingInvoke("Find", rows, requestedAbsent, outcome)
    assert !outcome.Result
    assert outcome.ErrorMessage == "source definition disposal failed"
    assert Object.ReferenceEquals(outcome.Definition, definition)
}

test "source definition guards retain registry access and caller-out phases" {
    builder := SourceDiscoveryTimingBuilder("Guard", 0)
    definition := SourceDiscoveryTimingDefinition(builder, "Guard", false)

    ordinary: ColumnarStructDef? = definition
    assert !ColumnarSourceDefinitionResolver.TryResolveStruct(typeof(int), null, out ordinary)
    assert ordinary == null

    assert ColumnarSourceDefinitionResolver.FindDirectType(null, typeof(int)) == null

    requested: Type = builder
    directThrew := false
    try {
        ColumnarSourceDefinitionResolver.FindDirectType(null, requested)
    } catch error: NullReferenceException {
        directThrew = true
    }
    assert directThrew

    closedDefinition: ColumnarStructDef? = definition
    closedArguments := new Type[](1)
    closedArguments[0] = typeof(string)
    assert !ColumnarSourceDefinitionResolver.TryResolveClosedReceiver(requested, null, out closedDefinition, out closedArguments)
    assert closedDefinition == null
    assert Object.ReferenceEquals(closedArguments, System.Type.EmptyTypes)

    open := SourceDiscoveryTimingBuilder("ClosedGuard", 1)
    typeArguments := new Type[](1)
    typeArguments[0] = typeof(int)
    openType: Type = open
    closed := openType.MakeGenericType(typeArguments)
    closedDefinition = definition
    closedArguments = new Type[](1)
    closedArguments[0] = typeof(string)
    closedThrew := false
    try {
        ColumnarSourceDefinitionResolver.TryResolveClosedReceiver(closed, null, out closedDefinition, out closedArguments)
    } catch error: NullReferenceException {
        closedThrew = true
    }
    assert closedThrew
    assert closedDefinition == null
    assert Object.ReferenceEquals(closedArguments, System.Type.EmptyTypes)
}
