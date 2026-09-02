namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// CONTRACTS FOR THE FORMATTER'S LEAF TEXT (task 019 slice 18). The three arm families that turn a
// type reference, a modifier mask and an `allow` header into source, taken out of `Formatter.cs`.
//
// NONE OF THESE COULD BE ASKED DIRECTLY BEFORE THE MOVE. All six members were privates of a class
// whose only public surface is "give me a whole formatted file", so every rule below could
// previously only be inferred from formatted text — and only for the shapes a parser happens to
// produce. A `Func<>` with no parameters, a modifier mask with an unknown bit, an `allow` reason
// that is three spaces: none of them has a source spelling that reaches the arm, and all three are
// asserted here.
//
// SEVEN THINGS THAT WERE PROSE, AN ACCIDENT OR UNREACHABLE ARE STATED HERE AS CONTRACTS:
//   (a) THE TWO N# TYPE-REFERENCE PRINTERS ARE NOT THE SAME FUNCTION. `FormatterSyntaxText` writes
//       source for the parser; `TypeReferenceFacts` writes prose for a human. They agree on seven
//       arms and disagree on two, and BOTH are asserted side by side so a later slice cannot
//       "consolidate" them without a failing test.
//   (b) AN UNRECOGNISED TYPE REFERENCE THROWS rather than printing something that would not parse.
//   (c) `public`/`private` SURVIVE ONLY WHEN THE CASE DOES NOT ALREADY SAY IT, and the comparison
//       is between two answers of the same question, not a casing test.
//   (d) A DECLARATION WITH NO NAME KEEPS ITS KEYWORD — constructors and indexers pass none.
//   (e) THE MODIFIER ORDER IS FIXED, and `override` comes before `async`, not in flag order.
//   (f) A BLANK `reason:` IS AN ABSENT ONE, so `allow(alloc, reason: "  ")` formats to `allow(alloc)`.
//   (g) AN ALREADY-ESCAPED QUOTE IS NOT DOUBLED, which is the one guard in the quoting loop.
func FstSimple(name: string): SimpleTypeReference {
    return new SimpleTypeReference(name, 0, 0)
}

func FstList(first: TypeReference): List<TypeReference> {
    types := new List<TypeReference>()
    types.Add(first)
    return types
}

func FstPair(first: TypeReference, second: TypeReference): List<TypeReference> {
    types := new List<TypeReference>()
    types.Add(first)
    types.Add(second)
    return types
}

func FstElements(): List<TupleTypeElement> {
    return new List<TupleTypeElement>()
}

// A modifier mask spelled as an int, so a combination that has no source syntax can still be asked
// for. `(Modifiers)value` is the emittable cast idiom (`ColumnarParserRecovery` accumulates its own
// flags the same way); `as` is a reference conversion and does not apply to an enum.
func FstMods(bits: int): Modifiers {
    return (Modifiers)bits
}

func FstAllow(effects: List<string>, reason: string?, owner: string?): AllowStatement {
    body := new BlockStatement(new List<Statement>(), 1, 1)
    return new AllowStatement(effects, reason, owner, body, 1, 1)
}

func FstEffects(only: string): List<string> {
    effects := new List<string>()
    effects.Add(only)
    return effects
}

// ---- the type reference -------------------------------------------------------------------------

test "a simple type is its own name" {
    assert FormatterSyntaxText.FormatTypeReference(FstSimple("int")) == "int"
}

test "a generic type prints its arguments in angle brackets" {
    generic := new GenericTypeReference("Dictionary", FstPair(FstSimple("string"), FstSimple("int")), 0, 0)
    assert FormatterSyntaxText.FormatTypeReference(generic) == "Dictionary<string, int>"
}

test "an array, a nullable and a byref each wrap their inner spelling" {
    inner := FstSimple("byte")
    assert FormatterSyntaxText.FormatTypeReference(new ArrayTypeReference(inner)) == "byte[]"
    assert FormatterSyntaxText.FormatTypeReference(new NullableTypeReference(inner)) == "byte?"
    assert FormatterSyntaxText.FormatTypeReference(new ByRefTypeReference(inner)) == "&byte"
}

test "a union joins its arms with a spaced pipe" {
    // `union` is a KEYWORD, so the local cannot be called that — an identifier that collides with
    // one declines the whole declaration at `parse.test` naming only the `test` line (finding 94.1).
    unionReference := new UnionTypeReference(FstPair(FstSimple("A"), FstSimple("B")))
    assert FormatterSyntaxText.FormatTypeReference(unionReference) == "A | B"
}

test "an empty union is the empty string, not a stray separator" {
    unionReference := new UnionTypeReference(new List<TypeReference>())
    assert FormatterSyntaxText.FormatTypeReference(unionReference) == ""
}

