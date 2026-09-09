namespace NSharpLang.Compiler

import System
import System.Reflection


// The analyzer's WELL-KNOWN-TYPE TABLES: the policy that is a pure function of
// `AnalyzerWellKnownTypes` (or of nothing at all).
//
// Three tables live here, and they are deliberately kept apart even though two of them look alike:
//
//   * KnownOpenGenericType — the compiler-known generic names, the ones a project may write WITHOUT
//     an import. It is consulted both when constructing a generic CLR type and when deciding whether
//     an unresolved generic name should be reported, so a name added here silently stops being
//     reported as missing.
//   * BindingSurrogateOpenGenericType — the SMALLER vocabulary used when a generic is being
//     reconstructed with `object` surrogates for N#-defined type arguments, purely so CLR method
//     binding can proceed. It deliberately omits `Result`, `JsonTypeInfo` and every namespace-
//     qualified spelling: those are only meaningful when the real type arguments are available.
//     Merging the two would silently widen the surrogate surface, so they stay separate — the same
//     discipline the two numeric vocabularies in `AnalyzerConversionFacts` are held to.
//   * BuiltInRuntimeClrType — the fallback used when no MetadataLoadContext facts exist at all. It
//     answers with RUNTIME types (the compiler's own), covers only the built-in simple types plus
//     arrays, nullables and oblivious wrappers, and — unlike the metadata-backed path — performs NO
//     alias resolution as it descends. That difference is behaviour, not an oversight.
//
// Every rule here is an exact, total function of its inputs — no analyzer state, no name resolution,
// no diagnostics. Do not reintroduce any of them in C#.
class AnalyzerWellKnownTypeFacts {

    // Compiler-known generic name + arity → its open CLR definition. Null when the name is not
    // compiler-known at that arity, or when no well-known-type facts have been built.
    static func KnownOpenGenericType(wellKnownTypes: AnalyzerWellKnownTypes?, name: string, arity: int): Type? {
        if wellKnownTypes == null {
            return null
        }

        if arity == 1 {
            if name == "List" {
                return wellKnownTypes.ListOpen
            }
            if name == "IEnumerable" {
                return wellKnownTypes.IEnumerableOpen
            }
            if name == "IQueryable" {
                return wellKnownTypes.IQueryableOpen
            }
            if name == "ICollection" {
                return wellKnownTypes.ICollectionOpen
            }
            if name == "IList" {
                return wellKnownTypes.IListOpen
            }
            if name == "Task" {
                return wellKnownTypes.TaskOpen
            }
            if name == "ValueTask" {
                return wellKnownTypes.ValueTaskOpen
            }
            if name == "JsonTypeInfo" || name == "System.Text.Json.Serialization.Metadata.JsonTypeInfo" {
                return wellKnownTypes.JsonTypeInfoOpen
            }

            if name == "Func" {
                return wellKnownTypes.Func1
            }
            if name == "Action" {
                return wellKnownTypes.Action1
            }
            return null
        }

        if arity == 2 {
            if name == "Dictionary" {
                return wellKnownTypes.DictionaryOpen
            }
            if name == "IDictionary" {
                return wellKnownTypes.IDictionaryOpen
            }
            if name == "Result" || name == "NSharpLang.Runtime.Result" {
                return wellKnownTypes.GetRuntimeResultOpen()
            }

            if name == "Func" {
                return wellKnownTypes.Func2
            }
            if name == "Action" {
                return wellKnownTypes.Action2
            }
            return null
        }

        if arity == 3 {
            if name == "Func" {
                return wellKnownTypes.Func3
            }
            if name == "Action" {
                return wellKnownTypes.Action3
            }
            return null
        }

        if arity == 4 {
            if name == "Func" {
                return wellKnownTypes.Func4
            }
            if name == "Action" {
                return wellKnownTypes.Action4
            }
            return null
        }

        if arity == 5 && name == "Func" {
            return wellKnownTypes.Func5
        }

        return null
    }

    // The surrogate-binding vocabulary. Strictly smaller than KnownOpenGenericType: no `Result`, no
    // `JsonTypeInfo`, no qualified spellings. See the class comment for why they are not merged.
    static func BindingSurrogateOpenGenericType(wellKnownTypes: AnalyzerWellKnownTypes?, name: string, arity: int): Type? {
        if wellKnownTypes == null {
            return null
        }

        if arity == 1 {
            if name == "List" {
                return wellKnownTypes.ListOpen
            }
            if name == "IEnumerable" {
                return wellKnownTypes.IEnumerableOpen
            }
            if name == "IQueryable" {
                return wellKnownTypes.IQueryableOpen
            }
            if name == "ICollection" {
                return wellKnownTypes.ICollectionOpen
            }
            if name == "IList" {
                return wellKnownTypes.IListOpen
            }
            if name == "Task" {
                return wellKnownTypes.TaskOpen
            }
            if name == "ValueTask" {
                return wellKnownTypes.ValueTaskOpen
            }
            if name == "Func" {
                return wellKnownTypes.Func1
            }
            if name == "Action" {
                return wellKnownTypes.Action1
            }
            return null
        }

        if arity == 2 {
            if name == "Dictionary" {
                return wellKnownTypes.DictionaryOpen
            }
            if name == "IDictionary" {
                return wellKnownTypes.IDictionaryOpen
            }
            if name == "Func" {
                return wellKnownTypes.Func2
            }
            if name == "Action" {
                return wellKnownTypes.Action2
            }
            return null
        }

        if arity == 3 {
            if name == "Func" {
                return wellKnownTypes.Func3
            }
            if name == "Action" {
                return wellKnownTypes.Action3
            }
            return null
        }

        if arity == 4 {
            if name == "Func" {
                return wellKnownTypes.Func4
            }
            if name == "Action" {
                return wellKnownTypes.Action4
            }
            return null
        }

        if arity == 5 && name == "Func" {
            return wellKnownTypes.Func5
        }

        return null
    }

