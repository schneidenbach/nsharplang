using System;
using System.Collections.Generic;
using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.Performance;

public sealed record SystemsReport(
    int SchemaVersion,
    string Profile,
    string Mode,
    string AotTarget,
    IReadOnlyList<string> Warmup,
    IReadOnlyList<SystemsFunctionSummary> Functions,
    IReadOnlyList<SystemsFinding> Findings,
    IReadOnlyList<SystemsTrustedSite> TrustedSites,
    SystemsReportSummary Summary)
{
    public static SystemsReport Empty(ProjectConfig? config) => new(
        1,
        config?.Language.Profile ?? "default",
        config?.Language.Systems.Mode ?? "strict",
        config?.Language.Systems.AotTarget ?? "nativeaot",
        config?.Language.Systems.Warmup.ToArray() ?? Array.Empty<string>(),
        Array.Empty<SystemsFunctionSummary>(),
        Array.Empty<SystemsFinding>(),
        Array.Empty<SystemsTrustedSite>(),
        new SystemsReportSummary(0, 0, 0, 0, 0, 0, 0));
}

public sealed record SystemsReportSummary(
    int Functions,
    int HotFunctions,
    int BoundaryFunctions,
    int Findings,
    int Errors,
    int Warnings,
    int TrustedSites);

public sealed record SystemsFunctionSummary(
    string Name,
    string File,
    int Line,
    int Column,
    bool IsHot,
    bool IsBoundary,
    bool AllocNone,
    string SummarySource,
    SystemsEffectFacts Effects,
    IReadOnlyList<string> Calls);

public sealed record SystemsEffectFacts(
    bool Allocates,
    bool Boxes,
    bool ConstructsDelegate,
    bool CapturesClosure,
    bool UsesRuntimeDispatch,
    bool UsesReflection,
    bool UsesDynamicCode,
    bool Throws,
    bool HasImplicitTrapObligation,
    bool UsesUnknownExternalCall,
    bool UsesResource,
    bool UsesPool,
    bool UsesConcurrencyPrimitive,
    bool RequiresWarmup,
    bool AotSafe);

public sealed record SystemsFinding(
    string Code,
    string Severity,
    string Effect,
    string Message,
    string File,
    int Line,
    int Column,
    int Length,
    string? Function,
    string? Policy,
    string? SummarySource,
    string? Suggestion,
    IReadOnlyList<string> CallPath);

public sealed record SystemsTrustedSite(
    string Function,
    string File,
    int Line,
    int Column,
    string? Reason,
    string? Owner,
    string? Review,
    string? Expires,
    bool HasUnsafe,
    int BodyStatementCount);

public static class SystemsFindingExtensions
{
    public static CompilerError ToCompilerError(this SystemsFinding finding)
    {
        var severity = string.Equals(finding.Severity, "error", StringComparison.OrdinalIgnoreCase)
            ? ErrorSeverity.Error
            : ErrorSeverity.Warning;

        return new CompilerError(ErrorCode.InvalidSyntax, finding.Message, finding.Line, finding.Column, severity)
        {
            DiagnosticIdOverride = finding.Code,
            FileName = finding.File,
            Length = finding.Length,
            Suggestion = finding.Suggestion,
            HumanExplanation = $"Systems policy '{finding.Policy ?? "local"}' rejected the '{finding.Effect}' effect.",
            ContextualHint = finding.CallPath.Count > 0
                ? $"effect path: {string.Join(" -> ", finding.CallPath)}"
                : null,
            DocsUrl = $"https://docs.n-sharp.dev/errors/{finding.Code}"
        };
    }
}

/// <summary>
/// Systems N# policy/effect analyzer. This is deliberately conservative and source based:
/// it gives the check/build/query surfaces deterministic facts without changing emitted IL.
/// </summary>
public sealed class SystemsAnalyzer
{
    private readonly string _projectRoot;
    private readonly ProjectConfig _config;
    private readonly List<SystemsFinding> _findings = new();
    private readonly List<SystemsFunctionSummary> _functions = new();
    private readonly List<SystemsTrustedSite> _trustedSites = new();
    private readonly Dictionary<string, FunctionDeclaration> _declaredFunctions = new(StringComparer.Ordinal);
    private readonly HashSet<string> _structTypes = new(StringComparer.Ordinal);
    private readonly HashSet<string> _enumTypes = new(StringComparer.Ordinal);

    public SystemsAnalyzer(string projectRoot, ProjectConfig? config)
    {
        _projectRoot = projectRoot;
        _config = config ?? ProjectFileParser.CreateDefault();
    }

    public SystemsReport Analyze(
        IReadOnlyDictionary<string, CompilationUnit> compilationUnits,
        PerformanceFactStore? performanceFacts = null)
    {
        _findings.Clear();
        _functions.Clear();
        _trustedSites.Clear();
        _declaredFunctions.Clear();
        _structTypes.Clear();
        _enumTypes.Clear();

        foreach (var (file, unit) in compilationUnits.OrderBy(kvp => kvp.Key, StringComparer.OrdinalIgnoreCase))
        {
            RegisterDeclarations(file, unit.Declarations, containingType: null);
        }

        foreach (var (file, unit) in compilationUnits.OrderBy(kvp => kvp.Key, StringComparer.OrdinalIgnoreCase))
        {
            AnalyzeDeclarations(file, unit.Declarations, containingType: null, performanceFacts);
        }

        var errors = _findings.Count(f => f.Severity == "error");
        var warnings = _findings.Count(f => f.Severity == "warning");
        return new SystemsReport(
            1,
            _config.Language.Profile,
            EffectiveMode,
            _config.Language.Systems.AotTarget,
            _config.Language.Systems.Warmup,
            _functions,
            _findings.OrderBy(f => f.File, StringComparer.OrdinalIgnoreCase).ThenBy(f => f.Line).ThenBy(f => f.Column).ToArray(),
            _trustedSites.OrderBy(t => t.File, StringComparer.OrdinalIgnoreCase).ThenBy(t => t.Line).ThenBy(t => t.Column).ToArray(),
            new SystemsReportSummary(
                _functions.Count,
                _functions.Count(f => f.IsHot),
                _functions.Count(f => f.IsBoundary),
                _findings.Count,
                errors,
                warnings,
                _trustedSites.Count));
    }

