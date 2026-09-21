namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// ONE PAINTED TOKEN, in the editor's own 0-based numbering, already filtered: a row exists only
// when the editor should colour something there.
//
// `Kind` is a WORD, not the protocol's legend index. The legend is a registration detail — its
// order is a promise the server made to this client at startup — and turning a word into a
// position in it is the caller's job. `IsCatchResult` is the one modifier this feature ever sets.
class EditorSemanticTokenRow {
    lineValue: int
    characterValue: int
    lengthValue: int
    kindValue: string
    isCatchResultValue: bool

    Line: int => lineValue
    Character: int => characterValue
    Length: int => lengthValue
    Kind: string => kindValue
    IsCatchResult: bool => isCatchResultValue

    constructor(Line: int, Character: int, Length: int, Kind: string, IsCatchResult: bool) {
        lineValue = Line
        characterValue = Character
        lengthValue = Length
        kindValue = Kind
        isCatchResultValue = IsCatchResult
    }
}

// WHAT THE EDITOR PAINTS, AND IN WHAT ORDER.
//
// THE MEMBERSHIPS ARE NOT COPIED HERE. Which token types are keywords, which are operators and
// which spellings name a built-in type are owned by `Lexer`, `ParserTokenFacts` and
// `AnalyzerTypeReferenceFacts`; this asks them rather than keeping tables that drift.
//
// THE ORDER OF THE IDENTIFIER RULES IS THE ANSWER. A name that is both an enum member and a
// property is painted as an enum member, because the tests are asked in this order and the first
// that matches wins: the catch-result binding, a built-in type spelling, an enum member, a
// declared type, a function, a parameter, a property, and finally the bound model's variables and
// functions. An identifier nothing recognises is NOT painted — the TextMate grammar beneath keeps
// its colour, and painting it "variable" would override that with a guess.
class EditorSemanticTokenFacts {
    static KeywordKind: string => "keyword"
    static CommentKind: string => "comment"
    static StringKind: string => "string"
    static NumberKind: string => "number"
    static OperatorKind: string => "operator"
    static TypeKind: string => "type"
    static ClassKind: string => "class"
    static StructKind: string => "struct"
    static EnumKind: string => "enum"
    static InterfaceKind: string => "interface"
    static EnumMemberKind: string => "enumMember"
    static FunctionKind: string => "function"
    static ParameterKind: string => "parameter"
    static PropertyKind: string => "property"
    static VariableKindName: string => "variable"

    // ── The tables the classification consults ───────────────────────────
    //
    // The editor keeps these as dictionaries of its own C# shapes, but it BUILDS them from the
    // symbol table this assembly already owns, so they are answerable here from the same source
    // the symbol table is read off — one walk, no editor state, and nothing for a handler to get
    // subtly different.

    // THE C# ENUM MEMBER'S OWN NAME. The editor's symbol kinds and this assembly's agree member
    // for member, and the classification reads five of these words; the rest are carried so that
    // the map says what every declared name IS rather than only what it is painted as.
    static func KindName(kind: EditorSymbolTableKind): string {
        if kind == EditorSymbolTableKind.Class {
            return "Class"
        }

        if kind == EditorSymbolTableKind.Struct {
            return "Struct"
        }

        if kind == EditorSymbolTableKind.Record {
            return "Record"
        }

        if kind == EditorSymbolTableKind.Interface {
            return "Interface"
        }

        if kind == EditorSymbolTableKind.Enum {
            return "Enum"
        }

        if kind == EditorSymbolTableKind.Union {
            return "Union"
        }

        if kind == EditorSymbolTableKind.Function {
            return "Function"
        }

        if kind == EditorSymbolTableKind.Method {
            return "Method"
        }

        if kind == EditorSymbolTableKind.Property {
            return "Property"
        }

        if kind == EditorSymbolTableKind.Field {
            return "Field"
        }

        if kind == EditorSymbolTableKind.Parameter {
            return "Parameter"
        }

        if kind == EditorSymbolTableKind.LocalVariable {
            return "LocalVariable"
        }

        if kind == EditorSymbolTableKind.EnumMember {
            return "EnumMember"
        }

        return "Constructor"
    }

