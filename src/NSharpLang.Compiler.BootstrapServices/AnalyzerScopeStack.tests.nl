namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// Native contracts for the analyzer's lexical scope stack.
//
// Every member here was `private` in Analyzer.cs behind a `Stack<Scope>` field, so no test named any
// of them: their behaviour was pinned only indirectly, through end-to-end diagnostics. This is their
// first DIRECT pinning, and it deliberately pins the parts that read like bookkeeping and are not:
// the LIFO walk order, the two walks that SKIP the innermost scope, the walks that STOP at a scope
// that binds the name under a different meaning, and the lockstep between the lexical scope stack and
// the semantic-scope-id stack.
func ScopeNameList(values: List<string>): string {
    text := ""
    index := 0
    while index < values.Count {
        if index > 0 {
            text = text + ","
        }
        text = text + values[index]
        index = index + 1
    }
    return text
}

func ScopeTypeName(candidate: TypeInfo?): string {
    if candidate == null {
        return "<null>"
    }

    simple := candidate as SimpleTypeInfo
    if simple != null {
        return simple.Name
    }

    nullable := candidate as NullableTypeInfo
    if nullable != null {
        return "nullable(" + ScopeTypeName(nullable.InnerType) + ")"
    }

    return "<other>"
}

// A stack of the given kinds, outermost first, already pushed through the real Push so the semantic
// scopes are opened exactly as production opens them.
func ScopeStackOf(model: SemanticModel, kinds: ScopeKind[]): AnalyzerScopeStack {
    stack := new AnalyzerScopeStack()
    index := 0
    while index < kinds.Length {
        stack.Push(model, new Scope(kinds[index]), index + 1, 1)
        index = index + 1
    }
    return stack
}

func ScopeSymbolOf(name: string): TypeInfo {
    return new SimpleTypeInfo(name)
}

test "the stack is LIFO, and Peek and GlobalScope name the two ends of it" {
    model := new SemanticModel()
    stack := new AnalyzerScopeStack()
    assert stack.Count == 0

    global := new Scope(ScopeKind.Global)
    typeScope := new Scope(ScopeKind.Class)
    body := new Scope(ScopeKind.Function)

    stack.Push(model, global, 1, 1)
    assert stack.Count == 1
    assert Object.ReferenceEquals(stack.Peek(), global)
    assert Object.ReferenceEquals(stack.GlobalScope(), global)

    stack.Push(model, typeScope, 2, 1)
    stack.Push(model, body, 3, 1)
    assert stack.Count == 3

    // The most recently pushed scope is the current one; the FIRST pushed stays the global one.
    assert Object.ReferenceEquals(stack.Peek(), body)
    assert Object.ReferenceEquals(stack.GlobalScope(), global)

    stack.NoteLine(9)
    stack.Pop(model)
    assert stack.Count == 2
    assert Object.ReferenceEquals(stack.Peek(), typeScope)

    stack.Clear()
    assert stack.Count == 0
    assert !stack.HasSemanticScope()
}

test "an empty stack throws for Peek, Pop and GlobalScope exactly as the collections it replaced" {
    model := new SemanticModel()
    stack := new AnalyzerScopeStack()

    // `Stack<Scope>.Peek()` and `.Pop()` threw InvalidOperationException("Stack empty."), and
    // `Enumerable.Last()` threw InvalidOperationException("Sequence contains no elements"). Both the
    // TYPE and the MESSAGE are pinned: a silent change from one exception to another is a behaviour
    // change even on a path production never takes.
    peekThrew := false
    peekMessage := ""
    try {
        stack.Peek()
    } catch ex: Exception {
        invalid := ex as InvalidOperationException
        peekThrew = invalid != null
        peekMessage = ex.Message
    }
    assert peekThrew
    assert peekMessage == "Stack empty."

    popThrew := false
    popMessage := ""
    try {
        stack.NoteLine(1)
        stack.Pop(model)
    } catch ex: Exception {
        invalid := ex as InvalidOperationException
        popThrew = invalid != null
        popMessage = ex.Message
    }
    assert popThrew
    assert popMessage == "Stack empty."

    globalThrew := false
    globalMessage := ""
    try {
        stack.GlobalScope()
    } catch ex: Exception {
        invalid := ex as InvalidOperationException
        globalThrew = invalid != null
        globalMessage = ex.Message
    }
    assert globalThrew
    assert globalMessage == "Sequence contains no elements"
}

