namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Diagnostics.CodeAnalysis
import System.IO
import System.Reflection
import System.Runtime.CompilerServices
import System.Threading
import NSharpLang.Compiler.Ast
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.Compiler.Columnar

class Analyzer: IDisposable {
    private readonly Errors: List<CompilerError>
    private readonly Scopes: AnalyzerScopeStack
    private readonly UsingNamespaces: List<string>
    private readonly UsingAliases: Dictionary<string, string>
    private readonly ImportedSymbolsByAlias: Dictionary<string, Dictionary<string, TypeInfo>>
    private readonly ImportedDeclarationsByAlias: Dictionary<string, Dictionary<string, SymbolDeclaration>>
    private readonly DeclarationContext: AnalyzerDeclarationContext
    private readonly ExtensionMethods: List<FunctionDeclaration>
    private DeclarationContextFilePath: string?
    private WellKnownTypes: AnalyzerWellKnownTypes?
    private ClrTypeConversion: AnalyzerClrTypeConversion
    private AssignabilityFacts: AnalyzerAssignabilityFacts
    private readonly MlcAssemblies: List<Assembly>
    private readonly ReferenceLoadFailures: Dictionary<string, string>
    private readonly ReferencedPackageNames: HashSet<string>
    private readonly ExternalTypeProbe: AnalyzerExternalTypeProbe
    private readonly TypeDeclarationFiles: Dictionary<string, string>
    private readonly ProjectSources: AnalyzerProjectSourceProvider
    private readonly ProjectDiscovery: AnalyzerProjectTypeDiscovery
    private readonly Diagnostics: AnalyzerDiagnosticSink
    private readonly Spans: AnalyzerDiagnosticSpans
    private readonly SyntheticCallReporter: AnalyzerSyntheticCallReporter
    private SyntheticCallWalk: AnalyzerSyntheticCallWalk
    private SyntheticCallValidator: AnalyzerSyntheticCallValidator
    private readonly ConstantExpressionFacts: AnalyzerConstantExpressionFacts
    private readonly TypeResolver: AnalyzerTypeResolver
    private readonly TypeSubstitution: AnalyzerTypeSubstitution
    private readonly StructuralAssignability: AnalyzerStructuralAssignability
    private readonly FunctionTypeFactory: AnalyzerFunctionTypeFactory
    private MemberResolution: AnalyzerMemberResolution
    private readonly ImplicitConversionGuard: AnalyzerImplicitConversionGuard
    private Assignability: AnalyzerAssignability
    private ExtensionMethodResolution: AnalyzerExtensionMethodResolution
    private OverloadScoring: AnalyzerOverloadScoring
    private ReflectionArgumentBinder: AnalyzerReflectionArgumentBinder
    private SyntheticCallBinder: AnalyzerSyntheticCallBinder
    private SemanticModel: SemanticModel
    private BindingMap: BindingMap
    private readonly CallableReferenceReportLog: AnalyzerCallableReferenceReportLog
    private ReflectionCallReporter: AnalyzerReflectionCallReporter
    private CallAnalysis: AnalyzerCallAnalysis
    private LambdaAnalysis: AnalyzerLambdaAnalysis
    private MatchExhaustiveness: AnalyzerMatchExhaustiveness
    private PatternShapes: AnalyzerPatternShapes
    private PatternReachability: AnalyzerPatternReachability
    private readonly PropertyPatternBinding: AnalyzerPropertyPatternBinding
    private PatternAnalysis: AnalyzerPatternAnalysis
    private readonly DefiniteAssignment: AnalyzerDefiniteAssignment
    private readonly NullFlow: AnalyzerNullFlow
    private FlowNarrowing: AnalyzerFlowNarrowing
    private VariableDeclaration: AnalyzerVariableDeclaration
    private readonly ExpressionStatements: AnalyzerExpressionStatements
    private readonly Ambient: AnalyzerAmbientContext
    private readonly LoopSequence: AnalyzerLoopSequence
    private readonly SoaEscape: AnalyzerSoaEscape
    private readonly Conditions: AnalyzerBooleanConditions
    private readonly Throwability: AnalyzerThrowability
    private readonly ResourceStatements: AnalyzerResourceStatements
    private readonly FunctionBodies: AnalyzerFunctionBodies
    private readonly AccessorBodies: AnalyzerAccessorBodies
    private readonly TypeDeclarations: AnalyzerTypeDeclarations
    private readonly ParameterDeclarations: AnalyzerParameterDeclarations
    private readonly DeclarationWalkers: AnalyzerDeclarationWalkers
    private readonly StatementSequence: AnalyzerStatementSequence
    private readonly LiteralExpressions: AnalyzerLiteralExpressions
    private readonly CompileTimeConstants: AnalyzerCompileTimeConstants
    private readonly PassThroughOperands: AnalyzerPassThroughOperands
    private readonly TargetTypedOperands: AnalyzerTargetTypedOperands
    private OperatorExpressions: AnalyzerOperatorExpressions
    private readonly IdentifierResolution: AnalyzerIdentifierResolution
    private readonly MemberAccess: AnalyzerMemberAccess
    private readonly IndexAccess: AnalyzerIndexAccess
    private readonly ArrayLiteral: AnalyzerArrayLiteral
    private Construction: AnalyzerConstruction
    private WriteTargets: AnalyzerWriteTargets
    private SoaDirectColumnCalls: AnalyzerSoaDirectColumnCalls
    private Assignment: AnalyzerAssignment
    private RangeExpression: AnalyzerRangeExpression
    private MatchExpression: AnalyzerMatchExpression
    private AttributeValidator: AnalyzerAttributeValidator
    private readonly Imports: AnalyzerImports
    private readonly DeclarationPolicy: AnalyzerDeclarationPolicy
    private readonly ExpressionTail: AnalyzerExpressionTail
    private readonly ReferenceLoadReport: AnalyzerReferenceLoadReport
    private readonly MetadataLoadSurface: AnalyzerMetadataLoadSurface
    private readonly ReferenceLoadOrchestration: AnalyzerReferenceLoadOrchestration
    private Disposed: bool

