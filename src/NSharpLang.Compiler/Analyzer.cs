using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;
using NSharpLang.Compiler.Columnar;

namespace NSharpLang.Compiler;

/// <summary>
/// Semantic analyzer for NewCLILang
/// Performs type checking, name resolution, and definite assignment analysis
/// </summary>
public class Analyzer : IDisposable
{
    private readonly List<CompilerError> _errors = new();
    private readonly AnalyzerScopeStack _scopes = new();
    private readonly List<string> _usingNamespaces = new();
    private readonly Dictionary<string, string> _usingAliases = new(); // alias -> fullName
    private readonly Dictionary<string, Dictionary<string, TypeInfo>> _importedSymbolsByAlias = new(); // alias -> (symbol -> TypeInfo)
    private readonly Dictionary<string, Dictionary<string, SymbolDeclaration>> _importedDeclarationsByAlias = new(); // alias -> (symbol -> declaration)
    private readonly AnalyzerDeclarationContext _declarationContext = new();
    private readonly List<FunctionDeclaration> _extensionMethods = new(); // Extension methods available in current compilation
    private string? _currentFilePath;
    private string? _declarationContextFilePath;
    private CompilationUnit? _compilationUnit; // Current file's AST (for namespace checks)
    private string? _sourceText;
    // MetadataLoadContext-based assembly inspection (no runtime loading, no version conflicts)
    private NSharpMetadataResolver? _metadataResolver;
    private MetadataLoadContext? _mlc;
    private AnalyzerWellKnownTypes? _wellKnownTypes;
    // Rebuilt, not mutated, whenever _wellKnownTypes changes: the owner's own fields never change
    // after construction.
    private AnalyzerClrTypeConversion _clrTypeConversion;
    private AnalyzerAssignabilityFacts _assignabilityFacts;
    private readonly List<Assembly> _mlcAssemblies = new();

    // Reference assemblies that failed to load or be inspected, keyed by identity (file path
    // or assembly name) → first failure detail. Surfaced as NL923 warnings whenever analysis
    // also produced unresolved-type errors, so a broken reference can't silently masquerade
    // as a plain "type not found".
    private readonly Dictionary<string, string> _referenceLoadFailures = new(StringComparer.Ordinal);

    private readonly HashSet<string> _referencedPackageNames = new(StringComparer.Ordinal);
    private readonly Dictionary<string, IReadOnlyDictionary<string, string>> _restoredPackageVersionsByProject = new(StringComparer.Ordinal);
    // The analyzer's external (MetadataLoadContext) type probe. Constructed once and never
    // rebuilt: it owns the resolution cache, and that cache participates in the probe ORDER.
    private readonly AnalyzerExternalTypeProbe _externalTypeProbe;
    private readonly Dictionary<string, string> _typeDeclarationFiles = new(StringComparer.Ordinal);
    // The project's sources, parsed units and declared namespaces, and the project-discovery walk
    // over them. Both are constructed once and never rebuilt: the provider's parsed-unit cache and
    // source snapshot outlive a single Analyze call.
    private readonly AnalyzerProjectSourceProvider _projectSources = new();
    private readonly AnalyzerProjectTypeDiscovery _projectDiscovery;
    // Every semantic diagnostic is constructed here, and every type reference is resolved here. The
    // sink appends to the SAME _errors list the remaining shell reports use, so report order does not
    // depend on which side of the boundary produced a diagnostic. Both are constructed once: the
    // resolver owns the per-analysis dedupe sets and the report opt-in.
    private readonly AnalyzerDiagnosticSink _diagnostics;

    // WHERE A SEMANTIC DIAGNOSTIC POINTS. Constructed over the sink so the span and the rendered
    // snippet are computed against one resolution of the analysed file's text.
    private readonly AnalyzerDiagnosticSpans _spans;

    // The source binder's placement walk plus its reporting arm, both N#-owned.
    private readonly AnalyzerSyntheticCallReporter _syntheticCallReporter;
    // Overload selection, match scoring and generic inference for a call to an N#-declared function,
    // plus the span its constraint reports anchor on. Rebuilt with the owners it reads.
    private AnalyzerSyntheticCallWalk _syntheticCallWalk;
    // Everything the analyzer SAYS about a call to an N#-declared function once the walk has chosen
    // one: arity, argument types, generic constraints, the no-matching-overload report, the SoA
    // intrinsics' value checks and the call's return type. Rebuilt with the walk it reads.
    private AnalyzerSyntheticCallValidator _syntheticCallValidator;
    // Literal and constant SHAPE — the null/default literal and the written negative constant. Reads
    // only the scope stack and the declaration context, both of which outlive every rebuild.
    private readonly AnalyzerConstantExpressionFacts _constantExpressionFacts;
    private readonly AnalyzerTypeResolver _typeResolver;
    // The substitution-aware half of the resolution surface, and the two assignability arms that
    // consult it and the metadata probe. Both are constructed once: neither reads the well-known-type
    // bag, so neither is rebuilt when that bag is built or torn down.
    private readonly AnalyzerTypeSubstitution _typeSubstitution;
    private readonly AnalyzerStructuralAssignability _structuralAssignability;
    // Every FunctionTypeInfo the analyzer builds is built by the factory; assignability is the whole
    // SCC. The factory reads no well-known types and is constructed once; the SCC holds the two
    // owners that ARE rebuilt when the bag changes, so it is rebuilt with them. The re-entrancy
    // guard for user-defined conversions is deliberately NOT part of that rebuild — it is the one
    // piece of state that must outlive an owner.
    private readonly AnalyzerFunctionTypeFactory _functionTypeFactory;
    // WHAT A MEMBER NAME RESOLVES TO ON A TYPE, whole: the dispatcher, every shape's closed member
    // set, the metadata probe and the fall-through to the extension surface. Rebuilt with the SCC —
    // it holds the CLR conversion funnel and the extension surface, both of which are.
    private AnalyzerMemberResolution _memberResolution;
    private readonly AnalyzerImplicitConversionGuard _implicitConversionGuard = new();
    private AnalyzerAssignability _assignability;
    // Which extension method a member name resolves to — the source `func`s and the external
    // `[Extension]` scan. Rebuilt with the SCC: it holds the assignability owner and the CLR
    // conversion funnel. The three collections it is handed — `_extensionMethods`,
    // `_usingNamespaces`, `_mlcAssemblies` — are `readonly` and mutated in place, so it holds the
    // LIVE lists and a rebuild does not resnapshot them.
    private AnalyzerExtensionMethodResolution _extensionMethodResolution;
    // The overload scoring kernel's collaborator-backed half. Rebuilt with the SCC: it holds the
    // conversion funnel, the assignability owner and the well-known-type bag, all three of which are.
    private AnalyzerOverloadScoring _overloadScoring;
    // The reflection binder's pure interior: which argument fills which parameter position, how well
    // the candidate matches, and the generic inference that falls out of it. Rebuilt with the SCC —
    // it holds the conversion funnel, the assignability owner, the assignability facts and the
    // scoring kernel, and all four of those are.
    private AnalyzerReflectionArgumentBinder _reflectionArgumentBinder;
    // The source binder's collaborator-backed half: the params comparison shapes, the least upper
    // bound and the generic-inference collecting walk. Rebuilt with the SCC — it holds the
    // declaration context, the scoring kernel, the assignability owner and the conversion funnel.
    private AnalyzerSyntheticCallBinder _syntheticCallBinder;
    private SemanticModel _semanticModel = new(); // Semantic model for IDE features
    private BindingMap _bindingMap = new(); // Binding map for semantic references
    // The NL411 report log. Like the implicit-conversion guard above it, this is deliberately NOT
    // part of the toolset rebuild: a log rebuilt with its reader would forget what it had already
    // said and report the same method group twice.
    private readonly AnalyzerCallableReferenceReportLog _callableReferenceReportLog = new();
    // What the analyzer says about a reflected call that bound to nothing, and about a method named
    // where a value is required. Rebuilt with the SCC — it holds the assignability facts.
    private AnalyzerReflectionCallReporter _reflectionCallReporter;
    // Everything a call expression means — the branch, the argument schedule, the receiver protocol,
    // the reporting order and the resulting type. Rebuilt with the SCC: it holds the walk, the
    // validator, the reflected-call reporter and assignability, all of which the rebuild replaces.
    private AnalyzerCallAnalysis _callAnalysis;
    // What a lambda means — the delegate door its expected type is read through, its parameters'
    // types and positions, which body shape it has and what it finally answers — and what
    // subscribing to an event with `on` means, which is a lambda site and nothing else. Rebuilt with
    // the SCC: it holds the CLR conversion and the assignability facts, both of which the rebuild
    // replaces.
    private AnalyzerLambdaAnalysis _lambdaAnalysis;
    // Whether a match covers everything its scrutinee can be, and the diagnostic when it does not.
    // Rebuilt with the SCC: it holds assignability, which the rebuild replaces.
    private AnalyzerMatchExhaustiveness _matchExhaustiveness;
    // The two pattern SHAPE questions: whether a value has a list shape (and what one element of it
    // holds), and whether a relational pattern's two sides can be compared before IL emission.
    // Rebuilt with the SCC: it holds assignability, which the rebuild replaces.
    private AnalyzerPatternShapes _patternShapes;
    // Whether a type test can ever succeed, and the two diagnostics when it cannot.
    // Rebuilt with the SCC: it holds assignability, which the rebuild replaces.
    private AnalyzerPatternReachability _patternReachability;
    // What an object pattern's property list resolves to and binds. NOT rebuilt with the SCC: it
    // holds nothing the rebuild replaces.
    private readonly AnalyzerPropertyPatternBinding _propertyPatternBinding;
    // What a pattern MEANS: which of the thirteen arms it takes, what it binds, which union case a
    // dotted name or a case pattern names, and which of its four diagnostics fires. Rebuilt with the
    // SCC: it holds the exhaustiveness, shape and reachability owners, which the rebuild replaces.
    private AnalyzerPatternAnalysis _patternAnalysis;
    // Whether a local is assigned by the time something reads it, and whether a constructor leaves a
    // non-nullable field unset. NOT rebuilt with the SCC: it holds the diagnostic sink and the type
    // resolver, neither of which the rebuild replaces.
    private readonly AnalyzerDefiniteAssignment _definiteAssignment;
    // What the analyzer believes about null at a point: the state of an expression, the default a
    // type implies, the flow type that state induces, the NL905 report and its dedup log, and the
    // ambient flow-type suppression flag. NOT rebuilt with the SCC — and the log is the reason, the
    // same one the callable-reference log carries: a log rebuilt with its reader would forget what
    // it had already said and squiggle the same dereference twice.
    private readonly AnalyzerNullFlow _nullFlow;
    // What a condition proves about the code it guards, and the writer that installs it. Rebuilt
    // with the SCC: it holds assignability, which the rebuild replaces.
    private AnalyzerFlowNarrowing _flowNarrowing;
    // What a local declaration means: the annotation, the four type outcomes, the five diagnostics,
    // the SoA escape the resulting type selects and the local's initial null state. Rebuilt with the
    // SCC: it holds assignability, which the rebuild replaces.
    private AnalyzerVariableDeclaration _variableDeclaration;
    // What an expression means where a statement belongs: the bare expression statement, the `for`
    // loop's update clause, `assert` and `assert throws` — which expressions actually do something,
    // the must-use closure, both NL313 forms and the assert-throws type report. NOT rebuilt with the
    // SCC: it holds only the diagnostic sink, the span reader and the type resolver, none of which
    // the rebuild replaces.
    private readonly AnalyzerExpressionStatements _expressionStatements;
    // WHERE THE WALK CURRENTLY IS: the enclosing function's declaration, return type, omitted-return
    // and async flags, and the control-flow context — whether a loop is open, how deep inside
    // `finally` handlers the walk sits, and the depths at which the innermost `break` and `continue`
    // targets were entered — plus every report that is a pure function of those: `break`/`continue`
    // outside a loop, all three NL319 shapes, and the four return-value-mismatch wordings. NOT
    // rebuilt with the SCC: it holds only the diagnostic sink and the span reader, neither of which
    // the rebuild replaces.
    private readonly AnalyzerAmbientContext _ambient;
    // WHAT A LOOP IS: all four loop statements — `foreach`, `await foreach`, `while` and `for` — as
    // one suspendable walk, plus the element type they and a generator's `yield` all ask for, the
    // shape normaliser every structural question starts from, the loop collection mismatch report,
    // and the `yield` statement itself. NOT rebuilt with the SCC: it holds the diagnostic sink, the
    // span reader, the scope stack, the declaration context, the type resolver, the ambient context,
    // the SoA escape owner and the boolean-condition owner, none of which the rebuild replaces; the
    // flow-narrowing writer, which the rebuild DOES replace, is passed in at `Begin`.
    private readonly AnalyzerLoopSequence _loopSequence;
    // WHAT A STRUCT-OF-ARRAYS VALUE MAY NOT DO: the row-view escape report in both its told and its
    // asked shapes, the direct-column escape report, the syntactic probe that decides what a column
    // read is, and the analysis-lifetime registry of column reads the member walk has resolved. NOT
    // rebuilt with the SCC: it holds the diagnostic sink, the span reader, the scope stack and the
    // declaration context, none of which the rebuild replaces.
    private readonly AnalyzerSoaEscape _soaEscape;
    // WHAT IT MEANS FOR A CONDITION TO BE A CONDITION: the whole boolean gate the `if`, `while`,
    // `for`, ternary and match-guard arms each ran by hand — both SoA escape reports, the boolean
    // test, the two suppressions, and all three report shapes. NOT rebuilt with the SCC: it holds the
    // diagnostic sink, the span reader and the SoA escape owner, none of which the rebuild replaces;
    // the guard's assignability oracle is passed in at the call for exactly that reason.
    private readonly AnalyzerBooleanConditions _conditions;
    // WHAT IT MEANS FOR A TYPE TO BE THROWABLE: the whole `System.Exception` predicate the `throw`,
    // `assert throws` and `catch` questions shared. NOT rebuilt with the SCC: it holds the scope
    // stack, the declaration context and the type substitution engine, none of which the rebuild
    // replaces; the CLR conversion funnel, which the rebuild DOES replace, is passed in at the call.
    private readonly AnalyzerThrowability _throwability;
    // WHAT A GUARDED REGION IS: `try`, `using` and `lock` as one suspendable walk — the catch
    // clauses and their scopes, the `finally` depth, both `using` resource forms and the
    // disposability question, and the whole NL320 lockee gate. NOT rebuilt with the SCC: the two
    // collaborators the rebuild DOES replace — the CLR conversion funnel and the assignability
    // oracle — are passed in at `Begin`.
    private readonly AnalyzerResourceStatements _resourceStatements;
    // WHAT A DECLARED FUNCTION'S BODY IS: the local function statement AND the top-level `func`
    // declaration as one suspendable walk in two forms — the name declared into the enclosing scope,
    // the operator rules, extension-method tracking, the naming convention, the function scope, the
    // type parameters and their constraints, the parameter declarations, the ambient boundary, both
    // body shapes, the missing-return rule and the expression body's return-type rule — plus the two
    // generator reports every declared function shares. NOT rebuilt with the SCC: it holds the
    // diagnostic sink, the span reader, the scope stack, the declaration context, the type resolver,
    // the function-type factory, the ambient context, the SoA escape owner, the definite-assignment
    // owner and the live extension-method list, none of which the rebuild replaces; the assignability
    // oracle, which the rebuild DOES replace, is passed in at `Begin`.
    private readonly AnalyzerFunctionBodies _functionBodies;
    // WHAT A PROPERTY'S AND AN INDEXER'S ACCESSORS MEAN, as one suspendable walk in two forms: the
    // property's entry, the indexer's entry, and the accessor PAIR they share, where each accessor
    // opens a function scope of its own, enters the accessor return-type boundary, declares the
    // indexer's parameters and the setter's implicit `value`, walks its block through the statement
    // dispatch, and closes both again. NOT rebuilt with the SCC: it holds the diagnostic sink, the
    // span reader, the type resolver, the ambient context and the SoA escape owner, none of which the
    // rebuild replaces; the assignability oracle, which it DOES replace, is passed in at `Begin`.
    private readonly AnalyzerAccessorBodies _accessorBodies;
    // WHAT A TYPE DECLARATION MEANS, as one suspendable walk in EIGHT forms: the class, struct,
    // record, interface, union, enum, `soa record` and field declarations — the naming convention
    // every one of them is held to, the ambient type context four of them enter, the scope five of
    // them open, the type parameters, the generic-static rule, the bases, the nested types, `this`,
    // the primary-constructor list, the class's forward-reference pass, the member walk, the union's
    // case rules, the enum's member rules, the SoA column rules and the whole of what a field is. NOT
    // rebuilt with the SCC: it holds the diagnostic sink, the span reader, the scope stack, the
    // declaration context, the type resolver, the function-type factory, the ambient context and the
    // SoA escape owner, none of which the rebuild replaces; the assignability oracle, which the
    // rebuild DOES replace, is passed in at `Begin`.
    private readonly AnalyzerTypeDeclarations _typeDeclarations;
    // WHAT A DECLARED PARAMETER LIST MUST SATISFY: both `params` rules, shared by every declaration
    // in the language that has a parameter list. NOT rebuilt with the SCC: it holds only the
    // diagnostic sink, which the rebuild does not replace.
    private readonly AnalyzerParameterDeclarations _parameterDeclarations;
    // WHAT A TEST, A `setup`, A `teardown` AND A CONSTRUCTOR MEAN: the four declaration forms whose
    // bodies are walked under a function scope the declaration itself fills. It also owns the file's
    // test scaffolding — at most one `setup`, at most one `teardown`, and the symbols the first
    // `setup` leaves behind for every test in the file. NOT rebuilt with the SCC, and it must not be:
    // it HOLDS those setup symbols across the whole analysis, and it holds only the diagnostic sink,
    // the span reader, the type resolver, the ambient context and the definite-assignment checker,
    // none of which the rebuild replaces. The assignability oracle, which the rebuild DOES replace,
    // is passed in at `Begin`.
    private readonly AnalyzerDeclarationWalkers _declarationWalkers;
    // WHAT A SEQUENCE OF STATEMENTS MEANS: the unreachable-code rule, the block statement's own
    // scope, and the transparency of `alloc`, `allow` and `unsafe`. NOT rebuilt with the SCC: it
    // holds only the diagnostic sink and the span reader, neither of which the rebuild replaces.
    private readonly AnalyzerStatementSequence _statementSequence;
    // WHAT A LITERAL MEANS: all seven literal forms of the expression walk — `int`, `float`, `char`,
    // `string`, interpolated string, `bool` and `null` — as one walk that ANSWERS a type. Six forms
    // answer without a step; the interpolated string suspends once per hole and resumes with that
    // hole's type, which is the operand of its row-escape report. NOT rebuilt with the SCC: it holds
    // the ambient context, the declaration context and the SoA escape owner, none of which the
    // rebuild replaces.
    private readonly AnalyzerLiteralExpressions _literalExpressions;
    // WHAT THE COMPILER KNOWS ABOUT A TYPE WITHOUT EVALUATING ANYTHING: `typeof`, `sizeof`, `nameof`
    // and `default`, as one walk that ANSWERS a type. Three forms answer without a step; `nameof`
    // suspends once and resumes with its target's type, which is the operand of its row-escape
    // report. NOT rebuilt with the SCC: it holds the sink, the span reader, the declaration context,
    // the type resolver, the ambient context and the SoA escape owner, none of which the rebuild
    // replaces — the well-known-type bag, which the rebuild DOES replace, is passed per walk instead.
    private readonly AnalyzerCompileTimeConstants _compileTimeConstants;
    // WHAT AN OPERATOR THAT HANDS ITS OPERAND THROUGH MEANS: `throw`, `is`, `spread`, `alloc`,
    // `must`, `stackalloc`, a tuple and `await`, as one walk that ANSWERS a type. Every form suspends
    // — seven exactly once, a tuple once per element — and every one of them consumes the answer,
    // because the operand IS the question. NOT rebuilt with the SCC: it holds the sink, the span
    // reader, the SoA escape owner, the type resolver, the ambient context, the declaration context,
    // the loop-sequence shape normaliser and the constant facts, none of which the rebuild replaces —
    // the pattern reachability checker, which the rebuild DOES replace, is passed per walk instead.
    private readonly AnalyzerPassThroughOperands _passThroughOperands;
    // WHAT AN EXPRESSION THAT CHOOSES THE TYPE ITS OPERANDS ARE WALKED UNDER MEANS: a cast, `checked`,
    // `unchecked` and a ternary, as one walk that ANSWERS a type. Each of them decides from the node
    // alone what expected type each operand is analysed against — a cast its own target behind the
    // hard-`default`/`new()` door test, the two wrappers the type already in force, a ternary `bool`
    // for its condition and its own expected type for both arms. NOT rebuilt with the SCC: it holds
    // the type resolver, the SoA escape owner, the ambient context and the condition reporter, none of
    // which the rebuild replaces.
    private readonly AnalyzerTargetTypedOperands _targetTypedOperands;
    // What every operator means: both arms of the expression walk that apply one, the numeric
    // promotion tables under them, the comparison and equality domains, operator-overload resolution
    // on both the declaration and the runtime side, and the seventeen reports the two arms raise.
    // Rebuilt with the SCC: it holds assignability, the CLR type conversion and the flow-narrowing
    // extractor, all three of which the rebuild replaces.
    private AnalyzerOperatorExpressions _operatorExpressions;
    // WHAT A BARE NAME MEANS: the identifier arm as a RULE rather than a walk — the six ordered
    // resolution channels, the four codes they raise, and the callee-position form the call arm asks
    // for. NOT rebuilt with the SCC: the two collaborators the rebuild DOES replace — member
    // resolution and the well-known-type bag — arrive through `SetMetadataCollaborators`, because the
    // rule holds the unverified-result dedupe set and rebuilding would drop it mid-analysis.
    private readonly AnalyzerIdentifierResolution _identifierResolution;
    // WHAT A MEMBER ACCESS MEANS: the `member` arm's whole walk — the import-alias form, the
    // qualified-external-type form, the nullable `HasValue`/`Value` fork, the four SoA refusals, the
    // visibility and binding records, and the rule for WHETHER a name that did not resolve is worth
    // reporting. It also publishes the receiver classification (`IsStaticMemberAccessTarget`,
    // `TryResolveTypeValuedMemberAccess`, `TryGetQualifiedExpressionTreeName`) and the
    // null-conditional result wrap, which the write-target classifiers, the array arm, the
    // expression-tree probe and the index arm ask for. NOT rebuilt with the SCC: the four
    // collaborators the rebuild DOES replace arrive through `SetMetadataCollaborators`, because the
    // owner carries the per-analysis compilation unit and binding map and a rebuild would drop them.
    private readonly AnalyzerMemberAccess _memberAccess;

