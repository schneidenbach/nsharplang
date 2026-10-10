namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Globalization
import System.Reflection
import NSharpLang.Compiler


// A REFERENCED ASSEMBLY'S FREE FUNCTIONS, AS THE SIBLINGS A BARE CALL RESOLVES.
//
// A namespace's free functions are its members wherever they were compiled, exactly as its types
// are. An N# assembly puts `func Helper()` of `namespace X` on the holder `X.Program` (the global
// namespace's on `Program`, and `<Program>` wherever the namespace declares a type named `Program`
// itself -- see `ColumnarFreeFunctionScope`), so a program that REFERENCES that assembly reaches
// `Helper` by its bare name through the same `SimpleNamePrecedence` walk a source function takes:
// the caller's own namespace, each enclosing one out to the global namespace, then its imports.
// Until this owner existed only source free functions took part in that walk, so a free function
// could not be called across an assembly boundary at all -- NL412 in the analyzer and
// `emit.call.bare-unresolved` in the emitter -- and carving `Compiler.Syntax`, whose parser kernels
// are global free functions, out of Core broke every Core call into them.
//
// ONLY THE HOLDER'S PUBLIC STATIC METHODS ARE FREE FUNCTIONS. A camelCase free function is emitted
// CLR `assembly`, so what a referenced assembly exports is exactly what it made public. A holder
// that declares one name TWICE is not one free function of that name -- N# never emits that, and
// guessing an overload here would bind a call the analyzer's overload resolution might not -- so the
// name is left out and a call to it declines.
class ColumnarExternalFreeFunctions {

    // The public static methods of one holder, one definition per name that the holder declares
    // exactly once, in metadata order. A method this back end cannot describe as a sibling is left
    // out rather than half-described.
    static func Definitions(holder: Type): List<ColumnarSiblingMethodDefinition> {
        definitions := new List<ColumnarSiblingMethodDefinition>()
        methods := holder.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.DeclaredOnly)
        counts := new Dictionary<string, int>(StringComparer.Ordinal)
        for counted in methods {
            if counted.IsSpecialName {
                continue
            }
            existing := 0
            counts.TryGetValue(counted.Name, out existing)
            counts[counted.Name] = existing + 1
        }

        for method in methods {
            if method.IsSpecialName || counts[method.Name] != 1 {
                continue
            }
            definition := DefinitionFor(method)
            if definition != null {
                definitions.Add(definition)
            }
        }

