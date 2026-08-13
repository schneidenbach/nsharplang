namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import System.Text
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// THE WHOLE ANSWER A CARET AFTER A DOT GETS: WHICH MEMBER ACCESS IT IS IN, WHAT THE TEXT BEFORE
// THE DOT SAYS, AND WHICH MEMBERS THAT RECEIVER OFFERS.
//
// The first two are halves of one question and they are asked on two consecutive lines: find the
// member access the cursor sits in, then render its receiver as the text a completion answer
// shows. Neither half is useful without the other, so they are kept together, and the answer they
// feed — `GetMemberAccessCompletions` at the foot of the file — is kept with them.
//
// THE SEARCH IS DELIBERATELY FUZZY, AND THAT IS THE POLICY. A completion is requested from a
// caret, not from a node, and a caret after a dot is PAST the expression it belongs to — often by
// more than one character, because the editor may send the position before or after the dot and
// the CLI counts columns from one while the AST counts from zero. So the walk tries seven columns
// in a fixed order — the caret itself first, then alternating outward `col-1, col+1, col-2, col+2,
// col-3, col+3` — and, at each, BOTH origins: `(line - 1, candidate - 1)` before `(line,
// candidate)`. The first column that lands on a member access wins, which is why the order is a
// contract and not an implementation detail: a nearer column must never lose to a farther one.
//
// A CALL IS UNWRAPPED ONCE, AND ONLY WHEN ITS CALLEE IS ITSELF A MEMBER ACCESS. `list.Add(` puts
// the caret inside a `CallExpression` whose callee is `list.Add`, and the receiver the user is
// completing is `list`. A call whose callee is a plain identifier — `Frobnicate(` — is NOT a
// member access and the walk keeps looking rather than answering with it.
//
// THE RENDERED TEXT IS SOURCE-SHAPED, NOT SEMANTIC. It is what the user typed, reassembled: an
// identifier answers its name, a dotted chain answers the chain, a call answers `callee()` with
// its arguments dropped, a parenthesised expression answers its inside with the parentheses
// dropped, and every literal answers its own literal text. That text is then handed to
// `CompletionReflectionFacts`, which reads it back to decide whether the receiver named a TYPE or
// a VALUE, so the two files agree on one spelling of a receiver by construction.
//
// THERE ARE EXACTLY TWO WAYS TO ANSWER NOTHING, and both mean "this is not a receiver a completion
// can name": an expression shape outside the thirteen below (a binary operator, an index, a
// lambda), and a call whose own callee cannot be named. A member access whose member name is
// missing or is the parser's `<error>` placeholder is NOT one of them — it answers the receiver
// WITHOUT the dot, which is what makes `person.` complete while the parser is still mid-error.
class CompletionReceiverFacts {

    // The member access the caret is in, or null. `unit` is a `CompilationUnit`; the finder walks
    // it structurally, so it is passed on as the `object` that walk takes.
    static func FindMemberAccessAtPosition(unit: CompilationUnit, line: int, column: int): MemberAccessExpression? {
        candidates := NearbyColumns(column, 3)

        index := 0
        while index < candidates.Count {
            candidateColumn := candidates[index]

            expression := AstNodeFinderCore.FindExpressionAtPosition(unit, line - 1, candidateColumn - 1) as Expression
            if expression == null {
                expression = AstNodeFinderCore.FindExpressionAtPosition(unit, line, candidateColumn) as Expression
            }

            memberAccess := expression as MemberAccessExpression
            if memberAccess != null {
                return memberAccess
            }

            call := expression as CallExpression
            if call != null {
                calleeMemberAccess := call.Callee as MemberAccessExpression
                if calleeMemberAccess != null {
                    return calleeMemberAccess
                }
            }

            index = index + 1
        }

        return null
    }

    // The columns to try, nearest first. A non-positive caret column contributes no column of its
    // own but still searches outward, and a candidate at or below zero is skipped on the left
    // while its mirror on the right is always kept — the AST has no column zero to find.
    static func NearbyColumns(column: int, maxDistance: int): List<int> {
        columns := new List<int>()
        if column > 0 {
            columns.Add(column)
        }

        distance := 1
        while distance <= maxDistance {
            if column - distance > 0 {
                columns.Add(column - distance)
            }

            columns.Add(column + distance)
            distance = distance + 1
        }

        return columns
    }

