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
