namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// CONTRACTS FOR THE LINT WALK'S STATE (task 019 slice 10). These are the semantic assertions that
// came out of `Linter.cs` with nineteen private fields and nineteen members: the scope stack, the
// parameter frames, the import and identifier ledgers, and the whole reporting spine.
//
// THE STATE WAS UNTESTABLE BEFORE THE MOVE, AND THAT IS THE POINT. Every one of these fields was a
// private of an `internal` visitor reachable only by running a whole lint over a parsed file, so a
// scope rule could only be asserted through the diagnostic it eventually produced. Below, each rule
// is asked directly: push a scope, declare a name, read it from three frames down, and ask what the
// state now says.
//
// FOUR THINGS THAT WERE PROSE, A COINCIDENCE OR UNREACHABLE ARE STATED HERE AS CONTRACTS:
//   (a) the span fork in `AddDiagnostic` — `span.Column == location.Column ? location : location
//       with { Column = span.Column }` — could not decide anything, because both arms produce the
//       same location. The equivalence is asserted over columns that resolve BOTH ways.
//   (b) NL004's `var needsAwait = true; if (needsAwait)` was a guard with nothing between the write
//       and the test. The three conditions that actually select the rule are asserted instead.
//   (c) the parameter-frame walk's two halves — "the resolved scope IS this frame's scope" and
//       "this frame declares the name" — are BOTH load-bearing, and each is asserted alone.
//   (d) `PopScope` on an empty stack reports NOTHING, where a pop that restores also reports. The
//       asymmetry is deliberate and is asserted, because it is what stops an unbalanced walk from
//       double-reporting NL001.
func LwsConfig(): LinterConfig {
    return LinterConfig.Default()
}

func LwsConfigWithout(ruleCode: string): LinterConfig {
    config := LinterConfig.Default()
    removed: object = 0
    config.RuleSeverities.Remove(ruleCode, out removed)
    return config
}

func LwsState(): LinterWalkState {
    return new LinterWalkState("test.nl", null, LwsConfig())
}

func LwsStateWithSource(source: string): LinterWalkState {
    return new LinterWalkState("test.nl", source, LwsConfig())
}

func LwsCodes(state: LinterWalkState): string {
    codes := ""
    for diagnostic in state.Diagnostics {
        codes = codes + diagnostic.Code + "@" + diagnostic.Location.Line.ToString() + ":" + diagnostic.Location.Column.ToString() + ";"
    }

    return codes
}

func LwsSpans(state: LinterWalkState): string {
    spans := ""
    for diagnostic in state.Diagnostics {
        spans = spans + diagnostic.Code + "@" + diagnostic.Location.Line.ToString() + ":" + diagnostic.Location.Column.ToString() + "+" + diagnostic.Length.ToString() + ";"
    }

    return spans
}

func LwsSimpleType(name: string): SimpleTypeReference {
    return new SimpleTypeReference(name, 1, 1)
}

// A type reference the parser never stamped, which is what a hand-built or synthesised tree looks
// like. `NameSpan` folds a zero line or column to `SourceSpan.None`, so this is the shape that
// exercises the caller-position fallback rather than the reference's own span.
func LwsPositionlessType(name: string): SimpleTypeReference {
    return new SimpleTypeReference(name, 0, 0)
}

func LwsIdentifier(name: string, line: int, column: int): IdentifierExpression {
    return new IdentifierExpression(name, line, column)
}

func LwsField(name: string): FieldDeclaration {
    return new FieldDeclaration(name, LwsSimpleType("int"), null, Modifiers.None, PropertyModifier.None, new List<AttributeNode>(), 1, 1)
}

func LwsProperty(name: string): PropertyDeclaration {
    return new PropertyDeclaration(name, LwsSimpleType("int"), null, null, null, Modifiers.None, PropertyModifier.None, new List<AttributeNode>(), 1, 1)
}

func LwsParameter(name: string, typeName: string): Parameter {
    return new Parameter(name, LwsSimpleType(typeName), null, false, ParameterModifier.None, null, 1, 1, false, null)
}

