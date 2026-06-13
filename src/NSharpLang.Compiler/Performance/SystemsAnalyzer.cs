using System;
using System.Collections.Generic;
using System.IO;
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
    SystemsAotReport Aot,
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
        new SystemsAotReport(
            config?.Language.Systems.AotTarget ?? "nativeaot",
            "pass",
            NativeImageEmitted: false,
            TrimSafe: true),
        new SystemsReportSummary(0, 0, 0, 0, 0, 0, 0));
}

public sealed record SystemsAotReport(
    string Target,
    string Analysis,
    bool NativeImageEmitted,
    bool TrimSafe);

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
/// Calls to user-declared functions are resolved through the Analyzer's semantic models
/// (the declaration bound at each call-site position), never by name matching; a hot-path
/// call that does not resolve semantically and matches no BCL/HotSummary fact is reported
/// as an unknown external call instead of being assumed clean.
/// </summary>
public sealed class SystemsAnalyzer
{
    private readonly string _projectRoot;
    private readonly ProjectConfig _config;
    private readonly List<SystemsFinding> _findings = new();
    private readonly List<SystemsFunctionSummary> _functions = new();
    private readonly List<SystemsTrustedSite> _trustedSites = new();
    private readonly Dictionary<FunctionDeclaration, FunctionEntry> _functionEntries = new(ReferenceEqualityComparer.Instance);
    private readonly Dictionary<DeclarationSite, List<FunctionEntry>> _functionEntriesBySite = new();
    private readonly Dictionary<string, HashSet<string>> _visibleDeclarationFilesByFile = new(StringComparer.OrdinalIgnoreCase);
    private readonly List<FunctionEntry> _orderedFunctionEntries = new();
    private readonly Dictionary<FunctionDeclaration, MutableFunctionSummary> _summaryCache = new(ReferenceEqualityComparer.Instance);
    private readonly HashSet<FunctionDeclaration> _visitingFunctions = new(ReferenceEqualityComparer.Instance);
    private readonly HashSet<FunctionDeclaration> _emittedFunctions = new(ReferenceEqualityComparer.Instance);
    private readonly HashSet<string> _structTypes = new(StringComparer.Ordinal);
    private readonly HashSet<string> _refStructTypes = new(StringComparer.Ordinal);
    private readonly HashSet<string> _enumTypes = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> _memberTypeNames = new(StringComparer.Ordinal);
    private IReadOnlyDictionary<string, SemanticModel> _semanticModels = EmptySemanticModels;
    private HotSummaryCatalog _hotSummaries;

    private static readonly IReadOnlyDictionary<string, SemanticModel> EmptySemanticModels =
        new Dictionary<string, SemanticModel>();

    public SystemsAnalyzer(string projectRoot, ProjectConfig? config)
    {
        _projectRoot = projectRoot;
        _config = config ?? ProjectFileParser.CreateDefault();
        _hotSummaries = HotSummaryCatalog.Load(projectRoot, _config);
    }

