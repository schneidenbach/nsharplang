namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Text

public class OutputFormatterTextKernels {
    public static func GetNoSymbolsText(): string {
        return "No symbols found."
    }

    public static func GetSymbolLineText(symbol: SymbolResult, indent: int): string {
        modifiers: string[] = new string[](0)
        rawModifiers := symbol.Modifiers
        if rawModifiers != null {
            modifiers = rawModifiers ?? new string[](0)
        }

        typeText := ""
        if symbol.TypeName != null {
            typeText = ": " + (symbol.TypeName ?? "")
        }

        return QuerySymbolIndentText(indent) +
            QuerySymbolModifierText(modifiers, modifiers.Length) +
            SymbolKindText(symbol.Kind) + " " + symbol.Name + typeText +
            "  (" + symbol.File + ":" + symbol.Line.ToString() + ")"
    }

    public static func GetSymbolParametersLineText(parameters: ParameterResult[], indent: int): string {
        count := parameters.Length
        names := new string[](count)
        types := new string[](count)
        hasDefaults := new int[](count)
        defaultValues := new string[](count)

        i := 0
        while i < count {
            parameter := parameters[i]
            names[i] = parameter.Name
            types[i] = parameter.Type
            hasDefaults[i] = 0
            if parameter.HasDefault {
                hasDefaults[i] = 1
            }

            defaultValues[i] = parameter.DefaultValue ?? ""
            i = i + 1
        }

        return QuerySymbolParametersLineText(indent, names, types, hasDefaults, defaultValues, count)
    }

    public static func GetOutlineFileLineText(fileName: string): string {
        return "File: " + fileName
    }

    public static func GetOutlineImportsLineText(imports: string[]): string {
        return QueryOutlineImportsLineText(imports, imports.Length)
    }

    public static func GetOutlineEntryLineText(entry: OutlineEntry, indent: int): string {
        returnType := entry.ReturnType ?? ""
        hasReturnType := 0
        if entry.ReturnType != null {
            hasReturnType = 1
        }

        return QueryOutlineEntryLineText(
            indent,
            SymbolKindText(entry.Kind),
            entry.Name,
            returnType,
            hasReturnType,
            entry.Line,
            entry.EndLine)
    }

    public static func GetTypeLocationHeaderText(fileName: string, line: int, column: int): string {
        return "At " + fileName + ":" + line.ToString() + ":" + column.ToString() + ":"
    }

    public static func GetTypeResultLineText(result: TypeResult): string {
        return "  " + result.Name + ": " + result.ResolvedType + " (" + result.Kind + ")"
    }

    public static func GetTypeNullabilityLineText(nullability: string): string {
        return "  Nullability: " + nullability
    }

    public static func GetTypeDefinedAtLineText(definition: LocationResult): string {
        return "  Defined at: " + definition.File + ":" + definition.Line.ToString() + ":" + definition.Column.ToString()
    }

    public static func GetCompletionsHeaderText(fileName: string, line: int, column: int, contextText: string): string {
        return "Completions at " + fileName + ":" + line.ToString() + ":" + column.ToString() + " (context: " + contextText + ")"
    }

    public static func GetCompletionReceiverLineText(receiver: string, receiverType: string?): string {
        typeText := ""
        if receiverType != null {
            typeText = " (" + (receiverType ?? "") + ")"
        }

        return "Receiver: " + receiver + typeText
    }

    public static func GetCompletionCategoryLineText(category: string, count: int): string {
        return "  " + category + " (" + count.ToString() + "):"
    }

    public static func GetCompletionItemLineText(item: CompletionItem): string {
        parameterText := ""
        if item.Parameters != null {
            parameterText = " " + (item.Parameters ?? "")
        }

        typeText := ""
        if item.Type != null {
            typeText = ": " + (item.Type ?? "")
        }

        return "    " + item.Name + parameterText + typeText
    }

    public static func GetCompletionOverflowLineText(remaining: int): string {
        return "    ... and " + remaining.ToString() + " more"
    }

    public static func GetInspectHeaderText(fileName: string, line: int, column: int): string {
        return "Inspect " + fileName + ":" + line.ToString() + ":" + column.ToString()
    }

    public static func GetInspectSymbolLineText(symbol: InspectSymbolResult): string {
        return "Symbol: " + symbol.Name + " (" + symbol.Kind + ")"
    }

    public static func GetInspectNoSymbolText(): string {
        return "Symbol: none"
    }

    public static func GetInspectTypeLineText(typeResult: TypeResult): string {
        return "Type: " + typeResult.ResolvedType + " (" + typeResult.Kind + ")"
    }

    public static func GetInspectUnknownTypeText(): string {
        return "Type: unknown"
    }

