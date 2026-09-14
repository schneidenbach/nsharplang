using NSharpLang.Compiler.CodeIntelligence;

namespace NSharpLang.LanguageServer.Services;

/// <summary>
/// The editor-side names for two questions `CodeIntelligenceTextUtilities` owns. Nothing is decided
/// here: both members forward, and the file exists only because ten call sites across nine handlers
/// spell the short name. Deleting it outright is the right end state and is blocked by the growth
/// ratchet — every one of those nine handlers sits at its epoch ceiling, so each would have to grow
/// by the `using` line the longer owner name needs.
/// </summary>
public static class EditorUtilities
{
    /// <summary>
    /// Extracts the identifier word at the given 0-based line and character position.
    /// Returns empty string if position is on whitespace, operator, or out of bounds.
    /// </summary>
    public static string GetWordAtPosition(string text, int line, int character) =>
        CodeIntelligenceTextUtilities.GetEditorWordAtPosition(text, line, character);

    /// <summary>
    /// Returns true when the given position is in string literal text, but not in
    /// an interpolated expression hole where identifiers are real code.
    /// </summary>
    public static bool IsPositionInsideStringLiteral(string text, int line, int character) =>
        CodeIntelligenceTextUtilities.IsEditorPositionInsideStringLiteral(text, line, character);
}