    public SystemsReport Analyze(
        IReadOnlyDictionary<string, CompilationUnit> compilationUnits,
        PerformanceFactStore? performanceFacts = null,
        IReadOnlyDictionary<string, SemanticModel>? semanticModels = null)
    {
        _findings.Clear();
        _functions.Clear();
        _trustedSites.Clear();
        _functionEntries.Clear();
        _functionEntriesBySite.Clear();
        _visibleDeclarationFilesByFile.Clear();
        _orderedFunctionEntries.Clear();
        _summaryCache.Clear();
        _visitingFunctions.Clear();
        _emittedFunctions.Clear();
        _structTypes.Clear();
        _refStructTypes.Clear();
        _enumTypes.Clear();
        _memberTypeNames.Clear();
        _semanticModels = semanticModels ?? EmptySemanticModels;
        _hotSummaries = HotSummaryCatalog.Load(_projectRoot, _config);
        BuildVisibleDeclarationFiles(compilationUnits);

        foreach (var (file, unit) in compilationUnits.OrderBy(kvp => kvp.Key, StringComparer.OrdinalIgnoreCase))
        {
            RegisterDeclarations(file, unit.Declarations, containingType: null);
        }

        foreach (var entry in _orderedFunctionEntries)
            AnalyzeFunction(entry, performanceFacts);

        var errors = _findings.Count(f => f.Severity == "error");
        var warnings = _findings.Count(f => f.Severity == "warning");
        var aotAnalysis = _findings.Any(f => f.Code == "NSYS060" && f.Severity == "error") ? "fail" : "pass";
        return new SystemsReport(
            1,
            _config.Language.Profile,
            EffectiveMode,
            _config.Language.Systems.AotTarget,
            _config.Language.Systems.Warmup,
            _functions,
            _findings.OrderBy(f => f.File, StringComparer.OrdinalIgnoreCase).ThenBy(f => f.Line).ThenBy(f => f.Column).ToArray(),
            _trustedSites.OrderBy(t => t.File, StringComparer.OrdinalIgnoreCase).ThenBy(t => t.Line).ThenBy(t => t.Column).ToArray(),
            new SystemsAotReport(
                _config.Language.Systems.AotTarget,
                aotAnalysis,
                NativeImageEmitted: false,
                TrimSafe: aotAnalysis == "pass"),
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
                    RegisterFunction(file, containingType, function);
                    break;
                case FieldDeclaration field:
                    RegisterMemberType(containingType, field.Name, field.Type);
                    break;
                case PropertyDeclaration property:
                    RegisterMemberType(containingType, property.Name, property.Type);
                    break;
                case ClassDeclaration cls:
                    RegisterDeclarations(file, cls.Members, cls.Name);
                    break;
                case StructDeclaration st:
                    _structTypes.Add(st.Name);
                    if (st.IsRefStruct)
                        _refStructTypes.Add(st.Name);
                    CheckRefLikeFields(file, st.Name, st.IsRefStruct, st.Members);
                    RegisterDeclarations(file, st.Members, st.Name);
                    break;
                case RecordDeclaration rec:
                    if (rec.IsStruct)
                        _structTypes.Add(rec.Name);
                    CheckRefLikeFields(file, rec.Name, isRefStruct: false, rec.Members);
                    RegisterDeclarations(file, rec.Members, rec.Name);
                    break;
                case SoaRecordDeclaration soa:
                    foreach (var column in soa.Columns)
                    {
                        RegisterMemberType(soa.Name, column.Name, column.Type);
                    }
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

    private void RegisterMemberType(string? containingType, string memberName, TypeReference? type)
    {
        if (containingType == null || type == null)
            return;

        _memberTypeNames[$"{containingType}.{memberName}"] = TypeReferenceName(type);
    }

    private void RegisterFunction(string file, string? containingType, FunctionDeclaration function)
    {
        var qualified = containingType == null ? function.Name : $"{containingType}.{function.Name}";
        var entry = new FunctionEntry(file, containingType, qualified, function);
        _functionEntries[function] = entry;

        // Secondary identity for declarations the Analyzer re-parsed (file imports produce a
        // fresh AST per importer): a declaration is also identified by its source site. The
        // site must match EXACTLY ONE registered entry to resolve — ambiguity is conservative.
        var site = DeclarationSite.For(function);
        if (!_functionEntriesBySite.TryGetValue(site, out var siteEntries))
        {
            siteEntries = new List<FunctionEntry>();
            _functionEntriesBySite[site] = siteEntries;
        }
        siteEntries.Add(entry);

        _orderedFunctionEntries.Add(entry);
    }

    private MutableFunctionSummary AnalyzeFunction(FunctionEntry entry, PerformanceFactStore? performanceFacts)
    {
        if (_summaryCache.TryGetValue(entry.Function, out var cached))
            return cached;

        var file = entry.File;
        var function = entry.Function;
        var name = entry.QualifiedName;
        var attributes = new AttributeSet(function.Attributes);
        var summary = new MutableFunctionSummary(name, file, function.Line, function.Column)
        {
            IsHot = attributes.Has("hot"),
            IsBoundary = attributes.Has("boundary"),
            AllocNone = attributes.Has("alloc") && attributes.AttributeHasArgument("alloc", "none"),
            IsTrusted = attributes.Has("trusted"),
            MemorySafe = attributes.Has("memory") && attributes.AttributeHasArgument("memory", "safe"),
            FunctionAllows = attributes.AllowEffects(),
        };

        var context = new WalkContext(entry, summary);
        _summaryCache[function] = summary;
        if (!_visitingFunctions.Add(function))
            return summary;

        ValidateFunctionLevelAllows(attributes, function, summary);

        if (function.Body != null)
            WalkStatement(function.Body, context);
        if (function.ExpressionBody != null)
            WalkExpression(function.ExpressionBody, context);

        if (summary.IsHot && function.Modifiers.HasFlag(Modifiers.Async))
        {
            summary.Allocates = true;
            summary.Resource = true;
            AddFinding("NSYS010", "allocation", "[hot] async functions allocate or require async machinery in Systems N# v1", function.Line, function.Column, Math.Max(1, function.Name.Length), summary, ErrorSeverity.Error, "Move async work to a [boundary] and call hot code with explicit buffers.");
        }

        if (summary.IsHot && function.Modifiers.HasFlag(Modifiers.Generator))
        {
            summary.Allocates = true;
            summary.Resource = true;
            AddFinding("NSYS010", "allocation", "[hot] iterator functions allocate state machines in Systems N# v1", function.Line, function.Column, Math.Max(1, function.Name.Length), summary, ErrorSeverity.Error, "Use a caller-provided buffer or direct loop instead of yield.");
        }

        MergeDeclaredCalleeSummaries(summary, performanceFacts);
        CheckPoolBalance(summary);
        CheckResourceBalance(summary);
        CheckFunctionSurface(function, summary);
        _visitingFunctions.Remove(function);

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
        if (_emittedFunctions.Add(function))
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
            if (!summary.MemorySafe)
            {
                AddFinding(
                    "NSYS100",
                    "memorySafety",
                    "[trusted] wrappers must declare [memory(safe)] for Systems N# v1",
                    function.Line,
                    function.Column,
                    Math.Max(1, function.Name.Length),
                    summary,
                    ErrorSeverity.Error,
                    "Add [memory(safe)] after documenting the unsafe proof.");
            }
        }

        return summary;
    }

    private void CheckRefLikeFields(string file, string typeName, bool isRefStruct, IEnumerable<Declaration> members)
    {
        if (isRefStruct)
            return;

        foreach (var field in members.OfType<FieldDeclaration>())
        {
            if (field.Type != null && IsRefLikeType(field.Type))
            {
                AddTypeFinding(
                    "NSYS080",
                    "lifetime",
                    $"ref-like field '{field.Name}' is only allowed inside a ref struct",
                    file,
                    field.Line,
                    field.Column,
                    Math.Max(1, field.Name.Length),
                    typeName,
                    "Declare the containing type as `ref struct`, or store a heap-safe owner such as Memory<T>/ReadOnlyMemory<T>.");
            }
        }
    }

    private void ValidateFunctionLevelAllows(AttributeSet attributes, FunctionDeclaration function, MutableFunctionSummary summary)
    {
        foreach (var allow in attributes.GetAll("allow"))
        {
            var reason = AttributeString(allow, "reason");
            var owner = AttributeString(allow, "owner");
            if (string.IsNullOrWhiteSpace(reason))
            {
                AddFinding(
                    // effectPolicy gets its own code (NSYS180); NSYS150 is reserved for effectDrift.
                    // Sharing one code made the per-error docs URL ambiguous and machine consumers
                    // unable to distinguish the two effects (M5).
                    "NSYS180",
                    "effectPolicy",
                    "function-level [allow] requires a reason",
                    function.Line,
                    function.Column,
                    Math.Max(1, function.Name.Length),
                    summary,
                    ErrorSeverity.Error,
                    "Prefer a narrow block-level allow(...), or add reason: \"...\" to the function-level policy.");
            }

            var isPublicApi = function.Modifiers.HasFlag(Modifiers.Public) || VisibilityConventions.IsExportedIdentifier(function.Name);
            if (isPublicApi && string.IsNullOrWhiteSpace(owner))
            {
                AddFinding(
                    "NSYS180",
                    "effectPolicy",
                    "public function-level [allow] requires an owner",
                    function.Line,
                    function.Column,
                    Math.Max(1, function.Name.Length),
                    summary,
                    ErrorSeverity.Error,
                    "Add owner: \"team-or-person\" so public systems waivers are auditable.");
            }
        }
    }

    private void CheckFunctionSurface(FunctionDeclaration function, MutableFunctionSummary summary)
    {
        if (!summary.IsHot && !summary.IsBoundary)
            return;

        foreach (var parameter in function.Parameters)
        {
            if (IsSystemsHostileSurface(parameter.Type, hotStrict: summary.IsHot, out var reason, function.Constraints))
            {
                AddFinding(
                    "NSYS070",
                    "boundaryLeak",
                    $"{(summary.IsHot ? "[hot]" : "[boundary]")} parameter '{parameter.Name}' exposes a systems-hostile type: {reason}",
                    parameter.Line,
                    parameter.Column,
                    Math.Max(1, parameter.Name.Length),
                    summary,
                    summary.IsHot ? ErrorSeverity.Error : ErrorSeverity.Warning,
                    "Use primitives, spans, readonly/ref structs, Result<T,E>, or an explicit boundary adapter type.");
            }
        }

        if (function.ReturnType != null
            && IsSystemsHostileSurface(function.ReturnType, hotStrict: summary.IsHot, out var returnReason, function.Constraints))
        {
            AddFinding(
                "NSYS070",
                "boundaryLeak",
                $"{(summary.IsHot ? "[hot]" : "[boundary]")} return type exposes a systems-hostile shape: {returnReason}",
                function.Line,
                function.Column,
                Math.Max(1, function.Name.Length),
                summary,
                summary.IsHot ? ErrorSeverity.Error : ErrorSeverity.Warning,
                "Return Result<T,E>, Span/ReadOnlySpan with a known lifetime, a primitive, enum, or systems-safe struct.");
        }

        if (function.ReturnType != null
            && IsResultType(function.ReturnType)
            && EstimateResultSize(function.ReturnType) is > 128 and var resultSize)
        {
            AddFinding(
                // resultAbi gets its own code (NSYS170); NSYS160 is reserved for resultMustUse (M5).
                "NSYS170",
                "resultAbi",
                $"Result<T,E> copy shape is estimated at {resultSize} bytes, above the v1 hot-path guidance of 128 bytes",
                function.Line,
                function.Column,
                Math.Max(1, function.Name.Length),
                summary,
                ErrorSeverity.Warning,
                "Return a smaller error/value payload or pass large data through caller-owned storage.");
        }

        if (summary.IsHot
            && function.ReturnType != null
            && ContainsRefLikeType(function.ReturnType)
            && string.IsNullOrWhiteSpace(function.ReturnLifetime))
        {
            AddFinding("NSYS080", "lifetime", "[hot] function returns a ref-like value with an unknown lifetime", function.Line, function.Column, Math.Max(1, function.Name.Length), summary, ErrorSeverity.Error, "Use `returns 'a`, `returns heap(owner)`, or return an owned value instead of a ref-like view.");
        }
    }

    private void CheckIgnoredResult(Expression expression, WalkContext context)
    {
        if (expression is not CallExpression call)
            return;

        if (!TryResolveDeclaredCallee(call, context, out var entry))
            return;

        if (entry.Function.ReturnType == null || !IsResultType(entry.Function.ReturnType))
            return;

        AddFinding(
            "NSYS160",
            "resultMustUse",
            $"Result returned by '{entry.QualifiedName}' is ignored",
            call.Line,
            call.Column,
            Math.Max(1, entry.Function.Name.Length),
            context,
            context.Summary.IsHot || IsSystemsProfile ? ErrorSeverity.Error : ErrorSeverity.Warning,
            "Bind the Result, return it, or explicitly inspect IsOk/IsErr so the error path is handled.");
    }

    private void CheckPoolBalance(MutableFunctionSummary summary)
    {
        if (!summary.IsHot && !IsSystemsProfile)
            return;

        foreach (var rent in summary.PoolRents.Values.Where(rent => !rent.Returned))
        {
            AddFinding(
                "NSYS130",
                "pool",
                $"pooled buffer '{rent.VariableName}' rented here is not returned on an obvious lexical path",
                rent.Line,
                rent.Column,
                Math.Max(1, rent.VariableName.Length),
                summary,
                summary.IsHot ? ErrorSeverity.Error : ErrorSeverity.Warning,
                "Return the buffer in a finally block, use a recognized owner/disposable pattern, or keep pooling inside a [boundary].");
        }
    }

    private void CheckResourceBalance(MutableFunctionSummary summary)
    {
        if (!summary.IsHot && !IsSystemsProfile)
            return;

        foreach (var resource in summary.ResourceLocals.Values.Where(resource => !resource.Disposed))
        {
            AddFinding(
                "NSYS090",
                "resource",
                $"disposable resource '{resource.VariableName}' created as {resource.Kind} is not disposed on an obvious lexical path",
                resource.Line,
                resource.Column,
                Math.Max(1, resource.VariableName.Length),
                summary,
                ErrorSeverity.Error,
                "Use `using`, call Dispose/DisposeAsync in a finally block, or return/transfer through an explicit owner once ownership is modeled.");
        }
    }

    private void AddTypeFinding(
        string code,
        string effect,
        string message,
        string file,
        int line,
        int column,
        int length,
        string typeName,
        string? suggestion)
    {
        var severity = IsAuditMode ? "warning" : "error";
        _findings.Add(new SystemsFinding(
            code,
            severity,
            effect,
            message,
            file,
            line,
            column,
            Math.Max(1, length),
            typeName,
            IsSystemsProfile ? $"systems:{EffectiveMode}" : "local",
            "sourceInferred",
            suggestion,
            new[] { typeName }));
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
            case UnsafeBlockStatement unsafeBlock:
                context.Summary.HasUnsafe = true;
                if (!context.Summary.IsTrusted || !context.Summary.MemorySafe)
                {
                    AddFindingForPolicy("NSYS100", "memorySafety", "unsafe block requires a [trusted] memory-safe wrapper in systems code", unsafeBlock, context, "Wrap unsafe code in a small [trusted(reason, owner, review)] function with [memory(safe)].");
                }
                context.PushUnsafeBlock();
                WalkStatement(unsafeBlock.Body, context);
                context.PopUnsafeBlock();
                break;
            case ExpressionStatement expression:
                CheckIgnoredResult(expression.Expression, context);
                WalkExpression(expression.Expression, context);
                break;
            case VariableDeclarationStatement variable:
                if (variable.Initializer != null)
                {
                    WalkExpression(variable.Initializer, context);
                    if (IsPoolRentExpression(variable.Initializer))
                    {
                        context.Summary.Pool = true;
                        context.Summary.PoolRents[variable.Name] = new PoolRent(variable.Name, variable.Line, variable.Column);
                    }
                    if (IsResourceCreationExpression(variable.Initializer, out var resourceKind))
                    {
                        context.Summary.Resource = true;
                        context.Summary.ResourceLocals[variable.Name] = new ResourceLocal(variable.Name, resourceKind, variable.Line, variable.Column);
                    }
                    if (variable.Initializer is StackAllocExpression)
                    {
                        context.Summary.StackallocLocals.Add(variable.Name);
                    }
                }
                break;
            case TupleDeconstructionStatement tuple:
                WalkExpression(tuple.Initializer, context);
                break;
            case IfStatement ifStatement:
                WalkExpression(ifStatement.Condition, context);
                context.PushGuards(DerivePositiveGuards(ifStatement.Condition));
                WalkStatement(ifStatement.ThenStatement, context);
                context.PopGuards();
                var guards = DeriveGuardsFromExitingIf(ifStatement);
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
                {
                    if (returnStatement.Value is IdentifierExpression returned
                        && context.Summary.StackallocLocals.Contains(returned.Name))
                    {
                        context.Summary.ImplicitTrap = true;
                        AddFinding("NSYS080", "lifetime", "stackalloc span cannot escape through a return value", returnStatement.Line, returnStatement.Column, "return".Length, context, ErrorSeverity.Error, "Copy into caller-provided storage or return a heap/parameter-backed span with an explicit lifetime.");
                    }
                    WalkExpression(returnStatement.Value, context);
                }
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
                if (context.Summary.IsHot)
                    AddHotFinding("NSYS120", "throw", "[hot] cannot throw exceptions", throwStatement, context);
                else
                    AddFindingForPolicy("NSYS120", "throw", "systems code must translate exception control flow into explicit Result/error values", throwStatement, context, "Catch exceptions at a [boundary] and return Result<T,E> or another explicit error value.");
                WalkExpression(throwStatement.Expression, context);
                break;
            case TryStatement tryStatement:
                context.Summary.Throws = true;
                if (context.Summary.IsHot)
                    AddHotFinding("NSYS120", "throw", "[hot] cannot use exception control flow", tryStatement, context);
                else
                    AddFindingForPolicy("NSYS120", "throw", "exception control flow is reported on systems paths", tryStatement, context, "Keep try/catch inside a [boundary] and translate failures into explicit Result/error values.");
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
                {
                    MarkResourceDisposedIfRecognized(usingStatement.Expression, context);
                    WalkExpression(usingStatement.Expression, context);
                }
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

    private void MergeDeclaredCalleeSummaries(
        MutableFunctionSummary caller,
        PerformanceFactStore? performanceFacts)
    {
        foreach (var callSite in caller.CallSites)
        {
            var callee = AnalyzeFunction(callSite.Callee, performanceFacts);
            caller.MergeEffectsFrom(callee);

            if (caller.IsHot || caller.AllocNone)
            {
                ReportCalleePolicyViolations(caller, callee, callSite);
            }
        }
    }

    /// <summary>
    /// Resolves a call to the user-declared function it semantically binds to. The Analyzer
    /// records the resolved declaration (including the overload selected for the call) at the
    /// callee's source position; that declaration maps back to its registered entry by AST
    /// reference, or — for declarations the Analyzer re-parsed via file imports — by its unique
    /// declaration site. Returns false when the call does not bind to exactly one project
    /// declaration; callers must treat that as unknown, never as clean.
    /// </summary>
    private bool TryResolveDeclaredCallee(CallExpression call, WalkContext context, out FunctionEntry entry)
    {
        entry = null!;
        if (!_semanticModels.TryGetValue(context.Summary.File, out var semanticModel))
            return false;

        if (!semanticModel.ExpressionTypes.TryGetValue((call.Callee.Line, call.Callee.Column), out var calleeType))
            return false;

        var declaration = calleeType switch
        {
            FunctionTypeInfo { Declaration: { } resolved } => resolved,
            NSharpMethodGroupInfo { Declarations: [{ } single] } => single,
            _ => null
        };

        if (declaration == null)
        {
            return call.Callee is MemberAccessExpression member
                && TryResolveConstrainedInterfaceCallee(member, context, semanticModel, out entry);
        }

        return TryGetEntryForDeclaration(declaration, context, out entry);
    }

    private bool TryGetEntryForDeclaration(FunctionDeclaration declaration, WalkContext context, out FunctionEntry entry)
    {
        if (_functionEntries.TryGetValue(declaration, out entry!))
            return true;

        if (_functionEntriesBySite.TryGetValue(DeclarationSite.For(declaration), out var siteEntries)
            && siteEntries.Count == 1)
        {
            entry = siteEntries[0];
            return true;
        }

        if (siteEntries != null
            && _visibleDeclarationFilesByFile.TryGetValue(context.Summary.File, out var visibleFiles))
        {
            var visibleEntries = siteEntries
                .Where(candidate => visibleFiles.Contains(candidate.File))
                .ToList();
            if (visibleEntries.Count == 1)
            {
                entry = visibleEntries[0];
                return true;
            }
        }

        entry = null!;
        return false;
    }

    private void BuildVisibleDeclarationFiles(IReadOnlyDictionary<string, CompilationUnit> compilationUnits)
    {
        var sourceFileByFullPath = compilationUnits.Keys.ToDictionary(
            Path.GetFullPath,
            path => path,
            StringComparer.OrdinalIgnoreCase);

        foreach (var (sourceFile, unit) in compilationUnits)
        {
            var visibleFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            {
                sourceFile
            };

            var resolver = new FileResolver(_projectRoot, sourceFile);
            foreach (var fileImport in unit.FileImports.OfType<FileImport>())
            {
                var resolvedPath = Path.GetFullPath(resolver.ResolveFilePath(fileImport.Path));
                if (sourceFileByFullPath.TryGetValue(resolvedPath, out var targetFile))
                    visibleFiles.Add(targetFile);
            }

            _visibleDeclarationFilesByFile[sourceFile] = visibleFiles;
        }
    }

    /// <summary>
    /// Resolves a member call on a generic type parameter of the current function through its
    /// constraint clause: `where T : Sortable&lt;T&gt;` makes `value.LessThan(...)` bind to the
    /// constraint interface's member declaration. Constrained calls are the blessed hot-path
    /// dispatch shape (they emit `constrained.` IL), so they resolve to the interface member's
    /// summary rather than being reported as unknown external calls.
    /// </summary>
    private bool TryResolveConstrainedInterfaceCallee(
        MemberAccessExpression member,
        WalkContext context,
        SemanticModel semanticModel,
        out FunctionEntry entry)
    {
        entry = null!;
        if (!semanticModel.ExpressionTypes.TryGetValue((member.Object.Line, member.Object.Column), out var receiverType))
            return false;

        // Type parameters surface as bare SimpleTypeInfo; anything else has a real declaration
        // and is resolved through the primary FunctionTypeInfo path above.
        if (receiverType is not SimpleTypeInfo simple)
            return false;

        var function = context.Entry.Function;
        if (function.TypeParameters == null
            || function.TypeParameters.All(parameter => parameter.Name != simple.Name))
        {
            return false;
        }

        foreach (var constraint in function.Constraints ?? Enumerable.Empty<GenericConstraint>())
        {
            if (!string.Equals(constraint.TypeParameter, simple.Name, StringComparison.Ordinal))
                continue;

            foreach (var constraintReference in constraint.Constraints)
            {
                if (!TryLookupTypeReference(semanticModel, constraintReference, out var constraintType))
                    continue;

                // Generic interface constraints (`Sortable<T>`) resolve to a GenericTypeInfo
                // instantiation; the declaring interface lives in the model's type table.
                if (constraintType is GenericTypeInfo generic
                    && semanticModel.Types.TryGetValue(generic.Name, out var openType))
                {
                    constraintType = openType;
                }

                if (constraintType is not InterfaceTypeInfo iface)
                    continue;

                var declared = iface.Declaration.Members
                    .OfType<FunctionDeclaration>()
                    .FirstOrDefault(candidate => candidate.Name == member.MemberName);
                if (declared != null && TryGetEntryForDeclaration(declared, context, out entry))
                    return true;
            }
        }

        entry = null!;
        return false;
    }

    private static bool TryLookupTypeReference(SemanticModel semanticModel, TypeReference reference, out TypeInfo type)
    {
        type = null!;
        var (line, column) = reference switch
        {
            { Span.IsValid: true } => (reference.Span.StartLine, reference.Span.StartColumn),
            SimpleTypeReference simple => (simple.Line, simple.Column),
            GenericTypeReference generic => (generic.Line, generic.Column),
            _ => (0, 0)
        };

        return line > 0 && semanticModel.TypeReferenceTypes.TryGetValue((line, column), out type!);
    }

    private void ReportCalleePolicyViolations(MutableFunctionSummary caller, MutableFunctionSummary callee, CallSite site)
    {
        var callPath = new[] { caller.Name, callee.Name };
        if (callee.Allocates && !caller.FunctionAllows.Contains("alloc"))
        {
            AddFinding("NSYS010", "allocation", $"callee '{callee.Name}' allocates on a hot/alloc(none) path", site.Line, site.Column, site.Length, caller, ErrorSeverity.Error, "Move the allocation behind a [boundary], pass caller-owned storage, or return Result<T,E> without formatting diagnostics.", callPath);
        }
        if (callee.Boxes)
            AddFinding("NSYS020", "boxing", $"callee '{callee.Name}' boxes a value on a hot path", site.Line, site.Column, site.Length, caller, ErrorSeverity.Error, "Use concrete generic/value-type APIs or add a HotSummary that proves constrained dispatch.", callPath);
        if (callee.Delegate || callee.Closure)
            AddFinding("NSYS030", "delegate", $"callee '{callee.Name}' constructs a delegate or closure on a hot path", site.Line, site.Column, site.Length, caller, ErrorSeverity.Error, "Use direct calls or move delegate construction behind a [boundary].", callPath);
        if (callee.Dispatch)
            AddFinding("NSYS040", "dispatch", $"callee '{callee.Name}' uses runtime dispatch on a hot path", site.Line, site.Column, site.Length, caller, ErrorSeverity.Error, "Use a concrete receiver, constrained generic call, or summarized dispatch-free wrapper.", callPath);
        if (callee.UnknownExternalCall)
            AddFinding("NSYS050", "unknownExternalCall", $"callee '{callee.Name}' reaches an unknown external call", site.Line, site.Column, site.Length, caller, ErrorSeverity.Error, "Add a HotSummary, make the callee hot-checkable, or isolate the call behind a [boundary].", callPath);
        if (callee.Reflection || callee.DynamicCode)
            AddFinding("NSYS060", "aot", $"callee '{callee.Name}' blocks AOT/trimming facts", site.Line, site.Column, site.Length, caller, ErrorSeverity.Error, "Replace reflection/dynamic code with source generation or move it behind a [boundary].", callPath);
        if (callee.ImplicitTrap)
            AddFinding("NSYS120", "implicitTrap", $"callee '{callee.Name}' has unproven implicit trap obligations", site.Line, site.Column, site.Length, caller, ErrorSeverity.Error, "Prove bounds/null/divide/overflow locally or use a narrow allow(trap).", callPath);
        if (callee.Resource)
            AddFinding("NSYS090", "resource", $"callee '{callee.Name}' creates or owns a disposable resource", site.Line, site.Column, site.Length, caller, ErrorSeverity.Error, "Open resources at a [boundary] and pass explicit handles or spans to hot code.", callPath);
        if (callee.Pool && !caller.FunctionAllows.Contains("pool"))
            AddFinding("NSYS130", "pool", $"callee '{callee.Name}' rents from a pool without a hot-ready pool precondition", site.Line, site.Column, site.Length, caller, ErrorSeverity.Error, "Return pooled buffers in the same lexical path or configure/warm the pool explicitly.", callPath);
        if (callee.RequiresWarmup)
            AddFinding("NSYS110", "hotReadiness", $"callee '{callee.Name}' requires warmup before the hot path is warm-ready", site.Line, site.Column, site.Length, caller, ErrorSeverity.Error, "Add the required warmup function to language.systems.warmup or remove first-use work.", callPath);
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
                if (!IsStackallocLengthWithinBudget(stackAlloc, out var stackallocReason))
                {
                    context.Summary.ImplicitTrap = true;
                    AddFinding("NSYS080", "lifetime", stackallocReason, stackAlloc.Line, stackAlloc.Column, "stackalloc".Length, context, ErrorSeverity.Error, "Use a constant within the systems stack budget, guard the maximum size, or allocate outside the hot path.");
                }
                break;
            case NewExpression newExpression:
                foreach (var argument in newExpression.ConstructorArguments)
                    WalkExpression(argument.Value, context);
                if (newExpression.ArrayLengthExpression != null)
                    WalkExpression(newExpression.ArrayLengthExpression, context);
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
                if (context.Summary.IsHot
                    && member.Object is IdentifierExpression receiver
                    && receiver.Name.Length > 0
                    && char.IsUpper(receiver.Name[0])
                    && !_enumTypes.Contains(receiver.Name)
                    && !IsKnownStaticHotReceiver(receiver.Name)
                    && !_hotSummaries.HasReceiverSummary(receiver.Name, _config.TargetFramework)
                    && _config.Language.Systems.Warmup.Count == 0)
                {
                    context.Summary.RequiresWarmup = true;
                    AddHotFinding("NSYS110", "hotReadiness", $"static member access '{receiver.Name}.{member.MemberName}' requires a warmup or HotSummary readiness fact", member, context);
                }
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
                if (TypeReferenceName(cast.TargetType) is "object" or "System.Object")
                {
                    context.Summary.Boxes = true;
                    AddFindingForPolicy("NSYS020", "boxing", "cast to object may box a value on systems paths", cast, context, "Keep values concrete or use a generic/constrained API.");
                }
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
                if (context.Summary.IsHot)
                    AddHotFinding("NSYS120", "throw", "[hot] cannot throw exceptions", throwExpression, context);
                else
                    AddFindingForPolicy("NSYS120", "throw", "systems code must translate exception control flow into explicit Result/error values", throwExpression, context, "Catch exceptions at a [boundary] and return Result<T,E> or another explicit error value.");
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

        if (TryResolveDeclaredCallee(call, context, out var calleeEntry))
        {
            context.Summary.Calls.Add(calleeEntry.QualifiedName);
            context.Summary.CallSites.Add(new CallSite(
                calleeEntry, call.Line, call.Column, Math.Max(1, calleeEntry.Function.Name.Length)));
            WalkExpression(call.Callee, context);
            return;
        }

        var target = GetCallTarget(call.Callee);
        if (target != null && target is not ("Ok" or "Err"))
            context.Summary.Calls.Add(target);

        WalkExpression(call.Callee, context);

        if (target == null)
        {
            AddUnknownExternalCall("<dynamic call>", call.Line, call.Column, context);
            return;
        }

        if (target is "Ok" or "Err")
            return;

        if (MarkResourceDisposedIfRecognized(call.Callee, context))
            return;

        if (IsKnownConcurrencyPrimitive(target))
        {
            context.Summary.ConcurrencyPrimitive = true;
            return;
        }

        if (IsUnsupportedConcurrencyPrimitive(target))
        {
            context.Summary.ConcurrencyPrimitive = true;
            AddFindingForPolicy(
                "NSYS140",
                "concurrency",
                $"concurrency primitive '{target}' has no v1 HotSummary semantics",
                call,
                context,
                "Use Volatile.Read/Write, Interlocked.Exchange/CompareExchange/Increment/Decrement/Add, or Thread.MemoryBarrier.");
            return;
        }

        if (IsRuntimeDispatchCall(target))
        {
            context.Summary.Dispatch = true;
            AddFindingForPolicy("NSYS040", "dispatch", $"call to '{target}' uses runtime dispatch or an unsummarized interface-shaped API", call, context, "Use a concrete receiver, constrained generic call, or HotSummary-covered wrapper.");
            return;
        }

        if (IsPoolCall(target))
        {
            context.Summary.Pool = true;
            MarkPoolReturnIfRecognized(call, context);
            if (context.Summary.IsHot && target.EndsWith(".Rent", StringComparison.Ordinal) && !context.IsAllowed("pool"))
            {
                AddHotFinding("NSYS130", "pool", "[hot] pool rent requires a hot-ready pool precondition or allow(pool)", call, context);
            }
            if (target.EndsWith(".Rent", StringComparison.Ordinal)
                && _config.Language.Systems.Warmup.Count == 0)
            {
                context.Summary.RequiresWarmup = true;
            }
            return;
        }

        if (IsDictionaryTryGetValueCall(call, target))
            return;

        if (IsBufferMemoryCopyCall(target))
        {
            ApplyBufferMemoryCopyFacts(call, context);
            return;
        }

        if (_hotSummaries.TryResolve(target, _config.TargetFramework, out var summaryEntry))
        {
            ApplyHotSummary(target, summaryEntry, call, context);
            return;
        }

        if (IsJsonSerializerCall(target))
        {
            ApplyJsonSerializerFacts(target, call, context);
            return;
        }

        if (IsReflectionOrDynamicCall(target, out var dynamicCode))
        {
            context.Summary.Reflection = true;
            context.Summary.DynamicCode |= dynamicCode;
            AddFindingForPolicy("NSYS060", "aot", $"call to '{target}' blocks target-qualified AOT/trimming facts", call, context, "Move reflection/dynamic code behind a [boundary] or replace it with source generation.");
            return;
        }

        AddUnknownExternalCall(target, call.Line, call.Column, context);
    }

    private void ApplyJsonSerializerFacts(string target, CallExpression call, WalkContext context)
    {
        RecordAllocation(call, context, explicitAllocation: false);

        if (UsesSourceGeneratedJsonMetadata(call))
            return;

        context.Summary.Reflection = true;
        AddFindingForPolicy(
            "NSYS060",
            "aot",
            $"JsonSerializer call '{target}' must use source-generated metadata for target-qualified AOT/trimming facts",
            call,
            context,
            "Pass a generated JsonSerializerContext/JsonTypeInfo value, or keep reflection serialization out of systems-profile code.");
    }

    private static bool IsBufferMemoryCopyCall(string target)
        => target is "Buffer.MemoryCopy" or "System.Buffer.MemoryCopy";

    private void ApplyBufferMemoryCopyFacts(CallExpression call, WalkContext context)
    {
        if (!context.InUnsafeBlock)
        {
            AddFindingForPolicy(
                "NSYS100",
                "memorySafety",
                "Buffer.MemoryCopy must be isolated inside an unsafe block",
                call,
                context,
                "Wrap Buffer.MemoryCopy in a small [trusted] [memory(safe)] function and document the bounds proof.");
            return;
        }

        if (!context.Summary.IsTrusted || !context.Summary.MemorySafe)
        {
            return;
        }
    }

    private void ApplyHotSummary(string target, HotSummaryEntry entry, CallExpression call, WalkContext context)
    {
        if (entry.IsSidecar && context.Summary.IsHot && !_config.Language.Systems.AllowHotSidecars)
        {
            context.Summary.UnknownExternalCall = true;
            AddFinding(
                "NSYS050",
                "unknownExternalCall",
                $"sidecar HotSummary for '{target}' is not allowed to satisfy [hot] by project policy",
                call.Line,
                call.Column,
                Math.Max(1, SimpleName(target).Length),
                context,
                ErrorSeverity.Error,
                "Set language.systems.allowHotSidecars only after auditing the sidecar identity and body hash, or move the call behind a [boundary].");
            return;
        }

        if (entry.IsSidecar
            && string.IsNullOrWhiteSpace(entry.BodyIdentity)
            && string.IsNullOrWhiteSpace(entry.PackageVersion))
        {
            context.Summary.UnknownExternalCall = true;
            AddFinding(
                "NSYS150",
                "effectDrift",
                $"sidecar HotSummary for '{target}' is missing body identity or package version, so per-fact drift cannot be audited",
                call.Line,
                call.Column,
                Math.Max(1, SimpleName(target).Length),
                context,
                ErrorSeverity.Error,
                "Key sidecar facts by MVID/body hash, source hash, or package version plus metadata identity.");
            return;
        }

        var effects = entry.Effects;
        context.Summary.Allocates |= effects.Allocates;
        context.Summary.Boxes |= effects.Boxes;
        context.Summary.Delegate |= effects.ConstructsDelegate;
        context.Summary.Closure |= effects.CapturesClosure;
        context.Summary.Dispatch |= effects.UsesRuntimeDispatch;
        context.Summary.Reflection |= effects.UsesReflection;
        context.Summary.DynamicCode |= effects.UsesDynamicCode;
        context.Summary.Throws |= effects.Throws;
        context.Summary.ImplicitTrap |= effects.HasImplicitTrapObligation;
        context.Summary.UnknownExternalCall |= effects.UsesUnknownExternalCall;
        context.Summary.Resource |= effects.UsesResource;
        context.Summary.Pool |= effects.UsesPool;
        context.Summary.ConcurrencyPrimitive |= effects.UsesConcurrencyPrimitive;

        if (effects.RequiresWarmup && _config.Language.Systems.Warmup.Count == 0)
        {
            context.Summary.RequiresWarmup = true;
            AddHotFinding("NSYS110", "hotReadiness", $"HotSummary for '{target}' requires warmup before [hot] use", call, context);
        }

        if (!effects.TrimSafe || !entry.IsAotSafeFor(_config.Language.Systems.AotTarget))
        {
            context.Summary.Reflection = true;
            AddFindingForPolicy(
                "NSYS060",
                "aot",
                $"HotSummary for '{target}' is not AOT/trim safe for {_config.Language.Systems.AotTarget}",
                call,
                context,
                "Use a source-generated path, a target-qualified summary, or move the call behind a [boundary].");
        }

        if (context.Summary.IsHot || context.Summary.AllocNone)
        {
            if (effects.Allocates)
                AddHotFinding("NSYS010", "allocation", $"HotSummary for '{target}' allocates", call, context);
            if (effects.Boxes)
                AddHotFinding("NSYS020", "boxing", $"HotSummary for '{target}' boxes", call, context);
            if (effects.ConstructsDelegate || effects.CapturesClosure)
                AddHotFinding("NSYS030", "delegate", $"HotSummary for '{target}' constructs a delegate or closure", call, context);
            if (effects.UsesRuntimeDispatch)
                AddHotFinding("NSYS040", "dispatch", $"HotSummary for '{target}' uses runtime dispatch", call, context);
            if (effects.Throws || effects.HasImplicitTrapObligation)
                AddHotFinding("NSYS120", effects.Throws ? "throw" : "implicitTrap", $"HotSummary for '{target}' has a throwing/trap obligation", call, context);
            if (effects.UsesResource)
                AddHotFinding("NSYS090", "resource", $"HotSummary for '{target}' uses a disposable resource", call, context);
        }
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
        if (context.IsAllowed(effect))
            return;

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
        => AddFinding(code, effect, message, line, column, length, summary, preferredSeverity, suggestion, new[] { summary.Name });

    private void AddFinding(
        string code,
        string effect,
        string message,
        int line,
        int column,
        int length,
        MutableFunctionSummary summary,
        ErrorSeverity preferredSeverity,
        string? suggestion,
        IReadOnlyList<string> callPath)
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
            callPath));
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
        => DerivePositiveGuards(condition);

    private static IReadOnlyList<Guard> DerivePositiveGuards(Expression? condition)
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
        AllocBlockStatement allocBlock => StatementExits(allocBlock.Body),
        AllowStatement allow => StatementExits(allow.Body),
        UnsafeBlockStatement unsafeBlock => StatementExits(unsafeBlock.Body),
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
        => (expression is IntLiteralExpression literal && int.TryParse(literal.Value, out var value) && value != 0)
            // A non-zero literal divisor can never divide-by-zero, for integer OR floating/decimal
            // division. This removes the false positive on `x / 2.0`, `x % 4.0f`, etc. (M2): the
            // trap check previously only recognized non-zero INT literals, so a float-literal
            // divisor was reported as an unproven trap even though it is provably non-zero.
            || (expression is FloatLiteralExpression floatLiteral && IsNonZeroFloatLiteral(floatLiteral.Value));

    private static bool IsNonZeroFloatLiteral(string text)
    {
        var trimmed = text.TrimEnd('f', 'F', 'd', 'D', 'm', 'M');
        return double.TryParse(
                trimmed,
                System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture,
                out var value)
            && value != 0.0;
    }

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

    private bool IsDictionaryTryGetValueCall(CallExpression call, string target)
    {
        if (!target.EndsWith(".TryGetValue", StringComparison.Ordinal))
            return false;

        if (call.Callee is not MemberAccessExpression { Object: var receiver })
            return false;

        return _memberTypeNames.TryGetValue(ExpressionKey(receiver), out var receiverType)
               && SimpleName(receiverType) is "Dictionary";
    }

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
        ByRefTypeReference byRef => "&" + TypeReferenceName(byRef.InnerType),
        _ => type.ToString() ?? string.Empty
    };