func LwsMembers(names: string[]): List<Declaration> {
    members := new List<Declaration>()
    index := 0
    while index < names.Length {
        members.Add(LwsField(names[index]))
        index = index + 1
    }

    return members
}

func LwsUnit(namespaceImports: string[], fileImports: string[]): CompilationUnit {
    imports := new List<ImportDirective>()
    index := 0
    while index < namespaceImports.Length {
        imports.Add(new ImportDirective(namespaceImports[index], null, index + 1, 1))
        index = index + 1
    }

    files := new List<Statement>()
    fileIndex := 0
    while fileIndex < fileImports.Length {
        files.Add(new FileImport(fileImports[fileIndex], null, 20 + fileIndex, 1))
        fileIndex = fileIndex + 1
    }

    return new CompilationUnit(null, imports, files, null, new List<Declaration>(), 1, 1)
}

// The shape a function walk opens: a fresh scope, the parameters declared into it and marked as
// binding sites, and the scope recorded against the frame.
func LwsOpenFunction(state: LinterWalkState, names: string[]): LinterFunctionFrame {
    frame := state.EnterFunction(false)
    state.PushScope()
    index := 0
    while index < names.Length {
        state.DeclareVariable(names[index], 10 + index, 5)
        state.MarkVariableUsed(names[index], false)
        state.AddParameter(names[index], 10 + index, 5)
        index = index + 1
    }

    state.RecordParameterScope()
    return frame
}

// ── the lexical scopes ───────────────────────────────────────────────────────────────────────

test "a declared name is unread until something reads it" {
    state := LwsState()
    state.PushScope()
    state.DeclareVariable("value", 3, 5)
    state.PopScope()
    assert LwsCodes(state) == "NL001@3:5;"
}

test "a read silences NL001" {
    state := LwsState()
    state.PushScope()
    state.DeclareVariable("value", 3, 5)
    state.MarkVariableUsed("value", true)
    state.PopScope()
    assert state.Diagnostics.Count == 0
}

test "a read from THREE scopes in marks the binding, not a copy of it" {
    state := LwsState()
    state.PushScope()
    state.DeclareVariable("outer", 3, 5)
    state.PushScope()
    state.PushScope()
    state.MarkVariableUsed("outer", true)
    state.PopScope()
    state.PopScope()
    state.PopScope()
    assert state.Diagnostics.Count == 0
}

test "the innermost binding of a name is the one a read marks" {
    // Both frames declare `value`; the read happens inside the inner one, so only the OUTER binding
    // is still unread when the walk finishes.
    state := LwsState()
    state.PushScope()
    state.DeclareVariable("value", 3, 5)
    state.PushScope()
    state.DeclareVariable("value", 7, 9)
    state.MarkVariableUsed("value", true)
    state.PopScope()
    state.PopScope()

    // The file-wide used-name set is deliberately coarser than the scope, so the OUTER binding is
    // silenced too — this states the behaviour rather than wishing it away. What is left is NL020,
    // because the inner declaration shadows the outer one.
    assert LwsCodes(state) == "NL020@7:9;"
}

test "a name read nowhere in the file is reported once per binding" {
    state := LwsState()
    state.PushScope()
    state.DeclareVariable("a", 3, 5)
    state.PushScope()
    state.DeclareVariable("b", 7, 9)
    state.PopScope()
    state.PopScope()
    assert LwsCodes(state) == "NL001@7:9;NL001@3:5;"
}

test "PopScope on an empty stack reports NOTHING" {
    // (d) The guard is not bookkeeping. A pop with nothing to restore also skips the report, which
    // is what keeps an unbalanced walk from reporting the same frame twice.
    state := LwsState()
    state.DeclareVariable("value", 3, 5)
    state.PopScope()
    assert state.Diagnostics.Count == 0

    // Non-vacuity: the same declaration reported through a balanced pop.
    balanced := LwsState()
    balanced.PushScope()
    balanced.DeclareVariable("value", 3, 5)
    balanced.PopScope()
    assert balanced.Diagnostics.Count == 1
}