        return definitions
    }

    // ONE METHOD AS A SIBLING: the handle the call emits, and every signature fact a bare call, a
    // named argument, an omitted default and the direct-call planner read off a source sibling --
    // here read off metadata, which a referenced method can answer where a `MethodBuilder` cannot.
    static func DefinitionFor(method: MethodInfo): ColumnarSiblingMethodDefinition? {
        parameters := method.GetParameters()
        isExtension := DeclaresAttribute(method.GetCustomAttributesData(), "System.Runtime.CompilerServices.ExtensionAttribute")
        paramTypes := new Type[](parameters.Length)
        modifierKinds := new int[](parameters.Length)
        names := new string[](parameters.Length)
        defaultKinds := new int[](parameters.Length)
        defaultTexts := new string[](parameters.Length)
        doesNotReturnIf := new int[](parameters.Length)
        index := 0
        while index < parameters.Length {
            parameter := parameters[index]
            paramTypes[index] = parameter.ParameterType
            modifierKinds[index] = ModifierKindFor(parameter, isExtension && index == 0)
            names[index] = parameter.Name ?? ""
            defaultKinds[index] = -1
            defaultTexts[index] = ""
            defaultKind := -1
            defaultText := ""
            if TryReadDefault(parameter, out defaultKind, out defaultText) {
                defaultKinds[index] = defaultKind
                defaultTexts[index] = defaultText
            }
            doesNotReturnIf[index] = ReachabilityFlowAttributeReflection.FromParameter(parameter)
            index = index + 1
        }

        typeParams := System.Type.EmptyTypes
        specialConstraints := new int[](0)
        baseConstraints := new Type?[](0)
        interfaceConstraints := new Type[][](0)
        if method.IsGenericMethodDefinition {
            typeParams = method.GetGenericArguments()
            specialConstraints = new int[](typeParams.Length)
            baseConstraints = new Type?[](typeParams.Length)
            interfaceConstraints = new Type[][](typeParams.Length)
            typeParamIndex := 0
            while typeParamIndex < typeParams.Length {
                typeParam := typeParams[typeParamIndex]
                specialConstraints[typeParamIndex] = SpecialConstraintFor(typeParam.GenericParameterAttributes)
                interfaces := new List<Type>()
                for constraint in typeParam.GetGenericParameterConstraints() {
                    if constraint.IsInterface {
                        interfaces.Add(constraint)
                    } else if constraint.FullName != "System.ValueType" {
                        baseConstraints[typeParamIndex] = constraint
                    }
                }
                interfaceConstraints[typeParamIndex] = interfaces.ToArray()
                typeParamIndex = typeParamIndex + 1
            }
        } else if method.IsGenericMethod {
            return null
        }

        definition := new ColumnarSiblingMethodDefinition(method, paramTypes, modifierKinds, method.ReturnType, typeParams, specialConstraints, baseConstraints, interfaceConstraints)
        definition.ParamNames = names
        definition.ParamDefaultKinds = defaultKinds
        definition.ParamDefaultTexts = defaultTexts
        definition.DoesNotReturn = ReachabilityFlowAttributeReflection.FromMethodAttributes(method.GetCustomAttributesData()) == ReachabilityFlowFacts.DoesNotReturn()
        definition.ParameterDoesNotReturnIf = doesNotReturnIf
        return definition
    }

    // The parser's modifier codes, read back off a parameter: `ref` 1, `out` 2, `params` 3, the
    // extension receiver `this` 4, `in` 5, and 0 for a plain parameter.
    static func ModifierKindFor(parameter: ParameterInfo, isExtensionReceiver: bool): int {
        if isExtensionReceiver {
            return 4
        }
        if parameter.ParameterType.IsByRef {
            if parameter.IsOut && !parameter.IsIn {
                return 2
            }
            if parameter.IsIn {
                return 5
            }
            return 1
        }
        if DeclaresAttribute(parameter.GetCustomAttributesData(), "System.ParamArrayAttribute") {
            return 3
        }
        return 0
    }

    // `class` 1, `struct` 2, `new()` 4 -- the bits `ColumnarGenericConstraintPlanner.AttributeBitsFor`
    // writes back as `GenericParameterAttributes`. A `struct` constraint implies `new()` in metadata
    // and is read as `struct` alone, the way it was written.
    static func SpecialConstraintFor(attributes: GenericParameterAttributes): int {
        special := 0
        if (attributes & GenericParameterAttributes.ReferenceTypeConstraint) != GenericParameterAttributes.None {
            special = special | 1
        }
        if (attributes & GenericParameterAttributes.NotNullableValueTypeConstraint) != GenericParameterAttributes.None {
            special = special | 2
        } else if (attributes & GenericParameterAttributes.DefaultConstructorConstraint) != GenericParameterAttributes.None {
            special = special | 4
        }
        return special
    }

    // AN OMITTED ARGUMENT'S DEFAULT, in the spelling a source default is carried in: the literal's
    // token kind and its written text (`null` 46, `true` 44, `false` 45, an `int` 1, a `string` 4 as
    // its quoted literal). A default this cannot spell -- another type, or a string that would need
    // an escape -- is left undescribed, so a call that omits it declines rather than guessing.
    static func TryReadDefault(parameter: ParameterInfo, out kind: int, out text: string): bool {
        kind = -1
        text = ""
        if !parameter.HasDefaultValue {
            return false
        }

        value := parameter.RawDefaultValue
        if value == null {
            kind = 46
            text = "null"
            return true
        }

        boxed: object = value
        trueValue: object = true
        falseValue: object = false
        if boxed.Equals(trueValue) {
            kind = 44
            text = "true"
            return true
        }
        if boxed.Equals(falseValue) {
            kind = 45
            text = "false"
            return true
        }

        parameterType := parameter.ParameterType
        if parameterType.FullName == "System.Int32" {
            kind = 1
            text = Convert.ToInt32(boxed, CultureInfo.InvariantCulture).ToString(CultureInfo.InvariantCulture)
            return true
        }
        if parameterType.FullName == "System.String" {
            written := boxed.ToString() ?? ""
            for character in written {
                if character == '"' || character == '\\' || character == '{' || character == '}' || Char.IsControl(character) {
                    return false
                }
            }
            kind = 4
            text = "\"" + written + "\""
            return true
        }

        return false
    }

    static func DeclaresAttribute(attributes: IList<CustomAttributeData>, fullName: string): bool {
        count := NullabilityMetadataReflection.SequenceCount(attributes)
        index := 0
        while index < count {
            if (attributes.get_Item(index).AttributeType.FullName ?? "") == fullName {
                return true
            }
            index = index + 1
        }
        return false
    }
}
