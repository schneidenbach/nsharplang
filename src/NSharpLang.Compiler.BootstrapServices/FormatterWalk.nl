namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Text
import NSharpLang.Compiler.Ast


// THE FORMATTER'S BODY WALK: EVERY STATEMENT, EVERY EXPRESSION AND EVERY PATTERN N# WRITES.
//
// `Formatter` is a walk over an AST that appends source text to a builder. Three slices took it
// apart in the order its own call graph allowed:
//
//   * slice 17 took the STATE — the indent depth, the comment stream, the two position cursors and
//     the two configured constants — into `FormatterWalkState`, because every arm here pushes and
//     pops the depth and an arm that could not reach its state would have needed a callback;
//   * slice 18 took the LEAF TEXT — the type reference, the modifier list and the `allow` header —
//     into `FormatterSyntaxText`, because those are total functions from a node to a string;
//   * this owner takes the WALK ITSELF, which is what was left once both were gone.
//
// MEASURED, IT WAS ONE CLOSED CUT AND NOT A CHOICE. `nl93-scc.py` reported a fourteen-member cycle
// (`FormatStatement` ↔ `FormatExpression` ↔ `FormatPattern` ↔ `FormatFunction` ↔ …, 1,283 lines)
// whose only escape was `GetCurrentColumn`; adding that one measurement closed the set to NOTHING.
// `GetCurrentColumn` is now DELETED along with the width rule that was its only caller — the
// formatter has no width limit — and the cycle is closed without it.
//
// THE SIX ENTRY POINTS ARE `FormatAttributes`, `FormatBlock`, `FormatParameter`,
// `AppendParameterList`, `FormatExpression` AND `FormatFunction`. Everything else is reachable only
// from inside this walk; the declaration formatters in `Formatter` name none of the rest.
//
// THE WRAPPING RULE IS THE FIRST THING BELOW, because it is the one decision every delimited list in
// the language routes through, and because before it existed this walk could only write a list on
// one line.
//
// THE STATE IS BORROWED, NOT OWNED. This walk and the `Formatter` that constructs it share one
// `FormatterWalkState` object, because a declaration formatter in C# and a statement arm here are
// the same walk at different depths and must agree about the indent depth and the comment cursor
// to the character. Constructing a second state would silently reset both.
class FormatterWalk {
    state: FormatterWalkState

    constructor(sharedState: FormatterWalkState) {
        state = sharedState
    }

    // ---- the wrapping rule -----------------------------------------------------------------------

    // WHETHER A DELIMITED LIST IS WRITTEN ON ONE LINE OR ONE ELEMENT PER LINE. THE AUTHOR DECIDES.
    //
    // This is gofmt's model, and it replaces having no model at all: before this rule every list arm
    // in this file wrote `", "` between elements and one line was the only shape it could produce, so
    // the formatter JOINED every hand-wrapped call in the estate onto a single line. The rule now is:
    //
    //   * a list the author wrote on ONE source line stays on one line, however long it is — there is
    //     NO width limit in the formatter, and the one that used to exist (the object initializer's
    //     `MaxLineLength` measurement) is deleted. A ceiling, if the language ever wants one, is a lint;
    //   * a list that SPANS MORE THAN ONE SOURCE LINE is canonicalised to one element per line, block
    //     indented one level, with the closing delimiter alone on its own line at the opening line's
    //     indent. No trailing comma — N# rejects one (NL101 in an argument list or array literal, NL102
    //     in a parameter list), so the last element is bare;
    //   * the formatter NEVER joins an author's line break.
    //
    // "SPANS MORE THAN ONE SOURCE LINE" IS A QUESTION ABOUT THE TWO DELIMITERS, not about the elements:
    // `f(a, b\n)` is wrapped even though every element fits on the opening line. The parser stamps each
    // list node's `EndLine` with its closer (`ColumnarParserRecovery.StampListEnd`), and `EndLine`
    // defaults to `Line`, so a hand-built AST — every tree in `Formatter.tests.nl` and in this file's
    // own contracts — reads as single-line and keeps the behaviour it has always had.
    //
    // NESTING COMPOSES OUTWARD FOR FREE. A wrapped inner list pushes the outer list's closer onto a
    // later line, so the outer is wrapped by this same test with no extra machinery.
    //
    // THE ONE EXEMPTION IS THE HUG, and it is why `maxElementLine` is a parameter. When every element
    // STARTS on the opening line and the LAST element is one that will be WRITTEN ACROSS LINES, the
    // outer stays flat and the inner does the wrapping: `Task.Run(() => { … })`, `add(new Foo { … })`,
    // `xs.Select(x => match x { … })`. That is what every gofmt-family formatter does, and without it
    // every callback in the estate is torn into five lines. Elements cannot begin before the opener,
    // so "every element starts on the opening line" is exactly `maxElementLine == openLine` — one
    // integer, no allocation. See `ExpressionSpansLines` for what counts as written across lines.
    //
    // THERE IS DELIBERATELY NO "A COMMENT FORCES THE WRAP" CLAUSE, and the first version of this rule
    // had one. It was both unnecessary and wrong. Unnecessary because a `//` comment runs to the end of
    // its line, so a list written entirely on ONE line cannot contain one — the flat shape is never at
    // risk. Wrong because the only cheap test for "a comment inside this list" is "a comment between
    // the two delimiter lines", and that also catches every comment inside a nested BLOCK: it fired on
    // the comment inside the lambda in `examples/17-issue-tracker/backend/Endpoints.nl` and tore a
    // hugged callback apart. A comment inside an element's own body is emitted by that element's own
    // walk, on its own lines, and was never this rule's business. What remains is that a WRAPPED list
    // emits the comments standing between its elements, which is stated below and contracted.
    //
    // IT IS IDEMPOTENT BY CONSTRUCTION, WHICH IS THE PROPERTY THAT MATTERS. Wrapped output puts every
    // element strictly below the opener and the closer strictly below them, so a reparse re-derives
    // "wrapped"; flat output puts opener, elements and closer on one line, so a reparse re-derives
    // "flat"; and a hugged list reparses with its elements still on the opening line and its last
    // element still wrapped, so it hugs again. `Formatter.FormatSafe` re-formats its own output and
    // returns the ORIGINAL source if the two differ, so a rule that were not idempotent would show up
    // as "the formatter did nothing", not as churn.
    static func ShouldWrapList(openLine: int, closeLine: int, elementCount: int, maxElementLine: int, lastElementSpansLines: bool): bool {
        // An empty list has nothing to put on a line of its own; `()` and `[]` stay as written.
        if elementCount == 0 {
            return false
        }

        // A tree with no source positions — hand-built, or from a path that never stamped one — is
        // single-line by definition. This is what keeps every AST-built contract unchanged.
        if openLine <= 0 {
            return false
        }

        if closeLine <= openLine {
            return false
        }

        if maxElementLine == openLine && lastElementSpansLines {
            return false
        }

        return true
    }

    // The same question for a list whose CLOSER the parser does not stamp: a declaration's parameter
    // list, whose `(` and `)` belong to the declaration node rather than to a list node of their own.
    //
    // Here the test is the ELEMENTS: a parameter that starts below the declaration's own line is a
    // wrapped list. The two tests differ only for a closer left dangling under a complete first line
    // (`func f(a: int\n)`), which the element test reads as flat — a shape that appears NOWHERE in the
    // estate, where all 188 wrapped parameter lists put a parameter on a later line. The hug cannot
    // arise here for the same reason: with no parameter below the opener there is nothing to wrap.
    static func ShouldWrapByElementLines(openLine: int, elementCount: int, maxElementLine: int): bool {
        return elementCount > 0 && openLine > 0 && maxElementLine > openLine
    }

    // WILL THIS EXPRESSION BE WRITTEN ACROSS LINES? Asked of a list's LAST element, to decide the hug.
    //
    // IT IS NOT ENOUGH TO ASK "IS IT A WRAPPED LIST", and getting that wrong tore `Task.Run(() => {
    // … })` into five lines in `examples/11-advanced-features/LockStatement`. A lambda with a BLOCK
    // BODY is not a list, but it is written across lines every time, and hugging it is the whole point
    // of the exemption — `f(x => { … })` and `Task.Run(() => { … })` are the shapes the rule exists to
    // protect. So the question is about the OUTPUT, and the answer is the complete set of expression
    // arms in this walk that emit a newline: a wrapped list, a lambda with a block body, and a `match`.
    //
    // A `new` carries two independent lists — its constructor arguments (its own span) and its
    // initializer (the initializer's own braces) — and either one wrapping is enough to hug.
    //
    // THE TEST IS DELIBERATELY SHALLOW: it asks about the element itself, not about anything nested
    // inside a larger expression. `f(a + g(\n x))` therefore wraps rather than hugs. That is the
    // conservative direction — it preserves the author's break by spelling it out — and it keeps the
    // rule predictable and idempotent, which recursing would not obviously do.
    static func ExpressionSpansLines(expression: Expression): bool {
        call := expression as CallExpression
        if call != null {
            return call.EndLine > call.Line
        }

        arrayLiteral := expression as ArrayLiteralExpression
        if arrayLiteral != null {
            return arrayLiteral.EndLine > arrayLiteral.Line
        }

        newExpression := expression as NewExpression
        if newExpression != null {
            if newExpression.EndLine > newExpression.Line {
                return true
            }

            initializer := newExpression.Initializer
            if initializer != null {
                return initializer.EndLine > initializer.Line
            }

            return false
        }

        objectInitializer := expression as ObjectInitializerExpression
        if objectInitializer != null {
            return objectInitializer.EndLine > objectInitializer.Line
        }

        // A block-bodied lambda always writes `=> {`, a newline, its statements and a closing brace. An
        // EXPRESSION-bodied one is as wide as its expression, so it spans lines exactly when that
        // expression does — `() => new { … }` over a wrapped initializer is the shape in
        // `examples/14-minimal-api`, and the lambda is the only wrapper this test looks through.
        lambda := expression as LambdaExpression
        if lambda != null {
            if lambda.BlockBody != null {
                return true
            }

            lambdaBody := lambda.ExpressionBody
            if lambdaBody != null {
                return ExpressionSpansLines(lambdaBody)
            }

            return false
        }

        // `on target.Event (a, b) => { … }` is a lambda behind a keyword.
        onSubscription := expression as OnSubscriptionExpression
        if onSubscription != null {
            return ExpressionSpansLines(onSubscription.Handler)
        }

        // A `match` is one line per case, always.
        matchExpression := expression as MatchExpression
        if matchExpression != null {
            return true
        }

        return false
    }

