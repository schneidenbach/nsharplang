namespace NSharpLang.OwnershipAudit

import System
import System.Collections.Generic
import System.IO
import System.Text
import System.Text.Json

static class OwnershipManagedFile {
    static func ReadAllBytes(path: string): byte[] {
        return ReadAllBytesWithBufferSize(path, 8192)
    }

    static func ReadAllBytesWithBufferSize(path: string, bufferSize: int): byte[] {
        if bufferSize <= 0 {
            throw new ArgumentOutOfRangeException("bufferSize")
        }
        stream := File.OpenRead(path)
        bytes := new List<byte>()
        buffer := new byte[](bufferSize)
        try {
            while true {
                count := stream.Read(buffer, 0, buffer.Length)
                if count <= 0 {
                    break
                }
                i := 0
                while i < count {
                    bytes.Add(buffer[i])
                    i = i + 1
                }
            }
        } finally {
            stream.Dispose()
        }
        return bytes.ToArray()
    }
}

class OwnershipClassification {
    Included: bool
    Unknown: bool
    Language: string
    Surface: string
    CampaignScope: string

    constructor(included: bool, unknown: bool, language: string, surface: string, campaignScope: string) {
        Included = included
        Unknown = unknown
        Language = language
        Surface = surface
        CampaignScope = campaignScope
    }
}

class OwnershipObservedFile {
    Path: string
    Language: string
    Surface: string
    CampaignScope: string
    Lines: int
    NonBlankLines: int
    AssertionMarkers: int
    Bytes: int
    Fingerprint: string

    constructor(
        path: string,
        language: string,
        surface: string,
        campaignScope: string,
        lines: int,
        nonBlankLines: int,
        assertionMarkers: int,
        bytes: int,
        fingerprint: string
    ) {
        Path = path
        Language = language
        Surface = surface
        CampaignScope = campaignScope
        Lines = lines
        NonBlankLines = nonBlankLines
        AssertionMarkers = assertionMarkers
        Bytes = bytes
        Fingerprint = fingerprint
    }
}

class OwnershipManifestEntry {
    Path: string
    Language: string
    Surface: string
    CampaignScope: string
    State: string
    EpochLines: int
    CurrentLines: int
    EpochNonBlankLines: int
    CurrentNonBlankLines: int
    EpochAssertionMarkers: int
    CurrentAssertionMarkers: int
    EpochBytes: int
    CurrentBytes: int
    CurrentFingerprint: string

    constructor() {
        Path = ""
        Language = ""
        Surface = ""
        CampaignScope = ""
        State = ""
        EpochLines = 0
        CurrentLines = 0
        EpochNonBlankLines = 0
        CurrentNonBlankLines = 0
        EpochAssertionMarkers = 0
        CurrentAssertionMarkers = 0
        EpochBytes = 0
        CurrentBytes = 0
        CurrentFingerprint = ""
    }
}

class OwnershipManifest {
    Phase: string
    CodeEpochFileCount: int
    CodeEpochPathFingerprint: string
    CodeEpochFactFingerprint: string
    ReviewedHeadFingerprint: string
    Files: List<OwnershipManifestEntry>

    constructor() {
        Phase = ""
        CodeEpochFileCount = 0
        CodeEpochPathFingerprint = ""
        CodeEpochFactFingerprint = ""
        ReviewedHeadFingerprint = ""
        Files = new List<OwnershipManifestEntry>()
    }
}

class OwnershipDiagnostic {
    Code: string
    Path: string
    Message: string

    constructor(code: string, path: string, message: string) {
        Code = code
        Path = path
        Message = message
    }

    func Render(): string {
        if Path == "" {
            return Code + ": " + Message
        }

        return Code + " [" + Path + "]: " + Message
    }
}

class OwnershipAuditResult {
    Diagnostics: List<OwnershipDiagnostic>

    constructor() {
        Diagnostics = new List<OwnershipDiagnostic>()
    }

    Succeeded: bool => Diagnostics.Count == 0

    func Add(code: string, path: string, message: string) {
        Diagnostics.Add(new OwnershipDiagnostic(code, path, message))
    }

    func Sort() {
        i := 1
        while i < Diagnostics.Count {
            current := Diagnostics[i]
            j := i
            while j > 0 && ComesAfter(Diagnostics[j - 1], current) {
                Diagnostics[j] = Diagnostics[j - 1]
                j = j - 1
            }
            Diagnostics[j] = current
            i = i + 1
        }
    }

    func HasCode(code: string): bool {
        i := 0
        while i < Diagnostics.Count {
            if Diagnostics[i].Code == code {
                return true
            }
            i = i + 1
        }

        return false
    }

    func Report(): string {
        builder := new StringBuilder()
        builder.Append("N# ownership growth audit failed with ")
        builder.Append(Diagnostics.Count)
        builder.Append(" violation(s):\n")
        i := 0
        while i < Diagnostics.Count {
            builder.Append("  ")
            builder.Append(Diagnostics[i].Render())
            builder.Append("\n")
            i = i + 1
        }

        return builder.ToString()
    }

    static func ComesAfter(left: OwnershipDiagnostic, right: OwnershipDiagnostic): bool {
        pathOrder := String.Compare(left.Path, right.Path, StringComparison.Ordinal)
        if pathOrder != 0 {
            return pathOrder > 0
        }

        codeOrder := String.Compare(left.Code, right.Code, StringComparison.Ordinal)
        if codeOrder != 0 {
            return codeOrder > 0
        }

        return String.Compare(left.Message, right.Message, StringComparison.Ordinal) > 0
    }
}

// The manifest holds two row classes with one honest rule each.
//
// CODE rows are the languages a product can be implemented in (C#, TypeScript, JavaScript,
// Python, Java, Rust, Go, native, and the rest). They carry the growth ratchet: immutable epoch
// ceilings that may never be raised, current ceilings that may only shrink or be removed, an
// exact-match fingerprint, and a frozen path set. A code file with no row is refused (OWN003);
// admitting one takes a new epoch, not a repin.
//
// DELIVERY rows are the config, MSBuild, shell and binary surfaces the product ships through
// (product-config, yaml-config, json-config, msbuild, shell, powershell, policy-data,
// gradle-config, and every binary language). They carry no ceiling, because a delivery change is
// judged by review rather than by size: the row records an exact-match fingerprint plus the line
// counts the audit reports, and any drift is always reported (OWN005). A NEW delivery file is
// admitted by adding its row in a reviewed repin -- never implicitly, so a new delivery file with
// no row is still refused (OWN003).
//
// E1 is the epoch taken at the bootstrap seed boundary: the code epoch triple (file count, path
// set, epoch facts) is computed over CODE rows only, so admitting or repinning a delivery row can
// never move it, while the reviewed-head fingerprint covers every row of both classes. Both keys
// live here and in the manifest header, so a manifest-only rebaseline can never pass the live gate.
class OwnershipPolicy {
    static ManifestFileName: string => "non-nsharp-growth-ratchet.v2.json"
    static SchemaVersion: int => 2

    static CodeEpochFileCount: int => 223
    static CodeEpochPathFingerprint: string => "pathset-v2:fbda7fc3d5053525"
    static CodeEpochFactFingerprint: string => "epochfacts-v2:05f608333cab8ef7"
    static ReviewedHeadFingerprint: string => "head-v2:1cea2d4282852e0a"

