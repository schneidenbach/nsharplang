namespace Census.Nullability.Tests

import System
import System.Collections.Generic
import System.IO
import System.Linq
import System.Reflection
import System.Reflection.Emit
import Census.Nullability
import NSharpLang.Compiler


// A PROGRAM SPLIT INTO TWO PROJECTS MEANS WHAT IT MEANT AS ONE.
//
// The same consumer source is analysed twice: once in ONE project beside the fixture library's own
// source (`tests/fixtures/census-external-nullability-library/Holder.nl`), and once in a project that
// references the library's BUILT assembly -- the shape every slice of `Compiler.Core` takes once it is
// carved into its own project. Both must report exactly the same NL202s. Before this held, a maybe-null
// value of a referenced class type reached a not-null parameter unreported twice over: the CLR bridge
// in `AnalyzerAssignability` accepted `Node?` for `Node` (a reference `?` is not a CLR type), and a
// call to a referenced METHOD never asked about nullability at all once its overload was chosen.
func NullRepositoryRoot(): string {
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

func NullLibrarySource(): string {
    fixtures := Path.Combine(Path.Combine(NullRepositoryRoot(), "tests"), "fixtures")
    return File.ReadAllText(Path.Combine(Path.Combine(fixtures, "census-external-nullability-library"), "Holder.nl"))
}

func NullRoot(tag: string): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-external-nullability-" + tag + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return root
}

// `extraDependencies` is a `dependencies:` body, possibly empty.
func NullProject(root: string, name: string, extraDependencies: string) {
    dependencies := extraDependencies.Length == 0 ? "" : "\ndependencies:\n" + extraDependencies
    File.WriteAllText(Path.Combine(root, "project.yml"), "name: " + name + "\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n" + dependencies)
}

