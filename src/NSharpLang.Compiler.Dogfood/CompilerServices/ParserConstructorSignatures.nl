import "CompilerServices/ParserDeclarations"
import "CompilerServices/ParserFunctionSignatures"
import "CompilerServices/ParserTypeReferences"

// Composed constructor-signature product core. ParserDeclarations.nl keeps the standalone constructor chain
// parser; this file owns the cross-file route that combines constructor parameter signatures, canonical type text,
// chaining initializer text, and body-brace validation for the columnar product adapter. The flattened
// ParseConstructorSignatureInfoInto ABI lives in the parity corpus.

struct ConstructorSignatureOutputTable {
    ParamNameTexts: string[]
    ParamTypeTexts: string[]
    ArgKinds: int[]
    ArgStarts: int[]
    ArgLengths: int[]
    ArgTexts: string[]
}

func ParseConstructorSignatureInfoCore(source: string, tokens: &ParserTokenTable, count: int, ctorIndex: int, outputs: &ConstructorSignatureOutputTable, typeStack: &ParserArgumentStack, nodes: &ParserNodeTable, children: &ParserChildIndexTable, canonicalNodes: &TypeReferenceCanonicalTable, parameters: &ParserFunctionParameterTable, typeParams: &ParserFunctionTypeParameterTable, whereItems: &ParserFunctionWhereTable, signatureResult: &ParserResultTable, result: &ParserResultTable): int {
    if result.Values.Length < 4 {
        return -1
    }

    paramCount := ParseFunctionSignatureCore(ref tokens, count, ctorIndex, ref typeStack, ref nodes, ref children, ref parameters, ref typeParams, ref whereItems, ref signatureResult)
    if paramCount < 0 || signatureResult.Values[1] >= 0 || signatureResult.Values[5] != 0 || signatureResult.Values[7] != 0 {
        return -1
    }

    if paramCount > outputs.ParamNameTexts.Length || paramCount > outputs.ParamTypeTexts.Length {
        return -1
    }

    paramIndex := 0
    while paramIndex < paramCount {
        paramName := FunctionSignatureSpanText(source, parameters.NameStarts[paramIndex], parameters.NameLengths[paramIndex])
        if paramName == "" {
            return -1
        }

        outputs.ParamNameTexts[paramIndex] = paramName
        outputs.ParamTypeTexts[paramIndex] = TypeReferenceCanonicalTextCore(source, ref canonicalNodes, parameters.TypeRoots[paramIndex])
        paramIndex = paramIndex + 1
    }

    if ctorIndex < 0 || ctorIndex >= count {
        return -1
    }

    if tokens.Kinds[ctorIndex] != 0 {
        return -1
    }

    if !ParserDeclarationTokenTextEquals(source, tokens.Starts[ctorIndex], tokens.ValueLengths[ctorIndex], "constructor") {
        return -1
    }

    declarationTokens := new ParserDeclarationTokenTable { Kinds: tokens.Kinds, Starts: tokens.Starts, ValueLengths: tokens.ValueLengths }
    chainArgs := new ConstructorChainArgTable { Kinds: outputs.ArgKinds, Starts: outputs.ArgStarts, Lengths: outputs.ArgLengths }
    chainResult := new ParserDeclarationResultTable { Values: result.Values }
    chainArgCount := ParseConstructorChainInfoCore(ref declarationTokens, count, ctorIndex, ref chainArgs, ref chainResult)
    if chainArgCount < 0 {
        return -1
    }

    if outputs.ArgTexts.Length < chainArgCount {
        return -1
    }

    chainArgIndex := 0
    while chainArgIndex < chainArgCount {
        outputs.ArgTexts[chainArgIndex] = source.Substring(chainArgs.Starts[chainArgIndex], chainArgs.Lengths[chainArgIndex])
        chainArgIndex = chainArgIndex + 1
    }

    bodyBrace := result.Values[1]
    if bodyBrace < 0 || bodyBrace >= count || tokens.Kinds[bodyBrace] != 129 {
        return -1
    }

    result.Values[2] = paramCount
    result.Values[3] = chainArgCount
    return paramCount
}
