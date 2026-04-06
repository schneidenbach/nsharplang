using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

/// <summary>
/// Result of a safe formatting operation.
/// </summary>
public class FormatResult
{
    /// <summary>The formatted (or original, if formatting was unsafe) source text.</summary>
    public required string Text { get; init; }

    /// <summary>True if the formatter produced valid output and the result is formatted text.</summary>
    public bool Success { get; init; }

    /// <summary>Warning messages about formatting issues (e.g., reparse failures).</summary>
    public List<string> Warnings { get; init; } = new();
}

public class Formatter
{
    private int _indent = 0;
    private readonly string _indentString;
    private readonly int _maxLineLength;
    private List<CommentTrivia> _comments = new();
    private int _commentIndex = 0;
    private int _lastEmittedSourceLine = 0;

    public Formatter(FormatterConfig? config = null)
    {
        config ??= new FormatterConfig();
        _indentString = config.GetIndentString();
        _maxLineLength = config.MaxLineLength;
    }

    /// <summary>
    /// Format source safely: formats the AST, then verifies the output re-parses without errors
    /// and is idempotent. If either check fails, returns the original source with warnings.
    /// </summary>
    public FormatResult FormatSafe(string originalSource, CompilationUnit ast, List<CommentTrivia>? comments = null, string fileName = "formatted.nl")
    {
        var warnings = new List<string>();

        try
        {
            var formatted = Format(ast, comments);
            var lexer = new Lexer(formatted, fileName);
            var tokens = lexer.Tokenize();
            var parser = new Parser(tokens, fileName, formatted);
            var reparseResult = parser.ParseCompilationUnit();

            if (reparseResult.Errors.Any(e => e.Severity == ErrorSeverity.Error))
            {
                var errorMessages = string.Join("; ", reparseResult.Errors.Where(e => e.Severity == ErrorSeverity.Error).Select(e => e.Message));
                warnings.Add($"Formatter would produce invalid output (reparse errors: {errorMessages}). Returning original source.");
                return new FormatResult { Text = originalSource, Success = false, Warnings = warnings };
            }

            // Safety gate 2: Idempotence check — format the output again and verify identical
            var reformatter = new Formatter(new FormatterConfig { IndentSize = _indentString.Contains('\t') ? 1 : _indentString.Length, UseSpaces = !_indentString.Contains('\t'), MaxLineLength = _maxLineLength });
            var reformatted = reformatter.Format(reparseResult.CompilationUnit!, lexer.Comments);

            if (!string.Equals(formatted, reformatted, StringComparison.Ordinal))
            {
                warnings.Add("Formatter output is not idempotent (formatting again produces different output). Returning original source.");
                return new FormatResult { Text = originalSource, Success = false, Warnings = warnings };
            }

            return new FormatResult { Text = formatted, Success = true, Warnings = warnings };
        }
        catch (Exception ex)
        {
            warnings.Add($"Formatter safety check failed ({ex.Message}). Returning original source.");
            return new FormatResult { Text = originalSource, Success = false, Warnings = warnings };
        }
    }

    public string Format(CompilationUnit ast, List<CommentTrivia>? comments = null)
    {
        _comments = comments ?? new List<CommentTrivia>();
        _commentIndex = 0;
        _lastEmittedSourceLine = 0;
        var sb = new StringBuilder();

        // Format package declaration
        if (ast.Package != null)
        {
            EmitCommentsBefore(ast.Package.Line, sb);
            if (_lastEmittedSourceLine > 0 && ast.Package.Line - _lastEmittedSourceLine > 1)
            {
                sb.AppendLine();
            }
            sb.AppendLine($"package {ast.Package.Name}");
            _lastEmittedSourceLine = ast.Package.Line;
            sb.AppendLine();
        }

        // Format namespace declaration
        if (ast.Namespace != null)
        {
            EmitCommentsBefore(ast.Namespace.Line, sb);
            if (_lastEmittedSourceLine > 0 && ast.Namespace.Line - _lastEmittedSourceLine > 1)
            {
                sb.AppendLine();
            }
            sb.AppendLine($"namespace {ast.Namespace.Name}");
            _lastEmittedSourceLine = ast.Namespace.Line;
            sb.AppendLine();
        }

        // Sort imports: System.* first, then alphabetical
        var sortedImports = ast.Imports
            .OrderByDescending(i => i.Namespace.StartsWith("System"))
            .ThenBy(i => i.Namespace)
            .ToList();

        // Format imports
        foreach (var import in sortedImports)
        {
            EmitCommentsBefore(import.Line, sb);
            sb.Append("import ");
            sb.Append(import.Namespace);
            if (import.Alias != null)
            {
                sb.Append($" as {import.Alias}");
            }
            sb.AppendLine();
            _lastEmittedSourceLine = import.Line;
        }

        // Format file imports
        foreach (var fileImport in ast.FileImports)
        {
            if (fileImport is FileImport fi)
            {
                EmitCommentsBefore(fi.Line, sb);
                sb.Append($"import \"{fi.Path}\"");
                if (fi.Alias != null)
                {
                    sb.Append($" as {fi.Alias}");
                }
                sb.AppendLine();
                _lastEmittedSourceLine = fi.Line;
            }
        }

        if (ast.Imports.Count > 0 || ast.FileImports.Count > 0)
        {
            sb.AppendLine();
        }

        // Format declarations with blank line preservation
        for (int i = 0; i < ast.Declarations.Count; i++)
        {
            var decl = ast.Declarations[i];
            EmitCommentsBefore(decl.Line, sb);
            if (i > 0 && _lastEmittedSourceLine > 0)
            {
                // Preserve blank lines between declarations based on source gap
                // Uses _lastEmittedSourceLine which accounts for any comments just emitted
                if (decl.Line - _lastEmittedSourceLine > 1)
                {
                    sb.AppendLine();
                }
            }
            FormatDeclaration(decl, sb);
            _lastEmittedSourceLine = decl.Line;
        }

        // Emit any trailing comments after all declarations
        EmitRemainingComments(sb);

        return sb.ToString();
    }

    /// <summary>
    /// Emit all comments whose line is before the given source line.
    /// </summary>
    private void EmitCommentsBefore(int beforeLine, StringBuilder sb)
    {
        while (_commentIndex < _comments.Count && _comments[_commentIndex].Line < beforeLine)
        {
            var comment = _comments[_commentIndex];
            // Preserve blank line before comment if source had one
            // (but only if we've already emitted content on a meaningful line)
            if (_lastEmittedSourceLine > 0 && comment.Line - _lastEmittedSourceLine > 1)
            {
                sb.AppendLine();
            }
            Indent(sb);
            sb.AppendLine(comment.Text);
            _lastEmittedSourceLine = comment.Line;
            _commentIndex++;
        }
    }

    /// <summary>
    /// Emit any remaining comments at the end of the file.
    /// </summary>
    private void EmitRemainingComments(StringBuilder sb)
    {
        while (_commentIndex < _comments.Count)
        {
            var comment = _comments[_commentIndex];
            if (comment.Line - _lastEmittedSourceLine > 1)
            {
                sb.AppendLine();
            }
            Indent(sb);
            sb.AppendLine(comment.Text);
            _lastEmittedSourceLine = comment.Line;
            _commentIndex++;
        }
    }

    /// <summary>
    /// Estimate the end line of a declaration (heuristic: next decl's line - 1).
    /// For declarations with bodies, we approximate using the start line.
    /// </summary>
    private static int GetEndLine(Declaration decl)
    {
        return decl.Line; // Conservative: use start line
    }

