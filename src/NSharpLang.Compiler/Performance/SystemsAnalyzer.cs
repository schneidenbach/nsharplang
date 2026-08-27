using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NSharpLang.Compiler.Ast;

namespace NSharpLang.Compiler.Performance;

/// <summary>
/// Systems N# policy/effect analyzer. This is deliberately conservative and source based:
/// it gives the check/build/query surfaces deterministic facts without changing emitted IL.
/// Calls to user-declared functions are resolved through the Analyzer's semantic models
/// (the function source site bound at each call-site position), never by name matching; a hot-path
/// call that does not resolve semantically and matches no BCL/HotSummary fact is reported
/// as an unknown external call instead of being assumed clean.
/// </summary>
public sealed class SystemsAnalyzer
{
    private readonly string _projectRoot;
    private readonly ProjectConfig _config;
    private readonly SystemsFindingSink _findingSink = new();
    private readonly List<SystemsFunctionSummary> _functions = new();
    private readonly List<SystemsTrustedSite> _trustedSites = new();
    private readonly Dictionary<DeclarationSite, List<FunctionEntry>> _functionEntriesBySite = new();
    private readonly Dictionary<string, HashSet<string>> _visibleDeclarationFilesByFile = new(StringComparer.OrdinalIgnoreCase);
    private readonly List<FunctionEntry> _orderedFunctionEntries = new();
    private readonly Dictionary<FunctionDeclaration, MutableFunctionSummary> _summaryCache = new(ReferenceEqualityComparer.Instance);
    private readonly HashSet<FunctionDeclaration> _visitingFunctions = new(ReferenceEqualityComparer.Instance);
    private readonly HashSet<FunctionDeclaration> _emittedFunctions = new(ReferenceEqualityComparer.Instance);
    private readonly SystemsTypePolicy _typePolicy = new();
    private readonly SystemsStackallocPolicy _stackalloc = new();
    private readonly SystemsCallPolicy _callPolicy = new();
    private readonly SystemsSurfacePolicy _surfacePolicy;
    private readonly SystemsBalancePolicy _balancePolicy;
    private readonly SystemsCalleePolicy _calleePolicy;
    private readonly SystemsAttributePolicy _attributePolicy;
    private readonly SystemsHotSummaryPolicy _hotSummaryPolicy;
    private readonly SystemsConstructPolicy _constructPolicy;
    private readonly SystemsTrapPolicy _trapPolicy;
    private IReadOnlyDictionary<string, SemanticModel> _semanticModels = EmptySemanticModels;
    private HotSummaryCatalog _hotSummaries;

    private static readonly IReadOnlyDictionary<string, SemanticModel> EmptySemanticModels =
        new Dictionary<string, SemanticModel>();

    public SystemsAnalyzer(string projectRoot, ProjectConfig? config)
    {
        _projectRoot = projectRoot;
        _config = config ?? ProjectFileParser.CreateDefault();
        _findingSink.BeginAnalysis(_config);
        _surfacePolicy = new SystemsSurfacePolicy(_typePolicy, _findingSink);
        _balancePolicy = new SystemsBalancePolicy(_findingSink);
        _calleePolicy = new SystemsCalleePolicy(_typePolicy, _findingSink);
        _calleePolicy.BeginAnalysis(_config);
        _attributePolicy = new SystemsAttributePolicy(_findingSink);
        _hotSummaryPolicy = new SystemsHotSummaryPolicy(_findingSink);
        _hotSummaryPolicy.BeginAnalysis(_config);
        _constructPolicy = new SystemsConstructPolicy(_findingSink);
        _trapPolicy = new SystemsTrapPolicy(_findingSink);
        _hotSummaries = HotSummaryCatalog.Load(projectRoot, _config);
    }