    // ---- the delimited lists ---------------------------------------------------------------------

    // AN ARGUMENT LIST — a call's or a constructor's, which are the same list of the same element type
    // and now the same code. Flat or one per line, decided by `ShouldWrapList` above.
    //
    // The comma is the whole difference between the two shapes: `", "` between elements on one line,
    // a bare `","` at the end of each wrapped line, and NEVER after the last element. When wrapped,
    // any comment the author left between two elements is emitted on its own line above the element
    // that follows it, and any comment between the last element and the closer above the closer —
    // which is where the leading-comment model puts every other comment in the file.
    func FormatArgumentList(arguments: List<Argument>, openLine: int, closeLine: int, builder: StringBuilder) {
        wrapped := ShouldWrapList(openLine, closeLine, arguments.Count, MaxArgumentLine(arguments), LastArgumentSpansLines(arguments)) && ArgumentsCanBeginLines(arguments)

        // The gap tracker is written through a LOCAL, because the columnar backend declines a property
        // assignment whose receiver is a field (NL103, node kind 23). Every other write of it in the
        // formatter is spelled the same way, for the same reason.
        tracker := state

        builder.Append("(")
        if wrapped {
            state.Push()
            // The gap the comment stream measures is now measured from INSIDE the list: the opening
            // line is the baseline, and each element becomes the next one. Without this the tracker
            // still holds the line before the statement, and every interior comment reads as though a
            // blank line stood above it.
            tracker.LastEmittedSourceLine = openLine
        }

        index := 0
        while index < arguments.Count {
            argument := arguments[index]
            if wrapped {
                builder.AppendLine()
                state.EmitCommentsBefore(argument.Value.Line, builder)
                state.Indent(builder)
                tracker.LastEmittedSourceLine = argument.Value.Line
            }

            AppendArgument(argument, builder)
            if index < arguments.Count - 1 {
                if wrapped {
                    builder.Append(",")
                } else {
                    builder.Append(", ")
                }
            }

            index = index + 1
        }

        if wrapped {
            builder.AppendLine()
            state.EmitCommentsBefore(closeLine, builder)
            state.Pop()
            state.Indent(builder)
        }

        builder.Append(")")
    }

    // One argument: the optional `name:` prefix, the optional `ref`/`out` modifier, the value.
    func AppendArgument(argument: Argument, builder: StringBuilder) {
        argumentName := argument.Name
        if argumentName != null {
            builder.Append(argumentName)
            builder.Append(": ")
        }

        if argument.Modifier == ArgumentModifier.Ref {
            builder.Append("ref ")
        } else if argument.Modifier == ArgumentModifier.Out {
            builder.Append("out ")
        }

        FormatExpression(argument.Value, builder)
    }

    // The lowest line every argument starts at or above. `Argument` carries no position of its own —
    // its `name:` prefix and its `ref`/`out` modifier stand on the value's line — so the VALUE's line
    // is the argument's line.
    static func MaxArgumentLine(arguments: List<Argument>): int {
        highest := 0
        index := 0
        while index < arguments.Count {
            argumentLine := arguments[index].Value.Line
            if argumentLine > highest {
                highest = argumentLine
            }

            index = index + 1
        }

        return highest
    }

    // CAN EVERY ARGUMENT BEGIN A LINE OF ITS OWN? A wrapped list that answers no would not re-parse.
    //
    // The parser ends an argument list at a continuation token that starts a statement, a declaration
    // or a modifier (`IsContinuationRecoveryBoundary`), and `ref` is a DECLARATION keyword. So
    // `f(a, ref b\n)` — a list the delimiter test calls wrapped — would be rewritten with `ref b` at
    // the head of a line, and the parser would stop the list before it. `FormatSafe`'s reparse gate
    // would then catch that and return the ORIGINAL source, so the file would silently stop being
    // formatted at all; refusing the wrap and leaving the list on one line is the better answer, and
    // it is still author-preserving in the direction that matters — nothing the author wrote is lost.
    //
    // `out` is not in any of the three sets and needs no guard; `ref` is the one modifier that is.
    static func ArgumentsCanBeginLines(arguments: List<Argument>): bool {
        index := 0
        while index < arguments.Count {
            if arguments[index].Modifier == ArgumentModifier.Ref {
                return false
            }

            index = index + 1
        }

        return true
    }

    static func LastArgumentSpansLines(arguments: List<Argument>): bool {
        if arguments.Count == 0 {
            return false
        }

        return ExpressionSpansLines(arguments[arguments.Count - 1].Value)
    }

    // A list of bare expressions — an array or collection literal's elements.
    static func MaxExpressionLine(expressions: List<Expression>): int {
        highest := 0
        index := 0
        while index < expressions.Count {
            expressionLine := expressions[index].Line
            if expressionLine > highest {
                highest = expressionLine
            }

            index = index + 1
        }

        return highest
    }

    static func LastExpressionSpansLines(expressions: List<Expression>): bool {
        if expressions.Count == 0 {
            return false
        }

        return ExpressionSpansLines(expressions[expressions.Count - 1])
    }

    // A PARAMETER LIST, wherever one is written: a function, a constructor, a record's primary
    // constructor, or an indexer — whose brackets are SQUARE, which is why the two delimiters are
    // arguments rather than literals. `openLine` is the declaration's own line; see
    // `ShouldWrapByElementLines` for why the closer plays no part here.
    func AppendParameterList(parameters: List<Parameter>, openLine: int, openText: string, closeText: string, builder: StringBuilder) {
        wrapped := ShouldWrapByElementLines(openLine, parameters.Count, MaxParameterLine(parameters))

        builder.Append(openText)
        if wrapped {
            state.Push()
        }

        index := 0
        while index < parameters.Count {
            if wrapped {
                builder.AppendLine()
                state.EmitCommentsBefore(parameters[index].Line, builder)
                state.Indent(builder)
            }

            FormatParameter(parameters[index], builder)
            if index < parameters.Count - 1 {
                if wrapped {
                    builder.Append(",")
                } else {
                    builder.Append(", ")
                }
            }

            index = index + 1
        }

        if wrapped {
            builder.AppendLine()
            state.Pop()
            state.Indent(builder)
        }

        builder.Append(closeText)
    }

    static func MaxParameterLine(parameters: List<Parameter>): int {
        highest := 0
        index := 0
        while index < parameters.Count {
            parameterLine := parameters[index].Line
            if parameterLine > highest {
                highest = parameterLine
            }

            index = index + 1
        }

        return highest
    }

    // ---- attributes ------------------------------------------------------------------------------

    // Attributes on their own lines, above the declaration they annotate.
    //
    // The C# guard was `attributes is not { Count: > 0 }`, which is a null test and an emptiness
    // test in one token; both halves are written out here, and a null list is as silent as an empty
    // one because a declaration parsed from a path that never allocated the list has neither.
    func FormatAttributes(attributes: List<AttributeNode>?, builder: StringBuilder) {
        if attributes == null {
            return
        }

        if attributes.Count == 0 {
            return
        }

        index := 0
        while index < attributes.Count {
            state.Indent(builder)
            FormatAttributeInline(attributes[index], builder)
            builder.AppendLine()
            index = index + 1
        }
    }

