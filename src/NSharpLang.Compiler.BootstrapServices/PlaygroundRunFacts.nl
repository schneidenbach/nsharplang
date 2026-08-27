namespace NSharpLang.Playground


// WHAT THE BROWSER RUNNER DECIDES — the hosted playground's execution policy, in one owner.
//
// `PlaygroundRunner.cs` is a tree-walking interpreter that exists because a browser tab has no
// process to spawn and no `Reflection.Emit` to run: it is the ONLY thing behind the playground's Run
// button, and its retirement is a Playground task (run emitted IL in the browser), not a
// compiler-ownership one. That MECHANISM stays where it is. What lives here is everything the
// mechanism DECIDES — the vocabulary a user reads when the runner refuses, the three budgets that
// stop a runaway program, the words the runner prints values with, and the handful of rules it uses
// to interpret a program's meaning.
//
// THE VOCABULARY IS THE LARGEST PART AND IT WAS THE LEAST PROTECTED. The runner spelled 37 codes,
// `PG201` through `PG237`, each paired with a sentence, as 74 string literals scattered across 37
// `throw` sites — over half of the file's whole literal census. Every one of them is USER-VISIBLE:
// it becomes a `PlaygroundDiagnostic.Code` and `.Message` in the `PlaygroundRunResponse` the browser
// renders. None of them was documented anywhere in the repository, and only sixteen of the
// thirty-seven are reachable at all by a program that survives analysis, because `RunProject` runs
// the analyzer first and executes nothing when it reports an error. The other twenty-one are guards
// against shapes the analyzer already refuses; they are kept, spelled once, rather than deleted on a
// reachability argument that a future analyzer change could invalidate.
//
// THE BUDGETS ARE POLICY, NOT TUNING. 20,000 steps, 128 frames and 200 output lines are the contract
// between the playground and a tutorial-scale program, and the last of them is quoted back to the
// user inside its own sentence.
//
// TWO RULES ARE DEFINED RATHER THAN COPIED, and both are recorded as reformulations rather than
// moves:
//   * `IsZeroDivisor` reads `divisor == 0.0` where the C# read `Math.Abs(divisor) < double.Epsilon`.
//     Those agree on EVERY double: `Double.Epsilon` is the smallest positive denormal, so the only
//     values whose magnitude is below it are `+0.0` and `-0.0`, both of which compare equal to
//     `0.0`; and `NaN` fails both tests. The rewrite was forced — the columnar backend does not
//     model `Double.Epsilon`, which is measured, not assumed.
//   * `NumbersEqual` negates by hand where the C# called `Math.Abs`, for the same reason: the
//     backend does not model `Math.Abs(double)` either. The two are pointwise identical, `NaN`
//     included.
//
// WHAT IS DELIBERATELY NOT HERE. The runner's `IsTruthy` has six arms and only one of them can ever
// run: N#'s five boolean gates — `if`, `while`, `for`, the ternary and a `match` guard — all reject
// a non-`bool` condition with `NL202`, so a program that reaches the interpreter has already been
// told that `if 1`, `if "hi"`, `if flag` on a `bool?` and `1 && 2` are type errors. The other five
// arms are a latent guard, and moving a decision nothing can observe would have been ceremony. The
// two BCL member rosters are also absent: their names are the switch labels of the calls that
// implement them, so restating them here would create the second spelling this campaign exists to
// remove.
class PlaygroundRunFacts {

    // ---- THE THREE BUDGETS ----

    // How many AST nodes one run may visit before the playground stops it.
    static func MaxSteps(): int {
        return 20000
    }

    // How deep the call stack may go. A browser tab shares its stack with the host.
    static func MaxCallDepth(): int {
        return 128
    }

    // How many lines one run may print. Quoted back to the user in `OutputLineLimitReached`.
    static func MaxOutputLines(): int {
        return 200
    }

    // ---- THE NAMES THE RUNNER RECOGNISES ----

