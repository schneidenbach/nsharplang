namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
// An async-machine probe HOST: reflectively emits a real type whose public fields mirror an async
// shape's exact layout (TaskAwaiter fields are not yet a modeled N# field surface, so the probe cannot
// be a plain N# class), then realizes every async member from the planner's OWN plans — MoveNextCore,
// MoveNextAsync, DisposeAsync, and a parameterless GetAsyncEnumerator clone — exactly like the C# emit
// host. Contracts drive real machines end to end: suspension registers the continuation, the completed
// Task.Delay re-drives MoveNextCore, and the pending ValueTask<bool> completes. The `(int)` constructor
// stores the state only; NewMachine wires the re-drive Action afterwards (the C# host ctor's ldftn).
class ColumnarAsyncProbeMachine {
    public MachineType: Type
    public Fields: FieldInfo[]
    public StateConstructor: ConstructorInfo
    public Shape: ColumnarIteratorShape

    constructor(probe: ColumnarIteratorShapeProbe, probeName: string) {
        shape := probe.Shape
        Shape = shape
        // The probe type is emitted through reflection invocations (only DynamicMethod-style reflective
        // construction is a modeled N# surface here, exactly like MakeIteratorDynamicMethod below).
        nameCtorTypes := new Type[](1)
        nameCtorTypes[0] = typeof(string)
        nameCtor := typeof(AssemblyName).GetConstructor(nameCtorTypes)
        if nameCtor == null {
            throw new InvalidOperationException("AssemblyName(string) was not found.")
        }
        nameArgs := new object[](1)
        IteratorSetObject(nameArgs, 0, probeName)
        target: object? = null

        assemblyBuilderType := AsyncProbeRuntimeType("System.Reflection.Emit.AssemblyBuilder")
        defineAssemblyTypes := new Type[](2)
        defineAssemblyTypes[0] = AsyncProbeRuntimeType("System.Reflection.AssemblyName")
        defineAssemblyTypes[1] = AsyncProbeRuntimeType("System.Reflection.Emit.AssemblyBuilderAccess")
        defineAssemblyArgs := new object[](2)
        IteratorSetObject(defineAssemblyArgs, 0, nameCtor.Invoke(nameArgs))
        IteratorSetObject(defineAssemblyArgs, 1, AsyncProbeEnumValue("System.Reflection.Emit.AssemblyBuilderAccess", "Run"))
        defineAssemblyMethod := AsyncProbeMethod(assemblyBuilderType, "DefineDynamicAssembly", defineAssemblyTypes)
        assemblyBuilder := AsyncProbeInvoke(defineAssemblyMethod, target, defineAssemblyArgs)

        defineModuleTypes := new Type[](1)
        defineModuleTypes[0] = typeof(string)
        defineModuleArgs := new object[](1)
        IteratorSetObject(defineModuleArgs, 0, "probe")
        defineModuleMethod := AsyncProbeMethod(assemblyBuilderType, "DefineDynamicModule", defineModuleTypes)
        moduleBuilder := AsyncProbeInvoke(defineModuleMethod, assemblyBuilder, defineModuleArgs)

        moduleBuilderType := AsyncProbeRuntimeType("System.Reflection.Emit.ModuleBuilder")
        defineTypeTypes := new Type[](2)
        defineTypeTypes[0] = typeof(string)
        defineTypeTypes[1] = AsyncProbeRuntimeType("System.Reflection.TypeAttributes")
        defineTypeArgs := new object[](2)
        IteratorSetObject(defineTypeArgs, 0, probeName)
        IteratorSetObject(defineTypeArgs, 1, AsyncProbeEnumValue("System.Reflection.TypeAttributes", "Public"))
        defineTypeMethod := AsyncProbeMethod(moduleBuilderType, "DefineType", defineTypeTypes)
        typeBuilderBox := AsyncProbeInvoke(defineTypeMethod, moduleBuilder, defineTypeArgs)
        typeBuilder := (Type)typeBuilderBox

        typeBuilderType := AsyncProbeRuntimeType("System.Reflection.Emit.TypeBuilder")
        defineFieldTypes := new Type[](3)
        defineFieldTypes[0] = typeof(string)
        defineFieldTypes[1] = typeof(Type)
        defineFieldTypes[2] = AsyncProbeRuntimeType("System.Reflection.FieldAttributes")
        defineFieldMethod := AsyncProbeMethod(typeBuilderType, "DefineField", defineFieldTypes)
        publicFieldAttribute := AsyncProbeEnumValue("System.Reflection.FieldAttributes", "Public")
        fieldBuilders := new FieldInfo[](shape.FieldCount)
        i := 0
        while i < shape.FieldCount {
            defineFieldArgs := new object[](3)
            IteratorSetObject(defineFieldArgs, 0, shape.FieldNames[i])
            IteratorSetObject(defineFieldArgs, 1, AsyncProbeFieldRuntimeType(shape, i))
            IteratorSetObject(defineFieldArgs, 2, publicFieldAttribute)
            fieldBox := AsyncProbeInvoke(defineFieldMethod, typeBuilderBox, defineFieldArgs)
            fieldBuilders[i] = (FieldInfo)fieldBox
            i = i + 1
        }

        ctorTypes := new Type[](1)
        ctorTypes[0] = typeof(int)
        defineConstructorTypes := new Type[](3)
        defineConstructorTypes[0] = AsyncProbeRuntimeType("System.Reflection.MethodAttributes")
        defineConstructorTypes[1] = AsyncProbeRuntimeType("System.Reflection.CallingConventions")
        defineConstructorTypes[2] = typeof(Type[])
        defineConstructorArgs := new object[](3)
        IteratorSetObject(defineConstructorArgs, 0, AsyncProbeEnumValue("System.Reflection.MethodAttributes", "Public"))
        IteratorSetObject(defineConstructorArgs, 1, AsyncProbeEnumValue("System.Reflection.CallingConventions", "Standard"))
        IteratorSetObject(defineConstructorArgs, 2, ctorTypes)
        defineConstructorMethod := AsyncProbeMethod(typeBuilderType, "DefineConstructor", defineConstructorTypes)
        ctorBuilder := AsyncProbeInvoke(defineConstructorMethod, typeBuilderBox, defineConstructorArgs)
        constructorBuilderType := AsyncProbeRuntimeType("System.Reflection.Emit.ConstructorBuilder")
        ilGeneratorMethod := AsyncProbeMethod(constructorBuilderType, "GetILGenerator", new Type[](0))
        ctorIlBox := AsyncProbeInvoke(ilGeneratorMethod, ctorBuilder, new object[](0))
        ctorIl := (ILGenerator)ctorIlBox

        // The ctor body replays a schema-4 plan (`this.<>__state = initialState`); System.Object's
        // constructor is a no-op the runtime does not require dynamic-assembly ctors to chain.
        ctorPlan := new ColumnarCodePlan()
        ctorPlan.PrepareMethodBody()
        probeTypeIdx := ctorPlan.AddType(typeBuilder)
        thisArg := ctorPlan.AddArgument(0, probeTypeIdx)
        intTypeIdx := ctorPlan.AddType(typeof(int))
        stateArg := ctorPlan.AddArgument(1, intTypeIdx)
        statePool := ctorPlan.AddField(fieldBuilders[0])
        ctorPlan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), thisArg)
        ctorPlan.AppendArgumentInstruction(ColumnarCodePlanContract.Ldarg(), stateArg)
        ctorPlan.AppendFieldInstruction(ColumnarCodePlanContract.Stfld(), statePool)
        ctorPlan.AppendInstructionWithoutOperand(ColumnarCodePlanContract.Ret())
        voidType := Type.GetType("System.Void")
        if voidType == null {
            throw new InvalidOperationException("System.Void was not found.")
        }
        ctorPlan.CompleteMethodBody(voidType)
        ColumnarCodePlanExecutor.Execute(ctorPlan, ctorIl)

        // The four async members, each realized from the planner's own plan against the unbaked
        // builder handles — the same discipline as the C# emit host.
        methodBuilderType := AsyncProbeRuntimeType("System.Reflection.Emit.MethodBuilder")
        defineMethodTypes := new Type[](4)
        defineMethodTypes[0] = typeof(string)
        defineMethodTypes[1] = AsyncProbeRuntimeType("System.Reflection.MethodAttributes")
        defineMethodTypes[2] = typeof(Type)
        defineMethodTypes[3] = typeof(Type[])
        defineMethodMethod := AsyncProbeMethod(typeBuilderType, "DefineMethod", defineMethodTypes)
        methodIlMethod := AsyncProbeMethod(methodBuilderType, "GetILGenerator", new Type[](0))
        publicMethodAttribute := AsyncProbeEnumValue("System.Reflection.MethodAttributes", "Public")
        noParameterTypes := new Type[](0)

        coreBox := AsyncProbeDefineMethod(
            defineMethodMethod, typeBuilderBox, "MoveNextCore", publicMethodAttribute, voidType, noParameterTypes)
        context := new ColumnarIteratorEmitContext(
            probe.Nodes, probe.Source, probe.BodyRoot, shape, typeBuilder, typeof(int),
            shape.FieldNames, fieldBuilders, (ConstructorInfo)ctorBuilder,
            null, null, null, null, null, null, null, null, (MethodInfo)coreBox)

        coreIl := (ILGenerator)AsyncProbeInvoke(methodIlMethod, coreBox, new object[](0))
        ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildAsyncMoveNextCorePlan(context), coreIl)

        valueTaskOfBool := AsyncProbeValueTaskOfBoolType()
        moveNextAsyncBox := AsyncProbeDefineMethod(
            defineMethodMethod, typeBuilderBox, "MoveNextAsync", publicMethodAttribute, valueTaskOfBool, noParameterTypes)
        moveNextAsyncIl := (ILGenerator)AsyncProbeInvoke(methodIlMethod, moveNextAsyncBox, new object[](0))
        ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildMoveNextAsyncPlan(context), moveNextAsyncIl)

        disposeAsyncBox := AsyncProbeDefineMethod(
            defineMethodMethod, typeBuilderBox, "DisposeAsync", publicMethodAttribute,
            AsyncProbeRuntimeType("System.Threading.Tasks.ValueTask"), noParameterTypes)
        disposeAsyncIl := (ILGenerator)AsyncProbeInvoke(methodIlMethod, disposeAsyncBox, new object[](0))
        ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildDisposeAsyncPlan(context), disposeAsyncIl)

        // The probe's clone view is parameterless and object-typed: the plan ignores the token and the
        // probe type does not implement the async interfaces the real host declares.
        cloneBox := AsyncProbeDefineMethod(
            defineMethodMethod, typeBuilderBox, "GetAsyncEnumerator", publicMethodAttribute, typeof(object), noParameterTypes)
        cloneIl := (ILGenerator)AsyncProbeInvoke(methodIlMethod, cloneBox, new object[](0))
        ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildGetAsyncEnumeratorPlan(context), cloneIl)

        createTypeMethod := AsyncProbeMethod(typeBuilderType, "CreateType", new Type[](0))
        bakedBox := AsyncProbeInvoke(createTypeMethod, typeBuilderBox, new object[](0))
        MachineType = (Type)bakedBox
        Fields = new FieldInfo[](shape.FieldCount)
        i = 0
        while i < shape.FieldCount {
            field := MachineType.GetField(shape.FieldNames[i])
            if field == null {
                throw new InvalidOperationException("Async probe machine lost field '" + shape.FieldNames[i] + "'.")
            }
            Fields[i] = field
            i = i + 1
        }
        bakedConstructor := MachineType.GetConstructor(ctorTypes)
        if bakedConstructor == null {
            throw new InvalidOperationException("Async probe machine lost its (int) constructor.")
        }
        StateConstructor = bakedConstructor
    }

    public func FieldNamed(name: string): FieldInfo {
        i := 0
        while i < Shape.FieldNames.Length {
            if Shape.FieldNames[i] == name {
                return Fields[i]
            }
            i = i + 1
        }
        throw new InvalidOperationException("Async probe machine has no field named '" + name + "'.")
    }

    // Construct a machine at the given state and wire the re-drive continuation to its own
    // MoveNextCore — the exact Action the real host ctor creates with ldftn.
    public func NewMachine(initialState: int): object {
        args := new object[](1)
        IteratorSetObject(args, 0, initialState)
        machine := StateConstructor.Invoke(args)
        actionType := AsyncProbeRuntimeType("System.Action")
        createDelegateTypes := new Type[](3)
        createDelegateTypes[0] = typeof(Type)
        createDelegateTypes[1] = typeof(object)
        createDelegateTypes[2] = typeof(string)
        createDelegateMethod := AsyncProbeMethod(AsyncProbeRuntimeType("System.Delegate"), "CreateDelegate", createDelegateTypes)
        createDelegateArgs := new object[](3)
        IteratorSetObject(createDelegateArgs, 0, actionType)
        IteratorSetObject(createDelegateArgs, 1, machine)
        IteratorSetObject(createDelegateArgs, 2, "MoveNextCore")
        target: object? = null
        continuation := AsyncProbeInvoke(createDelegateMethod, target, createDelegateArgs)
        WriteField(machine, "<>__continuation", continuation)
        return machine
    }

    public func ReadInt(machine: object, name: string): int {
        return Convert.ToInt32(FieldNamed(name).GetValue(machine))
    }

    public func ReadBool(machine: object, name: string): bool {
        return Convert.ToBoolean(FieldNamed(name).GetValue(machine))
    }

    public func ReadField(machine: object, name: string): object? {
        return FieldNamed(name).GetValue(machine)
    }

    public func WriteField(machine: object, name: string, value: object) {
        FieldNamed(name).SetValue(machine, value)
    }

    // Invoke a value-returning probe member (MoveNextAsync/DisposeAsync/GetAsyncEnumerator).
    public func InvokeMember(machine: object, name: string): object {
        method := MachineType.GetMethod(name)
        if method == null {
            throw new InvalidOperationException("Async probe machine has no member named '" + name + "'.")
        }
        return AsyncProbeInvoke(method, machine, new object[](0))
    }

    public func InvokeVoidMember(machine: object, name: string) {
        method := MachineType.GetMethod(name)
        if method == null {
            throw new InvalidOperationException("Async probe machine has no member named '" + name + "'.")
        }
        args := new object[](0)
        method.Invoke(machine, args)
    }
}