test "pushing opens a semantic scope parented to the current one; popping closes it" {
    model := new SemanticModel()
    stack := new AnalyzerScopeStack()

    assert stack.CurrentSemanticScopeId() == -1
    assert !stack.HasSemanticScope()

    stack.Push(model, new Scope(ScopeKind.Global), 1, 1)
    assert stack.HasSemanticScope()
    outerId := stack.CurrentSemanticScopeId()
    assert outerId == 0

    stack.Push(model, new Scope(ScopeKind.Function), 4, 5)
    innerId := stack.CurrentSemanticScopeId()
    assert innerId == 1

    scopes := model.Scopes
    assert scopes.Count == 2
    // The parent of the inner scope is whatever was on top when it opened; the outermost has no parent.
    assert scopes[outerId].ParentId == -1
    assert scopes[innerId].ParentId == outerId
    assert scopes[innerId].StartLine == 4
    assert scopes[innerId].StartColumn == 5

    stack.NoteLine(17)
    stack.Pop(model)
    // A closing scope ends on the analyzer's current line and runs to the end of it.
    assert scopes[innerId].EndLine == 17
    assert scopes[innerId].EndColumn == 2147483647
    assert stack.CurrentSemanticScopeId() == outerId

    // The outer scope is untouched until it is itself popped.
    assert scopes[outerId].EndLine == 0
}

test "name lookups answer from the INNERMOST scope that binds the name" {
    model := new SemanticModel()
    stack := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Class, ScopeKind.Function])

    outer := stack.GlobalScope()
    outer.Symbols["value"] = ScopeSymbolOf("outer-symbol")
    outer.Types["Shape"] = ScopeSymbolOf("outer-type")
    outer.Symbols["only-global"] = ScopeSymbolOf("global-only")

    inner := stack.Peek()
    inner.Symbols["value"] = ScopeSymbolOf("inner-symbol")
    inner.Types["Shape"] = ScopeSymbolOf("inner-type")

    assert ScopeTypeName(stack.LookupSymbol("value")) == "inner-symbol"
    assert ScopeTypeName(stack.LookupType("Shape")) == "inner-type"

    // A name only an enclosing scope has still resolves — the walk does not stop at the innermost.
    assert ScopeTypeName(stack.LookupSymbol("only-global")) == "global-only"
    assert stack.LookupSymbol("missing") == null
    assert stack.LookupType("Missing") == null

    // CurrentScopeSymbol is the innermost scope ALONE: no walk at all.
    assert ScopeTypeName(stack.CurrentScopeSymbol("value")) == "inner-symbol"
    assert stack.CurrentScopeSymbol("only-global") == null
}

test "a type parameter is declared once and is the SAME instance as a type and as a symbol" {
    model := new SemanticModel()
    stack := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Function])

    stack.DeclareTypeParameter("TItem")

    current := stack.Peek()
    asType := current.Types["TItem"]
    asSymbol := current.Symbols["TItem"]
    assert ScopeTypeName(asType) == "TItem"
    assert Object.ReferenceEquals(asType, asSymbol)

    // It is visible to both walks, and only in the scope it was declared in.
    assert ScopeTypeName(stack.LookupType("TItem")) == "TItem"
    assert ScopeTypeName(stack.LookupSymbol("TItem")) == "TItem"
    assert stack.GlobalScope().Types.ContainsKey("TItem") == false
}

test "a nested type declaration does not overwrite a name the scope already binds" {
    model := new SemanticModel()
    stack := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Class])

    stack.DeclareNestedTypeIfAbsent("Inner", ScopeSymbolOf("first"))
    stack.DeclareNestedTypeIfAbsent("Inner", ScopeSymbolOf("second"))
    assert ScopeTypeName(stack.LookupType("Inner")) == "first"

    stack.Peek().Types["Explicit"] = ScopeSymbolOf("declared")
    stack.DeclareNestedTypeIfAbsent("Explicit", ScopeSymbolOf("nested"))
    assert ScopeTypeName(stack.LookupType("Explicit")) == "declared"
}

