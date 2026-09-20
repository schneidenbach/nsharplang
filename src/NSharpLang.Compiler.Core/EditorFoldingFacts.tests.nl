namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// CONTRACTS FOR WHAT A FILE OFFERS TO FOLD. These came out of `FoldingRangeHandler.cs` with the
// members: the brace-depth walk that finds where a declaration ends, the one-line rule that keeps
// a useless control off the gutter, the import-group rule, the comment rows the lexer's own token
// text measures, and the ORDER an editor draws them in.
func EffLines(text: string): string[] {
    return text.Split('\n')
}

func EffUnit(imports: List<ImportDirective>, declarations: List<Declaration>): CompilationUnit {
    return new CompilationUnit(null, imports, new List<Statement>(), null, declarations, 1, 1)
}

func EffFunction(name: string, body: BlockStatement?, line: int): Declaration {
    declaration: Declaration = new FunctionDeclaration(name, new List<Parameter>(), null, body, null, null, null, Modifiers.None, new List<AttributeNode>(), false, null, false, false, line, 1)
    return declaration
}

func EffBlock(statements: List<Statement>, line: int): BlockStatement {
    return new BlockStatement(statements, line, 1)
}

func EffPrintable(line: int): Statement {
    statement: Statement = new ExpressionStatement(new IdentifierExpression("x", line, 1), line, 1)
    return statement
}

func EffOneStatement(line: int): List<Statement> {
    statements := new List<Statement>()
    statements.Add(EffPrintable(line))
    return statements
}

func EffDeclarations(declaration: Declaration): List<Declaration> {
    declarations := new List<Declaration>()
    declarations.Add(declaration)
    return declarations
}

func EffImport(name: string, line: int): ImportDirective {
    return new ImportDirective(name, null, line, 1)
}

// THE BRACE THAT OPENS ON THE DECLARATION'S LINE IS THE ONE THAT CLOSES THE REGION, counted by
// depth so a nested block cannot end it early. A declaration with no brace closes where it began.
test "the end of a declaration is the line its own brace closes on" {
    lines := EffLines("func run(): void {\n    if a {\n        b\n    }\n}\ntail")
    assert EditorFoldingFacts.EndLineOfBrace(1, lines) == 5
    assert EditorFoldingFacts.EndLineOfBrace(2, lines) == 4

    unbraced := EffLines("func run(): void\n    b")
    assert EditorFoldingFacts.EndLineOfBrace(1, unbraced) == 1
    assert EditorFoldingFacts.EndLineOfBrace(0, unbraced) == 0
}

// A CARRIAGE RETURN IS NOT A COLUMN A READER CAN SEE, so a CRLF file must not fold one past its
// own text.
test "the end column of a line does not count a carriage return" {
    lines := EffLines("func run(): void {\r\n}\r\n")
    assert EditorFoldingFacts.LineEndColumn(lines, 0) == 18
    assert EditorFoldingFacts.LineEndColumn(lines, 1) == 1
    assert EditorFoldingFacts.LineEndColumn(lines, 99) == 0
    assert EditorFoldingFacts.LineEndColumn(lines, -1) == 0
}

// FOLDING ONE LINE HIDES NOTHING, so a one-line declaration offers no region at all.
test "a declaration that spans one line offers nothing to fold" {
    lines := EffLines("func run(): void { }\n")
    rows := EditorFoldingFacts.FoldingRows(EffUnit(new List<ImportDirective>(), EffDeclarations(EffFunction("run", null, 1))), lines, null)

    assert rows.Count == 0
}

// A DECLARATION SAYS WHERE ON THE LAST LINE IT ENDS so that folding it leaves the closing brace
// visible; it starts at column zero and wears no kind.
test "a multi-line declaration folds from column zero to the end of its closing line" {
    lines := EffLines("func run(): void {\n    b\n}\n")
    rows := EditorFoldingFacts.FoldingRows(EffUnit(new List<ImportDirective>(), EffDeclarations(EffFunction("run", null, 1))), lines, null)

    assert rows.Count == 1
    assert rows[0].StartLine == 0
    assert rows[0].StartCharacter == 0
    assert rows[0].EndLine == 2
    assert rows[0].EndCharacter == 1
    assert rows[0].Kind == EditorFoldingFacts.NoKind
}