test "an underscore-prefixed name is never reported unused" {
    state := LwsState()
    state.PushScope()
    state.DeclareVariable("_ignored", 3, 5)
    state.PopScope()
    assert state.Diagnostics.Count == 0
}

test "NL020 fires from DeclareVariable when an enclosing scope already binds the name" {
    state := LwsState()
    state.PushScope()
    state.DeclareVariable("value", 1, 1)
    state.PushScope()
    state.DeclareVariable("value", 4, 9)
    assert LwsCodes(state) == "NL020@4:9;"
}

test "NL020 does NOT fire for a redeclaration in the SAME scope" {
    state := LwsState()
    state.PushScope()
    state.DeclareVariable("value", 1, 1)
    state.DeclareVariable("value", 4, 9)
    assert state.Diagnostics.Count == 0
}

// ── the parameter frames ─────────────────────────────────────────────────────────────────────

test "an unread parameter is NL012" {
    state := LwsState()
    frame := LwsOpenFunction(state, ["unused"])
    state.CheckUnusedParameters("f")
    state.PopScope()
    state.ExitFunction(frame)
    assert LwsCodes(state) == "NL012@10:5;"
}

test "a read parameter is silent" {
    state := LwsState()
    frame := LwsOpenFunction(state, ["used"])
    state.MarkVariableUsed("used", true)
    state.CheckUnusedParameters("f")
    state.PopScope()
    state.ExitFunction(frame)
    assert state.Diagnostics.Count == 0
}

test "a CAPTURED parameter read inside a nested function counts as read" {
    // The build-blocking false positive this rule exists to avoid: a lambda or local function that
    // only reads an enclosing parameter must not leave that parameter looking unread.
    state := LwsState()
    outer := LwsOpenFunction(state, ["captured"])
    inner := LwsOpenFunction(state, [])
    state.MarkVariableUsed("captured", true)
    state.PopScope()
    state.ExitFunction(inner)

    state.CheckUnusedParameters("outer")
    state.PopScope()
    state.ExitFunction(outer)
    assert state.Diagnostics.Count == 0
}

test "a SHADOWING local in the nested scope does NOT credit the enclosing parameter" {
    // (c) The scope half of the frame walk. The read resolves to the inner declaration, whose scope
    // is not the outer function's parameter scope, so nothing is credited.
    state := LwsState()
    outer := LwsOpenFunction(state, ["shadowed"])
    inner := LwsOpenFunction(state, [])
    state.DeclareVariable("shadowed", 30, 3)
    state.MarkVariableUsed("shadowed", true)
    state.PopScope()
    state.ExitFunction(inner)

    state.CheckUnusedParameters("outer")
    state.PopScope()
    state.ExitFunction(outer)
    assert LwsCodes(state) == "NL020@30:3;NL012@10:5;"
}

test "the frame's NAME half is load-bearing too" {
    // (c) The other half. The read resolves to the function's own parameter scope, but the name is
    // a local declared into that same scope rather than a parameter, so no parameter is credited.
    state := LwsState()
    frame := LwsOpenFunction(state, ["p"])
    state.DeclareVariable("local", 12, 3)
    state.MarkVariableUsed("local", true)
    state.CheckUnusedParameters("f")
    state.PopScope()
    state.ExitFunction(frame)
    assert LwsCodes(state) == "NL012@10:5;"
}

test "a BINDING site credits only the current function's parameter table" {
    // `creditEnclosingParameter: false` is what a parameter, loop variable, catch variable or lambda
    // parameter uses when it is introduced. Re-declaring an enclosing parameter's name never marks
    // that enclosing parameter as read.
    state := LwsState()
    outer := LwsOpenFunction(state, ["name"])
    inner := LwsOpenFunction(state, [])
    state.DeclareVariable("name", 30, 3)
    state.MarkVariableUsed("name", false)
    state.PopScope()
    state.ExitFunction(inner)

    state.CheckUnusedParameters("outer")
    state.PopScope()
    state.ExitFunction(outer)
    assert LwsCodes(state) == "NL020@30:3;NL012@10:5;"
}

