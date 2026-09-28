namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection


// ROWS WHOSE SUBJECT IS THE EMITTER ITSELF, beside it: a whole program it must emit, a private step
// of its constructor lowering it must refuse, and the writable-property admission it asks of a
// referenced type. They reach the emitter's own members (`TryEmitColumnarAssembly`, and by reflection
// `_il`, `EmitChainedConstructorCall` and `TryGetSupportedBclWritableProperty`), so they build here.
func EmitLoopBodyCall(method: MethodInfo, start: object?): int {
    arguments := new object?[](1)
    arguments[0] = start
    return Convert.ToInt32(method.Invoke(null, arguments))
}

test "a class pairing a bare nullable field with an initialized one emits instead of throwing" {
    program := EmitFixtureProgram([""], ["class Probe {\n    Tokens: string?\n    Count: int = 4\n}\n"], "FieldInitPlannerProbe")
    bytes: byte[] = null
    assert ColumnarIlEmitter.TryEmitColumnarAssembly("FieldInitPlanner" + Guid.NewGuid().ToString("N"), "Program", program, false, out bytes, null, null)
    assert bytes != null
    assert bytes.Length > 0
}

test "loop bodies read condition-proved Nullable values and keep continue branches isolated" {
    source := "func Dec(n: int): int? {\n    if n <= 0 {\n        return null\n    }\n    return n - 1\n}\n\nfunc WhileBody(start: int?): int {\n    total := 0\n    n := start\n    while n != null {\n        total = total + n\n        n = Dec(n)\n    }\n    return total\n}\n\nfunc ForBody(start: int?): int {\n    total := 0\n    n := start\n    for i := 0; n != null; i = i + 1 {\n        total = total + n\n        n = Dec(n)\n    }\n    return total\n}\n\nfunc WhileContinue(start: int?): int {\n    total := 0\n    n := start\n    while n != null {\n        if n % 2 == 0 {\n            n = Dec(n)\n            continue\n        }\n        total = total + n\n        n = Dec(n)\n    }\n    return total\n}\n\nfunc ForContinue(start: int?): int {\n    total := 0\n    n := start\n    for i := 0; n != null; i = i + 1 {\n        if n % 2 == 0 {\n            n = Dec(n)\n            continue\n        }\n        total = total + n\n        n = Dec(n)\n    }\n    return total\n}\n"
    program := EmitFixtureProgram([""], [source], "LoopBodyNarrowingEmitter")
    bytes: byte[] = null
    assert ColumnarIlEmitter.TryEmitColumnarAssembly("LoopBodyNarrowingEmitter" + Guid.NewGuid().ToString("N"), "Program", program, false, out bytes, null, null)
    assembly := Assembly.Load(bytes)
    owner := assembly.GetType("Program")
    assert owner != null

    whileBody := owner.GetMethod("WhileBody", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
    forBody := owner.GetMethod("ForBody", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
    whileContinue := owner.GetMethod("WhileContinue", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
    forContinue := owner.GetMethod("ForContinue", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
    assert whileBody != null
    assert forBody != null
    assert whileContinue != null
    assert forContinue != null

    assert EmitLoopBodyCall(whileBody, 3) == 6
    assert EmitLoopBodyCall(forBody, 3) == 6
    assert EmitLoopBodyCall(whileBody, 2) == 3
    assert EmitLoopBodyCall(forBody, 2) == 3
    assert EmitLoopBodyCall(whileContinue, 5) == 9
    assert EmitLoopBodyCall(forContinue, 5) == 9
    assert EmitLoopBodyCall(whileBody, null) == 0
    assert EmitLoopBodyCall(forBody, null) == 0
}

test "a surviving if branch does not emit a nullable read after its write" {
    source := "func Dec(n: int): int? {\n    return null\n}\n\nfunc BadElse(start: int?, c: bool): int {\n    n := start\n    while n != null {\n        if c {\n            return 0\n        } else {\n            n = Dec(n)\n        }\n        return n + 1\n    }\n    return 0\n}\n\nfunc BadThen(start: int?, c: bool): int {\n    n := start\n    while n != null {\n        if c {\n            n = Dec(n)\n        } else {\n            return 0\n        }\n        return n + 1\n    }\n    return 0\n}\n"
    program := EmitFixtureProgram([""], [source], "LoopBodyNarrowingWriteRefusal")
    bytes: byte[] = null

    // These fixtures bypass analysis on purpose: the emitter must carry its own assignment kills,
    // so it declines the nullable arithmetic instead of reading Nullable<T> storage as T.
    assert !ColumnarIlEmitter.TryEmitColumnarAssembly("LoopBodyNarrowingWriteRefusal" + Guid.NewGuid().ToString("N"), "Program", program, false, out bytes, null, null)
}

test "constructor chain selection rebinds every differing exact base before emitting IL" {
    invalidBase := EmitFixtureStructDefinition("ConstructorChainSelectionInvalidExactBase", 0)
    invalidBase.DefaultCtor = invalidBase.Builder.DefineDefaultConstructor(MethodAttributes.Public)
    invalidDerived := EmitFixtureStructDefinition("ConstructorChainSelectionInvalidExactDerived", 0)
    invalidDerived.BaseDef = invalidBase
    invalidDerived.ExactBaseType = typeof(string)
    self := invalidDerived.Builder.DefineDefaultConstructor(MethodAttributes.Public)
    chainBody := EmitFixtureEmptyBody(
        "ConstructorChainSelectionInvalidExactDerived",
        new string[](0),
        new string[](0)
    )
    chain := EmitFixtureConstructor(
        chainBody,
        2,
        new int[](0),
        new string[](0),
        false
    )

    runtimeHelperArgumentTypes := new Type[](1)
    runtimeHelperArgumentTypes[0] = typeof(Type)
    getUninitializedObject := typeof(System.Runtime.CompilerServices.RuntimeHelpers).GetMethod(
        "GetUninitializedObject",
        runtimeHelperArgumentTypes
    )
    if getUninitializedObject == null {
        throw new InvalidOperationException("Missing RuntimeHelpers.GetUninitializedObject")
    }
    runtimeHelperArguments := new object?[](1)
    EmitFixturePut(
        runtimeHelperArguments,
        0,
        typeof(ColumnarIlEmitter)
    )
    emitter := getUninitializedObject.Invoke(null, runtimeHelperArguments)
    if emitter == null {
        throw new InvalidOperationException("RuntimeHelpers.GetUninitializedObject returned null")
    }

    il := EmitFixtureDynamicIl("ConstructorChainSelectionInvalidExactBaseCall")
    ilField := typeof(ColumnarIlEmitter).GetField(
        "_il",
        BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly
    )
    if ilField == null {
        throw new InvalidOperationException("Missing ColumnarIlEmitter._il")
    }
    ilField.SetValue(emitter, il)
    emitChain := typeof(ColumnarIlEmitter).GetMethod(
        "EmitChainedConstructorCall",
        BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.DeclaredOnly
    )
    if emitChain == null {
        throw new InvalidOperationException("Missing ColumnarIlEmitter.EmitChainedConstructorCall")
    }
    arguments := new object?[](3)
    EmitFixturePut(arguments, 0, chain)
    EmitFixturePut(arguments, 1, self)
    EmitFixturePut(arguments, 2, invalidDerived)
    failure: Exception? = null
    try {
        ignored := emitChain.Invoke(emitter, arguments)
        _ = ignored
    } catch error: Exception {
        failure = error
    }
    if failure == null {
        throw new InvalidOperationException("The invalid exact base did not fail constructor selection")
    }
    captured: Exception = failure
    inner := captured.get_InnerException() as ArgumentException
    if inner == null {
        throw new InvalidOperationException("The constructor selection failure was not an ArgumentException")
    }
    assert il.ILOffset == 0
}

func IlEmitterAssertWritable(receiverType: Type, member: string, expectedResultName: string): PropertyInfo {
    result := ChtpWritableProperty(receiverType, member, null)
    assert Convert.ToBoolean(result[0])
    property := result[1] as PropertyInfo
    if property == null {
        throw new InvalidOperationException("The admitted writable property did not retain its metadata handle.")
    }
    assert property.get_DeclaringType() == receiverType
    assert property.get_Name() == member
    assert property.get_PropertyType().FullName == expectedResultName
    setter := property.get_SetMethod()
    if setter == null {
        throw new InvalidOperationException("The admitted writable property has no public setter.")
    }
    assert setter.get_IsPublic()
    assert !setter.get_IsStatic()
    return property
}

test "Cecil writable properties retain exact metadata handles and reset failed selections" {
    IlEmitterAssertWritable(typeof(Mono.Cecil.ReaderParameters), "ReadingMode", "Mono.Cecil.ReadingMode")
    IlEmitterAssertWritable(typeof(Mono.Cecil.ReaderParameters), "InMemory", "System.Boolean")
    IlEmitterAssertWritable(typeof(Mono.Cecil.TypeReference), "Scope", "Mono.Cecil.IMetadataScope")
    IlEmitterAssertWritable(typeof(Mono.Cecil.AssemblyNameReference), "Culture", "System.String")
    IlEmitterAssertWritable(typeof(Mono.Cecil.AssemblyNameReference), "PublicKeyToken", "System.Byte[]")

    // `ReadSymbols` was refused only because the admission table listed four Cecil members by name.
    // Admission is ordinary CLR resolution now, so a sibling settable property of the same type
    // answers exactly as the four listed ones do.
    IlEmitterAssertWritable(typeof(Mono.Cecil.ReaderParameters), "ReadSymbols", "System.Boolean")

    // A name the type does not declare still resets the out slot, and so does a receiver this
    // compilation is WRITING: a builder's members are the source path's, never reflection's.
    sentinel := typeof(Mono.Cecil.ReaderParameters).GetProperty("ReadingMode")
    missing := ChtpWritableProperty(typeof(Mono.Cecil.ReaderParameters), "NotAProperty", sentinel)
    assert !Convert.ToBoolean(missing[0])
    assert missing[1] == null
    builderBound := ChtpWritableProperty(EmitFixtureTypeBuilder("Mono.Cecil.ReaderParameters", "NSharpTests.ForeignWritable", 0), "InMemory", sentinel)
    assert !Convert.ToBoolean(builderBound[0])
    assert builderBound[1] == null
}
