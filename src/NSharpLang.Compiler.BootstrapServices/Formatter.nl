namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Text
import NSharpLang.Compiler.Ast


// THE FORMATTER ITSELF: THE FILE, ITS DECLARATIONS AND THE TWO SAFETY GATES.
//
// Four slices took `Formatter.cs` apart in the order its own call graph allowed, and this owner is
// what the fourth one found at the bottom:
//
//   * slice 17 took the STATE — the indent depth, the comment stream, the two position cursors and
//     the two configured constants — into `FormatterWalkState`;
//   * slice 18 took the LEAF TEXT — the type reference, the modifier list and the `allow` header —
//     into `FormatterSyntaxText`;
//   * slice 19 took the BODY WALK — every statement, every expression and every pattern — into
//     `FormatterWalk`;
//   * this owner takes what those three left: the file's own head (namespace, imports, package),
//     the declaration walk with its nineteen arms, and `FormatSafe`'s two safety gates. With it
//     `Formatter.cs` is DELETED, and the type keeps its name, its namespace and its signatures, so
//     every consumer — `Program.cs`, `DocumentFormattingHandler.cs` and `PlaygroundCompiler.cs` —
//     reads code-for-code against this type instead. That is the `Linter.cs` precedent exactly.
//
// THE STATE IS OWNED HERE AND BORROWED BY THE WALK. A declaration formatter and a statement arm are
// one walk at two depths: they must agree about the indent depth and the comment cursor to the
// character, so `Formatter` constructs the one `FormatterWalkState` and hands it to `FormatterWalk`.
// Building the walk its own carrier compiles and type-checks and is WRONG — it silently loses the
// depth at every declaration boundary.
//
// EVERY MEMBER BELOW WAS PRIVATE IN C# AND IS PUBLIC HERE, WHICH IS THE POINT. `Formatter`'s C#
// surface was "give me a whole formatted file", so not one of the declaration arms could be stated
// as a contract; `Formatter.tests.nl` now states them one at a time. The other half — the whole-file
// contract a user actually experiences — is `FormatterSourceText.tests.nl`, which replaced
// `tests/FormatterTests.cs`; neither half subsumes the other.
class Formatter {
    state: FormatterWalkState
    walk: FormatterWalk

    // A null configuration is the default configuration. The parameter keeps its default so
    // `new Formatter()` — which the playground, the tests and the format command all write — still
    // binds; N# call sites must pass it explicitly (gotcha 85.5), and both of this file's own do.
    constructor(config: FormatterConfig? = null) {
        state = new FormatterWalkState(config)
        walk = new FormatterWalk(state)
    }

    // ---- the safety gates ------------------------------------------------------------------------

    // Format source safely: format the AST, then prove the output re-parses without errors and is
    // idempotent. If either gate fails, return the ORIGINAL source with a warning.
    //
    // THIS IS THE ONLY MEMBER IN THE FILE THAT IS NOT A WALK, AND BOTH ITS GATES ARE LOAD-BEARING.
    // A formatter that emits text the parser cannot read would destroy a file on save; a formatter
    // that is not idempotent would make every save produce a fresh diff. Neither is a theoretical
    // risk — the reparse gate really does reject a file today, and it does so identically here and
    // in the C# this replaces.
    //
    // THE LEXER RUN IS NOT DEAD. `Tokenize` is called for its EFFECT: it populates `Comments`, and
    // the second format needs the comment stream of the FORMATTED text, not of the original.
    func FormatSafe(originalSource: string, ast: CompilationUnit, comments: List<CommentTrivia>? = null, fileName: string = "formatted.nl"): FormatResult {
        warnings := new List<string>()

        formatted := Format(ast, comments)
        lexer := new Lexer(formatted, fileName)
        lexer.Tokenize()
        reparseResult := ColumnarParserRecovery.ParseFileAst(formatted, fileName)

        if HasReparseError(reparseResult.Errors) {
            errorMessages := JoinErrorMessages(reparseResult.Errors)
            warnings.Add("Formatter would produce invalid output (reparse errors: " + errorMessages + "). Returning original source.")
            return FailedResult(originalSource, warnings)
        }

        // Safety gate 2: idempotence — format the output again and require an identical result.
        reformatter := new Formatter(state.RebuildConfig())
        reparsedUnit := reparseResult.CompilationUnit
        if reparsedUnit == null {
            // The C# wrote `reparseResult.CompilationUnit!` and dereferenced it, so a null unit with
            // no error diagnostics threw `NullReferenceException` from inside `Format`. The type is
            // reproduced here rather than the message, because a null-forgiving read is not a shape
            // this backend carries. The arm is unreachable through the recovery parser.
            throw new NullReferenceException()
        }

        reformatted := reformatter.Format(reparsedUnit, lexer.Comments)

        if !string.Equals(formatted, reformatted, StringComparison.Ordinal) {
            warnings.Add("Formatter output is not idempotent (formatting again produces different output). Returning original source.")
            return FailedResult(originalSource, warnings)
        }

        result := new FormatResult()
        result.Text = formatted
        result.Success = true
        result.Warnings = warnings
        return result
    }