    // EVERY NAME THAT NAMES A TYPE: the analyzer's own catalog of nominal types, widened by the
    // symbol table's type-kinded entries. The catalog is the authority; the table adds the ones it
    // saw declared.
    static func SourceTypeNames(unit: CompilationUnit?, text: string?): HashSet<string> {
        names := new HashSet<string>()

        for entry in EditorSymbolTableFacts.TypeCatalog(unit) {
            names.Add(entry.Key)
        }

        for entry in EditorSymbolTableFacts.SymbolInfoTable(unit, text) {
            if EditorSymbolTableFacts.IsTypeKind(entry.Value.Kind) {
                names.Add(entry.Key)
            }
        }

        return names
    }

    static func SourceTypeKinds(unit: CompilationUnit?, text: string?): Dictionary<string, string> {
        kinds := new Dictionary<string, string>()

        for entry in EditorSymbolTableFacts.SymbolInfoTable(unit, text) {
            kinds[entry.Key] = KindName(entry.Value.Kind)
        }

        return kinds
    }

    // A FUNCTION BY DECLARATION OR BY BINDING. The symbol table names what was declared in this
    // file; the bound model names everything the analyzer resolved, including what an import
    // brought in.
    static func SourceFunctionNames(unit: CompilationUnit?, text: string?, semanticModel: SemanticModel?): HashSet<string> {
        names := new HashSet<string>()

        for entry in EditorSymbolTableFacts.SymbolInfoTable(unit, text) {
            if entry.Value.Kind == EditorSymbolTableKind.Function || entry.Value.Kind == EditorSymbolTableKind.Method {
                names.Add(entry.Key)
            }
        }

        if semanticModel != null {
            for functionEntry in semanticModel.Functions {
                names.Add(functionEntry.Key)
            }
        }

        return names
    }

    // MEMBERS ARE SEARCHED ONE LEVEL DEEP, and by their own name rather than a qualified one — so
    // a property is painted as a property wherever that name appears, whichever type declared it.
    static func SourcePropertyNames(unit: CompilationUnit?, text: string?): HashSet<string> {
        names := new HashSet<string>()

        for entry in EditorSymbolTableFacts.SymbolInfoTable(unit, text) {
            for member in entry.Value.Members {
                if member.Kind == EditorSymbolTableKind.Property {
                    names.Add(member.Name)
                }
            }
        }

        return names
    }

    static func SourceEnumMemberNames(unit: CompilationUnit?, text: string?): HashSet<string> {
        names := new HashSet<string>()

        for entry in EditorSymbolTableFacts.SymbolInfoTable(unit, text) {
            for member in entry.Value.Members {
                if member.Kind == EditorSymbolTableKind.EnumMember {
                    names.Add(member.Name)
                }
            }
        }

        return names
    }

    // EVERY PAINTED TOKEN FROM THE SOURCE ALONE — the five tables above and the classification
    // below, so that a caller holding a parsed document needs no symbol dictionaries of its own.
    static func SourceTokenRows(tokens: List<Token>?, unit: CompilationUnit?, semanticModel: SemanticModel?, text: string?): List<EditorSemanticTokenRow> {
        return TokenRows(
            tokens,
            unit,
            semanticModel,
            SourceTypeNames(unit, text),
            SourceTypeKinds(unit, text),
            SourceFunctionNames(unit, text, semanticModel),
            SourcePropertyNames(unit, text),
            SourceEnumMemberNames(unit, text)
        )
    }

    // Every token the editor should colour, in token order.
    //
    // AN INTERPOLATED LITERAL IS NOT PAINTED AS A STRING and its holes are painted as the code
    // they are. The literal itself is skipped so the grammar beneath keeps the quotes and the
    // literal text; only the expressions inside it are re-lexed and classified.
    static func TokenRows(tokens: List<Token>?, unit: CompilationUnit?, semanticModel: SemanticModel?, typeNames: HashSet<string>, typeKinds: Dictionary<string, string>, functionNames: HashSet<string>, propertyNames: HashSet<string>, enumMemberNames: HashSet<string>): List<EditorSemanticTokenRow> {
        rows := new List<EditorSemanticTokenRow>()
        if tokens == null {
            return rows
        }

        parameterNames := ParameterNames(unit)
        catchResults := CatchResultBindings(unit, tokens)

        for token in tokens {
            if IsInterpolatedStringLiteral(token) {
                for embedded in InterpolationTokens(token) {
                    AppendRow(rows, embedded, semanticModel, typeNames, typeKinds, functionNames, parameterNames, propertyNames, enumMemberNames, catchResults)
                }

                continue
            }

            AppendRow(rows, token, semanticModel, typeNames, typeKinds, functionNames, parameterNames, propertyNames, enumMemberNames, catchResults)
        }

        return rows
    }

