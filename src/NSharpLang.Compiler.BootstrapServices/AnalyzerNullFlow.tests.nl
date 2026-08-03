namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast

// Native contracts for what the analyzer believes about null at a point in the program.
//
// THE ORDER OF THE FIVE ANSWERS IS THE CONTRACT, not just their values. `GetExpressionNullState`
// answers syntactically FIRST — a `null` literal is null and a `new` is not-null no matter what
// fact the scope holds for the same text — and only then consults the recorded fact for the
// expression's stable path, and only then the type's default. A test that recorded a fact and read
// a literal would pass under any ordering; the tests here record a fact and read the SAME PATH
// through both a syntactic arm and a path arm, so a re-ordering fails.
//
// OBLIVIOUS IS NOT NOT-NULL, and that distinction is the whole reason NL905 is trustworthy.
// External metadata whose nullability the analyzer was never told is OBLIVIOUS, which is unsafe for
// nothing and safe for nothing — it simply does not report. A reflected CLR VALUE type is the one
// reflected shape that answers NOT-NULL, and `Nullable<T>` is excluded from it by name.
//
// THE DEDUP LOG KEYS ON FOUR THINGS and the tests pin all four: the same line, column, path and
// operation reports once, and changing ANY of them reports again.

class NullFlowHarness {
    Owner: AnalyzerNullFlow
    Errors: List<CompilerError>
    Scopes: AnalyzerScopeStack
    Context: AnalyzerDeclarationContext

    constructor(
        owner: AnalyzerNullFlow,
        errors: List<CompilerError>,
        scopes: AnalyzerScopeStack,
        context: AnalyzerDeclarationContext) {
        Owner = owner
        Errors = errors
        Scopes = scopes
        Context = context
    }
}

func NullFlowDefault(): NullFlowHarness {
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
    provider := new AnalyzerProjectSourceProvider()
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    spans := new AnalyzerDiagnosticSpans(diagnostics)

    return new NullFlowHarness(
        new AnalyzerNullFlow(diagnostics, spans, scopes, context),
        errors,
        scopes,
        context)
}

func NfName(name: string): IdentifierExpression {
    return new IdentifierExpression(name, 4, 7)
}

func NfNull(): NullLiteralExpression {
    return new NullLiteralExpression(4, 7)
}

func NfMember(receiver: string, memberName: string, nullConditional: bool): MemberAccessExpression {
    return new MemberAccessExpression(NfName(receiver), memberName, nullConditional, 4, 7)
}

func NfNullable(inner: TypeInfo): NullableTypeInfo {
    return new NullableTypeInfo(inner)
}

// `typeof(Nullable<int>)` does not emit and `Nullable<>` does not parse, so the closed generic is
// built at run time. It is the same `Type` object the analyzer sees for a reflected `int?`, which
// is the whole point of the contract below: a CLR value type that IS a `Nullable<T>` must answer
// OBLIVIOUS rather than taking the value-type arm.
func NfNullableInt(): Type {
    definition := Type.GetType("System.Nullable`1")
    if definition == null {
        throw new InvalidOperationException("System.Nullable`1 was not loadable.")
    }

    arguments := new Type[](1)
    arguments[0] = typeof(int)
    return definition.MakeGenericType(arguments)
}

func NfReflected(clrType: Type): ReflectionTypeInfo {
    return new ReflectionTypeInfo(clrType)
}

// ── the state of one expression ───────────────────────────────────────────

