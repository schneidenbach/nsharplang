namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections
import System.Reflection

// Normal malformed native declarations stop at parsing, before the precedence being tested.
// Parse one valid input, alter only its metadata fields, and invoke the existing emitter entry
// directly so return, parameter, native-row and shared default validation compete in production.
// This test-only reflection access adds no host bridge or alternate emitter.
func PutPInvokeFixtureArgument(values: object?[], index: int, value: object?) {
    values[index] = value
}

func PInvokeFixtureHostMethod(typeName: string, methodName: string): MethodInfo {
    owner := Type.GetType("NSharpLang.Compiler.Columnar." + typeName + ", Compiler")
    if owner == null {
        throw new InvalidOperationException("Missing host " + typeName)
    }
    methods := owner.GetMethods((BindingFlags)40)
    for method in methods {
        if method.get_Name() == methodName {
            return method
        }
    }
    throw new InvalidOperationException("Missing host method " + methodName)
}

func ReadPInvokeFixtureField(target: object, name: string): object? {
    targetType := target.GetType()
    field := targetType.GetField(name)
    if field == null {
        throw new InvalidOperationException("Missing field " + name)
    }
    return field.GetValue(target)
}

func WritePInvokeFixtureField(target: object, name: string, value: object?) {
    targetType := target.GetType()
    field := targetType.GetField(name)
    if field == null {
        throw new InvalidOperationException("Missing field " + name)
    }
    field.SetValue(target, value)
}

func ReadPInvokeDeclineProperty(target: object, name: string): string {
    targetType := target.GetType()
    property := targetType.GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Missing property " + name)
    }
    return Convert.ToString(property.GetValue(target)) ?? ""
}

func EmitPInvokeFixtureWithInvalidMetadata(invalidReturn: bool, invalidParameter: bool, invalidNative: bool, invalidDefault: bool): string {
    parse := PInvokeFixtureHostMethod("ColumnarProgramInputBuilder", "TryBuild")
    args := new object?[](2)
    PutPInvokeFixtureArgument(args, 0, "static class Native {\n    [LibraryImport(\"c\", EntryPoint = \"abs\")]\n    static func Abs(value: int = 9): int\n}\n")
    PutPInvokeFixtureArgument(args, 1, null)
    assert Convert.ToBoolean(parse.Invoke(null, args))
    program := args[1]
    if program == null {
        throw new InvalidOperationException("Parser returned no program")
    }
    structs := ReadPInvokeFixtureField(program, "Structs") as IList
    if structs == null {
        throw new InvalidOperationException("No struct list")
    }
    owner := structs[0]
    if owner == null {
        throw new InvalidOperationException("No owner")
    }
    methods := ReadPInvokeFixtureField(owner, "Methods") as IList
    if methods == null {
        throw new InvalidOperationException("No method list")
    }
    method := methods[0]
    if method == null {
        throw new InvalidOperationException("No native method")
    }
    if invalidReturn {
        WritePInvokeFixtureField(method, "ReturnCanonical", "NoSuchReturn")
    }
    if invalidParameter {
        parameterTypes := new string[](1)
        parameterTypes[0] = "NoSuchParameter"
        WritePInvokeFixtureField(method, "ParamCanonicals", parameterTypes)
    }
    if invalidNative {
        WritePInvokeFixtureField(method, "NativeImportLibraryName", "")
    }
    if invalidDefault {
        defaultKinds := new int[](1)
        defaultKinds[0] = 9999
        WritePInvokeFixtureField(method, "ParamDefaultKinds", defaultKinds)
    }
    reset := PInvokeFixtureHostMethod("ColumnarDeclineTrace", "Reset")
    emptyArguments := new object?[](0)
    resetResult := reset.Invoke(null, emptyArguments)
    _ = resetResult
    emit := PInvokeFixtureHostMethod("ColumnarIlEmitter", "TryEmitColumnarAssembly")
    emitArgs := new object?[](7)
    PutPInvokeFixtureArgument(emitArgs, 0, "PInvokeDeclarationControl")
    PutPInvokeFixtureArgument(emitArgs, 1, "Program")
    PutPInvokeFixtureArgument(emitArgs, 2, program)
    PutPInvokeFixtureArgument(emitArgs, 3, false)
    PutPInvokeFixtureArgument(emitArgs, 4, null)
    PutPInvokeFixtureArgument(emitArgs, 5, null)
    PutPInvokeFixtureArgument(emitArgs, 6, null)
    succeeded := Convert.ToBoolean(emit.Invoke(null, emitArgs))
    snapshot := PInvokeFixtureHostMethod("ColumnarDeclineTrace", "Snapshot")
    records := snapshot.Invoke(null, emptyArguments) as IList
    if records == null {
        throw new InvalidOperationException("No decline snapshot")
    }
    if records.Count == 0 {
        if succeeded {
            image := emitArgs[4] as IList
            assert image != null
            assert image.Count > 2
            assert Convert.ToInt32(image[0]) == 77
            assert Convert.ToInt32(image[1]) == 90
            return "success"
        }
        return "false without decline"
    }
    assert !succeeded
    assert records.Count == 1
    first := records[0]
    if first == null {
        throw new InvalidOperationException("No first decline")
    }
    return ReadPInvokeDeclineProperty(first, "SiteId") + "|" + ReadPInvokeDeclineProperty(first, "Message") + "|" + ReadPInvokeDeclineProperty(first, "MemberName")
}

test "PInvoke return resolution precedes parameter native and default validation" {
    assert EmitPInvokeFixtureWithInvalidMetadata(true, true, true, true) == "emit.declaration.method-return|static method return type 'NoSuchReturn' could not be resolved for 'Native.Abs'|Native"
}

test "PInvoke parameter resolution precedes native and default validation" {
    assert EmitPInvokeFixtureWithInvalidMetadata(false, true, true, true) == "emit.declaration.method-param|static method parameter type 'NoSuchParameter' could not be resolved for 'Native.Abs'|Native"
}

test "PInvoke native validity precedes unsupported default emission" {
    assert EmitPInvokeFixtureWithInvalidMetadata(false, false, true, true) == "emit.declaration.native-import|native import metadata was invalid for 'Native.Abs'|Native"
}

test "PInvoke unsupported parameter default returns false without a located decline" {
    assert EmitPInvokeFixtureWithInvalidMetadata(false, false, false, true) == "false without decline"
}

test "PInvoke supported default emits the same valid native input" {
    assert EmitPInvokeFixtureWithInvalidMetadata(false, false, false, false) == "success"
}