    // What `a[i]` and `[a, b, c]` mean. Both are constructed AFTER the member-access owner because
    // the index arm asks it for the null-conditional result wrap; neither is rebuilt with the
    // metadata load context, because neither holds a metadata collaborator — the index arm reflects
    // only on types it is handed, and the array arm's collection-target predicates are pure.
    private readonly AnalyzerIndexAccess _indexAccess;
    private readonly AnalyzerArrayLiteral _arrayLiteral;
    // What `new T(a) { M: v }` and `t with { M: v }` mean: the constructed type including the
    // target-typed and union-case forms, the constructor-argument and sized-array-length operands,
    // and the object-initializer rule both forms share — which member a named entry writes, what its
    // declared type is under the receiver's substitution, and the assignability gate that is the ONLY
    // guard between a mismatched closed-generic initializer value and a type-confused read at run
    // time. Rebuilt with the SCC: it holds assignability, member resolution, match exhaustiveness and
    // the CLR type conversion, all four of which the rebuild replaces, and it carries no per-analysis
    // state — the compilation unit its union lookup needs is published by the member-access owner.
    private AnalyzerConstruction _construction;
    // WHAT MAY BE WRITTEN THROUGH: the shared rule the assignment arm, the increment arm and the
    // `ref`/`out` argument path all consult — the null-conditional, SoA-table-member, built-in-indexed,
    // read-only-property and readonly-field refusals, the capture-table shape question, and the
    // instance-field classification underneath both addressability rules. Rebuilt with the SCC: it
    // holds the CLR type conversion, which the rebuild replaces.
    private AnalyzerWriteTargets _writeTargets;
    // WHAT MAY BE DONE TO A SoA COLUMN BY A CALL: the four direct-column gates in their fixed order —
    // the mutating whole-array call, the unsupported static `Array` call and its two parameter tables,
    // the instance `Array` method taken as a call or as a value, and the ordinary receiver/argument
    // escape — plus the `System.Array` receiver question all of them share. Rebuilt with the SCC: it
    // holds the CLR type conversion, the member-access owner and the write-target family, all of which
    // the rebuild replaces.
    private AnalyzerSoaDirectColumnCalls _soaDirectColumnCalls;
    // WHAT AN ASSIGNMENT MEANS: the `assignment` arm's whole walk — the discard form, the four-part
    // target bracket, the eight ordered gates, the assignability front door in both renderings and the
    // compound form's operator question. Rebuilt with the SCC: it holds assignability and the operator
    // family, both of which the rebuild replaces.
    private AnalyzerAssignment _assignment;
    // WHAT A RANGE EXPRESSION MEANS: the `range` arm's whole walk — which endpoints are walked at all,
    // the two escape refusals on each, what an `int`-or-`System.Index` bound is, and the `System.Range`
    // it always answers. Rebuilt with the SCC: it holds assignability, which the rebuild replaces.
    private AnalyzerRangeExpression _rangeExpression;
    // WHAT A `match` EXPRESSION MEANS: the `match` arm's whole walk — the cleared-slot value walk, the
    // per-arm scope, the pattern binding, the guard's boolean question, the arm join and its one report,
    // and when exhaustiveness is asked. Rebuilt with the SCC: it holds assignability and match
    // exhaustiveness, both of which the rebuild replaces.
    private AnalyzerMatchExpression _matchExpression;
    // WHAT AN ATTRIBUTE MEANS: every question a written attribute raises on any declaration or
    // parameter that can carry one — which arguments are compile-time constants and of what kind,
    // which CLR type each constant has, which type the attribute NAME resolves to and whether it is
    // an attribute at all, which constructor accepts the positional arguments, and which named
    // argument is settable and with what type. Rebuilt with the SCC: it holds the CLR type
    // conversion and the well-known-type bag, both of which the rebuild replaces.
    private AnalyzerAttributeValidator _attributeValidator;
    // WHAT AN `import` MEANS, in both of the language's forms: which file a written path names, whether
    // it is a cycle, what an imported file exports and where each exported name lands; and for a
    // namespace import, whether the spelling names a namespace at all, whether it is a type written
    // where a namespace belongs, and where in the line the squiggle points. It also owns the
    // imported-symbol references and the collision report they feed, and the external
    // namespace-existence cache. NOT rebuilt with the SCC: everything it holds is constructed once,
    // and the two per-analysis collections it owns must survive the whole analysis — they are reset
    // through its own `BeginAnalysis`, from the same reset block. It is the one owner in the arc with
    // a driver that asks for an EFFECT: the assemblies a namespace import implies are loaded through
    // the MetadataLoadContext, which is task 021's surface and stays here.
    private readonly AnalyzerImports _imports;
    // WHAT IT MEANS TO DECLARE SOMETHING: a symbol (including the overload merge and the shadowing
    // ban), a type (including its canonical identity), a parameter with a default value, and a
    // package name. NOT rebuilt with the SCC — everything it holds is constructed once; the semantic
    // model, the binding map and the current file arrive through its own `BeginAnalysis`, and the
    // declaration-context path through its own setter, because that is established later.
    private readonly AnalyzerDeclarationPolicy _declarationPolicy;
    // WHAT HAPPENS TO EVERY EXPRESSION'S TYPE once the dispatch has computed it: null flow, the two
    // semantic-model records, and the four ordered guards that decide whether the value may be used
    // as a value at all. NOT rebuilt with the SCC; the semantic model arrives at `BeginAnalysis`.
    private readonly AnalyzerExpressionTail _expressionTail;
    // WHEN A FAILED REFERENCE LOAD IS WORTH REPORTING: only when the analysis also failed to resolve
    // a type. Holds the analyzer's own failure table by reference because the assembly-loading
    // surface writes into it throughout; the resolver's table arrives at the call because the
    // resolver is replaced when the load context is rebuilt.
    private readonly AnalyzerReferenceLoadReport _referenceLoadReport;
    private bool _disposed;

    public Analyzer()
    {
        _externalTypeProbe = new AnalyzerExternalTypeProbe(_mlcAssemblies, _usingNamespaces);
        _projectDiscovery = new AnalyzerProjectTypeDiscovery(
            _projectSources, _declarationContext, _usingNamespaces, _typeDeclarationFiles);
        _clrTypeConversion = new AnalyzerClrTypeConversion(_declarationContext, _wellKnownTypes);
        _assignabilityFacts = new AnalyzerAssignabilityFacts(_declarationContext, _wellKnownTypes);
        _diagnostics = new AnalyzerDiagnosticSink(_errors, _projectSources);
        _spans = new AnalyzerDiagnosticSpans(_diagnostics);
        _syntheticCallReporter = new AnalyzerSyntheticCallReporter(_diagnostics, _spans);
        _typeResolver = new AnalyzerTypeResolver(
            _scopes,
            _declarationContext,
            _projectDiscovery,
            _externalTypeProbe,
            _diagnostics,
            _usingAliases,
            _importedSymbolsByAlias,
            _importedDeclarationsByAlias,
            _semanticModel,
            _bindingMap);
        _typeSubstitution = new AnalyzerTypeSubstitution(_scopes, _declarationContext, _typeResolver);
        _structuralAssignability = new AnalyzerStructuralAssignability(_typeResolver, _externalTypeProbe);
        _functionTypeFactory = new AnalyzerFunctionTypeFactory(_declarationContext, _typeSubstitution);
        _propertyPatternBinding = new AnalyzerPropertyPatternBinding(
            _diagnostics, _spans, _declarationContext, _typeSubstitution);
        _definiteAssignment = new AnalyzerDefiniteAssignment(_diagnostics, _typeResolver);
        _nullFlow = new AnalyzerNullFlow(_diagnostics, _spans, _scopes, _declarationContext);
        _soaEscape = new AnalyzerSoaEscape(_diagnostics, _spans, _scopes, _declarationContext);
        _conditions = new AnalyzerBooleanConditions(_diagnostics, _spans, _soaEscape);
        _throwability = new AnalyzerThrowability(_scopes, _declarationContext, _typeSubstitution);
        _expressionStatements = new AnalyzerExpressionStatements(
            _diagnostics, _spans, _typeResolver, _soaEscape, _throwability);
        _ambient = new AnalyzerAmbientContext(_diagnostics, _spans, _soaEscape);
        _loopSequence = new AnalyzerLoopSequence(
            _diagnostics, _spans, _scopes, _declarationContext, _typeResolver, _ambient, _soaEscape,
            _conditions);
        _resourceStatements = new AnalyzerResourceStatements(
            _diagnostics, _spans, _scopes, _declarationContext, _typeResolver, _typeSubstitution,
            _ambient, _soaEscape, _throwability);
        _functionBodies = new AnalyzerFunctionBodies(
            _diagnostics, _spans, _scopes, _declarationContext, _typeResolver, _functionTypeFactory,
            _ambient, _soaEscape, _definiteAssignment, _extensionMethods);
        _accessorBodies = new AnalyzerAccessorBodies(
            _diagnostics, _spans, _typeResolver, _ambient, _soaEscape);
        _typeDeclarations = new AnalyzerTypeDeclarations(
            _diagnostics, _spans, _scopes, _declarationContext, _typeResolver, _functionTypeFactory,
            _ambient, _soaEscape);
        _parameterDeclarations = new AnalyzerParameterDeclarations(_diagnostics);
        _declarationWalkers = new AnalyzerDeclarationWalkers(
            _diagnostics, _spans, _typeResolver, _ambient, _definiteAssignment);
        _statementSequence = new AnalyzerStatementSequence(_diagnostics, _spans);
        _literalExpressions = new AnalyzerLiteralExpressions(_ambient, _declarationContext, _soaEscape);
        _compileTimeConstants = new AnalyzerCompileTimeConstants(
            _diagnostics, _spans, _declarationContext, _typeResolver, _ambient, _soaEscape);
        _assignability = CreateAssignability();
        _extensionMethodResolution = CreateExtensionMethodResolution();
        _memberResolution = CreateMemberResolution();
        _overloadScoring = CreateOverloadScoring();
        _reflectionArgumentBinder = CreateReflectionArgumentBinder();
        _syntheticCallBinder = CreateSyntheticCallBinder();
        _syntheticCallWalk = CreateSyntheticCallWalk();
        _constantExpressionFacts = new AnalyzerConstantExpressionFacts(_scopes, _declarationContext);
        _passThroughOperands = new AnalyzerPassThroughOperands(
            _diagnostics, _spans, _soaEscape, _typeResolver, _ambient, _declarationContext,
            _loopSequence, _constantExpressionFacts);
        _targetTypedOperands = new AnalyzerTargetTypedOperands(
            _typeResolver, _soaEscape, _ambient, _conditions);
        _syntheticCallValidator = CreateSyntheticCallValidator();
        _reflectionCallReporter = CreateReflectionCallReporter();
        _matchExhaustiveness = CreateMatchExhaustiveness();
        _patternShapes = CreatePatternShapes();
        _patternReachability = CreatePatternReachability();
        _patternAnalysis = CreatePatternAnalysis();
        _flowNarrowing = CreateFlowNarrowing();
        _variableDeclaration = CreateVariableDeclaration();
        _identifierResolution = new AnalyzerIdentifierResolution(
            _diagnostics, _scopes, _typeResolver, _projectDiscovery, _externalTypeProbe,
            _functionTypeFactory, _ambient, _nullFlow, _extensionMethods, _memberResolution,
            _semanticModel, _bindingMap);
        _memberAccess = new AnalyzerMemberAccess(
            _diagnostics, _spans, _scopes, _declarationContext, _nullFlow, _soaEscape, _ambient,
            _projectSources, _projectDiscovery, _externalTypeProbe, _typeSubstitution,
            _identifierResolution, _extensionMethods, _usingNamespaces, _usingAliases,
            _importedSymbolsByAlias, _importedDeclarationsByAlias, _mlcAssemblies,
            _memberResolution, _clrTypeConversion, _extensionMethodResolution, _bindingMap);
        _indexAccess = new AnalyzerIndexAccess(
            _diagnostics, _spans, _declarationContext, _ambient, _nullFlow, _soaEscape,
            _memberAccess, _constantExpressionFacts);
        _arrayLiteral = new AnalyzerArrayLiteral(
            _diagnostics, _spans, _declarationContext, _ambient, _soaEscape, _assignability,
            _assignabilityFacts);
        _writeTargets = CreateWriteTargets();
        _callAnalysis = CreateCallAnalysis();
        _lambdaAnalysis = CreateLambdaAnalysis();
        _soaDirectColumnCalls = CreateSoaDirectColumnCalls();
        _operatorExpressions = CreateOperatorExpressions();
        _construction = CreateConstruction();
        _assignment = CreateAssignment();
        _rangeExpression = CreateRangeExpression();
        _matchExpression = CreateMatchExpression();
        _attributeValidator = CreateAttributeValidator();
        _imports = new AnalyzerImports(
            _diagnostics, _scopes, _declarationContext, _projectSources, _externalTypeProbe,
            _functionTypeFactory, _mlcAssemblies, _usingNamespaces, _usingAliases,
            _importedSymbolsByAlias, _importedDeclarationsByAlias, _typeDeclarationFiles,
            _referencedPackageNames);
        _declarationPolicy = new AnalyzerDeclarationPolicy(
            _diagnostics, _spans, _scopes, _nullFlow, _declarationContext, _typeResolver,
            _parameterDeclarations, _projectDiscovery, _mlcAssemblies, _usingAliases,
            _importedSymbolsByAlias, _importedDeclarationsByAlias, _typeDeclarationFiles);
        _expressionTail = new AnalyzerExpressionTail(
            _diagnostics, _spans, _nullFlow, _ambient, _soaDirectColumnCalls, _reflectionCallReporter);
        _referenceLoadReport = new AnalyzerReferenceLoadReport(_diagnostics, _referenceLoadFailures);
    }

