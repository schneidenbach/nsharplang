namespace NSharpLang.CliCommandContracts.Tests

import System
import System.IO

// The original 38-shape production-source probe, remeasured on 2026-09-04: 16/22 before,
// 37/1 after. The third column is the exact build exit code. Uri is the catalog gap: the
// common scan omits its implementation assembly; the retained decline is measured separately.
func TypeOfCatalogMatrix(): string {
    return "object||0\nstring||0\nint||0\nint[]||0\nDateTime|System|0\nVersion|System|0\nException|System|0\nType|System|0\nUri|System|1\nGuid|System|0\nConsoleColor||0\nStringComparison|System|0\nStringComparer|System|0\nNullable<int>|System|0\nDelegate||0\nList<int>|System.Collections.Generic|0\nIEnumerable<int>|System.Collections.Generic|0\nHashSet<int>|System.Collections.Generic|0\nQueue<int>|System.Collections.Generic|0\nSortedSet<int>|System.Collections.Generic|0\nICollection<int>|System.Collections.Generic|0\nIList<int>|System.Collections.Generic|0\nIEnumerable|System.Collections|0\nStringBuilder|System.Text|0\nMemoryStream|System.IO|0\nStream|System.IO|0\nFileStream|System.IO|0\nTextWriter|System.IO|0\nStreamWriter|System.IO|0\nRegex|System.Text.RegularExpressions|0\nHttpClient|System.Net.Http|0\nJsonSerializer|System.Text.Json|0\nTask|System.Threading.Tasks|0\nProcess|System.Diagnostics|0\nPath|System.IO|0\nFile|System.IO|0\nEnvironment|System|0\nMath|System|0"
}

func TypeOfCatalogSource(shape: string, namespaceName: string): string {
    imports := ""
    if namespaceName.Length > 0 {
        imports = "import " + namespaceName + "\n\n"
    }
    return "namespace TypeOfMatrixProbe\n\n" + imports + "class Probe {\n    static func Ask(): string {\n        asked := typeof(" + shape + ")\n        return asked.get_FullName() ?? \"\"\n    }\n}\n"
}

test "typeof production source matches the 38 shape catalog contract" {
    directory := NewTempDirectory("nsharp-typeof-catalog")
    try {
        File.WriteAllText(Path.Combine(directory, "project.yml"), "name: TypeOfMatrixProbe\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
        rows := TypeOfCatalogMatrix().Split('\n')
        assert rows.Length == 38
        accepted := 0
        declined := 0
        for row in rows {
            cells := row.Split('|')
            assert cells.Length == 3
            File.WriteAllText(Path.Combine(directory, "Probe.nl"), TypeOfCatalogSource(cells[0], cells[1]))
            run := Nlc("build --project \"" + directory + "\"")
            expectedExit := (cells[2] == "0" ? 0 : 1)
            if run.ExitCode != expectedExit {
                throw new InvalidOperationException("typeof(" + cells[0] + ") exited " + run.ExitCode.ToString() + ": " + run.Stdout + run.Stderr)
            }
            if expectedExit == 0 {
                assert run.Stdout.Contains("Build successful")
                accepted = accepted + 1
            } else {
                assert run.Stderr.Contains("requires successful N# columnar emission")
                declined = declined + 1
            }
        }
        assert accepted == 37
        assert declined == 1
    } finally {
        Directory.Delete(directory, true)
    }
}

test "canonical collection resolution preserves source head shadowing" {
    directory := NewTempDirectory("nsharp-canonical-shadow")
    try {
        File.WriteAllText(Path.Combine(directory, "project.yml"), "name: CanonicalShadowProbe\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
        File.WriteAllText(
            Path.Combine(directory, "Probe.nl"),
            "namespace CanonicalShadowProbe\n\nimport System.Collections.Generic\n\nclass List<T> {\n    Value: T\n}\n\nclass Consumer {\n    Values: List<int>\n}\n"
        )
        shadowed := Nlc("build --project \"" + directory + "\"")
        assert shadowed.ExitCode == 1
        assert shadowed.Stderr.Contains("requires successful N# columnar emission")

        File.WriteAllText(
            Path.Combine(directory, "Probe.nl"),
            "namespace CanonicalShadowProbe\n\nimport System.Collections.Generic\n\nclass Consumer {\n    Values: List<int>\n}\n"
        )
        unshadowed := Nlc("build --project \"" + directory + "\"")
        assert unshadowed.ExitCode == 0
        assert unshadowed.Stdout.Contains("Build successful")
    } finally {
        Directory.Delete(directory, true)
    }
}