test "a null literal is NULL regardless of the type handed in" {
    harness := NullFlowDefault()

    assert harness.Owner.GetExpressionNullState(NfNull(), BuiltInTypes.String) == NullState.Null
}
test "a new, an array literal, a lambda and an interpolation are all NOT-NULL" {
    harness := NullFlowDefault()
    newExpr := new NewExpression(null, new List<Argument>(), null, 4, 7)
    arrayLiteral := new ArrayLiteralExpression(new List<Expression>(), false, 4, 7)
    lambda := new LambdaExpression(new List<Parameter>(), NfNull(), null, 4, 7)
    interpolated := new InterpolatedStringExpression(new List<InterpolatedStringPart>(), 4, 7)
    nullableString: TypeInfo = NfNullable(BuiltInTypes.String)

    assert harness.Owner.GetExpressionNullState(newExpr, nullableString) == NullState.NotNull
    assert harness.Owner.GetExpressionNullState(arrayLiteral, nullableString) == NullState.NotNull
    assert harness.Owner.GetExpressionNullState(lambda, nullableString) == NullState.NotNull
    assert harness.Owner.GetExpressionNullState(interpolated, nullableString) == NullState.NotNull
}
test "every literal kind, typeof and nameof are NOT-NULL" {
    harness := NullFlowDefault()
    nullableString: TypeInfo = NfNullable(BuiltInTypes.String)

    assert harness.Owner.GetExpressionNullState(new StringLiteralExpression("a", 4, 7), nullableString)
        == NullState.NotNull
    assert harness.Owner.GetExpressionNullState(new IntLiteralExpression("1", 4, 7), nullableString)
        == NullState.NotNull
    assert harness.Owner.GetExpressionNullState(new FloatLiteralExpression("1.0", 4, 7), nullableString)
        == NullState.NotNull
    assert harness.Owner.GetExpressionNullState(new CharLiteralExpression("a", 4, 7), nullableString)
        == NullState.NotNull
    assert harness.Owner.GetExpressionNullState(new BoolLiteralExpression(true, 4, 7), nullableString)
        == NullState.NotNull
    assert harness.Owner.GetExpressionNullState(
        new TypeOfExpression(new SimpleTypeReference("int", 0, 0), 4, 7), nullableString) == NullState.NotNull
    assert harness.Owner.GetExpressionNullState(new NameofExpression(NfName("x"), 4, 7), nullableString)
        == NullState.NotNull
}
test "a parenthesized expression answers whatever its inner expression answers" {
    harness := NullFlowDefault()
    wrapped := new ParenthesizedExpression(NfNull(), 4, 7)

    assert harness.Owner.GetExpressionNullState(wrapped, BuiltInTypes.String) == NullState.Null
}
test "a NULL-CONDITIONAL member access is MAYBE-NULL whatever its receiver says" {
    harness := NullFlowDefault()

    assert harness.Owner.GetExpressionNullState(NfMember("box", "Value", true), BuiltInTypes.String)
        == NullState.MaybeNull
}
test "a NULL-CONDITIONAL index access is MAYBE-NULL" {
    harness := NullFlowDefault()
    index := new IndexAccessExpression(NfName("items"), new IntLiteralExpression("0", 4, 7), true, 4, 7)

    assert harness.Owner.GetExpressionNullState(index, BuiltInTypes.String) == NullState.MaybeNull
}
test "a PLAIN member access is not maybe-null by construction" {
    harness := NullFlowDefault()

    assert harness.Owner.GetExpressionNullState(NfMember("box", "Value", false), BuiltInTypes.String)
        == NullState.NotNull
}
test "a RECORDED fact for the stable path wins over the type's default" {
    harness := NullFlowDefault()
    harness.Scopes.SetNullStateInCurrentScope("x", NullState.MaybeNull)

    assert harness.Owner.GetExpressionNullState(NfName("x"), BuiltInTypes.String) == NullState.MaybeNull
}
test "with no recorded fact the TYPE's default answers" {
    harness := NullFlowDefault()

    assert harness.Owner.GetExpressionNullState(NfName("x"), BuiltInTypes.String) == NullState.NotNull
    assert harness.Owner.GetExpressionNullState(NfName("x"), NfNullable(BuiltInTypes.String))
        == NullState.MaybeNull
}
test "THE SYNTACTIC ARMS RUN FIRST: a recorded fact for a path does not change a literal's answer" {
    harness := NullFlowDefault()
    harness.Scopes.SetNullStateInCurrentScope("x", NullState.MaybeNull)
    // Same scope, same recorded fact — but a `new` is answered before any path is computed.
    newExpr := new NewExpression(null, new List<Argument>(), null, 4, 7)

    assert harness.Owner.GetExpressionNullState(NfName("x"), BuiltInTypes.String) == NullState.MaybeNull
    assert harness.Owner.GetExpressionNullState(newExpr, BuiltInTypes.String) == NullState.NotNull
}
test "a MEMBER PATH carries its own recorded fact" {
    harness := NullFlowDefault()
    harness.Scopes.SetNullStateInCurrentScope("box.Value", NullState.Null)

    assert harness.Owner.GetExpressionNullState(NfMember("box", "Value", false), BuiltInTypes.String)
        == NullState.Null
}

