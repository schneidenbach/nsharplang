namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit

test "field metadata emitter preserves planned visibility static readonly and ThreadStatic facts" {
    owner := TypeOfCreateBuilder("FieldMetadataEmitterFacts", "NSharpFieldMetadataEmitter", 0)
    privateThreadStatic := ColumnarFieldMetadataEmitter.Define(owner, "Trace", typeof(int), 49, true)
    publicInstance := ColumnarFieldMetadataEmitter.Define(owner, "Value", typeof(string), 6, false)

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
