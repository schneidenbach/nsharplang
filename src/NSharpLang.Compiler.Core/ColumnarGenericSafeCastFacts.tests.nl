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
