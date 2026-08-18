namespace NSharpLang.Compiler.CodeIntelligence

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// CONTRACTS FOR THE SNAPSHOT'S ACCESSORS AND THE POSITION RESOLVERS (019 slice 21).
//
// WHAT IS ASSERTED HERE WAS BOUNDED BY A MEASURED TOOLSET GAP, AND THE GAP IS NOW CLOSED.
// `ProjectSnapshot`'s collections are `IReadOnlyDictionary<K, V>`, and `Dictionary<K, V>` did not
// widen to `IReadOnlyDictionary<K, V>` in ANY position — return, argument or field assignment —
// while `List<T>` widened to `IReadOnlyList<T>` in all three, so a snapshot could be RECEIVED by N#
// and never CONSTRUCTED by it and every contract that needed to build one stayed in the C# suite.
// **020 SLICE 10 PUBLISHED THE WIDENING** (the two-argument dictionary heads were missing from
// `TypeInfoIdentityFacts.HasKnownRuntimeGenericDefinition`, the gate above the conversion row), so
// this file's bound is lifted as soon as the toolset carries it: the snapshot-driven contracts are
// reachable from the estate and the C# pair is migratable. Until then the six snapshot-free things
// below remain what this file states.
//
// SIX THINGS THAT NEED NO SNAPSHOT ARE STATED HERE, AND FIVE OF THEM WERE UNREACHABLE BEFORE:
//   (a) `Bindings` IS NULL WHEN `Index` IS NULL AND IS THE INDEX'S OWN MAP OTHERWISE. The
//       distinction is load-bearing: a query answers an empty list for "no references" and refuses
//       entirely for "never analysed", and collapsing them would report a symbol as unused.
//   (b) THE SUBSTITUTED SYSTEMS REPORT IS A REAL REPORT, not a null the JSON writer special-cases.
//   (c) A MATCH CARRIES BOTH HALVES, and an unmatched one carries the text the caller typed with a
//       NULL unit — the two are read together and a second walk to recover the path would double
//       the cost of every hover.
//   (d) THE NULL-STATE ANSWER FALLS BACK TO WHAT THE TYPE ALONE IMPLIES when there is no semantic
//       model and no expression, which is the arm every `nlc query type` on an unanalysed position
//       takes.
//   (e) THE EXPRESSION FINDER ANSWERS NULL RATHER THAN THROWING on a unit with no declarations, at
//       every candidate column it tries.
//   (f) AN OUTLINE'S IMPORTS ARE THE NAMESPACE TEXTS IN SOURCE ORDER, and a unit with no imports
//       answers an empty array rather than null.
func CinAttributes(): List<AttributeNode> {
    return new List<AttributeNode>()
}

func CinClass(name: string, line: int, column: int): ClassDeclaration {
    return new ClassDeclaration(
        name, null, null, new List<TypeReference>(), new List<Declaration>(), null,
        Modifiers.Public, CinAttributes(), line, column)
}

func CinUnit(declarations: List<Declaration>, importNames: string[]): CompilationUnit {
    imports := new List<ImportDirective>()
    index := 0
    while index < importNames.Length {
        imports.Add(new ImportDirective(importNames[index], null, index + 1, 1))
        index = index + 1
    }

    return new CompilationUnit(null, imports, new List<Statement>(), null, declarations, 1, 1)
}

test "bindings answer null through a null index and the index's own map otherwise" {
    // (a) no index means no bindings — NOT an empty map
    assert ProjectSnapshot.IndexBindings(null) == null

    bindings := new BindingMap()
    index := new ProjectIndex(bindings, new Dictionary<string, string>())
    assert ProjectSnapshot.IndexBindings(index) != null
}

test "the substituted systems report is a real report with the shipped defaults" {
    // (b) the empty report is a value, not a null the writer has to special-case
    report := ProjectSnapshotDefaults.EmptySystemsReport()
    assert report != null
    assert report.Profile == "default"
    assert report.Mode == "strict"
    assert report.AotTarget == "nativeaot"
    assert report.Summary != null
    assert report.Summary.Functions == 0
}

test "a compilation-unit match carries both halves and an unmatched one carries the queried text" {
    unit := CinUnit(new List<Declaration>(), new string[](0))

    // (c) both halves cross together
    found := new CompilationUnitMatch("/p/src/alpha.nl", unit)
    assert found.FilePath == "/p/src/alpha.nl"
    assert found.Unit != null

    missing := new CompilationUnitMatch("nope.nl", null)
    assert missing.FilePath == "nope.nl"
    assert missing.Unit == null
}

test "the null-state answer falls back to the type when there is no model and no expression" {
    // (d) the fallback arm — no semantic model, no expression, so the TYPE alone decides
    typeInfo := new SimpleTypeInfo("int")
    assert CodeIntelligenceNavigation.NullabilityForExpression(null, null, typeInfo) ==
        NullStateFacts.GetSchemaText(CodeIntelligenceTypeResolution.DefaultNullState(typeInfo))

    // a nullable annotation and a plain one do not report the same thing
    nullableInfo := new SimpleTypeInfo("string?")
    assert CodeIntelligenceNavigation.NullabilityForExpression(null, null, nullableInfo) ==
        NullStateFacts.GetSchemaText(CodeIntelligenceTypeResolution.DefaultNullState(nullableInfo))
}

test "the expression finder answers null on a unit with nothing at the position" {
    // (e) every candidate column and both coordinate systems are tried, and none of them throws
    empty := CinUnit(new List<Declaration>(), new string[](0))
    assert CodeIntelligenceNavigation.FindExpressionAtPositionRobust(empty, 1, 1) == null
    assert CodeIntelligenceNavigation.FindExpressionAtPositionRobust(empty, 40, 12) == null

    declarations := new List<Declaration>()
    declarations.Add(CinClass("Alpha", 3, 1))
    withClass := CinUnit(declarations, new string[](0))
    assert CodeIntelligenceNavigation.FindExpressionAtPositionRobust(withClass, 3, 7) == null
}

test "the outline's imports are the namespace texts in source order" {
    // (f) three imports, in order, and an empty array rather than null when there are none
    unit := CinUnit(new List<Declaration>(), ["System", "System.Collections.Generic", "NSharpLang.Compiler"])
    namespaces := CodeIntelligenceQueries.ImportNamespaces(unit)
    assert namespaces.Length == 3
    assert namespaces[0] == "System"
    assert namespaces[1] == "System.Collections.Generic"
    assert namespaces[2] == "NSharpLang.Compiler"

    bare := CinUnit(new List<Declaration>(), new string[](0))
    assert CodeIntelligenceQueries.ImportNamespaces(bare).Length == 0
}