    // The receiver text of an expression, or null when the shape cannot be named.
    static func FormatReceiverExpression(expression: Expression?): string? {
        if expression == null {
            return null
        }

        identifier := expression as IdentifierExpression
        if identifier != null {
            return identifier.Name
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            return FormatMemberAccessReceiver(memberAccess)
        }

        call := expression as CallExpression
        if call != null {
            callee := FormatReceiverExpression(call.Callee)
            if callee == null {
                return null
            }

            return callee + "()"
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return FormatReceiverExpression(parenthesized.Inner)
        }

        stringLiteral := expression as StringLiteralExpression
        if stringLiteral != null {
            return stringLiteral.Value
        }

        interpolated := expression as InterpolatedStringExpression
        if interpolated != null {
            return FormatInterpolatedStringReceiver(interpolated)
        }

        charLiteral := expression as CharLiteralExpression
        if charLiteral != null {
            return charLiteral.Value
        }

        intLiteral := expression as IntLiteralExpression
        if intLiteral != null {
            return intLiteral.Value
        }

        floatLiteral := expression as FloatLiteralExpression
        if floatLiteral != null {
            return floatLiteral.Value
        }

        boolLiteral := expression as BoolLiteralExpression
        if boolLiteral != null {
            if boolLiteral.Value {
                return "true"
            }

            return "false"
        }

        nullLiteral := expression as NullLiteralExpression
        if nullLiteral != null {
            return "null"
        }

        thisExpression := expression as ThisExpression
        if thisExpression != null {
            return "this"
        }

        baseExpression := expression as BaseExpression
        if baseExpression != null {
            return "base"
        }

        return null
    }

    // An interpolated string reads back as its own literal text with every hole collapsed to
    // `{...}`. The holes are not evaluated and not named: the receiver's TYPE is `string` however
    // they are filled, so the text only has to be recognisable to the reader.
    static func FormatInterpolatedStringReceiver(expression: InterpolatedStringExpression): string {
        builder := new StringBuilder()
        parts := expression.Parts

        index := 0
        while index < parts.Count {
            part := parts[index]

            text := part as InterpolatedStringText
            if text != null {
                builder.Append(text.Text)
            } else {
                hole := part as InterpolatedStringHole
                if hole != null {
                    builder.Append("{...}")
                }
            }

            index = index + 1
        }

        body := builder.ToString()
        if expression.IsRaw {
            return "$\"\"\"" + body + "\"\"\""
        }

        return "$\"" + body + "\""
    }

    // A dotted chain reads back as `receiver.member`. A MISSING OR ERRORED MEMBER NAME ANSWERS THE
    // RECEIVER ALONE rather than nothing — that is the mid-edit case, where the user has typed the
    // dot and the parser has produced a member access with an `<error>` name, and it is exactly
    // the case a completion exists to serve.
    static func FormatMemberAccessReceiver(memberAccess: MemberAccessExpression): string? {
        receiver := FormatReceiverExpression(memberAccess.Object)
        memberName := memberAccess.MemberName
        if receiver == null || string.IsNullOrEmpty(memberName) || memberName == "<error>" {
            return receiver
        }

        return receiver + "." + memberName
    }

