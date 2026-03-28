using System.Linq;
using NSharpLang.Compiler;
using Xunit;

namespace NSharpLang.Tests;

/// <summary>
/// Unit tests for BindingMap — testing the data structure directly
/// without going through the Analyzer (those are in AnalyzerBindingMapTests).
/// </summary>
public class BindingMapTests
{
    // ── Recording and Looking Up Bindings ────────────────────────────────

    [Fact]
    public void RecordBinding_CanLookUpByUsagePosition()
    {
        var map = new BindingMap();
        var decl = new SymbolDeclaration("x", "test.nl", 1, 5, "variable");

        map.RecordBinding("test.nl", 3, 10, 1, decl);

        var result = map.GetBindingAt("test.nl", 3, 10);

        Assert.NotNull(result);
        Assert.Equal("x", result!.Name);
        Assert.Equal(1, result.Line);
        Assert.Equal(5, result.Column);
    }

    [Fact]
    public void RecordDeclaration_CanLookUpByDeclarationPosition()
    {
        var map = new BindingMap();
        var decl = new SymbolDeclaration("myFunc", "test.nl", 5, 1, "function");

        map.RecordDeclaration(decl);

        var result = map.GetBindingAt("test.nl", 5, 1);

        Assert.NotNull(result);
        Assert.Equal("myFunc", result!.Name);
        Assert.Equal("function", result.Kind);
    }

    [Fact]
    public void GetBindingAt_ReturnsNull_ForUnrecordedPosition()
    {
        var map = new BindingMap();

        var result = map.GetBindingAt("test.nl", 99, 99);

        Assert.Null(result);
    }

    // ── Forward Reference Handling ──────────────────────────────────────

    [Fact]
    public void RecordBinding_MultipleUsages_AllResolveToSameDeclaration()
    {
        var map = new BindingMap();
        var decl = new SymbolDeclaration("count", "test.nl", 1, 5, "variable");

        map.RecordBinding("test.nl", 3, 5, 5, decl);
        map.RecordBinding("test.nl", 5, 10, 5, decl);
        map.RecordBinding("test.nl", 8, 2, 5, decl);

        // All usages resolve to the same declaration
        Assert.Equal(decl, map.GetBindingAt("test.nl", 3, 5));
        Assert.Equal(decl, map.GetBindingAt("test.nl", 5, 10));
        Assert.Equal(decl, map.GetBindingAt("test.nl", 8, 2));
    }

    [Fact]
    public void RecordBinding_StoredDeclaration_RetrievableRegardlessOfLineOrder()
    {
        var map = new BindingMap();
        // Declaration is on line 10, usage is on line 3 (forward reference)
        var decl = new SymbolDeclaration("laterFunc", "test.nl", 10, 1, "function");

        map.RecordBinding("test.nl", 3, 5, 9, decl);

        var result = map.GetBindingAt("test.nl", 3, 5);

        Assert.NotNull(result);
        Assert.Equal("laterFunc", result!.Name);
        Assert.Equal(10, result.Line);
    }

    // ── FindReferences (Reverse Lookup) ─────────────────────────────────

    [Fact]
    public void GetReferences_ReturnsAllUsagesOfDeclaration()
    {
        var map = new BindingMap();
        var decl = new SymbolDeclaration("name", "test.nl", 1, 5, "variable");

        map.RecordBinding("test.nl", 3, 5, 4, decl);
        map.RecordBinding("test.nl", 7, 12, 4, decl);

        var refs = map.GetReferences(decl);

        Assert.Equal(2, refs.Count);
        Assert.Contains(refs, r => r.Line == 3 && r.Column == 5);
        Assert.Contains(refs, r => r.Line == 7 && r.Column == 12);
    }

    [Fact]
    public void GetReferences_ReturnsEmpty_ForDeclarationWithNoUsages()
    {
        var map = new BindingMap();
        var decl = new SymbolDeclaration("unused", "test.nl", 1, 1, "variable");

        map.RecordDeclaration(decl);

        var refs = map.GetReferences(decl);

        Assert.Empty(refs);
    }

