namespace NSharpLang.Compiler.Columnar

import System
import System.Globalization
import System.Reflection
import System.Reflection.Emit


// Sole owner for CLR parameter metadata defaults and the matching constructor-call default
// decisions. The host supplies live builders, enum definitions, and an IL stream; this owner keeps
// declaration order, partial builder mutations, and default-expression emission in one place.
class ColumnarParameterDefaultEmitter {
    static MemberAccessKind: int => 1000

    static func DefineMethodParameterMetadata(method: MethodBuilder, parameterTypes: Type[], names: string[], modifierKinds: int[], defaultKinds: int[], defaultTexts: string?[], enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>): bool {
        return DefineMethodParameterMetadataWithAttributes(method, parameterTypes, names, modifierKinds, defaultKinds, defaultTexts, enumRegistry, null, null, null, null)
    }

    // `labeledCanonicals` carries each parameter's type AS WRITTEN, tuple element labels included, so
    // a parameter of named-tuple type gets its `TupleElementNamesAttribute` on the SAME
    // `ParameterBuilder` this owner already created. Defining the position twice would overwrite the
    // name and flags written here, so the attribute is attached from inside the loop rather than by a
    // second pass.
    static func DefineMethodParameterMetadataWithAttributes(
        method: MethodBuilder,
        parameterTypes: Type[],
        names: string[],
        modifierKinds: int[],
        defaultKinds: int[],
        defaultTexts: string?[],
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        sourceAttributes: ColumnarSourceAttributeInput[][]?,
        sourceResolution: ColumnarSemanticTypeResolution?,
        labeledCanonicals: string[]?,
        sourceAttributeQueue: ColumnarSourceAttributeQueue?
    ): bool {
        index := 0
        while index < names.Length {
            attributes := ParameterAttributes.None
            if index < modifierKinds.Length && modifierKinds[index] == 2 {
                attributes = attributes | ParameterAttributes.Out
            }
            // AN `in` PARAMETER IS `&T` PLUS TWO MARKS, AND BOTH HAVE TO BE THERE. The signature alone
            // says by-reference and nothing more, so `in x: T` and `ref x: T` are the same signature:
            // `ParameterAttributes.In` is the direction bit (ECMA-335 II.23.1.13) and
            // `[IsReadOnly]` on the parameter is what tells every consumer — C#, F#, and the overload
            // rules of both — that the reference may not be written through. C# writes both, and a
            // consumer that saw only one would treat the parameter as an ordinary `ref`.
            if index < modifierKinds.Length && modifierKinds[index] == 5 {
                attributes = attributes | ParameterAttributes.In
            }
            parameterType := index < parameterTypes.Length ? parameterTypes[index] : typeof(object)
            defaultValue: ColumnarParameterDefaultValue? = null
            if HasParameterDefault(defaultKinds, defaultTexts, index) {
                defaultValue = SourceDefaultFor(parameterType, defaultKinds[index], defaultTexts[index], enumRegistry)
                if defaultValue == null {
                    return false
                }

                attributes = attributes | ParameterAttributes.Optional
                if defaultValue.HasConstantRow() {
                    attributes = attributes | ParameterAttributes.HasDefault
                }
            }
            parameter := method.DefineParameter(index + 1, attributes, names[index])
            if index < modifierKinds.Length && modifierKinds[index] == 3 && !ApplyParamArrayToParameter(parameter) {
                return false
            }
            if index < modifierKinds.Length && modifierKinds[index] == 5 && !ApplyIsReadOnlyToParameter(parameter) {
                return false
            }
            if sourceAttributes != null && sourceResolution != null && sourceAttributeQueue != null && index < sourceAttributes.Length {
                sourceAttributeQueue.QueueParameter(parameter, sourceAttributes[index], sourceResolution)
            }
            if labeledCanonicals != null && index < labeledCanonicals.Length {
                ColumnarSignatureMetadataEmitter.ApplyToParameter(parameter, DeclaredParameterTypeOrNull(parameterTypes, index), labeledCanonicals[index])
            }
            if defaultValue != null {
                defaultValue.ApplyTo(parameter)
            }
            index += 1
        }
        return true
    }