    private AnalyzerAttributeValidator CreateAttributeValidator()
        => new(
            _diagnostics, _spans, _scopes, _declarationContext, _externalTypeProbe, _typeResolver,
            _memberAccess, _literalExpressions, _clrTypeConversion, _wellKnownTypes);

    private AnalyzerRangeExpression CreateRangeExpression()
        => new(_diagnostics, _spans, _scopes, _declarationContext, _soaEscape, _assignability);

    private AnalyzerMatchExpression CreateMatchExpression()
        => new(
            _diagnostics, _spans, _ambient, _soaEscape, _conditions, _assignability,
            _matchExhaustiveness);

    private AnalyzerConstruction CreateConstruction()
        => new(
            _diagnostics, _spans, _scopes, _declarationContext, _typeResolver, _typeSubstitution,
            _projectDiscovery, _ambient, _soaEscape, _memberAccess, _arrayLiteral,
            _constantExpressionFacts, _assignability, _memberResolution, _matchExhaustiveness,
            _clrTypeConversion, _writeTargets);

    private AnalyzerWriteTargets CreateWriteTargets()
        => new(
            _diagnostics, _spans, _scopes, _declarationContext, _typeSubstitution, _clrTypeConversion,
            _ambient, _soaEscape, _memberAccess, _indexAccess);

    private AnalyzerSoaDirectColumnCalls CreateSoaDirectColumnCalls()
        => new(
            _diagnostics, _spans, _scopes, _declarationContext, _clrTypeConversion, _soaEscape,
            _memberAccess, _writeTargets);

    private AnalyzerAssignment CreateAssignment()
        => new(
            _diagnostics, _spans, _scopes, _declarationContext, _ambient, _nullFlow, _soaEscape,
            _identifierResolution, _assignability, _assignabilityFacts, _writeTargets,
            _operatorExpressions);

    private AnalyzerFlowNarrowing CreateFlowNarrowing()
        => new(_scopes, _typeResolver, _assignability);

    private AnalyzerVariableDeclaration CreateVariableDeclaration()
        => new(_diagnostics, _spans, _typeResolver, _assignability, _nullFlow, _scopes, _declarationContext, _soaEscape);

    private AnalyzerOperatorExpressions CreateOperatorExpressions()
        => new(
            _diagnostics, _spans, _scopes, _declarationContext, _typeSubstitution, _assignability,
            _clrTypeConversion, _externalTypeProbe, _soaEscape, _ambient, _flowNarrowing,
            _writeTargets);

    private AnalyzerMatchExhaustiveness CreateMatchExhaustiveness()
        => new(_diagnostics, _typeSubstitution, _assignability, _typeResolver);

    private AnalyzerPatternShapes CreatePatternShapes()
        => new(_diagnostics, _spans, _declarationContext, _assignability);

    private AnalyzerPatternReachability CreatePatternReachability()
        => new(_diagnostics, _spans, _declarationContext, _assignability);

    private AnalyzerPatternAnalysis CreatePatternAnalysis()
        => new(
            _diagnostics,
            _spans,
            _typeResolver,
            _typeSubstitution,
            _matchExhaustiveness,
            _patternShapes,
            _patternReachability,
            _propertyPatternBinding,
            _soaEscape,
            _ambient);

    private AnalyzerCallAnalysis CreateCallAnalysis()
        => new(
            _syntheticCallReporter,
            _syntheticCallWalk,
            _syntheticCallValidator,
            _reflectionCallReporter,
            _reflectionArgumentBinder,
            _clrTypeConversion,
            _typeSubstitution,
            _assignability,
            _diagnostics,
            _spans,
            _scopes,
            _ambient,
            _writeTargets,
            _identifierResolution);

    private AnalyzerLambdaAnalysis CreateLambdaAnalysis()
        => new(
            _diagnostics,
            _spans,
            _declarationContext,
            _typeResolver,
            _clrTypeConversion,
            _assignabilityFacts,
            _soaEscape,
            CreateExpressionTreeValidator());

    private AnalyzerExpressionTreeValidator CreateExpressionTreeValidator()
        => new(
            _diagnostics,
            _spans,
            _scopes,
            _declarationContext,
            _externalTypeProbe,
            _wellKnownTypes);

    private AnalyzerReflectionCallReporter CreateReflectionCallReporter()
        => new(
            _scopes,
            _declarationContext,
            _assignabilityFacts,
            _spans,
            _diagnostics,
            _callableReferenceReportLog);

    private AnalyzerSyntheticCallValidator CreateSyntheticCallValidator()
        => new(
            _declarationContext,
            _typeResolver,
            _assignability,
            _overloadScoring,
            _syntheticCallWalk,
            _syntheticCallReporter,
            _spans,
            _diagnostics,
            _constantExpressionFacts);

    private AnalyzerSyntheticCallBinder CreateSyntheticCallBinder()
        => new(
            _declarationContext,
            _overloadScoring,
            _assignability,
            _clrTypeConversion);

    private AnalyzerSyntheticCallWalk CreateSyntheticCallWalk()
        => new(
            _typeResolver,
            _syntheticCallBinder,
            _syntheticCallReporter,
            _overloadScoring,
            _assignability,
            _spans,
            _diagnostics);

    private AnalyzerReflectionArgumentBinder CreateReflectionArgumentBinder()
        => new(
            _clrTypeConversion,
            _assignability,
            _assignabilityFacts,
            _overloadScoring,
            _typeResolver);

    private AnalyzerExtensionMethodResolution CreateExtensionMethodResolution()
        => new(
            _typeResolver,
            _assignability,
            _declarationContext,
            _functionTypeFactory,
            _clrTypeConversion,
            _extensionMethods,
            _usingNamespaces,
            _mlcAssemblies);

    private AnalyzerMemberResolution CreateMemberResolution()
        => new(
            _functionTypeFactory,
            _declarationContext,
            _typeSubstitution,
            _typeResolver,
            _clrTypeConversion,
            _extensionMethodResolution,
            _usingNamespaces);

    private AnalyzerAssignability CreateAssignability()
        => new(
            _declarationContext,
            _assignabilityFacts,
            _structuralAssignability,
            _typeSubstitution,
            _clrTypeConversion,
            _implicitConversionGuard);

    private AnalyzerOverloadScoring CreateOverloadScoring()
        => new(
            _declarationContext,
            _clrTypeConversion,
            _assignability,
            _typeResolver,
            _wellKnownTypes);

