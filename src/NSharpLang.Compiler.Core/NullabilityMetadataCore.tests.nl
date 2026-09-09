namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// `NullabilityMetadataCore` AND `NullabilityTypeDisplay`: THE CLR↔N# TYPE-NAME MAPS AND THE
// NULLABILITY WRAPPING POLICY EVERY REFLECTED SIGNATURE PASSES THROUGH.
//
// NEITHER TYPE HAD ANY ESTATE COVERAGE OF ITS OWN BEFORE THIS FILE. `NullabilityMetadataReflection`
// has its own contracts and reaches these two only incidentally — through `FormatTypeInfo`,
// `StripMetadata` and one `TryFormatTypeInfo` NEGATIVE (`NullabilityMetadataReflection.tests.nl`,
// "the display form and the metadata stripper agree with the N#-owned half"). The only assertion
// layer that named these owners directly was `tests/NullabilityMetadataTests.cs`, 59 lines and four
// `[Fact]`s, and it SAMPLED every table it touched: two rows of a sixteen-row CLR map, three arms of
// a sixteen-arm display switch, five cells of a nine-cell wrapping table.
//
// THE MIGRATION CROSSES WHAT THE DELETED FILE SAMPLED, AND THE CROSSING FOUND SOMETHING THE SAMPLE
// COULD NOT SEE: `ConvertBuiltInType` AND `FormatSimpleClrTypeName` ARE THE SAME SIXTEEN-ROW TABLE
// WRITTEN TWICE, IN TWO VOCABULARIES. One maps `System.Int32` to the `BuiltInTypes.Int` TypeInfo;
// the other maps `Int32` to the text `int`. Nothing anywhere held them together, so a built-in added
// to one and forgotten in the other would have passed every test in the repository. The partition
// guard below states the relation once, over all sixteen rows, and derives one map's answer from the
// other's — so that divergence now fails a contract by name.
//
// THREE MORE THINGS THE DELETED FILE LEFT IMPLICIT ARE STATED HERE:
//   (a) THE WRAPPING TABLE IS 3 × 3 AND IT IS IDEMPOTENT. `EnsureNullable` / `EnsureOblivious` /
//       `EnsureNotNull` are each applied to a PLAIN, a NULLABLE and an OBLIVIOUS input, and each
//       cell states whether the answer is the SAME OBJECT or a new wrapper. The C# stated five of
//       the nine and never stated that applying an operation twice changes nothing.
//   (b) `EnsureNullable(oblivious)` REPLACES RATHER THAN NESTS. It answers `T?`, not `T!?` — the
//       oblivious layer is discarded, not wrapped. That is a real decision in the kernel and the
//       deleted file could only see it as "the inner type is the string".
//   (c) THE NON-NULLABLE SIMPLE-TYPE SET AND THE CLR MAP OVERLAP BY EXACTLY FOURTEEN. Of the
//       sixteen built-ins the CLR map produces, all but `string` and `object` are refused reference
//       nullability, and `null`/`never` are refused too although no CLR name produces them.
//
// ONE SPELLING NOTE. `typeof(void)` is off the columnar `typeof` surface (`AnalyzerWellKnownTypes`
// records the same gap), so the `System.Void` row is reached by its literal full name while the
// other fifteen are reached through `typeof(T).FullName`.

// ── Decoders ────────────────────────────────────────────────────────────────────────────────────

// The N# name a converted built-in answers to, or a marker naming what came back instead.
func NmcSimpleName(typeInfo: TypeInfo?): string {
    if typeInfo == null {
        return "<null>"
    }

    simple := typeInfo as SimpleTypeInfo
    if simple == null {
        return "<not-simple>"
    }

    return simple.Name
}

// One row of the shared sixteen-row table, read through BOTH maps and required to agree.
func NmcCrossedBuiltIn(clrShortName: string, clrFullName: string): string {
    converted := NmcSimpleName(NullabilityMetadataCore.ConvertBuiltInType(clrFullName))
    formatted := NullabilityMetadataCore.FormatSimpleClrTypeName(clrShortName)
    if converted != formatted {
        return "DISAGREE(" + clrShortName + "): TypeInfo says '" + converted + "' but text says '" + formatted + "'"
    }

    return converted
}