    // WHICH FUNCTION IS THE ENTRY POINT. Case-insensitive, so both `main` and `Main` run — which is
    // what the emitter does too, from the other side: `ColumnarIlEmitter` looks for `Main`.
    static func IsEntryPointFunctionName(name: string): bool {
        return string.Equals(name, "main", StringComparison.OrdinalIgnoreCase)
    }

    // The discard name in a deconstruction target list: `_` binds nothing.
    static func IsDiscardName(name: string): bool {
        return string.Equals(name, "_", StringComparison.Ordinal)
    }

    // The name the receiver is bound to inside an instance method body.
    static func ReceiverBindingName(): string {
        return "this"
    }

    // The member that reads a captured error's text: `err.Message`.
    static func ErrorMessageMemberName(): string {
        return "Message"
    }

    // The member that reads a string's or an array's length.
    static func LengthMemberName(): string {
        return "Length"
    }

    // `Exception("boom")` called as a free function, which is how `throw Exception(...)` reads.
    static func IsExceptionFactoryName(name: string): bool {
        return string.Equals(name, "Exception", StringComparison.Ordinal)
    }

    // `new Exception(...)` — both the short and the qualified spelling construct the same value.
    static func IsExceptionTypeName(typeName: string): bool {
        if string.Equals(typeName, "Exception", StringComparison.Ordinal) {
            return true
        }

        return string.Equals(typeName, "System.Exception", StringComparison.Ordinal)
    }

    // ---- THE INTERPRETATION RULES ----

    // WHEN TWO UNION CASE NAMES ARE THE SAME NAME. A case is written `Found` in the declaration and
    // reached as `LookupResult.Found` in a pattern or a construction, so the comparison is
    // suffix-tolerant in BOTH directions rather than exact.
    static func UnionCaseNamesMatch(left: string, right: string): bool {
        if string.Equals(left, right, StringComparison.Ordinal) {
            return true
        }

        if left.EndsWith("." + right, StringComparison.Ordinal) {
            return true
        }

        return right.EndsWith("." + left, StringComparison.Ordinal)
    }

    // HOW A QUALIFIED UNION CASE NAME SPLITS. `new LookupResult.Found(...)` names the union and the
    // case in one token; the split is at the LAST dot, and a name with no dot — or one that starts
    // with it — names no union case at all.
    static func IsQualifiedUnionCaseName(typeName: string): bool {
        return typeName.LastIndexOf(".") > 0
    }

    static func UnionOwnerNameOf(typeName: string): string {
        lastDot := typeName.LastIndexOf(".")
        if lastDot <= 0 {
            return ""
        }

        return typeName.Substring(0, lastDot)
    }

    static func UnionCaseNameOf(typeName: string): string {
        lastDot := typeName.LastIndexOf(".")
        if lastDot <= 0 {
            return ""
        }

        return typeName.Substring(lastDot + 1, typeName.Length - lastDot - 1)
    }

    // WHAT ENDS AN OUTPUT LINE. Always `\n`, never the host's newline: the transcript the browser
    // renders must not depend on which machine served the page.
    static func OutputLineTerminator(): string {
        return "\n"
    }

    // WHAT COUNTS AS DIVIDING BY ZERO. See the header: this is `Math.Abs(d) < Double.Epsilon`
    // written in a spelling the backend models, and the two agree on every double.
    static func IsZeroDivisor(divisor: double): bool {
        return divisor == 0.0
    }

    // The text a division by zero surfaces as. It is NOT the CLR's
    // `Attempted to divide by zero.` — the playground answers in its own words, and that divergence
    // is recorded rather than hidden.
    static func DivisionByZeroMessage(): string {
        return "division by zero"
    }

    // WHEN DIVISION TRUNCATES. Two integral operands divide as integers; anything else divides as
    // doubles.
    static func UseIntegerDivision(leftIsIntegral: bool, rightIsIntegral: bool): bool {
        return leftIsIntegral && rightIsIntegral
    }