    private bool IsSystemsProfile => string.Equals(_config.Language.Profile, "systems", StringComparison.OrdinalIgnoreCase);
    private string EffectiveMode => IsSystemsProfile ? _config.Language.Systems.Mode : "strict";
    private bool IsAuditMode => IsSystemsProfile && string.Equals(EffectiveMode, "audit", StringComparison.OrdinalIgnoreCase);

    private void RegisterDeclarations(string file, IEnumerable<Declaration> declarations, string? containingType)
    {
        foreach (var declaration in declarations)
        {
            switch (declaration)
            {
                case FunctionDeclaration function:
                    RegisterFunction(containingType, function);
                    break;
                case ClassDeclaration cls:
                    RegisterDeclarations(file, cls.Members, cls.Name);
                    break;
                case StructDeclaration st:
                    _structTypes.Add(st.Name);
                    RegisterDeclarations(file, st.Members, st.Name);
                    break;
                case RecordDeclaration rec:
                    if (rec.IsStruct)
                        _structTypes.Add(rec.Name);
                    RegisterDeclarations(file, rec.Members, rec.Name);
                    break;
                case InterfaceDeclaration iface:
                    RegisterDeclarations(file, iface.Members, iface.Name);
                    break;
                case EnumDeclaration enm:
                    _enumTypes.Add(enm.Name);
                    break;
            }
        }
    }

    private void RegisterFunction(string? containingType, FunctionDeclaration function)
    {
        var qualified = containingType == null ? function.Name : $"{containingType}.{function.Name}";
        _declaredFunctions[function.Name] = function;
        _declaredFunctions[qualified] = function;
    }

    private void AnalyzeDeclarations(
        string file,
        IEnumerable<Declaration> declarations,
        string? containingType,
        PerformanceFactStore? performanceFacts)
    {
        foreach (var declaration in declarations)
        {
            switch (declaration)
            {
                case FunctionDeclaration function:
                    AnalyzeFunction(file, containingType, function, performanceFacts);
                    break;
                case ClassDeclaration cls:
                    AnalyzeDeclarations(file, cls.Members, cls.Name, performanceFacts);
                    break;
                case StructDeclaration st:
                    AnalyzeDeclarations(file, st.Members, st.Name, performanceFacts);
                    break;
                case RecordDeclaration rec:
                    AnalyzeDeclarations(file, rec.Members, rec.Name, performanceFacts);
                    break;
                case InterfaceDeclaration iface:
                    AnalyzeDeclarations(file, iface.Members, iface.Name, performanceFacts);
                    break;
            }
        }
    }

    private void AnalyzeFunction(
        string file,
        string? containingType,
        FunctionDeclaration function,
        PerformanceFactStore? performanceFacts)
    {
        var name = containingType == null ? function.Name : $"{containingType}.{function.Name}";
        var attributes = new AttributeSet(function.Attributes);
        var summary = new MutableFunctionSummary(name, file, function.Line, function.Column)
        {
            IsHot = attributes.Has("hot"),
            IsBoundary = attributes.Has("boundary"),
            AllocNone = attributes.Has("alloc") && attributes.AttributeHasArgument("alloc", "none"),
            FunctionAllows = attributes.AllowEffects(),
        };

        var context = new WalkContext(summary);
        if (function.Body != null)
            WalkStatement(function.Body, context);
        if (function.ExpressionBody != null)
            WalkExpression(function.ExpressionBody, context);

        var facts = new SystemsEffectFacts(
            summary.Allocates,
            summary.Boxes,
            summary.Delegate,
            summary.Closure,
            summary.Dispatch,
            summary.Reflection,
            summary.DynamicCode,
            summary.Throws,
            summary.ImplicitTrap,
            summary.UnknownExternalCall,
            summary.Resource,
            summary.Pool,
            summary.ConcurrencyPrimitive,
            summary.RequiresWarmup,
            AotSafe: !summary.DynamicCode && !summary.Reflection);

        var functionSummary = new SystemsFunctionSummary(
            name,
            file,
            function.Line,
            function.Column,
            summary.IsHot,
            summary.IsBoundary,
            summary.AllocNone,
            summary.IsHot ? "explicitHot" : "sourceInferred",
            facts,
            summary.Calls.Distinct(StringComparer.Ordinal).OrderBy(c => c, StringComparer.Ordinal).ToArray());
        _functions.Add(functionSummary);

        performanceFacts?.Record(file, function.Line, function.Column, PerformanceFacts.Default with
        {
            Allocation = summary.Allocates ? AllocationKind.Unknown : AllocationKind.None,
            Dispatch = summary.Dispatch ? DispatchKind.Virtual : DispatchKind.Direct,
            AotSafety = facts.AotSafe ? AotSafetyKind.NoReflection : AotSafetyKind.MetadataRequired
        });

        if (attributes.Has("trusted"))
        {
            var trusted = attributes.Get("trusted")!;
            var reason = AttributeString(trusted, "reason");
            var owner = AttributeString(trusted, "owner");
            var review = AttributeString(trusted, "review");
            var expires = AttributeString(trusted, "expires");
            _trustedSites.Add(new SystemsTrustedSite(
                name,
                file,
                function.Line,
                function.Column,
                reason,
                owner,
                review,
                expires,
                summary.HasUnsafe,
                function.Body?.Statements.Count ?? 0));

            if (string.IsNullOrWhiteSpace(reason) || string.IsNullOrWhiteSpace(owner) || string.IsNullOrWhiteSpace(review))
            {
                AddFinding(
                    "NSYS100",
                    "memorySafety",
                    "[trusted] requires reason, owner, and review metadata",
                    function.Line,
                    function.Column,
                    Math.Max(1, function.Name.Length),
                    summary,
                    ErrorSeverity.Error,
                    "Write [trusted(reason: \"...\", owner: \"...\", review: \"...\")] on the wrapper.");
            }
        }
    }

