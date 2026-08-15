using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

public class Formatter
{
    // The indent depth, the comment stream and its cursor, the last emitted source line, and the two
    // values derived from the configuration all belong to the N# owner. What is left here is the
    // file's declaration walk; every statement, expression and pattern belongs to `_walk`, and the
    // two share one state object because they are one walk at different depths.
    private readonly FormatterWalkState _state;
    private readonly FormatterWalk _walk;

    public Formatter(FormatterConfig? config = null)
    {
        _state = new FormatterWalkState(config);
        _walk = new FormatterWalk(_state);
    }

    /// <summary>
    /// Format source safely: formats the AST, then verifies the output re-parses without errors
    /// and is idempotent. If either check fails, returns the original source with warnings.
    /// </summary>
    public FormatResult FormatSafe(string originalSource, CompilationUnit ast, List<CommentTrivia>? comments = null, string fileName = "formatted.nl")
    {
        var warnings = new List<string>();

            var formatted = Format(ast, comments);
            var lexer = new Lexer(formatted, fileName);
            lexer.Tokenize();   // populates lexer.Comments for the idempotence re-format below
            var reparseResult = NSharpLang.Compiler.Columnar.ColumnarParserRecovery.ParseFileAst(formatted, fileName);

            if (reparseResult.Errors.Any(e => e.Severity == ErrorSeverity.Error))
            {
                var errorMessages = string.Join("; ", reparseResult.Errors.Where(e => e.Severity == ErrorSeverity.Error).Select(e => e.Message));
                warnings.Add($"Formatter would produce invalid output (reparse errors: {errorMessages}). Returning original source.");
                return new FormatResult { Text = originalSource, Success = false, Warnings = warnings };
            }

            // Safety gate 2: Idempotence check — format the output again and verify identical
            var reformatter = new Formatter(_state.RebuildConfig());
            var reformatted = reformatter.Format(reparseResult.CompilationUnit!, lexer.Comments);

            if (!string.Equals(formatted, reformatted, StringComparison.Ordinal))
            {
                warnings.Add("Formatter output is not idempotent (formatting again produces different output). Returning original source.");
                return new FormatResult { Text = originalSource, Success = false, Warnings = warnings };
            }

            return new FormatResult { Text = formatted, Success = true, Warnings = warnings };
    }

