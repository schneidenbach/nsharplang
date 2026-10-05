namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
import System.Reflection
import System.Text
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.Columnar

// WHAT ONE SOURCE FILE OFFERS THE REST OF ITS PROJECT, AND WHAT IT ASKS OF IT.
//
// The per-file incremental analysis rests on one claim: a file's analysis reads another file only
// through NAMES. N# has no textual inclusion and no whole-program inference; a file resolves a name
// it wrote (or an attribute name plus `Attribute`) against the declarations the project offers, and
// everything it learns about a declaration it reached that way is in that declaration's SURFACE —
// its header, its members' signatures, its field initializers, its position — never in a function
// body. So a summary carries four sets of names and one hash:
//
//   * `DeclaredNames` — every name this file declares, at any depth (types, functions, members,
//     enum members, union cases, a record's positional parameters), plus its namespace's segments.
//     Collected by a structural walk of the parsed declarations, so a declaration kind added to the
//     language later is covered without anyone listing it.
//   * `BaseNames` — the names inside its types' base and interface lists: the reverse edge that
//     lets "every implementation of `Shape`" reach a file that never names anything `Shape`'s
//     users wrote.
//   * `ReferencedNames` — every name this file's declarations REFER to outside function bodies:
//     the types in its signatures and base lists, its attribute names, the identifiers in its field
//     initializers, default values and expression bodies. What a dependent learns about this file's
//     declarations, it learns in terms of these, so the dependency closure follows them.
//   * `Mentions` — every name this file's own analysis can ask the project for: every identifier-
//     shaped word inside its function bodies (string literals included, so a call written only in an
//     interpolation counts), every name its declarations refer to, its top-level declared names (a
//     second file declaring the same top-level name is a conflict this file must hear about), and the
//     words of its namespace and imports. A MEMBER name it merely declares is not a mention: another
//     type's member of the same name is nothing this file looks up.
//   * `SurfaceHash` — SHA-256 over every token outside function bodies with its kind, spelling,
//     line and column. Positions are part of the surface because analysis results carry them (a
//     free-function call's target is recorded by its declaration's line and column), so an edit
//     that moves a declaration is a surface edit even when it changes no signature.
//
// A FILE THAT DOES NOT PARSE CLEANLY IS OPAQUE: its names cannot be trusted, so every other file
// depends on it and it depends on every other file. Over-approximation is always the safe
// direction; the differential test in `tests/native/incremental-build` is what holds the claim.
class IncrementalFileSummary {

    // Bumped whenever a summary is computed differently, so a persisted summary cannot be reused.
    static FormatVersion: int => 4

    Path: string
    TextHash: string
    SurfaceHash: string
    Opaque: bool
    DeclaredNames: HashSet<string>
    BaseNames: HashSet<string>
    ReferencedNames: HashSet<string>
    Mentions: HashSet<string>
    // The namespace (or package) the file declares, or null. Not a declared NAME: whether a namespace
    // EXISTS in the project is a property of the whole file set, compared run to run by the plan.
    Namespace: string?

    constructor(path: string, contentHash: string, surfaceHash: string, opaque: bool) {
        Path = path
        TextHash = contentHash
        SurfaceHash = surfaceHash
        Opaque = opaque
        DeclaredNames = new HashSet<string>(StringComparer.Ordinal)
        BaseNames = new HashSet<string>(StringComparer.Ordinal)
        ReferencedNames = new HashSet<string>(StringComparer.Ordinal)
        Mentions = new HashSet<string>(StringComparer.Ordinal)
        Namespace = null
    }