// ── the default a type implies ────────────────────────────────────────────

test "the null TYPE defaults to NULL" {
    harness := NullFlowDefault()

    assert harness.Owner.GetDefaultNullState(BuiltInTypes.Null) == NullState.Null
}
test "a nullable defaults to MAYBE-NULL and an unknown to UNKNOWN" {
    harness := NullFlowDefault()

    assert harness.Owner.GetDefaultNullState(NfNullable(BuiltInTypes.String)) == NullState.MaybeNull
    assert harness.Owner.GetDefaultNullState(BuiltInTypes.Unknown) == NullState.Unknown
}
test "a reflected CLR VALUE type defaults to NOT-NULL" {
    harness := NullFlowDefault()

    assert harness.Owner.GetDefaultNullState(NfReflected(typeof(int))) == NullState.NotNull
}
test "a reflected Nullable<T> is OBLIVIOUS, not not-null — the underlying-type test excludes it" {
    harness := NullFlowDefault()

    assert harness.Owner.GetDefaultNullState(NfReflected(NfNullableInt())) == NullState.Oblivious
}
test "a reflected REFERENCE type is OBLIVIOUS: unannotated metadata is not a confident answer" {
    harness := NullFlowDefault()

    assert harness.Owner.GetDefaultNullState(NfReflected(typeof(string))) == NullState.Oblivious
}
// THE REFLECTED ARM THROUGH A REAL MetadataLoadContext, which is the only way the analyzer ever
// reaches it in production: an external type is an `EcmaDefinitionType` read out of a load context,
// never a live runtime `Type`. The contract that matters is the LAST one — through the MLC,
// `Nullable.GetUnderlyingType` compares the context's `Nullable\`1` against the LIVE `typeof(Nullable<>)`
// and they are different types, so an external `int?` takes the VALUE-TYPE arm and answers NOT-NULL
// where a live `int?` answers OBLIVIOUS. That divergence is `Analyzer.cs`'s behaviour verbatim and it
// is pinned rather than fixed.
func NfMlcType(loadContext: MetadataLoadContext, fullName: string): Type {
    core := loadContext.LoadFromAssemblyName("System.Runtime")
    resolved := core.GetType(fullName)
    if resolved == null {
        throw new InvalidOperationException("The load context does not define '" + fullName + "'.")
    }

    return resolved
}

test "an MLC-resolved VALUE type defaults to NOT-NULL and an MLC-resolved REFERENCE type to OBLIVIOUS" {
    harness := NullFlowDefault()
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        loadContext := scan.Context
        assert loadContext != null
        intType := NfMlcType(loadContext, "System.Int32")
        stringType := NfMlcType(loadContext, "System.String")
        // The types really are the LOAD CONTEXT'S, not the live runtime's.
        assert intType != typeof(int)
        assert stringType != typeof(string)

        assert harness.Owner.GetDefaultNullState(NfReflected(intType)) == NullState.NotNull
        assert harness.Owner.GetDefaultNullState(NfReflected(stringType)) == NullState.Oblivious
    } finally {
        scan.Dispose()
    }
}
test "an MLC-resolved Nullable<int> takes the VALUE-TYPE arm, where a LIVE one takes the oblivious arm" {
    harness := NullFlowDefault()
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        loadContext := scan.Context
        assert loadContext != null
        definition := NfMlcType(loadContext, "System.Nullable`1")
        arguments := new Type[](1)
        arguments[0] = NfMlcType(loadContext, "System.Int32")
        externalNullable := definition.MakeGenericType(arguments)

        // Through the load context `Nullable.GetUnderlyingType` answers null — it tests against the
        // LIVE `Nullable<>` — so the value-type arm wins and the answer is NOT-NULL.
        assert harness.Owner.GetDefaultNullState(NfReflected(externalNullable)) == NullState.NotNull
        // The live one, for contrast, is OBLIVIOUS.
        assert harness.Owner.GetDefaultNullState(NfReflected(NfNullableInt())) == NullState.Oblivious
    } finally {
        scan.Dispose()
    }
}
test "an MLC-resolved receiver reports NL905 only when the flow says so, never from the type alone" {
    harness := NullFlowDefault()
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        loadContext := scan.Context
        assert loadContext != null
        stringType: TypeInfo = NfReflected(NfMlcType(loadContext, "System.String"))

        // OBLIVIOUS from the type alone: silent.
        harness.Owner.ReportPossibleNullAccess(NfName("x"), stringType, 4, 7, "dereference", false)
        assert harness.Errors.Count == 0

        // A recorded flow fact overrides it and the report fires.
        harness.Scopes.SetNullStateInCurrentScope("x", NullState.MaybeNull)
        harness.Owner.ReportPossibleNullAccess(NfName("x"), stringType, 4, 7, "dereference", false)
        assert harness.Errors.Count == 1
        assert harness.Errors[0].Message == "Possible null dereference: `x` is maybe-null"
    } finally {
        scan.Dispose()
    }
}
test "every other type defaults to NOT-NULL" {
    harness := NullFlowDefault()

    assert harness.Owner.GetDefaultNullState(BuiltInTypes.String) == NullState.NotNull
    assert harness.Owner.GetDefaultNullState(BuiltInTypes.Int) == NullState.NotNull
    assert harness.Owner.GetDefaultNullState(new AnonymousUnionTypeInfo(new List<TypeInfo>())) == NullState.NotNull
}

