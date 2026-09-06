namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Globalization
import System.Reflection
import System.Reflection.Emit
import NSharpLang.Compiler


// The original host stored each pending initializer as a five-field CLR tuple. This N# data owner
// carries the same references and scalar values without validation, copying, or eager observation.
class ColumnarStaticFieldInitializer {
    Owner: ColumnarStructDef
    Field: FieldBuilder
    Type: Type
    InitKind: int
    InitText: string

    constructor(
        owner: ColumnarStructDef,
        field: FieldBuilder,
        fieldType: Type,
        initKind: int,
        initText: string
    ) {
        Owner = owner
        Field = field
        Type = fieldType
        InitKind = initKind
        InitText = initText
    }
}

// The live sibling registry previously used an eight-field CLR tuple. This N# owner carries those
// same handles and arrays by reference, with no validation or projection at construction time.
class ColumnarSiblingMethodDefinition {
    Method: MethodInfo
    ParamTypes: Type[]
    ParamModifierKinds: int[]
    ReturnType: Type
    TypeParams: Type[]
    SpecialConstraints: int[]
    BaseConstraints: Type?[]
    InterfaceConstraints: Type[][]

    constructor(
        method: MethodInfo,
        paramTypes: Type[],
        paramModifierKinds: int[],
        returnType: Type,
        typeParams: Type[],
        specialConstraints: int[],
        baseConstraints: Type?[],
        interfaceConstraints: Type[][]
    ) {
        Method = method
        ParamTypes = paramTypes
        ParamModifierKinds = paramModifierKinds
        ReturnType = returnType
        TypeParams = typeParams
        SpecialConstraints = specialConstraints
        BaseConstraints = baseConstraints
        InterfaceConstraints = interfaceConstraints
    }
}

// Sole owner for static-field initializer emission. The host supplies the declaration-order source
// definitions, pending initializer rows, and live sibling registry; this owner creates each .cctor
// lazily and emits every initializer and store in the original order.
class ColumnarStaticFieldInitializerEmitter {
    static func TryEmitAll(
        structDefinitions: ColumnarStructDef[],
        pendingInitializers: List<ColumnarStaticFieldInitializer>,
        siblings: IReadOnlyDictionary<string, ColumnarSiblingMethodDefinition>
    ): bool {
        structIndex := 0
        while structIndex < structDefinitions.Length {
            definition := structDefinitions[structIndex]
            initializerIl: ILGenerator? = null
            initializerIndex := 0
            while initializerIndex < pendingInitializers.Count {
                initializer := pendingInitializers[initializerIndex]
                if !Object.ReferenceEquals(initializer.Owner, definition) {
                    initializerIndex += 1
                    continue
                }

                if initializerIl == null {
                    initializerIl = definition.Builder.DefineTypeInitializer().GetILGenerator()
                }
                if !TryEmitStaticFieldInitializerLoad(
                    initializerIl,
                    definition,
                    initializer.Type,
                    initializer.InitKind,
                    initializer.InitText,
                    siblings
                ) {
                    return false
                }
                initializerIl.Emit(OpCodes.Stsfld, initializer.Field)
                initializerIndex += 1
            }

            if initializerIl != null {
                initializerIl.Emit(OpCodes.Ret)
            }
            structIndex += 1
        }
        return true
    }

    static func TryEmitStaticFieldInitializerLoad(
        il: ILGenerator,
        owner: ColumnarStructDef,
        fieldType: Type,
        initializerKind: int,
        text: string,
        siblings: IReadOnlyDictionary<string, ColumnarSiblingMethodDefinition>
    ): bool {
        if initializerKind == 1001 {
            return TryEmitStaticFieldExpressionInitializerLoad(il, owner, fieldType, text, siblings)
        }
        return TryEmitStaticFieldLiteralInitializerLoad(il, fieldType, initializerKind, text)
    }

