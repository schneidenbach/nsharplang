namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Text
import NSharpLang.Compiler.Ast


// THE FORMATTER'S LEAF TEXT: THE THREE FAMILIES THAT PRODUCE SOURCE AND TOUCH NO STATE.
//
// `Formatter` walks an AST and appends to a builder; almost every arm of that walk pushes the
// indent depth or moves the comment cursor, which is why the walk needed a state carrier
// (`FormatterWalkState`, slice 17) before any of it could move. THESE SIX MEMBERS ARE THE
// EXCEPTION. Each is a total function from a node to a string:
//
//   * `FormatTypeReference` — the source spelling of a type, nine arms, self-recursive;
//   * `FormatModifiers` + `ShouldPreserveExplicitCasingVisibility` — which modifier keywords survive
//     the round trip, given that N# encodes visibility in the identifier's CASE;
//   * `FormatAllowArguments` + `FormatAllowEffect` + `FormatQuotedString` — the argument list inside
//     an `allow(...)` header.
//
// Measured on the post-carrier tree, the three families are ONE closed cut: 112 lines that ESCAPE TO
// NOTHING and are entered from eighteen walk arms. They are the smallest closed cuts in the file,
// which is why they are first.
//
// THIS IS NOT `CodeIntelligenceDisplayText`, AND THE DIFFERENCE IS DELIBERATE. That owner (slice 13)
// prints a type reference for a HUMAN reading hover text, through `TypeReferenceFacts`. This one
// prints a type reference for the PARSER to read back, and the two answers really do differ on two
// of the nine arms — see `FormatTypeReference`. Consolidating them would be a behaviour change
// wearing a refactor's clothes, so they stay two owners answering two questions.
class FormatterSyntaxText {

    // ---- the type reference ----------------------------------------------------------------------

    // The source spelling of a type reference: what the formatter writes so the parser can read it
    // back. Nine arms, and the recursion is the shape of the type.
    //
    // TWO ARMS DIVERGE FROM `TypeReferenceFacts.GetDisplayName`, WHICH IS THE PROSE ANSWER TO THE
    // SAME-LOOKING QUESTION, AND BOTH DIVERGENCES ARE THE REASON THIS IS A SEPARATE OWNER:
    //
    //   * A FUNCTION TYPE PRINTS AS `Func<P1, P2, Ret>` HERE and as `(P1, P2) -> Ret` there. The
    //     return type is appended to the parameter list as the LAST type argument, which is why the
    //     loop below runs past the end of `ParameterTypes`.
    //   * AN UNRECOGNISED TYPE THROWS HERE and yields its runtime type's name there. A formatter
    //     that silently emitted a C# class name into a `.nl` file would produce source that does not
    //     parse, so the loud failure is the correct one and is preserved exactly.
    //
    // The final `GetType()` runs through `as object` because a `GetType()` on a typed receiver
    // declines against the pinned toolset; on a null argument that read throws exactly where the C#
    // `type.GetType()` did.
    static func FormatTypeReference(typeReference: TypeReference): string {
        simple := typeReference as SimpleTypeReference
        if simple != null {
            return simple.Name
        }

        generic := typeReference as GenericTypeReference
        if generic != null {
            builder := new StringBuilder()
            builder.Append(generic.Name)
            builder.Append("<")
            AppendTypeList(builder, generic.TypeArguments, ", ")
            builder.Append(">")
            return builder.ToString()
        }

        array := typeReference as ArrayTypeReference
        if array != null {
            return FormatTypeReference(array.ElementType) + "[]"
        }

        nullable := typeReference as NullableTypeReference
        if nullable != null {
            return FormatTypeReference(nullable.InnerType) + "?"
        }

        unionReference := typeReference as UnionTypeReference
        if unionReference != null {
            builder := new StringBuilder()
            AppendTypeList(builder, unionReference.Arms, " | ")
            return builder.ToString()
        }

        tuple := typeReference as TupleTypeReference
        if tuple != null {
            builder := new StringBuilder()
            builder.Append("(")
            index := 0
            while index < tuple.Elements.Count {
                if index > 0 {
                    builder.Append(", ")
                }

                element := tuple.Elements[index]
                if element.Name != null {
                    builder.Append(element.Name)
                    builder.Append(": ")
                }

                builder.Append(FormatTypeReference(element.Type))
                index = index + 1
            }

            builder.Append(")")
            return builder.ToString()
        }

        // `Func<…>` over the parameters WITH THE RETURN TYPE APPENDED — the C# spelled this
        // `ParameterTypes.Concat(new[] { ReturnType })`, so a nullary function prints as
        // `Func<Ret>` and never as `Func<>`.
        functionReference := typeReference as FunctionTypeReference
        if functionReference != null {
            builder := new StringBuilder()
            builder.Append("Func<")
            index := 0
            while index < functionReference.ParameterTypes.Count {
                if index > 0 {
                    builder.Append(", ")
                }

                builder.Append(FormatTypeReference(functionReference.ParameterTypes[index]))
                index = index + 1
            }

            if functionReference.ParameterTypes.Count > 0 {
                builder.Append(", ")
            }

            builder.Append(FormatTypeReference(functionReference.ReturnType))
            builder.Append(">")
            return builder.ToString()
        }

        byRef := typeReference as ByRefTypeReference
        if byRef != null {
            return "&" + FormatTypeReference(byRef.InnerType)
        }

        typeObject := typeReference as object
        throw new InvalidOperationException("Formatter does not handle type reference: " + typeObject.GetType().Name)
    }