    public SystemsReport Analyze(
        IReadOnlyDictionary<string, CompilationUnit> compilationUnits,
        PerformanceFactStore? performanceFacts = null,
        IReadOnlyDictionary<string, SemanticModel>? semanticModels = null)
    {
        _findingSink.BeginAnalysis(_config);
        _functions.Clear();
        _trustedSites.Clear();
        _functionEntriesBySite.Clear();
        _visibleDeclarationFilesByFile.Clear();
        _orderedFunctionEntries.Clear();
        _summaryCache.Clear();
        _visitingFunctions.Clear();
        _emittedFunctions.Clear();
        _typePolicy.BeginAnalysis();
        _stackalloc.BeginAnalysis(_config);
        _callPolicy.BeginAnalysis();
        _calleePolicy.BeginAnalysis(_config);
        _hotSummaryPolicy.BeginAnalysis(_config);
        _semanticModels = semanticModels ?? EmptySemanticModels;
        _hotSummaries = HotSummaryCatalog.Load(_projectRoot, _config);
        BuildVisibleDeclarationFiles(compilationUnits);

        foreach (var file in SystemsReportOrder.OrderedFiles(compilationUnits.Keys.ToArray()))
        {
            RegisterDeclarations(file, compilationUnits[file].Declarations, containingType: null);
        }

        foreach (var entry in _orderedFunctionEntries)
            AnalyzeFunction(entry, performanceFacts);

        var aotAnalysis = _findingSink.AotAnalysis();
        return new SystemsReport(
            1,
            _config.Language.Profile,
            EffectiveMode,
            _config.Language.Systems.AotTarget,
            _config.Language.Systems.Warmup,
            _functions,
            _findingSink.Ordered(),
            SystemsReportOrder.OrderedTrustedSites(_trustedSites),
            new SystemsAotReport(
                _config.Language.Systems.AotTarget,
                aotAnalysis,
                NativeImageEmitted: false,
                TrimSafe: aotAnalysis == "pass"),
            new SystemsReportSummary(
                _functions.Count,
                _functions.Count(f => f.IsHot),
                _functions.Count(f => f.IsBoundary),
                _findingSink.Count,
                _findingSink.ErrorCount,
                _findingSink.WarningCount,
                _trustedSites.Count));
    }

