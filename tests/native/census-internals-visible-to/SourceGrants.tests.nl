namespace Tests

import System
import System.Collections
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler


// THE GRANT AN N# PROJECT WRITES, AND WHAT IT ACTUALLY EXPOSES.
//
// `GrantedInternals.tests.nl` next door reads a grant made by a C# assembly: `LanguageServer.dll`
// carries `[assembly: InternalsVisibleTo("Tests")]` because its `.csproj` says so. This file is the
// other direction — an N# project that says `internalsVisibleTo:` in its own `project.yml`, emits
// the attribute itself, and is reached by a consumer the grant names — so the rule no longer
// depends on a C#-authored reference to exist at all.
//
// WHAT A GRANT EXPOSES FROM AN N# ASSEMBLY IS A MEASURED FACT, NOT AN ASSUMPTION, and the first
// test below is where it is measured rather than asserted from memory. N# emits every TYPE as CLR
// `public` and every FIELD as `public` — casing decides PACKAGE export, which is the compiler's own
// rule and invisible to the CLR — while a camelCase, unexported FUNCTION or METHOD is emitted as
// CLR `assembly`. Those unexported functions and methods are therefore exactly what an
// `internalsVisibleTo:` grant admits out of an N# assembly, and `website/docs/types.md` states the
// same rule for readers.
//
// EVERY ASSEMBLY HERE IS BUILT BY THE PRODUCTION PIPELINE, `MultiFileCompiler.CompileToIlAssembly`
// — the entry point `nlc build` uses — and the positive arm is then LOADED AND RUN, so the CLR
// performs its own friend check on the emitted call. A test that only compiled would not know
// whether the metadata it wrote is the metadata the runtime accepts.
func SourceGrantRoot(tag: string): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-ivt2-" + tag + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return root
}

// The helper library: one EXPORTED type with a PascalCase method and a camelCase one, one
// PACKAGE-PRIVATE type beside it, plus an exported and an unexported free function. The grant is
// written into `project.yml`, which is the whole point of the fixture.
//
// `ledgerNote` IS WHAT THE PAIR OF TYPES EXISTS FOR. A camelCase type is emitted CLR `assembly`, so
// what a grant admits out of an N# library is a TYPE as well as a method — and the `Ledger`/`ledgerNote`
// pair is how "camelCase is internal" is told apart from "everything is internal".
func SourceGrantHelperSource(): string {
    return "namespace Granting\n\nclass Ledger {\n    Seed: int\n\n    constructor(seed: int) {\n        Seed = seed\n    }\n\n    func Exported(): int => Seed * 2\n\n    func unexported(): int => Seed * 3\n}\n\nclass ledgerNote {\n    Text: string\n\n    constructor(text: string) {\n        Text = text\n    }\n\n    func Read(): string => Text\n}\n\nfunc ExportedFree(value: int): int => value + 1\n\nfunc unexportedFree(value: int): int => value + 2\n"
}

func SourceGrantHelperProject(assemblyName: string, grantedTo: string?): string {
    text := "name: " + assemblyName + "\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n"
    if grantedTo != null {
        text = text + "\ninternalsVisibleTo:\n  - " + (grantedTo ?? "") + "\n"
    }

    return text
}

// EVERY ASSEMBLY THIS FILE EMITS GETS A NAME OF ITS OWN. The blocks below load their fixtures into
// the running test process, and the CLR admits one assembly per identity per load context — so two
// fixtures sharing a name would make the second block read the FIRST block's metadata and quietly
// assert nothing. The NAMESPACE stays `Granting` in every one of them, because the consumer source
// imports it and a namespace is not an assembly name.
func SourceGrantUniqueName(prefix: string): string {
    return prefix + Guid.NewGuid().ToString("N")
}

