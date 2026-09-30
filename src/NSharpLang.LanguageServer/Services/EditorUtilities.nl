namespace NSharpLang.LanguageServer.Services

import NSharpLang.Compiler.CodeIntelligence

// The editor-side names for two questions `CodeIntelligenceTextUtilities` owns. Nothing is decided
// here: both members forward, and the file exists only because ten call sites across nine handlers
// spell the short name.
class EditorUtilities {

    // Extracts the identifier word at the given 0-based line and character position.
    // Returns empty string if position is on whitespace, operator, or out of bounds.
    static func GetWordAtPosition(text: string, line: int, character: int): string => CodeIntelligenceTextUtilities.GetEditorWordAtPosition(text, line, character)

    // Returns true when the given position is in string literal text, but not in
    // an interpolated expression hole where identifiers are real code.
    static func IsPositionInsideStringLiteral(text: string, line: int, character: int): bool => CodeIntelligenceTextUtilities.IsEditorPositionInsideStringLiteral(text, line, character)
}
