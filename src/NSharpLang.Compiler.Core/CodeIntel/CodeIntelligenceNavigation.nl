namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// WHICH FILE, WHICH NODE, WHICH DECLARATION — THE POSITION HALF OF EVERY NAVIGATION ANSWER.
//
// `CodeIntelligenceTypeResolution` (slice 16) answers "what type is this node"; this file answers
// the question that has to be settled first: which compilation unit the caller meant, which
// expression is under the cursor, and which declaration a position BINDS to. Hover, go-to-
// definition, `nlc query type` and both find-references entry points all funnel through here.
//
// IT COULD NOT MOVE UNTIL `ProjectSnapshot` DID, AND THAT IS A MEASUREMENT RATHER THAN A STORY.
// The closure report over the four type-at-position entry points read `ESCAPES TO (4)` where three
// of the four were `ProjectSnapshot` property reads; over the whole eleven-member family it read
// `ESCAPES TO (5)`, five property reads and NOTHING ELSE. Once the snapshot is an N# type the
// family escapes to nothing at all, which is why it crosses in one piece.
//
// THE FOUR ROUTES TO A TYPE ARE TRIED IN A FIXED ORDER AND THE ORDER IS THE POLICY.
// `TypeAtPosition` asks the DECLARED NAME first (the cursor is on a declaration's own name), then
// the TYPE USE (the cursor is on a type reference), then a BOUND VALUE, and only then the
// EXPRESSION. A declaration beats a use because the user pointed at the definition; a use beats a
// value because a type reference is not a value; and a binding beats an enclosing expression because
// a lambda parameter is not the lambda that contains it. Reordering them is a behaviour change, not
// a refactor.
//
// THE BINDING MAP IS THE ONLY DEFINITION ORACLE. There is no syntactic fallback: a position that
// the analyzer did not bind has no definition, and answering one from a name match would be the
// grep this product exists to replace. Both `DefinitionSymbolAtPosition` and
// `StrictReferenceDeclaration` are therefore the same one lookup, and they are kept as two names
// because the CLI's two commands are two questions.
//
// COLUMN CANDIDATES ARE A KERNEL DECISION, NOT A LOOP HERE. `BindingLookupKernels` decides which
// columns a click could have meant, and a REFUSAL from it is a hard failure rather than an empty
// answer — an unresolvable source is a defect in the caller, and swallowing it would turn a broken
// position into a silent "no results".
//
// THE UNUSED PARAMETER IS GONE. The C# `ResolveTypeUseAtPosition` took a `currentUnit` it never
// read; it was private, so nothing outside could have depended on it, and it is not carried across.
class CodeIntelligenceNavigation {

    // ── Which file ──────────────────────────────────────────────────────
    // TWO MATCHES IN ONE PASS, AND THE SEGMENT-AWARE ONE WINS. `MatchesFilePath` respects path
    // segment boundaries, so `Foo.nl` does not match `MyFoo.nl`; only when no unit matches that way
    // is the project root prepended and an exact key tried. An unmatched query answers with the
    // ORIGINAL text and a null unit, so the caller can report the name the user typed.
    static func FindCompilationUnit(snapshot: ProjectSnapshot, queryFile: string): CompilationUnitMatch {
        for entry in snapshot.CompilationUnits {
            if CodeIntelligenceResultKernels.MatchesFilePath(entry.Key, queryFile) {
                return new CompilationUnitMatch(entry.Key, entry.Value)
            }
        }

        fullPath := Path.GetFullPath(Path.Combine(snapshot.ProjectRoot, queryFile))
        found: CompilationUnit? = null
        if snapshot.CompilationUnits.TryGetValue(fullPath, out found) {
            return new CompilationUnitMatch(fullPath, found)
        }

        return new CompilationUnitMatch(queryFile, null)
    }

    // ── Which node ──────────────────────────────────────────────────────
    // CLI POSITIONS ARE 1-BASED AND THE FINDER HISTORICALLY EXPECTED 0-BASED, so both are tried at
    // every candidate column before the next column is considered. The column order is
    // `NearbyColumns`', which walks OUTWARD from the click, so the nearest node wins over a nearer
    // coordinate system.
    static func FindExpressionAtPositionRobust(cu: CompilationUnit, line: int, col: int): Expression? {
        candidateColumns := CodeIntelligenceSourceDoor.NearbyColumns(col, 3)
        for candidateColumn in candidateColumns {
            expression := AstNodeFinderCore.FindExpressionAtPosition(cu, line - 1, candidateColumn - 1) as Expression
            if expression == null {
                expression = AstNodeFinderCore.FindExpressionAtPosition(cu, line, candidateColumn) as Expression
            }

            if expression != null {
                return expression
            }
        }

        return null
    }