    constructor() {
        DeclarationContextFilePath = null
        WellKnownTypes = null
        Disposed = false
        Errors = new List<CompilerError>()
        Scopes = new AnalyzerScopeStack()
        UsingNamespaces = new List<string>()
        UsingAliases = new Dictionary<string, string>()
        ImportedSymbolsByAlias = new Dictionary<string, Dictionary<string, TypeInfo>>()
        ImportedDeclarationsByAlias = new Dictionary<string, Dictionary<string, SymbolDeclaration>>()
        DeclarationContext = new AnalyzerDeclarationContext()
        ExtensionMethods = new List<FunctionDeclaration>()
        MlcAssemblies = new List<Assembly>()
        ReferenceLoadFailures = new Dictionary<string, string>(StringComparer.Ordinal)
        ReferencedPackageNames = new HashSet<string>(StringComparer.Ordinal)
        TypeDeclarationFiles = new Dictionary<string, string>(StringComparer.Ordinal)
        ProjectSources = new AnalyzerProjectSourceProvider()
        ImplicitConversionGuard = new AnalyzerImplicitConversionGuard()
        SemanticModel = new SemanticModel()
        BindingMap = new BindingMap()
        CallableReferenceReportLog = new AnalyzerCallableReferenceReportLog()

        ExternalTypeProbe = new AnalyzerExternalTypeProbe(MlcAssemblies, UsingNamespaces)
        ProjectDiscovery = new AnalyzerProjectTypeDiscovery(
            ProjectSources,
            DeclarationContext,
            UsingNamespaces,
            TypeDeclarationFiles,
            ExternalTypeProbe
        )
        ClrTypeConversion = new AnalyzerClrTypeConversion(DeclarationContext, WellKnownTypes)
        AssignabilityFacts = new AnalyzerAssignabilityFacts(DeclarationContext, WellKnownTypes)
        Diagnostics = new AnalyzerDiagnosticSink(Errors, ProjectSources)
        Spans = new AnalyzerDiagnosticSpans(Diagnostics)
        SyntheticCallReporter = new AnalyzerSyntheticCallReporter(Diagnostics, Spans)
        TypeResolver = new AnalyzerTypeResolver(
            Scopes,
            DeclarationContext,
            ProjectDiscovery,
            ExternalTypeProbe,
            Diagnostics,
            UsingAliases,
            ImportedSymbolsByAlias,
            ImportedDeclarationsByAlias,
            SemanticModel,
            BindingMap
        )
        TypeSubstitution = new AnalyzerTypeSubstitution(Scopes, DeclarationContext, TypeResolver)
        StructuralAssignability = new AnalyzerStructuralAssignability(TypeResolver, ExternalTypeProbe)
        FunctionTypeFactory = new AnalyzerFunctionTypeFactory(DeclarationContext, TypeSubstitution)
        PropertyPatternBinding = new AnalyzerPropertyPatternBinding(
            Diagnostics,
            Spans,
            DeclarationContext,
            TypeSubstitution
        )
        DefiniteAssignment = new AnalyzerDefiniteAssignment(Diagnostics, TypeResolver)
        NullFlow = new AnalyzerNullFlow(Diagnostics, Spans, Scopes, DeclarationContext)
        SoaEscape = new AnalyzerSoaEscape(Diagnostics, Spans, Scopes, DeclarationContext)
        Conditions = new AnalyzerBooleanConditions(Diagnostics, Spans, SoaEscape)
        Throwability = new AnalyzerThrowability(Scopes, DeclarationContext, TypeSubstitution)
        ExpressionStatements = new AnalyzerExpressionStatements(
            Diagnostics,
            Spans,
            TypeResolver,
            SoaEscape,
            Throwability
        )
        Ambient = new AnalyzerAmbientContext(Diagnostics, Spans, SoaEscape)
        LoopSequence = new AnalyzerLoopSequence(
            Diagnostics,
            Spans,
            Scopes,
            DeclarationContext,
            TypeResolver,
            Ambient,
            SoaEscape,
            Conditions
        )
        ResourceStatements = new AnalyzerResourceStatements(
            Diagnostics,
            Spans,
            Scopes,
            DeclarationContext,
            TypeResolver,
            TypeSubstitution,
            Ambient,
            SoaEscape,
            Throwability
        )
        FunctionBodies = new AnalyzerFunctionBodies(
            Diagnostics,
            Spans,
            Scopes,
            DeclarationContext,
            TypeResolver,
            FunctionTypeFactory,
            Ambient,
            SoaEscape,
            DefiniteAssignment,
            ExtensionMethods
        )
        AccessorBodies = new AnalyzerAccessorBodies(
            Diagnostics,
            Spans,
            TypeResolver,
            Ambient,
            SoaEscape
        )
        TypeDeclarations = new AnalyzerTypeDeclarations(
            Diagnostics,
            Spans,
            Scopes,
            DeclarationContext,
            TypeResolver,
            FunctionTypeFactory,
            Ambient,
            SoaEscape
        )
        ParameterDeclarations = new AnalyzerParameterDeclarations(Diagnostics)
        DeclarationWalkers = new AnalyzerDeclarationWalkers(
            Diagnostics,
            Spans,
            TypeResolver,
            Ambient,
            DefiniteAssignment
        )
        StatementSequence = new AnalyzerStatementSequence(Diagnostics, Spans)
        LiteralExpressions = new AnalyzerLiteralExpressions(Ambient, DeclarationContext, SoaEscape)
        CompileTimeConstants = new AnalyzerCompileTimeConstants(
            Diagnostics,
            Spans,
            DeclarationContext,
            TypeResolver,
            Ambient,
            SoaEscape
        )
        Assignability = CreateAssignability()
        ExtensionMethodResolution = CreateExtensionMethodResolution()
        MemberResolution = CreateMemberResolution()
        OverloadScoring = CreateOverloadScoring()
        ReflectionArgumentBinder = CreateReflectionArgumentBinder()
        SyntheticCallBinder = CreateSyntheticCallBinder()
        SyntheticCallWalk = CreateSyntheticCallWalk()
        ConstantExpressionFacts = new AnalyzerConstantExpressionFacts(Scopes, DeclarationContext)
        PassThroughOperands = new AnalyzerPassThroughOperands(
            Diagnostics,
            Spans,
            SoaEscape,
            TypeResolver,
            Ambient,
            DeclarationContext,
            LoopSequence,
            ConstantExpressionFacts
        )
        TargetTypedOperands = new AnalyzerTargetTypedOperands(
            TypeResolver,
            SoaEscape,
            Ambient,
            Conditions
        )
        SyntheticCallValidator = CreateSyntheticCallValidator()
        ReflectionCallReporter = CreateReflectionCallReporter()
        MatchExhaustiveness = CreateMatchExhaustiveness()
        PatternShapes = CreatePatternShapes()
        PatternReachability = CreatePatternReachability()
        PatternAnalysis = CreatePatternAnalysis()
        FlowNarrowing = CreateFlowNarrowing()
        VariableDeclaration = CreateVariableDeclaration()
        IdentifierResolution = new AnalyzerIdentifierResolution(
            Diagnostics,
            Scopes,
            TypeResolver,
            ProjectDiscovery,
            ExternalTypeProbe,
            FunctionTypeFactory,
            Ambient,
            NullFlow,
            ExtensionMethods,
            MemberResolution,
            SemanticModel,
            BindingMap
        )
        MemberAccess = new AnalyzerMemberAccess(
            Diagnostics,
            Spans,
            Scopes,
            DeclarationContext,
            NullFlow,
            SoaEscape,
            Ambient,
            ProjectSources,
            ProjectDiscovery,
            ExternalTypeProbe,
            TypeSubstitution,
            IdentifierResolution,
            ExtensionMethods,
            UsingNamespaces,
            UsingAliases,
            ImportedSymbolsByAlias,
            ImportedDeclarationsByAlias,
            MlcAssemblies,
            MemberResolution,
            ClrTypeConversion,
            ExtensionMethodResolution,
            BindingMap
        )
        IndexAccess = new AnalyzerIndexAccess(
            Diagnostics,
            Spans,
            DeclarationContext,
            Ambient,
            NullFlow,
            SoaEscape,
            MemberAccess,
            ConstantExpressionFacts
        )
        ArrayLiteral = new AnalyzerArrayLiteral(
            Diagnostics,
            Spans,
            DeclarationContext,
            Ambient,
            SoaEscape,
            Assignability,
            AssignabilityFacts
        )
        WriteTargets = CreateWriteTargets()
        CallAnalysis = CreateCallAnalysis()
        LambdaAnalysis = CreateLambdaAnalysis()
        SoaDirectColumnCalls = CreateSoaDirectColumnCalls()
        OperatorExpressions = CreateOperatorExpressions()
        Construction = CreateConstruction()
        Assignment = CreateAssignment()
        RangeExpression = CreateRangeExpression()
        MatchExpression = CreateMatchExpression()
        AttributeValidator = CreateAttributeValidator()
        Imports = new AnalyzerImports(
            Diagnostics,
            Scopes,
            DeclarationContext,
            ProjectSources,
            ExternalTypeProbe,
            FunctionTypeFactory,
            MlcAssemblies,
            UsingNamespaces,
            UsingAliases,
            ImportedSymbolsByAlias,
            ImportedDeclarationsByAlias,
            TypeDeclarationFiles,
            ReferencedPackageNames
        )
        DeclarationPolicy = new AnalyzerDeclarationPolicy(
            Diagnostics,
            Spans,
            Scopes,
            NullFlow,
            DeclarationContext,
            TypeResolver,
            ParameterDeclarations,
            ProjectDiscovery,
            MlcAssemblies,
            UsingAliases,
            ImportedSymbolsByAlias,
            ImportedDeclarationsByAlias,
            TypeDeclarationFiles
        )
        ExpressionTail = new AnalyzerExpressionTail(
            Diagnostics,
            Spans,
            NullFlow,
            Ambient,
            SoaDirectColumnCalls,
            ReflectionCallReporter
        )
        ReferenceLoadReport = new AnalyzerReferenceLoadReport(Diagnostics, ReferenceLoadFailures)
        MetadataLoadSurface = new AnalyzerMetadataLoadSurface(MlcAssemblies, ReferenceLoadFailures)
        ReferenceLoadOrchestration = new AnalyzerReferenceLoadOrchestration(MetadataLoadSurface, ReferencedPackageNames)
    }

    private func CreateAttributeValidator(): AnalyzerAttributeValidator {
        return new AnalyzerAttributeValidator(
            Diagnostics,
            Spans,
            Scopes,
            DeclarationContext,
            ExternalTypeProbe,
            TypeResolver,
            MemberAccess,
            LiteralExpressions,
            ClrTypeConversion,
            WellKnownTypes
        )
    }

    private func CreateRangeExpression(): AnalyzerRangeExpression {
        return new AnalyzerRangeExpression(Diagnostics, Spans, Scopes, DeclarationContext, SoaEscape, Assignability)
    }

    private func CreateMatchExpression(): AnalyzerMatchExpression {
        return new AnalyzerMatchExpression(
            Diagnostics,
            Spans,
            Ambient,
            SoaEscape,
            Conditions,
            Assignability,
            MatchExhaustiveness
        )
    }

    private func CreateConstruction(): AnalyzerConstruction {
        return new AnalyzerConstruction(
            Diagnostics,
            Spans,
            Scopes,
            DeclarationContext,
            TypeResolver,
            TypeSubstitution,
            ProjectDiscovery,
            Ambient,
            SoaEscape,
            MemberAccess,
            ArrayLiteral,
            ConstantExpressionFacts,
            Assignability,
            MemberResolution,
            MatchExhaustiveness,
            ClrTypeConversion,
            WriteTargets
        )
    }

    private func CreateWriteTargets(): AnalyzerWriteTargets {
        return new AnalyzerWriteTargets(
            Diagnostics,
            Spans,
            Scopes,
            DeclarationContext,
            TypeSubstitution,
            ClrTypeConversion,
            Ambient,
            SoaEscape,
            MemberAccess,
            IndexAccess
        )
    }