    // The summary of `text`, which is the file's text exactly as the analyzer's project walk reads
    // it (`AnalyzerProjectSourceProvider.ProjectSourceText`): unpreprocessed, from disk or snapshot.
    static func Compute(path: string, text: string): IncrementalFileSummary {
        contentHash := ContentHash.OfText(text)
        unit: CompilationUnit? = null
        parseErrors := 0
        try {
            parseResult := ColumnarParserRecovery.ParseFileAst(text, path)
            unit = parseResult.CompilationUnit
            parseErrors = parseResult.Errors.Count
        } catch {
            unit = null
        }

        tokens: List<Token> = null
        try {
            tokens = new Lexer(text, path).Tokenize()
        } catch {
            tokens = null
        }

        opaque := unit == null || parseErrors > 0 || tokens == null
        surfaceBuilder := new StringBuilder()
        bodyWords := new HashSet<string>(StringComparer.Ordinal)
        if tokens != null {
            bodyStarts := new HashSet<long>()
            if unit != null {
                CollectBodyStarts(unit.Declarations, bodyStarts)
            }

            depth := 0
            for token in tokens {
                isLeftBrace := token.Type == TokenType.LeftBrace
                isRightBrace := token.Type == TokenType.RightBrace
                if depth > 0 {
                    AddWords(bodyWords, token.Value)
                    if isLeftBrace {
                        depth = depth + 1
                        continue
                    }
                    if isRightBrace {
                        depth = depth - 1
                        if depth > 0 {
                            continue
                        }
                    } else {
                        continue
                    }
                }

                tokenKind: int = (int)token.Type
                surfaceBuilder.Append(tokenKind.ToString(System.Globalization.CultureInfo.InvariantCulture))
                surfaceBuilder.Append(":")
                surfaceBuilder.Append(token.Line.ToString(System.Globalization.CultureInfo.InvariantCulture))
                surfaceBuilder.Append(":")
                surfaceBuilder.Append(token.Column.ToString(System.Globalization.CultureInfo.InvariantCulture))
                surfaceBuilder.Append(":")
                surfaceBuilder.Append(token.Value.Length.ToString(System.Globalization.CultureInfo.InvariantCulture))
                surfaceBuilder.Append(":")
                surfaceBuilder.Append(token.Value)
                surfaceBuilder.Append("\n")

                if isLeftBrace && bodyStarts.Contains(PositionKey(token.Line, token.Column)) {
                    depth = 1
                }
            }
        } else {
            surfaceBuilder.Append(text)
        }

        walk := new IncrementalDeclarationWalk()
        mentions := new HashSet<string>(StringComparer.Ordinal)
        if unit != null {
            AddNamespaceNames(mentions, unit)
            for declaration in unit.Declarations {
                walk.Visit(declaration, false, 0)
                topLevelName := DeclarationFacts.GetDeclarationName(declaration)
                if topLevelName != null {
                    mentions.Add(topLevelName)
                }
            }

            header := new IncrementalDeclarationWalk()
            header.Visit(unit.Imports, false, 0)
            header.Visit(unit.FileImports, false, 0)
            mentions.UnionWith(header.Referenced)
            opaque = opaque || header.Truncated
        }
        mentions.UnionWith(bodyWords)
        mentions.UnionWith(walk.Referenced)

        // A file whose walk was cut short, like one that did not parse, cannot vouch for its names.
        opaque = opaque || walk.Truncated
        summary := new IncrementalFileSummary(path, contentHash, ContentHash.OfText(surfaceBuilder.ToString()), opaque)
        if unit != null {
            summary.Namespace = AnalyzerProjectSourceProvider.UnitNamespace(unit)
        }
        if opaque {
            AddWords(summary.Mentions, text)
            AddWords(summary.ReferencedNames, text)
            AddWords(summary.DeclaredNames, text)
        } else {
            summary.Mentions.UnionWith(mentions)
            summary.ReferencedNames.UnionWith(walk.Referenced)
            summary.DeclaredNames.UnionWith(walk.Declared)
            summary.BaseNames.UnionWith(walk.BaseNames)
        }

        return summary
    }

    // ---- function bodies ------------------------------------------------------------------------

    private static func PositionKey(line: int, column: int): long {
        lineValue: long = line
        columnValue: long = column
        return lineValue * 1000000 + columnValue
    }

