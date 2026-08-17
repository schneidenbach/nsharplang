namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.IO
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
// THE THREE ROUTES TO A TYPE ARE TRIED IN A FIXED ORDER AND THE ORDER IS THE POLICY.
// `TypeAtPosition` asks the DECLARED NAME first (the cursor is on a declaration's own name), then
// the TYPE USE (the cursor is on a type reference), and only then the EXPRESSION. A declaration
// beats a use because the user pointed at the definition; a use beats an expression because a type
// reference is not a value. Reordering them is a behaviour change, not a refactor.
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
        index := 0
        while index < candidateColumns.Length {
            candidateColumn := candidateColumns[index]
            expression := AstNodeFinderCore.FindExpressionAtPosition(cu, line - 1, candidateColumn - 1) as Expression
            if expression == null {
                expression = AstNodeFinderCore.FindExpressionAtPosition(cu, line, candidateColumn) as Expression
            }

            if expression != null {
                return expression
            }

            index = index + 1
        }

        return null
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
        index := 0
        while index < declarations.Count {
            result := CodeIntelligenceTypeResolution.DeclaredNameTypeInDeclaration(snapshot.ProjectRoot, snapshot.CompilationUnits, filePath, declarations[index], selectedWord, line)
            if result != null {
                return result
            }

            index = index + 1
        }

        return null
    }

    // ── Route 3: the expression ─────────────────────────────────────────
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

        index := 0
        while index < candidateNames.Count {
            candidateName := candidateNames[index]
            typeInfo := CodeIntelligenceTypeResolution.TypeInfoByName(candidateName, semanticModel, snapshot.CompilationUnits, currentUnit)
            if typeInfo != null {
                resolvedName = candidateName
                return typeInfo
            }

            index = index + 1
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
            index := 0
            while index < declarations.Count {
                location := FindDefinitionLocationInDeclaration(snapshot, entry.Key, declarations[index], name)
                if location != null {
                    return location
                }

                index = index + 1
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
            index := 0
            while index < members.Count {
                member := members[index] as Declaration
                if member != null {
                    location := FindDefinitionLocationInDeclaration(snapshot, filePath, member, name)
                    if location != null {
                        return location
                    }
                }

                index = index + 1
            }
        }

        enumDecl := decl as EnumDeclaration
        if enumDecl != null {
            enumMembers := enumDecl.Members
            enumIndex := 0
            while enumIndex < enumMembers.Count {
                if enumMembers[enumIndex].Name == name {
                    return new LocationResult(CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, filePath), enumDecl.Line, enumDecl.Column)
                }

                enumIndex = enumIndex + 1
            }
        }

        unionDecl := decl as UnionDeclaration
        if unionDecl != null {
            cases := unionDecl.Cases
            caseIndex := 0
            while caseIndex < cases.Count {
                if cases[caseIndex].Name == name {
                    return new LocationResult(CodeIntelligenceSourceDoor.RelativePath(snapshot.ProjectRoot, filePath), unionDecl.Line, unionDecl.Column)
                }

                caseIndex = caseIndex + 1
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
        definition: LocationResult? = null
        if resolvedName != null {
            definition = FindDefinitionLocation(snapshot, resolvedName)
        }

        displayName := resolvedName ?? name ?? CodeIntelligenceDisplayText.GetTypeDisplayName(typeInfo, resolvedType)
        nullability := NullabilityForExpression(semanticModel, expr, typeInfo)
        return new TypeResult(displayName, resolvedType, kind, definition, nullability)
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