    // The rejected-output result, which both gates return with a different warning already added.
    static func FailedResult(originalSource: string, warnings: List<string>): FormatResult {
        result := new FormatResult()
        result.Text = originalSource
        result.Success = false
        result.Warnings = warnings
        return result
    }

    // `errors.Any(e => e.Severity == ErrorSeverity.Error)`, written out. A WARNING IS NOT A GATE
    // FAILURE: the recovery parser reports plenty, and rejecting on them would refuse to format
    // most real files.
    static func HasReparseError(errors: List<CompilerError>): bool {
        index := 0
        while index < errors.Count {
            if errors[index].Severity == ErrorSeverity.Error {
                return true
            }

            index = index + 1
        }

        return false
    }

    // `string.Join("; ", errors.Where(…).Select(e => e.Message))`, written out. The warnings are
    // filtered to errors a second time, exactly as the C# did, so a warning's message never appears
    // in the text that explains why the file was rejected.
    static func JoinErrorMessages(errors: List<CompilerError>): string {
        builder := new StringBuilder()
        written := 0
        index := 0
        while index < errors.Count {
            error := errors[index]
            if error.Severity == ErrorSeverity.Error {
                if written > 0 {
                    builder.Append("; ")
                }

                builder.Append(error.Message)
                written = written + 1
            }

            index = index + 1
        }

        return builder.ToString()
    }

    // ---- the file --------------------------------------------------------------------------------

    // One whole file: the namespace, the imports, the package, then every declaration.
    //
    // THE ORDER IS THE GRAMMAR'S AND NOT THE AST'S. `package` is written AFTER the imports even
    // though the parser accepts it before them, because that is the order the language spells and
    // the order a re-parse of this output has to accept.
    //
    // BLANK LINES ARE PRESERVED FROM THE SOURCE, AND THE GAP IS MEASURED FROM A DECLARATION'S
    // *END* LINE. Measuring from its start counts a multi-line body as a phantom gap, and the
    // second format then adds a blank line the first did not — which is precisely what
    // `FormatSafe`'s idempotence gate would catch.
    func Format(ast: CompilationUnit, comments: List<CommentTrivia>? = null): string {
        state.BeginFile(comments)
        tracker := state
        builder := new StringBuilder()

        astNamespace := ast.Namespace
        if astNamespace != null {
            state.EmitCommentsBefore(astNamespace.Line, builder)
            if state.HasBlankLineBefore(astNamespace.Line) {
                builder.AppendLine()
            }

            builder.Append("namespace ")
            builder.AppendLine(astNamespace.Name)
            tracker.LastEmittedSourceLine = astNamespace.Line
            builder.AppendLine()
        }

        sortedImports := FormatterImportOrderer.OrderBySystemThenNamespace(ast.Imports)

        index := 0
        while index < sortedImports.Count {
            importDirective := sortedImports[index]
            state.EmitCommentsBefore(importDirective.Line, builder)
            builder.Append("import ")
            builder.Append(importDirective.Namespace)
            importAlias := importDirective.Alias
            if importAlias != null {
                builder.Append(" as ")
                builder.Append(importAlias)
            }

            builder.AppendLine()
            tracker.LastEmittedSourceLine = importDirective.Line
            index = index + 1
        }

        index = 0
        while index < ast.FileImports.Count {
            fileImport := ast.FileImports[index] as FileImport
            if fileImport != null {
                state.EmitCommentsBefore(fileImport.Line, builder)
                builder.Append("import \"")
                builder.Append(fileImport.Path)
                builder.Append("\"")
                fileImportAlias := fileImport.Alias
                if fileImportAlias != null {
                    builder.Append(" as ")
                    builder.Append(fileImportAlias)
                }

                builder.AppendLine()
                tracker.LastEmittedSourceLine = fileImport.Line
            }

            index = index + 1
        }

        if ast.Imports.Count > 0 || ast.FileImports.Count > 0 {
            builder.AppendLine()
        }

        astPackage := ast.Package
        if astPackage != null {
            state.EmitCommentsBefore(astPackage.Line, builder)
            builder.Append("package ")
            builder.AppendLine(astPackage.Name)
            tracker.LastEmittedSourceLine = astPackage.Line
            builder.AppendLine()
        }

        index = 0
        while index < ast.Declarations.Count {
            declaration := ast.Declarations[index]
            state.EmitCommentsBefore(declaration.Line, builder)
            // The tracker accounts for any comments just emitted, so a comment closes the gap it
            // stood in and the blank line is not written twice.
            if index > 0 && state.HasBlankLineBefore(declaration.Line) {
                builder.AppendLine()
            }

            FormatDeclaration(declaration, builder)
            tracker.LastEmittedSourceLine = declaration.EndLine
            index = index + 1
        }

        state.EmitRemainingComments(builder)

        return builder.ToString()
    }

