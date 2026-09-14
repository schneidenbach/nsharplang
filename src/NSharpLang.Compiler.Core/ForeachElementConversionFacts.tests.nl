namespace NSharpLang.Compiler

import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler.Ast


// THE CONVERSION RULE AN ANNOTATED LOOP VARIABLE ANSWERS TO, asked directly.
//
// The oracle it consults is the ORDINARY assignability oracle, built here exactly as the analyzer
// builds it, so these contracts are about the RULE's five questions and not about a private copy of
// what "converts" means.
func ConversionAssignability(): AnalyzerAssignability {
    context := new AnalyzerDeclarationContext()
    context.Reset(".", new List<Assembly>())
    provider := new AnalyzerProjectSourceProvider()
    diagnostics := new AnalyzerDiagnosticSink(new List<CompilerError>(), provider)
    model := new SemanticModel()
    scopes := new AnalyzerScopeStack()
    scopes.Push(model, new Scope(ScopeKind.Global), 1, 1)
    discovery := new AnalyzerProjectTypeDiscovery(provider, context, new List<string>(), new Dictionary<string, string>(StringComparer.Ordinal))
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    resolver := new AnalyzerTypeResolver(scopes, context, discovery, probe, diagnostics, new Dictionary<string, string>(StringComparer.Ordinal), new Dictionary<string, Dictionary<string, TypeInfo>>(StringComparer.Ordinal), new Dictionary<string, Dictionary<string, SymbolDeclaration>>(StringComparer.Ordinal), model, new BindingMap())
    substitution := new AnalyzerTypeSubstitution(scopes, context, resolver)
    facts := new AnalyzerAssignabilityFacts(context, null)
    structural := new AnalyzerStructuralAssignability(resolver, probe)
    clrConversion := new AnalyzerClrTypeConversion(context, null)
    guard := new AnalyzerImplicitConversionGuard()
    return new AnalyzerAssignability(context, facts, structural, substitution, clrConversion, guard)
}

func Converts(elementType: TypeInfo, declaredType: TypeInfo): bool {
    return ForeachElementConversionFacts.IsConvertible(elementType, declaredType, ConversionAssignability())
}

func ConversionClass(name: string): TypeInfo {
    declared: TypeInfo = new ClassTypeInfo(name, 1, 1, false, null, new TypeReference[](0), new TypeParameter[](0), new ParameterDeclarationInfo[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0), true)
    return declared
}

test "AN IDENTITY AND AN IMPLICIT CONVERSION ARE BOTH ACCEPTED — THE EXPLICIT SET CONTAINS THE IMPLICIT ONE" {
    assert Converts(BuiltInTypes.Int, BuiltInTypes.Int)
    assert Converts(BuiltInTypes.Int, BuiltInTypes.Long)
    assert Converts(BuiltInTypes.Int, BuiltInTypes.Double)
    assert Converts(BuiltInTypes.String, BuiltInTypes.Object)
}

// THE REVERSE OF AN IMPLICIT CONVERSION IS THE EXPLICIT ONE, and asking the same oracle BACKWARDS is
// how a downcast and an unboxing are identified without a second classification.
test "A DOWNCAST AND AN UNBOXING ARE ACCEPTED BECAUSE THE REVERSE CONVERSION EXISTS" {
    assert Converts(BuiltInTypes.Object, BuiltInTypes.String)
    assert Converts(BuiltInTypes.Object, BuiltInTypes.Int)
    assert Converts(BuiltInTypes.Long, BuiltInTypes.Int)
}

test "EVERY PAIR OF NUMERIC TYPES CONVERTS, INCLUDING THE NARROWING ONES" {
    assert Converts(BuiltInTypes.Double, BuiltInTypes.Byte)
    assert Converts(BuiltInTypes.Char, BuiltInTypes.Int)
    assert Converts(BuiltInTypes.Decimal, BuiltInTypes.Float)
}

// `bool` TAKES PART IN NO NUMERIC CONVERSION, so it is refused against every numeric type in both
// directions — the one built-in that is not a number even though it fits in the same slot.
test "bool AND string CONVERT TO NO NUMBER IN EITHER DIRECTION" {
    assert !Converts(BuiltInTypes.Bool, BuiltInTypes.Int)
    assert !Converts(BuiltInTypes.Int, BuiltInTypes.Bool)
    assert !Converts(BuiltInTypes.Int, BuiltInTypes.String)
    assert !Converts(BuiltInTypes.String, BuiltInTypes.Int)
}

// TWO UNRELATED CLASSES CONVERT IN NEITHER DIRECTION, and that is the shape NL330 exists to report.
test "TWO UNRELATED DECLARED CLASSES ARE REFUSED" {
    assert !Converts(ConversionClass("Widget"), ConversionClass("Gadget"))
}

// AN INTERFACE ON EITHER SIDE IS ADMITTED. A conversion to or from an interface is explicit for any
// type not sealed against it, and refusing a legal one would refuse a correct program — while
// accepting an impossible one costs only the InvalidCastException the author asked for.
test "AN INTERFACE ON EITHER SIDE IS ADMITTED" {
    contract: TypeInfo = new InterfaceTypeInfo("Readable", 1, 1, false, new TypeReference[](0), new TypeParameter[](0), new DeclaredMemberInfo[](0), new NestedTypeInfo[](0))
    assert Converts(contract, ConversionClass("Widget"))
    assert Converts(ConversionClass("Widget"), contract)
}

// A TYPE THE RULE CANNOT MEASURE IS SILENT: `unknown` means an earlier diagnostic already fired, and
// an external type is a bare NAME with no base, no members and no interfaces, so every relation it
// takes part in would answer "no" for want of information rather than because it is impossible.
test "AN unknown OR EXTERNAL TYPE ON EITHER SIDE IS SILENT" {
    external: TypeInfo = new ExternalTypeInfo("Some.Foreign.Type")
    assert Converts(BuiltInTypes.Unknown, BuiltInTypes.String)
    assert Converts(BuiltInTypes.String, BuiltInTypes.Unknown)
    assert Converts(external, BuiltInTypes.Int)
    assert Converts(BuiltInTypes.Int, external)
}

test "THE SILENCE PREDICATE ANSWERS FOR THE THREE unknown FLAVOURS AND FOR EXTERNAL TYPES ALONE" {
    assert ForeachElementConversionFacts.IsSilent(BuiltInTypes.Unknown)
    assert ForeachElementConversionFacts.IsSilent(BuiltInTypes.InferenceHole)
    assert ForeachElementConversionFacts.IsSilent(BuiltInTypes.DeferredExternal)
    assert ForeachElementConversionFacts.IsSilent(new ExternalTypeInfo("Some.Foreign.Type"))
    assert !ForeachElementConversionFacts.IsSilent(BuiltInTypes.Int)
    assert !ForeachElementConversionFacts.IsSilent(ConversionClass("Widget"))
}

test "char IS NUMERIC AND bool IS NOT" {
    assert ForeachElementConversionFacts.IsNumericOrEnum(BuiltInTypes.Char)
    assert ForeachElementConversionFacts.IsNumericOrEnum(BuiltInTypes.Decimal)
    assert !ForeachElementConversionFacts.IsNumericOrEnum(BuiltInTypes.Bool)
    assert !ForeachElementConversionFacts.IsNumericOrEnum(BuiltInTypes.String)
    assert !ForeachElementConversionFacts.IsNumericOrEnum(BuiltInTypes.Object)
}
