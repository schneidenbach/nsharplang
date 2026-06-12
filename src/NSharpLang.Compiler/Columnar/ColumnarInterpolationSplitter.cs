using System.Collections.Generic;

namespace NSharpLang.Compiler.Columnar;

/// <summary>
/// Splits a $-string literal's TOKEN TEXT (the full `$"…"` span — the lexer emits ONE token with the
/// `$` and the holes inside it) into text segments and holes, mirroring the production parser's
/// re-lex (Parser.ParseInterpolatedString): `{{`/`}}` collapse to literal braces in TEXT, escape
/// pairs stay VERBATIM in text segments (StringLiteralDecoder.DecodeBody decodes at emit, exactly
/// like the oracle's EmitInterpolatedString), and a `{…}` hole splits at the first colon into an
/// expression part and a format clause. The modelled HOLE GRAMMAR is identifier chains only —
/// `name` / `name.field.field` — with an optional non-empty `:format`; any richer hole content
/// (calls, operators, ternaries, whitespace, nested strings/braces) returns false and the consumer
/// DECLINES to the C# fallback, which compiles it via the full sub-parse. Both the columnar emitter
/// and the diagnostics pass consume this splitter, so hole identifier USES and emitted IL agree by
/// construction (a program one of them cannot model declines for both).
/// </summary>
internal static class ColumnarInterpolationSplitter
{
    internal readonly struct Part
    {
        public Part(bool isHole, string text, string? format)
        {
            IsHole = isHole;
            Text = text;
            Format = format;
        }

        /// <summary>False = a TEXT segment (escapes verbatim); true = a hole.</summary>
        public bool IsHole { get; }

        /// <summary>The text segment, or the hole's identifier chain (`a` / `a.b.c`).</summary>
        public string Text { get; }

        /// <summary>The hole's format clause (the text after the first `:`), null when absent.</summary>
        public string? Format { get; }
    }

    internal static bool TrySplit(string literal, List<Part> parts)
    {
        // The token text is `$"…"`: strip the `$"` prefix and the closing quote.
        if (literal.Length < 3 || literal[0] != '$' || literal[1] != '"' || literal[^1] != '"')
            return false;
        var text = new System.Text.StringBuilder();
        var i = 2;
        var end = literal.Length - 1;
        while (i < end)
        {
            var c = literal[i];
            if (c == '\\' && i + 1 < end)
            {
                // Escape pairs stay VERBATIM in the text segment (decoded at emit, the oracle's rule).
                text.Append(c).Append(literal[i + 1]);
                i += 2;
                continue;
            }
            if (c == '{')
            {
                if (i + 1 < end && literal[i + 1] == '{')
                {
                    text.Append('{');
                    i += 2;
                    continue;
                }
                var close = literal.IndexOf('}', i + 1);
                if (close < 0 || close >= end)
                    return false; // unterminated hole.
                var content = literal.Substring(i + 1, close - i - 1);
                var colon = content.IndexOf(':');
                var expr = colon >= 0 ? content.Substring(0, colon) : content;
                var format = colon >= 0 ? content.Substring(colon + 1) : null;
                if (!IsIdentifierChain(expr) || format is { Length: 0 })
                    return false; // beyond the modelled hole grammar — decline.
                // The production hole scan is BRACE-DEPTH aware (and respects nested strings/escapes);
                // this splitter closes at the FIRST `}`. A format clause containing braces, quotes, or
                // backslashes could therefore disagree on the hole boundary — decline those outright so
                // the boundary rules can never diverge (plain `:F2`-style clauses, the entire observed
                // surface, contain none of them).
                if (format != null && format.IndexOfAny(new[] { '{', '}', '"', '\\' }) >= 0)
                    return false;
                if (text.Length > 0)
                {
                    parts.Add(new Part(false, text.ToString(), null));
                    text.Clear();
                }
                parts.Add(new Part(true, expr, format));
                i = close + 1;
                continue;
            }
            if (c == '}')
            {
                if (i + 1 < end && literal[i + 1] == '}')
                {
                    text.Append('}');
                    i += 2;
                    continue;
                }
                return false; // a lone `}` — not modelled.
            }
            text.Append(c);
            i++;
        }
        if (text.Length > 0)
            parts.Add(new Part(false, text.ToString(), null));
        return true;
    }

    /// <summary>
    /// The hole ROOT identifiers (the first name of each hole chain) — the diagnostics pass marks
    /// these as USES so a local referenced only inside a hole is never a false NL001.
    /// </summary>
    internal static void CollectHoleRoots(List<Part> parts, HashSet<string> roots)
    {
        foreach (var part in parts)
        {
            if (!part.IsHole)
                continue;
            var dot = part.Text.IndexOf('.');
            roots.Add(dot < 0 ? part.Text : part.Text.Substring(0, dot));
        }
    }

    private static bool IsIdentifierChain(string s)
    {
        if (s.Length == 0)
            return false;
        var expectIdentStart = true;
        foreach (var ch in s)
        {
            if (expectIdentStart)
            {
                if (!char.IsLetter(ch) && ch != '_')
                    return false;
                expectIdentStart = false;
            }
            else if (ch == '.')
            {
                expectIdentStart = true;
            }
            else if (!char.IsLetterOrDigit(ch) && ch != '_')
            {
                return false;
            }
        }
        return !expectIdentStart; // no trailing dot.
    }
}