    // ---- the declaration walk --------------------------------------------------------------------

    // A member list — a class, struct, record or interface body — with the comments and blank lines
    // the source had between its members. It is `Format`'s declaration loop minus the file head,
    // and the `i > 0` guard is what keeps a body from opening with a blank line.
    func FormatMembers(members: List<Declaration>, builder: StringBuilder) {
        tracker := state
        index := 0
        while index < members.Count {
            member := members[index]
            state.EmitCommentsBefore(member.Line, builder)
            if index > 0 && state.HasBlankLineBefore(member.Line) {
                builder.AppendLine()
            }

            FormatDeclaration(member, builder)
            tracker.LastEmittedSourceLine = member.EndLine
            index = index + 1
        }
    }

    // The nineteen-arm dispatch: every declaration the language has, at file scope or in a body.
    //
    // THREE ARMS ARE INLINE BECAUSE THEY ARE ONE LINE OF TEXT EACH — a type alias, a newtype and a
    // preprocessor directive have no structure to walk. The function arm is the walk's, not this
    // owner's: a function body is statements.
    func FormatDeclaration(declaration: Declaration, builder: StringBuilder) {
        functionDeclaration := declaration as FunctionDeclaration
        if functionDeclaration != null {
            walk.FormatFunction(functionDeclaration, builder)
            return
        }

        classDeclaration := declaration as ClassDeclaration
        if classDeclaration != null {
            FormatClass(classDeclaration, builder)
            return
        }

        structDeclaration := declaration as StructDeclaration
        if structDeclaration != null {
            FormatStruct(structDeclaration, builder)
            return
        }

        recordDeclaration := declaration as RecordDeclaration
        if recordDeclaration != null {
            FormatRecord(recordDeclaration, builder)
            return
        }

        soaRecordDeclaration := declaration as SoaRecordDeclaration
        if soaRecordDeclaration != null {
            FormatSoaRecord(soaRecordDeclaration, builder)
            return
        }

        interfaceDeclaration := declaration as InterfaceDeclaration
        if interfaceDeclaration != null {
            FormatInterface(interfaceDeclaration, builder)
            return
        }

        unionDeclaration := declaration as UnionDeclaration
        if unionDeclaration != null {
            FormatUnion(unionDeclaration, builder)
            return
        }

        enumDeclaration := declaration as EnumDeclaration
        if enumDeclaration != null {
            FormatEnum(enumDeclaration, builder)
            return
        }

        fieldDeclaration := declaration as FieldDeclaration
        if fieldDeclaration != null {
            FormatField(fieldDeclaration, builder)
            return
        }

        propertyDeclaration := declaration as PropertyDeclaration
        if propertyDeclaration != null {
            FormatProperty(propertyDeclaration, builder)
            return
        }

        constructorDeclaration := declaration as ConstructorDeclaration
        if constructorDeclaration != null {
            FormatConstructor(constructorDeclaration, builder)
            return
        }

        indexerDeclaration := declaration as IndexerDeclaration
        if indexerDeclaration != null {
            FormatIndexer(indexerDeclaration, builder)
            return
        }

        typeAliasDeclaration := declaration as TypeAliasDeclaration
        if typeAliasDeclaration != null {
            state.Indent(builder)
            builder.Append("type ")
            builder.Append(typeAliasDeclaration.Name)
            builder.Append(" = ")
            builder.AppendLine(FormatterSyntaxText.FormatTypeReference(typeAliasDeclaration.Type))
            return
        }

        testDeclaration := declaration as TestDeclaration
        if testDeclaration != null {
            FormatTest(testDeclaration, builder)
            return
        }

        setupDeclaration := declaration as SetupDeclaration
        if setupDeclaration != null {
            FormatSetup(setupDeclaration, builder)
            return
        }

        teardownDeclaration := declaration as TeardownDeclaration
        if teardownDeclaration != null {
            FormatTeardown(teardownDeclaration, builder)
            return
        }

        newtypeDeclaration := declaration as NewtypeDeclaration
        if newtypeDeclaration != null {
            state.Indent(builder)
            builder.Append("type ")
            builder.Append(newtypeDeclaration.Name)
            builder.Append(" = newtype ")
            builder.AppendLine(FormatterSyntaxText.FormatTypeReference(newtypeDeclaration.UnderlyingType))
            return
        }

        preprocessorDeclaration := declaration as PreprocessorDeclaration
        if preprocessorDeclaration != null {
            state.Indent(builder)
            builder.AppendLine(preprocessorDeclaration.Directive)
            return
        }

        FormatterWalk.ThrowUnhandled("declaration", declaration)
    }