test "the innermost recorded null fact wins, and a recorded Unknown is not the same as no fact" {
    model := new SemanticModel()
    stack := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Function, ScopeKind.Block])

    stack.GlobalScope().NullStates["value"] = NullState.MaybeNull
    assert stack.HasNullState("value")
    assert stack.NullStateOrUnknown("value") == NullState.MaybeNull

    stack.SetNullStateInCurrentScope("value", NullState.NotNull)
    assert stack.NullStateOrUnknown("value") == NullState.NotNull
    // The outer fact is untouched — it comes back when the narrowing scope closes.
    stack.NoteLine(5)
    stack.Pop(model)
    assert stack.NullStateOrUnknown("value") == NullState.MaybeNull

    // A path recorded AS unknown is present; a path with no fact is absent. Both answer Unknown, so
    // presence is the only thing that tells them apart.
    stack.SetNullStateInCurrentScope("recorded", NullState.Unknown)
    assert stack.HasNullState("recorded")
    assert stack.NullStateOrUnknown("recorded") == NullState.Unknown
    assert !stack.HasNullState("never-seen")
    assert stack.NullStateOrUnknown("never-seen") == NullState.Unknown
}

test "setting a null state refuses an empty stack and a blank path" {
    model := new SemanticModel()
    empty := new AnalyzerScopeStack()
    // No scope to record into, and no throw either.
    empty.SetNullStateInCurrentScope("value", NullState.NotNull)
    assert !empty.HasNullState("value")

    stack := ScopeStackOf(model, [ScopeKind.Global])
    stack.SetNullStateInCurrentScope("   ", NullState.NotNull)
    assert !stack.HasNullState("   ")
    assert stack.Peek().NullStates.Count == 0
}

test "an assignment invalidates the path and its member paths in EVERY open scope" {
    model := new SemanticModel()
    stack := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Function])

    outer := stack.GlobalScope()
    outer.NullStates["order"] = NullState.NotNull
    outer.NullStates["order.customer"] = NullState.NotNull
    outer.NullStates["orders"] = NullState.NotNull

    inner := stack.Peek()
    inner.NullStates["order.customer.name"] = NullState.NotNull
    inner.NullStates["other"] = NullState.NotNull

    stack.InvalidateNullFactsForAssignment("order")

    // The path itself and everything under it goes, in the enclosing scope as well as the current one.
    assert !stack.HasNullState("order")
    assert !stack.HasNullState("order.customer")
    assert !stack.HasNullState("order.customer.name")
    // A name that merely SHARES A PREFIX is not a member path and survives.
    assert stack.HasNullState("orders")
    assert stack.HasNullState("other")
}

test "the nullable ORIGIN of an identifier is looked up in the ENCLOSING scopes only" {
    model := new SemanticModel()
    stack := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Function, ScopeKind.Block])

    declared := new NullableTypeInfo(BuiltInTypes.Int)
    stack.GlobalScope().Symbols["count"] = declared
    // The innermost scope holds the NARROWED type, which is exactly what must be skipped.
    stack.Peek().Symbols["count"] = BuiltInTypes.Int

    origin := stack.FindEnclosingNullableSymbol("count")
    assert origin != null
    assert Object.ReferenceEquals(origin, declared)

    // A scope that binds the name to something NOT nullable does not stop the walk.
    middle := new Scope(ScopeKind.Function)
    middle.Symbols["count"] = BuiltInTypes.String
    stack.Clear()
    stack.Push(model, new Scope(ScopeKind.Global), 1, 1)
    stack.GlobalScope().Symbols["count"] = declared
    stack.Push(model, middle, 2, 1)
    stack.Push(model, new Scope(ScopeKind.Block), 3, 1)
    assert Object.ReferenceEquals(stack.FindEnclosingNullableSymbol("count"), declared)

    // With nothing but the innermost scope there is no enclosing scope to answer from.
    single := new AnalyzerScopeStack()
    single.Push(model, new Scope(ScopeKind.Function), 1, 1)
    single.Peek().Symbols["count"] = declared
    assert single.FindEnclosingNullableSymbol("count") == null
    assert new AnalyzerScopeStack().FindEnclosingNullableSymbol("count") == null
}

test "an error-tuple guard is registered in the current scope, and '_' and blanks are refused" {
    model := new SemanticModel()
    stack := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Function])

    stack.RegisterErrorTupleResult("result", "err", 7, 3)
    guard := stack.FindErrorTupleResultGuard("result")
    assert guard != null
    assert guard.ResultName == "result"
    assert guard.ErrorName == "err"
    assert guard.Line == 7
    assert guard.Column == 3

    stack.RegisterErrorTupleResult("_", "err", 8, 1)
    stack.RegisterErrorTupleResult("  ", "err", 9, 1)
    assert stack.FindErrorTupleResultGuard("_") == null
    assert stack.Peek().ErrorTupleResults.Count == 1

    // The guard dies with the scope that declared it.
    stack.NoteLine(10)
    stack.Pop(model)
    assert stack.FindErrorTupleResultGuard("result") == null
}