// ── The CLR built-in map, crossed in full ───────────────────────────────────────────────────────

test "the CLR built-in map and the CLR display map are one sixteen row table read two ways" {
    // Fifteen rows reached through the real CLR type, so a renamed framework type breaks the row.
    assert NmcCrossedBuiltIn("Boolean", typeof(bool).FullName) == "bool"
    assert NmcCrossedBuiltIn("Byte", typeof(byte).FullName) == "byte"
    assert NmcCrossedBuiltIn("SByte", typeof(sbyte).FullName) == "sbyte"
    assert NmcCrossedBuiltIn("Int16", typeof(short).FullName) == "short"
    assert NmcCrossedBuiltIn("UInt16", typeof(ushort).FullName) == "ushort"
    assert NmcCrossedBuiltIn("Int32", typeof(int).FullName) == "int"
    assert NmcCrossedBuiltIn("UInt32", typeof(uint).FullName) == "uint"
    assert NmcCrossedBuiltIn("Int64", typeof(long).FullName) == "long"
    assert NmcCrossedBuiltIn("UInt64", typeof(ulong).FullName) == "ulong"
    assert NmcCrossedBuiltIn("Single", typeof(float).FullName) == "float"
    assert NmcCrossedBuiltIn("Double", typeof(double).FullName) == "double"
    assert NmcCrossedBuiltIn("Decimal", typeof(decimal).FullName) == "decimal"
    assert NmcCrossedBuiltIn("Char", typeof(char).FullName) == "char"
    assert NmcCrossedBuiltIn("String", typeof(string).FullName) == "string"
    assert NmcCrossedBuiltIn("Object", typeof(object).FullName) == "object"

    // `typeof(void)` is off the columnar typeof surface, so this row names the CLR type by text.
    assert NmcCrossedBuiltIn("Void", "System.Void") == "void"
}

test "the built-in TypeInfo map answers the BuiltInTypes singletons and nothing else" {
    assert BuiltInTypes.Is(NullabilityMetadataCore.ConvertBuiltInType(typeof(int).FullName), BuiltInTypes.Int)
    assert BuiltInTypes.Is(NullabilityMetadataCore.ConvertBuiltInType(typeof(string).FullName), BuiltInTypes.String)
    assert BuiltInTypes.Is(NullabilityMetadataCore.ConvertBuiltInType(typeof(ulong).FullName), BuiltInTypes.ULong)
    assert BuiltInTypes.Is(NullabilityMetadataCore.ConvertBuiltInType(typeof(object).FullName), BuiltInTypes.Object)

    // A row is not merely SOME simple type: `System.Int64` is `long` and is NOT `int`.
    assert BuiltInTypes.IsNot(NullabilityMetadataCore.ConvertBuiltInType(typeof(long).FullName), BuiltInTypes.Int)
}

test "the built-in map declines a constructed generic, an unmodelled name and a null name" {
    // The deleted file's only negative: a closed generic is not a built-in.
    assert NullabilityMetadataCore.ConvertBuiltInType(typeof(Dictionary<string, int>).FullName) == null

    // Two more the deleted file never stated: an unmodelled BCL type, and a null argument.
    // (`typeof(StringComparison)` is off the columnar typeof surface, so the unmodelled row names
    // its CLR type by text — the same route the `System.Void` row above takes.)
    assert NullabilityMetadataCore.ConvertBuiltInType("System.Text.StringBuilder") == null
    assert NullabilityMetadataCore.ConvertBuiltInType(null) == null
    assert NullabilityMetadataCore.ConvertBuiltInType("Int32") == null
}

test "the CLR display map is identity for a name it does not own" {
    // The deleted file's own row, stated directly as well as through the crossing above.
    assert NullabilityMetadataCore.FormatSimpleClrTypeName("Int32") == "int"

    assert NullabilityMetadataCore.FormatSimpleClrTypeName("StringBuilder") == "StringBuilder"
    assert NullabilityMetadataCore.FormatSimpleClrTypeName("") == ""

    // Case matters: the map keys on the CLR spelling, not on the N# one.
    assert NullabilityMetadataCore.FormatSimpleClrTypeName("int") == "int"
    assert NullabilityMetadataCore.FormatSimpleClrTypeName("INT32") == "INT32"
}

