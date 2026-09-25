namespace NSharpLang.Compiler

// THE CLR NAME EACH BUILT-IN TYPE SPELLING DENOTES.
//
// `int` is `System.Int32`, `nint` is `System.IntPtr`, and so on for every spelling the language
// resolves before any other channel. The membership is the SAME membership
// `AnalyzerTypeReferenceFacts.IsBuiltInTypeName` answers -- the estate asserts the two agree on every
// name -- so a spelling can never be resolvable here and unknown there. It is a language fact with no
// analyzer state behind it, which is why the editor's type catalog can read it without reaching into
// the analyzer.
class BuiltInTypeSpellings {

    // The CLR name a built-in spelling denotes, or null when the name is not a built-in spelling.
    static func BuiltInClrTypeName(name: string): string? {
        if name == "bool" {
            return "System.Boolean"
        }
        if name == "byte" {
            return "System.Byte"
        }
        if name == "sbyte" {
            return "System.SByte"
        }
        if name == "short" {
            return "System.Int16"
        }
        if name == "ushort" {
            return "System.UInt16"
        }
        if name == "int" {
            return "System.Int32"
        }
        if name == "uint" {
            return "System.UInt32"
        }
        if name == "long" {
            return "System.Int64"
        }
        if name == "ulong" {
            return "System.UInt64"
        }
        if name == "nint" {
            return "System.IntPtr"
        }
        if name == "nuint" {
            return "System.UIntPtr"
        }
        if name == "char" {
            return "System.Char"
        }
        if name == "float" {
            return "System.Single"
        }
        if name == "double" {
            return "System.Double"
        }
        if name == "decimal" {
            return "System.Decimal"
        }
        if name == "string" {
            return "System.String"
        }
        if name == "object" {
            return "System.Object"
        }
        if name == "void" {
            return "System.Void"
        }
        return null
    }
}