test "the guard walk stops at a scope that binds the name as a plain symbol" {
    model := new SemanticModel()
    stack := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Function, ScopeKind.Block])

    stack.GlobalScope().ErrorTupleResults["result"] = new ErrorTupleResultGuard("result", "outerErr", 1, 1)

    // A scope BETWEEN the guard and the use rebinds the name; past that point it is not the guarded
    // result any more, so the outer guard must not be found.
    middleIndexScope := new Scope(ScopeKind.Function)
    middleIndexScope.Symbols["result"] = BuiltInTypes.Int

    shadowed := new AnalyzerScopeStack()
    shadowed.Push(model, stack.GlobalScope(), 1, 1)
    shadowed.Push(model, middleIndexScope, 2, 1)
    shadowed.Push(model, new Scope(ScopeKind.Block), 3, 1)
    assert shadowed.FindErrorTupleResultGuard("result") == null

    // Without the rebinding the same guard IS visible.
    assert stack.FindErrorTupleResultGuard("result") != null
}

test "proving an error null marks its results available in the CURRENT scope" {
    model := new SemanticModel()
    stack := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Function])

    stack.GlobalScope().ErrorTupleResults["value"] = new ErrorTupleResultGuard("value", "err", 1, 1)
    stack.GlobalScope().ErrorTupleResults["other"] = new ErrorTupleResultGuard("other", "otherErr", 1, 1)

    assert !stack.IsErrorTupleResultAvailable("value")

    stack.MarkErrorTupleResultsAvailableForError("err")
    assert stack.IsErrorTupleResultAvailable("value")
    // A result guarded by a DIFFERENT error is untouched.
    assert !stack.IsErrorTupleResultAvailable("other")

    // The mark landed in the innermost scope, not in the scope holding the guard, so it dies with the
    // branch that established it.
    assert stack.Peek().AvailableErrorTupleResults.Contains("value")
    assert !stack.GlobalScope().AvailableErrorTupleResults.Contains("value")
    stack.NoteLine(4)
    stack.Pop(model)
    assert !stack.IsErrorTupleResultAvailable("value")

    // Dotted, blank and empty-stack calls are refused outright.
    stack.MarkErrorTupleResultsAvailableForError("err.inner")
    stack.MarkErrorTupleResultsAvailableForError("   ")
    assert !stack.IsErrorTupleResultAvailable("value")
    emptyMark := new AnalyzerScopeStack()
    emptyMark.MarkErrorTupleResultsAvailableForError("err")
}

test "availability is decided by whichever fact the walk meets first" {
    model := new SemanticModel()

    // A name no scope knows about is available: it is not a guarded result at all.
    bare := ScopeStackOf(model, [ScopeKind.Global])
    assert bare.IsErrorTupleResultAvailable("anything")

    // A plain symbol binding INSIDE the guard answers available, because the name is no longer the
    // guarded result.
    rebound := new AnalyzerShadowProbe(model).ReboundStack()
    assert rebound.IsErrorTupleResultAvailable("result")

    // An availability mark in an inner scope wins over the guard in an outer one.
    marked := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Function])
    marked.GlobalScope().ErrorTupleResults["result"] = new ErrorTupleResultGuard("result", "err", 1, 1)
    assert !marked.IsErrorTupleResultAvailable("result")
    marked.Peek().AvailableErrorTupleResults.Add("result")
    assert marked.IsErrorTupleResultAvailable("result")
}

test "assigning over a guarded result makes it available; other targets are ignored" {
    model := new SemanticModel()
    stack := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Function])
    stack.Peek().ErrorTupleResults["result"] = new ErrorTupleResultGuard("result", "err", 1, 1)
    assert !stack.IsErrorTupleResultAvailable("result")

    stack.MarkErrorTupleResultAvailableAfterAssignment(new IdentifierExpression("result", 1, 1))
    assert stack.IsErrorTupleResultAvailable("result")

    // An identifier that is not a guarded result changes nothing, and a non-identifier target is not
    // a name at all.
    stack.MarkErrorTupleResultAvailableAfterAssignment(new IdentifierExpression("unrelated", 1, 1))
    assert !stack.Peek().AvailableErrorTupleResults.Contains("unrelated")
    stack.MarkErrorTupleResultAvailableAfterAssignment(new ThisExpression(1, 1))
    emptyAssign := new AnalyzerScopeStack()
    emptyAssign.MarkErrorTupleResultAvailableAfterAssignment(new IdentifierExpression("result", 1, 1))
}