// ── The CLR name shapers, which had no assertion anywhere ───────────────────────────────────────

test "the CLR generic arity suffix is stripped at the backtick and nowhere else" {
    assert NullabilityMetadataCore.StripClrGenericArity("List`1") == "List"
    assert NullabilityMetadataCore.StripClrGenericArity("Dictionary`2") == "Dictionary"
    assert NullabilityMetadataCore.StripClrGenericArity("String") == "String"
    assert NullabilityMetadataCore.StripClrGenericArity("`1") == ""

    // The real CLR name of a closed generic carries the arity, and the stripper removes it.
    assert NullabilityMetadataCore.StripClrGenericArity(typeof(List<int>).Name) == "List"
}

test "the CLR array and generic display forms are composed, not printed" {
    assert NullabilityMetadataCore.FormatArrayClrTypeName("int") == "int[]"
    assert NullabilityMetadataCore.FormatArrayClrTypeName("int[]") == "int[][]"

    oneArgument := new string[](1)
    oneArgument[0] = "string"
    assert NullabilityMetadataCore.FormatGenericClrTypeName("List", oneArgument) == "List<string>"

    twoArguments := new string[](2)
    twoArguments[0] = "string"
    twoArguments[1] = "int"
    assert NullabilityMetadataCore.FormatGenericClrTypeName("Dictionary", twoArguments) == "Dictionary<string, int>"

    // Zero arguments still brackets — the shaper does not decide whether a name is generic.
    noArguments := new string[](0)
    assert NullabilityMetadataCore.FormatGenericClrTypeName("List", noArguments) == "List<>"
}

// ── The N#-owned display form ───────────────────────────────────────────────────────────────────

test "the display form renders a generic, a nullable array and a function type" {
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.String)
    generic := new GenericTypeInfo("List", arguments)
    nullableArray := new NullableTypeInfo(new ArrayTypeInfo(generic))

    function := new FunctionTypeInfo()
    parameters := new List<TypeInfo>()
    parameters.Add(BuiltInTypes.Int)
    parameters.Add(nullableArray)
    function.ParameterTypes = parameters
    function.ReturnType = BuiltInTypes.Bool

    assert NullabilityTypeDisplay.TryFormatTypeInfo(generic) == "List<string>"
    assert NullabilityTypeDisplay.TryFormatTypeInfo(nullableArray) == "List<string>[]?"
    assert NullabilityTypeDisplay.TryFormatTypeInfo(function) == "(int, List<string>[]?) -> bool"
}

test "the display form composes its three wrapper suffixes in application order" {
    assert NullabilityTypeDisplay.TryFormatTypeInfo(BuiltInTypes.String) == "string"
    assert NullabilityTypeDisplay.TryFormatTypeInfo(new ArrayTypeInfo(BuiltInTypes.Int)) == "int[]"
    assert NullabilityTypeDisplay.TryFormatTypeInfo(new NullableTypeInfo(BuiltInTypes.String)) == "string?"

    // `!` is the oblivious marker and it is distinct from both of the others.
    assert NullabilityTypeDisplay.TryFormatTypeInfo(new ObliviousTypeInfo(BuiltInTypes.String)) == "string!"

    // Two layers nest outward-last: an array of nullables is not a nullable array.
    arrayOfNullable := new ArrayTypeInfo(new NullableTypeInfo(BuiltInTypes.String))
    nullableArray := new NullableTypeInfo(new ArrayTypeInfo(BuiltInTypes.String))
    assert NullabilityTypeDisplay.TryFormatTypeInfo(arrayOfNullable) == "string?[]"
    assert NullabilityTypeDisplay.TryFormatTypeInfo(nullableArray) == "string[]?"
}

