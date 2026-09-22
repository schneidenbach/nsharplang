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

    // THE FRIEND GRANTS THIS COMPILATION HOLDS. Built empty (a bare `new Analyzer()` with no project
    // behind it is granted nothing) and named by `LoadFromProjectConfig`, which is where the project's
    // assembly name is first known. Every owner that asks "may this compilation see that internal?"
    // shares this one instance.
    private readonly FriendGrants: InternalsVisibleToGrants
    private readonly TypeDeclarationFiles: Dictionary<string, string>
    private readonly ProjectSources: AnalyzerProjectSourceProvider
    private readonly ProjectDiscovery: AnalyzerProjectTypeDiscovery
    private readonly Diagnostics: AnalyzerDiagnosticSink
    private readonly Spans: AnalyzerDiagnosticSpans
    private readonly SyntheticCallReporter: AnalyzerSyntheticCallReporter
    private SyntheticCallWalk: AnalyzerSyntheticCallWalk
    private SyntheticCallValidator: AnalyzerSyntheticCallValidator
    private readonly ConstantExpressionFacts: AnalyzerConstantExpressionFacts
    private readonly ImportUsageCredit: AnalyzerImportUsageCredit
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
    private readonly NullabilityPostconditions: AnalyzerNullabilityPostconditions
    private readonly TerminatingCalls: AnalyzerTerminatingCalls
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

    // THE EXPRESSION WHOSE DISPATCH JUST ANSWERED, AND WHAT IT ANSWERED WITH — the two halves of an
    // expression walk that `AnalyzeExpression` returns only ONE of. `Finish` folds null flow and the
    // four value-misuse guards into the answer, and the guards read AMBIENT POSITION, so the tail's
    // result is a function of WHERE the expression was analysed as well as of what it is. Keeping the
    // DISPATCHED type is what lets the call walk's later reads of the same receiver re-run the tail
    // where they stand instead of re-walking the whole subtree — see `DriveMemberAccess`.
    private DispatchedExpression: Expression?
    private DispatchedType: TypeInfo?

    // THE RECEIVER A MEMBER-ACCESS WALK ANALYSED, published for the call walk that asked for the
    // member access. It is a SINGLE SLOT because it is read at one instant: a member access finishes
    // its own walk last, so the slot holds that member access when `AnalyzeExpression(call.Callee)`
    // returns to `AnalyzeCall`, and nothing between those two points writes it again.
    private ReceiverRelayMember: Expression?
    private ReceiverRelayNode: Expression?
    private ReceiverRelayDispatchedType: TypeInfo?

    constructor() {
        DeclarationContextFilePath = null
        WellKnownTypes = null
        Disposed = false
        DispatchedExpression = null
        DispatchedType = null
        ReceiverRelayMember = null
        ReceiverRelayNode = null
        ReceiverRelayDispatchedType = null
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

        FriendGrants = new InternalsVisibleToGrants()
        DeclarationContext.SetFriendGrants(FriendGrants)
        ExternalTypeProbe = new AnalyzerExternalTypeProbe(MlcAssemblies, UsingNamespaces, FriendGrants)
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
        ImportUsageCredit = new AnalyzerImportUsageCredit(DeclarationContext, UsingAliases)
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
        NullabilityPostconditions = new AnalyzerNullabilityPostconditions(Scopes, DeclarationContext)
        TerminatingCalls = new AnalyzerTerminatingCalls()
        SoaEscape = new AnalyzerSoaEscape(Diagnostics, Spans, Scopes, DeclarationContext)
        Conditions = new AnalyzerBooleanConditions(Diagnostics, Spans, SoaEscape)
        Throwability = new AnalyzerThrowability(Scopes, DeclarationContext, TypeSubstitution)
        ExpressionStatements = new AnalyzerExpressionStatements(
            Diagnostics,
            Spans,
            TypeResolver,
            SoaEscape,
            Throwability,
            TerminatingCalls
        )
        Ambient = new AnalyzerAmbientContext(Diagnostics, Spans, SoaEscape, DeclarationContext)
        LoopSequence = new AnalyzerLoopSequence(
            Diagnostics,
            Spans,
            Scopes,
            DeclarationContext,
            TypeResolver,
            Ambient,
            SoaEscape,
            Conditions,
            TypeSubstitution,
            TerminatingCalls
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
            ExtensionMethods,
            TerminatingCalls
        )
        AccessorBodies = new AnalyzerAccessorBodies(
            Diagnostics,
            Spans,
            TypeResolver,
            Ambient,
            SoaEscape,
            DeclarationContext
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
        StatementSequence = new AnalyzerStatementSequence(Diagnostics, Spans, TerminatingCalls)
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

        // The three name-resolution owners are built once and never rebuilt, so the import-usage
        // ledger is handed to them here. `ExtensionMethodResolution` IS rebuilt, and takes it in its
        // factory instead.
        TypeResolver.SetImportUsageCredit(ImportUsageCredit)
        IdentifierResolution.SetImportUsageCredit(ImportUsageCredit)
        MemberAccess.SetImportUsageCredit(ImportUsageCredit)
        ProjectDiscovery.SetImportUsageCredit(ImportUsageCredit)
        Diagnostics.SetImportUsageCredit(ImportUsageCredit)
        Imports.SetImportUsageCredit(ImportUsageCredit)
    }

    private func CreateAttributeValidator(): AnalyzerAttributeValidator {
        created := new AnalyzerAttributeValidator(
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
        created.SetImportUsageCredit(ImportUsageCredit)
        return created
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
            WriteTargets,
            FunctionTypeFactory,
            SyntheticCallWalk
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
        return new AnalyzerFlowNarrowing(Scopes, TypeResolver, Assignability, NullabilityPostconditions)
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
            Ambient,
            Scopes
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
            IdentifierResolution,
            DeclarationContext,
            NullabilityPostconditions,
            TerminatingCalls,
            NullFlow
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
            ConstantExpressionFacts,
            NullabilityPostconditions,
            TerminatingCalls
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
            TypeResolver,
            NullabilityPostconditions
        )
    }

    // REBUILT WHENEVER THE METADATA LOAD CONTEXT OPENS OR CLOSES, so the import-usage ledger is
    // handed to the NEW instance here rather than at the two rebuild sites: a rebuild that forgot it
    // would silently stop crediting `import System.Linq`, and NL010 would report a live import dead.
    private func CreateExtensionMethodResolution(): AnalyzerExtensionMethodResolution {
        created := new AnalyzerExtensionMethodResolution(
            TypeResolver,
            Assignability,
            DeclarationContext,
            FunctionTypeFactory,
            ClrTypeConversion,
            ExtensionMethods,
            UsingNamespaces,
            MlcAssemblies
        )
        created.SetImportUsageCredit(ImportUsageCredit)
        created.SetFriendGrants(FriendGrants)
        return created
    }

    private func CreateMemberResolution(): AnalyzerMemberResolution {
        created := new AnalyzerMemberResolution(
            FunctionTypeFactory,
            DeclarationContext,
            TypeSubstitution,
            TypeResolver,
            ClrTypeConversion,
            ExtensionMethodResolution,
            UsingNamespaces
        )
        created.SetFriendGrants(FriendGrants)
        created.SetAmbient(Ambient)
        return created
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
        DeclarationContext.SetImportUsageCredit(ImportUsageCredit, DeclarationContextFilePath)
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
        NullabilityPostconditions.BeginAnalysis()
        TerminatingCalls.BeginAnalysis()
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

        // A FRESH LEDGER PER ANALYSIS, STAMPED ON THE UNIT. The linter's two import rules read it
        // from the unit they are handed, which is the only thing they and this analysis have in
        // common; a re-analysis replaces it rather than adding to it, so a file edited to drop its
        // last use of an import reports that import dead on the very next pass.
        unit.ImportUsage = new ImportUsageFacts()
        ImportUsageCredit.BeginAnalysis(unit)

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

        // THE GATE NL010 ASKS BEFORE IT SPEAKS. Reaching here means every declaration in the file was
        // walked, so the ledger is complete; a walk that threw part-way leaves it false, and an
        // import whose use was never looked for is not an import that has been proven dead.
        analysedUsage := unit.ImportUsage
        if analysedUsage != null {
            analysedUsage.Analyzed = true
        }

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

        eventDeclaration := declaration as EventDeclaration
        if eventDeclaration != null {
            AnalyzeEventDeclaration(eventDeclaration)
            return
        }

        propertyDeclaration := declaration as PropertyDeclaration
        if propertyDeclaration != null {

            // A property's accessors and its expression body are a MEMBER body, so the receiver
            // boundary is opened around the whole walk rather than inside it: `static P: int => this.x`
            // must be told it has no `this` from the expression body as much as from a written getter.
            savedPropertyReceiver := Ambient.EnterMemberIsStatic(AnalyzerAmbientContext.ModifiersDeclareStatic(propertyDeclaration.Modifiers))
            DriveAccessorBody(AccessorBodies.BeginProperty(propertyDeclaration, Ambient.CurrentTypeName, Assignability))
            Ambient.ExitMemberIsStatic(savedPropertyReceiver)
            return
        }

        constructorDeclaration := declaration as ConstructorDeclaration
        if constructorDeclaration != null {
            DriveDeclarationWalk(DeclarationWalkers.BeginConstructor(constructorDeclaration, Assignability))
            return
        }

        indexerDeclaration := declaration as IndexerDeclaration
        if indexerDeclaration != null {
            savedIndexerReceiver := Ambient.EnterMemberIsStatic(AnalyzerAmbientContext.ModifiersDeclareStatic(indexerDeclaration.Modifiers))
            DriveAccessorBody(AccessorBodies.BeginIndexer(indexerDeclaration, Ambient.CurrentTypeName, Assignability))
            Ambient.ExitMemberIsStatic(savedIndexerReceiver)
        }
    }

    // AN EVENT'S TYPE NAMES THE HANDLER A SUBSCRIBER ATTACHES, so it has to BE a delegate: an event
    // over anything else has no `Invoke` signature to give a handler lambda, no accessor signature to
    // emit, and no `EventInfo` the CLR would accept. Reported at the event's NAME, because the name is
    // what the reader is looking at when they ask what went wrong. An UNRESOLVED type stays silent:
    // resolution has already reported it, and a second sentence about the same word is noise.
    private func AnalyzeEventDeclaration(eventDeclaration: EventDeclaration) {
        handlerType := TypeResolver.ResolveDeclaredType(eventDeclaration.Type)
        if BuiltInTypes.IsUnknown(handlerType) || AssignabilityFacts.CanBindCallableReferenceToExpectedType(handlerType) {
            return
        }

        span := Spans.GetTypeNameDiagnosticSpan(eventDeclaration.Name, eventDeclaration.Line, eventDeclaration.Column)
        written := TypeReferenceFacts.GetDisplayNameOrVoid(eventDeclaration.Type)
        Diagnostics.Report(ErrorCode.EventRequiresDelegateType, "'" + eventDeclaration.Name + "' is declared as an event, but '" + written + "' is not a delegate type", span.Line, span.Column, "An event's type is the handler a subscriber attaches, so it must be a delegate — `EventHandler`, `EventHandler<T>`, or an `Action`/`Func` shape. Drop the `event` word if you meant an ordinary field.", span.Length)
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
            DriveLoopStatement(LoopSequence.BeginForeach(foreachStatement, Assignability))
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
            Ambient.ReportYieldPlacementIfNeeded(yieldStatement.Line, yieldStatement.Column)
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
            thrownExpression := throwStatement.Expression
            if thrownExpression == null {
                // A BARE `throw` — the rethrow. There is no operand to type, so the only question is
                // placement, and `Ambient` is the one owner that knows which handler (if any) this
                // statement is standing in.
                Ambient.ReportRethrowIfNeeded(throwStatement.Line, throwStatement.Column)
                return
            }

            DriveExpressionStatement(ExpressionStatements.BeginThrow(thrownExpression, ClrTypeConversion))
            return
        }

        tryStatement := statement as TryStatement
        if tryStatement != null {
            DriveResourceStatement(ResourceStatements.BeginTry(tryStatement, ClrTypeConversion, Assignability))
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
            DrivePatternAnalysis(PatternAnalysis.BeginSwitch(switchStatement, FlowNarrowing))
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
            // The enclosing function's byref parameters travel INTO the local function's walk, so a
            // read of one inside the body is reported at the read (NL331) rather than declining the
            // whole program at emission with nowhere to point.
            savedByRefParameters := Ambient.EnterLocalFunctionByRefParameters(Ambient.CurrentFunction)
            DriveFunctionBody(FunctionBodies.BeginLocalFunction(localFunction, Ambient.CurrentTypeName, Assignability))
            Ambient.ExitLocalFunctionByRefParameters(savedByRefParameters)
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
            if kind == 4 {
                DeclareBlockLocalFunctions(step.Statements)
            }
            step = StatementSequence.NextStep(state)
        }
    }

    // WHAT A CONDITION THAT MUST HAVE HELD PROVES ABOUT THE CODE AFTER IT. `assert cond` is the only
    // caller: a failing assert throws, so the surviving flow is the condition's TRUE branch and the
    // facts belong to the ENCLOSING scope, exactly as they do for the guard clause
    // `if !cond { throw }`. The extraction is the same one every `if` uses, so `x != null`,
    // `x is T y`, `&&` chains, parentheses, `!` and a call's own `[NotNullWhen]`/`[MaybeNullWhen]`
    // postconditions all reach it without a second vocabulary.
    private func NarrowSurvivingFlow(condition: Expression?) {
        if condition == null {
            return
        }

        split := FlowNarrowing.ExtractFlowNarrowings(condition)
        if split.Then.Count == 0 {
            return
        }

        FlowNarrowing.ApplyNarrowingsToScope(split.Then)
    }

    // THE SAME NARROWING ON THE OTHER BRANCH. A `[DoesNotReturnIf(true)]` argument was FALSE on the
    // path that reached the next statement, so the surviving flow takes what the condition proved
    // when it was false.
    private func NarrowSurvivingFlowWhenFalse(condition: Expression?) {
        if condition == null {
            return
        }

        split := FlowNarrowing.ExtractFlowNarrowings(condition)
        if split.Else.Count == 0 {
            return
        }

        FlowNarrowing.ApplyNarrowingsToScope(split.Else)
    }

    // A BLOCK'S LOCAL FUNCTIONS, BOUND BEFORE ITS FIRST STATEMENT RUNS. The scope REMEMBERS that it
    // bound them, because the walk still reaches each declaration statement later and must not
    // declare the same name twice and report itself as a duplicate.
    private func DeclareBlockLocalFunctions(statements: List<Statement>?) {
        hoisted := AnalyzerLocalFunctionScope.Hoist(statements, Ambient.CurrentTypeName, FunctionTypeFactory)
        currentScope := Scopes.Peek()
        index := 0
        while index < hoisted.Count {
            entry := hoisted[index]
            currentScope.RecordHoistedLocalFunction(entry.Name)
            DeclarationPolicy.DeclareSymbol(entry.Name, entry.Signature, entry.Line, entry.Column, null, true)
            index = index + 1
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
            if kind == 9 {
                NarrowSurvivingFlow(step.Node)
            }
            if kind == 10 {
                NarrowSurvivingFlowWhenFalse(step.Node)
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
            if kind == 8 {
                Scopes.NoteLine(step.Line)
                DriveStatementSequence(StatementSequence.BeginList(step.Statements))
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
            if kind == 8 {
                // A CATCH FILTER'S TRUE-FACTS, INSTALLED INTO THE CLAUSE'S OWN SCOPE. The handler runs
                // only when the guard answered true, so it takes exactly what an `if`'s then-branch
                // takes — asked of the same extractor, so `!= null`, `is T x`, `&&` chains and a
                // call's `[NotNullWhen]` postconditions all reach it without a second vocabulary.
                NarrowSurvivingFlow(step.Node)
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

    // `nameof` NAMES SOMETHING; IT DOES NOT READ IT. The walk below is the ordinary expression walk —
    // the `nameof` answer has to know what its target resolved to, and re-implementing resolution for
    // one keyword is how a compiler ends up with two name binders that disagree. But the walk's tail
    // refuses, correctly, the shapes that are not VALUES: a bare method group ("Method 'X' must be
    // called or passed to a delegate", NL411) and a bare event. Inside `nameof` those are exactly the
    // shapes a developer means — `nameof(SimdReductions.SumInt32)` and `nameof(Changed)` are the
    // spellings that survive a rename — so the two value-side refusals step aside here, the same way
    // they step aside for a call's own callee. Nothing else is suppressed: the SoA row escape, the
    // shape rule and every resolution diagnostic the target produces are reported as before.
    private func DriveCompileTimeConstant(state: CompileTimeConstantState): TypeInfo {
        step := CompileTimeConstants.NextStep(state)
        while step != null {
            CompileTimeConstants.Supply(state, AnalyzeNameofTarget(step.Node))
            step = CompileTimeConstants.NextStep(state)
        }
        return CompileTimeConstants.Result(state)
    }

    private func AnalyzeNameofTarget(target: Expression?): TypeInfo {
        if target == null {
            return BuiltInTypes.Unknown
        }

        previousAllowUnboundCallableReference := Ambient.EnterAllowUnboundCallableReference()
        previousAllowEventReference := Ambient.EnterAllowEventReference()
        result: TypeInfo = null
        try {
            result = AnalyzeExpression(target)
        } finally {
            Ambient.ExitAllowEventReference(previousAllowEventReference)
            Ambient.ExitAllowUnboundCallableReference(previousAllowUnboundCallableReference)
        }
        return result
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
            if kind == 3 {
                PushScope(new Scope(ScopeKind.Block), step.Line, step.Column)
            }
            if kind == 4 {
                PopScope()
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

    // A MEMBER ACCESS, AND THE RECEIVER IT ANALYSED PUBLISHED FOR WHOEVER ASKS FOR IT NEXT.
    //
    // A call whose callee is a member access analyses that member access — which analyses the
    // RECEIVER — and then asks for the same receiver again, once per receiver-shaped question the
    // bind has (a receiver-style generic candidate, the reflected bind's CLR receiver, and four
    // more). Each of those repeats used to re-walk the receiver's whole subtree, so a fluent chain
    // `a.B().C().D()` — whose receiver is itself a call whose receiver is a call — analysed the
    // innermost link once per PATH through the chain: exponential in the chain's length, and a
    // 27-link chain does not terminate. The walk is published here and reused there; what is kept is
    // the DISPATCHED type, so the reader re-runs `ExpressionTail.Finish` under its own ambient
    // position and sees exactly the answer a re-analysis would have given it.
    private func DriveMemberAccess(state: MemberAccessState): TypeInfo {
        receiverNode: Expression? = null
        receiverDispatchedType: TypeInfo? = null
        step := MemberAccess.NextStep(state)
        while step != null {
            answer := AnalyzeExpression(step.Node)
            if DispatchedExpression != null && Object.ReferenceEquals(DispatchedExpression, step.Node) {
                receiverNode = step.Node
                receiverDispatchedType = DispatchedType
            }

            MemberAccess.Supply(state, answer)
            step = MemberAccess.NextStep(state)
        }

        result := MemberAccess.Result(state)
        ReceiverRelayMember = state.Member
        ReceiverRelayNode = receiverNode
        ReceiverRelayDispatchedType = receiverDispatchedType
        return result
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
                        thisExpression := expression as ThisExpression
                        baseExpression := expression as BaseExpression
                        if lambda != null {
                            result = DriveLambda(LambdaAnalysis.BeginLambda(lambda, Ambient.CurrentExpectedType, true, false))
                        } else if expression as CastExpression != null || expression as CheckedExpression != null || expression as UncheckedExpression != null || expression as TernaryExpression != null {
                            result = DriveTargetTypedOperand(TargetTypedOperands.Begin(expression, PatternReachability, FlowNarrowing))
                        } else if expression as ArrayLiteralExpression != null {
                            result = DriveArrayLiteral(ArrayLiteral.Begin(expression))
                        } else if expression as NewExpression != null {
                            result = DriveConstruction(Construction.Begin(expression))
                        } else if thisExpression != null {
                            result = AnalyzerCurrentInstanceReferences.ResolveThis(thisExpression, Scopes, Ambient, Diagnostics)
                        } else if baseExpression != null {
                            result = AnalyzerCurrentInstanceReferences.ResolveBase(baseExpression, Scopes, Ambient, DeclarationContext, Diagnostics)
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

        DispatchedExpression = expression
        DispatchedType = result
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

    // THE RECEIVER IS WALKED ONCE PER CALL, AND EVERY LATER READ OF IT IS THE TAIL ALONE.
    //
    // `receiverNode` / `receiverDispatchedType` are LOCALS rather than fields because their lifetime
    // is exactly this call's walk: a nested call analysed inside the callee gets its own pair, and
    // nothing survives the walk to be read stale. They are filled from the member-access relay the
    // instant the CALLEE answers, and every kind-16 read afterwards re-runs `ExpressionTail.Finish`
    // on the kept dispatched type instead of re-walking the receiver's subtree.
    private func AnalyzeCall(call: CallExpression): TypeInfo {
        state := CallAnalysis.BeginCall(call)
        receiverNode: Expression? = null
        receiverDispatchedType: TypeInfo? = null
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
                ReceiverRelayMember = null
                answer = AnalyzeExpression(step.Node)
                if ReceiverRelayMember != null && Object.ReferenceEquals(ReceiverRelayMember, call.Callee) {
                    receiverNode = ReceiverRelayNode
                    receiverDispatchedType = ReceiverRelayDispatchedType
                }

                ReceiverRelayMember = null
            }
            if kind == 16 {
                keptType := receiverDispatchedType
                if keptType != null && receiverNode != null && Object.ReferenceEquals(receiverNode, step.Node) {
                    answer = ExpressionTail.Finish(step.Node, keptType)
                } else {
                    answer = AnalyzeExpression(step.Node)
                }
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
                // A LAMBDA HANDLER re-enters the lambda walk with the event's delegate type as its
                // contextual target. ANY OTHER HANDLER is a delegate VALUE — `on widget.Clicked handler`
                // — and is analysed as an ordinary expression against the same expected type; the
                // assignability verdict is computed here, where its owner is, and the sentence is
                // written by the `on` walk, where the other three things `on` can say are.
                handlerLambda := step.Handler as LambdaExpression
                if handlerLambda != null {
                    handlerState := LambdaAnalysis.BeginLambda(handlerLambda, step.ExpectedType, step.ReportInferenceFailure, false)
                    handlerState.TargetsEventHandler = true
                    DriveLambda(handlerState)
                } else {
                    // The handler is analysed with the event's delegate type as its expected type and
                    // NOTHING relaxed: the slot is an ordinary delegate position, so a bare method name
                    // in it gets the same NL411 a delegate-typed parameter and a declared delegate local
                    // give it, rather than a sentence only `on` knows how to say.
                    handlerType := AnalyzeExpressionWithExpectedType(step.Handler, step.ExpectedType, false)
                    LambdaAnalysis.ReportHandlerValueMismatch(step, handlerType, step.ExpectedType != null && Assignability.IsAssignable(step.ExpectedType, handlerType))
                }
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

                // The boundary is what collected the block's `return` types, so its answer is read
                // AFTER it has closed — which is also the only point at which it is complete.
                answer = Ambient.LastInferredNestedBodyReturnType()
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
        TypeResolver.SetImportUsageCredit(ImportUsageCredit)
        IdentifierResolution.SetMetadataCollaborators(MemberResolution, WellKnownTypes)
        IdentifierResolution.SetImportUsageCredit(ImportUsageCredit)
        MemberAccess.SetMetadataCollaborators(MemberResolution, ClrTypeConversion, ExtensionMethodResolution, WellKnownTypes)
        MemberAccess.SetImportUsageCredit(ImportUsageCredit)
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

    // THE PROJECT'S OWN IDENTITY IS PART OF ITS REFERENCE SET. Which internals of a referenced
    // assembly this compilation may name depends on the name it is being compiled under, so the
    // friend grants are named here — the one point where the project config and the assembly list
    // meet — rather than being rediscovered by each owner that asks.
    func LoadFromProjectConfig(config: ProjectConfig, projectDirectory: string? = null) {
        directory := projectDirectory ?? Environment.CurrentDirectory
        FriendGrants.SetCompilingAssemblyName(CompilationReferenceResolverKernels.GetProjectAssemblyName(directory, config.Name))
        ReferenceLoadOrchestration.Load(config, directory)
    }

    func GetFriendGrants(): InternalsVisibleToGrants {
        return FriendGrants
    }

    func CreateEditorTypeCatalog(): EditorTypeCatalog {
        return MetadataLoadSurface.CreateEditorTypeCatalog(FriendGrants)
    }
}
