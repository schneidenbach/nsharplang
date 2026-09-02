namespace NSharpLang.Compiler


// `StringLiteralDecoder`: THE ONE PLACE A LEXED STRING OR CHAR LITERAL BECOMES ITS VALUE.
//
// THIS TYPE HAD NO ESTATE COVERAGE AT ALL BEFORE THIS FILE. Its only assertion layer anywhere was
// three `[Fact]`s in `tests/ColumnarLiteralFactsTests.cs`, which sampled three of the eleven escapes
// and never touched `DecodeCharacterBody`, `DecodeBody`, `IsTripleQuoteStringLiteral` or
// `IsInterpolatedRawStringLiteral` at all.
//
// THE CROSSING FOUND A DIVERGENCE THE SAMPLE COULD NOT SEE, AND IT IS THE MOST IMPORTANT FACT IN
// THIS FILE: `TryDecodeBody` AND `DecodeBody` DISAGREE ON EXACTLY TWO INPUTS, BY DESIGN.
// `TryDecodeBody` REFUSES an unrecognised escape (a `\u` form, say) and a trailing lone backslash, answering
// `false`; `DecodeBody` PASSES BOTH THROUGH LITERALLY and always answers a string. The deleted file
// asserted the two refusals and never asked what the other entry point does with the same bytes, so
// nothing recorded that the lexer's tolerant path and the planner's strict path differ — which is
// precisely the pair a future change is most likely to accidentally unify.
//
// THE ESCAPE TABLE IS CROSSED IN FULL, THROUGH THE SCALAR SEAM. All eleven admitted escapes are
// stated by CODE POINT via `DecodeCharacterBody`, which is both exact (a control character compared
// as text reads as nothing on a terminal) and the only assertion anywhere that reaches that seam —
// the no-out entry the columnar expression planners actually call.

// ── The escape table, crossed in full ───────────────────────────────────────────────────────────
test "every admitted escape decodes to its own code point through the scalar seam" {
    assert StringLiteralDecoder.DecodeCharacterBody("\\0") == 0
    assert StringLiteralDecoder.DecodeCharacterBody("\\a") == 7
    assert StringLiteralDecoder.DecodeCharacterBody("\\b") == 8
    assert StringLiteralDecoder.DecodeCharacterBody("\\t") == 9
    assert StringLiteralDecoder.DecodeCharacterBody("\\n") == 10
    assert StringLiteralDecoder.DecodeCharacterBody("\\v") == 11
    assert StringLiteralDecoder.DecodeCharacterBody("\\f") == 12
    assert StringLiteralDecoder.DecodeCharacterBody("\\r") == 13
    assert StringLiteralDecoder.DecodeCharacterBody("\\\"") == 34
    assert StringLiteralDecoder.DecodeCharacterBody("\\'") == 39
    assert StringLiteralDecoder.DecodeCharacterBody("\\\\") == 92
}

test "the scalar seam answers minus one for anything that is not exactly one character" {
    // Not an escape at all, but still one character: admitted.
    assert StringLiteralDecoder.DecodeCharacterBody("x") == 120

    // Two characters, zero characters, and an escape the table does not own.
    assert StringLiteralDecoder.DecodeCharacterBody("ab") == -1
    assert StringLiteralDecoder.DecodeCharacterBody("") == -1
    assert StringLiteralDecoder.DecodeCharacterBody("\\u1234") == -1
    assert StringLiteralDecoder.DecodeCharacterBody("\\") == -1

    // A decoded escape followed by a literal character is two characters, not one.
    assert StringLiteralDecoder.DecodeCharacterBody("\\nx") == -1
}

// ── The strict entry point ──────────────────────────────────────────────────────────────────────

test "the strict decoder decodes the escapes the deleted file sampled" {
    decoded := ""
    assert StringLiteralDecoder.TryDecodeBody("line\\n", out decoded)
    assert decoded == "line\n"
    assert decoded.Length == 5
    assert (int)decoded[4] == 10

    assert StringLiteralDecoder.TryDecodeBody("quote\\'slash\\\\", out decoded)
    assert decoded == "quote'slash\\"
}

test "the strict decoder returns the body unchanged when it holds no backslash" {
    decoded := ""
    assert StringLiteralDecoder.TryDecodeBody("plain text", out decoded)
    assert decoded == "plain text"

    assert StringLiteralDecoder.TryDecodeBody("", out decoded)
    assert decoded == ""
}