    // THREE THINGS KEEP A CLASSIFIED TOKEN OFF THE SCREEN: a position the lexer could not place, a
    // zero-width token, and a token that spans lines — the protocol's semantic tokens cannot, so a
    // multi-line string or comment is left to the grammar entirely.
    static func AppendRow(rows: List<EditorSemanticTokenRow>, token: Token, semanticModel: SemanticModel?, typeNames: HashSet<string>, typeKinds: Dictionary<string, string>, functionNames: HashSet<string>, parameterNames: HashSet<string>, propertyNames: HashSet<string>, enumMemberNames: HashSet<string>, catchResults: HashSet<string>) {
        kind := Classify(token, semanticModel, typeNames, typeKinds, functionNames, parameterNames, propertyNames, enumMemberNames, catchResults)
        if kind == null {
            return
        }

        line := token.Line - 1
        column := token.Column - 1
        if line < 0 || column < 0 || token.Value.Length <= 0 {
            return
        }

        if token.Value.Contains('\n') {
            return
        }

        rows.Add(new EditorSemanticTokenRow(line, column, token.Value.Length, kind, IsCatchResultBinding(token, catchResults)))
    }

    static func Classify(token: Token, semanticModel: SemanticModel?, typeNames: HashSet<string>, typeKinds: Dictionary<string, string>, functionNames: HashSet<string>, parameterNames: HashSet<string>, propertyNames: HashSet<string>, enumMemberNames: HashSet<string>, catchResults: HashSet<string>): string? {
        if Lexer.IsReservedKeyword(token.Type) {
            return KeywordKind
        }

        if token.Type == TokenType.Comment || token.Type == TokenType.MultiLineComment || token.Type == TokenType.XmlDocComment {
            return CommentKind
        }

        if IsInterpolatedStringLiteral(token) {
            return null
        }

        if token.Type == TokenType.StringLiteral || token.Type == TokenType.TripleQuoteStringLiteral {
            return StringKind
        }

        if token.Type == TokenType.IntLiteral || token.Type == TokenType.FloatLiteral {
            return NumberKind
        }

        if ParserTokenFacts.IsOperator(token.Type) {
            return OperatorKind
        }

        if token.Type == TokenType.Identifier {
            return ClassifyIdentifier(token, semanticModel, typeNames, typeKinds, functionNames, parameterNames, propertyNames, enumMemberNames, catchResults)
        }

        return null
    }

    static func ClassifyIdentifier(token: Token, semanticModel: SemanticModel?, typeNames: HashSet<string>, typeKinds: Dictionary<string, string>, functionNames: HashSet<string>, parameterNames: HashSet<string>, propertyNames: HashSet<string>, enumMemberNames: HashSet<string>, catchResults: HashSet<string>): string? {
        name := token.Value

        if IsCatchResultBinding(token, catchResults) {
            return VariableKindName
        }

        if AnalyzerTypeReferenceFacts.IsBuiltInTypeName(name) {
            return TypeKind
        }

        if enumMemberNames.Contains(name) {
            return EnumMemberKind
        }

        if typeNames.Contains(name) {
            return DeclaredTypeKind(name, typeKinds)
        }

        if functionNames.Contains(name) {
            return FunctionKind
        }

        if parameterNames.Contains(name) {
            return ParameterKind
        }

        if propertyNames.Contains(name) {
            return PropertyKind
        }

        if semanticModel != null {
            if semanticModel.Variables.ContainsKey(name) {
                return VariableKindName
            }

            if semanticModel.Functions.ContainsKey(name) {
                return FunctionKind
            }
        }

        return null
    }