    private void WalkStatement(Statement statement, WalkContext context)
    {
        switch (statement)
        {
            case BlockStatement block:
                foreach (var child in block.Statements)
                    WalkStatement(child, context);
                break;
            case AllocBlockStatement allocBlock:
                context.PushAllocZone();
                WalkStatement(allocBlock.Body, context);
                context.PopAllocZone();
                break;
            case AllowStatement allow:
                context.PushAllows(allow.Effects);
                WalkStatement(allow.Body, context);
                context.PopAllows();
                break;
            case ExpressionStatement expression:
                WalkExpression(expression.Expression, context);
                break;
            case VariableDeclarationStatement variable:
                if (variable.Initializer != null)
                    WalkExpression(variable.Initializer, context);
                break;
            case TupleDeconstructionStatement tuple:
                WalkExpression(tuple.Initializer, context);
                break;
            case IfStatement ifStatement:
                WalkExpression(ifStatement.Condition, context);
                var guards = DeriveGuardsFromExitingIf(ifStatement);
                WalkStatement(ifStatement.ThenStatement, context);
                if (ifStatement.ElseStatement != null)
                {
                    context.PushGuards(guards);
                    WalkStatement(ifStatement.ElseStatement, context);
                    context.PopGuards();
                }
                context.AddGuards(guards);
                break;
            case ForStatement forStatement:
                if (forStatement.Initializer != null)
                    WalkStatement(forStatement.Initializer, context);
                if (forStatement.Condition != null)
                    WalkExpression(forStatement.Condition, context);
                context.PushGuards(DeriveLoopGuards(forStatement.Condition));
                WalkStatement(forStatement.Body, context);
                context.PopGuards();
                if (forStatement.Iterator != null)
                    WalkExpression(forStatement.Iterator, context);
                break;
            case ForeachStatement foreachStatement:
                WalkExpression(foreachStatement.Collection, context);
                WalkStatement(foreachStatement.Body, context);
                break;
            case AwaitForEachStatement awaitForEachStatement:
                context.Summary.Resource = true;
                AddHotFinding("NSYS090", "resource", "[hot] cannot be an async iterator or await foreach boundary", awaitForEachStatement, context);
                WalkExpression(awaitForEachStatement.Collection, context);
                WalkStatement(awaitForEachStatement.Body, context);
                break;
            case WhileStatement whileStatement:
                WalkExpression(whileStatement.Condition, context);
                context.PushGuards(DeriveLoopGuards(whileStatement.Condition));
                WalkStatement(whileStatement.Body, context);
                context.PopGuards();
                break;
            case ReturnStatement returnStatement:
                if (returnStatement.Value != null)
                    WalkExpression(returnStatement.Value, context);
                break;
            case YieldStatement yieldStatement:
                context.Summary.Allocates = true;
                context.Summary.Resource = true;
                AddHotFinding("NSYS010", "allocation", "[hot] cannot allocate iterator state machines", yieldStatement, context);
                if (yieldStatement.Value != null)
                    WalkExpression(yieldStatement.Value, context);
                break;
            case ThrowStatement throwStatement:
                context.Summary.Throws = true;
                AddHotFinding("NSYS120", "throw", "[hot] cannot throw exceptions", throwStatement, context);
                WalkExpression(throwStatement.Expression, context);
                break;
            case TryStatement tryStatement:
                context.Summary.Throws = true;
                if (context.Summary.IsHot)
                    AddHotFinding("NSYS120", "throw", "[hot] cannot use exception control flow", tryStatement, context);
                WalkStatement(tryStatement.TryBlock, context);
                foreach (var catchClause in tryStatement.CatchClauses)
                    WalkStatement(catchClause.Block, context);
                if (tryStatement.FinallyBlock != null)
                    WalkStatement(tryStatement.FinallyBlock, context);
                break;
            case UsingStatement usingStatement:
                context.Summary.Resource = true;
                AddHotFinding("NSYS090", "resource", "[hot] cannot create or open disposable resources", usingStatement, context);
                if (usingStatement.Declaration?.Initializer != null)
                    WalkExpression(usingStatement.Declaration.Initializer, context);
                if (usingStatement.Expression != null)
                    WalkExpression(usingStatement.Expression, context);
                if (usingStatement.Body != null)
                    WalkStatement(usingStatement.Body, context);
                break;
            case LockStatement lockStatement:
                context.Summary.ConcurrencyPrimitive = true;
                WalkExpression(lockStatement.LockObject, context);
                WalkStatement(lockStatement.Body, context);
                break;
            case SwitchStatement switchStatement:
                WalkExpression(switchStatement.Value, context);
                foreach (var switchCase in switchStatement.Cases)
                    foreach (var child in switchCase.Statements)
                        WalkStatement(child, context);
                break;
            case PrintStatement printStatement:
                context.Summary.UnknownExternalCall = true;
                AddUnknownExternalCall("Console.WriteLine", printStatement.Line, printStatement.Column, context);
                WalkExpression(printStatement.Value, context);
                break;
            case AssertStatement assertStatement:
                WalkExpression(assertStatement.Condition, context);
                if (assertStatement.Message != null)
                    WalkExpression(assertStatement.Message, context);
                break;
            case AssertThrowsStatement assertThrowsStatement:
                context.Summary.Throws = true;
                WalkStatement(assertThrowsStatement.Body, context);
                break;
            case LocalFunctionStatement localFunction:
                if (localFunction.Function.Body != null)
                    WalkStatement(localFunction.Function.Body, context);
                if (localFunction.Function.ExpressionBody != null)
                    WalkExpression(localFunction.Function.ExpressionBody, context);
                break;
        }
    }

