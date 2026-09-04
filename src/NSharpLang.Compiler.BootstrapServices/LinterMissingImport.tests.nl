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

func LmiSimpleAt(name: string, line: int, column: int): TypeReference {
    return new SimpleTypeReference(name, line, column)
}

func LmiGenericAt(name: string, argument: TypeReference, line: int, column: int): TypeReference {
    arguments := new List<TypeReference>()
    arguments.Add(argument)
    return new GenericTypeReference(name, arguments, line, column)
}

// The named references a written type yields, IN ORDER, each with the span it answers for itself.
// The order is the contract's subject as much as the membership is: the base name comes first.
func LmiNamedSpans(typeReference: TypeReference): string {
    references := LinterTypeReferenceName.NamedReferences(typeReference)
    rendered := ""
    index := 0
    while index < references.Count {
        span := LinterTypeReferenceName.BaseNameSpan(references[index])
        name := LinterTypeReferenceName.Base(references[index]) ?? "<nameless>"
        rendered = rendered + name + "@" + span.StartLine.ToString() + ":" + span.StartColumn.ToString() + "+" + span.Length.ToString() + ";"
        index = index + 1
    }

    return rendered
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

func LmiTypeArguments(only: TypeReference): List<TypeReference> {
    arguments := new List<TypeReference>()
    arguments.Add(only)
    return arguments
}

// Exact set equality: every expected name mentioned, and nothing else mentioned. Both halves
// matter — a walk that missed an arm and a walk that invented a name are different defects.
func LmiMentions(typeReference: TypeReference, expected: string[]): bool {
    mentioned := LinterTypeReferenceName.MentionedNames(typeReference)
    if mentioned.Count != expected.Length {
        return false
    }

    index := 0
    while index < expected.Length {
        if !mentioned.Contains(expected[index]) {
            return false
        }

        index = index + 1
    }

    return true
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
        new NullableTypeReference(LmiSimple("Task"))
    ))
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

// ── WHERE each name a type reference writes is WRITTEN ───────────────────────────────────────
//
// `BaseNameSpan` and `NamedReferences` are the third and fourth questions about the same subject,
// and they exist because a per-name DIAGNOSTIC needs both halves: every name, and each name's own
// columns. They are asked here beside `Base` and `MentionedNames` for the reason this file's header
// gives — a walk that drifts from its siblings reports one arm's name at another arm's position.

test "the base name's span is the span of the reference Base took the name from" {
    assert LmiNamedSpans(LmiSimpleAt("Widget", 4, 9)) == "Widget@4:9+6;"

    // A generic spans its NAME and not its type arguments: `List<int>` underlines four columns.
    listOfWidget := LmiGenericAt("List", LmiSimpleAt("Widget", 4, 14), 4, 9)
    assert LmiNamedSpans(listOfWidget) == "List@4:9+4;Widget@4:14+6;"
}

test "the wrappers are transparent to the span exactly as they are to the name" {
    inner := LmiSimpleAt("Widget", 7, 20)
    assert LmiNamedSpans(new ArrayTypeReference(inner)) == "Widget@7:20+6;"
    assert LmiNamedSpans(new NullableTypeReference(inner)) == "Widget@7:20+6;"
    assert LmiNamedSpans(new ByRefTypeReference(inner)) == "Widget@7:20+6;"

    // `List<int>?[]` — the shape the rule actually meets. The base name is still the generic's.
    nested := new ArrayTypeReference(new NullableTypeReference(LmiGenericAt("List", LmiSimpleAt("int", 7, 25), 7, 20)))
    assert LmiNamedSpans(nested) == "List@7:20+4;int@7:25+3;"
}