// ── unsafety ──────────────────────────────────────────────────────────────

test "NULL and MAYBE-NULL are unsafe; NOT-NULL, OBLIVIOUS and UNKNOWN are not" {
    assert AnalyzerNullFlow.IsUnsafeNullState(NullState.Null)
    assert AnalyzerNullFlow.IsUnsafeNullState(NullState.MaybeNull)
    assert !AnalyzerNullFlow.IsUnsafeNullState(NullState.NotNull)
    assert !AnalyzerNullFlow.IsUnsafeNullState(NullState.Oblivious)
    assert !AnalyzerNullFlow.IsUnsafeNullState(NullState.Unknown)
}

// ── the flow type ─────────────────────────────────────────────────────────

test "a NOT-NULL nullable reads as its inner type" {
    harness := NullFlowDefault()
    nullable := NfNullable(BuiltInTypes.String)

    assert BuiltInTypes.Is(harness.Owner.ApplyNullabilityFlowType(nullable, NullState.NotNull), BuiltInTypes.String)
}
test "a MAYBE-NULL nullable keeps its nullability, and a non-nullable is never rewritten" {
    harness := NullFlowDefault()
    nullable: TypeInfo = NfNullable(BuiltInTypes.String)

    assert harness.Owner.ApplyNullabilityFlowType(nullable, NullState.MaybeNull) == nullable
    assert BuiltInTypes.Is(
        harness.Owner.ApplyNullabilityFlowType(BuiltInTypes.String, NullState.NotNull),
        BuiltInTypes.String)
}
test "UNDER SUPPRESSION nothing collapses, and the flag restores" {
    harness := NullFlowDefault()
    nullable: TypeInfo = NfNullable(BuiltInTypes.String)

    assert !harness.Owner.SuppressFlowType
    harness.Owner.SetSuppressFlowType(true)
    assert harness.Owner.SuppressFlowType
    assert harness.Owner.ApplyNullabilityFlowType(nullable, NullState.NotNull) == nullable
    harness.Owner.SetSuppressFlowType(false)
    assert BuiltInTypes.Is(harness.Owner.ApplyNullabilityFlowType(nullable, NullState.NotNull), BuiltInTypes.String)
}
test "BeginAnalysis clears the suppression flag" {
    harness := NullFlowDefault()
    harness.Owner.SetSuppressFlowType(true)

    harness.Owner.BeginAnalysis()

    assert !harness.Owner.SuppressFlowType
}

// ── the NL905 report ──────────────────────────────────────────────────────