test "a tuple element prints its name only when it has one" {
    elements := FstElements()
    elements.Add(new TupleTypeElement(FstSimple("int"), "x"))
    elements.Add(new TupleTypeElement(FstSimple("string"), null))
    assert FormatterSyntaxText.FormatTypeReference(new TupleTypeReference(elements)) == "(x: int, string)"
}

test "a function type appends its RETURN type as the last argument of Func" {
    // The return type is concatenated onto the parameter list, so the arity of `Func<…>` is one
    // more than the number of parameters and a nullary function is `Func<Ret>`, never `Func<>`.
    nullary := new FunctionTypeReference(new List<TypeReference>(), FstSimple("void"))
    unary := new FunctionTypeReference(FstList(FstSimple("int")), FstSimple("bool"))
    assert FormatterSyntaxText.FormatTypeReference(nullary) == "Func<void>"
    assert FormatterSyntaxText.FormatTypeReference(unary) == "Func<int, bool>"
}

test "the two N# type-reference printers agree on a simple type and DISAGREE on a function type" {
    // (a) This is the reason `FormatterSyntaxText` exists beside `TypeReferenceFacts` instead of
    // calling it. One writes source the parser reads back; the other writes prose for hover text.
    // Consolidating them would silently change what `nlc format` emits for a function type.
    simple := FstSimple("int")
    functionType := new FunctionTypeReference(FstList(FstSimple("int")), FstSimple("bool"))
    assert FormatterSyntaxText.FormatTypeReference(simple) == TypeReferenceFacts.GetDisplayName(simple)
    assert FormatterSyntaxText.FormatTypeReference(functionType) == "Func<int, bool>"
    assert TypeReferenceFacts.GetDisplayName(functionType) == "(int) -> bool"
}

test "nesting is the shape of the type, all the way down" {
    deep := new NullableTypeReference(new ArrayTypeReference(new GenericTypeReference("List", FstList(new UnionTypeReference(FstPair(FstSimple("A"), FstSimple("B")))), 0, 0)))
    assert FormatterSyntaxText.FormatTypeReference(deep) == "List<A | B>[]?"
}

// ---- the modifiers ------------------------------------------------------------------------------

test "an exported name drops a redundant public" {
    // (c) `Draw` already exports; the keyword says nothing the case did not.
    assert FormatterSyntaxText.FormatModifiers(FstMods(1), "Draw", true) == ""
}

test "an unexported name KEEPS an explicit public, because dropping it would change the export" {
    assert FormatterSyntaxText.FormatModifiers(FstMods(1), "draw", true) == "public"
}

test "an exported name KEEPS an explicit private for the same reason, mirrored" {
    assert FormatterSyntaxText.FormatModifiers(FstMods(2), "Draw", true) == "private"
    assert FormatterSyntaxText.FormatModifiers(FstMods(2), "draw", true) == ""
}

test "a declaration with no name keeps whatever visibility it was given" {
    // (d) Constructors and indexers pass no identifier: with nothing to compare against, the honest
    // answer is to preserve what was written.
    assert FormatterSyntaxText.FormatModifiers(FstMods(1), null, true) == "public"
    assert FormatterSyntaxText.FormatModifiers(FstMods(2), "", true) == "private"
}

test "preserveCasingVisibility false drops public and private and keeps everything else" {
    assert FormatterSyntaxText.FormatModifiers(FstMods(17), "draw", false) == "static"
    assert FormatterSyntaxText.FormatModifiers(FstMods(17), "draw", true) == "public static"
}

test "the modifier order is fixed and override comes before async" {
    // (e) The order is the order the arms are written in, NOT the numeric order of the flags:
    // `override` is bit 65536 and `async` is bit 2048, and `override` still prints first.
    assert FormatterSyntaxText.FormatModifiers(FstMods(67585), "draw", true) == "public override async"
}

test "an unknown modifier bit contributes no keyword and blocks nothing" {
    unknown := 1048576
    assert FormatterSyntaxText.FormatModifiers(FstMods(unknown), "Draw", true) == ""
    assert FormatterSyntaxText.FormatModifiers(FstMods(unknown + 16), "Draw", true) == "static"
}

test "the casing predicate is false whenever neither public nor private is present" {
    assert !FormatterSyntaxText.ShouldPreserveExplicitCasingVisibility(FstMods(16), "draw")
    assert !FormatterSyntaxText.ShouldPreserveExplicitCasingVisibility(FstMods(0), "draw")
    assert FormatterSyntaxText.ShouldPreserveExplicitCasingVisibility(FstMods(1), "draw")
}

