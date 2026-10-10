namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection


// A SOURCE ATTRIBUTE ALL THE WAY TO METADATA. The planner rows beside `ColumnarSourceAttributes` pin what
// the attribute scan records; these emit the program and read the attribute, flag and default rows the
// emitted assembly actually carries, so they build with the emitter.
func SourceAttributeAssembly(source: string): Assembly {
    program := EmitFixtureProgram([""], [source], "SourceAttributeProbe")
    bytes: byte[] = null
    assert ColumnarIlEmitter.TryEmitColumnarAssembly("SourceAttributes" + Guid.NewGuid().ToString("N"), "Program", program, false, out bytes, null, null)
    return Assembly.Load(bytes)
}

test "source attributes survive persisted type method and parameter metadata" {
    assembly := SourceAttributeAssembly("import System\n[Obsolete(\"type message\")]\nclass Probe {\n    [Obsolete(\"method message\")]\n    func Run([System.Runtime.InteropServices.In] value: int = 7): int { return value }\n}\n")
    owner := assembly.GetType("Probe")
    assert owner != null
    attributes := owner.GetCustomAttributesData()
    assert attributes.Count == 1
    attribute := attributes.get_Item(0)
    assert attribute.get_AttributeType() == typeof(ObsoleteAttribute)
    arguments := attribute.get_ConstructorArguments()
    assert (must arguments.get_Item(0).get_Value()).ToString() == "type message"
    method := owner.GetMethod("Run")
    assert method != null
    methodAttributes := method.GetCustomAttributesData()
    assert methodAttributes.Count == 1
    methodAttribute := methodAttributes.get_Item(0)
    methodArguments := methodAttribute.get_ConstructorArguments()
    assert (must methodArguments.get_Item(0).get_Value()).ToString() == "method message"
    parameters := method.GetParameters()
    assert parameters[0].get_IsIn()
    assert parameters[0].get_IsOptional()
    assert (must parameters[0].get_DefaultValue()).ToString() == "7"
}

test "source attributes bind explicit suffix and preserve an empty constructor" {
    assembly := SourceAttributeAssembly("[System.ObsoleteAttribute()]\nclass Probe { func Run(): int { return 1 } }\n")
    owner := assembly.GetType("Probe")
    assert owner != null
    attributes := owner.GetCustomAttributesData()
    assert attributes.Count == 1
    attribute := attributes.get_Item(0)
    assert attribute.get_Constructor().GetParameters().Length == 0
}

test "source attribute binding never treats a non-attribute type as metadata" {
    assembly := SourceAttributeAssembly("[System.String]\nclass Probe { func Run(): int { return 1 } }\n")
    owner := assembly.GetType("Probe")
    assert owner != null
    assert owner.GetCustomAttributesData().Count == 0
}

test "source attribute suffix lookup ignores a non-attribute homonym" {
    assembly := SourceAttributeAssembly("import System\nclass Obsolete { }\n[Obsolete(\"message\")]\nclass Probe { func Run(): int { return 1 } }\n")
    owner := assembly.GetType("Probe")
    assert owner != null
    attributes := owner.GetCustomAttributesData()
    assert attributes.Count == 1
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
    assert attributes.Count == 1
    attribute := attributes.get_Item(0)
    assert attribute.get_AttributeType() == typeof(ObsoleteAttribute)
}

test "MethodImpl sets the emitted implementation flags and writes no custom attribute" {
    assembly := SourceAttributeAssembly("import System.Runtime.CompilerServices\nclass Probe {\n    [MethodImpl(MethodImplOptions.AggressiveInlining | MethodImplOptions.NoOptimization)]\n    func Hot(): int { return 1 }\n\n    func Cold(): int { return 2 }\n}\n")
    owner := assembly.GetType("Probe")
    assert owner != null
    hot := owner.GetMethod("Hot")
    assert hot != null
    assert Convert.ToInt32(hot.GetMethodImplementationFlags()) == Convert.ToInt32(System.Runtime.CompilerServices.MethodImplOptions.AggressiveInlining | System.Runtime.CompilerServices.MethodImplOptions.NoOptimization)
    assert hot.GetCustomAttributesData().Count == 0, "a pseudo-custom attribute leaves no row"

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
    assert method.GetCustomAttributesData().Count == 0
}

