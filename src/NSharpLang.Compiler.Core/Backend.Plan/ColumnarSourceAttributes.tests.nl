namespace NSharpLang.Compiler.Columnar

import System.Collections.Generic
import System.Reflection

func SourceAttributeProgram(source: string): ColumnarProgramInput {
    sources := new List<string>()
    sources.Add(source)
    names := new List<string>()
    names.Add("/tmp/SourceAttributeProbe.nl")
    program: ColumnarProgramInput = null
    assert ColumnarProgramInputBuilder.TryBuildMultiFile(sources, names, "/tmp", out program)
    return program
}

test "source attributes retain declaration order and decoded strings" {
    program := SourceAttributeProgram("[System.Obsolete(\"first\\nline\")]\n[System.ComponentModel.Description(\"second\")]\nclass Probe {\n    [hot]\n    func Run(): int { return 1 }\n}\n")
    attributes := program.Structs[0].SourceAttributes
    assert attributes != null
    assert attributes.Length == 2
    assert attributes[0].Name == "System.Obsolete"
    assert attributes[0].Arguments[0] == "first\nline"
    assert attributes[1].Name == "System.ComponentModel.Description"
    assert attributes[1].Arguments[0] == "second"
}

// ── every argument as written, and which of them a blob can carry ───────────────────────────────
//
// The reader used to REFUSE an attribute whose arguments were not all string literals, and the
// refusal was silent: `[MethodImpl(MethodImplOptions.AggressiveInlining)]` reached the emitter as
// nothing at all. Arguments are now kept as SOURCE TEXT whatever their shape, and the string
// decoding is a separate, witnessed answer — `IsStringArgumentList` — so the blob writer still only
// ever sees the shapes it can write, and the pseudo-custom attributes can read the rest.

test "an argument that is not a string literal is kept as written and marked unblobbable" {
    program := SourceAttributeProgram("import System.Runtime.CompilerServices\nclass Probe {\n    [MethodImpl(MethodImplOptions.AggressiveInlining | MethodImplOptions.AggressiveOptimization)]\n    func Run(): int { return 1 }\n}\n")
    attributes := program.Structs[0].Methods[0].SourceAttributes
    assert attributes != null
    assert attributes.Length == 1
    assert attributes[0].Name == "MethodImpl"
    assert !attributes[0].IsStringArgumentList
    assert attributes[0].Arguments.Length == 0, "nothing a blob could write"
    assert attributes[0].ArgumentTexts.Length == 1
    assert attributes[0].ArgumentTexts[0] == "MethodImplOptions.AggressiveInlining | MethodImplOptions.AggressiveOptimization"
}

test "a string argument list still decodes, and still says so" {
    program := SourceAttributeProgram("[System.Obsolete(\"gone\")]\nclass Probe { func Run(): int { return 1 } }\n")
    attributes := program.Structs[0].SourceAttributes
    assert attributes != null
    assert attributes[0].IsStringArgumentList
    assert attributes[0].Arguments[0] == "gone"
    assert attributes[0].ArgumentTexts[0] == "\"gone\""
}

test "an attribute with no arguments is a string argument list with nothing in it" {
    program := SourceAttributeProgram("import System.Runtime.CompilerServices\nclass Probe {\n    [MethodImpl]\n    func Run(): int { return 1 }\n}\n")
    attributes := program.Structs[0].Methods[0].SourceAttributes
    assert attributes != null
    assert attributes.Length == 1
    assert attributes[0].IsStringArgumentList
    assert attributes[0].ArgumentTexts.Length == 0
}

test "arguments split on TOP-LEVEL commas only" {
    program := SourceAttributeProgram("import System.Runtime.CompilerServices\nclass Probe {\n    [MethodImpl(MethodImplOptions.InternalCall, MethodCodeType = MethodCodeType.Runtime)]\n    func Run(): int { return 1 }\n}\n")
    attributes := program.Structs[0].Methods[0].SourceAttributes
    assert attributes != null
    assert attributes[0].ArgumentTexts.Length == 2
    assert attributes[0].ArgumentTexts[0] == "MethodImplOptions.InternalCall"
    assert attributes[0].ArgumentTexts[1] == "MethodCodeType = MethodCodeType.Runtime"
}

// ── the pseudo-custom attribute goes to the flags, and only to the flags ────────────────────────