test "the enclosing function's frame is restored by ExitFunction" {
    state := LwsState()
    outer := LwsOpenFunction(state, ["outerParam"])
    inner := LwsOpenFunction(state, ["innerParam"])
    state.PopScope()
    state.ExitFunction(inner)

    // Back in the outer function: its own parameter is the one NL012 asks about.
    state.CheckUnusedParameters("outer")
    state.PopScope()
    state.ExitFunction(outer)
    assert LwsCodes(state) == "NL012@10:5;"
}

test "NL012 is silent unless its code is in the severity table" {
    state := new LinterWalkState("test.nl", null, LwsConfigWithout("NL012"))
    frame := LwsOpenFunction(state, ["unused"])
    state.CheckUnusedParameters("f")
    state.PopScope()
    state.ExitFunction(frame)
    assert state.Diagnostics.Count == 0
}

// ── NL004, and the guard that could not decide anything ──────────────────────────────────────

func LwsFunction(name: string, isAsync: bool, hasBlockBody: bool): FunctionDeclaration {
    body: BlockStatement? = null
    if hasBlockBody {
        body = new BlockStatement(new List<Statement>(), 1, 1)
    }

    modifiers := Modifiers.None
    if isAsync {
        modifiers = Modifiers.Async
    }

    return new FunctionDeclaration(name, new List<Parameter>(), null, body, null, null, null, modifiers, new List<AttributeNode>(), false, null, false, false, 7, 1)
}

test "an async function with a block body and no await is NL004" {
    // (b) The three conditions that actually select the rule.
    state := LwsState()
    frame := state.EnterFunction(true)
    state.CheckAsyncWithoutAwait(LwsFunction("f", true, true))
    state.ExitFunction(frame)
    assert LwsCodes(state) == "NL004@7:1;"
}

test "an await anywhere in the function silences NL004" {
    state := LwsState()
    frame := state.EnterFunction(true)
    state.NoteAwait()
    state.CheckAsyncWithoutAwait(LwsFunction("f", true, true))
    state.ExitFunction(frame)
    assert state.Diagnostics.Count == 0
}

test "a non-async function is never NL004" {
    state := LwsState()
    frame := state.EnterFunction(false)
    state.CheckAsyncWithoutAwait(LwsFunction("f", false, true))
    state.ExitFunction(frame)
    assert state.Diagnostics.Count == 0
}

test "an EXPRESSION-bodied async function is deliberately not reported" {
    state := LwsState()
    frame := state.EnterFunction(true)
    state.CheckAsyncWithoutAwait(LwsFunction("f", true, false))
    state.ExitFunction(frame)
    assert state.Diagnostics.Count == 0
}

test "the await flag belongs to the INNERMOST function and is restored on exit" {
    state := LwsState()
    outer := state.EnterFunction(true)
    inner := state.EnterFunction(true)
    state.NoteAwait()
    state.CheckAsyncWithoutAwait(LwsFunction("inner", true, true))
    state.ExitFunction(inner)

    // The inner function's await must not silence the outer one.
    state.CheckAsyncWithoutAwait(LwsFunction("outer", true, true))
    state.ExitFunction(outer)
    assert LwsCodes(state) == "NL004@7:1;"
}

test "an async function's implicit Task usage is recorded as a code identifier" {
    state := LwsState()
    state.RegisterImports(LwsUnit(["System.Threading.Tasks"], []))
    frame := state.EnterFunction(true)
    state.ExitFunction(frame)
    state.CheckUnusedImports()
    assert state.Diagnostics.Count == 0

    // Non-vacuity: without the async function the same import is unused.
    idle := LwsState()
    idle.RegisterImports(LwsUnit(["System.Threading.Tasks"], []))
    idle.CheckUnusedImports()
    assert idle.Diagnostics.Count == 1
}

// ── the import and identifier ledgers ────────────────────────────────────────────────────────

test "an import nothing mentions is NL010" {
    state := LwsState()
    state.RegisterImports(LwsUnit(["System.Text"], []))
    state.CheckUnusedImports()
    assert LwsCodes(state) == "NL010@1:1;"
}