    private func CreateSoaDirectColumnCalls(): AnalyzerSoaDirectColumnCalls {
        return new AnalyzerSoaDirectColumnCalls(
            Diagnostics,
            Spans,
            Scopes,
            DeclarationContext,
            ClrTypeConversion,
            SoaEscape,
            MemberAccess,
            WriteTargets
        )
    }

    private func CreateAssignment(): AnalyzerAssignment {
        return new AnalyzerAssignment(
            Diagnostics,
            Spans,
            Scopes,
            DeclarationContext,
            Ambient,
            NullFlow,
            SoaEscape,
            IdentifierResolution,
            Assignability,
            AssignabilityFacts,
            WriteTargets,
            OperatorExpressions
        )
    }

    private func CreateFlowNarrowing(): AnalyzerFlowNarrowing {
        return new AnalyzerFlowNarrowing(Scopes, TypeResolver, Assignability)
    }

    private func CreateVariableDeclaration(): AnalyzerVariableDeclaration {
        return new AnalyzerVariableDeclaration(Diagnostics, Spans, TypeResolver, Assignability, NullFlow, Scopes, DeclarationContext, SoaEscape)
    }

    private func CreateOperatorExpressions(): AnalyzerOperatorExpressions {
        return new AnalyzerOperatorExpressions(
            Diagnostics,
            Spans,
            Scopes,
            DeclarationContext,
            TypeSubstitution,
            Assignability,
            ClrTypeConversion,
            ExternalTypeProbe,
            SoaEscape,
            Ambient,
            FlowNarrowing,
            WriteTargets
        )
    }

    private func CreateMatchExhaustiveness(): AnalyzerMatchExhaustiveness {
        return new AnalyzerMatchExhaustiveness(Diagnostics, TypeSubstitution, Assignability, TypeResolver)
    }

    private func CreatePatternShapes(): AnalyzerPatternShapes {
        return new AnalyzerPatternShapes(Diagnostics, Spans, DeclarationContext, Assignability)
    }

    private func CreatePatternReachability(): AnalyzerPatternReachability {
        return new AnalyzerPatternReachability(Diagnostics, Spans, DeclarationContext, Assignability)
    }

    private func CreatePatternAnalysis(): AnalyzerPatternAnalysis {
        return new AnalyzerPatternAnalysis(
            Diagnostics,
            Spans,
            TypeResolver,
            TypeSubstitution,
            MatchExhaustiveness,
            PatternShapes,
            PatternReachability,
            PropertyPatternBinding,
            SoaEscape,
            Ambient
        )
    }

    private func CreateCallAnalysis(): AnalyzerCallAnalysis {
        return new AnalyzerCallAnalysis(
            SyntheticCallReporter,
            SyntheticCallWalk,
            SyntheticCallValidator,
            ReflectionCallReporter,
            ReflectionArgumentBinder,
            ClrTypeConversion,
            TypeSubstitution,
            Assignability,
            Diagnostics,
            Spans,
            Scopes,
            Ambient,
            WriteTargets,
            IdentifierResolution
        )
    }

    private func CreateLambdaAnalysis(): AnalyzerLambdaAnalysis {
        return new AnalyzerLambdaAnalysis(
            Diagnostics,
            Spans,
            DeclarationContext,
            TypeResolver,
            ClrTypeConversion,
            AssignabilityFacts,
            SoaEscape,
            CreateExpressionTreeValidator()
        )
    }

    private func CreateExpressionTreeValidator(): AnalyzerExpressionTreeValidator {
        return new AnalyzerExpressionTreeValidator(
            Diagnostics,
            Spans,
            Scopes,
            DeclarationContext,
            ExternalTypeProbe,
            WellKnownTypes
        )
    }

    private func CreateReflectionCallReporter(): AnalyzerReflectionCallReporter {
        return new AnalyzerReflectionCallReporter(
            Scopes,
            DeclarationContext,
            AssignabilityFacts,
            Spans,
            Diagnostics,
            CallableReferenceReportLog
        )
    }

    private func CreateSyntheticCallValidator(): AnalyzerSyntheticCallValidator {
        return new AnalyzerSyntheticCallValidator(
            DeclarationContext,
            TypeResolver,
            Assignability,
            OverloadScoring,
            SyntheticCallWalk,
            SyntheticCallReporter,
            Spans,
            Diagnostics,
            ConstantExpressionFacts
        )
    }

    private func CreateSyntheticCallBinder(): AnalyzerSyntheticCallBinder {
        return new AnalyzerSyntheticCallBinder(
            DeclarationContext,
            OverloadScoring,
            Assignability,
            ClrTypeConversion
        )
    }

    private func CreateSyntheticCallWalk(): AnalyzerSyntheticCallWalk {
        return new AnalyzerSyntheticCallWalk(
            TypeResolver,
            SyntheticCallBinder,
            SyntheticCallReporter,
            OverloadScoring,
            Assignability,
            Spans,
            Diagnostics
        )
    }

    private func CreateReflectionArgumentBinder(): AnalyzerReflectionArgumentBinder {
        return new AnalyzerReflectionArgumentBinder(
            ClrTypeConversion,
            Assignability,
            AssignabilityFacts,
            OverloadScoring,
            TypeResolver
        )
    }

    private func CreateExtensionMethodResolution(): AnalyzerExtensionMethodResolution {
        return new AnalyzerExtensionMethodResolution(
            TypeResolver,
            Assignability,
            DeclarationContext,
            FunctionTypeFactory,
            ClrTypeConversion,
            ExtensionMethods,
            UsingNamespaces,
            MlcAssemblies
        )
    }

    private func CreateMemberResolution(): AnalyzerMemberResolution {
        return new AnalyzerMemberResolution(
            FunctionTypeFactory,
            DeclarationContext,
            TypeSubstitution,
            TypeResolver,
            ClrTypeConversion,
            ExtensionMethodResolution,
            UsingNamespaces
        )
    }

    private func CreateAssignability(): AnalyzerAssignability {
        return new AnalyzerAssignability(
            DeclarationContext,
            AssignabilityFacts,
            StructuralAssignability,
            TypeSubstitution,
            ClrTypeConversion,
            ImplicitConversionGuard
        )
    }

    private func CreateOverloadScoring(): AnalyzerOverloadScoring {
        return new AnalyzerOverloadScoring(
            DeclarationContext,
            ClrTypeConversion,
            Assignability,
            TypeResolver,
            WellKnownTypes
        )
    }
    func SetProjectSourceTexts(sourceTexts: IReadOnlyDictionary<string, string>) {
        ProjectSources.ResetSourceTexts()
        entries: IEnumerable<KeyValuePair<string, string>> = sourceTexts
        enumerator := entries.GetEnumerator()
        try {
            while enumerator.MoveNext() {
                entry := enumerator.get_Current()
                ProjectSources.AddSourceText(entry.get_Key(), entry.get_Value())
            }
        } finally {
            disposable := enumerator as IDisposable
            if disposable != null {
                disposable.Dispose()
            }
        }
    }

    func GetTypeDeclarationFiles(): Dictionary<string, string> {
        source: IDictionary<string, string> = TypeDeclarationFiles
        return new Dictionary<string, string>(source)
    }

    func Analyze(unit: CompilationUnit): AnalysisResult {
        return Analyze(unit, null, null, null)
    }

    private func InitializeDeclarationContext(unit: CompilationUnit, currentFilePath: string?, projectRoot: string?) {
        contextRoot: string? = null
        if !string.IsNullOrWhiteSpace(projectRoot) {
            contextRoot = projectRoot
        } else if !string.IsNullOrWhiteSpace(currentFilePath) {
            contextRoot = Path.GetDirectoryName(Path.GetFullPath(currentFilePath))
        }
        effectiveRoot := contextRoot ?? Directory.GetCurrentDirectory()
        if !string.IsNullOrWhiteSpace(currentFilePath) {
            DeclarationContextFilePath = Path.GetFullPath(currentFilePath)
        } else {
            DeclarationContextFilePath = Path.Combine(effectiveRoot, ".nsharp-analyzer-memory.nl")
        }
        DeclarationPolicy.SetDeclarationContextFilePath(DeclarationContextFilePath)
        DeclarationContext.Reset(effectiveRoot, MlcAssemblies)
        DeclarationContext.AddCompilationUnit(DeclarationContextFilePath, unit)
        ProjectSources.AddProjectUnitsTo(DeclarationContext)
    }