// Emit the helper and answer WHERE it landed. The assembly name is the project's `name:`, so the
// same directory can hold the consumer beside it and the default loader finds the reference by
// simple name when the consumer is loaded.
func SourceGrantBuildHelper(root: string, assemblyName: string, grantedTo: string?): string {
    Directory.CreateDirectory(root)
    File.WriteAllText(Path.Combine(root, "project.yml"), SourceGrantHelperProject(assemblyName, grantedTo))
    File.WriteAllText(Path.Combine(root, "Ledger.nl"), SourceGrantHelperSource())

    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    compiler := new MultiFileCompiler(root, config)
    outputPath := Path.Combine(root, assemblyName + ".dll")
    result := compiler.CompileToIlAssembly(assemblyName, outputPath)

    assert result.Success, SourceGrantCodes(SourceGrantList(result.Errors))
    assert File.Exists(outputPath)
    return outputPath
}

func SourceGrantList(errors: IEnumerable<CompilerError>): List<CompilerError> {
    collected := new List<CompilerError>()
    for error in errors {
        collected.Add(error)
    }

    return collected
}

func SourceGrantCodes(errors: IReadOnlyList<CompilerError>): string {
    text := ""
    index := 0
    while index < errors.Count {
        if index > 0 {
            text = text + " | "
        }

        text = text + errors[index].DiagnosticId + " " + errors[index].Message
        index = index + 1
    }

    return text
}

func SourceGrantCount(errors: IReadOnlyList<CompilerError>, code: string): int {
    matches := 0
    index := 0
    while index < errors.Count {
        if errors[index].DiagnosticId == code {
            matches = matches + 1
        }

        index = index + 1
    }

    return matches
}

// The consumer reaches the helper's camelCase METHOD, which is the one member an N# grant admits.
func SourceGrantConsumerSource(): string {
    return "namespace Consuming\n\nimport Granting\n\nfunc ReachInternal(seed: int): int {\n    ledger := new Ledger(seed)\n    return ledger.unexported()\n}\n\nfunc ReachPublic(seed: int): int {\n    ledger := new Ledger(seed)\n    return ledger.Exported()\n}\n"
}

// Compile the consumer UNDER A GIVEN NAME against the helper. Only `name:` differs between the
// arms, so the answer is about the grant and not about a spelling.
// THE SDK'S OWN ANALYSIS-FREE PATH, which is where the emitter's refusal is the ONLY one. The
// analyzer now reports the same refusal as NL308 through the ordinary entry above; this keeps the
// emit-time backstop asserted, because a `<Project Sdk="NSharpLang.Sdk" />` build never runs
// analysis and nothing else stands between a stranger and a member the CLR refuses at load.
func SourceGrantEmitOnlyConsumer(root: string, helperPath: string, assemblyName: string): IReadOnlyList<CompilerError> {
    consumerRoot := Path.Combine(root, "emit-only-" + assemblyName)
    Directory.CreateDirectory(consumerRoot)
    File.WriteAllText(
        Path.Combine(consumerRoot, "project.yml"),
        "name: " + assemblyName + "\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n\ndependencies:\n  - dll: " + helperPath + "\n"
    )
    File.WriteAllText(Path.Combine(consumerRoot, "Consumer.nl"), SourceGrantConsumerSource())

    config := ProjectFileParser.Parse(Path.Combine(consumerRoot, "project.yml"))
    compiler := new MultiFileCompiler(consumerRoot, config)
    emitOnlyOutput := Path.Combine(consumerRoot, assemblyName + ".dll")
    result := compiler.CompileToIlAssembly(assemblyName, emitOnlyOutput, false, false)
    return SourceGrantList(result.Errors)
}