test "shadowing looks past the current scope and stops dead at a type boundary" {
    model := new SemanticModel()
    stack := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Function, ScopeKind.Block])
    globalScope := stack.GlobalScope()
    globalScope.Symbols["total"] = BuiltInTypes.Int

    // The global scope is not a Function/Block scope, so the walk stops before it: a global of the
    // same name is not shadowing.
    assert !stack.ShadowsEnclosingValueBinding("total", BuiltInTypes.Int)

    // An enclosing FUNCTION local of the same name is.
    functionScope := new AnalyzerScopeStack()
    functionScope.Push(model, new Scope(ScopeKind.Function), 1, 1)
    outerBody := functionScope.Peek()
    outerBody.Symbols["total"] = BuiltInTypes.Int
    functionScope.Push(model, new Scope(ScopeKind.Block), 2, 1)
    assert functionScope.ShadowsEnclosingValueBinding("total", BuiltInTypes.String)

    // A class scope between the two ends the walk.
    interrupted := new AnalyzerScopeStack()
    interrupted.Push(model, new Scope(ScopeKind.Function), 1, 1)
    interruptedBody := interrupted.Peek()
    interruptedBody.Symbols["total"] = BuiltInTypes.Int
    interrupted.Push(model, new Scope(ScopeKind.Class), 2, 1)
    interrupted.Push(model, new Scope(ScopeKind.Block), 3, 1)
    assert !interrupted.ShadowsEnclosingValueBinding("total", BuiltInTypes.String)
}

test "shadowing refuses underscore names, the two reserved names, functions and non-local scopes" {
    model := new SemanticModel()
    stack := new AnalyzerScopeStack()
    stack.Push(model, new Scope(ScopeKind.Function), 1, 1)
    body := stack.Peek()
    body.Symbols["_total"] = BuiltInTypes.Int
    body.Symbols["total"] = BuiltInTypes.Int
    body.Symbols["this"] = BuiltInTypes.Int
    body.Symbols["value"] = BuiltInTypes.Int
    stack.Push(model, new Scope(ScopeKind.Block), 2, 1)

    // Deliberate discards opt out of the rule.
    assert !stack.ShadowsEnclosingValueBinding("_", BuiltInTypes.Int)
    assert !stack.ShadowsEnclosingValueBinding("_total", BuiltInTypes.Int)
    assert stack.ShadowsEnclosingValueBinding("total", BuiltInTypes.Int)

    // `this` and `value` are not value bindings at all, so they can neither shadow nor be shadowed.
    assert !stack.ShadowsEnclosingValueBinding("this", BuiltInTypes.Int)
    assert !stack.ShadowsEnclosingValueBinding("value", BuiltInTypes.Int)

    // A FUNCTION declaration is not a value binding either — overloads are not shadowing.
    functionDeclaration := new FunctionTypeInfo()
    functionDeclaration.SourceName = "total"
    assert !stack.ShadowsEnclosingValueBinding("total", functionDeclaration)

    // A name the current scope also binds as a TYPE is a type declaration, not a local.
    typeBound := stack.Peek()
    typeBound.Types["total"] = ScopeSymbolOf("Total")
    assert !stack.ShadowsEnclosingValueBinding("total", BuiltInTypes.Int)

    // A declaration in a CLASS scope is a member, not a local, so it cannot shadow.
    inType := new AnalyzerScopeStack()
    inType.Push(model, new Scope(ScopeKind.Function), 1, 1)
    inTypeBody := inType.Peek()
    inTypeBody.Symbols["total"] = BuiltInTypes.Int
    inType.Push(model, new Scope(ScopeKind.Class), 2, 1)
    assert !inType.ShadowsEnclosingValueBinding("total", BuiltInTypes.Int)

    assert !new AnalyzerScopeStack().ShadowsEnclosingValueBinding("total", BuiltInTypes.Int)
}

