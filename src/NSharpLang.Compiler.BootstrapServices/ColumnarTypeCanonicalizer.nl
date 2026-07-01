namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import System.Text

public class ColumnarTupleElementNameStripResult {
    public Canonical: string
    public Names: string[]?

    constructor(canonical: string, names: string[]? = null) {
        Canonical = canonical
        Names = names
    }
}

public class ColumnarTypeCanonicalizer {
    public static func UnqualifiedTypeName(name: string): string {
        lastDot := -1
        i := 0
        while i < name.Length {
            if name[i] == '.' {
                lastDot = i
            }

            i = i + 1
        }

        if lastDot >= 0 && lastDot + 1 < name.Length {
            return name.Substring(lastDot + 1)
        }

        return name
    }

    public static func RemoveWhitespace(s: string): string {
        sb := new StringBuilder(s.Length)
        i := 0
        while i < s.Length {
            c := s[i]
            if !char.IsWhiteSpace(c) {
                sb.Append(c)
            }

            i = i + 1
        }

        return sb.ToString()
    }

    public static func StripTupleElementNames(canonical: string): ColumnarTupleElementNameStripResult {
        if canonical.Length < 2 || canonical[0] != '(' || canonical[canonical.Length - 1] != ')' {
            return new ColumnarTupleElementNameStripResult(canonical)
        }

        elements := SplitTopLevelCommas(canonical.Substring(1, canonical.Length - 2))
        stripped := new string[](elements.Count)
        collected: string[]? = null

        i := 0
        while i < elements.Count {
            element := elements[i]
            colon := element.IndexOf(':')
            if colon > 0 && IsBareIdentifier(element.Substring(0, colon)) {
                if collected == null {
                    collected = new string[](elements.Count)
                }

                collected[i] = element.Substring(0, colon)
                stripped[i] = element.Substring(colon + 1)
            } else {
                stripped[i] = element
            }

            i = i + 1
        }

        if collected == null {
            return new ColumnarTupleElementNameStripResult(canonical)
        }

        return new ColumnarTupleElementNameStripResult("(" + string.Join(",", stripped) + ")", collected)
    }

    public static func SplitTopLevelCommas(s: string): List<string> {
        parts := new List<string>()
        depth := 0
        start := 0
        i := 0
        while i < s.Length {
            c := s[i]
            if c == '(' || c == '<' || c == '[' {
                depth = depth + 1
            } else if c == ')' || c == '>' || c == ']' {
                depth = depth - 1
            } else if c == ',' && depth == 0 {
                parts.Add(s.Substring(start, i - start))
                start = i + 1
            }

            i = i + 1
        }

        parts.Add(s.Substring(start))
        return parts
    }

    static func IsBareIdentifier(text: string): bool {
        if text.Length == 0 {
            return false
        }

        i := 0
        while i < text.Length {
            c := text[i]
            if !char.IsLetterOrDigit(c) && c != '_' {
                return false
            }

            i = i + 1
        }

        return !char.IsDigit(text[0])
    }
}