    // WHICH ICON A DECLARED TYPE GETS. A record is a class and a union is an enum, because that is
    // what they are to a reader; anything the symbol table describes as something else — or does
    // not describe at all — is painted as a plain type rather than mis-iconed.
    static func DeclaredTypeKind(name: string, typeKinds: Dictionary<string, string>): string {
        declaredKind: string? = null
        if !typeKinds.TryGetValue(name, out declaredKind) {
            return TypeKind
        }

        if declaredKind == "Class" || declaredKind == "Record" {
            return ClassKind
        }

        if declaredKind == "Struct" {
            return StructKind
        }

        if declaredKind == "Enum" || declaredKind == "Union" {
            return EnumKind
        }

        if declaredKind == "Interface" {
            return InterfaceKind
        }

        return TypeKind
    }

    // A PARAMETER IS A TOP-LEVEL FUNCTION'S PARAMETER AND NOTHING ELSE. A method's parameters are
    // not collected, so inside a method a parameter is painted only if some top-level function
    // happens to share the name. That is the shipped answer.
    static func ParameterNames(unit: CompilationUnit?): HashSet<string> {
        names := new HashSet<string>()
        if unit == null {
            return names
        }

        for declaration in unit.Declarations {
            functionDeclaration := declaration as FunctionDeclaration
            if functionDeclaration != null {
                for parameter in functionDeclaration.Parameters {
                    names.Add(parameter.Name)
                }
            }
        }

        return names
    }

    // ── The interpolated literal ────────────────────────────────────────

    static func IsInterpolatedStringLiteral(token: Token): bool {
        if token.Type == TokenType.InterpolatedRawStringLiteral {
            return true
        }

        return token.Type == TokenType.StringLiteral && token.Value.StartsWith("$\"", StringComparison.Ordinal)
    }

    // THE HOLES ARE `LinterInterpolationScan`'s, which is the language's one scanner for "where are
    // the expression holes of this literal". All this does is re-lex each hole's text and shift the
    // result into the enclosing file's coordinates: the sub-lexer starts every hole at line 1
    // column 1, so a token on the hole's FIRST line additionally carries the hole's own column,
    // while a token on a later line already begins at column 1 in both frames.
    static func InterpolationTokens(token: Token): List<Token> {
        embedded := new List<Token>()
        if !IsInterpolatedStringLiteral(token) {
            return embedded
        }

        for hole in LinterInterpolationScan.HoleSpans(token.Value, token.Line, token.Column) {
            lexer := new Lexer(hole.Text, token.FileName)
            for inner in lexer.Tokenize() {
                if inner.Type == TokenType.Eof {
                    continue
                }

                line := inner.Line + hole.Line - 1
                column := inner.Column
                if inner.Line == 1 {
                    column = inner.Column + hole.Column - 1
                }

                embedded.Add(new Token(inner.Type, inner.Value, line, column, token.FileName, inner.IsTerminated))
            }
        }

        return embedded
    }

    // ── The Go-style error capture ──────────────────────────────────────

    // WHICH `err` IS THE ERROR OF A CAPTURE, identified by WHERE it is written rather than by its
    // spelling — an ordinary local called `err` must not be painted as one.
    //
    // `AnalyzerVariableDeclaration.IsErrorCaptureForm` owns which deconstructions are the capture.
    // The editor used to test `Names.Count >= 2`, which painted the modifier on three-name
    // deconstructions the analyzer and the emitter both treat as ordinary tuples.
    static func CatchResultBindings(unit: CompilationUnit?, tokens: List<Token>): HashSet<string> {
        bindings := new HashSet<string>()
        if unit == null {
            return bindings
        }

        for declaration in unit.Declarations {
            AppendBindingsFromDeclaration(declaration, tokens, bindings)
        }

        return bindings
    }

    static func BindingKey(line: int, column: int, name: string): string {
        return line.ToString() + ":" + column.ToString() + ":" + name
    }

    static func IsCatchResultBinding(token: Token, catchResults: HashSet<string>): bool {
        return catchResults.Contains(BindingKey(token.Line, token.Column, token.Value))
    }