    // `[IsReadOnly]` ON ONE PARAMETER. The attribute type is the one the runtime itself declares, so
    // there is nothing to synthesize and nothing to resolve out of a reference set: a consumer reading
    // it back gets the identical type C# writes. A missing parameterless constructor is a broken
    // corelib rather than a source problem, so it declines instead of emitting a half-marked
    // parameter that would read as an ordinary `ref`.
    static func ApplyIsReadOnlyToParameter(parameter: ParameterBuilder): bool {
        readOnlyCtor := typeof(System.Runtime.CompilerServices.IsReadOnlyAttribute).GetConstructor(Type.EmptyTypes)
        if readOnlyCtor == null {
            return false
        }

        parameter.SetCustomAttribute(new CustomAttributeBuilder(readOnlyCtor, new object[](0)))
        return true
    }

    // `params` is part of the CLR signature contract. Referenced assemblies expose it through
    // ParamArrayAttribute; without that metadata, the analyzer sees a plain array parameter and
    // cannot carry its selected expanded-argument binding into consumers.
    static func ApplyParamArrayToParameter(parameter: ParameterBuilder): bool {
        constructor := typeof(ParamArrayAttribute).GetConstructor(Type.EmptyTypes)
        if constructor == null {
            return false
        }

        parameter.SetCustomAttribute(new CustomAttributeBuilder(constructor, new object[](0)))
        return true
    }

    // The signature type of one parameter position, or null when the caller supplied fewer types than
    // names. The `typeof(object)` fallback below exists so a DEFAULT can still be set; it is not a
    // type anything wrote, so the metadata that describes what was written must not read it.
    static func DeclaredParameterTypeOrNull(parameterTypes: Type[], index: int): Type? {
        if index < 0 || index >= parameterTypes.Length {
            return null
        }

        return parameterTypes[index]
    }

    static func DefineConstructorParameterMetadata(
        constructorBuilder: ConstructorBuilder,
        parameterTypes: Type[],
        names: string[],
        modifierKinds: int[],
        defaultKinds: int[],
        defaultTexts: string?[],
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>
    ): bool {
        return DefineConstructorParameterMetadataWithTupleNames(constructorBuilder, parameterTypes, names, modifierKinds, defaultKinds, defaultTexts, enumRegistry, null)
    }

    static func DefineConstructorParameterMetadataWithTupleNames(
        constructorBuilder: ConstructorBuilder,
        parameterTypes: Type[],
        names: string[],
        modifierKinds: int[],
        defaultKinds: int[],
        defaultTexts: string?[],
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        labeledCanonicals: string[]?
    ): bool {
        return DefineConstructorParameterMetadataWithAttributes(constructorBuilder, parameterTypes, names, modifierKinds, defaultKinds, defaultTexts, enumRegistry, labeledCanonicals, null, null, null, null)
    }