test "a NULL-CONDITIONAL access is silent by construction" {
    harness := NullFlowDefault()
    harness.Scopes.SetNullStateInCurrentScope("x", NullState.MaybeNull)

    harness.Owner.ReportPossibleNullAccess(NfName("x"), BuiltInTypes.String, 4, 7, "dereference", true)

    assert harness.Errors.Count == 0
}
test "a NOT-NULL or OBLIVIOUS receiver is silent" {
    harness := NullFlowDefault()
    harness.Scopes.SetNullStateInCurrentScope("x", NullState.NotNull)
    harness.Scopes.SetNullStateInCurrentScope("y", NullState.Oblivious)

    harness.Owner.ReportPossibleNullAccess(NfName("x"), BuiltInTypes.String, 4, 7, "dereference", false)
    harness.Owner.ReportPossibleNullAccess(NfName("y"), BuiltInTypes.String, 5, 7, "dereference", false)

    assert harness.Errors.Count == 0
}
test "a MAYBE-NULL dereference reports NL905 with its message and its suggestion" {
    harness := NullFlowDefault()
    harness.Scopes.SetNullStateInCurrentScope("x", NullState.MaybeNull)

    harness.Owner.ReportPossibleNullAccess(NfName("x"), BuiltInTypes.String, 4, 7, "dereference", false)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Code == ErrorCode.PossibleNullAccess
    assert harness.Errors[0].Message == "Possible null dereference: `x` is maybe-null"
    assert harness.Errors[0].Suggestion
        == "Use '?.', add a '??' fallback, guard with 'if x == null { return }', or explicitly assert after proving 'x' is not null."
}
test "an INDEX operation carries its own wording" {
    harness := NullFlowDefault()
    harness.Scopes.SetNullStateInCurrentScope("x", NullState.Null)

    harness.Owner.ReportPossibleNullAccess(NfName("x"), BuiltInTypes.String, 4, 7, "index", false)

    assert harness.Errors[0].Message == "Possible null index: `x` is null"
    assert harness.Errors[0].Suggestion
        == "Use '?[', add a '??' fallback, guard with 'if x == null { return }', or explicitly assert after proving 'x' is not null."
}
test "a CALL operation is the one whose message is not built from the operation word" {
    harness := NullFlowDefault()
    harness.Scopes.SetNullStateInCurrentScope("x", NullState.MaybeNull)

    harness.Owner.ReportPossibleNullAccess(NfName("x"), BuiltInTypes.String, 4, 7, "call", false)

    assert harness.Errors[0].Message == "Possible null call: `x` is maybe-null"
    assert harness.Errors[0].Suggestion
        == "Guard with 'if x == null { return }', use '?.' when calling through a member, or explicitly assert after proving 'x' is not null."
}
test "an UNRECOGNISED operation takes the fallback suggestion and the operation-word message" {
    harness := NullFlowDefault()
    harness.Scopes.SetNullStateInCurrentScope("x", NullState.MaybeNull)

    harness.Owner.ReportPossibleNullAccess(NfName("x"), BuiltInTypes.String, 4, 7, "await", false)

    assert harness.Errors[0].Message == "Possible null await: `x` is maybe-null"
    assert harness.Errors[0].Suggestion
        == "Guard with 'if x == null { return }' or add a fallback before using 'x'."
}
test "a receiver with NO stable path renders as `this value`" {
    harness := NullFlowDefault()
    receiver := new CallExpression(NfName("Get"), new List<Argument>(), null, 4, 7)

    harness.Owner.ReportPossibleNullAccess(receiver, NfNullable(BuiltInTypes.String), 4, 7, "dereference", false)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Possible null dereference: `this value` is maybe-null"
}
test "THE LOG REPORTS ONCE for the same line, column, path and operation" {
    harness := NullFlowDefault()
    harness.Scopes.SetNullStateInCurrentScope("x", NullState.MaybeNull)

    harness.Owner.ReportPossibleNullAccess(NfName("x"), BuiltInTypes.String, 4, 7, "dereference", false)
    harness.Owner.ReportPossibleNullAccess(NfName("x"), BuiltInTypes.String, 4, 7, "dereference", false)

    assert harness.Errors.Count == 1
}
test "changing the OPERATION reports again, and so does changing the POSITION" {
    harness := NullFlowDefault()
    harness.Scopes.SetNullStateInCurrentScope("x", NullState.MaybeNull)

    harness.Owner.ReportPossibleNullAccess(NfName("x"), BuiltInTypes.String, 4, 7, "dereference", false)
    harness.Owner.ReportPossibleNullAccess(NfName("x"), BuiltInTypes.String, 4, 7, "index", false)
    harness.Owner.ReportPossibleNullAccess(NfName("x"), BuiltInTypes.String, 5, 7, "dereference", false)
    harness.Owner.ReportPossibleNullAccess(NfName("x"), BuiltInTypes.String, 4, 8, "dereference", false)

    assert harness.Errors.Count == 4
}
test "changing the PATH reports again at the same position" {
    harness := NullFlowDefault()
    harness.Scopes.SetNullStateInCurrentScope("a", NullState.MaybeNull)
    harness.Scopes.SetNullStateInCurrentScope("b", NullState.MaybeNull)

    harness.Owner.ReportPossibleNullAccess(NfName("a"), BuiltInTypes.String, 4, 7, "dereference", false)
    harness.Owner.ReportPossibleNullAccess(NfName("b"), BuiltInTypes.String, 4, 7, "dereference", false)

    assert harness.Errors.Count == 2
}
test "BeginAnalysis clears the report log so a second analysis says it again" {
    harness := NullFlowDefault()
    harness.Scopes.SetNullStateInCurrentScope("x", NullState.MaybeNull)

    harness.Owner.ReportPossibleNullAccess(NfName("x"), BuiltInTypes.String, 4, 7, "dereference", false)
    harness.Owner.BeginAnalysis()
    harness.Owner.ReportPossibleNullAccess(NfName("x"), BuiltInTypes.String, 4, 7, "dereference", false)

    assert harness.Errors.Count == 2
}
test "the report is graded on the RECEIVER's state, which may come from its type alone" {
    harness := NullFlowDefault()

    harness.Owner.ReportPossibleNullAccess(
        NfName("x"), NfNullable(BuiltInTypes.String), 4, 7, "dereference", false)

    assert harness.Errors.Count == 1
    assert harness.Errors[0].Message == "Possible null dereference: `x` is maybe-null"
}

