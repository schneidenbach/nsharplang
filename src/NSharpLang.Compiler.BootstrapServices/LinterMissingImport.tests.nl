namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// CONTRACTS FOR NL002 AND FOR WHAT A TYPE REFERENCE IS CALLED (task 019 slice 8). These are the
// semantic assertions that came out of `Linter.cs` with `CheckMissingImport`,
// `CheckMissingImportForType` and `GetBaseTypeName`, plus the rules the move made checkable rather
// than implied: the exact membership of BOTH tables, the subset relationship between them, the
// nine-name difference, and the ORDER in which the three silencers apply.
//
// The two tables were written as two `Dictionary<string,string>` literals inside two methods, so
// nothing could observe that one was a superset of the other and nothing could observe a row lost
// from just one of them. Both facts are now equalities below.

func LmiScopes(names: string[]): Stack<HashSet<string>> {
    scopes := new Stack<HashSet<string>>()
    frame := new HashSet<string>(StringComparer.Ordinal)
    index := 0
    while index < names.Length {
        frame.Add(names[index])
        index = index + 1
    }

    scopes.Push(frame)
    return scopes
}

func LmiNoScopes(): Stack<HashSet<string>> {
    return new Stack<HashSet<string>>()
}

func LmiSymbols(names: string[]): HashSet<string> {
    result := new HashSet<string>(StringComparer.Ordinal)
    index := 0
    while index < names.Length {
        result.Add(names[index])
        index = index + 1
    }

    return result
}

func LmiNoSymbols(): HashSet<string> {
    return new HashSet<string>(StringComparer.Ordinal)
}

func LmiOneSymbol(name: string): HashSet<string> {
    result := new HashSet<string>(StringComparer.Ordinal)
    result.Add(name)
    return result
}

func LmiOneScope(name: string): Stack<HashSet<string>> {
    scopes := new Stack<HashSet<string>>()
    frame := new HashSet<string>(StringComparer.Ordinal)
    frame.Add(name)
    scopes.Push(frame)
    return scopes
}

func LmiEmptyScope(): Stack<HashSet<string>> {
    scopes := new Stack<HashSet<string>>()
    scopes.Push(new HashSet<string>(StringComparer.Ordinal))
    return scopes
}

func LmiOneNamespace(namespaceName: string): List<string> {
    result := new List<string>()
    result.Add(namespaceName)
    return result
}

func LmiNamespaces(names: string[]): List<string> {
    result := new List<string>()
    index := 0
    while index < names.Length {
        result.Add(names[index])
        index = index + 1
    }

    return result
}

func LmiNoNamespaces(): List<string> {
    return new List<string>()
}

// Every name the identifier table carries, in the order the deleted dictionary listed them.
func LmiAllIdentifierNames(): string[] {
    return ["List", "Dictionary", "HashSet", "Queue", "Stack", "LinkedList", "StringBuilder", "Regex", "File", "Directory", "Path", "Stream", "HttpClient", "JsonSerializer", "Task", "CancellationToken", "Encoding", "DateTime", "TimeSpan", "Guid", "Uri", "Tuple", "Lazy", "Action", "Func"]
}

// Every name the type table carries — the first sixteen rows of the other one.
func LmiAllTypeNames(): string[] {
    return ["List", "Dictionary", "HashSet", "Queue", "Stack", "LinkedList", "StringBuilder", "Regex", "File", "Directory", "Path", "Stream", "HttpClient", "JsonSerializer", "Task", "CancellationToken"]
}

// The nine the identifier table carries alone.
func LmiIdentifierOnlyNames(): string[] {
    return ["Encoding", "DateTime", "TimeSpan", "Guid", "Uri", "Tuple", "Lazy", "Action", "Func"]
}

func LmiSimple(name: string): TypeReference {
    return new SimpleTypeReference(name, 1, 1)
}

func LmiGeneric(name: string): TypeReference {
    arguments := new List<TypeReference>()
    arguments.Add(LmiSimple("int"))
    return new GenericTypeReference(name, arguments, 1, 1)
}

func LmiUnion(arms: List<TypeReference>): TypeReference {
    return new UnionTypeReference(arms)
}

