import System.Text

func CodeIntelligenceFunctionSignatureText(
    name: string,
    parameterNames: string[],
    parameterTypes: string[],
    hasDefaults: int[],
    requestedCount: int,
    returnType: string,
    hasReturnType: int): string {
    count := CodeIntelligenceSignatureMinInt(requestedCount, parameterNames.Length)
    count = CodeIntelligenceSignatureMinInt(count, parameterTypes.Length)
    count = CodeIntelligenceSignatureMinInt(count, hasDefaults.Length)

    builder := new StringBuilder(32)
    builder.Append("func ")
    builder.Append(name)
    builder.Append("(")

    i := 0
    while i < count {
        if i > 0 {
            builder.Append(", ")
        }

        builder.Append(parameterNames[i])
        builder.Append(": ")
        builder.Append(parameterTypes[i])

        if hasDefaults[i] != 0 {
            builder.Append(" = ...")
        }

        i = i + 1
    }

    builder.Append(")")

    if hasReturnType != 0 {
        builder.Append(": ")
        builder.Append(returnType)
    }

    return builder.ToString()
}

func CodeIntelligenceFallbackSignatureText(kind: string, name: string, typeName: string, hasType: int): string {
    if hasType != 0 {
        return kind + " " + name + ": " + typeName
    }

    return kind + " " + name
}

func CodeIntelligenceSignatureMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}
