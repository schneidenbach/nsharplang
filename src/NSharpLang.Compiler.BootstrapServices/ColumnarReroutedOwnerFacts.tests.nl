namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit
import System.Text.Json


// 015-A1 rerouted the emitter's private C# spellings of these five members to their N# owners and
// DELETED the C#. That makes each owner the compiler's SOLE authority for its answer, and A0's
// differential -- which compared the two implementations against each other -- can no longer be run
// on them, because there is no second implementation left to compare against. These contracts are
// what replaces it: they pin the answers the emitter now depends on, in the owner, natively.
//
// (`IsRuntimeInterfaceType` and `SubstituteClosedTypeArguments`, the other two A1 members, are
// already pinned in ColumnarTypeAdmissibilityFacts.tests.nl and are not repeated here.)
func ReroutedStructDef(name: string, isInterface: bool): ColumnarStructDef {
    builder := TypeOfCreateBuilder(name, "ReroutedOwnerFactsAsm", 0)
    definition := new ColumnarStructDef(builder, new string[](0), new Dictionary<string, FieldBuilder>(StringComparer.Ordinal), true, false, false, name)
    definition.IsInterface = isInterface
    return definition
}

// `Type.GetType("System.Text.Json.JsonProperty")` answers NULL on the estate test host (the same
// probing-path limit A0 recorded for NSharpLang.Runtime), so the nested and non-generic Json shapes
// are reached through the assembly that certainly IS loaded -- the one `typeof(JsonElement)` names.
func ReroutedJsonType(fullName: string): Type {
    result := typeof(JsonElement).get_Assembly().GetType(fullName)
    if result == null {
        throw new InvalidOperationException("Rerouted-owner fixture Json type '" + fullName + "' was not found.")
    }
    return result
}

func ReroutedNames(definitions: List<ColumnarStructDef>): string {
    builder := new System.Text.StringBuilder()
    index := 0
    while index < definitions.Count {
        if index > 0 {
            builder.Append(',')
        }
        builder.Append(definitions[index].DeclaredTypeName)
        index = index + 1
    }
    return builder.ToString()
}

// A union canonical is split at the TOP level only: a pipe nested inside <>, () or [] belongs to the
// nested type, not to the union. The emitter resolves anonymous-union arms from this list, so an
// off-by-one here is a wrong TYPE, not a wrong message.
test "top-level pipe splitting keeps nested pipes inside their brackets" {
    twoArms := ColumnarTypeOfPlanner.SplitTopLevelPipes("int|string")
    assert twoArms.Count == 2
    assert twoArms[0] == "int"
    assert twoArms[1] == "string"

    // No top-level pipe at all yields the EMPTY list, not a one-element list -- the caller tests
    // `Count == 2` and a one-element answer would silently change which branch it takes.
    assert ColumnarTypeOfPlanner.SplitTopLevelPipes("int").Count == 0
    assert ColumnarTypeOfPlanner.SplitTopLevelPipes("").Count == 0

    nested := ColumnarTypeOfPlanner.SplitTopLevelPipes("List<int|string>|bool")
    assert nested.Count == 2
    assert nested[0] == "List<int|string>"
    assert nested[1] == "bool"

    parens := ColumnarTypeOfPlanner.SplitTopLevelPipes("(int|string)|bool")
    assert parens.Count == 2
    assert parens[0] == "(int|string)"

    brackets := ColumnarTypeOfPlanner.SplitTopLevelPipes("int[]|string")
    assert brackets.Count == 2
    assert brackets[0] == "int[]"

    // Three arms, and the leading/trailing empty arms are preserved rather than trimmed away.
    three := ColumnarTypeOfPlanner.SplitTopLevelPipes("a|b|c")
    assert three.Count == 3
    assert three[2] == "c"

    leading := ColumnarTypeOfPlanner.SplitTopLevelPipes("|b")
    assert leading.Count == 2
    assert leading[0] == ""

    trailing := ColumnarTypeOfPlanner.SplitTopLevelPipes("a|")
    assert trailing.Count == 2
    assert trailing[1] == ""

    // An unbalanced closer does not underflow the depth counter into a negative state.
    unbalanced := ColumnarTypeOfPlanner.SplitTopLevelPipes("a>b|c")
    assert unbalanced.Count == 2
    assert unbalanced[0] == "a>b"
}

