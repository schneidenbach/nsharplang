namespace NSharpLang.CompilerCoreSliceDirection.Tests

import System
import System.Collections.Generic
import System.IO

// THE SLICE RULE, HELD BEFORE THE SLICES ARE PROJECTS.
//
// A file under slice k may not reach a top-level name a file under slice j > k owns. PR 1 of the
// split moved Core's files into their slice directories and PR 2 retired the last product reach
// upward (the node table's binding context), so the product graph is acyclic by slice. Nothing else
// keeps it so until each directory is its own assembly: these rows fail the day a new reach upward
// is written, naming the file, the line and the name. See memory/architecture.md, "Compiler.Core's
// slice directories".
func RepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "AGENTS.md")) && Directory.Exists(Path.Combine(directory, "src")) && Directory.Exists(Path.Combine(directory, "tests")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not locate the N# repository root from " + AppContext.BaseDirectory + ".")
}

// Compiler.Core and every slice already carved out of it into its own project.
func CoreSliceGraph(): SliceGraph {
    return SliceGraph.LoadCompiler(Path.Combine(RepositoryRoot(), "src"))
}

// THE ESTATE'S REACHES UPWARD, A CEILING TO DRIVE TO ZERO. A `.tests.nl` compiles into its slice's
// own assembly once the slice is a project, so a row that reaches a higher slice's product code or
// test helper cannot build there. These are the split plan's fixture-hoisting work (moving a row to
// the slice its subject lives in, or a helper to the slice that uses it), not PR 2's; until that
// lands the count may only fall. Measured when this row was written: 116 reaches of product names
// and 55 of other estate files' helpers, 111 of them from Model's estate.
func EstateUpwardCeiling(): int {
    return 171
}

test "every Compiler.Core source file sits in one of the eight slice directories" {
    graph := CoreSliceGraph()
    unplaced := graph.Unplaced()
    assert unplaced.Count == 0, "outside every slice directory: " + string.Join(", ", unplaced)

    // Anti-vacuity: every slice holds product code, so a walk of the wrong directory cannot pass.
    for rank := 0; rank < SliceNames().Length; rank++ {
        assert graph.ProductFileCount(rank) > 0, SliceName(rank) + " holds no product file"
    }
}

test "a carved slice's product is read from its own project, and none of it is left in Core" {
    graph := CoreSliceGraph()
    carvedProduct := 0
    coreModelEstate := 0
    for file in graph.Files {
        if file.Rank == 0 && !file.IsEstate {
            assert IsInSliceProject(file.RelativePath), file.RelativePath + " is Model product outside src/NSharpLang.Compiler.Model"
            carvedProduct = carvedProduct + 1
        }
        if file.Rank == 0 && file.IsEstate && !IsInSliceProject(file.RelativePath) {
            coreModelEstate = coreModelEstate + 1
        }
    }
    // Model's product is its own project; its estate stays in Core's `Model/` until the fixture
    // hoisting, because its rows still reach the slices above it.
    assert carvedProduct > 90, carvedProduct.ToString()
    assert coreModelEstate > 40, coreModelEstate.ToString()
}

test "no Compiler.Core product file reaches a top-level name a higher slice owns" {
    graph := CoreSliceGraph()
    // Anti-vacuity: the walk resolves the whole downward graph - some thirty thousand reaches - so an
    // empty upward list is a finding about the source, not about a scanner that saw nothing.
    assert graph.ProductReferences.Count > 20000, graph.ProductReferences.Count.ToString()

    upward := SliceGraph.Upward(graph.ProductReferences)
    assert upward.Count == 0, upward.Count.ToString() + " product reaches upward:" + SliceGraph.Report(upward, 40)
}

test "the estate's reaches into a higher slice do not grow" {
    graph := CoreSliceGraph()
    assert graph.EstateReferences.Count > 20000, graph.EstateReferences.Count.ToString()

    upward := SliceGraph.Upward(graph.EstateReferences)
    assert upward.Count <= EstateUpwardCeiling(), upward.Count.ToString() + " estate reaches upward, ceiling " + EstateUpwardCeiling().ToString() + " - a new row or helper reaches a higher slice:" + SliceGraph.Report(upward, 40)
    assert upward.Count == EstateUpwardCeiling(), upward.Count.ToString() + " estate reaches upward, below the ceiling of " + EstateUpwardCeiling().ToString() + " - lower EstateUpwardCeiling() to the new count."
}

// THE RULE'S OWN CONTROLS, over a tree written for them: a reach upward is reported with its file,
// line and name; a reach downward, a member that shadows the name, a comment and literal text are
// not; an interpolation hole is code.
func ControlTree(): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-slice-direction-" + Guid.NewGuid().ToString("N"))
    ControlWrite(root, "Model/Low.nl", "namespace Demo\n\nclass Low {\n    planner: Planner?\n\n    // Emitter is only mentioned here\n    func Label(): string => \"Emitter\" + $\"{Emitter.Name}\"\n}\n")
    ControlWrite(root, "Backend.Plan/Planner.nl", "namespace Demo\n\nclass Planner {\n    low: Low?\n}\n")
    ControlWrite(root, "Backend.Emit/Emitter.nl", "namespace Demo\n\nclass Emitter {\n    static Name: string => \"emitter\"\n}\n")
    ControlWrite(root, "Syntax/Shadow.nl", "namespace Demo\n\nclass Shadow {\n    Planner: int\n\n    func Twice(): int => Planner * 2\n}\n")
    ControlWrite(root, "Syntax/Shadow.tests.nl", "namespace Demo\n\ntest \"reaches up\" {\n    assert new Emitter() != null\n}\n")
    return root
}