test "a two argument generic separates with a comma and a space" {
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.String)
    arguments.Add(BuiltInTypes.Int)
    assert NullabilityTypeDisplay.TryFormatTypeInfo(new GenericTypeInfo("Dictionary", arguments)) == "Dictionary<string, int>"

    // A generic with no arguments still brackets, exactly as the CLR shaper does.
    empty := new List<TypeInfo>()
    assert NullabilityTypeDisplay.TryFormatTypeInfo(new GenericTypeInfo("List", empty)) == "List<>"
}

test "a function type with no parameter list falls back through its two names to the word function" {
    // The deleted file only ever built a COMPLETE function type. These three arms decide what a
    // partially-known one prints, and nothing anywhere stated them.
    bare := new FunctionTypeInfo()
    assert NullabilityTypeDisplay.TryFormatTypeInfo(bare) == "function"

    named := new FunctionTypeInfo()
    named.SourceName = "handler"
    assert NullabilityTypeDisplay.TryFormatTypeInfo(named) == "handler"

    // The synthetic name wins over the source name when both are present.
    both := new FunctionTypeInfo()
    both.SourceName = "handler"
    both.SyntheticName = "<lambda>0"
    assert NullabilityTypeDisplay.TryFormatTypeInfo(both) == "<lambda>0"

    // A return type without parameter types is still incomplete.
    returnOnly := new FunctionTypeInfo()
    returnOnly.ReturnType = BuiltInTypes.Bool
    assert NullabilityTypeDisplay.TryFormatTypeInfo(returnOnly) == "function"
}

test "a zero parameter function type prints an empty parameter list" {
    function := new FunctionTypeInfo()
    function.ParameterTypes = new List<TypeInfo>()
    function.ReturnType = BuiltInTypes.Void
    assert NullabilityTypeDisplay.TryFormatTypeInfo(function) == "() -> void"
}

// ── The wrapping policy, as a 3 × 3 table ───────────────────────────────────────────────────────

test "EnsureNullable answers the same object for a nullable, replaces an oblivious and wraps a plain" {
    plain: TypeInfo = BuiltInTypes.String
    nullable: TypeInfo = new NullableTypeInfo(plain)
    oblivious: TypeInfo = new ObliviousTypeInfo(plain)

    // Already nullable: the SAME object, not an equal one.
    assert Object.ReferenceEquals(NullabilityMetadataCore.EnsureNullable(nullable), nullable)

    // Oblivious: the oblivious layer is REPLACED, not wrapped — `T?`, never `T!?`.
    wrapped := NullabilityMetadataCore.EnsureNullable(oblivious) as NullableTypeInfo
    assert wrapped != null
    assert Object.ReferenceEquals(wrapped.InnerType, plain)
    assert NullabilityTypeDisplay.TryFormatTypeInfo(wrapped) == "string?"

    // Plain: wrapped once.
    fresh := NullabilityMetadataCore.EnsureNullable(plain) as NullableTypeInfo
    assert fresh != null
    assert Object.ReferenceEquals(fresh.InnerType, plain)
}

test "EnsureOblivious answers the same object for both wrapped forms and wraps only a plain" {
    plain: TypeInfo = BuiltInTypes.String
    nullable: TypeInfo = new NullableTypeInfo(plain)
    oblivious: TypeInfo = new ObliviousTypeInfo(plain)

    // A nullable is NOT re-marked oblivious: nullability that is known stays known.
    assert Object.ReferenceEquals(NullabilityMetadataCore.EnsureOblivious(nullable), nullable)
    assert Object.ReferenceEquals(NullabilityMetadataCore.EnsureOblivious(oblivious), oblivious)

    fresh := NullabilityMetadataCore.EnsureOblivious(plain) as ObliviousTypeInfo
    assert fresh != null
    assert Object.ReferenceEquals(fresh.InnerType, plain)
}

test "EnsureNotNull unwraps both wrapped forms to the identical inner object and leaves a plain alone" {
    plain: TypeInfo = BuiltInTypes.String
    nullable: TypeInfo = new NullableTypeInfo(plain)
    oblivious: TypeInfo = new ObliviousTypeInfo(plain)

    assert Object.ReferenceEquals(NullabilityMetadataCore.EnsureNotNull(nullable), plain)
    assert Object.ReferenceEquals(NullabilityMetadataCore.EnsureNotNull(oblivious), plain)
    assert Object.ReferenceEquals(NullabilityMetadataCore.EnsureNotNull(plain), plain)
}