func AsyncProbeDefineMethod(
    defineMethodMethod: MethodInfo,
    typeBuilderBox: object,
    name: string,
    attribute: object,
    returnType: Type,
    parameterTypes: Type[]): object {
    args := new object[](4)
    IteratorSetObject(args, 0, name)
    IteratorSetObject(args, 1, attribute)
    IteratorSetObject(args, 2, returnType)
    IteratorSetObject(args, 3, parameterTypes)
    return AsyncProbeInvoke(defineMethodMethod, typeBuilderBox, args)
}

func AsyncProbeValueTaskOfBoolType(): Type {
    boolArgs := new Type[](1)
    boolArgs[0] = typeof(bool)
    return AsyncProbeRuntimeType("System.Threading.Tasks.ValueTask`1").MakeGenericType(boolArgs)
}

// Read a completed ValueTask<bool>'s outcome (or a ValueTask's completion flag) through reflection —
// the boxed struct's getters are the only modeled surface for the probe's return values.
func AsyncProbeValueTaskGetter(valueTaskBox: object, getterName: string): bool {
    method := valueTaskBox.GetType().GetMethod(getterName)
    if method == null {
        throw new InvalidOperationException("ValueTask getter '" + getterName + "' was not found.")
    }
    return Convert.ToBoolean(AsyncProbeInvoke(method, valueTaskBox, new object[](0)))
}

// Convert a pending ValueTask<bool> to its Task<bool>, wait for it (bounded), and return its result.
func AsyncProbeAwaitValueTask(valueTaskBox: object, timeoutMilliseconds: int): bool {
    asTaskMethod := valueTaskBox.GetType().GetMethod("AsTask")
    if asTaskMethod == null {
        throw new InvalidOperationException("ValueTask<bool>.AsTask was not found.")
    }
    taskBox := AsyncProbeInvoke(asTaskMethod, valueTaskBox, new object[](0))
    waitTypes := new Type[](1)
    waitTypes[0] = typeof(int)
    waitMethod := AsyncProbeMethod(taskBox.GetType(), "Wait", waitTypes)
    waitArgs := new object[](1)
    IteratorSetObject(waitArgs, 0, timeoutMilliseconds)
    if !Convert.ToBoolean(AsyncProbeInvoke(waitMethod, taskBox, waitArgs)) {
        throw new InvalidOperationException("The pending ValueTask<bool> did not complete in time.")
    }
    resultMethod := AsyncProbeMethod(taskBox.GetType(), "get_Result", new Type[](0))
    return Convert.ToBoolean(AsyncProbeInvoke(resultMethod, taskBox, new object[](0)))
}

func AsyncProbeFieldRuntimeType(shape: ColumnarIteratorShape, index: int): Type {
    role := shape.FieldRoles[index]
    if role == ColumnarIteratorPlanner.AwaiterFieldRole() {
        return AsyncProbeRuntimeType("System.Runtime.CompilerServices.TaskAwaiter")
    }
    if role == ColumnarIteratorPlanner.PromiseFieldRole() {
        boolArgs := new Type[](1)
        boolArgs[0] = typeof(bool)
        return AsyncProbeRuntimeType("System.Threading.Tasks.TaskCompletionSource`1").MakeGenericType(boolArgs)
    }
    if role == ColumnarIteratorPlanner.ContinuationFieldRole() {
        return AsyncProbeRuntimeType("System.Action")
    }
    if role == ColumnarIteratorPlanner.ResultFieldRole() {
        return typeof(bool)
    }
    canonical := shape.FieldCanonicals[index]
    if canonical == "int" {
        return typeof(int)
    }
    if canonical == "bool" {
        return typeof(bool)
    }
    if canonical == "string" {
        return typeof(string)
    }
    throw new InvalidOperationException("Async probe machine has no runtime type for '" + canonical + "'.")
}

func AsyncProbeRuntimeType(name: string): Type {
    resolved := Type.GetType(name)
    if resolved == null {
        throw new InvalidOperationException(name + " was not found.")
    }
    return resolved
}

func AsyncProbeMethod(owner: Type, name: string, parameterTypes: Type[]): MethodInfo {
    method := owner.GetMethod(name, parameterTypes)
    if method == null {
        throw new InvalidOperationException(owner.FullName + "." + name + " was not found.")
    }
    return method
}

func AsyncProbeInvoke(method: MethodInfo, receiver: object?, args: object[]): object {
    result := method.Invoke(receiver, args)
    if result == null {
        throw new InvalidOperationException("An async probe reflection call unexpectedly returned null.")
    }
    return result
}

// A boxed enum constant read from its static field, so reflective Invoke sees the exact enum type.
func AsyncProbeEnumValue(enumTypeName: string, memberName: string): object {
    enumType := AsyncProbeRuntimeType(enumTypeName)
    field := enumType.GetField(memberName)
    if field == null {
        throw new InvalidOperationException(enumTypeName + "." + memberName + " was not found.")
    }
    target: object? = null
    value := field.GetValue(target)
    if value == null {
        throw new InvalidOperationException(enumTypeName + "." + memberName + " read as null.")
    }
    return value
}

// A plain class whose public fields stand in for a synthesized state machine's fields, so a contract can
// execute the planner's MoveNext/get_Current plans onto DynamicMethods and run a real iterator without the
// C# emitter host.
public class ColumnarIteratorRunProbe {
    public state: int
    public current: int
    public n: int
    public i: int

    constructor() {
        state = 0
        current = 0
        n = 0
        i = 0
    }
}

// Parses a func* body into a columnar node table and runs the iterator planner's decision layer on it.
// Signature facts (return canonical, parameters, type parameters, instance receiver) are supplied
// explicitly so a contract exercises exactly one decision at a time.
class ColumnarIteratorShapeProbe {
    public Shape: ColumnarIteratorShape
    public Nodes: ColumnarNodeTable
    public BodyRoot: int
    public Source: string