// ── what an assignment does to the fact ───────────────────────────────────

test "an assignment to a target with NO stable path records nothing" {
    harness := NullFlowDefault()
    target := new CallExpression(NfName("Get"), new List<Argument>(), null, 4, 7)

    harness.Owner.UpdateNullStateAfterAssignment(target, NfNull(), BuiltInTypes.String, BuiltInTypes.Null)

    assert !harness.Scopes.HasNullState("Get")
}
test "assigning null records NULL for the target's path" {
    harness := NullFlowDefault()

    harness.Owner.UpdateNullStateAfterAssignment(
        NfName("x"), NfNull(), NfNullable(BuiltInTypes.String), BuiltInTypes.Null)

    assert harness.Scopes.NullStateOrUnknown("x") == NullState.Null
}
test "assigning a NEW records NOT-NULL even into a nullable target" {
    harness := NullFlowDefault()
    newExpr := new NewExpression(null, new List<Argument>(), null, 4, 7)

    harness.Owner.UpdateNullStateAfterAssignment(
        NfName("x"), newExpr, NfNullable(BuiltInTypes.String), BuiltInTypes.String)

    assert harness.Scopes.NullStateOrUnknown("x") == NullState.NotNull
}
test "an UNKNOWN value state falls back to the TARGET type's default, not the value's" {
    harness := NullFlowDefault()

    harness.Owner.UpdateNullStateAfterAssignment(
        NfName("x"), NfName("src"), NfNullable(BuiltInTypes.String), BuiltInTypes.Unknown)

    assert harness.Scopes.NullStateOrUnknown("x") == NullState.MaybeNull
}
test "a recorded fact for the VALUE's path flows to the target" {
    harness := NullFlowDefault()
    harness.Scopes.SetNullStateInCurrentScope("src", NullState.MaybeNull)

    harness.Owner.UpdateNullStateAfterAssignment(
        NfName("x"), NfName("src"), BuiltInTypes.String, BuiltInTypes.String)

    assert harness.Scopes.NullStateOrUnknown("x") == NullState.MaybeNull
}
test "an assignment INVALIDATES the facts derived from the target's path" {
    harness := NullFlowDefault()
    harness.Scopes.SetNullStateInCurrentScope("box", NullState.NotNull)
    harness.Scopes.SetNullStateInCurrentScope("box.Value", NullState.NotNull)

    harness.Owner.UpdateNullStateAfterAssignment(
        NfName("box"), NfNull(), NfNullable(BuiltInTypes.String), BuiltInTypes.Null)

    assert harness.Scopes.NullStateOrUnknown("box") == NullState.Null
    assert !harness.Scopes.HasNullState("box.Value")
}