    // The separator-joined spelling of a type list. The C# wrote `string.Join(sep, xs.Select(f))`,
    // a METHOD GROUP — an edge no paren-matching call-graph tool can see, and the same shape that
    // made the `allow` family look unreachable (finding 93.3). Written out, it is a plain loop.
    static func AppendTypeList(builder: StringBuilder, types: List<TypeReference>, separator: string) {
        index := 0
        while index < types.Count {
            if index > 0 {
                builder.Append(separator)
            }

            builder.Append(FormatTypeReference(types[index]))
            index = index + 1
        }
    }

    // ---- the modifiers ---------------------------------------------------------------------------

    // The modifier keywords that survive a format, in their canonical order.
    //
    // `public` AND `private` ARE THE ONLY TWO THAT CAN BE DROPPED, because N# encodes visibility in
    // the identifier's case: `Draw` is exported and `draw` is not, so a `public Draw` says nothing
    // the name did not already say and the keyword is noise. It is dropped only when it is
    // genuinely redundant — see `ShouldPreserveExplicitCasingVisibility`.
    //
    // EVERY ARGUMENT IS EXPLICIT AT EVERY CALL SITE. The C# defaulted `identifierName` to null and
    // `preserveCasingVisibility` to true; omitting a defaulted parameter declines at an N# call site
    // (gotcha 85.5), so the defaults are written out at the twelve callers instead of hidden here.
    static func FormatModifiers(modifiers: Modifiers, identifierName: string?, preserveCasingVisibility: bool): string {
        parts := new List<string>()
        bits := Convert.ToInt32(modifiers)

        if preserveCasingVisibility && ShouldPreserveExplicitCasingVisibility(modifiers, identifierName) {
            if HasModifier(bits, 1) {
                parts.Add("public")
            }

            if HasModifier(bits, 2) {
                parts.Add("private")
            }
        }

        if HasModifier(bits, 4) {
            parts.Add("internal")
        }

        if HasModifier(bits, 8) {
            parts.Add("protected")
        }

        if HasModifier(bits, 16) {
            parts.Add("static")
        }

        if HasModifier(bits, 32) {
            parts.Add("virtual")
        }

        if HasModifier(bits, 64) {
            parts.Add("abstract")
        }

        if HasModifier(bits, 128) {
            parts.Add("sealed")
        }

        if HasModifier(bits, 256) {
            parts.Add("partial")
        }

        if HasModifier(bits, 512) {
            parts.Add("readonly")
        }

        if HasModifier(bits, 1024) {
            parts.Add("const")
        }

        if HasModifier(bits, 65536) {
            parts.Add("override")
        }

        if HasModifier(bits, 2048) {
            parts.Add("async")
        }

        if HasModifier(bits, 32768) {
            parts.Add("file")
        }

        return string.Join(" ", parts)
    }