test "an identifier the code mentions makes its import used" {
    state := LwsState()
    state.RegisterImports(LwsUnit(["System.Text"], []))
    state.NoteCodeIdentifier("StringBuilder")
    state.CheckUnusedImports()
    assert state.Diagnostics.Count == 0
}

test "a member access makes an extension-method namespace used" {
    state := LwsState()
    state.RegisterImports(LwsUnit(["System.Linq"], []))
    state.NoteMemberAccessName("Select")
    state.CheckUnusedImports()
    assert state.Diagnostics.Count == 0
}

test "a written type reference mentions every name in it" {
    state := LwsState()
    state.RegisterImports(LwsUnit(["System.Collections.Generic"], []))
    arguments := new List<TypeReference>()
    arguments.Add(LwsSimpleType("string"))
    listOfString := new GenericTypeReference("List", arguments, 1, 1)
    state.TrackTypeReference(listOfString)
    state.CheckUnusedImports()
    assert state.Diagnostics.Count == 0
}

test "NL010 is silent unless its code is in the severity table" {
    state := new LinterWalkState("test.nl", null, LwsConfigWithout("NL010"))
    state.RegisterImports(LwsUnit(["System.Text"], []))
    state.CheckUnusedImports()
    assert state.Diagnostics.Count == 0
}

test "a file import whose target cannot be read is treated as USED" {
    // The linter refuses to report what it cannot verify: with no file on disk to extract exported
    // symbols from, the import stands. This is the file arm's behaviour and not an accident of the
    // fixture, so it is asserted rather than avoided.
    state := LwsState()
    state.RegisterImports(LwsUnit([], ["helpers.nl"]))
    state.CheckUnusedImports()
    assert state.Diagnostics.Count == 0

    // Non-vacuity: a namespace import registered by the same call IS reported.
    both := LwsState()
    both.RegisterImports(LwsUnit(["System.Text"], ["helpers.nl"]))
    both.CheckUnusedImports()
    assert LwsCodes(both) == "NL010@1:1;"
}

test "NL002 fires for a bare name that needs an import" {
    state := LwsState()
    state.CheckMissingImport(LwsIdentifier("StringBuilder", 5, 9))
    assert LwsCodes(state) == "NL002@5:9;"
}

test "an imported namespace silences NL002" {
    state := LwsState()
    state.RegisterImports(LwsUnit(["System.Text"], []))
    state.CheckMissingImport(LwsIdentifier("StringBuilder", 5, 9))
    assert state.Diagnostics.Count == 0
}

test "a TYPE-MEMBER name is not a missing import" {
    state := LwsState()
    state.PushTypeMemberScope(LwsMembers(["StringBuilder"]), null)
    state.CheckMissingImport(LwsIdentifier("StringBuilder", 5, 9))
    state.PopTypeMemberScope()
    assert state.Diagnostics.Count == 0
}

test "the type-member scope is POPPED, so the name stops silencing outside the type" {
    state := LwsState()
    state.PushTypeMemberScope(LwsMembers(["StringBuilder"]), null)
    state.PopTypeMemberScope()
    state.CheckMissingImport(LwsIdentifier("StringBuilder", 5, 9))
    assert LwsCodes(state) == "NL002@5:9;"
}

test "a property name counts as a type member" {
    state := LwsState()
    members := new List<Declaration>()
    members.Add(LwsProperty("StringBuilder"))
    state.PushTypeMemberScope(members, null)
    state.CheckMissingImport(LwsIdentifier("StringBuilder", 5, 9))
    state.PopTypeMemberScope()
    assert state.Diagnostics.Count == 0
}

test "a positional parameter is a member name AND its declared type is an import usage" {
    state := LwsState()
    state.RegisterImports(LwsUnit(["System.Text"], []))
    parameters := new List<Parameter>()
    parameters.Add(LwsParameter("Name", "StringBuilder"))
    state.PushTypeMemberScope(new List<Declaration>(), parameters)
    state.CheckMissingImport(LwsIdentifier("Name", 5, 9))
    state.PopTypeMemberScope()
    state.CheckUnusedImports()
    assert state.Diagnostics.Count == 0
}