    // The modifier prefix every named declaration shares: the keywords, then one space, and nothing
    // at all when they all dropped out. `FormatModifiers` decides which survive; this only spaces
    // them, and the emptiness test is what keeps a bare `class Foo` from opening with a space.
    func AppendModifiers(modifiers: Modifiers, identifierName: string?, builder: StringBuilder) {
        text := FormatterSyntaxText.FormatModifiers(modifiers, identifierName, true)
        if !string.IsNullOrEmpty(text) {
            builder.Append(text)
            builder.Append(" ")
        }
    }

    // A primary constructor's parameter list, or nothing. AN EMPTY LIST WRITES NO PARENTHESES:
    // `class Foo {` and `class Foo() {` are different source, and a record with no positional
    // parameters is spelled without them.
    func AppendPrimaryConstructorParameters(parameters: List<Parameter>?, builder: StringBuilder) {
        if parameters == null {
            return
        }

        if parameters.Count == 0 {
            return
        }

        builder.Append("(")
        index := 0
        while index < parameters.Count {
            walk.FormatParameter(parameters[index], builder)
            if index < parameters.Count - 1 {
                builder.Append(", ")
            }

            index = index + 1
        }

        builder.Append(")")
    }

    // A `: A, B` base list, or nothing.
    func AppendBaseList(types: List<TypeReference>, builder: StringBuilder) {
        if types.Count == 0 {
            return
        }

        builder.Append(": ")
        FormatterSyntaxText.AppendTypeList(builder, types, ", ")
    }

    // A braced member body at one greater depth, with its closing brace back at this one.
    func AppendMemberBody(members: List<Declaration>, builder: StringBuilder) {
        builder.AppendLine(" {")
        state.Push()
        FormatMembers(members, builder)
        state.Pop()
        state.Indent(builder)
        builder.AppendLine("}")
    }

    // ---- the type declarations -------------------------------------------------------------------