    private bool IsRefLikeType(TypeReference type)
    {
        var name = SimpleName(TypeReferenceName(type));
        return name is "Span" or "ReadOnlySpan"
            || type is ByRefTypeReference
            || _refStructTypes.Contains(name);
    }

    private bool ContainsRefLikeType(TypeReference type)
    {
        if (IsRefLikeType(type))
            return true;

        return type switch
        {
            GenericTypeReference generic => generic.TypeArguments.Any(ContainsRefLikeType),
            ArrayTypeReference array => ContainsRefLikeType(array.ElementType),
            NullableTypeReference nullable => ContainsRefLikeType(nullable.InnerType),
            UnionTypeReference union => union.Arms.Any(ContainsRefLikeType),
            ByRefTypeReference byRef => ContainsRefLikeType(byRef.InnerType),
            _ => false
        };
    }

    private static bool IsResultType(TypeReference type)
    {
        if (type is not GenericTypeReference generic)
            return false;

        return SimpleName(generic.Name) is "Result" && generic.TypeArguments.Count == 2;
    }

    private int EstimateResultSize(TypeReference type)
    {
        if (type is not GenericTypeReference generic || generic.TypeArguments.Count != 2)
            return 0;

        // byte tag + padding plus both payload fields. This is deliberately a
        // conservative copy-shape estimate, not a replacement for runtime sizeof.
        return 16 + EstimateTypeSize(generic.TypeArguments[0]) + EstimateTypeSize(generic.TypeArguments[1]);
    }