// Analysis and lint, the way `nlc build` validates a project.
func NullAnalyze(root: string, name: string): List<CompilerError> {
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
func NullConsumerFindings(errors: List<CompilerError>, code: string): List<string> {
    findings := new List<string>()
    for error in errors {
        fileName := error.FileName ?? ""
        if error.DiagnosticId == code && fileName.EndsWith("Consumer.nl", StringComparison.Ordinal) {
            findings.Add(error.Line.ToString() + ":" + error.Column.ToString() + " " + error.Message)
        }
    }
    return findings
}

func NullText(errors: List<CompilerError>): string {
    text := ""
    for error in errors {
        text = text + error.DiagnosticId + " " + (error.FileName ?? "") + ":" + error.Line.ToString() + " " + error.Message + "\n"
    }
    return text
}

// The same consumer, analysed in one project and against the referenced library.
func NullBothShapes(tag: string, consumer: string, out oneProject: List<CompilerError>, out twoProjects: List<CompilerError>) {
    single := NullRoot(tag + "-one")
    NullProject(single, "NullabilityOneProject", "")
    File.WriteAllText(Path.Combine(single, "Holder.nl"), NullLibrarySource())
    File.WriteAllText(Path.Combine(single, "Consumer.nl"), consumer)
    oneProject = NullAnalyze(single, "NullabilityOneProject")

    split := NullRoot(tag + "-two")
    NullProject(split, "NullabilityTwoProjects", "  - dll: " + typeof(Holder).Assembly.Location + "\n")
    File.WriteAllText(Path.Combine(split, "Consumer.nl"), consumer)
    twoProjects = NullAnalyze(split, "NullabilityTwoProjects")
}

func NullConsumer(body: string): string {
    return "namespace Census.Nullability.Consumer\n\nimport System\nimport System.IO\nimport Census.Nullability\n\nclass Uses {\n" + body + "}\n"
}

test "a maybe-null argument to a referenced N# signature is the NL202 the one-project program reports" {
    consumer := NullConsumer("    static func Local(node: Node): int {\n        return node.Name.Length\n    }\n\n    static func Run(holder: Holder): int {\n        total := Local(holder.Child) + Local(holder.Find())\n        total = total + Holder.Take(holder.Child) + Holder.TakeText(holder.Label)\n        total = total + Holder.TakeMaybe(holder.Child)\n        child := holder.Child\n        if child != null {\n            total = total + Local(child) + Holder.Take(child)\n        }\n        return total\n    }\n")
    oneProject := new List<CompilerError>()
    twoProjects := new List<CompilerError>()
    NullBothShapes("arguments", consumer, out oneProject, out twoProjects)

    single := NullConsumerFindings(oneProject, "NL202")
    split := NullConsumerFindings(twoProjects, "NL202")
    // A source function and a referenced method alike; the `?` parameter and the narrowed local pass.
    assert single.Count == 4, NullText(oneProject)
    joined := string.Join("\n", single)
    assert joined.Contains("Cannot pass `Node?` as argument for parameter `node` of type `Node`"), NullText(oneProject)
    assert joined.Contains("Cannot pass `string?` as argument for parameter `text` of type `string`"), NullText(oneProject)
    assert string.Join("\n", split) == string.Join("\n", single), "two projects:\n" + NullText(twoProjects) + "---- one project:\n" + NullText(oneProject)
}

test "a maybe-null referenced class value assigned or returned as not-null is the NL202 the one-project program reports" {
    consumer := NullConsumer("    static func Assign(holder: Holder): string {\n        node: Node = holder.Child\n        return node.Name\n    }\n\n    static func Pass(holder: Holder): Node {\n        return holder.Find()\n    }\n\n    static func Keep(holder: Holder): Node? {\n        maybe: Node? = holder.Child\n        return maybe\n    }\n")
    oneProject := new List<CompilerError>()
    twoProjects := new List<CompilerError>()
    NullBothShapes("assignments", consumer, out oneProject, out twoProjects)

    single := NullConsumerFindings(oneProject, "NL202")
    split := NullConsumerFindings(twoProjects, "NL202")
    assert single.Count == 2, NullText(oneProject)
    assert string.Join("\n", split) == string.Join("\n", single), "two projects:\n" + NullText(twoProjects) + "---- one project:\n" + NullText(oneProject)
}

test "a shared-framework class type and a framework signature keep the answer they always had" {
    // `Type?` into a not-null `Type`, and `string?` into `Path.GetFullPath`, are accepted today in one
    // project and in two; enforcing the framework's own annotations is a separate decision, so this
    // row fails the day either answer changes without one.
    consumer := NullConsumer("    static func TakeType(type: Type): int {\n        return type.Name.Length\n    }\n\n    static func Run(holder: Holder, maybeType: Type?): int {\n        return TakeType(maybeType) + TakeType(typeof(string).BaseType) + Path.GetFullPath(holder.Label).Length\n    }\n")
    oneProject := new List<CompilerError>()
    twoProjects := new List<CompilerError>()
    NullBothShapes("framework", consumer, out oneProject, out twoProjects)

    assert NullConsumerFindings(oneProject, "NL202").Count == 0, NullText(oneProject)
    assert NullConsumerFindings(twoProjects, "NL202").Count == 0, NullText(twoProjects)
}

// AN ASSEMBLY THAT STATES NO NULLABILITY. Written here with `PersistedAssemblyBuilder`, which emits no
// `NullableAttribute`, so its signature reads back OBLIVIOUS: it promises nothing, and a maybe-null
// argument passes exactly as it did before the rule existed.
func NullObliviousLibrary(root: string): string {
    builder := new PersistedAssemblyBuilder(new AssemblyName("NullabilityOblivious"), typeof(object).Assembly)
    module := builder.DefineDynamicModule("NullabilityOblivious")
    box := module.DefineType("Census.Oblivious.Box", TypeAttributes.Public | TypeAttributes.Class | TypeAttributes.Abstract | TypeAttributes.Sealed)
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    take := box.DefineMethod("Take", MethodAttributes.Public | MethodAttributes.Static, typeof(int), parameterTypes)
    take.DefineParameter(1, ParameterAttributes.None, "text")
    il := take.GetILGenerator()
    il.Emit(OpCodes.Ldc_I4_1)
    il.Emit(OpCodes.Ret)
    box.CreateType()
    path := Path.Combine(root, "NullabilityOblivious.dll")
    builder.Save(path)
    return path
}

test "an oblivious referenced signature accepts a maybe-null argument, as it always did" {
    root := NullRoot("oblivious")
    library := NullObliviousLibrary(root)
    consumerRoot := Path.Combine(root, "consumer")
    Directory.CreateDirectory(consumerRoot)
    NullProject(consumerRoot, "NullabilityObliviousConsumer", "  - dll: " + library + "\n  - dll: " + typeof(Holder).Assembly.Location + "\n")
    File.WriteAllText(Path.Combine(consumerRoot, "Consumer.nl"), "namespace Census.Nullability.Consumer\n\nimport Census.Nullability\nimport Census.Oblivious\n\nclass Uses {\n    static func Run(holder: Holder): int {\n        return Box.Take(holder.Label)\n    }\n}\n")
    errors := NullAnalyze(consumerRoot, "NullabilityObliviousConsumer")

    assert NullConsumerFindings(errors, "NL202").Count == 0, NullText(errors)
    assert NullConsumerFindings(errors, "NL402").Count == 0, NullText(errors)
}

// `Keys` OF A DICTIONARY CLOSED OVER A REFERENCED TYPE IS THE `IEnumerable<TKey>` ITS ARGUMENTS SPELL.
// Read off the closed CLR type, the substituted `TKey` inside `IEnumerable<TKey>` came back maybe-null
// (`IEnumerable<string?>`), and an overloaded call taking it -- `ToDictionary` has six -- found no
// applicable candidate: NL402 on `SystemsAnalyzer.nl` once Compiler.Model was carved. Over a SOURCE
// `Node` the member was always read from the definition, so this is the same answer in both shapes.
func NullIndexByName(units: IReadOnlyDictionary<string, Node>): Dictionary<string, string> {
    keySelector: Func<string, string> = name => name.ToUpperInvariant()
    valueSelector: Func<string, string> = name => name
    return Enumerable.ToDictionary<string, string, string>(units.Keys, keySelector, valueSelector, StringComparer.Ordinal)
}

test "an overloaded call takes the keys of a dictionary over a referenced type" {
    units := new Dictionary<string, Node>()
    units["alpha"] = new Node("a")
    units["beta"] = new Node("b")
    indexed := NullIndexByName(units)
    assert indexed.Count == 2
    assert indexed["ALPHA"] == "alpha"

    consumer := NullConsumer("    static func Run(units: System.Collections.Generic.IReadOnlyDictionary<string, Node>): int {\n        keySelector: Func<string, string> = name => name\n        return System.Linq.Enumerable.ToDictionary<string, string>(units.Keys, keySelector).Count\n    }\n")
    oneProject := new List<CompilerError>()
    twoProjects := new List<CompilerError>()
    NullBothShapes("keys", consumer, out oneProject, out twoProjects)
    assert NullConsumerFindings(oneProject, "NL402").Count == 0, NullText(oneProject)
    assert NullConsumerFindings(twoProjects, "NL402").Count == 0, NullText(twoProjects)
}

// A BARE REFERENCED CLASS TYPE SAYS NOT-NULL, AS ITS SOURCE DECLARATION DOES. The narrowed `out`
// value of `TryGetValue` over a dictionary of referenced `Node`s used to be left OBLIVIOUS (every
// reflected class type was), so returning it as `Node` reported NL202 in two projects and nothing in
// one; a written `Node` parameter was oblivious too, so dereferencing it could never be judged.
test "a narrowed out value of a referenced class type is not-null in two projects as in one" {
    consumer := "namespace Census.Nullability.Consumer\n\nimport System.Collections.Generic\nimport Census.Nullability\n\nclass Uses {\n" + ("    static func Found(map: Dictionary<string, Node>, key: string): Node {\n        let cached: Node? = null\n        if map.TryGetValue(key, out cached) {\n            return cached\n        }\n        return new Node(key)\n    }\n\n    static func Written(node: Node): int {\n        return node.Name.Length\n    }\n") + "}\n"
    oneProject := new List<CompilerError>()
    twoProjects := new List<CompilerError>()
    NullBothShapes("narrowing", consumer, out oneProject, out twoProjects)

    assert NullConsumerFindings(oneProject, "NL202").Count == 0, NullText(oneProject)
    assert NullConsumerFindings(twoProjects, "NL202").Count == 0, NullText(twoProjects)
    assert string.Join("\n", NullConsumerFindings(twoProjects, "NL907")) == string.Join("\n", NullConsumerFindings(oneProject, "NL907")), NullText(twoProjects)
}
