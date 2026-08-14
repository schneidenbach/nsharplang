using System;
using System.Collections.Generic;
using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler;

/// <summary>Main linter class that analyzes code and returns diagnostics</summary>
public class Linter
{
    private readonly LinterConfig _config;

    public Linter(LinterConfig? config = null)
    {
        _config = config ?? LinterConfig.Default();
    }

    public List<Diagnostic> Lint(CompilationUnit ast, string? filePath = null, string? sourceText = null)
    {
        var visitor = new LintVisitor(filePath, sourceText, _config);
        visitor.Visit(ast);
        return visitor.Diagnostics;
    }

}

/// <summary>AST visitor that performs linting checks</summary>
internal class LintVisitor
{
    // Every piece of per-file lint state belongs to the N# state owner, and the function, statement and
    // expression arms of the walk belong to the N# walk owner. What is left here is the DECLARATION
    // walk — the only part of the walk the N# owner is entered from.
    private readonly LinterWalkState _state;
    private readonly LinterWalk _walk;

    public List<Diagnostic> Diagnostics => _state.Diagnostics;

    public LintVisitor(string? filePath = null, string? sourceText = null, LinterConfig? config = null)
    {
        _state = new LinterWalkState(filePath, sourceText, config ?? LinterConfig.Default());
        _walk = new LinterWalk(_state);
    }

    public void Visit(CompilationUnit unit)
    {
        // Track imported namespaces and file symbols for NL002 and NL010
        _state.RegisterImports(unit);

        // Push global scope
        _state.PushScope();

        // Visit all declarations
        foreach (var declaration in unit.Declarations)
        {
            VisitDeclaration(declaration);
        }

        // Check for unused variables in global scope
        _state.CheckUnusedVariables();
        _state.PopScope();

        // NL010: Check for unused imports (after visiting the whole file)
        _state.CheckUnusedImports();
    }

    private void VisitDeclaration(Declaration declaration)
    {
        switch (declaration)
        {
            case FunctionDeclaration func:
                _walk.VisitFunction(func);
                break;
            case ClassDeclaration classDecl:
                _state.TrackTypeReference(classDecl.BaseClass);
                foreach (var iface in classDecl.Interfaces) _state.TrackTypeReference(iface);
                VisitClass(classDecl);
                break;
            case StructDeclaration structDecl:
                foreach (var iface in structDecl.Interfaces) _state.TrackTypeReference(iface);
                VisitStruct(structDecl);
                break;
            case RecordDeclaration recordDecl:
                foreach (var iface in recordDecl.Interfaces) _state.TrackTypeReference(iface);
                VisitRecord(recordDecl);
                break;
            case SoaRecordDeclaration soaRecordDecl:
                foreach (var column in soaRecordDecl.Columns)
                {
                    _state.TrackTypeReference(column.Type);
                }
                break;
            case InterfaceDeclaration interfaceDecl:
                foreach (var iface in interfaceDecl.BaseInterfaces) _state.TrackTypeReference(iface);
                VisitInterface(interfaceDecl);
                break;
            case UnionDeclaration unionDecl:
                break;
            case EnumDeclaration enumDecl:
                break;
            case FieldDeclaration field:
                _state.TrackTypeReference(field.Type);
                if (field.Initializer != null)
                    _walk.VisitExpression(field.Initializer);
                break;
            case PropertyDeclaration prop:
                _state.TrackTypeReference(prop.Type);
                if (prop.ExpressionBody != null)
                    _walk.VisitExpression(prop.ExpressionBody);
                if (prop.GetBody != null)
                    _walk.VisitStatement(prop.GetBody);
                if (prop.SetBody != null)
                    _walk.VisitStatement(prop.SetBody);
                break;
            case ConstructorDeclaration ctor:
                _walk.VisitStatement(ctor.Body);
                break;
            case TestDeclaration test:
                if (test.TableParameters != null)
                {
                    foreach (var param in test.TableParameters)
                        _state.TrackTypeReference(param.Type);
                }
                if (test.TableCases != null)
                {
                    foreach (var row in test.TableCases)
                        foreach (var expr in row)
                            _walk.VisitExpression(expr);
                }
                _walk.VisitStatement(test.Body);
                break;
            case SetupDeclaration setup:
                _walk.VisitStatement(setup.Body);
                break;
            case TeardownDeclaration teardown:
                _walk.VisitStatement(teardown.Body);
                break;
        }
    }

    private void VisitClass(ClassDeclaration classDecl)
    {
        VisitWithTypeMemberScope(classDecl.Members, classDecl.PrimaryConstructorParameters, () =>
        {
            foreach (var member in classDecl.Members)
            {
                VisitDeclaration(member);
            }
        });
    }

    private void VisitStruct(StructDeclaration structDecl)
    {
        VisitWithTypeMemberScope(structDecl.Members, structDecl.PrimaryConstructorParameters, () =>
        {
            foreach (var member in structDecl.Members)
            {
                VisitDeclaration(member);
            }
        });
    }

    private void VisitRecord(RecordDeclaration recordDecl)
    {
        VisitWithTypeMemberScope(recordDecl.Members, recordDecl.PrimaryConstructorParameters, () =>
        {
            foreach (var member in recordDecl.Members)
            {
                VisitDeclaration(member);
            }
        });
    }

    private void VisitInterface(InterfaceDeclaration interfaceDecl)
    {
        foreach (var member in interfaceDecl.Members)
        {
            VisitDeclaration(member);
        }
    }

    private void VisitWithTypeMemberScope(
        List<Declaration> members,
        List<Parameter>? primaryConstructorParameters,
        Action visit)
    {
        _state.PushTypeMemberScope(members, primaryConstructorParameters);
        try
        {
            visit();
        }
        finally
        {
            _state.PopTypeMemberScope();
        }
    }

}