    // A class: attributes, modifiers, name, type parameters, primary constructor, bases, body.
    //
    // THE BASE CLASS AND THE INTERFACES SHARE ONE `:` LIST and the base class comes first, because
    // the grammar has one list and not two.
    func FormatClass(classDeclaration: ClassDeclaration, builder: StringBuilder) {
        walk.FormatAttributes(classDeclaration.Attributes, builder)
        state.Indent(builder)
        AppendModifiers(classDeclaration.Modifiers, classDeclaration.Name, builder)

        builder.Append("class ")
        builder.Append(classDeclaration.Name)
        walk.AppendTypeParameters(classDeclaration.TypeParameters, builder)
        AppendPrimaryConstructorParameters(classDeclaration.PrimaryConstructorParameters, builder)

        bases := new List<TypeReference>()
        baseClass := classDeclaration.BaseClass
        if baseClass != null {
            bases.Add(baseClass)
        }

        index := 0
        while index < classDeclaration.Interfaces.Count {
            bases.Add(classDeclaration.Interfaces[index])
            index = index + 1
        }

        AppendBaseList(bases, builder)
        AppendMemberBody(classDeclaration.Members, builder)
    }

    // A struct, which is a class whose keyword may be two words and which has no base class.
    func FormatStruct(structDeclaration: StructDeclaration, builder: StringBuilder) {
        walk.FormatAttributes(structDeclaration.Attributes, builder)
        state.Indent(builder)
        AppendModifiers(structDeclaration.Modifiers, structDeclaration.Name, builder)

        builder.Append(structDeclaration.IsRefStruct ? "ref struct " : "struct ")
        builder.Append(structDeclaration.Name)
        walk.AppendTypeParameters(structDeclaration.TypeParameters, builder)
        AppendPrimaryConstructorParameters(structDeclaration.PrimaryConstructorParameters, builder)
        AppendBaseList(structDeclaration.Interfaces, builder)
        AppendMemberBody(structDeclaration.Members, builder)
    }

    // A record, whose `struct` is a SECOND keyword rather than a different one.
    //
    // THE BRACED BODY IS UNCONDITIONAL. The grammar requires it, so a record with no members still
    // writes ` {` and `}` — and an empty body is the common case for a positional record.
    func FormatRecord(recordDeclaration: RecordDeclaration, builder: StringBuilder) {
        walk.FormatAttributes(recordDeclaration.Attributes, builder)
        state.Indent(builder)
        AppendModifiers(recordDeclaration.Modifiers, recordDeclaration.Name, builder)

        builder.Append("record ")
        if recordDeclaration.IsStruct {
            builder.Append("struct ")
        }

        builder.Append(recordDeclaration.Name)
        walk.AppendTypeParameters(recordDeclaration.TypeParameters, builder)
        AppendPrimaryConstructorParameters(recordDeclaration.PrimaryConstructorParameters, builder)
        AppendBaseList(recordDeclaration.Interfaces, builder)
        AppendMemberBody(recordDeclaration.Members, builder)
    }

    // A struct-of-arrays record. ITS COLUMNS ARE NOT MEMBERS: they are a name and a type each, with
    // no modifiers, no attributes and no bodies, so they are written here rather than dispatched.
    func FormatSoaRecord(soaRecordDeclaration: SoaRecordDeclaration, builder: StringBuilder) {
        walk.FormatAttributes(soaRecordDeclaration.Attributes, builder)
        state.Indent(builder)
        AppendModifiers(soaRecordDeclaration.Modifiers, soaRecordDeclaration.Name, builder)

        builder.Append("soa record ")
        builder.Append(soaRecordDeclaration.Name)
        builder.AppendLine(" {")
        state.Push()
        index := 0
        while index < soaRecordDeclaration.Columns.Count {
            column := soaRecordDeclaration.Columns[index]
            state.Indent(builder)
            builder.Append(column.Name)
            builder.Append(": ")
            builder.Append(FormatterSyntaxText.FormatTypeReference(column.Type))
            builder.AppendLine()
            index = index + 1
        }

        state.Pop()
        state.Indent(builder)
        builder.AppendLine("}")
    }

