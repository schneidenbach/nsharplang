namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import System.Runtime.InteropServices
import System.Security.Cryptography
import System.Text
import NSharpLang.Compiler.Columnar

// WHAT A COMPILATION READ, AS VALUES THAT CAN BE COMPARED LATER.
//
// The incremental build's whole soundness argument is here: a compilation is a function of its
// inputs, so if every input it read still has the value it had last time, the output it wrote last
// time is the output it would write now. The inputs come in two shapes, the same two Go's build
// cache separates into an action ID and a list of consulted files:
//
//   * THE KEY — everything that is not a file: the compiler's own identity, the options the caller
//     chose, the parsed configuration, the ordered source list, the defines, the environment the
//     compiler reads. One SHA-256 over a canonical encoding (`IncrementalKeyBuilder`).
//   * THE ENTRIES — every file and directory the compilation consulted, each with the value it had
//     (`IncrementalInputEntry`). Recomputing an entry and comparing it is the whole check.
//
// FILES ARE COMPARED BY CONTENT. A modification time is never evidence of anything: `git checkout`,
// `touch`, a formatter that rewrites identical bytes and a copy that preserves times all break it in
// one direction or the other. The single exception is a file inside the running .NET installation's
// `shared/` or `packs/` tree — the BCL the analyzer reads metadata from, a few hundred megabytes that
// are versioned by directory and never rewritten in place — which is identified by its path, size
// and write time under a key that already carries the runtime's exact version.
//
// AN UNREADABLE INPUT NEVER MATCHES. A file that exists but cannot be read is recorded as `!`, and
// `!` is not equal to anything, including itself: the next build simply runs.
class IncrementalInputEntry {

    // Bumped whenever an entry's VALUE is computed differently, so an old stamp cannot match.
    static FileContent: int => 1
    static DirectoryListing: int => 2
    static InstalledRuntimeFile: int => 3
    static ProjectSourceEnumeration: int => 4
    static TestSourcePresence: int => 5

    Kind: int
    Path: string
    Value: string

    constructor(kind: int, path: string, value: string) {
        Kind = kind
        Path = path
        Value = value
    }

    static func Capture(kind: int, path: string): IncrementalInputEntry {
        return new IncrementalInputEntry(kind, path, ComputeValue(kind, path))
    }

    // Whether the input still has the value recorded for it.
    func IsCurrent(): bool {
        if Value == IncrementalInputEntry.UnreadableValue() {
            return false
        }

        current := ComputeValue(Kind, Path)
        return string.Equals(current, Value, StringComparison.Ordinal)
    }

    static func MissingValue(): string => "-"

    static func UnreadableValue(): string => "!"

    static func ComputeValue(kind: int, path: string): string {
        try {
            if kind == IncrementalInputEntry.FileContent {
                return ContentHash.OfFileOrMissing(path)
            }
            if kind == IncrementalInputEntry.DirectoryListing {
                return DirectoryListingValue(path)
            }
            if kind == IncrementalInputEntry.InstalledRuntimeFile {
                return InstalledRuntimeFileValue(path)
            }
            if kind == IncrementalInputEntry.ProjectSourceEnumeration {
                return ProjectSourceEnumerationValue(path)
            }
            if kind == IncrementalInputEntry.TestSourcePresence {
                if AnalyzerReferenceLoadOrchestration.HasTestSources(path) {
                    return "1"
                }
                return "0"
            }
        } catch {
            return IncrementalInputEntry.UnreadableValue()
        }

        return IncrementalInputEntry.UnreadableValue()
    }

    // The sorted names of a directory's entries, files and directories told apart. A directory that
    // gains or loses a version folder, a framework or a sibling assembly changes what a probe walking
    // it would find.
    private static func DirectoryListingValue(path: string): string {
        if !Directory.Exists(path) {
            return IncrementalInputEntry.MissingValue()
        }

        names := new List<string>()
        for directory in Directory.GetDirectories(path) {
            names.Add("d:" + (System.IO.Path.GetFileName(directory) ?? ""))
        }
        for file in Directory.GetFiles(path) {
            names.Add("f:" + (System.IO.Path.GetFileName(file) ?? ""))
        }
        names.Sort(StringComparer.Ordinal)
        return ContentHash.OfText(string.Join("\n", names))
    }

