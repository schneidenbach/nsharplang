namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import System.Text
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

class CompletionReceiverClassification {
    isMemberAccessValue: bool
    receiverValue: string?

    IsMemberAccess: bool => isMemberAccessValue
    Receiver: string? => receiverValue

    constructor(IsMemberAccess: bool, Receiver: string?) {
        isMemberAccessValue = IsMemberAccess
        receiverValue = Receiver
    }
}

class CompletionEngineKernels {
    static func ClassifyCompletionReceiver(beforeCursor: string): CompletionReceiverClassification {
        if !IsCompletionMemberAccessContext(beforeCursor) {
            return new CompletionReceiverClassification(false, null)
        }

        receiver := ExtractCompletionReceiver(beforeCursor)
        if receiver.Length == 0 {
            return new CompletionReceiverClassification(true, null)
        }

        return new CompletionReceiverClassification(true, receiver)
    }

    // ── ONE ROW PER NAME, IN ONE ORDER, SAID ONCE ──────────────────────────────────────────────
    //
    // WHAT A `string` RECEIVER USED TO ANSWER: 107 rows, 27 of them names repeated — `Split`
    // eleven times, `IndexOf` ten, `LastIndexOf` nine — because `GetMethods` hands back one
    // `MethodInfo` per OVERLOAD and every one became its own item with the same label. In an
    // editor that is a list you cannot read; the same 107 collapse to 39.
    //
    // ONE ROW PER MEMBER NAME, WITH THE COUNT IN THE DETAIL, is what Roslyn shows in VS Code and
    // what TypeScript shows, and it is the only shape that satisfies the extension suite's
    // duplicate-label check. The alternative — a row per overload with distinct labels — asks a
    // completion list to do signature help's job at the moment the user has typed a dot and no
    // arguments, so there is nothing yet to tell the overloads apart with.
    //
    // AND THE RULE WAS ALREADY HERE, SPELLED IN C# IN ONE PLACE ONLY. `PlaygroundCompiler` had
    // `DeduplicateCompletions`: group by label, keep the first, order by a kind rank then the
    // label. The playground has been ordering its lists that way all along while the CLI and the
    // editor showed reflection order — a third spelling of a shared decision, and the wrong two
    // were the ones a developer looks at. This is that rule, moved to its owner, with the count
    // the C# threw away when it kept only the first row.
    static func CompletionKindSortRank(kind: string): int {
        if kind == "keyword" {
            return 0
        }
        if kind == "variable" || kind == "parameter" {
            return 1
        }
        if kind == "function" || kind == "method" {
            return 2
        }
        if kind == "property" || kind == "field" {
            return 3
        }
        if kind == "class" || kind == "record" || kind == "struct" || kind == "interface" || kind == "enum" || kind == "union" || kind == "type" {
            return 4
        }

        return 9
    }

    // Collapse by name, then order by kind rank and name. The FIRST row of a name survives and
    // carries the count of the whole set, so the surviving signature is the one the receiver
    // offered first — the same row the playground's `.First()` kept, now able to say how many it
    // stands for. An already-collapsed row keeps its count, because the counts are SUMMED rather
    // than reset; running this twice is the same as running it once, which is what lets the CLI
    // group and the editor flatten through the same function.
    //
    // NOT EVERY REPEATED NAME IS AN OVERLOAD, AND BOTH WAYS THAT GOES WRONG WERE MEASURED RATHER
    // THAN PREDICTED. An identifier position offers `async` as a KEYWORD and again as a MODIFIER,
    // and it offers `Add` twice with the identical signature, because the declared-type table lists
    // top-level functions beside the functions table. Counting either merge would have told the
    // reader that their own one-line `Add` has an overload — a claim about their program, not a
    // display quirk. So a merge raises the count only when the two rows are the SAME KIND and carry
    // a signature the name has not shown yet; every other duplicate still collapses to one row,
    // because the reader must see the name once, but contributes nothing to the count.
    static func CollapseCompletionOverloads(items: List<CompletionItem>): List<CompletionItem> {
        collapsed := new List<CompletionItem>()
        indexByName := new Dictionary<string, int>(StringComparer.Ordinal)
        seenSignatures := new HashSet<string>()

        i := 0
        while i < items.Count {
            item := items[i]
            signature := CompletionItemSignatureKey(item)
            existingIndex := 0
            if indexByName.TryGetValue(item.Name, out existingIndex) {
                existing := collapsed[existingIndex]
                if existing.Kind == item.Kind && !seenSignatures.Contains(signature) {
                    seenSignatures.Add(signature)
                    collapsed[existingIndex] = new CompletionItem(existing.Name, existing.Kind, existing.Type, existing.Parameters, existing.Documentation, existing.IsStatic, existing.Overloads + item.Overloads)
                }
            } else {
                seenSignatures.Add(signature)
                indexByName.Add(item.Name, collapsed.Count)
                collapsed.Add(item)
            }

            i = i + 1
        }

        return OrderCompletionItems(collapsed)
    }