    // How close two numbers must be for `==` to answer true in the browser runner. This is a
    // DIVERGENCE from the language: `0.1 + 0.2 == 0.3` is `False` under `nlc run` and `True` here.
    static func NumericEqualityTolerance(): double {
        return 0.0000001
    }

    // See the header: hand-rolled magnitude, because `Math.Abs(double)` is not modelled.
    static func NumbersEqual(left: double, right: double): bool {
        delta := left - right
        if delta < 0.0 {
            delta = 0.0 - delta
        }

        return delta < NumericEqualityTolerance()
    }

    // THE ESCAPE DECODER. The AST carries a string literal's RAW text, delimiters and all, so the
    // runner has to undo the lexer's work to get the value. A raw string keeps its body verbatim; a
    // regular string loses its quotes and then decodes the five escapes the runner recognises.
    static func DecodeStringLiteralText(value: string): string {
        text := value
        if text.StartsWith("\"\"\"", StringComparison.Ordinal) && text.EndsWith("\"\"\"", StringComparison.Ordinal) && text.Length >= 6 {
            return text.Substring(3, text.Length - 6)
        }

        if text.StartsWith("\"", StringComparison.Ordinal) && text.EndsWith("\"", StringComparison.Ordinal) && text.Length >= 2 {
            text = text.Substring(1, text.Length - 2)
        }

        return text.Replace("\\n", "\n").Replace("\\r", "\r").Replace("\\t", "\t").Replace("\\\"", "\"").Replace("\\\\", "\\")
    }

    // ---- THE WORDS THE RUNNER PRINTS VALUES WITH ----

    static func NullDisplayText(): string {
        return "null"
    }

    // `True`/`False`, which is what the CLR's `Boolean.ToString()` answers, so this one AGREES with
    // `nlc run`.
    static func BooleanDisplayText(value: bool): string {
        if value {
            return "True"
        }

        return "False"
    }

    // The numeric format. `G` under the invariant culture, so a `de-DE` browser still sees `0.5`.
    static func NumberFormatSpecifier(): string {
        return "G"
    }

    // What an object with no declaration calls itself.
    static func AnonymousObjectDisplayName(): string {
        return "object"
    }

    static func DisplayFieldSeparator(): string {
        return ", "
    }

    static func ObjectFieldDisplayText(fieldName: string, valueText: string): string {
        return fieldName + ": " + valueText
    }

    // `Point { X: 1, Y: 2 }`. A DIVERGENCE: `nlc run` prints `P.Point`, the CLR default.
    static func ObjectDisplayText(typeName: string, fieldText: string): string {
        return typeName + " { " + fieldText + " }"
    }

    // `Shape.Circle(Radius: 3)`. A DIVERGENCE: `nlc run` prints `P.Shape+Circle`.
    static func UnionDisplayText(typeName: string, caseName: string, fieldText: string): string {
        return typeName + "." + caseName + "(" + fieldText + ")"
    }

    // ---- THE THIRTY-SEVEN FAULTS, PG201 THROUGH PG237 ----
    //
    // Sixteen are reachable by an analysis-clean program and are marked REACHABLE; the other
    // twenty-one guard shapes the analyzer refuses first, and are marked GUARD.

    // REACHABLE. A sample with no `main` cannot be run.
    static func NoEntryPoint(): PlaygroundRunFault {
        return new PlaygroundRunFault("PG201", "This sample does not declare a main function that the browser runner can execute.")
    }

    // REACHABLE. Recursion past `MaxCallDepth`.
    static func CallDepthExceeded(): PlaygroundRunFault {
        return new PlaygroundRunFault("PG202", "The browser runner stopped this program because it exceeded the maximum call depth.")
    }

