namespace NSharpLang.CompilerCoreSliceDirection.Tests

import System.IO

// ONE `Program` HOLDER PER NAMESPACE, ONCE THE SLICES ARE ASSEMBLIES. `SliceGraph.HolderViolations`
// says why only these two meetings are possible; these rows hold them to zero on Core's source
// before any slice is carved, where `census-free-function-identity`'s shipped-holder rows can only
// see them after a seed has been built from the split.
test "no namespace's free-function holder is written by two slices, and no estate writes one beside a lower slice's" {
    graph := CoreSliceGraph()
    // Anti-vacuity: the one product holder there is - the parser kernels' global `Program` - is
    // seen, and so are the estate's thousands of free functions.
    assert graph.ProductHolderSlices("") == "Syntax", graph.ProductHolderSlices("")
    assert graph.EstateFreeFunctionCount() > 3000, graph.EstateFreeFunctionCount().ToString()

    violations := graph.HolderViolations()
    assert violations.Count == 0, string.Join("\n  ", violations)
}

test "a holder two slices would ship, and an estate holder beside a lower slice's, are both reported" {
    root := ControlTree()
    try {
        ControlWrite(root, "Model/Shared.nl", "namespace Demo.Shared\n\nfunc Low(): int => 1\n")
        ControlWrite(root, "Driver/Shared.nl", "namespace Demo.Shared\n\nfunc High(): int => 2\n")
        ControlWrite(root, "Syntax/Kernels.nl", "namespace Demo.Kernels\n\nfunc Parse(): int => 3\n")
        // A higher slice's estate beside the Syntax holder: reported.
        ControlWrite(root, "Semantics/Kernels.tests.nl", "namespace Demo.Kernels\n\nfunc fixture(): int => Parse()\n")
        // The same slice's estate shares its own assembly's holder, and a LOWER slice's estate never
        // compiles beside Syntax's product: neither is reported.
        ControlWrite(root, "Syntax/Kernels.tests.nl", "namespace Demo.Kernels\n\nfunc sameSlice(): int => 4\n")
        ControlWrite(root, "Model/Kernels.tests.nl", "namespace Demo.Kernels\n\nfunc lowerSlice(): int => 5\n")

        violations := SliceGraph.Load(root).HolderViolations()
        report := string.Join(" | ", violations)
        assert violations.Count == 2, report
        assert violations.Contains("`Demo.Shared.Program` is written by the product code of 2 slices: Driver/Shared.nl [Driver], Model/Shared.nl [Model]"), report
        assert violations.Contains("Semantics/Kernels.tests.nl [Semantics] declares free functions in `Demo.Kernels.Program`, which Syntax/Kernels.nl [Syntax] already ships"), report
    } finally {
        Directory.Delete(root, true)
    }
}