    constructor(
        source: string,
        returnCanonical: string,
        paramNames: string[],
        paramCanonicals: string[],
        typeParamNames: string[],
        isInstance: bool,
        isAsync: bool = false) {
        capacity := source.Length * 3 + 16
        rawKinds := new int[](capacity)
        rawStarts := new int[](capacity)
        rawValueLengths := new int[](capacity)
        tokenKinds := new int[](capacity)
        tokenStarts := new int[](capacity)
        tokenValueLengths := new int[](capacity)
        tokenCounts := new int[](2)
        tokenCount := TokenizeColumnarSourceInto(
            source, rawKinds, rawStarts, rawValueLengths,
            tokenKinds, tokenStarts, tokenValueLengths, tokenCounts)

        funcIndex := 0
        while funcIndex < tokenCount && tokenKinds[funcIndex] != 7 {
            funcIndex = funcIndex + 1
        }

        functionNameTexts := new string[](1)
        returnTypeTexts := new string[](1)
        paramNameTexts := new string[](capacity)
        paramTypeTexts := new string[](capacity)
        paramModifierKinds := new int[](capacity)
        paramDefaultKinds := new int[](capacity)
        paramDefaultTexts := new string[](capacity)
        paramTupleNameCounts := new int[](capacity)
        paramTupleNameTexts := new string[](capacity)
        returnTupleNameTexts := new string[](capacity)
        typeParamTexts := new string[](capacity)
        typeParamSpecials := new int[](capacity)
        typeParamConstraintCounts := new int[](capacity)
        typeParamConstraintTypeTexts := new string[](capacity)
        nodeKinds := new int[](capacity)
        valueStarts := new int[](capacity)
        valueLengths := new int[](capacity)
        childStart := new int[](capacity)
        childCount := new int[](capacity)
        childIndices := new int[](capacity)
        spanStarts := new int[](capacity)
        spanLengths := new int[](capacity)
        localFunctionNodeIndices := new int[](capacity)
        localFunctionTokenIndices := new int[](capacity)
        result := new int[](9)

        status := ParseColumnarProductFunctionInfoInto(
            source, tokenKinds, tokenStarts, tokenValueLengths, tokenCount, funcIndex, 0,
            functionNameTexts, returnTypeTexts, paramNameTexts, paramTypeTexts, paramModifierKinds,
            paramDefaultKinds, paramDefaultTexts, paramTupleNameCounts, paramTupleNameTexts,
            returnTupleNameTexts, typeParamTexts, typeParamSpecials, typeParamConstraintCounts,
            typeParamConstraintTypeTexts, nodeKinds, valueStarts, valueLengths, childStart, childCount,
            childIndices, spanStarts, spanLengths, localFunctionNodeIndices, localFunctionTokenIndices, result)
        if status < 0 {
            throw new InvalidOperationException("Iterator-shape probe could not parse the func* body.")
        }

        bodyRoot := result[6]
        nodes := new ColumnarNodeTable(
            nodeKinds, valueStarts, valueLengths, childStart, childCount, childIndices, spanStarts, spanLengths)
        Nodes = nodes
        BodyRoot = bodyRoot
        Source = source
        Shape = ColumnarIteratorPlanner.AnalyzeShape(
            nodes, source, bodyRoot, "Gen", 0, returnCanonical, paramNames, paramCanonicals, typeParamNames, isInstance,
            "", new string[](0), new string[](0), new string[](0), new string[](0), isAsync)
    }
}

func IteratorSetObject(values: object[], index: int, value: object) {
    values[index] = value
}

func MakeIteratorDynamicMethod(name: string, returnType: Type, parameterType: Type): DynamicMethod {
    constructorTypes := new Type[](3)
    constructorTypes[0] = typeof(string)
    constructorTypes[1] = typeof(Type)
    constructorTypes[2] = typeof(Type[])
    ctor := typeof(DynamicMethod).GetConstructor(constructorTypes)
    if ctor == null {
        throw new InvalidOperationException("Required DynamicMethod constructor was not found.")
    }
    paramTypes := new Type[](1)
    paramTypes[0] = parameterType
    args := new object[](3)
    IteratorSetObject(args, 0, name)
    IteratorSetObject(args, 1, returnType)
    IteratorSetObject(args, 2, paramTypes)
    return (DynamicMethod)ctor.Invoke(args)
}

func IteratorNoStrings(): string[] {
    return new string[](0)
}

func IteratorOne(a: string): string[] {
    values := new string[](1)
    values[0] = a
    return values
}

test "iterator planner numbers zero yields with two fields and no resume states" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Zero(): IEnumerable<int> { }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)

    assert probe.Shape.Supported
    assert probe.Shape.ElementCanonical == "int"
    assert probe.Shape.YieldReturnCount == 0
    assert probe.Shape.FieldCount == 2
    assert probe.Shape.InitialState == 0
    assert probe.Shape.RunningState == -1
    assert probe.Shape.DoneState == -2
}

test "iterator planner numbers a single yield as one resume state" {
    probe := new ColumnarIteratorShapeProbe(
        "func* One(): IEnumerable<int> { yield 5 }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)

    assert probe.Shape.Supported
    assert probe.Shape.YieldReturnCount == 1
}

test "iterator planner numbers many yields sequentially" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Many(): IEnumerable<int> { yield 1\n yield 2\n yield 3 }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)

    assert probe.Shape.Supported
    assert probe.Shape.YieldReturnCount == 3
}

test "iterator planner excludes yield break from the resume-state count" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Break(): IEnumerable<int> { yield 1\n yield break }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)

    assert probe.Shape.Supported
    assert probe.Shape.YieldReturnCount == 1
}

test "iterator planner lays out state, current, parameters, then locals in hoist order" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Count(n: int): IEnumerable<int> { i: int = 0\n while i < n { yield i\n i = i + 1 } }",
        "IEnumerable<int>", IteratorOne("n"), IteratorOne("int"), IteratorNoStrings(), false)

    assert probe.Shape.Supported
    assert probe.Shape.YieldReturnCount == 1
    assert probe.Shape.FieldCount == 4
    assert probe.Shape.FieldNames[0] == "<>__state"
    assert probe.Shape.FieldRoles[0] == ColumnarIteratorPlanner.StateFieldRole()
    assert probe.Shape.FieldCanonicals[0] == "int"
    assert probe.Shape.FieldNames[1] == "<>__current"
    assert probe.Shape.FieldRoles[1] == ColumnarIteratorPlanner.CurrentFieldRole()
    assert probe.Shape.FieldNames[2] == "n"
    assert probe.Shape.FieldRoles[2] == ColumnarIteratorPlanner.CapturedParameterFieldRole()
    assert probe.Shape.FieldNames[3] == "i"
    assert probe.Shape.FieldRoles[3] == ColumnarIteratorPlanner.HoistedLocalFieldRole()
    assert probe.Shape.FieldCanonicals[3] == "int"
}

test "iterator planner infers the element type from an IEnumerable<T> return" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Strings(): IEnumerable<string> { yield break }",
        "IEnumerable<string>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)

    assert probe.Shape.Supported
    assert probe.Shape.ElementCanonical == "string"
    assert probe.Shape.FieldCanonicals[1] == "string"
}

test "iterator planner exposes the eight member and override specs" {
    probe := new ColumnarIteratorShapeProbe(
        "func* One(): IEnumerable<int> { yield 5 }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)

    assert probe.Shape.MemberCount == 8
    assert probe.Shape.MemberNames[0] == ".ctor"
    assert probe.Shape.MemberNames[1] == "MoveNext"
    assert probe.Shape.MemberOverrides[1] == "System.Collections.IEnumerator.MoveNext"
    assert probe.Shape.MemberNames[2] == "get_Current"
    assert probe.Shape.MemberSignatures[2] == "():int"
    assert probe.Shape.MemberNames[6] == "GetEnumerator"
    assert probe.Shape.MemberSignatures[6] == "():IEnumerator<int>"
}

test "iterator planner models a generic iterator element as the type parameter" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Repeat(): IEnumerable<T> { yield break }",
        "IEnumerable<T>", IteratorNoStrings(), IteratorNoStrings(), IteratorOne("T"), false)

    assert probe.Shape.Supported
    assert probe.Shape.ElementCanonical == "T"
    assert probe.Shape.FieldCanonicals[1] == "T"
}

func IteratorTwo(a: string, b: string): string[] {
    values := new string[](2)
    values[0] = a
    values[1] = b
    return values
}

test "iterator planner captures type-parameter values in the repeat shape" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Repeat(value: T, count: int): IEnumerable<T> { i: int = 0\n while i < count { yield value\n i = i + 1 } }",
        "IEnumerable<T>", IteratorTwo("value", "count"), IteratorTwo("T", "int"), IteratorOne("T"), false)

    assert probe.Shape.Supported
    assert probe.Shape.YieldReturnCount == 1
    assert probe.Shape.FieldCount == 5
    assert probe.Shape.FieldCanonicals[1] == "T"
    assert probe.Shape.FieldNames[2] == "value"
    assert probe.Shape.FieldCanonicals[2] == "T"
    assert probe.Shape.FieldNames[3] == "count"
    assert probe.Shape.FieldCanonicals[3] == "int"
    assert probe.Shape.FieldNames[4] == "i"
}

test "iterator planner declines binaries over type-parameter operands" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Sum(value: T, count: int): IEnumerable<T> { yield value + value }",
        "IEnumerable<T>", IteratorTwo("value", "count"), IteratorTwo("T", "int"), IteratorOne("T"), false)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.unsupported-shape"
}

test "iterator planner hoists an enumerable for..in as an enumerator field" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Loop(items: IEnumerable<int>): IEnumerable<int> { for x in items { yield x } }",
        "IEnumerable<int>", IteratorOne("items"), IteratorOne("IEnumerable<int>"), IteratorNoStrings(), false)

    assert probe.Shape.Supported
    assert probe.Shape.FieldCount == 5
    assert probe.Shape.FieldNames[2] == "items"
    assert probe.Shape.FieldCanonicals[2] == "IEnumerable<int>"
    assert probe.Shape.FieldNames[3] == "<>__enum0"
    assert probe.Shape.FieldRoles[3] == ColumnarIteratorPlanner.HoistedEnumeratorFieldRole()
    assert probe.Shape.FieldCanonicals[3] == "IEnumerator<int>"
    assert probe.Shape.FieldNames[4] == "x"
    assert probe.Shape.FieldRoles[4] == ColumnarIteratorPlanner.HoistedLocalFieldRole()
    assert probe.Shape.FieldCanonicals[4] == "int"
}

test "iterator planner hoists a list for..in through the same enumerator lowering" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Loop(items: List<int>): IEnumerable<int> { for x in items { yield x } }",
        "IEnumerable<int>", IteratorOne("items"), IteratorOne("List<int>"), IteratorNoStrings(), false)

    assert probe.Shape.Supported
    assert probe.Shape.FieldCanonicals[2] == "List<int>"
    assert probe.Shape.FieldRoles[3] == ColumnarIteratorPlanner.HoistedEnumeratorFieldRole()
    assert probe.Shape.FieldCanonicals[3] == "IEnumerator<int>"
}

test "iterator planner declines for..in over a non-sequence source" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Loop(n: int): IEnumerable<int> { for x in n { yield x } }",
        "IEnumerable<int>", IteratorOne("n"), IteratorOne("int"), IteratorNoStrings(), false)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.for-in-unsupported"
}

