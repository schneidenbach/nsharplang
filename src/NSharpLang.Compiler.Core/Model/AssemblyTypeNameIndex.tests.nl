namespace NSharpLang.Compiler

import System
import System.IO

// The reference type-name index's FILE-VERSION half (`AssemblyTypeNameIndex.TopLevelNamesAt`): one
// read per file version, shared by every load context that opens the file; null whenever the tables
// cannot speak. The per-assembly half and `GetTypeOrNull` are `ExternalAssemblyScan.tests.nl`'s.
test "the core library's tables list its top-level types and nothing it does not declare" {
    declared := AssemblyTypeNameIndex.TopLevelNamesAt(typeof(object).Assembly.Location)
    assert declared != null
    names := declared ?? new System.Collections.Generic.HashSet<string>()
    assert names.Contains("System.String")
    assert names.Contains("System.Collections.Generic.List`1")
    assert names.Contains("System.Environment")
    assert !names.Contains("System.Environment+SpecialFolder")
    assert !names.Contains("System.NoSuchTypeAnywhere")
}

test "a missing or unreadable file has no table" {
    assert AssemblyTypeNameIndex.TopLevelNamesAt("") == null
    assert AssemblyTypeNameIndex.TopLevelNamesAt("/nsharp/does-not-exist/missing.dll") == null
}

test "a file is read again only when its version changes" {
    source := typeof(object).Assembly.Location
    directory := Path.Combine(Path.GetTempPath(), "nlc-type-name-index-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    copy := Path.Combine(directory, "Copy.dll")
    try {
        File.Copy(source, copy)
        first := AssemblyTypeNameIndex.TopLevelNamesAt(copy)
        second := AssemblyTypeNameIndex.TopLevelNamesAt(copy)
        assert first != null
        assert Object.ReferenceEquals(first, second)

        // A different file at the same path (here: not an assembly at all) is a new version.
        File.WriteAllText(copy, "not metadata")
        File.SetLastWriteTimeUtc(copy, DateTime.UtcNow.AddMinutes(1))
        assert AssemblyTypeNameIndex.TopLevelNamesAt(copy) == null
    } finally {
        Directory.Delete(directory, true)
    }
}
