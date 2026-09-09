namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic


// CONTRACTS FOR THE EDITOR'S HALF OF A COMPLETION ANSWER. The numbers below are the Language
// Server Protocol's `CompletionItemKind` values, so these assertions are pinning an ECOSYSTEM FACT
// against drift, exactly as the JSON-RPC error-code contracts do — a change here is a protocol
// violation, not a preference.
func EcfItem(name: string, kind: string, itemType: string?, parameters: string?): CompletionItem {
    return new CompletionItem(name, kind, itemType, parameters, null, false)
}

test "every completion kind lands in the protocol slot the specification fixes" {
    assert EditorCompletionFacts.LspCompletionItemKind("method") == 2
    assert EditorCompletionFacts.LspCompletionItemKind("function") == 3
    assert EditorCompletionFacts.LspCompletionItemKind("field") == 5
    assert EditorCompletionFacts.LspCompletionItemKind("variable") == 6
    assert EditorCompletionFacts.LspCompletionItemKind("class") == 7
    assert EditorCompletionFacts.LspCompletionItemKind("interface") == 8
    assert EditorCompletionFacts.LspCompletionItemKind("property") == 10
    assert EditorCompletionFacts.LspCompletionItemKind("enum") == 13
    assert EditorCompletionFacts.LspCompletionItemKind("keyword") == 14
    assert EditorCompletionFacts.LspCompletionItemKind("struct") == 22
}

test "a record draws as a class and a union as an enum, because that is what each one is" {
    assert EditorCompletionFacts.LspCompletionItemKind("record") == EditorCompletionFacts.LspCompletionItemKind("class")
    assert EditorCompletionFacts.LspCompletionItemKind("union") == EditorCompletionFacts.LspCompletionItemKind("enum")
}

test "the three vocabulary kinds share the keyword slot" {
    assert EditorCompletionFacts.LspCompletionItemKind("keyword") == 14
    assert EditorCompletionFacts.LspCompletionItemKind("modifier") == 14
    assert EditorCompletionFacts.LspCompletionItemKind("primitive") == 14
}

test "a kind this table has never been taught answers Text rather than guessing" {
    assert EditorCompletionFacts.LspCompletionItemKind("newtype") == 1
    assert EditorCompletionFacts.LspCompletionItemKind("") == 1
}

test "the detail is the signature: parameters, then type" {
    method := EcfItem("Describe", "method", "string", "(prefix: string)")
    assert EditorCompletionFacts.MemberDetailText(method) == "(prefix: string): string"
}

test "a member with only a type shows the type alone, with no stray separator" {
    field := EcfItem("Count", "field", "int", null)
    assert EditorCompletionFacts.MemberDetailText(field) == "int"
}

test "a member with only parameters shows them alone" {
    action := EcfItem("Run", "method", null, "(times: int)")
    assert EditorCompletionFacts.MemberDetailText(action) == "(times: int)"
}

test "a member carrying neither falls back to its kind rather than an empty column" {
    bare := EcfItem("Red", "field", null, null)
    assert EditorCompletionFacts.MemberDetailText(bare) == "field"
}

test "the sort key pads to ten digits so it compares the way it counts" {
    assert EditorCompletionFacts.MemberSortText(0) == "0000000000"
    assert EditorCompletionFacts.MemberSortText(7) == "0000000007"
    assert EditorCompletionFacts.MemberSortText(42) == "0000000042"
    assert EditorCompletionFacts.MemberSortText(1234) == "0000001234"
}

test "THE PAD IS THE POINT: ten sorts after nine as a string only because it is padded" {
    nine := EditorCompletionFacts.MemberSortText(9)
    ten := EditorCompletionFacts.MemberSortText(10)

    assert String.Compare(nine, ten, StringComparison.Ordinal) < 0

    // Without the pad this is the comparison that would have been made, and it is backwards.
    assert String.Compare("9", "10", StringComparison.Ordinal) > 0
}

test "NO RANK CAN OVERFLOW THE PAD, so the ordering never degrades at the tail" {
    // A four-wide pad was the first shape of this function and it was WRONG: `10000` rendered as
    // "10000" sorts BEFORE "9999", reversing the tail of any list longer than ten thousand items.
    // Ten digits is `int.MaxValue`'s own width, so the failure has no representable input.
    assert EditorCompletionFacts.MemberSortText(2147483647).Length == 10
    assert String.Compare(EditorCompletionFacts.MemberSortText(9999), EditorCompletionFacts.MemberSortText(10000), StringComparison.Ordinal) < 0
    assert String.Compare(EditorCompletionFacts.MemberSortText(10000), EditorCompletionFacts.MemberSortText(2147483647), StringComparison.Ordinal) < 0
}

test "the collapsed row says how many declarations it stands for" {
    single := new CompletionItem("Trim", "method", "string", "()", null, false)
    assert EditorCompletionFacts.OverloadSuffix(single) == ""
    assert EditorCompletionFacts.MemberDetailText(single) == "(): string"

    pair := new CompletionItem("ToUpper", "method", "string", "()", null, false, 2)
    assert EditorCompletionFacts.OverloadSuffix(pair) == " (+1 overload)"
    assert EditorCompletionFacts.MemberDetailText(pair) == "(): string (+1 overload)"

    // ELEVEN `Split` DECLARATIONS, ONE ROW: the count is the whole reason the row can afford to be
    // one, and hover's own wording is reused so the two surfaces say it the same way.
    many := new CompletionItem("Split", "method", "string[]", "(separator char)", null, false, 11)
    assert EditorCompletionFacts.OverloadSuffix(many) == " (+10 overloads)"
    assert EditorCompletionFacts.MemberDetailText(many) == "(separator char): string[] (+10 overloads)"

    // The three thinner details carry it too, including the one that falls back to the kind word.
    assert EditorCompletionFacts.MemberDetailText(new CompletionItem("Split", "method", null, "(x int)", null, false, 3)) == "(x int) (+2 overloads)"
    assert EditorCompletionFacts.MemberDetailText(new CompletionItem("Length", "property", "int", null, null, false, 1)) == "int"
    assert EditorCompletionFacts.MemberDetailText(new CompletionItem("Odd", "union", null, null, null, false, 4)) == "union (+3 overloads)"
}