test "THE BASE NAME COMES FIRST, which is what lets a caller give it a fallback and nothing else" {
    // A union's first NAMED arm leads, not its first arm — the same rule `Base` follows, and it is
    // asked of `Base` rather than re-decided, so the two cannot disagree.
    tuple := new TupleTypeReference(new List<TupleTypeElement>())
    skipped := LmiUnion(LmiArms(tuple, LmiGenericAt("List", LmiSimpleAt("int", 2, 12), 2, 7)))
    assert LinterTypeReferenceName.Base(skipped) == "List"
    assert LmiNamedSpans(skipped) == "List@2:7+4;int@2:12+3;"

    // And with a named arm on BOTH sides the LATER arm still follows the earlier one.
    both := LmiUnion(LmiArms(LmiSimpleAt("Alpha", 2, 1), LmiSimpleAt("Beta", 2, 9)))
    assert LmiNamedSpans(both) == "Alpha@2:1+5;Beta@2:9+4;"
}

test "the kinds that are CALLED nothing still yield the names they contain" {
    // A tuple has no base name, so its first entry is just its first named part — which is exactly
    // why the caller asks `Base` before handing out a position of its own.
    elements := new List<TupleTypeElement>()
    elements.Add(new TupleTypeElement(LmiSimpleAt("Widget", 3, 5), null))
    elements.Add(new TupleTypeElement(LmiSimpleAt("Gadget", 3, 13), null))
    tuple := new TupleTypeReference(elements)
    assert LinterTypeReferenceName.Base(tuple) == null
    assert LmiNamedSpans(tuple) == "Widget@3:5+6;Gadget@3:13+6;"

    // A function type yields its RETURN type first, then its parameters, and is called nothing.
    parameterTypes := new List<TypeReference>()
    parameterTypes.Add(LmiSimpleAt("Widget", 3, 5))
    functionType := new FunctionTypeReference(parameterTypes, LmiSimpleAt("Gadget", 3, 17))
    assert LinterTypeReferenceName.Base(functionType) == null
    assert LmiNamedSpans(functionType) == "Gadget@3:17+6;Widget@3:5+6;"
}

test "an unstamped reference answers NO span, and that is how a hand-built tree is recognised" {
    // `NameSpan` folds a zero line or column to `SourceSpan.None`, and a zero-length span renders
    // as 0:0+0 here. The reporting rule turns that into silence rather than a diagnostic at 0:0.
    assert LmiNamedSpans(new SimpleTypeReference("Widget", 0, 0)) == "Widget@0:0+0;"
    assert !LinterTypeReferenceName.BaseNameSpan(new SimpleTypeReference("Widget", 0, 0)).IsValid
    assert LinterTypeReferenceName.BaseNameSpan(LmiSimpleAt("Widget", 4, 9)).IsValid
}

test "every reference NamedReferences yields is one MentionedNames names, and vice versa" {
    // The anti-drift claim, stated as an equality rather than trusted. The two walks visit the same
    // subject for two different rules; if one grows an arm the other lacks, this fails.
    deep := new ArrayTypeReference(LmiGenericAt("Dictionary", new NullableTypeReference(LmiGenericAt("List", LmiSimpleAt("Widget", 1, 30), 1, 20)), 1, 5))
    mentioned := LinterTypeReferenceName.MentionedNames(deep)
    yielded := LinterTypeReferenceName.NamedReferences(deep)
    assert yielded.Count == mentioned.Count
    index := 0
    while index < yielded.Count {
        name := LinterTypeReferenceName.Base(yielded[index]) ?? "<nameless>"
        assert mentioned.Contains(name)
        index = index + 1
    }
}

// ── what a type reference MENTIONS (task 019 slice 9) ────────────────────────────────────────
//
// NL010's side of the same subject. `Base` answers with ONE name and stops; `MentionedNames` walks
// the whole reference. Running the two here together is what keeps them from drifting: the shapes
// below are asked of both, and the cases where they differ are named rather than discovered later
// as a wrongly-reported unused import.

test "a simple and a generic type mention their own name" {
    assert LmiMentions(LmiSimple("Widget"), ["Widget"])
    assert LmiMentions(LmiGeneric("List"), ["List", "int"])
}

test "a generic mentions its ARGUMENTS too, which is where Base and MentionedNames part company" {
    inner := new List<TypeReference>()
    inner.Add(LmiSimple("string"))
    inner.Add(new GenericTypeReference("List", LmiTypeArguments(LmiSimple("Widget")), 1, 1))
    dictionary := new GenericTypeReference("Dictionary", inner, 1, 1)

    assert LinterTypeReferenceName.Base(dictionary) == "Dictionary"
    assert LmiMentions(dictionary, ["Dictionary", "string", "List", "Widget"])
}