func LmiArms(first: TypeReference, second: TypeReference): List<TypeReference> {
    arms := new List<TypeReference>()
    arms.Add(first)
    arms.Add(second)
    return arms
}


// ── what a type reference is called ──────────────────────────────────────────────────────────

test "a simple and a generic type answer with their written name" {
    assert LinterTypeReferenceName.Base(LmiSimple("Widget")) == "Widget"
    assert LinterTypeReferenceName.Base(LmiSimple("int")) == "int"
    assert LinterTypeReferenceName.Base(LmiGeneric("List")) == "List"
    assert LinterTypeReferenceName.Base(LmiGeneric("Dictionary")) == "Dictionary"
}

test "the wrappers are transparent, at any depth and in any combination" {
    assert LinterTypeReferenceName.Base(new NullableTypeReference(LmiSimple("Widget"))) == "Widget"
    assert LinterTypeReferenceName.Base(new ArrayTypeReference(LmiSimple("Widget"))) == "Widget"
    assert LinterTypeReferenceName.Base(new ByRefTypeReference(LmiSimple("Widget"))) == "Widget"

    // `List<int>?[]` — the shape the rule actually meets.
    nested := new ArrayTypeReference(new NullableTypeReference(LmiGeneric("List")))
    assert LinterTypeReferenceName.Base(nested) == "List"

    deep := new ByRefTypeReference(new ArrayTypeReference(new NullableTypeReference(new ArrayTypeReference(LmiSimple("Guid")))))
    assert LinterTypeReferenceName.Base(deep) == "Guid"
}

test "a union answers with its FIRST NAMED arm, which is not always its first arm" {
    named := LmiUnion(LmiArms(LmiSimple("Alpha"), LmiSimple("Beta")))
    assert LinterTypeReferenceName.Base(named) == "Alpha"

    // A tuple arm has no name of its own, so the union skips it rather than answering nothing.
    tuple := new TupleTypeReference(new List<TupleTypeElement>())
    skipped := LmiUnion(LmiArms(tuple, LmiGeneric("List")))
    assert LinterTypeReferenceName.Base(skipped) == "List"

    // Every arm nameless — the union is nameless too.
    bothNameless := LmiUnion(LmiArms(tuple, new TupleTypeReference(new List<TupleTypeElement>())))
    assert LinterTypeReferenceName.Base(bothNameless) == null
}

test "an empty union is nameless, so the arms scan is safe on a union with no arms" {
    assert LinterTypeReferenceName.Base(LmiUnion(new List<TypeReference>())) == null
}

test "a union of wrapped arms is still named, because the arms are asked recursively" {
    wrapped := LmiUnion(LmiArms(
        new ArrayTypeReference(new TupleTypeReference(new List<TupleTypeElement>())),
        new NullableTypeReference(LmiSimple("Task"))))
    assert LinterTypeReferenceName.Base(wrapped) == "Task"
}

test "the nameless kinds answer NOTHING, and that silence is the contract" {
    assert LinterTypeReferenceName.Base(new TupleTypeReference(new List<TupleTypeElement>())) == null

    parameterTypes := new List<TypeReference>()
    parameterTypes.Add(LmiSimple("int"))
    assert LinterTypeReferenceName.Base(new FunctionTypeReference(parameterTypes, LmiSimple("int"))) == null

    // A nameless kind stays nameless through every wrapper — NL002 must not demand an import for
    // `(int, int)[]` and NL010 must not record one as a used identifier.
    assert LinterTypeReferenceName.Base(new ArrayTypeReference(new TupleTypeReference(new List<TupleTypeElement>()))) == null
    assert LinterTypeReferenceName.Base(new NullableTypeReference(new TupleTypeReference(new List<TupleTypeElement>()))) == null
}


// ── the two tables ───────────────────────────────────────────────────────────────────────────

test "the identifier table carries exactly twenty-five names" {
    names := LmiAllIdentifierNames()
    assert names.Length == 25

    index := 0
    while index < names.Length {
        assert LinterMissingImport.RequiredNamespaceForIdentifier(names[index]) != null
        index = index + 1
    }
}

test "the type table carries exactly sixteen names" {
    names := LmiAllTypeNames()
    assert names.Length == 16

    index := 0
    while index < names.Length {
        assert LinterMissingImport.RequiredNamespaceForTypeName(names[index]) != null
        index = index + 1
    }
}