    // GUARD. Arity is an `NL` error before the runner ever sees the call.
    static func WrongArgumentCount(functionName: string, argumentCount: int): PlaygroundRunFault {
        return new PlaygroundRunFault("PG203", "The browser runner cannot call '" + functionName + "' with " + argumentCount.ToString() + " argument(s).")
    }

    // REACHABLE. `while`, `for`, `try`, and every other statement the walk has no arm for.
    static func UnsupportedStatement(statementKindName: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG204", "The browser runner does not yet support " + statementKindName + ".")
    }

    // REACHABLE. Any deconstruction that is not the two-name Go-style error capture.
    static func UnsupportedDeconstruction(): PlaygroundRunFault {
        return new PlaygroundRunFault("PG205", "The browser runner only supports result, err := Function(...) deconstruction.")
    }

    // GUARD. A non-array collection is typed before the runner reaches it.
    static func UnsupportedForeachCollection(): PlaygroundRunFault {
        return new PlaygroundRunFault("PG206", "The browser runner only supports foreach over array literals.")
    }

    // REACHABLE. `await`, lambdas, casts — every expression the walk has no arm for.
    static func UnsupportedExpression(expressionKindName: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG207", "The browser runner does not yet support " + expressionKindName + ".")
    }

    // REACHABLE — and this is the one the shipped `04-unions-patterns` example hits, because a
    // union pattern's SHORTHAND property binding declares nothing.
    static func UnresolvedName(name: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG208", "The browser runner could not resolve '" + name + "'.")
    }

    // REACHABLE. Seven of the language's twenty-one binary operators have no arm.
    static func UnsupportedBinaryOperator(operatorName: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG209", "The browser runner does not yet support the " + operatorName + " operator.")
    }

    // REACHABLE. Six of the eight unary operators have no arm.
    static func UnsupportedUnaryOperator(operatorName: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG210", "The browser runner does not yet support the " + operatorName + " operator.")
    }

    // REACHABLE. `??=` is the one compound assignment with no arm.
    static func UnsupportedAssignmentOperator(operatorName: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG211", "The browser runner does not yet support " + operatorName + ".")
    }

    // REACHABLE. Assigning through an indexer.
    static func UnsupportedAssignmentTarget(): PlaygroundRunFault {
        return new PlaygroundRunFault("PG212", "The browser runner only supports assignment to variables and object properties.")
    }

    // GUARD. A computed callee does not survive analysis.
    static func UnsupportedCallee(): PlaygroundRunFault {
        return new PlaygroundRunFault("PG213", "The browser runner only supports direct function and member calls.")
    }

    // GUARD. An unknown free function is `NL301`.
    static func UnknownFunction(name: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG214", "The browser runner cannot call '" + name + "'.")
    }

    // GUARD. A missing instance method is an analyzer error.
    static func MethodNotFound(memberName: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG215", "The browser runner could not find method '" + memberName + "'.")
    }

    // GUARD. A missing static method is an analyzer error.
    static func StaticMethodNotFound(memberName: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG216", "The browser runner could not find static method '" + memberName + "'.")
    }

    // REACHABLE. A `string` member outside the browser's bounded roster.
    static func UnsupportedStringMember(memberName: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG217", "The browser runner does not yet support string." + memberName + ".")
    }

    // REACHABLE. A numeric member outside the browser's bounded roster.
    static func UnsupportedNumericMember(memberName: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG218", "The browser runner does not yet support numeric." + memberName + ".")
    }

    // REACHABLE. A member call on a receiver the runner models no members for, such as `bool`.
    static func UnsupportedReceiverMember(memberName: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG219", "The browser runner cannot call member '" + memberName + "' on this receiver.")
    }

    // GUARD. An unresolvable member read is an analyzer error.
    static func UnresolvedMember(memberName: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG220", "The browser runner cannot resolve member '" + memberName + "'.")
    }