func ControlWrite(root: string, relativePath: string, text: string) {
    path := Path.Combine(root, relativePath)
    Directory.CreateDirectory(Path.GetDirectoryName(path) ?? root)
    File.WriteAllText(path, text)
}

test "a reach into a higher slice is reported by file, line and name, and nothing else is" {
    root := ControlTree()
    try {
        graph := SliceGraph.Load(root)
        upward := SliceGraph.Upward(graph.ProductReferences)
        texts := new List<string>()
        for reference in upward {
            texts.Add(reference.Text)
        }
        report := string.Join(" | ", texts)

        assert upward.Count == 2, report
        assert texts.Contains("Model/Low.nl:4 [Model] reaches `Planner` in Backend.Plan/Planner.nl [Backend.Plan]"), report
        assert texts.Contains("Model/Low.nl:7 [Model] reaches `Emitter` in Backend.Emit/Emitter.nl [Backend.Emit]"), report

        // The downward reach is seen - the walk is not blind - and is not upward.
        downward := 0
        for reference in graph.ProductReferences {
            if reference.From.RelativePath == "Backend.Plan/Planner.nl" && reference.Name == "Low" {
                downward = downward + 1
            }
        }
        assert downward == 1, downward.ToString()

        // The estate reader counts a row in a low slice that constructs a higher slice's type.
        estateUpward := SliceGraph.Upward(graph.EstateReferences)
        assert estateUpward.Count == 1 && estateUpward[0].Text == "Syntax/Shadow.tests.nl:4 [Syntax] reaches `Emitter` in Backend.Emit/Emitter.nl [Backend.Emit]", SliceGraph.Report(estateUpward, 5)
    } finally {
        Directory.Delete(root, true)
    }
}

test "a carved slice keeps its rank: its reach into a slice still in Core is upward, and a product file left behind is reported" {
    root := Path.Combine(Path.GetTempPath(), "nsharp-slice-carve-" + Guid.NewGuid().ToString("N"))
    try {
        ControlWrite(root, "NSharpLang.Compiler.Core/Syntax/Parser.nl", "namespace Demo\n\nclass Parser {\n    token: Token?\n}\n")
        ControlWrite(root, "NSharpLang.Compiler.Core/Model/Token.tests.nl", "namespace Demo\n\ntest \"reaches up\" {\n    assert new Parser() != null\n}\n")
        ControlWrite(root, "NSharpLang.Compiler.Model/Token.nl", "namespace Demo\n\nclass Token {\n    parser: Parser?\n}\n")
        graph := SliceGraph.LoadCompiler(root)
        assert graph.Unplaced().Count == 0, string.Join(",", graph.Unplaced())

        upward := SliceGraph.Upward(graph.ProductReferences)
        assert upward.Count == 1 && upward[0].Text == "NSharpLang.Compiler.Model/Token.nl:4 [Model] reaches `Parser` in Syntax/Parser.nl [Syntax]", SliceGraph.Report(upward, 5)
        estateUpward := SliceGraph.Upward(graph.EstateReferences)
        assert estateUpward.Count == 1 && estateUpward[0].Text == "Model/Token.tests.nl:4 [Model] reaches `Parser` in Syntax/Parser.nl [Syntax]", SliceGraph.Report(estateUpward, 5)

        // Model's product left in Core's `Model/` after the carve is reported; a slice not yet
        // carved keeps its product in Core's directory without complaint.
        ControlWrite(root, "NSharpLang.Compiler.Core/Model/Stale.nl", "namespace Demo\n\nclass Stale {\n}\n")
        unplaced := SliceGraph.LoadCompiler(root).Unplaced()
        assert string.Join(",", unplaced) == "Model/Stale.nl (Model is carved into NSharpLang.Compiler.Model)", string.Join(",", unplaced)
    } finally {
        Directory.Delete(root, true)
    }
}

test "a file outside the eight slice directories is reported" {
    root := ControlTree()
    try {
        ControlWrite(root, "Stray.nl", "namespace Demo\n\nclass Stray {\n}\n")
        ControlWrite(root, "CompilerServices/Kernel.nl", "namespace Demo\n\nfunc Kernel(): int => 1\n")
        unplaced := SliceGraph.Load(root).Unplaced()
        assert string.Join(",", unplaced) == "CompilerServices/Kernel.nl,Stray.nl", string.Join(",", unplaced)
    } finally {
        Directory.Delete(root, true)
    }
}
