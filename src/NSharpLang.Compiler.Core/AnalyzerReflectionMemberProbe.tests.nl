namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Linq
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler.Columnar


// AN OWNER THAT CANNOT ANSWER FOR ITS MEMBERS MUST NOT END THE COMPILATION.
//
// THE FAULT THIS PINS, IN THE WORDS OF THE RUN THAT FOUND IT. A project referencing
// `OmniSharp.Extensions.LanguageServer` pulls in `System.Reactive`, which declares extension methods
// over WPF types; `WindowsBase` does not exist on macOS, so materialising one of those signatures
// throws `FileNotFoundException`. The extension-method INDEX walks every extension method of every
// referenced assembly rather than only the ones a call names, so one unreadable signature anywhere
// in the reference set ended the whole check with "Could not load file or assembly 'WindowsBase'" —
// a sentence about an assembly the program never named, for a program with no error in it.
//
// THE FIXTURE IS AN UNCREATED `TypeBuilder`, and it is the right one: every member query on it
// throws `NotSupportedException` for the same reason a missing assembly throws
// `FileNotFoundException` — the owner exists as a handle and cannot answer for its members. The
// assertions are that each read ANSWERS (empty, or null) rather than throwing, and that a readable
// owner is completely unaffected.
//
// THE REAL UNLOADABLE-ASSEMBLY CASE IS PINNED END TO END by `tests/native/language-server-diagnostics`,
// whose own reference closure is the one described above; it cannot be built here, because an
// assembly that the test host CAN load is by definition not the case being tested.
func ProbeUncreatedOwner(): Type {
    assemblyName := "NSharpTests.ReflectionMemberProbe"
    dynamicAssembly := AssemblyBuilder.DefineDynamicAssembly(
        new AssemblyName(assemblyName),
        AssemblyBuilderAccess.Run
    )
    dynamicModule := dynamicAssembly.DefineDynamicModule(assemblyName)
    return dynamicModule.DefineType(
        "NSharpTests.ReflectionMemberProbe.Owner",
        TypeAttributes.Public | TypeAttributes.Abstract | TypeAttributes.Sealed
    )
}

func ProbeRequiredMethod(owner: Type, name: string): MethodInfo {
    method := owner.GetMethod(name)
    if method == null {
        throw new InvalidOperationException("Required reflection-probe method was not found: " + name)
    }

    return method
}

// ── an owner that cannot answer ───────────────────────────────────────────────────────────────

// THE FIXTURE IS PINNED AS A REAL FAILURE FIRST. An owner with no members would answer "empty"
// without ever reaching the guard, so the contract below would pass while saying nothing. The
// builder is given a method, and the RAW read is asserted to throw: only then does "empty" mean the
// guard answered.
test "the fixture is a genuine failure: the raw reads throw and the member it declares is real" {
    owner := ProbeUncreatedOwner()
    declared := ProbeDefineAbstractMethod(owner, "Unreadable")

    assert declared.get_Name() == "Unreadable"
    assert ProbeRawMethodsThrow(owner)
    assert ProbeRawConstructorsThrow(owner)
    assert ProbeRawParametersThrow(declared)
}

test "every member read over an owner that cannot answer yields nothing instead of throwing" {
    owner := ProbeUncreatedOwner()
    ProbeDefineAbstractMethod(owner, "Unreadable")

    assert AnalyzerReflectionMemberProbe.MethodsOrEmpty(owner, BindingFlags.Public | BindingFlags.Static).Length == 0
    assert AnalyzerReflectionMemberProbe.MethodsOrEmpty(owner, BindingFlags.Public | BindingFlags.Instance).Length == 0
    assert AnalyzerReflectionMemberProbe.ConstructorsOrEmpty(owner).Length == 0
    assert AnalyzerReflectionMemberProbe.InterfacesOrEmpty(owner).Length == 0
    assert AnalyzerReflectionMemberProbe.MethodOrNull(owner, "Unreadable") == null
}

test "a readable owner is unaffected: the guard is a failure path, not a policy" {
    assert AnalyzerReflectionMemberProbe.MethodsOrEmpty(typeof(string), BindingFlags.Public | BindingFlags.Instance).Length > 0
    assert AnalyzerReflectionMemberProbe.ConstructorsOrEmpty(typeof(object)).Length > 0
    assert AnalyzerReflectionMemberProbe.InterfacesOrEmpty(typeof(string)).Length > 0
    assert AnalyzerReflectionMemberProbe.MethodOrNull(typeof(Action), "Invoke") != null
}

test "a signature is read whole or not at all" {
    concat := typeof(string).GetMethod("Concat", ProbeConcatTypes())
    assert concat != null

    parameterTypes := AnalyzerReflectionMemberProbe.ParameterTypesOrNull(concat)
    assert parameterTypes != null
    assert parameterTypes.Length == 2
    assert parameterTypes[0] == typeof(string)
    assert parameterTypes[1] == typeof(string)

    assert AnalyzerReflectionMemberProbe.ReturnTypeOrNull(concat) == typeof(string)
}