    private static string GetNuGetPackagesRoot()
    {
        var configuredRoot = Environment.GetEnvironmentVariable("NUGET_PACKAGES");
        if (!string.IsNullOrWhiteSpace(configuredRoot))
        {
            return Path.GetFullPath(configuredRoot);
        }

        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".nuget",
            "packages");
    }

    /// <summary>
    /// Sets the source texts used by the current project snapshot. This lets semantic
    /// declarations point at identifier spans even when a referenced file is only
    /// present through an unsaved editor buffer.
    /// </summary>
    public void SetProjectSourceTexts(IReadOnlyDictionary<string, string> sourceTexts)
    {
        _projectSources.ResetSourceTexts();
        foreach (var (path, text) in sourceTexts)
        {
            _projectSources.AddSourceText(path, text);
        }
    }

    /// <summary>
    /// Get a snapshot of the type-declaration-to-file mapping recorded during the most recent Analyze() call.
    /// Used by MultiFileCompiler to build the project-level ProjectIndex.
    /// </summary>
    public Dictionary<string, string> GetTypeDeclarationFiles() => new(_typeDeclarationFiles);

    public AnalysisResult Analyze(CompilationUnit unit)
    {
        return Analyze(unit, null, null, null);
    }

    private void InitializeDeclarationContext(
        CompilationUnit unit,
        string? currentFilePath,
        string? projectRoot)
    {
        var contextRoot = !string.IsNullOrWhiteSpace(projectRoot)
            ? projectRoot
            : !string.IsNullOrWhiteSpace(currentFilePath)
                ? Path.GetDirectoryName(Path.GetFullPath(currentFilePath))
                : null;
        var effectiveRoot = contextRoot ?? Directory.GetCurrentDirectory();
        _declarationContextFilePath = !string.IsNullOrWhiteSpace(currentFilePath)
            ? Path.GetFullPath(currentFilePath)
            : Path.Combine(effectiveRoot, ".nsharp-analyzer-memory.nl");
        _declarationPolicy.SetDeclarationContextFilePath(_declarationContextFilePath);
        _declarationContext.Reset(effectiveRoot, _mlcAssemblies);
        _declarationContext.AddCompilationUnit(_declarationContextFilePath, unit);

        _projectSources.AddProjectUnitsTo(_declarationContext);
    }

    public AnalysisResult Analyze(CompilationUnit unit, string? currentFilePath, string? projectRoot, string? sourceCode = null)
    {
        _errors.Clear();
        _scopes.Clear();
        _usingNamespaces.Clear();
        _usingAliases.Clear();
        _importedSymbolsByAlias.Clear();
        _importedDeclarationsByAlias.Clear();
        _implicitConversionGuard.Clear();
        _extensionMethods.Clear();
        _semanticModel = new SemanticModel();  // Reset semantic model for new analysis
        _bindingMap = new BindingMap(); // Reset binding map for new analysis
        _soaEscape.BeginAnalysis();
        _nullFlow.BeginAnalysis();
        _ambient.BeginAnalysis();
        _currentFilePath = currentFilePath;
        _projectSources.BeginAnalysis(projectRoot);
        _compilationUnit = unit;
        _sourceText = sourceCode;
        _diagnostics.BeginAnalysis(currentFilePath, sourceCode);
        _typeResolver.BeginAnalysis(currentFilePath, unit, _semanticModel, _bindingMap);
        _identifierResolution.BeginAnalysis(unit, _semanticModel, _bindingMap);
        _memberAccess.BeginAnalysis(unit, _bindingMap);
        _imports.BeginAnalysis(_semanticModel, _bindingMap);
        _declarationPolicy.BeginAnalysis(_semanticModel, _bindingMap, currentFilePath, unit);
        _expressionTail.BeginAnalysis(_semanticModel);
        _typeDeclarationFiles.Clear();

        InitializeDeclarationContext(unit, currentFilePath, projectRoot);

        // Process import directives
        foreach (var importDirective in unit.Imports)
        {
            DriveImports(_imports.BeginNamespaceImport(
                importDirective.Namespace, importDirective.Alias, importDirective.Line, importDirective.Column));
        }

        // Validate package declaration if present
        if (unit.Package != null)
        {
            _declarationPolicy.ValidatePackageName(unit.Package);
        }

        // Create global scope first (needed for adding imported symbols)
        PushScope(new Scope(ScopeKind.Global), 1, 1);

        // Process file imports (adds symbols to global scope)
        if (unit.FileImports.Count > 0)
        {
            DriveImports(_imports.BeginFileImports(unit.FileImports));
        }

        // Check for import collisions
        _imports.CheckImportCollisions();

        // First pass: collect all type declarations and function signatures
        foreach (var decl in unit.Declarations)
        {
            if (decl is ClassDeclaration classDecl)
                _declarationPolicy.DeclareType(classDecl.Name, NominalTypeInfoFactory.FromClassDeclaration(classDecl), decl.Line, decl.Column);
            else if (decl is StructDeclaration structDecl)
                _declarationPolicy.DeclareType(structDecl.Name, NominalTypeInfoFactory.FromStructDeclaration(structDecl), decl.Line, decl.Column);
            else if (decl is RecordDeclaration recordDecl)
                _declarationPolicy.DeclareType(recordDecl.Name, NominalTypeInfoFactory.FromRecordDeclaration(recordDecl), decl.Line, decl.Column);
            else if (decl is SoaRecordDeclaration soaRecordDecl)
                _declarationPolicy.DeclareType(soaRecordDecl.Name, SoaTypeInfoFactory.FromDeclaration(soaRecordDecl), decl.Line, decl.Column);
            else if (decl is InterfaceDeclaration interfaceDecl)
                _declarationPolicy.DeclareType(interfaceDecl.Name, NominalTypeInfoFactory.FromInterfaceDeclaration(interfaceDecl), decl.Line, decl.Column);
            else if (decl is UnionDeclaration unionDecl)
                _declarationPolicy.DeclareType(unionDecl.Name, UnionTypeInfoFactory.FromDeclaration(unionDecl), decl.Line, decl.Column);
            else if (decl is EnumDeclaration enumDecl)
                _declarationPolicy.DeclareType(enumDecl.Name, EnumTypeInfoFactory.FromDeclaration(enumDecl), decl.Line, decl.Column);
            else if (decl is TypeAliasDeclaration aliasDecl)
                _declarationPolicy.DeclareType(aliasDecl.Name, new AliasTypeInfo(aliasDecl.Type), decl.Line, decl.Column);
            else if (decl is NewtypeDeclaration newtypeDecl)
                _declarationPolicy.DeclareType(newtypeDecl.Name, new NewtypeInfo(newtypeDecl.Name, newtypeDecl.UnderlyingType), decl.Line, decl.Column);
            else if (decl is FunctionDeclaration func)
            {
                // Add function signatures to enable forward references
                var funcTypeInfo = _functionTypeFactory.CreateFromDeclaration(func, _ambient.CurrentTypeName);
                _declarationPolicy.DeclareSymbol(func.Name, funcTypeInfo, func.Line, func.Column, null, true);
            }
        }

        // Validate and collect setup/teardown blocks (only one of each allowed)
        _declarationWalkers.CollectTestScaffolding(unit.Declarations);

        // Second pass: analyze all declarations
        foreach (var decl in unit.Declarations)
        {
            _scopes.NoteLine(decl.Line);
            AnalyzeDeclaration(decl);
        }

        PopScope();

        _referenceLoadReport.Report(_metadataResolver?.LoadFailures);

        return new AnalysisResult(_errors, _semanticModel, _bindingMap);
    }

    private void AnalyzeDeclaration(Declaration decl)
    {
        _attributeValidator.ValidateDeclarationAttributeArguments(decl);

        switch (decl)
        {
            case TestDeclaration test:
                DriveDeclarationWalk(_declarationWalkers.BeginTest(test, _assignability));
                break;
            case SetupDeclaration setup:
                DriveDeclarationWalk(_declarationWalkers.BeginSetup(setup, _assignability));
                break;
            case TeardownDeclaration teardown:
                DriveDeclarationWalk(_declarationWalkers.BeginTeardown(teardown, _assignability));
                break;
            case FunctionDeclaration func:
                DriveFunctionBody(_functionBodies.BeginFunctionDeclaration(
                    func, _ambient.CurrentTypeName, _assignability));
                break;
            case ClassDeclaration classDecl:
                DriveTypeDeclaration(_typeDeclarations.BeginClass(classDecl, _assignability));
                break;
            case StructDeclaration structDecl:
                DriveTypeDeclaration(_typeDeclarations.BeginStruct(structDecl, _assignability));
                break;
            case RecordDeclaration recordDecl:
                DriveTypeDeclaration(_typeDeclarations.BeginRecord(recordDecl, _assignability));
                break;
            case SoaRecordDeclaration soaRecordDecl:
                DriveTypeDeclaration(_typeDeclarations.BeginSoaRecord(soaRecordDecl, _assignability));
                break;
            case InterfaceDeclaration interfaceDecl:
                DriveTypeDeclaration(_typeDeclarations.BeginInterface(interfaceDecl, _assignability));
                break;
            case UnionDeclaration unionDecl:
                DriveTypeDeclaration(_typeDeclarations.BeginUnion(unionDecl, _assignability));
                break;
            case EnumDeclaration enumDecl:
                DriveTypeDeclaration(_typeDeclarations.BeginEnum(enumDecl, _assignability));
                break;
            case TypeAliasDeclaration aliasDecl:
                _typeResolver.ResolveDeclaredType(aliasDecl.Type);
                break;
            case NewtypeDeclaration newtypeDecl:
                _typeResolver.ResolveDeclaredType(newtypeDecl.UnderlyingType);
                break;
            case FieldDeclaration field:
                DriveTypeDeclaration(_typeDeclarations.BeginField(field, _assignability));
                break;
            case PropertyDeclaration prop:
                DriveAccessorBody(_accessorBodies.BeginProperty(
                    prop, _ambient.CurrentTypeName, _assignability));
                break;
            case ConstructorDeclaration ctor:
                DriveDeclarationWalk(_declarationWalkers.BeginConstructor(ctor, _assignability));
                break;
            case IndexerDeclaration indexer:
                DriveAccessorBody(_accessorBodies.BeginIndexer(
                    indexer, _ambient.CurrentTypeName, _assignability));
                break;
            case PreprocessorDeclaration:
                // Preprocessor directives don't need analysis - they're pass-through
                break;
        }
    }

    /// <summary>
    /// Which walk a statement IS. Every arm is a single route: it names the N#-owned walk the
    /// statement belongs to, hands that walk the typed node plus whichever collaborators this host
    /// holds and the walk cannot reach for itself, and runs the matching driver. No arm branches,
    /// computes, orders or words anything, and the compiler checks each route end to end — the arm's
    /// pattern type is the <c>Begin</c>'s parameter type, and the state it answers is the driver's.
    /// The 30 concrete <see cref="Statement"/> shapes account for exactly: 26 routes, two shapes with
    /// no semantic content, and <see cref="FileImport"/> / <see cref="NamespaceImport"/>, which are
    /// statements only so they can sit in <c>CompilationUnit.FileImports</c> and never reach a
    /// statement list.
    /// </summary>
    private void AnalyzeStatement(Statement stmt)
    {
        _scopes.NoteLine(stmt.Line);
        switch (stmt)
        {
            case ExpressionStatement exprStmt:
                DriveExpressionStatement(
                    _expressionStatements.BeginExpressionStatement(exprStmt.Expression));
                break;
            case VariableDeclarationStatement varDecl:
                DriveLocalDeclaration(_variableDeclaration.Begin(varDecl));
                break;
            case TupleDeconstructionStatement tupleDecl:
                DriveLocalDeclaration(_variableDeclaration.BeginTuple(tupleDecl));
                break;
            case BlockStatement block:
                DriveStatementSequence(_statementSequence.BeginBlock(block));
                break;
            case AllocBlockStatement allocBlock:
                DriveStatementSequence(_statementSequence.BeginTransparent(allocBlock.Body));
                break;
            case AllowStatement allow:
                DriveStatementSequence(_statementSequence.BeginTransparent(allow.Body));
                break;
            case UnsafeBlockStatement unsafeBlock:
                DriveStatementSequence(_statementSequence.BeginTransparent(unsafeBlock.Body));
                break;
            case IfStatement ifStmt:
                DriveLoopStatement(_loopSequence.BeginIf(ifStmt, _flowNarrowing));
                break;
            case ForStatement forStmt:
                DriveLoopStatement(_loopSequence.BeginFor(forStmt, _flowNarrowing));
                break;
            case ForeachStatement foreachStmt:
                DriveLoopStatement(_loopSequence.BeginForeach(foreachStmt));
                break;
            case AwaitForEachStatement awaitForeachStmt:
                DriveLoopStatement(_loopSequence.BeginAwaitForeach(awaitForeachStmt));
                break;
            case WhileStatement whileStmt:
                DriveLoopStatement(_loopSequence.BeginWhile(whileStmt, _flowNarrowing));
                break;
            case YieldStatement yieldStmt:
                DriveYieldStatement(_loopSequence.BeginYield(yieldStmt, _assignability));
                break;
            case ReturnStatement returnStmt:
                DriveReturnStatement(_ambient.BeginReturn(returnStmt, _assignability));
                break;
            case BreakStatement:
                _ambient.ReportBreakIfNeeded(stmt.Line, stmt.Column);
                break;
            case ContinueStatement:
                _ambient.ReportContinueIfNeeded(stmt.Line, stmt.Column);
                break;
            case ThrowStatement throwStmt:
                DriveExpressionStatement(
                    _expressionStatements.BeginThrow(throwStmt.Expression, _clrTypeConversion));
                break;
            case TryStatement tryStmt:
                DriveResourceStatement(_resourceStatements.BeginTry(tryStmt, _clrTypeConversion));
                break;
            case UsingStatement usingStmt:
                DriveResourceStatement(_resourceStatements.BeginUsing(usingStmt, _assignability));
                break;
            case LockStatement lockStmt:
                DriveResourceStatement(_resourceStatements.BeginLock(lockStmt, _ambient.CurrentClass));
                break;
            case SwitchStatement switchStmt:
                DrivePatternAnalysis(_patternAnalysis.BeginSwitch(switchStmt));
                break;
            case PrintStatement printStmt:
                DriveExpressionStatement(_expressionStatements.BeginPrint(printStmt.Value));
                break;
            case OffStatement off:
                DriveExpressionStatement(_expressionStatements.BeginOff(
                    off.Handle, typeof(NSharpLang.Runtime.NSharpEventSubscription)));
                break;
            case AssertStatement assertStmt:
                DriveExpressionStatement(_expressionStatements.BeginAssert(assertStmt));
                break;
            case AssertThrowsStatement assertThrows:
                DriveExpressionStatement(
                    _expressionStatements.BeginAssertThrows(assertThrows, _clrTypeConversion));
                break;
            case EmptyStatement:
            case PreprocessorDirective:
                // No semantic content: a stray `;` binds nothing, and a preprocessor directive was
                // already resolved by the time the semantic phase runs.
                break;
            case LocalFunctionStatement localFunc:
                DriveFunctionBody(_functionBodies.BeginLocalFunction(
                    localFunc, _ambient.CurrentTypeName, _assignability));
                break;
        }
    }

    /// <summary>
    /// The three steps the N#-owned statement-sequence walk cannot take for itself. Every sequence of
    /// statements in the language — a bare list, a <c>{ … }</c> block, and the body of an
    /// <c>alloc</c>, <c>allow</c> or <c>unsafe</c> wrapper — runs in
    /// <see cref="AnalyzerStatementSequence"/> and shares this one loop. The unreachable-code rule
    /// (that only the FIRST dead statement is reported, that the walk stops there, and that nothing
    /// below it is analysed at all), the block's own scope and its position, and the transparency of
    /// the three wrappers are all the walk's decisions; this loop performs the one operation it is
    /// handed, with the operands it is handed. Kind 1 re-enters the statement dispatch, which is what
    /// makes a nested block suspend independently of the one containing it. It is the estate's only
    /// driver with NO <c>Supply</c>: not one of the three operations answers anything, so there is
    /// nothing to hand back and the walk advances its own phase.
    /// </summary>
    private void DriveStatementSequence(StatementSequenceState state)
    {
        for (var step = _statementSequence.NextStep(state);
             step != null;
             step = _statementSequence.NextStep(state))
        {
            switch (step.Kind)
            {
                case 1:
                    AnalyzeStatement(step.Body!);
                    break;
                case 2:
                    PushScope(new Scope(ScopeKind.Block), step.Line, step.Column);
                    break;
                case 3:
                    PopScope();
                    break;
            }
        }
    }

    /// <summary>
    /// The steps the N#-owned statement-level expression walks cannot take for themselves. The bare
    /// expression statement, the <c>for</c> loop's update clause, <c>assert</c> and
    /// <c>assert throws</c> all run in <see cref="AnalyzerExpressionStatements"/> and share this one
    /// loop. One of its kinds is <see cref="DriveLocalDeclaration"/>'s, but four are not — a local
    /// declaration never opens a scope, never re-enters the statement dispatch and never asks whether
    /// a type is throwable — so the two families keep separate request types and separate loops.
    /// Each walk suspends at every step and resumes with the answer, because whether the next step
    /// happens at all is decided by the previous step's answer. Which statement it is, which report
    /// fires and with what wording are all the walk's decisions; this loop performs the one operation
    /// it is handed, with the operands it is handed. Kinds 2, 3 and 7 are gone: 2 and 3 were the two
    /// SoA escape reports and 7 was the throwability question, and all three of those are N#-owned
    /// now, so the walk asks them itself.
    /// </summary>
    private void DriveExpressionStatement(ExpressionStatementState state)
    {
        for (var step = _expressionStatements.NextStep(state);
             step != null;
             step = _expressionStatements.NextStep(state))
        {
            TypeInfo? answer = null;
            switch (step.Kind)
            {
                case 1:
                    answer = AnalyzeExpression(step.Node!);
                    break;
                case 4:
                    PushScope(new Scope(ScopeKind.Block), step.Line, step.Column);
                    break;
                case 5:
                    DriveStatementSequence(_statementSequence.BeginList(step.Statements!));
                    break;
                case 6:
                    PopScope();
                    break;
                case 8:
                    answer = _semanticModel.ExpressionTypes.TryGetValue(
                        (step.Line, step.Column), out var recorded)
                        ? recorded
                        : null;
                    break;
            }

            _expressionStatements.Supply(state, answer);
        }
    }

    /// <summary>
    /// The steps the N#-owned declared-function walk cannot take for itself. BOTH declared-function
    /// forms — the local function statement and the top-level <c>func</c> declaration — run in
    /// <see cref="AnalyzerFunctionBodies"/>, which owns everything about them that is a decision: that
    /// a local function's own name is declared into the ENCLOSING scope before its body scope opens,
    /// which is what makes a recursive call resolve and a sibling call below it resolve — and, because
    /// the name lands when the STATEMENT is walked rather than when the enclosing body is entered,
    /// what makes a call written ABOVE it NOT resolve; that a top-level declaration's name is declared
    /// only when the scope does not already hold it as a method group or an identically-signed
    /// function; that an operator overload is checked for <c>static</c>, for a symbol the language
    /// overloads and for its arity; that a first parameter marked <c>this</c> makes the declaration an
    /// extension method; that the naming convention is checked for everything except an operator
    /// overload; that the scope either form opens is a FUNCTION scope; that type parameters go in
    /// before any parameter type is resolved and before the constraints are resolved and checked for
    /// cycles; that the parameter list is validated before any name in it exists; where each parameter
    /// is declared when it carries no position of its own; which resolver reads the return type; which
    /// ambient boundary is entered; which of the two body shapes runs; that a non-void declaration
    /// whose body does not always return is told so; and what an expression body is measured against.
    /// Kind 1 is the ESTATE'S FIRST TARGET-TYPED walk step and is a kind of its own rather than a
    /// widening of any other driver's kind 1, every one of which deliberately leaves the ambient
    /// target-typing slot alone. Kind 5 is a statement LIST rather than
    /// <see cref="DriveLoopStatement"/>'s single statement, because a LOCAL function's body is walked
    /// as its statements — handing the block itself to the dispatch would open a second scope inside
    /// the function scope. Kind 9 is that same dispatch re-entry and is what a TOP-LEVEL declaration's
    /// block body takes instead, because that form's body IS a block: it advances the analysis cursor
    /// and opens a block scope, and the two forms differ there deliberately. Kind 7 is a RELAY and is
    /// the walk's ONE remaining RELAY: the default-value half of the parameter-list rules re-enters this
    /// analyzer's target-typed expression walk under SoA, and its callers are not driven. The naming
    /// convention was the second relay and is GONE — it moved whole to
    /// <see cref="AnalyzerDeclarationConventions"/> once the columnar <c>System.Char</c> catalog
    /// published <c>char.IsLower</c>, so this walk now calls it directly.
    /// </summary>
    private void DriveFunctionBody(FunctionBodyState state)
    {
        for (var step = _functionBodies.NextStep(state);
             step != null;
             step = _functionBodies.NextStep(state))
        {
            TypeInfo? answer = null;
            switch (step.Kind)
            {
                case 1:
                    answer = AnalyzeExpressionWithExpectedType(step.Node!, step.ExpectedType);
                    break;
                case 2:
                    PushScope(new Scope(ScopeKind.Function), step.Line, step.Column);
                    break;
                case 3:
                    _declarationPolicy.DeclareSymbol(step.Name!, step.CarriedType, step.Line, step.Column, null, true);
                    break;
                case 4:
                    _scopes.RecordVariable(_semanticModel, step.Name!, step.CarriedType);
                    break;
                case 5:
                    DriveStatementSequence(_statementSequence.BeginList(step.Statements!));
                    break;
                case 6:
                    PopScope();
                    break;
                case 7:
                    DriveParameterDeclarations(_declarationPolicy.BeginParameterDeclarations(step.Parameters!, step.Line, step.Column));
                    break;
                case 8:
                    _scopes.RecordFunction(_semanticModel, step.Name!, step.CarriedType);
                    break;
                case 9:
                    AnalyzeStatement(step.Body!);
                    break;
            }

            _functionBodies.Supply(state, answer);
        }
    }

    /// <summary>
    /// The steps the N#-owned accessor walks cannot take for themselves. Both of N#'s accessor-bearing
    /// declarations — the property and the indexer — run in <see cref="AnalyzerAccessorBodies"/> and
    /// share this one loop. Which form it is, which accessor is next, which scope opens, which name is
    /// declared and with what type, whether a binding declaration is recorded for it, which semantic
    /// model table is written and which report fires are all the walk's decisions; this loop performs
    /// the one operation it is handed, with the operands it is handed, and hands the answer back.
    /// </summary>
    private void DriveAccessorBody(AccessorBodyState state)
    {
        for (var step = _accessorBodies.NextStep(state);
             step != null;
             step = _accessorBodies.NextStep(state))
        {
            TypeInfo? answer = null;
            switch (step.Kind)
            {
                case 1:
                    answer = AnalyzeExpressionWithExpectedType(step.Node!, step.ExpectedType);
                    break;
                case 2:
                    PushScope(new Scope(ScopeKind.Function), step.Line, step.Column);
                    break;
                case 3:
                    _declarationPolicy.DeclareSymbol(step.Name!, step.CarriedType, step.Line, step.Column, null, step.RecordsBinding);
                    break;
                case 4:
                    _scopes.RecordVariable(_semanticModel, step.Name!, step.CarriedType);
                    break;
                case 5:
                    PopScope();
                    break;
                case 6:
                    DriveParameterDeclarations(_declarationPolicy.BeginParameterDeclarations(step.Parameters!, step.Line, step.Column));
                    break;
                case 7:
                    AnalyzeStatement(step.Body!);
                    break;
                case 8:
                    _semanticModel.RecordTypeMember(step.ContainingType!, step.Name!, step.CarriedType);
                    break;
                case 9:
                    _semanticModel.RecordProperty(step.Name!, step.CarriedType);
                    break;
            }

            _accessorBodies.Supply(state, answer);
        }
    }

    /// <summary>
    /// The steps the N#-owned type-declaration walks cannot take for themselves. All EIGHT of N#'s
    /// declaration forms — class, struct, record, interface, union, enum, <c>soa record</c> and field
    /// — run in <see cref="AnalyzerTypeDeclarations"/> and share this one loop, because they share one
    /// vocabulary: the convention, the scope, the declare/record pair and the member walk. Which form
    /// it is, which scope KIND opens, which name is declared and with what type, whether a binding
    /// declaration is recorded for it, which semantic-model table is written, which report fires and
    /// which members are walked are all the walk's decisions; this loop performs the one operation it
    /// is handed, with the operands it is handed, and hands the answer back.
    /// KIND 7 IS THE ESTATE'S FIRST RE-ENTRANT STEP: it hands a member back to
    /// <see cref="AnalyzeDeclaration"/>, which for a nested type reaches this same loop again. That is
    /// safe because it answers nothing and because every datum the walk holds lives on the state
    /// object <c>Begin</c> created, so a nested walk is a second state and a second frame.
    /// </summary>
    private void DriveTypeDeclaration(TypeDeclarationState state)
    {
        for (var step = _typeDeclarations.NextStep(state);
             step != null;
             step = _typeDeclarations.NextStep(state))
        {
            TypeInfo? answer = null;
            switch (step.Kind)
            {
                case 1:
                    answer = AnalyzeExpression(step.Node!);
                    break;
                case 2:
                    PushScope(new Scope(step.CarriedScopeKind), step.Line, step.Column);
                    break;
                case 3:
                    _declarationPolicy.DeclareSymbol(step.Name!, step.CarriedType, step.Line, step.Column, null, step.RecordsBinding);
                    break;
                case 4:
                    _scopes.RecordVariable(_semanticModel, step.Name!, step.CarriedType);
                    break;
                case 5:
                    PopScope();
                    break;
                case 6:
                    DriveParameterDeclarations(_declarationPolicy.BeginParameterDeclarations(step.Parameters!, step.Line, step.Column));
                    break;
                case 7:
                    AnalyzeDeclaration(step.Member!);
                    break;
                case 8:
                    _semanticModel.RecordTypeMember(step.ContainingType!, step.Name!, step.CarriedType);
                    break;
                case 9:
                    _semanticModel.RecordField(step.Name!, step.CarriedType);
                    break;
            }

            _typeDeclarations.Supply(state, answer);
        }
    }

    /// <summary>
    /// The steps the N#-owned local-declaration walks cannot take for themselves. Both of N#'s
    /// local-declaration statements — <c>let x: T = e</c> and <c>(a, b) := e</c> — run in
    /// <see cref="AnalyzerVariableDeclaration"/> and share this one loop, because a closure scan of
    /// the deconstruction arm resolved its re-entries to exactly the annotated arm's. Each walk
    /// suspends at every step and resumes with the answer, because the type its initializer answers
    /// is the operand of every step that follows. Which form it is, which phase runs, which report
    /// fires, which name is declared and with what type are all the walk's decisions; this loop
    /// performs the one operation it is handed, with the operands it is handed. Kinds 2 and 3 were
    /// the two SoA escape reports and are gone: those reporters are N#-owned, so the walk calls them
    /// itself, and with them went the escape flag this loop used to carry back.
    /// </summary>
    /// <summary>
    /// The steps the N#-owned declaration walks cannot take for themselves. All FOUR declaration
    /// forms whose body runs under a function scope the declaration itself fills — a test, a
    /// <c>setup</c>, a <c>teardown</c> and a constructor — run in
    /// <see cref="AnalyzerDeclarationWalkers"/> and share this one loop, because they share one
    /// vocabulary: open the scope, put names into it, walk the body, close the scope. Which names go
    /// in and where they came from, which table column a row value is measured against and with what
    /// wording it is scolded, whether a constructor's fields are checked for definite assignment, and
    /// which ambient boundary is entered are all the walk's decisions; this loop performs the one
    /// operation it is handed, with the operands it is handed. Kind 1 is a PLAIN expression walk and
    /// deliberately not the target-typed one: the table case value's expected type is bracketed by
    /// the OWNER, because that bracket spans the suspension. Kind 5 is a statement LIST and kind 8 a
    /// single statement, and the two differ for the reason
    /// <see cref="DriveFunctionBody"/>'s kinds 5 and 9 differ: a constructor's body IS a block and
    /// opens its own block scope, while a test, <c>setup</c> and <c>teardown</c> body is walked as
    /// its statements so that no second scope opens inside the function scope.
    /// </summary>
    private void DriveDeclarationWalk(DeclarationWalkState state)
    {
        for (var step = _declarationWalkers.NextStep(state);
             step != null;
             step = _declarationWalkers.NextStep(state))
        {
            TypeInfo? answer = null;
            switch (step.Kind)
            {
                case 1:
                    answer = AnalyzeExpression(step.Node!);
                    break;
                case 2:
                    PushScope(new Scope(ScopeKind.Function), step.Line, step.Column);
                    break;
                case 3:
                    _declarationPolicy.DeclareSymbol(step.Name!, step.CarriedType, step.Line, step.Column, null, true);
                    break;
                case 4:
                    _scopes.RecordVariable(_semanticModel, step.Name!, step.CarriedType);
                    break;
                case 5:
                    DriveStatementSequence(_statementSequence.BeginList(step.Statements!));
                    break;
                case 6:
                    PopScope();
                    break;
                case 7:
                    DriveParameterDeclarations(_declarationPolicy.BeginParameterDeclarations(step.Parameters!, step.Line, step.Column));
                    break;
                case 8:
                    AnalyzeStatement(step.Body!);
                    break;
            }

            _declarationWalkers.Supply(state, answer);
        }
    }

    /// <summary>
    /// The one step the N#-owned import walk cannot take for itself: loading the reference assemblies
    /// a written namespace implies. WHICH assemblies is the walk's own policy and arrives in the
    /// request; loading them is the MetadataLoadContext surface, which stays here.
    /// </summary>
    private void DriveImports(ImportWalkState state)
    {
        for (var step = _imports.NextStep(state);
             step != null;
             step = _imports.NextStep(state))
        {
            switch (step.Kind)
            {
                case 1:
                    foreach (var assemblyName in step.AssemblyNames)
                    {
                        LoadReferencedAssemblyByName(assemblyName);
                    }
                    break;
            }

            _imports.Supply(state);
        }
    }

    /// <summary>
    /// The one step the N#-owned parameter walk cannot take for itself: analysing a default-value
    /// expression against its parameter's type. The bracket around the ambient expected type is a
    /// <c>try</c>/<c>finally</c> that must survive a throw, which is a guarantee an owner-held pair
    /// spanning a suspension cannot keep, so the analysis stays here. Nothing is carried back: the
    /// walk counts the sink's own diagnostics on both sides of the step.
    /// </summary>
    private void DriveParameterDeclarations(ParameterWalkState state)
    {
        for (var step = _declarationPolicy.NextStep(state);
             step != null;
             step = _declarationPolicy.NextStep(state))
        {
            switch (step.Kind)
            {
                case 1:
                    AnalyzeExpressionWithExpectedType(step.Node, step.ExpectedType);
                    break;
            }

            _declarationPolicy.Supply(state);
        }
    }

    private void DriveLocalDeclaration(VariableDeclarationState state)
    {
        for (var step = _variableDeclaration.NextStep(state);
             step != null;
             step = _variableDeclaration.NextStep(state))
        {
            TypeInfo? answer = null;
            switch (step.Kind)
            {
                case 1:
                {
                    var previousExpectedType = _ambient.EnterExpectedType(step.ExpectedType);
                    answer = AnalyzeExpression(step.Node!);
                    _ambient.ExitExpectedType(previousExpectedType);
                    break;
                }
                case 4:
                    _declarationPolicy.DeclareSymbol(step.Name!, step.CarriedType, step.Line, step.Column, step.Text, true);
                    break;
                case 5:
                    _scopes.RecordVariable(_semanticModel, step.Name!, step.CarriedType);
                    break;
                case 6:
                    answer = AnalyzeExpression(step.Node!);
                    break;
            }

            _variableDeclaration.Supply(state, answer);
        }
    }

    /// <summary>
    /// The steps the N#-owned condition-and-body walks cannot take for themselves. All four of N#'s
    /// loop statements — <c>foreach</c>, <c>await foreach</c>, <c>while</c> and <c>for</c> — and
    /// <c>if</c> run in <see cref="AnalyzerLoopSequence"/> and share this one loop, because they are
    /// the same walk with and without a collection, an initializer, an update clause and a second
    /// branch. Each walk suspends at every step, because the answered type is the operand of the
    /// escape reports, of the element-type question and of the boolean gate. Which escape fires and
    /// with which action word, which question is asked, whether a condition is gated and under whose
    /// name, what the condition proves about each branch and in which scope those facts are
    /// installed, whether a branch that always leaves hands its facts to the surviving flow, which
    /// scope opens and where, and the order of every operation are all the walk's decisions. Kind 5
    /// is a SINGLE statement rather than <see cref="DriveExpressionStatement"/>'s statement LIST,
    /// because none of a loop body, a <c>for</c> initializer or an <c>if</c> branch ever had the
    /// unreachable-code rule applied to it; an <c>else if</c> arrives back at this dispatch through
    /// that same kind and needs nothing of its own. Kind 7 is the one place in this estate where a
    /// driver drives a driver: a <c>for</c> loop's update clause belongs to the statement-level
    /// expression family, and constructing that family's state and running its loop are the two
    /// things N# cannot do for itself.
    /// </summary>
    private void DriveLoopStatement(LoopStatementState state)
    {
        for (var step = _loopSequence.NextLoopStep(state);
             step != null;
             step = _loopSequence.NextLoopStep(state))
        {
            TypeInfo? answer = null;
            switch (step.Kind)
            {
                case 1:
                    answer = AnalyzeExpression(step.Node!);
                    break;
                case 2:
                    PushScope(new Scope(ScopeKind.Block), step.Line, step.Column);
                    break;
                case 3:
                    _declarationPolicy.DeclareSymbol(step.Name!, step.CarriedType, step.Line, step.Column, null, true);
                    break;
                case 4:
                    _scopes.RecordVariable(_semanticModel, step.Name!, step.CarriedType);
                    break;
                case 5:
                    AnalyzeStatement(step.Body!);
                    break;
                case 6:
                    PopScope();
                    break;
                case 7:
                    DriveExpressionStatement(_expressionStatements.BeginForIterator(step.Node!));
                    break;
            }

            _loopSequence.SupplyLoop(state, answer);
        }
    }

    /// <summary>
    /// The steps the N#-owned resource walks cannot take for themselves. All three of N#'s guarded
    /// regions — <c>try</c>, <c>using</c> and <c>lock</c> — run in
    /// <see cref="AnalyzerResourceStatements"/> and share this one loop, because they are the same
    /// shape: open a scope, name what the region is guarded by, run a body inside it, close. Which
    /// report fires and with which span and suggestion, what a bare <c>catch</c> catches, where a
    /// catch variable is declared, that a <c>finally</c> body raises the ambient finally depth for
    /// exactly its own extent, that a <c>using</c> resource is measured only when its own declaration
    /// was clean, and the order of every operation are all the walk's decisions. Kind 5 is a SINGLE
    /// statement, as <see cref="DriveLoopStatement"/>'s is: every body in this family is a
    /// <c>BlockStatement</c> handed to the statement dispatch, which is what opens the block's own
    /// scope and applies the unreachable-code rule to its contents. Kind 7 is the second place in
    /// this estate where a driver drives a driver: a <c>using</c> resource DECLARATION belongs to the
    /// local-declaration family, and constructing that family's state and running its loop are the
    /// two things N# cannot do for itself.
    /// </summary>
    private void DriveResourceStatement(ResourceStatementState state)
    {
        for (var step = _resourceStatements.NextResourceStep(state);
             step != null;
             step = _resourceStatements.NextResourceStep(state))
        {
            TypeInfo? answer = null;
            switch (step.Kind)
            {
                case 1:
                    answer = AnalyzeExpression(step.Node!);
                    break;
                case 2:
                    PushScope(new Scope(ScopeKind.Block), step.Line, step.Column);
                    break;
                case 3:
                    _declarationPolicy.DeclareSymbol(step.Name!, step.CarriedType, step.Line, step.Column, null, true);
                    break;
                case 4:
                    _scopes.RecordVariable(_semanticModel, step.Name!, step.CarriedType);
                    break;
                case 5:
                    AnalyzeStatement(step.Body!);
                    break;
                case 6:
                    PopScope();
                    break;
                case 7:
                    DriveLocalDeclaration(_variableDeclaration.Begin(step.Declaration!));
                    break;
            }

            _resourceStatements.SupplyResource(state, answer);
        }
    }

    /// <summary>
    /// The steps the N#-owned <c>yield</c> walk cannot take for itself. The walk runs in
    /// <see cref="AnalyzerLoopSequence"/> rather than in the ambient context, because the rule that
    /// ends it — does the yielded value fit the sequence — is a question about the ELEMENT TYPE, and
    /// that family lives there; the two ambient facts it reads it reaches through the context it
    /// holds. It asked for three steps until the two SoA escape reports became N#-owned; the walk
    /// calls those itself now and still READS both answers, because either escape silences the
    /// element-type rule. What is left is the analyzer's own expression walk.
    /// </summary>
    private void DriveYieldStatement(YieldStatementState state)
    {
        for (var step = _loopSequence.NextStep(state);
             step != null;
             step = _loopSequence.NextStep(state))
        {
            _loopSequence.Supply(state, AnalyzeExpression(step.Node!));
        }
    }

    /// <summary>
    /// The steps the N#-owned <c>return</c> walk cannot take for itself. The walk runs in
    /// <see cref="AnalyzerAmbientContext"/>, which already answers every question the statement asks
    /// — the enclosing function's return type, its <c>async</c> and generator modifiers, and the
    /// <c>finally</c> depth — and already owns both of the reports it can raise. Its kind set was
    /// <see cref="DriveLocalDeclaration"/>'s 1 / 2 / 3 with ZERO additions; kinds 2 and 3 were the
    /// two SoA escape reports and are gone now that those reporters are N#-owned. Kind 1 carries no
    /// expected type because the walk installs its own: the context IS the target-typing slot's
    /// owner, so the transition never leaves N#. The walk suspends at the expression step and resumes
    /// with the answer, because which escape report fires, whether the generator report fires and
    /// whether the value fits are all functions of it.
    /// </summary>
    private void DriveReturnStatement(ReturnStatementState state)
    {
        for (var step = _ambient.NextStep(state);
             step != null;
             step = _ambient.NextStep(state))
        {
            _ambient.Supply(state, AnalyzeExpression(step.Node!));
        }
    }

    /// <summary>
    /// The steps the N#-owned pattern family cannot take for itself: the analyzer's own expression
    /// walk, the scope stack's symbol declaration, its scope open and close, and the statement
    /// dispatch. Both of the family's forms — a PATTERN node and the <c>switch</c> statement that
    /// exists to dispatch on one — run in <see cref="AnalyzerPatternAnalysis"/> and share this one
    /// loop. Each walk suspends at each step and resumes WITH the answer, because both a step's
    /// operands and the number of steps depend on answers it does not have until it has already
    /// suspended: a literal pattern's row-escape report is passed the type the analysis before it
    /// produced, a relational pattern's two escape reports are joined by `&amp;&amp;` over their
    /// negations, and a <c>switch</c>'s scrutinee type — the operand of every case pattern below it —
    /// is the answer to its own first step. Which arm, which node, which binding, which report,
    /// which scope and in what order are all the walk's decisions; this loop performs the one
    /// operation it is handed, with the operands it is handed. A nested pattern comes back as a
    /// kind-5 request and recurses through <see cref="AnalyzePattern"/>, so the walk needs no stack
    /// of its own — and a <c>switch</c> case's own pattern is that SAME request, which is why the
    /// statement form added no kind for it.
    /// </summary>
    private void DrivePatternAnalysis(PatternAnalysisState state)
    {
        for (var step = _patternAnalysis.NextStep(state);
             step != null;
             step = _patternAnalysis.NextStep(state))
        {
            TypeInfo? answer = null;
            switch (step.Kind)
            {
                case 1:
                    answer = AnalyzeExpression(step.Node!);
                    break;
                case 4:
                    _declarationPolicy.DeclareSymbol(step.Name!, step.CarriedType, step.Line, step.Column, null, true);
                    break;
                case 5:
                    AnalyzePattern(step.Pattern!, step.CarriedType);
                    break;
                case 6:
                    PushScope(new Scope(ScopeKind.Block), step.Line, step.Column);
                    break;
                case 7:
                    DriveStatementSequence(_statementSequence.BeginList(step.Statements!));
                    break;
                case 8:
                    PopScope();
                    break;
            }

            _patternAnalysis.Supply(state, answer);
        }
    }

    private void AnalyzePattern(Pattern pattern, TypeInfo valueType)
        => DrivePatternAnalysis(_patternAnalysis.Begin(pattern, valueType));

    /// <summary>
    /// The five steps the N#-owned <c>match</c> expression cannot take for itself: the analyzer's own
    /// expression walk in BOTH of its forms, the scope stack's open and close, and the pattern family's
    /// driver. The arm runs in <see cref="AnalyzerMatchExpression"/>, which owns what the match value is
    /// walked under, that each arm gets a scope of its own, that every arm is target-typed against the
    /// MATCH's expected type rather than against the arm before it, the join rule and its one report,
    /// and that exhaustiveness is asked last and on the post-escape value type.
    /// Kinds 1 and 2 are BOTH expression walks and are deliberately different: kind 1 is a PLAIN walk
    /// under a cleared-slot bracket the owner opens and closes itself (slice 51's pattern, because the
    /// C# bracketed a plain walk), and kind 2 is the TARGET-TYPED walk (slice 52's, because the C#
    /// called the form that routes a lambda to <see cref="DriveLambda"/> before any bracket opens).
    /// An owner cannot simulate kind 2 by setting the slot, which is why it is a kind and not a bracket.
    /// Kind 4 re-enters the pattern walk through <see cref="AnalyzePattern"/>, the same recursion a
    /// nested pattern takes, so this walk needs no pattern stack of its own.
    /// This loop decides nothing: it performs the one operation it is handed, with the operands it is
    /// handed.
    /// </summary>
    private TypeInfo DriveMatchExpression(MatchExpressionState state)
    {
        for (var step = _matchExpression.NextStep(state);
             step != null;
             step = _matchExpression.NextStep(state))
        {
            TypeInfo? answer = null;
            switch (step.Kind)
            {
                case 1:
                    answer = AnalyzeExpression(step.Node!);
                    break;
                case 2:
                    answer = AnalyzeExpressionWithExpectedType(step.Node!, step.ExpectedType);
                    break;
                case 3:
                    PushScope(new Scope(ScopeKind.Block), step.Line, step.Column);
                    break;
                case 4:
                    AnalyzePattern(step.PatternNode!, step.CarriedType);
                    break;
                case 5:
                    PopScope();
                    break;
            }

            _matchExpression.Supply(state, answer);
        }

        return _matchExpression.Result(state);
    }

    /// <summary>
    /// The one step the N#-owned literal family cannot take for itself, and the ESTATE'S FIRST
    /// ANSWERING DRIVER. All seven literal forms run in <see cref="AnalyzerLiteralExpressions"/>,
    /// which owns what each of them is: the integer suffix rules and the target-typing of a
    /// suffixless one, the float suffix rule, the four constant answers, and everything an
    /// interpolated string means — that it is a <c>string</c> whatever its holes are, that its holes
    /// are walked in source order under no expected type, and that each hole is refused BOTH SoA
    /// escapes. Six of the seven ask for nothing, so this loop's body never runs for them; the
    /// interpolated string suspends once per hole and resumes WITH THAT HOLE'S TYPE, which is the
    /// operand of the row-escape report that follows it.
    /// Unlike every other driver in this file, this one RETURNS. A statement and a declaration answer
    /// nothing, so all eleven of their loops are <c>void</c> and carry answers only inward through
    /// <c>Supply</c>; an expression must hand a type back to the dispatch that asked for it, so the
    /// owner publishes <c>Result</c> and this loop returns what it says. Nothing else about the
    /// protocol changes, and this loop decides nothing: it performs the one operation it is handed,
    /// with the operand it is handed.
    /// </summary>
    private TypeInfo DriveLiteralExpression(LiteralExpressionState state)
    {
        for (var step = _literalExpressions.NextStep(state);
             step != null;
             step = _literalExpressions.NextStep(state))
        {
            _literalExpressions.Supply(state, AnalyzeExpression(step.Node!));
        }

        return _literalExpressions.Result(state);
    }

    /// <summary>
    /// The one step the N#-owned compile-time constant family cannot take for itself. All four forms
    /// run in <see cref="AnalyzerCompileTimeConstants"/>, which owns what each of them is: that
    /// <c>typeof</c> validates its written type reference and answers a live <c>System.Type</c>, that
    /// <c>sizeof</c> validates its own and is always <c>int</c>, that <c>nameof</c> is a
    /// <c>string</c> on every path and may name only an identifier or a member access, and that
    /// <c>default</c> is the ambient expected type or nothing at all. Three of the four ask for
    /// nothing, so this loop's body never runs for them; <c>nameof</c> suspends once and resumes WITH
    /// ITS TARGET'S TYPE, which is the operand of the row-escape report that follows it.
    /// The well-known-type bag is handed to <c>Begin</c> rather than held by the owner, because it is
    /// the one collaborator the metadata load context rebuilds and nulls; passing it here reads it at
    /// the same instant the dispatch reached the node, which is the same instant the owner reads the
    /// target-typing slot. This loop decides nothing: it performs the one operation it is handed,
    /// with the operand it is handed.
    /// </summary>
    private TypeInfo DriveCompileTimeConstant(CompileTimeConstantState state)
    {
        for (var step = _compileTimeConstants.NextStep(state);
             step != null;
             step = _compileTimeConstants.NextStep(state))
        {
            _compileTimeConstants.Supply(state, AnalyzeExpression(step.Node!));
        }

        return _compileTimeConstants.Result(state);
    }

    /// <summary>
    /// Performs the expression steps <see cref="AnalyzerPassThroughOperands"/> asks for and returns
    /// the type it decided. Every policy about what an operator that hands its operand through
    /// means — that a `throw` is `never`, an `is` a `bool`, a `spread` and an `alloc` their operand,
    /// a `must` one layer less nullable, a `stackalloc` a `Span` of its written element type, a
    /// tuple the tuple of its elements and an `await` the awaited result — belongs to the N# owner.
    /// Unlike the two families before it, none of these forms can answer before its operand has been
    /// walked, so every one of them suspends: seven exactly once, and a tuple once per element.
    /// A tuple's steps are bracketed by the owner with the expected type its annotation implies for
    /// that element; the bracket opens inside <c>NextStep</c> and closes in the phase after
    /// <c>Supply</c>, so nothing between them observes the slot and this loop stays unaware of it.
    /// The pattern reachability checker is handed to <c>Begin</c> rather than held by the owner,
    /// because it is rebuilt with the metadata load context; passing it here reads it at the same
    /// instant the dispatch reached the node. This loop decides nothing: it performs the one
    /// operation it is handed, with the operand it is handed.
    /// </summary>
    private TypeInfo DrivePassThroughOperand(PassThroughOperandState state)
    {
        for (var step = _passThroughOperands.NextStep(state);
             step != null;
             step = _passThroughOperands.NextStep(state))
        {
            _passThroughOperands.Supply(state, AnalyzeExpression(step.Node!));
        }

        return _passThroughOperands.Result(state);
    }

    /// <summary>
    /// Performs the steps <see cref="AnalyzerTargetTypedOperands"/> asks for and returns the type it
    /// decided. Every policy about what an expression that chooses the type its operands are walked
    /// under means — that a cast is its written target type and that its operand is walked under that
    /// target only for a hard cast over a <c>default</c> or a <c>new()</c>, that a <c>checked</c> and
    /// an <c>unchecked</c> are their operand and hand the surrounding expected type back to it, and
    /// that a ternary walks its condition under <c>bool</c>, both arms under its own expected type,
    /// and answers the common type of the two — belongs to the N# owner.
    /// The two expression kinds are the two DOORS into the walk and the owner names which: kind 1 is
    /// the ordinary walk that leaves the target-typing slot exactly as it found it, and kind 2 is the
    /// named-expected-type walk, which is not that operation with an extra argument — it forks to the
    /// lambda walk for a lambda operand, which a <c>checked</c> can have, so the owner cannot simulate
    /// it by writing the slot around a kind 1. Kind 3 is GONE: it was numeric widening, a rule whose
    /// five callers all lived in the operator arms, and now that those arms and their tables are
    /// N#-owned the ternary asks <see cref="AnalyzerOperatorExpressions"/> for a common type itself.
    /// This loop decides nothing: it performs the one operation it is handed, with the operands it is
    /// handed.
    /// </summary>
    private TypeInfo DriveTargetTypedOperand(TargetTypedOperandState state)
    {
        for (var step = _targetTypedOperands.NextStep(state);
             step != null;
             step = _targetTypedOperands.NextStep(state))
        {
            TypeInfo? answer = null;
            switch (step.Kind)
            {
                case 1:
                    answer = AnalyzeExpression(step.Node!);
                    break;
                case 2:
                    answer = AnalyzeExpressionWithExpectedType(step.Node!, step.ExpectedType);
                    break;
            }

            _targetTypedOperands.Supply(state, answer);
        }

        return _targetTypedOperands.Result(state);
    }

    /// <summary>
    /// Performs the steps <see cref="AnalyzerOperatorExpressions"/> asks for and returns the type it
    /// decided. Every policy about what an operator means — what each of the seven binary operator
    /// classes and the five unary ones are worth, which of them consult an operator overload and
    /// whether before or after the primitive rule, the two numeric promotion tables and the two
    /// comparison domains, which reports fire and in which order, and that all four of a binary's
    /// escape reports run without stopping one another — belongs to the N# owner.
    /// The THREE kinds are all WALKS and differ only in what is in force around them: the ordinary
    /// one; the one that preserves the nullability flow type, which only the left side of <c>??</c>
    /// takes because that is the fact the question is ABOUT; and the one inside a fresh block scope
    /// carrying what the left side of <c>&amp;&amp;</c> or <c>||</c> proved, asked for only when the
    /// narrowing list is non-empty so this loop never decides whether a scope is wanted.
    /// Seven kinds are gone. Five were WRITE-TARGET REPORTS and one was the question in front of them:
    /// they were steps only while those reports lived here, and the owner now calls
    /// <see cref="AnalyzerWriteTargets"/> itself. The seventh captured every sub-expression's type for
    /// a write target, and the table it installed is now an ambient slot the owner brackets for
    /// itself. This loop decides nothing: it performs the one operation it is handed, with the
    /// operands it is handed.
    /// </summary>
    private TypeInfo DriveOperatorExpression(OperatorExpressionState state)
    {
        for (var step = _operatorExpressions.NextStep(state);
             step != null;
             step = _operatorExpressions.NextStep(state))
        {
            TypeInfo? answer = null;
            switch (step.Kind)
            {
                case 1:
                    answer = AnalyzeExpression(step.Node!);
                    break;
                case 2:
                {
                    var previousSuppressFlowType = _nullFlow.SuppressFlowType;
                    _nullFlow.SetSuppressFlowType(true);
                    try
                    {
                        answer = AnalyzeExpression(step.Node!);
                    }
                    finally
                    {
                        _nullFlow.SetSuppressFlowType(previousSuppressFlowType);
                    }

                    break;
                }
                case 3:
                    PushScope(new Scope(ScopeKind.Block), step.Line, step.Column);
                    _flowNarrowing.ApplyNarrowingsToScope(step.Narrowings!);
                    answer = AnalyzeExpression(step.Node!);
                    PopScope();
                    break;
            }

            _operatorExpressions.Supply(state, answer);
        }

        return _operatorExpressions.Result(state);
    }

    /// <summary>
    /// Performs the steps <see cref="AnalyzerAssignment"/> asks for and returns the type it decided.
    /// Every policy about what an assignment means — that a discard binds nothing and is a plain
    /// <c>=</c> shape only, that a null-conditional target is refused before it is walked, the eight
    /// ordered gates a walked target passes, that every refusal still walks the value so errors inside
    /// it are reported too, which of those value walks run under the target's type, the readonly-field
    /// rule, the assignability front door in both its renderings, the compound form's operator
    /// question, and the null-state and error-tuple facts a successful store leaves behind — belongs
    /// to the N# owner.
    /// The ONE kind is the ordinary walk, handed out up to twice. Every bracket the arm needs — the
    /// four-part target bracket and the target-typed value bracket — is opened and closed by the owner
    /// around the step, because none of them carries a lambda fork this loop would have to simulate.
    /// This loop decides nothing: it performs the one operation it is handed, with the operand it is
    /// handed.
    /// </summary>
    private TypeInfo DriveAssignment(AssignmentState state)
    {
        for (var step = _assignment.NextStep(state);
             step != null;
             step = _assignment.NextStep(state))
        {
            _assignment.Supply(state, AnalyzeExpression(step.Node!));
        }

        return _assignment.Result(state);
    }

    /// <summary>
    /// Performs the steps <see cref="AnalyzerMemberAccess"/> asks for and returns the type it
    /// decided. Every policy about what a member access means — that an aliased import's symbol is a
    /// table lookup rather than a walk, that a dotted CLR type name outranks nothing a developer
    /// wrote, that a nullable's <c>HasValue</c> and <c>Value</c> are answered without metadata and
    /// that only a NON-narrowed <c>Value</c> is warned about, in which order the four SoA refusals
    /// fire and that each of them ends the walk, that visibility is checked and the binding recorded
    /// BEFORE resolution, and WHETHER a name that did not resolve is worth reporting at all —
    /// belongs to the N# owner.
    /// The ONE kind is the RECEIVER, and it is the ordinary dispatch rather than the identifier rule,
    /// because an identifier receiver must also be judged by the tail below. The second kind is gone:
    /// it rendered the undefined-member report, and it existed only because that report's did-you-mean
    /// list reads <c>PropertyInfo.Name</c> and <c>FieldInfo.Name</c>, which were measured as absent
    /// from the columnar catalog. Re-measurement showed the catalog is the legacy planner's surface
    /// and both names bind through the ordinary runtime resolver, so the report moved to the owner
    /// that decides it is owed.
    /// This loop decides nothing: it performs the one operation it is handed, with the operands it is
    /// handed.
    /// </summary>
    private TypeInfo DriveMemberAccess(MemberAccessState state)
    {
        for (var step = _memberAccess.NextStep(state);
             step != null;
             step = _memberAccess.NextStep(state))
        {
            _memberAccess.Supply(state, AnalyzeExpression(step.Node!));
        }

        return _memberAccess.Result(state);
    }

    private TypeInfo AnalyzeExpression(Expression expr)
    {
        var type = expr switch
        {
            IntLiteralExpression or FloatLiteralExpression or CharLiteralExpression
                or StringLiteralExpression or InterpolatedStringExpression or BoolLiteralExpression
                or NullLiteralExpression => DriveLiteralExpression(_literalExpressions.Begin(expr)),
            IdentifierExpression ident
                => _identifierResolution.Resolve(ident.Name, ident.Line, ident.Column, false),
            BinaryExpression or UnaryExpression
                => DriveOperatorExpression(_operatorExpressions.Begin(expr)),
            ThrowExpression or IsExpression or SpreadExpression or AllocExpression
                or MustExpression or StackAllocExpression or TupleExpression or AwaitExpression
                => DrivePassThroughOperand(_passThroughOperands.Begin(expr, _patternReachability)),
            MemberAccessExpression => DriveMemberAccess(_memberAccess.Begin(expr)),
            IndexAccessExpression => DriveIndexAccess(_indexAccess.Begin(expr)),
            CallExpression call => AnalyzeCall(call),
            AssignmentExpression => DriveAssignment(_assignment.Begin(expr)),
            OnSubscriptionExpression on => DriveOnSubscription(_lambdaAnalysis.BeginOnSubscription(
                on, typeof(NSharpLang.Runtime.NSharpEventSubscription))),
            LambdaExpression lambda => DriveLambda(_lambdaAnalysis.BeginLambda(
                lambda, _ambient.CurrentExpectedType, true, false)),
            CastExpression or CheckedExpression or UncheckedExpression or TernaryExpression
                => DriveTargetTypedOperand(_targetTypedOperands.Begin(expr)),
            ArrayLiteralExpression => DriveArrayLiteral(_arrayLiteral.Begin(expr)),
            NewExpression => DriveConstruction(_construction.Begin(expr)),
            ThisExpression => _scopes.CurrentTypeScope() ?? BuiltInTypes.Unknown,
            BaseExpression => _declarationContext.ResolveBaseType(_scopes.CurrentTypeScope()),
            MatchExpression => DriveMatchExpression(_matchExpression.Begin(expr)),
            TypeOfExpression or NameofExpression or SizeOfExpression or DefaultExpression
                => DriveCompileTimeConstant(_compileTimeConstants.Begin(expr, _wellKnownTypes)),
            RangeExpression => DriveRangeExpression(_rangeExpression.Begin(expr)),
            WithExpression => DriveConstruction(_construction.BeginWith(expr)),
            ParenthesizedExpression paren => AnalyzeExpression(paren.Inner),
            _ => BuiltInTypes.Unknown
        };

        return _expressionTail.Finish(expr, type);
    }

    /// <summary>
    /// Performs the steps <see cref="AnalyzerIndexAccess"/> asks for and returns the type it decided.
    /// Every policy about what an index access means — that the receiver decides whether the index is
    /// walked expecting an <c>int</c>, in which order the eight refusals fire and that each of them
    /// ends the walk, that a column slice allocates and is refused outside a write, and what the
    /// element type of an array, a string, a table, a named generic or a reflected indexer actually
    /// is — belongs to the N# owner.
    /// The ONE kind is an operand walk, handed out twice: the receiver, then the index. The
    /// expected-type bracket around the second is opened and closed by the OWNER, not here, because
    /// the C# bracketed a plain expression walk rather than the named-expected-type one, so there is
    /// no lambda fork inside the step.
    /// This loop decides nothing: it performs the one operation it is handed, with the operands it is
    /// handed.
    /// </summary>
    private TypeInfo DriveIndexAccess(IndexAccessState state)
    {
        for (var step = _indexAccess.NextStep(state);
             step != null;
             step = _indexAccess.NextStep(state))
        {
            _indexAccess.Supply(state, AnalyzeExpression(step.Node!));
        }

        return _indexAccess.Result(state);
    }

    /// <summary>
    /// The one step the N#-owned <c>range</c> walk cannot take for itself, and the SMALLEST driver in
    /// the estate. The arm runs in <see cref="AnalyzerRangeExpression"/>, which owns which endpoints
    /// exist and are therefore walked at all, which of the two SoA escapes fires on each and that the
    /// first of them silences the second, what an <c>int</c>-or-<c>System.Index</c> bound is, and the
    /// <c>System.Range</c> the expression always answers whatever its bounds turned out to be.
    /// The ONE kind is a plain operand walk with NOTHING bracketed — no expected type, no scope, no
    /// suppression — which is why this loop carries no operand but the node. It is handed out at most
    /// twice and, for the bare <c>..</c>, not at all.
    /// This loop decides nothing: it performs the one operation it is handed, with the operands it is
    /// handed.
    /// </summary>
    private TypeInfo DriveRangeExpression(RangeExpressionState state)
    {
        for (var step = _rangeExpression.NextStep(state);
             step != null;
             step = _rangeExpression.NextStep(state))
        {
            _rangeExpression.Supply(state, AnalyzeExpression(step.Node!));
        }

        return _rangeExpression.Result(state);
    }

    /// <summary>
    /// The steps the N#-owned call walk cannot take for itself, which are now nothing but the
    /// analyzer's own expression, lambda and semantic-model doors. The walk runs in
    /// <see cref="AnalyzerCallAnalysis"/>, suspends at each step and resumes with the answer, because
    /// the number of times the member-access RECEIVER is analysed depends on which overload the bind
    /// chose — and the bind consumes the first receiver analysis, so no schedule computed up front
    /// reproduces it. Which branch, which node, which expected type, which report, how many receiver
    /// analyses, which reflected candidate is preferred, whose diagnostics are withdrawn and what the
    /// call's type finally is are all the walk's decisions; this loop performs the one operation it is
    /// handed, with the operands it is handed. The reflected bind's own finalising walk is COMPOSED
    /// into that protocol rather than nested inside this loop, so there is still one loop here.
    /// </summary>
    private TypeInfo AnalyzeCall(CallExpression call)
    {
        var state = _callAnalysis.BeginCall(call);
        for (var step = _callAnalysis.NextCallStep(state);
             step != null;
             step = _callAnalysis.NextCallStep(state))
        {
            TypeInfo? answer = null;
            var handled = false;
            switch (step.Kind)
            {
                case 3:
                    _nullFlow.ReportPossibleNullAccess(
                        step.Node!, step.CarriedType!, step.Line, step.Column, step.Text!, step.Flag);
                    break;
                case 4:
                    answer = AnalyzeExpressionWithExpectedType(
                        step.Node!, step.CarriedType, allowUnboundCallableReference: step.Flag);
                    break;
                case 6:
                    answer = AnalyzeExpression(step.Node!);
                    break;
                case 7:
                    _soaEscape.ReportSoaRowEscape(step.Node!, step.Text!);
                    break;
                case 8:
                    handled = _soaDirectColumnCalls.ReportDirectColumnCallIfNeeded(call, step.CarriedType!);
                    break;
                case 14:
                    _semanticModel.RecordExpressionType(
                        call.Callee.Line, call.Callee.Column, step.CarriedType!);
                    break;
                case 15:
                    answer = DriveLambda(_lambdaAnalysis.BeginLambda(
                        step.Lambda!, step.CarriedType, true, step.Flag));
                    break;
            }

            _callAnalysis.SupplyCallStep(state, answer, handled);
        }

        return state.Result;
    }

    private TypeInfo AnalyzeExpressionWithExpectedType(
        Expression expression,
        TypeInfo? expectedType,
        bool allowUnboundCallableReference = false)
    {
        if (expression is LambdaExpression lambda)
            return DriveLambda(_lambdaAnalysis.BeginLambda(lambda, expectedType, true, false));

        var previousExpectedType = _ambient.EnterExpectedTypeIfProvided(expectedType);
        var previousAllowUnboundCallableReference =
            _ambient.EnterAllowUnboundCallableReferenceIfRequested(allowUnboundCallableReference);

        try
        {
            return AnalyzeExpression(expression);
        }
        finally
        {
            _ambient.ExitExpectedType(previousExpectedType);
            _ambient.ExitAllowUnboundCallableReference(previousAllowUnboundCallableReference);
        }
    }

    /// <summary>
    /// The two steps the N#-owned `on` walk cannot take for itself. What may be subscribed to, in
    /// which order its four failures are reported, and which expected type the handler is given are
    /// all the walk's decisions; this loop performs the one operation it is handed. The bare-event
    /// guard around the TARGET is bracketed HERE rather than held by the walk because the guarantee
    /// is that it is restored even if the analysis THROWS — a guarantee an owner-held pair spanning
    /// a suspension cannot keep.
    /// </summary>
    private TypeInfo DriveOnSubscription(OnSubscriptionState state)
    {
        for (var step = _lambdaAnalysis.NextOnStep(state);
             step != null;
             step = _lambdaAnalysis.NextOnStep(state))
        {
            TypeInfo? answer = null;
            switch (step.Kind)
            {
                case 1:
                    var previousAllow = _ambient.EnterAllowEventReference();
                    try
                    {
                        answer = AnalyzeExpression(step.Node!);
                    }
                    finally
                    {
                        _ambient.ExitAllowEventReference(previousAllow);
                    }

                    break;
                case 2:
                    DriveLambda(_lambdaAnalysis.BeginLambda(
                        step.Lambda!, step.ExpectedType, step.ReportInferenceFailure, false));
                    break;
            }

            _lambdaAnalysis.SupplyOnStep(state, answer);
        }

        return state.Result;
    }

    /// <summary>
    /// The steps the N#-owned lambda walk cannot take for itself. The walk runs in
    /// <see cref="AnalyzerLambdaAnalysis"/> and owns everything about a lambda that is a decision:
    /// which signature its expected type names, which parameters are inferred and from where, which
    /// untyped parameter is a hard error, where each parameter is declared, which body shape there
    /// is, what that body is measured against and what the lambda finally answers. This loop
    /// performs the one operation it is handed. Kinds 7 and 8 are GONE: they relayed the
    /// expression-tree validator while that validator was still C#, and it is now
    /// <see cref="AnalyzerExpressionTreeValidator"/>, which the walk holds and calls itself. The
    /// nested-body ambient boundary is bracketed HERE for the same reason `on`'s event guard is: the
    /// guarantee is that it is restored even if the body analysis THROWS.
    /// </summary>
    private FunctionTypeInfo DriveLambda(LambdaAnalysisState state)
    {
        for (var step = _lambdaAnalysis.NextLambdaStep(state);
             step != null;
             step = _lambdaAnalysis.NextLambdaStep(state))
        {
            TypeInfo? answer = null;
            switch (step.Kind)
            {
                case 1:
                    answer = AnalyzeExpressionWithExpectedType(step.Node!, step.ExpectedType);
                    break;
                case 2:
                    PushScope(new Scope(ScopeKind.Function), step.Line, step.Column);
                    break;
                case 3:
                    _declarationPolicy.DeclareSymbol(step.Name!, step.CarriedType, step.Line, step.Column, null, true);
                    break;
                case 4:
                    _scopes.RecordVariable(_semanticModel, step.Name!, step.CarriedType);
                    break;
                case 5:
                    var bodyFrame = _ambient.EnterNestedBody(null, step.CarriedType);
                    try
                    {
                        AnalyzeStatement(step.Body!);
                    }
                    finally
                    {
                        _ambient.ExitNestedBody(bodyFrame);
                    }

                    break;
                case 6:
                    PopScope();
                    break;
            }

            _lambdaAnalysis.SupplyLambdaStep(state, answer);
        }

        return state.Result!;
    }

    /// <summary>
    /// Performs the steps <see cref="AnalyzerArrayLiteral"/> asks for and returns the type it decided.
    /// Every policy about what an array literal means — that a named element type is the answer
    /// whatever the elements turn out to be while an unnamed one is decided by the FIRST element,
    /// that an empty literal takes no steps at all, which word a mismatched element is scolded with,
    /// and which collection targets the backend can actually materialise — belongs to the N# owner.
    /// The ONE kind is an element walk, handed out once per element and bracketed by the owner when
    /// the surrounding annotation named an element type.
    /// This loop decides nothing: it performs the one operation it is handed, with the operands it is
    /// handed.
    /// </summary>
    private TypeInfo DriveArrayLiteral(ArrayLiteralState state)
    {
        for (var step = _arrayLiteral.NextStep(state);
             step != null;
             step = _arrayLiteral.NextStep(state))
        {
            _arrayLiteral.Supply(state, AnalyzeExpression(step.Node!));
        }

        return _arrayLiteral.Result(state);
    }

    /// <summary>
    /// Performs the steps <see cref="AnalyzerConstruction"/> asks for and returns the type it decided.
    /// Every policy about what constructing a value means — which type a `new` names, including the
    /// target-typed form that adopts the annotation and the qualified form that turns out to be a
    /// union case; that a SoA table is built with one int capacity and nothing else; that a sized
    /// array takes a length and no arguments; which member a named initializer entry writes and what
    /// its declared type is under the receiver's substitution; and the assignability gate on that
    /// value, which is the ONLY guard the pipeline has against a mismatched closed generic reaching
    /// the emitter — belongs to the N# owner. It serves BOTH dispatch arms: `new` enters through
    /// <c>Begin</c> and `with` through <c>BeginWith</c>, because they are the same object-initializer
    /// rule asked over a fresh value and over an existing one.
    /// The two kinds are the two DOORS the value walk goes through and the owner names which: kind 1
    /// is the ordinary walk, which the owner brackets itself when the entry named an expected type,
    /// and kind 2 is the named-expected-type walk, which is not that operation with an extra argument
    /// — it forks to the lambda walk for a lambda value, which a `with` entry can have, so the owner
    /// cannot simulate it by writing the slot around a kind 1.
    /// This loop decides nothing: it performs the one operation it is handed, with the operands it is
    /// handed.
    /// </summary>
    private TypeInfo DriveConstruction(ConstructionState state)
    {
        for (var step = _construction.NextStep(state);
             step != null;
             step = _construction.NextStep(state))
        {
            TypeInfo? answer = null;
            switch (step.Kind)
            {
                case 1:
                    answer = AnalyzeExpression(step.Node!);
                    break;
                case 2:
                    answer = AnalyzeExpressionWithExpectedType(step.Node!, step.ExpectedType);
                    break;
            }

            _construction.Supply(state, answer);
        }

        return _construction.Result(state);
    }

    private void PushScope(Scope scope, int startLine, int startColumn)
    {
        _scopes.Push(_semanticModel, scope, startLine, startColumn);
    }

    private void PopScope()
    {
        _scopes.Pop(_semanticModel);
    }

    private void Error(string message, int line, int column)
    {
        Error(ErrorCode.InvalidSyntax, message, line, column);
    }

    private void Error(ErrorCode code, string message, int line, int column, string? suggestion = null, int length = 0)
        => _diagnostics.Report(code, message, line, column, suggestion, length);

    private void Warning(string message, int line, int column)
    {
        Warning(ErrorCode.UnusedVariable, message, line, column);
    }

    private void Warning(ErrorCode code, string message, int line, int column, string? suggestion = null, int length = 0)
        => _diagnostics.Warn(code, message, line, column, suggestion, length);

    private string? GetSourceSnippet(int line) => _diagnostics.SourceSnippet(line);

    /// <summary>
    /// Load a .NET assembly by file path for type resolution (metadata-only via MLC)
    /// </summary>
    public void LoadReferencedAssembly(string assemblyPath)
    {
        if (_mlc == null) return;
        {
            var fullPath = Path.GetFullPath(assemblyPath);
            _metadataResolver?.AddSearchDirectory(Path.GetDirectoryName(fullPath)!);

            if (IsMetadataAssemblyPathAlreadyLoaded(fullPath))
            {
                return;
            }

            AssemblyName assemblyName;
            {
                assemblyName = AssemblyName.GetAssemblyName(fullPath);
            }

            if (IsMetadataAssemblyAlreadyLoaded(assemblyName))
            {
                return;
            }

            var alreadyLoaded = _mlc.GetAssemblies().FirstOrDefault(loadedAssembly =>
                AssemblyName.ReferenceMatchesDefinition(loadedAssembly.GetName(), assemblyName));
            if (alreadyLoaded != null)
            {
                RegisterMetadataAssembly(alreadyLoaded);
                return;
            }

            var assembly = _mlc.LoadFromAssemblyPath(fullPath);
            RegisterMetadataAssembly(assembly);
        }
    }

    /// <summary>
    /// Load a .NET assembly by name (e.g., "System.Runtime") for type resolution (metadata-only via MLC)
    /// </summary>
    public void LoadReferencedAssemblyByName(string assemblyName)
    {
        if (_mlc == null) return;
            if (IsMetadataAssemblyAlreadyLoaded(assemblyName))
            {
                return;
            }

            var assembly = _mlc.LoadFromAssemblyName(assemblyName);
            RegisterMetadataAssembly(assembly);
    }

    private void RegisterMetadataAssembly(Assembly assembly)
    {
        if (_mlcAssemblies.Any(loadedAssembly =>
        {
                return AssemblyName.ReferenceMatchesDefinition(loadedAssembly.GetName(), assembly.GetName());
        }))
        {
            return;
        }

        _mlcAssemblies.Add(assembly);
    }

    private bool IsMetadataAssemblyAlreadyLoaded(AssemblyName assemblyName)
    {
        return _mlcAssemblies.Any(loadedAssembly =>
        {
                return AssemblyName.ReferenceMatchesDefinition(loadedAssembly.GetName(), assemblyName);
        });
    }

    private bool IsMetadataAssemblyAlreadyLoaded(string assemblyName)
    {
        return _mlcAssemblies.Any(loadedAssembly =>
        {
                return string.Equals(loadedAssembly.GetName().Name, assemblyName, StringComparison.OrdinalIgnoreCase);
        });
    }

    private bool IsMetadataAssemblyPathAlreadyLoaded(string assemblyPath)
    {
        var normalizedPath = Path.GetFullPath(assemblyPath);
        return _mlcAssemblies.Any(loadedAssembly =>
        {
                return string.Equals(
                    Path.GetFullPath(loadedAssembly.Location),
                    normalizedPath,
                    StringComparison.OrdinalIgnoreCase);
        });
    }

    /// <summary>
    /// Load system assemblies that are commonly used (initializes MetadataLoadContext)
    /// </summary>
    public void LoadSystemAssemblies()
    {
        _metadataResolver = new NSharpMetadataResolver();

        var runtimeDir = RuntimeEnvironment.GetRuntimeDirectory();
        _metadataResolver.AddSearchDirectory(runtimeDir);
        _metadataResolver.AddSearchDirectory(AppContext.BaseDirectory);

        var searchDir = runtimeDir;
        for (int i = 0; i < 5; i++)
        {
            searchDir = Path.GetDirectoryName(searchDir);
            if (searchDir == null) break;
            if (Path.GetFileName(searchDir) == "shared")
            {
                foreach (var fwDir in new[] { "Microsoft.AspNetCore.App", "Microsoft.NETCore.App" })
                {
                    var fwPath = Path.Combine(searchDir, fwDir);
                    if (!Directory.Exists(fwPath)) continue;
                    foreach (var versionDir in Directory.GetDirectories(fwPath)
                                 .OrderByDescending(Path.GetFileName, NuGetVersionComparer.Instance))
                        _metadataResolver.AddSearchDirectory(versionDir);
                }
                break;
            }
        }

        _mlc = new MetadataLoadContext(_metadataResolver, "System.Runtime");

        var commonAssemblies = new[]
        {
            "System.Runtime",
            "System.Console",
            "System.Collections",
            "System.Linq",
            "System.Linq.Queryable",
            "System.Net.Http",
            "System.Text.Json",
            "System.Threading",
            "System.Threading.Tasks",
            "System.IO.FileSystem",
            "System.Text.RegularExpressions",
            "System.ComponentModel.Annotations",
            "System.Collections.Concurrent",
            "System.Diagnostics.Debug",
            "System.Diagnostics.Process",
            "System.Runtime.InteropServices",
            "System.ObjectModel",
            "System.Linq.Expressions",
            "System.Memory",
            "System.IO.Pipes",
            "System.Net.Primitives",
            "System.Net.Sockets",
            "System.Security.Cryptography",
            "System.Text.Encoding.Extensions",
            "System.Xml.ReaderWriter",
            "System.Private.CoreLib"
        };

        foreach (var assemblyName in commonAssemblies)
        {
            LoadReferencedAssemblyByName(assemblyName);
        }

        _wellKnownTypes = new AnalyzerWellKnownTypes(
            _mlc,
            _mlc.CoreAssembly ?? throw new InvalidOperationException("MLC core assembly not loaded"));
        _clrTypeConversion = new AnalyzerClrTypeConversion(_declarationContext, _wellKnownTypes);
        _assignabilityFacts = new AnalyzerAssignabilityFacts(_declarationContext, _wellKnownTypes);
        _assignability = CreateAssignability();
        _extensionMethodResolution = CreateExtensionMethodResolution();
        _memberResolution = CreateMemberResolution();
        _overloadScoring = CreateOverloadScoring();
        _reflectionArgumentBinder = CreateReflectionArgumentBinder();
        _syntheticCallBinder = CreateSyntheticCallBinder();
        _syntheticCallWalk = CreateSyntheticCallWalk();
        _syntheticCallValidator = CreateSyntheticCallValidator();
        _reflectionCallReporter = CreateReflectionCallReporter();
        _matchExhaustiveness = CreateMatchExhaustiveness();
        _patternShapes = CreatePatternShapes();
        _patternReachability = CreatePatternReachability();
        _patternAnalysis = CreatePatternAnalysis();
        _flowNarrowing = CreateFlowNarrowing();
        _variableDeclaration = CreateVariableDeclaration();
        _writeTargets = CreateWriteTargets();
        _callAnalysis = CreateCallAnalysis();
        _lambdaAnalysis = CreateLambdaAnalysis();
        _soaDirectColumnCalls = CreateSoaDirectColumnCalls();
        _operatorExpressions = CreateOperatorExpressions();
        _typeResolver.SetWellKnownTypes(_wellKnownTypes);
        _identifierResolution.SetMetadataCollaborators(_memberResolution, _wellKnownTypes);
        _memberAccess.SetMetadataCollaborators(_memberResolution, _clrTypeConversion, _extensionMethodResolution, _wellKnownTypes);
        _construction = CreateConstruction();
        _assignment = CreateAssignment();
        _rangeExpression = CreateRangeExpression();
        _matchExpression = CreateMatchExpression();
        _attributeValidator = CreateAttributeValidator();
    }

    public void Dispose()
    {
        if (!_disposed)
        {
            _mlc?.Dispose();
            _mlc = null;
            _wellKnownTypes = null;
            _clrTypeConversion = new AnalyzerClrTypeConversion(_declarationContext, null);
            _assignabilityFacts = new AnalyzerAssignabilityFacts(_declarationContext, null);
            _assignability = CreateAssignability();
            _extensionMethodResolution = CreateExtensionMethodResolution();
            _memberResolution = CreateMemberResolution();
            _overloadScoring = CreateOverloadScoring();
            _reflectionArgumentBinder = CreateReflectionArgumentBinder();
            _syntheticCallBinder = CreateSyntheticCallBinder();
            _syntheticCallWalk = CreateSyntheticCallWalk();
            _syntheticCallValidator = CreateSyntheticCallValidator();
            _reflectionCallReporter = CreateReflectionCallReporter();
            _matchExhaustiveness = CreateMatchExhaustiveness();
            _patternShapes = CreatePatternShapes();
            _patternReachability = CreatePatternReachability();
            _patternAnalysis = CreatePatternAnalysis();
            _flowNarrowing = CreateFlowNarrowing();
            _variableDeclaration = CreateVariableDeclaration();
            _writeTargets = CreateWriteTargets();
            _callAnalysis = CreateCallAnalysis();
            _lambdaAnalysis = CreateLambdaAnalysis();
            _soaDirectColumnCalls = CreateSoaDirectColumnCalls();
            _operatorExpressions = CreateOperatorExpressions();
            _typeResolver.SetWellKnownTypes(null);
            _identifierResolution.SetMetadataCollaborators(_memberResolution, null);
            _memberAccess.SetMetadataCollaborators(_memberResolution, _clrTypeConversion, _extensionMethodResolution, null);
            _construction = CreateConstruction();
            _assignment = CreateAssignment();
            _rangeExpression = CreateRangeExpression();
            _matchExpression = CreateMatchExpression();
            _attributeValidator = CreateAttributeValidator();
            _mlcAssemblies.Clear();
            _disposed = true;
        }
    }

    /// <summary>
    /// Load assemblies from project configuration (References and Dependencies)
    /// </summary>
    public void LoadFromProjectConfig(ProjectConfig config, string? projectDirectory = null)
    {
        projectDirectory ??= Environment.CurrentDirectory;

        foreach (var (packageName, packageVersion) in GetRestoredPackageVersions(projectDirectory))
        {
            _metadataResolver?.PinPackageVersion(packageName, packageVersion);
        }

        if (config.Dependencies != null && config.Dependencies.Count > 0)
        {
            foreach (var reference in config.Dependencies.Where(r => r.Type != ReferenceType.NuGet))
            {
                LoadProjectReference(reference, projectDirectory, config.TargetFramework);
            }

            foreach (var reference in config.Dependencies.Where(r => r.Type == ReferenceType.NuGet))
            {
                if (!string.IsNullOrWhiteSpace(reference.Nuget))
                {
                    _referencedPackageNames.Add(reference.Nuget);
                }

                LoadProjectReference(reference, projectDirectory, config.TargetFramework);
            }
        }

        if (config.TestDependencies != null && config.TestDependencies.Count > 0)
        {
            foreach (var dependency in config.TestDependencies.Where(r => r.Type == ReferenceType.NuGet))
            {
                if (!string.IsNullOrWhiteSpace(dependency.Nuget))
                {
                    _referencedPackageNames.Add(dependency.Nuget);
                }

                if (dependency.Nuget != null)
                {
                    try
                    {
                        LoadReferencedAssemblyByName(dependency.Nuget);
                    }
                    catch (FileNotFoundException)
                    {
                    }
                }
            }
        }

        if (config.Sdk?.Contains("Web") == true)
        {
            var aspNetAssemblies = new[]
            {
                "Microsoft.AspNetCore",
                "Microsoft.AspNetCore.Http",
                "Microsoft.AspNetCore.Http.Abstractions",
                "Microsoft.AspNetCore.Mvc.Core",
                "Microsoft.AspNetCore.Mvc.Abstractions",
                "Microsoft.AspNetCore.Routing",
                "Microsoft.Extensions.DependencyInjection",
                "Microsoft.Extensions.DependencyInjection.Abstractions"
            };

            foreach (var assembly in aspNetAssemblies)
            {
                LoadReferencedAssemblyByName(assembly);
            }
        }
    }

    /// <summary>
    /// Load a single project reference based on its type
    /// </summary>
    private void LoadProjectReference(Reference reference, string projectDirectory, string targetFramework)
    {
        switch (reference.Type)
        {
            case ReferenceType.NuGet:
                LoadNuGetPackage(reference.Nuget!, reference.Version, targetFramework, projectDirectory);
                break;

            case ReferenceType.Dll:
                var dllPath = Path.IsPathRooted(reference.Dll!)
                    ? reference.Dll!
                    : Path.Combine(projectDirectory, reference.Dll!);
                LoadReferencedAssembly(dllPath);
                break;

            case ReferenceType.Project:
                var projectPath = Path.IsPathRooted(reference.Project!)
                    ? reference.Project!
                    : Path.Combine(projectDirectory, reference.Project!);
                LoadProjectReferenceFile(projectPath, targetFramework);
                break;

            case ReferenceType.Framework:
                break;
        }
    }

    /// <summary>
    /// Load a NuGet package assembly
    /// </summary>
    private void LoadNuGetPackage(string packageName, string? version, string targetFramework, string projectDirectory)
    {

        var binPath = Path.Combine(projectDirectory, "bin", "Debug", targetFramework, $"{packageName}.dll");
        if (File.Exists(binPath))
        {
            LoadReferencedAssembly(binPath);
            return;
        }

        version ??= TryGetRestoredPackageVersion(projectDirectory, packageName);

        var nugetCache = Path.Combine(GetNuGetPackagesRoot(), packageName.ToLowerInvariant());

        if (Directory.Exists(nugetCache))
        {
            var versionDir = version != null
                ? Path.Combine(nugetCache, version)
                : NuGetVersionOrder.PickHighestVersionDirectory(Directory.GetDirectories(nugetCache));

            if (versionDir != null && Directory.Exists(versionDir))
            {
                var possiblePaths = new[]
                {
                    Path.Combine(versionDir, "lib", targetFramework, $"{packageName}.dll"),
                    Path.Combine(versionDir, "lib", "net10.0", $"{packageName}.dll"),
                    Path.Combine(versionDir, "lib", "net9.0", $"{packageName}.dll"),
                    Path.Combine(versionDir, "lib", "net8.0", $"{packageName}.dll"),
                    Path.Combine(versionDir, "lib", "netstandard2.1", $"{packageName}.dll"),
                    Path.Combine(versionDir, "lib", "netstandard2.0", $"{packageName}.dll")
                };

                foreach (var path in possiblePaths)
                {
                    if (File.Exists(path))
                    {
                        LoadReferencedAssembly(path);
                        return;
                    }
                }
            }
        }

    }

    private string? TryGetRestoredPackageVersion(string projectDirectory, string packageName)
        => GetRestoredPackageVersions(projectDirectory).TryGetValue(packageName, out var version)
            ? version
            : null;

    /// <summary>
    /// Reads the package versions the project restored from <c>obj/project.assets.json</c>,
    /// keyed by package name. Returns an empty map when the project has no restore output.
    /// </summary>
    private IReadOnlyDictionary<string, string> GetRestoredPackageVersions(string projectDirectory)
    {
        if (_restoredPackageVersionsByProject.TryGetValue(projectDirectory, out var cached))
        {
            return cached;
        }

        var versions = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var assetsPath = Path.Combine(projectDirectory, "obj", "project.assets.json");
        if (File.Exists(assetsPath))
        {
            try
            {
                using var assets = JsonDocument.Parse(File.ReadAllText(assetsPath));
                if (assets.RootElement.TryGetProperty("libraries", out var libraries) &&
                    libraries.ValueKind == JsonValueKind.Object)
                {
                    foreach (var library in libraries.EnumerateObject())
                    {
                        var separator = library.Name.IndexOf('/');
                        if (separator > 0 && separator < library.Name.Length - 1)
                        {
                            versions[library.Name[..separator]] = library.Name[(separator + 1)..];
                        }
                    }
                }
            }
            catch (IOException)
            {
            }
            catch (JsonException)
            {
            }
        }

        _restoredPackageVersionsByProject[projectDirectory] = versions;
        return versions;
    }

    /// <summary>
    /// Load a project reference (either .csproj or project.yml)
    /// </summary>
    private void LoadProjectReferenceFile(string projectPath, string targetFramework)
    {
        var projectDir = Path.GetDirectoryName(projectPath)!;

        if (projectPath.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase))
        {
            var projectName = Path.GetFileNameWithoutExtension(projectPath);
            var outputPath = Path.Combine(projectDir, "bin", "Debug", targetFramework, $"{projectName}.dll");

            {
                LoadReferencedAssembly(outputPath);
            }
        }
        else if (projectPath.EndsWith(".yml", StringComparison.OrdinalIgnoreCase))
        {
            var nsharpProject = ProjectFileParser.Parse(projectPath);
            var outputPath = Path.Combine(projectDir, "bin", "Debug", targetFramework, $"{nsharpProject.EffectiveName}.dll");

            {
                LoadReferencedAssembly(outputPath);
            }
        }
        else
        {
            Console.Error.WriteLine($"Warning: Unknown project reference type: {projectPath}");
        }
    }


    /// <summary>
    /// Custom MetadataAssemblyResolver that dynamically searches directories for assemblies.
    /// Replaces the old AppDomain.AssemblyResolve-based AssemblyResolver.
    /// </summary>
    internal sealed class NSharpMetadataResolver : MetadataAssemblyResolver
    {
        private static readonly string[] Tfms = { "net10.0", "net9.0", "net8.0", "net7.0", "net6.0", "netstandard2.1", "netstandard2.0" };

        private readonly List<string> _searchDirectories = new();
        private readonly Dictionary<string, string> _pinnedPackageVersions = new(StringComparer.OrdinalIgnoreCase);

        internal Dictionary<string, string> LoadFailures { get; } = new(StringComparer.Ordinal);

        private void RecordLoadFailure(string path, Exception exception)
        {
            if (!LoadFailures.ContainsKey(path))
                LoadFailures[path] = $"{exception.GetType().Name}: {exception.Message}";
        }

        public void AddSearchDirectory(string directory)
        {
            if (!string.IsNullOrEmpty(directory) && Directory.Exists(directory) && !_searchDirectories.Contains(directory))
                _searchDirectories.Add(directory);
        }

        /// <summary>
        /// Records the package version a project restored. NuGet-cache fallback scans bind
        /// the pinned version instead of the highest extracted one.
        /// </summary>
        public void PinPackageVersion(string packageName, string version)
        {
            _pinnedPackageVersions[packageName] = version;
        }

        public override Assembly? Resolve(MetadataLoadContext context, AssemblyName assemblyName)
        {
            var simpleName = assemblyName.Name;
            if (simpleName == null) return null;

            foreach (var loadedAssembly in context.GetAssemblies())
            {
                if (string.Equals(loadedAssembly.GetName().Name, simpleName, StringComparison.OrdinalIgnoreCase))
                    return loadedAssembly;
            }

            foreach (var dir in _searchDirectories)
            {
                var dllPath = Path.Combine(dir, $"{simpleName}.dll");
                if (File.Exists(dllPath))
                {
                    try { return context.LoadFromAssemblyPath(dllPath); }
                    catch (Exception ex)
                    {
                        RecordLoadFailure(dllPath, ex);
                        continue;
                    }
                }
            }

            var nugetRoot = Analyzer.GetNuGetPackagesRoot();

            var nugetExact = Path.Combine(nugetRoot, simpleName.ToLowerInvariant());
            var found = TryLoadFromNuGetPackageDir(context, nugetExact, simpleName);
            if (found != null) return found;

            if (Directory.Exists(nugetRoot))
            {
                    var prefix = simpleName.ToLowerInvariant();
                    foreach (var pkgDir in Directory.GetDirectories(nugetRoot))
                    {
                        var dirName = Path.GetFileName(pkgDir);
                        if (dirName != null && dirName.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                        {
                            var result = TryLoadFromNuGetPackageDir(context, pkgDir, simpleName);
                            if (result != null) return result;
                        }
                    }
            }

            return null;
        }

        private Assembly? TryLoadFromNuGetPackageDir(MetadataLoadContext context, string packageDir, string simpleName)
        {
            if (!Directory.Exists(packageDir)) return null;

            var versionDir = PickPackageVersionDirectory(packageDir);
            if (versionDir == null) return null;

            foreach (var tfm in Tfms)
            {
                var dllPath = Path.Combine(versionDir, "lib", tfm, $"{simpleName}.dll");
                if (File.Exists(dllPath))
                {
                    try { return context.LoadFromAssemblyPath(dllPath); }
                    catch (Exception ex)
                    {
                        RecordLoadFailure(dllPath, ex);
                        continue;
                    }
                }
            }
            return null;
        }

        private string? PickPackageVersionDirectory(string packageDir)
        {
            var packageName = Path.GetFileName(packageDir);
            if (packageName != null &&
                _pinnedPackageVersions.TryGetValue(packageName, out var pinnedVersion))
            {
                var pinnedDir = Path.Combine(packageDir, pinnedVersion);
                if (Directory.Exists(pinnedDir))
                    return pinnedDir;
            }

            return NuGetVersionOrder.PickHighestVersionDirectory(Directory.GetDirectories(packageDir));
        }
    }

    /// <summary>
    /// Orders NuGet package version folder names by SemVer precedence: numeric parts compare
    /// numerically and a release outranks its prereleases — unlike ordinal string ordering,
    /// which ranks "0.1.0-beta" above "0.1.0" and "0.10.0" below "0.9.0".
    /// </summary>
    internal static class NuGetVersionOrder
    {
        public static string? PickHighestVersionDirectory(string[] versionDirectories)
            => versionDirectories
                .OrderByDescending(Path.GetFileName, NuGetVersionComparer.Instance)
                .FirstOrDefault();
    }

    internal sealed class NuGetVersionComparer : IComparer<string?>
    {
        public static readonly NuGetVersionComparer Instance = new();

        public int Compare(string? x, string? y)
        {
            if (ReferenceEquals(x, y)) return 0;
            if (x == null) return -1;
            if (y == null) return 1;

            var parsedX = TryParse(x, out var numbersX, out var prereleaseX);
            var parsedY = TryParse(y, out var numbersY, out var prereleaseY);
            if (!parsedX || !parsedY)
            {
                return parsedX == parsedY ? string.CompareOrdinal(x, y) : (parsedX ? 1 : -1);
            }

            for (var i = 0; i < numbersX.Length; i++)
            {
                var byNumber = numbersX[i].CompareTo(numbersY[i]);
                if (byNumber != 0) return byNumber;
            }

            if (prereleaseX.Length == 0) return prereleaseY.Length == 0 ? 0 : 1;
            if (prereleaseY.Length == 0) return -1;
            return ComparePrereleaseIdentifiers(prereleaseX, prereleaseY);
        }

        private static bool TryParse(string version, out long[] numbers, out string prerelease)
        {
            numbers = new long[4];
            prerelease = string.Empty;

            var metadataStart = version.IndexOf('+');
            if (metadataStart >= 0)
                version = version[..metadataStart];

            var prereleaseStart = version.IndexOf('-');
            if (prereleaseStart >= 0)
            {
                prerelease = version[(prereleaseStart + 1)..];
                version = version[..prereleaseStart];
            }

            var parts = version.Split('.');
            if (parts.Length is < 1 or > 4) return false;

            for (var i = 0; i < parts.Length; i++)
            {
                if (!long.TryParse(parts[i], NumberStyles.None, CultureInfo.InvariantCulture, out numbers[i]))
                    return false;
            }

            return true;
        }

        private static int ComparePrereleaseIdentifiers(string x, string y)
        {
            var identifiersX = x.Split('.');
            var identifiersY = y.Split('.');
            for (var i = 0; i < Math.Max(identifiersX.Length, identifiersY.Length); i++)
            {
                if (i >= identifiersX.Length) return -1;
                if (i >= identifiersY.Length) return 1;

                var numericX = long.TryParse(identifiersX[i], NumberStyles.None, CultureInfo.InvariantCulture, out var numberX);
                var numericY = long.TryParse(identifiersY[i], NumberStyles.None, CultureInfo.InvariantCulture, out var numberY);
                if (numericX && numericY)
                {
                    var byNumber = numberX.CompareTo(numberY);
                    if (byNumber != 0) return byNumber;
                }
                else if (numericX != numericY)
                {
                    return numericX ? -1 : 1;
                }
                else
                {
                    var byText = string.CompareOrdinal(identifiersX[i], identifiersY[i]);
                    if (byText != 0) return byText;
                }
            }

            return 0;
        }
    }
}