    static func AppendBindingsFromDeclaration(declaration: Declaration, tokens: List<Token>, bindings: HashSet<string>) {
        functionDeclaration := declaration as FunctionDeclaration
        if functionDeclaration != null {
            AppendBindingsFromStatement(functionDeclaration.Body, tokens, bindings)
            AppendBindingsFromExpression(functionDeclaration.ExpressionBody, tokens, bindings)
            return
        }

        // ONLY THESE FOUR HOLD MEMBERS WORTH DESCENDING INTO. An enum's members are values, not
        // declarations, and are read below.
        members: List<Declaration>? = null
        classDeclaration := declaration as ClassDeclaration
        if classDeclaration != null {
            members = classDeclaration.Members
        }

        structDeclaration := declaration as StructDeclaration
        if structDeclaration != null {
            members = structDeclaration.Members
        }

        recordDeclaration := declaration as RecordDeclaration
        if recordDeclaration != null {
            members = recordDeclaration.Members
        }

        interfaceDeclaration := declaration as InterfaceDeclaration
        if interfaceDeclaration != null {
            members = interfaceDeclaration.Members
        }

        if members != null {
            for member in members {
                AppendBindingsFromDeclaration(member, tokens, bindings)
            }

            return
        }

        fieldDeclaration := declaration as FieldDeclaration
        if fieldDeclaration != null {
            AppendBindingsFromExpression(fieldDeclaration.Initializer, tokens, bindings)
            return
        }

        propertyDeclaration := declaration as PropertyDeclaration
        if propertyDeclaration != null {
            AppendBindingsFromStatement(propertyDeclaration.GetBody, tokens, bindings)
            AppendBindingsFromStatement(propertyDeclaration.SetBody, tokens, bindings)
            AppendBindingsFromExpression(propertyDeclaration.ExpressionBody, tokens, bindings)
            return
        }

        constructorDeclaration := declaration as ConstructorDeclaration
        if constructorDeclaration != null {
            AppendBindingsFromStatement(constructorDeclaration.Body, tokens, bindings)
            AppendBindingsFromExpression(constructorDeclaration.Initializer, tokens, bindings)
            return
        }

        indexerDeclaration := declaration as IndexerDeclaration
        if indexerDeclaration != null {
            AppendBindingsFromStatement(indexerDeclaration.GetBody, tokens, bindings)
            AppendBindingsFromStatement(indexerDeclaration.SetBody, tokens, bindings)
            return
        }

        enumDeclaration := declaration as EnumDeclaration
        if enumDeclaration != null {
            for enumMember in enumDeclaration.Members {
                AppendBindingsFromExpression(enumMember.Value, tokens, bindings)
            }
        }
    }