test "an expression-bodied member survives the attribute list of the member after it" {
    assembly := SourceAttributeAssembly("import System.Runtime.CompilerServices\nclass Probe {\n    amount: int = 21\n\n    Doubled: int => amount * 2\n\n    [MethodImpl(MethodImplOptions.NoInlining)]\n    Tripled: int => amount * 3\n\n    [System.Obsolete]\n    func Quadrupled(): int => amount * 4\n}\n")
    owner := assembly.GetType("Probe")
    assert owner != null
    instance := Activator.CreateInstance(owner)
    assert instance != null

    doubled := owner.GetProperty("Doubled")
    assert doubled != null
    assert (must doubled.GetValue(instance)).ToString() == "42"

    tripled := owner.GetProperty("Tripled")
    assert tripled != null
    assert (must tripled.GetValue(instance)).ToString() == "63"

    quadrupled := owner.GetMethod("Quadrupled")
    assert quadrupled != null
    assert (must quadrupled.Invoke(instance, null)).ToString() == "84"

    // …and the attributes still landed where they were written.
    tripledGetter := owner.GetMethod("get_Tripled")
    assert tripledGetter != null
    assert Convert.ToInt32(tripledGetter.GetMethodImplementationFlags()) == Convert.ToInt32(System.Runtime.CompilerServices.MethodImplOptions.NoInlining)
    assert quadrupled.GetCustomAttributesData().Count == 1
}

test "an index access on the SAME line is still an index access" {
    assembly := SourceAttributeAssembly("class Probe {\n    values: int[] = [7, 8, 9]\n\n    func First(): int => values[0]\n}\n")
    owner := assembly.GetType("Probe")
    assert owner != null
    instance := Activator.CreateInstance(owner)
    assert instance != null
    method := owner.GetMethod("First")
    assert method != null
    assert (must method.Invoke(instance, null)).ToString() == "7"
}

// THE ENUM IS MATERIALIZED AFTER THE ATTRIBUTE QUEUE FLUSHES, so both rows are still open when the
// blobs are written — and the type is still an enum afterwards.
test "an enum's and its members' attributes reach the emitted rows" {
    assembly := SourceAttributeAssembly("import System\n[Flags]\nenum Level {\n    [Obsolete(\"gone\")]\n    Low = 1,\n    High = 2\n}\n")
    owner := assembly.GetType("Level")
    assert owner != null
    assert owner.IsEnum
    assert Enum.GetUnderlyingType(owner) == typeof(int)
    typeAttributes := owner.GetCustomAttributesData()
    assert typeAttributes.Count == 1
    assert typeAttributes.get_Item(0).get_AttributeType() == typeof(FlagsAttribute)

    member := owner.GetField("Low", BindingFlags.Public | BindingFlags.Static)
    assert member != null
    assert member.IsLiteral
    memberAttributes := member.GetCustomAttributesData()
    assert memberAttributes.Count == 1
    assert memberAttributes.get_Item(0).get_AttributeType() == typeof(ObsoleteAttribute)

    plain := owner.GetField("High", BindingFlags.Public | BindingFlags.Static)
    assert plain != null
    assert plain.GetCustomAttributesData().Count == 0
}

test "a field's attribute reaches the emitted field row" {
    assembly := SourceAttributeAssembly("import System\nclass Probe {\n    [Obsolete(\"field gone\")]\n    static Shared: int = 3\n    Value: int\n    constructor() {\n        Value = 1\n    }\n}\n")
    owner := assembly.GetType("Probe")
    assert owner != null
    field := owner.GetField("Shared", BindingFlags.Public | BindingFlags.Static)
    assert field != null
    fieldAttributes := field.GetCustomAttributesData()
    assert fieldAttributes.Count == 1
    assert fieldAttributes.get_Item(0).get_AttributeType() == typeof(ObsoleteAttribute)
    plain := owner.GetField("Value")
    assert plain != null
    assert plain.GetCustomAttributesData().Count == 0
}

// AN OMITTED OPTIONAL ARGUMENT IS WRITTEN AS THE PARAMETER'S DECLARED DEFAULT. Exact arity used to be
// required, so `[Mark]` on a one-parameter constructor bound nothing at all.
test "an omitted optional attribute argument is written as its declared default" {
    assembly := SourceAttributeAssembly("import System\nclass MarkAttribute: Attribute {\n    Level: int\n    constructor(level: int = 4) {\n        Level = level\n    }\n}\n[Mark]\nclass Probe { func Run(): int { return 1 } }\n")
    owner := assembly.GetType("Probe")
    assert owner != null
    attributes := owner.GetCustomAttributesData()
    assert attributes.Count == 1
    arguments := attributes.get_Item(0).get_ConstructorArguments()
    assert arguments.Count == 1
    assert (must arguments.get_Item(0).get_Value()).ToString() == "4"
}