func SourceGrantCompileConsumer(root: string, helperPath: string, assemblyName: string, out outputPath: string): IReadOnlyList<CompilerError> {
    consumerRoot := Path.Combine(root, "consumer-" + assemblyName)
    Directory.CreateDirectory(consumerRoot)
    File.WriteAllText(
        Path.Combine(consumerRoot, "project.yml"),
        "name: " + assemblyName + "\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n\ndependencies:\n  - dll: " + helperPath + "\n"
    )
    File.WriteAllText(Path.Combine(consumerRoot, "Consumer.nl"), SourceGrantConsumerSource())

    config := ProjectFileParser.Parse(Path.Combine(consumerRoot, "project.yml"))
    compiler := new MultiFileCompiler(consumerRoot, config)
    outputPath = Path.Combine(Path.GetDirectoryName(helperPath) ?? consumerRoot, assemblyName + ".dll")
    result := compiler.CompileToIlAssembly(assemblyName, outputPath)
    return SourceGrantList(result.Errors)
}

func SourceGrantSequenceCount(sequence: object): int {
    values := (IList)sequence
    return values.Count
}

// How many friend rows this assembly's metadata carries for a given name. `GetCustomAttributesData`
// is the reader — the same one `InternalsVisibleToGrants` uses — because it reads METADATA and not
// a materialized attribute instance.
func SourceGrantRowsFor(assembly: Assembly, grantedTo: string): int {
    rows := 0
    attributes := assembly.GetCustomAttributesData()
    count := SourceGrantSequenceCount(attributes)
    index := 0
    while index < count {
        attribute := attributes.get_Item(index)
        if attribute.AttributeType.FullName == "System.Runtime.CompilerServices.InternalsVisibleToAttribute" {
            declared := attribute.ConstructorArguments.get_Item(0).Value as string
            if declared == grantedTo {
                rows = rows + 1
            }
        }

        index = index + 1
    }

    return rows
}

func SourceGrantTotalRows(assembly: Assembly): int {
    rows := 0
    attributes := assembly.GetCustomAttributesData()
    count := SourceGrantSequenceCount(attributes)
    index := 0
    while index < count {
        if attributes.get_Item(index).AttributeType.FullName == "System.Runtime.CompilerServices.InternalsVisibleToAttribute" {
            rows = rows + 1
        }

        index = index + 1
    }

    return rows
}