    // The `{` of every block whose CONTENTS are a body: functions, constructors, accessors and test
    // blocks, at any nesting depth. A body this walk does not know is kept in the surface, which only
    // makes the surface larger.
    private static func CollectBodyStarts(declarations: List<Declaration>, starts: HashSet<long>) {
        for declaration in declarations {
            CollectBodyStartsOf(declaration, starts)
        }
    }

    private static func CollectBodyStartsOf(declaration: Declaration, starts: HashSet<long>) {
        function := declaration as FunctionDeclaration
        if function != null {
            AddBlock(function.Body, starts)
            return
        }
        constructorDeclaration := declaration as ConstructorDeclaration
        if constructorDeclaration != null {
            AddBlock(constructorDeclaration.Body, starts)
            return
        }
        property := declaration as PropertyDeclaration
        if property != null {
            AddBlock(property.GetBody, starts)
            AddBlock(property.SetBody, starts)
            return
        }
        indexer := declaration as IndexerDeclaration
        if indexer != null {
            AddBlock(indexer.GetBody, starts)
            AddBlock(indexer.SetBody, starts)
            return
        }
        testDeclaration := declaration as TestDeclaration
        if testDeclaration != null {
            AddBlock(testDeclaration.Body, starts)
            return
        }
        setup := declaration as SetupDeclaration
        if setup != null {
            AddBlock(setup.Body, starts)
            return
        }
        teardown := declaration as TeardownDeclaration
        if teardown != null {
            AddBlock(teardown.Body, starts)
            return
        }
        classDeclaration := declaration as ClassDeclaration
        if classDeclaration != null {
            CollectBodyStarts(classDeclaration.Members, starts)
            return
        }
        structDeclaration := declaration as StructDeclaration
        if structDeclaration != null {
            CollectBodyStarts(structDeclaration.Members, starts)
            return
        }
        recordDeclaration := declaration as RecordDeclaration
        if recordDeclaration != null {
            CollectBodyStarts(recordDeclaration.Members, starts)
            return
        }
        interfaceDeclaration := declaration as InterfaceDeclaration
        if interfaceDeclaration != null {
            CollectBodyStarts(interfaceDeclaration.Members, starts)
        }
    }

    private static func AddBlock(block: BlockStatement?, starts: HashSet<long>) {
        if block == null {
            return
        }

        starts.Add(PositionKey(block.Line, block.Column))
    }

    // ---- names ----------------------------------------------------------------------------------

    private static func AddNamespaceNames(names: HashSet<string>, unit: CompilationUnit) {
        namespaceName := AnalyzerProjectSourceProvider.UnitNamespace(unit)
        if namespaceName == null {
            return
        }

        for segment in namespaceName.Split('.') {
            if segment.Length > 0 {
                names.Add(segment)
            }
        }
    }

    // Identifier-shaped words: a letter or `_`, then letters, digits and `_`.
    static func AddWords(words: HashSet<string>, text: string) {
        index := 0
        length := text.Length
        while index < length {
            ch := text[index]
            if char.IsLetter(ch) || ch == '_' {
                start := index
                index = index + 1
                while index < length && (char.IsLetterOrDigit(text[index]) || text[index] == '_') {
                    index = index + 1
                }
                words.Add(text.Substring(start, index - start))
            } else {
                index = index + 1
            }
        }
    }
}

// THE STRUCTURAL WALK OF ONE FILE'S DECLARATIONS, outside function bodies. Every string the AST
// holds is either a name the file DECLARES — the `Name` of a declaration, an enum member, a union
// case or one of its properties, or a primary-constructor parameter (those become members) — or a
// word the file REFERS to: a type reference, an attribute, an identifier in an initializer or a
// default value. Function parameters and type parameters declare nothing another file can look up,
// so their names are neither. The bodies the surface hash strips (a declaration's `Body`, `GetBody`
// and `SetBody`) are not walked; a lambda's body inside an initializer is.
//
// Reflection, not a list of node kinds: a declaration kind or a property added to the AST later is
// walked without anyone remembering to. A walk that hits its depth limit sets `Truncated`, and the
// summary is then opaque rather than silently incomplete.
class IncrementalDeclarationWalk {
    Declared: HashSet<string>
    Referenced: HashSet<string>
    BaseNames: HashSet<string>
    Truncated: bool