    // GUARD. Assigning a member of a non-object is an analyzer error.
    static func UnassignableMember(memberName: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG221", "The browser runner cannot assign member '" + memberName + "'.")
    }

    // GUARD. `new` with no nameable type.
    static func UnsupportedConstructionTarget(): PlaygroundRunFault {
        return new PlaygroundRunFault("PG222", "The browser runner only supports named object construction.")
    }

    // REACHABLE. `new List<int>()` and every other type declared outside the sample.
    static func UnknownConstructedType(typeName: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG223", "The browser runner cannot construct '" + typeName + "'.")
    }

    // REACHABLE. A class with an explicit constructor rather than a primary one.
    static func UnsupportedConstructorArguments(): PlaygroundRunFault {
        return new PlaygroundRunFault("PG224", "The browser runner only supports constructor arguments on primary constructors and union cases.")
    }

    // GUARD. Constructor arity is an analyzer error.
    static func WrongConstructorArgumentCount(): PlaygroundRunFault {
        return new PlaygroundRunFault("PG225", "The browser runner received the wrong number of constructor arguments.")
    }

    // GUARD. Indexer initializers do not survive analysis here.
    static func UnsupportedIndexerInitializer(): PlaygroundRunFault {
        return new PlaygroundRunFault("PG226", "The browser runner does not yet support indexer initializers.")
    }

    // GUARD. `with` on a non-record is an analyzer error.
    static func UnsupportedWithTarget(): PlaygroundRunFault {
        return new PlaygroundRunFault("PG227", "The browser runner only supports with expressions on records and objects.")
    }

    // GUARD. Indexer values inside a `with`.
    static func UnsupportedWithIndexer(): PlaygroundRunFault {
        return new PlaygroundRunFault("PG228", "The browser runner does not yet support indexer values in with expressions.")
    }

    // GUARD. Exhaustiveness is checked before the run.
    static func NoMatchingMatchArm(): PlaygroundRunFault {
        return new PlaygroundRunFault("PG229", "The browser runner reached a match expression without a matching arm.")
    }

    // GUARD. A float literal pattern is `NL103` at parse time.
    static func UnsupportedLiteralPattern(): PlaygroundRunFault {
        return new PlaygroundRunFault("PG230", "The browser runner only supports literal string, int, bool, and null match patterns.")
    }

    // GUARD. Every other pattern kind.
    static func UnsupportedPattern(patternKindName: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG231", "The browser runner does not yet support " + patternKindName + ".")
    }

    // GUARD. An unknown union case is an analyzer error.
    static func UnknownUnionCase(caseName: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG232", "The browser runner could not find union case '" + caseName + "'.")
    }

    // GUARD. Union case arity is an analyzer error.
    static func WrongUnionCaseArgumentCount(): PlaygroundRunFault {
        return new PlaygroundRunFault("PG233", "The browser runner received the wrong number of union case arguments.")
    }

    // REACHABLE. The output budget, quoted.
    static func OutputLineLimitReached(): PlaygroundRunFault {
        return new PlaygroundRunFault("PG234", "The browser runner stopped this program after " + MaxOutputLines().ToString() + " output lines.")
    }

    // GUARD in practice — the depth budget is reached first by every recursion, and a bounded loop
    // cannot run at all because `while` and `for` have no arm. The step budget, quoted.
    static func StepLimitReached(): PlaygroundRunFault {
        return new PlaygroundRunFault("PG235", "The browser runner stopped this program after " + MaxSteps().ToString() + " execution steps.")
    }

    // GUARD. Arithmetic on a non-number is an analyzer error.
    static func ExpectedNumber(valueText: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG236", "The browser runner expected a number, but found " + valueText + ".")
    }

    // GUARD. `%` on a non-integer is an analyzer error.
    static func ExpectedInteger(valueText: string): PlaygroundRunFault {
        return new PlaygroundRunFault("PG237", "The browser runner expected an integer, but found " + valueText + ".")
    }
}
