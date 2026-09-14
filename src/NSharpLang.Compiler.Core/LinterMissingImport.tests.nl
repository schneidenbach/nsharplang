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

// ══════════════════════════════════════════════════════════════════════════════════════════════
// NL002 — THE OTHER READING OF NL010'S FACT
//
// These replace 270 lines that pinned two TABLES: a 25-name identifier whitelist, a 16-name type
// whitelist, the subset relation between them, and the namespace each row mapped to. Every one of
// those assertions was about a list of BCL spellings that could not be finished, and the census
// proved the cost: `OperatingSystem.IsWindows()` written with no `import System` was accepted in
// silence, because the list had never heard of the name — while the same file WITH the import had
// NL010 report the import dead, for the same reason.
//
// The rule now answers from what the analyzer BOUND. `ImportUsageFacts` records the namespace that
// supplied each name the file wrote; if the file imports it the import is used (NL010 quiet), and if
// it does not, this rule speaks. What is pinned here is that decision — four independent silencers
// and nothing else — and the two sentences.

func LmiFacts(name: string, supplier: string): ImportUsageFacts {
    facts := new ImportUsageFacts()
    facts.CreditName(name, supplier)
    facts.Analyzed = true
    return facts
}

func LmiIncompleteFacts(name: string, supplier: string): ImportUsageFacts {
    facts := new ImportUsageFacts()
    facts.CreditName(name, supplier)
    return facts
}

// ── which namespace the analysis says a name needs ───────────────────────────────────────────

test "the supplier is the namespace the analysis recorded for the name" {
    assert LinterMissingImport.SupplyingNamespace(LmiFacts("StringBuilder", "System.Text"), "StringBuilder") == "System.Text"
}

test "NOTHING ABOUT THE NAME MATTERS, which is the whole difference from the table" {
    // `OperatingSystem` was in neither of the deleted tables, and neither is `Contoso.Widget`.
    assert LinterMissingImport.SupplyingNamespace(LmiFacts("OperatingSystem", "System"), "OperatingSystem") == "System"
    assert LinterMissingImport.SupplyingNamespace(LmiFacts("Widget", "Contoso.Widgets"), "Widget") == "Contoso.Widgets"
}

test "a name the analysis did not record has no supplier, and silence is the answer" {
    // A local, a member, a type parameter, a source declaration, or a name that did not resolve at
    // all: none of them needs an import, and none of them is this rule's business.
    assert LinterMissingImport.SupplyingNamespace(LmiFacts("StringBuilder", "System.Text"), "total") == null
}

test "a file that was NEVER ANALYSED has no supplier for any name" {
    assert LinterMissingImport.SupplyingNamespace(null, "StringBuilder") == null
}

test "a file whose analysis did not COMPLETE has none either" {
    assert LinterMissingImport.SupplyingNamespace(LmiIncompleteFacts("StringBuilder", "System.Text"), "StringBuilder") == null
}

test "the lookup is ORDINAL: a spelling differing in case is a different name" {
    assert LinterMissingImport.SupplyingNamespace(LmiFacts("StringBuilder", "System.Text"), "stringbuilder") == null
}

test "the FIRST namespace to supply a name keeps it" {
    // A spelling that resolves through two namespaces in one file is an ambiguity NL209 reports;
    // this rule does not get a second opinion about which import to suggest.
    facts := new ImportUsageFacts()
    facts.CreditName("Widget", "Contoso.Widgets")
    facts.CreditName("Widget", "Fabrikam.Widgets")
    facts.Analyzed = true
    assert LinterMissingImport.SupplyingNamespace(facts, "Widget") == "Contoso.Widgets"
}

// ── the decision ─────────────────────────────────────────────────────────────────────────────

test "a name written with no import at all is reported, with the namespace that supplies it" {
    assert LinterMissingImport.MissingNamespaceForTypeName("StringBuilder", LmiFacts("StringBuilder", "System.Text"), LmiNoSymbols(), LmiNoNamespaces()) == "System.Text"
}

test "an already-imported namespace silences its own names and nothing else" {
    facts := new ImportUsageFacts()
    facts.CreditName("StringBuilder", "System.Text")
    facts.CreditName("List", "System.Collections.Generic")
    facts.Analyzed = true
    imported := LmiOneNamespace("System.Text")

    assert LinterMissingImport.MissingNamespaceForTypeName("StringBuilder", facts, LmiNoSymbols(), imported) == null
    assert LinterMissingImport.MissingNamespaceForTypeName("List", facts, LmiNoSymbols(), imported) == "System.Collections.Generic"
}

