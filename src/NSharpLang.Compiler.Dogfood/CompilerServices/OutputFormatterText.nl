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

func QueryTypeLocationHeaderText(fileName: string, line: int, column: int): string {
    return "At " + fileName + ":" + line.ToString() + ":" + column.ToString() + ":"
}

func QueryTypeResultLineText(name: string, resolvedType: string, kindText: string): string {
    return "  " + name + ": " + resolvedType + " (" + kindText + ")"
}

func QueryTypeNullabilityLineText(nullability: string): string {
    return "  Nullability: " + nullability
}

func QueryTypeDefinedAtLineText(fileName: string, line: int, column: int): string {
    return "  Defined at: " + fileName + ":" + line.ToString() + ":" + column.ToString()
}

func QueryCompletionsHeaderText(fileName: string, line: int, column: int, contextText: string): string {
    return "Completions at " + fileName + ":" + line.ToString() + ":" + column.ToString() + " (context: " + contextText + ")"
}

func QueryCompletionReceiverLineText(receiver: string, receiverType: string, hasReceiverType: int): string {
    typeText := ""
    if hasReceiverType != 0 {
        typeText = " (" + receiverType + ")"
    }

    return "Receiver: " + receiver + typeText
}

func QueryCompletionCategoryLineText(category: string, count: int): string {
    return "  " + category + " (" + count.ToString() + "):"
}

func QueryCompletionItemLineText(name: string, parameters: string, hasParameters: int, typeName: string, hasType: int): string {
    parameterText := ""
    if hasParameters != 0 {
        parameterText = " " + parameters
    }

    typeText := ""
    if hasType != 0 {
        typeText = ": " + typeName
    }

    return "    " + name + parameterText + typeText
}

func QueryCompletionOverflowLineText(remaining: int): string {
    return "    ... and " + remaining.ToString() + " more"
}

func QueryInspectHeaderText(fileName: string, line: int, column: int): string {
    return "Inspect " + fileName + ":" + line.ToString() + ":" + column.ToString()
}

func QueryInspectSymbolLineText(name: string, kindText: string): string {
    return "Symbol: " + name + " (" + kindText + ")"
}

func QueryInspectNoSymbolText(): string {
    return "Symbol: none"
}

func QueryInspectTypeLineText(resolvedType: string, kindText: string): string {
    return "Type: " + resolvedType + " (" + kindText + ")"
}

func QueryInspectUnknownTypeText(): string {
    return "Type: unknown"
}

func QueryInspectDefinitionLineText(kindText: string, name: string, fileName: string, line: int, column: int): string {
    return "Definition: " + kindText + " " + name + " at " + fileName + ":" + line.ToString() + ":" + column.ToString()
}

func QueryInspectNoDefinitionText(): string {
    return "Definition: none"
}

func QueryInspectReferencesHeaderText(count: int, definitionCount: int): string {
    return "References: " + count.ToString() + " total (" + definitionCount.ToString() + " definitions)"
}

func QueryInspectReferencesOverflowLineText(remaining: int): string {
    return "  ... and " + remaining.ToString() + " more"
}

func QueryHoverHeaderText(fileName: string, line: int, column: int): string {
    return "Hover " + fileName + ":" + line.ToString() + ":" + column.ToString()
}

func QueryHoverSignatureLineText(signature: string): string {
    return "Signature:  " + signature
}

func QueryHoverKindLineText(kindText: string): string {
    return "Kind:       " + kindText
}

func QueryHoverDefinedInLineText(definedIn: string): string {
    return "Defined in: " + definedIn
}

func QueryHoverDocumentationHeaderText(): string {
    return "Documentation:"
}

func QueryHoverDocumentationLineText(docLine: string): string {
    return "  " + docLine
}

func QueryCallGraphForHeaderText(functionName: string): string {
    return "Call graph for: " + functionName
}

func QueryCallGraphFullHeaderText(): string {
    return "Call graph (full project)"
}

func QueryCallGraphSectionHeaderText(label: string, count: int): string {
    return label + " (" + count.ToString() + "):"
}

func QueryCallGraphEdgeLineText(name: string, fileName: string, line: int): string {
    return "  " + name + "  (" + fileName + ":" + line.ToString() + ")"
}

func QueryCallGraphTruncatedLineText(separator: string): string {
    return "(results truncated " + separator + " use --limit to increase)"
}

func QueryImplementorsHeaderText(interfaceName: string, count: int): string {
    return "Implementors of " + interfaceName + " (" + count.ToString() + "):"
}

func QueryImplementorLineText(kindText: string, typeName: string, fileName: string, line: int): string {
    return "  " + kindText + " " + typeName + "  (" + fileName + ":" + line.ToString() + ")"
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

func QueryDefinitionLineText(kindText: string, name: string, fileName: string, line: int, column: int): string {
    return kindText + " " + name + " at " + fileName + ":" + line.ToString() + ":" + column.ToString()
}

func QueryNoDefinitionsText(name: string): string {
    return "No definitions found for '" + name + "'."
}

func QueryDefinitionsHeaderText(name: string): string {
    return "Definitions of '" + name + "':"
}

func QueryDefinitionSearchResultLineText(kindText: string, name: string, fileName: string, line: int, column: int): string {
    return "  " + QueryDefinitionLineText(kindText, name, fileName, line, column)
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
