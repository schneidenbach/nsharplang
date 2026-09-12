namespace NSharpLang.Compiler.Performance

import System
import System.Collections
import System.Collections.Generic
import System.IO
import System.Linq
import NSharpLang.Compiler.Ast


// The complete systems policy/effect analysis owner. It deliberately remains conservative and
// source based: calls to source functions resolve through the semantic model's declaration sites,
// while a hot-path call that resolves to neither source nor a known runtime fact stays unknown.
sealed class SystemsAnalyzer {
    private readonly ProjectRoot: string
    private readonly Config: ProjectConfig
    private readonly FindingSink: SystemsFindingSink
    private readonly Functions: List<SystemsFunctionSummary>
    private readonly TrustedSites: List<SystemsTrustedSite>
    private readonly FunctionEntriesBySite: Dictionary<DeclarationSite, List<FunctionEntry>>
    private readonly VisibleDeclarationFilesByFile: Dictionary<string, HashSet<string>>
    private readonly OrderedFunctionEntries: List<FunctionEntry>
    private readonly SummaryCache: Dictionary<FunctionDeclaration, MutableFunctionSummary>
    private readonly VisitingFunctions: HashSet<FunctionDeclaration>
    private readonly EmittedFunctions: HashSet<FunctionDeclaration>
    private readonly TypePolicy: SystemsTypePolicy
    private readonly StackallocPolicy: SystemsStackallocPolicy
    private readonly CallPolicy: SystemsCallPolicy
    private readonly SurfacePolicy: SystemsSurfacePolicy
    private readonly BalancePolicy: SystemsBalancePolicy
    private readonly CalleePolicy: SystemsCalleePolicy
    private readonly AttributePolicy: SystemsAttributePolicy
    private readonly HotSummaryPolicy: SystemsHotSummaryPolicy
    private readonly ConstructPolicy: SystemsConstructPolicy
    private readonly TrapPolicy: SystemsTrapPolicy
    private SemanticModels: IReadOnlyDictionary<string, SemanticModel>
    private HotSummaries: HotSummaryCatalog

    private static readonly EmptySemanticModels: IReadOnlyDictionary<string, SemanticModel> = CreateEmptySemanticModels()

    private static func CreateEmptySemanticModels(): IReadOnlyDictionary<string, SemanticModel> {
        return new Dictionary<string, SemanticModel>()
    }

    public constructor(projectRoot: string, config: ProjectConfig?) {
        // C# runs instance field initializers before the constructor body. Keep those allocations
        // in their declaration order before assigning the two constructor-owned fields.
        FindingSink = new SystemsFindingSink()
        Functions = new List<SystemsFunctionSummary>()
        TrustedSites = new List<SystemsTrustedSite>()
        FunctionEntriesBySite = new Dictionary<SystemsAnalyzer.DeclarationSite, List<SystemsAnalyzer.FunctionEntry>>()
        VisibleDeclarationFilesByFile = new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase)
        OrderedFunctionEntries = new List<SystemsAnalyzer.FunctionEntry>()
        SummaryCache = new Dictionary<FunctionDeclaration, SystemsAnalyzer.MutableFunctionSummary>(ReferenceEqualityComparer.Instance)
        VisitingFunctions = new HashSet<FunctionDeclaration>(ReferenceEqualityComparer.Instance)
        EmittedFunctions = new HashSet<FunctionDeclaration>(ReferenceEqualityComparer.Instance)
        TypePolicy = new SystemsTypePolicy()
        StackallocPolicy = new SystemsStackallocPolicy()
        CallPolicy = new SystemsCallPolicy()
        SemanticModels = SystemsAnalyzer.EmptySemanticModels