    // ONE ATTRIBUTE, WRITTEN BACK EXACTLY AS THE AUTHOR WROTE IT.
    //
    // AN ATTRIBUTE IS AN ANNOTATION, NOT CODE THE FORMATTER MAY CANONICALISE, and re-rendering one
    // from its parts destroyed two real files in one reformat:
    //
    //   * `[aotSafe(mono-wasm)]` — an argument is stored as an EXPRESSION, so a policy token that
    //     merely looks like code is re-rendered as code, and it came back `[aotSafe(mono - wasm)]`;
    //   * `[trusted(\n reason: …,\n owner: …\n)]` — the node holds no line structure, so five lines
    //     were joined onto one and the `trusted` census stopped finding the site at all.
    //
    // Both are the SAME defect and both are fixed the same way: the parser stamps the `[`-to-`]` span
    // on the node and this writes it out unchanged. `FormatAttributes` normalises the indentation of
    // the line the attribute STARTS on and nothing else, so the author's line structure inside the
    // brackets survives — the gofmt rule, applied to a construct whose interior is not the
    // formatter's to decide.
    //
    // THE CLAIM THAT USED TO STAND HERE — that a named attribute argument is spelled `name = value`
    // while a call's is `name: value`, "the grammar, not an oversight" — WAS FALSE. `ParseAttributes`
    // parses its arguments with the SAME `ParseArgumentList()` a call uses, so `:` is the only
    // spelling that reads back, and the ` = ` form was output that the parser could not have produced
    // and cannot re-read. The fallback below therefore writes `: `, and it is a fallback: it runs only
    // for a tree with no span behind it, which means a hand-built one.
    func FormatAttributeInline(attribute: AttributeNode, builder: StringBuilder) {
        attributeSource := attribute.SourceText
        if attributeSource != null {
            builder.Append(attributeSource)
            return
        }

        builder.Append("[")
        builder.Append(attribute.Name)

        if attribute.Arguments.Count > 0 {
            builder.Append("(")
            index := 0
            while index < attribute.Arguments.Count {
                if index > 0 {
                    builder.Append(", ")
                }

                argument := attribute.Arguments[index]
                argumentName := argument.Name
                if argumentName != null {
                    builder.Append(argumentName)
                    builder.Append(": ")
                }

                FormatExpression(argument.Value, builder)
                index = index + 1
            }

            builder.Append(")")
        }

        builder.Append("]")
    }

    // ---- parameters ------------------------------------------------------------------------------

    // One parameter, everywhere a parameter list is written: functions, constructors, indexers,
    // primary constructors and explicitly typed lambdas.
    //
    // THE TYPE IS NEVER OPTIONAL HERE. A lambda whose parameters are all inferred is printed by the
    // lambda arm without ever reaching this member; anything that does reach it has a type to write.
    func FormatParameter(parameter: Parameter, builder: StringBuilder) {
        attributes := parameter.Attributes
        if attributes != null && attributes.Count > 0 {
            attributeIndex := 0
            while attributeIndex < attributes.Count {
                FormatAttributeInline(attributes[attributeIndex], builder)
                builder.Append(" ")
                attributeIndex = attributeIndex + 1
            }
        }

        if parameter.IsThis {
            builder.Append("this ")
        }

        if parameter.Modifier == ParameterModifier.Ref {
            builder.Append("ref ")
        } else if parameter.Modifier == ParameterModifier.Out {
            builder.Append("out ")
        } else if parameter.Modifier == ParameterModifier.Params {
            builder.Append("params ")
        }

        builder.Append(parameter.Name)
        builder.Append(": ")
        builder.Append(FormatterSyntaxText.FormatTypeReference(parameter.Type))

        if parameter.IsScoped {
            builder.Append(" scoped")
            lifetime := parameter.Lifetime
            if lifetime != null && !string.IsNullOrEmpty(lifetime) {
                builder.Append(" ")
                builder.Append(lifetime)
            }
        }

        if parameter.DefaultValue != null {
            builder.Append(" = ")
            FormatExpression(parameter.DefaultValue, builder)
        }
    }

    // ---- functions -------------------------------------------------------------------------------

    // A function declaration: attributes, modifiers, the `func` keyword or a conversion operator's
    // name, the parameter list, the return type, and one of three body shapes.
    //
    // A GENERATOR IS `func*` AND ITS FLAG IS NOT PRINTED AS A MODIFIER. `Generator` is bit 4,096 in
    // `Modifiers`, and `FormatterSyntaxText.FormatModifiers` deliberately has no arm for it — the
    // star after the keyword is the whole spelling.
    //
    // A CONVERSION OPERATOR TAKES THE OTHER FORK ENTIRELY: its name is `implicit` or `explicit` and
    // its return type follows the name rather than the parameter list, so the type-parameter list
    // and the `: Ret` suffix are both skipped. The same declaration also asks
    // `FormatModifiers` NOT to drop `public`/`private`, because an operator's name is not an
    // identifier whose case could carry the visibility.
    func FormatFunction(declaration: FunctionDeclaration, builder: StringBuilder) {
        FormatAttributes(declaration.Attributes, builder)
        state.Indent(builder)

        preserveCasing := !declaration.IsOperatorOverload && !declaration.IsConversionOperator
        modifiers := FormatterSyntaxText.FormatModifiers(declaration.Modifiers, declaration.Name, preserveCasing)
        if !string.IsNullOrEmpty(modifiers) {
            builder.Append(modifiers)
            builder.Append(" ")
        }

        if declaration.IsConversionOperator {
            builder.Append(declaration.Name)
            builder.Append(" ")
            if declaration.ReturnType != null {
                builder.Append(FormatterSyntaxText.FormatTypeReference(declaration.ReturnType))
            }
        } else {
            modifierBits := Convert.ToInt32(declaration.Modifiers)
            if FormatterSyntaxText.HasModifier(modifierBits, 4096) {
                builder.Append("func*")
            } else {
                builder.Append("func")
            }

            builder.Append(" ")
            builder.Append(declaration.Name)
            AppendTypeParameters(declaration.TypeParameters, builder)
        }

        AppendParameterList(declaration.Parameters, declaration.Line, "(", ")", builder)

        if !declaration.IsConversionOperator && declaration.ReturnType != null {
            builder.Append(": ")
            builder.Append(FormatterSyntaxText.FormatTypeReference(declaration.ReturnType))
        }

        returnLifetime := declaration.ReturnLifetime
        if returnLifetime != null && !string.IsNullOrEmpty(returnLifetime) {
            builder.Append(" returns ")
            builder.Append(returnLifetime)
        }

        if declaration.ExpressionBody != null {
            builder.Append(" => ")
            FormatExpression(declaration.ExpressionBody, builder)
            builder.AppendLine()
        } else if declaration.Body != null {
            builder.AppendLine(" {")
            state.Push()
            FormatBlock(declaration.Body, builder)
            state.Pop()
            state.Indent(builder)
            builder.AppendLine("}")
        } else {
            builder.AppendLine()
        }
    }

    // `<T, U>` or nothing. The C# wrote `string.Join(", ", xs.Select(tp => tp.Name))` at five sites
    // in the file, of which only the function's is inside this cut; written out it is a plain loop.
    func AppendTypeParameters(typeParameters: List<TypeParameter>?, builder: StringBuilder) {
        if typeParameters == null {
            return
        }

        if typeParameters.Count == 0 {
            return
        }

        builder.Append("<")
        index := 0
        while index < typeParameters.Count {
            if index > 0 {
                builder.Append(", ")
            }

            builder.Append(typeParameters[index].Name)
            index = index + 1
        }

        builder.Append(">")
    }

    // ---- blocks ----------------------------------------------------------------------------------

    // A statement list, with the comments and blank lines the source had between its statements.
    //
    // THE TRACKER IS BASELINED ON THE OPENING BRACE'S OWN LINE, and the guard matters: a block
    // parsed from a path that never stamped a line would otherwise reset the tracker to zero and
    // swallow the gap before the block's first statement.
    //
    // THE TRACKER IS WRITTEN THROUGH A LOCAL BOUND FROM THE FIELD, AND THAT IS NOT A STYLE CHOICE.
    // A property SET whose receiver is a FIELD declines against the pinned toolset at
    // `emit.statement.block-child` (node kind 23); the identical write through a local bound from
    // the same field compiles and stores to the same object, because the field holds a reference.
    // Proved single-variable by an isolated probe in which those two lines are the only difference.
    // It is the recorded "bind the receiver" gotcha, reaching assignment targets and not only
    // chained calls.
    func FormatBlock(block: BlockStatement, builder: StringBuilder) {
        tracker := state

        if block.Line > 0 {
            tracker.LastEmittedSourceLine = block.Line
        }

        index := 0
        while index < block.Statements.Count {
            statement := block.Statements[index]
            state.EmitCommentsBefore(statement.Line, builder)

            if index > 0 && state.HasBlankLineBefore(statement.Line) {
                builder.AppendLine()
            }

            FormatStatement(statement, builder)
            tracker.LastEmittedSourceLine = statement.EndLine
            index = index + 1
        }
    }

    // `alloc { … }`, `unsafe { … }` and `allow(…) { … }` differ only in their header text.
    func FormatKeywordBlock(header: string, body: BlockStatement, builder: StringBuilder) {
        state.Indent(builder)
        builder.Append(header)
        builder.AppendLine(" {")
        state.Push()
        FormatBlock(body, builder)
        state.Pop()
        state.Indent(builder)
        builder.AppendLine("}")
    }

    // ---- the if chain ----------------------------------------------------------------------------