test "'this' in the innermost binding scope is the current type, and it drives member reference" {
    model := new SemanticModel()
    stack := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Class, ScopeKind.Function])
    assert stack.CurrentTypeScope() == null

    owner := ScopeSymbolOf("Widget")
    outerScope := stack.GlobalScope()
    outerScope.Symbols["this"] = ScopeSymbolOf("Outer")
    // The innermost binding of `this` wins.
    currentScope := stack.Peek()
    currentScope.Symbols["this"] = owner
    assert Object.ReferenceEquals(stack.CurrentTypeScope(), owner)
}

test "a bare 'this' outside every type scope is worth the no-information type, not a null" {
    model := new SemanticModel()

    // No scope binds `this`: the answer is Unknown rather than the null the nullable door gives.
    outside := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Function])
    assert outside.CurrentTypeScope() == null
    assert BuiltInTypes.IsUnknown(outside.CurrentTypeScopeOrUnknown())

    // An empty stack answers the same way, and asking is never an error.
    assert BuiltInTypes.IsUnknown(new AnalyzerScopeStack().CurrentTypeScopeOrUnknown())

    // When a type scope IS open, the two doors answer with the SAME instance.
    owner := ScopeSymbolOf("Widget")
    inside := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Class])
    inside.Peek().Symbols["this"] = owner
    assert Object.ReferenceEquals(inside.CurrentTypeScopeOrUnknown(), owner)
    assert Object.ReferenceEquals(inside.CurrentTypeScopeOrUnknown(), inside.CurrentTypeScope())
}

test "a member reference is decided by the scope the walk STOPS at" {
    model := new SemanticModel()

    // A local in a function scope is not a member reference.
    local := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Class, ScopeKind.Function])
    local.Peek().Symbols["this"] = ScopeSymbolOf("Widget")
    local.Peek().Symbols["count"] = BuiltInTypes.Int
    assert !local.IsCurrentTypeMemberReference("count")

    // A name bound in the CLASS scope is.
    fieldOwner := new AnalyzerScopeStack()
    fieldOwner.Push(model, new Scope(ScopeKind.Class), 1, 1)
    fieldOwner.Peek().Symbols["count"] = BuiltInTypes.Int
    fieldOwner.Push(model, new Scope(ScopeKind.Function), 2, 1)
    fieldOwner.Peek().Symbols["this"] = ScopeSymbolOf("Widget")
    assert fieldOwner.IsCurrentTypeMemberReference("count")

    // A name NOTHING binds is a member reference exactly when there is a current type at all: the
    // walk stops at the first type-level scope and answers from `this`.
    unbound := new AnalyzerScopeStack()
    unbound.Push(model, new Scope(ScopeKind.Class), 1, 1)
    unbound.Push(model, new Scope(ScopeKind.Function), 2, 1)
    unbound.Peek().Symbols["this"] = ScopeSymbolOf("Widget")
    assert unbound.IsCurrentTypeMemberReference("missing")

    noType := ScopeStackOf(model, [ScopeKind.Function])
    assert !noType.IsCurrentTypeMemberReference("missing")
    assert !new AnalyzerScopeStack().IsCurrentTypeMemberReference("missing")
}

test "a type-reference binding is recorded from the innermost scope that binds the name" {
    model := new SemanticModel()
    bindings := new BindingMap()
    stack := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Function])

    outer := stack.GlobalScope()
    outer.Types["Shape"] = ScopeSymbolOf("outer")
    outer.RecordDeclarationLocation("Shape", "outer.nl", 3, 5, "class")

    stack.RecordTypeBinding(bindings, "use.nl", "Shape", 20, 9)
    assert bindings.BindingCount == 1
    declarations := bindings.AllDeclarations
    assert declarations.Count == 1
    assert declarations[0].File == "outer.nl"
    assert declarations[0].Line == 3

    // A nearer scope that binds the name WITHOUT a declaration location ends the walk in silence: it
    // does not fall through to the outer declaration.
    stack.Peek().Types["Shape"] = ScopeSymbolOf("inner")
    stack.RecordTypeBinding(bindings, "use.nl", "Shape", 21, 9)
    assert bindings.BindingCount == 1

    // A name no scope binds records nothing.
    stack.RecordTypeBinding(bindings, "use.nl", "Missing", 22, 9)
    assert bindings.BindingCount == 1
}