    public static func GetInspectDefinitionLineText(definition: DefinitionResult): string {
        return "Definition: " + definition.Kind + " " + definition.Name + " at " +
            definition.File + ":" + definition.Line.ToString() + ":" + definition.Column.ToString()
    }

    public static func GetInspectNoDefinitionText(): string {
        return "Definition: none"
    }

    public static func GetInspectReferencesHeaderText(count: int, definitionCount: int): string {
        return "References: " + count.ToString() + " total (" + definitionCount.ToString() + " definitions)"
    }

    public static func GetInspectReferencesOverflowLineText(remaining: int): string {
        return "  ... and " + remaining.ToString() + " more"
    }

    public static func GetHoverHeaderText(fileName: string, line: int, column: int): string {
        return "Hover " + fileName + ":" + line.ToString() + ":" + column.ToString()
    }

    public static func GetHoverSignatureLineText(signature: string): string {
        return "Signature:  " + signature
    }

    public static func GetHoverKindLineText(kindText: string): string {
        return "Kind:       " + kindText
    }

    public static func GetHoverDefinedInLineText(definedIn: string): string {
        return "Defined in: " + definedIn
    }

    public static func GetHoverDocumentationHeaderText(): string {
        return "Documentation:"
    }

    public static func GetHoverDocumentationLineText(docLine: string): string {
        return "  " + docLine
    }

    public static func GetCallGraphFunctionHeaderText(functionName: string): string {
        return "Call graph for: " + functionName
    }

    public static func GetCallGraphFullHeaderText(): string {
        return "Call graph (full project)"
    }

    public static func GetCallGraphSectionHeaderText(label: string, count: int): string {
        return label + " (" + count.ToString() + "):"
    }

    public static func GetCallGraphEdgeLineText(callSite: CallSiteResult): string {
        return "  " + callSite.Name + "  (" + (callSite.File ?? "") + ":" + callSite.Line.ToString() + ")"
    }

    public static func GetCallGraphTruncatedLineText(): string {
        return "(results truncated " + QueryTextSeparator() + " use --limit to increase)"
    }

    public static func GetImplementorsHeaderText(interfaceName: string, count: int): string {
        return "Implementors of " + interfaceName + " (" + count.ToString() + "):"
    }

    public static func GetImplementorLineText(result: ImplementorResult): string {
        return "  " + result.Kind + " " + result.TypeName + "  (" + (result.File ?? "") + ":" + result.Line.ToString() + ")"
    }

    public static func GetDocHeaderText(result: DocResult): string {
        return result.Kind + " " + result.FullName
    }

    public static func GetDocNamespaceLineText(namespaceName: string): string {
        return "  Namespace: " + namespaceName
    }

    public static func GetDocSummaryLineText(summary: string): string {
        return "  " + summary
    }

    public static func GetDocImplementsLineText(baseTypes: string[]): string {
        return QueryDocImplementsLineText(baseTypes, baseTypes.Length)
    }

    public static func GetDocParametersHeaderText(): string {
        return "  Parameters:"
    }

    public static func GetDocParameterLineText(parameter: DocParameterResult): string {
        summaryText := parameter.Summary ?? ""
        hasSummary := 0
        if parameter.Summary != null {
            hasSummary = 1
        }

        return QueryDocParameterLineText(parameter.Name, parameter.Type, summaryText, hasSummary)
    }

    public static func GetDocReturnsLineText(returnType: string, returnDoc: string?): string {
        docText := returnDoc ?? ""
        hasReturnDoc := 0
        if returnDoc != null {
            hasReturnDoc = 1
        }

        return QueryDocReturnsLineText(returnType, docText, hasReturnDoc)
    }

    public static func GetDocMembersHeaderText(kindText: string): string {
        label := "Members:"
        if kindText.IndexOf("overload", StringComparison.Ordinal) >= 0 {
            label = "Overloads:"
        }

        return "  " + label
    }

    public static func GetDocMemberLineText(member: DocMemberResult): string {
        parameters := member.Parameters ?? ""
        hasParameters := 0
        if member.Parameters != null {
            hasParameters = 1
        }

        typeName := member.Type ?? ""
        hasType := 0
        if member.Type != null {
            hasType = 1
        }

        summary := member.Summary ?? ""
        hasSummary := 0
        if member.Summary != null {
            hasSummary = 1
        }

        return QueryDocMemberLineText(
            member.Kind,
            member.Name,
            parameters,
            hasParameters,
            typeName,
            hasType,
            summary,
            hasSummary)
    }

    public static func GetDocOverflowLineText(remaining: int): string {
        return "    ... and " + remaining.ToString() + " more"
    }