    /// <summary>
    /// Format a list of member declarations (e.g., inside a class/struct/interface),
    /// preserving comments and blank lines between members.
    /// </summary>
    private void FormatMembers(List<Declaration> members, StringBuilder sb)
    {
        for (int i = 0; i < members.Count; i++)
        {
            var member = members[i];
            EmitCommentsBefore(member.Line, sb);
            if (i > 0 && _lastEmittedSourceLine > 0 && member.Line - _lastEmittedSourceLine > 1)
            {
                sb.AppendLine();
            }
            FormatDeclaration(member, sb);
            _lastEmittedSourceLine = member.Line;
        }
    }

    private void FormatDeclaration(Declaration decl, StringBuilder sb)
    {
        switch (decl)
        {
            case FunctionDeclaration func:
                FormatFunction(func, sb);
                break;
            case ClassDeclaration cls:
                FormatClass(cls, sb);
                break;
            case StructDeclaration str:
                FormatStruct(str, sb);
                break;
            case RecordDeclaration rec:
                FormatRecord(rec, sb);
                break;
            case InterfaceDeclaration iface:
                FormatInterface(iface, sb);
                break;
            case UnionDeclaration union:
                FormatUnion(union, sb);
                break;
            case EnumDeclaration enumDecl:
                FormatEnum(enumDecl, sb);
                break;
            case FieldDeclaration field:
                FormatField(field, sb);
                break;
            case PropertyDeclaration prop:
                FormatProperty(prop, sb);
                break;
            case ConstructorDeclaration ctor:
                FormatConstructor(ctor, sb);
                break;
            case IndexerDeclaration indexer:
                FormatIndexer(indexer, sb);
                break;
            case TypeAliasDeclaration alias:
                Indent(sb);
                sb.AppendLine($"type {alias.Name} = {FormatTypeReference(alias.Type)}");
                break;
            case TestDeclaration test:
                FormatTest(test, sb);
                break;
            case SetupDeclaration setup:
                FormatSetup(setup, sb);
                break;
            case TeardownDeclaration teardown:
                FormatTeardown(teardown, sb);
                break;
            case NewtypeDeclaration newtype:
                Indent(sb);
                sb.AppendLine($"type {newtype.Name} = newtype {FormatTypeReference(newtype.UnderlyingType)}");
                break;
            case PreprocessorDeclaration preproc:
                Indent(sb);
                sb.AppendLine(preproc.Directive);
                break;
            default:
                throw new InvalidOperationException($"Formatter does not handle declaration type: {decl.GetType().Name}");
        }
    }

    private void FormatFunction(FunctionDeclaration func, StringBuilder sb)
    {
        Indent(sb);

        // Format modifiers
        var mods = FormatModifiers(func.Modifiers);
        if (!string.IsNullOrEmpty(mods))
        {
            sb.Append(mods);
            sb.Append(" ");
        }

        // Format function keyword
        if (func.Modifiers.HasFlag(Modifiers.Generator))
        {
            sb.Append("func*");
        }
        else
        {
            sb.Append("func");
        }

        sb.Append(" ");
        sb.Append(func.Name);

        // Format type parameters
        if (func.TypeParameters != null && func.TypeParameters.Count > 0)
        {
            sb.Append("<");
            sb.Append(string.Join(", ", func.TypeParameters.Select(tp => tp.Name)));
            sb.Append(">");
        }

        // Format parameters
        sb.Append("(");
        for (int i = 0; i < func.Parameters.Count; i++)
        {
            FormatParameter(func.Parameters[i], sb);
            if (i < func.Parameters.Count - 1)
            {
                sb.Append(", ");
            }
        }
        sb.Append(")");

        // Format return type
        if (func.ReturnType != null)
        {
            sb.Append(": ");
            sb.Append(FormatTypeReference(func.ReturnType));
        }

        // Format body
        if (func.ExpressionBody != null)
        {
            sb.Append(" => ");
            FormatExpression(func.ExpressionBody, sb);
            sb.AppendLine();
        }
        else if (func.Body != null)
        {
            sb.AppendLine(" {");
            _lastEmittedSourceLine = func.Line;
            _indent++;
            FormatBlock(func.Body, sb);
            _indent--;
            Indent(sb);
            sb.AppendLine("}");
        }
        else
        {
            sb.AppendLine();
        }
    }