    public string Format(CompilationUnit ast, List<CommentTrivia>? comments = null)
    {
        _state.BeginFile(comments);
        var sb = new StringBuilder();

        // Format namespace declaration
        if (ast.Namespace != null)
        {
            _state.EmitCommentsBefore(ast.Namespace.Line, sb);
            if (_state.HasBlankLineBefore(ast.Namespace.Line))
            {
                sb.AppendLine();
            }
            sb.AppendLine($"namespace {ast.Namespace.Name}");
            _state.LastEmittedSourceLine = ast.Namespace.Line;
            sb.AppendLine();
        }

        var sortedImports = FormatterImportOrderer.OrderBySystemThenNamespace(ast.Imports);

        // Format imports
        foreach (var import in sortedImports)
        {
            _state.EmitCommentsBefore(import.Line, sb);
            sb.Append("import ");
            sb.Append(import.Namespace);
            if (import.Alias != null)
            {
                sb.Append($" as {import.Alias}");
            }
            sb.AppendLine();
            _state.LastEmittedSourceLine = import.Line;
        }

        // Format file imports
        foreach (var fileImport in ast.FileImports)
        {
            if (fileImport is FileImport fi)
            {
                _state.EmitCommentsBefore(fi.Line, sb);
                sb.Append($"import \"{fi.Path}\"");
                if (fi.Alias != null)
                {
                    sb.Append($" as {fi.Alias}");
                }
                sb.AppendLine();
                _state.LastEmittedSourceLine = fi.Line;
            }
        }

        if (ast.Imports.Count > 0 || ast.FileImports.Count > 0)
        {
            sb.AppendLine();
        }

        // Format package declaration after imports to match parser and language syntax.
        if (ast.Package != null)
        {
            _state.EmitCommentsBefore(ast.Package.Line, sb);
            sb.AppendLine($"package {ast.Package.Name}");
            _state.LastEmittedSourceLine = ast.Package.Line;
            sb.AppendLine();
        }

        // Format declarations with blank line preservation
        for (int i = 0; i < ast.Declarations.Count; i++)
        {
            var decl = ast.Declarations[i];
            _state.EmitCommentsBefore(decl.Line, sb);
            // Preserve blank lines between declarations based on source gap. The tracker accounts
            // for any comments just emitted, so a comment closes the gap it stood in.
            if (i > 0 && _state.HasBlankLineBefore(decl.Line))
            {
                sb.AppendLine();
            }
            FormatDeclaration(decl, sb);
            // Gaps are measured from the declaration's END line; measuring from its start counts a
            // multi-line body as a phantom gap and breaks idempotence when formatting reflows lines.
            _state.LastEmittedSourceLine = decl.EndLine;
        }

        // Emit any trailing comments after all declarations
        _state.EmitRemainingComments(sb);

        return sb.ToString();
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
            _state.EmitCommentsBefore(member.Line, sb);
            if (i > 0 && _state.HasBlankLineBefore(member.Line))
            {
                sb.AppendLine();
            }
            FormatDeclaration(member, sb);
            _state.LastEmittedSourceLine = member.EndLine;
        }
    }

    private void FormatDeclaration(Declaration decl, StringBuilder sb)
    {
        switch (decl)
        {
            case FunctionDeclaration func:
                _walk.FormatFunction(func, sb);
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
            case SoaRecordDeclaration soa:
                FormatSoaRecord(soa, sb);
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
                _state.Indent(sb);
                sb.AppendLine($"type {alias.Name} = {FormatterSyntaxText.FormatTypeReference(alias.Type)}");
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
                _state.Indent(sb);
                sb.AppendLine($"type {newtype.Name} = newtype {FormatterSyntaxText.FormatTypeReference(newtype.UnderlyingType)}");
                break;
            case PreprocessorDeclaration preproc:
                _state.Indent(sb);
                sb.AppendLine(preproc.Directive);
                break;
            default:
                throw new InvalidOperationException($"Formatter does not handle declaration type: {decl.GetType().Name}");
        }
    }

    private void FormatClass(ClassDeclaration cls, StringBuilder sb)
    {
        _walk.FormatAttributes(cls.Attributes, sb);
        _state.Indent(sb);

        var mods = FormatterSyntaxText.FormatModifiers(cls.Modifiers, cls.Name, true);
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
                _walk.FormatParameter(cls.PrimaryConstructorParameters[i], sb);
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
            bases.Add(FormatterSyntaxText.FormatTypeReference(cls.BaseClass));
        }
        bases.AddRange(cls.Interfaces.Select(FormatterSyntaxText.FormatTypeReference));

        if (bases.Count > 0)
        {
            sb.Append(": ");
            sb.Append(string.Join(", ", bases));
        }

        sb.AppendLine(" {");
        _state.Push();
        FormatMembers(cls.Members, sb);
        _state.Pop();
        _state.Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatStruct(StructDeclaration str, StringBuilder sb)
    {
        _walk.FormatAttributes(str.Attributes, sb);
        _state.Indent(sb);

        var mods = FormatterSyntaxText.FormatModifiers(str.Modifiers, str.Name, true);
        if (!string.IsNullOrEmpty(mods))
        {
            sb.Append(mods);
            sb.Append(" ");
        }

        sb.Append(str.IsRefStruct ? "ref struct " : "struct ");
        sb.Append(str.Name);

        if (str.TypeParameters != null && str.TypeParameters.Count > 0)
        {
            sb.Append("<");
            sb.Append(string.Join(", ", str.TypeParameters.Select(tp => tp.Name)));
            sb.Append(">");
        }

        if (str.PrimaryConstructorParameters != null && str.PrimaryConstructorParameters.Count > 0)
        {
            sb.Append("(");
            for (int i = 0; i < str.PrimaryConstructorParameters.Count; i++)
            {
                _walk.FormatParameter(str.PrimaryConstructorParameters[i], sb);
                if (i < str.PrimaryConstructorParameters.Count - 1)
                {
                    sb.Append(", ");
                }
            }
            sb.Append(")");
        }

        if (str.Interfaces.Count > 0)
        {
            sb.Append(": ");
            sb.Append(string.Join(", ", str.Interfaces.Select(FormatterSyntaxText.FormatTypeReference)));
        }

        sb.AppendLine(" {");
        _state.Push();
        FormatMembers(str.Members, sb);
        _state.Pop();
        _state.Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatRecord(RecordDeclaration rec, StringBuilder sb)
    {
        _walk.FormatAttributes(rec.Attributes, sb);
        _state.Indent(sb);

        var mods = FormatterSyntaxText.FormatModifiers(rec.Modifiers, rec.Name, true);
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
                _walk.FormatParameter(rec.PrimaryConstructorParameters[i], sb);
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
            sb.Append(string.Join(", ", rec.Interfaces.Select(FormatterSyntaxText.FormatTypeReference)));
        }

        // The grammar requires a braced body on every record, so an empty member list still emits braces.
        sb.AppendLine(" {");
        _state.Push();
        FormatMembers(rec.Members, sb);
        _state.Pop();
        _state.Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatSoaRecord(SoaRecordDeclaration soa, StringBuilder sb)
    {
        _walk.FormatAttributes(soa.Attributes, sb);
        _state.Indent(sb);

        var mods = FormatterSyntaxText.FormatModifiers(soa.Modifiers, soa.Name, true);
        if (!string.IsNullOrEmpty(mods))
        {
            sb.Append(mods);
            sb.Append(" ");
        }

        sb.Append("soa record ");
        sb.Append(soa.Name);
        sb.AppendLine(" {");
        _state.Push();
        foreach (var column in soa.Columns)
        {
            _state.Indent(sb);
            sb.Append(column.Name);
            sb.Append(": ");
            sb.Append(FormatterSyntaxText.FormatTypeReference(column.Type));
            sb.AppendLine();
        }
        _state.Pop();
        _state.Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatInterface(InterfaceDeclaration iface, StringBuilder sb)
    {
        _walk.FormatAttributes(iface.Attributes, sb);
        _state.Indent(sb);

        var mods = FormatterSyntaxText.FormatModifiers(iface.Modifiers, iface.Name, true);
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
            sb.Append(string.Join(", ", iface.BaseInterfaces.Select(FormatterSyntaxText.FormatTypeReference)));
        }

        sb.AppendLine(" {");
        _state.Push();
        FormatMembers(iface.Members, sb);
        _state.Pop();
        _state.Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatUnion(UnionDeclaration union, StringBuilder sb)
    {
        _walk.FormatAttributes(union.Attributes, sb);
        _state.Indent(sb);

        var mods = FormatterSyntaxText.FormatModifiers(union.Modifiers, union.Name, true);
        if (!string.IsNullOrEmpty(mods))
        {
            sb.Append(mods);
            sb.Append(" ");
        }

        sb.Append("union ");
        sb.Append(union.Name);

        if (union.TypeParameters != null && union.TypeParameters.Count > 0)
        {
            sb.Append("<");
            sb.Append(string.Join(", ", union.TypeParameters.Select(tp => tp.Name)));
            sb.Append(">");
        }

        sb.AppendLine(" {");

        _state.Push();
        for (int i = 0; i < union.Cases.Count; i++)
        {
            var c = union.Cases[i];
            _state.Indent(sb);
            sb.Append(c.Name);

            if (c.Properties != null && c.Properties.Count > 0)
            {
                sb.Append(" { ");
                for (int j = 0; j < c.Properties.Count; j++)
                {
                    var prop = c.Properties[j];
                    sb.Append(prop.Name);
                    sb.Append(": ");
                    sb.Append(FormatterSyntaxText.FormatTypeReference(prop.Type));
                    if (j < c.Properties.Count - 1)
                    {
                        sb.Append(", ");
                    }
                }
                sb.Append(" }");
            }

            sb.AppendLine();
        }
        _state.Pop();

        _state.Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatEnum(EnumDeclaration enumDecl, StringBuilder sb)
    {
        _walk.FormatAttributes(enumDecl.Attributes, sb);
        _state.Indent(sb);

        var mods = FormatterSyntaxText.FormatModifiers(enumDecl.Modifiers, enumDecl.Name, true);
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

        _state.Push();
        for (int i = 0; i < enumDecl.Members.Count; i++)
        {
            var member = enumDecl.Members[i];
            _state.Indent(sb);
            sb.Append(member.Name);

            if (member.Value != null)
            {
                sb.Append(" = ");
                _walk.FormatExpression(member.Value, sb);
            }

            if (i < enumDecl.Members.Count - 1)
            {
                sb.Append(",");
            }

            sb.AppendLine();
        }
        _state.Pop();

        _state.Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatField(FieldDeclaration field, StringBuilder sb)
    {
        _walk.FormatAttributes(field.Attributes, sb);
        _state.Indent(sb);

        var mods = FormatterSyntaxText.FormatModifiers(field.Modifiers, field.Name, true);
        if (!string.IsNullOrEmpty(mods))
        {
            sb.Append(mods);
            sb.Append(" ");
        }

        sb.Append(field.Name);

        if (field.Type != null)
        {
            sb.Append(": ");
            sb.Append(FormatterSyntaxText.FormatTypeReference(field.Type));
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
            _walk.FormatExpression(field.Initializer, sb);
        }

        sb.AppendLine();
    }

    private void FormatProperty(PropertyDeclaration prop, StringBuilder sb)
    {
        _walk.FormatAttributes(prop.Attributes, sb);
        _state.Indent(sb);

        var mods = FormatterSyntaxText.FormatModifiers(prop.Modifiers, prop.Name, true);
        if (!string.IsNullOrEmpty(mods))
        {
            sb.Append(mods);
            sb.Append(" ");
        }

        sb.Append(prop.Name);
        sb.Append(": ");
        sb.Append(FormatterSyntaxText.FormatTypeReference(prop.Type));

        if (prop.ExpressionBody != null)
        {
            sb.Append(" => ");
            _walk.FormatExpression(prop.ExpressionBody, sb);
            sb.AppendLine();
        }
        else if (prop.GetBody != null || prop.SetBody != null)
        {
            sb.AppendLine(" {");
            _state.Push();

            if (prop.GetBody != null)
            {
                _state.Indent(sb);
                sb.AppendLine("get {");
                _state.Push();
                _walk.FormatBlock(prop.GetBody, sb);
                _state.Pop();
                _state.Indent(sb);
                sb.AppendLine("}");
            }

            if (prop.SetBody != null)
            {
                _state.Indent(sb);
                sb.AppendLine("set {");
                _state.Push();
                _walk.FormatBlock(prop.SetBody, sb);
                _state.Pop();
                _state.Indent(sb);
                sb.AppendLine("}");
            }

            _state.Pop();
            _state.Indent(sb);
            sb.AppendLine("}");
        }
        else
        {
            sb.AppendLine();
        }
    }

    private void FormatConstructor(ConstructorDeclaration ctor, StringBuilder sb)
    {
        _walk.FormatAttributes(ctor.Attributes, sb);
        _state.Indent(sb);

        var mods = FormatterSyntaxText.FormatModifiers(ctor.Modifiers, null, true);
        if (!string.IsNullOrEmpty(mods))
        {
            sb.Append(mods);
            sb.Append(" ");
        }

        sb.Append("constructor(");
        for (int i = 0; i < ctor.Parameters.Count; i++)
        {
            _walk.FormatParameter(ctor.Parameters[i], sb);
            if (i < ctor.Parameters.Count - 1)
            {
                sb.Append(", ");
            }
        }
        sb.Append(")");

        if (ctor.Initializer != null)
        {
            sb.Append(": ");
            _walk.FormatExpression(ctor.Initializer, sb);
        }

        sb.AppendLine(" {");
        _state.Push();
        _walk.FormatBlock(ctor.Body, sb);
        _state.Pop();
        _state.Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatIndexer(IndexerDeclaration indexer, StringBuilder sb)
    {
        _walk.FormatAttributes(indexer.Attributes, sb);
        _state.Indent(sb);

        var mods = FormatterSyntaxText.FormatModifiers(indexer.Modifiers, null, true);
        if (!string.IsNullOrEmpty(mods))
        {
            sb.Append(mods);
            sb.Append(" ");
        }

        sb.Append("this[");
        for (int i = 0; i < indexer.Parameters.Count; i++)
        {
            _walk.FormatParameter(indexer.Parameters[i], sb);
            if (i < indexer.Parameters.Count - 1)
            {
                sb.Append(", ");
            }
        }
        sb.Append("]: ");
        sb.Append(FormatterSyntaxText.FormatTypeReference(indexer.Type));
        sb.AppendLine(" {");

        _state.Push();
        if (indexer.GetBody != null)
        {
            _state.Indent(sb);
            sb.AppendLine("get {");
            _state.Push();
            _walk.FormatBlock(indexer.GetBody, sb);
            _state.Pop();
            _state.Indent(sb);
            sb.AppendLine("}");
        }

        if (indexer.SetBody != null)
        {
            _state.Indent(sb);
            sb.AppendLine("set {");
            _state.Push();
            _walk.FormatBlock(indexer.SetBody, sb);
            _state.Pop();
            _state.Indent(sb);
            sb.AppendLine("}");
        }
        _state.Pop();

        _state.Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatTest(TestDeclaration test, StringBuilder sb)
    {
        _state.Indent(sb);
        sb.Append("test ");
        sb.Append($"\"{test.Description}\"");

        // Table-driven parameters and cases
        if (test.TableParameters != null && test.TableCases != null)
        {
            sb.Append(" with (");
            sb.Append(string.Join(", ", test.TableParameters.Select(p =>
                $"{p.Name}: {FormatterSyntaxText.FormatTypeReference(p.Type)}")));
            sb.AppendLine(") [");
            _state.Push();
            for (int i = 0; i < test.TableCases.Count; i++)
            {
                _state.Indent(sb);
                sb.Append("(");
                var exprs = new List<string>();
                foreach (var expr in test.TableCases[i])
                {
                    var exprSb = new StringBuilder();
                    _walk.FormatExpression(expr, exprSb);
                    exprs.Add(exprSb.ToString());
                }
                sb.Append(string.Join(", ", exprs));
                sb.Append(")");
                if (i < test.TableCases.Count - 1)
                    sb.Append(",");
                sb.AppendLine();
            }
            _state.Pop();
            _state.Indent(sb);
            sb.Append("]");
        }

        // Skip reason
        if (test.SkipReason != null)
        {
            sb.Append($" skip \"{test.SkipReason}\"");
        }

        sb.AppendLine(" {");
        _state.Push();
        _walk.FormatBlock(test.Body, sb);
        _state.Pop();
        _state.Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatSetup(SetupDeclaration setup, StringBuilder sb)
    {
        _state.Indent(sb);
        sb.AppendLine("setup {");
        _state.Push();
        _walk.FormatBlock(setup.Body, sb);
        _state.Pop();
        _state.Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatTeardown(TeardownDeclaration teardown, StringBuilder sb)
    {
        _state.Indent(sb);
        sb.AppendLine("teardown {");
        _state.Push();
        _walk.FormatBlock(teardown.Body, sb);
        _state.Pop();
        _state.Indent(sb);
        sb.AppendLine("}");
    }
}
