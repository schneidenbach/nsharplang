namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit


// WRITING `TupleElementNamesAttribute` ONTO THE POSITIONS THAT MENTION A NAMED TUPLE.
//
// A named tuple is a `System.ValueTuple` in metadata and nothing else; the names are an attribute on
// the SIGNATURE POSITION -- the return parameter, a parameter, a field, a property -- not on the type.
// Without it a C# consumer of an N# assembly sees `ValueTuple<int, int>` and has only `Item1`/`Item2`,
// which is the same thing an N# consumer of a C# assembly sees when the C# side omits it. Every
// language that wants its element names to survive the assembly boundary writes this attribute, so
// N# writes it too, in the byte-exact shape the C# compiler writes.
//
// THE BLOB IS HAND-ROLLED, NOT BUILT WITH `CustomAttributeBuilder`. That builder's CONSTRUCTOR throws
// `PlatformNotSupportedException` under NativeAOT, so an AOT `nlc` would silently drop every tuple
// name; `ColumnarAttributeBlobs` spells the ECMA-335 bytes instead and the emit host attaches them
// with `SetCustomAttribute(ConstructorInfo, byte[])`.
//
// THE PARAMETER BUILDER IS NEVER DEFINED TWICE. `DefineParameter` is what creates a Param row, so
// calling it a second time for the same position would overwrite the name and flags the parameter
// metadata owner just wrote. Parameters therefore take the builder that owner already made
// (`ApplyToParameter`); only the RETURN position, which nothing else defines, is created here.
class ColumnarTupleElementNameEmitter {

    // `TupleElementNamesAttribute(string[])`, resolved from the reference universe the way the other
    // compiler-services attributes are. Null when the target framework has no such type, in which
    // case no position carries names -- the same silence C# keeps when the attribute is unavailable.
    static func Constructor(): ConstructorInfo? {
        return typeof(System.Runtime.CompilerServices.TupleElementNamesAttribute).GetConstructor([typeof(string[])])
    }

    // The method's RETURN position. `DefineParameter(0, ...)` is the return value's Param row, and no
    // other owner writes it, so creating it here is safe.
    static func ApplyToReturn(method: MethodBuilder, labeledCanonical: string?) {
        names := Flatten(labeledCanonical)
        if names == null {
            return
        }

        constructor := Constructor()
        if constructor == null {
            return
        }

        returnParameter := method.DefineParameter(0, ParameterAttributes.None, null)
        returnParameter.SetCustomAttribute(constructor, ColumnarTupleElementNames.Blob(names))
    }

    // One already-defined parameter position.
    static func ApplyToParameter(parameter: ParameterBuilder, labeledCanonical: string?) {
        names := Flatten(labeledCanonical)
        if names == null {
            return
        }

        constructor := Constructor()
        if constructor == null {
            return
        }

        parameter.SetCustomAttribute(constructor, ColumnarTupleElementNames.Blob(names))
    }

    // A field whose written type mentions a named tuple.
    static func ApplyToField(field: FieldBuilder, labeledCanonical: string?) {
        names := Flatten(labeledCanonical)
        if names == null {
            return
        }

        constructor := Constructor()
        if constructor == null {
            return
        }

        field.SetCustomAttribute(constructor, ColumnarTupleElementNames.Blob(names))
    }

    // A property. C# writes the attribute on the property itself AS WELL AS on its accessors'
    // positions, and a consumer that reads `PropertyInfo.GetCustomAttributesData()` sees only this
    // one, so both are needed for the names to be visible from every angle.
    static func ApplyToProperty(property: PropertyBuilder, labeledCanonical: string?) {
        names := Flatten(labeledCanonical)
        if names == null {
            return
        }

        constructor := Constructor()
        if constructor == null {
            return
        }

        property.SetCustomAttribute(constructor, ColumnarTupleElementNames.Blob(names))
    }

    // The labelled canonical of one position, flattened, or null when the position names nothing and
    // must therefore carry no attribute at all.
    static func Flatten(labeledCanonical: string?): string[]? {
        if labeledCanonical == null {
            return null
        }

        return ColumnarTupleElementNames.Flatten(labeledCanonical)
    }
}