        ProjectRoot = projectRoot
        Config = config ?? ProjectFileParser.CreateDefault(null)
        FindingSink.BeginAnalysis(Config)
        SurfacePolicy = new SystemsSurfacePolicy(TypePolicy, FindingSink)
        BalancePolicy = new SystemsBalancePolicy(FindingSink)
        CalleePolicy = new SystemsCalleePolicy(TypePolicy, FindingSink)
        CalleePolicy.BeginAnalysis(Config)
        AttributePolicy = new SystemsAttributePolicy(FindingSink)
        HotSummaryPolicy = new SystemsHotSummaryPolicy(FindingSink)
        HotSummaryPolicy.BeginAnalysis(Config)
        ConstructPolicy = new SystemsConstructPolicy(FindingSink)
        TrapPolicy = new SystemsTrapPolicy(FindingSink)
        HotSummaries = HotSummaryCatalog.Load(projectRoot, Config)
    }

    func Analyze(compilationUnits: IReadOnlyDictionary<string, CompilationUnit>, performanceFacts: PerformanceFactStore? = null, semanticModels: IReadOnlyDictionary<string, SemanticModel>? = null): SystemsReport {
        FindingSink.BeginAnalysis(Config)
        Functions.Clear()
        TrustedSites.Clear()
        FunctionEntriesBySite.Clear()
        VisibleDeclarationFilesByFile.Clear()
        OrderedFunctionEntries.Clear()
        SummaryCache.Clear()
        VisitingFunctions.Clear()
        EmittedFunctions.Clear()
        TypePolicy.BeginAnalysis()
        StackallocPolicy.BeginAnalysis(Config)
        CallPolicy.BeginAnalysis()
        CalleePolicy.BeginAnalysis(Config)
        HotSummaryPolicy.BeginAnalysis(Config)
        SemanticModels = semanticModels ?? SystemsAnalyzer.EmptySemanticModels
        HotSummaries = HotSummaryCatalog.Load(ProjectRoot, Config)
        BuildVisibleDeclarationFiles(compilationUnits)

        compilationUnitKeys := compilationUnits.get_Keys()
        orderedFileInputs := compilationUnitKeys.ToArray()
        orderedFiles := SystemsReportOrder.OrderedFiles(orderedFileInputs)
        fileIndex := 0
        while fileIndex < orderedFiles.Length {
            filePath := orderedFiles[fileIndex]
            RegisterDeclarations(filePath, compilationUnits[filePath].Declarations, null)
            fileIndex = fileIndex + 1
        }

        entryEnumerator := OrderedFunctionEntries.GetEnumerator()
        try {
            while entryEnumerator.MoveNext() {
                AnalyzeFunction(entryEnumerator.get_Current(), performanceFacts)
            }
        } finally {
            entryEnumerator.Dispose()
        }

        aotAnalysis := FindingSink.AotAnalysis()
        profile := Config.Language.Profile
        effectiveMode := EffectiveMode()
        aotTarget := Config.Language.Systems.AotTarget
        warmup := Config.Language.Systems.Warmup
        functions := Functions
        findings := FindingSink.Ordered()
        trustedSites := SystemsReportOrder.OrderedTrustedSites(TrustedSites)
        aotReportTarget := Config.Language.Systems.AotTarget
        aotReport := new SystemsAotReport(aotReportTarget, aotAnalysis, false, aotAnalysis == "pass")
        functionCount := Functions.Count
        hotFunctionCount := CountHotFunctions(Functions)
        boundaryFunctionCount := CountBoundaryFunctions(Functions)
        findingCount := FindingSink.Count
        errorCount := FindingSink.ErrorCount
        warningCount := FindingSink.WarningCount
        trustedSiteCount := TrustedSites.Count
        summary := new SystemsReportSummary(functionCount, hotFunctionCount, boundaryFunctionCount, findingCount, errorCount, warningCount, trustedSiteCount)
        report := new SystemsReport(
            1,
            profile,
            effectiveMode,
            aotTarget,
            warmup,
            functions,
            findings,
            trustedSites,
            aotReport,
            summary
        )
        return report
    }

    private static func CountHotFunctions(summaries: List<SystemsFunctionSummary>): int {
        count := 0
        enumerator := summaries.GetEnumerator()
        try {
            while enumerator.MoveNext() {
                if enumerator.get_Current().IsHot {
                    count = count + 1
                }
            }
        } finally {
            enumerator.Dispose()
        }
        return count
    }

    private static func CountBoundaryFunctions(summaries: List<SystemsFunctionSummary>): int {
        count := 0
        enumerator := summaries.GetEnumerator()
        try {
            while enumerator.MoveNext() {
                if enumerator.get_Current().IsBoundary {
                    count = count + 1
                }
            }
        } finally {
            enumerator.Dispose()
        }
        return count
    }

    private func IsSystemsProfile(): bool {
        return FindingSink.IsSystemsProfile
    }

    private func EffectiveMode(): string {
        return FindingSink.EffectiveMode
    }

    private func RegisterDeclarations(filePath: string, declarations: IEnumerable<Declaration>, containingType: string?) {
        declarationEnumerator := declarations.GetEnumerator()
        movement := declarationEnumerator as IEnumerator
        try {
            while movement.MoveNext() {
                declaration := declarationEnumerator.get_Current()
                if declaration is FunctionDeclaration {
                    function := declaration as FunctionDeclaration
                    RegisterFunction(filePath, containingType, function)
                } else if declaration is FieldDeclaration {
                    field := declaration as FieldDeclaration
                    CallPolicy.RegisterMemberType(containingType, field.Name, field.Type)
                } else if declaration is PropertyDeclaration {
                    property := declaration as PropertyDeclaration
                    CallPolicy.RegisterMemberType(containingType, property.Name, property.Type)
                } else if declaration is ClassDeclaration {
                    classDeclaration := declaration as ClassDeclaration
                    RegisterDeclarations(filePath, classDeclaration.Members, classDeclaration.Name)
                } else if declaration is StructDeclaration {
                    structDeclaration := declaration as StructDeclaration
                    TypePolicy.RegisterStructType(structDeclaration.Name)
                    if structDeclaration.IsRefStruct {
                        TypePolicy.RegisterRefStructType(structDeclaration.Name)
                    }
                    SurfacePolicy.CheckRefLikeFields(filePath, structDeclaration.Name, structDeclaration.IsRefStruct, structDeclaration.Members)
                    RegisterDeclarations(filePath, structDeclaration.Members, structDeclaration.Name)
                } else if declaration is RecordDeclaration {
                    recordDeclaration := declaration as RecordDeclaration
                    if recordDeclaration.IsStruct {
                        TypePolicy.RegisterStructType(recordDeclaration.Name)
                    }
                    SurfacePolicy.CheckRefLikeFields(filePath, recordDeclaration.Name, false, recordDeclaration.Members)
                    RegisterDeclarations(filePath, recordDeclaration.Members, recordDeclaration.Name)
                } else if declaration is SoaRecordDeclaration {
                    RegisterSoaColumns(declaration as SoaRecordDeclaration)
                } else if declaration is InterfaceDeclaration {
                    interfaceDeclaration := declaration as InterfaceDeclaration
                    RegisterDeclarations(filePath, interfaceDeclaration.Members, interfaceDeclaration.Name)
                } else if declaration is EnumDeclaration {
                    enumDeclaration := declaration as EnumDeclaration
                    TypePolicy.RegisterEnumType(enumDeclaration.Name)
                } else if declaration is TypeAliasDeclaration {
                    alias := declaration as TypeAliasDeclaration
                    StackallocPolicy.RegisterTypeAlias(alias.Name, alias.Type)
                }
            }
        } finally {
            disposable := declarationEnumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
    }

    private func RegisterSoaColumns(soa: SoaRecordDeclaration) {
        columnEnumerator := soa.Columns.GetEnumerator()
        try {
            while columnEnumerator.MoveNext() {
                column := columnEnumerator.get_Current()
                CallPolicy.RegisterMemberType(soa.Name, column.Name, column.Type)
            }
        } finally {
            columnEnumerator.Dispose()
        }
    }

    private func RegisterFunction(filePath: string, containingType: string?, function: FunctionDeclaration) {
        qualified := containingType == null ? function.Name : containingType + "." + function.Name
        entry := new FunctionEntry(filePath, containingType, qualified, function)

        // Imported files are parsed again, so source identity is the declaration's owner, name,
        // position, and arity. A site remains usable only when exactly one entry owns it.
        siteName := function.Name
        siteContainingType := containingType
        siteLine := function.Line
        siteColumn := function.Column
        siteParameterCount := function.Parameters.Count
        site := new SystemsAnalyzer.DeclarationSite(siteName, siteContainingType, siteLine, siteColumn, siteParameterCount)
        siteEntries: List<FunctionEntry> = null
        if !FunctionEntriesBySite.TryGetValue(site, out siteEntries) {
            siteEntries = new List<SystemsAnalyzer.FunctionEntry>()
            FunctionEntriesBySite[site] = siteEntries
        }
        siteEntries.Add(entry)
        OrderedFunctionEntries.Add(entry)
    }

    private func AnalyzeFunction(entry: FunctionEntry, performanceFacts: PerformanceFactStore?): MutableFunctionSummary {
        cached: MutableFunctionSummary = null
        if SummaryCache.TryGetValue(entry.Function, out cached) {
            return cached
        }

        filePath := entry.File
        function := entry.Function
        name := entry.QualifiedName
        attributes := new SystemsAttributeSet(function.Attributes)
        summary := new MutableFunctionSummary(name, filePath)
        summary.IsHot = attributes.Has("hot")
        summary.IsBoundary = attributes.Has("boundary")
        summary.AllocNone = attributes.Has("alloc") && attributes.AttributeHasArgument("alloc", "none")
        summary.IsTrusted = attributes.Has("trusted")
        summary.MemorySafe = attributes.Has("memory") && attributes.AttributeHasArgument("memory", "safe")
        summary.FunctionAllows = attributes.AllowEffects()

        context := new WalkContext(entry, summary)
        SummaryCache[function] = summary
        if !VisitingFunctions.Add(function) {
            return summary
        }

        AttributePolicy.ValidateFunctionLevelAllows(attributes, function, summary.File, summary.Name, summary.IsHot, summary.IsBoundary)

        if function.Body != null {
            WalkStatement(function.Body, context)
        }
        if function.ExpressionBody != null {
            WalkExpression(function.ExpressionBody, context, false)
        }

        if AttributePolicy.ValidateHotStateMachines(function, summary.File, summary.Name, summary.IsHot, summary.IsBoundary) {
            summary.Allocates = true
            summary.Resource = true
        }

        MergeDeclaredCalleeSummaries(summary, performanceFacts)
        BalancePolicy.CheckPoolBalance(summary.PoolRents, summary.File, summary.Name, summary.IsHot, summary.IsBoundary)
        BalancePolicy.CheckResourceBalance(summary.ResourceLocals, summary.File, summary.Name, summary.IsHot, summary.IsBoundary)
        SurfacePolicy.CheckFunctionSurface(function, summary.File, summary.Name, summary.IsHot, summary.IsBoundary)
        VisitingFunctions.Remove(function)

        functionSummary := new SystemsFunctionSummary(
            name,
            filePath,
            function.Line,
            function.Column,
            summary.IsHot,
            summary.IsBoundary,
            summary.AllocNone,
            summary.IsHot ? "explicitHot" : "sourceInferred",
            summary.ToFacts(),
            SystemsReportOrder.OrderedCalls(summary.Calls)
        )
        if EmittedFunctions.Add(function) {
            Functions.Add(functionSummary)
        }

        if attributes.Has("trusted") {
            trusted := attributes.Get("trusted")
            reason := SystemsAttributeSet.AttributeString(trusted, "reason")
            owner := SystemsAttributeSet.AttributeString(trusted, "owner")
            review := SystemsAttributeSet.AttributeString(trusted, "review")
            expires := SystemsAttributeSet.AttributeString(trusted, "expires")
            TrustedSites.Add(new SystemsTrustedSite(
                name,
                filePath,
                function.Line,
                function.Column,
                reason,
                owner,
                review,
                expires,
                summary.HasUnsafe,
                TrustedBodyStatementCount(function)
            ))

            AttributePolicy.ValidateTrustedFunction(reason, owner, review, summary.MemorySafe, function, summary.File, summary.Name, summary.IsHot, summary.IsBoundary)
        }

        return summary
    }

    private func WalkStatement(statement: Statement, context: WalkContext) {
        if statement is BlockStatement {
            block := statement as BlockStatement
            WalkStatementList(block.Statements, context)
            return
        }

        if statement is AllocBlockStatement {
            allocBlock := statement as AllocBlockStatement
            context.PushAllocZone()
            WalkStatement(allocBlock.Body, context)
            context.PopAllocZone()
            return
        }

        if statement is AllowStatement {
            allowStatement := statement as AllowStatement
            context.Allows.Push(allowStatement.Effects)
            WalkStatement(allowStatement.Body, context)
            context.Allows.Pop()
            return
        }

        if statement is UnsafeBlockStatement {
            unsafeBlock := statement as UnsafeBlockStatement
            context.Summary.HasUnsafe = true
            AttributePolicy.ReportUnsafeBlock(context.Summary.IsTrusted, context.Summary.MemorySafe, context.Allows, unsafeBlock.Line, unsafeBlock.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
            context.PushUnsafeBlock()
            WalkStatement(unsafeBlock.Body, context)
            context.PopUnsafeBlock()
            return
        }

        if statement is ExpressionStatement {
            expressionStatement := statement as ExpressionStatement
            discarded := expressionStatement.Expression as CallExpression
            discardedCallee: FunctionEntry = null
            if discarded != null && TryResolveDeclaredCallee(discarded, context, out discardedCallee) {
                CalleePolicy.CheckIgnoredResult(discardedCallee.Function.ReturnType, discardedCallee.QualifiedName, discardedCallee.Function.Name, discarded.Line, discarded.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
            }
            WalkExpression(expressionStatement.Expression, context, false)
            return
        }

        if statement is VariableDeclarationStatement {
            variable := statement as VariableDeclarationStatement
            if variable.Initializer != null {
                WalkExpression(variable.Initializer, context, false)
                if CallPolicy.IsPoolRentExpression(variable.Initializer) {
                    context.Summary.Pool = true
                    context.Summary.PoolRents[variable.Name] = new PoolRent(variable.Name, variable.Line, variable.Column)
                }
                resourceKind := CallPolicy.ResourceCreationKind(variable.Initializer)
                if resourceKind != null {
                    context.Summary.Resource = true
                    context.Summary.ResourceLocals[variable.Name] = new ResourceLocal(variable.Name, resourceKind, variable.Line, variable.Column)
                }
                if StackallocPolicy.IsStackallocBackedInitializer(variable.Initializer) {
                    context.Summary.StackallocLocals.Add(variable.Name)
                }
            }
            return
        }

        if statement is TupleDeconstructionStatement {
            tuple := statement as TupleDeconstructionStatement
            WalkExpression(tuple.Initializer, context, false)
            return
        }

        if statement is IfStatement {
            ifStatement := statement as IfStatement
            WalkExpression(ifStatement.Condition, context, false)
            context.PushGuards(SystemsGuardPolicy.DerivePositiveGuards(ifStatement.Condition))
            WalkStatement(ifStatement.ThenStatement, context)
            context.PopGuards()
            guards := SystemsGuardPolicy.DeriveGuardsFromExitingIf(ifStatement)
            if ifStatement.ElseStatement != null {
                context.PushGuards(guards)
                WalkStatement(ifStatement.ElseStatement, context)
                context.PopGuards()
            }
            context.AddGuards(guards)
            return
        }

        if statement is ForStatement {
            forStatement := statement as ForStatement
            if forStatement.Initializer != null {
                WalkStatement(forStatement.Initializer, context)
            }
            if forStatement.Condition != null {
                WalkExpression(forStatement.Condition, context, false)
            }
            context.PushGuards(SystemsGuardPolicy.DeriveLoopGuards(forStatement.Condition))
            WalkStatement(forStatement.Body, context)
            context.PopGuards()
            if forStatement.Iterator != null {
                WalkExpression(forStatement.Iterator, context, false)
            }
            return
        }

        if statement is ForeachStatement {
            foreachStatement := statement as ForeachStatement
            WalkExpression(foreachStatement.Collection, context, false)
            WalkStatement(foreachStatement.Body, context)
            return
        }

        if statement is AwaitForEachStatement {
            awaitForEachStatement := statement as AwaitForEachStatement
            context.Summary.Resource = true
            ConstructPolicy.ReportAwaitForEach(awaitForEachStatement.Line, awaitForEachStatement.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
            WalkExpression(awaitForEachStatement.Collection, context, false)
            WalkStatement(awaitForEachStatement.Body, context)
            return
        }

        if statement is WhileStatement {
            whileStatement := statement as WhileStatement
            WalkExpression(whileStatement.Condition, context, false)
            context.PushGuards(SystemsGuardPolicy.DeriveLoopGuards(whileStatement.Condition))
            WalkStatement(whileStatement.Body, context)
            context.PopGuards()
            return
        }

        if statement is ReturnStatement {
            returnStatement := statement as ReturnStatement
            if returnStatement.Value != null {
                escape := StackallocPolicy.EscapeViolation(returnStatement.Value, context.Summary.StackallocLocals)
                if escape != null {
                    context.Summary.ImplicitTrap = true
                    AddFinding(escape.Code, escape.Effect, escape.Message, returnStatement.Line, returnStatement.Column, "return".Length, context, ErrorSeverity.Error, escape.Suggestion)
                }
                WalkExpression(returnStatement.Value, context, false)
            }
            return
        }

        if statement is YieldStatement {
            yieldStatement := statement as YieldStatement
            context.Summary.Allocates = true
            context.Summary.Resource = true
            ConstructPolicy.ReportYield(yieldStatement.Line, yieldStatement.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
            if yieldStatement.Value != null {
                WalkExpression(yieldStatement.Value, context, false)
            }
            return
        }

        if statement is ThrowStatement {
            throwStatement := statement as ThrowStatement
            context.Summary.Throws = true
            ConstructPolicy.ReportThrow(context.Allows, throwStatement.Line, throwStatement.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
            WalkExpression(throwStatement.Expression, context, false)
            return
        }

        if statement is TryStatement {
            tryStatement := statement as TryStatement
            context.Summary.Throws = true
            ConstructPolicy.ReportTry(context.Allows, tryStatement.Line, tryStatement.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
            WalkStatement(tryStatement.TryBlock, context)
            WalkCatchClauses(tryStatement.CatchClauses, context)
            if tryStatement.FinallyBlock != null {
                WalkStatement(tryStatement.FinallyBlock, context)
            }
            return
        }

        if statement is UsingStatement {
            usingStatement := statement as UsingStatement
            context.Summary.Resource = true
            ConstructPolicy.ReportUsing(usingStatement.Line, usingStatement.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
            declaration := usingStatement.Declaration
            if declaration != null && declaration.Initializer != null {
                WalkExpression(declaration.Initializer, context, false)
            }
            if usingStatement.Expression != null {
                CallPolicy.MarkResourceDisposedIfRecognized(usingStatement.Expression, context.Summary.PoolRents, context.Summary.ResourceLocals, null)
                WalkExpression(usingStatement.Expression, context, false)
            }
            if usingStatement.Body != null {
                WalkStatement(usingStatement.Body, context)
            }
            return
        }

        if statement is LockStatement {
            lockStatement := statement as LockStatement
            context.Summary.ConcurrencyPrimitive = true
            WalkExpression(lockStatement.LockObject, context, false)
            WalkStatement(lockStatement.Body, context)
            return
        }

        if statement is SwitchStatement {
            switchStatement := statement as SwitchStatement
            WalkExpression(switchStatement.Value, context, false)
            WalkSwitchCases(switchStatement.Cases, context)
            return
        }

        if statement is PrintStatement {
            printStatement := statement as PrintStatement
            context.Summary.UnknownExternalCall = true
            CalleePolicy.ReportUnknownExternalCall("Console.WriteLine", printStatement.Line, printStatement.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
            WalkExpression(printStatement.Value, context, false)
            return
        }

        if statement is AssertStatement {
            assertStatement := statement as AssertStatement
            WalkExpression(assertStatement.Condition, context, false)
            if assertStatement.Message != null {
                WalkExpression(assertStatement.Message, context, false)
            }
            return
        }

        if statement is AssertThrowsStatement {
            assertThrowsStatement := statement as AssertThrowsStatement
            context.Summary.Throws = true
            WalkStatement(assertThrowsStatement.Body, context)
            return
        }

        if statement is LocalFunctionStatement {
            localFunction := statement as LocalFunctionStatement
            if localFunction.Function.Body != null {
                WalkStatement(localFunction.Function.Body, context)
            }
            if localFunction.Function.ExpressionBody != null {
                WalkExpression(localFunction.Function.ExpressionBody, context, false)
            }
        }
    }

    private func WalkStatementList(statements: List<Statement>, context: WalkContext) {
        statementEnumerator := statements.GetEnumerator()
        try {
            while statementEnumerator.MoveNext() {
                WalkStatement(statementEnumerator.get_Current(), context)
            }
        } finally {
            statementEnumerator.Dispose()
        }
    }

    private func WalkCatchClauses(catchClauses: List<CatchClause>, context: WalkContext) {
        catchEnumerator := catchClauses.GetEnumerator()
        try {
            while catchEnumerator.MoveNext() {
                WalkStatement(catchEnumerator.get_Current().Block, context)
            }
        } finally {
            catchEnumerator.Dispose()
        }
    }

    private func WalkSwitchCases(cases: List<SwitchCase>, context: WalkContext) {
        caseEnumerator := cases.GetEnumerator()
        try {
            while caseEnumerator.MoveNext() {
                WalkStatementList(caseEnumerator.get_Current().Statements, context)
            }
        } finally {
            caseEnumerator.Dispose()
        }
    }

    private func MergeDeclaredCalleeSummaries(caller: MutableFunctionSummary, performanceFacts: PerformanceFactStore?) {
        callSiteEnumerator := caller.CallSites.GetEnumerator()
        try {
            while callSiteEnumerator.MoveNext() {
                callSite := callSiteEnumerator.get_Current()
                callee := AnalyzeFunction(callSite.Callee, performanceFacts)
                calleeFacts := callee.ToFacts()
                caller.MergeEffectsFrom(calleeFacts)
                CalleePolicy.ReportCalleePolicyViolations(
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
                    caller.AllocNone
                )
            }
        } finally {
            callSiteEnumerator.Dispose()
        }
    }

    // Resolve only the declaration that the semantic model bound at this exact call position.
    private func TryResolveDeclaredCallee(call: CallExpression, context: WalkContext, out entry: FunctionEntry): bool {
        entry = null
        semanticModel: SemanticModel = null
        if !SemanticModels.TryGetValue(context.Summary.File, out semanticModel) {
            return false
        }

        calleeType: TypeInfo = null
        calleeKey := (Line: call.Callee.Line, Column: call.Callee.Column)
        if !semanticModel.ExpressionTypes.TryGetValue(calleeKey, out calleeType) {
            return false
        }

        functionType := calleeType as FunctionTypeInfo
        if functionType != null && TryGetEntryForFunctionType(functionType, context, out entry) {
            return true
        }

        group := calleeType as NSharpMethodGroupInfo
        if group != null && TryGetEntryForMethodGroup(group, context, out entry) {
            return true
        }

        member := call.Callee as MemberAccessExpression
        return member != null && TryResolveConstrainedInterfaceCallee(member, context, semanticModel, out entry)
    }

    private func TryGetEntryForFunctionType(functionType: FunctionTypeInfo, context: WalkContext, out entry: FunctionEntry): bool {
        if !string.IsNullOrEmpty(functionType.SourceName) && functionType.SourceLine > 0 && functionType.SourceColumn > 0 && functionType.SourceParameterCount >= 0 {
            site := new SystemsAnalyzer.DeclarationSite(functionType.SourceName, functionType.SourceContainingType, functionType.SourceLine, functionType.SourceColumn, functionType.SourceParameterCount)
            return TryGetEntryForDeclarationSite(site, context, out entry)
        }

        entry = null
        return false
    }

    private func TryGetEntryForMethodGroup(methodGroup: NSharpMethodGroupInfo, context: WalkContext, out entry: FunctionEntry): bool {
        functionTypes := GetMethodGroupFunctions(methodGroup)
        if functionTypes != null && functionTypes.Count == 1 {
            singleFunction := functionTypes[0]
            if singleFunction != null {
                return TryGetEntryForFunctionType(singleFunction, context, out entry)
            }
        }

        entry = null
        return false
    }

    private static func GetMethodGroupFunctions(methodGroup: NSharpMethodGroupInfo): List<FunctionTypeInfo> {
        return NSharpMethodGroupInfoFactory.GetFunctions(methodGroup)
    }

    private func TryGetEntryForDeclarationSite(site: DeclarationSite, context: WalkContext, out entry: FunctionEntry): bool {
        siteEntries: List<FunctionEntry> = null
        if FunctionEntriesBySite.TryGetValue(site, out siteEntries) && siteEntries.Count == 1 {
            entry = siteEntries[0]
            return true
        }

        visibleFiles: HashSet<string> = null
        if siteEntries != null && VisibleDeclarationFilesByFile.TryGetValue(context.Summary.File, out visibleFiles) {
            visibleEntries := MaterializeVisibleEntries(siteEntries, visibleFiles)
            if visibleEntries.Count == 1 {
                entry = visibleEntries[0]
                return true
            }
        }

        entry = null
        return false
    }

    private static func MaterializeVisibleEntries(siteEntries: List<FunctionEntry>, visibleFiles: HashSet<string>): List<FunctionEntry> {
        visibleEntries := new List<SystemsAnalyzer.FunctionEntry>()
        entryEnumerator := siteEntries.GetEnumerator()
        try {
            while entryEnumerator.MoveNext() {
                candidate := entryEnumerator.get_Current()
                if visibleFiles.Contains(candidate.File) {
                    visibleEntries.Add(candidate)
                }
            }
        } finally {
            entryEnumerator.Dispose()
        }
        return visibleEntries
    }

    private func BuildVisibleDeclarationFiles(compilationUnits: IReadOnlyDictionary<string, CompilationUnit>) {
        sourceFileKeys := compilationUnits.get_Keys()
        keySelector: Func<string, string> = path => Path.GetFullPath(path)
        valueSelector: Func<string, string> = path => path
        sourceFileByFullPath := Enumerable.ToDictionary<string, string, string>(sourceFileKeys, keySelector, valueSelector, StringComparer.OrdinalIgnoreCase)

        entryEnumerator := compilationUnits.GetEnumerator()
        entryMovement := entryEnumerator as IEnumerator
        try {
            while entryMovement.MoveNext() {
                pair := entryEnumerator.get_Current()
                sourceFile := pair.get_Key()
                unit := pair.get_Value()
                visibleFiles := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
                visibleFiles.Add(sourceFile)

                resolver := new FileResolver(ProjectRoot, sourceFile)
                AddVisibleFileImports(unit.FileImports, resolver, sourceFileByFullPath, visibleFiles)
                VisibleDeclarationFilesByFile[sourceFile] = visibleFiles
            }
        } finally {
            disposable := entryEnumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
    }

    private static func AddVisibleFileImports(fileImports: List<Statement>, resolver: FileResolver, sourceFileByFullPath: Dictionary<string, string>, visibleFiles: HashSet<string>) {
        importEnumerator := fileImports.GetEnumerator()
        try {
            while importEnumerator.MoveNext() {
                fileImport := importEnumerator.get_Current() as FileImport
                if fileImport != null {
                    resolvedPath := Path.GetFullPath(resolver.ResolveFilePath(fileImport.Path))
                    targetFile: string = null
                    if sourceFileByFullPath.TryGetValue(resolvedPath, out targetFile) {
                        visibleFiles.Add(targetFile)
                    }
                }
            }
        } finally {
            importEnumerator.Dispose()
        }
    }

    private func TryResolveConstrainedInterfaceCallee(member: MemberAccessExpression, context: WalkContext, semanticModel: SemanticModel, out entry: FunctionEntry): bool {
        entry = null
        receiverType: TypeInfo = null
        receiverKey := (Line: member.Object.Line, Column: member.Object.Column)
        if !semanticModel.ExpressionTypes.TryGetValue(receiverKey, out receiverType) {
            return false
        }

        // A constrained receiver starts as the bare type-parameter name. Nominal receivers have a
        // real declaration and have already gone through the primary semantic binding path.
        simple := receiverType as SimpleTypeInfo
        if simple == null {
            return false
        }

        function := context.Entry.Function
        if function.TypeParameters == null || !ContainsTypeParameter(function.TypeParameters, simple.Name) {
            return false
        }

        constraints := function.Constraints
        if constraints != null {
            constraintEnumerator := constraints.GetEnumerator()
            try {
                while constraintEnumerator.MoveNext() {
                    constraint := constraintEnumerator.get_Current()
                    if string.Equals(constraint.TypeParameter, simple.Name, StringComparison.Ordinal) && TryResolveConstraintMember(constraint.Constraints, member.MemberName, context, semanticModel, out entry) {
                        return true
                    }
                }
            } finally {
                constraintEnumerator.Dispose()
            }
        }

        entry = null
        return false
    }

    private static func ContainsTypeParameter(parameters: List<TypeParameter>, name: string): bool {
        parameterEnumerator := parameters.GetEnumerator()
        try {
            while parameterEnumerator.MoveNext() {
                if parameterEnumerator.get_Current().Name == name {
                    return true
                }
            }
        } finally {
            parameterEnumerator.Dispose()
        }
        return false
    }

    private func TryResolveConstraintMember(constraintReferences: List<TypeReference>, memberName: string, context: WalkContext, semanticModel: SemanticModel, out entry: FunctionEntry): bool {
        referenceEnumerator := constraintReferences.GetEnumerator()
        try {
            while referenceEnumerator.MoveNext() {
                constraintReference := referenceEnumerator.get_Current()
                constraintType: TypeInfo = null
                if !TryLookupTypeReference(semanticModel, constraintReference, out constraintType) {
                    continue
                }

                generic := constraintType as GenericTypeInfo
                if generic != null {
                    // The OPEN definition behind a constructed reference is recorded under the
                    // identity key (`IHandler``1`); the bare name is the fallback for a model that
                    // recorded it before this type was written.
                    openType: TypeInfo = null
                    if semanticModel.TypesByIdentity.TryGetValue(TypeArityNames.Key(generic.Name, generic.TypeArguments.Count), out openType) {
                        constraintType = openType
                    } else {
                        bareOpenType: TypeInfo = null
                        if semanticModel.Types.TryGetValue(generic.Name, out bareOpenType) {
                            constraintType = bareOpenType
                        }
                    }
                }

                interfaceType := constraintType as InterfaceTypeInfo
                if interfaceType == null {
                    continue
                }

                declared := FirstDeclaredFunction(interfaceType.DeclaredMembers, memberName)
                if declared != null && TryGetEntryForDeclarationSite(new SystemsAnalyzer.DeclarationSite(declared.Name, declared.ContainingType, declared.Line, declared.Column, declared.ParameterCount), context, out entry) {
                    return true
                }
            }
        } finally {
            referenceEnumerator.Dispose()
        }

        entry = null
        return false
    }

    private static func FirstDeclaredFunction(members: DeclaredMemberInfo[], memberName: string): DeclaredMemberInfo? {
        index := 0
        while index < members.Length {
            candidate := members[index]
            if candidate.Kind == DeclaredMemberKind.Function && candidate.Name == memberName {
                return candidate
            }
            index = index + 1
        }
        return null
    }

    private static func TryLookupTypeReference(semanticModel: SemanticModel, reference: TypeReference, out selectedType: TypeInfo): bool {
        selectedType = null
        if reference == null {
            return false
        }
        line := 0
        column := 0
        if reference.Span.IsValid {
            line = reference.Span.StartLine
            column = reference.Span.StartColumn
        } else {
            simple := reference as SimpleTypeReference
            if simple != null {
                line = simple.Line
                column = simple.Column
            } else {
                generic := reference as GenericTypeReference
                if generic != null {
                    line = generic.Line
                    column = generic.Column
                }
            }
        }

        if line <= 0 {
            return false
        }
        key := (Line: line, Column: column)
        return semanticModel.TypeReferenceTypes.TryGetValue(key, out selectedType)
    }

    private func WalkExpression(expression: Expression, context: WalkContext, explicitAllocation: bool = false) {
        if expression is AllocExpression {
            allocExpression := expression as AllocExpression
            WalkExpression(allocExpression.Expression, context, true)
            return
        }

        if expression is StackAllocExpression {
            stackAlloc := expression as StackAllocExpression
            WalkExpression(stackAlloc.LengthExpression, context, false)
            budget := StackallocPolicy.BudgetViolation(stackAlloc)
            if budget != null {
                context.Summary.ImplicitTrap = true
                AddFinding(budget.Code, budget.Effect, budget.Message, stackAlloc.Line, stackAlloc.Column, "stackalloc".Length, context, ErrorSeverity.Error, budget.Suggestion)
            }
            return
        }

        if expression is NewExpression {
            newExpression := expression as NewExpression
            WalkArguments(newExpression.ConstructorArguments, context)
            if newExpression.ArrayLengthExpression != null {
                WalkExpression(newExpression.ArrayLengthExpression, context, false)
            }
            if newExpression.Initializer != null {
                WalkExpression(newExpression.Initializer, context, false)
            }
            if TypePolicy.IsHeapAllocation(newExpression) {
                RecordAllocation(newExpression, context, explicitAllocation || context.InAllocZone)
            }
            return
        }

        if expression is ObjectInitializerExpression {
            initializer := expression as ObjectInitializerExpression
            WalkProperties(initializer.Properties, context)
            return
        }

        if expression is ArrayLiteralExpression {
            array := expression as ArrayLiteralExpression
            WalkExpressions(array.Elements, context)
            RecordAllocation(array, context, explicitAllocation || context.InAllocZone)
            return
        }

        if expression is InterpolatedStringExpression {
            interpolated := expression as InterpolatedStringExpression
            WalkInterpolatedHoles(interpolated.Parts, context)
            RecordAllocation(interpolated, context, explicitAllocation || context.InAllocZone)
            return
        }

        if expression is LambdaExpression {
            lambda := expression as LambdaExpression
            context.Summary.Delegate = true
            context.Summary.Closure = true
            ConstructPolicy.ReportLambda(context.Allows, lambda.Line, lambda.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
            if lambda.ExpressionBody != null {
                WalkExpression(lambda.ExpressionBody, context, false)
            }
            if lambda.BlockBody != null {
                WalkStatement(lambda.BlockBody, context)
            }
            return
        }

        if expression is CallExpression {
            WalkCall(expression as CallExpression, context)
            return
        }

        if expression is MemberAccessExpression {
            member := expression as MemberAccessExpression
            WalkExpression(member.Object, context, false)
            receiver := member.Object as IdentifierExpression
            if receiver != null && HotSummaryPolicy.ReportStaticReceiverWarmup(
                receiver.Name,
                member.MemberName,
                TypePolicy,
                CallPolicy,
                HotSummaries,
                Config.TargetFramework,
                member.Line,
                member.Column,
                context.Summary.File,
                context.Summary.Name,
                context.Summary.IsHot,
                context.Summary.IsBoundary
            ) {
                context.Summary.RequiresWarmup = true
            }
            return
        }

        if expression is IndexAccessExpression {
            index := expression as IndexAccessExpression
            WalkExpression(index.Object, context, false)
            WalkExpression(index.Index, context, false)
            if TrapPolicy.ReportIndexTrap(index, context.Guards, context.Allows, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary) {
                context.Summary.ImplicitTrap = true
            }
            return
        }

        if expression is BinaryExpression {
            binary := expression as BinaryExpression
            WalkExpression(binary.Left, context, false)
            WalkExpression(binary.Right, context, false)
            if TrapPolicy.ReportDivisionTrap(binary, context.Guards, context.Allows, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary) {
                context.Summary.ImplicitTrap = true
            }
            return
        }

        if expression is UnaryExpression {
            unary := expression as UnaryExpression
            WalkExpression(unary.Operand, context, false)
            return
        }

        if expression is MustExpression {
            mustExpression := expression as MustExpression
            WalkExpression(mustExpression.Expression, context, false)
            return
        }

        if expression is AssignmentExpression {
            assignment := expression as AssignmentExpression
            WalkExpression(assignment.Target, context, false)
            WalkExpression(assignment.Value, context, false)
            return
        }

        if expression is TernaryExpression {
            ternary := expression as TernaryExpression
            WalkExpression(ternary.Condition, context, false)
            WalkExpression(ternary.ThenExpression, context, false)
            WalkExpression(ternary.ElseExpression, context, false)
            return
        }

        if expression is CastExpression {
            castExpression := expression as CastExpression
            WalkExpression(castExpression.Expression, context, false)
            if ConstructPolicy.ReportCastToObject(castExpression.TargetType, context.Allows, castExpression.Line, castExpression.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary) {
                context.Summary.Boxes = true
            }
            return
        }

        if expression is IsExpression {
            isExpression := expression as IsExpression
            WalkExpression(isExpression.Expression, context, false)
            return
        }

        if expression is AwaitExpression {
            awaitExpression := expression as AwaitExpression
            context.Summary.Resource = true
            ConstructPolicy.ReportAwait(awaitExpression.Line, awaitExpression.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
            WalkExpression(awaitExpression.Expression, context, false)
            return
        }

        if expression is ThrowExpression {
            throwExpression := expression as ThrowExpression
            context.Summary.Throws = true
            ConstructPolicy.ReportThrow(context.Allows, throwExpression.Line, throwExpression.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
            WalkExpression(throwExpression.Expression, context, false)
            return
        }

        if expression is CheckedExpression {
            checkedExpression := expression as CheckedExpression
            WalkExpression(checkedExpression.Expression, context, false)
            if TrapPolicy.ReportCheckedTrap(context.Allows, checkedExpression.Line, checkedExpression.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary) {
                context.Summary.ImplicitTrap = true
            }
            return
        }

        if expression is UncheckedExpression {
            uncheckedExpression := expression as UncheckedExpression
            WalkExpression(uncheckedExpression.Expression, context, false)
            return
        }

        if expression is RangeExpression {
            range := expression as RangeExpression
            if range.Start != null {
                WalkExpression(range.Start, context, false)
            }
            if range.End != null {
                WalkExpression(range.End, context, false)
            }
            return
        }

        if expression is TupleExpression {
            tuple := expression as TupleExpression
            WalkTupleElements(tuple.Elements, context)
            return
        }

        if expression is MatchExpression {
            matchExpression := expression as MatchExpression
            WalkExpression(matchExpression.Value, context, false)
            WalkMatchCases(matchExpression.Cases, context)
            return
        }

        if expression is WithExpression {
            withExpression := expression as WithExpression
            WalkExpression(withExpression.Target, context, false)
            RecordAllocation(withExpression, context, explicitAllocation || context.InAllocZone)
            WalkProperties(withExpression.Properties, context)
            return
        }

        if expression is SpreadExpression {
            spread := expression as SpreadExpression
            WalkExpression(spread.Expression, context, false)
            return
        }

        if expression is ParenthesizedExpression {
            parenthesized := expression as ParenthesizedExpression
            WalkExpression(parenthesized.Inner, context, false)
            return
        }

        if expression is TypeOfExpression {
            context.Summary.Reflection = true
            ConstructPolicy.ReportTypeOf(context.Allows, expression.Line, expression.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
        }
    }

    private func WalkArguments(arguments: List<Argument>, context: WalkContext) {
        argumentEnumerator := arguments.GetEnumerator()
        try {
            while argumentEnumerator.MoveNext() {
                WalkExpression(argumentEnumerator.get_Current().Value, context, false)
            }
        } finally {
            argumentEnumerator.Dispose()
        }
    }

    private func WalkProperties(properties: List<PropertyInitializer>, context: WalkContext) {
        propertyEnumerator := properties.GetEnumerator()
        try {
            while propertyEnumerator.MoveNext() {
                property := propertyEnumerator.get_Current()
                if property.IndexExpression != null {
                    WalkExpression(property.IndexExpression, context, false)
                }
                WalkExpression(property.Value, context, false)
            }
        } finally {
            propertyEnumerator.Dispose()
        }
    }

    private func WalkExpressions(expressions: List<Expression>, context: WalkContext) {
        expressionEnumerator := expressions.GetEnumerator()
        try {
            while expressionEnumerator.MoveNext() {
                WalkExpression(expressionEnumerator.get_Current(), context, false)
            }
        } finally {
            expressionEnumerator.Dispose()
        }
    }

    private func WalkInterpolatedHoles(parts: List<InterpolatedStringPart>, context: WalkContext) {
        partEnumerator := parts.GetEnumerator()
        try {
            while partEnumerator.MoveNext() {
                hole := partEnumerator.get_Current() as InterpolatedStringHole
                if hole != null {
                    WalkExpression(hole.Expression, context, false)
                }
            }
        } finally {
            partEnumerator.Dispose()
        }
    }

    private func WalkTupleElements(elements: List<TupleElement>, context: WalkContext) {
        elementEnumerator := elements.GetEnumerator()
        try {
            while elementEnumerator.MoveNext() {
                WalkExpression(elementEnumerator.get_Current().Value, context, false)
            }
        } finally {
            elementEnumerator.Dispose()
        }
    }

    private func WalkMatchCases(cases: List<MatchCase>, context: WalkContext) {
        caseEnumerator := cases.GetEnumerator()
        try {
            while caseEnumerator.MoveNext() {
                matchCase := caseEnumerator.get_Current()
                if matchCase.Guard != null {
                    WalkExpression(matchCase.Guard, context, false)
                }
                WalkExpression(matchCase.Expression, context, false)
            }
        } finally {
            caseEnumerator.Dispose()
        }
    }

    private func WalkCall(call: CallExpression, context: WalkContext) {
        WalkArguments(call.Arguments, context)

        calleeEntry: FunctionEntry = null
        if TryResolveDeclaredCallee(call, context, out calleeEntry) {
            context.Summary.Calls.Add(calleeEntry.QualifiedName)
            callSites := context.Summary.CallSites
            callLine := call.Line
            callColumn := call.Column
            calleeFunction := calleeEntry.Function
            calleeName := calleeFunction.Name
            callLength := Math.Max(1, calleeName.Length)
            callSite := new SystemsAnalyzer.CallSite(calleeEntry, callLine, callColumn, callLength)
            callSites.Add(callSite)
            CallPolicy.MarkDeclaredCalleeDischarges(call, context.Summary.PoolRents, context.Summary.ResourceLocals)
            WalkExpression(call.Callee, context, false)
            return
        }

        target := SystemsExpressionNames.CallTarget(call.Callee)
        if target != null && !CallPolicy.IsResultFactoryTarget(target) {
            context.Summary.Calls.Add(target)
        }

        WalkExpression(call.Callee, context, false)

        if target == null {
            context.Summary.UnknownExternalCall = true
            CalleePolicy.ReportUnknownExternalCall("<dynamic call>", call.Line, call.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
            return
        }

        if CallPolicy.IsResultFactoryTarget(target) {
            return
        }

        resourceCallee := call.Callee
        resourcePoolRents := context.Summary.PoolRents
        resourceLocals := context.Summary.ResourceLocals
        disposalModel: SemanticModel = null
        selectedDisposalModel: SemanticModel? = null
        if SemanticModels.TryGetValue(context.Summary.File, out disposalModel) {
            selectedDisposalModel = disposalModel
        }
        if CallPolicy.MarkResourceDisposedIfRecognized(resourceCallee, resourcePoolRents, resourceLocals, selectedDisposalModel) {
            return
        }

        if CallPolicy.IsKnownConcurrencyPrimitive(target) {
            context.Summary.ConcurrencyPrimitive = true
            return
        }

        if CallPolicy.IsUnsupportedConcurrencyPrimitive(target) {
            context.Summary.ConcurrencyPrimitive = true
            CalleePolicy.ReportUnsupportedConcurrencyPrimitive(target, context.Allows, call.Line, call.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
            return
        }

        if CallPolicy.IsRuntimeDispatchCall(target) {
            context.Summary.Dispatch = true
            CalleePolicy.ReportRuntimeDispatch(target, context.Allows, call.Line, call.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
            return
        }

        if CallPolicy.IsPoolCall(target) {
            context.Summary.Pool = true
            poolRents := context.Summary.PoolRents
            poolReturnModel: SemanticModel = null
            selectedPoolReturnModel: SemanticModel? = null
            if SemanticModels.TryGetValue(context.Summary.File, out poolReturnModel) {
                selectedPoolReturnModel = poolReturnModel
            }
            CallPolicy.MarkPoolReturnIfRecognized(call, poolRents, selectedPoolReturnModel)
            isPoolRent := CallPolicy.IsPoolRentTarget(target)
            CalleePolicy.ReportHotPoolRent(isPoolRent, context.Allows, call.Line, call.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
            if isPoolRent && Config.Language.Systems.Warmup.Count == 0 {
                context.Summary.RequiresWarmup = true
            }
            return
        }

        if CallPolicy.IsDictionaryTryGetValueCall(call, target) {
            return
        }

        if CallPolicy.IsBufferMemoryCopyCall(target) {
            HotSummaryPolicy.ReportBufferMemoryCopy(context.InUnsafeBlock, context.Allows.IsAllowed("memorySafety"), call.Line, call.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
            return
        }

        summaryEntry: HotSummaryEntry = null
        if HotSummaries.TryResolve(target, Config.TargetFramework, out summaryEntry) {
            context.Summary.MergeEffectsFrom(HotSummaryPolicy.ApplyHotSummary(target, summaryEntry, context.Allows.IsAllowed("aot"), call.Line, call.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary, context.Summary.AllocNone))
            return
        }

        if CallPolicy.IsReflectionOrDynamicCall(target) {
            reflectionSummary := context.Summary
            reflectionSummary.Reflection = true
            existingDynamicCode := reflectionSummary.DynamicCode
            callUsesDynamicCode := CallPolicy.IsDynamicCodeCall(target)
            if existingDynamicCode || callUsesDynamicCode {
                reflectionSummary.DynamicCode = true
            } else {
                reflectionSummary.DynamicCode = false
            }
            CalleePolicy.ReportReflectionOrDynamicCall(target, context.Allows, call.Line, call.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
            return
        }

        context.Summary.UnknownExternalCall = true
        CalleePolicy.ReportUnknownExternalCall(target, call.Line, call.Column, context.Summary.File, context.Summary.Name, context.Summary.IsHot, context.Summary.IsBoundary)
    }

    private func RecordAllocation(expression: Expression, context: WalkContext, explicitAllocation: bool) {
        context.Summary.Allocates = true

        violation := SystemsAllocationPolicy.Violation(
            context.Summary.IsHot,
            context.Summary.AllocNone,
            context.Summary.IsBoundary,
            context.Allows.IsAllowed("alloc"),
            IsSystemsProfile(),
            explicitAllocation
        )
        if violation != null {
            AddFinding(
                violation.Code,
                violation.Effect,
                violation.Message,
                expression.Line,
                expression.Column,
                1,
                context,
                violation.Severity,
                violation.Suggestion
            )
        }
    }

    private func AddFinding(code: string, effect: string, message: string, line: int, column: int, length: int, context: WalkContext, preferredSeverity: ErrorSeverity, suggestion: string?) {
        AddFinding(code, effect, message, line, column, length, context.Summary, preferredSeverity, suggestion)
    }

    private func AddFinding(code: string, effect: string, message: string, line: int, column: int, length: int, summary: MutableFunctionSummary, preferredSeverity: ErrorSeverity, suggestion: string?) {
        FindingSink.AddForFunction(code, effect, message, line, column, length, summary.File, summary.Name, summary.IsHot, summary.IsBoundary, preferredSeverity, suggestion)
    }

    private func AddFinding(code: string, effect: string, message: string, line: int, column: int, length: int, summary: MutableFunctionSummary, preferredSeverity: ErrorSeverity, suggestion: string?, callPath: IReadOnlyList<string>) {
        FindingSink.Add(code, effect, message, line, column, length, summary.File, summary.Name, summary.IsHot, summary.IsBoundary, preferredSeverity, suggestion, callPath)
    }

    private static func TrustedBodyStatementCount(function: FunctionDeclaration): int {
        body := function.Body
        if body == null {
            return 0
        }
        return body.Statements.Count
    }

    private sealed class MutableFunctionSummary {
        Name: string
        File: string
        IsHot: bool
        IsBoundary: bool
        AllocNone: bool
        IsTrusted: bool
        MemorySafe: bool
        FunctionAllows: HashSet<string>
        Allocates: bool
        Boxes: bool
        Delegate: bool
        Closure: bool
        Dispatch: bool
        Reflection: bool
        DynamicCode: bool
        Throws: bool
        ImplicitTrap: bool
        UnknownExternalCall: bool
        Resource: bool
        Pool: bool
        ConcurrencyPrimitive: bool
        RequiresWarmup: bool
        HasUnsafe: bool
        Calls: List<string>
        CallSites: List<CallSite>
        StackallocLocals: HashSet<string>
        PoolRents: Dictionary<string, PoolRent>
        ResourceLocals: Dictionary<string, ResourceLocal>

        constructor(name: string, filePath: string) {
            IsHot = false
            IsBoundary = false
            AllocNone = false
            IsTrusted = false
            MemorySafe = false
            Allocates = false
            Boxes = false
            Delegate = false
            Closure = false
            Dispatch = false
            Reflection = false
            DynamicCode = false
            Throws = false
            ImplicitTrap = false
            UnknownExternalCall = false
            Resource = false
            Pool = false
            ConcurrencyPrimitive = false
            RequiresWarmup = false
            HasUnsafe = false

            FunctionAllows = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
            Calls = new List<string>()
            CallSites = new List<SystemsAnalyzer.CallSite>()
            StackallocLocals = new HashSet<string>(StringComparer.Ordinal)
            PoolRents = new Dictionary<string, PoolRent>(StringComparer.Ordinal)
            ResourceLocals = new Dictionary<string, ResourceLocal>(StringComparer.Ordinal)
            Name = name
            File = filePath
        }

        func ToFacts(): SystemsEffectFacts {
            return new SystemsEffectFacts(Allocates, Boxes, Delegate, Closure, Dispatch, Reflection, DynamicCode, Throws, ImplicitTrap, UnknownExternalCall, Resource, Pool, ConcurrencyPrimitive, RequiresWarmup, !DynamicCode && !Reflection)
        }

        func MergeEffectsFrom(other: SystemsEffectFacts) {
            Allocates = MergeEffectFlag(Allocates, other.Allocates)
            Boxes = MergeEffectFlag(Boxes, other.Boxes)
            Delegate = MergeEffectFlag(Delegate, other.ConstructsDelegate)
            Closure = MergeEffectFlag(Closure, other.CapturesClosure)
            Dispatch = MergeEffectFlag(Dispatch, other.UsesRuntimeDispatch)
            Reflection = MergeEffectFlag(Reflection, other.UsesReflection)
            DynamicCode = MergeEffectFlag(DynamicCode, other.UsesDynamicCode)
            Throws = MergeEffectFlag(Throws, other.Throws)
            ImplicitTrap = MergeEffectFlag(ImplicitTrap, other.HasImplicitTrapObligation)
            UnknownExternalCall = MergeEffectFlag(UnknownExternalCall, other.UsesUnknownExternalCall)
            Resource = MergeEffectFlag(Resource, other.UsesResource)
            Pool = MergeEffectFlag(Pool, other.UsesPool)
            ConcurrencyPrimitive = MergeEffectFlag(ConcurrencyPrimitive, other.UsesConcurrencyPrimitive)
            RequiresWarmup = MergeEffectFlag(RequiresWarmup, other.RequiresWarmup)
        }

        private static func MergeEffectFlag(existing: bool, incoming: bool): bool {
            return existing || incoming
        }
    }

    private sealed record FunctionEntry(File: string, ContainingType: string?, QualifiedName: string, Function: FunctionDeclaration) {
    }

    // N#'s positional record-struct surface does not yet carry C#'s `readonly record struct`
    // modifier. Keep this private key immutable with explicit init-only components instead. Record
    // synthesis still consumes the complete field order for its value equality and hash bodies.
    private record struct DeclarationSite {
        readonly Name: string
        readonly ContainingType: string?
        readonly Line: int
        readonly Column: int
        readonly ParameterCount: int

        public constructor(name: string, containingType: string?, line: int, column: int, parameterCount: int) {
            Name = name
            ContainingType = containingType
            Line = line
            Column = column
            ParameterCount = parameterCount
        }
    }

    private sealed record CallSite(Callee: FunctionEntry, Line: int, Column: int, Length: int) {
    }

    private sealed class WalkContext {
        private readonly GuardStack: Stack<int>
        private AllocZoneDepth: int
        private UnsafeBlockDepth: int
        Entry: FunctionEntry
        Summary: MutableFunctionSummary
        Allows: SystemsAllowStack
        Guards: List<Guard>

        constructor(entry: FunctionEntry, summary: MutableFunctionSummary) {
            GuardStack = new Stack<int>()
            AllocZoneDepth = 0
            UnsafeBlockDepth = 0
            Guards = new List<Guard>()
            Entry = entry
            Summary = summary
            Allows = new SystemsAllowStack(summary.FunctionAllows)
        }

        InAllocZone: bool => AllocZoneDepth > 0

        InUnsafeBlock: bool => UnsafeBlockDepth > 0

        func PushAllocZone() {
            AllocZoneDepth = AllocZoneDepth + 1
        }

        func PopAllocZone() {
            AllocZoneDepth = Math.Max(0, AllocZoneDepth - 1)
        }

        func PushUnsafeBlock() {
            UnsafeBlockDepth = UnsafeBlockDepth + 1
        }

        func PopUnsafeBlock() {
            UnsafeBlockDepth = Math.Max(0, UnsafeBlockDepth - 1)
        }

        func AddGuards(guards: IReadOnlyList<Guard>) {
            Guards.AddRange(guards)
        }

        func PushGuards(guards: IReadOnlyList<Guard>) {
            GuardStack.Push(Guards.Count)
            Guards.AddRange(guards)
        }

        func PopGuards() {
            if GuardStack.Count == 0 {
                return
            }

            mark := GuardStack.Pop()
            if mark < Guards.Count {
                Guards.RemoveRange(mark, Guards.Count - mark)
            }
        }
    }
}