    private void WalkExpression(Expression expression, WalkContext context, bool explicitAllocation = false)
    {
        switch (expression)
        {
            case AllocExpression alloc:
                WalkExpression(alloc.Expression, context, explicitAllocation: true);
                break;
            case StackAllocExpression stackAlloc:
                WalkExpression(stackAlloc.LengthExpression, context);
                break;
            case NewExpression newExpression:
                foreach (var argument in newExpression.ConstructorArguments)
                    WalkExpression(argument.Value, context);
                if (newExpression.Initializer != null)
                    WalkExpression(newExpression.Initializer, context);
                if (IsHeapAllocation(newExpression))
                    RecordAllocation(newExpression, context, explicitAllocation || context.InAllocZone);
                break;
            case ObjectInitializerExpression initializer:
                foreach (var property in initializer.Properties)
                {
                    if (property.IndexExpression != null)
                        WalkExpression(property.IndexExpression, context);
                    WalkExpression(property.Value, context);
                }
                break;
            case ArrayLiteralExpression array:
                foreach (var element in array.Elements)
                    WalkExpression(element, context);
                RecordAllocation(array, context, explicitAllocation || context.InAllocZone);
                break;
            case InterpolatedStringExpression interpolated:
                foreach (var hole in interpolated.Parts.OfType<InterpolatedStringHole>())
                    WalkExpression(hole.Expression, context);
                RecordAllocation(interpolated, context, explicitAllocation || context.InAllocZone);
                break;
            case LambdaExpression lambda:
                context.Summary.Delegate = true;
                context.Summary.Closure = true;
                AddFindingForPolicy("NSYS030", "delegate", "delegate or closure construction is not allowed here", lambda, context, "Move delegate construction behind a [boundary] or use a direct call.");
                if (lambda.ExpressionBody != null)
                    WalkExpression(lambda.ExpressionBody, context);
                if (lambda.BlockBody != null)
                    WalkStatement(lambda.BlockBody, context);
                break;
            case CallExpression call:
                WalkCall(call, context);
                break;
            case MemberAccessExpression member:
                WalkExpression(member.Object, context);
                break;
            case IndexAccessExpression index:
                WalkExpression(index.Object, context);
                WalkExpression(index.Index, context);
                if (context.Summary.IsHot && !context.IsAllowed("trap") && !IsIndexGuarded(index, context))
                {
                    context.Summary.ImplicitTrap = true;
                    AddHotFinding("NSYS120", "implicitTrap", "index access in [hot] requires a proven bounds guard or allow(trap)", index, context);
                }
                break;
            case BinaryExpression binary:
                WalkExpression(binary.Left, context);
                WalkExpression(binary.Right, context);
                if (context.Summary.IsHot
                    && (binary.Operator is BinaryOperator.Divide or BinaryOperator.Modulo)
                    && !context.IsAllowed("trap")
                    && !IsNonZeroGuarded(binary.Right, context)
                    && !IsDefinitelyNonZero(binary.Right))
                {
                    context.Summary.ImplicitTrap = true;
                    AddHotFinding("NSYS120", "implicitTrap", "division in [hot] requires a proven non-zero divisor or allow(trap)", binary, context);
                }
                break;
            case UnaryExpression unary:
                WalkExpression(unary.Operand, context);
                break;
            case MustExpression must:
                WalkExpression(must.Expression, context);
                break;
            case AssignmentExpression assignment:
                WalkExpression(assignment.Target, context);
                WalkExpression(assignment.Value, context);
                break;
            case TernaryExpression ternary:
                WalkExpression(ternary.Condition, context);
                WalkExpression(ternary.ThenExpression, context);
                WalkExpression(ternary.ElseExpression, context);
                break;
            case CastExpression cast:
                WalkExpression(cast.Expression, context);
                break;
            case IsExpression isExpression:
                WalkExpression(isExpression.Expression, context);
                break;
            case AwaitExpression awaitExpression:
                context.Summary.Resource = true;
                AddHotFinding("NSYS090", "resource", "[hot] async work is deferred in Systems N# v1", awaitExpression, context);
                WalkExpression(awaitExpression.Expression, context);
                break;
            case ThrowExpression throwExpression:
                context.Summary.Throws = true;
                AddHotFinding("NSYS120", "throw", "[hot] cannot throw exceptions", throwExpression, context);
                WalkExpression(throwExpression.Expression, context);
                break;
            case CheckedExpression checkedExpression:
                WalkExpression(checkedExpression.Expression, context);
                if (context.Summary.IsHot && !context.IsAllowed("trap"))
                {
                    context.Summary.ImplicitTrap = true;
                    AddHotFinding("NSYS120", "implicitTrap", "checked arithmetic in [hot] requires an overflow proof or allow(trap)", checkedExpression, context);
                }
                break;
            case UncheckedExpression uncheckedExpression:
                WalkExpression(uncheckedExpression.Expression, context);
                break;
            case RangeExpression range:
                if (range.Start != null) WalkExpression(range.Start, context);
                if (range.End != null) WalkExpression(range.End, context);
                break;
            case TupleExpression tuple:
                foreach (var element in tuple.Elements)
                    WalkExpression(element.Value, context);
                break;
            case MatchExpression match:
                WalkExpression(match.Value, context);
                foreach (var matchCase in match.Cases)
                {
                    if (matchCase.Guard != null)
                        WalkExpression(matchCase.Guard, context);
                    WalkExpression(matchCase.Expression, context);
                }
                break;
            case WithExpression with:
                WalkExpression(with.Target, context);
                RecordAllocation(with, context, explicitAllocation || context.InAllocZone);
                foreach (var property in with.Properties)
                {
                    if (property.IndexExpression != null)
                        WalkExpression(property.IndexExpression, context);
                    WalkExpression(property.Value, context);
                }
                break;
            case SpreadExpression spread:
                WalkExpression(spread.Expression, context);
                break;
            case ParenthesizedExpression parenthesized:
                WalkExpression(parenthesized.Inner, context);
                break;
            case TypeOfExpression:
                context.Summary.Reflection = true;
                AddFindingForPolicy("NSYS060", "aot", "typeof requires metadata and may block trimming/AOT facts", expression, context, "Move reflection to a [boundary] or use a source-generated shape.");
                break;
            case NameofExpression:
            case SizeOfExpression:
            case IntLiteralExpression:
            case FloatLiteralExpression:
            case CharLiteralExpression:
            case StringLiteralExpression:
            case BoolLiteralExpression:
            case NullLiteralExpression:
            case IdentifierExpression:
            case ThisExpression:
            case BaseExpression:
            case DefaultExpression:
                break;
        }
    }