    // `if cond { … } else if … { … } else { … }`, written as one flat chain rather than nested
    // blocks.
    //
    // THE ELSE-IF ARM RECURSES WITHOUT PUSHING, which is what keeps the chain flat: an `else if`
    // re-enters this member at the SAME indent depth, so a five-branch chain is five lines at one
    // level and not a staircase. A non-block `then` or `else` still gets braces, because the
    // formatter emits canonical N# and canonical N# braces every body.
    func FormatIfStatement(ifStatement: IfStatement, builder: StringBuilder) {
        builder.Append("if ")
        FormatExpression(ifStatement.Condition, builder)
        builder.AppendLine(" {")
        state.Push()

        thenBlock := ifStatement.ThenStatement as BlockStatement
        if thenBlock != null {
            FormatBlock(thenBlock, builder)
        } else {
            FormatStatement(ifStatement.ThenStatement, builder)
        }

        state.Pop()
        state.Indent(builder)
        builder.Append("}")

        elseStatement := ifStatement.ElseStatement
        if elseStatement != null {
            builder.Append(" else ")
            elseIfStatement := elseStatement as IfStatement
            if elseIfStatement != null {
                FormatIfStatement(elseIfStatement, builder)
            } else {
                builder.AppendLine("{")
                state.Push()
                elseBlock := elseStatement as BlockStatement
                if elseBlock != null {
                    FormatBlock(elseBlock, builder)
                } else {
                    FormatStatement(elseStatement, builder)
                }

                state.Pop()
                state.Indent(builder)
                builder.AppendLine("}")
            }
        } else {
            builder.AppendLine()
        }
    }

    // ---- statements ------------------------------------------------------------------------------

    // THE STATEMENT ARMS: twenty-nine of them, in the order the C# `switch` tested them.
    //
    // The order is preserved even though no two statement types are related by inheritance — every
    // one derives directly from `Statement` — because a reordering that is safe today would stop
    // being safe the day a statement type gains a subclass, and nothing is gained by it.
    //
    // TWO ARMS ARE NOT `switch` ARMS AT ALL AND BOTH ARE DELIBERATE: `EmptyStatement` matches and
    // does NOTHING, so a stray `;` disappears rather than emitting a blank line; and the final
    // `throw` is the formatter's contract, because a statement it cannot spell must fail loudly
    // rather than emit text that will not parse back.
    func FormatStatement(statement: Statement, builder: StringBuilder) {
        expressionStatement := statement as ExpressionStatement
        if expressionStatement != null {
            state.Indent(builder)
            FormatExpression(expressionStatement.Expression, builder)
            builder.AppendLine()
            return
        }

        variableDeclaration := statement as VariableDeclarationStatement
        if variableDeclaration != null {
            state.Indent(builder)
            // THE TYPE IS FORMATTED BEFORE THE KEYWORD BECAUSE THE KEYWORD DEPENDS ON IT. `let` is
            // not recoverable from `Kind` — `let x: T = v` and `x: T = v` are the same kind — so the
            // arm asks two questions: did the author write it, and would the shorter spelling read
            // back? The second is a question about the type's own text.
            declaredTypeText: string? = null
            if variableDeclaration.Type != null {
                declaredTypeText = FormatterSyntaxText.FormatTypeReference(variableDeclaration.Type)
            }

            if variableDeclaration.Kind == VariableKind.Const {
                builder.Append("const ")
            } else if variableDeclaration.Kind == VariableKind.Readonly {
                builder.Append("readonly ")
            } else if variableDeclaration.HasLetKeyword || (declaredTypeText != null && FormatterSyntaxText.TypedDeclarationNeedsLet(declaredTypeText, variableDeclaration.Initializer != null)) {
                // The first clause is PRESERVATION and the second is SOUNDNESS; either alone leaves a
                // hole. Without the first, `let n: int = 3` silently loses its keyword. Without the
                // second, a tree built by hand — or by any path that does not stamp the flag — writes
                // a tuple-typed local in a spelling the parser then refuses.
                builder.Append("let ")
            }

            builder.Append(variableDeclaration.Name)
            if declaredTypeText != null {
                builder.Append(": ")
                builder.Append(declaredTypeText)
            }

            if variableDeclaration.Initializer != null {
                // `:=` infers, `=` assigns to a written type. The distinction is the declaration's
                // whole syntax and is decided by the presence of the type, not by the initializer.
                if variableDeclaration.Type == null {
                    builder.Append(" := ")
                } else {
                    builder.Append(" = ")
                }

                FormatExpression(variableDeclaration.Initializer, builder)
            }

            builder.AppendLine()
            return
        }

        tupleDeclaration := statement as TupleDeconstructionStatement
        if tupleDeclaration != null {
            state.Indent(builder)
            builder.Append(string.Join(", ", tupleDeclaration.Names))
            builder.Append(" := ")
            FormatExpression(tupleDeclaration.Initializer, builder)
            builder.AppendLine()
            return
        }

        blockStatement := statement as BlockStatement
        if blockStatement != null {
            state.Indent(builder)
            builder.AppendLine("{")
            state.Push()
            FormatBlock(blockStatement, builder)
            state.Pop()
            state.Indent(builder)
            builder.AppendLine("}")
            return
        }

        allocBlock := statement as AllocBlockStatement
        if allocBlock != null {
            FormatKeywordBlock("alloc", allocBlock.Body, builder)
            return
        }

        allowBlock := statement as AllowStatement
        if allowBlock != null {
            FormatKeywordBlock("allow(" + FormatterSyntaxText.FormatAllowArguments(allowBlock) + ")", allowBlock.Body, builder)
            return
        }

        unsafeBlock := statement as UnsafeBlockStatement
        if unsafeBlock != null {
            FormatKeywordBlock("unsafe", unsafeBlock.Body, builder)
            return
        }

        ifStatement := statement as IfStatement
        if ifStatement != null {
            state.Indent(builder)
            FormatIfStatement(ifStatement, builder)
            return
        }

        forStatement := statement as ForStatement
        if forStatement != null {
            // A `for x in xs` parses as a three-null `for` wrapping a foreach, and must print back
            // as `for x in xs` rather than as an empty C-style header around a nested loop.
            if forStatement.Initializer == null && forStatement.Condition == null && forStatement.Iterator == null {
                forInBody := forStatement.Body as ForeachStatement
                if forInBody != null {
                    state.Indent(builder)
                    FormatForeachBody(forInBody, builder)
                    return
                }
            }

            state.Indent(builder)
            builder.Append("for ")
            initializer := forStatement.Initializer
            if initializer != null {
                initializerDeclaration := initializer as VariableDeclarationStatement
                if initializerDeclaration != null {
                    builder.Append(initializerDeclaration.Name)
                    if initializerDeclaration.Type != null {
                        builder.Append(": ")
                        builder.Append(FormatterSyntaxText.FormatTypeReference(initializerDeclaration.Type))
                    }

                    if initializerDeclaration.Initializer != null {
                        if initializerDeclaration.Type == null {
                            builder.Append(" := ")
                        } else {
                            builder.Append(" = ")
                        }

                        FormatExpression(initializerDeclaration.Initializer, builder)
                    }
                } else {
                    // The only other initializer the parser produces is an expression statement,
                    // and the C# spelled this as a HARD CAST to one — so an unexpected shape threw
                    // `InvalidCastException`, and that observable type is reproduced rather than
                    // improved. A hard cast to a user-declared reference type declines against the
                    // pinned toolset (`emit.local.initializer`), proved by an isolated probe, so
                    // the test is written out and the exception is thrown by hand. The MESSAGE is
                    // this owner's own — the CLR's cast message cannot be reproduced without the
                    // cast that raises it — and that difference is declared, not hidden.
                    initializerExpression := initializer as ExpressionStatement
                    if initializerExpression == null {
                        throw new InvalidCastException("Formatter cannot cast a for-initializer of type " + StatementTypeName(initializer) + " to ExpressionStatement.")
                    }

                    FormatExpression(initializerExpression.Expression, builder)
                }
            }

            builder.Append("; ")
            if forStatement.Condition != null {
                FormatExpression(forStatement.Condition, builder)
            }

            builder.Append("; ")
            if forStatement.Iterator != null {
                FormatExpression(forStatement.Iterator, builder)
            }

            builder.AppendLine(" {")
            state.Push()
            forBlock := forStatement.Body as BlockStatement
            if forBlock != null {
                FormatBlock(forBlock, builder)
            } else {
                FormatStatement(forStatement.Body, builder)
            }

            state.Pop()
            state.Indent(builder)
            builder.AppendLine("}")
            return
        }

        foreachStatement := statement as ForeachStatement
        if foreachStatement != null {
            state.Indent(builder)
            FormatForeachBody(foreachStatement, builder)
            return
        }

        awaitForeach := statement as AwaitForEachStatement
        if awaitForeach != null {
            state.Indent(builder)
            builder.Append("await foreach ")
            builder.Append(awaitForeach.VariableName)
            builder.Append(" in ")
            FormatExpression(awaitForeach.Collection, builder)
            builder.AppendLine(" {")
            state.Push()
            awaitForeachBlock := awaitForeach.Body as BlockStatement
            if awaitForeachBlock != null {
                FormatBlock(awaitForeachBlock, builder)
            } else {
                FormatStatement(awaitForeach.Body, builder)
            }

            state.Pop()
            state.Indent(builder)
            builder.AppendLine("}")
            return
        }

        whileStatement := statement as WhileStatement
        if whileStatement != null {
            state.Indent(builder)
            builder.Append("while ")
            FormatExpression(whileStatement.Condition, builder)
            builder.AppendLine(" {")
            state.Push()
            whileBlock := whileStatement.Body as BlockStatement
            if whileBlock != null {
                FormatBlock(whileBlock, builder)
            } else {
                FormatStatement(whileStatement.Body, builder)
            }

            state.Pop()
            state.Indent(builder)
            builder.AppendLine("}")
            return
        }

        returnStatement := statement as ReturnStatement
        if returnStatement != null {
            state.Indent(builder)
            builder.Append("return")
            if returnStatement.Value != null {
                builder.Append(" ")
                FormatExpression(returnStatement.Value, builder)
            }

            builder.AppendLine()
            return
        }

        yieldStatement := statement as YieldStatement
        if yieldStatement != null {
            state.Indent(builder)
            if yieldStatement.Value != null {
                builder.Append("yield ")
                FormatExpression(yieldStatement.Value, builder)
            } else {
                builder.Append("yield break")
            }

            builder.AppendLine()
            return
        }

        breakStatement := statement as BreakStatement
        if breakStatement != null {
            state.Indent(builder)
            builder.AppendLine("break")
            return
        }

        continueStatement := statement as ContinueStatement
        if continueStatement != null {
            state.Indent(builder)
            builder.AppendLine("continue")
            return
        }

        throwStatement := statement as ThrowStatement
        if throwStatement != null {
            state.Indent(builder)
            builder.Append("throw ")
            FormatExpression(throwStatement.Expression, builder)
            builder.AppendLine()
            return
        }

        printStatement := statement as PrintStatement
        if printStatement != null {
            state.Indent(builder)
            builder.Append("print ")
            FormatExpression(printStatement.Value, builder)
            builder.AppendLine()
            return
        }

        offStatement := statement as OffStatement
        if offStatement != null {
            state.Indent(builder)
            builder.Append("off ")
            FormatExpression(offStatement.Handle, builder)
            builder.AppendLine()
            return
        }

        tryStatement := statement as TryStatement
        if tryStatement != null {
            state.Indent(builder)
            builder.AppendLine("try {")
            state.Push()
            FormatBlock(tryStatement.TryBlock, builder)
            state.Pop()
            state.Indent(builder)
            builder.Append("}")

            // Every clause continues the SAME line the closing brace ended, which is why the arms
            // append `}` without a newline and the single `AppendLine` comes after all of them.
            clauseIndex := 0
            while clauseIndex < tryStatement.CatchClauses.Count {
                catchClause := tryStatement.CatchClauses[clauseIndex]
                builder.Append(" catch")
                exceptionType := catchClause.ExceptionType
                if exceptionType != null {
                    variableName := catchClause.VariableName
                    if variableName != null {
                        builder.Append(" ")
                        builder.Append(variableName)
                        builder.Append(": ")
                        builder.Append(FormatterSyntaxText.FormatTypeReference(exceptionType))
                    } else {
                        builder.Append(" (")
                        builder.Append(FormatterSyntaxText.FormatTypeReference(exceptionType))
                        builder.Append(")")
                    }
                }

                builder.AppendLine(" {")
                state.Push()
                FormatBlock(catchClause.Block, builder)
                state.Pop()
                state.Indent(builder)
                builder.Append("}")
                clauseIndex = clauseIndex + 1
            }

            if tryStatement.FinallyBlock != null {
                builder.AppendLine(" finally {")
                state.Push()
                FormatBlock(tryStatement.FinallyBlock, builder)
                state.Pop()
                state.Indent(builder)
                builder.Append("}")
            }

            builder.AppendLine()
            return
        }

        usingStatement := statement as UsingStatement
        if usingStatement != null {
            state.Indent(builder)
            builder.Append("using ")
            usingDeclaration := usingStatement.Declaration
            if usingDeclaration != null {
                builder.Append(usingDeclaration.Name)
                if usingDeclaration.Type != null {
                    builder.Append(": ")
                    builder.Append(FormatterSyntaxText.FormatTypeReference(usingDeclaration.Type))
                }

                // A `using` declaration always writes `=`, never `:=`, even with no type — which is
                // the C# exactly and is not the variable-declaration rule above.
                if usingDeclaration.Initializer != null {
                    builder.Append(" = ")
                    FormatExpression(usingDeclaration.Initializer, builder)
                }
            } else if usingStatement.Expression != null {
                FormatExpression(usingStatement.Expression, builder)
            }

            if usingStatement.Body != null {
                builder.AppendLine(" {")
                state.Push()
                usingBlock := usingStatement.Body as BlockStatement
                if usingBlock != null {
                    FormatBlock(usingBlock, builder)
                } else {
                    FormatStatement(usingStatement.Body, builder)
                }

                state.Pop()
                state.Indent(builder)
                builder.AppendLine("}")
            } else {
                builder.AppendLine()
            }

            return
        }

        lockStatement := statement as LockStatement
        if lockStatement != null {
            state.Indent(builder)
            builder.Append("lock ")
            FormatExpression(lockStatement.LockObject, builder)
            builder.AppendLine(" {")
            state.Push()
            FormatBlock(lockStatement.Body, builder)
            state.Pop()
            state.Indent(builder)
            builder.AppendLine("}")
            return
        }

        switchStatement := statement as SwitchStatement
        if switchStatement != null {
            state.Indent(builder)
            builder.Append("switch ")
            FormatExpression(switchStatement.Value, builder)
            builder.AppendLine(" {")
            state.Push()
            caseIndex := 0
            while caseIndex < switchStatement.Cases.Count {
                caseClause := switchStatement.Cases[caseIndex]
                state.Indent(builder)
                casePattern := caseClause.Pattern
                // THE LABEL IS AN ARROW, NOT A C# COLON. The grammar demands `=>` after every
                // `case` pattern and after `default` (ColumnarParserRecovery's switch arm), so a
                // colon here is output that cannot re-parse. The body is ALWAYS braced: an
                // unbraced arrow body carries exactly one statement, while the parser flattens a
                // braced block into the case's statement list — so braces round-trip any
                // statement count without adding or dropping a BlockStatement.
                if casePattern != null {
                    builder.Append("case ")
                    FormatPattern(casePattern, builder)
                    builder.AppendLine(" => {")
                } else {
                    builder.AppendLine("default => {")
                }

                state.Push()
                caseStatementIndex := 0
                while caseStatementIndex < caseClause.Statements.Count {
                    FormatStatement(caseClause.Statements[caseStatementIndex], builder)
                    caseStatementIndex = caseStatementIndex + 1
                }

                state.Pop()
                state.Indent(builder)
                builder.AppendLine("}")
                caseIndex = caseIndex + 1
            }

            state.Pop()
            state.Indent(builder)
            builder.AppendLine("}")
            return
        }

        localFunction := statement as LocalFunctionStatement
        if localFunction != null {
            FormatFunction(localFunction.Function, builder)
            return
        }

        assertStatement := statement as AssertStatement
        if assertStatement != null {
            state.Indent(builder)
            builder.Append("assert ")
            FormatExpression(assertStatement.Condition, builder)
            if assertStatement.Message != null {
                builder.Append(", ")
                FormatExpression(assertStatement.Message, builder)
            }

            builder.AppendLine()
            return
        }

        assertThrows := statement as AssertThrowsStatement
        if assertThrows != null {
            state.Indent(builder)
            builder.Append("assert throws ")
            builder.Append(FormatterSyntaxText.FormatTypeReference(assertThrows.ExceptionType))
            builder.AppendLine(" {")
            state.Push()
            FormatBlock(assertThrows.Body, builder)
            state.Pop()
            state.Indent(builder)
            builder.AppendLine("}")
            return
        }

        preprocessor := statement as PreprocessorDirective
        if preprocessor != null {
            state.Indent(builder)
            builder.AppendLine(preprocessor.Directive)
            return
        }

        // An empty statement is matched and emits nothing at all. It is a separate arm from the
        // throw below on purpose: silence here is a decision, not a gap.
        emptyStatement := statement as EmptyStatement
        if emptyStatement != null {
            return
        }

        ThrowUnhandled("statement", statement)
    }