    // What makes two rows the same declaration to a reader: the name, the word it is offered under,
    // and the signature drawn beside it. Two rows equal in all three are one member listed twice.
    static func CompletionItemSignatureKey(item: CompletionItem): string {
        return item.Name + "\n" + item.Kind + "\n" + (item.Parameters ?? "") + "\n" + (item.Type ?? "")
    }

    // A STABLE insertion sort on (kind rank, name), and the stability is a contract: two rows that
    // compare equal keep the order the receiver produced them in, which is what makes the answer
    // reproducible rather than dependent on a sort's internals.
    static func OrderCompletionItems(items: List<CompletionItem>): List<CompletionItem> {
        ordered := new List<CompletionItem>()

        i := 0
        while i < items.Count {
            item := items[i]
            position := ordered.Count
            j := 0
            while j < ordered.Count {
                if CompareCompletionItems(item, ordered[j]) < 0 {
                    position = j
                    j = ordered.Count
                } else {
                    j = j + 1
                }
            }

            ordered.Insert(position, item)
            i = i + 1
        }

        return ordered
    }

    static func CompareCompletionItems(left: CompletionItem, right: CompletionItem): int {
        rankDifference := CompletionKindSortRank(left.Kind) - CompletionKindSortRank(right.Kind)
        if rankDifference != 0 {
            return rankDifference
        }

        return string.Compare(left.Name, right.Name, StringComparison.OrdinalIgnoreCase)
    }

    // THE GROUPS AS ONE LIST, FOR THE TWO SURFACES THAT DRAW A LIST RATHER THAN A TABLE. The
    // editor and the playground both want a flat, ordered, duplicate-free answer, and asking the
    // same function for it is what keeps them from drifting apart the way they had.
    static func FlattenCompletionGroups(completions: Dictionary<string, List<CompletionItem>>): List<CompletionItem> {
        flattened := new List<CompletionItem>()
        for pair in completions {
            group := pair.Value
            index := 0
            while index < group.Count {
                flattened.Add(group[index])
                index = index + 1
            }
        }

        return CollapseCompletionOverloads(flattened)
    }

    static func AddGroupedCompletionItemsByKind(rawItems: List<CompletionItem>, completions: Dictionary<string, List<CompletionItem>>) {
        if rawItems.Count == 0 {
            return
        }

        // Collapsed and ordered BEFORE grouping, so the groups arrive in kind-rank order and each
        // one is alphabetical inside — the JSON's group order and the editor's row order are then
        // the same order, computed once.
        items := CollapseCompletionOverloads(rawItems)
        order := new List<string>()
        groups := new Dictionary<string, List<CompletionItem>>(StringComparer.Ordinal)

        i := 0
        while i < items.Count {
            item := items[i]
            key := PluralizeCompletionKind(item.Kind)
            group := new List<CompletionItem>()
            if !groups.TryGetValue(key, out group) {
                group = new List<CompletionItem>()
                groups.Add(key, group)
                order.Add(key)
            }

            group.Add(item)
            i = i + 1
        }

        j := 0
        while j < order.Count {
            key := order[j]
            group := new List<CompletionItem>()
            groups.TryGetValue(key, out group)
            if completions.ContainsKey(key) {
                removed := new List<CompletionItem>()
                completions.Remove(key, out removed)
            }
            completions.Add(key, group)
            j = j + 1
        }
    }