    // An interface, whose `duck` prefix sits between the modifiers and the keyword.
    func FormatInterface(interfaceDeclaration: InterfaceDeclaration, builder: StringBuilder) {
        walk.FormatAttributes(interfaceDeclaration.Attributes, builder)
        state.Indent(builder)
        AppendModifiers(interfaceDeclaration.Modifiers, interfaceDeclaration.Name, builder)

        if interfaceDeclaration.IsDuckInterface {
            builder.Append("duck ")
        }

        builder.Append("interface ")
        builder.Append(interfaceDeclaration.Name)
        walk.AppendTypeParameters(interfaceDeclaration.TypeParameters, builder)
        AppendBaseList(interfaceDeclaration.BaseInterfaces, builder)
        AppendMemberBody(interfaceDeclaration.Members, builder)
    }

    // A union. ITS CASES ARE NOT MEMBERS EITHER: a case is a name and an optional inline property
    // list, written on one line, and a case with no properties writes no braces at all.
    func FormatUnion(unionDeclaration: UnionDeclaration, builder: StringBuilder) {
        walk.FormatAttributes(unionDeclaration.Attributes, builder)
        state.Indent(builder)
        AppendModifiers(unionDeclaration.Modifiers, unionDeclaration.Name, builder)

        builder.Append("union ")
        builder.Append(unionDeclaration.Name)
        walk.AppendTypeParameters(unionDeclaration.TypeParameters, builder)
        builder.AppendLine(" {")

        state.Push()
        index := 0
        while index < unionDeclaration.Cases.Count {
            unionCase := unionDeclaration.Cases[index]
            state.Indent(builder)
            builder.Append(unionCase.Name)

            caseProperties := unionCase.Properties
            if caseProperties != null && caseProperties.Count > 0 {
                builder.Append(" { ")
                propertyIndex := 0
                while propertyIndex < caseProperties.Count {
                    caseProperty := caseProperties[propertyIndex]
                    builder.Append(caseProperty.Name)
                    builder.Append(": ")
                    builder.Append(FormatterSyntaxText.FormatTypeReference(caseProperty.Type))
                    if propertyIndex < caseProperties.Count - 1 {
                        builder.Append(", ")
                    }

                    propertyIndex = propertyIndex + 1
                }

                builder.Append(" }")
            }

            builder.AppendLine()
            index = index + 1
        }

        state.Pop()

        state.Indent(builder)
        builder.AppendLine("}")
    }

    // An enum. THE TRAILING COMMA IS OMITTED ON THE LAST MEMBER, and a string-backed enum announces
    // itself with `: string` — the only backing type the language spells.
    func FormatEnum(enumDeclaration: EnumDeclaration, builder: StringBuilder) {
        walk.FormatAttributes(enumDeclaration.Attributes, builder)
        state.Indent(builder)
        AppendModifiers(enumDeclaration.Modifiers, enumDeclaration.Name, builder)

        builder.Append("enum ")
        builder.Append(enumDeclaration.Name)

        if enumDeclaration.Type == EnumType.String {
            builder.Append(": string")
        }

        builder.AppendLine(" {")

        state.Push()
        index := 0
        while index < enumDeclaration.Members.Count {
            member := enumDeclaration.Members[index]
            state.Indent(builder)
            builder.Append(member.Name)

            memberValue := member.Value
            if memberValue != null {
                builder.Append(" = ")
                walk.FormatExpression(memberValue, builder)
            }

            if index < enumDeclaration.Members.Count - 1 {
                builder.Append(",")
            }

            builder.AppendLine()
            index = index + 1
        }

        state.Pop()

        state.Indent(builder)
        builder.AppendLine("}")
    }

    // ---- the member declarations -----------------------------------------------------------------

    // A field. THE TWO ASSIGNMENT SPELLINGS ARE THE WHOLE ARM: `:=` infers the type and `=` states
    // it, so a field with an initializer and no written type gets `:=` and one with both gets `=`.
    func FormatField(fieldDeclaration: FieldDeclaration, builder: StringBuilder) {
        walk.FormatAttributes(fieldDeclaration.Attributes, builder)
        state.Indent(builder)
        AppendModifiers(fieldDeclaration.Modifiers, fieldDeclaration.Name, builder)

        builder.Append(fieldDeclaration.Name)

        fieldType := fieldDeclaration.Type
        if fieldType != null {
            builder.Append(": ")
            builder.Append(FormatterSyntaxText.FormatTypeReference(fieldType))
        }

        initializer := fieldDeclaration.Initializer
        if initializer != null {
            if fieldType == null {
                builder.Append(" := ")
            } else {
                builder.Append(" = ")
            }

            walk.FormatExpression(initializer, builder)
        }

        builder.AppendLine()
    }

