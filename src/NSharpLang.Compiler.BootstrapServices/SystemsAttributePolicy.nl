namespace NSharpLang.Compiler.Performance

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// WHAT A DECLARATION'S ATTRIBUTES MEAN.
//
// `[hot]`, `[boundary]`, `[alloc(none)]`, `[trusted]`, `[memory(safe)]` and `[allow(...)]` are the
// systems profile's whole declaration vocabulary, and this is the one place that reads them. Every
// other systems owner is handed the ANSWER — `isHot`, `allocNone`, an allow set — and never the
// attribute list, so a change to how an attribute is spelled is a change to this file alone.
//
// AN ATTRIBUTE NAME IS MATCHED WITHOUT ITS `Attribute` SUFFIX AND WITHOUT CASE, BUT THE TWO HALVES
// USE DIFFERENT COMPARISONS. The suffix strip is ORDINAL and the name comparison that follows is
// not, so `[hot]`, `[Hot]` and `[HotAttribute]` are one attribute while `[hotattribute]` is a
// DIFFERENT one. That is the CLR's own suffix convention plus C#'s case-insensitive attribute
// lookup, and the asymmetry is the original's.
//
// THIS IS NOT `NominalTypeInfoFactory.AttributeNameEquals`, AND THE TWO MUST NOT BE FOLDED. That one is a
// length check plus an ORDINAL comparison with no suffix stripping — it is the `[MustUse]` reader,
// which is deliberately exact — so it answers FALSE for `("HotAttribute", "hot")` where this one
// answers TRUE. They share a name and disagree on purpose; a contract asserts the disagreement.
//
// THE ALLOW SET IS BUILT ONCE PER FUNCTION AND READ BY TWO DIFFERENT TESTS. `WalkContext.IsAllowed`
// widens it — `alloc` is allowed by `allow(alloc: pooled)` because the set carries `alloc:pooled` and
// the test admits an `effect:` prefix — while the callee-policy rule tests it EXACTLY, because a
// waiver on the caller's own statements is not a waiver on everything those statements call. Both
// read the SAME set, so the set's identity is load-bearing in two families at once, and it has three
// parts: the `StringComparer.OrdinalIgnoreCase` comparer (which is what makes `[allow(ALLOC)]`
// silence the exact test), the two-form insertion (`name` AND `name:value`, which is the only thing
// that makes the prefix arm reachable), and the ordinal `reason`/`owner` exclusion below.
//
// `reason` AND `owner` ARE EXCLUDED BY THEIR EXACT LOWER-CASE SPELLING, and that asymmetry is real:
// the attribute NAME is matched case-insensitively but these two argument names are matched
// ordinally, so `[allow(Reason: "x")]` puts `Reason` into the effect set as if it were an effect.
// Preserved rather than harmonised, because harmonising it would silently change which programs are
// waived.
//
// A FUNCTION-LEVEL WAIVER MUST BE AUDITABLE. `allow(...)` written on a declaration covers everything
// the function does, forever, so it must say WHY; and if the function is part of the program's public
// surface it must also say WHO owns the exception. Those two sentences are the only findings this
// family reports, and both are NSYS180 — `effectPolicy` has its own code because sharing NSYS150
// with `effectDrift` made the per-error docs URL ambiguous and left machine consumers unable to tell
// the two effects apart (M5).
//
// "PUBLIC" HERE IS THE `public` MODIFIER OR THE EXPORTED-IDENTIFIER CONVENTION, AND THAT IS NOT
// `VisibilityConventions.IsExportedIdentifier(name, modifiers)`. The two-argument form answers FALSE
// for an upper-case name carrying `private`; this rule answers TRUE, because a waiver on `Foo` is
// worth an owner whichever way the file spells its visibility. A contract pins the disagreement.
class SystemsAttributeSet {
    attributesValue: List<AttributeNode>

    constructor(attributes: List<AttributeNode>) {
        attributesValue = attributes
    }

    func Has(name: string): bool {
        return Get(name) != null
    }

    // The FIRST attribute with this name; a declaration that writes `[allow]` twice is read by `Get`
    // as its first one and by `GetAll` as both.
    func Get(name: string): AttributeNode? {
        index := 0
        while index < attributesValue.Count {
            candidate := attributesValue[index]
            if AttributeNameEquals(candidate.Name, name) {
                return candidate
            }

            index = index + 1
        }

        return null
    }

    // In declaration order, which is the order the waiver findings are reported in.
    func GetAll(name: string): List<AttributeNode> {
        matched := new List<AttributeNode>()
        index := 0
        while index < attributesValue.Count {
            candidate := attributesValue[index]
            if AttributeNameEquals(candidate.Name, name) {
                matched.Add(candidate)
            }

            index = index + 1
        }

        return matched
    }

    // WHETHER AN ATTRIBUTE CARRIES A BARE WORD ARGUMENT — `[alloc(none)]`, `[memory(safe)]`. The
    // argument must be an IDENTIFIER, not a string: `[alloc("none")]` does not claim anything, and
    // reading it as if it did would silently turn a typo into a promise.
    func AttributeHasArgument(attributeName: string, argumentName: string): bool {
        attribute := Get(attributeName)
        if attribute == null {
            return false
        }

        index := 0
        while index < attribute.Arguments.Count {
            identifier := attribute.Arguments[index].Value as IdentifierExpression
            if identifier != null && string.Equals(identifier.Name, argumentName, StringComparison.OrdinalIgnoreCase) {
                return true
            }

            index = index + 1
        }

        return false
    }

