namespace NSharpLang.Compiler.Columnar

// THE PARSER-OWNED BITS OF A FUNCTION'S MODIFIER COLUMN.
//
// The columnar parser writes a function's modifiers as one int column, and the declaration planner
// reads it back through `ColumnarFunctionInput.ModifierFlags`. Most bits are `Modifiers` enum values;
// the native-import bit is not -- the parser sets it on a static, bodyless method that carries
// `[LibraryImport]` -- so both halves ask here, below the parser, rather than the parser asking the
// planner's input model.
class ColumnarFunctionModifierFlags {

    // The parser and declaration planner share this input flag. It is not a Modifiers enum member.
    static func NativeImportModifierFlag(): int {
        return 131072
    }

    static func HasNativeImportModifier(flags: int): bool {
        return (flags & NativeImportModifierFlag()) != 0
    }
}
