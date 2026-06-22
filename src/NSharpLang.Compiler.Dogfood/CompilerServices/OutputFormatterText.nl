import System.Text

func QueryNoSymbolsText(): string {
    return "No symbols found."
}

func QuerySymbolLineText(
    indent: int,
    kindText: string,
    name: string,
    typeName: string,
    hasType: int,
    fileName: string,
    line: int,
    modifiers: string[],
    modifierCount: int): string {
    prefix := QuerySymbolIndentText(indent)
    modifierText := QuerySymbolModifierText(modifiers, modifierCount)
    typeText := ""
    if hasType != 0 {
        typeText = ": " + typeName
    }

    return prefix + modifierText + kindText + " " + name + typeText + "  (" + fileName + ":" + line.ToString() + ")"
}

func QuerySymbolParametersLineText(
    indent: int,
    names: string[],
    types: string[],
    hasDefaults: int[],
    defaultValues: string[],
    requestedCount: int): string {
    count := QuerySymbolMinInt(requestedCount, names.Length)
    count = QuerySymbolMinInt(count, types.Length)
    count = QuerySymbolMinInt(count, hasDefaults.Length)
    count = QuerySymbolMinInt(count, defaultValues.Length)

    builder := new StringBuilder(32)
    builder.Append(QuerySymbolIndentText(indent))
    builder.Append("  (")

    i := 0
    while i < count {
        if i > 0 {
            builder.Append(", ")
        }

        builder.Append(names[i])
        builder.Append(": ")
        builder.Append(types[i])
        if hasDefaults[i] != 0 {
            builder.Append(" = ")
            builder.Append(defaultValues[i])
        }

        i = i + 1
    }

    builder.Append(")")
    return builder.ToString()
}

func QueryOutlineFileLineText(fileName: string): string {
    return "File: " + fileName
}

func QueryOutlineImportsLineText(imports: string[], requestedCount: int): string {
    count := QuerySymbolMinInt(requestedCount, imports.Length)
    builder := new StringBuilder(32)
    builder.Append("Imports: ")

    i := 0
    while i < count {
        if i > 0 {
            builder.Append(", ")
        }

        builder.Append(imports[i])
        i = i + 1
    }

    return builder.ToString()
}

func QueryOutlineEntryLineText(
    indent: int,
    kindText: string,
    name: string,
    returnType: string,
    hasReturnType: int,
    line: int,
    endLine: int): string {
    prefix := QuerySymbolIndentText(indent)
    typeText := ""
    if hasReturnType != 0 {
        typeText = " -> " + returnType
    }

    rangeText := " (line " + line.ToString() + ")"
    if endLine > line {
        rangeText = " (lines " + line.ToString() + "-" + endLine.ToString() + ")"
    }

    return prefix + kindText + " " + name + typeText + rangeText
}

func QueryNoReferencesText(symbolName: string): string {
    return "No references found for '" + symbolName + "'."
}

func QueryReferencesHeaderText(symbolName: string, count: int): string {
    return "References to '" + symbolName + "' (" + count.ToString() + " found):"
}

func QueryReferenceLineText(
    fileName: string,
    line: int,
    column: int,
    isDefinition: int,
    context: string,
    hasContext: int): string {
    definitionMarker := ""
    if isDefinition != 0 {
        definitionMarker = " [definition]"
    }

    contextText := ""
    if hasContext != 0 {
        contextText = "  " + context.Trim()
    }

    return "  " + fileName + ":" + line.ToString() + ":" + column.ToString() + definitionMarker + contextText
}

func QuerySymbolModifierText(modifiers: string[], requestedCount: int): string {
    count := QuerySymbolMinInt(requestedCount, modifiers.Length)
    if count <= 0 {
        return ""
    }

    builder := new StringBuilder(32)
    builder.Append("[")

    i := 0
    while i < count {
        if i > 0 {
            builder.Append(", ")
        }

        builder.Append(modifiers[i])
        i = i + 1
    }

    builder.Append("] ")
    return builder.ToString()
}

func QuerySymbolIndentText(indent: int): string {
    spaceCount := indent * 2
    if spaceCount <= 0 {
        return ""
    }

    builder := new StringBuilder(spaceCount)
    i := 0
    while i < spaceCount {
        builder.Append(' ')
        i = i + 1
    }

    return builder.ToString()
}

func QuerySymbolMinInt(left: int, right: int): int {
    if left < right {
        return left
    }

    return right
}
