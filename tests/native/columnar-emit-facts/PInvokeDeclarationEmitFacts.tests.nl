namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Runtime.InteropServices

static class PInvokeDeclarationNative {
    [LibraryImport("c", EntryPoint = "abs")]
    static func Abs(value: int = 9): int

    [LibraryImport("nsharp-pinvoke-metadata-only", EntryPoint = "Shapes")]
    static func Shapes(out result: int, flag: bool = true, text: string = "hello", nil: string? = null): int
}

test "PInvoke integer optional parameter preserves metadata and executes through libc" {
    method := typeof(PInvokeDeclarationNative).GetMethod("Abs")
    if method == null {
        throw new InvalidOperationException("Native method metadata missing.")
    }
    parameters := method.GetParameters()
    assert parameters.Length == 1
    valueParameter := parameters[0]
    assert valueParameter.get_Name() == "value"
    assert valueParameter.get_Position() == 0
    assert valueParameter.get_IsOptional()
    assert valueParameter.get_HasDefaultValue()
    assert Convert.ToInt32(valueParameter.get_RawDefaultValue()) == 9
    assert Convert.ToInt32(method.get_Attributes()) == 8342
    assert Convert.ToInt32(method.GetMethodImplementationFlags()) == 128
    assert method.GetMethodBody() == null
    // libc is the executable witness on Unix; the metadata assertions above are platform-independent.
    if !OperatingSystem.IsWindows() {
        assert PInvokeDeclarationNative.Abs(-9) == 9
    }
}

test "PInvoke out and bool string null defaults preserve parameter rows" {
    method := typeof(PInvokeDeclarationNative).GetMethod("Shapes")
    if method == null {
        throw new InvalidOperationException("Native method metadata missing.")
    }
    parameters := method.GetParameters()
    assert parameters.Length == 4
    outParameter := parameters[0]
    boolParameter := parameters[1]
    textParameter := parameters[2]
    nullParameter := parameters[3]
    assert outParameter.get_IsOut()
    assert !outParameter.get_IsOptional()
    assert !outParameter.get_HasDefaultValue()
    assert Convert.ToInt32(outParameter.get_Attributes()) == 2
    assert boolParameter.get_IsOptional()
    assert Convert.ToInt32(boolParameter.get_Attributes()) == 4112
    assert Convert.ToBoolean(boolParameter.get_RawDefaultValue())
    assert Convert.ToString(textParameter.get_RawDefaultValue()) == "hello"
    assert nullParameter.get_HasDefaultValue()
    assert nullParameter.get_RawDefaultValue() == null
}