    private int EstimateTypeSize(TypeReference type) => type switch
    {
        SimpleTypeReference simple => EstimateSimpleTypeSize(SimpleName(simple.Name)),
        GenericTypeReference generic when SimpleName(generic.Name) is "Span" or "ReadOnlySpan" or "Memory" or "ReadOnlyMemory" => 16,
        GenericTypeReference generic when SimpleName(generic.Name) is "Result" => EstimateResultSize(generic),
        GenericTypeReference => 32,
        ArrayTypeReference => 8,
        NullableTypeReference nullable => EstimateTypeSize(nullable.InnerType) + 1,
        ByRefTypeReference => 8,
        UnionTypeReference union => union.Arms.Count == 0 ? 0 : union.Arms.Max(EstimateTypeSize) + 8,
        _ => 32
    };

    private int EstimateSimpleTypeSize(string name)
    {
        if (_enumTypes.Contains(name))
            return 4;
        if (_structTypes.Contains(name))
            return 32;
        return name switch
        {
            "bool" or "byte" or "sbyte" => 1,
            "short" or "ushort" or "char" => 2,
            "int" or "uint" or "float" => 4,
            "long" or "ulong" or "double" or "nint" or "nuint" => 8,
            "decimal" or "Guid" => 16,
            "DateTime" or "TimeSpan" => 8,
            _ => 8
        };
    }

