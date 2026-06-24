namespace NSharpLang.Compiler;

public static class StringLiteralDecoder
{
    /// <summary>
    /// Materializes a string literal TOKEN TEXT (delimiting quotes included, escape pairs verbatim)
    /// into its runtime value. Tolerates unterminated tokens (no closing quote) from error recovery.
    /// </summary>
    public static string Decode(string tokenText)
    {
        var start = tokenText.Length > 0 && tokenText[0] == '"' ? 1 : 0;
        var end = tokenText.Length > start && tokenText[^1] == '"' ? tokenText.Length - 1 : tokenText.Length;
        return DecodeBody(tokenText.Substring(start, end - start));
    }

    /// <summary>
    /// Decodes a literal BODY (no delimiting quotes — e.g. an interpolated string's TEXT segment, whose
    /// escape pairs the parser keeps verbatim). The token-text overload strips delimiters then calls this.
    /// </summary>
    public static string DecodeBody(string body)
    {
        if (body.IndexOf('\\') < 0)
            return body;

        var sb = new System.Text.StringBuilder(body.Length);
        for (var i = 0; i < body.Length; i++)
        {
            var c = body[i];
            if (c != '\\' || i + 1 >= body.Length)
            {
                sb.Append(c);
                continue;
            }
            var next = body[i + 1];
            var decoded = next switch
            {
                '\'' => '\'',
                '"' => '"',
                '\\' => '\\',
                '0' => '\0',
                'a' => '\a',
                'b' => '\b',
                'f' => '\f',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                'v' => '\v',
                _ => '￿', // sentinel: unknown escape -> pass the pair through raw.
            };
            if (decoded == '￿' && next != '￿')
            {
                sb.Append(c); // keep the backslash; the next char appends on its own iteration.
                continue;
            }
            sb.Append(decoded);
            i++; // the pair is consumed.
        }
        return sb.ToString();
    }
}