    [Fact]
    public void FindAllReferences_FromUsagePosition_FindsDeclarationAndAllUsages()
    {
        var map = new BindingMap();
        var decl = new SymbolDeclaration("total", "test.nl", 2, 5, "variable");

        map.RecordDeclaration(decl);
        map.RecordBinding("test.nl", 5, 10, 5, decl);
        map.RecordBinding("test.nl", 8, 3, 5, decl);

        // Find from a usage position
        var (foundDecl, usages) = map.FindAllReferences("test.nl", 5, 10);

        Assert.NotNull(foundDecl);
        Assert.Equal("total", foundDecl!.Name);
        Assert.Equal(2, usages.Count);
    }

    [Fact]
    public void FindAllReferences_FromDeclarationPosition_FindsAllUsages()
    {
        var map = new BindingMap();
        var decl = new SymbolDeclaration("total", "test.nl", 2, 5, "variable");

        map.RecordDeclaration(decl);
        map.RecordBinding("test.nl", 5, 10, 5, decl);

        // Find from the declaration position itself
        var (foundDecl, usages) = map.FindAllReferences("test.nl", 2, 5);

        Assert.NotNull(foundDecl);
        Assert.Equal("total", foundDecl!.Name);
        Assert.Single(usages);
    }

    [Fact]
    public void FindAllReferences_NoBinding_ReturnsNullDeclaration()
    {
        var map = new BindingMap();

        var (decl, usages) = map.FindAllReferences("test.nl", 99, 99);

        Assert.Null(decl);
        Assert.Empty(usages);
    }

    // ── FindDeclarationsByName ──────────────────────────────────────────

    [Fact]
    public void FindDeclarationsByName_FindsMatchingDeclarations()
    {
        var map = new BindingMap();
        var decl1 = new SymbolDeclaration("Person", "models.nl", 1, 1, "class");
        var decl2 = new SymbolDeclaration("Person", "other.nl", 5, 1, "record");
        var decl3 = new SymbolDeclaration("Animal", "models.nl", 10, 1, "class");

        map.RecordDeclaration(decl1);
        map.RecordDeclaration(decl2);
        map.RecordDeclaration(decl3);

        var results = map.FindDeclarationsByName("Person");

        Assert.Equal(2, results.Count);
        Assert.All(results, r => Assert.Equal("Person", r.Name));
    }

    [Fact]
    public void FindDeclarationsByName_ReturnsEmpty_WhenNoMatch()
    {
        var map = new BindingMap();
        map.RecordDeclaration(new SymbolDeclaration("Foo", "test.nl", 1, 1, "class"));

        var results = map.FindDeclarationsByName("NonExistent");

        Assert.Empty(results);
    }

    // ── Scope Boundaries ────────────────────────────────────────────────

    [Fact]
    public void Bindings_SameNameDifferentPositions_AreIndependent()
    {
        var map = new BindingMap();
        // Two declarations of "x" in different scopes
        var outerDecl = new SymbolDeclaration("x", "test.nl", 2, 5, "variable");
        var innerDecl = new SymbolDeclaration("x", "test.nl", 5, 9, "variable");

        map.RecordDeclaration(outerDecl);
        map.RecordDeclaration(innerDecl);

        // Outer usage binds to outer declaration
        map.RecordBinding("test.nl", 3, 5, 1, outerDecl);
        // Inner usage binds to inner declaration
        map.RecordBinding("test.nl", 6, 9, 1, innerDecl);

        var outerResult = map.GetBindingAt("test.nl", 3, 5);
        var innerResult = map.GetBindingAt("test.nl", 6, 9);

        Assert.Equal(2, outerResult!.Line);  // Outer decl
        Assert.Equal(5, innerResult!.Line);  // Inner decl
    }

    [Fact]
    public void GetReferences_InnerScope_DoesNotLeakToOuter()
    {
        var map = new BindingMap();
        var outerDecl = new SymbolDeclaration("x", "test.nl", 1, 5, "variable");
        var innerDecl = new SymbolDeclaration("x", "test.nl", 4, 9, "variable");

        map.RecordDeclaration(outerDecl);
        map.RecordDeclaration(innerDecl);
        map.RecordBinding("test.nl", 2, 5, 1, outerDecl);
        map.RecordBinding("test.nl", 5, 9, 1, innerDecl);

        var outerRefs = map.GetReferences(outerDecl);
        var innerRefs = map.GetReferences(innerDecl);

        // Each declaration's references are independent
        Assert.Single(outerRefs);
        Assert.Equal(2, outerRefs[0].Line);

        Assert.Single(innerRefs);
        Assert.Equal(5, innerRefs[0].Line);
    }