    static func BuildMemberItemsFromRows(names: string[], kinds: string[], typeTexts: string[], isStaticValues: bool[]): List<CompletionItem> {
        return BuildMemberItemsFromRows(names, kinds, typeTexts, isStaticValues, new int[](0))
    }

    // THE SAME ROWS, PLUS HOW MANY DECLARATIONS EACH ONE STANDS FOR. A count array shorter than the
    // rows — or absent entirely — means one declaration each, which is what every producer but the
    // reflected one has to say.
    static func BuildMemberItemsFromRows(names: string[], kinds: string[], typeTexts: string[], isStaticValues: bool[], overloads: int[]): List<CompletionItem> {
        items := new List<CompletionItem>()
        count := names.Length
        if kinds.Length < count {
            count = kinds.Length
        }

        if typeTexts.Length < count {
            count = typeTexts.Length
        }

        if isStaticValues.Length < count {
            count = isStaticValues.Length
        }

        i := 0
        while i < count {
            typeText: string? = null
            if typeTexts[i].Length > 0 {
                typeText = typeTexts[i]
            }

            overloadCount := 1
            if i < overloads.Length && overloads[i] > 1 {
                overloadCount = overloads[i]
            }

            items.Add(new CompletionItem(names[i], kinds[i], typeText, null, null, isStaticValues[i], overloadCount))
            i = i + 1
        }

        return items
    }

    static func PluralizeCompletionKind(kind: string): string {
        if kind == "property" {
            return "properties"
        }

        if kind == "class" {
            return "classes"
        }

        return kind + "s"
    }

    static func IsCompletionMemberAccessContext(beforeCursor: string): bool {
        end := TrimCompletionReceiverEnd(beforeCursor, beforeCursor.Length)
        if end <= 0 {
            return false
        }

        if beforeCursor[end - 1] == '.' {
            return true
        }

        lastDot := LastCompletionReceiverCharBefore(beforeCursor, '.', end)
        if lastDot > 0 {
            beforeDotEnd := TrimCompletionReceiverEnd(beforeCursor, lastDot)
            if beforeDotEnd > 0 && IsCompletionReceiverIdentifierChar(beforeCursor[beforeDotEnd - 1]) {
                return true
            }
        }

        return false
    }

    static func ExtractCompletionReceiver(beforeCursor: string): string {
        end := TrimCompletionReceiverEnd(beforeCursor, beforeCursor.Length)
        dotIndex := FindLastCompletionTopLevelDot(beforeCursor, end)
        if dotIndex < 0 {
            return ""
        }

        withoutDotEnd := TrimCompletionReceiverEnd(beforeCursor, dotIndex)
        return ExtractCompletionExpressionSuffix(beforeCursor, withoutDotEnd)
    }

    static func ExtractCompletionExpressionSuffix(text: string, end: int): string {
        literalReceiver := TryExtractCompletionLiteralSuffix(text, end)
        if literalReceiver.Length > 0 {
            return literalReceiver
        }

        start := end - 1
        parenDepth := 0
        consumed := false

        while start >= 0 {
            current := text[start]
            if current == ')' {
                parenDepth = parenDepth + 1
                consumed = true
                start = start - 1
                continue
            }

            if current == '(' {
                if parenDepth == 0 {
                    break
                }

                parenDepth = parenDepth - 1
                start = start - 1
                continue
            }

            if parenDepth > 0 {
                start = start - 1
                continue
            }

            if IsCompletionReceiverIdentifierChar(current) || current == '.' {
                consumed = true
                start = start - 1
                continue
            }

            break
        }

        if !consumed || parenDepth != 0 {
            return ""
        }

        start = start + 1
        if start < end {
            return NormalizeCompletionReceiverCalls(text, start, end)
        }

        return ""
    }