    // `for x in xs { … }` — the canonical N# loop. A `foreach` in the tree prints as `for … in …`
    // because that is the only spelling the language has.
    func FormatForeachBody(foreachStatement: ForeachStatement, builder: StringBuilder) {
        builder.Append("for ")
        builder.Append(foreachStatement.VariableName)
        builder.Append(" in ")
        FormatExpression(foreachStatement.Collection, builder)
        builder.AppendLine(" {")
        state.Push()

        foreachBlock := foreachStatement.Body as BlockStatement
        if foreachBlock != null {
            FormatBlock(foreachBlock, builder)
        } else {
            FormatStatement(foreachStatement.Body, builder)
        }

        state.Pop()
        state.Indent(builder)
        builder.AppendLine("}")
    }

    // ---- expressions -----------------------------------------------------------------------------

    // THE EXPRESSION ARMS: forty-one of them, in the order the C# `switch` tested them.
    //
    // THIS WALK ADDS NO PARENTHESES OF ITS OWN. A `ParenthesizedExpression` in the tree prints its
    // parentheses and nothing else does, which is why the parser keeps that node instead of folding
    // it away: the formatter's output has to re-parse to the same tree, and precedence recovered by
    // re-deriving brackets would not be the source the author wrote.
    func FormatExpression(expression: Expression, builder: StringBuilder) {
        // A NUMERIC LITERAL IS WRITTEN AS THE AUTHOR SPELLED IT. `Lexer.ReadNumber` drops digit
        // separators so that `Parse` sees a numeral it accepts, so `Value` alone cannot spell
        // `2_147_483_647`, `0x7fff_ffff` or `1_2.5_0e1D` back — the formatter rewrote all three, which
        // is the same defect class as writing a raw string's content without its delimiters: the file
        // still compiles to the same program and the author's source is gone. `Spelling` is null for
        // every numeral that has no separators, so the common arm is unchanged.
        intLiteral := expression as IntLiteralExpression
        if intLiteral != null {
            intSpelling := intLiteral.Spelling
            if intSpelling != null {
                builder.Append(intSpelling)
            } else {
                builder.Append(intLiteral.Value)
            }

            return
        }

        floatLiteral := expression as FloatLiteralExpression
        if floatLiteral != null {
            floatSpelling := floatLiteral.Spelling
            if floatSpelling != null {
                builder.Append(floatSpelling)
            } else {
                builder.Append(floatLiteral.Value)
            }

            return
        }

        charLiteral := expression as CharLiteralExpression
        if charLiteral != null {
            builder.Append(charLiteral.Value)
            return
        }

        stringLiteral := expression as StringLiteralExpression
        if stringLiteral != null {
            // AN ORDINARY LITERAL'S `Value` CARRIES ITS OWN QUOTES AND A RAW LITERAL'S DOES NOT, so
            // the raw arm writes the delimiters back and the ordinary arm must not. Writing the raw
            // content bare is not a formatting infelicity — it emits an IDENTIFIER where the author
            // wrote a string, and wherever that identifier is itself a legal expression BOTH of
            // `FormatSafe`'s gates pass and the file is rewritten. `v := """abc"""` became
            // `v := abc` on disk, and through `DocumentFormattingHandler` on format-on-save.
            //
            // THE RE-EMISSION IS EXACT, WHICH IS WHY NOTHING IS RE-SYNTHESISED. N# raw strings do
            // not strip a common indent (the content is everything between the delimiters, leading
            // newline included), and `Lexer.ReadTripleQuoteString` TERMINATES AT THE FIRST `"""`, so
            // a token's content provably contains no `"""` and provably does not end in a quote.
            // `"""` + content + `"""` is therefore the author's own bytes, character for character.
            if stringLiteral.IsRaw {
                builder.Append("\"\"\"")
                builder.Append(stringLiteral.Value)
                builder.Append("\"\"\"")
            } else {
                builder.Append(stringLiteral.Value)
            }

            return
        }

        interpolated := expression as InterpolatedStringExpression
        if interpolated != null {
            // A literal's `Value` already carries its quotes; an interpolated string is stored
            // decomposed, so this arm writes the delimiters back itself.
            if interpolated.IsRaw {
                builder.Append("$\"\"\"")
            } else {
                builder.Append("$\"")
            }

            partIndex := 0
            while partIndex < interpolated.Parts.Count {
                part := interpolated.Parts[partIndex]

                textPart := part as InterpolatedStringText
                if textPart != null {
                    if interpolated.IsRaw {
                        // A raw string's braces are literal in source and have to be doubled to
                        // survive a round trip through the non-raw reader.
                        rawText := textPart.Text
                        escaped := rawText.Replace("{", "{{", StringComparison.Ordinal)
                        escaped = escaped.Replace("}", "}}", StringComparison.Ordinal)
                        builder.Append(escaped)
                    } else {
                        builder.Append(textPart.Text)
                    }
                } else {
                    holePart := part as InterpolatedStringHole
                    if holePart != null {
                        builder.Append('{')
                        FormatExpression(holePart.Expression, builder)
                        formatClause := holePart.FormatClause
                        if formatClause != null {
                            builder.Append(':')
                            builder.Append(formatClause)
                        }

                        builder.Append('}')
                    }
                }

                partIndex = partIndex + 1
            }

            if interpolated.IsRaw {
                builder.Append("\"\"\"")
            } else {
                builder.Append("\"")
            }

            return
        }

        boolLiteral := expression as BoolLiteralExpression
        if boolLiteral != null {
            if boolLiteral.Value {
                builder.Append("true")
            } else {
                builder.Append("false")
            }

            return
        }

        nullLiteral := expression as NullLiteralExpression
        if nullLiteral != null {
            builder.Append("null")
            return
        }

        identifier := expression as IdentifierExpression
        if identifier != null {
            builder.Append(identifier.Name)
            return
        }

        binary := expression as BinaryExpression
        if binary != null {
            FormatExpression(binary.Left, builder)
            builder.Append(" ")
            builder.Append(OperatorFacts.GetRequiredBinaryText(binary.Operator))
            builder.Append(" ")
            FormatExpression(binary.Right, builder)
            return
        }

        unary := expression as UnaryExpression
        if unary != null {
            // The two postfix operators are the only ones written after their operand, and the
            // enum is what decides it — the operator TEXT is the same either way.
            if unary.Operator == UnaryOperator.PostIncrement || unary.Operator == UnaryOperator.PostDecrement {
                FormatExpression(unary.Operand, builder)
                builder.Append(OperatorFacts.GetRequiredUnaryText(unary.Operator))
            } else {
                builder.Append(OperatorFacts.GetRequiredUnaryText(unary.Operator))
                FormatExpression(unary.Operand, builder)
            }

            return
        }

        mustExpression := expression as MustExpression
        if mustExpression != null {
            builder.Append("must ")
            FormatExpression(mustExpression.Expression, builder)
            return
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            FormatExpression(memberAccess.Object, builder)
            if memberAccess.IsNullConditional {
                builder.Append("?.")
            } else {
                builder.Append(".")
            }

            builder.Append(memberAccess.MemberName)
            return
        }

        indexAccess := expression as IndexAccessExpression
        if indexAccess != null {
            FormatExpression(indexAccess.Object, builder)
            if indexAccess.IsNullConditional {
                builder.Append("?[")
            } else {
                builder.Append("[")
            }

            FormatExpression(indexAccess.Index, builder)
            builder.Append("]")
            return
        }

        call := expression as CallExpression
        if call != null {
            FormatExpression(call.Callee, builder)
            typeArguments := call.TypeArguments
            if typeArguments != null && typeArguments.Count > 0 {
                builder.Append("<")
                FormatterSyntaxText.AppendTypeList(builder, typeArguments, ", ")
                builder.Append(">")
            }

            // The call's own span IS its argument list's span: the node is anchored on the `(` and
            // stamped with the `)`.
            FormatArgumentList(call.Arguments, call.Line, call.EndLine, builder)
            return
        }

        assignment := expression as AssignmentExpression
        if assignment != null {
            FormatExpression(assignment.Target, builder)
            builder.Append(" ")
            builder.Append(OperatorFacts.GetRequiredAssignmentText(assignment.Operator))
            builder.Append(" ")
            FormatExpression(assignment.Value, builder)
            return
        }

        onSubscription := expression as OnSubscriptionExpression
        if onSubscription != null {
            builder.Append("on ")
            FormatExpression(onSubscription.Target, builder)
            builder.Append(" ")
            FormatExpression(onSubscription.Handler, builder)
            return
        }

        lambda := expression as LambdaExpression
        if lambda != null {
            // ONE INFERRED PARAMETER LOSES ITS BRACKETS AND MORE THAN ONE KEEPS THEM; a single
            // parameter with a WRITTEN type keeps them too, because `x: int => …` would not parse.
            // `var` counts as inferred, which is what lets a tree built by an earlier pass round
            // trip to the shorthand the author wrote.
            allInferred := true
            inferredIndex := 0
            while inferredIndex < lambda.Parameters.Count {
                parameterType := lambda.Parameters[inferredIndex].Type
                if parameterType != null {
                    simpleType := parameterType as SimpleTypeReference
                    if simpleType == null || simpleType.Name != "var" {
                        allInferred = false
                    }
                }

                inferredIndex = inferredIndex + 1
            }

            if lambda.Parameters.Count == 1 && allInferred {
                builder.Append(lambda.Parameters[0].Name)
            } else if lambda.Parameters.Count > 1 && allInferred {
                builder.Append("(")
                nameIndex := 0
                while nameIndex < lambda.Parameters.Count {
                    if nameIndex > 0 {
                        builder.Append(", ")
                    }

                    builder.Append(lambda.Parameters[nameIndex].Name)
                    nameIndex = nameIndex + 1
                }

                builder.Append(")")
            } else {
                builder.Append("(")
                typedIndex := 0
                while typedIndex < lambda.Parameters.Count {
                    FormatParameter(lambda.Parameters[typedIndex], builder)
                    if typedIndex < lambda.Parameters.Count - 1 {
                        builder.Append(", ")
                    }

                    typedIndex = typedIndex + 1
                }

                builder.Append(")")
            }

            builder.Append(" => ")
            if lambda.ExpressionBody != null {
                FormatExpression(lambda.ExpressionBody, builder)
            } else if lambda.BlockBody != null {
                builder.AppendLine("{")
                state.Push()
                FormatBlock(lambda.BlockBody, builder)
                state.Pop()
                state.Indent(builder)
                builder.Append("}")
            }

            return
        }

        ternary := expression as TernaryExpression
        if ternary != null {
            FormatExpression(ternary.Condition, builder)
            builder.Append(" ? ")
            FormatExpression(ternary.ThenExpression, builder)
            builder.Append(" : ")
            FormatExpression(ternary.ElseExpression, builder)
            return
        }

        arrayLiteral := expression as ArrayLiteralExpression
        if arrayLiteral != null {
            if arrayLiteral.IsImmutable {
                builder.Append("#[")
            } else {
                builder.Append("[")
            }

            elementsWrapped := ShouldWrapList(arrayLiteral.Line, arrayLiteral.EndLine, arrayLiteral.Elements.Count, MaxExpressionLine(arrayLiteral.Elements), LastExpressionSpansLines(arrayLiteral.Elements))
            elementTracker := state
            if elementsWrapped {
                state.Push()
                elementTracker.LastEmittedSourceLine = arrayLiteral.Line
            }

            elementIndex := 0
            while elementIndex < arrayLiteral.Elements.Count {
                element := arrayLiteral.Elements[elementIndex]
                if elementsWrapped {
                    builder.AppendLine()
                    state.EmitCommentsBefore(element.Line, builder)
                    state.Indent(builder)
                    elementTracker.LastEmittedSourceLine = element.Line
                }

                FormatExpression(element, builder)
                if elementIndex < arrayLiteral.Elements.Count - 1 {
                    if elementsWrapped {
                        builder.Append(",")
                    } else {
                        builder.Append(", ")
                    }
                }

                elementIndex = elementIndex + 1
            }

            if elementsWrapped {
                builder.AppendLine()
                state.EmitCommentsBefore(arrayLiteral.EndLine, builder)
                state.Pop()
                state.Indent(builder)
            }

            builder.Append("]")
            return
        }

        tuple := expression as TupleExpression
        if tuple != null {
            builder.Append("(")
            tupleIndex := 0
            while tupleIndex < tuple.Elements.Count {
                tupleElement := tuple.Elements[tupleIndex]
                elementName := tupleElement.Name
                if elementName != null {
                    builder.Append(elementName)
                    builder.Append(": ")
                }

                FormatExpression(tupleElement.Value, builder)
                if tupleIndex < tuple.Elements.Count - 1 {
                    builder.Append(", ")
                }

                tupleIndex = tupleIndex + 1
            }

            builder.Append(")")
            return
        }

        newExpression := expression as NewExpression
        if newExpression != null {
            builder.Append("new")
            newType := newExpression.Type
            if newType != null {
                builder.Append(" ")
                // `new int[n]` names the ELEMENT type, not the array type, so an array creation
                // with a length unwraps one level before printing.
                arrayType := newType as ArrayTypeReference
                if newExpression.ArrayLengthExpression != null && arrayType != null {
                    builder.Append(FormatterSyntaxText.FormatTypeReference(arrayType.ElementType))
                } else {
                    builder.Append(FormatterSyntaxText.FormatTypeReference(newType))
                }
            }

            if newExpression.ArrayLengthExpression != null {
                builder.Append("[")
                FormatExpression(newExpression.ArrayLengthExpression, builder)
                builder.Append("]")
            } else if newExpression.ConstructorArguments.Count > 0 || newExpression.Initializer == null {
                // An empty argument list is written unless an object initializer follows, because
                // `new Foo { … }` and `new Foo() { … }` are both valid and the first is canonical.
                //
                // A `new`'s own span is its CONSTRUCTOR ARGUMENT LIST's span and not the whole
                // expression's: `new Foo(a) { X: 1 }` has a flat argument list and a wrapped
                // initializer, and the initializer carries its own braces.
                FormatArgumentList(newExpression.ConstructorArguments, newExpression.Line, newExpression.EndLine, builder)
            }

            if newExpression.Initializer != null {
                FormatObjectInitializer(newExpression.Initializer, builder)
            }

            return
        }

        cast := expression as CastExpression
        if cast != null {
            if cast.Kind == CastKind.Hard {
                builder.Append("(")
                builder.Append(FormatterSyntaxText.FormatTypeReference(cast.TargetType))
                builder.Append(")")
                FormatExpression(cast.Expression, builder)
            } else {
                FormatExpression(cast.Expression, builder)
                builder.Append(" as ")
                builder.Append(FormatterSyntaxText.FormatTypeReference(cast.TargetType))
            }

            return
        }

        isExpression := expression as IsExpression
        if isExpression != null {
            FormatExpression(isExpression.Expression, builder)
            builder.Append(" is ")
            builder.Append(FormatterSyntaxText.FormatTypeReference(isExpression.Type))
            isVariableName := isExpression.VariableName
            if isVariableName != null {
                builder.Append(" ")
                builder.Append(isVariableName)
            }

            return
        }

        matchExpression := expression as MatchExpression
        if matchExpression != null {
            builder.Append("match ")
            FormatExpression(matchExpression.Value, builder)
            builder.AppendLine(" {")
            state.Push()
            matchIndex := 0
            while matchIndex < matchExpression.Cases.Count {
                matchCase := matchExpression.Cases[matchIndex]
                state.Indent(builder)
                FormatPattern(matchCase.Pattern, builder)
                if matchCase.Guard != null {
                    builder.Append(" when ")
                    FormatExpression(matchCase.Guard, builder)
                }

                builder.Append(" => ")
                FormatExpression(matchCase.Expression, builder)

                // Commas separate the cases and the last one has none.
                if matchIndex < matchExpression.Cases.Count - 1 {
                    builder.Append(",")
                }

                builder.AppendLine()
                matchIndex = matchIndex + 1
            }

            state.Pop()
            state.Indent(builder)
            builder.Append("}")
            return
        }

        withExpression := expression as WithExpression
        if withExpression != null {
            FormatExpression(withExpression.Target, builder)
            builder.Append(" with { ")
            withIndex := 0
            while withIndex < withExpression.Properties.Count {
                withProperty := withExpression.Properties[withIndex]
                withPropertyName := withProperty.Name
                if withPropertyName != null {
                    builder.Append(withPropertyName)
                    builder.Append(": ")
                }

                FormatExpression(withProperty.Value, builder)
                if withIndex < withExpression.Properties.Count - 1 {
                    builder.Append(", ")
                }

                withIndex = withIndex + 1
            }

            builder.Append(" }")
            return
        }

        awaitExpression := expression as AwaitExpression
        if awaitExpression != null {
            builder.Append("await ")
            FormatExpression(awaitExpression.Expression, builder)
            return
        }

        throwExpression := expression as ThrowExpression
        if throwExpression != null {
            builder.Append("throw ")
            FormatExpression(throwExpression.Expression, builder)
            return
        }

        typeOfExpression := expression as TypeOfExpression
        if typeOfExpression != null {
            builder.Append("typeof(")
            builder.Append(FormatterSyntaxText.FormatTypeReference(typeOfExpression.Type))
            builder.Append(")")
            return
        }

        nameofExpression := expression as NameofExpression
        if nameofExpression != null {
            builder.Append("nameof(")
            FormatExpression(nameofExpression.Target, builder)
            builder.Append(")")
            return
        }

        sizeOfExpression := expression as SizeOfExpression
        if sizeOfExpression != null {
            builder.Append("sizeof(")
            builder.Append(FormatterSyntaxText.FormatTypeReference(sizeOfExpression.Type))
            builder.Append(")")
            return
        }

        thisExpression := expression as ThisExpression
        if thisExpression != null {
            builder.Append("this")
            return
        }

        baseExpression := expression as BaseExpression
        if baseExpression != null {
            builder.Append("base")
            return
        }

        rangeExpression := expression as RangeExpression
        if rangeExpression != null {
            // Both ends are optional and `..` alone is a whole range, so neither side is guarded
            // by the other.
            if rangeExpression.Start != null {
                FormatExpression(rangeExpression.Start, builder)
            }

            builder.Append("..")
            if rangeExpression.End != null {
                FormatExpression(rangeExpression.End, builder)
            }

            return
        }

        spread := expression as SpreadExpression
        if spread != null {
            builder.Append("...")
            FormatExpression(spread.Expression, builder)
            return
        }

        checkedExpression := expression as CheckedExpression
        if checkedExpression != null {
            builder.Append("checked(")
            FormatExpression(checkedExpression.Expression, builder)
            builder.Append(")")
            return
        }

        uncheckedExpression := expression as UncheckedExpression
        if uncheckedExpression != null {
            builder.Append("unchecked(")
            FormatExpression(uncheckedExpression.Expression, builder)
            builder.Append(")")
            return
        }

        defaultExpression := expression as DefaultExpression
        if defaultExpression != null {
            builder.Append("default")
            return
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            builder.Append("(")
            FormatExpression(parenthesized.Inner, builder)
            builder.Append(")")
            return
        }

        ThrowUnhandled("expression", expression)
    }

