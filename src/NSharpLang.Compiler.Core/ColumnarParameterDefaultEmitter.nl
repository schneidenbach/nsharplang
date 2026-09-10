namespace NSharpLang.Compiler.Columnar

import System
import System.Globalization
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler


// Sole owner for CLR parameter metadata defaults and the matching constructor-call default
// decisions. The host supplies live builders, enum definitions, and an IL stream; this owner keeps
// declaration order, partial builder mutations, and default-expression emission in one place.
class ColumnarParameterDefaultEmitter {
    static MemberAccessKind: int => 1000

    static func DefineMethodParameterMetadata(method: MethodBuilder, parameterTypes: Type[], names: string[], modifierKinds: int[], defaultKinds: int[], defaultTexts: string?[], enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>): bool {
        return DefineMethodParameterMetadataWithAttributes(method, parameterTypes, names, modifierKinds, defaultKinds, defaultTexts, enumRegistry, null, null, null)
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
        labeledCanonicals: string[]?
    ): bool {
        index := 0
        while index < names.Length {
            attributes := ParameterAttributes.None
            if index < modifierKinds.Length && modifierKinds[index] == 2 {
                attributes = attributes | ParameterAttributes.Out
            }
            hasDefault := HasParameterDefault(defaultKinds, defaultTexts, index)
            if hasDefault {
                attributes = attributes | ParameterAttributes.Optional | ParameterAttributes.HasDefault
            }
            parameter := method.DefineParameter(index + 1, attributes, names[index])
            if sourceAttributes != null && sourceResolution != null && index < sourceAttributes.Length {
                ColumnarSourceAttributes.ApplyParameter(parameter, sourceAttributes[index], sourceResolution)
            }
            if labeledCanonicals != null && index < labeledCanonicals.Length {
                ColumnarTupleElementNameEmitter.ApplyToParameter(parameter, labeledCanonicals[index])
            }
            parameterType := index < parameterTypes.Length ? parameterTypes[index] : typeof(object)
            if hasDefault && !TrySetParameterDefault(parameter, parameterType, defaultKinds[index], defaultTexts[index], enumRegistry) {
                return false
            }
            index += 1
        }
        return true
    }

    static func DefineConstructorParameterMetadata(
        constructorBuilder: ConstructorBuilder,
        parameterTypes: Type[],
        names: string[],
        modifierKinds: int[],
        defaultKinds: int[],
        defaultTexts: string?[],
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>,
        labeledCanonicals: string[]? = null
    ): bool {
        index := 0
        while index < names.Length {
            attributes := ParameterAttributes.None
            if index < modifierKinds.Length && modifierKinds[index] == 2 {
                attributes = attributes | ParameterAttributes.Out
            }
            hasDefault := HasParameterDefault(defaultKinds, defaultTexts, index)
            if hasDefault {
                attributes = attributes | ParameterAttributes.Optional | ParameterAttributes.HasDefault
            }
            parameter := constructorBuilder.DefineParameter(index + 1, attributes, names[index])
            if labeledCanonicals != null && index < labeledCanonicals.Length {
                ColumnarTupleElementNameEmitter.ApplyToParameter(parameter, labeledCanonicals[index])
            }
            parameterType := index < parameterTypes.Length ? parameterTypes[index] : typeof(object)
            if hasDefault && !TrySetParameterDefault(parameter, parameterType, defaultKinds[index], defaultTexts[index], enumRegistry) {
                return false
            }
            index += 1
        }
        return true
    }

    static func HasParameterDefault(defaultKinds: int[], defaultTexts: string?[], index: int): bool {
        return index >= 0 && index < defaultKinds.Length && index < defaultTexts.Length && defaultKinds[index] >= 0
    }