test "NL002 for a written type reference asks about the BASE name" {
    state := LwsState()
    state.CheckMissingImportForType(LwsSimpleType("StringBuilder"), 6, 3)
    assert LwsCodes(state) == "NL002@1:1;"
}

test "the NL002 span is the TYPE REFERENCE'S OWN, and the caller's position is only a fallback" {
    // The reference wins. `LwsSimpleType` stamps line 1 column 1 and the caller offers 6:3; the
    // report lands on the reference, covering exactly the thirteen columns of `StringBuilder`.
    // This is the whole of the anchoring fix stated at the owner: the caller of
    // `CheckMissingImportForType` points at the syntax that ENCLOSES the type (`new`), and the
    // message is about the type, so the position the message is about has to win.
    stamped := LwsState()
    stamped.CheckMissingImportForType(LwsSimpleType("StringBuilder"), 6, 3)
    assert LwsSpans(stamped) == "NL002@1:1+13;"

    // The fallback, and it is not decoration: a hand-built or synthesised type reference carries no
    // position at all, and dropping the caller's would put the diagnostic at 0:0.
    positionless := LwsState()
    positionless.CheckMissingImportForType(LwsPositionlessType("StringBuilder"), 6, 3)
    assert LwsSpans(positionless) == "NL002@6:3+1;"
}

test "EVERY name a written type mentions is asked about, not only the one it is CALLED" {
    // `Dictionary<string, StringBuilder>` needs two imports and is two findings, each on its own
    // columns. The base name leads, because that is the order `NamedReferences` yields.
    state := LwsState()
    arguments := new List<TypeReference>()
    arguments.Add(new SimpleTypeReference("string", 2, 20))
    arguments.Add(new SimpleTypeReference("StringBuilder", 2, 28))
    lookup := new GenericTypeReference("Dictionary", arguments, 2, 9)
    state.CheckMissingImportsInType(lookup)
    assert LwsSpans(state) == "NL002@2:9+10;NL002@2:28+13;"

    // Non-vacuity in both directions: importing ONE of the two namespaces leaves exactly the other.
    halfImported := LwsState()
    halfImported.RegisterImports(LwsUnit(["System.Collections.Generic"], []))
    halfImported.CheckMissingImportsInType(lookup)
    assert LwsSpans(halfImported) == "NL002@2:28+13;"

    silent := LwsState()
    silent.RegisterImports(LwsUnit(["System.Collections.Generic", "System.Text"], []))
    silent.CheckMissingImportsInType(lookup)
    assert silent.Diagnostics.Count == 0
}

test "THE FALLBACK POSITION BELONGS TO THE BASE NAME AND TO NOTHING ELSE" {
    // The `new` keyword is a defensible place to put a diagnostic about the constructed type and a
    // nonsensical place to put one about its type argument. So an unstamped ARGUMENT is skipped
    // rather than piled onto the keyword: reporting it at the caller's position would draw two
    // squiggles on the same three characters saying different things.
    state := LwsState()
    arguments := new List<TypeReference>()
    arguments.Add(new SimpleTypeReference("StringBuilder", 0, 0))
    unstamped := new GenericTypeReference("List", arguments, 0, 0)
    state.CheckMissingImportForType(unstamped, 6, 3)
    assert LwsSpans(state) == "NL002@6:3+1;"

    // Stamp the argument and it reports where it is written, while the base name keeps the fallback.
    mixed := LwsState()
    mixedArguments := new List<TypeReference>()
    mixedArguments.Add(new SimpleTypeReference("StringBuilder", 6, 12))
    partlyStamped := new GenericTypeReference("List", mixedArguments, 0, 0)
    mixed.CheckMissingImportForType(partlyStamped, 6, 3)
    assert LwsSpans(mixed) == "NL002@6:3+1;NL002@6:12+13;"
}

