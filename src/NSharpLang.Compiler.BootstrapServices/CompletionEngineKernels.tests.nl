namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// CONTRACTS FOR WHAT A POSITION THAT IS NOT AFTER A DOT OFFERS (task 019 slice 4). These assertions
// came out of `CompletionEngine.GetIdentifierCompletions` with the three vocabulary tables: the
// group ORDER a caller sees, the rule that an empty group is omitted rather than emitted empty, the
// rule that a name recorded as both a variable and a function is offered once as a function, and
// the LLM-first default that keywords, primitive types and modifiers are off unless asked for.
func CekUnit(declarations: List<Declaration>): CompilationUnit {
    return new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, declarations, 1, 1)
}

func CekEmptyUnit(): CompilationUnit {
    return CekUnit(new List<Declaration>())
}

func CekUnitWithClass(name: string): CompilationUnit {
    declarations := new List<Declaration>()
    declaration: Declaration = new ClassDeclaration(name, null, null, new List<TypeReference>(), new List<Declaration>(), null, Modifiers.None, new List<AttributeNode>(), 1, 1)
    declarations.Add(declaration)
    return CekUnit(declarations)
}

func CekGroupNames(result: CompletionResult): string {
    text := ""
    completions := result.Completions
    for pair in completions {
        if text.Length > 0 {
            text = text + ","
        }

        text = text + pair.Key
    }

    return text
}

func CekItemNames(result: CompletionResult, group: string): string {
    completions := result.Completions
    items := new List<CompletionItem>()
    if !completions.TryGetValue(group, out items) {
        return "<no-group>"
    }

    text := ""
    index := 0
    while index < items.Count {
        if index > 0 {
            text = text + ","
        }

        text = text + items[index].Name
        index = index + 1
    }

    return text
}

func CekItemCount(result: CompletionResult, group: string): int {
    completions := result.Completions
    items := new List<CompletionItem>()
    if !completions.TryGetValue(group, out items) {
        return -1
    }

    return items.Count
}

test "an identifier position answers Identifier with no receiver, and omits every empty group" {
    // Nothing declared and no model at all: the answer is well-formed and completely empty. It is
    // NOT `Unknown` — the position is understood, there is simply nothing in scope.
    bare := CompletionEngineKernels.GetIdentifierCompletions(CekEmptyUnit(), null, false, 1, 1)
    assert bare.Context == CompletionContext.Identifier
    assert bare.Receiver == null
    assert bare.ReceiverType == null
    assert bare.Completions.Count == 0

    // A model with nothing in it adds no groups either — empty groups are omitted, not emitted.
    empty := CompletionEngineKernels.GetIdentifierCompletions(CekEmptyUnit(), new SemanticModel(), false, 1, 1)
    assert empty.Completions.Count == 0
}

test "the groups appear in one fixed order, because that order is what a caller reads" {
    model := new SemanticModel()
    variables := model.Variables
    variables["count"] = BuiltInTypes.Int
    functions := model.Functions
    functions["Run"] = BuiltInTypes.Void

    // Variables, functions, types, then the three vocabulary tables. The CLI's JSON and text
    // renderers both walk this dictionary in insertion order, so this is a wire-format contract.
    full := CompletionEngineKernels.GetIdentifierCompletions(CekUnitWithClass("Widget"), model, true, 0, 0)
    assert CekGroupNames(full) == "variables,functions,types,keywords,primitiveTypes,modifiers"

    // Without the vocabulary the first three keep the same relative order.
    lean := CompletionEngineKernels.GetIdentifierCompletions(CekUnitWithClass("Widget"), model, false, 0, 0)
    assert CekGroupNames(lean) == "variables,functions,types"
}

test "a name that is both a variable and a function is offered once, as the function" {
    model := new SemanticModel()
    variables := model.Variables
    variables["helper"] = BuiltInTypes.Int
    variables["count"] = BuiltInTypes.Int
    functions := model.Functions
    functions["helper"] = BuiltInTypes.Void

    result := CompletionEngineKernels.GetIdentifierCompletions(CekEmptyUnit(), model, false, 0, 0)

    // `helper` is filed under both. It appears ONCE, and under functions — the entry that can carry
    // a parameter list is the one that survives.
    assert CekItemNames(result, "variables") == "count"
    assert CekItemNames(result, "functions") == "helper"

    // A model whose every variable is also a function emits no variables group at all.
    shadowed := new SemanticModel()
    shadowedVariables := shadowed.Variables
    shadowedVariables["helper"] = BuiltInTypes.Int
    shadowedFunctions := shadowed.Functions
    shadowedFunctions["helper"] = BuiltInTypes.Void
    onlyFunctions := CompletionEngineKernels.GetIdentifierCompletions(CekEmptyUnit(), shadowed, false, 0, 0)
    assert CekGroupNames(onlyFunctions) == "functions"
}

