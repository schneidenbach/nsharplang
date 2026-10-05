namespace NSharpLang.Compiler

import System
import System.IO

// The reference type-name index: one read per file version, "maybe" whenever the tables cannot speak.
test "the core library's table answers its top-level types and refuses names it does not declare" {
    declared := ExternalTypeNameIndex.TopLevelNames(typeof(object).Assembly.Location)
    assert declared != null
    assert ExternalTypeNameIndex.MayDeclare(declared, "System.String")
    assert ExternalTypeNameIndex.MayDeclare(declared, "System.Collections.Generic.List`1")
    assert !ExternalTypeNameIndex.MayDeclare(declared, "System.NoSuchTypeAnywhere")
}

test "a nested name is answered through its top-level type" {
    assert ExternalTypeNameIndex.TopLevelName("Ns.Outer+Inner+Deeper") == "Ns.Outer"
    assert ExternalTypeNameIndex.TopLevelName("Ns.Plain") == "Ns.Plain"

    declared := ExternalTypeNameIndex.TopLevelNames(typeof(object).Assembly.Location)
    assert ExternalTypeNameIndex.MayDeclare(declared, "System.Environment+SpecialFolder")
}

test "names the tables cannot speak for, and missing tables, answer maybe" {
    declared := ExternalTypeNameIndex.TopLevelNames(typeof(object).Assembly.Location)
    assert ExternalTypeNameIndex.MayDeclare(declared, "System.Collections.Generic.List`1[[System.Int32]]")
    assert ExternalTypeNameIndex.MayDeclare(declared, "System.String, System.Private.CoreLib")
    assert ExternalTypeNameIndex.MayDeclare(declared, "System.Int32&")
    assert ExternalTypeNameIndex.MayDeclare(declared, "System.Int32*")
    assert ExternalTypeNameIndex.MayDeclare(null, "Anything.At.All")

    assert ExternalTypeNameIndex.TopLevelNames("") == null
    assert ExternalTypeNameIndex.TopLevelNames("/nsharp/does-not-exist/missing.dll") == null
}

test "a file is read again only when its version changes" {
    source := typeof(object).Assembly.Location
    directory := Path.Combine(Path.GetTempPath(), "nlc-type-name-index-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    copy := Path.Combine(directory, "Copy.dll")
    try {
        File.Copy(source, copy)
        first := ExternalTypeNameIndex.TopLevelNames(copy)
        second := ExternalTypeNameIndex.TopLevelNames(copy)
        assert first != null
        assert Object.ReferenceEquals(first, second)

        // A different file at the same path (here: not an assembly at all) is a new version.
        File.WriteAllText(copy, "not metadata")
        File.SetLastWriteTimeUtc(copy, DateTime.UtcNow.AddMinutes(1))
        assert ExternalTypeNameIndex.TopLevelNames(copy) == null
    } finally {
        Directory.Delete(directory, true)
    }
}