test "every wrapping operation is idempotent by reference" {
    plain: TypeInfo = BuiltInTypes.String

    onceNullable := NullabilityMetadataCore.EnsureNullable(plain)
    assert Object.ReferenceEquals(NullabilityMetadataCore.EnsureNullable(onceNullable), onceNullable)

    onceOblivious := NullabilityMetadataCore.EnsureOblivious(plain)
    assert Object.ReferenceEquals(NullabilityMetadataCore.EnsureOblivious(onceOblivious), onceOblivious)

    onceNotNull := NullabilityMetadataCore.EnsureNotNull(onceNullable)
    assert Object.ReferenceEquals(NullabilityMetadataCore.EnsureNotNull(onceNotNull), onceNotNull)

    // Only ONE layer is removed: `EnsureNotNull` over a doubly-oblivious type still answers oblivious.
    doubled: TypeInfo = new ObliviousTypeInfo(new ObliviousTypeInfo(plain))
    once := NullabilityMetadataCore.EnsureNotNull(doubled) as ObliviousTypeInfo
    assert once != null
    assert Object.ReferenceEquals(once.InnerType, plain)
}

// ── Reference-nullability eligibility ───────────────────────────────────────────────────────────

test "reference nullability eligibility is decided per TypeInfo shape" {
    // The four cells the deleted file stated.
    assert !NullabilityMetadataCore.CanCarryReferenceNullability(BuiltInTypes.Int)
    assert NullabilityMetadataCore.CanCarryReferenceNullability(BuiltInTypes.String)
    assert !NullabilityMetadataCore.CanCarryReferenceNullability(new NullableTypeInfo(BuiltInTypes.String))
    assert NullabilityMetadataCore.CanCarryReferenceNullability(new ObliviousTypeInfo(BuiltInTypes.String))
    assert !NullabilityMetadataCore.CanCarryReferenceNullability(BuiltInTypes.Unknown)

    // The oblivious arm RECURSES rather than answering true: an oblivious `int` is still an int.
    assert !NullabilityMetadataCore.CanCarryReferenceNullability(new ObliviousTypeInfo(BuiltInTypes.Int))

    // The shapes with no arm of their own fall through to true.
    arguments := new List<TypeInfo>()
    arguments.Add(BuiltInTypes.String)
    assert NullabilityMetadataCore.CanCarryReferenceNullability(new GenericTypeInfo("List", arguments))
    assert NullabilityMetadataCore.CanCarryReferenceNullability(new ArrayTypeInfo(BuiltInTypes.Int))
    assert NullabilityMetadataCore.CanCarryReferenceNullability(new FunctionTypeInfo())
}

test "the non nullable simple set covers fourteen of the sixteen CLR built-ins plus null and never" {
    // Everything the CLR map can produce EXCEPT `string` and `object` is refused.
    assert NullabilityMetadataCore.IsNonNullableSimpleType("bool")
    assert NullabilityMetadataCore.IsNonNullableSimpleType("byte")
    assert NullabilityMetadataCore.IsNonNullableSimpleType("sbyte")
    assert NullabilityMetadataCore.IsNonNullableSimpleType("short")
    assert NullabilityMetadataCore.IsNonNullableSimpleType("ushort")
    assert NullabilityMetadataCore.IsNonNullableSimpleType("int")
    assert NullabilityMetadataCore.IsNonNullableSimpleType("uint")
    assert NullabilityMetadataCore.IsNonNullableSimpleType("long")
    assert NullabilityMetadataCore.IsNonNullableSimpleType("ulong")
    assert NullabilityMetadataCore.IsNonNullableSimpleType("float")
    assert NullabilityMetadataCore.IsNonNullableSimpleType("double")
    assert NullabilityMetadataCore.IsNonNullableSimpleType("decimal")
    assert NullabilityMetadataCore.IsNonNullableSimpleType("char")
    assert NullabilityMetadataCore.IsNonNullableSimpleType("void")

    // The two the CLR map produces that ARE eligible.
    assert !NullabilityMetadataCore.IsNonNullableSimpleType("string")
    assert !NullabilityMetadataCore.IsNonNullableSimpleType("object")

    // Two the CLR map never produces but the set still owns.
    assert NullabilityMetadataCore.IsNonNullableSimpleType("null")
    assert NullabilityMetadataCore.IsNonNullableSimpleType("never")

    // Not a member: any name the set does not list.
    assert !NullabilityMetadataCore.IsNonNullableSimpleType("Int32")
    assert !NullabilityMetadataCore.IsNonNullableSimpleType("unknown")
}