func SourceGrantInvoke(assembly: Assembly, typeName: string, methodName: string, argument: int): int {
    holder := assembly.GetType(typeName)
    assert holder != null, "the emitted consumer must declare '" + typeName + "'"
    method := holder.GetMethod(methodName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
    assert method != null, "the emitted consumer must declare '" + methodName + "'"
    arguments := new object[](1)
    arguments[0] = argument
    return (int)(method.Invoke(null, arguments) ?? 0)
}

// ── what N# emits, and therefore what a grant can expose ──────────────────────────────────────

test "an N# assembly emits everything it did not export as CLR internal — types included" {
    root := SourceGrantRoot("shape")
    helperPath := SourceGrantBuildHelper(root, SourceGrantUniqueName("GrantShape"), "Reader")
    helper := Assembly.LoadFrom(helperPath)

    ledger := helper.GetType("Granting.Ledger")
    assert ledger != null
    assert ledger.IsPublic, "a PascalCase type is exported from its package, and CLR `public` is how that is said"
    assert ledger.IsVisible

    // THE TWIN, AND THE CLAIM THIS ROW WAS STRENGTHENED TO MAKE. A camelCase type is emitted
    // `NotPublic`: another assembly cannot name it at all without a friend grant, where before the
    // casing rule stopped at the compiler and metadata said `public`.
    note := helper.GetType("Granting.ledgerNote")
    assert note != null
    assert note.IsNotPublic, "a camelCase type is NOT exported, and CLR `assembly` is how that is said"
    assert !note.IsPublic
    assert !note.IsVisible

    exported := ledger.GetMethod("Exported", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
    assert exported != null
    assert exported.IsPublic

    unexported := ledger.GetMethod("unexported", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
    assert unexported != null
    assert unexported.IsAssembly, "a camelCase method is the member an InternalsVisibleTo grant admits"
    assert !unexported.IsPublic
    assert !unexported.IsPrivate

    seed := ledger.GetField("Seed", BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance)
    assert seed != null
    assert seed.IsPublic, "N# emits fields as CLR public, so a grant exposes nothing extra at a field"
}

// ── the attribute the project file asked for ──────────────────────────────────────────────────

test "internalsVisibleTo in project.yml becomes an InternalsVisibleTo row in the emitted metadata" {
    root := SourceGrantRoot("attribute")
    granted := Assembly.LoadFrom(SourceGrantBuildHelper(root, SourceGrantUniqueName("GrantRow"), "Reader"))

    assert SourceGrantRowsFor(granted, "Reader") == 1
    assert SourceGrantTotalRows(granted) == 1
    assert SourceGrantRowsFor(granted, "Other") == 0

    // AND AN ASSEMBLY THAT DECLARES NONE CARRIES NONE. Every assembly N# emitted before this key
    // existed carried no friend row at all, and one without the key still does.
    ungranted := Assembly.LoadFrom(SourceGrantBuildHelper(SourceGrantRoot("attribute-none"), SourceGrantUniqueName("GrantNone"), null))
    assert SourceGrantTotalRows(ungranted) == 0
}

// A DISPLAY NAME IS WRITTEN WHOLE. The strong-name key after the comma is part of the name a grant
// carries; the reader narrows to the simple name in front of it, so a keyed grant still names the
// assembly and an unkeyed consumer is still its friend.
test "a grant that carries a public key is written whole and still names the simple assembly" {
    root := SourceGrantRoot("keyed")
    keyed := Assembly.LoadFrom(SourceGrantBuildHelper(root, SourceGrantUniqueName("GrantKeyed"), "\"Reader, PublicKey=00240000\""))

    assert SourceGrantRowsFor(keyed, "Reader, PublicKey=00240000") == 1
    assert InternalsVisibleToGrants.FriendSimpleName("Reader, PublicKey=00240000") == "Reader"
    assert InternalsVisibleToGrants.NamesCompilation("Reader, PublicKey=00240000", "Reader")
}

// ── the source grant, honoured by the compiler that wrote it ──────────────────────────────────

test "a consumer the N# source grant names reaches the unexported member; a stranger does not" {
    root := SourceGrantRoot("consume")
    helperPath := SourceGrantBuildHelper(root, SourceGrantUniqueName("GrantConsume"), "Reader")

    grantedOutput := ""
    granted := SourceGrantCompileConsumer(root, helperPath, "Reader", out grantedOutput)
    assert granted.Count == 0, SourceGrantCodes(granted)
    assert File.Exists(grantedOutput)

    strangerOutput := ""
    stranger := SourceGrantCompileConsumer(root, helperPath, "Stranger", out strangerOutput)
    assert stranger.Count > 0, "a project the grant does not name must not compile against the unexported member"
    // THE ANALYZER'S REFUSAL, which is what `nlc check` and `nlc build` now report first: NL308,
    // the same code and sentence a source `internal` member gets. It used to be NL103 from the
    // emitter and nothing at all from analysis.
    assert SourceGrantCount(stranger, "NL308") == 1, SourceGrantCodes(stranger)
    assert SourceGrantCodes(stranger).IndexOf("internal", StringComparison.Ordinal) >= 0, SourceGrantCodes(stranger)

    // AND THE EMIT-TIME BACKSTOP IS UNCHANGED, measured through the analysis-free path the SDK uses.
    strangerEmitOnly := SourceGrantEmitOnlyConsumer(root, helperPath, "StrangerEmitOnly")
    assert SourceGrantCount(strangerEmitOnly, "NL103") == 1, SourceGrantCodes(strangerEmitOnly)
    assert SourceGrantCodes(strangerEmitOnly).IndexOf("unexported", StringComparison.Ordinal) >= 0, SourceGrantCodes(strangerEmitOnly)

    // THE ONLY DIFFERENCE BETWEEN THE TWO ARMS IS `name:`, so the refusal is the rule and not the
    // source: the public member of the same type compiles under either name.
    assert SourceGrantCodes(stranger).IndexOf("ReachPublic", StringComparison.Ordinal) < 0, SourceGrantCodes(stranger)
}

// A SECOND CONSUMER, reaching the helper's camelCase TYPE rather than its camelCase method. It is a
// separate source because the two refusals come from different owners: a member's is the accessibility
// relation, a type's is name RESOLUTION — an unexported type of a reference is not a name a stranger
// can spell at all.
func SourceGrantTypeConsumerSource(): string {
    return "namespace Consuming\n\nimport Granting\n\nfunc ReachHiddenType(): string {\n    note := new ledgerNote(\"kept\")\n    return note.Read()\n}\n"
}

func SourceGrantCompileTypeConsumer(root: string, helperPath: string, assemblyName: string): IReadOnlyList<CompilerError> {
    consumerRoot := Path.Combine(root, "type-" + assemblyName)
    Directory.CreateDirectory(consumerRoot)
    File.WriteAllText(
        Path.Combine(consumerRoot, "project.yml"),
        "name: " + assemblyName + "\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n\ndependencies:\n  - dll: " + helperPath + "\n"
    )
    File.WriteAllText(Path.Combine(consumerRoot, "Consumer.nl"), SourceGrantTypeConsumerSource())

    config := ProjectFileParser.Parse(Path.Combine(consumerRoot, "project.yml"))
    compiler := new MultiFileCompiler(consumerRoot, config)
    // The output lands BESIDE the helper so the default loader finds the reference by simple name,
    // which is the same placement `SourceGrantCompileConsumer` uses and the reason the path is a local.
    outputPath := Path.Combine(Path.GetDirectoryName(helperPath) ?? consumerRoot, assemblyName + ".dll")
    result := compiler.CompileToIlAssembly(assemblyName, outputPath)
    return SourceGrantList(result.Errors)
}

test "a camelCase TYPE of a reference is unreachable to a stranger and reachable to a friend" {
    // THE CROSS-ASSEMBLY HALF OF THE TYPE RULE. Before a camelCase type was emitted `assembly`, this
    // stranger COMPILED — into a dll the CLR refuses at load, with no diagnostic, because metadata said
    // the type was public. The grant is the only thing that separates the two arms.
    root := SourceGrantRoot("hidden-type")
    helperPath := SourceGrantBuildHelper(root, SourceGrantUniqueName("GrantHiddenType"), "Reader")

    stranger := SourceGrantCompileTypeConsumer(root, helperPath, "Stranger")
    assert stranger.Count > 0, "a project the grant does not name must not compile against an unexported TYPE"

    granted := SourceGrantCompileTypeConsumer(root, helperPath, "Reader")
    assert granted.Count == 0, SourceGrantCodes(granted)
}

// ── and the CLR agrees, at load ───────────────────────────────────────────────────────────────

test "the friend consumer RUNS: the CLR accepts the emitted call to the granted internal member" {
    root := SourceGrantRoot("run")
    consumerName := SourceGrantUniqueName("GrantRunner")
    helperPath := SourceGrantBuildHelper(root, SourceGrantUniqueName("GrantRunHelper"), consumerName)
    Assembly.LoadFrom(helperPath)

    output := ""
    errors := SourceGrantCompileConsumer(root, helperPath, consumerName, out output)
    assert errors.Count == 0, SourceGrantCodes(errors)

    consumer := Assembly.LoadFrom(output)

    // `unexported()` is `Seed * 3` and `Exported()` is `Seed * 2`. Reaching the first one at run
    // time is what the whole feature is for: the JIT re-checks the friend grant when it compiles
    // the call, so a missing or misspelled attribute row would be a MethodAccessException here.
    assert SourceGrantInvoke(consumer, "Consuming.Program", "ReachInternal", 7) == 21
    assert SourceGrantInvoke(consumer, "Consuming.Program", "ReachPublic", 7) == 14
}
