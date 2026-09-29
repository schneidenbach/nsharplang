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
func NullProject(root: string, name: string, extraDependencies: string, enforceReferencedNullability: bool = false) {
    dependencies := extraDependencies.Length == 0 ? "" : "\ndependencies:\n" + extraDependencies
    language := ""
    if enforceReferencedNullability {
        language = "\nlanguage:\n  enforceReferencedNullability: true\n"
    }

    File.WriteAllText(Path.Combine(root, "project.yml"), "name: " + name + "\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n" + dependencies + language)
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

func NullConsumerErrors(errors: List<CompilerError>, code: string): List<CompilerError> {
    findings := new List<CompilerError>()
    for error in errors {
        fileName := error.FileName ?? ""
        if error.DiagnosticId == code && fileName.EndsWith("Consumer.nl", StringComparison.Ordinal) {
            findings.Add(error)
        }
    }

    return findings
}

// Source declarations and the same emitted metadata keep the same diagnostic core. A reflected
// reference adds the owning .NET member and assembly to NL202, which has no such metadata context
// when the declaration is in the same compilation.
func NullFindingsWithoutMetadataContext(errors: List<CompilerError>, code: string): List<string> {
    findings := NullConsumerFindings(errors, code)
    index := 0
    while index < findings.Count {
        contextStart := findings[index].IndexOf(". The .NET member `", StringComparison.Ordinal)
        if contextStart >= 0 {
            findings[index] = findings[index].Substring(0, contextStart)
        }
        index = index + 1
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

func NullOriginHopConsumer(runBody: string): string {
    return "namespace Census.FrameworkNullability.Consumer\n\nimport System\nimport System.Collections.Generic\nimport System.Diagnostics\nimport System.Linq\n\nclass Uses {\n    static func TakeType(value: Type): int {\n        return value.Name.Length\n    }\n\n    static func TakeText(value: string): int {\n        return value.Length\n    }\n\n    static func FromBase(): Type? {\n        return typeof(string).BaseType\n    }\n\n    static func FromConditional(chooseLeft: bool): Type? {\n        return chooseLeft ? typeof(string).BaseType : typeof(int).BaseType\n    }\n\n    static func FromCoalesce(chooseLeft: bool): Type? {\n        return (chooseLeft ? typeof(string).BaseType : typeof(int).BaseType) ?? typeof(object).BaseType\n    }\n\n    static func FromGeneric(types: IEnumerable<Type>): Type? {\n        return Enumerable.FirstOrDefault<Type>(types)\n    }\n\n    static func FromElement(info: ProcessStartInfo): string? {\n        return info.Environment[\"N\"]\n    }\n\n    static func Run(info: ProcessStartInfo, types: IEnumerable<Type>): int {\n        " + runBody + "\n    }\n}\n"
}

func NullOriginHopDiagnostics(errors: List<CompilerError>): List<CompilerError> {
    diagnostics := new List<CompilerError>()
    for error in errors {
        fileName := error.FileName ?? ""
        if fileName.EndsWith("Consumer.nl", StringComparison.Ordinal) && (error.DiagnosticId == "NL202" || error.DiagnosticId == "NL905" || error.DiagnosticId == "NL402") {
            diagnostics.Add(error)
        }
    }

    return diagnostics
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

    single := NullFindingsWithoutMetadataContext(oneProject, "NL202")
    split := NullFindingsWithoutMetadataContext(twoProjects, "NL202")
    // A source function and a referenced method alike; the `?` parameter and the narrowed local pass.
    assert single.Count == 4, NullText(oneProject)
    joined := string.Join("\n", single)
    assert joined.Contains("Cannot pass `Node?` as argument for parameter `node` of type `Node`"), NullText(oneProject)
    assert joined.Contains("Cannot pass `string?` as argument for parameter `text` of type `string`"), NullText(oneProject)
    assert string.Join("\n", split) == string.Join("\n", single), "two projects:\n" + NullText(twoProjects) + "---- one project:\n" + NullText(oneProject)
}

test "AllowNull and DisallowNull source and reflection flow facts share one owner" {
    consumer := NullConsumer("    static func Run(maybeText: string?): int {\n        allowed := Holder.TakeAllowed(maybeText)\n        disallowed := Holder.TakeDisallowed(maybeText)\n        return allowed + disallowed\n    }\n")
    root := NullRoot("source-flow-attributes")
    NullProject(root, "SourceFlowAttributes", "")
    File.WriteAllText(Path.Combine(root, "Holder.nl"), NullLibrarySource())
    File.WriteAllText(Path.Combine(root, "Consumer.nl"), consumer)
    errors := NullAnalyze(root, "SourceFlowAttributes")

    findings := NullConsumerFindings(errors, "NL202")
    assert findings.Count == 1, NullText(errors)
}

test "MemberNotNull and MemberNotNullWhen source attributes narrow their named members" {
    root := NullRoot("source-member-postconditions")
    consumer := NullConsumer("    static func Run(holder: Holder): int {\n        holder.EnsureReady()\n        total := holder.Ready.Length\n        if holder.TryEnsureReady() {\n            total = total + holder.Ready.Length\n        }\n        return total\n    }\n")
    NullProject(root, "SourceMemberPostconditions", "")
    File.WriteAllText(Path.Combine(root, "Holder.nl"), NullLibrarySource())
    File.WriteAllText(Path.Combine(root, "Consumer.nl"), consumer)
    errors := NullAnalyze(root, "SourceMemberPostconditions")

    assert NullConsumerFindings(errors, "NL905").Count == 0, NullText(errors)
}

test "BCL AllowNull and DisallowNull flow attributes affect metadata checks only with the switch" {
    root := NullRoot("framework-flow")
    consumer := "namespace Census.FrameworkNullability.Consumer\n\nimport System.Collections.Generic\nimport System.IO\n\nclass Uses {\n    static func Run(maybeText: string?): int {\n        writer: TextWriter = Console.Out\n        writer.NewLine = maybeText\n        comparer: IEqualityComparer<string> = EqualityComparer<string>.Default\n        return comparer.GetHashCode(maybeText)\n    }\n}\n"

    offRoot := Path.Combine(root, "off")
    Directory.CreateDirectory(offRoot)
    NullProject(offRoot, "FrameworkFlowOff", "")
    File.WriteAllText(Path.Combine(offRoot, "Consumer.nl"), consumer)
    off := NullAnalyze(offRoot, "FrameworkFlowOff")
    offFindings := NullConsumerFindings(off, "NL202")
    assert offFindings.Count == 1, NullText(off)

    strictRoot := Path.Combine(root, "on")
    Directory.CreateDirectory(strictRoot)
    NullProject(strictRoot, "FrameworkFlowOn", "", true)
    File.WriteAllText(Path.Combine(strictRoot, "Consumer.nl"), consumer)
    on := NullAnalyze(strictRoot, "FrameworkFlowOn")
    findings := NullConsumerFindings(on, "NL202")
    assert findings.Count == 1, NullText(on)
    assert findings[0].Contains("GetHashCode"), NullText(on)
}

test "nullable generic arguments on a BCL property reach its indexer value" {
    root := NullRoot("framework-nested-generic")
    consumer := "namespace Census.FrameworkNullability.Consumer\n\nimport System.Diagnostics\n\nclass Uses {\n    static func Run(info: ProcessStartInfo, maybeValue: string?): int {\n        info.Environment[\"N\"] = maybeValue\n        value := info.Environment[\"N\"]\n        if value != null {\n            return value.Length\n        }\n        return 0\n    }\n}\n"

    offRoot := Path.Combine(root, "off")
    Directory.CreateDirectory(offRoot)
    NullProject(offRoot, "FrameworkNestedGenericOff", "")
    File.WriteAllText(Path.Combine(offRoot, "Consumer.nl"), consumer)
    off := NullAnalyze(offRoot, "FrameworkNestedGenericOff")
    assert NullConsumerFindings(off, "NL202").Count == 0, NullText(off)
    assert NullConsumerFindings(off, "NL905").Count == 0, NullText(off)

    strictRoot := Path.Combine(root, "on")
    Directory.CreateDirectory(strictRoot)
    NullProject(strictRoot, "FrameworkNestedGenericOn", "", true)
    File.WriteAllText(Path.Combine(strictRoot, "Consumer.nl"), consumer)
    on := NullAnalyze(strictRoot, "FrameworkNestedGenericOn")
    assert NullConsumerFindings(on, "NL202").Count == 0, NullText(on)
    assert NullConsumerFindings(on, "NL905").Count == 0, NullText(on)
}

test "a maybe-null referenced class value assigned or returned as not-null is the NL202 the one-project program reports" {
    consumer := NullConsumer("    static func Assign(holder: Holder): string {\n        node: Node = holder.Child\n        return node.Name\n    }\n\n    static func Pass(holder: Holder): Node {\n        return holder.Find()\n    }\n\n    static func Keep(holder: Holder): Node? {\n        maybe: Node? = holder.Child\n        return maybe\n    }\n")
    oneProject := new List<CompilerError>()
    twoProjects := new List<CompilerError>()
    NullBothShapes("assignments", consumer, out oneProject, out twoProjects)

    single := NullFindingsWithoutMetadataContext(oneProject, "NL202")
    split := NullFindingsWithoutMetadataContext(twoProjects, "NL202")
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

test "referenced framework nullable members and parameters are errors only with the temporary switch" {
    consumerRoot := NullRoot("framework-strict")
    consumer := "namespace Census.Nullability.Consumer\n\nimport System\n\nclass Uses {\n    static func Run(maybeText: string?): int {\n        type: Type = typeof(string).BaseType\n        return \"x\".IndexOf(maybeText)\n    }\n\n    static func DereferenceBaseType(): int {\n        return typeof(string).BaseType.Name.Length\n    }\n}\n"

    NullProject(consumerRoot, "FrameworkNullabilityOff", "")
    File.WriteAllText(Path.Combine(consumerRoot, "Consumer.nl"), consumer)
    off := NullAnalyze(consumerRoot, "FrameworkNullabilityOff")
    assert NullConsumerFindings(off, "NL202").Count == 0, NullText(off)

    strictRoot := NullRoot("framework-strict-on")
    NullProject(strictRoot, "FrameworkNullabilityOn", "", true)
    File.WriteAllText(Path.Combine(strictRoot, "Consumer.nl"), consumer)
    on := NullAnalyze(strictRoot, "FrameworkNullabilityOn")
    strictFindings := NullConsumerFindings(on, "NL202")
    assert strictFindings.Count >= 2, NullText(on)
    rendered := string.Join("\n", strictFindings)
    assert rendered.Contains("BaseType"), NullText(on)
    assert rendered.Contains("IndexOf"), NullText(on)
    assert rendered.Contains("null"), NullText(on)
    assert rendered.Contains("annotated"), NullText(on)
    assert rendered.Contains("does not accept null"), NullText(on)

    nullAccesses := NullConsumerErrors(on, "NL905")
    assert nullAccesses.Count == 1, NullText(on)
    assert nullAccesses[0].Message.Contains("System.Type.BaseType"), NullText(on)
    assert nullAccesses[0].Message.Contains("annotated"), NullText(on)
    nullSuggestion := nullAccesses[0].Suggestion ?? ""
    assert nullSuggestion.Contains("if ") && nullSuggestion.Contains("must "), NullText(on)

    diagnostics := NullConsumerErrors(on, "NL202")
    sawMemberSuggestion := false
    sawParameterSuggestion := false
    for diagnostic in diagnostics {
        suggestion := diagnostic.Suggestion ?? ""
        if diagnostic.Message.Contains("BaseType") {
            sawMemberSuggestion = suggestion.Contains("if ") && suggestion.Contains("must ")
        }
        if diagnostic.Message.Contains("IndexOf") {
            sawParameterSuggestion = suggestion.Contains("if ") && suggestion.Contains("must ")
        }
    }
    assert sawMemberSuggestion, NullText(on)
    assert sawParameterSuggestion, NullText(on)
}

test "referenced nullability origins survive locals and callable returns" {
    root := NullRoot("framework-origin-local-return")
    NullProject(root, "FrameworkOriginLocalReturn", "", true)
    File.WriteAllText(Path.Combine(root, "Consumer.nl"), NullOriginHopConsumer("local: Type? = typeof(string).BaseType\n        return TakeType(local) + TakeType(FromBase())"))
    errors := NullAnalyze(root, "FrameworkOriginLocalReturn")

    diagnostics := NullOriginHopDiagnostics(errors)
    for error in diagnostics {
        assert error.Message.Contains("The .NET member `"), NullText(errors)
        assert error.Suggestion != null && error.Suggestion.Length > 0, NullText(errors)
    }
    assert diagnostics.Count >= 2, NullText(errors)
    assert NullText(errors).Contains("System.Type.BaseType"), NullText(errors)
}

test "referenced nullability origins survive conditional and coalescing operands" {
    root := NullRoot("framework-origin-joins")
    NullProject(root, "FrameworkOriginJoins", "", true)
    File.WriteAllText(Path.Combine(root, "Consumer.nl"), NullOriginHopConsumer("return TakeType(FromConditional(true)) + TakeType(FromCoalesce(true))"))
    errors := NullAnalyze(root, "FrameworkOriginJoins")

    diagnostics := NullOriginHopDiagnostics(errors)
    for error in diagnostics {
        assert error.Message.Contains("The .NET member `"), NullText(errors)
        assert error.Suggestion != null && error.Suggestion.Length > 0, NullText(errors)
    }
    assert diagnostics.Count >= 2, NullText(errors)
    assert NullText(errors).Contains("System.Type.BaseType"), NullText(errors)
}

test "referenced nullability origins survive generic substitution" {
    root := NullRoot("framework-origin-generic")
    NullProject(root, "FrameworkOriginGeneric", "", true)
    File.WriteAllText(Path.Combine(root, "Consumer.nl"), NullOriginHopConsumer("return TakeType(FromGeneric(types))"))
    errors := NullAnalyze(root, "FrameworkOriginGeneric")

    diagnostics := NullOriginHopDiagnostics(errors)
    for error in diagnostics {
        assert error.Message.Contains("The .NET member `"), NullText(errors)
        assert error.Suggestion != null && error.Suggestion.Length > 0, NullText(errors)
    }
    assert diagnostics.Count >= 1, NullText(errors)
    assert NullText(errors).Contains("System.Linq.Enumerable.FirstOrDefault"), NullText(errors)
}

test "referenced nullability origins survive collection element reads" {
    root := NullRoot("framework-origin-collection")
    NullProject(root, "FrameworkOriginCollection", "", true)
    File.WriteAllText(Path.Combine(root, "Consumer.nl"), NullOriginHopConsumer("return TakeText(FromElement(info))"))
    errors := NullAnalyze(root, "FrameworkOriginCollection")

    diagnostics := NullOriginHopDiagnostics(errors)
    for error in diagnostics {
        assert error.Message.Contains("The .NET member `"), NullText(errors)
        assert error.Suggestion != null && error.Suggestion.Length > 0, NullText(errors)
    }
    assert diagnostics.Count >= 1, NullText(errors)
    assert NullText(errors).Contains("ProcessStartInfo.Environment"), NullText(errors)
    assert NullText(errors).Contains("IDictionary`2.Item") || NullText(errors).Contains("get_Item"), NullText(errors)
}

test "BCL nullable arguments survive overload selection and report NL202 for outer and nested annotations" {
    root := NullRoot("framework-nullable-overload")
    consumer := "namespace Census.FrameworkNullability.Consumer\n\nimport System\nimport System.Collections.Generic\nimport System.Diagnostics\n\nclass Uses {\n    static func TakeType(value: Type): int {\n        return value.Name.Length\n    }\n\n    static func TakeEnvironment(value: IDictionary<string, string>): int {\n        return value.Count\n    }\n\n    static func Run(info: ProcessStartInfo): int {\n        return TakeType(typeof(string).GetElementType()) + TakeEnvironment(info.Environment)\n    }\n}\n"

    offRoot := Path.Combine(root, "off")
    Directory.CreateDirectory(offRoot)
    NullProject(offRoot, "FrameworkNullableOverloadOff", "")
    File.WriteAllText(Path.Combine(offRoot, "Consumer.nl"), consumer)
    off := NullAnalyze(offRoot, "FrameworkNullableOverloadOff")
    assert NullConsumerFindings(off, "NL202").Count == 0, NullText(off)
    assert NullConsumerFindings(off, "NL402").Count == 0, NullText(off)

    strictRoot := Path.Combine(root, "on")
    Directory.CreateDirectory(strictRoot)
    NullProject(strictRoot, "FrameworkNullableOverloadOn", "", true)
    File.WriteAllText(Path.Combine(strictRoot, "Consumer.nl"), consumer)
    on := NullAnalyze(strictRoot, "FrameworkNullableOverloadOn")
    findings := NullConsumerFindings(on, "NL202")
    assert findings.Count == 2, NullText(on)
    assert NullConsumerFindings(on, "NL402").Count == 0, NullText(on)
    rendered := string.Join("\n", findings)
    assert rendered.Contains("System.Type.GetElementType"), NullText(on)
    assert rendered.Contains("ProcessStartInfo.Environment"), NullText(on)
    assert rendered.Contains("annotated to return"), NullText(on)
    for diagnostic in NullConsumerErrors(on, "NL202") {
        suggestion := diagnostic.Suggestion ?? ""
        assert suggestion.Contains("if ") && suggestion.Contains("must "), NullText(on)
    }
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

// AN `out` ARGUMENT FLOWS OUT. The callee writes the variable before it returns and never reads what was
// there, so a maybe-null local handed to a not-null `out Node` is exactly right -- the call is what fills
// it, and the true branch reads a `Node`. The same declaration in source has always said so; a
// referenced one was checked as if the argument flowed IN and reported NL202 (the Emit carve routed
// around it by declaring such locals with the parameter's own type).
test "an out argument to a referenced N# method is written by the call, in two projects as in one" {
    consumer := NullConsumer("    static func Static(key: string): string {\n        let found: Node? = null\n        if Holder.TryFind(key, out found) {\n            return found.Name\n        }\n        return \"\"\n    }\n\n    static func Instance(holder: Holder, key: string): string {\n        let found: Node? = null\n        if holder.TryFindHere(key, out found) {\n            return found.Name\n        }\n        return \"\"\n    }\n\n    static func Declared(key: string): int {\n        let found: Node\n        Holder.TryFind(key, out found)\n        return found.Name.Length\n    }\n\n    static func Maybe(key: string): int {\n        let found: Node = new Node(key)\n        Holder.TryFindMaybe(key, out found)\n        return found.Name.Length\n    }\n\n    static func Overloaded(key: int): string {\n        let found: Node? = null\n        if Holder.TryFind(key, out found) {\n            return found.Name\n        }\n        return \"\"\n    }\n")
    oneProject := new List<CompilerError>()
    twoProjects := new List<CompilerError>()
    NullBothShapes("out", consumer, out oneProject, out twoProjects)

    assert NullConsumerFindings(oneProject, "NL202").Count == 0, NullText(oneProject)
    assert NullConsumerFindings(twoProjects, "NL202").Count == 0, NullText(twoProjects)
    assert NullConsumerFindings(twoProjects, "NL402").Count == 0, NullText(twoProjects)
    // What the call WROTE is what the flow reads: a `Node?` out parameter leaves the variable maybe-null
    // whatever it held before, in both shapes, and a `Node` one leaves it not-null.
    single := NullConsumerFindings(oneProject, "NL905")
    assert single.Count == 1, NullText(oneProject)
    assert single[0].StartsWith("33:", StringComparison.Ordinal), single[0]
    assert string.Join("\n", NullConsumerFindings(twoProjects, "NL905")) == string.Join("\n", single), "two projects:\n" + NullText(twoProjects) + "---- one project:\n" + NullText(oneProject)
}

test "a narrowed short-circuit right operand keeps a referenced out postcondition in both project shapes" {
    consumer := NullConsumer("    static func Probe(key: string, other: Node?): string {\n        let picked: Node? = null\n        if other != null && Holder.TryFind(key, out picked) {\n            return Holder.Take(picked).ToString()\n        }\n        return \"\"\n    }\n")
    oneProject := new List<CompilerError>()
    twoProjects := new List<CompilerError>()
    NullBothShapes("short-circuit-out", consumer, out oneProject, out twoProjects)

    assert NullConsumerFindings(oneProject, "NL202").Count == 0, NullText(oneProject)
    assert NullConsumerFindings(twoProjects, "NL202").Count == 0, NullText(twoProjects)
    assert NullConsumerFindings(twoProjects, "NL905").Count == 0, NullText(twoProjects)
}

// A `ref` ARGUMENT FLOWS BOTH WAYS, so its annotation must match in both directions, and an `in` argument
// flows in: it binds a referenced `in` parameter bare or spelled, as the same declaration in source does,
// and a maybe-null one is refused as a by-value argument would be.
test "a ref argument matches both ways and an in argument binds, in two projects as in one" {
    consumer := NullConsumer("    static func RefMaybe(): int {\n        let held: Node? = null\n        Holder.Replace(ref held)\n        return 0\n    }\n\n    static func RefNotNull(): int {\n        let held: Node = new Node(\"h\")\n        Holder.ReplaceMaybe(ref held)\n        return held.Name.Length\n    }\n\n    static func RefExact(node: Node, maybe: Node?): int {\n        held := node\n        Holder.Replace(ref held)\n        other := maybe\n        Holder.ReplaceMaybe(ref other)\n        return held.Name.Length\n    }\n\n    static func In(node: Node, maybe: Node?): int {\n        return Holder.Peek(node) + Holder.Peek(in node) + Holder.Peek(in maybe)\n    }\n")
    oneProject := new List<CompilerError>()
    twoProjects := new List<CompilerError>()
    NullBothShapes("ref-in", consumer, out oneProject, out twoProjects)

    single := NullFindingsWithoutMetadataContext(oneProject, "NL202")
    split := NullFindingsWithoutMetadataContext(twoProjects, "NL202")
    assert single.Count == 3, NullText(oneProject)
    joined := string.Join("\n", single)
    assert joined.Contains("Cannot pass `&Node?` as argument for parameter `node` of type `&Node`"), joined
    assert joined.Contains("Cannot pass `&Node` as argument for parameter `node` of type `&Node?`"), joined
    assert joined.Contains("Cannot pass `Node?` as argument for parameter `node` of type `Node`"), joined
    assert string.Join("\n", split) == joined, "two projects:\n" + NullText(twoProjects) + "---- one project:\n" + NullText(oneProject)
    assert NullConsumerFindings(twoProjects, "NL402").Count == 0, NullText(twoProjects)
    assert NullConsumerFindings(oneProject, "NL402").Count == 0, NullText(oneProject)
}

// THE SAME THREE DIRECTIONS, COMPILED AND RUN: this project references the library's built assembly, so
// every call below is a referenced call, analysed and emitted by the compiler under test.
func NullFoundName(key: string): string {
    let found: Node? = null
    if Holder.TryFind(key, out found) {
        return found.Name
    }
    return "none"
}

func NullReplaced(name: string): string {
    held := new Node(name)
    Holder.Replace(ref held)
    return held.Name
}

func NullPeeked(name: string): int {
    node := new Node(name)
    return Holder.Peek(node) + Holder.Peek(in node)
}

test "a referenced out, ref and in call compiles and runs" {
    assert NullFoundName("key") == "key"
    assert NullFoundName("") == "none"
    assert NullReplaced("n") == "n!"
    assert NullPeeked("abc") == 6
}
