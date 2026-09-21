namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler


// THE METADATA A SIGNATURE POSITION CARRIES BESIDE ITS TYPE: a named tuple's element names and a
// reference type's nullability. Both are attributes on the POSITION -- a return parameter, a
// parameter, a field, a property -- rather than on the type, both are written by every .NET language
// that wants them to survive the assembly boundary, and both are decided from the SAME input: the
// type AS WRITTEN, whose labelled canonical still carries the element labels and the `?`s that the
// structural canonical and the CLR handle have both discarded.
//
// THIS IS THE SOLE WRITER OF A METHOD'S RETURN `Param` ROW. `DefineParameter(0, …)` is what CREATES
// that row, so two owners each calling it would emit the row twice; the return position therefore
// has one entry point that creates the row once and attaches whatever the two attribute owners
// have to say about it. A parameter, a field and a property already have a builder by the time they
// get here, so those three only attach.
//
// The blobs are hand-rolled rather than built with `CustomAttributeBuilder`, for the reason
// `ColumnarAttributeBlobs` records: that builder's CONSTRUCTOR throws under NativeAOT, so an AOT
// `nlc` would silently drop every one of these attributes.
class ColumnarSignatureMetadataEmitter {

    // `NullableAttribute(byte)` and `NullableAttribute(byte[])`, resolved from the reference universe
    // the way the other compiler-services attributes are. Null when the target framework has no such
    // type, in which case no position carries flags -- the same silence C# keeps when an attribute it
    // would synthesise is unavailable.
    static func NullableByteConstructor(): ConstructorInfo? {
        return typeof(System.Runtime.CompilerServices.NullableAttribute).GetConstructor([typeof(byte)])
    }

    static func NullableByteArrayConstructor(): ConstructorInfo? {
        return typeof(System.Runtime.CompilerServices.NullableAttribute).GetConstructor([typeof(byte[])])
    }

    // The method's RETURN position, with both attributes. The row is created only when at least one
    // of them has something to say, so a method whose return is an `int` still has no `Param` row for
    // it -- which is what every N# assembly emitted before this owner existed.
    static func ApplyToReturn(method: MethodBuilder, returnType: Type?, labeledCanonical: string?) {
        names := ColumnarTupleElementNameEmitter.Flatten(labeledCanonical)
        flags := ColumnarNullableMetadata.TryFlags(returnType, labeledCanonical)
        if names == null && flags == null {
            return
        }

        returnParameter := method.DefineParameter(0, ParameterAttributes.None, null)
        if names != null {
            ColumnarTupleElementNameEmitter.ApplyToParameter(returnParameter, labeledCanonical)
        }

        ApplyFlagsToParameter(returnParameter, flags)
    }

    // One already-defined parameter position.
    static func ApplyToParameter(parameter: ParameterBuilder, parameterType: Type?, labeledCanonical: string?) {
        ColumnarTupleElementNameEmitter.ApplyToParameter(parameter, labeledCanonical)
        ApplyFlagsToParameter(parameter, ColumnarNullableMetadata.TryFlags(parameterType, labeledCanonical))
    }

    // A field whose written type mentions a named tuple or an annotated reference type.
    static func ApplyToField(field: FieldBuilder, fieldType: Type?, labeledCanonical: string?) {
        ColumnarTupleElementNameEmitter.ApplyToField(field, labeledCanonical)
        flags := ColumnarNullableMetadata.TryFlags(fieldType, labeledCanonical)
        if flags == null {
            return
        }

        if ColumnarNullableMetadata.IsUniform(flags) {
            singleConstructor := NullableByteConstructor()
            if singleConstructor == null {
                return
            }

            field.SetCustomAttribute(singleConstructor, ColumnarAttributeBlobs.OneByte(flags[0]))
            return
        }

        arrayConstructor := NullableByteArrayConstructor()
        if arrayConstructor == null {
            return
        }

        field.SetCustomAttribute(arrayConstructor, ColumnarAttributeBlobs.ByteArray(flags))
    }

    // A property. `NullabilityInfoContext.Create(PropertyInfo)` and Roslyn's own metadata reader both
    // read the flags off the PROPERTY row rather than off its accessors, which is also where the
    // tuple names go, so one attachment answers every reader.
    static func ApplyToProperty(property: PropertyBuilder, propertyType: Type?, labeledCanonical: string?) {
        ColumnarTupleElementNameEmitter.ApplyToProperty(property, labeledCanonical)
        flags := ColumnarNullableMetadata.TryFlags(propertyType, labeledCanonical)
        if flags == null {
            return
        }

        if ColumnarNullableMetadata.IsUniform(flags) {
            singleConstructor := NullableByteConstructor()
            if singleConstructor == null {
                return
            }

            property.SetCustomAttribute(singleConstructor, ColumnarAttributeBlobs.OneByte(flags[0]))
            return
        }

        arrayConstructor := NullableByteArrayConstructor()
        if arrayConstructor == null {
            return
        }

        property.SetCustomAttribute(arrayConstructor, ColumnarAttributeBlobs.ByteArray(flags))
    }

    static func ApplyFlagsToParameter(parameter: ParameterBuilder, flags: int[]?) {
        if flags == null {
            return
        }

        if ColumnarNullableMetadata.IsUniform(flags) {
            singleConstructor := NullableByteConstructor()
            if singleConstructor == null {
                return
            }

            parameter.SetCustomAttribute(singleConstructor, ColumnarAttributeBlobs.OneByte(flags[0]))
            return
        }

        arrayConstructor := NullableByteArrayConstructor()
        if arrayConstructor == null {
            return
        }

        parameter.SetCustomAttribute(arrayConstructor, ColumnarAttributeBlobs.ByteArray(flags))
    }
}