test "an identifier binds to a SYMBOL before a TYPE of the same name, and records where it came from" {
    model := new SemanticModel()
    bindings := new BindingMap()
    stack := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Function])

    outer := stack.GlobalScope()
    outer.Symbols["Shape"] = ScopeSymbolOf("as-symbol")
    outer.Types["Shape"] = ScopeSymbolOf("as-type")
    outer.RecordDeclarationLocation("Shape", "decl.nl", 11, 2, "variable")

    assert ScopeTypeName(stack.ResolveBindingTarget(bindings, "use.nl", "Shape", 30, 4)) == "as-symbol"
    assert bindings.BindingCount == 1

    // With no symbol of that name the TYPE walk answers.
    typeOnly := ScopeStackOf(model, [ScopeKind.Global])
    typeOnly.GlobalScope().Types["Shape"] = ScopeSymbolOf("as-type")
    assert ScopeTypeName(typeOnly.ResolveBindingTarget(bindings, "use.nl", "Shape", 31, 4)) == "as-type"

    // Nothing bound anywhere is a null answer, and the caller decides what that means.
    assert typeOnly.ResolveBindingTarget(bindings, "use.nl", "Missing", 32, 4) == null
}

test "type names in scope come out innermost first, which is the suggestion tie-breaker" {
    model := new SemanticModel()
    stack := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Function])

    outer := stack.GlobalScope()
    outer.Types["Alpha"] = ScopeSymbolOf("a")
    outer.Types["Beta"] = ScopeSymbolOf("b")

    inner := stack.Peek()
    inner.Types["Gamma"] = ScopeSymbolOf("g")

    assert ScopeNameList(stack.AllTypeNamesInScope()) == "Gamma,Alpha,Beta"
    assert ScopeNameList(new AnalyzerScopeStack().AllTypeNamesInScope()) == ""
}

test "variable suggestions come from every symbol in scope" {
    model := new SemanticModel()
    stack := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Function])
    stack.GlobalScope().Symbols["counter"] = BuiltInTypes.Int
    stack.Peek().Symbols["counted"] = BuiltInTypes.Int

    suggestions := stack.SuggestSimilarVariableNames("countr")
    assert suggestions.Count > 0
    assert suggestions[0] == "counted" || suggestions[0] == "counter"

    // A name nothing resembles gets no suggestion.
    assert stack.SuggestSimilarVariableNames("zzzzzzzz").Count == 0
}

test "callable suggestions take only callable symbols, plus extension methods, deduplicated" {
    model := new SemanticModel()
    stack := ScopeStackOf(model, [ScopeKind.Global, ScopeKind.Function])

    callable := new FunctionTypeInfo()
    callable.SourceName = "Compute"
    globalScope := stack.GlobalScope()
    globalScope.Symbols["Compute"] = callable
    // A non-callable symbol of a near-identical name must NOT be suggested as a function.
    globalScope.Symbols["Computed"] = BuiltInTypes.Int

    extensions := new List<string>()
    extensions.Add("Compute")
    extensions.Add("Commute")

    suggestions := stack.SuggestSimilarCallableNames("Comptue", extensions)

    // "Compute" is both a scope symbol and an extension method; it appears ONCE. "Computed" is a
    // symbol but not a callable one, so it is not a candidate at all.
    computeCount := 0
    computedCount := 0
    index := 0
    while index < suggestions.Count {
        if suggestions[index] == "Compute" {
            computeCount = computeCount + 1
        }
        if suggestions[index] == "Computed" {
            computedCount = computedCount + 1
        }
        index = index + 1
    }
    assert computeCount == 1
    assert computedCount == 0
}

// A guarded result that an inner scope rebinds as a plain symbol: available, because past the
// rebinding the name is no longer the result.
class AnalyzerShadowProbe {
    model: SemanticModel

    constructor(semanticModel: SemanticModel) {
        model = semanticModel
    }

    func ReboundStack(): AnalyzerScopeStack {
        stack := new AnalyzerScopeStack()
        outer := new Scope(ScopeKind.Global)
        outer.ErrorTupleResults["result"] = new ErrorTupleResultGuard("result", "err", 1, 1)
        stack.Push(model, outer, 1, 1)

        rebinding := new Scope(ScopeKind.Function)
        rebinding.Symbols["result"] = BuiltInTypes.Int
        stack.Push(model, rebinding, 2, 1)
        return stack
    }
}
