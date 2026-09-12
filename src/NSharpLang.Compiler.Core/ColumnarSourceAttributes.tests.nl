namespace NSharpLang.Compiler.Columnar

import System
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

func SourceAttributeAssembly(source: string): Assembly {
    program := SourceAttributeProgram(source)
    bytes: byte[] = null
    assert ColumnarIlEmitter.TryEmitColumnarAssembly("SourceAttributes" + Guid.NewGuid().ToString("N"), "Program", program, false, out bytes, null, null)
    return Assembly.Load(bytes)
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

test "source attributes survive persisted type method and parameter metadata" {
    assembly := SourceAttributeAssembly("import System\n[Obsolete(\"type message\")]\nclass Probe {\n    [Obsolete(\"method message\")]\n    func Run([System.Runtime.InteropServices.In] value: int = 7): int { return value }\n}\n")
    owner := assembly.GetType("Probe")
    assert owner != null
    attributes := owner.GetCustomAttributesData()
    assert NullabilityProbeSequenceCount(attributes) == 1
    attribute := attributes.get_Item(0)
    assert attribute.get_AttributeType() == typeof(ObsoleteAttribute)
    arguments := attribute.get_ConstructorArguments()
    assert arguments.get_Item(0).get_Value().ToString() == "type message"
    method := owner.GetMethod("Run")
    assert method != null
    methodAttributes := method.GetCustomAttributesData()
    assert NullabilityProbeSequenceCount(methodAttributes) == 1
    methodAttribute := methodAttributes.get_Item(0)
    methodArguments := methodAttribute.get_ConstructorArguments()
    assert methodArguments.get_Item(0).get_Value().ToString() == "method message"
    parameters := method.GetParameters()
    assert parameters[0].get_IsIn()
    assert parameters[0].get_IsOptional()
    assert parameters[0].get_DefaultValue().ToString() == "7"
}

test "source attributes bind explicit suffix and preserve an empty constructor" {
    assembly := SourceAttributeAssembly("[System.ObsoleteAttribute()]\nclass Probe { func Run(): int { return 1 } }\n")
    owner := assembly.GetType("Probe")
    assert owner != null
    attributes := owner.GetCustomAttributesData()
    assert NullabilityProbeSequenceCount(attributes) == 1
    attribute := attributes.get_Item(0)
    assert attribute.get_Constructor().GetParameters().Length == 0
}

test "source attribute binding never treats a non-attribute type as metadata" {
    assembly := SourceAttributeAssembly("[System.String]\nclass Probe { func Run(): int { return 1 } }\n")
    owner := assembly.GetType("Probe")
    assert owner != null
    assert NullabilityProbeSequenceCount(owner.GetCustomAttributesData()) == 0
}

test "source attribute suffix lookup ignores a non-attribute homonym" {
    assembly := SourceAttributeAssembly("import System\nclass Obsolete { }\n[Obsolete(\"message\")]\nclass Probe { func Run(): int { return 1 } }\n")
    owner := assembly.GetType("Probe")
    assert owner != null
    attributes := owner.GetCustomAttributesData()
    assert NullabilityProbeSequenceCount(attributes) == 1
    attribute := attributes.get_Item(0)
    assert attribute.get_AttributeType() == typeof(ObsoleteAttribute)
}

test "source attributes survive on a top-level function" {
    assembly := SourceAttributeAssembly("[System.Obsolete]\nfunc Run(): int { return 1 }\n")
    owner := assembly.GetType("Program")
    assert owner != null
    method := owner.GetMethod("Run")
    assert method != null
    attributes := method.GetCustomAttributesData()
    assert NullabilityProbeSequenceCount(attributes) == 1
    attribute := attributes.get_Item(0)
    assert attribute.get_AttributeType() == typeof(ObsoleteAttribute)
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

test "MethodImpl sets the emitted implementation flags and writes no custom attribute" {
    assembly := SourceAttributeAssembly("import System.Runtime.CompilerServices\nclass Probe {\n    [MethodImpl(MethodImplOptions.AggressiveInlining | MethodImplOptions.NoOptimization)]\n    func Hot(): int { return 1 }\n\n    func Cold(): int { return 2 }\n}\n")
    owner := assembly.GetType("Probe")
    assert owner != null
    hot := owner.GetMethod("Hot")
    assert hot != null
    assert Convert.ToInt32(hot.GetMethodImplementationFlags()) == Convert.ToInt32(System.Runtime.CompilerServices.MethodImplOptions.AggressiveInlining | System.Runtime.CompilerServices.MethodImplOptions.NoOptimization)
    assert NullabilityProbeSequenceCount(hot.GetCustomAttributesData()) == 0, "a pseudo-custom attribute leaves no row"

    cold := owner.GetMethod("Cold")
    assert cold != null
    assert Convert.ToInt32(cold.GetMethodImplementationFlags()) == 0, "an unmarked method stays IL | Managed"
}

test "a bare MethodImpl asks for nothing and still writes no custom attribute" {
    assembly := SourceAttributeAssembly("import System.Runtime.CompilerServices\nclass Probe {\n    [MethodImpl]\n    func Run(): int { return 1 }\n}\n")
    owner := assembly.GetType("Probe")
    assert owner != null
    method := owner.GetMethod("Run")
    assert method != null
    assert Convert.ToInt32(method.GetMethodImplementationFlags()) == 0
    assert NullabilityProbeSequenceCount(method.GetCustomAttributesData()) == 0
}

// ── an attribute list on a new line is not an index into the member above it ────────────────────
//
// The columnar postfix kernel had no line rule, so an expression-bodied member followed by the NEXT
// member's `[Attribute]` read as `<body>[Attribute]` — an index access over the body — and the whole
// declaration then declined at `emit.return.expression`. The production parser has always ended a
// postfix chain at a continuation token on a new line; the kernel now agrees, and this is the shape
// that proves it. `Result.cs`'s hot members are exactly this: expression bodies, each preceded by
// `[MethodImpl(...)]`.

test "an expression-bodied member survives the attribute list of the member after it" {
    assembly := SourceAttributeAssembly("import System.Runtime.CompilerServices\nclass Probe {\n    amount: int = 21\n\n    Doubled: int => amount * 2\n\n    [MethodImpl(MethodImplOptions.NoInlining)]\n    Tripled: int => amount * 3\n\n    [System.Obsolete]\n    func Quadrupled(): int => amount * 4\n}\n")
    owner := assembly.GetType("Probe")
    assert owner != null
    instance := Activator.CreateInstance(owner)
    assert instance != null

    doubled := owner.GetProperty("Doubled")
    assert doubled != null
    assert doubled.GetValue(instance).ToString() == "42"

    tripled := owner.GetProperty("Tripled")
    assert tripled != null
    assert tripled.GetValue(instance).ToString() == "63"

    quadrupled := owner.GetMethod("Quadrupled")
    assert quadrupled != null
    assert quadrupled.Invoke(instance, null).ToString() == "84"

    // …and the attributes still landed where they were written.
    tripledGetter := owner.GetMethod("get_Tripled")
    assert tripledGetter != null
    assert Convert.ToInt32(tripledGetter.GetMethodImplementationFlags()) == Convert.ToInt32(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)
    assert NullabilityProbeSequenceCount(quadrupled.GetCustomAttributesData()) == 1
}

test "an index access on the SAME line is still an index access" {
    assembly := SourceAttributeAssembly("class Probe {\n    values: int[] = [7, 8, 9]\n\n    func First(): int => values[0]\n}\n")
    owner := assembly.GetType("Probe")
    assert owner != null
    instance := Activator.CreateInstance(owner)
    assert instance != null
    method := owner.GetMethod("First")
    assert method != null
    assert method.Invoke(instance, null).ToString() == "7"
}