    private static func InstalledRuntimeFileValue(path: string): string {
        info := new FileInfo(path)
        if !info.Exists {
            return IncrementalInputEntry.MissingValue()
        }

        lengthText := info.Length.ToString(System.Globalization.CultureInfo.InvariantCulture)
        ticksText := info.LastWriteTimeUtc.Ticks.ToString(System.Globalization.CultureInfo.InvariantCulture)
        return lengthText + ":" + ticksText
    }

    // The file SET the analyzer's own project walk sees (`ProjectConfig.EnumerateSourceFiles`), in
    // sorted order. Each file's content is a separate `FileContent` entry; this one catches a file
    // added, removed or renamed anywhere the walk reaches.
    private static func ProjectSourceEnumerationValue(projectRoot: string): string {
        if !Directory.Exists(projectRoot) {
            return IncrementalInputEntry.MissingValue()
        }

        files := new List<string>()
        for file in ProjectConfig.EnumerateSourceFileArray(projectRoot) {
            files.Add(System.IO.Path.GetFullPath(file))
        }
        files.Sort(StringComparer.Ordinal)
        return ContentHash.OfText(string.Join("\n", files))
    }
}

// THE ONE CONTENT HASH. Upper-case hexadecimal SHA-256, so two owners can never disagree about the
// spelling of the same bytes.
static class ContentHash {
    static func OfBytes(bytes: byte[]): string {
        algorithm := SHA256.Create()
        try {
            hash := algorithm.ComputeHash(bytes)
            return Convert.ToHexString(hash)
        } finally {
            algorithm.Dispose()
        }
    }

    static func OfText(text: string): string {
        bytes := Encoding.UTF8.GetBytes(text)
        return ContentHash.OfBytes(bytes)
    }

    static func OfFileOrMissing(path: string): string {
        if !File.Exists(path) {
            return IncrementalInputEntry.MissingValue()
        }

        bytes := File.ReadAllBytes(path)
        return ContentHash.OfBytes(bytes)
    }
}

// THE KEY: a canonical, length-prefixed encoding of every non-file input, hashed once. Each field is
// written as `name=length:value;` so no two different field sequences can encode to the same bytes.
class IncrementalKeyBuilder {
    private readonly builder: StringBuilder

    constructor() {
        builder = new StringBuilder()
    }

    func Add(name: string, value: string?) {
        text := value ?? "\u0000null"
        builder.Append(name)
        builder.Append("=")
        builder.Append(text.Length.ToString(System.Globalization.CultureInfo.InvariantCulture))
        builder.Append(":")
        builder.Append(text)
        builder.Append(";")
    }

    func AddBool(name: string, value: bool) {
        if value {
            Add(name, "true")
        } else {
            Add(name, "false")
        }
    }

    func Build(): string {
        return ContentHash.OfText(builder.ToString())
    }
}

// WHICH COMPILER THIS IS. Every compiler assembly is emitted deterministically — its module version
// id is derived from a hash of its own bytes (`ColumnarDeterministicPeIdentity`) — so the MVIDs of
// the assemblies that make up the pipeline name the compiler exactly, at the cost of reading a
// field. The runtime the compiler runs on is part of it too: the analyzer reads BCL metadata from
// the running installation and the emitter resolves through the host's own loaded assemblies.
static class IncrementalCompilerIdentity {
    private static cached: string?

    // Computed once per process: the answer cannot change while the process runs.
    static func Current(): string {
        existing := cached
        if existing != null {
            return existing
        }

        described := IncrementalCompilerIdentity.Describe()
        cached = described
        return described
    }

    static func Describe(): string {
        key := new IncrementalKeyBuilder()
        AddAssembly(key, typeof(CompilerError).Assembly)
        AddAssembly(key, typeof(ColumnarParserRecovery).Assembly)
        AddAssembly(key, typeof(Analyzer).Assembly)
        AddAssembly(key, typeof(ColumnarEmissionPlanner).Assembly)
        AddAssembly(key, typeof(ColumnarIlEmitter).Assembly)
        AddAssembly(key, typeof(Linter).Assembly)
        AddAssembly(key, typeof(MultiFileCompiler).Assembly)
        key.Add("clr", Environment.Version.ToString())
        key.Add("runtime-directory", RuntimeEnvironment.GetRuntimeDirectory())
        key.Add("framework", RuntimeInformation.FrameworkDescription)
        key.Add("rid", RuntimeInformation.RuntimeIdentifier)
        return key.Build()
    }