    // ---- patterns --------------------------------------------------------------------------------

    // THE PATTERN ARMS: thirteen of them, in the order the C# `switch` tested them.
    //
    // A pattern never touches the indent depth or the comment cursor — it is always written inside
    // one line of a `case`, a `match` arm or an `is`. It reaches `FormatExpression` for the literal
    // and relational arms, which is the edge that puts it inside this walk's cycle.
    func FormatPattern(pattern: Pattern, builder: StringBuilder) {
        identifierPattern := pattern as IdentifierPattern
        if identifierPattern != null {
            builder.Append(identifierPattern.Name)
            return
        }

        literalPattern := pattern as LiteralPattern
        if literalPattern != null {
            FormatExpression(literalPattern.Literal, builder)
            return
        }

        unionCase := pattern as UnionCasePattern
        if unionCase != null {
            builder.Append(unionCase.CaseName)
            caseProperties := unionCase.Properties
            if caseProperties != null && caseProperties.Count > 0 {
                builder.Append(" { ")
                propertyIndex := 0
                while propertyIndex < caseProperties.Count {
                    FormatPropertyPattern(caseProperties[propertyIndex], builder)
                    if propertyIndex < caseProperties.Count - 1 {
                        builder.Append(", ")
                    }

                    propertyIndex = propertyIndex + 1
                }

                builder.Append(" }")
            }

            return
        }

        relational := pattern as RelationalPattern
        if relational != null {
            // The operator is stored as its own text, so it is written straight out rather than
            // routed through `OperatorFacts`.
            builder.Append(relational.Operator)
            builder.Append(" ")
            FormatExpression(relational.Value, builder)
            return
        }

        andPattern := pattern as AndPattern
        if andPattern != null {
            FormatPattern(andPattern.Left, builder)
            builder.Append(" and ")
            FormatPattern(andPattern.Right, builder)
            return
        }

        orPattern := pattern as OrPattern
        if orPattern != null {
            FormatPattern(orPattern.Left, builder)
            builder.Append(" or ")
            FormatPattern(orPattern.Right, builder)
            return
        }

        notPattern := pattern as NotPattern
        if notPattern != null {
            builder.Append("not ")
            FormatPattern(notPattern.Pattern, builder)
            return
        }

        positional := pattern as PositionalPattern
        if positional != null {
            builder.Append("(")
            positionalIndex := 0
            while positionalIndex < positional.Patterns.Count {
                FormatPattern(positional.Patterns[positionalIndex], builder)
                if positionalIndex < positional.Patterns.Count - 1 {
                    builder.Append(", ")
                }

                positionalIndex = positionalIndex + 1
            }

            builder.Append(")")
            return
        }

        objectPattern := pattern as ObjectPattern
        if objectPattern != null {
            builder.Append("{ ")
            objectIndex := 0
            while objectIndex < objectPattern.Properties.Count {
                FormatPropertyPattern(objectPattern.Properties[objectIndex], builder)
                if objectIndex < objectPattern.Properties.Count - 1 {
                    builder.Append(", ")
                }

                objectIndex = objectIndex + 1
            }

            builder.Append(" }")
            return
        }

        listPattern := pattern as ListPattern
        if listPattern != null {
            builder.Append("[")
            listIndex := 0
            while listIndex < listPattern.Elements.Count {
                FormatPattern(listPattern.Elements[listIndex], builder)
                if listIndex < listPattern.Elements.Count - 1 {
                    builder.Append(", ")
                }

                listIndex = listIndex + 1
            }

            builder.Append("]")
            return
        }

        slicePattern := pattern as SlicePattern
        if slicePattern != null {
            builder.Append("..")
            sliceBinding := slicePattern.BindingName
            if sliceBinding != null {
                builder.Append(" ")
                builder.Append(sliceBinding)
            }

            return
        }

        typePattern := pattern as TypePattern
        if typePattern != null {
            builder.Append(FormatterSyntaxText.FormatTypeReference(typePattern.Type))
            typeBinding := typePattern.BindingName
            if typeBinding != null {
                builder.Append(" ")
                builder.Append(typeBinding)
            }

            return
        }

        ThrowUnhandled("pattern", pattern)
    }

