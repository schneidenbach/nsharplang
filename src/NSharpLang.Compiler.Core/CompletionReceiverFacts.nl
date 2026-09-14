namespace NSharpLang.Compiler.CodeIntelligence

import System
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

        // A CONSTRUCTED GENERIC TYPE RECEIVER reads back as the type the developer WROTE —
        // `Vector<int>`, `Dictionary<string, List<int>>` — which is what the text-scan classifier
        // extracts from the buffer, so the two spellings of a receiver agree by construction here
        // too.
        genericTypeExpression := expression as GenericTypeExpression
        if genericTypeExpression != null {
            return TypeReferenceFacts.GetDisplayName(genericTypeExpression.Type)
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
    //
    // `compilationUnits` is the project's PARSED FILES, and it crosses the boundary for one reason:
    // a member's visibility is a question about PACKAGES, and only a file knows which namespace it
    // wrote its declarations into. A caller with no project — a loose editor buffer, a test holding
    // one `TypeInfo` — passes none, and the six-argument form below says exactly that.
    static func GetMemberAccessCompletions(unit: CompilationUnit, semanticModel: SemanticModel?, precomputedReceiver: string?, line: int, column: int, semanticModels: IEnumerable<SemanticModel>): CompletionResult {
        return GetMemberAccessCompletions(unit, semanticModel, precomputedReceiver, line, column, semanticModels, new List<CompilationUnit>())
    }

    static func GetMemberAccessCompletions(unit: CompilationUnit, semanticModel: SemanticModel?, precomputedReceiver: string?, line: int, column: int, semanticModels: IEnumerable<SemanticModel>, compilationUnits: IEnumerable<CompilationUnit>): CompletionResult {
        return GetMemberAccessCompletions(unit, semanticModel, precomputedReceiver, line, column, semanticModels, compilationUnits, null)
    }

    // `friendGrants` IS THE PROJECT'S OWN `InternalsVisibleToGrants`, or null when the caller has
    // none. A referenced assembly that names this project in an `InternalsVisibleTo` has made its
    // `internal` members bindable — the analyzer has resolved them since friends landed — and a
    // completion that offered only the public surface hid exactly what the compiler would accept.
    static func GetMemberAccessCompletions(unit: CompilationUnit, semanticModel: SemanticModel?, precomputedReceiver: string?, line: int, column: int, semanticModels: IEnumerable<SemanticModel>, compilationUnits: IEnumerable<CompilationUnit>, friendGrants: InternalsVisibleToGrants?): CompletionResult {
        requestingNamespace := CompletionVisibilityFacts.UnitNamespaceName(unit)

        // THE TYPE THE CARET IS WRITTEN INSIDE decides what a written `private` or `protected` lets
        // this list offer. A caret at namespace scope answers null, which offers exactly the public
        // and package surface — the same list this produced before the declared rule existed.
        accessingTypeName := CompletionVisibilityFacts.EnclosingTypeName(unit, line)
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
                // A CONSTRUCTED GENERIC TYPE RECEIVER IS A TYPE NAME, and the shape says so where
                // the TEXT cannot: `IsStaticTypeReceiver` asks whether the receiver is spelled like
                // an exported name, and `Vector<int>` is not spelled like an identifier at all.
                if receiverExpression as GenericTypeExpression != null {
                    filter = CompletionMemberFilter.StaticOnly
                }

                expressionResult := ResolveMemberCompletions(receiverType, displayReceiver, semanticModels, completions, filter, compilationUnits, requestingNamespace, accessingTypeName, friendGrants)
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
                identifierResult := ResolveMemberCompletions(typeInfo, receiver, semanticModels, completions, filter, compilationUnits, requestingNamespace, accessingTypeName, friendGrants)
                if identifierResult != null {
                    return identifierResult
                }
            }
        }

        literalTypeInfo := CompletionReflectionFacts.ResolveLiteralReceiverType(receiver)
        if literalTypeInfo != null {
            literalResult := ResolveMemberCompletions(literalTypeInfo, receiver, semanticModels, completions, CompletionMemberFilter.InstanceOnly, compilationUnits, requestingNamespace, accessingTypeName, friendGrants)
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
    static func ResolveMemberCompletions(typeInfo: TypeInfo, receiver: string, semanticModels: IEnumerable<SemanticModel>, completions: Dictionary<string, List<CompletionItem>>, filter: CompletionMemberFilter, compilationUnits: IEnumerable<CompilationUnit>, requestingNamespace: string): CompletionResult? {
        return ResolveMemberCompletions(typeInfo, receiver, semanticModels, completions, filter, compilationUnits, requestingNamespace, null)
    }

    static func ResolveMemberCompletions(typeInfo: TypeInfo, receiver: string, semanticModels: IEnumerable<SemanticModel>, completions: Dictionary<string, List<CompletionItem>>, filter: CompletionMemberFilter, compilationUnits: IEnumerable<CompilationUnit>, requestingNamespace: string, accessingTypeName: string?): CompletionResult? {
        return ResolveMemberCompletions(typeInfo, receiver, semanticModels, completions, filter, compilationUnits, requestingNamespace, accessingTypeName, null)
    }

    static func ResolveMemberCompletions(typeInfo: TypeInfo, receiver: string, semanticModels: IEnumerable<SemanticModel>, completions: Dictionary<string, List<CompletionItem>>, filter: CompletionMemberFilter, compilationUnits: IEnumerable<CompilationUnit>, requestingNamespace: string, accessingTypeName: string?, friendGrants: InternalsVisibleToGrants?): CompletionResult? {
        typeName := CompletionTypeTextFacts.FormatTypeText(typeInfo)

        // The RECEIVER rule: `protected` is offerable only when the caret's type IS the receiver's
        // type or derives from it. `private` needs the narrower answer, so it is asked separately.
        canReachProtected := CompletionVisibilityFacts.IsTypeOrDerived(accessingTypeName, typeName, compilationUnits)
        isInsideDeclaringType := canReachProtected && CompletionVisibilityFacts.SimpleTypeName(typeName) == CompletionVisibilityFacts.SimpleTypeName(accessingTypeName ?? "")

        declaringNamespace := CompletionVisibilityFacts.DeclaringNamespaceOfReceiverType(typeInfo, typeName, compilationUnits)
        declaredMembers := CompletionDeclarationFacts.GetTypeMemberItems(typeInfo, semanticModels, declaringNamespace, requestingNamespace, canReachProtected, isInsideDeclaringType)
        AppendInheritedMemberItems(typeInfo, semanticModels, filter, compilationUnits, requestingNamespace, accessingTypeName, canReachProtected, friendGrants, declaredMembers)
        if declaredMembers.Count > 0 {
            CompletionEngineKernels.AddGroupedCompletionItemsByKind(declaredMembers, completions)
            return new CompletionResult(CompletionContext.MemberAccess, receiver, typeName, completions)
        }

        clrType := CompletionReflectionFacts.ResolveCompletionReflectionType(typeInfo)
        if clrType != null {
            friendAdmits := CompletionReflectionFacts.FriendAdmits(friendGrants, clrType)
            flags := CompletionReflectionFacts.GetReflectionBindingFlags(filter, false, friendAdmits)
            reflectionMembers := CompletionReflectionFacts.BuildReflectionMemberItems(clrType, flags, false, friendAdmits)
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

    // WHAT THE RECEIVER INHERITS, APPENDED TO WHAT IT DECLARES.
    //
    // A source type's member surface is its own declarations, then its declared base's, and — when
    // the chain ends at a type this compilation did not write — that base's whole reflected surface.
    // The editor used to see only the first of those: `class Names: List<string>` offered its own
    // members and NOTHING else, so a caret after `names.` produced an empty list while the same
    // caret after a `List<string>` local produced fifty. Resolution and `nlc query type` had already
    // walked the chain; completion had not.
    //
    // THE BASE IS TAKEN FROM THE SEMANTIC MODEL, NOT RE-RESOLVED. `AnalyzerTypeResolver` records
    // every type reference it resolves at the reference's own start span, so the `:` clause's
    // already-analyzed `TypeInfo` — with its type arguments closed — is read back by position. That
    // is what lets the reflected half close `List<string>` rather than guess at `List<T>`.
    //
    // A NAME THE DERIVED TYPE ALREADY OFFERS IS NOT OFFERED TWICE. The first list wins, which is the
    // order the language resolves in.
    static func AppendInheritedMemberItems(typeInfo: TypeInfo, semanticModels: IEnumerable<SemanticModel>, filter: CompletionMemberFilter, compilationUnits: IEnumerable<CompilationUnit>, requestingNamespace: string, items: List<CompletionItem>) {
        AppendInheritedMemberItems(typeInfo, semanticModels, filter, compilationUnits, requestingNamespace, null, false, null, items)
    }

    static func AppendInheritedMemberItems(typeInfo: TypeInfo, semanticModels: IEnumerable<SemanticModel>, filter: CompletionMemberFilter, compilationUnits: IEnumerable<CompilationUnit>, requestingNamespace: string, accessingTypeName: string?, canReachProtected: bool, items: List<CompletionItem>) {
        AppendInheritedMemberItems(typeInfo, semanticModels, filter, compilationUnits, requestingNamespace, accessingTypeName, canReachProtected, null, items)
    }

    // A BASE'S `protected` MEMBER IS INHERITED SURFACE, not foreign surface: the same receiver rule
    // that admits it on the derived type admits it here, so the flag the caller already computed is
    // carried down the chain rather than recomputed against each base.
    static func AppendInheritedMemberItems(typeInfo: TypeInfo, semanticModels: IEnumerable<SemanticModel>, filter: CompletionMemberFilter, compilationUnits: IEnumerable<CompilationUnit>, requestingNamespace: string, accessingTypeName: string?, canReachProtected: bool, friendGrants: InternalsVisibleToGrants?, items: List<CompletionItem>) {
        current := typeInfo
        depth := 0
        while depth < 64 {
            baseReference := DeclaredBaseReference(current)
            if baseReference == null {
                return
            }

            baseTypeInfo := RecordedTypeReferenceType(baseReference, semanticModels)
            if baseTypeInfo == null {
                return
            }

            if CompletionDeclarationFacts.DeclaredMembersOfType(baseTypeInfo) != null {
                baseNamespace := CompletionVisibilityFacts.DeclaringNamespaceOfReceiverType(baseTypeInfo, CompletionTypeTextFacts.FormatTypeText(baseTypeInfo), compilationUnits)
                baseTypeName := CompletionTypeTextFacts.FormatTypeText(baseTypeInfo)
                insideBase := accessingTypeName != null && CompletionVisibilityFacts.SimpleTypeName(baseTypeName) == CompletionVisibilityFacts.SimpleTypeName(accessingTypeName)
                AppendNewMemberItems(items, CompletionDeclarationFacts.GetTypeMemberItems(baseTypeInfo, semanticModels, baseNamespace, requestingNamespace, canReachProtected, insideBase))
                current = baseTypeInfo
                depth = depth + 1
                continue
            }

            baseClrType := CompletionReflectionFacts.ResolveCompletionReflectionType(baseTypeInfo)
            if baseClrType == null {
                return
            }

            baseFriendAdmits := CompletionReflectionFacts.FriendAdmits(friendGrants, baseClrType)
            AppendNewMemberItems(items, CompletionReflectionFacts.BuildReflectionMemberItems(baseClrType, CompletionReflectionFacts.GetReflectionBindingFlags(filter, canReachProtected, baseFriendAdmits), canReachProtected, baseFriendAdmits))
            return
        }
    }

    // The `:` clause's class reference, or nothing. Only a CLASS has one; a struct, a record and an
    // interface name no base class, and an interface's own bases are a separate surface.
    static func DeclaredBaseReference(typeInfo: TypeInfo): TypeReference? {
        classType := typeInfo as ClassTypeInfo
        if classType == null {
            return null
        }

        return classType.BaseClass
    }

    // The analyzed type behind a written reference, read back from the model that recorded it.
    static func RecordedTypeReferenceType(typeReference: TypeReference, semanticModels: IEnumerable<SemanticModel>): TypeInfo? {
        span := TypeReferenceFacts.GetStartSpan(typeReference)
        if !span.IsValid {
            return null
        }

        key := (Line: span.StartLine, Column: span.StartColumn)
        for semanticModel in semanticModels {
            recorded: TypeInfo? = null
            if semanticModel.TypeReferenceTypes.TryGetValue(key, out recorded) && recorded != null && !BuiltInTypes.IsUnknown(recorded) {
                return recorded
            }
        }

        return null
    }

    static func AppendNewMemberItems(items: List<CompletionItem>, candidates: List<CompletionItem>) {
        seen := new HashSet<string>(StringComparer.Ordinal)
        existingIndex := 0
        while existingIndex < items.Count {
            seen.Add(items[existingIndex].Name)
            existingIndex = existingIndex + 1
        }

        candidateIndex := 0
        while candidateIndex < candidates.Count {
            candidate := candidates[candidateIndex]
            if !seen.Contains(candidate.Name) {
                items.Add(candidate)
            }

            candidateIndex = candidateIndex + 1
        }
    }

    // A member-access answer with no members. It still says MemberAccess: the caller asked about a
    // receiver and the honest answer is "that receiver, nothing to offer", not "I do not know what
    // kind of position this is".
    static func EmptyMemberAccessResult(): CompletionResult {
        return new CompletionResult(CompletionContext.MemberAccess, null, null, new Dictionary<string, List<CompletionItem>>())
    }
}