test "the type table is a SUBSET of the identifier table, and agrees with it everywhere" {
    names := LmiAllTypeNames()
    index := 0
    while index < names.Length {
        assert LinterMissingImport.RequiredNamespaceForTypeName(names[index]) == LinterMissingImport.RequiredNamespaceForIdentifier(names[index])
        index = index + 1
    }
}

test "the difference between the tables is exactly the nine static-receiver names" {
    onlyIdentifier := LmiIdentifierOnlyNames()
    assert onlyIdentifier.Length == 9

    index := 0
    while index < onlyIdentifier.Length {
        name := onlyIdentifier[index]
        assert LinterMissingImport.RequiredNamespaceForIdentifier(name) != null
        assert LinterMissingImport.RequiredNamespaceForTypeName(name) == null
        index = index + 1
    }
}

test "every row of the identifier table is either a type-table row or one of the nine" {
    all := LmiAllIdentifierNames()
    shared := LmiAllTypeNames()
    onlyIdentifier := LmiIdentifierOnlyNames()

    index := 0
    while index < all.Length {
        name := all[index]
        inShared := LinterMissingImport.Contains(shared, name)
        inOnly := LinterMissingImport.Contains(onlyIdentifier, name)

        // Exactly one of the two, never both and never neither — the partition is total.
        assert inShared != inOnly
        index = index + 1
    }

    assert shared.Length + onlyIdentifier.Length == all.Length
}

test "each name maps to the namespace the deleted dictionary gave it" {
    assert LinterMissingImport.RequiredNamespaceForIdentifier("List") == "System.Collections.Generic"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Dictionary") == "System.Collections.Generic"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("HashSet") == "System.Collections.Generic"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Queue") == "System.Collections.Generic"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Stack") == "System.Collections.Generic"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("LinkedList") == "System.Collections.Generic"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("StringBuilder") == "System.Text"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Encoding") == "System.Text"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Regex") == "System.Text.RegularExpressions"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("File") == "System.IO"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Directory") == "System.IO"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Path") == "System.IO"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Stream") == "System.IO"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("HttpClient") == "System.Net.Http"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("JsonSerializer") == "System.Text.Json"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Task") == "System.Threading.Tasks"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("CancellationToken") == "System.Threading"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("DateTime") == "System"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("TimeSpan") == "System"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Guid") == "System"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Uri") == "System"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Tuple") == "System"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Lazy") == "System"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Action") == "System"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Func") == "System"
}

test "Task and CancellationToken are DIFFERENT namespaces, which the two neighbouring rows hide" {
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Task") == "System.Threading.Tasks"
    assert LinterMissingImport.RequiredNamespaceForIdentifier("CancellationToken") == "System.Threading"
    assert LinterMissingImport.RequiredNamespaceForTypeName("Task") == "System.Threading.Tasks"
    assert LinterMissingImport.RequiredNamespaceForTypeName("CancellationToken") == "System.Threading"
}

test "a name no table carries is silent, and silence is the default answer" {
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Widget") == null
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Console") == null
    assert LinterMissingImport.RequiredNamespaceForIdentifier("StringComparer") == null
    assert LinterMissingImport.RequiredNamespaceForIdentifier("") == null
    assert LinterMissingImport.RequiredNamespaceForIdentifier("   ") == null
    assert LinterMissingImport.RequiredNamespaceForTypeName("Widget") == null
    assert LinterMissingImport.RequiredNamespaceForTypeName("") == null
}

test "the lookup is ORDINAL: a name differing in case is a different name" {
    assert LinterMissingImport.RequiredNamespaceForIdentifier("list") == null
    assert LinterMissingImport.RequiredNamespaceForIdentifier("LIST") == null
    assert LinterMissingImport.RequiredNamespaceForIdentifier("guid") == null
    assert LinterMissingImport.RequiredNamespaceForIdentifier("task") == null
    assert LinterMissingImport.RequiredNamespaceForTypeName("file") == null
}

