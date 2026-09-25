namespace NSharpLang.CensusEmitShapes.Tests

import System.IO
import System.IO.Compression
import System.Text

// TWO BCL SURFACES THAT LIVE IN NO ASSEMBLY THE COMPILER USED TO LOAD, and the CLI needs both:
// `nlc watch` is a FileSystemWatcher loop and `nlc pack` writes a zip. The compiler pre-loads a
// fixed table of framework assemblies (ExternalAssemblyScan.CommonAssemblyNames) and neither
// `System.IO.FileSystem.Watcher` nor the two compression assemblies were in it, so
// `FileSystemWatcher` reported NL201 "Type 'FileSystemWatcher' not found" and
// `import System.IO.Compression` reported NL704 "namespace not found" — with no import, package or
// project reference a user could add to fix either one.
class FrameworkSurface {

    // A WATCHER, SUBSCRIBED AND UNSUBSCRIBED. The subscription itself is the point: `NotifyFilters`,
    // `FileSystemEventArgs` and `RenamedEventArgs` all live in the same assembly as the watcher, so
    // a handler that reads `eventArgs.FullPath` proves the whole surface resolved, not just the type
    // name. Raising is left to the caller; this only has to come back alive.
    static func WatchDirectory(root: string): int {
        seen := 0
        watcher := new FileSystemWatcher(root) {
            IncludeSubdirectories: true,
            NotifyFilter: NotifyFilters.FileName | NotifyFilters.DirectoryName | NotifyFilters.LastWrite
        }
        changed := on watcher.Changed (sender, eventArgs) => {
            if eventArgs.FullPath.Length > 0 {
                seen = seen + 1
            }
        }
        renamed := on watcher.Renamed (sender, eventArgs) => {
            if eventArgs.OldFullPath.Length > 0 {
                seen = seen + 1
            }
        }
        watcher.EnableRaisingEvents = true
        watcher.EnableRaisingEvents = false
        off changed
        off renamed
        watcher.Dispose()
        return seen
    }

    static func WatcherFilter(): NotifyFilters {
        return NotifyFilters.FileName | NotifyFilters.LastWrite
    }

    // A ZIP, WRITTEN AND READ BACK. `ZipFile.Open` and `ZipArchive.CreateEntryFromFile` are in
    // `System.IO.Compression.ZipFile` (the second is an extension method on the archive) and
    // `ZipArchive`/`ZipArchiveMode` in `System.IO.Compression`, so one package write needs both
    // entries in the table.
    static func WritePackage(packagePath: string, textEntryName: string, contents: string, fileEntryName: string, sourceFile: string) {
        if File.Exists(packagePath) {
            File.Delete(packagePath)
        }

        archive := ZipFile.Open(packagePath, ZipArchiveMode.Create)
        entry := archive.CreateEntry(textEntryName)
        writer := new StreamWriter(entry.Open(), Encoding.UTF8)
        writer.Write(contents)
        writer.Dispose()
        archive.CreateEntryFromFile(sourceFile, fileEntryName)
        archive.Dispose()
    }

    static func ReadPackageEntry(packagePath: string, entryName: string): string {
        archive := ZipFile.OpenRead(packagePath)
        entry := archive.GetEntry(entryName)
        if entry == null {
            archive.Dispose()
            return ""
        }

        reader := new StreamReader(entry.Open(), Encoding.UTF8)
        text := reader.ReadToEnd()
        reader.Dispose()
        archive.Dispose()
        return text
    }

    static func PackageEntryCount(packagePath: string): int {
        archive := ZipFile.OpenRead(packagePath)
        count := archive.Entries.Count
        archive.Dispose()
        return count
    }
}