    // ── THE ANSWER ITSELF ───────────────────────────────────────────────────────────────────────
    //
    // THREE WAYS TO TYPE A RECEIVER, TRIED IN A FIXED ORDER, AND THE ORDER IS THE POLICY.
    //   1. THE EXPRESSION'S OWN RECORDED TYPE, read at the receiver node's position. This is the
    //      only door that can type a CHAIN — `message.ToUpper().` or `factory.Create().` have no
    //      identifier to look up, and only the analyzer's per-position record knows what they
    //      evaluate to. It is tried first because it is the most specific thing known.
    //   2. THE RECEIVER TEXT AS AN IDENTIFIER, at the position first and then file-wide. This is
    //      the plain `person.` case, and the position-scoped lookup runs before the file-wide one
    //      so an inner shadow beats an outer declaration.
    //   3. THE RECEIVER TEXT AS A LITERAL — `"abc".`, `1.`, `'c'.` — which no model records
    //      because no declaration exists. A literal is always an INSTANCE, never a type name, so
    //      this arm does not ask which half of the type is wanted; it says instance.
    // A DOOR THAT TYPES THE RECEIVER BUT FINDS NO MEMBERS DOES NOT END THE SEARCH: the next door
    // is tried, and only when all three are exhausted is the answer empty. That is what lets a
    // receiver whose recorded type is a bare unknown still be completed as an identifier.
    //
    // `semanticModels` is the project's model collection, needed only to resolve a source-declared
    // type by name; nothing else about a project snapshot is read here.
    static func GetMemberAccessCompletions(unit: CompilationUnit, semanticModel: SemanticModel?, precomputedReceiver: string?, line: int, column: int, semanticModels: IEnumerable<SemanticModel>): CompletionResult {
        memberAccess := FindMemberAccessAtPosition(unit, line, column)
        receiver := precomputedReceiver
        if receiver == null && memberAccess != null {
            receiver = FormatReceiverExpression(memberAccess.Object)
        }

        completions := new Dictionary<string, List<CompletionItem>>()

        if semanticModel != null && memberAccess != null {
            receiverExpression := memberAccess.Object
            receiverType := semanticModel.LookupTypeAtPosition(receiverExpression.Line, receiverExpression.Column)
            if receiverType != null && !BuiltInTypes.IsUnknown(receiverType) {
                displayReceiver := receiver ?? FormatReceiverExpression(receiverExpression) ?? "<expression>"

                filter := CompletionReflectionFacts.GetMemberFilter(displayReceiver, receiverType)
                expressionResult := ResolveMemberCompletions(receiverType, displayReceiver, semanticModels, completions, filter)
                if expressionResult != null {
                    return expressionResult
                }
            }
        }

        if receiver == null {
            return EmptyMemberAccessResult()
        }

        if semanticModel != null {
            typeInfo := semanticModel.LookupIdentifierAtPosition(receiver, line, column)
            if typeInfo == null {
                typeInfo = semanticModel.LookupIdentifier(receiver)
            }

            if typeInfo != null {
                filter := CompletionReflectionFacts.GetMemberFilter(receiver, typeInfo)
                identifierResult := ResolveMemberCompletions(typeInfo, receiver, semanticModels, completions, filter)
                if identifierResult != null {
                    return identifierResult
                }
            }
        }

        literalTypeInfo := CompletionReflectionFacts.ResolveLiteralReceiverType(receiver)
        if literalTypeInfo != null {
            literalResult := ResolveMemberCompletions(literalTypeInfo, receiver, semanticModels, completions, CompletionMemberFilter.InstanceOnly)
            if literalResult != null {
                return literalResult
            }
        }

        return EmptyMemberAccessResult()
    }

    // WHAT A TYPED RECEIVER OFFERS: SOURCE FIRST, METADATA SECOND, AND NOTHING AT ALL IF NEITHER
    // HAS ANYTHING. A source declaration wins outright when it produces items, so `Person.` shows
    // the project's `Person` and never some unrelated loaded type of the same simple name — the
    // rule the Language Server already follows and the reason this ordering is not an accident of
    // how the two lookups were written.
    //
    // THE ANSWERED TYPE NAME COMES FROM WHICHEVER DOOR ANSWERED: the declaration's display text
    // when source answered, and the CLR full name — falling back to the simple name for a type
    // that has none, which is what a generic parameter and an array of one look like — when
    // metadata did. Null means BOTH doors were silent, which is what tells the caller to try the
    // next way of typing the receiver.
    static func ResolveMemberCompletions(typeInfo: TypeInfo, receiver: string, semanticModels: IEnumerable<SemanticModel>, completions: Dictionary<string, List<CompletionItem>>, filter: CompletionMemberFilter): CompletionResult? {
        typeName := CompletionTypeTextFacts.FormatTypeText(typeInfo)

        declaredMembers := CompletionDeclarationFacts.GetTypeMemberItems(typeInfo, semanticModels)
        if declaredMembers.Count > 0 {
            CompletionEngineKernels.AddGroupedCompletionItemsByKind(declaredMembers, completions)
            return new CompletionResult(CompletionContext.MemberAccess, receiver, typeName, completions)
        }

        clrType := CompletionReflectionFacts.ResolveCompletionReflectionType(typeInfo)
        if clrType != null {
            flags := CompletionReflectionFacts.GetReflectionBindingFlags(filter)
            reflectionMembers := CompletionReflectionFacts.BuildReflectionMemberItems(clrType, flags)
            if reflectionMembers.Count > 0 {
                CompletionEngineKernels.AddGroupedCompletionItemsByKind(reflectionMembers, completions)
                clrTypeName := clrType.get_FullName()
                if clrTypeName == null {
                    clrTypeName = clrType.get_Name()
                }

                return new CompletionResult(CompletionContext.MemberAccess, receiver, clrTypeName, completions)
            }
        }

        return null
    }

    // A member-access answer with no members. It still says MemberAccess: the caller asked about a
    // receiver and the honest answer is "that receiver, nothing to offer", not "I do not know what
    // kind of position this is".
    static func EmptyMemberAccessResult(): CompletionResult {
        return new CompletionResult(CompletionContext.MemberAccess, null, null, new Dictionary<string, List<CompletionItem>>())
    }
}