    static func AppendBindingsFromStatement(statement: Statement?, tokens: List<Token>, bindings: HashSet<string>) {
        if statement == null {
            return
        }

        block := statement as BlockStatement
        if block != null {
            for child in block.Statements {
                AppendBindingsFromStatement(child, tokens, bindings)
            }

            return
        }

        expressionStatement := statement as ExpressionStatement
        if expressionStatement != null {
            AppendBindingsFromExpression(expressionStatement.Expression, tokens, bindings)
            return
        }

        variableDeclaration := statement as VariableDeclarationStatement
        if variableDeclaration != null {
            AppendBindingsFromExpression(variableDeclaration.Initializer, tokens, bindings)
            return
        }

        tupleDeconstruction := statement as TupleDeconstructionStatement
        if tupleDeconstruction != null {
            AppendCaptureBinding(tupleDeconstruction, tokens, bindings)
            AppendBindingsFromExpression(tupleDeconstruction.Initializer, tokens, bindings)
            return
        }

        returnStatement := statement as ReturnStatement
        if returnStatement != null {
            AppendBindingsFromExpression(returnStatement.Value, tokens, bindings)
            return
        }

        throwStatement := statement as ThrowStatement
        if throwStatement != null {
            AppendBindingsFromExpression(throwStatement.Expression, tokens, bindings)
            return
        }

        ifStatement := statement as IfStatement
        if ifStatement != null {
            AppendBindingsFromExpression(ifStatement.Condition, tokens, bindings)
            AppendBindingsFromStatement(ifStatement.ThenStatement, tokens, bindings)
            AppendBindingsFromStatement(ifStatement.ElseStatement, tokens, bindings)
            return
        }

        forStatement := statement as ForStatement
        if forStatement != null {
            AppendBindingsFromStatement(forStatement.Initializer, tokens, bindings)
            AppendBindingsFromExpression(forStatement.Condition, tokens, bindings)
            AppendBindingsFromExpression(forStatement.Iterator, tokens, bindings)
            AppendBindingsFromStatement(forStatement.Body, tokens, bindings)
            return
        }

        foreachStatement := statement as ForeachStatement
        if foreachStatement != null {
            AppendBindingsFromExpression(foreachStatement.Collection, tokens, bindings)
            AppendBindingsFromStatement(foreachStatement.Body, tokens, bindings)
            return
        }

        awaitForeachStatement := statement as AwaitForEachStatement
        if awaitForeachStatement != null {
            AppendBindingsFromExpression(awaitForeachStatement.Collection, tokens, bindings)
            AppendBindingsFromStatement(awaitForeachStatement.Body, tokens, bindings)
            return
        }

        whileStatement := statement as WhileStatement
        if whileStatement != null {
            AppendBindingsFromExpression(whileStatement.Condition, tokens, bindings)
            AppendBindingsFromStatement(whileStatement.Body, tokens, bindings)
            return
        }

        tryStatement := statement as TryStatement
        if tryStatement != null {
            AppendBindingsFromStatement(tryStatement.TryBlock, tokens, bindings)
            for catchClause in tryStatement.CatchClauses {
                AppendBindingsFromStatement(catchClause.Block, tokens, bindings)
            }

            AppendBindingsFromStatement(tryStatement.FinallyBlock, tokens, bindings)
            return
        }

        usingStatement := statement as UsingStatement
        if usingStatement != null {
            if usingStatement.Declaration != null {
                AppendBindingsFromStatement(usingStatement.Declaration, tokens, bindings)
            }

            AppendBindingsFromStatement(usingStatement.Body, tokens, bindings)
            return
        }

        lockStatement := statement as LockStatement
        if lockStatement != null {
            AppendBindingsFromExpression(lockStatement.LockObject, tokens, bindings)
            AppendBindingsFromStatement(lockStatement.Body, tokens, bindings)
            return
        }

        switchStatement := statement as SwitchStatement
        if switchStatement != null {
            AppendBindingsFromExpression(switchStatement.Value, tokens, bindings)
            for switchCase in switchStatement.Cases {
                for child in switchCase.Statements {
                    AppendBindingsFromStatement(child, tokens, bindings)
                }
            }

            return
        }

        localFunction := statement as LocalFunctionStatement
        if localFunction != null {
            AppendBindingsFromStatement(localFunction.Function.Body, tokens, bindings)
            return
        }

        printStatement := statement as PrintStatement
        if printStatement != null {
            AppendBindingsFromExpression(printStatement.Value, tokens, bindings)
            return
        }

        assertStatement := statement as AssertStatement
        if assertStatement != null {
            AppendBindingsFromExpression(assertStatement.Condition, tokens, bindings)
            AppendBindingsFromExpression(assertStatement.Message, tokens, bindings)
            return
        }

        assertThrowsStatement := statement as AssertThrowsStatement
        if assertThrowsStatement != null {
            AppendBindingsFromStatement(assertThrowsStatement.Body, tokens, bindings)
        }
    }