    private void WalkCall(CallExpression call, WalkContext context)
    {
        foreach (var argument in call.Arguments)
            WalkExpression(argument.Value, context);

        var target = GetCallTarget(call.Callee);
        if (target != null)
            context.Summary.Calls.Add(target);

        WalkExpression(call.Callee, context);

        if (target == null)
        {
            AddUnknownExternalCall("<dynamic call>", call.Line, call.Column, context);
            return;
        }

        if (IsConcurrencyPrimitive(target))
        {
            context.Summary.ConcurrencyPrimitive = true;
            return;
        }

        if (IsPoolCall(target))
        {
            context.Summary.Pool = true;
            if (context.Summary.IsHot && target.EndsWith(".Rent", StringComparison.Ordinal) && !context.IsAllowed("pool"))
            {
                AddHotFinding("NSYS130", "pool", "[hot] pool rent requires a hot-ready pool precondition or allow(pool)", call, context);
            }
            return;
        }

        if (IsKnownHotSummary(target))
            return;

        if (IsReflectionOrDynamicCall(target, out var dynamicCode))
        {
            context.Summary.Reflection = true;
            context.Summary.DynamicCode |= dynamicCode;
            AddFindingForPolicy("NSYS060", "aot", $"call to '{target}' blocks target-qualified AOT/trimming facts", call, context, "Move reflection/dynamic code behind a [boundary] or replace it with source generation.");
            return;
        }

        if (_declaredFunctions.ContainsKey(target) || _declaredFunctions.ContainsKey(SimpleName(target)))
            return;

        AddUnknownExternalCall(target, call.Line, call.Column, context);
    }

    private void RecordAllocation(Expression expression, WalkContext context, bool explicitAllocation)
    {
        context.Summary.Allocates = true;

        if (context.Summary.IsHot || context.Summary.AllocNone)
        {
            if (!context.IsAllowed("alloc"))
            {
                AddFinding(
                    "NSYS010",
                    "allocation",
                    context.Summary.IsHot
                        ? "allocation not allowed in [hot] function"
                        : "allocation not allowed in [alloc(none)] function",
                    expression.Line,
                    expression.Column,
                    1,
                    context,
                    ErrorSeverity.Error,
                    "Move allocation behind a [boundary], return caller-provided storage, or use a narrow allow(alloc) only for a cold path.");
            }
            return;
        }

        if (context.Summary.IsBoundary)
        {
            AddFinding(
                "NSYS001",
                "allocation",
                "boundary allocation reported for systems handoff review",
                expression.Line,
                expression.Column,
                1,
                context,
                ErrorSeverity.Warning,
                "Keep allocation inside the [boundary] and hand systems code explicit values, spans, or Result<T,E>.");
            return;
        }

        if (IsSystemsProfile && !context.Summary.IsBoundary && !explicitAllocation)
        {
            AddFinding(
                "NSYS001",
                "allocation",
                "heap allocation in systems strict must be marked with alloc",
                expression.Line,
                expression.Column,
                1,
                context,
                ErrorSeverity.Error,
                "Write alloc new/alloc [...]/alloc $\"...\" or move this work into a [boundary].");
        }
    }

    private bool IsHeapAllocation(NewExpression expression)
    {
        if (expression.Type == null)
            return true;

        if (expression.Type is ArrayTypeReference)
            return true;

        var name = TypeReferenceName(expression.Type);
        return !IsValueTypeName(name);
    }