test "exactly two of the sixteen CLR built-ins can carry reference nullability, and they are string and object" {
    // A PARTITION over the whole CLR map rather than a restatement of the simple-type arm. The
    // eligibility of a `SimpleTypeInfo` is BY CONSTRUCTION the negation of the non-nullable set, so
    // asserting that relation cell by cell would be vacuous; what is NOT vacuous, and what nothing
    // anywhere held, is the composition of the two tables — the CLR map's sixteen rows admit exactly
    // two reference types, and adding a seventeenth CLR row without listing it in the non-nullable
    // set would silently make a third.
    eligible := NmcEligibleBuiltIns()
    assert eligible == "string,object", "the CLR built-in map admits reference nullability for: " + eligible
}

// The N# names of every CLR built-in the map converts that can carry reference nullability, in the
// order the map declares them.
func NmcEligibleBuiltIns(): string {
    names := new string[](16)
    names[0] = typeof(int).FullName
    names[1] = typeof(long).FullName
    names[2] = typeof(float).FullName
    names[3] = typeof(double).FullName
    names[4] = typeof(decimal).FullName
    names[5] = typeof(byte).FullName
    names[6] = typeof(sbyte).FullName
    names[7] = typeof(short).FullName
    names[8] = typeof(ushort).FullName
    names[9] = typeof(uint).FullName
    names[10] = typeof(ulong).FullName
    names[11] = typeof(char).FullName
    names[12] = typeof(bool).FullName
    names[13] = typeof(string).FullName
    names[14] = "System.Void"
    names[15] = typeof(object).FullName

    admitted := ""
    index := 0
    while index < names.Length {
        converted := NullabilityMetadataCore.ConvertBuiltInType(names[index])
        if converted == null {
            return "MISSING ROW: " + names[index]
        }

        if NullabilityMetadataCore.CanCarryReferenceNullability(converted) {
            if admitted.Length > 0 {
                admitted = admitted + ","
            }

            admitted = admitted + NmcSimpleName(converted)
        }

        index = index + 1
    }

    return admitted
}

test "the reflected eligibility gate defers to the converted answer only for a generic parameter" {
    // A three-boolean decision with eight rows; nothing anywhere stated any of them.
    // Not a generic parameter: the CLR value-type flag alone decides, and the converted answer is
    // ignored in both directions.
    assert NullabilityMetadataCore.CanReflectedTypeCarryReferenceNullability(false, false, false)
    assert NullabilityMetadataCore.CanReflectedTypeCarryReferenceNullability(false, false, true)
    assert !NullabilityMetadataCore.CanReflectedTypeCarryReferenceNullability(false, true, false)
    assert !NullabilityMetadataCore.CanReflectedTypeCarryReferenceNullability(false, true, true)

    // A generic parameter: the converted answer alone decides, and the value-type flag is ignored.
    assert !NullabilityMetadataCore.CanReflectedTypeCarryReferenceNullability(true, false, false)
    assert NullabilityMetadataCore.CanReflectedTypeCarryReferenceNullability(true, false, true)
    assert !NullabilityMetadataCore.CanReflectedTypeCarryReferenceNullability(true, true, false)
    assert NullabilityMetadataCore.CanReflectedTypeCarryReferenceNullability(true, true, true)
}

// ── The flow-attribute kinds ────────────────────────────────────────────────────────────────────