    static func AppendBindingsFromExpression(expression: Expression?, tokens: List<Token>, bindings: HashSet<string>) {
        if expression == null {
            return
        }

        binary := expression as BinaryExpression
        if binary != null {
            AppendBindingsFromExpression(binary.Left, tokens, bindings)
            AppendBindingsFromExpression(binary.Right, tokens, bindings)
            return
        }

        unary := expression as UnaryExpression
        if unary != null {
            AppendBindingsFromExpression(unary.Operand, tokens, bindings)
            return
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            AppendBindingsFromExpression(memberAccess.Object, tokens, bindings)
            return
        }

        indexAccess := expression as IndexAccessExpression
        if indexAccess != null {
            AppendBindingsFromExpression(indexAccess.Object, tokens, bindings)
            AppendBindingsFromExpression(indexAccess.Index, tokens, bindings)
            return
        }

        call := expression as CallExpression
        if call != null {
            AppendBindingsFromExpression(call.Callee, tokens, bindings)
            for argument in call.Arguments {
                AppendBindingsFromExpression(argument.Value, tokens, bindings)
            }

            return
        }

        assignment := expression as AssignmentExpression
        if assignment != null {
            AppendBindingsFromExpression(assignment.Target, tokens, bindings)
            AppendBindingsFromExpression(assignment.Value, tokens, bindings)
            return
        }

        lambda := expression as LambdaExpression
        if lambda != null {
            AppendBindingsFromExpression(lambda.ExpressionBody, tokens, bindings)
            AppendBindingsFromStatement(lambda.BlockBody, tokens, bindings)
            return
        }

        ternary := expression as TernaryExpression
        if ternary != null {
            AppendBindingsFromExpression(ternary.Condition, tokens, bindings)
            AppendBindingsFromExpression(ternary.ThenExpression, tokens, bindings)
            AppendBindingsFromExpression(ternary.ElseExpression, tokens, bindings)
            return
        }

        arrayLiteral := expression as ArrayLiteralExpression
        if arrayLiteral != null {
            for element in arrayLiteral.Elements {
                AppendBindingsFromExpression(element, tokens, bindings)
            }

            return
        }

        tuple := expression as TupleExpression
        if tuple != null {
            for element in tuple.Elements {
                AppendBindingsFromExpression(element.Value, tokens, bindings)
            }

            return
        }

        initializer := expression as ObjectInitializerExpression
        if initializer != null {
            for property in initializer.Properties {
                AppendBindingsFromExpression(property.IndexExpression, tokens, bindings)
                AppendBindingsFromExpression(property.Value, tokens, bindings)
            }

            return
        }

        newExpression := expression as NewExpression
        if newExpression != null {
            for argument in newExpression.ConstructorArguments {
                AppendBindingsFromExpression(argument.Value, tokens, bindings)
            }

            AppendBindingsFromExpression(newExpression.Initializer, tokens, bindings)
            return
        }

        cast := expression as CastExpression
        if cast != null {
            AppendBindingsFromExpression(cast.Expression, tokens, bindings)
            return
        }

        isExpression := expression as IsExpression
        if isExpression != null {
            AppendBindingsFromExpression(isExpression.Expression, tokens, bindings)
            return
        }

        matchExpression := expression as MatchExpression
        if matchExpression != null {
            AppendBindingsFromExpression(matchExpression.Value, tokens, bindings)
            for matchCase in matchExpression.Cases {
                AppendBindingsFromExpression(matchCase.Guard, tokens, bindings)
                AppendBindingsFromExpression(matchCase.Expression, tokens, bindings)
            }

            return
        }

        awaitExpression := expression as AwaitExpression
        if awaitExpression != null {
            AppendBindingsFromExpression(awaitExpression.Expression, tokens, bindings)
            return
        }

        spread := expression as SpreadExpression
        if spread != null {
            AppendBindingsFromExpression(spread.Expression, tokens, bindings)
            return
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            AppendBindingsFromExpression(parenthesized.Inner, tokens, bindings)
        }
    }

    // THE CAPTURE'S ERROR IS THE LAST NAME OF THE DECONSTRUCTION, FOUND IN THE TOKEN STREAM.
    //
    // The AST records where the STATEMENT starts and not where each name sits, so the names are
    // counted off in the token stream from that point: identifiers in order until the one whose
    // index is the last, and it must literally be spelled `err`. The scan stops at the first
    // assignment operator, because everything after it is the right-hand side.
    static func AppendCaptureBinding(statement: TupleDeconstructionStatement, tokens: List<Token>, bindings: HashSet<string>) {
        names := statement.Names
        if names.Count == 0 || !AnalyzerVariableDeclaration.IsErrorCaptureForm(names.Count, names[names.Count - 1]) {
            return
        }

        captureIndex := names.Count - 1
        identifierIndex := 0

        for token in tokens {
            if token.Line < statement.Line || (token.Line == statement.Line && token.Column < statement.Column) {
                continue
            }

            if token.Type == TokenType.ColonAssign || token.Type == TokenType.Assign {
                return
            }

            if token.Type != TokenType.Identifier {
                continue
            }

            if identifierIndex == captureIndex && token.Value == "err" {
                bindings.Add(BindingKey(token.Line, token.Column, token.Value))
                return
            }

            identifierIndex = identifierIndex + 1
        }
    }
}
