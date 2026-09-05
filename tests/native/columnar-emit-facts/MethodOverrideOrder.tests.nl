namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections
import System.Reflection

// Normal malformed override declarations stop at parsing, before the precedence being tested.
// Parse one valid input, alter only its metadata fields, and invoke the existing emitter entry
// directly so return, parameter, override-row and shared default validation compete in production.
// This test-only reflection access adds no host bridge or alternate emitter.
func PutOverrideFixtureArgument(values: object?[], index: int, value: object?) {
    values[index] = value
}

func OverrideFixtureHostMethod(typeName: string, methodName: string): MethodInfo {
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

func ReadOverrideFixtureField(target: object, name: string): object? {
    targetType := target.GetType()
    field := targetType.GetField(name)
    if field == null {
        throw new InvalidOperationException("Missing field " + name)
    }
    return field.GetValue(target)
}

func WriteOverrideFixtureField(target: object, name: string, value: object?) {
    targetType := target.GetType()
    field := targetType.GetField(name)
    if field == null {
        throw new InvalidOperationException("Missing field " + name)
    }
    field.SetValue(target, value)
}

func ReadOverrideDeclineProperty(target: object, name: string): string {
    targetType := target.GetType()
    property := targetType.GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Missing property " + name)
    }
    return Convert.ToString(property.GetValue(target)) ?? ""
}

func EmitOverrideFixtureWithInvalidMetadata(invalidReturn: bool, invalidParameter: bool, invalidBase: bool, invalidDefault: bool): string {
    parse := OverrideFixtureHostMethod("ColumnarProgramInputBuilder", "TryBuild")
    args := new object?[](2)
    PutOverrideFixtureArgument(args, 0, "class OverrideFixture {\n    override func Equals(value: object? = null): bool { return true }\n}\n")
    PutOverrideFixtureArgument(args, 1, null)
    assert Convert.ToBoolean(parse.Invoke(null, args))
    program := args[1]
    if program == null {
        throw new InvalidOperationException("Parser returned no program")
    }
    structs := ReadOverrideFixtureField(program, "Structs") as IList
    if structs == null {
        throw new InvalidOperationException("No struct list")
    }
    owner := structs[0]
    if owner == null {
        throw new InvalidOperationException("No owner")
    }
    methods := ReadOverrideFixtureField(owner, "Methods") as IList
    if methods == null {
        throw new InvalidOperationException("No method list")
    }
    method := methods[0]
    if method == null {
        throw new InvalidOperationException("No native method")
    }
    if invalidReturn {
        WriteOverrideFixtureField(method, "ReturnCanonical", "NoSuchReturn")
    }
    if invalidParameter {
        parameterTypes := new string[](1)
        parameterTypes[0] = "NoSuchParameter"
        WriteOverrideFixtureField(method, "ParamCanonicals", parameterTypes)
    }
    if invalidBase {
        WriteOverrideFixtureField(method, "Name", "NoBaseTarget")
    }
    if invalidDefault {
        defaultKinds := new int[](1)
        defaultKinds[0] = 9999
        WriteOverrideFixtureField(method, "ParamDefaultKinds", defaultKinds)
    }
    reset := OverrideFixtureHostMethod("ColumnarDeclineTrace", "Reset")
    emptyArguments := new object?[](0)
    resetResult := reset.Invoke(null, emptyArguments)
    _ = resetResult
    emit := OverrideFixtureHostMethod("ColumnarIlEmitter", "TryEmitColumnarAssembly")
    emitArgs := new object?[](7)
    PutOverrideFixtureArgument(emitArgs, 0, "OverrideDeclarationControl")
    PutOverrideFixtureArgument(emitArgs, 1, "Program")
    PutOverrideFixtureArgument(emitArgs, 2, program)
    PutOverrideFixtureArgument(emitArgs, 3, false)
    PutOverrideFixtureArgument(emitArgs, 4, null)
    PutOverrideFixtureArgument(emitArgs, 5, null)
    PutOverrideFixtureArgument(emitArgs, 6, null)
    succeeded := Convert.ToBoolean(emit.Invoke(null, emitArgs))
    snapshot := OverrideFixtureHostMethod("ColumnarDeclineTrace", "Snapshot")
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
    return ReadOverrideDeclineProperty(first, "SiteId") + "|" + ReadOverrideDeclineProperty(first, "Message") + "|" + ReadOverrideDeclineProperty(first, "MemberName")
}

test "override return resolution precedes invalid base target and default validation" {
    assert EmitOverrideFixtureWithInvalidMetadata(true, true, true, true) == "emit.declaration.method-return|method return type 'NoSuchReturn' could not be resolved for 'OverrideFixture.NoBaseTarget'|OverrideFixture"
}

test "override parameter resolution precedes invalid base target and default validation" {
    assert EmitOverrideFixtureWithInvalidMetadata(false, true, true, true) == "emit.declaration.method-param|method parameter type 'NoSuchParameter' could not be resolved for 'OverrideFixture.NoBaseTarget'|OverrideFixture"
}

test "invalid base target precedes unsupported parameter default emission" {
    assert EmitOverrideFixtureWithInvalidMetadata(false, false, true, true) == "emit.declaration.override-target|no overridable base member matches 'NoBaseTarget' for 'OverrideFixture'|OverrideFixture"
}

test "a valid override target reaches unsupported default failure without a located decline" {
    assert EmitOverrideFixtureWithInvalidMetadata(false, false, false, true) == "false without decline"
}

test "the same base override with its supported null default emits an MZ image" {
    assert EmitOverrideFixtureWithInvalidMetadata(false, false, false, false) == "success"
}