    private bool IsValueTypeName(string name)
    {
        name = SimpleName(name);
        return name is "bool" or "byte" or "sbyte" or "short" or "ushort" or "int" or "uint"
            or "long" or "ulong" or "float" or "double" or "decimal" or "char" or "nint" or "nuint"
            or "DateTime" or "Guid" or "TimeSpan"
            || _structTypes.Contains(name)
            || _enumTypes.Contains(name);
    }

    private void AddUnknownExternalCall(string target, int line, int column, WalkContext context)
    {
        context.Summary.UnknownExternalCall = true;
        if (context.Summary.IsHot)
        {
            AddFinding(
                "NSYS050",
                "unknownExternalCall",
                $"unknown external call '{target}' is not callable from [hot]",
                line,
                column,
                Math.Max(1, SimpleName(target).Length),
                context,
                ErrorSeverity.Error,
                "Add a compiler/HotSummary entry, make the callee [hot], or move this call behind a [boundary].");
            return;
        }

        if (context.Summary.IsBoundary)
        {
            AddFinding(
                "NSYS050",
                "unknownExternalCall",
                $"boundary external call '{target}' reported for systems handoff review",
                line,
                column,
                Math.Max(1, SimpleName(target).Length),
                context,
                ErrorSeverity.Warning,
                "Keep unknown external work inside the [boundary] and expose a systems-safe result.");
            return;
        }

        if (!IsSystemsProfile)
            return;

        var policy = _config.Language.Systems.UnknownExternalCalls;
        if (policy == "allow")
            return;

        AddFinding(
            "NSYS050",
            "unknownExternalCall",
            $"unknown external call '{target}' has no systems summary",
            line,
            column,
            Math.Max(1, SimpleName(target).Length),
            context,
            policy == "error" ? ErrorSeverity.Error : ErrorSeverity.Warning,
            "Add a sidecar HotSummary or put the call in a [boundary].");
    }

    private void AddHotFinding(string code, string effect, string message, AstNode node, WalkContext context)
    {
        if (!context.Summary.IsHot)
            return;

        AddFinding(code, effect, message, node.Line, node.Column, 1, context, ErrorSeverity.Error, null);
    }

    private void AddFindingForPolicy(
        string code,
        string effect,
        string message,
        AstNode node,
        WalkContext context,
        string? suggestion)
    {
        if (context.Summary.IsBoundary)
        {
            AddFinding(code, effect, message, node.Line, node.Column, 1, context, ErrorSeverity.Warning, suggestion);
            return;
        }

        if (context.Summary.IsHot || IsSystemsProfile)
        {
            AddFinding(code, effect, message, node.Line, node.Column, 1, context, ErrorSeverity.Error, suggestion);
        }
    }

    private void AddFinding(
        string code,
        string effect,
        string message,
        AstNode node,
        MutableFunctionSummary summary,
        ErrorSeverity preferredSeverity,
        string? suggestion)
        => AddFinding(code, effect, message, node.Line, node.Column, 1, summary, preferredSeverity, suggestion);

    private void AddFinding(
        string code,
        string effect,
        string message,
        int line,
        int column,
        int length,
        WalkContext context,
        ErrorSeverity preferredSeverity,
        string? suggestion)
        => AddFinding(code, effect, message, line, column, length, context.Summary, preferredSeverity, suggestion);

    private void AddFinding(
        string code,
        string effect,
        string message,
        int line,
        int column,
        int length,
        MutableFunctionSummary summary,
        ErrorSeverity preferredSeverity,
        string? suggestion)
    {
        if (summary.IsBoundary && !summary.IsHot && preferredSeverity == ErrorSeverity.Error)
            preferredSeverity = ErrorSeverity.Warning;
        if (IsAuditMode)
            preferredSeverity = ErrorSeverity.Warning;

        _findings.Add(new SystemsFinding(
            code,
            preferredSeverity == ErrorSeverity.Error ? "error" : "warning",
            effect,
            message,
            summary.File,
            line,
            column,
            Math.Max(1, length),
            summary.Name,
            summary.IsHot ? "[hot]" : IsSystemsProfile ? $"systems:{EffectiveMode}" : "local",
            "sourceInferred",
            suggestion,
            new[] { summary.Name }));
    }

    private static IReadOnlyList<Guard> DeriveGuardsFromExitingIf(IfStatement ifStatement)
    {
        if (!StatementExits(ifStatement.ThenStatement))
            return Array.Empty<Guard>();

        var guards = new List<Guard>();
        CollectNegativeGuard(ifStatement.Condition, guards);
        return guards;
    }

    private static IReadOnlyList<Guard> DeriveLoopGuards(Expression? condition)
    {
        var guards = new List<Guard>();
        if (condition != null)
            CollectPositiveGuard(condition, guards);
        return guards;
    }

    private static bool StatementExits(Statement statement) => statement switch
    {
        ReturnStatement or ThrowStatement or BreakStatement or ContinueStatement => true,
        BlockStatement block => block.Statements.Any(StatementExits),
        _ => false
    };

    private static void CollectNegativeGuard(Expression expression, List<Guard> guards)
    {
        if (expression is BinaryExpression binary)
        {
            if (TryGetLengthComparison(binary, out var receiver, out var literal, out var op))
            {
                if (op is BinaryOperator.Less && literal > 0)
                    guards.Add(Guard.MinLength(receiver, literal));
                if (op is BinaryOperator.Equal && literal == 0)
                    guards.Add(Guard.MinLength(receiver, 1));
            }
            if (binary.Operator == BinaryOperator.Equal && binary.Left is IdentifierExpression id && IsZero(binary.Right))
                guards.Add(Guard.NonZero(id.Name));
        }
    }