test "a table name with anything appended or prepended is not a table name" {
    assert LinterMissingImport.RequiredNamespaceForIdentifier("Lists") == null
    assert LinterMissingImport.RequiredNamespaceForIdentifier("MyList") == null
    assert LinterMissingImport.RequiredNamespaceForIdentifier("List1") == null
    assert LinterMissingImport.RequiredNamespaceForIdentifier("List<int>") == null
    assert LinterMissingImport.RequiredNamespaceForIdentifier("System.IO.File") == null
}


// ── the decision: the three silencers, and the order they apply in ───────────────────────────

test "a table name written with no import at all is reported, with its namespace" {
    assert LinterMissingImport.MissingNamespaceForIdentifier("List", LmiNoScopes(), LmiNoSymbols(), LmiNoNamespaces()) == "System.Collections.Generic"
    assert LinterMissingImport.MissingNamespaceForIdentifier("Guid", LmiNoScopes(), LmiNoSymbols(), LmiNoNamespaces()) == "System"
    assert LinterMissingImport.MissingNamespaceForTypeName("Regex", LmiNoSymbols(), LmiNoNamespaces()) == "System.Text.RegularExpressions"
}

test "an already-imported namespace silences its own names and nothing else" {
    imported := LmiNamespaces(["System.Collections.Generic"])

    assert LinterMissingImport.MissingNamespaceForIdentifier("List", LmiNoScopes(), LmiNoSymbols(), imported) == null
    assert LinterMissingImport.MissingNamespaceForIdentifier("Dictionary", LmiNoScopes(), LmiNoSymbols(), imported) == null

    // A different namespace's name is untouched by it.
    assert LinterMissingImport.MissingNamespaceForIdentifier("Guid", LmiNoScopes(), LmiNoSymbols(), imported) == "System"
    assert LinterMissingImport.MissingNamespaceForTypeName("List", LmiNoSymbols(), imported) == null
    assert LinterMissingImport.MissingNamespaceForTypeName("Task", LmiNoSymbols(), imported) == "System.Threading.Tasks"
}

test "importing System does NOT silence System.Collections.Generic, because the match is exact" {
    imported := LmiNamespaces(["System"])

    assert LinterMissingImport.MissingNamespaceForIdentifier("Guid", LmiNoScopes(), LmiNoSymbols(), imported) == null
    assert LinterMissingImport.MissingNamespaceForIdentifier("List", LmiNoScopes(), LmiNoSymbols(), imported) == "System.Collections.Generic"
    assert LinterMissingImport.MissingNamespaceForIdentifier("Task", LmiNoScopes(), LmiNoSymbols(), imported) == "System.Threading.Tasks"
}

test "a FILE import of the same symbol name silences the rule for that name alone" {
    symbols := LmiSymbols(["List"])

    assert LinterMissingImport.MissingNamespaceForIdentifier("List", LmiNoScopes(), symbols, LmiNoNamespaces()) == null
    assert LinterMissingImport.MissingNamespaceForIdentifier("Dictionary", LmiNoScopes(), symbols, LmiNoNamespaces()) == "System.Collections.Generic"
    assert LinterMissingImport.MissingNamespaceForTypeName("List", symbols, LmiNoNamespaces()) == null
    assert LinterMissingImport.MissingNamespaceForTypeName("Dictionary", symbols, LmiNoNamespaces()) == "System.Collections.Generic"
}

test "an enclosing type's own member silences the IDENTIFIER arm, and only that arm" {
    scopes := LmiScopes(["Task", "Widget"])

    assert LinterMissingImport.MissingNamespaceForIdentifier("Task", scopes, LmiNoSymbols(), LmiNoNamespaces()) == null

    // The TYPE arm never consults the member scopes: a member called `Task` cannot shadow the
    // type written in a `new`.
    assert LinterMissingImport.MissingNamespaceForTypeName("Task", LmiNoSymbols(), LmiNoNamespaces()) == "System.Threading.Tasks"

    // A member name that no table carries was already silent; the scope check changes nothing.
    assert LinterMissingImport.MissingNamespaceForIdentifier("Widget", scopes, LmiNoSymbols(), LmiNoNamespaces()) == null
}

