namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit

test "field metadata emitter preserves planned visibility static readonly and ThreadStatic facts" {
    owner := TypeOfCreateBuilder("FieldMetadataEmitterFacts", "NSharpFieldMetadataEmitter", 0)
    privateThreadStatic := ColumnarFieldMetadataEmitter.Define(owner, "Trace", typeof(int), 49, true, false, 0)
    publicInstance := ColumnarFieldMetadataEmitter.Define(owner, "Value", typeof(string), 6, false, false, 0)

    assert privateThreadStatic.get_IsPrivate()
    assert privateThreadStatic.get_IsStatic()
    assert privateThreadStatic.get_IsInitOnly()
    assert !publicInstance.get_IsPrivate()
    assert !publicInstance.get_IsStatic()
    assert !publicInstance.get_IsInitOnly()

    createType := ExecutorRequiredMethod(typeof(TypeBuilder), "CreateType", new Type[](0))
    bakedValue := TypeOfRequiredInvocation(createType, owner, new object[](0))
    baked := bakedValue as Type
    assert baked != null
    trace := baked.GetField("Trace", BindingFlags.NonPublic | BindingFlags.Static)
    value := baked.GetField("Value", BindingFlags.Public | BindingFlags.Instance)
    assert trace != null
    assert value != null
    assert trace.get_IsPrivate()
    assert trace.get_IsStatic()
    assert trace.get_IsInitOnly()
    threadStaticType := TypeOfRequiredRuntimeType(typeof(object), "System.ThreadStaticAttribute")
    assert trace.IsDefined(threadStaticType, false)
    assert !value.IsDefined(threadStaticType, false)
}

test "literal field metadata publishes a CLR constant row and rejects init-only storage" {
    owner := TypeOfCreateBuilder("LiteralFieldMetadataEmitterFacts", "NSharpLiteralFieldMetadataEmitter", 0)
    literal := ColumnarFieldMetadataEmitter.Define(owner, "Answer", typeof(int), 32854, false, true, 17)

    assert literal.get_IsPublic()
    assert literal.get_IsStatic()
    assert literal.get_IsLiteral()
    assert !literal.get_IsInitOnly()

    createType := ExecutorRequiredMethod(typeof(TypeBuilder), "CreateType", new Type[](0))
    bakedValue := TypeOfRequiredInvocation(createType, owner, new object[](0))
    baked := bakedValue as Type
    assert baked != null
    field := baked.GetField("Answer", BindingFlags.Public | BindingFlags.Static)
    assert field != null
    assert field.get_IsLiteral()
    assert field.GetRawConstantValue().ToString() == "17"
}

test "the first source literal field slice accepts only unsuffixed int values" {
    value := 0
    assert ColumnarFieldMetadataEmitter.TryGetIntLiteralValue(typeof(int), 1, "65536", out value)
    assert value == 65536
    assert !ColumnarFieldMetadataEmitter.TryGetIntLiteralValue(typeof(int), 1, "65536L", out value)
    assert !ColumnarFieldMetadataEmitter.TryGetIntLiteralValue(typeof(long), 1, "65536", out value)
    assert !ColumnarFieldMetadataEmitter.TryGetIntLiteralValue(typeof(int), 4, "65536", out value)
    assert !ColumnarFieldMetadataEmitter.TryGetIntLiteralValue(typeof(int), 1, "2147483648", out value)
}