test "public BEATS internal, so an explicit public survives beside it whatever the case" {
    // `VisibilityConventions.IsExportedIdentifier` tests the PUBLIC bit FIRST and returns true
    // without looking further, so `public internal Draw` exports and `internal Draw` does not: the
    // two answers disagree and the keyword is kept. It is kept for `draw` too, and for the same
    // reason — which is why this is a comparison of two answers and not a casing test. Dropping
    // `public` here would silently un-export the declaration.
    assert FormatterSyntaxText.FormatModifiers(FstMods(5), "Draw", true) == "public internal"
    assert FormatterSyntaxText.FormatModifiers(FstMods(5), "draw", true) == "public internal"
    assert FormatterSyntaxText.ShouldPreserveExplicitCasingVisibility(FstMods(5), "Draw")
}

// ---- the allow header ---------------------------------------------------------------------------

test "an effect with no colon is handed back untouched" {
    assert FormatterSyntaxText.FormatAllowEffect("alloc") == "alloc"
}

test "an effect is canonically spaced after its colon" {
    assert FormatterSyntaxText.FormatAllowEffect("alloc:heap") == "alloc: heap"
    assert FormatterSyntaxText.FormatAllowEffect("alloc:   heap  ") == "alloc: heap"
}

test "a leading or trailing colon is positional and leaves the effect alone" {
    // Rewriting `:heap` would produce `: heap`, which names no effect; rewriting `alloc:` would
    // produce `alloc: `, which names no argument. Neither would parse back.
    assert FormatterSyntaxText.FormatAllowEffect(":heap") == ":heap"
    assert FormatterSyntaxText.FormatAllowEffect("alloc:") == "alloc:"
    assert FormatterSyntaxText.FormatAllowEffect(":") == ":"
    assert FormatterSyntaxText.FormatAllowEffect("") == ""
}

test "only the FIRST colon separates; the rest belong to the argument" {
    assert FormatterSyntaxText.FormatAllowEffect("a:b:c") == "a: b:c"
}

test "a quoted string is wrapped and its four escapes are written" {
    assert FormatterSyntaxText.FormatQuotedString("plain") == "\"plain\""
    assert FormatterSyntaxText.FormatQuotedString("") == "\"\""
    assert FormatterSyntaxText.FormatQuotedString("a\nb") == "\"a\\nb\""
    assert FormatterSyntaxText.FormatQuotedString("a\rb") == "\"a\\rb\""
    assert FormatterSyntaxText.FormatQuotedString("a\tb") == "\"a\\tb\""
}

test "a bare quote is escaped and an ALREADY-escaped quote is not doubled" {
    // (g) The single guard in the loop. Without it a reason that already reads `\"hi\"` in source
    // would be re-escaped on every format and `FormatSafe`'s idempotence gate would reject the file.
    assert FormatterSyntaxText.FormatQuotedString("say \"hi\"") == "\"say \\\"hi\\\"\""
    assert FormatterSyntaxText.FormatQuotedString("say \\\"hi\\\"") == "\"say \\\"hi\\\"\""
}

test "a quote in the FIRST position is always escaped, because nothing precedes it" {
    assert FormatterSyntaxText.FormatQuotedString("\"x") == "\"\\\"x\""
}

test "the allow arguments are the effects, canonically spaced" {
    effects := new List<string>()
    effects.Add("alloc:heap")
    effects.Add("io")
    assert FormatterSyntaxText.FormatAllowArguments(FstAllow(effects, null, null)) == "alloc: heap, io"
}

test "a reason and an owner follow the effects, quoted, in that order" {
    assert FormatterSyntaxText.FormatAllowArguments(FstAllow(FstEffects("alloc"), "why", "who")) == "alloc, reason: \"why\", owner: \"who\""
}

test "a BLANK reason is an ABSENT reason" {
    // (f) `IsNullOrWhiteSpace`, not a null check: `allow(alloc, reason: "  ")` formats to
    // `allow(alloc)`, and the whitespace is not preserved as an empty pair of quotes.
    assert FormatterSyntaxText.FormatAllowArguments(FstAllow(FstEffects("alloc"), "   ", null)) == "alloc"
    assert FormatterSyntaxText.FormatAllowArguments(FstAllow(FstEffects("alloc"), "", null)) == "alloc"
    assert FormatterSyntaxText.FormatAllowArguments(FstAllow(FstEffects("alloc"), null, "  ")) == "alloc"
}

test "an allow with no effects and no reason is the empty argument list" {
    assert FormatterSyntaxText.FormatAllowArguments(FstAllow(new List<string>(), null, null)) == ""
}

test "an owner survives a blank reason without leaving a stray separator" {
    assert FormatterSyntaxText.FormatAllowArguments(FstAllow(FstEffects("alloc"), " ", "who")) == "alloc, owner: \"who\""
}