    private bool IsSystemsHostileSurface(
        TypeReference type,
        bool hotStrict,
        out string reason,
        IReadOnlyList<GenericConstraint>? constraints = null)
    {
        reason = string.Empty;

        switch (type)
        {
            case ByRefTypeReference byRef:
                return IsSystemsHostileSurface(byRef.InnerType, hotStrict, out reason, constraints);
            case ArrayTypeReference array:
                return IsSystemsHostileSurface(array.ElementType, hotStrict: false, out reason, constraints);
            case NullableTypeReference nullable:
                return IsSystemsHostileSurface(nullable.InnerType, hotStrict, out reason, constraints);
            case UnionTypeReference union:
                foreach (var arm in union.Arms)
                {
                    if (IsSystemsHostileSurface(arm, hotStrict, out reason, constraints))
                        return true;
                }
                return false;
            case GenericTypeReference generic:
            {
                var name = SimpleName(generic.Name);
                if (name is "Result")
                {
                    foreach (var argument in generic.TypeArguments)
                    {
                        if (IsSystemsHostileSurface(argument, hotStrict, out reason, constraints))
                            return true;
                    }
                    return false;
                }

                if (name is "Span" or "ReadOnlySpan" or "Memory" or "ReadOnlyMemory")
                    return false;

                if (name is "IEnumerable" or "IQueryable" or "IEnumerator" or "IAsyncEnumerable"
                    or "Task" or "ValueTask" or "Func" or "Action" or "List" or "Dictionary"
                    or "IList" or "ICollection" or "IReadOnlyList" or "IReadOnlyCollection")
                {
                    reason = name;
                    return true;
                }

                if (hotStrict)
                {
                    reason = $"generic type '{name}' has no HotSummary surface rule";
                    return true;
                }

                return false;
            }
            case SimpleTypeReference simple:
            {
                var name = SimpleName(simple.Name);
                if (IsValueConstrainedGenericParameter(name, constraints))
                    return false;
                if (IsValueTypeName(name) || name is "string" or "ReadOnlySpan" or "Span")
                    return false;
                if (name is "object" or "dynamic" or "Type" or "Stream" or "Delegate")
                {
                    reason = name;
                    return true;
                }
                if (hotStrict && !_structTypes.Contains(name) && !_enumTypes.Contains(name))
                {
                    reason = $"managed or unsummarized type '{name}'";
                    return true;
                }
                return false;
            }
            default:
                return false;
        }
    }