test "the wrappers are transparent here too, at any depth" {
    assert LmiMentions(new NullableTypeReference(LmiSimple("Widget")), ["Widget"])
    assert LmiMentions(new ArrayTypeReference(LmiSimple("Widget")), ["Widget"])
    assert LmiMentions(new ByRefTypeReference(LmiSimple("Widget")), ["Widget"])
    assert LmiMentions(new ArrayTypeReference(new NullableTypeReference(LmiGeneric("List"))), ["List", "int"])
}

test "a union mentions EVERY arm, not just the first named one — the sharpest difference" {
    // `int | Widget` is CALLED `int` and MENTIONS both. Dropping `Widget` would report a live
    // import as unused, which for NL010 at error severity breaks a green build.
    twoArms := LmiUnion(LmiArms(LmiSimple("int"), LmiSimple("Widget")))
    assert LinterTypeReferenceName.Base(twoArms) == "int"
    assert LmiMentions(twoArms, ["int", "Widget"])
}

test "the kinds that are CALLED nothing still mention what they contain" {
    // A tuple, a function type and their contents: `Base` answers null for all three, and every
    // name inside them is still a real import usage.
    tupleElements := new List<TupleTypeElement>()
    tupleElements.Add(new TupleTypeElement(LmiSimple("Widget"), "first"))
    tupleElements.Add(new TupleTypeElement(LmiGeneric("List"), null))
    tuple := new TupleTypeReference(tupleElements)
    assert LinterTypeReferenceName.Base(tuple) == null
    assert LmiMentions(tuple, ["Widget", "List", "int"])

    parameterTypes := new List<TypeReference>()
    parameterTypes.Add(LmiSimple("Guid"))
    parameterTypes.Add(LmiSimple("Uri"))
    functionType := new FunctionTypeReference(parameterTypes, LmiSimple("Task"))
    assert LinterTypeReferenceName.Base(functionType) == null
    assert LmiMentions(functionType, ["Guid", "Uri", "Task"])
}

test "an empty union, an empty tuple and a null reference mention nothing" {
    assert LmiMentions(LmiUnion(new List<TypeReference>()), [])
    assert LmiMentions(new TupleTypeReference(new List<TupleTypeElement>()), [])
    assert LinterTypeReferenceName.MentionedNames(null).Count == 0
}

test "the answer is a SET, so a name written twice is mentioned once" {
    repeated := LmiUnion(LmiArms(LmiSimple("Widget"), LmiSimple("Widget")))
    assert LmiMentions(repeated, ["Widget"])
}

test "the set is ordinal — two names differing only in case are two mentions" {
    cased := LmiUnion(LmiArms(LmiSimple("Widget"), LmiSimple("widget")))
    assert LmiMentions(cased, ["Widget", "widget"])
}

test "every name Base finds is also a name MentionedNames finds" {
    // The two questions have different answers, but never contradictory ones: whatever a reference
    // is CALLED is certainly one of the names it MENTIONS. Stated over every shape above.
    subjects := new List<TypeReference>()
    subjects.Add(LmiSimple("Widget"))
    subjects.Add(LmiGeneric("List"))
    subjects.Add(new NullableTypeReference(LmiSimple("Guid")))
    subjects.Add(new ArrayTypeReference(new NullableTypeReference(LmiGeneric("List"))))
    subjects.Add(LmiUnion(LmiArms(LmiSimple("int"), LmiSimple("Widget"))))
    subjects.Add(LmiUnion(LmiArms(new TupleTypeReference(new List<TupleTypeElement>()), LmiGeneric("List"))))
    subjects.Add(new ByRefTypeReference(LmiSimple("Uri")))

    named := 0
    index := 0
    while index < subjects.Count {
        baseName := LinterTypeReferenceName.Base(subjects[index])
        if baseName != null {
            assert LinterTypeReferenceName.MentionedNames(subjects[index]).Contains(baseName)
            named = named + 1
        }

        index = index + 1
    }

    // Non-vacuity: every subject above IS named, so the containment was actually checked seven times.
    assert named == 7
}