    // THE CALL THE POSITION IS THE CALLEE OF, FOUND AT THE SAME COLUMN THE EXPRESSION WAS.
    //
    // The candidate-column walk above tries several columns and two coordinate bases, and the two
    // questions must be answered by the SAME attempt or they can describe different nodes: a column
    // that finds no expression must not be allowed to contribute a call, and a column that finds one
    // must contribute ITS call and then stop. So the expression is asked first at each candidate and
    // the call only where it answered.
    static func FindEnclosingCallAtPositionRobust(cu: CompilationUnit, line: int, col: int): CallExpression? {
        candidateColumns := CodeIntelligenceSourceDoor.NearbyColumns(col, 3)
        for candidateColumn in candidateColumns {
            zeroBased := AstNodeFinderCore.FindExpressionAtPosition(cu, line - 1, candidateColumn - 1) as Expression
            if zeroBased != null {
                return AstNodeFinderCore.FindCallExpressionAtPosition(cu, line - 1, candidateColumn - 1) as CallExpression
            }

            oneBased := AstNodeFinderCore.FindExpressionAtPosition(cu, line, candidateColumn) as Expression
            if oneBased != null {
                return AstNodeFinderCore.FindCallExpressionAtPosition(cu, line, candidateColumn) as CallExpression
            }
        }

        return null
    }

    // THE CLASS THE POSITION IS INSIDE, FOUND BY THE SAME ATTEMPT THAT FOUND THE EXPRESSION, for the
    // reason the call above is: two answers about one position must describe the same node.
    static func FindEnclosingClassAtPositionRobust(cu: CompilationUnit, line: int, col: int): ClassDeclaration? {
        candidateColumns := CodeIntelligenceSourceDoor.NearbyColumns(col, 3)
        for candidateColumn in candidateColumns {
            zeroBased := AstNodeFinderCore.FindExpressionAtPosition(cu, line - 1, candidateColumn - 1) as Expression
            if zeroBased != null {
                return AstNodeFinderCore.FindEnclosingClassAtPosition(cu, line - 1, candidateColumn - 1) as ClassDeclaration
            }

            oneBased := AstNodeFinderCore.FindExpressionAtPosition(cu, line, candidateColumn) as Expression
            if oneBased != null {
                return AstNodeFinderCore.FindEnclosingClassAtPosition(cu, line, candidateColumn) as ClassDeclaration
            }
        }

        return null
    }

    // THE CALL'S ARGUMENT TYPES, POSITIONALLY, OR NULL WHERE THEY CANNOT BE TRUSTED TO BE.
    //
    // A NAMED ARGUMENT BREAKS THE CORRESPONDENCE the scorer depends on — `f(b: 1, a: "x")` writes
    // its arguments in an order the parameter list does not share — so a call carrying one declines
    // TYPE scoring entirely and is scored on arity alone. That is a narrowing of the evidence, not
    // of the answer: arity still applies, because a named argument still fills a position.
    //
    // An argument whose type nothing can say is left NULL rather than guessed. It scores nothing
    // and costs nothing, so a call with one unknown argument still ranks on the ones it knows.
    static func CallArgumentTypeInfos(call: CallExpression?, semanticModel: SemanticModel?, snapshot: ProjectSnapshot, currentUnit: CompilationUnit): TypeInfo?[]? {
        if call == null {
            return null
        }

        arguments := call.Arguments
        types := new TypeInfo?[](arguments.Count)
        index := 0
        while index < arguments.Count {
            argument := arguments[index]
            if argument.Name != null {
                return new TypeInfo?[](arguments.Count)
            }

            types[index] = CodeIntelligenceTypeResolution.TypeInfoFromExpression(argument.Value, semanticModel, snapshot.CompilationUnits, currentUnit)
            index = index + 1
        }

        return types
    }

    // ── Which declaration ───────────────────────────────────────────────
    static func TryResolveDefinitionViaBindings(snapshot: ProjectSnapshot, filePath: string, line: int, col: int): SymbolDeclaration? {
        bindings := snapshot.Bindings
        if bindings == null {
            return null
        }

        candidateColumns := GetBindingCandidateColumns(snapshot, filePath, line, col)
        declaration: SymbolDeclaration? = null
        if BindingLookupKernels.TryResolveBindingDeclaration(bindings, filePath, line, candidateColumns, out declaration) {
            return declaration
        }

        return null
    }

    static func GetBindingCandidateColumns(snapshot: ProjectSnapshot, filePath: string, line: int, col: int): int[] {
        span := CodeIntelligenceSourceDoor.IdentifierSpanAt(CodeIntelligenceSourceDoor.SourceText(snapshot.SourceTexts, filePath), line, col)
        candidateColumns := new int[](0)
        if !BindingLookupKernels.TryGetBindingCandidateColumns(col, span, out candidateColumns) {
            throw new InvalidOperationException("N# binding candidate column kernel rejected the source.")
        }

        return candidateColumns
    }

