namespace NSharpLang.Compiler

import System
import NSharpLang.Compiler.Ast


// THE ONE STEP A LITERAL CANNOT TAKE FOR ITSELF, AND EVERYTHING IT NEEDS.
//
// SIX OF THE SEVEN LITERAL FORMS ASK FOR NOTHING AT ALL. An `int`, a `float`, a `char`, a `string`,
// a `bool` and a `null` literal are pure functions of the node and of the ambient target type, and
// every fact they consult — the numeric-literal facts, the built-in type table, the target-typing
// slot and the declared-alias resolver — is already N#-owned and directly callable. Their walks take
// ZERO steps: the driver's loop body never runs and it returns the answer the entry already had.
//
// THE SEVENTH IS THE INTERPOLATED STRING, and it is the reason this protocol exists at all. Each of
// its HOLES is an expression the analyzer must walk, and the walk cannot walk one: that door is
// `AnalyzeExpression`, which is the very thing this territory is being taken from. So the walk
// SUSPENDS at every hole and resumes WITH THE HOLE'S TYPE, because that type is the OPERAND of the
// row-escape report that runs immediately after it. The number of steps is a pure function of the
// node (one per hole, in source order); the operands are not.
//
// The kinds:
//   1  analyse an EXPRESSION — one interpolated-string hole, under NO expected type. It ANSWERS a
//      type, and that answer is the row-escape report's second argument. There is no kind 2: nothing
//      else in this family is beyond the walk's own reach.
//
// The numbering is this walk's own protocol with its own driver and starts at 1; the other walks'
// numbers mean different operations and none of them is a shared vocabulary.
class LiteralExpressionRequest {
    Kind: int
    Node: Expression?
    Line: int
    Column: int

    constructor(kind: int, node: Expression?, line: int, column: int) {
        Kind = kind
        Node = node
        Line = line
        Column = column
    }
}

// THE WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// `Form` names which literal this is — 0 `int`, 1 `float`, 2 `char`, 3 `string`, 4 interpolated
// string, 5 `bool`, 6 `null` — and it is on the state rather than inferred at each suspension
// because six of the seven forms never suspend and the seventh must be told apart from them by the
// contracts that assert the empty walk.
//
// `ResultType` IS THE ANSWER THE DISPATCH GETS BACK, and it is decided at `Begin` for every one of
// the seven forms. That is not an optimisation: it is what the family IS. An interpolated string is
// a `string` whatever its holes turn out to be, and an `int` literal's type is decided by its own
// text and by the target-typing slot AS READ AT THE INSTANT THE DISPATCH REACHED IT — which is why
// the integer form resolves at entry rather than at exit, exactly as `Analyzer.cs` did when the
// switch arm called `GetIntLiteralType` before anything else could move the slot.
//
// `PartIndex` is the cursor into an interpolated string's parts. It walks TEXT parts as well as
// holes, because "the next hole" is defined by the part list's order and a text part between two
// holes must not reorder them.
//
// `HoleType` is the outstanding step's answer, folded in by `Supply` and consumed by the phase that
// runs the two escape reports. It is never the walk's own answer.
class LiteralExpressionState {
    formValue: int
    interpolatedValue: InterpolatedStringExpression?

    Form: int => formValue
    Interpolated: InterpolatedStringExpression? => interpolatedValue

    Phase: int
    PartIndex: int
    Pending: int
    HoleType: TypeInfo
    ResultType: TypeInfo

    constructor(form: int, interpolated: InterpolatedStringExpression?, resultType: TypeInfo) {
        formValue = form
        interpolatedValue = interpolated
        Phase = 0
        PartIndex = 0
        Pending = 0
        HoleType = BuiltInTypes.Unknown
        ResultType = resultType
    }
}

