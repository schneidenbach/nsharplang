namespace NSharpLang.Compiler

import System.Collections.Generic


// THE CONTRACTS FOR THE OWNER THAT SAYS WHAT A QUALIFIED MEMBER NAME MEANS.
//
// THREE STRINGS, AND THEY ARE NOT THE SAME STRING. The DECLARED spelling
// (`IEnumerable.GetEnumerator`) is what the source writes and what every member table is keyed by —
// which is what keeps the member off the declaring type's surface. The METADATA name
// (`System.Collections.IEnumerable.GetEnumerator`) is what the CLR carries. The SIMPLE name
// (`GetEnumerator`) is what the interface declares its slot under, and it is what the slot match is
// made on. Confusing any two of them is a silently wrong program, so each is pinned here.
test "the separator is the LAST dot at angle depth zero" {
    assert ExplicitInterfaceMemberFacts.IsExplicitMemberName("IEnumerable.GetEnumerator")
    assert ExplicitInterfaceMemberFacts.QualifierOf("IEnumerable.GetEnumerator") == "IEnumerable"
    assert ExplicitInterfaceMemberFacts.SimpleNameOf("IEnumerable.GetEnumerator") == "GetEnumerator"

    // A NAMESPACE-QUALIFIED interface: the dots before the last one are the qualifier's own.
    assert ExplicitInterfaceMemberFacts.QualifierOf("System.Collections.IEnumerable.GetEnumerator") == "System.Collections.IEnumerable"
    assert ExplicitInterfaceMemberFacts.SimpleNameOf("System.Collections.IEnumerable.GetEnumerator") == "GetEnumerator"

    // A DOT INSIDE A TYPE ARGUMENT IS NOT A SEPARATOR, which is why the scan counts angle depth
    // rather than searching for the last dot in the string.
    assert ExplicitInterfaceMemberFacts.QualifierOf("IBox<System.Guid>.Unwrap") == "IBox<System.Guid>"
    assert ExplicitInterfaceMemberFacts.SimpleNameOf("IBox<System.Guid>.Unwrap") == "Unwrap"
    assert ExplicitInterfaceMemberFacts.SimpleNameOf("IMap<string,List<System.Guid>>.Add") == "Add"
}

test "an ordinary member name is not a qualified one, and answers itself" {
    assert !ExplicitInterfaceMemberFacts.IsExplicitMemberName("GetEnumerator")
    assert !ExplicitInterfaceMemberFacts.IsExplicitMemberName("")
    assert !ExplicitInterfaceMemberFacts.IsExplicitMemberName(".Leading")
    assert !ExplicitInterfaceMemberFacts.IsExplicitMemberName("Trailing.")
    assert !ExplicitInterfaceMemberFacts.IsExplicitMemberName("op_Implicit")

    // `SimpleNameOf` answers the name itself for an unqualified one, so a caller may ask
    // unconditionally; `QualifierOf` answers EMPTY, so a caller that forgot to ask gets nothing
    // rather than a wrong half.
    assert ExplicitInterfaceMemberFacts.SimpleNameOf("GetEnumerator") == "GetEnumerator"
    assert ExplicitInterfaceMemberFacts.QualifierOf("GetEnumerator") == ""
}

test "a qualifier reports its open name, its simple name and its arity" {
    assert ExplicitInterfaceMemberFacts.QualifierOpenName("IEnumerable") == "IEnumerable"
    assert ExplicitInterfaceMemberFacts.QualifierOpenName("IEnumerable<string>") == "IEnumerable"
    assert ExplicitInterfaceMemberFacts.QualifierSimpleName("System.Collections.Generic.IEnumerable<string>") == "IEnumerable"

    assert ExplicitInterfaceMemberFacts.QualifierArity("IEnumerable") == 0
    assert ExplicitInterfaceMemberFacts.QualifierArity("IEnumerable<string>") == 1
    assert ExplicitInterfaceMemberFacts.QualifierArity("IDictionary<string,int>") == 2

    // NESTED ARGUMENTS DO NOT ADD TO THE COUNT — the commas inside them are at depth two, and an
    // arity that counted them would refuse a correctly written qualifier.
    assert ExplicitInterfaceMemberFacts.QualifierArity("IDictionary<string,List<int>>") == 2
    assert ExplicitInterfaceMemberFacts.QualifierArity("ICollection<KeyValuePair<string,int>>") == 1

    assert !ExplicitInterfaceMemberFacts.QualifierIsConstructed("IEnumerable")
    assert ExplicitInterfaceMemberFacts.QualifierIsConstructed("IEnumerable<string>")
}