test "the member-scope check runs BEFORE the table lookup, so every enclosing frame is asked" {
    scopes := new Stack<HashSet<string>>()
    outer := new HashSet<string>(StringComparer.Ordinal)
    outer.Add("Guid")
    scopes.Push(outer)
    inner := new HashSet<string>(StringComparer.Ordinal)
    inner.Add("List")
    scopes.Push(inner)

    // Both frames answer, not just the innermost.
    assert LinterMissingImport.MissingNamespaceForIdentifier("List", scopes, LmiNoSymbols(), LmiNoNamespaces()) == null
    assert LinterMissingImport.MissingNamespaceForIdentifier("Guid", scopes, LmiNoSymbols(), LmiNoNamespaces()) == null
    assert LinterMissingImport.MissingNamespaceForIdentifier("Task", scopes, LmiNoSymbols(), LmiNoNamespaces()) == "System.Threading.Tasks"
}

test "no member scopes at all is not the same as a scope that contains nothing, and both stay silent about nothing" {
    empty := LmiEmptyScope()

    assert LinterMissingImport.MissingNamespaceForIdentifier("List", empty, LmiNoSymbols(), LmiNoNamespaces()) == "System.Collections.Generic"
    assert LinterMissingImport.MissingNamespaceForIdentifier("List", LmiNoScopes(), LmiNoSymbols(), LmiNoNamespaces()) == "System.Collections.Generic"
}

test "the silencers compose: any one of the three is enough on its own" {
    name := "Task"
    byScope := LinterMissingImport.MissingNamespaceForIdentifier(name, LmiOneScope(name), LmiNoSymbols(), LmiNoNamespaces())
    bySymbol := LinterMissingImport.MissingNamespaceForIdentifier(name, LmiNoScopes(), LmiOneSymbol(name), LmiNoNamespaces())
    byNamespace := LinterMissingImport.MissingNamespaceForIdentifier(name, LmiNoScopes(), LmiNoSymbols(), LmiOneNamespace("System.Threading.Tasks"))

    assert byScope == null
    assert bySymbol == null
    assert byNamespace == null
    assert LinterMissingImport.MissingNamespaceForIdentifier(name, LmiNoScopes(), LmiNoSymbols(), LmiNoNamespaces()) == "System.Threading.Tasks"
}

test "every table name is reported when nothing supplies it, so no row is silently unreachable" {
    names := LmiAllIdentifierNames()
    reported := 0
    index := 0
    while index < names.Length {
        if LinterMissingImport.MissingNamespaceForIdentifier(names[index], LmiNoScopes(), LmiNoSymbols(), LmiNoNamespaces()) != null {
            reported = reported + 1
        }

        index = index + 1
    }

    assert reported == 25
}

test "every table name is silenced when its own namespace is imported, so no row names the wrong one" {
    names := LmiAllIdentifierNames()
    silenced := 0
    index := 0
    while index < names.Length {
        own := LinterMissingImport.RequiredNamespaceForIdentifier(names[index])
        if own != null {
            ownNamespace: string = own
            imported := LmiOneNamespace(ownNamespace)
            if LinterMissingImport.MissingNamespaceForIdentifier(names[index], LmiNoScopes(), LmiNoSymbols(), imported) == null {
                silenced = silenced + 1
            }
        }

        index = index + 1
    }

    assert silenced == 25
}


// ── what the diagnostic says ─────────────────────────────────────────────────────────────────

test "the message names the identifier and the suggestion names the import to add" {
    assert LinterMissingImport.Message("Guid") == "I can't find 'Guid' — it looks like a missing import"
    assert LinterMissingImport.Message("List") == "I can't find 'List' — it looks like a missing import"
    assert LinterMissingImport.Suggestion("System") == "Add 'import System' at the top of the file"
    assert LinterMissingImport.Suggestion("System.Collections.Generic") == "Add 'import System.Collections.Generic' at the top of the file"
}

test "the suggestion is composed from the namespace the decision returned, never from the name" {
    name := "JsonSerializer"
    requiredNs := LinterMissingImport.MissingNamespaceForIdentifier(name, LmiNoScopes(), LmiNoSymbols(), LmiNoNamespaces())

    assert requiredNs == "System.Text.Json"
    if requiredNs != null {
        assert LinterMissingImport.Suggestion(requiredNs) == "Add 'import System.Text.Json' at the top of the file"
    }

    assert LinterMissingImport.Message(name) == "I can't find 'JsonSerializer' — it looks like a missing import"
}