    // A property, in one of its three shapes: an expression body, an accessor block, or neither —
    // which is an auto-property and writes nothing after its type.
    func FormatProperty(propertyDeclaration: PropertyDeclaration, builder: StringBuilder) {
        walk.FormatAttributes(propertyDeclaration.Attributes, builder)
        state.Indent(builder)
        AppendModifiers(propertyDeclaration.Modifiers, propertyDeclaration.Name, builder)

        builder.Append(propertyDeclaration.Name)
        builder.Append(": ")
        builder.Append(FormatterSyntaxText.FormatTypeReference(propertyDeclaration.Type))

        expressionBody := propertyDeclaration.ExpressionBody
        getBody := propertyDeclaration.GetBody
        setBody := propertyDeclaration.SetBody

        if expressionBody != null {
            builder.Append(" => ")
            walk.FormatExpression(expressionBody, builder)
            builder.AppendLine()
        } else if getBody != null || setBody != null {
            builder.AppendLine(" {")
            state.Push()

            if getBody != null {
                AppendAccessor("get {", getBody, builder)
            }

            if setBody != null {
                AppendAccessor("set {", setBody, builder)
            }

            state.Pop()
            state.Indent(builder)
            builder.AppendLine("}")
        } else {
            builder.AppendLine()
        }
    }

    // One `get { … }` or `set { … }` accessor, at the depth its owner already pushed to.
    func AppendAccessor(header: string, body: BlockStatement, builder: StringBuilder) {
        state.Indent(builder)
        builder.AppendLine(header)
        state.Push()
        walk.FormatBlock(body, builder)
        state.Pop()
        state.Indent(builder)
        builder.AppendLine("}")
    }

    // A constructor. IT HAS NO NAME AND NO RETURN TYPE, and its initializer — `: base(x)` or
    // `: this(x)` — is an EXPRESSION, so the walk writes it.
    func FormatConstructor(constructorDeclaration: ConstructorDeclaration, builder: StringBuilder) {
        walk.FormatAttributes(constructorDeclaration.Attributes, builder)
        state.Indent(builder)
        AppendModifiers(constructorDeclaration.Modifiers, null, builder)

        builder.Append("constructor(")
        AppendParameterList(constructorDeclaration.Parameters, builder)
        builder.Append(")")

        initializer := constructorDeclaration.Initializer
        if initializer != null {
            builder.Append(": ")
            walk.FormatExpression(initializer, builder)
        }

        builder.AppendLine(" {")
        state.Push()
        walk.FormatBlock(constructorDeclaration.Body, builder)
        state.Pop()
        state.Indent(builder)
        builder.AppendLine("}")
    }

    // A comma-separated parameter list with no brackets of its own; the caller writes those,
    // because a constructor's are round and an indexer's are square.
    func AppendParameterList(parameters: List<Parameter>, builder: StringBuilder) {
        index := 0
        while index < parameters.Count {
            walk.FormatParameter(parameters[index], builder)
            if index < parameters.Count - 1 {
                builder.Append(", ")
            }

            index = index + 1
        }
    }

    // An indexer: `this[i: int]: T { get { … } set { … } }`.
    //
    // ITS BRACED BODY IS UNCONDITIONAL where a property's is not — an indexer with neither accessor
    // still writes ` {` and `}`, which is the C# exactly and is what the grammar accepts back.
    func FormatIndexer(indexerDeclaration: IndexerDeclaration, builder: StringBuilder) {
        walk.FormatAttributes(indexerDeclaration.Attributes, builder)
        state.Indent(builder)
        AppendModifiers(indexerDeclaration.Modifiers, null, builder)

        builder.Append("this[")
        AppendParameterList(indexerDeclaration.Parameters, builder)
        builder.Append("]: ")
        builder.Append(FormatterSyntaxText.FormatTypeReference(indexerDeclaration.Type))
        builder.AppendLine(" {")

        state.Push()
        getBody := indexerDeclaration.GetBody
        if getBody != null {
            AppendAccessor("get {", getBody, builder)
        }

        setBody := indexerDeclaration.SetBody
        if setBody != null {
            AppendAccessor("set {", setBody, builder)
        }

        state.Pop()

        state.Indent(builder)
        builder.AppendLine("}")
    }