    // `memberFields` IS WHAT MAKES A POSITIONAL PARAMETER DIFFERENT FROM EVERY OTHER PARAMETER. A
    // primary constructor's parameter declares a field as well as a parameter, and the attribute
    // written on it belongs to whichever of the two its `[AttributeUsage]` admits — a decision the
    // attribute queue makes once every type in the program has been defined. A null entry, or a null
    // column, is an ordinary parameter whose attributes have only one place to go.
    static func DefineConstructorParameterMetadataWithAttributes(
        constructorBuilder: ConstructorBuilder,
        parameterTypes: Type[],
        names: string[],
        modifierKinds: int[],
        defaultKinds: int[],
        defaultTexts: string?[],
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        labeledCanonicals: string[]?,
        sourceAttributes: ColumnarSourceAttributeInput[][]?,
        sourceResolution: ColumnarSemanticTypeResolution?,
        sourceAttributeQueue: ColumnarSourceAttributeQueue?,
        memberFields: FieldBuilder?[]?
    ): bool {
        index := 0
        while index < names.Length {
            attributes := ParameterAttributes.None
            if index < modifierKinds.Length && modifierKinds[index] == 2 {
                attributes = attributes | ParameterAttributes.Out
            }
            // The same two marks a method's `in` parameter gets; see the method loop above.
            if index < modifierKinds.Length && modifierKinds[index] == 5 {
                attributes = attributes | ParameterAttributes.In
            }
            parameterType := index < parameterTypes.Length ? parameterTypes[index] : typeof(object)
            defaultValue: ColumnarParameterDefaultValue? = null
            if HasParameterDefault(defaultKinds, defaultTexts, index) {
                defaultValue = SourceDefaultFor(parameterType, defaultKinds[index], defaultTexts[index], enumRegistry)
                if defaultValue == null {
                    return false
                }

                attributes = attributes | ParameterAttributes.Optional
                if defaultValue.HasConstantRow() {
                    attributes = attributes | ParameterAttributes.HasDefault
                }
            }
            parameter := constructorBuilder.DefineParameter(index + 1, attributes, names[index])
            if index < modifierKinds.Length && modifierKinds[index] == 3 && !ApplyParamArrayToParameter(parameter) {
                return false
            }
            if index < modifierKinds.Length && modifierKinds[index] == 5 && !ApplyIsReadOnlyToParameter(parameter) {
                return false
            }
            if sourceAttributes != null && sourceResolution != null && sourceAttributeQueue != null && index < sourceAttributes.Length {
                memberField: FieldBuilder? = null
                if memberFields != null && index < memberFields.Length {
                    memberField = memberFields[index]
                }

                sourceAttributeQueue.QueuePositionalParameter(parameter, memberField, sourceAttributes[index], sourceResolution)
            }
            if labeledCanonicals != null && index < labeledCanonicals.Length {
                ColumnarSignatureMetadataEmitter.ApplyToParameter(parameter, DeclaredParameterTypeOrNull(parameterTypes, index), labeledCanonicals[index])
            }
            if defaultValue != null {
                defaultValue.ApplyTo(parameter)
            }
            index += 1
        }
        return true
    }

    static func HasParameterDefault(defaultKinds: int[], defaultTexts: string?[], index: int): bool {
        return index >= 0 && index < defaultKinds.Length && index < defaultTexts.Length && defaultKinds[index] >= 0
    }

    // THE DEFAULT ONE SOURCE PARAMETER DECLARES, as a value of the parameter's own type: a literal,
    // `null` or `default` through `ColumnarParameterDefaultValue`, or a member of the parameter's
    // enum through this compilation's enum registry. Null is a default this type cannot hold.
    static func SourceDefaultFor(
        parameterType: Type,
        defaultKind: int,
        defaultText: string?,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>
    ): ColumnarParameterDefaultValue? {
        if ColumnarParameterDefaultValue.IsSourceLiteralKind(defaultKind) {
            return ColumnarParameterDefaultValue.FromSource(defaultKind, defaultText, parameterType)
        }
        if defaultKind != ColumnarParameterDefaultEmitter.MemberAccessKind {
            return null
        }

        stringEnumDefault := ""
        if TryResolveStringEnumParameterDefault(parameterType, defaultText, enumRegistry, out stringEnumDefault) {
            return new ColumnarParameterDefaultValue(ColumnarParameterDefaultValue.ConstantForm, parameterType, stringEnumDefault)
        }
        enumDefault := 0
        if TryResolveEnumParameterDefault(parameterType, defaultText, enumRegistry, out enumDefault) {
            return new ColumnarParameterDefaultValue(ColumnarParameterDefaultValue.ConstantForm, parameterType, enumDefault)
        }
        return null
    }