    // One property inside an object or union-case pattern, in one of its THREE shapes:
    // `Name: pattern`, `Name: binding` and — when both are absent — the bare `Name`, which is the
    // shorthand that binds a property to a variable of the same name.
    func FormatPropertyPattern(propertyPattern: PropertyPattern, builder: StringBuilder) {
        builder.Append(propertyPattern.Name)

        if propertyPattern.Pattern != null {
            builder.Append(": ")
            FormatPattern(propertyPattern.Pattern, builder)
            return
        }

        bindingName := propertyPattern.BindingName
        if bindingName != null {
            builder.Append(": ")
            builder.Append(bindingName)
        }
    }

    // ---- object initializers ---------------------------------------------------------------------

    // `{ Prop: value, … }` on one line, or one property per line. THE AUTHOR DECIDES, not the width.
    //
    // THIS ARM USED TO HOLD THE FORMATTER'S ONLY WIDTH RULE — it formatted the inline form into a
    // throwaway builder, measured it against `MaxLineLength` from the column already written, and
    // broke if it did not fit. That rule is deleted with the measurement that served it: the owner's
    // rule is that there is no width limit in the formatter. `max_line_length` is still read out of
    // `.editorconfig` and still round-trips through `RebuildConfig`, so no user configuration breaks;
    // the walk simply no longer consults it.
    //
    // The initializer is anchored on its OWN braces (`ColumnarParserRecovery` stamps the `{` and the
    // `}`), which is what lets `new Foo(\n a) { X: 1 }` keep a flat initializer under a wrapped
    // argument list. A single property is no longer a special case: written on one line it stays on
    // one line however long, and written across lines it is wrapped like any other list.
    func FormatObjectInitializer(initializer: ObjectInitializerExpression, builder: StringBuilder) {
        properties := initializer.Properties
        wrapped := ShouldWrapList(initializer.Line, initializer.EndLine, properties.Count, MaxPropertyLine(properties), LastPropertySpansLines(properties))

        if !wrapped {
            builder.Append(" { ")
            index := 0
            while index < properties.Count {
                AppendPropertyInitializer(properties[index], builder)
                if index < properties.Count - 1 {
                    builder.Append(", ")
                }

                index = index + 1
            }

            builder.Append(" }")
            return
        }

        tracker := state
        builder.Append(" {")
        state.Push()
        tracker.LastEmittedSourceLine = initializer.Line
        multiIndex := 0
        while multiIndex < properties.Count {
            multiProperty := properties[multiIndex]
            builder.AppendLine()
            state.EmitCommentsBefore(PropertyInitializerLine(multiProperty), builder)
            state.Indent(builder)
            tracker.LastEmittedSourceLine = PropertyInitializerLine(multiProperty)
            AppendPropertyInitializer(multiProperty, builder)
            if multiIndex < properties.Count - 1 {
                builder.Append(",")
            }

            multiIndex = multiIndex + 1
        }

        builder.AppendLine()
        state.EmitCommentsBefore(initializer.EndLine, builder)
        state.Pop()
        state.Indent(builder)
        builder.Append("}")
    }