test "the accumulator form and the answering form are the same walk" {
    // The linter calls the accumulator on every declared type in a file, into one shared set. The
    // two must not drift, so the union of two accumulator calls is asserted against the union of
    // the two answers.
    shared := new HashSet<string>(StringComparer.Ordinal)
    LinterTypeReferenceName.CollectMentionedNames(LmiGeneric("List"), shared)
    LinterTypeReferenceName.CollectMentionedNames(new ArrayTypeReference(LmiSimple("Widget")), shared)

    assert shared.Count == 3
    assert shared.Contains("List")
    assert shared.Contains("int")
    assert shared.Contains("Widget")

    // A null reference leaves the accumulator untouched rather than throwing — the linter passes
    // optional types straight through.
    LinterTypeReferenceName.CollectMentionedNames(null, shared)
    assert shared.Count == 3
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
    assert LinterMissingImport.Message("Guid") == "'Guid' is used without the import that provides it"
    assert LinterMissingImport.Message("List") == "'List' is used without the import that provides it"
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

    assert LinterMissingImport.Message(name) == "'JsonSerializer' is used without the import that provides it"
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// END-TO-END NL002 CONTRACTS OVER REAL SOURCE (020 slice 15)
//
// These came out of `tests/ExampleLintTests.cs`, which is deleted. That file asked three questions:
// `List` without `import System.Collections.Generic` reports, `List` with it does not, and
// `StringBuilder` without `import System.Text` reports.
//
// THE MIDDLE ONE WAS THE ONLY NON-VACUOUS HALF OF A PAIR AND IT HAD NO PARTNER. Its census is
// stated whole below, next to the removal control that makes it mean something, and the two
// reporting cases now state WHERE the squiggle lands — which turns out to be a fact nothing had
// ever written down.

func LmieCensus(source: string): string {
    parsed := ColumnarParserRecovery.ParseFileAst(source, "test.nl")
    unit := parsed.CompilationUnit
    if unit == null {
        throw new InvalidOperationException("the parser answered no compilation unit for: " + source)
    }

    if parsed.Errors.Count != 0 {
        throw new InvalidOperationException("the source did not parse cleanly: " + source)
    }

    linter := new Linter(LinterConfig.Default())
    diagnostics := linter.Lint(unit, "test.nl", source)
    census := ""
    for diagnostic in diagnostics {
        census = census + diagnostic.Code + "@" + diagnostic.Location.Line.ToString() + ":" + diagnostic.Location.Column.ToString() + "+" + diagnostic.Length.ToString() + ";"
    }

    return census
}

func LmieMessages(source: string): string {
    parsed := ColumnarParserRecovery.ParseFileAst(source, "test.nl")
    unit := parsed.CompilationUnit
    if unit == null {
        throw new InvalidOperationException("the parser answered no compilation unit for: " + source)
    }

    linter := new Linter(LinterConfig.Default())
    diagnostics := linter.Lint(unit, "test.nl", source)
    census := ""
    for diagnostic in diagnostics {
        census = census + diagnostic.Code + "|" + diagnostic.Message + ";"
    }

    return census
}

test "A CONSTRUCTED TYPE WITH NO IMPORT REPORTS NL002 — AND THE SPAN IS THE TYPE NAME" {
    // THE PRODUCT DECISION THIS TEST WAS WAITING FOR HAS BEEN TAKEN. Its previous text read: "The
    // span is stated here, and stating it is what found that the squiggle covers `new` (column 14,
    // three characters) rather than the type name it is complaining about. That is pinned rather
    // than corrected: moving a reported span changes what every editor draws and is a product
    // decision, not a test migration."
    //
    // It is corrected now, and what the editor draws is the point of correcting it: VS Code offers a
    // quick fix only for a diagnostic whose range contains the cursor, so an NL002 anchored on `new`
    // put the "Add import" fix out of reach of anyone whose cursor was on the name the message
    // names. The span is now the base name and nothing else — `List`, not `new` and not `List<int>`.
    //
    // `tests/fixtures/diagnostics/top25.golden.txt` already rendered this diagnostic with four
    // carets under `List` at column 18 of the same line of text. The linter now agrees with the
    // golden the product ships.
    listSource := "\nfunc main() {\n    items := new List<int>()\n    x := items\n}"
    assert LmieCensus(listSource) == "NL002@3:18+4;NL001@4:5+1;"
    assert LmieMessages(listSource) == "NL002|'List' is used without the import that provides it;NL001|Variable 'x' is declared but never read;"

    builderSource := "\nfunc main() {\n    sb := new StringBuilder()\n    x := sb\n}"
    assert LmieCensus(builderSource) == "NL002@3:15+13;NL001@4:5+1;"
    assert LmieMessages(builderSource) == "NL002|'StringBuilder' is used without the import that provides it;NL001|Variable 'x' is declared but never read;"

    // THE ANCHOR SURVIVES A WRAPPER. `new StringBuilder[](2)` is an `ArrayTypeReference` around the
    // simple one, and `Base` unwraps it to answer `StringBuilder`; the span unwraps with it, so the
    // squiggle covers the element name rather than `StringBuilder[]` or, as before, `new`.
    arraySource := "\nfunc main() {\n    ys := new StringBuilder[](2)\n    x := ys\n}"
    assert LmieCensus(arraySource) == "NL002@3:15+13;NL001@4:5+1;"

    // NON-VACUITY FOR THE COLUMN, which no census on its own can give: the same construction moved
    // four columns to the right reports four columns to the right. A hard-coded anchor would not.
    indentedSource := "\nfunc main() {\n        items := new List<int>()\n        x := items\n}"
    assert LmieCensus(indentedSource) == "NL002@3:22+4;NL001@4:9+1;"
}

test "the import silences NL002, and REMOVING IT BRINGS THE SAME DIAGNOSTIC BACK" {
    // The absence claim, stated as a whole census so an unrelated diagnostic cannot hide inside it.
    assert LmieCensus("\nimport System.Collections.Generic\n\nfunc main() {\n    items := new List<int>()\n    x := items\n}") == "NL001@6:5+1;"

    // REMOVAL CONTROL: the identical body with the import line taken out. The NL001 moves up two
    // lines with the text and the NL002 appears, so the silence above is the import doing its job.
    assert LmieCensus("\nfunc main() {\n    items := new List<int>()\n    x := items\n}") == "NL002@3:18+4;NL001@4:5+1;"

    // And the same for System.Text, which the deleted file only ever asked in the reporting
    // direction.
    assert LmieCensus("\nimport System.Text\n\nfunc main() {\n    sb := new StringBuilder()\n    x := sb\n}") == "NL001@6:5+1;"
}

// ══════════════════════════════════════════════════════════════════════════════════════════════
// NL002 AT EVERY POSITION A TYPE CAN BE WRITTEN
//
// The rule used to be asked at exactly two places: a bare identifier, and the type of a `new`
// expression. Every other written type — a parameter, a return, a field, a property, a local's
// annotation, a base class, an interface, a positional record parameter, and every type argument
// inside any of them — was silent. `CheckMissingImportForType`'s own comment claimed otherwise
// ("a generic argument or an array element is reached by the walk in its own right"), and it was
// never true: the walk descends EXPRESSIONS, and a type argument is a `TypeReference`.
//
// MEASURED BEFORE THE CHANGE, because "silent" is a claim about the whole toolchain and not just
// about this rule: with `System.Text` unimported, `func takes(sb: StringBuilder) { sb.Append("x") }`
// produced no diagnostic from `nlc check` AND BUILT AND RAN. A genuinely unknown name in the same
// position is caught — `NotARealTypeAtAll` is NL201 "Type not found", anchored on the name — so the
// silence was never a resolution hole. NL002 is import HYGIENE, which the `new` position proves
// from the other side: with NL002 suppressed, `new StringBuilder()` without the import compiles and
// prints. The defect was that the hygiene rule inspected one syntactic position out of many.

test "NL002 covers a PARAMETER type, and lands on the type name" {
    assert LmieCensus("\nfunc takes(sb: StringBuilder): int {\n    return sb.Length\n}") == "NL002@2:16+13;"
}

test "NL002 covers a RETURN type" {
    assert LmieCensus("\nfunc make(): StringBuilder {\n    return null\n}") == "NL002@2:14+13;"
}

test "NL002 covers a FIELD type" {
    assert LmieCensus("\nclass Holder {\n    Buffer: StringBuilder\n}") == "NL002@3:13+13;"
}

test "NL002 covers a GENERIC ARGUMENT, which is the case the old comment claimed and never did" {
    // The enclosing generic is imported, so the only finding is the ARGUMENT — and it is anchored
    // on the argument, not on `List` and not on `new`.
    assert LmieCensus("\nimport System.Collections.Generic\n\nfunc make(): List<StringBuilder> {\n    return null\n}") == "NL002@4:19+13;"

    // Neither imported: two findings, base name first, each on its own columns.
    assert LmieCensus("\nfunc make(): List<StringBuilder> {\n    return null\n}") == "NL002@2:14+4;NL002@2:19+13;"
}

test "the import silences the newly covered positions too, which is the whole point of the rule" {
    // Non-vacuity for every one of them at once: the same four positions with both imports present
    // report nothing at all.
    covered := "\nimport System.Collections.Generic\nimport System.Text\n\nfunc takes(sb: StringBuilder): int {\n    return sb.Length\n}\n\nfunc make(): List<StringBuilder> {\n    return null\n}\n\nclass Holder {\n    Buffer: StringBuilder\n}"
    assert LmieCensus(covered) == ""
}

test "NL002's bare-identifier span STOPS AT THE IDENTIFIER, and does not run the member chain in" {
    // `DiagnosticSpanResolver` covers a whole dotted chain when it is asked to infer an extent, and
    // that is correct for a diagnostic about the chain — `foo.bar.baz` is one span, and the resolver
    // has its own contract saying so. It is wrong here: the message names `StringBuilder`, so the
    // squiggle covered `StringBuilder.ToString` (22 columns) and the import fix was offered on
    // `.ToString` too. The rule now states the identifier's own length rather than asking.
    dotted := "\nfunc main() {\n    print(StringBuilder.ToString())\n}"
    assert LmieCensus(dotted) == "NL002@3:11+13;"
    assert LmieMessages(dotted) == "NL002|'StringBuilder' is used without the import that provides it;"

    // CONTROL, and it is the one that says the resolver was not broken to get here: an identifier
    // with nothing after it was always right, and is unchanged at the same thirteen columns.
    bare := "\nfunc main() {\n    let sb = StringBuilder\n    print(sb)\n}"
    assert LmieCensus(bare) == "NL002@3:14+13;"

    // And the RESOLVER'S own rule still runs a chain together for the callers that want it, which is
    // why it was left alone: this is the same source line, asked of the resolver directly.
    assert DiagnosticSpanContractCovers("StringBuilder.ToString()", 1, "StringBuilder.ToString")
}

// THE SENTENCE STOPPED CLAIMING THE COMPILER CANNOT FIND THE NAME, BECAUSE IT ALWAYS CAN. Measured on
// the shipped CLI with the rule silenced, every row of this table resolves: `StringBuilder`, `Task`,
// `CancellationToken`, `List<int>` and `Stack<int>` BUILD with no import, and the rows that
// fail — `Regex`, `HttpClient`, `Queue<int>` — fail identically WITH their import, because the
// backend cannot lower those types yet. `tests/native/diagnostic-honesty` runs both sides on every
// gate.
test "NL002's sentence states what is true of EVERY row: the name is used, the import is not there" {
    assert LinterMissingImport.Message("StringBuilder") == "'StringBuilder' is used without the import that provides it"
    assert LinterMissingImport.Message("List") == "'List' is used without the import that provides it"

    // The claim it no longer makes, and the half that was always true and is unchanged.
    assert LinterMissingImport.Message("StringBuilder").IndexOf("can't find", StringComparison.Ordinal) < 0
    assert LinterMissingImport.Suggestion("System.Text") == "Add 'import System.Text' at the top of the file"
}