    private bool IsSystemsProfile => _findingSink.IsSystemsProfile;
    private string EffectiveMode => _findingSink.EffectiveMode;

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
                    _callPolicy.RegisterMemberType(containingType, field.Name, field.Type);
                    break;
                case PropertyDeclaration property:
                    _callPolicy.RegisterMemberType(containingType, property.Name, property.Type);
                    break;
                case ClassDeclaration cls:
                    RegisterDeclarations(file, cls.Members, cls.Name);
                    break;
                case StructDeclaration st:
                    _typePolicy.RegisterStructType(st.Name);
                    if (st.IsRefStruct)
                        _typePolicy.RegisterRefStructType(st.Name);
                    _surfacePolicy.CheckRefLikeFields(file, st.Name, st.IsRefStruct, st.Members);
                    RegisterDeclarations(file, st.Members, st.Name);
                    break;
                case RecordDeclaration rec:
                    if (rec.IsStruct)
                        _typePolicy.RegisterStructType(rec.Name);
                    _surfacePolicy.CheckRefLikeFields(file, rec.Name, isRefStruct: false, rec.Members);
                    RegisterDeclarations(file, rec.Members, rec.Name);
                    break;
                case SoaRecordDeclaration soa:
                    foreach (var column in soa.Columns)
                    {
                        _callPolicy.RegisterMemberType(soa.Name, column.Name, column.Type);
                    }
                    break;
                case InterfaceDeclaration iface:
                    RegisterDeclarations(file, iface.Members, iface.Name);
                    break;
                case EnumDeclaration enm:
                    _typePolicy.RegisterEnumType(enm.Name);
                    break;
                case TypeAliasDeclaration alias:
                    _stackalloc.RegisterTypeAlias(alias.Name, alias.Type);
                    break;
            }
        }
    }

    private void RegisterFunction(string file, string? containingType, FunctionDeclaration function)
    {
        var qualified = containingType == null ? function.Name : $"{containingType}.{function.Name}";
        var entry = new FunctionEntry(file, containingType, qualified, function);

        // Source-site identity also handles declarations the Analyzer re-parsed (file imports
        // produce a fresh AST per importer). The
        // site must match EXACTLY ONE registered entry to resolve — ambiguity is conservative.
        var site = DeclarationSite.For(function, containingType);
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
        var attributes = new SystemsAttributeSet(function.Attributes);
        var summary = new MutableFunctionSummary(name, file)
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

        _attributePolicy.ValidateFunctionLevelAllows(attributes, function, summary.File, summary.Name, summary.IsHot, summary.IsBoundary);

        if (function.Body != null)
            WalkStatement(function.Body, context);
        if (function.ExpressionBody != null)
            WalkExpression(function.ExpressionBody, context);

        if (_attributePolicy.ValidateHotStateMachines(function, summary.File, summary.Name, summary.IsHot, summary.IsBoundary))
        {
            summary.Allocates = true;
            summary.Resource = true;
        }

        MergeDeclaredCalleeSummaries(summary, performanceFacts);
        _balancePolicy.CheckPoolBalance(summary.PoolRents, summary.File, summary.Name, summary.IsHot, summary.IsBoundary);
        _balancePolicy.CheckResourceBalance(summary.ResourceLocals, summary.File, summary.Name, summary.IsHot, summary.IsBoundary);
        _surfacePolicy.CheckFunctionSurface(function, summary.File, summary.Name, summary.IsHot, summary.IsBoundary);
        _visitingFunctions.Remove(function);

        var functionSummary = new SystemsFunctionSummary(
            name,
            file,
            function.Line,
            function.Column,
            summary.IsHot,
            summary.IsBoundary,
            summary.AllocNone,
            summary.IsHot ? "explicitHot" : "sourceInferred",
            summary.ToFacts(),
            SystemsReportOrder.OrderedCalls(summary.Calls));
        if (_emittedFunctions.Add(function))
            _functions.Add(functionSummary);

        if (attributes.Has("trusted"))
        {
            var trusted = attributes.Get("trusted")!;
            var reason = SystemsAttributeSet.AttributeString(trusted, "reason");
            var owner = SystemsAttributeSet.AttributeString(trusted, "owner");
            var review = SystemsAttributeSet.AttributeString(trusted, "review");
            var expires = SystemsAttributeSet.AttributeString(trusted, "expires");
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

            _attributePolicy.ValidateTrustedFunction(reason, owner, review, summary.MemorySafe, function, summary.File, summary.Name, summary.IsHot, summary.IsBoundary);
        }

        return summary;
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
                context.Allows.Push(allow.Effects);
                WalkStatement(allow.Body, context);
                context.Allows.Pop();
                break;
            case UnsafeBlockStatement unsafeBlock:
                context.Summary.HasUnsafe = true;
                _attributePolicy.ReportUnsafeBlock(context.Summary.IsTrusted, context.Summary.MemorySafe, context.Allows, unsafeBlock.Line, unsafeBlock.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
                context.PushUnsafeBlock();
                WalkStatement(unsafeBlock.Body, context);
                context.PopUnsafeBlock();
                break;
            case ExpressionStatement expression:
                if (expression.Expression is CallExpression discarded
                    && TryResolveDeclaredCallee(discarded, context, out var discardedCallee))
                {
                    _calleePolicy.CheckIgnoredResult(discardedCallee.Function.ReturnType, discardedCallee.QualifiedName, discardedCallee.Function.Name, discarded.Line, discarded.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
                }
                WalkExpression(expression.Expression, context);
                break;
            case VariableDeclarationStatement variable:
                if (variable.Initializer != null)
                {
                    WalkExpression(variable.Initializer, context);
                    if (_callPolicy.IsPoolRentExpression(variable.Initializer))
                    {
                        context.Summary.Pool = true;
                        context.Summary.PoolRents[variable.Name] = new PoolRent(variable.Name, variable.Line, variable.Column);
                    }
                    var resourceKind = _callPolicy.ResourceCreationKind(variable.Initializer);
                    if (resourceKind != null)
                    {
                        context.Summary.Resource = true;
                        context.Summary.ResourceLocals[variable.Name] = new ResourceLocal(variable.Name, resourceKind, variable.Line, variable.Column);
                    }
                    if (_stackalloc.IsStackallocBackedInitializer(variable.Initializer))
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
                context.PushGuards(SystemsGuardPolicy.DerivePositiveGuards(ifStatement.Condition));
                WalkStatement(ifStatement.ThenStatement, context);
                context.PopGuards();
                var guards = SystemsGuardPolicy.DeriveGuardsFromExitingIf(ifStatement);
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
                context.PushGuards(SystemsGuardPolicy.DeriveLoopGuards(forStatement.Condition));
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
                _constructPolicy.ReportAwaitForEach(awaitForEachStatement.Line, awaitForEachStatement.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
                WalkExpression(awaitForEachStatement.Collection, context);
                WalkStatement(awaitForEachStatement.Body, context);
                break;
            case WhileStatement whileStatement:
                WalkExpression(whileStatement.Condition, context);
                context.PushGuards(SystemsGuardPolicy.DeriveLoopGuards(whileStatement.Condition));
                WalkStatement(whileStatement.Body, context);
                context.PopGuards();
                break;
            case ReturnStatement returnStatement:
                if (returnStatement.Value != null)
                {
                    if (_stackalloc.EscapeViolation(returnStatement.Value, context.Summary.StackallocLocals) is { } escape)
                    {
                        context.Summary.ImplicitTrap = true;
                        AddFinding(escape.Code, escape.Effect, escape.Message, returnStatement.Line, returnStatement.Column, "return".Length, context, ErrorSeverity.Error, escape.Suggestion);
                    }
                    WalkExpression(returnStatement.Value, context);
                }
                break;
            case YieldStatement yieldStatement:
                context.Summary.Allocates = true;
                context.Summary.Resource = true;
                _constructPolicy.ReportYield(yieldStatement.Line, yieldStatement.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
                if (yieldStatement.Value != null)
                    WalkExpression(yieldStatement.Value, context);
                break;
            case ThrowStatement throwStatement:
                context.Summary.Throws = true;
                _constructPolicy.ReportThrow(context.Allows, throwStatement.Line, throwStatement.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
                WalkExpression(throwStatement.Expression, context);
                break;
            case TryStatement tryStatement:
                context.Summary.Throws = true;
                _constructPolicy.ReportTry(context.Allows, tryStatement.Line, tryStatement.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
                WalkStatement(tryStatement.TryBlock, context);
                foreach (var catchClause in tryStatement.CatchClauses)
                    WalkStatement(catchClause.Block, context);
                if (tryStatement.FinallyBlock != null)
                    WalkStatement(tryStatement.FinallyBlock, context);
                break;
            case UsingStatement usingStatement:
                context.Summary.Resource = true;
                _constructPolicy.ReportUsing(usingStatement.Line, usingStatement.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
                if (usingStatement.Declaration?.Initializer != null)
                    WalkExpression(usingStatement.Declaration.Initializer, context);
                if (usingStatement.Expression != null)
                {
                    _callPolicy.MarkResourceDisposedIfRecognized(usingStatement.Expression, context.Summary.PoolRents, context.Summary.ResourceLocals);
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
                _calleePolicy.ReportUnknownExternalCall("Console.WriteLine", printStatement.Line, printStatement.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
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
            var calleeFacts = callee.ToFacts();
            caller.MergeEffectsFrom(calleeFacts);
            _calleePolicy.ReportCalleePolicyViolations(
                calleeFacts,
                callee.Name,
                caller.FunctionAllows.Contains("alloc"),
                caller.FunctionAllows.Contains("pool"),
                callSite.Line,
                callSite.Column,
                callSite.Length,
                caller.File,
                caller.Name,
                caller.IsHot,
                caller.IsBoundary,
                caller.AllocNone);
        }
    }

    /// <summary>
    /// Resolves a call to the user-declared function it semantically binds to. The Analyzer
    /// records the resolved declaration (including the overload selected for the call) at the
    /// callee's source position; that function fact maps back to its registered entry by its
    /// unique declaration site. Returns false when the call does not bind to exactly one project
    /// declaration; callers must treat that as unknown, never as clean.
    /// </summary>
    private bool TryResolveDeclaredCallee(CallExpression call, WalkContext context, out FunctionEntry entry)
    {
        entry = null!;
        if (!_semanticModels.TryGetValue(context.Summary.File, out var semanticModel))
            return false;

        if (!semanticModel.ExpressionTypes.TryGetValue((call.Callee.Line, call.Callee.Column), out var calleeType))
            return false;

        if (calleeType is FunctionTypeInfo functionType
            && TryGetEntryForFunctionType(functionType, context, out entry))
        {
            return true;
        }

        if (calleeType is NSharpMethodGroupInfo group
            && TryGetEntryForMethodGroup(group, context, out entry))
        {
            return true;
        }

        return call.Callee is MemberAccessExpression member
            && TryResolveConstrainedInterfaceCallee(member, context, semanticModel, out entry);
    }

    private bool TryGetEntryForFunctionType(FunctionTypeInfo functionType, WalkContext context, out FunctionEntry entry)
    {
        if (DeclarationSite.TryFor(functionType, out var site))
        {
            return TryGetEntryForDeclarationSite(site, context, out entry);
        }

        entry = null!;
        return false;
    }

    private bool TryGetEntryForMethodGroup(NSharpMethodGroupInfo methodGroup, WalkContext context, out FunctionEntry entry)
    {
        var functionTypes = GetMethodGroupFunctions(methodGroup);
        if (functionTypes is [{ } singleFunction])
            return TryGetEntryForFunctionType(singleFunction, context, out entry);

        entry = null!;
        return false;
    }

    private static List<FunctionTypeInfo> GetMethodGroupFunctions(NSharpMethodGroupInfo methodGroup)
        => NSharpMethodGroupInfoFactory.GetFunctions(methodGroup);

    private bool TryGetEntryForDeclarationSite(DeclarationSite site, WalkContext context, out FunctionEntry entry)
    {
        if (_functionEntriesBySite.TryGetValue(site, out var siteEntries)
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

                var declared = iface.DeclaredMembers
                    .FirstOrDefault(candidate =>
                        candidate.Kind == DeclaredMemberKind.Function
                        && candidate.Name == member.MemberName);
                if (declared != null && TryGetEntryForDeclarationSite(DeclarationSite.For(declared), context, out entry))
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

    private void WalkExpression(Expression expression, WalkContext context, bool explicitAllocation = false)
    {
        switch (expression)
        {
            case AllocExpression alloc:
                WalkExpression(alloc.Expression, context, explicitAllocation: true);
                break;
            case StackAllocExpression stackAlloc:
                WalkExpression(stackAlloc.LengthExpression, context);
                if (_stackalloc.BudgetViolation(stackAlloc) is { } budget)
                {
                    context.Summary.ImplicitTrap = true;
                    AddFinding(budget.Code, budget.Effect, budget.Message, stackAlloc.Line, stackAlloc.Column, "stackalloc".Length, context, ErrorSeverity.Error, budget.Suggestion);
                }
                break;
            case NewExpression newExpression:
                foreach (var argument in newExpression.ConstructorArguments)
                    WalkExpression(argument.Value, context);
                if (newExpression.ArrayLengthExpression != null)
                    WalkExpression(newExpression.ArrayLengthExpression, context);
                if (newExpression.Initializer != null)
                    WalkExpression(newExpression.Initializer, context);
                if (_typePolicy.IsHeapAllocation(newExpression))
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
                _constructPolicy.ReportLambda(context.Allows, lambda.Line, lambda.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
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
                if (member.Object is IdentifierExpression receiver
                    && _hotSummaryPolicy.ReportStaticReceiverWarmup(
                        receiver.Name,
                        member.MemberName,
                        _typePolicy,
                        _callPolicy,
                        _hotSummaries,
                        _config.TargetFramework,
                        member.Line,
                        member.Column,
                        context.Summary.File,
                        context.Summary.Name,
                        context.Summary.IsHot,
                        context.Summary.IsBoundary))
                {
                    context.Summary.RequiresWarmup = true;
                }
                break;
            case IndexAccessExpression index:
                WalkExpression(index.Object, context);
                WalkExpression(index.Index, context);
                if (_trapPolicy.ReportIndexTrap(index, context.Guards, context.Allows, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary))
                {
                    context.Summary.ImplicitTrap = true;
                }
                break;
            case BinaryExpression binary:
                WalkExpression(binary.Left, context);
                WalkExpression(binary.Right, context);
                if (_trapPolicy.ReportDivisionTrap(binary, context.Guards, context.Allows, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary))
                {
                    context.Summary.ImplicitTrap = true;
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
                if (_constructPolicy.ReportCastToObject(cast.TargetType, context.Allows, cast.Line, cast.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary))
                {
                    context.Summary.Boxes = true;
                }
                break;
            case IsExpression isExpression:
                WalkExpression(isExpression.Expression, context);
                break;
            case AwaitExpression awaitExpression:
                context.Summary.Resource = true;
                _constructPolicy.ReportAwait(awaitExpression.Line, awaitExpression.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
                WalkExpression(awaitExpression.Expression, context);
                break;
            case ThrowExpression throwExpression:
                context.Summary.Throws = true;
                _constructPolicy.ReportThrow(context.Allows, throwExpression.Line, throwExpression.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
                WalkExpression(throwExpression.Expression, context);
                break;
            case CheckedExpression checkedExpression:
                WalkExpression(checkedExpression.Expression, context);
                if (_trapPolicy.ReportCheckedTrap(context.Allows, checkedExpression.Line, checkedExpression.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary))
                {
                    context.Summary.ImplicitTrap = true;
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
                _constructPolicy.ReportTypeOf(context.Allows, expression.Line, expression.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
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

        var target = SystemsExpressionNames.CallTarget(call.Callee);
        if (target != null && !_callPolicy.IsResultFactoryTarget(target))
            context.Summary.Calls.Add(target);

        WalkExpression(call.Callee, context);

        if (target == null)
        {
            context.Summary.UnknownExternalCall = true;
            _calleePolicy.ReportUnknownExternalCall("<dynamic call>", call.Line, call.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
            return;
        }

        if (_callPolicy.IsResultFactoryTarget(target))
            return;

        if (_callPolicy.MarkResourceDisposedIfRecognized(call.Callee, context.Summary.PoolRents, context.Summary.ResourceLocals))
            return;

        if (_callPolicy.IsKnownConcurrencyPrimitive(target))
        {
            context.Summary.ConcurrencyPrimitive = true;
            return;
        }

        if (_callPolicy.IsUnsupportedConcurrencyPrimitive(target))
        {
            context.Summary.ConcurrencyPrimitive = true;
            _calleePolicy.ReportUnsupportedConcurrencyPrimitive(target, context.Allows, call.Line, call.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
            return;
        }

        if (_callPolicy.IsRuntimeDispatchCall(target))
        {
            context.Summary.Dispatch = true;
            _calleePolicy.ReportRuntimeDispatch(target, context.Allows, call.Line, call.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
            return;
        }

        if (_callPolicy.IsPoolCall(target))
        {
            context.Summary.Pool = true;
            _callPolicy.MarkPoolReturnIfRecognized(call, context.Summary.PoolRents);
            var isPoolRent = _callPolicy.IsPoolRentTarget(target);
            _calleePolicy.ReportHotPoolRent(isPoolRent, context.Allows, call.Line, call.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
            if (isPoolRent && _config.Language.Systems.Warmup.Count == 0)
            {
                context.Summary.RequiresWarmup = true;
            }
            return;
        }

        if (_callPolicy.IsDictionaryTryGetValueCall(call, target))
            return;

        if (_callPolicy.IsBufferMemoryCopyCall(target))
        {
            _hotSummaryPolicy.ReportBufferMemoryCopy(context.InUnsafeBlock, context.Allows.IsAllowed("memorySafety"), call.Line, call.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
            return;
        }

        if (_hotSummaries.TryResolve(target, _config.TargetFramework, out var summaryEntry))
        {
            context.Summary.MergeEffectsFrom(_hotSummaryPolicy.ApplyHotSummary(target, summaryEntry, context.Allows.IsAllowed("aot"), call.Line, call.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary, context.Summary.AllocNone));
            return;
        }

        if (_callPolicy.IsReflectionOrDynamicCall(target))
        {
            context.Summary.Reflection = true;
            context.Summary.DynamicCode |= _callPolicy.IsDynamicCodeCall(target);
            _calleePolicy.ReportReflectionOrDynamicCall(target, context.Allows, call.Line, call.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
            return;
        }

        context.Summary.UnknownExternalCall = true;
        _calleePolicy.ReportUnknownExternalCall(target, call.Line, call.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary);
    }

    private void RecordAllocation(Expression expression, WalkContext context, bool explicitAllocation)
    {
        context.Summary.Allocates = true;

        var violation = SystemsAllocationPolicy.Violation(
            context.Summary.IsHot,
            context.Summary.AllocNone,
            context.Summary.IsBoundary,
            context.Allows.IsAllowed("alloc"),
            IsSystemsProfile,
            explicitAllocation);
        if (violation != null)
        {
            AddFinding(
                violation.Code,
                violation.Effect,
                violation.Message,
                expression.Line,
                expression.Column,
                1,
                context,
                violation.Severity,
                violation.Suggestion);
        }
    }

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
        => _findingSink.AddForFunction(code, effect, message, line, column, length, summary.File, summary.Name, summary.IsHot, summary.IsBoundary, preferredSeverity, suggestion);

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
        => _findingSink.Add(code, effect, message, line, column, length, summary.File, summary.Name, summary.IsHot, summary.IsBoundary, preferredSeverity, suggestion, callPath);

    private sealed class MutableFunctionSummary
    {
        public MutableFunctionSummary(string name, string file)
        {
            Name = name;
            File = file;
        }

        public string Name { get; }
        public string File { get; }
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

        public SystemsEffectFacts ToFacts()
            => new(Allocates, Boxes, Delegate, Closure, Dispatch, Reflection, DynamicCode, Throws, ImplicitTrap, UnknownExternalCall, Resource, Pool, ConcurrencyPrimitive, RequiresWarmup, AotSafe: !DynamicCode && !Reflection);

        public void MergeEffectsFrom(SystemsEffectFacts other)
        {
            Allocates |= other.Allocates;
            Boxes |= other.Boxes;
            Delegate |= other.ConstructsDelegate;
            Closure |= other.CapturesClosure;
            Dispatch |= other.UsesRuntimeDispatch;
            Reflection |= other.UsesReflection;
            DynamicCode |= other.UsesDynamicCode;
            Throws |= other.Throws;
            ImplicitTrap |= other.HasImplicitTrapObligation;
            UnknownExternalCall |= other.UsesUnknownExternalCall;
            Resource |= other.UsesResource;
            Pool |= other.UsesPool;
            ConcurrencyPrimitive |= other.UsesConcurrencyPrimitive;
            RequiresWarmup |= other.RequiresWarmup;
        }
    }

    private sealed record FunctionEntry(string File, string? ContainingType, string QualifiedName, FunctionDeclaration Function);

    /// <summary>
    /// Source-site identity of a function declaration: owner, name, position, and arity. File imports
    /// re-parse the imported unit, so a semantically resolved declaration can be a different AST
    /// object than the registered one — but it always shares the declaration site. The site is
    /// only trusted when it identifies exactly one registered entry.
    /// </summary>
    private readonly record struct DeclarationSite(string Name, string? ContainingType, int Line, int Column, int ParameterCount)
    {
        public static DeclarationSite For(FunctionDeclaration function, string? containingType)
            => new(function.Name, containingType, function.Line, function.Column, function.Parameters.Count);

        public static DeclarationSite For(DeclaredMemberInfo member)
            => new(member.Name, member.ContainingType, member.Line, member.Column, member.ParameterCount);

        public static bool TryFor(FunctionTypeInfo functionType, out DeclarationSite site)
        {
            if (string.IsNullOrEmpty(functionType.SourceName)
                || functionType.SourceLine <= 0
                || functionType.SourceColumn <= 0
                || functionType.SourceParameterCount < 0)
            {
                site = default;
                return false;
            }

            site = new DeclarationSite(
                functionType.SourceName,
                functionType.SourceContainingType,
                functionType.SourceLine,
                functionType.SourceColumn,
                functionType.SourceParameterCount);
            return true;
        }
    }

    private sealed record CallSite(FunctionEntry Callee, int Line, int Column, int Length);

    private sealed class WalkContext
    {
        // Marks (Guards.Count at push time) so Pop truncates back exactly, instead of removing by
        // value (which corrupts the set for structurally-identical nested guards — M3).
        private readonly Stack<int> _guardStack = new();
        private int _allocZoneDepth;
        private int _unsafeBlockDepth;

        public WalkContext(FunctionEntry entry, MutableFunctionSummary summary)
        {
            Entry = entry;
            Summary = summary;
            Allows = new SystemsAllowStack(summary.FunctionAllows);
        }

        public FunctionEntry Entry { get; }
        public MutableFunctionSummary Summary { get; }
        public SystemsAllowStack Allows { get; }
        public bool InAllocZone => _allocZoneDepth > 0;
        public bool InUnsafeBlock => _unsafeBlockDepth > 0;
        public List<Guard> Guards { get; } = new();

        public void PushAllocZone() => _allocZoneDepth++;
        public void PopAllocZone() => _allocZoneDepth = Math.Max(0, _allocZoneDepth - 1);
        public void PushUnsafeBlock() => _unsafeBlockDepth++;
        public void PopUnsafeBlock() => _unsafeBlockDepth = Math.Max(0, _unsafeBlockDepth - 1);

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

}