    // One member: `Name: value`, `[index] = value`, or a bare element in a collection initializer.
    //
    // `IsIndexerInitializer` IS `IndexExpression != null`, so the C# spelled the guard as the property
    // and then wrote `!` at the use. The null test is written directly here instead: it is the same
    // condition, and the checker can see it. (The `!` shape reports NL202 on the live tree — caught by
    // the live-tree check, not by the build.)
    func AppendPropertyInitializer(property: PropertyInitializer, builder: StringBuilder) {
        propertyName := property.Name
        if propertyName != null {
            builder.Append(propertyName)
            builder.Append(": ")
        }

        indexExpression := property.IndexExpression
        if indexExpression != null {
            builder.Append("[")
            FormatExpression(indexExpression, builder)
            builder.Append("] = ")
        }

        FormatExpression(property.Value, builder)
    }

    // A member's line. `NameLine` is the name's own anchor and is 0 for a bare collection element or
    // an indexer member, so the VALUE's line is the fallback — the two agree wherever both exist.
    static func PropertyInitializerLine(property: PropertyInitializer): int {
        if property.NameLine > 0 {
            return property.NameLine
        }

        return property.Value.Line
    }

    static func MaxPropertyLine(properties: List<PropertyInitializer>): int {
        highest := 0
        index := 0
        while index < properties.Count {
            propertyLine := PropertyInitializerLine(properties[index])
            if propertyLine > highest {
                highest = propertyLine
            }

            index = index + 1
        }

        return highest
    }

    static func LastPropertySpansLines(properties: List<PropertyInitializer>): bool {
        if properties.Count == 0 {
            return false
        }

        return ExpressionSpansLines(properties[properties.Count - 1].Value)
    }

    // The formatter's contract when it meets a node it cannot spell: fail loudly.
    //
    // Emitting a placeholder would produce a `.nl` file that does not parse, and `FormatSafe`'s
    // reparse gate would then reject the whole file with a message about the OUTPUT rather than
    // about the node. The runtime type is read through `as object` because a `GetType()` on a typed
    // receiver declines against the pinned toolset.
    static func ThrowUnhandled(kindName: string, node: object) {
        holder := node as object
        throw new InvalidOperationException("Formatter does not handle " + kindName + " type: " + holder.GetType().Name)
    }

    // The runtime type name of a statement, read through `as object` for the same reason.
    static func StatementTypeName(statement: Statement): string {
        holder := statement as object
        return holder.GetType().Name
    }
}