    static func TryEmitStaticFieldExpressionInitializerLoad(
        il: ILGenerator,
        owner: ColumnarStructDef,
        fieldType: Type,
        text: string,
        siblings: IReadOnlyDictionary<string, ColumnarSiblingMethodDefinition>
    ): bool {
        methodName := ""
        ownerBuilder: Type = owner.Builder
        ownerName := TypeNameOrEmpty(ownerBuilder)
        if !TryParseParameterlessStaticInitializerCall(
            text,
            ownerName,
            out methodName
        ) {
            return false
        }

        overloads: List<ColumnarStaticMethodDef>? = null
        if owner.StaticMethods.TryGetValue(methodName, out overloads) {
            if overloads == null {
                throw new NullReferenceException()
            }
            overloadIndex := 0
            while overloadIndex < overloads.Count {
                overload := overloads[overloadIndex]
                if overload.ParamTypes.Length == 0 && ColumnarTypeEquivalenceFacts.TypesEquivalent(overload.ReturnType, fieldType) {
                    il.Emit(OpCodes.Call, overload.Builder)
                    return true
                }
                overloadIndex += 1
            }
        }

        sibling: ColumnarSiblingMethodDefinition? = null
        if siblings.TryGetValue(methodName, out sibling) {
            if sibling == null {
                throw new NullReferenceException()
            }
            if sibling.TypeParams.Length == 0 && sibling.ParamTypes.Length == 0 && ColumnarTypeEquivalenceFacts.TypesEquivalent(sibling.ReturnType, fieldType) {
                il.Emit(OpCodes.Call, sibling.Method)
                return true
            }
        }
        return false
    }

    static func TypeNameOrEmpty(valueType: Type): string {
        name := valueType.get_Name()
        if name == null {
            return ""
        }
        return name
    }

    static func TryParseParameterlessStaticInitializerCall(
        text: string,
        ownerName: string,
        out methodName: string
    ): bool {
        methodName = ""
        trimmed := text.Trim()
        if !trimmed.EndsWith(")", StringComparison.Ordinal) {
            return false
        }
        openParen := trimmed.IndexOf('(')
        if openParen <= 0 || trimmed.IndexOf('(', openParen + 1) >= 0 {
            return false
        }
        if !string.IsNullOrWhiteSpace(
            trimmed.Substring(openParen + 1, trimmed.Length - openParen - 2)
        ) {
            return false
        }

        target := trimmed.Substring(0, openParen).Trim()
        dot := target.LastIndexOf('.')
        if dot >= 0 {
            receiver := target.Substring(0, dot).Trim()
            if !string.Equals(receiver, ownerName, StringComparison.Ordinal) {
                return false
            }
            target = target.Substring(dot + 1).Trim()
        }
        if !IsSimpleIdentifierText(target) {
            return false
        }
        methodName = target
        return true
    }

    static func IsSimpleIdentifierText(text: string): bool {
        if text.Length == 0 || (!char.IsLetter(text[0]) && text[0] != '_') {
            return false
        }
        index := 1
        while index < text.Length {
            ch := text[index]
            if !char.IsLetterOrDigit(ch) && ch != '_' {
                return false
            }
            index += 1
        }
        return true
    }

    static func IsSupportedGenericExtensionReceiverChainText(
        receiverChain: string,
        out names: string[]
    ): bool {
        names = System.Array.Empty<string>()
        if receiverChain.Length == 0 || receiverChain.Contains('(') || receiverChain.Contains(')') || receiverChain.Contains('[') || receiverChain.Contains(']') {
            return false
        }

        names = receiverChain.Split('.')
        if names.Length == 0 {
            return false
        }
        index := 0
        while index < names.Length {
            if !IsSimpleIdentifierText(names[index]) {
                return false
            }
            index += 1
        }
        return true
    }

