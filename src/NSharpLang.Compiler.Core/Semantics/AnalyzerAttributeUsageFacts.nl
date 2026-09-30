namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection

// WHAT AN ATTRIBUTE TYPE SAYS ABOUT WHERE IT MAY BE WRITTEN.
//
// `[AttributeUsage(...)]` is the one attribute whose meaning is about ANOTHER attribute, and it is the
// only thing that makes `[Serializable]` on a method an error rather than a harmless extra metadata
// row. Three of its answers matter here: which declarations accept it, whether it may be written more
// than once on the same declaration, and whether a derived attribute inherits those answers.
class AnalyzerAttributeUsage {
    Targets: int
    AllowMultiple: bool
    Inherited: bool

    constructor(targets: int, allowMultiple: bool, inherited: bool) {
        Targets = targets
        AllowMultiple = allowMultiple
        Inherited = inherited
    }
}

// THE TARGET BITS, AND THE ENGLISH FOR THEM.
//
// The bits are `System.AttributeTargets`'s own and are named here rather than read from the enum,
// because the question is asked about a type that may not exist yet — a source-declared attribute is
// measured before its `[AttributeUsage]` argument has anything to reflect over.
//
// ZERO IS NOT A TARGET, IT IS "NO TARGET KNOWN". A caller that validates a bare attribute list without
// saying what carries it passes zero, and the placement question is not asked at all. Reporting
// "cannot be applied to nothing" would be worse than saying nothing.
class AnalyzerAttributeUsageFacts {
    static AssemblyTarget: int => 1
    static ModuleTarget: int => 2
    static ClassTarget: int => 4
    static StructTarget: int => 8
    static EnumTarget: int => 16
    static ConstructorTarget: int => 32
    static MethodTarget: int => 64
    static PropertyTarget: int => 128
    static FieldTarget: int => 256
    static EventTarget: int => 512
    static InterfaceTarget: int => 1024
    static ParameterTarget: int => 2048
    static DelegateTarget: int => 4096
    static ReturnValueTarget: int => 8192
    static GenericParameterTarget: int => 16384
    static AllTargets: int => 32767
    static UnknownTarget: int => 0

    // WHAT A PROPERTY DECLARATION OFFERS. N# has no per-accessor attribute position: a property's
    // attributes are written once and reach BOTH accessors, so a property accepts an attribute declared
    // for properties and one declared for methods alike.
    static func PropertyDeclarationTargets(): int {
        propertyBit := AnalyzerAttributeUsageFacts.PropertyTarget
        methodBit := AnalyzerAttributeUsageFacts.MethodTarget
        return propertyBit | methodBit
    }

    // WHAT A POSITIONAL CONSTRUCTOR PARAMETER OFFERS. `record Options(Summary: bool)` is one
    // declaration that becomes two metadata rows — the constructor's parameter and the field it
    // stores into — and N# has no `[property: ...]`/`[field: ...]` prefix to choose between them. So
    // the declaration admits an attribute declared for either, and the attribute's own usage decides
    // which row it is written on: a parameter wherever it allows one, the field otherwise.
    static func PositionalParameterDeclarationTargets(): int {
        parameterBit := AnalyzerAttributeUsageFacts.ParameterTarget
        fieldBit := AnalyzerAttributeUsageFacts.FieldTarget
        return parameterBit | fieldBit
    }

    // `[AttributeUsage]` OMITTED MEANS ALL TARGETS, ONCE, INHERITED — the CLR's own defaults, which are
    // also the defaults of the attribute class `AttributeUsageAttribute` itself.
    static func DefaultUsage(): AnalyzerAttributeUsage {
        return new AnalyzerAttributeUsage(AnalyzerAttributeUsageFacts.AllTargets, false, true)
    }

    static func IsAttributeUsageName(name: string): bool {
        return name == "AttributeUsage" || name == "AttributeUsageAttribute" || name == "System.AttributeUsage" || name == "System.AttributeUsageAttribute"
    }

    static func AllowMultipleMemberName(): string {
        return "AllowMultiple"
    }

    static func InheritedMemberName(): string {
        return "Inherited"
    }

    // THE DECLARATION A TARGET BIT NAMES, as the sentence reads it: "cannot be applied to A METHOD".
    static func DescribeTarget(target: int): string {
        if target == AnalyzerAttributeUsageFacts.ClassTarget {
            return "a class"
        }
        if target == AnalyzerAttributeUsageFacts.StructTarget {
            return "a struct"
        }
        if target == AnalyzerAttributeUsageFacts.EnumTarget {
            return "an enum"
        }
        if target == AnalyzerAttributeUsageFacts.InterfaceTarget {
            return "an interface"
        }
        if target == AnalyzerAttributeUsageFacts.ConstructorTarget {
            return "a constructor"
        }
        if target == AnalyzerAttributeUsageFacts.FieldTarget {
            return "a field"
        }
        if target == AnalyzerAttributeUsageFacts.ParameterTarget {
            return "a parameter"
        }
        if target == AnalyzerAttributeUsageFacts.MethodTarget {
            return "a function"
        }

        // A PROPERTY CARRIES TWO BITS IN N#, and the sentence names the declaration the developer
        // wrote rather than the pair.
        if target == AnalyzerAttributeUsageFacts.PropertyTarget + AnalyzerAttributeUsageFacts.MethodTarget {
            return "a property"
        }

        // SO DOES A POSITIONAL CONSTRUCTOR PARAMETER, for the same reason: one declaration, two rows.
        if target == AnalyzerAttributeUsageFacts.PositionalParameterDeclarationTargets() {
            return "a positional constructor parameter"
        }

        return "this declaration"
    }