    private static bool IsValueConstrainedGenericParameter(string name, IReadOnlyList<GenericConstraint>? constraints)
        => constraints?.Any(constraint =>
            string.Equals(constraint.TypeParameter, name, StringComparison.Ordinal)
            && constraint.SpecialConstraints.HasFlag(SpecialConstraintKind.Struct)) == true;

    private static bool IsKnownStaticHotReceiver(string name)
        => name is "BinaryPrimitives" or "MemoryMarshal" or "BitOperations" or "Math" or "MathF"
            or "Volatile" or "Interlocked" or "Thread";

    private static bool IsKnownConcurrencyPrimitive(string target)
        => target is "Volatile.Read" or "Volatile.Write"
            or "System.Threading.Volatile.Read" or "System.Threading.Volatile.Write"
            or "Interlocked.Exchange" or "Interlocked.CompareExchange"
            or "Interlocked.Increment" or "Interlocked.Decrement" or "Interlocked.Add"
            or "System.Threading.Interlocked.Exchange" or "System.Threading.Interlocked.CompareExchange"
            or "System.Threading.Interlocked.Increment" or "System.Threading.Interlocked.Decrement"
            or "System.Threading.Interlocked.Add"
            or "Thread.MemoryBarrier" or "System.Threading.Thread.MemoryBarrier";

