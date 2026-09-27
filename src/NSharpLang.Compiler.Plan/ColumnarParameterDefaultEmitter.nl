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
            hasDefault := HasParameterDefault(defaultKinds, defaultTexts, index)
            if hasDefault {
                attributes = attributes | ParameterAttributes.Optional | ParameterAttributes.HasDefault
            }
            parameter := method.DefineParameter(index + 1, attributes, names[index])
            if index < modifierKinds.Length && modifierKinds[index] == 5 && !ApplyIsReadOnlyToParameter(parameter) {
                return false
            }
            if sourceAttributes != null && sourceResolution != null && sourceAttributeQueue != null && index < sourceAttributes.Length {
                sourceAttributeQueue.QueueParameter(parameter, sourceAttributes[index], sourceResolution)
            }
            if labeledCanonicals != null && index < labeledCanonicals.Length {
                ColumnarSignatureMetadataEmitter.ApplyToParameter(parameter, DeclaredParameterTypeOrNull(parameterTypes, index), labeledCanonicals[index])
            }
            parameterType := index < parameterTypes.Length ? parameterTypes[index] : typeof(object)
            if hasDefault && !TrySetParameterDefault(parameter, parameterType, defaultKinds[index], defaultTexts[index], enumRegistry) {
                return false
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
            hasDefault := HasParameterDefault(defaultKinds, defaultTexts, index)
            if hasDefault {
                attributes = attributes | ParameterAttributes.Optional | ParameterAttributes.HasDefault
            }
            parameter := constructorBuilder.DefineParameter(index + 1, attributes, names[index])
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

    // A DEFAULT THAT LIVES IN METADATA RATHER THAN IN THIS PROGRAM'S SOURCE. An external
    // constructor's omitted argument has no default TEXT for the kind/text pair above to read: the
    // value is a `Constant` row the CLR already decoded, and it arrives boxed. It is planned and
    // emitted from that constant, against the parameter type the signature declares — an omitted
    // argument is not a conversion site, so a default whose type is not the parameter's own is
    // refused rather than widened.
    static NoMetadataDefault: int => 0
    static NullMetadataDefault: int => 1
    static Int32MetadataDefault: int => 2
    static Int64MetadataDefault: int => 3
    static SingleMetadataDefault: int => 4
    static DoubleMetadataDefault: int => 5
    static StringMetadataDefault: int => 6

    static func TryPlanMetadataDefault(parameter: ParameterInfo, expectedType: Type, out kind: int, out bits: long, out text: string): bool {
        kind = ColumnarParameterDefaultEmitter.NoMetadataDefault
        bits = 0L
        text = ""
        if !parameter.IsOptional || !parameter.HasDefaultValue {
            return false
        }

        defaultValue := parameter.DefaultValue
        if defaultValue == null {
            if expectedType.IsValueType {
                return false
            }

            kind = ColumnarParameterDefaultEmitter.NullMetadataDefault
            return true
        }

        known: object = defaultValue
        defaultText := known as string
        if defaultText != null {
            if expectedType != typeof(string) {
                return false
            }

            kind = ColumnarParameterDefaultEmitter.StringMetadataDefault
            text = defaultText
            return true
        }

        valueType := known.GetType()
        if !MetadataDefaultTypeMatches(expectedType, valueType) {
            return false
        }

        if valueType == typeof(float) {
            kind = ColumnarParameterDefaultEmitter.SingleMetadataDefault
            bits = (long)BitConverter.SingleToInt32Bits(Convert.ToSingle(known))
            return true
        }

        if valueType == typeof(double) {
            kind = ColumnarParameterDefaultEmitter.DoubleMetadataDefault
            bits = BitConverter.DoubleToInt64Bits(Convert.ToDouble(known))
            return true
        }

        if !ColumnarAttributeBlobWriter.TryConstantToBits(known, out bits) {
            return false
        }

        kind = MetadataIntegerWidth(valueType) == 8 ? ColumnarParameterDefaultEmitter.Int64MetadataDefault : ColumnarParameterDefaultEmitter.Int32MetadataDefault
        return true
    }

    // THE PARAMETER'S OWN TYPE, OR THE ENUM WHOSE UNDERLYING TYPE THE CONSTANT WAS STORED AS — a
    // metadata `Constant` row for an enum parameter carries the underlying integer, and some readers
    // hand it back already boxed as the enum.
    static func MetadataDefaultTypeMatches(expectedType: Type, valueType: Type): bool {
        if expectedType == valueType {
            return true
        }

        if expectedType is TypeBuilder || expectedType is EnumBuilder || !expectedType.IsEnum {
            return false
        }

        return Enum.GetUnderlyingType(expectedType) == valueType
    }

    static func MetadataIntegerWidth(valueType: Type): int {
        if valueType == typeof(long) || valueType == typeof(ulong) {
            return 8
        }

        return 4
    }

    static func CanUseMetadataDefaultAs(parameter: ParameterInfo, expectedType: Type): bool {
        kind := 0
        bits := 0L
        text := ""
        return TryPlanMetadataDefault(parameter, expectedType, out kind, out bits, out text)
    }

    static func TryEmitMetadataDefaultArgument(il: ILGenerator, parameter: ParameterInfo, expectedType: Type, out resultType: Type): bool {
        resultType = null
        kind := 0
        bits := 0L
        text := ""
        if !TryPlanMetadataDefault(parameter, expectedType, out kind, out bits, out text) {
            return false
        }

        if kind == ColumnarParameterDefaultEmitter.NullMetadataDefault {
            il.Emit(OpCodes.Ldnull)
            resultType = expectedType
            return true
        }

        if kind == ColumnarParameterDefaultEmitter.StringMetadataDefault {
            il.Emit(OpCodes.Ldstr, text)
            resultType = expectedType
            return true
        }

        if kind == ColumnarParameterDefaultEmitter.SingleMetadataDefault {
            il.Emit(OpCodes.Ldc_R4, BitConverter.Int32BitsToSingle((int)bits))
            resultType = expectedType
            return true
        }

        if kind == ColumnarParameterDefaultEmitter.DoubleMetadataDefault {
            il.Emit(OpCodes.Ldc_R8, BitConverter.Int64BitsToDouble(bits))
            resultType = expectedType
            return true
        }

        if kind == ColumnarParameterDefaultEmitter.Int64MetadataDefault {
            il.Emit(OpCodes.Ldc_I8, bits)
            resultType = expectedType
            return true
        }

        il.Emit(OpCodes.Ldc_I4, (int)bits)
        resultType = expectedType
        return true
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
            return !expectedType.IsValueType
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
        if defaultKind == 46 && !expectedType.IsValueType {
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
