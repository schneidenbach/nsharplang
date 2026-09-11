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
        expressionNodes: ColumnarNodeTable = null
        callNode := -1
        if !TryParseStaticInitializerCall(
            text,
            ownerName,
            out expressionNodes,
            out callNode,
            out methodName
        ) {
            return false
        }

        argumentCount := expressionNodes.ChildCount(callNode) - 1
        argumentType := typeof(int)
        if argumentCount == 1 {
            argumentNode := expressionNodes.Child(callNode, 1)
            if !TryGetStaticInitializerArgumentType(
                expressionNodes,
                text,
                argumentNode,
                out argumentType
            ) {
                return false
            }
        } else if argumentCount != 0 {
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
                if StaticInitializerSignatureMatches(
                    overload.ParamTypes,
                    overload.ParamModifierKinds,
                    overload.ReturnType,
                    argumentCount,
                    argumentType,
                    fieldType
                ) {
                    if argumentCount == 1 && !TryEmitStaticInitializerArgument(
                        expressionNodes,
                        text,
                        expressionNodes.Child(callNode, 1),
                        il,
                        argumentType
                    ) {
                        return false
                    }
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
            if sibling.TypeParams.Length == 0 && StaticInitializerSignatureMatches(
                sibling.ParamTypes,
                sibling.ParamModifierKinds,
                sibling.ReturnType,
                argumentCount,
                argumentType,
                fieldType
            ) {
                if argumentCount == 1 && !TryEmitStaticInitializerArgument(
                    expressionNodes,
                    text,
                    expressionNodes.Child(callNode, 1),
                    il,
                    argumentType
                ) {
                    return false
                }
                il.Emit(OpCodes.Call, sibling.Method)
                return true
            }
        }
        return false
    }

    static func StaticInitializerSignatureMatches(
        parameterTypes: Type[],
        parameterModifierKinds: int[],
        returnType: Type,
        argumentCount: int,
        argumentType: Type,
        fieldType: Type
    ): bool {
        if parameterTypes.Length != argumentCount || !ColumnarTypeEquivalenceFacts.TypesEquivalent(returnType, fieldType) {
            return false
        }
        // The accepted parameterless path never observed modifier metadata. Keep that lookup
        // boundary unchanged, including for corrupt rows that carry a null modifier array.
        if argumentCount == 0 {
            return true
        }
        if argumentCount != 1 || (parameterModifierKinds.Length != 0 && parameterModifierKinds.Length != parameterTypes.Length) {
            return false
        }
        return (parameterModifierKinds.Length == 0 || parameterModifierKinds[0] == 0) && ColumnarTypeEquivalenceFacts.TypesEquivalent(parameterTypes[0], argumentType)
    }

    static func TryGetStaticInitializerArgumentType(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        out argumentType: Type
    ): bool {
        argumentType = typeof(int)
        plan := new ColumnarCodePlan()
        kind := nodes.Kind(node)
        if kind == ColumnarExpressionNodeKind.StringLiteralExpression() {
            return ColumnarScalarLiteralPlanner.TryGetType(nodes, source, node, plan, out argumentType)
        }
        if kind == ColumnarExpressionNodeKind.NameOfExpression() {
            return ColumnarNameOfPlanner.TryGetType(nodes, source, node, plan, out argumentType)
        }
        return false
    }

    static func TryEmitStaticInitializerArgument(
        nodes: ColumnarNodeTable,
        source: string,
        node: int,
        il: ILGenerator,
        expectedType: Type
    ): bool {
        emittedType := typeof(int)
        plan := new ColumnarCodePlan()
        kind := nodes.Kind(node)
        emitted := kind == ColumnarExpressionNodeKind.StringLiteralExpression() ? ColumnarScalarLiteralPlanner.TryEmit(nodes, source, node, plan, il, out emittedType) : kind == ColumnarExpressionNodeKind.NameOfExpression() && ColumnarNameOfPlanner.TryEmit(nodes, source, node, plan, il, out emittedType)
        return emitted && ColumnarTypeEquivalenceFacts.TypesEquivalent(emittedType, expectedType)
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
        nodes: ColumnarNodeTable = null
        callNode := -1
        if !TryParseStaticInitializerCall(text, ownerName, out nodes, out callNode, out methodName) {
            return false
        }
        if nodes.ChildCount(callNode) != 1 {
            methodName = ""
            return false
        }
        return true
    }

    static func TryParseStaticInitializerCall(
        text: string,
        ownerName: string,
        out nodes: ColumnarNodeTable,
        out callNode: int,
        out methodName: string
    ): bool {
        nodes = null
        callNode = -1
        methodName = ""
        if text == null {
            throw new NullReferenceException()
        }
        if string.IsNullOrWhiteSpace(text) {
            return false
        }

        capacity := Math.Max(3 * (text.Length + 1) + 8, 32)
        rawKinds := new int[capacity]
        rawStarts := new int[capacity]
        rawValueLengths := new int[capacity]
        tokenKinds := new int[capacity]
        tokenStarts := new int[capacity]
        tokenValueLengths := new int[capacity]
        tokenCounts := new int[2]
        tokenCount := TokenizeColumnarSourceInto(
            text,
            rawKinds,
            rawStarts,
            rawValueLengths,
            tokenKinds,
            tokenStarts,
            tokenValueLengths,
            tokenCounts
        )
        rawCount := tokenCounts[0]
        if rawCount < 0 || rawCount > capacity || tokenCount <= 0 || tokenCount > rawCount || tokenCount != tokenCounts[1] {
            return false
        }

        nodeKinds := new int[capacity]
        valueStarts := new int[capacity]
        valueLengths := new int[capacity]
        childStarts := new int[capacity]
        childCounts := new int[capacity]
        childIndices := new int[Math.Max(capacity * 4, 32)]
        spanStarts := new int[capacity]
        spanLengths := new int[capacity]
        result := new int[3]
        nodeCount := ParseColumnarExpressionInto(
            text,
            tokenKinds,
            tokenStarts,
            tokenValueLengths,
            tokenCount,
            nodeKinds,
            valueStarts,
            valueLengths,
            childStarts,
            childCounts,
            childIndices,
            spanStarts,
            spanLengths,
            result
        )
        if nodeCount < 0 || result[1] != nodeCount || result[0] < 0 || result[0] >= nodeCount || result[2] < 0 || result[2] > childIndices.Length {
            return false
        }

        rowCount := Math.Min(nodeCount + 1, nodeKinds.Length)
        nodes = new ColumnarNodeTable(
            nodeKinds[..rowCount],
            valueStarts[..rowCount],
            valueLengths[..rowCount],
            childStarts[..rowCount],
            childCounts[..rowCount],
            childIndices[..result[2]],
            spanStarts[..rowCount],
            spanLengths[..rowCount]
        )
        callNode = result[0]
        if nodes.Kind(callNode) != ColumnarExpressionNodeKind.CallExpression() || nodes.ChildCount(callNode) < 1 || nodes.ChildCount(callNode) > 2 {
            return false
        }

        callee := nodes.Child(callNode, 0)
        calleeKind := nodes.Kind(callee)
        if calleeKind == ColumnarExpressionNodeKind.IdentifierExpression() && nodes.ChildCount(callee) == 0 {
            methodName = nodes.Text(text, callee)
            return IsSimpleIdentifierText(methodName)
        }
        if calleeKind != ColumnarExpressionNodeKind.MemberAccessExpression() || nodes.ChildCount(callee) != 1 {
            return false
        }

        receiver := nodes.Child(callee, 0)
        if nodes.Kind(receiver) != ColumnarExpressionNodeKind.IdentifierExpression() || nodes.ChildCount(receiver) != 0 || !string.Equals(nodes.Text(text, receiver), ownerName, StringComparison.Ordinal) {
            return false
        }
        methodName = nodes.Text(text, callee)
        if !IsSimpleIdentifierText(methodName) {
            methodName = ""
            return false
        }
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