test "the variable set is position-aware only when there is both a position and a recorded scope" {
    model := new SemanticModel()
    model.RecordVariable("outer", BuiltInTypes.Int)

    scopeId := model.OpenScope(-1, 10, 1)
    model.RecordScopedVariable(scopeId, "inner", BuiltInTypes.String)
    model.CloseScope(scopeId, 20, 1)

    // Inside the scope, the position-aware read answers the SCOPE's variables — `outer` was never
    // recorded in one, so it is not visible there.
    inside := CompletionEngineKernels.GetIdentifierCompletions(CekEmptyUnit(), model, false, 15, 3)
    assert CekItemNames(inside, "variables") == "inner"

    // Outside every scope, the position-aware read answers nothing rather than falling back wide.
    // A position that resolves to no scope is a real answer, not a reason to widen.
    outside := CompletionEngineKernels.GetIdentifierCompletions(CekEmptyUnit(), model, false, 99, 3)
    assert CekGroupNames(outside) == ""

    // WITH NO POSITION the answer is deliberately WIDER, not empty: a caller that gave no line
    // gets every variable the file declared rather than nothing at all.
    wide := CompletionEngineKernels.GetIdentifierCompletions(CekEmptyUnit(), model, false, 0, 0)
    assert CekItemNames(wide, "variables") == "outer,inner"
}

test "the three vocabulary tables are off by default, and each one is offered under its own word" {
    lean := CompletionEngineKernels.GetIdentifierCompletions(CekEmptyUnit(), null, false, 1, 1)
    assert lean.Completions.Count == 0

    full := CompletionEngineKernels.GetIdentifierCompletions(CekEmptyUnit(), null, true, 1, 1)
    assert CekGroupNames(full) == "keywords,primitiveTypes,modifiers"

    // The tables are DATA and their sizes are part of the contract: a keyword silently lost to a
    // typo in the table would otherwise never be noticed.
    assert CekItemCount(full, "keywords") == 43
    assert CekItemCount(full, "primitiveTypes") == 16
    assert CekItemCount(full, "modifiers") == 12

    keywords := CompletionEngineKernels.NSharpKeywordItems()
    assert keywords[0].Name == "func"
    assert keywords[0].Kind == "keyword"
    assert keywords[0].Type == null
    assert !keywords[0].IsStatic

    primitives := CompletionEngineKernels.PrimitiveTypeItems()
    assert primitives[0].Name == "int"

    // A primitive type is offered as a "type", NOT as a "keyword" — the word is what an editor
    // renders an icon from.
    assert primitives[0].Kind == "type"

    modifiers := CompletionEngineKernels.ModifierItems()
    assert modifiers[0].Name == "pub"
    assert modifiers[0].Kind == "modifier"
}

test "a function type shows its parameter list and anything else filed as a function does not" {
    model := new SemanticModel()
    functions := model.Functions
    functionType := new FunctionTypeInfo()
    functionType.SourceReturnType = new SimpleTypeReference("bool")
    typed: TypeInfo = functionType
    functions["Check"] = typed
    functions["Opaque"] = BuiltInTypes.Int

    result := CompletionEngineKernels.GetIdentifierCompletions(CekEmptyUnit(), model, false, 0, 0)
    items := new List<CompletionItem>()
    completions := result.Completions
    assert completions.TryGetValue("functions", out items)
    assert items.Count == 2

    index := 0
    while index < items.Count {
        item := items[index]
        if item.Name == "Check" {
            assert item.Kind == "function"
            assert item.Type == "bool"
        }

        // A non-function type filed under functions shows its type text and NO fabricated
        // signature. The completion would rather say nothing than invent a parameter list.
        if item.Name == "Opaque" {
            assert item.Parameters == null
            assert item.Type == "int"
        }

        index = index + 1
    }
}

test "the declared types of the file are offered in source order and unnameable declarations are dropped" {
    declarations := new List<Declaration>()
    first: Declaration = new ClassDeclaration("Alpha", null, null, new List<TypeReference>(), new List<Declaration>(), null, Modifiers.None, new List<AttributeNode>(), 1, 1)
    declarations.Add(first)
    second: Declaration = new InterfaceDeclaration("IBeta", null, new List<TypeReference>(), new List<Declaration>(), Modifiers.None, false, new List<AttributeNode>(), 2, 1)
    declarations.Add(second)

    result := CompletionEngineKernels.GetIdentifierCompletions(CekUnit(declarations), null, false, 1, 1)

    // SOURCE ORDER, not sorted: the file's own order is the one a reader is holding in their head.
    assert CekItemNames(result, "types") == "Alpha,IBeta"

    items := new List<CompletionItem>()
    completions := result.Completions
    assert completions.TryGetValue("types", out items)
    assert items[0].Kind == "class"
    assert items[1].Kind == "interface"
}