    static func TryExtractCompletionLiteralSuffix(text: string, end: int): string {
        if end <= 0 {
            return ""
        }

        if EndsCompletionReceiverWith(text, end, "true") {
            start := end - 4
            if IsCompletionReceiverTokenBoundary(text, start) && !HasCompletionLineCommentBefore(text, start) {
                return text.Substring(start, 4)
            }
        }

        if EndsCompletionReceiverWith(text, end, "false") {
            start := end - 5
            if IsCompletionReceiverTokenBoundary(text, start) && !HasCompletionLineCommentBefore(text, start) {
                return text.Substring(start, 5)
            }
        }

        current := text[end - 1]
        if current == '"' {
            rawStart := FindCompletionRawStringStart(text, end)
            if rawStart >= 0 && !HasCompletionLineCommentBefore(text, rawStart) {
                return text.Substring(rawStart, end - rawStart)
            }

            stringStart := FindCompletionStringStart(text, end)
            if stringStart >= 0 && !HasCompletionLineCommentBefore(text, stringStart) {
                return text.Substring(stringStart, end - stringStart)
            }
        }

        if current == '\'' {
            charStart := FindCompletionCharStart(text, end)
            if charStart >= 0 && !HasCompletionLineCommentBefore(text, charStart) {
                return text.Substring(charStart, end - charStart)
            }
        }

        numericStart := FindCompletionNumericLiteralStart(text, end)
        if numericStart >= 0 && !HasCompletionLineCommentBefore(text, numericStart) {
            return text.Substring(numericStart, end - numericStart)
        }

        return ""
    }

    static func NormalizeCompletionReceiverCalls(text: string, start: int, end: int): string {
        builder := new StringBuilder(end - start)
        index := start

        while index < end {
            current := text[index]
            builder.Append(current)
            if current != '(' {
                index = index + 1
                continue
            }

            parenDepth := 1
            index = index + 1
            while index < end && parenDepth > 0 {
                if text[index] == '(' {
                    parenDepth = parenDepth + 1
                } else if text[index] == ')' {
                    parenDepth = parenDepth - 1
                }

                index = index + 1
            }

            builder.Append(')')
        }

        return builder.ToString()
    }

    static func FindCompletionRawStringStart(text: string, end: int): int {
        if end < 6 || text[end - 1] != '"' || text[end - 2] != '"' || text[end - 3] != '"' {
            return -1
        }

        position := end - 6
        while position >= 0 {
            if text[position] == '"' && text[position + 1] == '"' && text[position + 2] == '"' {
                while position > 0 && text[position - 1] == '$' {
                    position = position - 1
                }

                return position
            }

            position = position - 1
        }

        return -1
    }

    static func FindCompletionStringStart(text: string, end: int): int {
        position := end - 2

        while position >= 0 {
            if text[position] == '"' && !IsCompletionEscaped(text, position) {
                if position > 0 && text[position - 1] == '$' {
                    return position - 1
                }

                return position
            }

            position = position - 1
        }

        return -1
    }

    static func FindCompletionCharStart(text: string, end: int): int {
        position := end - 2

        while position >= 0 {
            if text[position] == '\'' && !IsCompletionEscaped(text, position) {
                return position
            }

            position = position - 1
        }

        return -1
    }

    static func IsCompletionEscaped(text: string, index: int): bool {
        slashCount := 0
        position := index - 1

        while position >= 0 && text[position] == '\\' {
            slashCount = slashCount + 1
            position = position - 1
        }

        return (slashCount & 1) == 1
    }

