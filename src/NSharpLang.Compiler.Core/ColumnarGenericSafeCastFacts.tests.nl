namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection

func GenericSafeCastProgram(source: string): ColumnarProgramInput {
    sources := new List<string>()
    sources.Add(source)
    fileNames := new List<string>()
    fileNames.Add("/tmp/ColumnarGenericSafeCastFacts.nl")
    program: ColumnarProgramInput = null
    assert ColumnarProgramInputBuilder.TryBuildMultiFile(sources, fileNames, "/tmp", out program)
    return program
}

func GenericSafeCastAssembly(source: string): Assembly {
    program := GenericSafeCastProgram(source)
    bytes: byte[] = null
    assert ColumnarIlEmitter.TryEmitColumnarAssembly(
        "ColumnarGenericSafeCast" + Guid.NewGuid().ToString("N"),
        "Program",
        program,
        false,
        out bytes,
        null,
        null
    )
    return Assembly.Load(bytes)
}

func GenericSafeCastDeclines(source: string): bool {
    program := GenericSafeCastProgram(source)
    bytes: byte[] = null
    return !ColumnarIlEmitter.TryEmitColumnarAssembly(
        "ColumnarGenericSafeCastDecline" + Guid.NewGuid().ToString("N"),
        "Program",
        program,
        false,
        out bytes,
        null,
        null
    )
}

func GenericSafeCastMethod(assembly: Assembly): MethodInfo {
    owner := assembly.GetType("Program")
    if owner == null {
        throw new InvalidOperationException("The generic safe-cast fixture did not publish Program.")
    }
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(object)
    method := owner.GetMethod("AsReadOnly", parameterTypes)
    if method == null {
        throw new InvalidOperationException("The generic safe-cast fixture did not publish AsReadOnly.")
    }
    return method
}

func GenericSafeCastInvoke(method: MethodInfo, value: object?): object? {
    arguments := new object?[](1)
    arguments[0] = value
    return method.Invoke(null, arguments)
}

test "generic safe casts preserve null results, covariance, and reference identity" {
    source := "import System.Collections.Generic\n\nfunc AsReadOnly(value: object?): IReadOnlyList<object?>? {\n    return value as IReadOnlyList<object?>\n}\n"
    method := GenericSafeCastMethod(GenericSafeCastAssembly(source))

    values: object[] = ["kept", null]
    objectResult := GenericSafeCastInvoke(method, values)
    assert Object.ReferenceEquals(objectResult, values)

    assert GenericSafeCastInvoke(method, null) == null

    strings := new List<string>()
    strings.Add("same")
    stringResult := GenericSafeCastInvoke(method, strings)
    assert Object.ReferenceEquals(stringResult, strings)

    numbers := new List<int>()
    numbers.Add(7)
    assert GenericSafeCastInvoke(method, numbers) == null
}

test "safe casts decline value targets" {
    nullableSource := "func AsNullable(value: object?): object? {\n    return value as int?\n}\n"
    assert GenericSafeCastDeclines(nullableSource)
}

// A SAFE CAST TO A GENERIC CLOSED OVER THE FUNCTION'S OWN TYPE PARAMETER. This used to decline: the
// type-parameter walk had no read-only-collection row, so `IReadOnlyList<T>` resolved to nothing and
// the cast had no target. The row exists on both walks now and admits a type-parameter argument, and
// `isinst` over a generic instantiation is ordinary IL — the instantiation is written into the token
// and the CLR closes it per call. The contract is therefore the runtime one: the SAME reference comes
// back when the value implements the closed interface, and null when it does not.
test "a safe cast to a generic closed over the function's own type parameter emits and dispatches" {
    openSource := "import System.Collections.Generic\n\nfunc AsOpen<T>(value: object?): object? {\n    return value as IReadOnlyList<T>\n}\n"
    assembly := GenericSafeCastAssembly(openSource)
    owner := assembly.GetType("Program")
    if owner == null {
        throw new InvalidOperationException("The open generic safe-cast fixture did not publish Program.")
    }
    openMethod := owner.GetMethod("AsOpen")
    if openMethod == null {
        throw new InvalidOperationException("The open generic safe-cast fixture did not publish AsOpen.")
    }
    typeArguments := new Type[](1)
    typeArguments[0] = typeof(string)
    closedMethod := openMethod.MakeGenericMethod(typeArguments)

    strings := new List<string>()
    strings.Add("kept")
    assert Object.ReferenceEquals(GenericSafeCastInvoke(closedMethod, strings), strings)

    numbers := new List<int>()
    numbers.Add(7)
    assert GenericSafeCastInvoke(closedMethod, numbers) == null

    assert GenericSafeCastInvoke(closedMethod, null) == null
}

test "a source type shadows the read-only collection head" {
    shadowedSource := "import System.Collections.Generic\n\nclass IReadOnlyList {}\n\nfunc AsShadowed(value: object?): object? {\n    return value as IReadOnlyList<int>\n}\n"
    assert GenericSafeCastDeclines(shadowedSource)
}

// THE VALUE-TYPE RULE BELONGS TO THE OPERATOR, NOT TO THE TARGET. `as` refuses a value target above
// because it must hand back the TYPE and a non-nullable value type has no null to hand back. `is`
// asks a different question — `isinst` takes a value-type token and answers "is this reference a
// boxed one of these" — so it accepts the same target, for a primitive and equally for a source
// struct closed over its own type parameters, which is how a `readonly struct` writes the
// `override func Equals(obj: object?)` every `IEquatable<T>` implementation needs.
test "an is-test accepts the value target its sibling safe cast refuses" {
    primitiveSource := "func IsInt(value: object?): bool {\n    return value is int\n}\n"
    assert !GenericSafeCastDeclines(primitiveSource)

    selfTypedSource := "import System\nimport System.Collections.Generic\n\nreadonly struct Box<T>: IEquatable<Box<T>> {\n    readonly value: T\n\n    constructor(value: T) {\n        this.value = value\n    }\n\n    func Equals(other: Box<T>): bool {\n        return EqualityComparer<T>.Default.Equals(value, other.value)\n    }\n\n    override func Equals(obj: object?): bool {\n        return obj is Box<T> other && Equals(other)\n    }\n\n    override func GetHashCode(): int {\n        return 0\n    }\n}\n"
    assert !GenericSafeCastDeclines(selfTypedSource)
}