// A BLOCK INSIDE A BODY IS ITS OWN REGION and, unlike a declaration, names no start column — the
// editor folds the whole line, which is what a body brace wants.
test "a block statement inside a function body folds as its own region" {
    lines := EffLines("func run(): void {\n    if a {\n        b\n    }\n}\n")
    thenBlock := EffBlock(EffOneStatement(3), 2)
    ifStatement: Statement = new IfStatement(new IdentifierExpression("a", 2, 8), thenBlock, null, 2, 5)
    bodyStatements := new List<Statement>()
    bodyStatements.Add(ifStatement)
    body := EffBlock(bodyStatements, 1)

    rows := EditorFoldingFacts.FoldingRows(EffUnit(new List<ImportDirective>(), EffDeclarations(EffFunction("run", body, 1))), lines, null)

    assert rows.Count == 2
    assert rows[1].StartLine == 1
    assert rows[1].StartCharacter == null
    assert rows[1].EndLine == 3
    assert rows[1].Kind == EditorFoldingFacts.NoKind
}

// ONE IMPORT IS NOT A BLOCK, and a run that sits on one line has nothing to hide.
test "the import group folds only when more than one import spans more than one line" {
    lines := EffLines("import A\nimport B\n")

    single := new List<ImportDirective>()
    single.Add(EffImport("A", 1))
    assert EditorFoldingFacts.FoldingRows(EffUnit(single, new List<Declaration>()), lines, null).Count == 0

    sameLine := new List<ImportDirective>()
    sameLine.Add(EffImport("A", 1))
    sameLine.Add(EffImport("B", 1))
    assert EditorFoldingFacts.FoldingRows(EffUnit(sameLine, new List<Declaration>()), lines, null).Count == 0

    group := new List<ImportDirective>()
    group.Add(EffImport("A", 1))
    group.Add(EffImport("B", 2))
    rows := EditorFoldingFacts.FoldingRows(EffUnit(group, new List<Declaration>()), lines, null)
    assert rows.Count == 1
    assert rows[0].StartLine == 0
    assert rows[0].EndLine == 1
    assert rows[0].StartCharacter == null
    assert rows[0].EndCharacter == null
    assert rows[0].Kind == EditorFoldingFacts.ImportsKind
}

// A MULTI-LINE COMMENT IS MEASURED BY THE NEWLINES THE LEXER ALREADY KEPT, not by a second scan of
// the file, and a single-line one is not a region.
test "a multi-line comment token folds over the lines its own text carries" {
    tokens := new List<Token>()
    tokens.Add(new Token(TokenType.MultiLineComment, "/* one\ntwo\nthree */", 2, 1))
    tokens.Add(new Token(TokenType.MultiLineComment, "/* flat */", 8, 1))
    tokens.Add(new Token(TokenType.Identifier, "x", 9, 1))

    rows := EditorFoldingFacts.FoldingRows(null, EffLines(""), tokens)

    assert rows.Count == 1
    assert rows[0].StartLine == 1
    assert rows[0].EndLine == 3
    assert rows[0].Kind == EditorFoldingFacts.CommentKind
}

// THE ORDER IS PART OF THE ANSWER: imports, then declarations in source order with their nested
// regions, then comments.
test "folding rows are offered as imports, then declarations, then comments" {
    lines := EffLines("import A\nimport B\n\nfunc run(): void {\n    b\n}\n")
    imports := new List<ImportDirective>()
    imports.Add(EffImport("A", 1))
    imports.Add(EffImport("B", 2))

    tokens := new List<Token>()
    tokens.Add(new Token(TokenType.MultiLineComment, "/* a\nb */", 7, 1))

    rows := EditorFoldingFacts.FoldingRows(EffUnit(imports, EffDeclarations(EffFunction("run", null, 4))), lines, tokens)

    assert rows.Count == 3
    assert rows[0].Kind == EditorFoldingFacts.ImportsKind
    assert rows[1].Kind == EditorFoldingFacts.NoKind
    assert rows[1].StartLine == 3
    assert rows[2].Kind == EditorFoldingFacts.CommentKind
    assert rows[2].StartLine == 6
}

// A FILE WITH NO PARSE STILL FOLDS ITS COMMENTS, because the lexer answered even where the parser
// could not.
test "a file with no compilation unit still offers its comment regions" {
    tokens := new List<Token>()
    tokens.Add(new Token(TokenType.MultiLineComment, "/* a\nb */", 1, 1))

    rows := EditorFoldingFacts.FoldingRows(null, EffLines(""), tokens)

    assert rows.Count == 1
    assert rows[0].Kind == EditorFoldingFacts.CommentKind
}