test "the strict decoder refuses an unrecognised escape and a trailing lone backslash" {
    decoded := ""
    assert !StringLiteralDecoder.TryDecodeBody("\\u1234", out decoded)
    assert !StringLiteralDecoder.TryDecodeBody("trailing\\", out decoded)

    // Refusal is per-body, not per-character: one bad escape rejects a body whose other escapes are
    // all fine, and the position of the bad escape does not matter.
    assert !StringLiteralDecoder.TryDecodeBody("\\n\\u0041\\t", out decoded)
    assert !StringLiteralDecoder.TryDecodeBody("\\x41", out decoded)
    assert !StringLiteralDecoder.TryDecodeBody("\\N", out decoded)
}

// ── The tolerant entry point, and where the two disagree ────────────────────────────────────────

test "the tolerant decoder passes through exactly what the strict decoder refuses" {
    // THE DIVERGENCE. Every input in the refusal contract above answers a STRING here rather than
    // `false`, and the unrecognised escape survives verbatim — backslash included.
    assert StringLiteralDecoder.DecodeBody("\\u1234") == "\\u1234"
    assert StringLiteralDecoder.DecodeBody("trailing\\") == "trailing\\"
    assert StringLiteralDecoder.DecodeBody("\\x41") == "\\x41"
    assert StringLiteralDecoder.DecodeBody("\\N") == "\\N"

    // A body that mixes a known and an unknown escape decodes the known one and keeps the other.
    // `a` + decoded newline + `b` + the six literal characters of `A` + `c` = ten characters.
    mixed := StringLiteralDecoder.DecodeBody("a\\nb\\u0041c")
    assert mixed.Length == 10
    assert (int)mixed[1] == 10
    assert mixed[2] == 'b'
    assert mixed.Substring(3) == "\\u0041c"
}

test "the two decoders agree on every body the strict one admits" {
    assert SldAgree("plain text")
    assert SldAgree("")
    assert SldAgree("line\\n")
    assert SldAgree("quote\\'slash\\\\")
    assert SldAgree("\\0\\a\\b\\t\\n\\v\\f\\r")
    assert SldAgree("a\\\"b")
}

func SldAgree(body: string): bool {
    strict := ""
    if !StringLiteralDecoder.TryDecodeBody(body, out strict) {
        return false
    }

    return strict == StringLiteralDecoder.DecodeBody(body)
}

// ── The literal-form classifiers and the front door ─────────────────────────────────────────────

test "a raw string literal keeps its backslashes and an ordinary one decodes them" {
    // The deleted file's three `Decode` rows.
    assert StringLiteralDecoder.Decode("\"slash\\n\"", false) == "slash\n"
    assert StringLiteralDecoder.Decode("\"slash\\n\"", false).Length == 6
    assert StringLiteralDecoder.Decode("\"\"\"slash\\n\"\"\"", false) == "slash\\n"
    assert StringLiteralDecoder.Decode("$\"\"\"slash\\n\"\"\"", false) == "slash\\n"
}

test "the front door strips whatever delimiters it finds and tolerates having none" {
    assert StringLiteralDecoder.Decode("\"plain\"", false) == "plain"
    assert StringLiteralDecoder.Decode("\"\"", false) == ""

    // No delimiters at all: the body is decoded where it stands, which is what the lexer's
    // already-trimmed token text needs.
    assert StringLiteralDecoder.Decode("plain", false) == "plain"

    // A leading quote without a trailing one strips only the leading one.
    assert StringLiteralDecoder.Decode("\"open", false) == "open"
}

test "the interpolated text decoder is chosen by the literal that contains it, not by the text" {
    // The same hole text decodes differently depending on whether its literal is raw.
    assert StringLiteralDecoder.DecodeInterpolatedText("$\"x\"", "\\n") == "\n"
    ordinary := StringLiteralDecoder.DecodeInterpolatedText("$\"x\"", "\\n")
    assert ordinary.Length == 1
    assert (int)ordinary[0] == 10

    assert StringLiteralDecoder.DecodeInterpolatedText("$\"\"\"x\"\"\"", "\\n") == "\\n"

    // A NON-interpolated raw literal is not the raw arm — that arm keys on `$"""` specifically —
    // so its text goes through the ordinary decode. Nothing anywhere stated this asymmetry.
    tripleOnly := StringLiteralDecoder.DecodeInterpolatedText("\"\"\"x\"\"\"", "\\n")
    assert tripleOnly.Length == 1
    assert (int)tripleOnly[0] == 10
}