    static func FindCompletionNumericLiteralStart(text: string, end: int): int {
        position := end - 1

        while position >= 0 {
            if IsCompletionDigit(text[position]) && IsCompletionNumericStartBoundary(text, position) && ScanCompletionNumber(text, position, end) == end {
                return position
            }

            position = position - 1
        }

        return -1
    }

    static func ScanCompletionNumber(text: string, position: int, end: int): int {
        if text[position] == '0' && position + 1 < end && (text[position + 1] == 'x' || text[position + 1] == 'X') {
            position = position + 2
            while position < end && (IsCompletionHexDigit(text[position]) || text[position] == '_') {
                position = position + 1
            }

            return ConsumeCompletionIntegerSuffix(text, position, end)
        }

        if text[position] == '0' && position + 1 < end && (text[position + 1] == 'b' || text[position + 1] == 'B') {
            position = position + 2
            while position < end && (text[position] == '0' || text[position] == '1' || text[position] == '_') {
                position = position + 1
            }

            return ConsumeCompletionIntegerSuffix(text, position, end)
        }

        isFloat := false
        while position < end && (IsCompletionDigit(text[position]) || text[position] == '.' || text[position] == '_') {
            if text[position] == '.' {
                if position + 1 < end && text[position + 1] == '.' {
                    break
                }

                if position + 1 >= end || !IsCompletionDigit(text[position + 1]) {
                    break
                }

                isFloat = true
            }

            position = position + 1
        }

        if position < end && (text[position] == 'e' || text[position] == 'E') {
            isFloat = true
            position = position + 1
            if position < end && (text[position] == '+' || text[position] == '-') {
                position = position + 1
            }

            while position < end && (IsCompletionDigit(text[position]) || text[position] == '_') {
                position = position + 1
            }
        }

        if isFloat {
            return ConsumeCompletionFloatSuffix(text, position, end)
        }

        if position < end && (text[position] == 'm' || text[position] == 'M') {
            return position + 1
        }

        return ConsumeCompletionIntegerSuffix(text, position, end)
    }

    static func IsCompletionNumericStartBoundary(text: string, start: int): bool {
        if start <= 0 {
            return true
        }

        previous := text[start - 1]
        if previous == '.' {
            return start < 2 || !IsCompletionDigit(text[start - 2])
        }

        if previous == '+' || previous == '-' {
            if start >= 3 {
                marker := text[start - 2]
                if (marker == 'e' || marker == 'E') && IsCompletionDigit(text[start - 3]) {
                    return false
                }
            }

            return true
        }

        return !IsCompletionReceiverIdentifierChar(previous)
    }

    static func ConsumeCompletionFloatSuffix(text: string, position: int, end: int): int {
        if position < end && (text[position] == 'f' || text[position] == 'F' || text[position] == 'd' || text[position] == 'D' || text[position] == 'm' || text[position] == 'M') {
            return position + 1
        }

        return position
    }

    static func ConsumeCompletionIntegerSuffix(text: string, position: int, end: int): int {
        if position < end && (text[position] == 'u' || text[position] == 'U') {
            position = position + 1
            if position < end && (text[position] == 'l' || text[position] == 'L') {
                position = position + 1
            }

            return position
        }

        if position < end && (text[position] == 'l' || text[position] == 'L') {
            position = position + 1
            if position < end && (text[position] == 'u' || text[position] == 'U') {
                position = position + 1
            }

            return position
        }

        return position
    }

    static func FindLastCompletionTopLevelDot(text: string, end: int): int {
        parenDepth := 0
        index := end - 1

        while index >= 0 {
            current := text[index]
            if current == ')' {
                parenDepth = parenDepth + 1
            } else if current == '(' {
                if parenDepth > 0 {
                    parenDepth = parenDepth - 1
                }
            } else if current == '.' && parenDepth == 0 {
                return index
            }

            index = index - 1
        }

        return -1
    }