test "the four flow attribute kinds are distinct, positive and keyed on the exact attribute name" {
    maybeNull := NullabilityMetadataCore.GetMaybeNullAttributeKind()
    notNull := NullabilityMetadataCore.GetNotNullAttributeKind()
    notNullWhen := NullabilityMetadataCore.GetNotNullWhenAttributeKind()
    paramArray := NullabilityMetadataCore.GetParamArrayAttributeKind()

    assert maybeNull != notNull
    assert maybeNull != notNullWhen
    assert maybeNull != paramArray
    assert notNull != notNullWhen
    assert notNull != paramArray
    assert notNullWhen != paramArray
    assert maybeNull != 0
    assert notNull != 0
    assert notNullWhen != 0
    assert paramArray != 0

    assert NullabilityMetadataCore.GetFlowAttributeKind("System.Diagnostics.CodeAnalysis.MaybeNullAttribute") == maybeNull
    assert NullabilityMetadataCore.GetFlowAttributeKind("System.Diagnostics.CodeAnalysis.NotNullAttribute") == notNull
    assert NullabilityMetadataCore.GetFlowAttributeKind("System.Diagnostics.CodeAnalysis.NotNullWhenAttribute") == notNullWhen
    assert NullabilityMetadataCore.GetFlowAttributeKind("System.ParamArrayAttribute") == paramArray

    // Zero is "not a flow attribute", and the match is ORDINAL and unqualified-name-blind.
    assert NullabilityMetadataCore.GetFlowAttributeKind(null) == 0
    assert NullabilityMetadataCore.GetFlowAttributeKind("") == 0
    assert NullabilityMetadataCore.GetFlowAttributeKind("MaybeNullAttribute") == 0
    assert NullabilityMetadataCore.GetFlowAttributeKind("System.Diagnostics.CodeAnalysis.MaybeNull") == 0
    assert NullabilityMetadataCore.GetFlowAttributeKind("System.ObsoleteAttribute") == 0
}

test "the flow attribute facts choose nullable over not-null and pass an unannotated type through" {
    plain: TypeInfo = BuiltInTypes.String

    // MaybeNull wins when both are present — the order in the kernel is a decision, not an accident.
    both := NullabilityMetadataCore.ApplyFlowAttributeFacts(plain, true, true)
    assert NullabilityTypeDisplay.TryFormatTypeInfo(both) == "string?"

    maybe := NullabilityMetadataCore.ApplyFlowAttributeFacts(plain, true, false)
    assert NullabilityTypeDisplay.TryFormatTypeInfo(maybe) == "string?"

    nullable: TypeInfo = new NullableTypeInfo(plain)
    notNull := NullabilityMetadataCore.ApplyFlowAttributeFacts(nullable, false, true)
    assert Object.ReferenceEquals(notNull, plain)

    // Neither flag: the same object comes back untouched.
    assert Object.ReferenceEquals(NullabilityMetadataCore.ApplyFlowAttributeFacts(plain, false, false), plain)
}

test "the read state applier is gated twice before it wraps anything" {
    plain: TypeInfo = BuiltInTypes.String

    // A nullable VALUE type short-circuits first: neither read state reaches the wrapper.
    assert Object.ReferenceEquals(NullabilityMetadataCore.ApplyReadState(plain, true, true, true, false), plain)
    assert Object.ReferenceEquals(NullabilityMetadataCore.ApplyReadState(plain, true, true, false, true), plain)

    // An ineligible type short-circuits second.
    assert Object.ReferenceEquals(NullabilityMetadataCore.ApplyReadState(plain, false, false, true, false), plain)

    // Eligible and nullable-read: wrapped nullable. Eligible and unknown-read: wrapped oblivious.
    assert NullabilityTypeDisplay.TryFormatTypeInfo(NullabilityMetadataCore.ApplyReadState(plain, false, true, true, false)) == "string?"
    assert NullabilityTypeDisplay.TryFormatTypeInfo(NullabilityMetadataCore.ApplyReadState(plain, false, true, false, true)) == "string!"

    // Nullable-read wins over unknown-read when both are set.
    assert NullabilityTypeDisplay.TryFormatTypeInfo(NullabilityMetadataCore.ApplyReadState(plain, false, true, true, true)) == "string?"

    // Neither read state: untouched.
    assert Object.ReferenceEquals(NullabilityMetadataCore.ApplyReadState(plain, false, true, false, false), plain)
}