// WHAT A LITERAL MEANS.
//
// THE FAMILY IS THE EXPRESSION WALK'S FIRST OWNED TERRITORY, AND IT IS THE FIRST WALK IN THIS ARC
// WHOSE DRIVER RETURNS AN ANSWER. Every walk moved before this one was a STATEMENT or a
// DECLARATION, and a statement answers nothing: all eleven of the analyzer's driver loops return
// `void` and carry answers only INWARD, through `Supply`. An expression must hand a type BACK to the
// dispatch that asked, so this owner publishes `Result`, and its driver returns what `Result` says.
// That is the whole of the new shape — no callback, no re-entry the walk performs itself, and no
// answer that crosses the boundary in any direction other than the two the protocol already had.
//
// IT OWNS WHAT EACH OF THE SEVEN LITERALS IS:
//   * that an integer literal with BOTH an unsigned and a long suffix is `ulong`; that one with only
//     `u` is `uint` when it fits and `ulong` when it does not; that one with only `l` is `long` when
//     it fits and `ulong` when it does not; that a literal whose text is not a parseable unsigned
//     magnitude at all is plain `int`; and that a SUFFIXLESS literal is TARGET-TYPED — it takes the
//     ambient expected type when that type is an integer type the magnitude fits in, looking through
//     a declared alias and through one layer of nullability, and is `int` otherwise;
//   * that a float literal's type is decided by its suffix alone (`m` decimal, `f` float, else
//     `double`), which is a numeric-literal FACT and not this walk's to restate;
//   * that a `char` literal is `char`, a `string` literal is `string`, a `bool` literal is `bool` and
//     a `null` literal is the NULL type — not `object`, which is what the attribute-argument walk
//     answers for the same node and is the reason that walk's literal table is a different question;
//   * that an interpolated string is a `string` REGARDLESS of its holes, that every hole is analysed
//     in source order under NO expected type, and that each hole is refused BOTH SoA escapes — the
//     row view and the direct column value — with the action word "formatted in an interpolated
//     string", both reports run unconditionally so that a hole which is both is told both.
//
// IT IS AN OBJECT RATHER THAN A STATIC because three of its facts are ambient: the target-typing
// slot it reads for a suffixless integer, the declared-alias resolver that slot's value is read
// through, and the SoA escape reporter the holes are handed to. All three are constructed exactly
// once by `Analyzer.cs` and are never rebuilt with the metadata load context, so holding them is
// safe.
class AnalyzerLiteralExpressions {
    ambientValue: AnalyzerAmbientContext
    declarationContextValue: AnalyzerDeclarationContext
    soaEscapeValue: AnalyzerSoaEscape

    constructor(ambient: AnalyzerAmbientContext, declarationContext: AnalyzerDeclarationContext, soaEscape: AnalyzerSoaEscape) {
        ambientValue = ambient
        declarationContextValue = declarationContext
        soaEscapeValue = soaEscape
    }

    // THE ENTRY, AND IT DECIDES THE ANSWER. Every form's type is settled here; only the interpolated
    // string has anything left to do afterwards, and what it has left to do cannot change what it
    // answers. A node that is not one of the seven forms answers `unknown` and takes no steps — the
    // dispatch never hands one over, and the walk says so rather than guessing.
    func Begin(expression: Expression): LiteralExpressionState {
        intLiteral := expression as IntLiteralExpression
        if intLiteral != null {
            return new LiteralExpressionState(0, null, IntLiteralType(intLiteral.Value))
        }

        floatLiteral := expression as FloatLiteralExpression
        if floatLiteral != null {
            return new LiteralExpressionState(1, null, NumericLiteralFacts.GetFloatLiteralTypeInfo(floatLiteral.Value))
        }

        charLiteral := expression as CharLiteralExpression
        if charLiteral != null {
            return new LiteralExpressionState(2, null, BuiltInTypes.Char)
        }

        stringLiteral := expression as StringLiteralExpression
        if stringLiteral != null {
            return new LiteralExpressionState(3, null, BuiltInTypes.String)
        }

        interpolated := expression as InterpolatedStringExpression
        if interpolated != null {
            return new LiteralExpressionState(4, interpolated, BuiltInTypes.String)
        }

        boolLiteral := expression as BoolLiteralExpression
        if boolLiteral != null {
            return new LiteralExpressionState(5, null, BuiltInTypes.Bool)
        }

        nullLiteral := expression as NullLiteralExpression
        if nullLiteral != null {
            return new LiteralExpressionState(6, null, BuiltInTypes.Null)
        }

        return new LiteralExpressionState(-1, null, BuiltInTypes.Unknown)
    }

