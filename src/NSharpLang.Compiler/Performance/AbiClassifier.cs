using System;
using System.Collections.Generic;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.Performance;

/// <summary>
/// The ABI boundary a declaration sits on, ordered from most-visible to least.
/// This is a self-contained classification used by the performance pipeline to
/// decide how aggressively a declaration can be specialized: declarations that
/// are not visible across the CLR/assembly boundary can use a tighter,
/// performance-oriented ABI without breaking C# interop.
/// </summary>
public enum AbiBoundary
{
    /// <summary>Visible to external CLR consumers (public surface).</summary>
    ClrPublic,

    /// <summary>Visible only within the emitted assembly (internal).</summary>
    ClrInternal,

    /// <summary>File-scoped (camelCase convention or explicit `file` modifier).</summary>
    FilePrivate,

    /// <summary>Local functions / lambdas nested inside a member body.</summary>
    Local,
}

/// <summary>
/// A single classification result for a declaration.
/// </summary>
public readonly record struct AbiClassification(
    string Name,
    AbiBoundary Boundary,
    int Line,
    int Column);

/// <summary>
/// Pure-analysis pass that classifies each declaration in a parsed
/// <see cref="CompilationUnit"/> by its ABI boundary. This pass performs NO
/// emitter changes and has NO behavioral effect; it only builds a lookup table
/// that downstream performance passes can consult.
/// </summary>
public sealed class AbiClassifier
{
    private readonly Dictionary<DeclarationKey, AbiClassification> _classifications = new();

    /// <summary>Identity key for a classified declaration.</summary>
    public readonly record struct DeclarationKey(string File, int Line, int Column);

    private readonly string _file;

    public AbiClassifier(string file = "")
    {
        _file = file;
    }

    /// <summary>All classifications collected during <see cref="Classify"/>.</summary>
    public IReadOnlyDictionary<DeclarationKey, AbiClassification> Classifications => _classifications;

    /// <summary>
    /// Walks the compilation unit and classifies every type, top-level function,
    /// nested member, and local function. Returns the populated lookup so callers
    /// can chain. Safe to call multiple times (results accumulate / overwrite by key).
    /// </summary>
    public AbiClassifier Classify(CompilationUnit unit)
    {
        if (unit is null)
        {
            return this;
        }

        foreach (var declaration in unit.Declarations)
        {
            ClassifyTopLevel(declaration);
        }

        return this;
    }

    /// <summary>
    /// Looks up a previously-computed classification by source position.
    /// </summary>
    public bool TryGet(int line, int column, out AbiClassification classification)
    {
        return _classifications.TryGetValue(new DeclarationKey(_file, line, column), out classification);
    }

    /// <summary>
    /// Convenience lookup that returns the boundary directly, or null if the
    /// position was not classified.
    /// </summary>
    public AbiBoundary? GetBoundary(int line, int column)
    {
        return TryGet(line, column, out var classification) ? classification.Boundary : null;
    }

    private void ClassifyTopLevel(Declaration declaration)
    {
        switch (declaration)
        {
            case FunctionDeclaration func:
                Record(func.Name, func.Modifiers, func.Line, func.Column, isTopLevel: true);
                WalkFunctionBody(func);
                break;

            case ClassDeclaration cls:
                Record(cls.Name, cls.Modifiers, cls.Line, cls.Column, isTopLevel: true);
                ClassifyMembers(cls.Members);
                break;

            case StructDeclaration st:
                Record(st.Name, st.Modifiers, st.Line, st.Column, isTopLevel: true);
                ClassifyMembers(st.Members);
                break;

            case RecordDeclaration rec:
                Record(rec.Name, rec.Modifiers, rec.Line, rec.Column, isTopLevel: true);
                ClassifyMembers(rec.Members);
                break;

            case InterfaceDeclaration iface:
                Record(iface.Name, iface.Modifiers, iface.Line, iface.Column, isTopLevel: true);
                ClassifyMembers(iface.Members);
                break;

            case UnionDeclaration union:
                Record(union.Name, union.Modifiers, union.Line, union.Column, isTopLevel: true);
                break;

            case EnumDeclaration en:
                Record(en.Name, en.Modifiers, en.Line, en.Column, isTopLevel: true);
                break;
        }
    }

    private void ClassifyMembers(List<Declaration> members)
    {
        foreach (var member in members)
        {
            switch (member)
            {
                case FunctionDeclaration func:
                    Record(func.Name, func.Modifiers, func.Line, func.Column, isTopLevel: false);
                    WalkFunctionBody(func);
                    break;

                case FieldDeclaration field:
                    Record(field.Name, field.Modifiers, field.Line, field.Column, isTopLevel: false);
                    break;

                case PropertyDeclaration prop:
                    Record(prop.Name, prop.Modifiers, prop.Line, prop.Column, isTopLevel: false);
                    break;

                // Nested types are themselves type declarations; recurse so their
                // members (and any nested local functions) are classified too.
                case ClassDeclaration:
                case StructDeclaration:
                case RecordDeclaration:
                case InterfaceDeclaration:
                case UnionDeclaration:
                case EnumDeclaration:
                    ClassifyTopLevel(member);
                    break;
            }
        }
    }

