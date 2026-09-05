namespace NSharpLang.Compiler

import System


// CONTRACTS FOR WHAT AN IDENTIFIER IS MADE OF (task 019 slice 9).
//
// These assertions came out of eight places at once: the whole-string rule out of
// `AnalyzerDeclarationPolicy` (whose seven assertions moved here) and out of the language server's
// `SignatureHelpHandler`, and the character rule out of `Lexer`, `DiagnosticSpanResolver`,
// `LinterBlockOwnerSpan`, the columnar interpolation splitter, the columnar parser kernels and the
// language server's `CompletionHandler`.
//
// THE FILE'S REASON FOR EXISTING IS THE THING NO COPY COULD BE ASKED ABOUT. Eight agreeing copies
// have no observable agreement: nothing failed when one drifted, because nothing compared them. The
// consolidated rule can be asked about its own consistency, and the last section does exactly that
// — every character class is checked against BOTH predicates, and `IsValid` is checked to agree
// with `IsStart`/`IsPart` character by character over a spread of scripts and categories rather
// than over the ASCII letters everyone remembers to test.
func IdtChars(text: string): char[] {
    return text.ToCharArray()
}

// `IsValid` re-derived from the character rules, independently of how `IsValid` is written. Any
// future edit that makes the string rule stop being the character rule applied position by
// position fails the agreement contract below.
func IdtValidByCharacters(name: string): bool {
    if name == null {
        return false
    }

    if name.Length == 0 {
        return false
    }

    if !IdentifierText.IsStart(name[0]) {
        return false
    }

    index := 1
    while index < name.Length {
        if !IdentifierText.IsPart(name[index]) {
            return false
        }

        index = index + 1
    }

    return true
}

// ── the character rule ───────────────────────────────────────────────────────────────────────

test "letters, digits and the underscore are identifier characters" {
    letters := IdtChars("abcxyzABCXYZ")
    index := 0
    while index < letters.Length {
        assert IdentifierText.IsPart(letters[index])
        assert IdentifierText.IsStart(letters[index])
        index = index + 1
    }

    digits := IdtChars("0123456789")
    digitIndex := 0
    while digitIndex < digits.Length {
        assert IdentifierText.IsPart(digits[digitIndex])
        digitIndex = digitIndex + 1
    }

    assert IdentifierText.IsPart('_')
    assert IdentifierText.IsStart('_')
}

test "a digit is a PART but never a START, and that is the only difference between the two" {
    digits := IdtChars("0123456789")
    index := 0
    while index < digits.Length {
        assert IdentifierText.IsPart(digits[index])
        assert !IdentifierText.IsStart(digits[index])
        index = index + 1
    }
}

test "everything else is neither — operators, punctuation, quotes, whitespace and the controls" {
    rejected := IdtChars("+-*/%&|^!=<>:,.;?()[]{}@#$~`'\"\\ \t\n\r")
    index := 0
    while index < rejected.Length {
        assert !IdentifierText.IsPart(rejected[index])
        assert !IdentifierText.IsStart(rejected[index])
        index = index + 1
    }
}

test "the rule is Unicode's, so non-ASCII letters and digits count" {
    // Latin with diacritics, Greek, Cyrillic, Han, Hebrew — all letters to the CLR, and all
    // identifier characters here. This is not an accident of the implementation; it is what
    // `char.IsLetter` means and what every one of the eight copies inherited.
    letters := IdtChars("éÉïÑßΩλЖжカ漢א")
    index := 0
    while index < letters.Length {
        assert IdentifierText.IsPart(letters[index])
        assert IdentifierText.IsStart(letters[index])
        index = index + 1
    }

    // A non-ASCII DIGIT is a part and not a start, exactly like an ASCII one.
    assert IdentifierText.IsPart('٣')
    assert !IdentifierText.IsStart('٣')
}

test "the CLR's OTHER connectors are refused — N# names one connector and it is the underscore" {
    // U+2040 CHARACTER TIE and U+203F UNDERTIE are connector punctuation, and U+200C/U+200D are the
    // zero-width non-joiner and joiner. A CLR identifier may contain all four; an N# one may not.
    // This narrowing is inherited from all eight copies and is deliberate.
    connectors := IdtChars("⁀‿‌‍")
    index := 0
    while index < connectors.Length {
        assert !IdentifierText.IsPart(connectors[index])
        assert !IdentifierText.IsStart(connectors[index])
        index = index + 1
    }
}