// The modeled positional ValueTuple surface is arity 2..7. Arity 1 and the >7 nested-TRest form are
// NOT modeled, and the emitter declines on the null rather than constructing a wrong tuple.
test "open ValueTuple definitions cover exactly arity two through seven" {
    assert ColumnarTypeOfPlanner.OpenValueTupleType(2) == typeof(ValueTuple<int, int>).GetGenericTypeDefinition()
    assert ColumnarTypeOfPlanner.OpenValueTupleType(3) == typeof(ValueTuple<int, int, int>).GetGenericTypeDefinition()
    assert ColumnarTypeOfPlanner.OpenValueTupleType(4) == typeof(ValueTuple<int, int, int, int>).GetGenericTypeDefinition()
    assert ColumnarTypeOfPlanner.OpenValueTupleType(5) == typeof(ValueTuple<int, int, int, int, int>).GetGenericTypeDefinition()
    assert ColumnarTypeOfPlanner.OpenValueTupleType(6) == typeof(ValueTuple<int, int, int, int, int, int>).GetGenericTypeDefinition()
    assert ColumnarTypeOfPlanner.OpenValueTupleType(7) == typeof(ValueTuple<int, int, int, int, int, int, int>).GetGenericTypeDefinition()

    // Every returned definition is OPEN and carries exactly its arity's parameters.
    assert ColumnarTypeOfPlanner.OpenValueTupleType(4).get_IsGenericTypeDefinition()
    assert ColumnarTypeOfPlanner.OpenValueTupleType(4).GetGenericArguments().Length == 4

    assert ColumnarTypeOfPlanner.OpenValueTupleType(-1) == null
    assert ColumnarTypeOfPlanner.OpenValueTupleType(0) == null
    assert ColumnarTypeOfPlanner.OpenValueTupleType(1) == null
    assert ColumnarTypeOfPlanner.OpenValueTupleType(8) == null
    assert ColumnarTypeOfPlanner.OpenValueTupleType(9) == null
}

// JSON identities use the same catalog admission rule, including nested metadata names. The
// array-element guard remains a separate lowering fact.
test "JSON external value identities use general catalog admission" {
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(JsonElement))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(JsonDocument))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(JsonValueKind))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(JsonSerializerOptions))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(JsonNamingPolicy))
    assert ColumnarTypeOfPlanner.IsSupportedType(ReroutedJsonType("System.Text.Json.JsonProperty"))
    assert ColumnarTypeOfPlanner.IsSupportedType(ReroutedJsonType("System.Text.Json.JsonElement+ArrayEnumerator"))
    assert ColumnarTypeOfPlanner.IsSupportedType(ReroutedJsonType("System.Text.Json.JsonElement+ObjectEnumerator"))

    // Neighbouring catalog identities need no new admission row.
    assert ColumnarTypeOfPlanner.IsSupportedType(ReroutedJsonType("System.Text.Json.JsonSerializer"))
    assert ColumnarTypeOfPlanner.IsSupportedType(ReroutedJsonType("System.Text.Json.JsonException"))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(string))
    assert ColumnarTypeOfPlanner.IsSupportedType(typeof(int))
    // This structural array guard is unchanged by admitting external identities.
    assert !ColumnarTypeOfPlanner.IsSupportedType(typeof(JsonElement).MakeArrayType())
}