test "iterator planner declines for..in over an unlowered array element" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Loop(xs: int[][]): IEnumerable<int> { for x in xs { yield 1 } }",
        "IEnumerable<int>", IteratorOne("xs"), IteratorOne("int[][]"), IteratorNoStrings(), false)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.for-in-unsupported"
}

test "iterator planner declines an instance receiver" {
    probe := new ColumnarIteratorShapeProbe(
        "func* One(): IEnumerable<int> { yield 5 }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), true)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.instance-unsupported"
}

test "iterator planner declines a nested or recursive call in the body" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Nested(): IEnumerable<int> { yield Other() }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.nested-unsupported"
}

test "iterator planner declines an otherwise-unlowered throw shape" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Throwing(): IEnumerable<int> { throw MakeError() }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.unsupported-shape"
}

test "iterator planner MoveNext and get_Current plans run a counting iterator sequence" {
    source := "func* Count(n: int): IEnumerable<int> { i: int = 0\n while i < n { yield i\n i = i + 1 } }"
    probe := new ColumnarIteratorShapeProbe(
        source, "IEnumerable<int>", IteratorOne("n"), IteratorOne("int"), IteratorNoStrings(), false)
    assert probe.Shape.Supported
    assert probe.Shape.FieldCount == 4

    smType := typeof(ColumnarIteratorRunProbe)
    fields := new FieldInfo[](4)
    fields[0] = smType.GetField("state")
    fields[1] = smType.GetField("current")
    fields[2] = smType.GetField("n")
    fields[3] = smType.GetField("i")
    context := new ColumnarIteratorEmitContext(
        probe.Nodes, probe.Source, probe.BodyRoot, probe.Shape, smType, typeof(int), probe.Shape.FieldNames, fields)

    moveNextPlan := ColumnarIteratorBodyPlanner.BuildMoveNextPlan(context)
    getCurrentPlan := ColumnarIteratorBodyPlanner.BuildGetCurrentPlan(context)

    moveNext := MakeIteratorDynamicMethod("MoveNext", typeof(bool), smType)
    ColumnarCodePlanExecutor.Execute(moveNextPlan, moveNext.GetILGenerator())
    getCurrent := MakeIteratorDynamicMethod("get_Current", typeof(int), smType)
    ColumnarCodePlanExecutor.Execute(getCurrentPlan, getCurrent.GetILGenerator())

    machine := new ColumnarIteratorRunProbe()
    machine.state = 0
    machine.n = 5
    invokeArgs := new object[](1)
    IteratorSetObject(invokeArgs, 0, machine)

    target: object? = null
    results := new List<int>()
    moveResult := moveNext.Invoke(target, invokeArgs)
    hasNext := Convert.ToBoolean(moveResult)
    while hasNext {
        currentResult := getCurrent.Invoke(target, invokeArgs)
        results.Add(Convert.ToInt32(currentResult))
        moveResult = moveNext.Invoke(target, invokeArgs)
        hasNext = Convert.ToBoolean(moveResult)
    }

    assert results.Count == 5
    assert results[0] == 0
    assert results[1] == 1
    assert results[2] == 2
    assert results[3] == 3
    assert results[4] == 4
}

// A run-probe machine with the `.ctor(int)` shape the clone and factory plans construct through.
public class ColumnarIteratorCloneProbe {
    public state: int
    public current: int
    public n: int
    public i: int

    constructor(initialState: int) {
        state = initialState
        current = 0
        n = 0
        i = 0
    }
}

func IteratorVoidType(): Type {
    voidType := Type.GetType("System.Void")
    if voidType == null {
        throw new InvalidOperationException("System.Void was not found.")
    }
    return voidType
}

func IteratorCloneProbeContext(): ColumnarIteratorEmitContext {
    source := "func* Count(n: int): IEnumerable<int> { i: int = 0\n while i < n { yield i\n i = i + 1 } }"
    probe := new ColumnarIteratorShapeProbe(
        source, "IEnumerable<int>", IteratorOne("n"), IteratorOne("int"), IteratorNoStrings(), false)
    smType := typeof(ColumnarIteratorCloneProbe)
    fields := new FieldInfo[](4)
    fields[0] = smType.GetField("state")
    fields[1] = smType.GetField("current")
    fields[2] = smType.GetField("n")
    fields[3] = smType.GetField("i")
    ctorTypes := new Type[](1)
    ctorTypes[0] = typeof(int)
    smConstructor := smType.GetConstructor(ctorTypes)
    if smConstructor == null {
        throw new InvalidOperationException("ColumnarIteratorCloneProbe.ctor(int) was not found.")
    }
    return new ColumnarIteratorEmitContext(
        probe.Nodes, probe.Source, probe.BodyRoot, probe.Shape, smType, typeof(int),
        probe.Shape.FieldNames, fields, smConstructor)
}

test "iterator planner dispose plan marks the machine done" {
    context := IteratorCloneProbeContext()
    disposePlan := ColumnarIteratorBodyPlanner.BuildDisposePlan(context)
    dispose := MakeIteratorDynamicMethod("Dispose", IteratorVoidType(), context.StateMachineType)
    ColumnarCodePlanExecutor.Execute(disposePlan, dispose.GetILGenerator())

    machine := new ColumnarIteratorCloneProbe(0)
    machine.state = 5
    invokeArgs := new object[](1)
    IteratorSetObject(invokeArgs, 0, machine)
    target: object? = null
    dispose.Invoke(target, invokeArgs)

    assert machine.state == -2
}

test "iterator planner reset plan throws NotSupportedException" {
    resetPlan := ColumnarIteratorBodyPlanner.BuildResetPlan()
    context := IteratorCloneProbeContext()
    reset := MakeIteratorDynamicMethod("Reset", IteratorVoidType(), context.StateMachineType)
    ColumnarCodePlanExecutor.Execute(resetPlan, reset.GetILGenerator())

    machine := new ColumnarIteratorCloneProbe(0)
    invokeArgs := new object[](1)
    IteratorSetObject(invokeArgs, 0, machine)
    target: object? = null
    threwNotSupported := false
    try {
        reset.Invoke(target, invokeArgs)
    } catch ex: Exception {
        // reflection Invoke wraps the plan's NotSupportedException in TargetInvocationException.
        innerBox: object? = ex.get_InnerException()
        threwNotSupported = innerBox != null && innerBox.GetType() == typeof(NotSupportedException)
    }

    assert threwNotSupported
}

test "iterator planner interface current plan boxes the value element" {
    context := IteratorCloneProbeContext()
    currentPlan := ColumnarIteratorBodyPlanner.BuildInterfaceGetCurrentPlan(context)
    boxedCurrent := MakeIteratorDynamicMethod("BoxedCurrent", typeof(object), context.StateMachineType)
    ColumnarCodePlanExecutor.Execute(currentPlan, boxedCurrent.GetILGenerator())

    machine := new ColumnarIteratorCloneProbe(0)
    machine.current = 42
    invokeArgs := new object[](1)
    IteratorSetObject(invokeArgs, 0, machine)
    target: object? = null
    boxedResult := boxedCurrent.Invoke(target, invokeArgs)

    assert Convert.ToInt32(boxedResult) == 42
}

test "iterator planner clone plan starts a fresh machine with captured parameters" {
    context := IteratorCloneProbeContext()
    clonePlan := ColumnarIteratorBodyPlanner.BuildGetEnumeratorPlan(context)
    getEnumerator := MakeIteratorDynamicMethod("GetEnumerator", typeof(object), context.StateMachineType)
    ColumnarCodePlanExecutor.Execute(clonePlan, getEnumerator.GetILGenerator())

    machine := new ColumnarIteratorCloneProbe(0)
    machine.state = 3
    machine.n = 7
    machine.i = 5
    machine.current = 9
    invokeArgs := new object[](1)
    IteratorSetObject(invokeArgs, 0, machine)
    target: object? = null
    clone := (ColumnarIteratorCloneProbe)getEnumerator.Invoke(target, invokeArgs)

    assert !Object.ReferenceEquals(machine, clone)
    assert clone.state == 0
    assert clone.n == 7
    assert clone.i == 0
    assert clone.current == 0
}

test "iterator planner interface enumerator plan mirrors the clone body" {
    context := IteratorCloneProbeContext()
    clonePlan := ColumnarIteratorBodyPlanner.BuildInterfaceGetEnumeratorPlan(context)
    getEnumerator := MakeIteratorDynamicMethod("InterfaceGetEnumerator", typeof(object), context.StateMachineType)
    ColumnarCodePlanExecutor.Execute(clonePlan, getEnumerator.GetILGenerator())

    machine := new ColumnarIteratorCloneProbe(0)
    machine.state = -2
    machine.n = 11
    invokeArgs := new object[](1)
    IteratorSetObject(invokeArgs, 0, machine)
    target: object? = null
    clone := (ColumnarIteratorCloneProbe)getEnumerator.Invoke(target, invokeArgs)

    assert !Object.ReferenceEquals(machine, clone)
    assert clone.state == 0
    assert clone.n == 11
}

test "iterator planner drops dead statements after yield break" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Dead(): IEnumerable<int> { yield break\n yield 5 }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)

    assert probe.Shape.Supported
    assert probe.Shape.YieldReturnCount == 0
}

test "iterator planner guard yield break plans run for both branch outcomes" {
    source := "func* Guarded(n: int): IEnumerable<int> { if n <= 0 { yield break }\n yield 1\n yield 2 }"
    probe := new ColumnarIteratorShapeProbe(
        source, "IEnumerable<int>", IteratorOne("n"), IteratorOne("int"), IteratorNoStrings(), false)
    assert probe.Shape.Supported
    assert probe.Shape.YieldReturnCount == 2
    assert probe.Shape.FieldCount == 3

    smType := typeof(ColumnarIteratorCloneProbe)
    fields := new FieldInfo[](3)
    fields[0] = smType.GetField("state")
    fields[1] = smType.GetField("current")
    fields[2] = smType.GetField("n")
    context := new ColumnarIteratorEmitContext(
        probe.Nodes, probe.Source, probe.BodyRoot, probe.Shape, smType, typeof(int), probe.Shape.FieldNames, fields)

    moveNextPlan := ColumnarIteratorBodyPlanner.BuildMoveNextPlan(context)
    getCurrentPlan := ColumnarIteratorBodyPlanner.BuildGetCurrentPlan(context)
    moveNext := MakeIteratorDynamicMethod("GuardedMoveNext", typeof(bool), smType)
    ColumnarCodePlanExecutor.Execute(moveNextPlan, moveNext.GetILGenerator())
    getCurrent := MakeIteratorDynamicMethod("GuardedCurrent", typeof(int), smType)
    ColumnarCodePlanExecutor.Execute(getCurrentPlan, getCurrent.GetILGenerator())

    target: object? = null

    guardedMachine := new ColumnarIteratorCloneProbe(0)
    guardedMachine.n = 0
    guardedArgs := new object[](1)
    IteratorSetObject(guardedArgs, 0, guardedMachine)
    assert !Convert.ToBoolean(moveNext.Invoke(target, guardedArgs))

    yieldingMachine := new ColumnarIteratorCloneProbe(0)
    yieldingMachine.n = 3
    yieldingArgs := new object[](1)
    IteratorSetObject(yieldingArgs, 0, yieldingMachine)
    results := new List<int>()
    hasNext := Convert.ToBoolean(moveNext.Invoke(target, yieldingArgs))
    while hasNext {
        results.Add(Convert.ToInt32(getCurrent.Invoke(target, yieldingArgs)))
        hasNext = Convert.ToBoolean(moveNext.Invoke(target, yieldingArgs))
    }
    assert results.Count == 2
    assert results[0] == 1
    assert results[1] == 2
}