    private void FormatClass(ClassDeclaration cls, StringBuilder sb)
    {
        Indent(sb);

        var mods = FormatModifiers(cls.Modifiers);
        if (!string.IsNullOrEmpty(mods))
        {
            sb.Append(mods);
            sb.Append(" ");
        }

        sb.Append("class ");
        sb.Append(cls.Name);

        if (cls.TypeParameters != null && cls.TypeParameters.Count > 0)
        {
            sb.Append("<");
            sb.Append(string.Join(", ", cls.TypeParameters.Select(tp => tp.Name)));
            sb.Append(">");
        }

        if (cls.PrimaryConstructorParameters != null && cls.PrimaryConstructorParameters.Count > 0)
        {
            sb.Append("(");
            for (int i = 0; i < cls.PrimaryConstructorParameters.Count; i++)
            {
                FormatParameter(cls.PrimaryConstructorParameters[i], sb);
                if (i < cls.PrimaryConstructorParameters.Count - 1)
                {
                    sb.Append(", ");
                }
            }
            sb.Append(")");
        }

        var bases = new List<string>();
        if (cls.BaseClass != null)
        {
            bases.Add(FormatTypeReference(cls.BaseClass));
        }
        bases.AddRange(cls.Interfaces.Select(FormatTypeReference));

        if (bases.Count > 0)
        {
            sb.Append(": ");
            sb.Append(string.Join(", ", bases));
        }

        sb.AppendLine(" {");
        _indent++;
        FormatMembers(cls.Members, sb);
        _indent--;
        Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatStruct(StructDeclaration str, StringBuilder sb)
    {
        Indent(sb);

        var mods = FormatModifiers(str.Modifiers);
        if (!string.IsNullOrEmpty(mods))
        {
            sb.Append(mods);
            sb.Append(" ");
        }

        sb.Append("struct ");
        sb.Append(str.Name);

        if (str.TypeParameters != null && str.TypeParameters.Count > 0)
        {
            sb.Append("<");
            sb.Append(string.Join(", ", str.TypeParameters.Select(tp => tp.Name)));
            sb.Append(">");
        }

        if (str.Interfaces.Count > 0)
        {
            sb.Append(": ");
            sb.Append(string.Join(", ", str.Interfaces.Select(FormatTypeReference)));
        }

        sb.AppendLine(" {");
        _indent++;
        FormatMembers(str.Members, sb);
        _indent--;
        Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatRecord(RecordDeclaration rec, StringBuilder sb)
    {
        Indent(sb);

        var mods = FormatModifiers(rec.Modifiers);
        if (!string.IsNullOrEmpty(mods))
        {
            sb.Append(mods);
            sb.Append(" ");
        }

        sb.Append("record ");
        if (rec.IsStruct)
        {
            sb.Append("struct ");
        }
        sb.Append(rec.Name);

        if (rec.TypeParameters != null && rec.TypeParameters.Count > 0)
        {
            sb.Append("<");
            sb.Append(string.Join(", ", rec.TypeParameters.Select(tp => tp.Name)));
            sb.Append(">");
        }

        if (rec.PrimaryConstructorParameters != null && rec.PrimaryConstructorParameters.Count > 0)
        {
            sb.Append("(");
            for (int i = 0; i < rec.PrimaryConstructorParameters.Count; i++)
            {
                FormatParameter(rec.PrimaryConstructorParameters[i], sb);
                if (i < rec.PrimaryConstructorParameters.Count - 1)
                {
                    sb.Append(", ");
                }
            }
            sb.Append(")");
        }

        if (rec.Interfaces.Count > 0)
        {
            sb.Append(": ");
            sb.Append(string.Join(", ", rec.Interfaces.Select(FormatTypeReference)));
        }

        if (rec.Members.Count > 0)
        {
            sb.AppendLine(" {");
            _indent++;
            FormatMembers(rec.Members, sb);
            _indent--;
            Indent(sb);
            sb.AppendLine("}");
        }
        else
        {
            sb.AppendLine();
        }
    }

    private void FormatInterface(InterfaceDeclaration iface, StringBuilder sb)
    {
        Indent(sb);

        var mods = FormatModifiers(iface.Modifiers);
        if (!string.IsNullOrEmpty(mods))
        {
            sb.Append(mods);
            sb.Append(" ");
        }

        if (iface.IsDuckInterface)
        {
            sb.Append("duck ");
        }

        sb.Append("interface ");
        sb.Append(iface.Name);

        if (iface.TypeParameters != null && iface.TypeParameters.Count > 0)
        {
            sb.Append("<");
            sb.Append(string.Join(", ", iface.TypeParameters.Select(tp => tp.Name)));
            sb.Append(">");
        }

        if (iface.BaseInterfaces.Count > 0)
        {
            sb.Append(": ");
            sb.Append(string.Join(", ", iface.BaseInterfaces.Select(FormatTypeReference)));
        }

        sb.AppendLine(" {");
        _indent++;
        FormatMembers(iface.Members, sb);
        _indent--;
        Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatUnion(UnionDeclaration union, StringBuilder sb)
    {
        Indent(sb);

        var mods = FormatModifiers(union.Modifiers);
        if (!string.IsNullOrEmpty(mods))
        {
            sb.Append(mods);
            sb.Append(" ");
        }

        sb.Append("union ");
        sb.Append(union.Name);
        sb.AppendLine(" {");

        _indent++;
        for (int i = 0; i < union.Cases.Count; i++)
        {
            var c = union.Cases[i];
            Indent(sb);
            sb.Append(c.Name);

            if (c.Properties != null && c.Properties.Count > 0)
            {
                sb.Append(" { ");
                for (int j = 0; j < c.Properties.Count; j++)
                {
                    var prop = c.Properties[j];
                    sb.Append(prop.Name);
                    sb.Append(": ");
                    sb.Append(FormatTypeReference(prop.Type));
                    if (j < c.Properties.Count - 1)
                    {
                        sb.Append(", ");
                    }
                }
                sb.Append(" }");
            }

            sb.AppendLine();
        }
        _indent--;

        Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatEnum(EnumDeclaration enumDecl, StringBuilder sb)
    {
        Indent(sb);

        var mods = FormatModifiers(enumDecl.Modifiers);
        if (!string.IsNullOrEmpty(mods))
        {
            sb.Append(mods);
            sb.Append(" ");
        }

        sb.Append("enum ");
        sb.Append(enumDecl.Name);

        if (enumDecl.Type == EnumType.String)
        {
            sb.Append(": string");
        }

        sb.AppendLine(" {");

        _indent++;
        for (int i = 0; i < enumDecl.Members.Count; i++)
        {
            var member = enumDecl.Members[i];
            Indent(sb);
            sb.Append(member.Name);

            if (member.Value != null)
            {
                sb.Append(" = ");
                FormatExpression(member.Value, sb);
            }

            if (i < enumDecl.Members.Count - 1)
            {
                sb.Append(",");
            }

            sb.AppendLine();
        }
        _indent--;

        Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatField(FieldDeclaration field, StringBuilder sb)
    {
        Indent(sb);

        var mods = FormatModifiers(field.Modifiers);
        if (!string.IsNullOrEmpty(mods))
        {
            sb.Append(mods);
            sb.Append(" ");
        }

        sb.Append(field.Name);

        if (field.Type != null)
        {
            sb.Append(": ");
            sb.Append(FormatTypeReference(field.Type));
        }

        if (field.Initializer != null)
        {
            if (field.Type == null)
            {
                sb.Append(" := ");
            }
            else
            {
                sb.Append(" = ");
            }
            FormatExpression(field.Initializer, sb);
        }

        sb.AppendLine();
    }

    private void FormatProperty(PropertyDeclaration prop, StringBuilder sb)
    {
        Indent(sb);

        var mods = FormatModifiers(prop.Modifiers);
        if (!string.IsNullOrEmpty(mods))
        {
            sb.Append(mods);
            sb.Append(" ");
        }

        sb.Append(prop.Name);
        sb.Append(": ");
        sb.Append(FormatTypeReference(prop.Type));

        if (prop.ExpressionBody != null)
        {
            sb.Append(" => ");
            FormatExpression(prop.ExpressionBody, sb);
            sb.AppendLine();
        }
        else if (prop.GetBody != null || prop.SetBody != null)
        {
            sb.AppendLine(" {");
            _indent++;

            if (prop.GetBody != null)
            {
                Indent(sb);
                sb.AppendLine("get {");
                _indent++;
                FormatBlock(prop.GetBody, sb);
                _indent--;
                Indent(sb);
                sb.AppendLine("}");
            }

            if (prop.SetBody != null)
            {
                Indent(sb);
                sb.AppendLine("set {");
                _indent++;
                FormatBlock(prop.SetBody, sb);
                _indent--;
                Indent(sb);
                sb.AppendLine("}");
            }

            _indent--;
            Indent(sb);
            sb.AppendLine("}");
        }
        else
        {
            sb.AppendLine();
        }
    }

    private void FormatConstructor(ConstructorDeclaration ctor, StringBuilder sb)
    {
        Indent(sb);

        var mods = FormatModifiers(ctor.Modifiers);
        if (!string.IsNullOrEmpty(mods))
        {
            sb.Append(mods);
            sb.Append(" ");
        }

        sb.Append("constructor(");
        for (int i = 0; i < ctor.Parameters.Count; i++)
        {
            FormatParameter(ctor.Parameters[i], sb);
            if (i < ctor.Parameters.Count - 1)
            {
                sb.Append(", ");
            }
        }
        sb.Append(")");

        if (ctor.Initializer != null)
        {
            sb.Append(": ");
            FormatExpression(ctor.Initializer, sb);
        }

        sb.AppendLine(" {");
        _indent++;
        FormatBlock(ctor.Body, sb);
        _indent--;
        Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatIndexer(IndexerDeclaration indexer, StringBuilder sb)
    {
        Indent(sb);

        var mods = FormatModifiers(indexer.Modifiers);
        if (!string.IsNullOrEmpty(mods))
        {
            sb.Append(mods);
            sb.Append(" ");
        }

        sb.Append("this[");
        for (int i = 0; i < indexer.Parameters.Count; i++)
        {
            FormatParameter(indexer.Parameters[i], sb);
            if (i < indexer.Parameters.Count - 1)
            {
                sb.Append(", ");
            }
        }
        sb.Append("]: ");
        sb.Append(FormatTypeReference(indexer.Type));
        sb.AppendLine(" {");

        _indent++;
        if (indexer.GetBody != null)
        {
            Indent(sb);
            sb.AppendLine("get {");
            _indent++;
            FormatBlock(indexer.GetBody, sb);
            _indent--;
            Indent(sb);
            sb.AppendLine("}");
        }

        if (indexer.SetBody != null)
        {
            Indent(sb);
            sb.AppendLine("set {");
            _indent++;
            FormatBlock(indexer.SetBody, sb);
            _indent--;
            Indent(sb);
            sb.AppendLine("}");
        }
        _indent--;

        Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatTest(TestDeclaration test, StringBuilder sb)
    {
        Indent(sb);
        sb.Append("test ");
        sb.Append($"\"{test.Description}\"");

        // Table-driven parameters and cases
        if (test.TableParameters != null && test.TableCases != null)
        {
            sb.Append(" with (");
            sb.Append(string.Join(", ", test.TableParameters.Select(p =>
                $"{p.Name}: {FormatTypeReference(p.Type)}")));
            sb.AppendLine(") [");
            _indent++;
            for (int i = 0; i < test.TableCases.Count; i++)
            {
                Indent(sb);
                sb.Append("(");
                var exprs = new List<string>();
                foreach (var expr in test.TableCases[i])
                {
                    var exprSb = new StringBuilder();
                    FormatExpression(expr, exprSb);
                    exprs.Add(exprSb.ToString());
                }
                sb.Append(string.Join(", ", exprs));
                sb.Append(")");
                if (i < test.TableCases.Count - 1)
                    sb.Append(",");
                sb.AppendLine();
            }
            _indent--;
            Indent(sb);
            sb.Append("]");
        }

        // Skip reason
        if (test.SkipReason != null)
        {
            sb.Append($" skip \"{test.SkipReason}\"");
        }

        sb.AppendLine(" {");
        _indent++;
        FormatBlock(test.Body, sb);
        _indent--;
        Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatSetup(SetupDeclaration setup, StringBuilder sb)
    {
        Indent(sb);
        sb.AppendLine("setup {");
        _indent++;
        FormatBlock(setup.Body, sb);
        _indent--;
        Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatTeardown(TeardownDeclaration teardown, StringBuilder sb)
    {
        Indent(sb);
        sb.AppendLine("teardown {");
        _indent++;
        FormatBlock(teardown.Body, sb);
        _indent--;
        Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatBlock(BlockStatement block, StringBuilder sb)
    {
        for (int i = 0; i < block.Statements.Count; i++)
        {
            var stmt = block.Statements[i];
            EmitCommentsBefore(stmt.Line, sb);
            // Preserve blank lines between statements
            // Use _lastEmittedSourceLine to account for comments just emitted
            if (i > 0 && _lastEmittedSourceLine > 0 && stmt.Line - _lastEmittedSourceLine > 1)
            {
                sb.AppendLine();
            }
            FormatStatement(stmt, sb);
            _lastEmittedSourceLine = stmt.Line;
        }
    }

    private void FormatIfStatement(IfStatement ifStmt, StringBuilder sb)
    {
        sb.Append("if ");
        FormatExpression(ifStmt.Condition, sb);
        sb.AppendLine(" {");
        _indent++;
        if (ifStmt.ThenStatement is BlockStatement thenBlock)
        {
            FormatBlock(thenBlock, sb);
        }
        else
        {
            FormatStatement(ifStmt.ThenStatement, sb);
        }
        _indent--;
        Indent(sb);
        sb.Append("}");

        if (ifStmt.ElseStatement != null)
        {
            sb.Append(" else ");
            if (ifStmt.ElseStatement is IfStatement elseIfStmt)
            {
                FormatIfStatement(elseIfStmt, sb);
            }
            else
            {
                sb.AppendLine("{");
                _indent++;
                if (ifStmt.ElseStatement is BlockStatement elseBlock)
                {
                    FormatBlock(elseBlock, sb);
                }
                else
                {
                    FormatStatement(ifStmt.ElseStatement, sb);
                }
                _indent--;
                Indent(sb);
                sb.AppendLine("}");
            }
        }
        else
        {
            sb.AppendLine();
        }
    }

    private void FormatStatement(Statement stmt, StringBuilder sb)
    {
        switch (stmt)
        {
            case ExpressionStatement exprStmt:
                Indent(sb);
                FormatExpression(exprStmt.Expression, sb);
                sb.AppendLine();
                break;

            case VariableDeclarationStatement varDecl:
                Indent(sb);
                if (varDecl.Kind == VariableKind.Const)
                {
                    sb.Append("const ");
                }
                else if (varDecl.Kind == VariableKind.Readonly)
                {
                    sb.Append("readonly ");
                }
                sb.Append(varDecl.Name);
                if (varDecl.Type != null)
                {
                    sb.Append(": ");
                    sb.Append(FormatTypeReference(varDecl.Type));
                }
                if (varDecl.Initializer != null)
                {
                    if (varDecl.Type == null)
                    {
                        sb.Append(" := ");
                    }
                    else
                    {
                        sb.Append(" = ");
                    }
                    FormatExpression(varDecl.Initializer, sb);
                }
                sb.AppendLine();
                break;

            case TupleDeconstructionStatement tupleDecl:
                Indent(sb);
                sb.Append(string.Join(", ", tupleDecl.Names));
                sb.Append(" := ");
                FormatExpression(tupleDecl.Initializer, sb);
                sb.AppendLine();
                break;

            case BlockStatement block:
                Indent(sb);
                sb.AppendLine("{");
                _indent++;
                FormatBlock(block, sb);
                _indent--;
                Indent(sb);
                sb.AppendLine("}");
                break;

            case IfStatement ifStmt:
                Indent(sb);
                FormatIfStatement(ifStmt, sb);
                break;

            case ForStatement forStmt:
                // Detect for...in pattern: ForStatement(null, null, null, ForeachStatement)
                if (forStmt.Initializer == null && forStmt.Condition == null
                    && forStmt.Iterator == null && forStmt.Body is ForeachStatement forInStmt)
                {
                    Indent(sb);
                    FormatForeachBody(forInStmt, sb);
                    break;
                }
                Indent(sb);
                sb.Append("for ");
                if (forStmt.Initializer != null)
                {
                    if (forStmt.Initializer is VariableDeclarationStatement vd)
                    {
                        sb.Append(vd.Name);
                        if (vd.Type != null)
                        {
                            sb.Append(": ");
                            sb.Append(FormatTypeReference(vd.Type));
                        }
                        if (vd.Initializer != null)
                        {
                            // Use := for shorthand declarations (no explicit type), = for typed declarations
                            sb.Append(vd.Type == null ? " := " : " = ");
                            FormatExpression(vd.Initializer, sb);
                        }
                    }
                    else
                    {
                        FormatExpression(((ExpressionStatement)forStmt.Initializer).Expression, sb);
                    }
                }
                sb.Append("; ");
                if (forStmt.Condition != null)
                {
                    FormatExpression(forStmt.Condition, sb);
                }
                sb.Append("; ");
                if (forStmt.Iterator != null)
                {
                    FormatExpression(forStmt.Iterator, sb);
                }
                sb.AppendLine(" {");
                _indent++;
                if (forStmt.Body is BlockStatement forBlock)
                {
                    FormatBlock(forBlock, sb);
                }
                else
                {
                    FormatStatement(forStmt.Body, sb);
                }
                _indent--;
                Indent(sb);
                sb.AppendLine("}");
                break;

            case ForeachStatement foreachStmt:
                Indent(sb);
                FormatForeachBody(foreachStmt, sb);
                break;

            case AwaitForEachStatement awaitForeach:
                Indent(sb);
                sb.Append("await foreach ");
                sb.Append(awaitForeach.VariableName);
                sb.Append(" in ");
                FormatExpression(awaitForeach.Collection, sb);
                sb.AppendLine(" {");
                _indent++;
                if (awaitForeach.Body is BlockStatement awaitForBlock)
                {
                    FormatBlock(awaitForBlock, sb);
                }
                else
                {
                    FormatStatement(awaitForeach.Body, sb);
                }
                _indent--;
                Indent(sb);
                sb.AppendLine("}");
                break;

            case WhileStatement whileStmt:
                Indent(sb);
                sb.Append("while ");
                FormatExpression(whileStmt.Condition, sb);
                sb.AppendLine(" {");
                _indent++;
                if (whileStmt.Body is BlockStatement whileBlock)
                {
                    FormatBlock(whileBlock, sb);
                }
                else
                {
                    FormatStatement(whileStmt.Body, sb);
                }
                _indent--;
                Indent(sb);
                sb.AppendLine("}");
                break;

            case ReturnStatement retStmt:
                Indent(sb);
                sb.Append("return");
                if (retStmt.Value != null)
                {
                    sb.Append(" ");
                    FormatExpression(retStmt.Value, sb);
                }
                sb.AppendLine();
                break;

            case YieldStatement yieldStmt:
                Indent(sb);
                if (yieldStmt.Value != null)
                {
                    sb.Append("yield ");
                    FormatExpression(yieldStmt.Value, sb);
                }
                else
                {
                    sb.Append("yield break");
                }
                sb.AppendLine();
                break;

            case BreakStatement:
                Indent(sb);
                sb.AppendLine("break");
                break;

            case ContinueStatement:
                Indent(sb);
                sb.AppendLine("continue");
                break;

            case ThrowStatement throwStmt:
                Indent(sb);
                sb.Append("throw ");
                FormatExpression(throwStmt.Expression, sb);
                sb.AppendLine();
                break;

            case PrintStatement printStmt:
                Indent(sb);
                sb.Append("print ");
                FormatExpression(printStmt.Value, sb);
                sb.AppendLine();
                break;

            case TryStatement tryStmt:
                Indent(sb);
                sb.AppendLine("try {");
                _indent++;
                FormatBlock(tryStmt.TryBlock, sb);
                _indent--;
                Indent(sb);
                sb.Append("}");

                foreach (var catchClause in tryStmt.CatchClauses)
                {
                    sb.Append(" catch");
                    if (catchClause.ExceptionType != null)
                    {
                        sb.Append(" (");
                        sb.Append(FormatTypeReference(catchClause.ExceptionType));
                        if (catchClause.VariableName != null)
                        {
                            sb.Append(" ");
                            sb.Append(catchClause.VariableName);
                        }
                        sb.Append(")");
                    }
                    sb.AppendLine(" {");
                    _indent++;
                    FormatBlock(catchClause.Block, sb);
                    _indent--;
                    Indent(sb);
                    sb.Append("}");
                }

                if (tryStmt.FinallyBlock != null)
                {
                    sb.AppendLine(" finally {");
                    _indent++;
                    FormatBlock(tryStmt.FinallyBlock, sb);
                    _indent--;
                    Indent(sb);
                    sb.Append("}");
                }

                sb.AppendLine();
                break;

            case UsingStatement usingStmt:
                Indent(sb);
                sb.Append("using ");
                if (usingStmt.Declaration != null)
                {
                    sb.Append(usingStmt.Declaration.Name);
                    if (usingStmt.Declaration.Type != null)
                    {
                        sb.Append(": ");
                        sb.Append(FormatTypeReference(usingStmt.Declaration.Type));
                    }
                    if (usingStmt.Declaration.Initializer != null)
                    {
                        sb.Append(" = ");
                        FormatExpression(usingStmt.Declaration.Initializer, sb);
                    }
                }
                else if (usingStmt.Expression != null)
                {
                    FormatExpression(usingStmt.Expression, sb);
                }

                if (usingStmt.Body != null)
                {
                    sb.AppendLine(" {");
                    _indent++;
                    if (usingStmt.Body is BlockStatement usingBlock)
                    {
                        FormatBlock(usingBlock, sb);
                    }
                    else
                    {
                        FormatStatement(usingStmt.Body, sb);
                    }
                    _indent--;
                    Indent(sb);
                    sb.AppendLine("}");
                }
                else
                {
                    sb.AppendLine();
                }
                break;

            case LockStatement lockStmt:
                Indent(sb);
                sb.Append("lock ");
                FormatExpression(lockStmt.LockObject, sb);
                sb.AppendLine(" {");
                _indent++;
                FormatBlock(lockStmt.Body, sb);
                _indent--;
                Indent(sb);
                sb.AppendLine("}");
                break;

            case SwitchStatement switchStmt:
                Indent(sb);
                sb.Append("switch ");
                FormatExpression(switchStmt.Value, sb);
                sb.AppendLine(" {");
                _indent++;
                foreach (var caseClause in switchStmt.Cases)
                {
                    Indent(sb);
                    if (caseClause.Pattern != null)
                    {
                        sb.Append("case ");
                        FormatPattern(caseClause.Pattern, sb);
                        sb.AppendLine(":");
                    }
                    else
                    {
                        sb.AppendLine("default:");
                    }
                    _indent++;
                    foreach (var caseStmt in caseClause.Statements)
                    {
                        FormatStatement(caseStmt, sb);
                    }
                    _indent--;
                }
                _indent--;
                Indent(sb);
                sb.AppendLine("}");
                break;

            case LocalFunctionStatement localFunc:
                FormatFunction(localFunc.Function, sb);
                break;

            case AssertStatement assertStmt:
                Indent(sb);
                sb.Append("assert ");
                FormatExpression(assertStmt.Condition, sb);
                if (assertStmt.Message != null)
                {
                    sb.Append(", ");
                    FormatExpression(assertStmt.Message, sb);
                }
                sb.AppendLine();
                break;

            case AssertThrowsStatement assertThrows:
                Indent(sb);
                sb.Append("assert throws ");
                sb.Append(FormatTypeReference(assertThrows.ExceptionType));
                sb.AppendLine(" {");
                _indent++;
                FormatBlock(assertThrows.Body, sb);
                _indent--;
                Indent(sb);
                sb.AppendLine("}");
                break;

            case PreprocessorDirective preproc:
                Indent(sb);
                sb.AppendLine(preproc.Directive);
                break;

            case EmptyStatement:
                break;
            default:
                throw new InvalidOperationException($"Formatter does not handle statement type: {stmt.GetType().Name}");
        }
    }

    private void FormatForeachBody(ForeachStatement foreachStmt, StringBuilder sb)
    {
        // Canonical N# style: for x in collection (not foreach)
        sb.Append("for ");
        sb.Append(foreachStmt.VariableName);
        sb.Append(" in ");
        FormatExpression(foreachStmt.Collection, sb);
        sb.AppendLine(" {");
        _indent++;
        if (foreachStmt.Body is BlockStatement foreachBlock)
        {
            FormatBlock(foreachBlock, sb);
        }
        else
        {
            FormatStatement(foreachStmt.Body, sb);
        }
        _indent--;
        Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatExpression(Expression expr, StringBuilder sb)
    {
        switch (expr)
        {
            case IntLiteralExpression intLit:
                sb.Append(intLit.Value);
                break;
            case FloatLiteralExpression floatLit:
                sb.Append(floatLit.Value);
                break;
            case StringLiteralExpression strLit:
                sb.Append(strLit.Value);
                break;
            case InterpolatedStringExpression interpolated:
                sb.Append("$\"");
                foreach (var part in interpolated.Parts)
                {
                    switch (part)
                    {
                        case InterpolatedStringText text:
                            sb.Append(text.Text);
                            break;
                        case InterpolatedStringHole hole:
                            sb.Append('{');
                            FormatExpression(hole.Expression, sb);
                            if (hole.FormatClause != null)
                            {
                                sb.Append(':');
                                sb.Append(hole.FormatClause);
                            }
                            sb.Append('}');
                            break;
                    }
                }
                sb.Append('"');
                break;
            case BoolLiteralExpression boolLit:
                sb.Append(boolLit.Value ? "true" : "false");
                break;
            case NullLiteralExpression:
                sb.Append("null");
                break;
            case IdentifierExpression ident:
                sb.Append(ident.Name);
                break;
            case BinaryExpression bin:
                FormatExpression(bin.Left, sb);
                sb.Append(" ");
                sb.Append(FormatBinaryOperator(bin.Operator));
                sb.Append(" ");
                FormatExpression(bin.Right, sb);
                break;
            case UnaryExpression unary:
                if (unary.Operator == UnaryOperator.PostIncrement || unary.Operator == UnaryOperator.PostDecrement)
                {
                    FormatExpression(unary.Operand, sb);
                    sb.Append(FormatUnaryOperator(unary.Operator));
                }
                else
                {
                    sb.Append(FormatUnaryOperator(unary.Operator));
                    FormatExpression(unary.Operand, sb);
                }
                break;
            case MemberAccessExpression member:
                FormatExpression(member.Object, sb);
                sb.Append(member.IsNullConditional ? "?." : ".");
                sb.Append(member.MemberName);
                break;
            case IndexAccessExpression index:
                FormatExpression(index.Object, sb);
                sb.Append(index.IsNullConditional ? "?[" : "[");
                FormatExpression(index.Index, sb);
                sb.Append("]");
                break;
            case CallExpression call:
                FormatExpression(call.Callee, sb);
                if (call.TypeArguments != null && call.TypeArguments.Count > 0)
                {
                    sb.Append("<");
                    sb.Append(string.Join(", ", call.TypeArguments.Select(FormatTypeReference)));
                    sb.Append(">");
                }
                sb.Append("(");
                for (int i = 0; i < call.Arguments.Count; i++)
                {
                    var arg = call.Arguments[i];
                    if (arg.Name != null)
                    {
                        sb.Append(arg.Name);
                        sb.Append(": ");
                    }
                    if (arg.Modifier == ArgumentModifier.Ref)
                    {
                        sb.Append("ref ");
                    }
                    else if (arg.Modifier == ArgumentModifier.Out)
                    {
                        sb.Append("out ");
                    }
                    FormatExpression(arg.Value, sb);
                    if (i < call.Arguments.Count - 1)
                    {
                        sb.Append(", ");
                    }
                }
                sb.Append(")");
                break;
            case AssignmentExpression assign:
                FormatExpression(assign.Target, sb);
                sb.Append(" ");
                sb.Append(FormatAssignmentOperator(assign.Operator));
                sb.Append(" ");
                FormatExpression(assign.Value, sb);
                break;
            case LambdaExpression lambda:
                bool allParamsInferred = lambda.Parameters.All(p =>
                    p.Type == null || (p.Type is SimpleTypeReference s && s.Name == "var"));
                if (lambda.Parameters.Count == 1 && allParamsInferred)
                {
                    // Single inferred-type param: x => expr
                    sb.Append(lambda.Parameters[0].Name);
                }
                else if (lambda.Parameters.Count > 1 && allParamsInferred)
                {
                    // Multi inferred-type params: (x, y) => expr
                    sb.Append("(");
                    sb.Append(string.Join(", ", lambda.Parameters.Select(p => p.Name)));
                    sb.Append(")");
                }
                else
                {
                    sb.Append("(");
                    for (int i = 0; i < lambda.Parameters.Count; i++)
                    {
                        FormatParameter(lambda.Parameters[i], sb);
                        if (i < lambda.Parameters.Count - 1)
                        {
                            sb.Append(", ");
                        }
                    }
                    sb.Append(")");
                }
                sb.Append(" => ");
                if (lambda.ExpressionBody != null)
                {
                    FormatExpression(lambda.ExpressionBody, sb);
                }
                else if (lambda.BlockBody != null)
                {
                    sb.AppendLine("{");
                    _indent++;
                    FormatBlock(lambda.BlockBody, sb);
                    _indent--;
                    Indent(sb);
                    sb.Append("}");
                }
                break;
            case TernaryExpression ternary:
                FormatExpression(ternary.Condition, sb);
                sb.Append(" ? ");
                FormatExpression(ternary.ThenExpression, sb);
                sb.Append(" : ");
                FormatExpression(ternary.ElseExpression, sb);
                break;
            case ArrayLiteralExpression array:
                sb.Append(array.IsImmutable ? "#[" : "[");
                for (int i = 0; i < array.Elements.Count; i++)
                {
                    FormatExpression(array.Elements[i], sb);
                    if (i < array.Elements.Count - 1)
                    {
                        sb.Append(", ");
                    }
                }
                sb.Append("]");
                break;
            case TupleExpression tuple:
                sb.Append("(");
                for (int i = 0; i < tuple.Elements.Count; i++)
                {
                    var elem = tuple.Elements[i];
                    if (elem.Name != null)
                    {
                        sb.Append(elem.Name);
                        sb.Append(": ");
                    }
                    FormatExpression(elem.Value, sb);
                    if (i < tuple.Elements.Count - 1)
                    {
                        sb.Append(", ");
                    }
                }
                sb.Append(")");
                break;
            case NewExpression newExpr:
                sb.Append("new");
                if (newExpr.Type != null)
                {
                    sb.Append(" ");
                    sb.Append(FormatTypeReference(newExpr.Type));
                }
                sb.Append("(");
                for (int i = 0; i < newExpr.ConstructorArguments.Count; i++)
                {
                    var arg = newExpr.ConstructorArguments[i];
                    if (arg.Name != null)
                    {
                        sb.Append(arg.Name);
                        sb.Append(": ");
                    }
                    FormatExpression(arg.Value, sb);
                    if (i < newExpr.ConstructorArguments.Count - 1)
                    {
                        sb.Append(", ");
                    }
                }
                sb.Append(")");
                if (newExpr.Initializer != null)
                {
                    FormatObjectInitializer(newExpr.Initializer, sb);
                }
                break;
            case CastExpression cast:
                if (cast.Kind == CastKind.Hard)
                {
                    sb.Append("(");
                    sb.Append(FormatTypeReference(cast.TargetType));
                    sb.Append(")");
                    FormatExpression(cast.Expression, sb);
                }
                else
                {
                    FormatExpression(cast.Expression, sb);
                    sb.Append(" as ");
                    sb.Append(FormatTypeReference(cast.TargetType));
                }
                break;
            case IsExpression isExpr:
                FormatExpression(isExpr.Expression, sb);
                sb.Append(" is ");
                sb.Append(FormatTypeReference(isExpr.Type));
                if (isExpr.VariableName != null)
                {
                    sb.Append(" ");
                    sb.Append(isExpr.VariableName);
                }
                break;
            case MatchExpression match:
                sb.Append("match ");
                FormatExpression(match.Value, sb);
                sb.AppendLine(" {");
                _indent++;
                for (int i = 0; i < match.Cases.Count; i++)
                {
                    var caseExpr = match.Cases[i];
                    Indent(sb);
                    FormatPattern(caseExpr.Pattern, sb);
                    if (caseExpr.Guard != null)
                    {
                        sb.Append(" when ");
                        FormatExpression(caseExpr.Guard, sb);
                    }
                    sb.Append(" => ");
                    FormatExpression(caseExpr.Expression, sb);
                    // Commas required between cases (not after last)
                    if (i < match.Cases.Count - 1)
                    {
                        sb.Append(",");
                    }
                    sb.AppendLine();
                }
                _indent--;
                Indent(sb);
                sb.Append("}");
                break;
            case WithExpression withExpr:
                FormatExpression(withExpr.Target, sb);
                sb.Append(" with { ");
                for (int i = 0; i < withExpr.Properties.Count; i++)
                {
                    var prop = withExpr.Properties[i];
                    if (prop.Name != null)
                    {
                        sb.Append(prop.Name);
                        sb.Append(": ");
                    }
                    FormatExpression(prop.Value, sb);
                    if (i < withExpr.Properties.Count - 1)
                    {
                        sb.Append(", ");
                    }
                }
                sb.Append(" }");
                break;
            case AwaitExpression awaitExpr:
                sb.Append("await ");
                FormatExpression(awaitExpr.Expression, sb);
                break;
            case ThrowExpression throwExpr:
                sb.Append("throw ");
                FormatExpression(throwExpr.Expression, sb);
                break;
            case TypeOfExpression typeofExpr:
                sb.Append("typeof(");
                sb.Append(FormatTypeReference(typeofExpr.Type));
                sb.Append(")");
                break;
            case NameofExpression nameofExpr:
                sb.Append("nameof(");
                FormatExpression(nameofExpr.Target, sb);
                sb.Append(")");
                break;
            case SizeOfExpression sizeofExpr:
                sb.Append("sizeof(");
                sb.Append(FormatTypeReference(sizeofExpr.Type));
                sb.Append(")");
                break;
            case ThisExpression:
                sb.Append("this");
                break;
            case BaseExpression:
                sb.Append("base");
                break;
            case RangeExpression range:
                if (range.Start != null)
                {
                    FormatExpression(range.Start, sb);
                }
                sb.Append("..");
                if (range.End != null)
                {
                    FormatExpression(range.End, sb);
                }
                break;
            case SpreadExpression spread:
                sb.Append("...");
                FormatExpression(spread.Expression, sb);
                break;
            case OutVariableDeclarationExpression outVar:
                sb.Append("out ");
                if (outVar.Type != null)
                {
                    sb.Append(FormatTypeReference(outVar.Type));
                    sb.Append(" ");
                }
                else
                {
                    sb.Append("var ");
                }
                sb.Append(outVar.VariableName);
                break;
            case CheckedExpression checkedExpr:
                sb.Append("checked(");
                FormatExpression(checkedExpr.Expression, sb);
                sb.Append(")");
                break;
            case UncheckedExpression uncheckedExpr:
                sb.Append("unchecked(");
                FormatExpression(uncheckedExpr.Expression, sb);
                sb.Append(")");
                break;
            case DefaultExpression:
                sb.Append("default");
                break;
            case ParenthesizedExpression paren:
                sb.Append("(");
                FormatExpression(paren.Inner, sb);
                sb.Append(")");
                break;
            default:
                throw new InvalidOperationException($"Formatter does not handle expression type: {expr.GetType().Name}");
        }
    }

    private void FormatPattern(Pattern pattern, StringBuilder sb)
    {
        switch (pattern)
        {
            case IdentifierPattern ident:
                sb.Append(ident.Name);
                break;
            case LiteralPattern lit:
                FormatExpression(lit.Literal, sb);
                break;
            case UnionCasePattern unionCase:
                sb.Append(unionCase.CaseName);
                if (unionCase.Properties != null && unionCase.Properties.Count > 0)
                {
                    sb.Append(" { ");
                    for (int i = 0; i < unionCase.Properties.Count; i++)
                    {
                        var prop = unionCase.Properties[i];
                        FormatPropertyPattern(prop, sb);
                        if (i < unionCase.Properties.Count - 1)
                        {
                            sb.Append(", ");
                        }
                    }
                    sb.Append(" }");
                }
                break;
            case RelationalPattern rel:
                sb.Append(rel.Operator);
                sb.Append(" ");
                FormatExpression(rel.Value, sb);
                break;
            case AndPattern and:
                FormatPattern(and.Left, sb);
                sb.Append(" and ");
                FormatPattern(and.Right, sb);
                break;
            case OrPattern or:
                FormatPattern(or.Left, sb);
                sb.Append(" or ");
                FormatPattern(or.Right, sb);
                break;
            case NotPattern not:
                sb.Append("not ");
                FormatPattern(not.Pattern, sb);
                break;
            case PositionalPattern pos:
                sb.Append("(");
                for (int i = 0; i < pos.Patterns.Count; i++)
                {
                    FormatPattern(pos.Patterns[i], sb);
                    if (i < pos.Patterns.Count - 1)
                    {
                        sb.Append(", ");
                    }
                }
                sb.Append(")");
                break;
            case ObjectPattern obj:
                sb.Append("{ ");
                for (int i = 0; i < obj.Properties.Count; i++)
                {
                    FormatPropertyPattern(obj.Properties[i], sb);
                    if (i < obj.Properties.Count - 1)
                    {
                        sb.Append(", ");
                    }
                }
                sb.Append(" }");
                break;
            case ListPattern list:
                sb.Append("[");
                for (int i = 0; i < list.Elements.Count; i++)
                {
                    FormatPattern(list.Elements[i], sb);
                    if (i < list.Elements.Count - 1)
                    {
                        sb.Append(", ");
                    }
                }
                sb.Append("]");
                break;
            case SlicePattern slice:
                sb.Append("..");
                if (slice.BindingName != null)
                {
                    sb.Append(" ");
                    sb.Append(slice.BindingName);
                }
                break;
            case TypePattern type:
                sb.Append(FormatTypeReference(type.Type));
                if (type.BindingName != null)
                {
                    sb.Append(" ");
                    sb.Append(type.BindingName);
                }
                break;
            default:
                throw new InvalidOperationException($"Formatter does not handle pattern type: {pattern.GetType().Name}");
        }
    }

    private void FormatPropertyPattern(PropertyPattern prop, StringBuilder sb)
    {
        sb.Append(prop.Name);
        if (prop.Pattern != null)
        {
            sb.Append(": ");
            FormatPattern(prop.Pattern, sb);
        }
        else if (prop.BindingName != null)
        {
            sb.Append(": ");
            sb.Append(prop.BindingName);
        }
        // When both Pattern and BindingName are null, it's a simple binding: { Name }
    }

    private void FormatParameter(Parameter param, StringBuilder sb)
    {
        if (param.Attributes is { Count: > 0 })
        {
            foreach (var attr in param.Attributes)
            {
                sb.Append("[");
                sb.Append(attr.Name);
                if (attr.Arguments.Count > 0)
                {
                    sb.Append("(");
                    for (int i = 0; i < attr.Arguments.Count; i++)
                    {
                        if (i > 0) sb.Append(", ");
                        FormatExpression(attr.Arguments[i].Value, sb);
                    }
                    sb.Append(")");
                }
                sb.Append("] ");
            }
        }
        if (param.IsThis)
        {
            sb.Append("this ");
        }
        if (param.Modifier == ParameterModifier.Ref)
        {
            sb.Append("ref ");
        }
        else if (param.Modifier == ParameterModifier.Out)
        {
            sb.Append("out ");
        }
        else if (param.Modifier == ParameterModifier.Params)
        {
            sb.Append("params ");
        }
        sb.Append(param.Name);
        sb.Append(": ");
        sb.Append(FormatTypeReference(param.Type));
        if (param.DefaultValue != null)
        {
            sb.Append(" = ");
            FormatExpression(param.DefaultValue, sb);
        }
    }

    private string FormatTypeReference(TypeReference type)
    {
        return type switch
        {
            SimpleTypeReference simple => simple.Name,
            GenericTypeReference generic => $"{generic.Name}<{string.Join(", ", generic.TypeArguments.Select(FormatTypeReference))}>",
            ArrayTypeReference array => $"{FormatTypeReference(array.ElementType)}[]",
            NullableTypeReference nullable => $"{FormatTypeReference(nullable.InnerType)}?",
            TupleTypeReference tuple => $"({string.Join(", ", tuple.Elements.Select(e => e.Name != null ? $"{e.Name}: {FormatTypeReference(e.Type)}" : FormatTypeReference(e.Type)))})",
            FunctionTypeReference func => $"({string.Join(", ", func.ParameterTypes.Select(FormatTypeReference))}) => {FormatTypeReference(func.ReturnType)}",
            _ => throw new InvalidOperationException($"Formatter does not handle type reference: {type.GetType().Name}")
        };
    }

    private string FormatModifiers(Modifiers modifiers)
    {
        var parts = new List<string>();

        if (modifiers.HasFlag(Modifiers.Public)) parts.Add("public");
        if (modifiers.HasFlag(Modifiers.Private)) parts.Add("private");
        if (modifiers.HasFlag(Modifiers.Internal)) parts.Add("internal");
        if (modifiers.HasFlag(Modifiers.Protected)) parts.Add("protected");
        if (modifiers.HasFlag(Modifiers.Static)) parts.Add("static");
        if (modifiers.HasFlag(Modifiers.Virtual)) parts.Add("virtual");
        if (modifiers.HasFlag(Modifiers.Abstract)) parts.Add("abstract");
        if (modifiers.HasFlag(Modifiers.Sealed)) parts.Add("sealed");
        if (modifiers.HasFlag(Modifiers.Partial)) parts.Add("partial");
        if (modifiers.HasFlag(Modifiers.Readonly)) parts.Add("readonly");
        if (modifiers.HasFlag(Modifiers.Const)) parts.Add("const");
        if (modifiers.HasFlag(Modifiers.Async)) parts.Add("async");
        if (modifiers.HasFlag(Modifiers.Override)) parts.Add("override");
        if (modifiers.HasFlag(Modifiers.File)) parts.Add("file");

        return string.Join(" ", parts);
    }

    private string FormatBinaryOperator(BinaryOperator op)
    {
        return op switch
        {
            BinaryOperator.Add => "+",
            BinaryOperator.Subtract => "-",
            BinaryOperator.Multiply => "*",
            BinaryOperator.Divide => "/",
            BinaryOperator.Modulo => "%",
            BinaryOperator.Equal => "==",
            BinaryOperator.NotEqual => "!=",
            BinaryOperator.Less => "<",
            BinaryOperator.LessOrEqual => "<=",
            BinaryOperator.Greater => ">",
            BinaryOperator.GreaterOrEqual => ">=",
            BinaryOperator.And => "&&",
            BinaryOperator.Or => "||",
            BinaryOperator.BitwiseAnd => "&",
            BinaryOperator.BitwiseOr => "|",
            BinaryOperator.BitwiseXor => "^",
            BinaryOperator.LeftShift => "<<",
            BinaryOperator.RightShift => ">>",
            BinaryOperator.NullCoalesce => "??",
            BinaryOperator.Range => "..",
            _ => throw new InvalidOperationException($"Formatter does not handle binary operator: {op}")
        };
    }

    private string FormatUnaryOperator(UnaryOperator op)
    {
        return op switch
        {
            UnaryOperator.Negate => "-",
            UnaryOperator.Not => "!",
            UnaryOperator.BitwiseNot => "~",
            UnaryOperator.PreIncrement => "++",
            UnaryOperator.PreDecrement => "--",
            UnaryOperator.PostIncrement => "++",
            UnaryOperator.PostDecrement => "--",
            UnaryOperator.IndexFromEnd => "^",
            _ => throw new InvalidOperationException($"Formatter does not handle unary operator: {op}")
        };
    }

    private string FormatAssignmentOperator(AssignmentOperator op)
    {
        return op switch
        {
            AssignmentOperator.Assign => "=",
            AssignmentOperator.AddAssign => "+=",
            AssignmentOperator.SubtractAssign => "-=",
            AssignmentOperator.MultiplyAssign => "*=",
            AssignmentOperator.DivideAssign => "/=",
            AssignmentOperator.NullCoalesceAssign => "??=",
            _ => throw new InvalidOperationException($"Formatter does not handle assignment operator: {op}")
        };
    }

    private void Indent(StringBuilder sb)
    {
        for (int i = 0; i < _indent; i++)
        {
            sb.Append(_indentString);
        }
    }

    /// <summary>
    /// Format an object initializer, choosing inline or multi-line based on line length.
    /// Inline: { Prop1: val1, Prop2: val2 }
    /// Multi-line:
    ///   {
    ///       Prop1: val1,
    ///       Prop2: val2
    ///   }
    /// </summary>
    private void FormatObjectInitializer(ObjectInitializerExpression initializer, StringBuilder sb)
    {
        // First, measure the inline form to decide if it fits
        var inlineSb = new StringBuilder();
        inlineSb.Append(" { ");
        for (int i = 0; i < initializer.Properties.Count; i++)
        {
            var prop = initializer.Properties[i];
            if (prop.Name != null)
            {
                inlineSb.Append(prop.Name);
                inlineSb.Append(": ");
            }
            if (prop.IsIndexerInitializer)
            {
                inlineSb.Append("[");
                inlineSb.Append(FormatExpressionToString(prop.IndexExpression!));
                inlineSb.Append("] = ");
            }
            inlineSb.Append(FormatExpressionToString(prop.Value));
            if (i < initializer.Properties.Count - 1)
            {
                inlineSb.Append(", ");
            }
        }
        inlineSb.Append(" }");

        int currentCol = GetCurrentColumn(sb);
        bool fitsOnLine = currentCol + inlineSb.Length <= _maxLineLength;

        if (fitsOnLine || initializer.Properties.Count <= 1)
        {
            // Inline form
            sb.Append(inlineSb);
        }
        else
        {
            // Multi-line form
            sb.Append(" {");
            _indent++;
            for (int i = 0; i < initializer.Properties.Count; i++)
            {
                sb.AppendLine();
                Indent(sb);
                var prop = initializer.Properties[i];
                if (prop.Name != null)
                {
                    sb.Append(prop.Name);
                    sb.Append(": ");
                }
                if (prop.IsIndexerInitializer)
                {
                    sb.Append("[");
                    FormatExpression(prop.IndexExpression!, sb);
                    sb.Append("] = ");
                }
                FormatExpression(prop.Value, sb);
                if (i < initializer.Properties.Count - 1)
                {
                    sb.Append(",");
                }
            }
            _indent--;
            sb.AppendLine();
            Indent(sb);
            sb.Append("}");
        }
    }

    /// <summary>
    /// Returns the column position (characters since last newline) in the StringBuilder.
    /// </summary>
    private static int GetCurrentColumn(StringBuilder sb)
    {
        for (int i = sb.Length - 1; i >= 0; i--)
        {
            if (sb[i] == '\n')
                return sb.Length - i - 1;
        }
        return sb.Length;
    }

    /// <summary>
    /// Format an expression to a standalone string (for measuring inline length).
    /// Saves and restores formatter state so the measurement pass has no side effects.
    /// </summary>
    private string FormatExpressionToString(Expression expr)
    {
        var savedCommentIndex = _commentIndex;
        var savedLastEmittedSourceLine = _lastEmittedSourceLine;
        var tempSb = new StringBuilder();
        FormatExpression(expr, tempSb);
        _commentIndex = savedCommentIndex;
        _lastEmittedSourceLine = savedLastEmittedSourceLine;
        return tempSb.ToString();
    }
}