    static func TryEmitStaticFieldLiteralInitializerLoad(
        il: ILGenerator,
        fieldType: Type,
        initializerKind: int,
        text: string
    ): bool {
        if initializerKind == 1 {
            negated := text.StartsWith("-", StringComparison.Ordinal)
            body := negated ? text.Substring(1).TrimStart() : text
            end := body.Length
            sawUnsigned := false
            sawLong := false
            scanning := true
            while end > 0 && scanning {
                suffix := body[end - 1]
                if suffix != 'u' && suffix != 'U' && suffix != 'l' && suffix != 'L' {
                    scanning = false
                    continue
                }
                if body[end - 1] == 'u' || body[end - 1] == 'U' {
                    sawUnsigned = true
                } else {
                    sawLong = true
                }
                end -= 1
            }

            digits := body.Substring(0, end)
            if sawUnsigned && sawLong {
                ulongValue := 0UL
                if negated || fieldType != typeof(ulong) || !UInt64.TryParse(digits, out ulongValue) {
                    return false
                }
                il.Emit(OpCodes.Ldc_I8, (long)ulongValue)
                return true
            }
            if sawUnsigned {
                return false
            }
            if sawLong {
                longValue := 0L
                if fieldType != typeof(long) || !Int64.TryParse(digits, out longValue) {
                    return false
                }
                emittedLong := longValue
                if negated {
                    emittedLong = -longValue
                }
                il.Emit(OpCodes.Ldc_I8, emittedLong)
                return true
            }

            intValue := 0
            if fieldType != typeof(int) || !Int32.TryParse(digits, out intValue) {
                return false
            }
            emittedInt := intValue
            if negated {
                emittedInt = -intValue
            }
            il.Emit(OpCodes.Ldc_I4, emittedInt)
            return true
        }

        if initializerKind == 2 {
            negated := text.StartsWith("-", StringComparison.Ordinal)
            body := negated ? text.Substring(1).TrimStart() : text
            last := body.Length > 0 ? body[body.Length - 1] : '\0'
            if last == 'm' || last == 'M' {
                return false
            }
            isFloatLiteral := last == 'f' || last == 'F'
            if isFloatLiteral || last == 'd' || last == 'D' {
                body = body.Substring(0, body.Length - 1)
            }

            doubleValue := 0.0
            if !TryParseFloatingLiteralBody(body, out doubleValue) {
                return false
            }
            if negated {
                doubleValue = -doubleValue
            }
            if isFloatLiteral {
                if fieldType != typeof(float) {
                    return false
                }
                il.Emit(OpCodes.Ldc_R4, (float)doubleValue)
                return true
            }
            if fieldType != typeof(double) {
                return false
            }
            il.Emit(OpCodes.Ldc_R8, doubleValue)
            return true
        }

        if initializerKind == 3 {
            if fieldType != typeof(char) {
                return false
            }
            raw := text
            if raw.Length >= 2 && raw[0] == '\'' && raw[raw.Length - 1] == '\'' {
                raw = raw.Substring(1, raw.Length - 2)
            }
            charValue := ""
            if !StringLiteralDecoder.TryDecodeBody(raw, out charValue) || charValue.Length != 1 {
                return false
            }
            il.Emit(OpCodes.Ldc_I4, (int)charValue[0])
            return true
        }

        if initializerKind == 4 {
            if fieldType != typeof(string) {
                return false
            }
            if text.Length > 0 && text[0] == '$' {
                return false
            }
            decoded := StringLiteralDecoder.Decode(text, false)
            il.Emit(OpCodes.Ldstr, decoded)
            return true
        }

        if initializerKind == 44 {
            if fieldType != typeof(bool) {
                return false
            }
            il.Emit(OpCodes.Ldc_I4_1)
            return true
        }

        if initializerKind == 45 {
            if fieldType != typeof(bool) {
                return false
            }
            il.Emit(OpCodes.Ldc_I4_0)
            return true
        }
        return false
    }

    static func TryParseFloatingLiteralBody(body: string, out value: double): bool {
        value = 0
        normalized := body.Trim().Replace("_", "")
        return Double.TryParse(
            normalized,
            NumberStyles.Float | NumberStyles.AllowThousands,
            CultureInfo.InvariantCulture,
            out value
        )
    }
}