    // "Would dropping `public`/`private` change what this declaration exports?"
    //
    // The question is asked by COMPARING THE TWO ANSWERS `VisibilityConventions` gives — once with
    // the modifiers as written, once with the visibility keywords removed. If both agree, the
    // keyword was redundant with the identifier's case and is dropped; if they disagree, the keyword
    // is an interop escape hatch (`public legacyCamel`, `private SecretPascal`) and dropping it would
    // change the export rules, so it stays.
    //
    // A DECLARATION WITH NO NAME KEEPS ITS KEYWORD. Constructors and indexers pass no identifier, and
    // with nothing to compare against the honest answer is to preserve what was written.
    static func ShouldPreserveExplicitCasingVisibility(modifiers: Modifiers, identifierName: string?): bool {
        bits := Convert.ToInt32(modifiers)
        hasPublic := HasModifier(bits, 1)
        hasPrivate := HasModifier(bits, 2)
        if !hasPublic && !hasPrivate {
            return false
        }

        if string.IsNullOrEmpty(identifierName) {
            return true
        }

        withoutPublicPrivate := bits & ~1 & ~2
        asWritten := VisibilityConventions.IsExportedIdentifier(identifierName, bits)
        withoutKeywords := VisibilityConventions.IsExportedIdentifier(identifierName, withoutPublicPrivate)
        return asWritten != withoutKeywords
    }

    // `Modifiers.HasFlag` reduced to the bit test it is. Every flag in the enum is a single bit, so
    // the `(value & flag) == flag` form and a plain mask agree; the form is kept because that is what
    // `HasFlag` means, and because `VisibilityConventions` already answers the same way.
    static func HasModifier(bits: int, flag: int): bool {
        return (bits & flag) == flag
    }

    // ---- the allow header ------------------------------------------------------------------------

    // The argument list inside `allow(...)`: the effects, then the optional `reason:` and `owner:`.
    //
    // BLANK IS ABSENT. A reason of `""` or `"   "` is not written back out, so a hand-written
    // `allow(alloc, reason: "  ")` formats to `allow(alloc)` — which is the C# exactly, and is why
    // the test is `IsNullOrWhiteSpace` and not a null check.
    static func FormatAllowArguments(allowStatement: AllowStatement): string {
        args := new List<string>()
        index := 0
        while index < allowStatement.Effects.Count {
            args.Add(FormatAllowEffect(allowStatement.Effects[index]))
            index = index + 1
        }

        reason := allowStatement.Reason
        if reason != null && !string.IsNullOrWhiteSpace(reason) {
            args.Add("reason: " + FormatQuotedString(reason))
        }

        owner := allowStatement.Owner
        if owner != null && !string.IsNullOrWhiteSpace(owner) {
            args.Add("owner: " + FormatQuotedString(owner))
        }

        return string.Join(", ", args)
    }

    // One effect, canonically spaced: `alloc:heap` becomes `alloc: heap`.
    //
    // THE TWO GUARDS ARE BOTH POSITIONAL AND BOTH MATTER. A colon at index 0 has no effect name
    // before it and a colon at the last index has no argument after it; in either case the effect is
    // handed back untouched rather than rewritten into something that would not parse. `IndexOf`
    // takes the STRING ":" because the char overload declines against the pinned toolset (finding
    // 93.4); for a one-character ordinal search the two agree.
    static func FormatAllowEffect(effect: string): string {
        colonIndex := effect.IndexOf(":", StringComparison.Ordinal)
        if colonIndex <= 0 || colonIndex >= effect.Length - 1 {
            return effect
        }

        head := effect.Substring(0, colonIndex)
        tail := effect.Substring(colonIndex + 1)
        return head + ": " + tail.Trim()
    }

    // A string as N# source: quoted, with the four escapes the lexer understands.
    //
    // THE QUOTE ARM CARRIES A GUARD THAT LOOKS LIKE A BUG AND IS NOT QUITE ONE. It escapes a `"`
    // only when the preceding character is not a backslash, so a value that ALREADY contains `\"`
    // is not doubled into `\\"`. The C# spelled this as a `case … when` whose failure fell through
    // to `default`, which appends the quote RAW; reproduced here as the `else` chain it compiles to.
    // A lone backslash is not escaped either — that is the C# exactly, and it is why this member
    // formats an `allow` reason rather than arbitrary text.
    static func FormatQuotedString(value: string): string {
        builder := new StringBuilder(value.Length + 2)
        builder.Append('"')
        index := 0
        while index < value.Length {
            ch := value[index]
            if ch == '"' && (index == 0 || value[index - 1] != '\\') {
                builder.Append("\\\"")
            } else if ch == '\n' {
                builder.Append("\\n")
            } else if ch == '\r' {
                builder.Append("\\r")
            } else if ch == '\t' {
                builder.Append("\\t")
            } else {
                builder.Append(ch)
            }

            index = index + 1
        }

        builder.Append('"')
        return builder.ToString()
    }
}