    // The built-in type KEYWORDS mapped to their METADATA CLR types, which is what makes
    // `int.Parse(...)` and `string.IsNullOrEmpty(...)` bind against the project's own core library.
    // Answers null without facts, and — unlike `BuiltInSimpleType`, the sixteen spellings the type
    // resolver recognises — deliberately omits `void`: there is no static member access on `void`,
    // and admitting the keyword here would let one be attempted.
    static func BuiltInMetadataClrType(wellKnownTypes: AnalyzerWellKnownTypes?, name: string): Type? {
        if wellKnownTypes == null {
            return null
        }

        if name == "int" {
            return wellKnownTypes.Int32
        }
        if name == "long" {
            return wellKnownTypes.Int64
        }
        if name == "float" {
            return wellKnownTypes.Single
        }
        if name == "double" {
            return wellKnownTypes.Double
        }
        if name == "decimal" {
            return wellKnownTypes.Decimal
        }
        if name == "byte" {
            return wellKnownTypes.Byte
        }
        if name == "sbyte" {
            return wellKnownTypes.SByte
        }
        if name == "short" {
            return wellKnownTypes.Int16
        }
        if name == "ushort" {
            return wellKnownTypes.UInt16
        }
        if name == "uint" {
            return wellKnownTypes.UInt32
        }
        if name == "ulong" {
            return wellKnownTypes.UInt64
        }
        if name == "char" {
            return wellKnownTypes.Char
        }
        if name == "bool" {
            return wellKnownTypes.Boolean
        }
        if name == "string" {
            return wellKnownTypes.String
        }
        if name == "object" {
            return wellKnownTypes.Object
        }
        return null
    }

    // The no-metadata fallback: a built-in TypeInfo mapped to the compiler's own RUNTIME type.
    // Descends through arrays, nullables and oblivious wrappers WITHOUT resolving aliases, and
    // answers null for everything else — including a nullable whose inner type is a reference type.
    static func BuiltInRuntimeClrType(candidate: TypeInfo): Type? {
        simple := candidate as SimpleTypeInfo
        if simple != null {
            return BuiltInSimpleRuntimeClrType(simple)
        }

        arrayType := candidate as ArrayTypeInfo
        if arrayType != null {
            elementType := BuiltInRuntimeClrType(arrayType.ElementType)
            if elementType == null {
                return null
            }

            return elementType.MakeArrayType()
        }

        nullableType := candidate as NullableTypeInfo
        if nullableType != null {
            innerType := BuiltInRuntimeClrType(nullableType.InnerType)
            if innerType == null || !innerType.get_IsValueType() {
                return null
            }

            nullableOpen := RuntimeCoreType("System.Nullable`1")
            if nullableOpen == null {
                return null
            }

            arguments := new Type[](1)
            arguments[0] = innerType
            return nullableOpen.MakeGenericType(arguments)
        }

        obliviousType := candidate as ObliviousTypeInfo
        if obliviousType != null {
            return BuiltInRuntimeClrType(obliviousType.InnerType)
        }

        return null
    }

    static func BuiltInSimpleRuntimeClrType(simple: SimpleTypeInfo): Type? {
        if BuiltInTypes.Is(simple, BuiltInTypes.Int) {
            return typeof(int)
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Long) {
            return typeof(long)
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Float) {
            return typeof(float)
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Double) {
            return typeof(double)
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Decimal) {
            return typeof(decimal)
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Byte) {
            return typeof(byte)
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.SByte) {
            return typeof(sbyte)
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Short) {
            return typeof(short)
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.UShort) {
            return typeof(ushort)
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.UInt) {
            return typeof(uint)
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.ULong) {
            return typeof(ulong)
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Char) {
            return typeof(char)
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Bool) {
            return typeof(bool)
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.String) {
            return typeof(string)
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Void) {
            return RuntimeCoreType("System.Void")
        }
        if BuiltInTypes.Is(simple, BuiltInTypes.Object) {
            return typeof(object)
        }
        return null
    }

    // `typeof(void)` and `typeof(Nullable<>)` are not part of the columnar front end's `typeof`
    // surface, and extending that surface is a compiler-capability change requiring a two-stage
    // bootstrap. The core library is read directly instead — the established
    // `typeof(object).get_Assembly()` idiom — which yields the identical runtime Type instances.
    static func RuntimeCoreType(fullName: string): Type? {
        coreLibrary := typeof(object).get_Assembly()
        return coreLibrary.GetType(fullName)
    }
}