test "the metadata name is the interface as METADATA spells it, measured against the BCL" {
    // THESE TWO NAMES WERE READ OUT OF `System.Private.CoreLib`, not invented. `List<T>` really does
    // carry `System.Collections.IEnumerable.GetEnumerator`, and `Dictionary<TKey, TValue>` really
    // does carry the second one — type arguments fully qualified, no space after the comma. A C#
    // consumer of an N# assembly looks for exactly these.
    listType := typeof(List<string>)
    untypedEnumerable := typeof(System.Collections.IEnumerable)
    assert ExplicitInterfaceMemberFacts.RuntimeInterfaceDisplayName(untypedEnumerable) == "System.Collections.IEnumerable"
    assert ExplicitInterfaceMemberFacts.MetadataName(ExplicitInterfaceMemberFacts.RuntimeInterfaceDisplayName(untypedEnumerable), "GetEnumerator") == "System.Collections.IEnumerable.GetEnumerator"

    closedEnumerable := typeof(IEnumerable<string>)
    assert ExplicitInterfaceMemberFacts.RuntimeInterfaceDisplayName(closedEnumerable) == "System.Collections.Generic.IEnumerable<System.String>"

    nested := typeof(ICollection<KeyValuePair<string, int>>)
    assert ExplicitInterfaceMemberFacts.RuntimeInterfaceDisplayName(nested) == "System.Collections.Generic.ICollection<System.Collections.Generic.KeyValuePair<System.String,System.Int32>>"

    // An OPEN definition renders its type PARAMETERS by their bare names, which is what the BCL's own
    // `System.Collections.Generic.IEnumerable<T>.GetEnumerator` on `List<T>` shows.
    openDefinition := listType.GetGenericTypeDefinition().GetInterfaces()[0]
    assert openDefinition != null
}

test "an accessor's prefix goes INSIDE the qualification" {
    // `System.Collections.IList.get_Item`, not `get_System.Collections.IList.Item`. The second is a
    // name no consumer looks for, and the difference is invisible to everything except a caller.
    assert ExplicitInterfaceMemberFacts.MetadataAccessorName("System.Collections.IList", "get_", "Item") == "System.Collections.IList.get_Item"
    assert ExplicitInterfaceMemberFacts.MetadataAccessorName("Sample.ILabeled", "set_", "Label") == "Sample.ILabeled.set_Label"
}

test "the tree reading finds the same extent the columnar one does" {
    lexer := new Lexer("func IEnumerable<string>.GetEnumerator(): IEnumerator {", "probe.nl")
    tokens := lexer.Tokenize()

    // Token 0 is `func`, so the name starts at 1.
    nameEnd := ExplicitInterfaceMemberFacts.QualifiedMemberNameEnd(tokens, 1)
    assert nameEnd > 1
    assert ExplicitInterfaceMemberFacts.QualifiedMemberNameText(tokens, 1, nameEnd) == "IEnumerable<string>.GetEnumerator"

    // A GENERIC METHOD IS NOT A QUALIFIED NAME. `Compare<T>(` is an argument list with no dot behind
    // it, and answering anything but -1 here would swallow the type-parameter list the owner that has
    // always parsed it is about to read.
    genericLexer := new Lexer("func Compare<T>(left: T, right: T): int {", "probe.nl")
    genericTokens := genericLexer.Tokenize()
    assert ExplicitInterfaceMemberFacts.QualifiedMemberNameEnd(genericTokens, 1) == -1

    plainLexer := new Lexer("func Read(): string {", "probe.nl")
    plainTokens := plainLexer.Tokenize()
    assert ExplicitInterfaceMemberFacts.QualifiedMemberNameEnd(plainTokens, 1) == -1
}