test "iterator planner while body ending in yield break omits the back edge" {
    source := "func* LoopBreak(n: int): IEnumerable<int> { while n > 0 { yield break } }"
    probe := new ColumnarIteratorShapeProbe(
        source, "IEnumerable<int>", IteratorOne("n"), IteratorOne("int"), IteratorNoStrings(), false)
    assert probe.Shape.Supported
    assert probe.Shape.YieldReturnCount == 0

    smType := typeof(ColumnarIteratorCloneProbe)
    fields := new FieldInfo[](3)
    fields[0] = smType.GetField("state")
    fields[1] = smType.GetField("current")
    fields[2] = smType.GetField("n")
    context := new ColumnarIteratorEmitContext(
        probe.Nodes, probe.Source, probe.BodyRoot, probe.Shape, smType, typeof(int), probe.Shape.FieldNames, fields)

    moveNextPlan := ColumnarIteratorBodyPlanner.BuildMoveNextPlan(context)
    moveNext := MakeIteratorDynamicMethod("LoopBreakMoveNext", typeof(bool), smType)
    ColumnarCodePlanExecutor.Execute(moveNextPlan, moveNext.GetILGenerator())

    machine := new ColumnarIteratorCloneProbe(0)
    machine.n = 1
    invokeArgs := new object[](1)
    IteratorSetObject(invokeArgs, 0, machine)
    target: object? = null
    assert !Convert.ToBoolean(moveNext.Invoke(target, invokeArgs))
}

test "iterator planner factory plan constructs the machine from arguments" {
    context := IteratorCloneProbeContext()
    factoryPlan := ColumnarIteratorBodyPlanner.BuildFactoryPlan(context)
    factory := MakeIteratorDynamicMethod("Factory", typeof(object), typeof(int))
    ColumnarCodePlanExecutor.Execute(factoryPlan, factory.GetILGenerator())

    invokeArgs := new object[](1)
    IteratorSetObject(invokeArgs, 0, 11)
    target: object? = null
    machine := (ColumnarIteratorCloneProbe)factory.Invoke(target, invokeArgs)

    assert machine.state == 0
    assert machine.n == 11
    assert machine.i == 0
    assert machine.current == 0
}

// A run-probe machine for the array for..in lowering: a captured array parameter plus the loop's
// synthetic index and element fields.
public class ColumnarIteratorArrayProbe {
    public state: int
    public current: int
    public xs: int[]
    public idx: int
    public x: int

    constructor(initialState: int) {
        state = initialState
        current = 0
        xs = new int[](0)
        idx = 0
        x = 0
    }
}

test "iterator planner hoists array for..in loops as index plus element fields" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Pass(xs: int[]): IEnumerable<int> { for x in xs { yield x } }",
        "IEnumerable<int>", IteratorOne("xs"), IteratorOne("int[]"), IteratorNoStrings(), false)

    assert probe.Shape.Supported
    assert probe.Shape.YieldReturnCount == 1
    assert probe.Shape.FieldCount == 5
    assert probe.Shape.FieldNames[2] == "xs"
    assert probe.Shape.FieldRoles[2] == ColumnarIteratorPlanner.CapturedParameterFieldRole()
    assert probe.Shape.FieldCanonicals[2] == "int[]"
    assert probe.Shape.FieldNames[3] == "<>__index0"
    assert probe.Shape.FieldRoles[3] == ColumnarIteratorPlanner.HoistedLocalFieldRole()
    assert probe.Shape.FieldCanonicals[3] == "int"
    assert probe.Shape.FieldNames[4] == "x"
    assert probe.Shape.FieldRoles[4] == ColumnarIteratorPlanner.HoistedLocalFieldRole()
    assert probe.Shape.FieldCanonicals[4] == "int"
}

func IteratorArrayProbeContext(source: string): ColumnarIteratorEmitContext {
    probe := new ColumnarIteratorShapeProbe(
        source, "IEnumerable<int>", IteratorOne("xs"), IteratorOne("int[]"), IteratorNoStrings(), false)
    if !probe.Shape.Supported {
        throw new InvalidOperationException("Array probe shape unexpectedly declined: " + probe.Shape.DeclineMessage)
    }
    smType := typeof(ColumnarIteratorArrayProbe)
    fields := new FieldInfo[](5)
    fields[0] = smType.GetField("state")
    fields[1] = smType.GetField("current")
    fields[2] = smType.GetField("xs")
    fields[3] = smType.GetField("idx")
    fields[4] = smType.GetField("x")
    return new ColumnarIteratorEmitContext(
        probe.Nodes, probe.Source, probe.BodyRoot, probe.Shape, smType, typeof(int),
        probe.Shape.FieldNames, fields)
}

test "iterator planner array for..in plans run the full element sequence" {
    context := IteratorArrayProbeContext(
        "func* Pass(xs: int[]): IEnumerable<int> { for x in xs { yield x } }")
    moveNext := MakeIteratorDynamicMethod("ArrayMoveNext", typeof(bool), context.StateMachineType)
    ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildMoveNextPlan(context), moveNext.GetILGenerator())
    getCurrent := MakeIteratorDynamicMethod("ArrayCurrent", typeof(int), context.StateMachineType)
    ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildGetCurrentPlan(context), getCurrent.GetILGenerator())

    machine := new ColumnarIteratorArrayProbe(0)
    values := new int[](3)
    values[0] = 7
    values[1] = 8
    values[2] = 9
    machine.xs = values
    invokeArgs := new object[](1)
    IteratorSetObject(invokeArgs, 0, machine)
    target: object? = null
    results := new List<int>()
    hasNext := Convert.ToBoolean(moveNext.Invoke(target, invokeArgs))
    while hasNext {
        results.Add(Convert.ToInt32(getCurrent.Invoke(target, invokeArgs)))
        hasNext = Convert.ToBoolean(moveNext.Invoke(target, invokeArgs))
    }

    assert results.Count == 3
    assert results[0] == 7
    assert results[1] == 8
    assert results[2] == 9
}

test "iterator planner array for..in with a guard break stops mid-array" {
    context := IteratorArrayProbeContext(
        "func* Until(xs: int[]): IEnumerable<int> { for x in xs { if x < 0 { yield break }\n yield x } }")
    moveNext := MakeIteratorDynamicMethod("GuardArrayMoveNext", typeof(bool), context.StateMachineType)
    ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildMoveNextPlan(context), moveNext.GetILGenerator())
    getCurrent := MakeIteratorDynamicMethod("GuardArrayCurrent", typeof(int), context.StateMachineType)
    ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildGetCurrentPlan(context), getCurrent.GetILGenerator())

    machine := new ColumnarIteratorArrayProbe(0)
    values := new int[](4)
    values[0] = 5
    values[1] = 6
    values[2] = -1
    values[3] = 9
    machine.xs = values
    invokeArgs := new object[](1)
    IteratorSetObject(invokeArgs, 0, machine)
    target: object? = null
    results := new List<int>()
    hasNext := Convert.ToBoolean(moveNext.Invoke(target, invokeArgs))
    while hasNext {
        results.Add(Convert.ToInt32(getCurrent.Invoke(target, invokeArgs)))
        hasNext = Convert.ToBoolean(moveNext.Invoke(target, invokeArgs))
    }

    assert results.Count == 2
    assert results[0] == 5
    assert results[1] == 6
}

test "iterator planner throw plans classify and raise the constructed exception" {
    source := "func* Guard(n: int): IEnumerable<int> { if n == 0 { throw new ArgumentException(\"bad step\") }\n yield 1 }"
    probe := new ColumnarIteratorShapeProbe(
        source, "IEnumerable<int>", IteratorOne("n"), IteratorOne("int"), IteratorNoStrings(), false)
    assert probe.Shape.Supported
    assert probe.Shape.YieldReturnCount == 1

    smType := typeof(ColumnarIteratorCloneProbe)
    fields := new FieldInfo[](3)
    fields[0] = smType.GetField("state")
    fields[1] = smType.GetField("current")
    fields[2] = smType.GetField("n")
    context := new ColumnarIteratorEmitContext(
        probe.Nodes, probe.Source, probe.BodyRoot, probe.Shape, smType, typeof(int), probe.Shape.FieldNames, fields)
    moveNext := MakeIteratorDynamicMethod("ThrowMoveNext", typeof(bool), smType)
    ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildMoveNextPlan(context), moveNext.GetILGenerator())
    getCurrent := MakeIteratorDynamicMethod("ThrowCurrent", typeof(int), smType)
    ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildGetCurrentPlan(context), getCurrent.GetILGenerator())

    target: object? = null

    throwingMachine := new ColumnarIteratorCloneProbe(0)
    throwingMachine.n = 0
    throwingArgs := new object[](1)
    IteratorSetObject(throwingArgs, 0, throwingMachine)
    threwArgument := false
    thrownMessage := ""
    try {
        moveNext.Invoke(target, throwingArgs)
    } catch ex: Exception {
        innerBox: object? = ex.get_InnerException()
        if innerBox != null && innerBox.GetType() == typeof(ArgumentException) {
            threwArgument = true
            inner := (Exception)innerBox
            thrownMessage = inner.get_Message()
        }
    }
    assert threwArgument
    assert thrownMessage == "bad step"

    yieldingMachine := new ColumnarIteratorCloneProbe(0)
    yieldingMachine.n = 5
    yieldingArgs := new object[](1)
    IteratorSetObject(yieldingArgs, 0, yieldingMachine)
    assert Convert.ToBoolean(moveNext.Invoke(target, yieldingArgs))
    assert Convert.ToInt32(getCurrent.Invoke(target, yieldingArgs)) == 1
    assert !Convert.ToBoolean(moveNext.Invoke(target, yieldingArgs))
}