    // THE FUNCTION-LEVEL ALLOW SET. See the header for the three parts of its identity and for why
    // two families depend on all three.
    //
    // AN ARGUMENT CONTRIBUTES EITHER ITS NAME OR ITS VALUE, NEVER BOTH AS SEPARATE EFFECTS. A NAMED
    // argument adds its name, and additionally `name:value` when the value is a bare word; an
    // UNNAMED argument adds its bare-word value and nothing else. So `[allow(alloc)]` and
    // `[allow(alloc: pooled)]` both allow `alloc`, and only the second also records the reason the
    // widening test can read.
    func AllowEffects(): HashSet<string> {
        result := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        allows := GetAll("allow")
        allowIndex := 0
        while allowIndex < allows.Count {
            AddAllowEffects(allows[allowIndex], result)
            allowIndex = allowIndex + 1
        }

        return result
    }

    static func AddAllowEffects(attribute: AttributeNode, result: HashSet<string>) {
        index := 0
        while index < attribute.Arguments.Count {
            argument := attribute.Arguments[index]
            index = index + 1
            if argument.Name == "reason" || argument.Name == "owner" {
                continue
            }

            identifier := argument.Value as IdentifierExpression
            if !string.IsNullOrWhiteSpace(argument.Name) {
                argumentName := argument.Name ?? ""
                result.Add(argumentName)
                if identifier != null {
                    result.Add(argumentName + ":" + identifier.Name)
                }
            } else if identifier != null {
                result.Add(identifier.Name)
            }
        }
    }

    // A STRING-VALUED ATTRIBUTE ARGUMENT, matched by name without case: the `reason`, `owner`,
    // `review` and `expires` a `[trusted]` or `[allow]` carries. Only a string literal answers —
    // an identifier or a number is not a reason — and the literal arrives with its quotes still on,
    // because the parser keeps the written token.
    //
    // THE FIRST ARGUMENT WITH THE NAME WINS, AND IT WINS EVEN WHEN ITS VALUE IS NOT A STRING, which
    // is why this is written as a search that STOPS rather than one that keeps looking:
    // `[allow(reason: bare, reason: "real")]` has no reason.
    static func AttributeString(attribute: AttributeNode, name: string): string? {
        index := 0
        while index < attribute.Arguments.Count {
            argument := attribute.Arguments[index]
            if string.Equals(argument.Name, name, StringComparison.OrdinalIgnoreCase) {
                literal := argument.Value as StringLiteralExpression
                if literal == null {
                    return null
                }

                return Unquote(literal.Value)
            }

            index = index + 1
        }

        return null
    }

    // The parser keeps a string literal's quotes; every consumer of a reason or an owner wants the
    // text. A value that is not quoted on BOTH ends is returned untouched rather than half-stripped.
    static func Unquote(value: string): string {
        if value.Length < 2 {
            return value
        }

        if value[0] != '"' || value[value.Length - 1] != '"' {
            return value
        }

        return value.Substring(1, value.Length - 2)
    }

    // See the header: this is the suffix-stripping, case-insensitive match, and it is NOT
    // `TypeInfoFactories.AttributeNameEquals`.
    static func AttributeNameEquals(actual: string, expected: string): bool {
        name := actual
        if actual.EndsWith("Attribute", StringComparison.Ordinal) {
            name = actual.Substring(0, actual.Length - 9)
        }

        return string.Equals(name, expected, StringComparison.OrdinalIgnoreCase)
    }
}

// The reporting half of the same subject: what a declaration's waiver must SAY. Held apart from the
// set because the set answers questions and this one emits findings, and only this half needs the
// sink.
class SystemsAttributePolicy {
    sinkValue: SystemsFindingSink

    constructor(sink: SystemsFindingSink) {
        sinkValue = sink
    }

    // ONE FINDING PER `[allow]` PER MISSING FIELD, in declaration order, both at the FUNCTION's
    // position and underlined by the function's own name — because the thing that needs the
    // justification is the declaration, not the attribute.
    //
    // BOTH ARMS PREFER `Error`. A function-level waiver is a promise the whole program relies on; the
    // sink still downgrades it at a `[boundary]` and in audit mode, which is the only reason it is
    // ever a warning.
    func ValidateFunctionLevelAllows(attributes: SystemsAttributeSet, function: FunctionDeclaration, filePath: string, functionName: string, isHot: bool, isBoundary: bool) {
        allows := attributes.GetAll("allow")
        length := Math.Max(1, function.Name.Length)
        isPublicApi := IsPublicApi(function)
        index := 0
        while index < allows.Count {
            allowAttribute := allows[index]
            reason := SystemsAttributeSet.AttributeString(allowAttribute, "reason")
            owner := SystemsAttributeSet.AttributeString(allowAttribute, "owner")
            if string.IsNullOrWhiteSpace(reason) {
                sinkValue.AddForFunction("NSYS180", "effectPolicy", "function-level [allow] requires a reason", function.Line, function.Column, length, filePath, functionName, isHot, isBoundary, ErrorSeverity.Error, "Prefer a narrow block-level allow(...), or add reason: \"...\" to the function-level policy.")
            }

            if isPublicApi && string.IsNullOrWhiteSpace(owner) {
                sinkValue.AddForFunction("NSYS180", "effectPolicy", "public function-level [allow] requires an owner", function.Line, function.Column, length, filePath, functionName, isHot, isBoundary, ErrorSeverity.Error, "Add owner: \"team-or-person\" so public systems waivers are auditable.")
            }

            index = index + 1
        }
    }

    // The written `public` modifier OR the exported-identifier convention. See the header for why
    // this is deliberately wider than `VisibilityConventions.IsExportedIdentifier(name, modifiers)`.
    static func IsPublicApi(function: FunctionDeclaration): bool {
        if (Convert.ToInt32(function.Modifiers) & 1) == 1 {
            return true
        }

        return VisibilityConventions.IsExportedIdentifier(function.Name)
    }
}