    // WHERE THE ATTRIBUTE MAY GO, listed in the order `AttributeTargets` declares them so two
    // attributes with the same targets always read the same way.
    static func DescribeTargets(targets: int): string {
        if targets == AnalyzerAttributeUsageFacts.AllTargets {
            return "any declaration"
        }

        names := new List<string>()
        AppendTargetName(names, targets, AnalyzerAttributeUsageFacts.AssemblyTarget, "assemblies")
        AppendTargetName(names, targets, AnalyzerAttributeUsageFacts.ModuleTarget, "modules")
        AppendTargetName(names, targets, AnalyzerAttributeUsageFacts.ClassTarget, "classes")
        AppendTargetName(names, targets, AnalyzerAttributeUsageFacts.StructTarget, "structs")
        AppendTargetName(names, targets, AnalyzerAttributeUsageFacts.EnumTarget, "enums")
        AppendTargetName(names, targets, AnalyzerAttributeUsageFacts.ConstructorTarget, "constructors")
        AppendTargetName(names, targets, AnalyzerAttributeUsageFacts.MethodTarget, "functions")
        AppendTargetName(names, targets, AnalyzerAttributeUsageFacts.PropertyTarget, "properties")
        AppendTargetName(names, targets, AnalyzerAttributeUsageFacts.FieldTarget, "fields")
        AppendTargetName(names, targets, AnalyzerAttributeUsageFacts.EventTarget, "events")
        AppendTargetName(names, targets, AnalyzerAttributeUsageFacts.InterfaceTarget, "interfaces")
        AppendTargetName(names, targets, AnalyzerAttributeUsageFacts.ParameterTarget, "parameters")
        AppendTargetName(names, targets, AnalyzerAttributeUsageFacts.DelegateTarget, "delegates")
        AppendTargetName(names, targets, AnalyzerAttributeUsageFacts.ReturnValueTarget, "return values")
        AppendTargetName(names, targets, AnalyzerAttributeUsageFacts.GenericParameterTarget, "generic parameters")
        if names.Count == 0 {
            return "nothing"
        }

        return string.Join(", ", names)
    }

    static func AppendTargetName(names: List<string>, targets: int, bit: int, name: string) {
        if (targets & bit) == bit {
            names.Add(name)
        }
    }

    // THE USAGE A METADATA ATTRIBUTE TYPE DECLARES, read from its own custom-attribute ROWS rather than
    // by instantiating it: a reference-loaded type cannot be instantiated at all. False means the type
    // declares none of its own, and the caller asks its base — `[AttributeUsage]` is itself inherited.
    static func TryReadDeclaredUsage(attributeType: Type, out usage: AnalyzerAttributeUsage): bool {
        usage = AnalyzerAttributeUsageFacts.DefaultUsage()
        rows := attributeType.GetCustomAttributesData()
        rowIndex := 0
        while rowIndex < rows.Count {
            row := rows[rowIndex]
            rowIndex = rowIndex + 1
            if row.AttributeType.FullName != "System.AttributeUsageAttribute" {
                continue
            }

            targets := AnalyzerAttributeUsageFacts.AllTargets
            constructorArguments := row.ConstructorArguments
            if constructorArguments.Count == 1 {
                targetValue := constructorArguments[0].get_Value()
                if targetValue != null {
                    targets = Convert.ToInt32(targetValue)
                }
            }

            allowMultiple := false
            inherited := true
            namedArguments := row.NamedArguments
            namedIndex := 0
            while namedIndex < namedArguments.Count {
                named := namedArguments[namedIndex]
                namedIndex = namedIndex + 1
                namedValue := named.TypedValue.get_Value()
                if namedValue == null {
                    continue
                }

                if named.MemberName == AnalyzerAttributeUsageFacts.AllowMultipleMemberName() {
                    allowMultiple = Convert.ToBoolean(namedValue)
                }

                if named.MemberName == AnalyzerAttributeUsageFacts.InheritedMemberName() {
                    inherited = Convert.ToBoolean(namedValue)
                }
            }

            usage = new AnalyzerAttributeUsage(targets, allowMultiple, inherited)
            return true
        }

        return false
    }

    // THE WHOLE METADATA ANSWER: the type's own declaration, or the nearest base that declares one.
    // The walk is bounded rather than trusted to terminate, for the same reason every other base walk
    // in this compiler is.
    static func ReadUsage(attributeType: Type): AnalyzerAttributeUsage {
        current: Type? = attributeType
        depth := 0
        while current != null && depth < 64 {
            step: Type = current
            usage := AnalyzerAttributeUsageFacts.DefaultUsage()
            if TryReadDeclaredUsage(step, out usage) {
                return usage
            }

            current = step.BaseType
            depth = depth + 1
        }

        return AnalyzerAttributeUsageFacts.DefaultUsage()
    }
}