    static func Classify(path: string): OwnershipClassification {
        normalized := NormalizeRelativePath(path)
        lower := normalized.ToLowerInvariant()

        if lower.EndsWith(".cs") {
            return Included("csharp", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }

        if IsExactDataOrAssetException(normalized) {
            return Ignored()
        }

        if lower.EndsWith(".nl") || lower.EndsWith(".tests.nl") || lower.EndsWith(".md") || lower.EndsWith(".svg") || lower.EndsWith(".png") || lower.EndsWith(".ico") || lower.EndsWith(".woff") || lower.EndsWith(".woff2") || lower.EndsWith(".ttf") || lower.EndsWith(".mp3") || lower.EndsWith(".rtf") || lower.EndsWith(".icns") {
            return Ignored()
        }

        if lower.EndsWith(".ts") || lower.EndsWith(".tsx") {
            return Included("typescript", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".fs") || lower.EndsWith(".fsx") {
            return Included("fsharp", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".vb") {
            return Included("visual-basic", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".swift") || lower.EndsWith(".rb") || lower.EndsWith(".php") || lower.EndsWith(".scala") || lower.EndsWith(".sql") {
            return Included("source-code", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".js") || lower.EndsWith(".jsx") || lower.EndsWith(".mjs") || lower.EndsWith(".cjs") {
            return Included("javascript", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".csproj") || lower.EndsWith(".props") || lower.EndsWith(".targets") || lower.EndsWith(".sln") || lower.EndsWith(".slnx") || lower.EndsWith(".fsproj") || lower.EndsWith(".vbproj") {
            return Included("msbuild", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".sh") || lower.EndsWith(".bash") || lower.EndsWith(".zsh") || lower.EndsWith(".fish") || lower.EndsWith(".bat") || lower.EndsWith(".cmd") {
            return Included("shell", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".ps1") || lower.EndsWith(".psm1") || lower.EndsWith(".psd1") || lower.EndsWith(".ps1xml") {
            return Included("powershell", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".py") {
            return Included("python", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".gradle") || lower.EndsWith(".kts") || lower.EndsWith(".kt") {
            return Included("gradle-kotlin", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".properties") || Path.GetFileName(lower) == "gradlew" {
            return Included("gradle-config", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".java") {
            return Included("java", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".c") || lower.EndsWith(".cc") || lower.EndsWith(".cpp") || lower.EndsWith(".h") || lower.EndsWith(".hpp") {
            return Included("native", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".rs") {
            return Included("rust", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".go") {
            return Included("go", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".wasm") {
            return Included("wasm-binary", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".dll") {
            return Included("managed-binary", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".dylib") || lower.EndsWith(".node") {
            return Included("native-binary", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".vsix") || lower.EndsWith(".nupkg") || lower.EndsWith(".asar") || lower.EndsWith(".pak") {
            return Included("package-binary", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".bin") {
            return Included("opaque-binary", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".dat") || lower.EndsWith(".nib") {
            return Included("opaque-binary", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".scpt") {
            return Included("automation-binary", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".plist") || lower.EndsWith(".mobileconfig") {
            return Included("platform-config-binary", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".txt") || lower.EndsWith(".log") || lower.EndsWith(".map") || lower.EndsWith(".symbols") || lower.EndsWith(".stamp") || lower.EndsWith(".tiktoken") || lower.EndsWith(".lock") {
            return Included("policy-data", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if lower.EndsWith(".toml") || lower.EndsWith(".ini") || lower.EndsWith(".conf") || lower.EndsWith(".env") || lower.EndsWith(".mk") || lower.EndsWith(".xaml") {
            return Included("product-config", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if IsAuditedJson(normalized) {
            return Included("json-config", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if IsAuditedYaml(normalized) {
            return Included("yaml-config", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }
        if IsAuditedMarkupOrConfig(normalized) {
            return Included("product-config", SurfaceFor(normalized), CampaignScopeFor(normalized))
        }

        if !IsProductAdjacent(normalized) {
            return Ignored()
        }

        if IsKnownDataOrDocumentation(normalized) {
            return Ignored()
        }

        return new OwnershipClassification(false, true, "unknown", SurfaceFor(normalized), CampaignScopeFor(normalized))
    }

    static func NormalizeRelativePath(path: string): string {
        return path.Replace('\\', '/').Trim()
    }

    static func IsCanonicalManifestPath(path: string): bool {
        if path == "" || Path.IsPathRooted(path) || path[0] == '/' || path[path.Length - 1] == '/' {
            return false
        }
        if path.IndexOf('\\') >= 0 || path.IndexOf('*') >= 0 || path.IndexOf('?') >= 0 {
            return false
        }
        if path.IndexOf('\n') >= 0 || path.IndexOf('\r') >= 0 || path.IndexOf('\t') >= 0 {
            return false
        }
        if path.StartsWith("./", StringComparison.Ordinal) || path.IndexOf("//", StringComparison.Ordinal) >= 0 {
            return false
        }

        start := 0
        i := 0
        while i <= path.Length {
            if i == path.Length || path[i] == '/' {
                segment := path.Substring(start, i - start)
                if segment == "" || segment == "." || segment == ".." {
                    return false
                }
                start = i + 1
            }
            i = i + 1
        }

        return path == NormalizeRelativePath(path)
    }

    static func ShouldSkipDirectory(path: string): bool {
        normalized := NormalizeRelativePath(path)
        name := Path.GetFileName(normalized) ?? ""
        if name == ".git" || name == "bin" || name == "obj" || name == "node_modules" || name == ".vscode-test" || name == ".nsharp" || name == "BenchmarkDotNet.Artifacts" {
            return true
        }

        return normalized == "artifacts" || normalized == ".context" || normalized == ".claude" || normalized == "editors/vscode/out" || normalized == "editors/vscode/server" || normalized == "website/static/playground/wasm/_framework"
    }

    static func IsAssertionTracked(path: string, language: string): bool {
        lower := path.ToLowerInvariant()
        isTest := lower.IndexOf("/test", StringComparison.Ordinal) >= 0 || lower.EndsWith(".test.ts") || lower.EndsWith(".tests.ts") || lower.EndsWith("tests.cs") || lower.EndsWith("test.cs")
        return isTest && (language == "csharp" || language == "typescript" || language == "javascript")
    }

    static func IsBinaryLanguage(language: string): bool {
        return language == "wasm-binary" || language == "managed-binary" || language == "native-binary" || language == "package-binary" || language == "opaque-binary" || language == "automation-binary" || language == "platform-config-binary"
    }

    // Config, build and packaging surfaces: reviewed by fingerprint, never by ceiling.
    static func IsDeliveryLanguage(language: string): bool {
        if language == "msbuild" || language == "shell" || language == "powershell" {
            return true
        }
        if language == "product-config" || language == "yaml-config" || language == "json-config" {
            return true
        }
        if language == "policy-data" || language == "gradle-config" {
            return true
        }
        return IsBinaryLanguage(language)
    }

    // Every other audited language is code, and code keeps the growth ratchet.
    static func IsCodeLanguage(language: string): bool {
        return !IsDeliveryLanguage(language)
    }

    static func IsDeliveryPath(path: string): bool {
        classification := Classify(path)
        if !classification.Included {
            return false
        }
        return IsDeliveryLanguage(classification.Language)
    }

    static func Included(language: string, surface: string, campaignScope: string): OwnershipClassification {
        return new OwnershipClassification(true, false, language, surface, campaignScope)
    }

    static func Ignored(): OwnershipClassification {
        return new OwnershipClassification(false, false, "", "", "")
    }

    static func IsProductAdjacent(path: string): bool {
        return path.StartsWith("src/", StringComparison.Ordinal) || path.StartsWith("editors/", StringComparison.Ordinal) || path.StartsWith("scripts/", StringComparison.Ordinal) || path.StartsWith("tests/", StringComparison.Ordinal) || path.StartsWith("website/", StringComparison.Ordinal) || path.StartsWith("templates/", StringComparison.Ordinal) || path.StartsWith("examples/", StringComparison.Ordinal) || path.StartsWith("ci/", StringComparison.Ordinal) || path.StartsWith("benchmarks/", StringComparison.Ordinal) || path.StartsWith(".github/", StringComparison.Ordinal) || path == "Directory.Build.props" || path == "Directory.Build.targets" || path == "Directory.Packages.props" || path == "global.json" || path == "package.json" || path == "package-lock.json" || path == "docker-compose.yml" || path == "docker-compose.yaml" || path == "Dockerfile" || path == "Makefile" || path.EndsWith(".sh", StringComparison.Ordinal) && path.IndexOf('/') < 0 || path == "NSharpLang.sln" || path == ".gitattributes" || path == ".gitignore"
    }

    static func IsAuditedJson(path: string): bool {
        lower := path.ToLowerInvariant()
        if lower == "tests/native/ownership-audit/non-nsharp-growth-ratchet.v2.json" {
            return false
        }
        if lower.StartsWith("tests/fixtures/", StringComparison.Ordinal) && lower.EndsWith(".golden.json", StringComparison.Ordinal) {
            return false
        }
        name := Path.GetFileName(lower) ?? ""
        return lower.EndsWith(".json") || name == "package.json" || name == "package-lock.json"
    }

    static func IsAuditedYaml(path: string): bool {
        lower := path.ToLowerInvariant()
        if lower.EndsWith("/project.yml") || lower == "project.yml" {
            return false
        }
        return lower.EndsWith(".yml") || lower.EndsWith(".yaml")
    }

    static func IsAuditedMarkupOrConfig(path: string): bool {
        lower := path.ToLowerInvariant()
        name := Path.GetFileName(lower) ?? ""
        return lower.EndsWith(".vsixmanifest") || lower.EndsWith(".vscodeignore") || lower.EndsWith(".toolchain") || lower.EndsWith(".config") || lower.EndsWith(".xml") || lower.EndsWith(".html") || lower.EndsWith(".css") || lower.EndsWith(".code-snippets") || lower.EndsWith(".tmlanguage") || lower.EndsWith(".nojekyll") || name == "dockerfile" || name.StartsWith("dockerfile.", StringComparison.Ordinal) || name == ".dockerignore" || name == "makefile" || name == ".editorconfig" || name == ".gitattributes" || name == ".gitignore"
    }

    static func IsKnownDataOrDocumentation(path: string): bool {
        lower := path.ToLowerInvariant()
        return lower.EndsWith(".gitignore")
    }

    static func IsExactDataOrAssetException(path: string): bool {
        lower := path.ToLowerInvariant()
        name := Path.GetFileName(lower) ?? ""
        if lower == "editors/vscode/nsharp-0.6.0.vsix" || lower == "editors/vscode/package-lock.json" || lower == "editors/vscode/test/fixtures/simple/.vscode/settings.json" || lower == "website/static/playground/wasm/main.js" || lower == "website/static/playground/wasm/package.json" || lower == "website/static/playground/wasm/nsharplang.playground.wasm.runtimeconfig.json" {
            return true
        }
        if lower == ".claude/launch.json" || lower == "examples/14-minimal-api/minimalapi.g.csproj" || lower == "examples/17-issue-tracker/backend/issuetracker.g.csproj" {
            return true
        }
        if name == "project.yml" || lower == "tests/native/ownership-audit/non-nsharp-growth-ratchet.v2.json" {
            return true
        }
        if lower.StartsWith("tests/fixtures/", StringComparison.Ordinal) && lower.EndsWith(".golden.json", StringComparison.Ordinal) {
            return true
        }
        if name == "license.txt" || name == "compile-debug.log" {
            return true
        }
        if lower.StartsWith("tests/fixtures/", StringComparison.Ordinal) && (lower.EndsWith(".golden.txt", StringComparison.Ordinal) || lower.StartsWith("tests/fixtures/diagnostics/screenshots/", StringComparison.Ordinal)) {
            return true
        }
        if lower.StartsWith("editors/visualstudio/nsharp.visualstudio/resources/", StringComparison.Ordinal) && lower.EndsWith(".png.txt", StringComparison.Ordinal) {
            return true
        }
        if lower.StartsWith("editors/rider-plugin/src/main/resources/filetemplates/", StringComparison.Ordinal) && lower.EndsWith(".nl.ft", StringComparison.Ordinal) {
            return true
        }
        return lower == "website/static/playground/wasm/.stamp"
    }

    static func SurfaceFor(path: string): string {
        if path.StartsWith("src/NSharpLang.Runtime/", StringComparison.Ordinal) {
            return "runtime"
        }
        if path.StartsWith("src/NSharpLang.Compiler", StringComparison.Ordinal) {
            return "compiler-core"
        }
        // `NSharpLang.TestHost` is the CLI's own N# host assembly — `nlc test`, `nlc watch` and the
        // dispatch pipeline — referenced by `src/NSharpLang.Cli` and by nothing else, so it is the
        // CLI surface rather than a repository-build one.
        if path.StartsWith("src/NSharpLang.Cli/", StringComparison.Ordinal) || path.StartsWith("src/NSharpLang.TestHost/", StringComparison.Ordinal) {
            return "cli"
        }
        if path.StartsWith("src/NSharpLang.Build.Tasks/", StringComparison.Ordinal) || path.StartsWith("src/NSharpLang.Sdk/", StringComparison.Ordinal) {
            return "build-sdk"
        }
        if path.StartsWith("src/NSharpLang.LanguageServer/", StringComparison.Ordinal) {
            return "language-server"
        }
        if path.StartsWith("src/NSharpLang.Playground", StringComparison.Ordinal) || path.StartsWith("website/", StringComparison.Ordinal) {
            return "playground-web"
        }
        if path.StartsWith("editors/", StringComparison.Ordinal) {
            return "editor"
        }
        if path.StartsWith("templates/", StringComparison.Ordinal) {
            return "template-build"
        }
        if path.StartsWith("examples/", StringComparison.Ordinal) {
            return "examples"
        }
        if path.StartsWith("ci/", StringComparison.Ordinal) {
            return "ci-infrastructure"
        }
        if path.StartsWith("benchmarks/", StringComparison.Ordinal) {
            return "benchmark-reference"
        }
        if path.StartsWith("scripts/", StringComparison.Ordinal) || path.StartsWith("tests/scripts/", StringComparison.Ordinal) || path.StartsWith(".github/", StringComparison.Ordinal) {
            return "gate-infrastructure"
        }
        if path.StartsWith("tests/", StringComparison.Ordinal) {
            return "compiler-tests"
        }
        return "repository-build"
    }

    static func CampaignScopeFor(path: string): string {
        if path.StartsWith("src/NSharpLang.Runtime/", StringComparison.Ordinal) || path.StartsWith("tests/native-benchmarks/", StringComparison.Ordinal) || path.StartsWith("tests/benchmarks/native/", StringComparison.Ordinal) || path.StartsWith("benchmarks/native-comparison/", StringComparison.Ordinal) {
            return "separate-campaign"
        }
        return "closeout"
    }
}

class OwnershipFacts {
    static func NormalizeText(text: string): string {
        return text.Replace("\r\n", "\n").Replace('\r', '\n')
    }

    static func Fingerprint(text: string): string {
        normalized := NormalizeText(text)
        hash := 14695981039346656037UL
        i := 0
        while i < normalized.Length {
            hash = hash ^ (ulong)normalized[i]
            hash = unchecked(hash * 1099511628211UL)
            i = i + 1
        }
        return "text-v1:" + Hex64(hash)
    }

    static func FingerprintBytes(bytes: byte[]): string {
        hash := 14695981039346656037UL
        i := 0
        while i < bytes.Length {
            hash = hash ^ (ulong)bytes[i]
            hash = unchecked(hash * 1099511628211UL)
            i = i + 1
        }
        return "binary-v1:" + Hex64(hash)
    }

    static func PathSetFingerprint(paths: List<string>): string {
        ordered := new List<string>()
        i := 0
        while i < paths.Count {
            ordered.Add(paths[i])
            i = i + 1
        }
        SortStrings(ordered)
        return "pathset-v2:" + Fingerprint(string.Join("\n", ordered)).Substring("text-v1:".Length)
    }

    // The epoch covers code rows only, so a reviewed delivery row can never move it.
    static func CodeRows(entries: List<OwnershipManifestEntry>): List<OwnershipManifestEntry> {
        rows := new List<OwnershipManifestEntry>()
        i := 0
        while i < entries.Count {
            if OwnershipPolicy.IsCodeLanguage(entries[i].Language) {
                rows.Add(entries[i])
            }
            i = i + 1
        }
        return rows
    }

    static func CodeEpochPathFingerprint(entries: List<OwnershipManifestEntry>): string {
        rows := CodeRows(entries)
        paths := new List<string>()
        i := 0
        while i < rows.Count {
            paths.Add(rows[i].Path)
            i = i + 1
        }
        return PathSetFingerprint(paths)
    }

    static func CodeEpochFactFingerprint(entries: List<OwnershipManifestEntry>): string {
        rows := CodeRows(entries)
        builder := new StringBuilder()
        i := 0
        while i < rows.Count {
            entry := rows[i]
            AppendFactString(builder, entry.Path)
            AppendFactString(builder, entry.Language)
            AppendFactString(builder, entry.Surface)
            AppendFactString(builder, entry.CampaignScope)
            AppendFactInt(builder, entry.EpochLines)
            AppendFactInt(builder, entry.EpochNonBlankLines)
            AppendFactInt(builder, entry.EpochAssertionMarkers)
            AppendFactInt(builder, entry.EpochBytes)
            builder.Append('\n')
            i = i + 1
        }
        return "epochfacts-v2:" + Fingerprint(builder.ToString()).Substring("text-v1:".Length)
    }

    // The reviewed head covers every row of both classes, so a delivery repin is reviewed too.
    static func ReviewedHeadFingerprint(entries: List<OwnershipManifestEntry>): string {
        builder := new StringBuilder()
        i := 0
        while i < entries.Count {
            entry := entries[i]
            AppendFactString(builder, entry.Path)
            AppendFactString(builder, entry.State)
            AppendFactInt(builder, entry.CurrentLines)
            AppendFactInt(builder, entry.CurrentNonBlankLines)
            AppendFactInt(builder, entry.CurrentAssertionMarkers)
            AppendFactInt(builder, entry.CurrentBytes)
            AppendFactString(builder, entry.CurrentFingerprint)
            builder.Append('\n')
            i = i + 1
        }
        return "head-v2:" + Fingerprint(builder.ToString()).Substring("text-v1:".Length)
    }

    static func Observe(path: string, classification: OwnershipClassification, text: string): OwnershipObservedFile {
        normalized := NormalizeText(text)
        lines := CountLines(normalized)
        nonBlank := CountNonBlankLines(normalized)
        assertions := 0
        if OwnershipPolicy.IsAssertionTracked(path, classification.Language) {
            assertions = CountAssertionMarkers(normalized)
        }
        return new OwnershipObservedFile(
            path,
            classification.Language,
            classification.Surface,
            classification.CampaignScope,
            lines,
            nonBlank,
            assertions,
            0,
            Fingerprint(normalized)
        )
    }

    static func ObserveBinary(
        path: string,
        classification: OwnershipClassification,
        bytes: byte[]
    ): OwnershipObservedFile {
        return new OwnershipObservedFile(
            path,
            classification.Language,
            classification.Surface,
            classification.CampaignScope,
            0,
            0,
            0,
            bytes.Length,
            FingerprintBytes(bytes)
        )
    }

    static func CountLines(normalizedText: string): int {
        if normalizedText.Length == 0 {
            return 0
        }
        count := 0
        i := 0
        while i < normalizedText.Length {
            if normalizedText[i] == '\n' {
                count = count + 1
            }
            i = i + 1
        }
        if normalizedText[normalizedText.Length - 1] != '\n' {
            count = count + 1
        }
        return count
    }

    static func CountNonBlankLines(normalizedText: string): int {
        count := 0
        lineStart := 0
        i := 0
        while i <= normalizedText.Length {
            if i == normalizedText.Length || normalizedText[i] == '\n' {
                hasContent := false
                j := lineStart
                while j < i {
                    if !Char.IsWhiteSpace(normalizedText[j]) {
                        hasContent = true
                        break
                    }
                    j = j + 1
                }
                if hasContent {
                    count = count + 1
                }
                lineStart = i + 1
            }
            i = i + 1
        }
        return count
    }

    static func CountAssertionMarkers(text: string): int {
        return CountOccurrences(text, "[Fact]") + CountOccurrences(text, "[Theory]") + CountOccurrences(text, "Assert.") + CountOccurrences(text, "Should(") + CountOccurrences(text, "test(") + CountOccurrences(text, "it(") + CountOccurrences(text, "expect(")
    }

    static func SortStrings(values: List<string>) {
        i := 1
        while i < values.Count {
            current := values[i]
            j := i
            while j > 0 && String.Compare(values[j - 1], current, StringComparison.Ordinal) > 0 {
                values[j] = values[j - 1]
                j = j - 1
            }
            values[j] = current
            i = i + 1
        }
    }

    static func CountOccurrences(text: string, marker: string): int {
        count := 0
        start := 0
        while start < text.Length {
            index := text.IndexOf(marker, start, StringComparison.Ordinal)
            if index < 0 {
                break
            }
            count = count + 1
            start = index + marker.Length
        }
        return count
    }

    static func AppendFactString(builder: StringBuilder, value: string) {
        builder.Append(value.Length)
        builder.Append(':')
        builder.Append(value)
        builder.Append(';')
    }

    static func AppendFactInt(builder: StringBuilder, value: int) {
        builder.Append(value)
        builder.Append(';')
    }

    static func Hex64(value: ulong): string {
        digits := "0123456789abcdef"
        builder := new StringBuilder(16)
        shift := 60
        while shift >= 0 {
            nibble := (int)((value >> shift) & 15UL)
            builder.Append(digits[nibble])
            shift = shift - 4
        }
        return builder.ToString()
    }
}

class OwnershipAudit {
    static func AuditLiveRepository(): OwnershipAuditResult {
        result := new OwnershipAuditResult()
        root := FindRepositoryRoot(Environment.CurrentDirectory)
        if root == null {
            result.Add("OWN010", "", "repository root is invalid; expected AGENTS.md, src, and tests sentinels")
            result.Sort()
            return result
        }

        manifestPath := Path.Combine(root, "tests/native/ownership-audit/" + OwnershipPolicy.ManifestFileName)
        if !File.Exists(manifestPath) {
            result.Add("OWN010", "", "ownership manifest is missing: tests/native/ownership-audit/" + OwnershipPolicy.ManifestFileName)
            result.Sort()
            return result
        }

        try {
            observed := ScanRepository(root, result)
            if result.Diagnostics.Count > 0 {
                result.Sort()
                return result
            }

            return AuditSnapshotAgainstPolicy(
                File.ReadAllText(manifestPath),
                observed,
                OwnershipPolicy.CodeEpochFileCount,
                OwnershipPolicy.CodeEpochPathFingerprint,
                OwnershipPolicy.CodeEpochFactFingerprint,
                OwnershipPolicy.ReviewedHeadFingerprint
            )
        } catch ex: Exception {
            result.Add("OWN010", "", "repository ownership scan failed: " + ex.Message)
            result.Sort()
            return result
        }
    }

    static func AuditSnapshot(
        manifestText: string,
        observed: List<OwnershipObservedFile>,
        enforceLiveEpoch: bool
    ): OwnershipAuditResult {
        if enforceLiveEpoch {
            return AuditSnapshotAgainstPolicy(
                manifestText,
                observed,
                OwnershipPolicy.CodeEpochFileCount,
                OwnershipPolicy.CodeEpochPathFingerprint,
                OwnershipPolicy.CodeEpochFactFingerprint,
                OwnershipPolicy.ReviewedHeadFingerprint
            )
        }
        result := new OwnershipAuditResult()
        manifest := ParseManifest(manifestText, result)
        if manifest == null {
            result.Sort()
            return result
        }

        ValidateManifest(manifest, result)
        CompareSnapshot(manifest, observed, result)
        result.Sort()
        return result
    }

    static func AuditSnapshotAgainstPolicy(
        manifestText: string,
        observed: List<OwnershipObservedFile>,
        expectedCodeEpochFileCount: int,
        expectedPathFingerprint: string,
        expectedCodeEpochFactFingerprint: string,
        expectedReviewedHeadFingerprint: string
    ): OwnershipAuditResult {
        result := AuditSnapshot(manifestText, observed, false)
        parseResult := new OwnershipAuditResult()
        manifest := ParseManifest(manifestText, parseResult)
        if manifest == null {
            return result
        }
        if manifest.CodeEpochFileCount != expectedCodeEpochFileCount {
            result.Add("OWN008", "", "policy code epoch file count changed; expected " + Number(expectedCodeEpochFileCount))
        }
        if manifest.CodeEpochPathFingerprint != expectedPathFingerprint {
            result.Add("OWN008", "", "policy code path fingerprint changed; expected " + expectedPathFingerprint)
        }
        if manifest.CodeEpochFactFingerprint != expectedCodeEpochFactFingerprint {
            result.Add("OWN008", "", "policy code epoch facts changed; expected " + expectedCodeEpochFactFingerprint)
        }
        if manifest.ReviewedHeadFingerprint != expectedReviewedHeadFingerprint {
            result.Add("OWN008", "", "policy reviewed head changed; expected " + expectedReviewedHeadFingerprint)
        }
        result.Sort()
        return result
    }

    static func FindRepositoryRoot(startPath: string): string? {
        current: string? = Path.GetFullPath(startPath)
        while current != null {
            value := current ?? ""
            if File.Exists(Path.Combine(value, "AGENTS.md")) && Directory.Exists(Path.Combine(value, "src")) && Directory.Exists(Path.Combine(value, "tests")) {
                return value
            }
            parent := Path.GetDirectoryName(value)
            if parent == null || parent == "" || parent == value {
                current = null
            } else {
                current = parent
            }
        }
        return null
    }

    static func ScanRepository(root: string, result: OwnershipAuditResult): List<OwnershipObservedFile> {
        observed := new List<OwnershipObservedFile>()
        if !Directory.Exists(root) {
            result.Add("OWN010", "", "repository root does not exist: " + root)
            return observed
        }

        ScanDirectory(root, root, observed, result)
        SortObserved(observed)
        if observed.Count == 0 {
            result.Add("OWN010", "", "repository scan found no non-N# ownership files")
        }
        return observed
    }

    static func ScanDirectory(
        root: string,
        directory: string,
        observed: List<OwnershipObservedFile>,
        result: OwnershipAuditResult
    ) {
        files := Directory.GetFiles(directory, "*", SearchOption.TopDirectoryOnly)
        SortStringArray(files)
        i := 0
        while i < files.Length {
            relative := OwnershipPolicy.NormalizeRelativePath(Path.GetRelativePath(root, files[i]))
            classification := OwnershipPolicy.Classify(relative)
            if classification.Unknown {
                result.Add(
                    "OWN009",
                    relative,
                    "unknown product-adjacent file type; classify it in N# or remove it before it can enter the ownership epoch"
                )
            } else if classification.Included {
                if OwnershipPolicy.IsBinaryLanguage(classification.Language) {
                    observed.Add(OwnershipFacts.ObserveBinary(
                        relative,
                        classification,
                        OwnershipManagedFile.ReadAllBytes(files[i])
                    ))
                } else {
                    observed.Add(OwnershipFacts.Observe(relative, classification, File.ReadAllText(files[i])))
                }
            }
            i = i + 1
        }

        directories := Directory.GetDirectories(directory, "*", SearchOption.TopDirectoryOnly)
        SortStringArray(directories)
        i = 0
        while i < directories.Length {
            relativeDirectory := OwnershipPolicy.NormalizeRelativePath(Path.GetRelativePath(root, directories[i]))
            if !OwnershipPolicy.ShouldSkipDirectory(relativeDirectory) {
                ScanDirectory(root, directories[i], observed, result)
            }
            i = i + 1
        }
    }

    static func ParseManifest(text: string, result: OwnershipAuditResult): OwnershipManifest? {
        try {
            document := JsonDocument.Parse(text)
            root := document.RootElement
            if root.ValueKind != JsonValueKind.Object {
                result.Add("OWN001", "", "manifest root must be a JSON object")
                document.Dispose()
                return null
            }

            declaredVersion := ReadSchemaVersion(root)
            if declaredVersion != OwnershipPolicy.SchemaVersion {
                result.Add("OWN001", "", SchemaRejection(declaredVersion))
                document.Dispose()
                return null
            }

            manifest := new OwnershipManifest()
            rootFields := new HashSet<string>(StringComparer.Ordinal)
            rootEnumerator := root.EnumerateObject()
            while rootEnumerator.MoveNext() {
                property := rootEnumerator.Current
                if !rootFields.Add(property.Name) {
                    result.Add("OWN001", "", "duplicate root field '" + property.Name + "'")
                } else if property.Name == "schemaVersion" {
                    // Read and gated before any field parsing; accepted here as a known field.
                    continue
                } else if property.Name == "phase" {
                    manifest.Phase = RequireString(property.Value, "phase", "", result)
                } else if property.Name == "codeEpochFileCount" {
                    if property.Value.ValueKind == JsonValueKind.Number {
                        manifest.CodeEpochFileCount = property.Value.GetInt32()
                    } else {
                        result.Add("OWN001", "", "epochFileCount must be an integer")
                    }
                } else if property.Name == "codeEpochPathFingerprint" {
                    manifest.CodeEpochPathFingerprint = RequireString(property.Value, "codeEpochPathFingerprint", "", result)
                } else if property.Name == "codeEpochFactFingerprint" {
                    manifest.CodeEpochFactFingerprint = RequireString(property.Value, "codeEpochFactFingerprint", "", result)
                } else if property.Name == "reviewedHeadFingerprint" {
                    manifest.ReviewedHeadFingerprint = RequireString(property.Value, "reviewedHeadFingerprint", "", result)
                } else if property.Name == "files" {
                    ParseEntries(property.Value, manifest.Files, result)
                } else {
                    result.Add("OWN001", "", "unknown root field '" + property.Name + "'")
                }
            }

            RequireRootField(rootFields, "schemaVersion", result)
            RequireRootField(rootFields, "phase", result)
            RequireRootField(rootFields, "codeEpochFileCount", result)
            RequireRootField(rootFields, "codeEpochPathFingerprint", result)
            RequireRootField(rootFields, "codeEpochFactFingerprint", result)
            RequireRootField(rootFields, "reviewedHeadFingerprint", result)
            RequireRootField(rootFields, "files", result)
            document.Dispose()
            return manifest
        } catch ex: Exception {
            result.Add("OWN001", "", "manifest is not valid strict JSON: " + ex.Message)
            return null
        }
    }

    static func ReadSchemaVersion(root: JsonElement): int {
        version := 0
        enumerator := root.EnumerateObject()
        while enumerator.MoveNext() {
            property := enumerator.Current
            if property.Name == "schemaVersion" && property.Value.ValueKind == JsonValueKind.Number {
                version = property.Value.GetInt32()
            }
        }
        return version
    }

    static func SchemaRejection(declaredVersion: int): string {
        if declaredVersion == 1 {
            return "schemaVersion 1 is the pre-E1 growth ratchet and is no longer accepted: it gave every row a ceiling and froze the file set against config and delivery changes. Regenerate the manifest at schemaVersion 2, where code rows keep their epoch ceilings under codeEpochFileCount, codeEpochPathFingerprint and codeEpochFactFingerprint, and config, MSBuild, shell and binary rows become reviewed delivery rows carrying a fingerprint and line counts but no ceiling"
        }
        if declaredVersion == 0 {
            return "manifest declares no integer schemaVersion; expected " + Number(OwnershipPolicy.SchemaVersion)
        }
        return "unsupported schemaVersion " + Number(declaredVersion) + "; expected " + Number(OwnershipPolicy.SchemaVersion)
    }

    static func ParseEntries(element: JsonElement, entries: List<OwnershipManifestEntry>, result: OwnershipAuditResult) {
        if element.ValueKind != JsonValueKind.Array {
            result.Add("OWN001", "", "files must be an array")
            return
        }
        enumerator := element.EnumerateArray()
        while enumerator.MoveNext() {
            item := enumerator.Current
            if item.ValueKind != JsonValueKind.Object {
                result.Add("OWN001", "", "every files entry must be an object")
            } else {
                entries.Add(ParseEntry(item, result))
            }
        }
    }

    static func ParseEntry(element: JsonElement, result: OwnershipAuditResult): OwnershipManifestEntry {
        entry := new OwnershipManifestEntry()
        fields := new HashSet<string>(StringComparer.Ordinal)
        enumerator := element.EnumerateObject()
        while enumerator.MoveNext() {
            property := enumerator.Current
            path := entry.Path
            if !fields.Add(property.Name) {
                result.Add("OWN001", path, "duplicate entry field '" + property.Name + "'")
            } else if property.Name == "path" {
                entry.Path = RequireString(property.Value, "path", path, result)
            } else if property.Name == "language" {
                entry.Language = RequireString(property.Value, "language", path, result)
            } else if property.Name == "surface" {
                entry.Surface = RequireString(property.Value, "surface", path, result)
            } else if property.Name == "campaignScope" {
                entry.CampaignScope = RequireString(property.Value, "campaignScope", path, result)
            } else if property.Name == "state" {
                entry.State = RequireString(property.Value, "state", path, result)
            } else if property.Name == "epochLines" {
                entry.EpochLines = RequireInt(property.Value, "epochLines", path, result)
            } else if property.Name == "currentLines" {
                entry.CurrentLines = RequireInt(property.Value, "currentLines", path, result)
            } else if property.Name == "epochNonBlankLines" {
                entry.EpochNonBlankLines = RequireInt(property.Value, "epochNonBlankLines", path, result)
            } else if property.Name == "currentNonBlankLines" {
                entry.CurrentNonBlankLines = RequireInt(property.Value, "currentNonBlankLines", path, result)
            } else if property.Name == "epochAssertionMarkers" {
                entry.EpochAssertionMarkers = RequireInt(property.Value, "epochAssertionMarkers", path, result)
            } else if property.Name == "currentAssertionMarkers" {
                entry.CurrentAssertionMarkers = RequireInt(property.Value, "currentAssertionMarkers", path, result)
            } else if property.Name == "epochBytes" {
                entry.EpochBytes = RequireInt(property.Value, "epochBytes", path, result)
            } else if property.Name == "currentBytes" {
                entry.CurrentBytes = RequireInt(property.Value, "currentBytes", path, result)
            } else if property.Name == "currentFingerprint" {
                entry.CurrentFingerprint = RequireString(property.Value, "currentFingerprint", path, result)
            } else {
                result.Add("OWN001", path, "unknown entry field '" + property.Name + "'")
            }
        }

        RequireEntryField(fields, "path", entry.Path, result)
        RequireEntryField(fields, "language", entry.Path, result)
        RequireEntryField(fields, "surface", entry.Path, result)
        RequireEntryField(fields, "campaignScope", entry.Path, result)
        RequireEntryField(fields, "state", entry.Path, result)
        RequireEntryField(fields, "currentLines", entry.Path, result)
        RequireEntryField(fields, "currentNonBlankLines", entry.Path, result)
        RequireEntryField(fields, "currentBytes", entry.Path, result)
        RequireEntryField(fields, "currentFingerprint", entry.Path, result)
        // The row class is derived from the path, so a row cannot declare itself out of its shape.
        if OwnershipPolicy.IsDeliveryPath(entry.Path) {
            RejectEntryField(fields, "epochLines", entry.Path, result)
            RejectEntryField(fields, "epochNonBlankLines", entry.Path, result)
            RejectEntryField(fields, "epochAssertionMarkers", entry.Path, result)
            RejectEntryField(fields, "epochBytes", entry.Path, result)
            RejectEntryField(fields, "currentAssertionMarkers", entry.Path, result)
        } else {
            RequireEntryField(fields, "epochLines", entry.Path, result)
            RequireEntryField(fields, "epochNonBlankLines", entry.Path, result)
            RequireEntryField(fields, "epochAssertionMarkers", entry.Path, result)
            RequireEntryField(fields, "epochBytes", entry.Path, result)
            RequireEntryField(fields, "currentAssertionMarkers", entry.Path, result)
        }
        return entry
    }

    static func ValidateManifest(
        manifest: OwnershipManifest,
        result: OwnershipAuditResult
    ) {
        if manifest.Phase != "growth-ratchet" {
            result.Add("OWN001", "", "phase must be exactly 'growth-ratchet'")
        }
        codeRowCount := OwnershipFacts.CodeRows(manifest.Files).Count
        if manifest.CodeEpochFileCount != codeRowCount {
            result.Add("OWN008", "", "codeEpochFileCount " + Number(manifest.CodeEpochFileCount) + " does not match the code row count " + Number(codeRowCount))
        }

        exactPaths := new HashSet<string>(StringComparer.Ordinal)
        casePaths := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        previous := ""
        i := 0
        while i < manifest.Files.Count {
            entry := manifest.Files[i]
            if !OwnershipPolicy.IsCanonicalManifestPath(entry.Path) {
                result.Add("OWN002", entry.Path, "manifest path is not canonical; use a repository-relative '/' path with no traversal or wildcards")
            }
            if !exactPaths.Add(entry.Path) {
                result.Add("OWN002", entry.Path, "manifest path is duplicated")
            } else if !casePaths.Add(entry.Path) {
                result.Add("OWN002", entry.Path, "manifest path aliases another entry by case")
            }
            if i > 0 && String.Compare(previous, entry.Path, StringComparison.Ordinal) >= 0 {
                result.Add("OWN002", entry.Path, "manifest paths must be unique and sorted ordinally")
            }
            previous = entry.Path

            classification := OwnershipPolicy.Classify(entry.Path)
            if !classification.Included || classification.Unknown {
                result.Add("OWN002", entry.Path, "manifest path is not classified as audited non-N# ownership by the N# policy")
            } else {
                if entry.Language != classification.Language {
                    result.Add("OWN002", entry.Path, "language '" + entry.Language + "' does not match derived '" + classification.Language + "'")
                }
                if entry.Surface != classification.Surface {
                    result.Add("OWN002", entry.Path, "surface '" + entry.Surface + "' does not match derived '" + classification.Surface + "'")
                }
                if entry.CampaignScope != classification.CampaignScope {
                    result.Add("OWN002", entry.Path, "campaignScope '" + entry.CampaignScope + "' does not match derived '" + classification.CampaignScope + "'")
                }
            }

            if OwnershipPolicy.IsDeliveryLanguage(entry.Language) {
                if entry.State != "reviewed" && entry.State != "removed" {
                    result.Add("OWN001", entry.Path, "a delivery row state must be 'reviewed' or 'removed'")
                }
            } else if entry.State != "existing-debt" && entry.State != "removed" {
                result.Add("OWN001", entry.Path, "a code row state must be 'existing-debt' or 'removed'; survivor verdicts are forbidden before H8")
            }
            ValidateMetrics(entry, result)
            i = i + 1
        }

        pathFingerprint := OwnershipFacts.CodeEpochPathFingerprint(manifest.Files)
        if manifest.CodeEpochPathFingerprint != pathFingerprint {
            result.Add("OWN008", "", "codeEpochPathFingerprint does not match the sorted code row path set; observed " + pathFingerprint)
        }
        epochFactFingerprint := OwnershipFacts.CodeEpochFactFingerprint(manifest.Files)
        if manifest.CodeEpochFactFingerprint != epochFactFingerprint {
            result.Add("OWN008", "", "codeEpochFactFingerprint does not match canonical code row paths, classifications, and epoch ceilings; observed " + epochFactFingerprint)
        }
        reviewedHeadFingerprint := OwnershipFacts.ReviewedHeadFingerprint(manifest.Files)
        if manifest.ReviewedHeadFingerprint != reviewedHeadFingerprint {
            result.Add("OWN008", "", "reviewedHeadFingerprint does not match the canonical current facts and states of every row; observed " + reviewedHeadFingerprint)
        }
    }

    static func ValidateMetrics(entry: OwnershipManifestEntry, result: OwnershipAuditResult) {
        if entry.EpochLines < 0 || entry.CurrentLines < 0 || entry.EpochNonBlankLines < 0 || entry.CurrentNonBlankLines < 0 || entry.EpochAssertionMarkers < 0 || entry.CurrentAssertionMarkers < 0 || entry.EpochBytes < 0 || entry.CurrentBytes < 0 {
            result.Add("OWN001", entry.Path, "ownership metrics cannot be negative")
        }
        if OwnershipPolicy.IsDeliveryLanguage(entry.Language) {
            ValidateDeliveryMetrics(entry, result)
        } else {
            ValidateCodeMetrics(entry, result)
        }
        ValidateRecordedFingerprint(entry, result)
    }

    // A delivery row records what review accepted. It has no ceiling to compare against; the
    // recorded counts exist so the audit and the repin can quote the reviewed size.
    static func ValidateDeliveryMetrics(entry: OwnershipManifestEntry, result: OwnershipAuditResult) {
        if OwnershipPolicy.IsBinaryLanguage(entry.Language) {
            if entry.CurrentLines != 0 || entry.CurrentNonBlankLines != 0 {
                result.Add("OWN001", entry.Path, "a binary delivery row records bytes only; line counts must be zero")
            }
        } else if entry.CurrentBytes != 0 {
            result.Add("OWN001", entry.Path, "a text delivery row records line counts only; byte counts must be zero")
        }
    }

    static func ValidateCodeMetrics(entry: OwnershipManifestEntry, result: OwnershipAuditResult) {
        if entry.EpochBytes != 0 || entry.CurrentBytes != 0 {
            result.Add("OWN001", entry.Path, "code ownership uses line and assertion ceilings; byte metrics must be zero")
        }
        if entry.CurrentLines > entry.EpochLines || entry.CurrentNonBlankLines > entry.EpochNonBlankLines || entry.CurrentAssertionMarkers > entry.EpochAssertionMarkers {
            result.Add("OWN004", entry.Path, "current ceilings cannot exceed immutable epoch ceilings")
        }
    }

    static func ValidateRecordedFingerprint(entry: OwnershipManifestEntry, result: OwnershipAuditResult) {
        if entry.State == "removed" {
            if entry.CurrentLines != 0 || entry.CurrentNonBlankLines != 0 || entry.CurrentAssertionMarkers != 0 || entry.CurrentBytes != 0 || entry.CurrentFingerprint != "text-v1:removed" {
                result.Add("OWN001", entry.Path, "removed entries require zero current metrics and fingerprint 'text-v1:removed'")
            }
        } else if !IsFingerprintForLanguage(entry.CurrentFingerprint, entry.Language) {
            expectedPrefix := "text-v1"
            if OwnershipPolicy.IsBinaryLanguage(entry.Language) {
                expectedPrefix = "binary-v1"
            }
            result.Add(
                "OWN001",
                entry.Path,
                "currentFingerprint must be a lowercase deterministic " + expectedPrefix + " fingerprint"
            )
        }
    }

    static func CompareSnapshot(
        manifest: OwnershipManifest,
        observed: List<OwnershipObservedFile>,
        result: OwnershipAuditResult
    ) {
        entries := new Dictionary<string, OwnershipManifestEntry>(StringComparer.Ordinal)
        i := 0
        while i < manifest.Files.Count {
            entry := manifest.Files[i]
            if !entries.ContainsKey(entry.Path) {
                entries.Add(entry.Path, entry)
            }
            i = i + 1
        }

        observedPaths := new HashSet<string>(StringComparer.Ordinal)
        casePaths := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        i = 0
        while i < observed.Count {
            observedFile := observed[i]
            if !observedPaths.Add(observedFile.Path) {
                result.Add("OWN002", observedFile.Path, "repository scan produced a duplicate path")
                i = i + 1
                continue
            }
            if !casePaths.Add(observedFile.Path) {
                result.Add("OWN002", observedFile.Path, "repository contains case-aliasing ownership paths")
            }

            entry := new OwnershipManifestEntry()
            hasEntry := entries.TryGetValue(observedFile.Path, out entry)
            // The class comes from the observed file, never from what a row claims, so a
            // mislabelled row can never move a code file out of the ratchet.
            isDelivery := OwnershipPolicy.IsDeliveryLanguage(observedFile.Language)
            if !hasEntry {
                if isDelivery {
                    result.Add("OWN003", observedFile.Path, "new delivery file with no reviewed row; a config, MSBuild, shell or binary file is admitted only by adding its row in a reviewed repin, never implicitly")
                } else {
                    result.Add("OWN003", observedFile.Path, "new unclassified non-N# file; implement this behavior in N# or remove the file. Do not add it to the E1 code epoch")
                }
                i = i + 1
                continue
            }
            if entry.State == "removed" {
                result.Add("OWN007", observedFile.Path, "removed ownership path reappeared; delete it rather than restoring debt")
                i = i + 1
                continue
            }

            if observedFile.Language != entry.Language || observedFile.Surface != entry.Surface || observedFile.CampaignScope != entry.CampaignScope {
                result.Add("OWN002", observedFile.Path, "observed classification does not match the manifest classification")
            }
            if isDelivery {
                CompareDeliveryRow(observedFile, entry, result)
            } else {
                CompareCodeRow(observedFile, entry, result)
            }
            i = i + 1
        }

        i = 0
        while i < manifest.Files.Count {
            entry := manifest.Files[i]
            if entry.State != "removed" && !observedPaths.Contains(entry.Path) {
                if OwnershipPolicy.IsDeliveryLanguage(entry.Language) {
                    result.Add("OWN006", entry.Path, "reviewed delivery file disappeared; review its retirement explicitly and mark the row removed in the same deletion commit")
                } else {
                    result.Add("OWN006", entry.Path, "active debt entry disappeared; mark it removed in the same deletion commit")
                }
            }
            i = i + 1
        }
    }

    // A delivery row has no ceiling: drift is always reported, and the repin is the review.
    static func CompareDeliveryRow(
        observedFile: OwnershipObservedFile,
        entry: OwnershipManifestEntry,
        result: OwnershipAuditResult
    ) {
        if observedFile.Fingerprint != entry.CurrentFingerprint {
            result.Add(
                "OWN005",
                observedFile.Path,
                "reviewed delivery snapshot drift; expected " + entry.CurrentFingerprint + "; observed " + observedFile.Fingerprint + " at lines=" + Number(observedFile.Lines) + ", nonblank=" + Number(observedFile.NonBlankLines) + ", bytes=" + Number(observedFile.Bytes) + ". A delivery row carries no ceiling: review the change and repin this row"
            )
            return
        }
        if observedFile.Lines != entry.CurrentLines || observedFile.NonBlankLines != entry.CurrentNonBlankLines || observedFile.Bytes != entry.CurrentBytes {
            result.Add(
                "OWN001",
                observedFile.Path,
                "reviewed delivery row records stale counts for its reviewed fingerprint; observed lines=" + Number(observedFile.Lines) + ", nonblank=" + Number(observedFile.NonBlankLines) + ", bytes=" + Number(observedFile.Bytes)
            )
        }
    }

    // A code row keeps the growth ratchet exactly: exact current facts under an immutable ceiling.
    static func CompareCodeRow(
        observedFile: OwnershipObservedFile,
        entry: OwnershipManifestEntry,
        result: OwnershipAuditResult
    ) {
        if observedFile.Lines != entry.CurrentLines || observedFile.NonBlankLines != entry.CurrentNonBlankLines || observedFile.AssertionMarkers != entry.CurrentAssertionMarkers || observedFile.Bytes != entry.CurrentBytes {
            result.Add(
                "OWN004",
                observedFile.Path,
                "observed metrics lines=" + Number(observedFile.Lines) + ", nonblank=" + Number(observedFile.NonBlankLines) + ", assertions=" + Number(observedFile.AssertionMarkers) + ", bytes=" + Number(observedFile.Bytes) + "; allowed current lines=" + Number(entry.CurrentLines) + ", nonblank=" + Number(entry.CurrentNonBlankLines) + ", assertions=" + Number(entry.CurrentAssertionMarkers) + ", bytes=" + Number(entry.CurrentBytes) + ". Never raise a ceiling"
            )
        }
        if observedFile.Lines > entry.EpochLines || observedFile.NonBlankLines > entry.EpochNonBlankLines || observedFile.AssertionMarkers > entry.EpochAssertionMarkers {
            result.Add("OWN004", observedFile.Path, "observed ownership exceeds the immutable E1 epoch ceiling")
        }
        if observedFile.Fingerprint != entry.CurrentFingerprint {
            result.Add(
                "OWN005",
                observedFile.Path,
                "fingerprint drift; observed " + observedFile.Fingerprint + ". For an approved shrink, review the same-commit N# owner, lower current ceilings, and update the fingerprint. Never raise a ceiling"
            )
        }
    }

    static func RequireRootField(fields: HashSet<string>, name: string, result: OwnershipAuditResult) {
        if !fields.Contains(name) {
            result.Add("OWN001", "", "missing required root field '" + name + "'")
        }
    }

    static func RequireEntryField(
        fields: HashSet<string>,
        name: string,
        path: string,
        result: OwnershipAuditResult
    ) {
        if !fields.Contains(name) {
            result.Add("OWN001", path, "manifest entry is missing required field '" + name + "'")
        }
    }

    static func RejectEntryField(
        fields: HashSet<string>,
        name: string,
        path: string,
        result: OwnershipAuditResult
    ) {
        if fields.Contains(name) {
            result.Add("OWN001", path, "a reviewed delivery row carries no ceiling; remove field '" + name + "'")
        }
    }

    static func RequireString(element: JsonElement, name: string, path: string, result: OwnershipAuditResult): string {
        if element.ValueKind != JsonValueKind.String {
            result.Add("OWN001", path, "field '" + name + "' must be a string")
            return ""
        }
        return element.GetString() ?? ""
    }

    static func RequireInt(element: JsonElement, name: string, path: string, result: OwnershipAuditResult): int {
        if element.ValueKind != JsonValueKind.Number {
            result.Add("OWN001", path, "field '" + name + "' must be an integer")
            return 0
        }
        return element.GetInt32()
    }

    static func SortObserved(values: List<OwnershipObservedFile>) {
        i := 1
        while i < values.Count {
            current := values[i]
            j := i
            while j > 0 && String.Compare(values[j - 1].Path, current.Path, StringComparison.Ordinal) > 0 {
                values[j] = values[j - 1]
                j = j - 1
            }
            values[j] = current
            i = i + 1
        }
    }

    static func SortStringArray(values: string[]) {
        i := 1
        while i < values.Length {
            current := values[i]
            j := i
            while j > 0 && String.Compare(values[j - 1], current, StringComparison.Ordinal) > 0 {
                values[j] = values[j - 1]
                j = j - 1
            }
            values[j] = current
            i = i + 1
        }
    }

    static func Number(value: int): string {
        return value.ToString()
    }

    static func IsFingerprintForLanguage(value: string, language: string): bool {
        prefix := "text-v1:"
        if OwnershipPolicy.IsBinaryLanguage(language) {
            prefix = "binary-v1:"
        }
        if !value.StartsWith(prefix, StringComparison.Ordinal) || value.Length != prefix.Length + 16 {
            return false
        }
        i := prefix.Length
        while i < value.Length {
            c := value[i]
            if !(c >= '0' && c <= '9') && !(c >= 'a' && c <= 'f') {
                return false
            }
            i = i + 1
        }
        return true
    }
}
