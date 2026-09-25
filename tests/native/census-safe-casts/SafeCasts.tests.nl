namespace Census.SafeCasts.Tests

import System
import System.Collections.Generic
import System.IO
import Census.Nullability
import NSharpLang.Compiler


// ── the runtime half: a narrowed `as` result is the value, and a failed cast is still null ──────
test "a narrowed safe cast reads the value, and a failed one takes the other branch" {
    assert BarkIfDog(new Dog("rex")) == "rex barks/rex barks"
    assert BarkIfDog(new Animal("tom")) == "not a dog"
    assert BarkOrReturn(new Dog("ace")) == "ace barks"
    assert BarkOrReturn(new Animal("tom")) == "not a dog"
    assert BarkThroughPattern(new Dog("max")) == "max barks"
    assert BarkThroughPattern("text") == "not a dog"
    assert BarkOrFallback(new Animal("tom")) == "stand-in barks"
    assert NameIfDog(new Dog("rex")) == "rex"
    assert NameIfDog(new Animal("tom")) == null
    assert UpcastName(new Dog("upcast")) == "upcast"
    assert TextHash("same") == "same".GetHashCode()
}

// ── the analysis half, in one project and in two ──────────────────────────────────────────────
//
// The consumer is analysed once beside the fixture library's own source and once against its BUILT
// assembly (`tests/fixtures/census-external-nullability-library`), and a safe cast to a referenced
// class must be judged exactly as a safe cast to the same class in source.
func CastRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "AGENTS.md")) && Directory.Exists(Path.Combine(directory, "src")) && Directory.Exists(Path.Combine(directory, "tests")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            break
        }
        current = parent
    }

    throw new InvalidOperationException("Could not locate the N# repository root from " + AppContext.BaseDirectory + ".")
}

func CastLibrarySource(): string {
    fixtures := Path.Combine(Path.Combine(CastRepositoryRoot(), "tests"), "fixtures")
    return File.ReadAllText(Path.Combine(Path.Combine(fixtures, "census-external-nullability-library"), "Holder.nl"))
}

func CastRoot(tag: string): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-safe-casts-" + tag + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return root
}

func CastProject(root: string, name: string, extraDependencies: string) {
    dependencies := extraDependencies.Length == 0 ? "" : "\ndependencies:\n" + extraDependencies
    File.WriteAllText(Path.Combine(root, "project.yml"), "name: " + name + "\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n" + dependencies)
}

// Analysis and lint, the way `nlc build` validates a project.
func CastAnalyze(root: string, name: string): List<CompilerError> {
    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    compiler := new MultiFileCompiler(root, config)
    compiler.AotMode = false
    result := compiler.CompileToIlAssembly(name, Path.Combine(Path.Combine(root, "out"), name + ".dll"), true, true)
    errors := new List<CompilerError>()
    for error in result.Errors {
        errors.Add(error)
    }
    return errors
}

// The consumer file's diagnostics of one code, as `line:column message`, in report order.
func CastFindings(errors: List<CompilerError>, code: string): List<string> {
    findings := new List<string>()
    for error in errors {
        fileName := error.FileName ?? ""
        if error.DiagnosticId == code && fileName.EndsWith("Consumer.nl", StringComparison.Ordinal) {
            findings.Add(error.Line.ToString() + ":" + error.Column.ToString() + " " + error.Message)
        }
    }
    return findings
}

func CastText(errors: List<CompilerError>): string {
    text := ""
    for error in errors {
        text = text + error.DiagnosticId + " " + (error.FileName ?? "") + ":" + error.Line.ToString() + " " + error.Message + "\n"
    }
    return text
}

func CastBothShapes(tag: string, body: string, out oneProject: List<CompilerError>, out twoProjects: List<CompilerError>) {
    consumer := "namespace Census.Nullability.Consumer\n\nimport Census.Nullability\n\nclass Uses {\n" + body + "}\n"
    single := CastRoot(tag + "-one")
    CastProject(single, "SafeCastsOneProject", "")
    File.WriteAllText(Path.Combine(single, "Holder.nl"), CastLibrarySource())
    File.WriteAllText(Path.Combine(single, "Consumer.nl"), consumer)
    oneProject = CastAnalyze(single, "SafeCastsOneProject")

    split := CastRoot(tag + "-two")
    CastProject(split, "SafeCastsTwoProjects", "  - dll: " + typeof(Holder).Assembly.Location + "\n")
    File.WriteAllText(Path.Combine(split, "Consumer.nl"), consumer)
    twoProjects = CastAnalyze(split, "SafeCastsTwoProjects")
}

func CastSameFindings(oneProject: List<CompilerError>, twoProjects: List<CompilerError>, code: string): bool {
    return string.Join("\n", CastFindings(oneProject, code)) == string.Join("\n", CastFindings(twoProjects, code))
}