    private static bool IsUnsupportedConcurrencyPrimitive(string target)
        => target.StartsWith("Interlocked.", StringComparison.Ordinal)
           || target.StartsWith("System.Threading.Interlocked.", StringComparison.Ordinal)
           || target.StartsWith("Volatile.", StringComparison.Ordinal)
           || target.StartsWith("System.Threading.Volatile.", StringComparison.Ordinal)
           || target.StartsWith("Thread.", StringComparison.Ordinal)
           || target.StartsWith("System.Threading.Thread.", StringComparison.Ordinal);

    private static bool IsJsonSerializerCall(string target)
        => target is "JsonSerializer.Serialize" or "JsonSerializer.Deserialize"
           || target.EndsWith(".JsonSerializer.Serialize", StringComparison.Ordinal)
           || target.EndsWith(".JsonSerializer.Deserialize", StringComparison.Ordinal);

    private static bool UsesSourceGeneratedJsonMetadata(CallExpression call)
    {
        if (call.Arguments.Count < 2)
            return false;

        return call.Arguments
            .Skip(1)
            .Select(argument => ExpressionKey(argument.Value))
            .Any(key => key.Contains("JsonContext", StringComparison.Ordinal)
                        || key.Contains("JsonTypeInfo", StringComparison.Ordinal)
                        || key.Contains(".Default.", StringComparison.Ordinal));
    }

    private static bool IsRuntimeDispatchCall(string target)
        => target.Contains("System.Linq", StringComparison.Ordinal)
           || target.Contains("IEnumerable", StringComparison.Ordinal)
           || target.Contains("IQueryable", StringComparison.Ordinal)
           || target.EndsWith(".GetEnumerator", StringComparison.Ordinal)
           || target.EndsWith(".MoveNext", StringComparison.Ordinal)
           || target.EndsWith(".DynamicInvoke", StringComparison.Ordinal);

    private static bool IsPoolCall(string target)
        => target.Contains("ArrayPool", StringComparison.Ordinal)
           || target.Contains("MemoryPool", StringComparison.Ordinal)
           || target.EndsWith(".Rent", StringComparison.Ordinal)
           || target.EndsWith(".Return", StringComparison.Ordinal);

    private static bool IsPoolRentExpression(Expression expression)
        => expression is CallExpression call
           && GetCallTarget(call.Callee) is { } target
           && IsPoolCall(target)
           && target.EndsWith(".Rent", StringComparison.Ordinal);

    private static bool IsResourceCreationExpression(Expression expression, out string kind)
    {
        kind = string.Empty;
        switch (expression)
        {
            case AllocExpression alloc:
                return IsResourceCreationExpression(alloc.Expression, out kind);
            case NewExpression { Type: not null } newExpression:
                var typeName = SimpleName(TypeReferenceName(newExpression.Type));
                if (IsKnownDisposableType(typeName))
                {
                    kind = typeName;
                    return true;
                }
                return false;
            case CallExpression call when GetCallTarget(call.Callee) is { } target && IsKnownResourceFactory(target):
                kind = target;
                return true;
            default:
                return false;
        }
    }

    private static bool IsKnownDisposableType(string typeName)
        => typeName is "FileStream" or "StreamReader" or "StreamWriter"
            or "BinaryReader" or "BinaryWriter" or "TextReader" or "TextWriter"
            or "MemoryStream" or "Socket" or "TcpClient" or "UdpClient"
            or "HttpClient" or "SemaphoreSlim" or "CancellationTokenSource";

    private static bool IsKnownResourceFactory(string target)
        => target is "File.Open" or "File.OpenRead" or "File.OpenWrite" or "File.Create"
            or "System.IO.File.Open" or "System.IO.File.OpenRead" or "System.IO.File.OpenWrite" or "System.IO.File.Create";