// Both the SHORT and the fully-qualified spelling of each modeled external head resolve to the same
// handle. THE OUT-SLOT CONTRACT IS PART OF THIS: on the FALSE path the owner leaves typeof(object)
// in the slot, not null, so every caller must read the slot only when the bool is true. The emitter's
// one call site copies through a local for exactly this reason.
test "known external heads resolve under both spellings and leave object on the false path" {
    resolved := typeof(object)
    assert ColumnarTypeOfPlanner.TryResolveKnownExternalType("JsonElement", out resolved)
    assert resolved == typeof(JsonElement)
    assert ColumnarTypeOfPlanner.TryResolveKnownExternalType("System.Text.Json.JsonElement", out resolved)
    assert resolved == typeof(JsonElement)
    assert ColumnarTypeOfPlanner.TryResolveKnownExternalType("JsonDocument", out resolved)
    assert resolved == typeof(JsonDocument)
    assert ColumnarTypeOfPlanner.TryResolveKnownExternalType("JsonValueKind", out resolved)
    assert resolved == typeof(JsonValueKind)
    assert ColumnarTypeOfPlanner.TryResolveKnownExternalType("System.Text.Json.JsonSerializerOptions", out resolved)
    assert resolved == typeof(JsonSerializerOptions)
    assert ColumnarTypeOfPlanner.TryResolveKnownExternalType("JsonNamingPolicy", out resolved)
    assert resolved == typeof(JsonNamingPolicy)

    // The Yaml heads resolve through the referenced assembly by name.
    assert ColumnarTypeOfPlanner.TryResolveKnownExternalType("IYamlTypeConverter", out resolved)
    assert resolved.FullName == "YamlDotNet.Serialization.IYamlTypeConverter"
    assert ColumnarTypeOfPlanner.TryResolveKnownExternalType("YamlDotNet.Core.Events.Scalar", out resolved)
    assert resolved.FullName == "YamlDotNet.Core.Events.Scalar"
    assert ColumnarTypeOfPlanner.TryResolveKnownExternalType("DeserializerBuilder", out resolved)
    assert resolved.FullName == "YamlDotNet.Serialization.DeserializerBuilder"

    // MISSES: the bool is false AND the slot holds System.Object, never null. This is the exact
    // hazard the emitter's call site guards, so it is pinned rather than left to memory.
    resolved = typeof(string)
    assert !ColumnarTypeOfPlanner.TryResolveKnownExternalType("NotAModeledType", out resolved)
    assert resolved == typeof(object)
    assert resolved != null

    resolved = typeof(string)
    assert !ColumnarTypeOfPlanner.TryResolveKnownExternalType("", out resolved)
    assert resolved == typeof(object)

    resolved = typeof(string)
    assert !ColumnarTypeOfPlanner.TryResolveKnownExternalType("int", out resolved)
    assert resolved == typeof(object)
}

// Pre-order DFS over an interface's transitive bases, self FIRST. The emitter registers real CLR
// interface metadata from this walk, so both the ORDER and the duplicate-on-a-diamond behaviour are
// contract, not incidental: a diamond must yield the shared base TWICE because the caller dedups by
// builder identity and would otherwise depend on the walk to do it.
test "interface base enumeration is a pre-order walk that keeps diamond duplicates" {
    root := ReroutedStructDef("ReroutedRoot", true)
    single := new List<ColumnarStructDef>()
    ColumnarBaseTypePlanner.EnumerateInterfaceAndBases(root, single)
    assert single.Count == 1
    assert ReroutedNames(single) == "ReroutedRoot"

    baseA := ReroutedStructDef("ReroutedBaseA", true)
    baseB := ReroutedStructDef("ReroutedBaseB", true)
    derived := ReroutedStructDef("ReroutedDerived", true)
    derived.InterfaceBases.Add(baseA)
    derived.InterfaceBases.Add(baseB)

    chained := new List<ColumnarStructDef>()
    ColumnarBaseTypePlanner.EnumerateInterfaceAndBases(derived, chained)
    assert chained.Count == 3
    assert ReroutedNames(chained) == "ReroutedDerived,ReroutedBaseA,ReroutedBaseB"

    // Depth before breadth: a base's OWN base is visited before the next sibling.
    grandBase := ReroutedStructDef("ReroutedGrandBase", true)
    baseA.InterfaceBases.Add(grandBase)
    deep := new List<ColumnarStructDef>()
    ColumnarBaseTypePlanner.EnumerateInterfaceAndBases(derived, deep)
    assert deep.Count == 4
    assert ReroutedNames(deep) == "ReroutedDerived,ReroutedBaseA,ReroutedGrandBase,ReroutedBaseB"

    // A DIAMOND yields the shared base twice, in both arms.
    baseB.InterfaceBases.Add(grandBase)
    diamond := new List<ColumnarStructDef>()
    ColumnarBaseTypePlanner.EnumerateInterfaceAndBases(derived, diamond)
    assert diamond.Count == 5
    assert ReroutedNames(diamond) == "ReroutedDerived,ReroutedBaseA,ReroutedGrandBase,ReroutedBaseB,ReroutedGrandBase"

    // The output list is APPENDED to, never cleared -- the emitter's sites reuse fresh lists, but
    // the contract is that prior contents survive.
    seeded := new List<ColumnarStructDef>()
    seeded.Add(root)
    ColumnarBaseTypePlanner.EnumerateInterfaceAndBases(baseB, seeded)
    assert seeded.Count == 3
    assert seeded[0].DeclaredTypeName == "ReroutedRoot"
    assert seeded[1].DeclaredTypeName == "ReroutedBaseB"
}