    constructor() {
        Declared = new HashSet<string>(StringComparer.Ordinal)
        Referenced = new HashSet<string>(StringComparer.Ordinal)
        BaseNames = new HashSet<string>(StringComparer.Ordinal)
        Truncated = false
    }

    func Visit(node: object?, inBaseList: bool, depth: int) {
        if node == null {
            return
        }
        if depth > 512 {
            Truncated = true
            return
        }

        text := node as string
        if text != null {
            IncrementalFileSummary.AddWords(Referenced, text)
            if inBaseList {
                IncrementalFileSummary.AddWords(BaseNames, text)
            }
            return
        }

        sequence := node as IEnumerable
        if sequence != null {
            for item in sequence {
                Visit(item, inBaseList, depth + 1)
            }
            return
        }

        nodeType := node.GetType()
        if !IncrementalDeclarationWalk.IsAstType(nodeType) {
            return
        }

        isDeclaration := node is Declaration
        declaresName := isDeclaration || node is EnumMember || node is UnionCase || node is UnionCaseProperty
        flags := BindingFlags.Public | BindingFlags.Instance
        for field in nodeType.GetFields(flags) {
            VisitMember(node, field.Name, field.GetValue(node), isDeclaration, declaresName, inBaseList, depth)
        }
        for property in nodeType.GetProperties(flags) {
            if property.GetIndexParameters().Length != 0 || !property.CanRead {
                continue
            }
            VisitMember(node, property.Name, property.GetValue(node), isDeclaration, declaresName, inBaseList, depth)
        }
    }

    private func VisitMember(node: object, memberName: string, value: object?, isDeclaration: bool, declaresName: bool, inBaseList: bool, depth: int) {
        if value == null {
            return
        }
        if isDeclaration && (memberName == "Body" || memberName == "GetBody" || memberName == "SetBody") {
            return
        }
        if memberName == "TypeParameters" {
            return
        }

        nameText := value as string
        if nameText != null {
            if memberName == "Name" && declaresName {
                Declared.Add(nameText)
            } else if memberName == "Name" && node is Parameter {
                return
            } else {
                Visit(nameText, inBaseList, depth + 1)
            }
            return
        }

        if memberName == "PrimaryConstructorParameters" {
            VisitPrimaryParameters(value, depth + 1)
            return
        }

        if !IncrementalDeclarationWalk.IsWalkable(value) {
            return
        }

        childInBaseList := inBaseList || memberName == "BaseClass" || memberName == "Interfaces" || memberName == "BaseInterfaces"
        Visit(value, childInBaseList, depth + 1)
    }

    // A record's or class's positional parameters are members: their names are declared, and their
    // types and defaults are referenced like any signature's.
    private func VisitPrimaryParameters(value: object, depth: int) {
        parameters := value as IEnumerable
        if parameters == null {
            return
        }

        for item in parameters {
            parameter := item as Parameter
            if parameter != null {
                Declared.Add(parameter.Name)
            }
            Visit(item, false, depth + 1)
        }
    }

    // A value worth walking: an AST object, or a collection holding them.
    static func IsWalkable(value: object): bool {
        valueType := value.GetType()
        if IncrementalDeclarationWalk.IsAstType(valueType) {
            return true
        }

        if valueType.IsGenericType {
            for argument in valueType.GetGenericArguments() {
                if IncrementalDeclarationWalk.IsAstType(argument) {
                    return true
                }
                if argument.IsGenericType {
                    for nested in argument.GetGenericArguments() {
                        if IncrementalDeclarationWalk.IsAstType(nested) {
                            return true
                        }
                    }
                }
            }
        }

        return false
    }

    static func IsAstType(type: Type): bool {
        namespaceName := type.Namespace ?? ""
        return namespaceName == "NSharpLang.Compiler.Ast"
    }
}