// A `MethodBuilder` is a method handle whose parameters cannot be read either, which is the
// per-METHOD half of the same rule: the owner enumerated, one member did not answer.
test "a method whose parameters cannot be read contributes no signature" {
    owner := ProbeUncreatedOwner()
    builderMethod := ProbeDefineAbstractMethod(owner, "Unreadable")

    assert ProbeRawParametersThrow(builderMethod)
    assert ColumnarExtensionMethodResolver.ParametersOrNull(builderMethod) == null
    assert AnalyzerReflectionMemberProbe.ParameterTypesOrNull(builderMethod) == null
    assert ColumnarExtensionMethodResolver.ParameterTypesOrNull(new ParameterInfo[](0)) != null
}

test "a base-chain read that cannot be answered ends the walk instead of the analysis" {
    owner := ProbeUncreatedOwner()

    // An uncreated builder DOES answer for its base, so this pins the readable direction; the
    // unreadable one is the null the guard returns, which the delegate predicates then read as
    // "not a delegate" rather than propagating.
    assert AnalyzerReflectionMemberProbe.BaseTypeOrNull(typeof(string)) == typeof(object)
    assert AnalyzerReflectionMemberProbe.BaseTypeOrNull(typeof(object)) == null
    assert !AnalyzerCallableReferenceFacts.IsMetadataDelegateType(owner)
}

// ── the index build, which is the walk that actually broke ────────────────────────────────────

test "the extension index skips a host it cannot read and indexes everything it can" {
    index := new ColumnarExtensionMethodIndex()
    owner := ProbeUncreatedOwner()

    // The host DOES declare a method, and the walk that would read it throws — so "indexes nothing"
    // is the guard answering rather than an empty type.
    ProbeDefineAbstractMethod(owner, "Unreadable")
    assert ProbeRawMethodsThrow(owner)

    // A host whose attribute list cannot be read is not a static extension host, and adding it
    // indexes nothing. Neither call throws, which is the whole claim.
    assert !ColumnarExtensionMethodResolver.IsStaticExtensionHost(owner)
    ColumnarExtensionMethodResolver.AddType(index, owner)

    unreadable := new List<ColumnarExtensionMethodCandidate>()
    assert !index.TryGet("Unreadable", out unreadable)

    // The readable half still works: `System.Linq.Enumerable` indexes its own extensions.
    ColumnarExtensionMethodResolver.AddType(index, typeof(Enumerable))
    selected := new List<ColumnarExtensionMethodCandidate>()
    assert index.TryGet("Count", out selected)
    assert selected.Count > 0
}

func ProbeConcatTypes(): Type[] {
    types := new Type[](2)
    types[0] = typeof(string)
    types[1] = typeof(string)
    return types
}

func ProbeDefineAbstractMethod(owner: Type, name: string): MethodInfo {
    defineMethodTypes := new Type[](4)
    defineMethodTypes[0] = typeof(string)
    defineMethodTypes[1] = typeof(MethodAttributes)
    defineMethodTypes[2] = typeof(Type)
    defineMethodTypes[3] = typeof(Type[])
    defineMethod := typeof(TypeBuilder).GetMethod("DefineMethod", defineMethodTypes)
    if defineMethod == null {
        throw new InvalidOperationException("TypeBuilder.DefineMethod(string, MethodAttributes, Type, Type[]) was not found.")
    }

    arguments := new object[](4)
    methodName: object = name
    attributes: object = MethodAttributes.Public | MethodAttributes.Static | MethodAttributes.Abstract
    returnType: object = typeof(int)
    parameterTypes: object = new Type[](0)
    ProbeSetObject(arguments, 0, methodName)
    ProbeSetObject(arguments, 1, attributes)
    ProbeSetObject(arguments, 2, returnType)
    ProbeSetObject(arguments, 3, parameterTypes)

    defined := defineMethod.Invoke(owner, arguments) as MethodInfo
    if defined == null {
        throw new InvalidOperationException("TypeBuilder.DefineMethod did not answer with a method.")
    }

    return defined
}

func ProbeSetObject(values: object[], index: int, value: object) {
    values[index] = value
}

// The three raw reads the guards wrap, asserted to FAIL on the fixture. A fixture that stopped
// failing would make every contract above vacuous, and these are what would say so.
func ProbeRawMethodsThrow(owner: Type): bool {
    try {
        ignored := owner.GetMethods(BindingFlags.Public | BindingFlags.Static)
        return ignored == null
    } catch {
        return true
    }
}

func ProbeRawConstructorsThrow(owner: Type): bool {
    try {
        ignored := owner.GetConstructors()
        return ignored == null
    } catch {
        return true
    }
}

func ProbeRawParametersThrow(method: MethodInfo): bool {
    try {
        ignored := method.GetParameters()
        return ignored == null
    } catch {
        return true
    }
}