    private static bool MarkResourceDisposedIfRecognized(Expression expression, WalkContext context)
    {
        string? variableName = expression switch
        {
            IdentifierExpression identifier => identifier.Name,
            CallExpression { Callee: MemberAccessExpression member }
                when member.MemberName is "Dispose" or "DisposeAsync"
                     && member.Object is IdentifierExpression receiver => receiver.Name,
            MemberAccessExpression { MemberName: "Dispose" or "DisposeAsync", Object: IdentifierExpression receiver } => receiver.Name,
            _ => null
        };

        if (variableName == null)
            return false;

        var recognized = false;
        if (context.Summary.PoolRents.TryGetValue(variableName, out var rent))
        {
            rent.Returned = true;
            recognized = true;
        }

        if (context.Summary.ResourceLocals.TryGetValue(variableName, out var resource))
        {
            resource.Disposed = true;
            recognized = true;
        }

        return recognized;
    }

    private static void MarkPoolReturnIfRecognized(CallExpression call, WalkContext context)
    {
        if (GetCallTarget(call.Callee) is not { } target || !target.EndsWith(".Return", StringComparison.Ordinal))
            return;

        foreach (var argument in call.Arguments)
        {
            if (argument.Value is IdentifierExpression identifier
                && context.Summary.PoolRents.TryGetValue(identifier.Name, out var rent))
            {
                rent.Returned = true;
            }
        }
    }

    private bool IsStackallocLengthWithinBudget(StackAllocExpression stackAlloc, out string reason)
    {
        reason = string.Empty;

        if (stackAlloc.LengthExpression is not IntLiteralExpression literal
            || !int.TryParse(literal.Value, out var elementCount))
        {
            reason = "stackalloc length must be statically bounded in Systems N# v1";
            return false;
        }

        if (elementCount < 0)
        {
            reason = "stackalloc length cannot be negative";
            return false;
        }

        var elementSize = TypeReferenceName(stackAlloc.ElementType) switch
        {
            "bool" or "byte" or "sbyte" => 1,
            "short" or "ushort" or "char" => 2,
            "int" or "uint" or "float" => 4,
            "long" or "ulong" or "double" => 8,
            "decimal" => 16,
            _ => 16
        };
        // Compute in long: int*int overflows for large counts (e.g. `stackalloc int[2_000_000_000]`)
        // and would wrap to a small/negative value that wrongly passes the budget check (M4).
        var total = (long)elementCount * elementSize;
        if (total <= _config.Language.Systems.StackBudgetBytes)
            return true;

        reason = $"stackalloc reserves {total} bytes, above the configured systems stack budget of {_config.Language.Systems.StackBudgetBytes} bytes";
        return false;
    }

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

        public IEnumerable<AttributeNode> GetAll(string name)
            => _attributes.Where(attribute => AttributeNameEquals(attribute.Name, name));

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
                    if (!string.IsNullOrWhiteSpace(argument.Name))
                    {
                        result.Add(argument.Name);
                        if (argument.Value is IdentifierExpression namedIdentifier)
                            result.Add($"{argument.Name}:{namedIdentifier.Name}");
                    }
                    else if (argument.Value is IdentifierExpression identifier)
                    {
                        result.Add(identifier.Name);
                    }
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
        public bool IsTrusted { get; init; }
        public bool MemorySafe { get; init; }
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
        public List<CallSite> CallSites { get; } = new();
        public HashSet<string> StackallocLocals { get; } = new(StringComparer.Ordinal);
        public Dictionary<string, PoolRent> PoolRents { get; } = new(StringComparer.Ordinal);
        public Dictionary<string, ResourceLocal> ResourceLocals { get; } = new(StringComparer.Ordinal);

        public void MergeEffectsFrom(MutableFunctionSummary other)
        {
            Allocates |= other.Allocates;
            Boxes |= other.Boxes;
            Delegate |= other.Delegate;
            Closure |= other.Closure;
            Dispatch |= other.Dispatch;
            Reflection |= other.Reflection;
            DynamicCode |= other.DynamicCode;
            Throws |= other.Throws;
            ImplicitTrap |= other.ImplicitTrap;
            UnknownExternalCall |= other.UnknownExternalCall;
            Resource |= other.Resource;
            Pool |= other.Pool;
            ConcurrencyPrimitive |= other.ConcurrencyPrimitive;
            RequiresWarmup |= other.RequiresWarmup;
        }
    }

    private sealed record FunctionEntry(string File, string? ContainingType, string QualifiedName, FunctionDeclaration Function);

    /// <summary>
    /// Source-site identity of a function declaration: name, position, and arity. File imports
    /// re-parse the imported unit, so a semantically resolved declaration can be a different AST
    /// object than the registered one — but it always shares the declaration site. The site is
    /// only trusted when it identifies exactly one registered entry.
    /// </summary>
    private readonly record struct DeclarationSite(string Name, int Line, int Column, int ParameterCount)
    {
        public static DeclarationSite For(FunctionDeclaration function)
            => new(function.Name, function.Line, function.Column, function.Parameters.Count);
    }

    private sealed record CallSite(FunctionEntry Callee, int Line, int Column, int Length);

    private sealed record PoolRent(string VariableName, int Line, int Column)
    {
        public bool Returned { get; set; }
    }

    private sealed record ResourceLocal(string VariableName, string Kind, int Line, int Column)
    {
        public bool Disposed { get; set; }
    }

    private sealed class WalkContext
    {
        private readonly Stack<HashSet<string>> _allowStack = new();
        // Marks (Guards.Count at push time) so Pop truncates back exactly, instead of removing by
        // value (which corrupts the set for structurally-identical nested guards — M3).
        private readonly Stack<int> _guardStack = new();
        private int _allocZoneDepth;
        private int _unsafeBlockDepth;

        public WalkContext(FunctionEntry entry, MutableFunctionSummary summary)
        {
            Entry = entry;
            Summary = summary;
        }

        public FunctionEntry Entry { get; }
        public MutableFunctionSummary Summary { get; }
        public bool InAllocZone => _allocZoneDepth > 0;
        public bool InUnsafeBlock => _unsafeBlockDepth > 0;
        public List<Guard> Guards { get; } = new();

        public void PushAllocZone() => _allocZoneDepth++;
        public void PopAllocZone() => _allocZoneDepth = Math.Max(0, _allocZoneDepth - 1);
        public void PushUnsafeBlock() => _unsafeBlockDepth++;
        public void PopUnsafeBlock() => _unsafeBlockDepth = Math.Max(0, _unsafeBlockDepth - 1);

        public void PushAllows(IEnumerable<string> effects)
            => _allowStack.Push(new HashSet<string>(effects, StringComparer.OrdinalIgnoreCase));

        public void PopAllows()
        {
            if (_allowStack.Count > 0)
                _allowStack.Pop();
        }

        public bool IsAllowed(string effect)
            => ContainsEffect(Summary.FunctionAllows, effect)
               || _allowStack.Any(set => ContainsEffect(set, effect));

        private static bool ContainsEffect(HashSet<string> effects, string effect)
            => effects.Contains(effect)
               || effects.Any(value => value.StartsWith(effect + ":", StringComparison.OrdinalIgnoreCase));

        public void AddGuards(IReadOnlyList<Guard> guards) => Guards.AddRange(guards);

        public void PushGuards(IReadOnlyList<Guard> guards)
        {
            // Record the guard-set length BEFORE adding, so the matching Pop can truncate back to
            // exactly this point.
            _guardStack.Push(Guards.Count);
            Guards.AddRange(guards);
        }

        public void PopGuards()
        {
            if (_guardStack.Count == 0)
                return;

            // Truncate back to the mark taken at push time. This removes the pushed scope-entry
            // guards AND any flow guards AddGuards() accumulated during the scope — all of which
            // expire when the scope exits. Removing by value (the previous approach) corrupted the
            // set when a nested scope pushed a structurally-identical guard: List.Remove deleted
            // the first value-equal element (the OUTER instance), not the inner one (M3).
            var mark = _guardStack.Pop();
            if (mark < Guards.Count)
                Guards.RemoveRange(mark, Guards.Count - mark);
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