test "a nameless type still has its parts asked about, and gets no fallback of its own" {
    // A tuple is CALLED nothing, so `CheckMissingImportForType` offers its fallback to no one — but
    // `(int, StringBuilder)` still mentions a name a user can point at, and an unstamped one is
    // silence rather than a diagnostic on the enclosing syntax.
    state := LwsState()
    elements := new List<TupleTypeElement>()
    elements.Add(new TupleTypeElement(new SimpleTypeReference("int", 4, 10), null))
    elements.Add(new TupleTypeElement(new SimpleTypeReference("StringBuilder", 4, 15), null))
    state.CheckMissingImportForType(new TupleTypeReference(elements), 6, 3)
    assert LwsSpans(state) == "NL002@4:15+13;"

    unstamped := LwsState()
    unstampedElements := new List<TupleTypeElement>()
    unstampedElements.Add(new TupleTypeElement(new SimpleTypeReference("StringBuilder", 0, 0), null))
    unstamped.CheckMissingImportForType(new TupleTypeReference(unstampedElements), 6, 3)
    assert unstamped.Diagnostics.Count == 0
}

test "a type reference with no base name reports nothing" {
    state := LwsState()
    elements := new List<TupleTypeElement>()
    elements.Add(new TupleTypeElement(LwsSimpleType("int"), null))
    elements.Add(new TupleTypeElement(LwsSimpleType("int"), null))
    tuple := new TupleTypeReference(elements)
    state.CheckMissingImportForType(tuple, 6, 3)
    assert state.Diagnostics.Count == 0
}

// ── the reporting spine ──────────────────────────────────────────────────────────────────────

test "a disabled rule is silent" {
    config := LwsConfig()
    config.AddDisabledRule("NL001")
    state := new LinterWalkState("test.nl", null, config)
    state.PushScope()
    state.DeclareVariable("value", 3, 5)
    state.PopScope()
    assert state.Diagnostics.Count == 0
}

test "a suppressed line is silent" {
    source := "// nlc:ignore NL001\nvalue := 1\n"
    state := LwsStateWithSource(source)
    state.PushScope()
    state.DeclareVariable("value", 2, 1)
    state.PopScope()
    assert state.Diagnostics.Count == 0

    // Non-vacuity: the same declaration one line further down is not suppressed.
    other := LwsStateWithSource(source)
    other.PushScope()
    other.DeclareVariable("value", 1, 1)
    other.PopScope()
    assert other.Diagnostics.Count == 1
}

test "the reported column is the SPAN's column, whether or not it equals the asked-for one" {
    // (a) The C# asked `span.Column == location.Column ? location : location with { Column =
    // span.Column }`. Both arms produce a location whose column is the SPAN's, so the fork could not
    // decide anything. Asserted over a column the resolver KEEPS and one it MOVES — and the resolver
    // only moves a column when the caller asks for NO length, which is why NL006 is the probe.
    source := "    value := 1\n"
    kept := LwsStateWithSource(source)
    kept.ReportUnreachableCode(1, 5)
    assert LwsCodes(kept) == "NL006@1:5;"

    moved := LwsStateWithSource(source)
    moved.ReportUnreachableCode(1, 1)
    assert LwsCodes(moved) == "NL006@1:5;"

    // A caller that asks for a LENGTH keeps its own column, so the same two positions stay apart.
    withLength := LwsStateWithSource(source)
    withLength.PushScope()
    withLength.DeclareVariable("value", 1, 1)
    withLength.PopScope()
    assert LwsCodes(withLength) == "NL001@1:1;"
}

test "a diagnostic carries the state's file path" {
    state := LwsState()
    state.PushScope()
    state.DeclareVariable("value", 3, 5)
    state.PopScope()
    assert state.Diagnostics[0].Location.FilePath == "test.nl"
}

test "a diagnostic's severity is the configured severity for its code" {
    config := LwsConfig()
    config.RuleSeverities["NL001"] = LinterConfig.SeverityObject(DiagnosticSeverity.Error)
    state := new LinterWalkState("test.nl", null, config)
    state.PushScope()
    state.DeclareVariable("value", 3, 5)
    state.PopScope()
    assert state.Diagnostics[0].Severity == DiagnosticSeverity.Error
}

