namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler


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

    // THE READING DIRECTION, FOR THE EMITTER. The element names an EXTERNAL method's return position
    // declares, trimmed to the tuple's own arity -- which is what a body needs to rewrite `r.Min` into
    // `r.Item1`. The attribute's array is the FLATTENED walk, and its first `arity` entries are always
    // the top-level tuple's own names, so the trim is a prefix rather than a search. Null when the
    // return is not a tuple, or carries no attribute, or names nothing.
    static func TopLevelReturnNames(method: MethodInfo): string[]? {
        arity := ValueTupleArity(method.get_ReturnType())
        if arity <= 0 {
            return null
        }

        flattened := AnalyzerTupleElementNames.Read(method.get_ReturnParameter().GetCustomAttributesData())
        if flattened == null {
            return null
        }

        names := new string[](arity)
        named := false
        index := 0
        while index < arity {
            declared: string? = null
            if index < flattened.Length {
                declared = flattened[index]
            }

            names[index] = declared ?? ""
            if names[index].Length > 0 {
                named = true
            }

            index = index + 1
        }

        if !named {
            return null
        }

        return names
    }

    // The number of elements a `ValueTuple` carries, following the REST nesting a tuple of more than
    // seven elements uses. Zero for anything that is not a tuple.
    static func ValueTupleArity(clrType: Type?): int {
        if clrType == null || !clrType.get_IsGenericType() {
            return 0
        }

        definition := clrType.GetGenericTypeDefinition()
        fullName := definition.FullName
        if fullName == null || !fullName.StartsWith("System.ValueTuple`", StringComparison.Ordinal) {
            return 0
        }

        arguments := clrType.GetGenericArguments()
        if arguments.Length == 8 {
            rest := ValueTupleArity(arguments[7])
            if rest > 0 {
                return 7 + rest
            }
        }

        return arguments.Length
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