    /// <summary>
    /// Walks a function body for local function statements, classifying each as
    /// <see cref="AbiBoundary.Local"/> regardless of casing or modifiers.
    /// </summary>
    private void WalkFunctionBody(FunctionDeclaration func)
    {
        if (func.Body is { } body)
        {
            WalkBlock(body);
        }
    }

    private void WalkBlock(BlockStatement block)
    {
        foreach (var statement in block.Statements)
        {
            WalkStatement(statement);
        }
    }

    private void WalkStatement(Statement? statement)
    {
        switch (statement)
        {
            case null:
                break;

            case LocalFunctionStatement local:
                // Local functions are never part of any CLR ABI surface.
                RecordLocal(local.Function.Name, local.Function.Line, local.Function.Column);
                WalkFunctionBody(local.Function);
                break;

            case BlockStatement block:
                WalkBlock(block);
                break;

            // Control-flow statements can nest blocks (and therefore local
            // functions) in their bodies; recurse so none are missed.
            case IfStatement ifStmt:
                WalkStatement(ifStmt.ThenStatement);
                WalkStatement(ifStmt.ElseStatement);
                break;

            case ForStatement forStmt:
                WalkStatement(forStmt.Initializer);
                WalkStatement(forStmt.Body);
                break;

            case ForeachStatement foreachStmt:
                WalkStatement(foreachStmt.Body);
                break;

            case AwaitForEachStatement awaitForeach:
                WalkStatement(awaitForeach.Body);
                break;

            case WhileStatement whileStmt:
                WalkStatement(whileStmt.Body);
                break;

            case LockStatement lockStmt:
                WalkBlock(lockStmt.Body);
                break;

            case UsingStatement usingStmt:
                WalkStatement(usingStmt.Body);
                break;

            case TryStatement tryStmt:
                WalkBlock(tryStmt.TryBlock);
                foreach (var catchClause in tryStmt.CatchClauses)
                {
                    WalkBlock(catchClause.Block);
                }
                if (tryStmt.FinallyBlock is { } finallyBlock)
                {
                    WalkBlock(finallyBlock);
                }
                break;

            case SwitchStatement switchStmt:
                foreach (var switchCase in switchStmt.Cases)
                {
                    foreach (var caseStatement in switchCase.Statements)
                    {
                        WalkStatement(caseStatement);
                    }
                }
                break;
        }
    }

    private void Record(string name, Modifiers modifiers, int line, int column, bool isTopLevel)
    {
        var boundary = ClassifyBoundary(name, modifiers, isTopLevel);
        Add(new AbiClassification(name, boundary, line, column));
    }

    private void RecordLocal(string name, int line, int column)
    {
        Add(new AbiClassification(name, AbiBoundary.Local, line, column));
    }

    private void Add(AbiClassification classification)
    {
        var key = new DeclarationKey(_file, classification.Line, classification.Column);
        _classifications[key] = classification;
    }

    /// <summary>
    /// Classifies a <see cref="FunctionDeclaration"/> by its ABI boundary using the same
    /// rules as the full walk. Exposed so performance passes (e.g. generic specialization)
    /// can determine a single declaration's boundary without re-running the whole classifier.
    /// </summary>
    /// <param name="function">The function declaration to classify.</param>
    /// <param name="isTopLevel">
    /// <c>true</c> when the function is declared at compilation-unit scope (not a type member
    /// or local function); top-level camelCase declarations are file-private by convention.
    /// </param>
    public static AbiBoundary ClassifyFunctionBoundary(FunctionDeclaration function, bool isTopLevel)
    {
        ArgumentNullException.ThrowIfNull(function);
        return ClassifyBoundary(function.Name, function.Modifiers, isTopLevel);
    }

    /// <summary>
    /// Maps N# visibility conventions onto an <see cref="AbiBoundary"/>.
    /// </summary>
    /// <remarks>
    /// The <c>file</c> modifier always means file-private. Otherwise the existing
    /// <see cref="VisibilityConventions"/> helpers determine whether the symbol is
    /// exported (PascalCase / explicit public) vs. unexported (camelCase / explicit
    /// non-public). Exported declarations land on the public CLR surface; everything
    /// else is internal to the assembly.
    /// </remarks>
    private static AbiBoundary ClassifyBoundary(string name, Modifiers modifiers, bool isTopLevel)
    {
        if (modifiers.HasFlag(Modifiers.File))
        {
            return AbiBoundary.FilePrivate;
        }

        if (VisibilityConventions.IsExportedIdentifier(name, modifiers))
        {
            return AbiBoundary.ClrPublic;
        }

        // Unexported (camelCase by convention, or explicit private/protected/internal).
        // camelCase top-level declarations are file-private by N# convention; explicit
        // non-public modifiers and unexported members are assembly-internal.
        if (isTopLevel && !VisibilityConventions.HasExplicitVisibility(modifiers))
        {
            return AbiBoundary.FilePrivate;
        }

        return AbiBoundary.ClrInternal;
    }
}