    // ── Overwritten Bindings ────────────────────────────────────────────

    [Fact]
    public void RecordBinding_OverwriteAtSamePosition_UsesLatestBinding()
    {
        var map = new BindingMap();
        var declOld = new SymbolDeclaration("oldX", "test.nl", 1, 5, "variable");
        var declNew = new SymbolDeclaration("newX", "test.nl", 3, 5, "variable");

        map.RecordBinding("test.nl", 5, 10, 1, declOld);
        map.RecordBinding("test.nl", 5, 10, 1, declNew);

        // Forward lookup should return the latest binding
        var result = map.GetBindingAt("test.nl", 5, 10);
        Assert.Equal("newX", result!.Name);

        // Reverse lookup: new declaration should have the usage
        var newRefs = map.GetReferences(declNew);
        Assert.Contains(newRefs, r => r.Line == 5 && r.Column == 10);
    }

    [Fact]
    public void RecordDeclaration_TypeDeclaration_NotOverwrittenByThis()
    {
        var map = new BindingMap();
        var typeDecl = new SymbolDeclaration("Person", "test.nl", 1, 1, "class");
        var thisDecl = new SymbolDeclaration("this", "test.nl", 1, 1, "variable");

        map.RecordDeclaration(typeDecl);
        map.RecordDeclaration(thisDecl);

        var result = map.GetBindingAt("test.nl", 1, 1);

        // Type declaration should be preserved, not overwritten by "this"
        Assert.Equal("Person", result!.Name);
        Assert.Equal("class", result.Kind);
    }

    // ── Merge ───────────────────────────────────────────────────────────

    [Fact]
    public void Merge_CombinesDeclarationsFromBothMaps()
    {
        var map1 = new BindingMap();
        var map2 = new BindingMap();

        map1.RecordDeclaration(new SymbolDeclaration("Foo", "a.nl", 1, 1, "class"));
        map2.RecordDeclaration(new SymbolDeclaration("Bar", "b.nl", 1, 1, "class"));

        map1.Merge(map2);

        Assert.Equal(2, map1.AllDeclarations.Count);
        Assert.Contains(map1.AllDeclarations, d => d.Name == "Foo");
        Assert.Contains(map1.AllDeclarations, d => d.Name == "Bar");
    }

    [Fact]
    public void Merge_CombinesBindingsAndReferences()
    {
        var map1 = new BindingMap();
        var map2 = new BindingMap();

        var decl = new SymbolDeclaration("shared", "a.nl", 1, 1, "variable");
        map1.RecordDeclaration(decl);
        map1.RecordBinding("a.nl", 3, 5, 6, decl);

        map2.RecordBinding("b.nl", 2, 3, 6, decl);

        map1.Merge(map2);

        var refs = map1.GetReferences(decl);

        Assert.Equal(2, refs.Count);
        Assert.Contains(refs, r => r.File == "a.nl");
        Assert.Contains(refs, r => r.File == "b.nl");
    }

    // ── BindingCount ────────────────────────────────────────────────────

    [Fact]
    public void BindingCount_ReflectsNumberOfRecordedBindings()
    {
        var map = new BindingMap();
        var decl = new SymbolDeclaration("x", "test.nl", 1, 1, "variable");

        Assert.Equal(0, map.BindingCount);

        map.RecordBinding("test.nl", 3, 5, 1, decl);
        Assert.Equal(1, map.BindingCount);

        map.RecordBinding("test.nl", 5, 5, 1, decl);
        Assert.Equal(2, map.BindingCount);
    }

    // ── Cross-File Bindings ─────────────────────────────────────────────

    [Fact]
    public void RecordBinding_CrossFile_ResolvesToCorrectDeclaration()
    {
        var map = new BindingMap();
        var decl = new SymbolDeclaration("Person", "models.nl", 1, 1, "class");

        map.RecordDeclaration(decl);
        map.RecordBinding("program.nl", 5, 10, 6, decl);

        var result = map.GetBindingAt("program.nl", 5, 10);

        Assert.NotNull(result);
        Assert.Equal("Person", result!.Name);
        Assert.Equal("models.nl", result.File);
    }
}