    func Analyze(unit: CompilationUnit, currentFilePath: string?, projectRoot: string?, sourceCode: string? = null): AnalysisResult {
        Errors.Clear()
        Scopes.Clear()
        UsingNamespaces.Clear()
        UsingAliases.Clear()
        ImportedSymbolsByAlias.Clear()
        ImportedDeclarationsByAlias.Clear()
        ImplicitConversionGuard.Clear()
        ExtensionMethods.Clear()
        SemanticModel = new SemanticModel()
        BindingMap = new BindingMap()

        SoaEscape.BeginAnalysis()
        NullFlow.BeginAnalysis()
        Ambient.BeginAnalysis()
        ProjectSources.BeginAnalysis(projectRoot)
        Diagnostics.BeginAnalysis(currentFilePath, sourceCode)
        TypeResolver.BeginAnalysis(currentFilePath, unit, SemanticModel, BindingMap)
        IdentifierResolution.BeginAnalysis(unit, SemanticModel, BindingMap)
        MemberAccess.BeginAnalysis(unit, BindingMap)
        Imports.BeginAnalysis(SemanticModel, BindingMap)
        DeclarationPolicy.BeginAnalysis(SemanticModel, BindingMap, currentFilePath, unit)
        ExpressionTail.BeginAnalysis(SemanticModel)
        TypeDeclarationFiles.Clear()

        InitializeDeclarationContext(unit, currentFilePath, projectRoot)

        importEnumerator := unit.Imports.GetEnumerator()
        try {
            while importEnumerator.MoveNext() {
                importDirective := importEnumerator.get_Current()
                this.DriveImports(Imports.BeginNamespaceImport(
                    importDirective.Namespace,
                    importDirective.Alias,
                    importDirective.Line,
                    importDirective.Column
                ))
            }
        } finally {
            importEnumerator.Dispose()
        }

        if unit.Package != null {
            DeclarationPolicy.ValidatePackageName(unit.Package)
        }

        PushScope(new Scope(ScopeKind.Global), 1, 1)

        if unit.FileImports.Count > 0 {
            this.DriveImports(Imports.BeginFileImports(unit.FileImports))
        }

        Imports.CheckImportCollisions()

        declarationEnumerator := unit.Declarations.GetEnumerator()
        try {
            while declarationEnumerator.MoveNext() {
                declaration := declarationEnumerator.get_Current()
                classDeclaration := declaration as ClassDeclaration
                if classDeclaration != null {
                    DeclarationPolicy.DeclareType(classDeclaration.Name, NominalTypeInfoFactory.FromClassDeclaration(classDeclaration), declaration.Line, declaration.Column)
                } else {
                    structDeclaration := declaration as StructDeclaration
                    if structDeclaration != null {
                        DeclarationPolicy.DeclareType(structDeclaration.Name, NominalTypeInfoFactory.FromStructDeclaration(structDeclaration), declaration.Line, declaration.Column)
                    } else {
                        recordDeclaration := declaration as RecordDeclaration
                        if recordDeclaration != null {
                            DeclarationPolicy.DeclareType(recordDeclaration.Name, NominalTypeInfoFactory.FromRecordDeclaration(recordDeclaration), declaration.Line, declaration.Column)
                        } else {
                            soaRecordDeclaration := declaration as SoaRecordDeclaration
                            if soaRecordDeclaration != null {
                                DeclarationPolicy.DeclareType(soaRecordDeclaration.Name, SoaTypeInfoFactory.FromDeclaration(soaRecordDeclaration), declaration.Line, declaration.Column)
                            } else {
                                interfaceDeclaration := declaration as InterfaceDeclaration
                                if interfaceDeclaration != null {
                                    DeclarationPolicy.DeclareType(interfaceDeclaration.Name, NominalTypeInfoFactory.FromInterfaceDeclaration(interfaceDeclaration), declaration.Line, declaration.Column)
                                } else {
                                    unionDeclaration := declaration as UnionDeclaration
                                    if unionDeclaration != null {
                                        DeclarationPolicy.DeclareType(unionDeclaration.Name, UnionTypeInfoFactory.FromDeclaration(unionDeclaration), declaration.Line, declaration.Column)
                                    } else {
                                        enumDeclaration := declaration as EnumDeclaration
                                        if enumDeclaration != null {
                                            DeclarationPolicy.DeclareType(enumDeclaration.Name, EnumTypeInfoFactory.FromDeclaration(enumDeclaration), declaration.Line, declaration.Column)
                                        } else {
                                            aliasDeclaration := declaration as TypeAliasDeclaration
                                            if aliasDeclaration != null {
                                                DeclarationPolicy.DeclareType(aliasDeclaration.Name, new AliasTypeInfo(aliasDeclaration.Type), declaration.Line, declaration.Column)
                                            } else {
                                                newtypeDeclaration := declaration as NewtypeDeclaration
                                                if newtypeDeclaration != null {
                                                    DeclarationPolicy.DeclareType(newtypeDeclaration.Name, new NewtypeInfo(newtypeDeclaration.Name, newtypeDeclaration.UnderlyingType), declaration.Line, declaration.Column)
                                                } else {
                                                    functionDeclaration := declaration as FunctionDeclaration
                                                    if functionDeclaration != null {
                                                        functionType := FunctionTypeFactory.CreateFromDeclaration(functionDeclaration, Ambient.CurrentTypeName)
                                                        DeclarationPolicy.DeclareSymbol(functionDeclaration.Name, functionType, functionDeclaration.Line, functionDeclaration.Column, null, true)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } finally {
            declarationEnumerator.Dispose()
        }

        DeclarationWalkers.CollectTestScaffolding(unit.Declarations)

        analysisDeclarationEnumerator := unit.Declarations.GetEnumerator()
        try {
            while analysisDeclarationEnumerator.MoveNext() {
                declaration := analysisDeclarationEnumerator.get_Current()
                Scopes.NoteLine(declaration.Line)
                AnalyzeDeclaration(declaration)
            }
        } finally {
            analysisDeclarationEnumerator.Dispose()
        }

        PopScope()
        ReferenceLoadReport.Report(MetadataLoadSurface.ResolverFailures)

        return new AnalysisResult(Errors, SemanticModel, BindingMap)
    }

    private func AnalyzeDeclaration(declaration: Declaration) {
        AttributeValidator.ValidateDeclarationAttributeArguments(declaration)

        testDeclaration := declaration as TestDeclaration
        if testDeclaration != null {
            DriveDeclarationWalk(DeclarationWalkers.BeginTest(testDeclaration, Assignability))
            return
        }

        setupDeclaration := declaration as SetupDeclaration
        if setupDeclaration != null {
            DriveDeclarationWalk(DeclarationWalkers.BeginSetup(setupDeclaration, Assignability))
            return
        }

        teardownDeclaration := declaration as TeardownDeclaration
        if teardownDeclaration != null {
            DriveDeclarationWalk(DeclarationWalkers.BeginTeardown(teardownDeclaration, Assignability))
            return
        }

        functionDeclaration := declaration as FunctionDeclaration
        if functionDeclaration != null {
            DriveFunctionBody(FunctionBodies.BeginFunctionDeclaration(functionDeclaration, Ambient.CurrentTypeName, Assignability))
            return
        }

        classDeclaration := declaration as ClassDeclaration
        if classDeclaration != null {
            DriveTypeDeclaration(TypeDeclarations.BeginClass(classDeclaration, Assignability))
            return
        }

        structDeclaration := declaration as StructDeclaration
        if structDeclaration != null {
            DriveTypeDeclaration(TypeDeclarations.BeginStruct(structDeclaration, Assignability))
            return
        }

        recordDeclaration := declaration as RecordDeclaration
        if recordDeclaration != null {
            DriveTypeDeclaration(TypeDeclarations.BeginRecord(recordDeclaration, Assignability))
            return
        }

        soaRecordDeclaration := declaration as SoaRecordDeclaration
        if soaRecordDeclaration != null {
            DriveTypeDeclaration(TypeDeclarations.BeginSoaRecord(soaRecordDeclaration, Assignability))
            return
        }

        interfaceDeclaration := declaration as InterfaceDeclaration
        if interfaceDeclaration != null {
            DriveTypeDeclaration(TypeDeclarations.BeginInterface(interfaceDeclaration, Assignability))
            return
        }

        unionDeclaration := declaration as UnionDeclaration
        if unionDeclaration != null {
            DriveTypeDeclaration(TypeDeclarations.BeginUnion(unionDeclaration, Assignability))
            return
        }

        enumDeclaration := declaration as EnumDeclaration
        if enumDeclaration != null {
            DriveTypeDeclaration(TypeDeclarations.BeginEnum(enumDeclaration, Assignability))
            return
        }

        aliasDeclaration := declaration as TypeAliasDeclaration
        if aliasDeclaration != null {
            TypeResolver.ResolveDeclaredType(aliasDeclaration.Type)
            return
        }

        newtypeDeclaration := declaration as NewtypeDeclaration
        if newtypeDeclaration != null {
            TypeResolver.ResolveDeclaredType(newtypeDeclaration.UnderlyingType)
            return
        }

        fieldDeclaration := declaration as FieldDeclaration
        if fieldDeclaration != null {
            DriveTypeDeclaration(TypeDeclarations.BeginField(fieldDeclaration, Assignability))
            return
        }

        propertyDeclaration := declaration as PropertyDeclaration
        if propertyDeclaration != null {
            DriveAccessorBody(AccessorBodies.BeginProperty(propertyDeclaration, Ambient.CurrentTypeName, Assignability))
            return
        }

        constructorDeclaration := declaration as ConstructorDeclaration
        if constructorDeclaration != null {
            DriveDeclarationWalk(DeclarationWalkers.BeginConstructor(constructorDeclaration, Assignability))
            return
        }

        indexerDeclaration := declaration as IndexerDeclaration
        if indexerDeclaration != null {
            DriveAccessorBody(AccessorBodies.BeginIndexer(indexerDeclaration, Ambient.CurrentTypeName, Assignability))
        }
    }

    private func AnalyzeStatement(statement: Statement) {
        Scopes.NoteLine(statement.Line)

        expressionStatement := statement as ExpressionStatement
        if expressionStatement != null {
            DriveExpressionStatement(ExpressionStatements.BeginExpressionStatement(expressionStatement.Expression))
            return
        }

        variableDeclaration := statement as VariableDeclarationStatement
        if variableDeclaration != null {
            DriveLocalDeclaration(VariableDeclaration.Begin(variableDeclaration))
            return
        }

        tupleDeclaration := statement as TupleDeconstructionStatement
        if tupleDeclaration != null {
            DriveLocalDeclaration(VariableDeclaration.BeginTuple(tupleDeclaration))
            return
        }

        blockStatement := statement as BlockStatement
        if blockStatement != null {
            DriveStatementSequence(StatementSequence.BeginBlock(blockStatement))
            return
        }

        allocBlock := statement as AllocBlockStatement
        if allocBlock != null {
            DriveStatementSequence(StatementSequence.BeginTransparent(allocBlock.Body))
            return
        }

        allowStatement := statement as AllowStatement
        if allowStatement != null {
            DriveStatementSequence(StatementSequence.BeginTransparent(allowStatement.Body))
            return
        }

        unsafeBlock := statement as UnsafeBlockStatement
        if unsafeBlock != null {
            DriveStatementSequence(StatementSequence.BeginTransparent(unsafeBlock.Body))
            return
        }

        ifStatement := statement as IfStatement
        if ifStatement != null {
            DriveLoopStatement(LoopSequence.BeginIf(ifStatement, FlowNarrowing))
            return
        }

        forStatement := statement as ForStatement
        if forStatement != null {
            DriveLoopStatement(LoopSequence.BeginFor(forStatement, FlowNarrowing))
            return
        }

        foreachStatement := statement as ForeachStatement
        if foreachStatement != null {
            DriveLoopStatement(LoopSequence.BeginForeach(foreachStatement))
            return
        }

        awaitForeachStatement := statement as AwaitForEachStatement
        if awaitForeachStatement != null {
            DriveLoopStatement(LoopSequence.BeginAwaitForeach(awaitForeachStatement))
            return
        }

        whileStatement := statement as WhileStatement
        if whileStatement != null {
            DriveLoopStatement(LoopSequence.BeginWhile(whileStatement, FlowNarrowing))
            return
        }

        yieldStatement := statement as YieldStatement
        if yieldStatement != null {
            DriveYieldStatement(LoopSequence.BeginYield(yieldStatement, Assignability))
            return
        }

        returnStatement := statement as ReturnStatement
        if returnStatement != null {
            DriveReturnStatement(Ambient.BeginReturn(returnStatement, Assignability))
            return
        }

        if statement as BreakStatement != null {
            Ambient.ReportBreakIfNeeded(statement.Line, statement.Column)
            return
        }

        if statement as ContinueStatement != null {
            Ambient.ReportContinueIfNeeded(statement.Line, statement.Column)
            return
        }

        throwStatement := statement as ThrowStatement
        if throwStatement != null {
            DriveExpressionStatement(ExpressionStatements.BeginThrow(throwStatement.Expression, ClrTypeConversion))
            return
        }

        tryStatement := statement as TryStatement
        if tryStatement != null {
            DriveResourceStatement(ResourceStatements.BeginTry(tryStatement, ClrTypeConversion))
            return
        }

        usingStatement := statement as UsingStatement
        if usingStatement != null {
            DriveResourceStatement(ResourceStatements.BeginUsing(usingStatement, Assignability))
            return
        }

        lockStatement := statement as LockStatement
        if lockStatement != null {
            DriveResourceStatement(ResourceStatements.BeginLock(lockStatement, Ambient.CurrentClass))
            return
        }

        switchStatement := statement as SwitchStatement
        if switchStatement != null {
            DrivePatternAnalysis(PatternAnalysis.BeginSwitch(switchStatement))
            return
        }

        printStatement := statement as PrintStatement
        if printStatement != null {
            DriveExpressionStatement(ExpressionStatements.BeginPrint(printStatement.Value))
            return
        }

        offStatement := statement as OffStatement
        if offStatement != null {
            DriveExpressionStatement(ExpressionStatements.BeginOff(offStatement.Handle, typeof(NSharpLang.Runtime.NSharpEventSubscription)))
            return
        }

        assertStatement := statement as AssertStatement
        if assertStatement != null {
            DriveExpressionStatement(ExpressionStatements.BeginAssert(assertStatement))
            return
        }

        assertThrowsStatement := statement as AssertThrowsStatement
        if assertThrowsStatement != null {
            DriveExpressionStatement(ExpressionStatements.BeginAssertThrows(assertThrowsStatement, ClrTypeConversion))
            return
        }

        localFunction := statement as LocalFunctionStatement
        if localFunction != null {
            DriveFunctionBody(FunctionBodies.BeginLocalFunction(localFunction, Ambient.CurrentTypeName, Assignability))
        }
    }
    private func DriveStatementSequence(state: StatementSequenceState) {
        step := StatementSequence.NextStep(state)
        while step != null {
            kind := step.Kind
            if kind == 1 {
                AnalyzeStatement(step.Body)
            }
            if kind == 2 {
                PushScope(new Scope(ScopeKind.Block), step.Line, step.Column)
            }
            if kind == 3 {
                PopScope()
            }
            step = StatementSequence.NextStep(state)
        }
    }

    private func DriveExpressionStatement(state: ExpressionStatementState) {
        step := ExpressionStatements.NextStep(state)
        while step != null {
            answer: TypeInfo? = null
            kind := step.Kind
            if kind == 1 {
                answer = AnalyzeExpression(step.Node)
            }
            if kind == 4 {
                PushScope(new Scope(ScopeKind.Block), step.Line, step.Column)
            }
            if kind == 5 {
                DriveStatementSequence(StatementSequence.BeginList(step.Statements))
            }
            if kind == 6 {
                PopScope()
            }
            if kind == 8 {
                recorded: TypeInfo = null
                key := (Line: step.Line, Column: step.Column)
                if SemanticModel.ExpressionTypes.TryGetValue(key, out recorded) {
                    answer = recorded
                }
            }
            ExpressionStatements.Supply(state, answer)
            step = ExpressionStatements.NextStep(state)
        }
    }

    private func DriveFunctionBody(state: FunctionBodyState) {
        step := FunctionBodies.NextStep(state)
        while step != null {
            answer: TypeInfo? = null
            kind := step.Kind
            if kind == 1 {
                answer = AnalyzeExpressionWithExpectedType(step.Node, step.ExpectedType, false)
            }
            if kind == 2 {
                PushScope(new Scope(ScopeKind.Function), step.Line, step.Column)
            }
            if kind == 3 {
                DeclarationPolicy.DeclareSymbol(step.Name, step.CarriedType, step.Line, step.Column, null, true)
            }
            if kind == 4 {
                Scopes.RecordVariable(SemanticModel, step.Name, step.CarriedType)
            }
            if kind == 5 {
                DriveStatementSequence(StatementSequence.BeginList(step.Statements))
            }
            if kind == 6 {
                PopScope()
            }
            if kind == 7 {
                DriveParameterDeclarations(DeclarationPolicy.BeginParameterDeclarations(step.Parameters, step.Line, step.Column))
            }
            if kind == 8 {
                Scopes.RecordFunction(SemanticModel, step.Name, step.CarriedType)
            }
            if kind == 9 {
                AnalyzeStatement(step.Body)
            }
            FunctionBodies.Supply(state, answer)
            step = FunctionBodies.NextStep(state)
        }
    }

    private func DriveAccessorBody(state: AccessorBodyState) {
        step := AccessorBodies.NextStep(state)
        while step != null {
            answer: TypeInfo? = null
            kind := step.Kind
            if kind == 1 {
                answer = AnalyzeExpressionWithExpectedType(step.Node, step.ExpectedType, false)
            }
            if kind == 2 {
                PushScope(new Scope(ScopeKind.Function), step.Line, step.Column)
            }
            if kind == 3 {
                DeclarationPolicy.DeclareSymbol(step.Name, step.CarriedType, step.Line, step.Column, null, step.RecordsBinding)
            }
            if kind == 4 {
                Scopes.RecordVariable(SemanticModel, step.Name, step.CarriedType)
            }
            if kind == 5 {
                PopScope()
            }
            if kind == 6 {
                DriveParameterDeclarations(DeclarationPolicy.BeginParameterDeclarations(step.Parameters, step.Line, step.Column))
            }
            if kind == 7 {
                AnalyzeStatement(step.Body)
            }
            if kind == 8 {
                SemanticModel.RecordTypeMember(step.ContainingType, step.Name, step.CarriedType)
            }
            if kind == 9 {
                SemanticModel.RecordProperty(step.Name, step.CarriedType)
            }
            AccessorBodies.Supply(state, answer)
            step = AccessorBodies.NextStep(state)
        }
    }

    private func DriveTypeDeclaration(state: TypeDeclarationState) {
        step := TypeDeclarations.NextStep(state)
        while step != null {
            answer: TypeInfo? = null
            kind := step.Kind
            if kind == 1 {
                answer = AnalyzeExpression(step.Node)
            }
            if kind == 2 {
                PushScope(new Scope(step.CarriedScopeKind), step.Line, step.Column)
            }
            if kind == 3 {
                DeclarationPolicy.DeclareSymbol(step.Name, step.CarriedType, step.Line, step.Column, null, step.RecordsBinding)
            }
            if kind == 4 {
                Scopes.RecordVariable(SemanticModel, step.Name, step.CarriedType)
            }
            if kind == 5 {
                PopScope()
            }
            if kind == 6 {
                DriveParameterDeclarations(DeclarationPolicy.BeginParameterDeclarations(step.Parameters, step.Line, step.Column))
            }
            if kind == 7 {
                AnalyzeDeclaration(step.Member)
            }
            if kind == 8 {
                SemanticModel.RecordTypeMember(step.ContainingType, step.Name, step.CarriedType)
            }
            if kind == 9 {
                SemanticModel.RecordField(step.Name, step.CarriedType)
            }
            TypeDeclarations.Supply(state, answer)
            step = TypeDeclarations.NextStep(state)
        }
    }

    private func DriveDeclarationWalk(state: DeclarationWalkState) {
        step := DeclarationWalkers.NextStep(state)
        while step != null {
            answer: TypeInfo? = null
            kind := step.Kind
            if kind == 1 {
                answer = AnalyzeExpression(step.Node)
            }
            if kind == 2 {
                PushScope(new Scope(ScopeKind.Function), step.Line, step.Column)
            }
            if kind == 3 {
                DeclarationPolicy.DeclareSymbol(step.Name, step.CarriedType, step.Line, step.Column, null, true)
            }
            if kind == 4 {
                Scopes.RecordVariable(SemanticModel, step.Name, step.CarriedType)
            }
            if kind == 5 {
                DriveStatementSequence(StatementSequence.BeginList(step.Statements))
            }
            if kind == 6 {
                PopScope()
            }
            if kind == 7 {
                DriveParameterDeclarations(DeclarationPolicy.BeginParameterDeclarations(step.Parameters, step.Line, step.Column))
            }
            if kind == 8 {
                AnalyzeStatement(step.Body)
            }
            DeclarationWalkers.Supply(state, answer)
            step = DeclarationWalkers.NextStep(state)
        }
    }

    private func DriveImports(state: ImportWalkState) {
        step := Imports.NextStep(state)
        while step != null {
            kind := step.Kind
            if kind == 1 {
                assemblyNames := step.AssemblyNames
                assemblyIndex := 0
                while assemblyIndex < assemblyNames.Length {
                    MetadataLoadSurface.LoadByName(assemblyNames[assemblyIndex])
                    assemblyIndex = assemblyIndex + 1
                }
            }
            Imports.Supply(state)
            step = Imports.NextStep(state)
        }
    }

    private func DriveParameterDeclarations(state: ParameterWalkState) {
        step := DeclarationPolicy.NextStep(state)
        while step != null {
            kind := step.Kind
            if kind == 1 {
                AnalyzeExpressionWithExpectedType(step.Node, step.ExpectedType, false)
            }
            DeclarationPolicy.Supply(state)
            step = DeclarationPolicy.NextStep(state)
        }
    }

    private func DriveLocalDeclaration(state: VariableDeclarationState) {
        step := VariableDeclaration.NextStep(state)
        while step != null {
            answer: TypeInfo? = null
            kind := step.Kind
            if kind == 1 {
                previousExpectedType := Ambient.EnterExpectedType(step.ExpectedType)
                answer = AnalyzeExpression(step.Node)
                Ambient.ExitExpectedType(previousExpectedType)
            }
            if kind == 4 {
                DeclarationPolicy.DeclareSymbol(step.Name, step.CarriedType, step.Line, step.Column, step.Text, true)
            }
            if kind == 5 {
                Scopes.RecordVariable(SemanticModel, step.Name, step.CarriedType)
            }
            if kind == 6 {
                answer = AnalyzeExpression(step.Node)
            }
            VariableDeclaration.Supply(state, answer)
            step = VariableDeclaration.NextStep(state)
        }
    }

    private func DriveLoopStatement(state: LoopStatementState) {
        step := LoopSequence.NextLoopStep(state)
        while step != null {
            answer: TypeInfo? = null
            kind := step.Kind
            if kind == 1 {
                answer = AnalyzeExpression(step.Node)
            }
            if kind == 2 {
                PushScope(new Scope(ScopeKind.Block), step.Line, step.Column)
            }
            if kind == 3 {
                DeclarationPolicy.DeclareSymbol(step.Name, step.CarriedType, step.Line, step.Column, null, true)
            }
            if kind == 4 {
                Scopes.RecordVariable(SemanticModel, step.Name, step.CarriedType)
            }
            if kind == 5 {
                AnalyzeStatement(step.Body)
            }
            if kind == 6 {
                PopScope()
            }
            if kind == 7 {
                DriveExpressionStatement(ExpressionStatements.BeginForIterator(step.Node))
            }
            LoopSequence.SupplyLoop(state, answer)
            step = LoopSequence.NextLoopStep(state)
        }
    }

    private func DriveResourceStatement(state: ResourceStatementState) {
        step := ResourceStatements.NextResourceStep(state)
        while step != null {
            answer: TypeInfo? = null
            kind := step.Kind
            if kind == 1 {
                answer = AnalyzeExpression(step.Node)
            }
            if kind == 2 {
                PushScope(new Scope(ScopeKind.Block), step.Line, step.Column)
            }
            if kind == 3 {
                DeclarationPolicy.DeclareSymbol(step.Name, step.CarriedType, step.Line, step.Column, null, true)
            }
            if kind == 4 {
                Scopes.RecordVariable(SemanticModel, step.Name, step.CarriedType)
            }
            if kind == 5 {
                AnalyzeStatement(step.Body)
            }
            if kind == 6 {
                PopScope()
            }
            if kind == 7 {
                DriveLocalDeclaration(VariableDeclaration.Begin(step.Declaration))
            }
            ResourceStatements.SupplyResource(state, answer)
            step = ResourceStatements.NextResourceStep(state)
        }
    }

    private func DriveYieldStatement(state: YieldStatementState) {
        step := LoopSequence.NextStep(state)
        while step != null {
            LoopSequence.Supply(state, AnalyzeExpression(step.Node))
            step = LoopSequence.NextStep(state)
        }
    }

    private func DriveReturnStatement(state: ReturnStatementState) {
        step := Ambient.NextStep(state)
        while step != null {
            Ambient.Supply(state, AnalyzeExpression(step.Node))
            step = Ambient.NextStep(state)
        }
    }

    private func DrivePatternAnalysis(state: PatternAnalysisState) {
        step := PatternAnalysis.NextStep(state)
        while step != null {
            answer: TypeInfo? = null
            kind := step.Kind
            if kind == 1 {
                answer = AnalyzeExpression(step.Node)
            }
            if kind == 4 {
                DeclarationPolicy.DeclareSymbol(step.Name, step.CarriedType, step.Line, step.Column, null, true)
            }
            if kind == 5 {
                AnalyzePattern(step.Pattern, step.CarriedType)
            }
            if kind == 6 {
                PushScope(new Scope(ScopeKind.Block), step.Line, step.Column)
            }
            if kind == 7 {
                DriveStatementSequence(StatementSequence.BeginList(step.Statements))
            }
            if kind == 8 {
                PopScope()
            }
            PatternAnalysis.Supply(state, answer)
            step = PatternAnalysis.NextStep(state)
        }
    }

    private func AnalyzePattern(pattern: Pattern, valueType: TypeInfo) {
        DrivePatternAnalysis(PatternAnalysis.Begin(pattern, valueType))
    }
    private func DriveMatchExpression(state: MatchExpressionState): TypeInfo {
        step := MatchExpression.NextStep(state)
        while step != null {
            answer: TypeInfo? = null
            kind := step.Kind
            if kind == 1 {
                answer = AnalyzeExpression(step.Node)
            }
            if kind == 2 {
                answer = AnalyzeExpressionWithExpectedType(step.Node, step.ExpectedType, false)
            }
            if kind == 3 {
                PushScope(new Scope(ScopeKind.Block), step.Line, step.Column)
            }
            if kind == 4 {
                AnalyzePattern(step.PatternNode, step.CarriedType)
            }
            if kind == 5 {
                PopScope()
            }
            MatchExpression.Supply(state, answer)
            step = MatchExpression.NextStep(state)
        }
        return MatchExpression.Result(state)
    }

    private func DriveLiteralExpression(state: LiteralExpressionState): TypeInfo {
        step := LiteralExpressions.NextStep(state)
        while step != null {
            LiteralExpressions.Supply(state, AnalyzeExpression(step.Node))
            step = LiteralExpressions.NextStep(state)
        }
        return LiteralExpressions.Result(state)
    }

    private func DriveCompileTimeConstant(state: CompileTimeConstantState): TypeInfo {
        step := CompileTimeConstants.NextStep(state)
        while step != null {
            CompileTimeConstants.Supply(state, AnalyzeExpression(step.Node))
            step = CompileTimeConstants.NextStep(state)
        }
        return CompileTimeConstants.Result(state)
    }

    private func DrivePassThroughOperand(state: PassThroughOperandState): TypeInfo {
        step := PassThroughOperands.NextStep(state)
        while step != null {
            PassThroughOperands.Supply(state, AnalyzeExpression(step.Node))
            step = PassThroughOperands.NextStep(state)
        }
        return PassThroughOperands.Result(state)
    }

    private func DriveTargetTypedOperand(state: TargetTypedOperandState): TypeInfo {
        step := TargetTypedOperands.NextStep(state)
        while step != null {
            answer: TypeInfo? = null
            kind := step.Kind
            if kind == 1 {
                answer = AnalyzeExpression(step.Node)
            }
            if kind == 2 {
                answer = AnalyzeExpressionWithExpectedType(step.Node, step.ExpectedType, false)
            }
            TargetTypedOperands.Supply(state, answer)
            step = TargetTypedOperands.NextStep(state)
        }
        return TargetTypedOperands.Result(state)
    }

    private func DriveOperatorExpression(state: OperatorExpressionState): TypeInfo {
        step := OperatorExpressions.NextStep(state)
        while step != null {
            answer: TypeInfo? = null
            kind := step.Kind
            if kind == 1 {
                answer = AnalyzeExpression(step.Node)
            }
            if kind == 2 {
                previousSuppressFlowType := NullFlow.SuppressFlowType
                NullFlow.SetSuppressFlowType(true)
                try {
                    answer = AnalyzeExpression(step.Node)
                } finally {
                    NullFlow.SetSuppressFlowType(previousSuppressFlowType)
                }
            }
            if kind == 3 {
                PushScope(new Scope(ScopeKind.Block), step.Line, step.Column)
                FlowNarrowing.ApplyNarrowingsToScope(step.Narrowings)
                answer = AnalyzeExpression(step.Node)
                PopScope()
            }
            OperatorExpressions.Supply(state, answer)
            step = OperatorExpressions.NextStep(state)
        }
        return OperatorExpressions.Result(state)
    }

    private func DriveAssignment(state: AssignmentState): TypeInfo {
        step := Assignment.NextStep(state)
        while step != null {
            Assignment.Supply(state, AnalyzeExpression(step.Node))
            step = Assignment.NextStep(state)
        }
        return Assignment.Result(state)
    }

    private func DriveMemberAccess(state: MemberAccessState): TypeInfo {
        step := MemberAccess.NextStep(state)
        while step != null {
            MemberAccess.Supply(state, AnalyzeExpression(step.Node))
            step = MemberAccess.NextStep(state)
        }
        return MemberAccess.Result(state)
    }

    private func AnalyzeExpression(expression: Expression): TypeInfo {
        result: TypeInfo = null

        if expression as IntLiteralExpression != null || expression as FloatLiteralExpression != null || expression as CharLiteralExpression != null || expression as StringLiteralExpression != null || expression as InterpolatedStringExpression != null || expression as BoolLiteralExpression != null || expression as NullLiteralExpression != null {
            result = DriveLiteralExpression(LiteralExpressions.Begin(expression))
        } else {
            identifier := expression as IdentifierExpression
            if identifier != null {
                result = IdentifierResolution.Resolve(identifier.Name, identifier.Line, identifier.Column, false)
            } else if expression as BinaryExpression != null || expression as UnaryExpression != null {
                result = DriveOperatorExpression(OperatorExpressions.Begin(expression))
            } else if expression as ThrowExpression != null || expression as IsExpression != null || expression as SpreadExpression != null || expression as AllocExpression != null || expression as MustExpression != null || expression as StackAllocExpression != null || expression as TupleExpression != null || expression as AwaitExpression != null {
                result = DrivePassThroughOperand(PassThroughOperands.Begin(expression, PatternReachability))
            } else if expression as MemberAccessExpression != null {
                result = DriveMemberAccess(MemberAccess.Begin(expression))
            } else if expression as IndexAccessExpression != null {
                result = DriveIndexAccess(IndexAccess.Begin(expression))
            } else {
                callExpression := expression as CallExpression
                if callExpression != null {
                    result = AnalyzeCall(callExpression)
                } else if expression as AssignmentExpression != null {
                    result = DriveAssignment(Assignment.Begin(expression))
                } else {
                    subscription := expression as OnSubscriptionExpression
                    if subscription != null {
                        result = DriveOnSubscription(LambdaAnalysis.BeginOnSubscription(subscription, typeof(NSharpLang.Runtime.NSharpEventSubscription)))
                    } else {
                        lambda := expression as LambdaExpression
                        genericTypeExpression := expression as GenericTypeExpression
                        if lambda != null {
                            result = DriveLambda(LambdaAnalysis.BeginLambda(lambda, Ambient.CurrentExpectedType, true, false))
                        } else if expression as CastExpression != null || expression as CheckedExpression != null || expression as UncheckedExpression != null || expression as TernaryExpression != null {
                            result = DriveTargetTypedOperand(TargetTypedOperands.Begin(expression, PatternReachability))
                        } else if expression as ArrayLiteralExpression != null {
                            result = DriveArrayLiteral(ArrayLiteral.Begin(expression))
                        } else if expression as NewExpression != null {
                            result = DriveConstruction(Construction.Begin(expression))
                        } else if expression as ThisExpression != null {
                            result = Scopes.CurrentTypeScopeOrUnknown()
                        } else if expression as BaseExpression != null {
                            result = DeclarationContext.ResolveBaseType(Scopes.CurrentTypeScope())
                        } else if expression as MatchExpression != null {
                            result = DriveMatchExpression(MatchExpression.Begin(expression))
                        } else if genericTypeExpression != null {
                            // A CONSTRUCTED GENERIC TYPE NAMED IN EXPRESSION POSITION — `Vector<int>` in
                            // `Vector<int>.Count`. It answers the TYPE, exactly as a bare `Console`
                            // identifier answers `System.Console` through the identifier channels, so the
                            // member-access arm sees a type receiver and resolves static members against
                            // it. Resolving as a DECLARED type is what makes the unresolved-name and
                            // wrong-arity reports fire at the receiver's own position.
                            result = TypeResolver.ResolveDeclaredType(genericTypeExpression.Type)
                        } else if expression as TypeOfExpression != null || expression as NameofExpression != null || expression as SizeOfExpression != null || expression as DefaultExpression != null {
                            result = DriveCompileTimeConstant(CompileTimeConstants.Begin(expression, WellKnownTypes))
                        } else if expression as RangeExpression != null {
                            result = DriveRangeExpression(RangeExpression.Begin(expression))
                        } else if expression as WithExpression != null {
                            result = DriveConstruction(Construction.BeginWith(expression))
                        } else {
                            parenthesized := expression as ParenthesizedExpression
                            if parenthesized != null {
                                result = AnalyzeExpression(parenthesized.Inner)
                            } else {
                                result = BuiltInTypes.Unknown
                            }
                        }
                    }
                }
            }
        }

        return ExpressionTail.Finish(expression, result)
    }

    private func DriveIndexAccess(state: IndexAccessState): TypeInfo {
        step := IndexAccess.NextStep(state)
        while step != null {
            IndexAccess.Supply(state, AnalyzeExpression(step.Node))
            step = IndexAccess.NextStep(state)
        }
        return IndexAccess.Result(state)
    }

    private func DriveRangeExpression(state: RangeExpressionState): TypeInfo {
        step := RangeExpression.NextStep(state)
        while step != null {
            RangeExpression.Supply(state, AnalyzeExpression(step.Node))
            step = RangeExpression.NextStep(state)
        }
        return RangeExpression.Result(state)
    }

    private func AnalyzeCall(call: CallExpression): TypeInfo {
        state := CallAnalysis.BeginCall(call)
        step := CallAnalysis.NextCallStep(state)
        while step != null {
            answer: TypeInfo? = null
            kind := step.Kind
            handled := false
            if kind == 3 {
                NullFlow.ReportPossibleNullAccess(step.Node, step.CarriedType, step.Line, step.Column, step.Text, step.Flag)
            }
            if kind == 4 {
                // An argument's target comes from its parameter, never the enclosing call's result.
                previousArgumentTarget := Ambient.EnterExpectedType(step.CarriedType)
                try {
                    answer = AnalyzeExpressionWithExpectedType(step.Node, step.CarriedType, step.Flag)
                } finally {
                    Ambient.ExitExpectedType(previousArgumentTarget)
                }
            }
            if kind == 6 {
                answer = AnalyzeExpression(step.Node)
            }
            if kind == 7 {
                SoaEscape.ReportSoaRowEscape(step.Node, step.Text)
            }
            if kind == 8 {
                handled = SoaDirectColumnCalls.ReportDirectColumnCallIfNeeded(call, step.CarriedType)
            }
            if kind == 14 {
                SemanticModel.RecordExpressionType(call.Callee.Line, call.Callee.Column, step.CarriedType)
            }
            if kind == 15 {
                answer = DriveLambda(LambdaAnalysis.BeginLambda(step.Lambda, step.CarriedType, true, step.Flag))
            }
            CallAnalysis.SupplyCallStep(state, answer, handled)
            step = CallAnalysis.NextCallStep(state)
        }
        return state.Result
    }

    private func AnalyzeExpressionWithExpectedType(expression: Expression, expectedType: TypeInfo?, allowUnboundCallableReference: bool = false): TypeInfo {
        lambda := expression as LambdaExpression
        if lambda != null {
            return DriveLambda(LambdaAnalysis.BeginLambda(lambda, expectedType, true, false))
        }

        previousExpectedType := Ambient.EnterExpectedTypeIfProvided(expectedType)
        previousAllowUnboundCallableReference := Ambient.EnterAllowUnboundCallableReferenceIfRequested(allowUnboundCallableReference)
        result: TypeInfo = null
        try {
            result = AnalyzeExpression(expression)
        } finally {
            Ambient.ExitExpectedType(previousExpectedType)
            Ambient.ExitAllowUnboundCallableReference(previousAllowUnboundCallableReference)
        }
        return result
    }

    private func DriveOnSubscription(state: OnSubscriptionState): TypeInfo {
        step := LambdaAnalysis.NextOnStep(state)
        while step != null {
            answer: TypeInfo? = null
            kind := step.Kind
            if kind == 1 {
                previousAllow := Ambient.EnterAllowEventReference()
                try {
                    answer = AnalyzeExpression(step.Node)
                } finally {
                    Ambient.ExitAllowEventReference(previousAllow)
                }
            }
            if kind == 2 {
                DriveLambda(LambdaAnalysis.BeginLambda(step.Lambda, step.ExpectedType, step.ReportInferenceFailure, false))
            }
            LambdaAnalysis.SupplyOnStep(state, answer)
            step = LambdaAnalysis.NextOnStep(state)
        }
        return state.Result
    }

    private func DriveLambda(state: LambdaAnalysisState): FunctionTypeInfo {
        step := LambdaAnalysis.NextLambdaStep(state)
        while step != null {
            answer: TypeInfo? = null
            kind := step.Kind
            if kind == 1 {
                answer = AnalyzeExpressionWithExpectedType(step.Node, step.ExpectedType, false)
            }
            if kind == 2 {
                PushScope(new Scope(ScopeKind.Function), step.Line, step.Column)
            }
            if kind == 3 {
                DeclarationPolicy.DeclareSymbol(step.Name, step.CarriedType, step.Line, step.Column, null, true)
            }
            if kind == 4 {
                Scopes.RecordVariable(SemanticModel, step.Name, step.CarriedType)
            }
            if kind == 5 {
                bodyFrame := Ambient.EnterNestedBody(null, step.CarriedType)
                try {
                    AnalyzeStatement(step.Body)
                } finally {
                    Ambient.ExitNestedBody(bodyFrame)
                }
            }
            if kind == 6 {
                PopScope()
            }
            LambdaAnalysis.SupplyLambdaStep(state, answer)
            step = LambdaAnalysis.NextLambdaStep(state)
        }
        return state.Result
    }

    private func DriveArrayLiteral(state: ArrayLiteralState): TypeInfo {
        step := ArrayLiteral.NextStep(state)
        while step != null {
            ArrayLiteral.Supply(state, AnalyzeExpression(step.Node))
            step = ArrayLiteral.NextStep(state)
        }
        return ArrayLiteral.Result(state)
    }

    private func DriveConstruction(state: ConstructionState): TypeInfo {
        step := Construction.NextStep(state)
        while step != null {
            answer: TypeInfo? = null
            kind := step.Kind
            if kind == 1 {
                answer = AnalyzeExpression(step.Node)
            }
            if kind == 2 {
                answer = AnalyzeExpressionWithExpectedType(step.Node, step.ExpectedType, false)
            }
            Construction.Supply(state, answer)
            step = Construction.NextStep(state)
        }
        return Construction.Result(state)
    }

    private func PushScope(scope: Scope, startLine: int, startColumn: int) {
        Scopes.Push(SemanticModel, scope, startLine, startColumn)
    }

    private func PopScope() {
        Scopes.Pop(SemanticModel)
    }
    func LoadSystemAssemblies() {
        MetadataLoadSurface.Open()

        assemblyNames := AnalyzerMetadataLoadPolicy.CommonAssemblyNames()
        assemblyIndex := 0
        while assemblyIndex < assemblyNames.Length {
            MetadataLoadSurface.LoadByName(assemblyNames[assemblyIndex])
            assemblyIndex = assemblyIndex + 1
        }

        WellKnownTypes = MetadataLoadSurface.CreateWellKnownTypes()
        ClrTypeConversion = new AnalyzerClrTypeConversion(DeclarationContext, WellKnownTypes)
        AssignabilityFacts = new AnalyzerAssignabilityFacts(DeclarationContext, WellKnownTypes)
        Assignability = CreateAssignability()
        ExtensionMethodResolution = CreateExtensionMethodResolution()
        MemberResolution = CreateMemberResolution()
        OverloadScoring = CreateOverloadScoring()
        ReflectionArgumentBinder = CreateReflectionArgumentBinder()
        SyntheticCallBinder = CreateSyntheticCallBinder()
        SyntheticCallWalk = CreateSyntheticCallWalk()
        SyntheticCallValidator = CreateSyntheticCallValidator()
        ReflectionCallReporter = CreateReflectionCallReporter()
        MatchExhaustiveness = CreateMatchExhaustiveness()
        PatternShapes = CreatePatternShapes()
        PatternReachability = CreatePatternReachability()
        PatternAnalysis = CreatePatternAnalysis()
        FlowNarrowing = CreateFlowNarrowing()
        VariableDeclaration = CreateVariableDeclaration()
        WriteTargets = CreateWriteTargets()
        CallAnalysis = CreateCallAnalysis()
        LambdaAnalysis = CreateLambdaAnalysis()
        SoaDirectColumnCalls = CreateSoaDirectColumnCalls()
        OperatorExpressions = CreateOperatorExpressions()
        TypeResolver.SetWellKnownTypes(WellKnownTypes)
        IdentifierResolution.SetMetadataCollaborators(MemberResolution, WellKnownTypes)
        MemberAccess.SetMetadataCollaborators(MemberResolution, ClrTypeConversion, ExtensionMethodResolution, WellKnownTypes)
        Construction = CreateConstruction()
        Assignment = CreateAssignment()
        RangeExpression = CreateRangeExpression()
        MatchExpression = CreateMatchExpression()
        AttributeValidator = CreateAttributeValidator()
    }

    func Dispose() {
        if !Disposed {
            MetadataLoadSurface.Close()
            WellKnownTypes = null
            ClrTypeConversion = new AnalyzerClrTypeConversion(DeclarationContext, null)
            AssignabilityFacts = new AnalyzerAssignabilityFacts(DeclarationContext, null)
            Assignability = CreateAssignability()
            ExtensionMethodResolution = CreateExtensionMethodResolution()
            MemberResolution = CreateMemberResolution()
            OverloadScoring = CreateOverloadScoring()
            ReflectionArgumentBinder = CreateReflectionArgumentBinder()
            SyntheticCallBinder = CreateSyntheticCallBinder()
            SyntheticCallWalk = CreateSyntheticCallWalk()
            SyntheticCallValidator = CreateSyntheticCallValidator()
            ReflectionCallReporter = CreateReflectionCallReporter()
            MatchExhaustiveness = CreateMatchExhaustiveness()
            PatternShapes = CreatePatternShapes()
            PatternReachability = CreatePatternReachability()
            PatternAnalysis = CreatePatternAnalysis()
            FlowNarrowing = CreateFlowNarrowing()
            VariableDeclaration = CreateVariableDeclaration()
            WriteTargets = CreateWriteTargets()
            CallAnalysis = CreateCallAnalysis()
            LambdaAnalysis = CreateLambdaAnalysis()
            SoaDirectColumnCalls = CreateSoaDirectColumnCalls()
            OperatorExpressions = CreateOperatorExpressions()
            TypeResolver.SetWellKnownTypes(null)
            IdentifierResolution.SetMetadataCollaborators(MemberResolution, null)
            MemberAccess.SetMetadataCollaborators(MemberResolution, ClrTypeConversion, ExtensionMethodResolution, null)
            Construction = CreateConstruction()
            Assignment = CreateAssignment()
            RangeExpression = CreateRangeExpression()
            MatchExpression = CreateMatchExpression()
            AttributeValidator = CreateAttributeValidator()
            MlcAssemblies.Clear()
            Disposed = true
        }
    }

    func LoadFromProjectConfig(config: ProjectConfig, projectDirectory: string? = null) {
        ReferenceLoadOrchestration.Load(config, projectDirectory ?? Environment.CurrentDirectory)
    }

    func CreateEditorTypeCatalog(): EditorTypeCatalog {
        return MetadataLoadSurface.CreateEditorTypeCatalog()
    }
}
