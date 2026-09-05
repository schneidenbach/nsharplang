namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import NSharpLang.Compiler

// Admission consumes a selected identity; it does not turn namespace familiarity into evidence.
test "external type admission round trips the selected catalog identity in both universes" {
    scan := ExternalAssemblyScan.OpenWithReferences(null)
    try {
        selection := ExternalAssemblyScan.FindExactType(scan, "System.Guid")
        assert selection.Status == ExternalAssemblyTypeLookupStatus.Found
        assert selection.HasRuntimeType
        assert ColumnarTypeOfPlanner.IsSupportedCatalogType(selection.RuntimeType)
        assert scan.Context != null
        metadataType := scan.Context.LoadFromAssemblyName("System.Private.CoreLib").GetType("System.Guid")
        assert metadataType != null
        assert ColumnarTypeOfPlanner.IsSupportedCatalogType(metadataType)
        assert metadataType != selection.RuntimeType
        assert metadataType.get_AssemblyQualifiedName() == selection.RuntimeType.get_AssemblyQualifiedName()
        assert !ExternalAssemblyScan.HasExactTypeIdentity(metadataType, "System.Guid, Unrelated.Assembly")
        assert !ExternalAssemblyScan.HasExactTypeIdentity(metadataType, "Unrelated.Guid, System.Private.CoreLib")
        metadataVoid := scan.Context.LoadFromAssemblyName("System.Private.CoreLib").GetType("System.Void")
        assert metadataVoid != null
        assert !ColumnarTypeOfPlanner.IsSupportedType(metadataVoid)
        // The original 38-row decode used a different catalog for its 22/22 claim. The product's
        // shared common scan has no Uri entry; this is resolution, before type admission.
        uri := ExternalAssemblyScan.FindExactType(scan, "System.Uri")
        assert uri.Status == ExternalAssemblyTypeLookupStatus.Missing
        assert !uri.HasRuntimeType
        assert uri.SemanticTypeIdentity == ""
    } finally {
        scan.Dispose()
    }
}

test "external admission leaves structural shapes to their owners" {
    assert !ColumnarTypeOfPlanner.IsSupportedCatalogType(null)
    assert !ColumnarTypeOfPlanner.IsSupportedCatalogType(typeof(int).MakePointerType())
    assert !ColumnarTypeOfPlanner.IsSupportedCatalogType(typeof(int).MakeByRefType())
    assert !ColumnarTypeOfPlanner.IsSupportedCatalogType(typeof(int[]))
    assert !ColumnarTypeOfPlanner.IsSupportedType(typeof(int).MakeArrayType(2))
    assert !ColumnarTypeOfPlanner.IsSupportedCatalogType(typeof(List<int>).GetGenericTypeDefinition())
    assert !ColumnarTypeOfPlanner.IsSupportedType(AdmissibilitySpan(typeof(string)))
    assert !ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityClosed1("System.Nullable`1", AdmissibilityRuntimeType("System.Guid")))
    assert ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityQueueOfInt())
    assert ColumnarTypeOfPlanner.IsSupportedCatalogType(AdmissibilityQueueOfInt())
    assert !ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityRuntimeType("System.Void"))
}

func CatalogTypeOfTree(name: string, scope: ColumnarBindingScopeFacts): ColumnarRangePlannerTestTree {
    tree := TypeOfSimpleTree(name)
    tree.Nodes.SetBindingContext(scope, "", new string[](0), null)
    return tree
}

test "typeof consults exact aliases and refuses an unresolved qualified tail" {
    scope := ExactTypeSingleScope("import System.Text as Text\ntype Selected = Text.StringBuilder\n")
    bindings := ExactTypeEmptyBindings()
    aliasTree := CatalogTypeOfTree("Selected", scope)
    selected := ColumnarSelectedTypeReference.Missing(
        bindings.StructuralTypeReferences
    )
    assert ColumnarTypeOfPlanner.TryResolveTarget(aliasTree.Nodes, aliasTree.Source, aliasTree.Root, bindings, out selected)
    assert selected.RuntimeType == typeof(System.Text.StringBuilder)
    assert bindings.StructuralTypeReferences.ValidatePair(
        selected,
        typeof(System.Text.StringBuilder)
    )
    missingTree := CatalogTypeOfTree("Unrelated.StringBuilder", scope)
    assert !ColumnarTypeOfPlanner.TryResolveTarget(missingTree.Nodes, missingTree.Source, missingTree.Root, bindings, out selected)
    brokenScope := ExactTypeSingleScope("type StringBuilder = Missing.Target\n")
    brokenTree := CatalogTypeOfTree("StringBuilder", brokenScope)
    assert !ColumnarTypeOfPlanner.TryResolveTarget(brokenTree.Nodes, brokenTree.Source, brokenTree.Root, bindings, out selected)
}

test "typeof preserves a source identity that shares a BCL name" {
    builder := TypeOfCreateSourceBuilder("Scope.DateTime", false)
    definitions := new List<ColumnarStructDef>()
    definitions.Add(ExactTypeDefinition(builder, "Scope.DateTime"))
    bindings := ExactTypeBindings(definitions)
    bindings.StructuralTypeReferences.RegisterSourceDefinition(
        "Scope.DateTime",
        builder,
        false
    )
    scope := ExactTypeSingleScope("namespace Scope\nclass DateTime {}\n")
    tree := CatalogTypeOfTree("DateTime", scope)
    selected := ColumnarSelectedTypeReference.Missing(
        bindings.StructuralTypeReferences
    )
    assert ColumnarTypeOfPlanner.TryResolveTarget(tree.Nodes, tree.Source, tree.Root, bindings, out selected)
    assert ColumnarSourceDirectCallResolver.ExactTypeShapeMatches(selected.RuntimeType, builder)
    assert selected.RuntimeType != typeof(DateTime)
    assert selected.SourceProvenanceName == "Scope.DateTime"
    missing := CatalogTypeOfTree("Unrelated.DateTime", scope)
    assert !ColumnarTypeOfPlanner.TryResolveTarget(missing.Nodes, missing.Source, missing.Root, bindings, out selected)
}

// These closures have no assembly-qualified identity that Assembly.GetType can materialize while
// their source argument is still a builder. The specialized rebinding facts must remain live.
test "type admission retains external generics closed over source builders" {
    sourceClass := TypeOfCreateBuilder("Catalog.SourceArgument", "CatalogSourceArguments", 0)
    assert ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityClosed1("System.Collections.Generic.List`1", sourceClass))
    assert ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityClosed2("System.Collections.Generic.Dictionary`2", typeof(string), sourceClass))
    assert ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityClosed1("System.Threading.Tasks.Task`1", sourceClass))
    assert ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityResult(sourceClass, typeof(string)))
    assert ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityUnion(sourceClass, typeof(string)))
    // The HashSet type head is admitted; key eligibility is a separate, narrower question.
    assert ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityClosed1("System.Collections.Generic.HashSet`1", sourceClass))
    assert !ColumnarTypeOfPlanner.IsAdmissibleHashSetElement(sourceClass)
    assert !ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityClosed1("System.Func`1", sourceClass))
    assert !ColumnarTypeOfPlanner.IsSupportedType(AdmissibilityClosed2("System.ValueTuple`2", typeof(int), sourceClass))
}