test "iterator planner reuses the hoisted slot for same-typed disjoint redeclarations" {
    source := "func* UpOrDown(n: int): IEnumerable<int> { if n > 0 { v := n\n yield v } else { v := 0 - n\n yield v } }"
    probe := new ColumnarIteratorShapeProbe(
        source, "IEnumerable<int>", IteratorOne("n"), IteratorOne("int"), IteratorNoStrings(), false)
    assert probe.Shape.Supported
    assert probe.Shape.FieldCount == 4
    assert probe.Shape.FieldNames[3] == "v"

    smType := typeof(ColumnarIteratorCloneProbe)
    fields := new FieldInfo[](4)
    fields[0] = smType.GetField("state")
    fields[1] = smType.GetField("current")
    fields[2] = smType.GetField("n")
    fields[3] = smType.GetField("i")
    context := new ColumnarIteratorEmitContext(
        probe.Nodes, probe.Source, probe.BodyRoot, probe.Shape, smType, typeof(int), probe.Shape.FieldNames, fields)
    moveNext := MakeIteratorDynamicMethod("SlotReuseMoveNext", typeof(bool), smType)
    ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildMoveNextPlan(context), moveNext.GetILGenerator())
    getCurrent := MakeIteratorDynamicMethod("SlotReuseCurrent", typeof(int), smType)
    ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildGetCurrentPlan(context), getCurrent.GetILGenerator())

    target: object? = null

    upMachine := new ColumnarIteratorCloneProbe(0)
    upMachine.n = 5
    upArgs := new object[](1)
    IteratorSetObject(upArgs, 0, upMachine)
    assert Convert.ToBoolean(moveNext.Invoke(target, upArgs))
    assert Convert.ToInt32(getCurrent.Invoke(target, upArgs)) == 5
    assert !Convert.ToBoolean(moveNext.Invoke(target, upArgs))

    downMachine := new ColumnarIteratorCloneProbe(0)
    downMachine.n = -3
    downArgs := new object[](1)
    IteratorSetObject(downArgs, 0, downMachine)
    assert Convert.ToBoolean(moveNext.Invoke(target, downArgs))
    assert Convert.ToInt32(getCurrent.Invoke(target, downArgs)) == 3
    assert !Convert.ToBoolean(moveNext.Invoke(target, downArgs))
}

test "iterator planner declines a differently-typed local redeclaration" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Mixed(n: int): IEnumerable<int> { if n > 0 { v := 1\n yield v } else { v := true\n yield 2 } }",
        "IEnumerable<int>", IteratorOne("n"), IteratorOne("int"), IteratorNoStrings(), false)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.unsupported-shape"
}

// A run-probe machine for the enumerator-hoisting lowering. The enumerator slot is object-typed on
// the probe (its interface type sits outside the probe class's declarable surface); the plans bind
// fields by handle and DynamicMethods execute unverified, so the runtime behavior is exact.
public class ColumnarIteratorEnumProbe {
    public state: int
    public current: int
    public xs: List<int>
    public en: object?
    public item: int

    constructor(initialState: int) {
        state = initialState
        current = 0
        xs = new List<int>()
        en = null
        item = 0
    }
}

func IteratorEnumProbeContext(source: string): ColumnarIteratorEmitContext {
    probe := new ColumnarIteratorShapeProbe(
        source, "IEnumerable<int>", IteratorOne("xs"), IteratorOne("List<int>"), IteratorNoStrings(), false)
    if !probe.Shape.Supported {
        throw new InvalidOperationException("Enum probe shape unexpectedly declined: " + probe.Shape.DeclineMessage)
    }
    smType := typeof(ColumnarIteratorEnumProbe)
    fields := new FieldInfo[](5)
    fields[0] = smType.GetField("state")
    fields[1] = smType.GetField("current")
    fields[2] = smType.GetField("xs")
    fields[3] = smType.GetField("en")
    fields[4] = smType.GetField("item")
    return new ColumnarIteratorEmitContext(
        probe.Nodes, probe.Source, probe.BodyRoot, probe.Shape, smType, typeof(int),
        probe.Shape.FieldNames, fields)
}

test "iterator planner enumerator for..in plans run and release the enumerator" {
    context := IteratorEnumProbeContext(
        "func* Pass(xs: List<int>): IEnumerable<int> { for item in xs { yield item } }")
    moveNext := MakeIteratorDynamicMethod("EnumMoveNext", typeof(bool), context.StateMachineType)
    ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildMoveNextPlan(context), moveNext.GetILGenerator())
    getCurrent := MakeIteratorDynamicMethod("EnumCurrent", typeof(int), context.StateMachineType)
    ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildGetCurrentPlan(context), getCurrent.GetILGenerator())

    machine := new ColumnarIteratorEnumProbe(0)
    machine.xs.Add(4)
    machine.xs.Add(5)
    machine.xs.Add(6)
    invokeArgs := new object[](1)
    IteratorSetObject(invokeArgs, 0, machine)
    target: object? = null
    results := new List<int>()
    hasNext := Convert.ToBoolean(moveNext.Invoke(target, invokeArgs))
    // Suspended inside the loop: the hoisted enumerator is live.
    assert machine.en != null
    while hasNext {
        results.Add(Convert.ToInt32(getCurrent.Invoke(target, invokeArgs)))
        hasNext = Convert.ToBoolean(moveNext.Invoke(target, invokeArgs))
    }

    assert results.Count == 3
    assert results[0] == 4
    assert results[1] == 5
    assert results[2] == 6
    // The loop's normal exit disposed and nulled the enumerator.
    assert machine.en == null
}

test "iterator planner dispose plan releases a suspended enumerator" {
    context := IteratorEnumProbeContext(
        "func* Pass(xs: List<int>): IEnumerable<int> { for item in xs { yield item } }")
    moveNext := MakeIteratorDynamicMethod("EnumSuspendMoveNext", typeof(bool), context.StateMachineType)
    ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildMoveNextPlan(context), moveNext.GetILGenerator())
    dispose := MakeIteratorDynamicMethod("EnumSuspendDispose", IteratorVoidType(), context.StateMachineType)
    ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildDisposePlan(context), dispose.GetILGenerator())

    machine := new ColumnarIteratorEnumProbe(0)
    machine.xs.Add(9)
    machine.xs.Add(10)
    invokeArgs := new object[](1)
    IteratorSetObject(invokeArgs, 0, machine)
    target: object? = null
    assert Convert.ToBoolean(moveNext.Invoke(target, invokeArgs))
    assert machine.en != null

    dispose.Invoke(target, invokeArgs)
    assert machine.en == null
    assert machine.state == -2
    assert !Convert.ToBoolean(moveNext.Invoke(target, invokeArgs))
}

test "iterator planner fault region disposes the enumerator on exception" {
    context := IteratorEnumProbeContext(
        "func* Boom(xs: List<int>): IEnumerable<int> { for item in xs { throw new InvalidOperationException(\"boom\") }\n yield 1 }")
    moveNext := MakeIteratorDynamicMethod("EnumFaultMoveNext", typeof(bool), context.StateMachineType)
    ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildMoveNextPlan(context), moveNext.GetILGenerator())

    machine := new ColumnarIteratorEnumProbe(0)
    machine.xs.Add(1)
    invokeArgs := new object[](1)
    IteratorSetObject(invokeArgs, 0, machine)
    target: object? = null
    threwBoom := false
    try {
        moveNext.Invoke(target, invokeArgs)
    } catch ex: Exception {
        innerBox: object? = ex.get_InnerException()
        threwBoom = innerBox != null && innerBox.GetType() == typeof(InvalidOperationException)
    }

    assert threwBoom
    // The fault handler released and nulled the live enumerator.
    assert machine.en == null
}

// A generic run-probe machine: the repeat shape's fields with the element flowing through T. The
// contract executes the plans against a CLOSED instantiation's runtime field handles.
public class ColumnarIteratorGenericProbe<T> {
    public state: int
    public current: T
    public value: T
    public count: int
    public i: int

    constructor(initialState: int, seed: T, repeatCount: int) {
        state = initialState
        current = seed
        value = seed
        count = repeatCount
        i = 0
    }
}

test "iterator planner generic repeat plans run over a closed instantiation" {
    source := "func* Repeat(value: T, count: int): IEnumerable<T> { i: int = 0\n while i < count { yield value\n i = i + 1 } }"
    probe := new ColumnarIteratorShapeProbe(
        source, "IEnumerable<T>", IteratorTwo("value", "count"), IteratorTwo("T", "int"), IteratorOne("T"), false)
    assert probe.Shape.Supported

    machine := new ColumnarIteratorGenericProbe<int>(0, 7, 3)
    machineBox: object = machine
    smType := machineBox.GetType()
    fields := new FieldInfo[](5)
    fields[0] = smType.GetField("state")
    fields[1] = smType.GetField("current")
    fields[2] = smType.GetField("value")
    fields[3] = smType.GetField("count")
    fields[4] = smType.GetField("i")
    context := new ColumnarIteratorEmitContext(
        probe.Nodes, probe.Source, probe.BodyRoot, probe.Shape, smType, typeof(int),
        probe.Shape.FieldNames, fields)

    moveNext := MakeIteratorDynamicMethod("GenericMoveNext", typeof(bool), smType)
    ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildMoveNextPlan(context), moveNext.GetILGenerator())
    getCurrent := MakeIteratorDynamicMethod("GenericCurrent", typeof(int), smType)
    ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildGetCurrentPlan(context), getCurrent.GetILGenerator())

    invokeArgs := new object[](1)
    IteratorSetObject(invokeArgs, 0, machine)
    target: object? = null
    results := new List<int>()
    hasNext := Convert.ToBoolean(moveNext.Invoke(target, invokeArgs))
    while hasNext {
        results.Add(Convert.ToInt32(getCurrent.Invoke(target, invokeArgs)))
        hasNext = Convert.ToBoolean(moveNext.Invoke(target, invokeArgs))
    }

    assert results.Count == 3
    assert results[0] == 7
    assert results[1] == 7
    assert results[2] == 7
}

// Enclosing-type probe for instance iterators, and a machine probe with the captured receiver slot.
public class ColumnarIteratorHostProbe {
    public Value: int
    public Worth: int