    // THE NEXT STEP THE DRIVER MUST PERFORM, or null when this walk is finished. Six of the seven
    // forms answer null on the first call.
    func NextStep(state: LiteralExpressionState): LiteralExpressionRequest? {
        while state.Phase != 99 {
            request := Advance(state)
            if request != null {
                return request
            }
        }

        return null
    }

    // THE ANSWER TO THE OUTSTANDING STEP: a hole's type, which is the row-escape report's operand. A
    // walk that asked for nothing folds in nothing, and a null answer is `unknown` rather than a
    // missing one — the analyzer's expression walk never answers null, and a walk that saw one would
    // otherwise carry it into a report.
    func Supply(state: LiteralExpressionState, answer: TypeInfo?) {
        pending := state.Pending
        state.Pending = 0

        if pending != 1 {
            return
        }

        if answer != null {
            state.HoleType = answer
        } else {
            state.HoleType = BuiltInTypes.Unknown
        }
    }

    // WHAT THE WALK ANSWERS, which is what the dispatch hands to its caller. It is defined before the
    // first step and is unchanged by every step there is, which is exactly why an interpolated string
    // with a hole that fails to analyse is still a `string`.
    func Result(state: LiteralExpressionState): TypeInfo {
        return state.ResultType
    }

    func Advance(state: LiteralExpressionState): LiteralExpressionRequest? {
        phase := state.Phase
        if phase == 0 {
            return AdvanceEntry(state)
        }

        if phase == 1 {
            return AdvanceNextHole(state)
        }

        if phase == 2 {
            return AdvanceHoleEscapes(state)
        }

        state.Phase = 99
        return null
    }

    // THE FORK, AND SIX OF SEVEN FORMS TAKE THE SHORT ARM. Only an interpolated string has parts to
    // walk; every other form is finished the moment it began.
    func AdvanceEntry(state: LiteralExpressionState): LiteralExpressionRequest? {
        if state.Form != 4 {
            state.Phase = 99
            return null
        }

        state.Phase = 1
        return null
    }

    // THE NEXT HOLE IN SOURCE ORDER. Text parts are walked past rather than skipped over, because
    // "the next hole" is a position in the part list and nothing else.
    func AdvanceNextHole(state: LiteralExpressionState): LiteralExpressionRequest? {
        interpolated := state.Interpolated
        if interpolated == null {
            state.Phase = 99
            return null
        }

        parts := interpolated.Parts
        while state.PartIndex < parts.Count {
            part := parts[state.PartIndex]
            state.PartIndex = state.PartIndex + 1
            hole := part as InterpolatedStringHole
            if hole != null {
                state.Pending = 1
                state.Phase = 2
                return new LiteralExpressionRequest(1, hole.Expression, hole.Expression.Line, hole.Expression.Column)
            }
        }

        state.Phase = 99
        return null
    }

    // WHAT A HOLE MAY NOT CARRY. Both reports run: a hole that is a row view AND a direct column read
    // is told both things, because they are different mistakes with different fixes and neither
    // silences the other. The hole's own expression is the span both are reported against.
    func AdvanceHoleEscapes(state: LiteralExpressionState): LiteralExpressionRequest? {
        interpolated := state.Interpolated
        if interpolated == null {
            state.Phase = 99
            return null
        }

        parts := interpolated.Parts
        hole := parts[state.PartIndex - 1] as InterpolatedStringHole
        if hole != null {
            soaEscapeValue.ReportSoaRowEscapeIfNeeded(hole.Expression, state.HoleType, "formatted in an interpolated string")
            soaEscapeValue.ReportUnsupportedSoaDirectColumnValueEscapeIfNeeded(hole.Expression, "formatted in an interpolated string")
        }

        state.Phase = 1
        return null
    }