// ── THE OVERLOAD COLLAPSE AND THE ONE ORDER (O1) ────────────────────────────────────────────────
//
// A `string` receiver answered 107 rows under 39 names because `GetMethods` hands back one entry
// per overload. These blocks pin the collapse, the count it owes the reader, and the order — which
// is not a new rule but the one `PlaygroundCompiler.DeduplicateCompletions` had been applying in C#
// while the CLI and the editor showed reflection order.
func CekItem(name: string, kind: string): CompletionItem {
    return new CompletionItem(name, kind, null, null, null, false)
}

func CekNames(items: List<CompletionItem>): string {
    names := ""
    index := 0
    while index < items.Count {
        if names.Length > 0 {
            names = names + ","
        }

        names = names + items[index].Name
        index = index + 1
    }

    return names
}

test "the kind rank is the playground's, moved to its owner" {
    assert CompletionEngineKernels.CompletionKindSortRank("keyword") == 0
    assert CompletionEngineKernels.CompletionKindSortRank("variable") == 1
    assert CompletionEngineKernels.CompletionKindSortRank("parameter") == 1
    assert CompletionEngineKernels.CompletionKindSortRank("function") == 2
    assert CompletionEngineKernels.CompletionKindSortRank("method") == 2
    assert CompletionEngineKernels.CompletionKindSortRank("property") == 3
    assert CompletionEngineKernels.CompletionKindSortRank("field") == 3
    assert CompletionEngineKernels.CompletionKindSortRank("record") == 4
    assert CompletionEngineKernels.CompletionKindSortRank("type") == 4
    assert CompletionEngineKernels.CompletionKindSortRank("modifier") == 9
    assert CompletionEngineKernels.CompletionKindSortRank("snippet") == 9
}

test "overloads collapse to one row that counts them, and the first row is the survivor" {
    items := new List<CompletionItem>()
    items.Add(new CompletionItem("Split", "method", "string[]", "(separator char)", null, false))
    items.Add(new CompletionItem("Split", "method", "string[]", "(separator string)", null, false))
    items.Add(new CompletionItem("Split", "method", "string[]", "(separator char[])", null, false))
    items.Add(CekItem("Length", "property"))

    collapsed := CompletionEngineKernels.CollapseCompletionOverloads(items)
    assert CekNames(collapsed) == "Split,Length"

    // THE SURVIVOR IS THE FIRST ROW, so the signature shown is the one the receiver offered first.
    assert collapsed[0].Parameters == "(separator char)"
    assert collapsed[0].Overloads == 3
    assert collapsed[1].Overloads == 1

    // IDEMPOTENT: the counts are summed, not reset, so grouping and then flattening cannot inflate
    // or lose them — which is what lets the CLI and the editor run the same function.
    twice := CompletionEngineKernels.CollapseCompletionOverloads(collapsed)
    assert CekNames(twice) == "Split,Length"
    assert twice[0].Overloads == 3
}

test "a name that appears under two KINDS collapses without being called an overload" {
    // An identifier position really does offer these: `Add` is both a function and a row in the
    // declared-type table, and `async` is both a keyword and a modifier. The reader must still see
    // one row each — but telling them `Add` has an overload would be a claim about their program.
    items := new List<CompletionItem>()
    items.Add(CekItem("Add", "function"))
    items.Add(CekItem("Add", "type"))
    items.Add(CekItem("async", "keyword"))
    items.Add(CekItem("async", "modifier"))

    collapsed := CompletionEngineKernels.CollapseCompletionOverloads(items)
    assert CekNames(collapsed) == "async,Add"
    assert collapsed[0].Overloads == 1
    assert collapsed[1].Overloads == 1

    // The FIRST row still wins, so `Add` keeps the kind the functions table gave it.
    assert collapsed[1].Kind == "function"
    assert collapsed[0].Kind == "keyword"
}

test "the SAME declaration listed twice is one row and one declaration" {
    // The identifier position really does offer `Add` twice with the identical signature: the
    // declared-type table lists top-level functions beside the functions table. Same kind, same
    // everything — so it is one listing repeated, not an overload set.
    items := new List<CompletionItem>()
    items.Add(new CompletionItem("Add", "function", "int", "(a int, b int)", null, false))
    items.Add(new CompletionItem("Add", "function", "int", "(a int, b int)", null, false))

    collapsed := CompletionEngineKernels.CollapseCompletionOverloads(items)
    assert collapsed.Count == 1
    assert collapsed[0].Overloads == 1

    // Change one field of the signature and it becomes what it now looks like: two declarations.
    distinct := new List<CompletionItem>()
    distinct.Add(new CompletionItem("Add", "function", "int", "(a int, b int)", null, false))
    distinct.Add(new CompletionItem("Add", "function", "int", "(a int, b int, c int)", null, false))
    assert CompletionEngineKernels.CollapseCompletionOverloads(distinct)[0].Overloads == 2
}

