namespace NSharpLang.CompileTimeBench

import System
import System.IO


// THE SYNTHETIC PROJECT IS THE SAME BYTES EVERYWHERE. A throughput before/after pair is only a
// comparison if both sides compiled identical input, and the documented size is a number the
// throughput profile in memory/testing.md quotes.
func BenchSyntheticTempRoot(): string {
    return Path.Combine(Path.GetTempPath(), "nsharp-synthetic-" + Guid.NewGuid().ToString("N"))
}

test "the default synthetic shape is 80,009 lines in 101 files" {
    root := BenchSyntheticTempRoot()
    try {
        assert BenchWriteSyntheticProject(root, 10, 10, 6) == 80009
        assert Directory.GetFiles(root, "*.nl", SearchOption.AllDirectories).Length == 101
        assert File.Exists(Path.Combine(root, "project.yml"))
    } finally {
        Directory.Delete(root, true)
    }
}

test "two synthetic projects of one shape are byte-identical" {
    first := BenchSyntheticTempRoot()
    second := BenchSyntheticTempRoot()
    try {
        BenchWriteSyntheticProject(first, 2, 2, 2)
        BenchWriteSyntheticProject(second, 2, 2, 2)
        firstFiles := Directory.GetFiles(first, "*", SearchOption.AllDirectories)
        Array.Sort(firstFiles, StringComparer.Ordinal)
        assert firstFiles.Length == Directory.GetFiles(second, "*", SearchOption.AllDirectories).Length
        for firstFile in firstFiles {
            relative := Path.GetRelativePath(first, firstFile)
            assert File.ReadAllText(firstFile) == File.ReadAllText(Path.Combine(second, relative)), relative
        }
    } finally {
        Directory.Delete(first, true)
        Directory.Delete(second, true)
    }
}

test "a synthetic shape is three positive whole numbers" {
    shape := BenchParseSyntheticShape("10x10x6")
    assert shape != null
    if shape != null {
        assert shape[0] == 10 && shape[1] == 10 && shape[2] == 6
    }
    for bad in ["", "10x10", "10x10x6x1", "0x1x1", "ax1x1", "1x-1x1"] {
        assert BenchParseSyntheticShape(bad) == null, bad
    }
}
