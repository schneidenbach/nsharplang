namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Runtime.CompilerServices

// WHICH TOP-LEVEL TYPE NAMES A REFERENCE ASSEMBLY CAN ANSWER, read once per FILE VERSION.
//
// `Assembly.GetType` on a metadata-load-context assembly finds a top-level type exactly when the name
// is one of the module's type definitions or exported types, and a MISS is the expensive answer: the
// load context parses the name and builds, then discards, a `TypeLoadException` with a localized
// message. A binder probing a simple name against every imported namespace misses against nearly every
// reference — about 180 of them for an ASP.NET project — so those misses dominated a warm `nlc check`.
// `ExternalAssemblyScan.ReadTopLevelTypeNames` reads the two tables; this owner keeps what it read,
// keyed by the file's path, length and write time, so a reference read once is never read again for
// as long as the file is unchanged. In a one-shot `nlc` that is once per command; in the workspace
// server and the language server it is once per file version for the life of the process.
//
// A name the tables cannot speak for (a constructed generic, an assembly-qualified name, a pointer or
// by-ref spelling), or a file that cannot be read, answers "maybe", which leaves the lookup exactly
// what it was without the index.
// A table (or the absence of one) held for one assembly object.
class ExternalTypeNameBox {
    Names: HashSet<string>?

    constructor(names: HashSet<string>?) {
        Names = names
    }
}

class ExternalTypeNameIndex {
    private static gate: object = new object()
    private static paths: Dictionary<string, string> = new Dictionary<string, string>(StringComparer.Ordinal)
    private static names: Dictionary<string, HashSet<string>?> = new Dictionary<string, HashSet<string>?>(StringComparer.Ordinal)
    private static registered: bool = false
    private static byAssembly: ConditionalWeakTable<Assembly, ExternalTypeNameBox> = new ConditionalWeakTable<Assembly, ExternalTypeNameBox>()

    // The table for an assembly's file, or null when it has none or it cannot be read. Remembered per
    // ASSEMBLY OBJECT (weakly, so it dies with the load context that made the assembly): a resolver
    // asks about the same handful of assemblies many thousands of times per analysis, and even a
    // `stat` per question would cost more than the misses it saves.
    static func TopLevelNamesOf(assembly: Assembly): HashSet<string>? {
        box: ExternalTypeNameBox? = null
        if ExternalTypeNameIndex.byAssembly.TryGetValue(assembly, out box) && box != null {
            return (box ?? new ExternalTypeNameBox(null)).Names
        }

        location := ""
        try {
            location = assembly.Location
        } catch locationFailure: Exception {
            location = ""
        }

        names := TopLevelNames(location)
        ExternalTypeNameIndex.byAssembly.AddOrUpdate(assembly, new ExternalTypeNameBox(names))
        return names
    }

    // Whether a table (null: no table) can declare `fullName`.
    static func MayDeclare(declared: HashSet<string>?, fullName: string): bool {
        if declared == null || !IsIndexableName(fullName) {
            return true
        }

        return declared.Contains(TopLevelName(fullName))
    }

    // The table for `path`, or null when it cannot be read.
    static func TopLevelNames(path: string): HashSet<string>? {
        if path == null || path == "" || !File.Exists(path) {
            return null
        }

        version := VersionOf(path)
        lock ExternalTypeNameIndex.gate {
            EnsureRegistered()
            cachedVersion := ""
            if ExternalTypeNameIndex.paths.TryGetValue(path, out cachedVersion) && cachedVersion == version {
                return ExternalTypeNameIndex.names[path]
            }
        }

        read := ExternalAssemblyScan.ReadTopLevelTypeNames(path)
        lock ExternalTypeNameIndex.gate {
            ExternalTypeNameIndex.paths[path] = version
            ExternalTypeNameIndex.names[path] = read
        }

        return read
    }

    static func IsIndexableName(fullName: string): bool {
        if fullName.Length == 0 {
            return false
        }

        return fullName.IndexOfAny(['[', ']', ',', '&', '*']) < 0
    }

    // `Ns.Outer+Inner` is found through `Ns.Outer`.
    static func TopLevelName(fullName: string): string {
        nested := fullName.IndexOf('+')
        if nested < 0 {
            return fullName
        }

        return fullName.Substring(0, nested)
    }

    static func VersionOf(path: string): string {
        info := new FileInfo(path)
        return info.Length.ToString() + "|" + info.LastWriteTimeUtc.Ticks.ToString()
    }

    static func Count(): int {
        lock ExternalTypeNameIndex.gate {
            return ExternalTypeNameIndex.paths.Count
        }
    }

    static func Clear() {
        lock ExternalTypeNameIndex.gate {
            ExternalTypeNameIndex.paths.Clear()
            ExternalTypeNameIndex.names.Clear()
        }
    }

    static func EnsureRegistered() {
        if ExternalTypeNameIndex.registered {
            return
        }

        ExternalTypeNameIndex.registered = true
        WarmStateRegistry.Register(
            "reference-type-names",
            path => {
            },
            () => ExternalTypeNameIndex.Clear(),
            () => ExternalTypeNameIndex.Count().ToString() + " reference assemblies indexed"
        )
    }
}