test "a row can be built already carrying its declaration count" {
    names := new string[](2)
    names[0] = "Split"
    names[1] = "Length"
    kinds := new string[](2)
    kinds[0] = "method"
    kinds[1] = "property"
    typeTexts := new string[](2)
    typeTexts[0] = "string[]"
    typeTexts[1] = "int"
    isStatic := new bool[](2)
    isStatic[0] = false
    isStatic[1] = false

    // NO COUNTS AT ALL: one declaration each, which is what every producer but the reflected one says.
    plain := CompletionEngineKernels.BuildMemberItemsFromRows(names, kinds, typeTexts, isStatic)
    assert plain.Count == 2
    assert plain[0].Overloads == 1
    assert plain[1].Overloads == 1

    counts := new int[](2)
    counts[0] = 11
    counts[1] = 1
    counted := CompletionEngineKernels.BuildMemberItemsFromRows(names, kinds, typeTexts, isStatic, counts)
    assert counted[0].Overloads == 11
    assert counted[1].Overloads == 1

    // A SHORT COUNT ARRAY IS NOT A FAULT, it is "one each" for the rows it does not reach — the
    // reflected builder is the only caller that fills it, and it fills it completely.
    short := new int[](1)
    short[0] = 4
    shortened := CompletionEngineKernels.BuildMemberItemsFromRows(names, kinds, typeTexts, isStatic, short)
    assert shortened[0].Overloads == 4
    assert shortened[1].Overloads == 1
}

test "the order is kind rank first, then the name, and it is stable inside a tie" {
    items := new List<CompletionItem>()
    items.Add(CekItem("zeta", "property"))
    items.Add(CekItem("Beta", "method"))
    items.Add(CekItem("alpha", "method"))
    items.Add(CekItem("Widget", "record"))
    items.Add(CekItem("count", "variable"))
    items.Add(CekItem("if", "keyword"))

    // keyword(0), variable(1), method(2), property(3), type(4) — and alphabetical, case-insensitively,
    // inside each run, which is why `alpha` precedes `Beta`.
    assert CekNames(CompletionEngineKernels.OrderCompletionItems(items)) == "if,count,alpha,Beta,zeta,Widget"
}

test "the grouped answer arrives collapsed, in rank order, with each group alphabetical" {
    items := new List<CompletionItem>()
    items.Add(CekItem("summary", "property"))
    items.Add(new CompletionItem("Trim", "method", "string", "()", null, false))
    items.Add(new CompletionItem("Trim", "method", "string", "(trimChar char)", null, false))
    items.Add(CekItem("Contains", "method"))

    completions := new Dictionary<string, List<CompletionItem>>()
    CompletionEngineKernels.AddGroupedCompletionItemsByKind(items, completions)

    // METHODS BEFORE PROPERTIES even though a property was produced first: the group order follows
    // the kind rank now, not the order the receiver happened to reflect its members in.
    assert CekGroupOrder(completions) == "methods,properties"
    assert CekNames(completions["methods"]) == "Contains,Trim"
    assert CekNames(completions["properties"]) == "summary"
    assert completions["methods"][1].Overloads == 2
}

test "flattening the groups gives one ordered, duplicate-free list" {
    completions := new Dictionary<string, List<CompletionItem>>()
    methods := new List<CompletionItem>()
    methods.Add(new CompletionItem("Trim", "method", "string", "()", null, false))
    methods.Add(new CompletionItem("Trim", "method", "string", "(trimChar char)", null, false))
    methods.Add(CekItem("Contains", "method"))
    properties := new List<CompletionItem>()
    properties.Add(CekItem("Length", "property"))
    properties.Add(CekItem("Chars", "property"))
    completions["properties"] = properties
    completions["methods"] = methods

    // THE DICTIONARY HANDS THE PROPERTIES OVER FIRST AND THE ANSWER IS STILL METHODS-FIRST: the
    // flatten re-derives the order rather than inheriting whatever order the groups were built in,
    // which is what makes the editor's list independent of how the receiver was reflected.
    flattened := CompletionEngineKernels.FlattenCompletionGroups(completions)
    assert CekNames(flattened) == "Contains,Trim,Chars,Length"
    assert flattened[1].Overloads == 2
    assert flattened[0].Overloads == 1
}

func CekGroupOrder(completions: Dictionary<string, List<CompletionItem>>): string {
    order := ""
    for pair in completions {
        if order.Length > 0 {
            order = order + ","
        }

        order = order + pair.Key
    }

    return order
}