    static func TryResolveStringEnumParameterDefault(
        parameterType: Type,
        defaultText: string?,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        out value: string
    ): bool {
        value = ""
        if string.IsNullOrWhiteSpace(defaultText) {
            return false
        }

        lastDot := defaultText.LastIndexOf('.')
        if lastDot <= 0 || lastDot + 1 >= defaultText.Length {
            return false
        }

        enumTypeName := defaultText.Substring(0, lastDot)
        memberText := defaultText
        memberStart := lastDot + 1
        memberName := memberText.Substring(memberStart, memberText.Length - memberStart)
        enumDefinition: ColumnarEnumDef = null
        resolvedValue := ""
        if enumRegistry.TryGetValue(enumTypeName, out enumDefinition) && enumDefinition.StringConstants != null && ColumnarTypeEquivalenceFacts.TypesEquivalent(enumDefinition.EnumType, parameterType) && enumDefinition.StringConstants.TryGetValue(memberName, out resolvedValue) {
            value = resolvedValue
            return true
        }
        return false
    }

    static func TryResolveEnumParameterDefault(
        parameterType: Type,
        defaultText: string?,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        out value: int
    ): bool {
        value = 0
        if string.IsNullOrWhiteSpace(defaultText) {
            return false
        }

        lastDot := defaultText.LastIndexOf('.')
        if lastDot <= 0 || lastDot + 1 >= defaultText.Length {
            return false
        }

        enumTypeName := defaultText.Substring(0, lastDot)
        memberText := defaultText
        memberStart := lastDot + 1
        memberName := memberText.Substring(memberStart, memberText.Length - memberStart)
        enumDefinition: ColumnarEnumDef = null
        if enumRegistry.TryGetValue(enumTypeName, out enumDefinition) && ColumnarTypeEquivalenceFacts.TypesEquivalent(enumDefinition.EnumType, parameterType) && enumDefinition.Constants.TryGetValue(memberName, out value) {
            return true
        }

        if !(parameterType is TypeBuilder) && !(parameterType is EnumBuilder) && parameterType.IsEnum && string.Equals(Enum.GetUnderlyingType(parameterType).FullName, "System.Int32", StringComparison.Ordinal) && string.Equals(parameterType.Name, enumTypeName, StringComparison.Ordinal) && Enum.IsDefined(parameterType, memberName) {
            value = Convert.ToInt32(Enum.Parse(parameterType, memberName), CultureInfo.InvariantCulture)
            return true
        }

        if !(parameterType is TypeBuilder) && !(parameterType is EnumBuilder) && parameterType.IsEnum && string.Equals(Enum.GetUnderlyingType(parameterType).FullName, "System.Int32", StringComparison.Ordinal) && string.Equals(parameterType.FullName, enumTypeName, StringComparison.Ordinal) && Enum.IsDefined(parameterType, memberName) {
            value = Convert.ToInt32(Enum.Parse(parameterType, memberName), CultureInfo.InvariantCulture)
            return true
        }
        return false
    }

    static func CanUseConstructorDefaultAs(
        expectedType: Type,
        defaultKinds: int[],
        defaultTexts: string?[],
        index: int,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>
    ): bool {
        if index < 0 || index >= defaultKinds.Length || index >= defaultTexts.Length {
            return false
        }
        return SourceDefaultFor(expectedType, defaultKinds[index], defaultTexts[index], enumRegistry) != null
    }

    static func TryEmitConstructorDefaultArgument(
        il: ILGenerator,
        expectedType: Type,
        defaultKind: int,
        defaultText: string?,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        out resultType: Type
    ): bool {
        resultType = null
        defaultValue := SourceDefaultFor(expectedType, defaultKind, defaultText, enumRegistry)
        if defaultValue == null || !defaultValue.EmitTo(il) {
            return false
        }

        resultType = expectedType
        return true
    }
}