    static func TrySetParameterDefault(
        parameter: ParameterBuilder,
        parameterType: Type,
        defaultKind: int,
        defaultText: string?,
        enumRegistry: ColumnarSemanticRegistry<ColumnarEnumDef>
    ): bool {
        if defaultKind == 46 {
            parameter.SetConstant(null)
            return true
        }
        if defaultKind == 44 {
            parameter.SetConstant(true)
            return true
        }
        if defaultKind == 45 {
            parameter.SetConstant(false)
            return true
        }
        if defaultKind == 1 {
            intDefault := 0
            if Int32.TryParse(defaultText, NumberStyles.Integer, CultureInfo.InvariantCulture, out intDefault) {
                parameter.SetConstant(intDefault)
                return true
            }
            return false
        }
        if defaultKind == 4 {
            decoded: string? = null
            if defaultText != null {
                decoded = StringLiteralDecoder.Decode(defaultText, false)
            }
            parameter.SetConstant(decoded)
            return true
        }
        if defaultKind == ColumnarParameterDefaultEmitter.MemberAccessKind {
            stringEnumDefault := ""
            if TryResolveStringEnumParameterDefault(parameterType, defaultText, enumRegistry, out stringEnumDefault) {
                parameter.SetConstant(stringEnumDefault)
                return true
            }
            enumDefault := 0
            if TryResolveEnumParameterDefault(parameterType, defaultText, enumRegistry, out enumDefault) {
                parameter.SetConstant(enumDefault)
                return true
            }
        }
        return false
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

        if !(parameterType is TypeBuilder) && !(parameterType is EnumBuilder) && parameterType.get_IsEnum() && string.Equals(Enum.GetUnderlyingType(parameterType).FullName, "System.Int32", StringComparison.Ordinal) && string.Equals(parameterType.Name, enumTypeName, StringComparison.Ordinal) && Enum.IsDefined(parameterType, memberName) {
            value = Convert.ToInt32(Enum.Parse(parameterType, memberName), CultureInfo.InvariantCulture)
            return true
        }

        if !(parameterType is TypeBuilder) && !(parameterType is EnumBuilder) && parameterType.get_IsEnum() && string.Equals(Enum.GetUnderlyingType(parameterType).FullName, "System.Int32", StringComparison.Ordinal) && string.Equals(parameterType.FullName, enumTypeName, StringComparison.Ordinal) && Enum.IsDefined(parameterType, memberName) {
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
        defaultKind := defaultKinds[index]
        if defaultKind == 46 {
            return !expectedType.get_IsValueType()
        }
        if defaultKind == 44 || defaultKind == 45 {
            return expectedType == typeof(bool)
        }
        if defaultKind == 1 {
            intDefault := 0
            return expectedType == typeof(int) && Int32.TryParse(defaultTexts[index], NumberStyles.Integer, CultureInfo.InvariantCulture, out intDefault)
        }
        if defaultKind == 4 {
            return expectedType == typeof(string)
        }
        if defaultKind == ColumnarParameterDefaultEmitter.MemberAccessKind {
            stringValue := ""
            if TryResolveStringEnumParameterDefault(expectedType, defaultTexts[index], enumRegistry, out stringValue) {
                return true
            }
            intValue := 0
            return TryResolveEnumParameterDefault(expectedType, defaultTexts[index], enumRegistry, out intValue)
        }
        return false
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
        if defaultKind == 46 && !expectedType.get_IsValueType() {
            il.Emit(OpCodes.Ldnull)
            resultType = expectedType
            return true
        }
        if defaultKind == 44 && expectedType == typeof(bool) {
            il.Emit(OpCodes.Ldc_I4_1)
            resultType = typeof(bool)
            return true
        }
        if defaultKind == 45 && expectedType == typeof(bool) {
            il.Emit(OpCodes.Ldc_I4_0)
            resultType = typeof(bool)
            return true
        }
        if defaultKind == 1 && expectedType == typeof(int) {
            intDefault := 0
            if Int32.TryParse(defaultText, NumberStyles.Integer, CultureInfo.InvariantCulture, out intDefault) {
                il.Emit(OpCodes.Ldc_I4, intDefault)
                resultType = typeof(int)
                return true
            }
            return false
        }
        if defaultKind == 4 && expectedType == typeof(string) {
            emittedText := ""
            if defaultText != null {
                emittedText = StringLiteralDecoder.Decode(defaultText, false)
            }
            il.Emit(OpCodes.Ldstr, emittedText)
            resultType = typeof(string)
            return true
        }
        if defaultKind == ColumnarParameterDefaultEmitter.MemberAccessKind {
            stringEnumDefault := ""
            if TryResolveStringEnumParameterDefault(expectedType, defaultText, enumRegistry, out stringEnumDefault) {
                il.Emit(OpCodes.Ldstr, stringEnumDefault)
                resultType = expectedType
                return true
            }
            enumDefault := 0
            if TryResolveEnumParameterDefault(expectedType, defaultText, enumRegistry, out enumDefault) {
                il.Emit(OpCodes.Ldc_I4, enumDefault)
                resultType = expectedType
                return true
            }
        }
        return false
    }
}