test "dereferencing an unchecked safe cast is NL905, in one project and in two" {
    body := "    static func Local(value: object): int {\n        node := value as Node\n        return node.Name.Length\n    }\n\n    static func Direct(value: object): int {\n        return (value as Node).Name.Length\n    }\n\n    static func Text(value: object): int {\n        text := value as string\n        return text.Length\n    }\n"
    oneProject := new List<CompilerError>()
    twoProjects := new List<CompilerError>()
    CastBothShapes("dereference", body, out oneProject, out twoProjects)

    single := CastFindings(oneProject, "NL905")
    assert single.Count == 3, CastText(oneProject)
    joined := string.Join("\n", single)
    assert joined.Contains("Possible null dereference: `node` is maybe-null"), CastText(oneProject)
    assert joined.Contains("Possible null dereference: `text` is maybe-null"), CastText(oneProject)
    assert CastSameFindings(oneProject, twoProjects, "NL905"), "two projects:\n" + CastText(twoProjects) + "---- one project:\n" + CastText(oneProject)
}

test "passing or returning an unchecked safe cast as not-null is NL202, in one project and in two" {
    body := "    static func Pass(value: object): int {\n        return Holder.Take(value as Node)\n    }\n\n    static func PassLocal(value: object): int {\n        node := value as Node\n        return Holder.Take(node)\n    }\n\n    static func Give(value: object): Node {\n        return value as Node\n    }\n\n    static func Maybe(value: object): int {\n        return Holder.TakeMaybe(value as Node)\n    }\n"
    oneProject := new List<CompilerError>()
    twoProjects := new List<CompilerError>()
    CastBothShapes("arguments", body, out oneProject, out twoProjects)

    // `TakeMaybe(node: Node?)` accepts the maybe-null result; the other three positions state not-null.
    single := CastFindings(oneProject, "NL202")
    assert single.Count == 3, CastText(oneProject)
    assert string.Join("\n", single).Contains("Cannot pass `Node?` as argument for parameter `node` of type `Node`"), CastText(oneProject)
    assert CastSameFindings(oneProject, twoProjects, "NL202"), "two projects:\n" + CastText(twoProjects) + "---- one project:\n" + CastText(oneProject)
}

test "a narrowed or guarded safe cast, and an upcast, report nothing" {
    body := "    static func Checked(value: object): int {\n        node := value as Node\n        if node != null {\n            return node.Name.Length + Holder.Take(node)\n        }\n        return 0\n    }\n\n    static func Returned(value: object): int {\n        node := value as Node\n        if node == null {\n            return 0\n        }\n        return Holder.Take(node)\n    }\n\n    static func Pattern(value: object): int {\n        if value is Node node {\n            return Holder.Take(node)\n        }\n        return 0\n    }\n\n    static func Guarded(value: object): int {\n        return (value as Node)?.Name.Length ?? 0\n    }\n\n    static func Fallback(value: object): int {\n        node := value as Node ?? new Node(\"stand-in\")\n        return Holder.Take(node)\n    }\n\n    static func Upcast(node: Node): int {\n        boxed := node as object\n        return boxed.GetHashCode()\n    }\n"
    oneProject := new List<CompilerError>()
    twoProjects := new List<CompilerError>()
    CastBothShapes("narrowed", body, out oneProject, out twoProjects)

    assert CastFindings(oneProject, "NL905").Count == 0, CastText(oneProject)
    assert CastFindings(oneProject, "NL202").Count == 0, CastText(oneProject)
    assert CastFindings(twoProjects, "NL905").Count == 0, CastText(twoProjects)
    assert CastFindings(twoProjects, "NL202").Count == 0, CastText(twoProjects)
}

test "an upcast of a maybe-null value keeps the maybe" {
    body := "    static func Upcast(holder: Holder): int {\n        boxed := holder.Child as object\n        return boxed.GetHashCode()\n    }\n"
    oneProject := new List<CompilerError>()
    twoProjects := new List<CompilerError>()
    CastBothShapes("maybe-upcast", body, out oneProject, out twoProjects)

    assert CastFindings(oneProject, "NL905").Count == 1, CastText(oneProject)
    assert CastSameFindings(oneProject, twoProjects, "NL905"), "two projects:\n" + CastText(twoProjects) + "---- one project:\n" + CastText(oneProject)
}

// THE LEFT OPERAND OF `??` DENOTES ITS DECLARED VALUE, BUT ITS ARGUMENTS ARE READS OF THEIR OWN. The
// operand is walked with the flow type suppressed, and the suppression used to reach every argument
// nested inside it: `Label(node) ?? node.Name` reported NL202 on a `node` the enclosing `if` had
// proved, while the same call bound to a local on the line before did not.
test "a narrowed safe cast passed as an argument inside the left operand of ?? is not-null" {
    body := "    static func Label(node: Node): string? {\n        return null\n    }\n\n    static func Describe(value: object): string {\n        node := value as Node\n        if node != null {\n            return Label(node) ?? node.Name\n        }\n        return \"\"\n    }\n\n    static func Unchecked(value: object): string {\n        node := value as Node\n        return Label(node) ?? \"none\"\n    }\n"
    oneProject := new List<CompilerError>()
    twoProjects := new List<CompilerError>()
    CastBothShapes("coalesce", body, out oneProject, out twoProjects)

    // Only the unchecked call reports, and it reports exactly once.
    single := CastFindings(oneProject, "NL202")
    assert single.Count == 1, CastText(oneProject)
    assert single[0].StartsWith("20:"), CastText(oneProject)
    assert CastSameFindings(oneProject, twoProjects, "NL202"), "two projects:\n" + CastText(twoProjects) + "---- one project:\n" + CastText(oneProject)
}
