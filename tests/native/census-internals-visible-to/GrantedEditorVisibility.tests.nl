namespace Tests

import System
import System.IO
import NSharpLang.Compiler
import NSharpLang.Compiler.CodeIntelligence
import NSharpLang.LanguageServer.Handlers


// WHAT THE EDITOR SAYS ABOUT A NAME THE FRIEND GRANT ADMITTED.
//
// Completion already offers a granting reference's internals (`GrantedCompletions.tests.nl`), so
// the developer can WRITE the member. This file is the other half of telling them the truth about
// it: hovering the member used to render exactly like a public one, which left the friend grant —
// the only reason the name resolves at all — invisible. Move the same call into a project the
// reference does not befriend and it is NL301 with nothing in the editor having hinted why.
//
// So a member whose DECLARED level is not `public` now carries that level's word beside its kind,
// through `MemberAccessibility` — the same owner whose word the refusal quotes — and the answer is
// therefore consistent with the semantic rule by construction rather than by coincidence.
//
// THE QUERIES ARE THE PRODUCTION ONES. `CodeIntelligenceService` is the surface `nlc query hover`
// and the language server both go through, so these are the answers a real editor receives.
func EditorVisibilityRoot(): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-ivt2-editor-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return root
}

// A PUBLIC ANCHOR: this only answers WHICH assembly and WHERE, so it must not also be a bet on
// some particular internal of that assembly surviving the N# ownership lanes.
func EditorVisibilityLanguageServerPath(): string {
    located := typeof(WorkspaceSymbolHandler).Assembly.Location
    if located.Length > 0 && File.Exists(located) {
        return located
    }

    throw new InvalidOperationException("The referenced LanguageServer assembly had no readable location: '" + located + "'")
}

func EditorVisibilityReferenceLines(): string {
    directory := Path.GetDirectoryName(EditorVisibilityLanguageServerPath())
    if directory == null {
        throw new InvalidOperationException("The referenced assembly had no directory.")
    }

    lines := ""
    references := Directory.GetFiles(directory, "*.dll")
    Array.Sort(references)
    index := 0
    while index < references.Length {
        lines = lines + "  - dll: " + references[index] + "\n"
        index = index + 1
    }

    return lines
}

// Line 6 is the call. `MatchesQuery` is `internal static` on the PUBLIC type
// `WorkspaceSymbolHandler`, and `Handle` beside it is public, so the same file asks both questions
// of the same reference.
func EditorVisibilitySource(): string {
    return "namespace Consumer\n\nimport NSharpLang.LanguageServer.Handlers\n\nfunc CallInternal(): bool {\n    return WorkspaceSymbolHandler.MatchesQuery(\"Alpha\", \"a\")\n}\n"
}

func EditorVisibilitySnapshot(assemblyName: string): ProjectSnapshot {
    root := EditorVisibilityRoot()
    File.WriteAllText(
        Path.Combine(root, "project.yml"),
        "name: " + assemblyName + "\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n\ndependencies:\n" + EditorVisibilityReferenceLines()
    )
    File.WriteAllText(Path.Combine(root, "Consumer.nl"), EditorVisibilitySource())

    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    service := new CodeIntelligenceService()
    return service.LoadProject(root, config)
}

func EditorVisibilityHover(assemblyName: string, line: int, column: int): HoverResult? {
    service := new CodeIntelligenceService()
    return service.GetHoverInfo(EditorVisibilitySnapshot(assemblyName), "Consumer.nl", line, column)
}

// `    return WorkspaceSymbolHandler.MatchesQuery("Alpha", "a")` — `MatchesQuery` starts at 35.
func EditorVisibilityMemberColumn(): int {
    return 35
}

test "hover on a granted internal member says it is internal, and names the declaring type" {
    hover := EditorVisibilityHover("Tests", 6, EditorVisibilityMemberColumn())

    assert hover != null, "the friend grant must make the member resolvable to hover at all"
    assert hover.Kind == "method"
    assert hover.Accessibility == "internal", "the editor must say WHY this name resolves"
    assert hover.DeclaringType == "NSharpLang.LanguageServer.Handlers.WorkspaceSymbolHandler"
}

// THE MARKER IS THE MEMBER'S DECLARED LEVEL, NOT A FLAG FOR "FRIEND". A public member of the very
// same granting reference carries nothing, so the decoration marks the members whose presence
// needs explaining and leaves every ordinary one alone.
test "hover on a public member of the same granting reference says nothing about accessibility" {
    hover := EditorVisibilityHover("Tests", 6, 12)

    assert hover != null
    assert hover.Accessibility == null
}

// CONSISTENT WITH THE SEMANTIC RULE, WHICH IS THE WHOLE POINT. The editor reads the grant from the
// SAME owner the compiler does — the snapshot carries the analyzer's live `InternalsVisibleToGrants`
// — so the answer cannot drift: where the rule says this compilation is not a friend, the editor
// must not present the member as an available internal one.
test "the editor's answer follows the grant, under the granted name and under a stranger's" {
    friend := EditorVisibilitySnapshot("Tests")
    friendGrants := friend.FriendGrants
    assert friendGrants != null
    assert friendGrants.SameAssemblyOrFriend(typeof(WorkspaceSymbolHandler)), "the fixture's grant must be real"

    stranger := EditorVisibilitySnapshot("NotAFriend")
    strangerGrants := stranger.FriendGrants
    assert strangerGrants != null
    assert !strangerGrants.SameAssemblyOrFriend(typeof(WorkspaceSymbolHandler))

    service := new CodeIntelligenceService()
    hover := service.GetHoverInfo(stranger, "Consumer.nl", 6, EditorVisibilityMemberColumn())
    assert hover == null || hover.Accessibility == null, "a stranger must not be told the member is an available internal"
}

// THE TWO SURFACES AGREE, because one owner computes the word: the JSON envelope the CLI prints
// and the markdown the language server renders both read `HoverResult.Accessibility`.
test "the CLI envelope and the editor markdown both carry the internal marker" {
    hover := EditorVisibilityHover("Tests", 6, EditorVisibilityMemberColumn())
    assert hover != null

    json := OutputFormatterJsonKernels.HoverToJson(hover, "Consumer.nl", 6, EditorVisibilityMemberColumn())
    assert json.IndexOf("\"accessibility\": \"internal\"", StringComparison.Ordinal) >= 0, json

    markdown := EditorHoverFacts.ProjectHoverMarkdown(hover)
    assert markdown.IndexOf("*Accessibility:* `internal`", StringComparison.Ordinal) >= 0, markdown

    text := OutputFormatterTextBuilders.HoverToText(hover, "Consumer.nl", 6, EditorVisibilityMemberColumn())
    assert text.IndexOf("Access:     internal", StringComparison.Ordinal) >= 0, text
}