test "the two literal-form classifiers state their own length floors and are disjoint" {
    assert StringLiteralDecoder.IsInterpolatedRawStringLiteral("$\"\"\"x\"\"\"")
    assert StringLiteralDecoder.IsInterpolatedRawStringLiteral("$\"\"\"\"\"\"")
    assert !StringLiteralDecoder.IsInterpolatedRawStringLiteral("$\"\"\"\"\"")

    assert StringLiteralDecoder.IsTripleQuoteStringLiteral("\"\"\"\"\"\"")
    assert !StringLiteralDecoder.IsTripleQuoteStringLiteral("\"\"\"\"\"")

    // Disjointness in both directions: a `$`-prefixed raw literal is not a plain triple-quote one,
    // and a plain triple-quote one is not interpolated.
    assert !StringLiteralDecoder.IsTripleQuoteStringLiteral("$\"\"\"x\"\"\"")
    assert !StringLiteralDecoder.IsInterpolatedRawStringLiteral("\"\"\"x\"\"\"")

    // Neither classifier admits an ordinary literal.
    assert !StringLiteralDecoder.IsInterpolatedRawStringLiteral("\"x\"")
    assert !StringLiteralDecoder.IsTripleQuoteStringLiteral("\"x\"")
    assert !StringLiteralDecoder.IsInterpolatedRawStringLiteral("")
    assert !StringLiteralDecoder.IsTripleQuoteStringLiteral("")
}

// THE THREE STRING FORMS AGAINST THE TWO INPUTS ANYONE EVER HANDS THIS OWNER, STATED AS ONE FAMILY.
//
// The two inputs are not interchangeable and that is the whole reason the family needs stating:
//
//   * A SOURCE SLICE carries its delimiters for all three forms — `"…"`, `"""…"""`, `$"""…"""` — and
//     is what all thirteen production call sites pass. The classifiers work, and always did.
//   * AN AST `Value` carries them for the ORDINARY form ONLY, because `Lexer.ReadString` appends its
//     quotes and `Lexer.ReadTripleQuoteString` appends neither of its `"""`. No prefix test can
//     recover the difference — a raw body is arbitrary text — so a caller holding a `Value` has to
//     say which form it has.
//
// Deriving that per owner is what produced two implementations and one live defect;
// `PlaygroundRunFacts` sniffed the text and got every raw string wrong.
test "the decoder answers the three string forms from a source slice, and takes the raw body on trust" {
    // Source slices: the delimiters are present and each form is classified by them.
    assert StringLiteralDecoder.Decode("\"a\\nb\"", false).Length == 3
    assert StringLiteralDecoder.Decode("\"\"\"a\\nb\"\"\"", false) == "a\\nb"
    assert StringLiteralDecoder.Decode("$\"\"\"a\\nb\"\"\"", false) == "a\\nb"

    // The ordinary form decodes its escapes; the two raw forms do not. That is the one difference
    // between them, and it is why the raw arms exist at all.
    ordinary := StringLiteralDecoder.Decode("\"a\\nb\"", false)
    assert ordinary == "a\nb"
    assert (int)ordinary[1] == 10

    // AN AST VALUE, WHICH IS THE INPUT THE CLASSIFIERS CANNOT HELP WITH. The ordinary form still
    // carries its quotes, so it needs no flag; the raw form does not, so it does.
    assert StringLiteralDecoder.Decode("\"a\\nb\"", false) == "a\nb"
    assert StringLiteralDecoder.Decode("a\\nb", true) == "a\\nb"

    // Without the flag the same body is escape-decoded — the shape of the Playground defect, stated
    // here so the owner carries the evidence rather than only the fix.
    assert StringLiteralDecoder.Decode("a\\nb", false).Length == 3

    // The flag is verbatim all the way: no quote stripping, no escape, no length floor.
    assert StringLiteralDecoder.Decode("", true) == ""
    assert StringLiteralDecoder.Decode("\"looks quoted\"", true) == "\"looks quoted\""
    assert StringLiteralDecoder.Decode("\n  indented\n", true) == "\n  indented\n"
}

// THE `$"""`-ONLY ARM IN `DecodeInterpolatedText` IS AN ASYMMETRY, AND IT IS CONTRACTED RATHER THAN
// CHANGED. A plain `"""…"""` literal reaching it would have its TEXT escape-decoded, because the
// verbatim arm keys on the interpolated prefix specifically. That is unreachable today — both entry
// points (`ColumnarScalarLiteralPlanner.TryAppendString` and the emitter's interpolation path) gate
// on `text[0] == '$'` before any part is split — so changing it would be a behaviour change with no
// caller to justify it. Stated here so the next reader finds the reasoning instead of the surprise.
test "the interpolated-text decoder keys its verbatim arm on the interpolated raw prefix alone" {
    assert StringLiteralDecoder.DecodeInterpolatedText("$\"\"\"x\"\"\"", "\\n") == "\\n"

    plain := StringLiteralDecoder.DecodeInterpolatedText("\"\"\"x\"\"\"", "\\n")
    assert plain.Length == 1
    assert (int)plain[0] == 10

    ordinary := StringLiteralDecoder.DecodeInterpolatedText("$\"x\"", "\\n")
    assert ordinary.Length == 1
}