    // The definition question and the strict-reference question are the same lookup. Both are kept
    // because `nlc query definition` and `nlc query references` are two commands, and a future
    // difference between them belongs at this seam rather than inside the binding map.
    static func DefinitionSymbolAtPosition(snapshot: ProjectSnapshot, queryFile: string, line: int, col: int): SymbolDeclaration? {
        unitMatch := FindCompilationUnit(snapshot, queryFile)
        if unitMatch.Unit == null {
            return null
        }

        return TryResolveDefinitionViaBindings(snapshot, unitMatch.FilePath, line, col)
    }

    static func StrictReferenceDeclaration(snapshot: ProjectSnapshot, filePath: string, line: int, col: int): SymbolDeclaration? {
        return TryResolveDefinitionViaBindings(snapshot, filePath, line, col)
    }

    // ── Route 2: the type use ───────────────────────────────────────────
    // A BOUND POSITION IS ONLY A TYPE USE WHEN THE DECLARATION IT BINDS TO IS A TYPE. Anything else
    // — a local, a function, a field — falls through to route 3, which is why the kind test is a
    // guard and not a projection. The semantic model refines the ANSWER when it has a type reference
    // recorded at the identifier's own start column; when it does not, the declaration's own name is
    // the resolved type, which is what a type declaration means.
    static func TypeUseAtPosition(snapshot: ProjectSnapshot, filePath: string, semanticModel: SemanticModel?, line: int, col: int): TypeResult? {
        declaration := TryResolveDefinitionViaBindings(snapshot, filePath, line, col)
        if declaration == null || !AnalyzerBindingFacts.IsTypeDeclarationKind(declaration.Kind) {
            return null
        }

        span := CodeIntelligenceSourceDoor.IdentifierSpanAt(CodeIntelligenceSourceDoor.SourceText(snapshot.SourceTexts, filePath), line, col)
        typeInfo: TypeInfo? = null
        // THE GUARD IS NESTED RATHER THAN COMPOUND, AND THAT IS NOT A STYLE CHOICE. Under
        // `if span.HasValue && semanticModel != null` the ANALYZER narrows `span` (so `.Value` is
        // an error) while the EMITTER does not (so `.Item1` declines) — each phase rejects the
        // spelling the other requires. The simple `if span.HasValue { … span.Value … }` shape is
        // the one the shipped kernels use and the only one both phases accept.
        if span.HasValue {
            spanValue := span.Value
            if semanticModel != null {
                typeInfo = semanticModel.LookupTypeReferenceAtPosition(line, spanValue.Item1)
            }
        }

        resolvedType := declaration.Name
        nullability: string? = null
        if typeInfo != null {
            resolvedType = NullabilityMetadataReflection.FormatTypeInfo(typeInfo)
            nullability = NullStateFacts.GetSchemaText(CodeIntelligenceTypeResolution.DefaultNullState(typeInfo))
        }

        declarationFile := declaration.File ?? ""
        location := new LocationResult(CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, declarationFile), declaration.Line, declaration.Column)
        return new TypeResult(declaration.Name, resolvedType, declaration.Kind, location, nullability)
    }

    // ── Route 3: the bound source value ──────────────────────────────────
    // A lambda parameter has a binding declaration and a lexical semantic scope, but no standalone
    // expression node. Asking the expression finder at its name therefore finds the enclosing lambda
    // and reports `(T) -> U` instead of the parameter's `T`. The binding chooses the actual symbol;
    // its own declaration position validates the lexical type before any use-site fact is accepted.
    // A use-site expression type still wins when present so flow narrowing reaches the hover, but a
    // same-named inner scope can never substitute for the binding the cursor actually resolved to.
    // This is deliberately limited to `variable` bindings: functions and members keep their existing
    // expression-specific projections below.
    static func BoundVariableTypeAtPosition(snapshot: ProjectSnapshot, filePath: string, semanticModel: SemanticModel?, line: int, col: int): TypeResult? {
        if semanticModel == null {
            return null
        }

        declaration := TryResolveDefinitionViaBindings(snapshot, filePath, line, col)
        if declaration == null || declaration.Kind != "variable" {
            return null
        }

        declarationFile := declaration.File ?? ""
        if !CodeIntelligenceResultKernels.MatchesFilePath(filePath, declarationFile) {
            return null
        }

        // The binding map and the semantic scope are separate products of analysis. Re-resolving the
        // declaration's exact name span proves the scope fact belongs to this binding rather than to
        // a same-named value that happens to be visible at the query position.
        boundAtDeclaration := TryResolveDefinitionViaBindings(snapshot, declarationFile, declaration.Line, declaration.Column)
        if boundAtDeclaration == null || !boundAtDeclaration.Equals(declaration) {
            return null
        }

        typeInfo := semanticModel.LookupIdentifierAtPosition(declaration.Name, declaration.Line, declaration.Column)
        if typeInfo == null || BuiltInTypes.IsUnknown(typeInfo) {
            return null
        }

        span := CodeIntelligenceSourceDoor.IdentifierSpanAt(CodeIntelligenceSourceDoor.SourceText(snapshot.SourceTexts, filePath), line, col)
        if span.HasValue {
            spanValue := span.Value
            // A declaration name intentionally uses its scoped declaration type: the analyzer records
            // the enclosing lambda at that position, not a parameter expression. A use name may have
            // an exact expression type, whose flow refinement is more precise than the declared type.
            if line != declaration.Line || spanValue.Item1 != declaration.Column {
                useType := semanticModel.LookupTypeAtPosition(line, spanValue.Item1)
                if useType != null && !BuiltInTypes.IsUnknown(useType) {
                    typeInfo = useType
                }
            }
        }

        location := new LocationResult(CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, declarationFile), declaration.Line, declaration.Column)
        resolvedType := NullabilityMetadataReflection.FormatTypeInfo(must typeInfo)
        nullability := NullStateFacts.GetSchemaText(CodeIntelligenceTypeResolution.DefaultNullState(typeInfo))
        return new TypeResult(declaration.Name, resolvedType, declaration.Kind, location, nullability)
    }

    // ── Route 1: the declared name ──────────────────────────────────────
    // THE SELECTED WORD IS READ FROM SOURCE, NOT FROM THE TREE, because a declaration's own name is
    // exactly the text under the cursor and the tree would answer with the enclosing node. A blank
    // selection answers nothing rather than matching the first declaration.
    static func DeclaredNameTypeAtPosition(snapshot: ProjectSnapshot, filePath: string, currentUnit: CompilationUnit, line: int, col: int): TypeResult? {
        selectedName := CodeIntelligenceSourceDoor.WordAt(CodeIntelligenceSourceDoor.SourceText(snapshot.SourceTexts, filePath), line, col)
        selectedWord := selectedName ?? ""
        if string.IsNullOrWhiteSpace(selectedWord) {
            return null
        }

        declarations := currentUnit.Declarations
        for declaration in declarations {
            result := CodeIntelligenceTypeResolution.DeclaredNameTypeInDeclaration(snapshot.ProjectRoot, snapshot.CompilationUnits, filePath, declaration, selectedWord, line)
            if result != null {
                return result
            }
        }

        return null
    }

    // ── Route 4: the expression ─────────────────────────────────────────
    // THE EXPRESSION IS ASKED FIRST AND THE CANDIDATE NAMES ARE THE FALLBACK, and the resolved NAME
    // follows whichever answered: an expression answer keeps the expression's own query name, and a
    // name answer replaces it with the candidate that worked. That is why `resolvedName` is written
    // before the walk and again inside the loop.
    static func TypeInfoAtPosition(expr: Expression?, candidateNames: IReadOnlyList<string>, semanticModel: SemanticModel?, snapshot: ProjectSnapshot, currentUnit: CompilationUnit, out resolvedName: string?): TypeInfo? {
        resolvedName = CodeIntelligenceDisplayText.GetExpressionQueryName(expr)
        fromExpression := CodeIntelligenceTypeResolution.TypeInfoFromExpression(expr, semanticModel, snapshot.CompilationUnits, currentUnit)
        if fromExpression != null {
            return fromExpression
        }

        for candidateName in candidateNames {
            typeInfo := CodeIntelligenceTypeResolution.TypeInfoByName(candidateName, semanticModel, snapshot.CompilationUnits, currentUnit)
            if typeInfo != null {
                resolvedName = candidateName
                return typeInfo
            }
        }

        return null
    }

    // THE ANALYZER'S RECORDED NULL STATE WINS WHEN THERE IS ONE AT THE EXPRESSION'S OWN POSITION.
    // Everything else falls back to what the TYPE alone implies, which is why a nullable annotation
    // still reports `maybe-null` for an expression the flow analysis never reached.
    static func NullabilityForExpression(semanticModel: SemanticModel?, expression: Expression?, typeInfo: TypeInfo): string {
        if expression != null && semanticModel != null {
            state := NullState.Unknown
            if semanticModel.ExpressionNullStates.TryGetValue((Line: expression.Line, Column: expression.Column), out state) {
                return NullStateFacts.GetSchemaText(state)
            }
        }

        return NullStateFacts.GetSchemaText(CodeIntelligenceTypeResolution.DefaultNullState(typeInfo))
    }

    // ── Where a name is declared ────────────────────────────────────────
    // THE FIRST MATCH IN PROJECT ORDER WINS, and the walk descends into members before it moves to
    // the next declaration, so a nested type's member outranks a later top-level one. Enum members
    // and union cases answer with their CONTAINER's position, because neither carries one of its
    // own and the container is where the reader wants to land.
    static func FindDefinitionLocation(snapshot: ProjectSnapshot, name: string): LocationResult? {
        for entry in snapshot.CompilationUnits {
            declarations := entry.Value.Declarations
            for declaration in declarations {
                location := FindDefinitionLocationInDeclaration(snapshot, entry.Key, declaration, name)
                if location != null {
                    return location
                }
            }
        }

        return null
    }

    static func FindDefinitionLocationInDeclaration(snapshot: ProjectSnapshot, filePath: string, decl: Declaration, name: string): LocationResult? {
        if DeclarationFacts.GetDeclarationName(decl) == name {
            return new LocationResult(CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, filePath), decl.Line, decl.Column)
        }

        members := DeclarationFacts.GetDeclarationMembers(decl)
        if members != null {
            for memberItem in members {
                member := memberItem as Declaration
                if member != null {
                    location := FindDefinitionLocationInDeclaration(snapshot, filePath, member, name)
                    if location != null {
                        return location
                    }
                }
            }
        }

        enumDecl := decl as EnumDeclaration
        if enumDecl != null {
            enumMembers := enumDecl.Members
            for enumMember in enumMembers {
                if enumMember.Name == name {
                    return new LocationResult(CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, filePath), enumDecl.Line, enumDecl.Column)
                }
            }
        }

        unionDecl := decl as UnionDeclaration
        if unionDecl != null {
            cases := unionDecl.Cases
            for caseItem in cases {
                if caseItem.Name == name {
                    return new LocationResult(CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, filePath), unionDecl.Line, unionDecl.Column)
                }
            }
        }

        return null
    }

    // ── The whole type-at-position answer ───────────────────────────────
    // THE THREE ROUTES IN THEIR ORDER, AND THE DISPLAY NAME IS A THIRD FALLBACK CHAIN OF ITS OWN:
    // the name the resolver settled on, else the first candidate the source offered, else whatever
    // the type itself is willing to be called. A `TypeResult` with no name is not an answer.
    static func TypeAtPosition(snapshot: ProjectSnapshot, queryFile: string, line: int, col: int): TypeResult? {
        unitMatch := FindCompilationUnit(snapshot, queryFile)
        cu := unitMatch.Unit
        if cu == null {
            return null
        }

        filePath := unitMatch.FilePath
        semanticModel: SemanticModel? = null
        snapshot.SemanticModels.TryGetValue(filePath, out semanticModel)

        declarationType := DeclaredNameTypeAtPosition(snapshot, filePath, cu, line, col)
        if declarationType != null {
            return declarationType
        }

        typeUse := TypeUseAtPosition(snapshot, filePath, semanticModel, line, col)
        if typeUse != null {
            return typeUse
        }

        boundValue := BoundVariableTypeAtPosition(snapshot, filePath, semanticModel, line, col)
        if boundValue != null {
            return boundValue
        }

        expr := FindExpressionAtPositionRobust(cu, line, col)
        candidateNames := CodeIntelligenceSourceDoor.CandidateQueryNames(expr, CodeIntelligenceSourceDoor.SourceText(snapshot.SourceTexts, filePath), line, col)
        name: string? = null
        if candidateNames.Count > 0 {
            name = candidateNames[0]
        }

        resolvedName: string? = null
        typeInfo := TypeInfoAtPosition(expr, candidateNames, semanticModel, snapshot, cu, out resolvedName)
        if typeInfo == null {
            return null
        }

        resolvedType := NullabilityMetadataReflection.FormatTypeInfo(typeInfo)
        kind := CodeIntelligenceDisplayText.TypeInfoToKind(typeInfo)

        // THE ONE KIND WHOSE `resolvedType` IS NOT A TYPE. `TypeInfoToKind` already answers
        // `method` for both reflected method shapes — the single and the group — so the test is the
        // kind the answer is about to carry rather than a second list of type tests that could
        // drift from it. Every other kind keeps the type it always had.
        if kind == "method" {
            methodSignature := ReflectedMethodSignatureText(expr, FindEnclosingCallAtPositionRobust(cu, line, col), FindEnclosingClassAtPositionRobust(cu, line, col), filePath, semanticModel, snapshot, cu)
            if methodSignature != null {
                resolvedType = methodSignature ?? ""
            }
        }

        definition: LocationResult? = null
        if resolvedName != null {
            definition = FindDefinitionLocation(snapshot, resolvedName)
        }

        displayName := resolvedName ?? name ?? CodeIntelligenceDisplayText.GetTypeDisplayName(typeInfo, resolvedType)
        nullability := NullabilityForExpression(semanticModel, expr, typeInfo)
        return new TypeResult(displayName, resolvedType, kind, definition, nullability)
    }

    // ── Which reflected member ──────────────────────────────────────────
    // A SEPARATE QUESTION FROM `TypeAtPosition`, AND SEPARATE ON PURPOSE. "What TYPE is this" and
    // "what MEMBER is this" have different answers at the same position — `DateTime.Now` is a
    // `DateTime` and is also a property — and only hover needs the second one. Keeping it out of
    // `TypeResult` is what leaves `nlc query type` byte-identical while `nlc query hover` gains a
    // signature: the type answer did not change, a second answer was added beside it.
    //
    // THE WALK IS REPEATED RATHER THAN SHARED, AND THAT IS THE CHEAP SIDE OF THE TRADE. A hover is
    // one interactive request and the walk is one pass over one file's AST; threading a member out
    // of `TypeAtPosition` would have put it in a result type five other callers read.
    static func ReflectedMemberAtPosition(snapshot: ProjectSnapshot, queryFile: string, line: int, col: int): ReflectedMemberHandle? {
        unitMatch := FindCompilationUnit(snapshot, queryFile)
        cu := unitMatch.Unit
        if cu == null {
            return null
        }

        semanticModel: SemanticModel? = null
        snapshot.SemanticModels.TryGetValue(unitMatch.FilePath, out semanticModel)

        return ReflectedMemberAtExpression(FindExpressionAtPositionRobust(cu, line, col), FindEnclosingCallAtPositionRobust(cu, line, col), FindEnclosingClassAtPositionRobust(cu, line, col), unitMatch.FilePath, semanticModel, snapshot, cu)
    }

    // THE SAME QUESTION ASKED OF AN EXPRESSION THE CALLER ALREADY HAS. `TypeAtPosition` walks the
    // AST once and then needs the member too, so the walk is handed over rather than repeated: the
    // two commands answer about the SAME node by construction, which is what makes
    // `hover.signature` and `query type`'s `kind`/`name`/`resolvedType` provably the same fact.
    static func ReflectedMemberAtExpression(expr: Expression?, enclosingCall: CallExpression?, enclosingClass: ClassDeclaration?, filePath: string, semanticModel: SemanticModel?, snapshot: ProjectSnapshot, currentUnit: CompilationUnit): ReflectedMemberHandle? {
        memberAccess := MemberAccessAtPosition(expr)
        if memberAccess == null {
            return ImplicitThisReflectedMember(expr, enclosingCall, enclosingClass, filePath, semanticModel, snapshot, currentUnit)
        }

        argumentTypes := CallArgumentTypeInfos(enclosingCall, semanticModel, snapshot, currentUnit)

        // THE ANALYZER'S OWN ANSWER OUTRANKS A FRESH METADATA LOOKUP, because it is the only one
        // that did real overload resolution. `AnalyzerExpressionTail` records every expression's
        // type at its own position, so where the analyzer bound `Next(-20, 55)` it already chose
        // `Next(int, int)` from the three, and re-deriving that here from arity alone would be a
        // worse copy of work already done. The metadata lookup below is for the positions the
        // analyzer never reached.
        recorded := RecordedReflectedMethod(semanticModel, memberAccess, argumentTypes)
        if recorded != null {
            return recorded
        }

        receiverType := ReflectedReceiverTypeInfo(memberAccess, semanticModel, snapshot, currentUnit)
        if receiverType == null {
            return null
        }

        ownInstance := IsOwnInstanceReceiver(memberAccess.Object)
        direct := CodeIntelligenceTypeResolution.ReflectedMemberOfTypeForCall(receiverType, memberAccess.MemberName, argumentTypes, ownInstance)
        if direct != null {
            return direct
        }

        return InheritedReflectedMember(snapshot, receiverType, memberAccess.MemberName, argumentTypes, ownInstance)
    }

    // `this.Items` AND `base.Items` READ THE ENCLOSING INSTANCE, which is the one receiver through
    // which an inherited protected member is reachable.
    static func IsOwnInstanceReceiver(receiver: Expression): bool {
        return receiver is ThisExpression || receiver is BaseExpression
    }

    // A BARE NAME NO SOURCE SYMBOL CLAIMS, INSIDE A CLASS, IS A MEMBER OF THAT CLASS'S EXTERNAL BASE.
    // `Items` in `class Bag: Collection<string>` means `this.Items`, and it deserves the same hover.
    //
    // THE BINDING MAP DECIDES "NO SOURCE SYMBOL", and it is asked before anything else: a local, a
    // parameter, a function or a field of that name is bound, and a bound name is never re-read as an
    // inherited member. The class's own members are checked again by `InheritedReflectedMember` as it
    // climbs, so a source member shadowing the external one still wins where the map is silent.
    static func ImplicitThisReflectedMember(expr: Expression?, enclosingCall: CallExpression?, enclosingClass: ClassDeclaration?, filePath: string, semanticModel: SemanticModel?, snapshot: ProjectSnapshot, currentUnit: CompilationUnit): ReflectedMemberHandle? {
        if enclosingClass == null {
            return null
        }

        identifier := ImplicitMemberIdentifier(expr)
        if identifier == null {
            return null
        }

        if TryResolveDefinitionViaBindings(snapshot, filePath, identifier.Line, identifier.Column) != null {
            return null
        }

        classType: TypeInfo = NominalTypeInfoFactory.FromClassDeclaration(enclosingClass)
        return InheritedReflectedMember(snapshot, classType, identifier.Name, CallArgumentTypeInfos(enclosingCall, semanticModel, snapshot, currentUnit), true)
    }

    // A CALL IS ITS CALLEE HERE TOO, for the reason `MemberAccessAtPosition` gives: `Add("x")` and
    // `Add` are the same member whichever node the click landed on.
    static func ImplicitMemberIdentifier(expr: Expression?): IdentifierExpression? {
        identifier := expr as IdentifierExpression
        if identifier != null {
            return identifier
        }

        call := expr as CallExpression
        if call != null {
            return call.Callee as IdentifierExpression
        }

        return null
    }

    // ── The external base of a source class ─────────────────────────────
    // A SOURCE CLASS HAS NO CLR TYPE, BUT ITS FIRST EXTERNAL ANCESTOR DOES. The walk climbs the
    // source bases and stops the moment one of them declares the name — a source member always
    // shadows an inherited one — and otherwise asks the first base the project did not declare.
    // The depth bound is for a cyclic `class A: B` / `class B: A`, which the analyzer reports and
    // this walk must survive.
    static func InheritedReflectedMember(snapshot: ProjectSnapshot, receiverType: TypeInfo, memberName: string, argumentTypes: TypeInfo?[]?, includeProtected: bool): ReflectedMemberHandle? {
        current: TypeInfo = UnwrapNullableReceiver(receiverType)
        depth := 0
        while depth < 32 {
            classType := current as ClassTypeInfo
            if classType == null {
                if depth == 0 {
                    return null
                }

                return CodeIntelligenceTypeResolution.ReflectedMemberOfTypeForCall(current, memberName, argumentTypes, includeProtected)
            }

            if DeclaresMember(classType, memberName) {
                return null
            }

            baseClass := classType.BaseClass
            if baseClass == null {
                return null
            }

            current = ResolvedBaseType(snapshot, baseClass)
            depth = depth + 1
        }

        return null
    }

    static func UnwrapNullableReceiver(receiverType: TypeInfo): TypeInfo {
        nullableType := receiverType as NullableTypeInfo
        if nullableType != null {
            return UnwrapNullableReceiver(nullableType.InnerType)
        }

        obliviousType := receiverType as ObliviousTypeInfo
        if obliviousType != null {
            return UnwrapNullableReceiver(obliviousType.InnerType)
        }

        return receiverType
    }

    static func DeclaresMember(classType: ClassTypeInfo, memberName: string): bool {
        for member in classType.DeclaredMembers {
            if member.Name == memberName {
                return true
            }
        }

        return false
    }

    // THE BASE AS THE ANALYZER RESOLVED IT, read from the semantic model of the file that WRITES the
    // base clause. The syntactic `TypeReferenceToTypeInfo` cannot answer for an external base — it
    // keeps `Collection<string>` a bare name with no definition behind it — while the analyzer
    // recorded the reference's real `GenericTypeInfo`, definition and all. The file is found by the
    // reference's IDENTITY, not by its name or position, so two files declaring same-named classes
    // cannot answer for each other. A source base has no recorded external answer and resolves
    // syntactically, which is what carries the walk up to ITS base.
    static func ResolvedBaseType(snapshot: ProjectSnapshot, baseClass: TypeReference): TypeInfo {
        recorded := RecordedBaseType(snapshot, baseClass)
        if recorded != null && !BuiltInTypes.IsUnknown(recorded) {
            return recorded
        }

        return CodeIntelligenceTypeResolution.TypeReferenceToTypeInfo(baseClass, snapshot.CompilationUnits)
    }

    static func RecordedBaseType(snapshot: ProjectSnapshot, baseClass: TypeReference): TypeInfo? {
        span := TypeReferenceFacts.GetStartSpan(baseClass)
        if !span.IsValid {
            return null
        }

        for entry in snapshot.CompilationUnits {
            if UnitWritesBaseClause(entry.Value.Declarations, baseClass) {
                semanticModel: SemanticModel? = null
                snapshot.SemanticModels.TryGetValue(entry.Key, out semanticModel)
                if semanticModel == null {
                    return null
                }

                return semanticModel.LookupTypeReferenceAtPosition(span.StartLine, span.StartColumn)
            }
        }

        return null
    }

    static func UnitWritesBaseClause(declarations: IEnumerable<Declaration>, baseClass: TypeReference): bool {
        for declaration in declarations {
            classDeclaration := declaration as ClassDeclaration
            if classDeclaration != null {
                if Object.ReferenceEquals(classDeclaration.BaseClass, baseClass) {
                    return true
                }

                if UnitWritesBaseClause(classDeclaration.Members, baseClass) {
                    return true
                }
            }
        }

        return false
    }

    // THE METHOD SIGNATURE `query type` PRINTS, WHICH IS HOVER'S SIGNATURE AND NOT A SECOND ONE.
    // A method position has no type to name — the analyzer carries `ToArray(...)` there so a
    // DIAGNOSTIC can say which member it means — and rendering that placeholder as a resolved type
    // was defect A. The placeholder itself is not touched: it is the analyzer's own text and its
    // messages are pinned on it. What changes is that this seam, which is the only place a
    // placeholder reaches a USER as an answer, asks the signature renderer instead.
    static func ReflectedMethodSignatureText(expr: Expression?, enclosingCall: CallExpression?, enclosingClass: ClassDeclaration?, filePath: string, semanticModel: SemanticModel?, snapshot: ProjectSnapshot, currentUnit: CompilationUnit): string? {
        handle := ReflectedMemberAtExpression(expr, enclosingCall, enclosingClass, filePath, semanticModel, snapshot, currentUnit)
        if handle == null {
            return null
        }

        method := handle.Method
        if method == null {
            return null
        }

        return CodeIntelligenceSignatureKernels.GetReflectedMemberSignatureText(handle)
    }

    // A recorded `ReflectionMethodInfo` is one resolved method; a `ReflectionMethodGroupInfo` is the
    // set the analyzer could NOT narrow, and the call site is asked to narrow what it could not.
    // Neither carries a type override: the analyzer resolved these against its own closed types, so
    // their signatures are already written in real types.
    //
    // A SURROGATE GROUP IS THE ONE THAT IS NOT. Its candidates were read off an instantiation closed
    // over `object` because the real type argument has no CLR handle yet, so rendering one would say
    // `object?[] ToArray()` where the program means `Reading[] ToArray()`. It is a binding device for
    // the CALL and never an answer for the reader, so it declines here and the caller falls back to
    // the definition-plus-arguments path that substitutes the spelled type back in.
    static func RecordedReflectedMethod(semanticModel: SemanticModel?, memberAccess: MemberAccessExpression, argumentTypes: TypeInfo?[]?): ReflectedMemberHandle? {
        if semanticModel == null {
            return null
        }

        recordedType := semanticModel.LookupTypeAtPosition(memberAccess.Line, memberAccess.Column)
        if recordedType == null {
            return null
        }

        single := recordedType as ReflectionMethodInfo
        if single != null {
            method := single.Method
            return new ReflectedMemberHandle(null, null, method, method.Name, CodeIntelligenceTypeResolution.DeclaringTypeText(method.DeclaringType), null, 1)
        }

        group := recordedType as ReflectionMethodGroupInfo
        if group != null && !group.IsSurrogateBinding {
            methods := group.Methods
            if methods.Length > 0 {
                chosen := CodeIntelligenceTypeResolution.ChooseReflectedOverload(methods, argumentTypes)
                return new ReflectedMemberHandle(null, null, chosen, chosen.Name, CodeIntelligenceTypeResolution.DeclaringTypeText(chosen.DeclaringType), null, CodeIntelligenceTypeResolution.VisibleOverloadCount(chosen, methods.Length, argumentTypes))
            }
        }

        return null
    }

    // A CALL IS ITS CALLEE HERE. Hovering the name in `x.Foo()` can land on either node depending on
    // where the click fell relative to the dot, and both mean the same member.
    static func MemberAccessAtPosition(expr: Expression?): MemberAccessExpression? {
        memberAccess := expr as MemberAccessExpression
        if memberAccess != null {
            return memberAccess
        }

        call := expr as CallExpression
        if call != null {
            return MemberAccessAtPosition(call.Callee)
        }

        return null
    }

    // THE RECEIVER, ASKED THE TWO WAYS `MemberTypeInfo` ASKS IT AND THEN ONE MORE THAT ONLY HOVER
    // NEEDS. A bare identifier nothing explains may still be an EXTERNAL TYPE NAME — `DateTime` in
    // `DateTime.Now` is not a variable and no project declaration answers for it — and
    // `SimpleTypeInfo` is the shape the known-receiver table is keyed on. It is LAST because a real
    // local of the same name must always win.
    static func ReflectedReceiverTypeInfo(memberAccess: MemberAccessExpression, semanticModel: SemanticModel?, snapshot: ProjectSnapshot, currentUnit: CompilationUnit): TypeInfo? {
        receiver := memberAccess.Object
        receiverType := CodeIntelligenceTypeResolution.TypeInfoFromExpression(receiver, semanticModel, snapshot.CompilationUnits, currentUnit)
        if receiverType != null {
            return receiverType
        }

        receiverIdentifier := receiver as IdentifierExpression
        if receiverIdentifier != null {
            byName := CodeIntelligenceTypeResolution.TypeInfoByName(receiverIdentifier.Name, semanticModel, snapshot.CompilationUnits, currentUnit)
            if byName != null {
                return byName
            }

            return new SimpleTypeInfo(receiverIdentifier.Name)
        }

        return null
    }
}

// The C# returned `(string filePath, CompilationUnit? cu)` and the two halves are always read
// together, so they cross as one value rather than as two lookups: a second walk of the project's
// compilation units to recover the path would double the cost of every hover.
class CompilationUnitMatch {
    filePathValue: string
    unitValue: CompilationUnit?

    FilePath: string => filePathValue
    Unit: CompilationUnit? => unitValue

    constructor(filePath: string, unit: CompilationUnit?) {
        filePathValue = filePath
        unitValue = unit
    }
}
