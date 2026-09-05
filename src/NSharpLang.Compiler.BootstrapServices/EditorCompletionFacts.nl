namespace NSharpLang.Compiler.CodeIntelligence


// THE EDITOR'S HALF OF A COMPLETION ANSWER: THE SAME ITEMS THE CLI ALREADY COMPUTED, SAID IN THE
// THREE WORDS AN LSP CLIENT UNDERSTANDS.
//
// Nothing here decides WHAT a receiver offers — `CompletionReceiverFacts` decided that, and the
// editor and `nlc query completions` are answered by that one owner so they cannot drift. What is
// left is presentation, and it is exactly three questions: which icon the client draws, what the
// grey text beside the label says, and in what order the list appears.
//
// THE KIND NUMBERS ARE THE LANGUAGE SERVER PROTOCOL'S, NOT N#'s. `CompletionItemKind` is fixed by
// the specification's §"Completion Request" table — Method is 2, Field is 5, Property is 10 — the
// same class of ecosystem fact as JSON-RPC's member names: a number a specification fixes, which no
// N# owner may reinvent. What IS an N# decision, and therefore lives here, is which of those slots
// each of the thirteen completion kinds lands in. A kind nobody has taught this table answers Text
// (1), the protocol's own "no particular icon", rather than guessing.
//
// THE ORDER IS THE OWNER'S ORDER, PRESERVED, NOT A NEW ONE — and since the overload collapse the
// owner's order is worth preserving. `CompletionEngineKernels.CollapseCompletionOverloads` sorts by
// kind rank and then by name before the items are ever grouped, so the list arrives methods-then-
// properties with each run alphabetical; an editor that re-sorted them would be recomputing what it
// was handed. So the sort key is still the item's POSITION in the owner's answer, zero-padded so it
// compares as a string the way it counts as a number, which is what an LSP `sortText` is.
//
// (It said the same sentence before the collapse, when the position it preserved was REFLECTION
// order — `GetMethods` order, with every overload its own row. The sentence was right and the order
// behind it was not; fixing the order is what made the sentence true.)
class EditorCompletionFacts {

    // The protocol slot for one N# completion kind.
    static func LspCompletionItemKind(kind: string): int {
        if kind == "method" {
            return 2
        }
        if kind == "function" {
            return 3
        }
        if kind == "field" {
            return 5
        }
        if kind == "variable" {
            return 6
        }
        if kind == "class" || kind == "record" {
            return 7
        }
        if kind == "interface" {
            return 8
        }
        if kind == "property" {
            return 10
        }
        if kind == "enum" {
            return 13
        }
        if kind == "keyword" || kind == "modifier" || kind == "primitive" {
            return 14
        }
        if kind == "struct" {
            return 22
        }

        // A union is a closed set of named cases, and `Enum` is the slot whose icon says that.
        if kind == "union" {
            return 13
        }

        return 1
    }

    // THE GREY TEXT BESIDE THE LABEL, AND WHY IT IS NOT THE CLI'S LINE. `GetCompletionItemLineText`
    // renders `    Name (params): Type` because a terminal has nothing but the line; a client draws
    // the name itself and the icon already says the kind, so repeating either would be noise. What
    // is left is the signature — the parameters when there are any, the type when there is one —
    // and when an item carries neither, the kind word is better than an empty column.
    static func MemberDetailText(item: CompletionItem): string {
        parameters := item.Parameters
        typeText := item.Type

        if parameters != null && typeText != null {
            return (parameters ?? "") + ": " + (typeText ?? "") + OverloadSuffix(item)
        }

        if parameters != null {
            return (parameters ?? "") + OverloadSuffix(item)
        }

        if typeText != null {
            return (typeText ?? "") + OverloadSuffix(item)
        }

        return item.Kind + OverloadSuffix(item)
    }

    // WHAT THE COLLAPSE OWES THE READER. One row now stands for every overload of a name, and the
    // count is the one thing that row would otherwise not say — so it goes in the grey text, in
    // hover's own words (`(+2 overloads)`), and a name with a single declaration says nothing extra.
    static func OverloadSuffix(item: CompletionItem): string {
        hidden := item.Overloads - 1
        if hidden < 1 {
            return ""
        }

        if hidden == 1 {
            return " (+1 overload)"
        }

        return " (+" + hidden.ToString() + " overloads)"
    }

    // The item's place in the owner's answer, as a string that sorts like the number it is.
    //
    // TEN DIGITS, AND THE WIDTH IS THE WHOLE CORRECTNESS ARGUMENT. An LSP `sortText` is compared as
    // TEXT, so a pad that any rank can outgrow is worse than none: at width four, rank 10000 renders
    // `"10000"`, which sorts BEFORE `"9999"` and silently reverses the tail of the list. `int.MaxValue`
    // is 2147483647 — ten digits — so a ten-wide pad is one no rank can overflow, and ordinal order
    // and numeric order are then the same order for every value this can ever be handed.
    static func MemberSortText(rank: int): string {
        padded := rank.ToString()
        while padded.Length < 10 {
            padded = "0" + padded
        }

        return padded
    }
}