    public static func GetNoReferencesText(symbolName: string): string {
        return "No references found for '" + symbolName + "'."
    }

    public static func GetReferencesHeaderText(symbolName: string, count: int): string {
        return "References to '" + symbolName + "' (" + count.ToString() + " found):"
    }

    public static func GetReferenceLineText(reference: ReferenceResult): string {
        definitionFlag := 0
        if reference.IsDefinition {
            definitionFlag = 1
        }

        context := reference.Context ?? ""
        hasContext := 0
        if reference.Context != null {
            hasContext = 1
        }

        return QueryReferenceLineText(
            reference.File,
            reference.Line,
            reference.Column,
            definitionFlag,
            context,
            hasContext)
    }

    public static func GetDefinitionLineText(definition: DefinitionResult): string {
        return definition.Kind + " " + definition.Name + " at " +
            definition.File + ":" + definition.Line.ToString() + ":" + definition.Column.ToString()
    }

    public static func GetDefinitionSearchResultLineText(definition: DefinitionResult): string {
        return "  " + definition.Kind + " " + definition.Name + " at " +
            definition.File + ":" + definition.Line.ToString() + ":" + definition.Column.ToString()
    }

    static func QuerySymbolParametersLineText(
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

    static func QueryOutlineImportsLineText(imports: string[], requestedCount: int): string {
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

    static func QueryOutlineEntryLineText(
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

    static func QueryDocImplementsLineText(baseTypes: string[], requestedCount: int): string {
        count := QuerySymbolMinInt(requestedCount, baseTypes.Length)
        builder := new StringBuilder(32)
        builder.Append("  Implements: ")

        i := 0
        while i < count {
            if i > 0 {
                builder.Append(", ")
            }

            builder.Append(baseTypes[i])
            i = i + 1
        }

        return builder.ToString()
    }

    static func QueryDocParameterLineText(
        name: string,
        typeName: string,
        summary: string,
        hasSummary: int): string {
        docText := ""
        if hasSummary != 0 {
            docText = " " + QueryTextSeparator() + " " + summary
        }

        return "    " + name + ": " + typeName + docText
    }

    static func QueryDocReturnsLineText(
        returnType: string,
        returnDoc: string,
        hasReturnDoc: int): string {
        docText := ""
        if hasReturnDoc != 0 {
            docText = " " + QueryTextSeparator() + " " + returnDoc
        }

        return "  Returns: " + returnType + docText
    }

    static func QueryDocMemberLineText(
        kindText: string,
        name: string,
        parameters: string,
        hasParameters: int,
        typeName: string,
        hasType: int,
        summary: string,
        hasSummary: int): string {
        parameterText := ""
        if hasParameters != 0 {
            parameterText = " " + parameters
        }

        typeText := ""
        if hasType != 0 {
            typeText = ": " + typeName
        }

        docText := ""
        if hasSummary != 0 {
            docText = " " + QueryTextSeparator() + " " + summary
        }

        return "    " + kindText + " " + name + parameterText + typeText + docText
    }

    static func QueryReferenceLineText(
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

    static func QueryTextSeparator(): string {
        return "—"
    }

    static func QuerySymbolModifierText(modifiers: string[], requestedCount: int): string {
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

    static func QuerySymbolIndentText(indent: int): string {
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

    static func QuerySymbolMinInt(left: int, right: int): int {
        if left < right {
            return left
        }

        return right
    }

    static func SymbolKindText(kind: SymbolKind): string {
        if kind == SymbolKind.Function {
            return "Function"
        }

        if kind == SymbolKind.Class {
            return "Class"
        }

        if kind == SymbolKind.Struct {
            return "Struct"
        }

        if kind == SymbolKind.Record {
            return "Record"
        }

        if kind == SymbolKind.Interface {
            return "Interface"
        }

        if kind == SymbolKind.Enum {
            return "Enum"
        }

        if kind == SymbolKind.Union {
            return "Union"
        }

        if kind == SymbolKind.Property {
            return "Property"
        }

        if kind == SymbolKind.Field {
            return "Field"
        }

        if kind == SymbolKind.Method {
            return "Method"
        }

        if kind == SymbolKind.Variable {
            return "Variable"
        }

        if kind == SymbolKind.Parameter {
            return "Parameter"
        }

        if kind == SymbolKind.Constructor {
            return "Constructor"
        }

        if kind == SymbolKind.EnumMember {
            return "EnumMember"
        }

        if kind == SymbolKind.TypeAlias {
            return "TypeAlias"
        }

        if kind == SymbolKind.Test {
            return "Test"
        }

        return Convert.ToInt32(kind).ToString()
    }
}