// ── an attribute list on a new line is not an index into the member above it ────────────────────
//
// The columnar postfix kernel had no line rule, so an expression-bodied member followed by the NEXT
// member's `[Attribute]` read as `<body>[Attribute]` — an index access over the body — and the whole
// declaration then declined at `emit.return.expression`. The production parser has always ended a
// postfix chain at a continuation token on a new line; the kernel now agrees, and this is the shape
// that proves it. `Result.cs`'s hot members are exactly this: expression bodies, each preceded by
// `[MethodImpl(...)]`.

// A FIELD DECLARES ITS OWN ATTRIBUTES AT ITS OWN MEMBER POSITION. The struct member scan records each
// field's name-token index; without it there was no position to scan back from and every field
// attribute was validated and then dropped.
test "a field's attributes are read from its own declaration position" {
    program := SourceAttributeProgram("import System\nclass Probe {\n    [Obsolete(\"gone\")]\n    Value: int\n    Plain: int\n    constructor() {\n        Value = 1\n        Plain = 2\n    }\n}\n")
    fieldAttributes := program.Structs[0].FieldSourceAttributes
    assert fieldAttributes != null
    assert program.Structs[0].FieldSourceAttributesAt(0).Length == 1
    assert program.Structs[0].FieldSourceAttributesAt(0)[0].Name == "Obsolete"
    assert program.Structs[0].FieldSourceAttributesAt(1).Length == 0
    assert program.Structs[0].FieldSourceAttributesAt(9) == null
}

// AN ENUM MEMBER DECLARES ITS OWN ATTRIBUTES AT ITS OWN MEMBER POSITION, exactly as a field does —
// the enum member scan records each member's name-token index — and the enum keyword's position
// carries the declaration's own.
test "an enum's and its members' attributes are read from their own declaration positions" {
    program := SourceAttributeProgram("import System\n[Flags]\nenum Level {\n    [Obsolete(\"gone\")]\n    Low = 1,\n    High = 2\n}\n")
    declared := program.Enums[0]
    assert declared.SourceAttributes != null
    assert declared.SourceAttributes.Length == 1
    assert declared.SourceAttributes[0].Name == "Flags"
    assert declared.MemberSourceAttributes != null
    assert (must declared.MemberSourceAttributesAt(0)).Length == 1
    assert (must declared.MemberSourceAttributesAt(0))[0].Name == "Obsolete"
    assert (must declared.MemberSourceAttributesAt(1)).Length == 0
    assert declared.MemberSourceAttributesAt(9) == null
}

// A METADATA PARAMETER'S DEFAULT ARRIVES BOXED, and the binder turns it into the same argument SHAPE
// a written argument reduces to. The probe is an N#-declared constructor from this very assembly,
// which is a baked runtime type by the time this test runs.
func SourceAttributeOptionalParameter(): ParameterInfo {
    constructors := typeof(ColumnarSourceAttributeInput).GetConstructors()
    assert constructors.Length == 1
    parameters := constructors[0].GetParameters()
    assert parameters.Length == 4
    assert parameters[3].get_IsOptional()
    return parameters[3]
}

test "a metadata parameter's default becomes the argument shape a written one has" {
    node: ColumnarAttributeArgumentNode = null
    assert ColumnarSourceAttributeBinder.TryReadMetadataDefault(SourceAttributeOptionalParameter(), out node)
    assert node.Kind == ColumnarAttributeArgumentKind.BoolLiteral
    assert node.Text == "true"

    constructors := typeof(ColumnarSourceAttributeInput).GetConstructors()
    mandatory := constructors[0].GetParameters()[0]
    assert !ColumnarSourceAttributeBinder.TryReadMetadataDefault(mandatory, out node)
}

test "a constant with no shape a blob can carry is refused rather than guessed" {
    node: ColumnarAttributeArgumentNode = null
    assert ColumnarSourceAttributeBinder.TryNodeFromConstant(null, out node)
    assert node.Kind == ColumnarAttributeArgumentKind.NullLiteral

    assert ColumnarSourceAttributeBinder.TryNodeFromConstant(-5, out node)
    assert node.Kind == ColumnarAttributeArgumentKind.Negate
    assert node.Children[0].Text == "5"

    assert ColumnarSourceAttributeBinder.TryNodeFromConstant(18446744073709551615UL, out node)
    assert node.Kind == ColumnarAttributeArgumentKind.IntLiteral
    assert node.Text == "18446744073709551615"

    assert !ColumnarSourceAttributeBinder.TryNodeFromConstant(new object(), out node)
}