    // ---- the test declarations -------------------------------------------------------------------

    // A test. ITS DESCRIPTION IS WRAPPED IN QUOTES AND NOT ESCAPED — that is the C# exactly, and it
    // is why a description containing a quote is a source-level problem rather than a formatter one.
    //
    // A TABLE-DRIVEN TEST NEEDS BOTH HALVES. The parameter list and the case rows are separate
    // nullable fields and the header is written only when both are present, because a `with (…)`
    // with no rows and rows with no parameters are both unparseable.
    func FormatTest(testDeclaration: TestDeclaration, builder: StringBuilder) {
        state.Indent(builder)
        builder.Append("test ")
        builder.Append("\"")
        builder.Append(testDeclaration.Description)
        builder.Append("\"")

        tableParameters := testDeclaration.TableParameters
        tableCases := testDeclaration.TableCases
        if tableParameters != null && tableCases != null {
            builder.Append(" with (")
            parameterIndex := 0
            while parameterIndex < tableParameters.Count {
                if parameterIndex > 0 {
                    builder.Append(", ")
                }

                tableParameter := tableParameters[parameterIndex]
                builder.Append(tableParameter.Name)
                builder.Append(": ")
                builder.Append(FormatterSyntaxText.FormatTypeReference(tableParameter.Type))
                parameterIndex = parameterIndex + 1
            }

            builder.AppendLine(") [")
            state.Push()
            caseIndex := 0
            while caseIndex < tableCases.Count {
                state.Indent(builder)
                builder.Append("(")
                expressions := tableCases[caseIndex]
                expressionIndex := 0
                while expressionIndex < expressions.Count {
                    if expressionIndex > 0 {
                        builder.Append(", ")
                    }

                    // A THROWAWAY BUILDER PER EXPRESSION, exactly as the C# wrote it. The state is
                    // NOT snapshotted around it — `FormatExpressionToString` would, and the
                    // difference is observable whenever an expression touches the comment cursor.
                    temporary := new StringBuilder()
                    walk.FormatExpression(expressions[expressionIndex], temporary)
                    builder.Append(temporary.ToString())
                    expressionIndex = expressionIndex + 1
                }

                builder.Append(")")
                if caseIndex < tableCases.Count - 1 {
                    builder.Append(",")
                }

                builder.AppendLine()
                caseIndex = caseIndex + 1
            }

            state.Pop()
            state.Indent(builder)
            builder.Append("]")
        }

        skipReason := testDeclaration.SkipReason
        if skipReason != null {
            builder.Append(" skip \"")
            builder.Append(skipReason)
            builder.Append("\"")
        }

        builder.AppendLine(" {")
        state.Push()
        walk.FormatBlock(testDeclaration.Body, builder)
        state.Pop()
        state.Indent(builder)
        builder.AppendLine("}")
    }

    // `setup { … }` — a keyword and a block, with no name, no parameters and no attributes.
    func FormatSetup(setupDeclaration: SetupDeclaration, builder: StringBuilder) {
        AppendKeywordBody("setup {", setupDeclaration.Body, builder)
    }

    // `teardown { … }` — the same shape with the other keyword.
    func FormatTeardown(teardownDeclaration: TeardownDeclaration, builder: StringBuilder) {
        AppendKeywordBody("teardown {", teardownDeclaration.Body, builder)
    }

    // A bare keyword and a braced block at this declaration's own depth.
    func AppendKeywordBody(header: string, body: BlockStatement, builder: StringBuilder) {
        state.Indent(builder)
        builder.AppendLine(header)
        state.Push()
        walk.FormatBlock(body, builder)
        state.Pop()
        state.Indent(builder)
        builder.AppendLine("}")
    }
}