test "NL006 names the statement it cannot reach" {
    state := LwsState()
    state.ReportUnreachableCode(9, 5)
    assert LwsCodes(state) == "NL006@9:5;"
}

test "NL011 reports the OWNER of an empty catch block, not the brace" {
    state := LwsStateWithSource("    catch (e) {\n")
    state.ReportEmptyCatchBlock(1, 15)
    assert LwsCodes(state) == "NL011@1:5;"

    // Non-vacuity: with no source line to read, the block's own position is reported.
    bare := LwsState()
    bare.ReportEmptyCatchBlock(1, 15)
    assert LwsCodes(bare) == "NL011@1:15;"
}

test "SourceLine answers only for a line that exists" {
    state := LwsStateWithSource("first\nsecond\n")
    assert state.SourceLine(1) == "first"
    assert state.SourceLine(2) == "second"
    assert state.SourceLine(0) == ""
    assert state.SourceLine(9) == ""
    assert LwsState().SourceLine(1) == ""
}

test "FindTokenColumn is ORDINAL and falls back when the line does not carry the token" {
    state := LwsStateWithSource("func compute() {\n")
    assert state.FindTokenColumn(1, "compute", 99) == 6
    assert state.FindTokenColumn(1, "missing", 99) == 99
    assert state.FindTokenColumn(1, "   ", 99) == 99
    assert state.FindTokenColumn(9, "compute", 99) == 99
}

// ── the rules that read one node ─────────────────────────────────────────────────────────────

func LwsLiteralNullCheck(): BinaryExpression {
    literal := new IntLiteralExpression("1", 4, 9)
    nullLiteral := new NullLiteralExpression(4, 14)
    return new BinaryExpression(literal, BinaryOperator.NotEqual, nullLiteral, 4, 9)
}

func LwsFreshNullCheck(): BinaryExpression {
    widgetType := LwsSimpleType("Widget")
    arguments := new List<Argument>()
    created := new NewExpression(widgetType, arguments, null, 4, 9, null)
    nullLiteral := new NullLiteralExpression(4, 20)
    return new BinaryExpression(created, BinaryOperator.NotEqual, nullLiteral, 4, 9)
}

test "NL003 fires on a null check against a value-type literal" {
    state := LwsState()
    state.CheckUnnecessaryNullCheck(LwsLiteralNullCheck())
    assert LwsCodes(state) == "NL003@4:9;"
}

test "NL016 fires on a null check against a freshly created value" {
    state := LwsState()
    state.CheckRedundantNullCheck(LwsFreshNullCheck())
    assert LwsCodes(state) == "NL016@4:9;"
}

test "the two null-check rules partition their operands" {
    // A value-type literal is NL003's and never NL016's; a `new` is NL016's and never NL003's.
    onlyNl003 := LwsState()
    onlyNl003.CheckUnnecessaryNullCheck(LwsLiteralNullCheck())
    onlyNl003.CheckRedundantNullCheck(LwsLiteralNullCheck())
    assert LwsCodes(onlyNl003) == "NL003@4:9;"

    onlyNl016 := LwsState()
    onlyNl016.CheckUnnecessaryNullCheck(LwsFreshNullCheck())
    onlyNl016.CheckRedundantNullCheck(LwsFreshNullCheck())
    assert LwsCodes(onlyNl016) == "NL016@4:9;"
}

test "an interpolated string's holes are genuine reads" {
    state := LwsState()
    state.PushScope()
    state.DeclareVariable("name", 3, 5)
    state.HandleStringInterpolation("$\"hello {name}\"")
    state.PopScope()
    assert state.Diagnostics.Count == 0

    // Non-vacuity: a literal that mentions nothing leaves the declaration unread.
    silent := LwsState()
    silent.PushScope()
    silent.DeclareVariable("name", 3, 5)
    silent.HandleStringInterpolation("$\"hello\"")
    silent.PopScope()
    assert silent.Diagnostics.Count == 1
}