    private static void CollectPositiveGuard(Expression expression, List<Guard> guards)
    {
        if (expression is BinaryExpression binary)
        {
            if (TryGetIndexLessThanLength(binary, out var receiver, out var index))
                guards.Add(Guard.IndexWithin(receiver, index));
            if (binary.Operator == BinaryOperator.NotEqual && binary.Left is IdentifierExpression id && IsZero(binary.Right))
                guards.Add(Guard.NonZero(id.Name));
        }
    }

    private static bool IsIndexGuarded(IndexAccessExpression index, WalkContext context)
    {
        var receiver = ExpressionKey(index.Object);
        var indexName = index.Index is IdentifierExpression identifier ? identifier.Name : null;
        var literalIndex = index.Index is IntLiteralExpression literal && int.TryParse(literal.Value, out var value) ? value : (int?)null;

        return context.Guards.Any(guard =>
            guard.Kind == GuardKind.IndexWithin && guard.Target == receiver && guard.Secondary == indexName
            || guard.Kind == GuardKind.MinLength && guard.Target == receiver && literalIndex != null && guard.Value > literalIndex.Value);
    }

    private static bool IsNonZeroGuarded(Expression expression, WalkContext context)
        => expression is IdentifierExpression identifier
           && context.Guards.Any(guard => guard.Kind == GuardKind.NonZero && guard.Target == identifier.Name);

    private static bool IsDefinitelyNonZero(Expression expression)
        => expression is IntLiteralExpression literal && int.TryParse(literal.Value, out var value) && value != 0;

    private static bool TryGetLengthComparison(BinaryExpression binary, out string receiver, out int literal, out BinaryOperator op)
    {
        receiver = string.Empty;
        literal = 0;
        op = binary.Operator;
        if (binary.Left is MemberAccessExpression { MemberName: "Length" } member
            && binary.Right is IntLiteralExpression value
            && int.TryParse(value.Value, out literal))
        {
            receiver = ExpressionKey(member.Object);
            return true;
        }

        return false;
    }

    private static bool TryGetIndexLessThanLength(BinaryExpression binary, out string receiver, out string index)
    {
        receiver = string.Empty;
        index = string.Empty;
        if (binary.Operator != BinaryOperator.Less)
            return false;
        if (binary.Left is not IdentifierExpression identifier)
            return false;
        if (binary.Right is not MemberAccessExpression { MemberName: "Length" } member)
            return false;

        receiver = ExpressionKey(member.Object);
        index = identifier.Name;
        return true;
    }

    private static bool IsZero(Expression expression)
        => expression is IntLiteralExpression { Value: "0" };

    private static string? GetCallTarget(Expression callee) => callee switch
    {
        IdentifierExpression identifier => identifier.Name,
        MemberAccessExpression member => $"{GetCallTarget(member.Object) ?? ExpressionKey(member.Object)}.{member.MemberName}",
        ParenthesizedExpression parenthesized => GetCallTarget(parenthesized.Inner),
        _ => null
    };

    private static string ExpressionKey(Expression expression) => expression switch
    {
        IdentifierExpression identifier => identifier.Name,
        MemberAccessExpression member => $"{ExpressionKey(member.Object)}.{member.MemberName}",
        ThisExpression => "this",
        _ => $"@{expression.Line}:{expression.Column}"
    };

    private static string SimpleName(string value)
    {
        var index = value.LastIndexOf('.');
        return index >= 0 ? value[(index + 1)..] : value;
    }

    private static string TypeReferenceName(TypeReference type) => type switch
    {
        SimpleTypeReference simple => simple.Name,
        GenericTypeReference generic => generic.Name,
        ArrayTypeReference array => TypeReferenceName(array.ElementType) + "[]",
        NullableTypeReference nullable => TypeReferenceName(nullable.InnerType) + "?",
        _ => type.ToString() ?? string.Empty
    };

    private static bool IsKnownHotSummary(string target)
    {
        var simple = SimpleName(target);
        return target.StartsWith("BinaryPrimitives.", StringComparison.Ordinal)
            || target.StartsWith("MemoryMarshal.", StringComparison.Ordinal)
            || target.StartsWith("BitOperations.", StringComparison.Ordinal)
            || target.StartsWith("Math.", StringComparison.Ordinal)
            || target.StartsWith("MathF.", StringComparison.Ordinal)
            || simple is "Slice" or "AsSpan" or "CopyTo" or "Clear" or "Fill";
    }

    private static bool IsConcurrencyPrimitive(string target)
        => target.StartsWith("Interlocked.", StringComparison.Ordinal)
           || target.StartsWith("Volatile.", StringComparison.Ordinal);

    private static bool IsPoolCall(string target)
        => target.Contains("ArrayPool", StringComparison.Ordinal)
           || target.Contains("MemoryPool", StringComparison.Ordinal)
           || target.EndsWith(".Rent", StringComparison.Ordinal)
           || target.EndsWith(".Return", StringComparison.Ordinal);

