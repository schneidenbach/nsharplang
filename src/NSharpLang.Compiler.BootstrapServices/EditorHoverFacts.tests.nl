namespace NSharpLang.Compiler.CodeIntelligence

import System
import NSharpLang.Compiler


// CONTRACTS FOR THE EDITOR'S HALF OF A HOVER ANSWER. These strings are what the VS Code suite reads
// back out of a hover, so they are a CONTRACT with the editor and not a style choice.

test "a keyword and a primitive answer for themselves, and nothing else does" {
    assert EditorHoverFacts.KeywordOrPrimitiveMarkdown("func") == "**func** *(keyword)*"
    assert EditorHoverFacts.KeywordOrPrimitiveMarkdown("match") == "**match** *(keyword)*"
    assert EditorHoverFacts.KeywordOrPrimitiveMarkdown("int") == "**int** *(primitive type)*"
    assert EditorHoverFacts.KeywordOrPrimitiveMarkdown("string") == "**string** *(primitive type)*"
    assert EditorHoverFacts.KeywordOrPrimitiveMarkdown("forecast") == null
    assert EditorHoverFacts.KeywordOrPrimitiveMarkdown("") == null
}

test "the project hover renders the signature and OMITS every section it has nothing for" {
    markdown := EditorHoverFacts.ProjectHoverMarkdown(new HoverResult("field Count: int", null, null, "field"))

    assert markdown.Contains("```nsharp", StringComparison.Ordinal)
    assert markdown.Contains("field Count: int", StringComparison.Ordinal)
    assert !markdown.Contains("*Defined in:*", StringComparison.Ordinal)
    assert !markdown.Contains("*Declaring Type:*", StringComparison.Ordinal)
}

test "a metadata member shows its declaring type where a source symbol shows its file — D2's missing line" {
    reflected := EditorHoverFacts.ProjectHoverMarkdown(new HoverResult("method ToUpper: string ToUpper()", null, null, "method", "System.String"))
    assert reflected.Contains("*Declaring Type:* `System.String`", StringComparison.Ordinal)
    assert !reflected.Contains("*Defined in:*", StringComparison.Ordinal)

    declared := EditorHoverFacts.ProjectHoverMarkdown(new HoverResult("field Count: int", "The count.", "Models.nl", "field"))
    assert declared.Contains("*Defined in:* `Models.nl`", StringComparison.Ordinal)
    assert declared.Contains("The count.", StringComparison.Ordinal)
    assert !declared.Contains("*Declaring Type:*", StringComparison.Ordinal)
}

test "a variable with no resolvable system type is the short form, and with one it carries both lines" {
    short := EditorHoverFacts.VariableMarkdown("count", "int", null, null)
    assert short == "**(variable)** `count`\n\n```nsharp\ncount: int\n```"

    full := EditorHoverFacts.VariableMarkdown("items", "List<int>", "System.Collections.Generic", "System.Private.CoreLib")
    assert full.Contains("*Namespace:* `System.Collections.Generic`", StringComparison.Ordinal)
    assert full.Contains("*Assembly:* `System.Private.CoreLib`", StringComparison.Ordinal)
}

test "a declaration hover names the shape it is, and anything unrecognised is `type` rather than a guess" {
    // A `SimpleTypeInfo` is none of the six declaration shapes, so it takes the honest catch-all
    // rather than being guessed into one of them. The format string is pinned on the same value.
    assert EditorHoverFacts.TypeDeclarationKindWord(new SimpleTypeInfo("int")) == "type"
    assert EditorHoverFacts.TypeDeclarationMarkdown("Widget", new SimpleTypeInfo("int")) == "**Widget** *(type)*\n\n```nsharp\ntype Widget\n```"
}

test "the highlighted range starts at the word, and falls back to the cursor when the line does not hold it" {
    assert EditorHoverFacts.WordRangeStartColumn("    upper := summary.ToUpper()", 25, "ToUpper") == 21
    assert EditorHoverFacts.WordRangeStartColumn("    let x = 1", 8, "missing") == 8
}