// ── the whole-string rule (the seven that moved from AnalyzerDeclarationPolicy, and more) ────

test "the identifier rule itself answers each shape" {
    assert IdentifierText.IsValid("Name")
    assert IdentifierText.IsValid("_name")
    assert IdentifierText.IsValid("n1")
    assert !IdentifierText.IsValid("1n")
    assert !IdentifierText.IsValid("")
    assert !IdentifierText.IsValid("has-dash")
    assert !IdentifierText.IsValid("has space")
}

test "null and empty are both refused rather than throwing, because callers pass segments" {
    // A leading, trailing or doubled dot in a dotted name produces an EMPTY segment, and the
    // package-name rule splits on dots and asks about every segment. Answering false is what makes
    // that caller safe to write as a loop.
    assert !IdentifierText.IsValid(null)
    assert !IdentifierText.IsValid("")
}

test "a single character is enough, and a single digit is not" {
    assert IdentifierText.IsValid("x")
    assert IdentifierText.IsValid("_")
    assert IdentifierText.IsValid("Ω")
    assert !IdentifierText.IsValid("1")
    assert !IdentifierText.IsValid("-")
}

test "the rule is about EVERY character, not just the first" {
    assert IdentifierText.IsValid("a1_b2")
    assert !IdentifierText.IsValid("a b")
    assert !IdentifierText.IsValid("ab ")
    assert !IdentifierText.IsValid(" ab")
    assert !IdentifierText.IsValid("a.b")
    assert !IdentifierText.IsValid("a-b")
    assert !IdentifierText.IsValid("a?")
}

test "a dotted name is not an identifier — it is a sequence of them" {
    assert !IdentifierText.IsValid("System.Text")
    assert IdentifierText.IsValid("System")
    assert IdentifierText.IsValid("Text")
}

// ── the two rules are ONE rule, which is the point of the consolidation ──────────────────────

test "IsValid is IsStart followed by IsPart, character for character" {
    subjects := [
        "Name",
        "_name",
        "n1",
        "1n",
        "",
        "has-dash",
        "has space",
        "x",
        "_",
        "Ω",
        "1",
        "-",
        "a1_b2",
        "a b",
        "ab ",
        " ab",
        "a.b",
        "a-b",
        "a?",
        "System.Text",
        "naïve",
        "Ωmega",
        "café2",
        "_9",
        "9_",
        "__",
        "a⁀b",
        "‌x",
        "ЖивойКод",
        "漢字",
        "٣x",
        "x٣"
    ]
    index := 0
    while index < subjects.Length {
        assert IdentifierText.IsValid(subjects[index]) == IdtValidByCharacters(subjects[index])
        index = index + 1
    }

    // Non-vacuity: the subject list must contain both answers, or the equality above proves nothing.
    accepted := 0
    refused := 0
    countIndex := 0
    while countIndex < subjects.Length {
        if IdentifierText.IsValid(subjects[countIndex]) {
            accepted = accepted + 1
        } else {
            refused = refused + 1
        }

        countIndex = countIndex + 1
    }

    assert accepted > 0
    assert refused > 0
    assert accepted + refused == subjects.Length
}

test "every START character is also a PART character, and the converse fails only for digits" {
    // Stated over a spread wide enough to catch a one-sided edit: if `IsStart` ever accepted
    // something `IsPart` refused, a name valid at position 0 would be invalid at position 1.
    subjects := IdtChars("aZ_0 9.-Ωж漢٣⁀+")
    index := 0
    while index < subjects.Length {
        if IdentifierText.IsStart(subjects[index]) {
            assert IdentifierText.IsPart(subjects[index])
        }

        index = index + 1
    }

    partOnly := 0
    countIndex := 0
    while countIndex < subjects.Length {
        if IdentifierText.IsPart(subjects[countIndex]) && !IdentifierText.IsStart(subjects[countIndex]) {
            partOnly = partOnly + 1
        }

        countIndex = countIndex + 1
    }

    // `0`, `9` and `٣` — the digits in the subject list, and nothing else.
    assert partOnly == 3
}