test "importing System does NOT silence System.Text, because the match is exact" {
    assert LinterMissingImport.MissingNamespaceForTypeName("StringBuilder", LmiFacts("StringBuilder", "System.Text"), LmiNoSymbols(), LmiOneNamespace("System")) == "System.Text"
}

test "a FILE import of the same symbol name silences the rule for that name alone" {
    facts := LmiFacts("StringBuilder", "System.Text")
    assert LinterMissingImport.MissingNamespaceForTypeName("StringBuilder", facts, LmiOneSymbol("StringBuilder"), LmiNoNamespaces()) == null
    assert LinterMissingImport.MissingNamespaceForTypeName("StringBuilder", facts, LmiOneSymbol("Helpers"), LmiNoNamespaces()) == "System.Text"
}

test "an enclosing type's own member silences the IDENTIFIER arm, and only that arm" {
    facts := LmiFacts("StringBuilder", "System.Text")
    assert LinterMissingImport.MissingNamespaceForIdentifier("StringBuilder", facts, LmiOneScope("StringBuilder"), LmiNoSymbols(), LmiNoNamespaces()) == null

    // The TYPE arm never consults the member scopes: a `new` names a type, and a member cannot
    // shadow one.
    assert LinterMissingImport.MissingNamespaceForTypeName("StringBuilder", facts, LmiNoSymbols(), LmiNoNamespaces()) == "System.Text"
}

test "the member-scope check asks EVERY enclosing frame, not just the innermost" {
    facts := LmiFacts("StringBuilder", "System.Text")
    scopes := LmiScopes(["StringBuilder", "other"])
    assert LinterMissingImport.MissingNamespaceForIdentifier("StringBuilder", facts, scopes, LmiNoSymbols(), LmiNoNamespaces()) == null
}

test "no member scopes at all is not the same as a scope containing nothing, and both stay silent about nothing" {
    facts := LmiFacts("StringBuilder", "System.Text")
    assert LinterMissingImport.MissingNamespaceForIdentifier("StringBuilder", facts, LmiNoScopes(), LmiNoSymbols(), LmiNoNamespaces()) == "System.Text"
    assert LinterMissingImport.MissingNamespaceForIdentifier("StringBuilder", facts, LmiEmptyScope(), LmiNoSymbols(), LmiNoNamespaces()) == "System.Text"
}

test "the silencers compose: any one of the four is enough on its own" {
    facts := LmiFacts("StringBuilder", "System.Text")
    assert LinterMissingImport.MissingNamespaceForIdentifier("StringBuilder", null, LmiNoScopes(), LmiNoSymbols(), LmiNoNamespaces()) == null
    assert LinterMissingImport.MissingNamespaceForIdentifier("StringBuilder", facts, LmiOneScope("StringBuilder"), LmiNoSymbols(), LmiNoNamespaces()) == null
    assert LinterMissingImport.MissingNamespaceForIdentifier("StringBuilder", facts, LmiNoScopes(), LmiOneSymbol("StringBuilder"), LmiNoNamespaces()) == null
    assert LinterMissingImport.MissingNamespaceForIdentifier("StringBuilder", facts, LmiNoScopes(), LmiNoSymbols(), LmiOneNamespace("System.Text")) == null

    // Non-vacuity: with none of them, the same call reports.
    assert LinterMissingImport.MissingNamespaceForIdentifier("StringBuilder", facts, LmiNoScopes(), LmiNoSymbols(), LmiNoNamespaces()) == "System.Text"
}

// ── what the diagnostic says ─────────────────────────────────────────────────────────────────

test "the message names the identifier and the suggestion names the import to add" {
    assert LinterMissingImport.Message("StringBuilder") == "'StringBuilder' is used without the import that provides it"
    assert LinterMissingImport.Suggestion("System.Text") == "Add 'import System.Text' at the top of the file"
}

test "the sentence states what is true of EVERY finding: the name is used, the import is not there" {
    // NL002 IS IMPORT HYGIENE, not a resolution failure: the name resolved — that is how the
    // namespace is known — and what is missing is the import that should have provided it.
    assert LinterMissingImport.Message("OperatingSystem").Contains("is used without the import that provides it")
    assert !LinterMissingImport.Message("OperatingSystem").Contains("not found")
}

test "the suggestion is composed from the NAMESPACE the decision returned, never from the name" {
    assert LinterMissingImport.Suggestion("Contoso.Widgets") == "Add 'import Contoso.Widgets' at the top of the file"
}
