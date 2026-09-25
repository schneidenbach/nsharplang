namespace NSharpLang.LanguageServerHandlers.Tests

import System
import System.Collections.Generic
import System.IO
import NSharpLang.Compiler.CodeIntelligence

// The CLI and the editor share one owner, so the two surfaces are asserted equal
// rather than each asserted separately.
func LshCliCompletionSignatures(result: CompletionResult): List<string> {
    values := new List<string>()
    for group in result.Completions {
        items := group.Value
        index := 0
        while index < items.Count {
            item := items[index]
            values.Add(item.Name + ":" + EditorCompletionFacts.LspCompletionItemKind(item.Kind).ToString())
            index = index + 1
        }
    }
    values.Sort(StringComparer.Ordinal)
    return values
}

test "member completion answers exactly what the CLI completion query answers" {
    root := LshMemberCompletionProject()
    try {
        docs := LshNewDocs()
        types := LshNewTypes()
        uri := LshFileUri(Path.Combine(root, "Program.nl"))
        LshOpen(docs, uri, LshMemberCompletionProgramText())

        snapshot := new CodeIntelligenceService().LoadProject(root)
        engine := new CompletionEngine()

        // A cross-file user receiver, then a BCL receiver; both trailing dots.
        lines: int[] = [7, 8]
        characters: int[] = [20, 16]
        index := 0
        while index < lines.Length {
            line := lines[index]
            character := characters[index]

            cli := engine.GetCompletions(snapshot, "Program.nl", line + 1, character + 1, false)
            assert cli.Context.ToString() == "MemberAccess"

            lsp := LshCompletions(docs, types, uri, line, character)
            LshAssertSameSignatures(LshCliCompletionSignatures(cli), LshCompletionSignatures(lsp))

            // No enclosing-scope identifier, no keyword, and no accessor the filter should drop.
            assert !LshHasCompletion(lsp, "sensor")
            assert !LshHasCompletion(lsp, "label")
            assert !LshHasCompletion(lsp, "func")
            assert !LshHasCompletion(lsp, "class")
            assert !LshHasCompletionStartingWith(lsp, "get_")

            index = index + 1
        }

        user := LshCompletions(docs, types, uri, 7, 20)
        assert LshHasCompletion(user, "Name")
        assert LshHasCompletion(user, "Reading")
        assert LshHasCompletion(LshCompletions(docs, types, uri, 8, 16), "ToUpper")
    } finally {
        LshDeleteTree(root)
    }
}

test "hover answers exactly what the CLI hover query answers" {
    root := LshMemberCompletionProject()
    try {
        docs := LshNewDocs()
        types := LshNewTypes()
        uri := LshFileUri(Path.Combine(root, "Program.nl"))
        LshOpen(docs, uri, LshMemberCompletionProgramText())

        service := new CodeIntelligenceService()
        snapshot := service.LoadProject(root)

        // A BCL property on a string local, then a cross-file user record field.
        lines: int[] = [8, 7]
        characters: int[] = [16, 20]
        index := 0
        while index < lines.Length {
            line := lines[index]
            character := characters[index]

            cli := service.GetHoverInfo(snapshot, "Program.nl", line + 1, character + 1)
            assert cli != null

            lsp := LshHover(docs, types, uri, line, character)
            assert lsp != null
            markdown := LshHoverMarkdown(lsp)

            assert markdown.Contains(cli.Signature, StringComparison.Ordinal)

            declaring := cli.DeclaringType ?? cli.DefinedIn
            assert declaring != null
            assert markdown.Contains(declaring, StringComparison.Ordinal)

            index = index + 1
        }

        bclHover := LshHover(docs, types, uri, 8, 16)
        assert bclHover != null
        bcl := LshHoverMarkdown(bclHover)
        assert bcl.Contains("property Length: int { get; }", StringComparison.Ordinal)
        assert bcl.Contains("*Declaring Type:* `System.String`", StringComparison.Ordinal)
    } finally {
        LshDeleteTree(root)
    }
}
