namespace NSharpLang.CensusEmitShapes.Tests

import System
import System.IO

func FrameworkSurfaceScratch(): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-framework-surface-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(directory)
    return directory
}

test "a FileSystemWatcher resolves, subscribes and unsubscribes" {
    scratch := FrameworkSurfaceScratch()
    try {
        assert FrameworkSurface.WatchDirectory(scratch) == 0
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "the watcher's own NotifyFilters flags combine to the value the BCL declares" {
    expected := NotifyFilters.FileName | NotifyFilters.LastWrite
    assert FrameworkSurface.WatcherFilter() == expected
    assert FrameworkSurface.WatcherFilter() != NotifyFilters.FileName
}

test "a zip archive is written and read back through both compression assemblies" {
    scratch := FrameworkSurfaceScratch()
    try {
        sourceFile := Path.Combine(scratch, "payload.txt")
        File.WriteAllText(sourceFile, "from a file")
        packagePath := Path.Combine(scratch, "package.zip")

        FrameworkSurface.WritePackage(packagePath, "manifest.nuspec", "<package />", "lib/net10.0/payload.txt", sourceFile)

        assert File.Exists(packagePath)
        assert FrameworkSurface.PackageEntryCount(packagePath) == 2
        assert FrameworkSurface.ReadPackageEntry(packagePath, "manifest.nuspec") == "<package />"
        assert FrameworkSurface.ReadPackageEntry(packagePath, "lib/net10.0/payload.txt") == "from a file"
        assert FrameworkSurface.ReadPackageEntry(packagePath, "absent") == ""
    } finally {
        Directory.Delete(scratch, true)
    }
}