    // WHAT AN INTEGER LITERAL'S TEXT MEANS, INCLUDING WHEN THE TARGET DECIDES IT.
    //
    // The suffix rules come first and are absolute: `ul` is `ulong`; `u` is `uint` when the magnitude
    // fits and `ulong` when it does not; `l` is `long` when it fits and `ulong` when it does not. A
    // literal whose text is not a parseable unsigned magnitude — an empty `0x`, a malformed digit run
    // — is `int` and asks nothing further, because there is no magnitude to fit anything against.
    //
    // ONLY A SUFFIXLESS LITERAL IS TARGET-TYPED, and it is read from the ambient slot AT THE INSTANT
    // THE WALK BEGAN. The attribute-argument walk asks this same question for the same reason and gets
    // the same answer, which is why this is a published member and not a phase.
    func IntLiteralType(value: string): TypeInfo {
        magnitude: ulong = 0
        if !NumericLiteralFacts.TryParseUnsignedIntegerMagnitude(value, out magnitude) {
            return BuiltInTypes.Int
        }

        suffix := NumericLiteralFacts.GetIntegerSuffix(value)
        if suffix.HasUnsigned && suffix.HasLong {
            return BuiltInTypes.ULong
        }

        if suffix.HasUnsigned {
            if magnitude <= 4294967295UL {
                return BuiltInTypes.UInt
            }

            return BuiltInTypes.ULong
        }

        if suffix.HasLong {
            if magnitude <= 9223372036854775807UL {
                return BuiltInTypes.Long
            }

            return BuiltInTypes.ULong
        }

        expected := ambientValue.CurrentExpectedType
        if expected != null {
            targetType: TypeInfo = BuiltInTypes.Int
            if TryGetExpectedIntegerLiteralType(expected, magnitude, out targetType) {
                return targetType
            }
        }

        return BuiltInTypes.Int
    }

    // WHETHER THE TARGET TYPE IS AN INTEGER TYPE THIS MAGNITUDE FITS IN. The expected type is resolved
    // through declared aliases first, and a nullable target is looked through — once, and its inner
    // type is resolved through aliases again, because `type Small = byte` and `Small?` are both things
    // an author writes. Both a written built-in name and a reflected CLR type answer; a reflected
    // `Nullable<T>` answers as its `T`. Anything else does not answer, and the caller falls back to
    // `int`.
    func TryGetExpectedIntegerLiteralType(expectedType: TypeInfo, magnitude: ulong, out targetType: TypeInfo): bool {
        resolved := declarationContextValue.ResolveDeclaredAlias(expectedType)
        nullable := resolved as NullableTypeInfo
        if nullable != null {
            resolved = declarationContextValue.ResolveDeclaredAlias(nullable.InnerType)
        }

        simple := resolved as SimpleTypeInfo
        if simple != null {
            simpleMaxValue: ulong = 0
            if NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue(simple.Name, out simpleMaxValue) && magnitude <= simpleMaxValue {
                targetType = simple
                return true
            }
        }

        reflection := resolved as ReflectionTypeInfo
        if reflection != null {
            clrType := reflection.Type
            underlying := Nullable.GetUnderlyingType(clrType)
            if underlying != null {
                clrType = underlying
            }

            reflectionType: SimpleTypeInfo = BuiltInTypes.Int
            if NumericLiteralFacts.TryGetIntegerLiteralTypeInfo(clrType, out reflectionType) {
                reflectionMaxValue: ulong = 0
                if NumericLiteralFacts.TryGetUnsignedIntegerLiteralMaxValue(reflectionType.Name, out reflectionMaxValue) && magnitude <= reflectionMaxValue {
                    targetType = reflectionType
                    return true
                }
            }
        }

        targetType = BuiltInTypes.Int
        return false
    }
}
