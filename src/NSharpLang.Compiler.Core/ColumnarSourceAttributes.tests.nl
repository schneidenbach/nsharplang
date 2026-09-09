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