    private static bool IsReflectionOrDynamicCall(string target, out bool dynamicCode)
    {
        dynamicCode = target.Contains("Activator.CreateInstance", StringComparison.Ordinal)
            || target.EndsWith(".CreateDelegate", StringComparison.Ordinal)
            || target.EndsWith(".DynamicInvoke", StringComparison.Ordinal)
            || target.EndsWith(".MakeGenericType", StringComparison.Ordinal)
            || target.EndsWith(".MakeGenericMethod", StringComparison.Ordinal);

        return dynamicCode
            || target.EndsWith(".GetType", StringComparison.Ordinal)
            || target.Contains(".GetMethod", StringComparison.Ordinal)
            || target.Contains(".GetMethods", StringComparison.Ordinal)
            || target.Contains(".GetProperty", StringComparison.Ordinal)
            || target.Contains(".GetCustomAttribute", StringComparison.Ordinal);
    }

    private static string? AttributeString(AttributeNode attribute, string name)
    {
        var arg = attribute.Arguments.FirstOrDefault(argument =>
            string.Equals(argument.Name, name, StringComparison.OrdinalIgnoreCase));
        return arg?.Value is StringLiteralExpression literal ? Unquote(literal.Value) : null;
    }

    private static string Unquote(string value)
        => value.Length >= 2 && value[0] == '"' && value[^1] == '"' ? value[1..^1] : value;

    private sealed class AttributeSet
    {
        private readonly List<AttributeNode> _attributes;

        public AttributeSet(List<AttributeNode> attributes)
        {
            _attributes = attributes;
        }

        public bool Has(string name) => Get(name) != null;

        public AttributeNode? Get(string name)
            => _attributes.FirstOrDefault(attribute => AttributeNameEquals(attribute.Name, name));

        public bool AttributeHasArgument(string attributeName, string argumentName)
        {
            var attribute = Get(attributeName);
            return attribute?.Arguments.Any(argument =>
                argument.Value is IdentifierExpression identifier
                && string.Equals(identifier.Name, argumentName, StringComparison.OrdinalIgnoreCase)) == true;
        }

        public HashSet<string> AllowEffects()
        {
            var result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var attribute in _attributes.Where(attribute => AttributeNameEquals(attribute.Name, "allow")))
            {
                foreach (var argument in attribute.Arguments)
                {
                    if (argument.Name is "reason" or "owner")
                        continue;
                    if (argument.Value is IdentifierExpression identifier)
                        result.Add(identifier.Name);
                }
            }

            return result;
        }

        private static bool AttributeNameEquals(string actual, string expected)
        {
            var name = actual.EndsWith("Attribute", StringComparison.Ordinal)
                ? actual[..^"Attribute".Length]
                : actual;
            return string.Equals(name, expected, StringComparison.OrdinalIgnoreCase);
        }
    }

    private sealed class MutableFunctionSummary
    {
        public MutableFunctionSummary(string name, string file, int line, int column)
        {
            Name = name;
            File = file;
            Line = line;
            Column = column;
        }

        public string Name { get; }
        public string File { get; }
        public int Line { get; }
        public int Column { get; }
        public bool IsHot { get; init; }
        public bool IsBoundary { get; init; }
        public bool AllocNone { get; init; }
        public HashSet<string> FunctionAllows { get; init; } = new(StringComparer.OrdinalIgnoreCase);
        public bool Allocates { get; set; }
        public bool Boxes { get; set; }
        public bool Delegate { get; set; }
        public bool Closure { get; set; }
        public bool Dispatch { get; set; }
        public bool Reflection { get; set; }
        public bool DynamicCode { get; set; }
        public bool Throws { get; set; }
        public bool ImplicitTrap { get; set; }
        public bool UnknownExternalCall { get; set; }
        public bool Resource { get; set; }
        public bool Pool { get; set; }
        public bool ConcurrencyPrimitive { get; set; }
        public bool RequiresWarmup { get; set; }
        public bool HasUnsafe { get; set; }
        public List<string> Calls { get; } = new();
    }

    private sealed class WalkContext
    {
        private readonly Stack<HashSet<string>> _allowStack = new();
        private readonly Stack<IReadOnlyList<Guard>> _guardStack = new();
        private int _allocZoneDepth;

        public WalkContext(MutableFunctionSummary summary)
        {
            Summary = summary;
        }

        public MutableFunctionSummary Summary { get; }
        public bool InAllocZone => _allocZoneDepth > 0;
        public List<Guard> Guards { get; } = new();

        public void PushAllocZone() => _allocZoneDepth++;
        public void PopAllocZone() => _allocZoneDepth = Math.Max(0, _allocZoneDepth - 1);

        public void PushAllows(IEnumerable<string> effects)
            => _allowStack.Push(new HashSet<string>(effects, StringComparer.OrdinalIgnoreCase));

        public void PopAllows()
        {
            if (_allowStack.Count > 0)
                _allowStack.Pop();
        }

        public bool IsAllowed(string effect)
            => Summary.FunctionAllows.Contains(effect)
               || _allowStack.Any(set => set.Contains(effect));

        public void AddGuards(IReadOnlyList<Guard> guards) => Guards.AddRange(guards);

        public void PushGuards(IReadOnlyList<Guard> guards)
        {
            _guardStack.Push(guards);
            Guards.AddRange(guards);
        }

        public void PopGuards()
        {
            if (_guardStack.Count == 0)
                return;

            var guards = _guardStack.Pop();
            foreach (var guard in guards)
                Guards.Remove(guard);
        }
    }

    private enum GuardKind
    {
        MinLength,
        IndexWithin,
        NonZero
    }

    private sealed record Guard(GuardKind Kind, string Target, int Value = 0, string? Secondary = null)
    {
        public static Guard MinLength(string target, int value) => new(GuardKind.MinLength, target, value);
        public static Guard IndexWithin(string target, string index) => new(GuardKind.IndexWithin, target, 0, index);
        public static Guard NonZero(string target) => new(GuardKind.NonZero, target);
    }
}