    static func LastCompletionReceiverCharBefore(text: string, ch: char, end: int): int {
        index := end - 1

        while index >= 0 {
            if text[index] == ch {
                return index
            }

            index = index - 1
        }

        return -1
    }

    static func TrimCompletionReceiverEnd(text: string, end: int): int {
        if end > text.Length {
            end = text.Length
        }

        while end > 0 && IsCompletionReceiverWhitespace(text[end - 1]) {
            end = end - 1
        }

        return end
    }

    static func EndsCompletionReceiverWith(text: string, end: int, suffix: string): bool {
        if end < suffix.Length {
            return false
        }

        start := end - suffix.Length
        i := 0
        while i < suffix.Length {
            if text[start + i] != suffix[i] {
                return false
            }

            i = i + 1
        }

        return true
    }

    static func IsCompletionReceiverTokenBoundary(text: string, start: int): bool {
        return start <= 0 || !IsCompletionReceiverIdentifierChar(text[start - 1])
    }

    static func HasCompletionLineCommentBefore(text: string, start: int): bool {
        position := 0
        last := start - 1

        while position < last {
            if text[position] == '/' && text[position + 1] == '/' {
                return true
            }

            position = position + 1
        }

        return false
    }

    static func IsCompletionReceiverIdentifierChar(ch: char): bool {
        if ch >= 'a' && ch <= 'z' {
            return true
        }

        if ch <= '~' {
            return ch == '_' || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')
        }

        if ch >= 'A' && ch <= 'Z' {
            return true
        }

        if ch >= '0' && ch <= '9' {
            return true
        }

        return Char.IsLetterOrDigit(ch)
    }

    static func IsCompletionReceiverWhitespace(ch: char): bool {
        if ch == ' ' {
            return true
        }

        if ch <= '~' {
            return ch >= '\t' && ch <= '\r'
        }

        return Char.IsWhiteSpace(ch)
    }

    static func IsCompletionDigit(ch: char): bool {
        return ch >= '0' && ch <= '9'
    }