    private static func AddAssembly(key: IncrementalKeyBuilder, assembly: Assembly) {
        name := assembly.GetName().Name ?? ""
        module := assembly.ManifestModule
        key.Add("assembly:" + name, module.ModuleVersionId.ToString())
    }
}

// THE CONFIGURATION, AS A VALUE. `ProjectConfig` grows a field whenever the language grows a
// setting, and a fingerprint that listed the fields by hand would silently stop seeing the next one.
// So the walk is structural: every public instance field and every public read/write property, in
// ordinal name order, recursively through lists, dictionaries and nested objects. A property with
// no setter is DERIVED (`EffectiveName`, `Reference.Type`) and is skipped; what it derives from is
// already in the walk.
static class IncrementalConfigFingerprint {
    static func Describe(config: ProjectConfig?): string {
        builder := new StringBuilder()
        AppendValue(builder, config, 0)
        return builder.ToString()
    }

    private static func AppendValue(builder: StringBuilder, value: object?, depth: int) {
        if value == null {
            builder.Append("null")
            return
        }
        if depth > 12 {
            throw new InvalidOperationException("the project configuration is nested too deeply to fingerprint")
        }

        text := value as string
        if text != null {
            builder.Append("\"")
            builder.Append(text.Length.ToString(System.Globalization.CultureInfo.InvariantCulture))
            builder.Append(":")
            builder.Append(text)
            builder.Append("\"")
            return
        }

        valueType := value.GetType()
        if valueType.IsPrimitive || valueType.IsEnum {
            builder.Append(Convert.ToString(value, System.Globalization.CultureInfo.InvariantCulture))
            return
        }

        dictionary := value as System.Collections.IDictionary
        if dictionary != null {
            entries := new List<string>()
            enumerator := dictionary.GetEnumerator()
            while enumerator.MoveNext() {
                entryBuilder := new StringBuilder()
                AppendValue(entryBuilder, enumerator.Key, depth + 1)
                entryBuilder.Append("=>")
                AppendValue(entryBuilder, enumerator.Value, depth + 1)
                entries.Add(entryBuilder.ToString())
            }
            entries.Sort(StringComparer.Ordinal)
            builder.Append("{")
            builder.Append(string.Join(",", entries))
            builder.Append("}")
            return
        }

        sequence := value as System.Collections.IEnumerable
        if sequence != null {
            builder.Append("[")
            itemEnumerator := sequence.GetEnumerator()
            first := true
            while itemEnumerator.MoveNext() {
                if !first {
                    builder.Append(",")
                }
                first = false
                AppendValue(builder, itemEnumerator.Current, depth + 1)
            }
            builder.Append("]")
            return
        }

        builder.Append(valueType.FullName ?? valueType.Name)
        builder.Append("(")
        members := new List<string>()
        flags := BindingFlags.Public | BindingFlags.Instance
        for field in valueType.GetFields(flags) {
            fieldBuilder := new StringBuilder()
            fieldBuilder.Append(field.Name)
            fieldBuilder.Append(":")
            AppendValue(fieldBuilder, field.GetValue(value), depth + 1)
            members.Add(fieldBuilder.ToString())
        }
        for property in valueType.GetProperties(flags) {
            if !property.CanRead || !property.CanWrite {
                continue
            }
            if property.GetIndexParameters().Length != 0 {
                continue
            }
            propertyBuilder := new StringBuilder()
            propertyBuilder.Append(property.Name)
            propertyBuilder.Append(":")
            AppendValue(propertyBuilder, property.GetValue(value), depth + 1)
            members.Add(propertyBuilder.ToString())
        }
        members.Sort(StringComparer.Ordinal)
        builder.Append(string.Join(";", members))
        builder.Append(")")
    }
}

// THE SWITCH. `NSHARP_INCREMENTAL=0` (or `false`) turns every incremental shortcut off for the
// process — the escape hatch for a suspected stale result, and the control arm of a measurement.
static class IncrementalBuildPolicy {
    static func IsEnabled(): bool {
        value := Environment.GetEnvironmentVariable("NSHARP_INCREMENTAL")
        if value == null {
            return true
        }

        return !(value == "0" || string.Equals(value, "false", StringComparison.OrdinalIgnoreCase))
    }
}