    constructor(value: int, worth: int) {
        Value = value
        Worth = worth
    }
}

public class ColumnarIteratorInstanceProbe {
    public state: int
    public current: int
    public thisRef: ColumnarIteratorHostProbe?

    constructor(initialState: int) {
        state = initialState
        current = 0
        thisRef = null
    }
}

test "iterator planner hoists the receiver and runs enclosing member reads" {
    parseProbe := new ColumnarIteratorShapeProbe(
        "func* Vals(): IEnumerable<int> { yield Value\n yield Worth }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)
    memberNames := IteratorTwo("Value", "Worth")
    memberCanonicals := IteratorTwo("int", "int")
    shape := ColumnarIteratorPlanner.AnalyzeShape(
        parseProbe.Nodes, parseProbe.Source, parseProbe.BodyRoot, "Vals", 0, "IEnumerable<int>",
        IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), true, "HostProbe",
        memberNames, memberCanonicals, IteratorNoStrings(), IteratorNoStrings(), false)

    assert shape.Supported
    assert shape.YieldReturnCount == 2
    assert shape.FieldCount == 3
    assert shape.FieldNames[2] == "<>__this"
    assert shape.FieldRoles[2] == ColumnarIteratorPlanner.CapturedParameterFieldRole()
    assert shape.FieldCanonicals[2] == "HostProbe"

    smType := typeof(ColumnarIteratorInstanceProbe)
    hostType := typeof(ColumnarIteratorHostProbe)
    fields := new FieldInfo[](3)
    fields[0] = smType.GetField("state")
    fields[1] = smType.GetField("current")
    fields[2] = smType.GetField("thisRef")
    hostFields := new FieldInfo[](2)
    hostFields[0] = hostType.GetField("Value")
    hostFields[1] = hostType.GetField("Worth")
    context := new ColumnarIteratorEmitContext(
        parseProbe.Nodes, parseProbe.Source, parseProbe.BodyRoot, shape, smType, typeof(int),
        shape.FieldNames, fields, null, hostType, memberNames, hostFields, memberCanonicals,
        IteratorNoStrings(), new MethodInfo[](0), IteratorNoStrings(), new Type[](0))

    moveNext := MakeIteratorDynamicMethod("InstanceMoveNext", typeof(bool), smType)
    ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildMoveNextPlan(context), moveNext.GetILGenerator())
    getCurrent := MakeIteratorDynamicMethod("InstanceCurrent", typeof(int), smType)
    ColumnarCodePlanExecutor.Execute(ColumnarIteratorBodyPlanner.BuildGetCurrentPlan(context), getCurrent.GetILGenerator())

    machine := new ColumnarIteratorInstanceProbe(0)
    machine.thisRef = new ColumnarIteratorHostProbe(4, 9)
    invokeArgs := new object[](1)
    IteratorSetObject(invokeArgs, 0, machine)
    target: object? = null
    results := new List<int>()
    hasNext := Convert.ToBoolean(moveNext.Invoke(target, invokeArgs))
    while hasNext {
        results.Add(Convert.ToInt32(getCurrent.Invoke(target, invokeArgs)))
        hasNext = Convert.ToBoolean(moveNext.Invoke(target, invokeArgs))
    }

    assert results.Count == 2
    assert results[0] == 4
    assert results[1] == 9
}

test "iterator planner declines enclosing member writes" {
    parseProbe := new ColumnarIteratorShapeProbe(
        "func* Bad(): IEnumerable<int> { Value = 3\n yield 1 }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)
    shape := ColumnarIteratorPlanner.AnalyzeShape(
        parseProbe.Nodes, parseProbe.Source, parseProbe.BodyRoot, "Bad", 0, "IEnumerable<int>",
        IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), true, "HostProbe",
        IteratorOne("Value"), IteratorOne("int"), IteratorNoStrings(), IteratorNoStrings(), false)

    assert !shape.Supported
    assert shape.DeclineSite == "emit.iterator.unsupported-shape"
}

test "iterator planner classifies member-call for..in sources" {
    parseProbe := new ColumnarIteratorShapeProbe(
        "func* Walk(): IEnumerable<int> { yield Value\n for child in Children { for v in child.Walk() { yield v } } }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false)
    shape := ColumnarIteratorPlanner.AnalyzeShape(
        parseProbe.Nodes, parseProbe.Source, parseProbe.BodyRoot, "Walk", 0, "IEnumerable<int>",
        IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), true, "TreeNode",
        IteratorTwo("Value", "Children"), IteratorTwo("int", "List<TreeNode>"),
        IteratorOne("Walk"), IteratorOne("IEnumerable<int>"), false)

    assert shape.Supported
    assert shape.YieldReturnCount == 2
    assert shape.FieldCount == 7
    assert shape.FieldNames[2] == "<>__this"
    assert shape.FieldCanonicals[3] == "IEnumerator<TreeNode>"
    assert shape.FieldRoles[3] == ColumnarIteratorPlanner.HoistedEnumeratorFieldRole()
    assert shape.FieldNames[4] == "child"
    assert shape.FieldCanonicals[4] == "TreeNode"
    assert shape.FieldCanonicals[5] == "IEnumerator<int>"
    assert shape.FieldNames[6] == "v"
}

// ---- async-iterator classification (`async func*` -> IAsyncEnumerable<T>) ----

