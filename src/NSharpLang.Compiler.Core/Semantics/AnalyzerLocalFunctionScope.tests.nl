namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler.Ast


// Native contracts for WHERE A LOCAL FUNCTION'S NAME IS VISIBLE.
//
// The rule the tip used to have was "wherever the walk has already been": the name landed when the
// declaration STATEMENT was reached, so a call above it, and a call from a sibling written above it,
// both reported NL412. That made mutual recursion unspellable — whichever of the pair is written
// first cannot see the other — which is why the fix is a rule about the BLOCK rather than a
// look-ahead at the call.
//
// What is pinned here is the list this owner builds: which statements contribute a name, in what
// order, at which position, and — the half that is easy to get wrong — that it does NOT descend.
func ScopeFactory(): AnalyzerFunctionTypeFactory {
    context := new AnalyzerDeclarationContext()
    assemblies := new List<Assembly>()
    assemblies.Add(typeof(List<int>).get_Assembly())
    context.Reset(Path.GetFullPath("."), assemblies)
    scopes := new AnalyzerScopeStack()
    scopes.Push(new SemanticModel(), new Scope(ScopeKind.Global), 1, 1)
    provider := new AnalyzerProjectSourceProvider()
    discovery := new AnalyzerProjectTypeDiscovery(
        provider,
        context,
        new List<string>(),
        new Dictionary<string, string>(StringComparer.Ordinal)
    )
    probe := new AnalyzerExternalTypeProbe(new List<Assembly>(), new List<string>())
    errors := new List<CompilerError>()
    diagnostics := new AnalyzerDiagnosticSink(errors, provider)
    resolver := new AnalyzerTypeResolver(
        scopes,
        context,
        discovery,
        probe,
        diagnostics,
        new Dictionary<string, string>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, TypeInfo>>(StringComparer.Ordinal),
        new Dictionary<string, Dictionary<string, SymbolDeclaration>>(StringComparer.Ordinal),
        new SemanticModel(),
        new BindingMap()
    )

    return new AnalyzerFunctionTypeFactory(context, new AnalyzerTypeSubstitution(scopes, context, resolver))
}

func ScopeLocalFunction(name: string, line: int, column: int): Statement {
    body := new BlockStatement(new List<Statement>(), line, column)
    declaration := new FunctionDeclaration(name, new List<Parameter>(), null, body, null, null, null, Modifiers.None, new List<AttributeNode>(), false, null, false, false, line + 40, column + 40)
    statement: Statement = new LocalFunctionStatement(declaration, line, column)
    return statement
}

func ScopePlain(line: int): Statement {
    statement: Statement = new PrintStatement(new IntLiteralExpression("1", line, 7), line, 1)
    return statement
}

func ScopeNames(hoisted: List<AnalyzerHoistedLocalFunction>): string {
    text := ""
    index := 0
    while index < hoisted.Count {
        if text.Length > 0 {
            text = text + ";"
        }

        entry := hoisted[index]
        text = text + entry.Name + "@" + entry.Line.ToString() + ":" + entry.Column.ToString()
        index = index + 1
    }

    return text
}

test "EVERY LOCAL FUNCTION IN THE LIST IS HOISTED, IN DECLARATION ORDER" {
    statements := new List<Statement>()
    statements.Add(ScopeLocalFunction("visitStatement", 3, 5))
    statements.Add(ScopePlain(8))
    statements.Add(ScopeLocalFunction("visitBlock", 9, 5))

    hoisted := AnalyzerLocalFunctionScope.Hoist(statements, null, ScopeFactory())

    // The ORDER is behaviour: two that collide on a name must report the SECOND as the duplicate.
    assert ScopeNames(hoisted) == "visitStatement@3:5;visitBlock@9:5"
}

test "THE POSITION IS THE STATEMENT'S, NOT THE INNER DECLARATION'S" {
    statements := new List<Statement>()
    statements.Add(ScopeLocalFunction("helper", 6, 3))

    hoisted := AnalyzerLocalFunctionScope.Hoist(statements, null, ScopeFactory())

    // The inner `FunctionDeclaration` in this fixture sits at 46:43 and is deliberately not used —
    // the same choice `AnalyzerFunctionBodies.BeginLocalFunction` makes, so go-to-definition does
    // not move now that the binding happens earlier.
    assert hoisted.Count == 1
    assert hoisted[0].Line == 6
    assert hoisted[0].Column == 3
}

test "THE HOISTED SIGNATURE IS THE FUNCTION'S OWN TYPE" {
    statements := new List<Statement>()
    statements.Add(ScopeLocalFunction("helper", 6, 3))

    hoisted := AnalyzerLocalFunctionScope.Hoist(statements, null, ScopeFactory())

    signature := hoisted[0].Signature as FunctionTypeInfo
    assert signature != null
    assert signature.SourceName == "helper"
}

test "A LIST WITH NO LOCAL FUNCTION HOISTS NOTHING" {
    statements := new List<Statement>()
    statements.Add(ScopePlain(3))
    statements.Add(ScopePlain(4))

    hoisted := AnalyzerLocalFunctionScope.Hoist(statements, null, ScopeFactory())

    assert hoisted.Count == 0
}

test "A NULL LIST HOISTS NOTHING RATHER THAN FAILING" {
    hoisted := AnalyzerLocalFunctionScope.Hoist(null, null, ScopeFactory())

    assert hoisted.Count == 0
}

test "THE HOIST DOES NOT DESCEND — A NESTED BLOCK'S LOCAL FUNCTIONS ARE ITS OWN" {
    inner := new List<Statement>()
    inner.Add(ScopeLocalFunction("hidden", 5, 9))
    outer := new List<Statement>()
    nested: Statement = new BlockStatement(inner, 4, 5)
    outer.Add(nested)
    outer.Add(ScopeLocalFunction("visible", 8, 5))

    hoisted := AnalyzerLocalFunctionScope.Hoist(outer, null, ScopeFactory())

    // `hidden` belongs to the nested block and is bound when THAT block is walked, into THAT block's
    // scope. Hoisting it here would make it callable from a place it is not in scope.
    assert ScopeNames(hoisted) == "visible@8:5"
}

test "A SCOPE REMEMBERS WHICH LOCAL FUNCTIONS IT HOISTED, AND FORGETS EVERY OTHER NAME" {
    scope := new Scope(ScopeKind.Block)

    scope.RecordHoistedLocalFunction("visitBlock")

    // The memory is what stops the declaration STATEMENT from declaring the name a second time and
    // reporting the declaration as a duplicate of itself.
    assert scope.HasHoistedLocalFunction("visitBlock")
    assert !scope.HasHoistedLocalFunction("visitStatement")
}

test "THE HOIST MEMORY IS PER-SCOPE, BECAUSE VISIBILITY IS PER-BLOCK" {
    outer := new Scope(ScopeKind.Function)
    inner := new Scope(ScopeKind.Block)

    inner.RecordHoistedLocalFunction("hidden")

    assert !outer.HasHoistedLocalFunction("hidden")
}
