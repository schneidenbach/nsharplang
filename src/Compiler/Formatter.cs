using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using NewCLILang.Compiler.Ast;

namespace NewCLILang.Compiler;

public class Formatter
{
    private int _indent = 0;
    private const string IndentString = "    "; // 4 spaces

    public string Format(CompilationUnit ast)
    {
        var sb = new StringBuilder();

        // Format package declaration
        if (ast.Package != null)
        {
            sb.AppendLine($"package {ast.Package.Name}");
            sb.AppendLine();
        }

        // Format namespace declaration
        if (ast.Namespace != null)
        {
            sb.AppendLine($"namespace {ast.Namespace.Name}");
            sb.AppendLine();
        }

        // Format imports
        foreach (var import in ast.Imports)
        {
            sb.Append("import ");
            sb.Append(import.Namespace);
            if (import.Alias != null)
            {
                sb.Append($" as {import.Alias}");
            }
            sb.AppendLine();
        }

        // Format file imports
        foreach (var fileImport in ast.FileImports)
        {
            if (fileImport is FileImport fi)
            {
                sb.Append($"import \"{fi.Path}\"");
                if (fi.Alias != null)
                {
                    sb.Append($" as {fi.Alias}");
                }
                sb.AppendLine();
            }
        }

        if (ast.Imports.Count > 0 || ast.FileImports.Count > 0)
        {
            sb.AppendLine();
        }

        // Format declarations
        for (int i = 0; i < ast.Declarations.Count; i++)
        {
            FormatDeclaration(ast.Declarations[i], sb);
            if (i < ast.Declarations.Count - 1)
            {
                sb.AppendLine();
            }
        }

        return sb.ToString();
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
            case PreprocessorDeclaration preproc:
                Indent(sb);
                sb.AppendLine(preproc.Directive);
                break;
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
        for (int i = 0; i < cls.Members.Count; i++)
        {
            FormatDeclaration(cls.Members[i], sb);
        }
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
        for (int i = 0; i < str.Members.Count; i++)
        {
            FormatDeclaration(str.Members[i], sb);
        }
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
            for (int i = 0; i < rec.Members.Count; i++)
            {
                FormatDeclaration(rec.Members[i], sb);
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
        for (int i = 0; i < iface.Members.Count; i++)
        {
            FormatDeclaration(iface.Members[i], sb);
        }
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
                sb.Append("(");
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
                sb.Append(")");
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
        sb.AppendLine(" {");
        _indent++;
        FormatBlock(test.Body, sb);
        _indent--;
        Indent(sb);
        sb.AppendLine("}");
    }

    private void FormatBlock(BlockStatement block, StringBuilder sb)
    {
        foreach (var stmt in block.Statements)
        {
            FormatStatement(stmt, sb);
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
                sb.Append("(");
                sb.Append(string.Join(", ", tupleDecl.Names));
                sb.Append(") := ");
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
                            sb.Append(" = ");
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
                sb.Append("foreach ");
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
                        sb.Append(" ");
                        sb.Append(FormatTypeReference(catchClause.ExceptionType));
                        if (catchClause.VariableName != null)
                        {
                            sb.Append(" ");
                            sb.Append(catchClause.VariableName);
                        }
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
                sb.AppendLine();
                break;

            case PreprocessorDirective preproc:
                Indent(sb);
                sb.AppendLine(preproc.Directive);
                break;

            case EmptyStatement:
                break;
        }
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
                if (lambda.Parameters.Count == 1 && lambda.Parameters[0].Type == null)
                {
                    sb.Append(lambda.Parameters[0].Name);
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
                sb.Append("new ");
                if (newExpr.Type != null)
                {
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
                    sb.Append(" { ");
                    for (int i = 0; i < newExpr.Initializer.Properties.Count; i++)
                    {
                        var prop = newExpr.Initializer.Properties[i];
                        if (prop.Name != null)
                        {
                            sb.Append(prop.Name);
                            sb.Append(" = ");
                        }
                        FormatExpression(prop.Value, sb);
                        if (i < newExpr.Initializer.Properties.Count - 1)
                        {
                            sb.Append(", ");
                        }
                    }
                    sb.Append(" }");
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
                FormatExpression(match.Value, sb);
                sb.AppendLine(" match {");
                _indent++;
                foreach (var caseExpr in match.Cases)
                {
                    Indent(sb);
                    FormatPattern(caseExpr.Pattern, sb);
                    if (caseExpr.Guard != null)
                    {
                        sb.Append(" when ");
                        FormatExpression(caseExpr.Guard, sb);
                    }
                    sb.Append(" => ");
                    FormatExpression(caseExpr.Expression, sb);
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
                        sb.Append(" = ");
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
                    sb.Append("(");
                    for (int i = 0; i < unionCase.Properties.Count; i++)
                    {
                        var prop = unionCase.Properties[i];
                        sb.Append(prop.Name);
                        sb.Append(": ");
                        if (prop.Pattern != null)
                        {
                            FormatPattern(prop.Pattern, sb);
                        }
                        else if (prop.BindingName != null)
                        {
                            sb.Append(prop.BindingName);
                        }
                        if (i < unionCase.Properties.Count - 1)
                        {
                            sb.Append(", ");
                        }
                    }
                    sb.Append(")");
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
                    var prop = obj.Properties[i];
                    sb.Append(prop.Name);
                    sb.Append(": ");
                    if (prop.Pattern != null)
                    {
                        FormatPattern(prop.Pattern, sb);
                    }
                    else if (prop.BindingName != null)
                    {
                        sb.Append(prop.BindingName);
                    }
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
        }
    }

    private void FormatParameter(Parameter param, StringBuilder sb)
    {
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
            _ => "unknown"
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
            _ => "?"
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
            _ => "?"
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
            _ => "="
        };
    }

    private void Indent(StringBuilder sb)
    {
        for (int i = 0; i < _indent; i++)
        {
            sb.Append(IndentString);
        }
    }
}