    static func IsCompletionHexDigit(ch: char): bool {
        return (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')
    }

    // ── WHAT A POSITION THAT IS NOT AFTER A DOT OFFERS ──────────────────────────────────────────
    //
    // `ClassifyCompletionReceiver` above decides which of the two answers a caret gets; this is the
    // other one. Where a member access asks "what does THIS thing have", an identifier position
    // asks "what can I write here at all", and the answer is everything in scope, grouped.
    //
    // THE GROUPS ARE ALWAYS IN THIS ORDER — variables, functions, types, then the three vocabulary
    // tables — and an EMPTY GROUP IS OMITTED RATHER THAN EMITTED EMPTY. That is a wire-format
    // contract, not a tidiness preference: the CLI's JSON and text renderers both walk the
    // dictionary in insertion order, so the order here is the order a caller sees.
    //
    // A NAME THAT IS BOTH A VARIABLE AND A FUNCTION IS SHOWN ONCE, AS A FUNCTION. The semantic
    // model records a local function under both, and offering it twice would be two entries the
    // caller has to reconcile; the function entry is the one that carries a parameter list, so it
    // is the one that survives.
    //
    // THE VARIABLE SET IS POSITION-AWARE ONLY WHEN IT CAN BE. With a real line and a model that
    // recorded scopes, the answer is the variables visible AT that point; without either, it is
    // every variable the file declared. The fallback is deliberately wider rather than empty — a
    // caller that gave no position gets too much rather than nothing.
    //
    // KEYWORDS, PRIMITIVE TYPES AND MODIFIERS ARE OFF BY DEFAULT, and that is the LLM-first rule
    // this engine was built for: a model already knows the language's vocabulary, so spending
    // tokens on it is waste. An editor asks for them explicitly.
    static func GetIdentifierCompletions(unit: CompilationUnit, semanticModel: SemanticModel?, includeKeywords: bool, line: int, column: int): CompletionResult {
        completions := new Dictionary<string, List<CompletionItem>>()

        if semanticModel != null {
            variables := VisibleVariableItems(semanticModel, line, column)
            if variables.Count > 0 {
                completions["variables"] = variables
            }

            functions := FunctionItems(semanticModel)
            if functions.Count > 0 {
                completions["functions"] = functions
            }
        }

        types := DeclaredTypeItems(unit)
        if types.Count > 0 {
            completions["types"] = types
        }

        if includeKeywords {
            keywords := NSharpKeywordItems()
            completions["keywords"] = keywords

            primitiveTypes := PrimitiveTypeItems()
            completions["primitiveTypes"] = primitiveTypes

            modifiers := ModifierItems()
            completions["modifiers"] = modifiers
        }

        return new CompletionResult(CompletionContext.Identifier, null, null, completions)
    }

    // The variables offered at a position. A name the model also records as a function is skipped
    // here and offered by `FunctionItems` instead.
    static func VisibleVariableItems(semanticModel: SemanticModel, line: int, column: int): List<CompletionItem> {
        scopes := semanticModel.Scopes
        visible := semanticModel.Variables
        if line > 0 && scopes.Count > 0 {
            visible = semanticModel.GetVisibleVariablesAtPosition(line, column)
        }

        functions := semanticModel.Functions
        items := new List<CompletionItem>()
        for pair in visible {
            if !functions.ContainsKey(pair.Key) {
                items.Add(new CompletionItem(pair.Key, "variable", CompletionTypeTextFacts.FormatTypeText(pair.Value), null, null, false))
            }
        }

        return items
    }

    // The functions in scope. Only a function TYPE can show a parameter list; anything else the
    // model filed as a function shows its type text alone rather than a fabricated signature.
    static func FunctionItems(semanticModel: SemanticModel): List<CompletionItem> {
        items := new List<CompletionItem>()
        for pair in semanticModel.Functions {
            parameterText: string? = null
            functionType := pair.Value as FunctionTypeInfo
            if functionType != null {
                parameterText = CompletionTypeTextFacts.FormatFunctionTypeParameters(functionType)
            }

            items.Add(new CompletionItem(pair.Key, "function", CompletionTypeTextFacts.FormatTypeText(pair.Value), parameterText, null, false))
        }

        return items
    }

    // The types this file declares, in source order. A declaration with no completion shape is
    // dropped rather than named.
    static func DeclaredTypeItems(unit: CompilationUnit): List<CompletionItem> {
        items := new List<CompletionItem>()
        declarations := unit.Declarations

        index := 0
        while index < declarations.Count {
            item := CompletionDeclarationFacts.ToCompletionItem(declarations[index])
            if item != null {
                items.Add(item)
            }

            index = index + 1
        }

        return items
    }

    // A vocabulary table rendered as completion items, in table order.
    static func WordCompletionItems(words: string, kind: string): List<CompletionItem> {
        items := new List<CompletionItem>()
        parts := words.Split(' ')

        index := 0
        while index < parts.Length {
            items.Add(new CompletionItem(parts[index], kind, null, null, null, false))
            index = index + 1
        }

        return items
    }

    // THE THREE VOCABULARY TABLES. Order is the order an editor sees them in, so each table is
    // written in the grouping the language reads in — declaration forms, then control flow, then
    // expression keywords, then literals — and not alphabetically.
    static func NSharpKeywordItems(): List<CompletionItem> {
        return WordCompletionItems("func class struct record interface enum union if else for foreach while return break continue match switch case when yield await async throw try catch finally lock must new this base import namespace print test assert true false null is as typeof nameof", "keyword")
    }

    static func ModifierItems(): List<CompletionItem> {
        return WordCompletionItems("pub static virtual override abstract sealed partial readonly const required init async", "modifier")
    }

    static func PrimitiveTypeItems(): List<CompletionItem> {
        return WordCompletionItems("int long float double bool string void object byte short char decimal uint ulong ushort sbyte", "type")
    }
}