test "async iterator planner classifies element type with await and yield resume counts" {
    probe := new ColumnarIteratorShapeProbe(
        "async func* Numbers(): IAsyncEnumerable<int> { await Task.Delay(1)\n yield 1 }",
        "IAsyncEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false, true)

    assert probe.Shape.Supported
    assert probe.Shape.IsAsync
    assert probe.Shape.ElementCanonical == "int"
    assert probe.Shape.YieldReturnCount == 1
    assert probe.Shape.AwaitResumeCount == 1
}

test "async iterator planner counts each await as a distinct resume state" {
    probe := new ColumnarIteratorShapeProbe(
        "async func* Multi(): IAsyncEnumerable<int> { await Task.Delay(1)\n yield 1\n await Task.Delay(2)\n yield 2\n await Task.Delay(3) }",
        "IAsyncEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false, true)

    assert probe.Shape.Supported
    assert probe.Shape.IsAsync
    assert probe.Shape.ElementCanonical == "int"
    assert probe.Shape.YieldReturnCount == 2
    assert probe.Shape.AwaitResumeCount == 3
}

test "async iterator planner classifies a yield-only body with zero awaits" {
    probe := new ColumnarIteratorShapeProbe(
        "async func* Just(): IAsyncEnumerable<int> { yield 7 }",
        "IAsyncEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false, true)

    assert probe.Shape.Supported
    assert probe.Shape.IsAsync
    assert probe.Shape.YieldReturnCount == 1
    assert probe.Shape.AwaitResumeCount == 0
}

test "async iterator planner counts awaits inside a while loop body" {
    probe := new ColumnarIteratorShapeProbe(
        "async func* Loop(): IAsyncEnumerable<int> { i := 0\n while i < 3 { await Task.Delay(5)\n yield i } }",
        "IAsyncEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false, true)

    assert probe.Shape.Supported
    assert probe.Shape.IsAsync
    assert probe.Shape.AwaitResumeCount == 1
    assert probe.Shape.YieldReturnCount == 1
}

test "async classification declines a non-IAsyncEnumerable async iterator return" {
    probe := new ColumnarIteratorShapeProbe(
        "async func* Wrong(): IEnumerable<int> { await A()\n yield 1 }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false, true)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.async-return-unsupported"
}

test "synchronous iterator planner rejects IAsyncEnumerable without the async modifier" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Sync(): IAsyncEnumerable<int> { yield 1 }",
        "IAsyncEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false, false)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.async-unsupported"
}

test "synchronous iterator planner rejects an await expression" {
    probe := new ColumnarIteratorShapeProbe(
        "func* Sync(): IEnumerable<int> { await A()\n yield 1 }",
        "IEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false, false)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.unsupported-shape"
}

// ---- async state-machine shape facts (task-014 stage 3) ----

test "async iterator planner lays out awaiter, promise, result, and continuation fields" {
    probe := new ColumnarIteratorShapeProbe(
        "async func* Numbers(n: int): IAsyncEnumerable<int> { i := 0\n while i < n { await Task.Delay(1)\n yield i\n i = i + 1 } }",
        "IAsyncEnumerable<int>", IteratorOne("n"), IteratorOne("int"), IteratorNoStrings(), false, true)

    assert probe.Shape.Supported
    assert probe.Shape.IsAsync
    assert probe.Shape.FieldCount == 8
    assert probe.Shape.FieldNames[0] == "<>__state"
    assert probe.Shape.FieldNames[1] == "<>__current"
    assert probe.Shape.FieldNames[2] == "n"
    assert probe.Shape.FieldRoles[2] == ColumnarIteratorPlanner.CapturedParameterFieldRole()
    assert probe.Shape.FieldNames[3] == "i"
    assert probe.Shape.FieldRoles[3] == ColumnarIteratorPlanner.HoistedLocalFieldRole()
    assert probe.Shape.FieldNames[4] == "<>__awaiter0"
    assert probe.Shape.FieldRoles[4] == ColumnarIteratorPlanner.AwaiterFieldRole()
    assert probe.Shape.FieldCanonicals[4] == "TaskAwaiter"
    assert probe.Shape.FieldNames[5] == "<>__promise"
    assert probe.Shape.FieldRoles[5] == ColumnarIteratorPlanner.PromiseFieldRole()
    assert probe.Shape.FieldCanonicals[5] == "TaskCompletionSource<bool>"
    assert probe.Shape.FieldNames[6] == "<>__result"
    assert probe.Shape.FieldRoles[6] == ColumnarIteratorPlanner.ResultFieldRole()
    assert probe.Shape.FieldNames[7] == "<>__continuation"
    assert probe.Shape.FieldRoles[7] == ColumnarIteratorPlanner.ContinuationFieldRole()
    assert probe.Shape.FieldCanonicals[7] == "Action"
}

test "async iterator planner exposes the six async member and override specs" {
    probe := new ColumnarIteratorShapeProbe(
        "async func* Just(): IAsyncEnumerable<int> { yield 7 }",
        "IAsyncEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false, true)

    assert probe.Shape.MemberCount == 6
    assert probe.Shape.MemberNames[0] == ".ctor"
    assert probe.Shape.MemberSignatures[0] == "(int):void"
    assert probe.Shape.MemberNames[1] == "MoveNextCore"
    assert probe.Shape.MemberOverrides[1] == ""
    assert probe.Shape.MemberNames[2] == "MoveNextAsync"
    assert probe.Shape.MemberSignatures[2] == "():ValueTask<bool>"
    assert probe.Shape.MemberOverrides[2] == "System.Collections.Generic.IAsyncEnumerator<T>.MoveNextAsync"
    assert probe.Shape.MemberNames[3] == "get_Current"
    assert probe.Shape.MemberSignatures[3] == "():int"
    assert probe.Shape.MemberNames[4] == "DisposeAsync"
    assert probe.Shape.MemberSignatures[4] == "():ValueTask"
    assert probe.Shape.MemberOverrides[4] == "System.IAsyncDisposable.DisposeAsync"
    assert probe.Shape.MemberNames[5] == "GetAsyncEnumerator"
    assert probe.Shape.MemberSignatures[5] == "(CancellationToken):IAsyncEnumerator<int>"
    assert probe.Shape.MemberOverrides[5] == "System.Collections.Generic.IAsyncEnumerable<T>.GetAsyncEnumerator"
}

test "async iterator planner declines a generic async iterator" {
    probe := new ColumnarIteratorShapeProbe(
        "async func* Repeat(): IAsyncEnumerable<T> { yield break }",
        "IAsyncEnumerable<T>", IteratorNoStrings(), IteratorNoStrings(), IteratorOne("T"), false, true)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.async-unsupported"
}

test "async iterator planner declines a non-Task-Delay awaited operand" {
    probe := new ColumnarIteratorShapeProbe(
        "async func* Bad(): IAsyncEnumerable<int> { await Other()\n yield 1 }",
        "IAsyncEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false, true)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.async-await-unsupported"
}

test "async iterator planner declines an await in a value position" {
    probe := new ColumnarIteratorShapeProbe(
        "async func* Bad(): IAsyncEnumerable<int> { x := await Task.Delay(1)\n yield 1 }",
        "IAsyncEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false, true)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.async-await-unsupported"
}

test "async iterator planner declines a non-int Task.Delay argument" {
    probe := new ColumnarIteratorShapeProbe(
        "async func* Bad(): IAsyncEnumerable<int> { await Task.Delay(true)\n yield 1 }",
        "IAsyncEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false, true)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.async-await-unsupported"
}

test "async iterator planner declines for..in over a sequence source" {
    probe := new ColumnarIteratorShapeProbe(
        "async func* Bad(items: IEnumerable<int>): IAsyncEnumerable<int> { for x in items { yield x } }",
        "IAsyncEnumerable<int>", IteratorOne("items"), IteratorOne("IEnumerable<int>"), IteratorNoStrings(), false, true)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.for-in-unsupported"
}

test "async iterator planner declines await foreach inside an iterator body" {
    probe := new ColumnarIteratorShapeProbe(
        "async func* Bad(xs: IAsyncEnumerable<int>): IAsyncEnumerable<int> { await foreach x in xs { yield x } }",
        "IAsyncEnumerable<int>", IteratorOne("xs"), IteratorOne("IAsyncEnumerable<int>"), IteratorNoStrings(), false, true)

    assert !probe.Shape.Supported
    assert probe.Shape.DeclineSite == "emit.iterator.async-await-unsupported"
}

// ---- async state-machine executed proofs (plans realized onto a reflective probe host) ----

test "async iterator planner core plan completes a fast-path await and yield synchronously" {
    probe := new ColumnarIteratorShapeProbe(
        "async func* Fast(): IAsyncEnumerable<int> { await Task.Delay(0)\n yield 7 }",
        "IAsyncEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false, true)
    assert probe.Shape.Supported
    assert probe.Shape.YieldReturnCount == 1
    assert probe.Shape.AwaitResumeCount == 1

    host := new ColumnarAsyncProbeMachine(probe, "AsyncProbeFastCore")
    machine := host.NewMachine(0)
    host.InvokeVoidMember(machine, "MoveNextCore")
    // Task.Delay(0) is complete at the awaiter check: the drive never suspends. The await is resume
    // state 1 and the yield resume state 2 (one shared counter, body walk order).
    assert host.ReadInt(machine, "<>__state") == 2
    assert host.ReadInt(machine, "<>__current") == 7
    assert host.ReadBool(machine, "<>__result")
    assert host.ReadField(machine, "<>__promise") == null

    host.InvokeVoidMember(machine, "MoveNextCore")
    assert host.ReadInt(machine, "<>__state") == -2
    assert !host.ReadBool(machine, "<>__result")
}

test "async iterator machine suspends on a real delay and resumes through the continuation" {
    probe := new ColumnarIteratorShapeProbe(
        "async func* Slow(): IAsyncEnumerable<int> { await Task.Delay(200)\n yield 42 }",
        "IAsyncEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false, true)
    assert probe.Shape.Supported

    host := new ColumnarAsyncProbeMachine(probe, "AsyncProbeSlow")
    machine := host.NewMachine(0)
    pending := host.InvokeMember(machine, "MoveNextAsync")
    // The 200ms delay cannot be complete at the awaiter check, so the drive suspended: the promise is
    // live and the returned ValueTask<bool> is Task-backed. Await it — the completed Task.Delay fires
    // the registered continuation, MoveNextCore re-drives, and the yield completes the promise.
    assert host.ReadField(machine, "<>__promise") != null
    assert AsyncProbeAwaitValueTask(pending, 20000)
    assert host.ReadInt(machine, "<>__current") == 42
    assert host.ReadInt(machine, "<>__state") == 2

    second := host.InvokeMember(machine, "MoveNextAsync")
    assert AsyncProbeValueTaskGetter(second, "get_IsCompleted")
    assert !AsyncProbeAwaitValueTask(second, 20000)
    assert host.ReadInt(machine, "<>__state") == -2

    afterDone := host.InvokeMember(machine, "MoveNextAsync")
    assert AsyncProbeValueTaskGetter(afterDone, "get_IsCompleted")
    assert !AsyncProbeAwaitValueTask(afterDone, 20000)
}

test "async iterator machine routes a synchronous body exception to the caller" {
    probe := new ColumnarIteratorShapeProbe(
        "async func* Boom(): IAsyncEnumerable<int> { await Task.Delay(0)\n throw new InvalidOperationException(\"boom\") }",
        "IAsyncEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false, true)
    assert probe.Shape.Supported

    host := new ColumnarAsyncProbeMachine(probe, "AsyncProbeBoom")
    machine := host.NewMachine(0)
    found := false
    try {
        host.InvokeMember(machine, "MoveNextAsync")
    } catch ex: Exception {
        cursorBox: object? = ex
        depth := 0
        while cursorBox != null && depth < 5 {
            if cursorBox.GetType() == typeof(InvalidOperationException) {
                found = true
            }
            cursorException := (Exception)cursorBox
            cursorBox = cursorException.get_InnerException()
            depth = depth + 1
        }
    }
    assert found
    assert host.ReadInt(machine, "<>__state") == -2
}

test "async iterator machine routes a post-suspension exception through the promise" {
    probe := new ColumnarIteratorShapeProbe(
        "async func* LateBoom(): IAsyncEnumerable<int> { await Task.Delay(200)\n throw new InvalidOperationException(\"late\") }",
        "IAsyncEnumerable<int>", IteratorNoStrings(), IteratorNoStrings(), IteratorNoStrings(), false, true)
    assert probe.Shape.Supported

    host := new ColumnarAsyncProbeMachine(probe, "AsyncProbeLateBoom")
    machine := host.NewMachine(0)
    pending := host.InvokeMember(machine, "MoveNextAsync")
    assert host.ReadField(machine, "<>__promise") != null
    found := false
    try {
        AsyncProbeAwaitValueTask(pending, 20000)
    } catch ex: Exception {
        cursorBox: object? = ex
        depth := 0
        while cursorBox != null && depth < 6 {
            if cursorBox.GetType() == typeof(InvalidOperationException) {
                found = true
            }
            cursorException := (Exception)cursorBox
            cursorBox = cursorException.get_InnerException()
            depth = depth + 1
        }
    }
    assert found
    assert host.ReadInt(machine, "<>__state") == -2
}

test "async iterator machine clone, dispose, and factory keep the sync machine discipline" {
    probe := new ColumnarIteratorShapeProbe(
        "async func* Capture(n: int): IAsyncEnumerable<int> { await Task.Delay(0)\n yield n }",
        "IAsyncEnumerable<int>", IteratorOne("n"), IteratorOne("int"), IteratorNoStrings(), false, true)
    assert probe.Shape.Supported

    host := new ColumnarAsyncProbeMachine(probe, "AsyncProbeCapture")
    machine := host.NewMachine(0)
    host.WriteField(machine, "n", 9)
    first := host.InvokeMember(machine, "MoveNextAsync")
    assert AsyncProbeValueTaskGetter(first, "get_IsCompleted")
    assert AsyncProbeAwaitValueTask(first, 20000)
    assert host.ReadInt(machine, "<>__current") == 9

    // Clone semantics: a FRESH machine at the initial state with captured parameters copied.
    clone := host.InvokeMember(machine, "GetAsyncEnumerator")
    assert !Object.ReferenceEquals(machine, clone)
    assert host.ReadInt(clone, "<>__state") == 0
    assert host.ReadInt(clone, "n") == 9
    assert host.ReadInt(clone, "<>__current") == 0

    disposed := host.InvokeMember(machine, "DisposeAsync")
    assert AsyncProbeValueTaskGetter(disposed, "get_IsCompleted")
    assert host.ReadInt(machine, "<>__state") == -2
    afterDispose := host.InvokeMember(machine, "MoveNextAsync")
    assert !AsyncProbeAwaitValueTask(afterDispose, 20000)

    // The async factory constructs the machine at the initial state from the method arguments.
    factoryContext := new ColumnarIteratorEmitContext(
        probe.Nodes, probe.Source, probe.BodyRoot, probe.Shape, host.MachineType, typeof(int),
        probe.Shape.FieldNames, host.Fields, host.StateConstructor)
    factoryPlan := ColumnarIteratorBodyPlanner.BuildAsyncFactoryPlan(factoryContext)
    factory := MakeIteratorDynamicMethod("AsyncFactory", typeof(object), typeof(int))
    ColumnarCodePlanExecutor.Execute(factoryPlan, factory.GetILGenerator())
    factoryArgs := new object[](1)
    IteratorSetObject(factoryArgs, 0, 5)
    target: object? = null
    made := factory.Invoke(target, factoryArgs)
    assert made != null
    assert host.ReadInt(made, "<>__state") == 0
    assert host.ReadInt(made, "n") == 5
}
