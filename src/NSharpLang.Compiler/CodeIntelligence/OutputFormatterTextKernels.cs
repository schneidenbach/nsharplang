using System;

namespace NSharpLang.Compiler.CodeIntelligence;

internal static class OutputFormatterTextKernels
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);

    internal static string GetNoSymbolsText()
        => RequiredBindings.QueryNoSymbolsText();

    internal static string GetSymbolLineText(SymbolResult symbol, int indent)
    {
        var modifiers = symbol.Modifiers ?? Array.Empty<string>();
        return RequiredBindings.QuerySymbolLineText(
            indent,
            symbol.Kind.ToString(),
            symbol.Name,
            symbol.TypeName ?? string.Empty,
            symbol.TypeName != null ? 1 : 0,
            symbol.File,
            symbol.Line,
            modifiers,
            modifiers.Length);
    }

    internal static string GetSymbolParametersLineText(ParameterResult[] parameters, int indent)
    {
        var count = parameters.Length;
        var names = new string[count];
        var types = new string[count];
        var hasDefaults = new int[count];
        var defaultValues = new string[count];

        for (var i = 0; i < count; i++)
        {
            var parameter = parameters[i];
            names[i] = parameter.Name;
            types[i] = parameter.Type;
            hasDefaults[i] = parameter.HasDefault ? 1 : 0;
            defaultValues[i] = parameter.DefaultValue ?? string.Empty;
        }

        return RequiredBindings.QuerySymbolParametersLineText(
            indent,
            names,
            types,
            hasDefaults,
            defaultValues,
            count);
    }

    internal static string GetOutlineFileLineText(string file)
        => RequiredBindings.QueryOutlineFileLineText(file);

    internal static string GetOutlineImportsLineText(string[] imports)
        => RequiredBindings.QueryOutlineImportsLineText(imports, imports.Length);

    internal static string GetOutlineEntryLineText(OutlineEntry entry, int indent)
        => RequiredBindings.QueryOutlineEntryLineText(
            indent,
            entry.Kind.ToString(),
            entry.Name,
            entry.ReturnType ?? string.Empty,
            entry.ReturnType != null ? 1 : 0,
            entry.Line,
            entry.EndLine);

    internal static string GetTypeLocationHeaderText(string file, int line, int column)
        => RequiredBindings.QueryTypeLocationHeaderText(file, line, column);

    internal static string GetTypeResultLineText(TypeResult result)
        => RequiredBindings.QueryTypeResultLineText(result.Name, result.ResolvedType, result.Kind);

    internal static string GetTypeNullabilityLineText(string nullability)
        => RequiredBindings.QueryTypeNullabilityLineText(nullability);

    internal static string GetTypeDefinedAtLineText(LocationResult definition)
        => RequiredBindings.QueryTypeDefinedAtLineText(definition.File, definition.Line, definition.Column);

    internal static string GetCompletionsHeaderText(string file, int line, int column, string contextText)
        => RequiredBindings.QueryCompletionsHeaderText(file, line, column, contextText);

    internal static string GetCompletionReceiverLineText(string receiver, string? receiverType)
        => RequiredBindings.QueryCompletionReceiverLineText(
            receiver,
            receiverType ?? string.Empty,
            receiverType != null ? 1 : 0);

    internal static string GetCompletionCategoryLineText(string category, int count)
        => RequiredBindings.QueryCompletionCategoryLineText(category, count);

    internal static string GetCompletionItemLineText(CompletionItem item)
        => RequiredBindings.QueryCompletionItemLineText(
            item.Name,
            item.Parameters ?? string.Empty,
            item.Parameters != null ? 1 : 0,
            item.Type ?? string.Empty,
            item.Type != null ? 1 : 0);

    internal static string GetCompletionOverflowLineText(int remaining)
        => RequiredBindings.QueryCompletionOverflowLineText(remaining);

    internal static string GetInspectHeaderText(string file, int line, int column)
        => RequiredBindings.QueryInspectHeaderText(file, line, column);

    internal static string GetInspectSymbolLineText(InspectSymbolResult symbol)
        => RequiredBindings.QueryInspectSymbolLineText(symbol.Name, symbol.Kind);

    internal static string GetInspectNoSymbolText()
        => RequiredBindings.QueryInspectNoSymbolText();

    internal static string GetInspectTypeLineText(TypeResult type)
        => RequiredBindings.QueryInspectTypeLineText(type.ResolvedType, type.Kind);

    internal static string GetInspectUnknownTypeText()
        => RequiredBindings.QueryInspectUnknownTypeText();

    internal static string GetInspectDefinitionLineText(DefinitionResult definition)
        => RequiredBindings.QueryInspectDefinitionLineText(
            definition.Kind,
            definition.Name,
            definition.File,
            definition.Line,
            definition.Column);

    internal static string GetInspectNoDefinitionText()
        => RequiredBindings.QueryInspectNoDefinitionText();

    internal static string GetInspectReferencesHeaderText(int count, int definitionCount)
        => RequiredBindings.QueryInspectReferencesHeaderText(count, definitionCount);

    internal static string GetInspectReferencesOverflowLineText(int remaining)
        => RequiredBindings.QueryInspectReferencesOverflowLineText(remaining);

    internal static string GetHoverHeaderText(string file, int line, int column)
        => RequiredBindings.QueryHoverHeaderText(file, line, column);

    internal static string GetHoverSignatureLineText(string signature)
        => RequiredBindings.QueryHoverSignatureLineText(signature);

    internal static string GetHoverKindLineText(string kind)
        => RequiredBindings.QueryHoverKindLineText(kind);

    internal static string GetHoverDefinedInLineText(string definedIn)
        => RequiredBindings.QueryHoverDefinedInLineText(definedIn);

    internal static string GetHoverDocumentationHeaderText()
        => RequiredBindings.QueryHoverDocumentationHeaderText();

    internal static string GetHoverDocumentationLineText(string docLine)
        => RequiredBindings.QueryHoverDocumentationLineText(docLine);

    internal static string GetCallGraphFunctionHeaderText(string functionName)
        => RequiredBindings.QueryCallGraphForHeaderText(functionName);

    internal static string GetCallGraphFullHeaderText()
        => RequiredBindings.QueryCallGraphFullHeaderText();

    internal static string GetCallGraphSectionHeaderText(string label, int count)
        => RequiredBindings.QueryCallGraphSectionHeaderText(label, count);

    internal static string GetCallGraphEdgeLineText(CallSiteResult callSite)
        => RequiredBindings.QueryCallGraphEdgeLineText(
            callSite.Name,
            callSite.File ?? string.Empty,
            callSite.Line);

    internal static string GetCallGraphTruncatedLineText()
        => RequiredBindings.QueryCallGraphTruncatedLineText();

    internal static string GetImplementorsHeaderText(string interfaceName, int count)
        => RequiredBindings.QueryImplementorsHeaderText(interfaceName, count);

    internal static string GetImplementorLineText(ImplementorResult result)
        => RequiredBindings.QueryImplementorLineText(
            result.Kind,
            result.TypeName,
            result.File ?? string.Empty,
            result.Line);

    internal static string GetDocHeaderText(DocResult result)
        => RequiredBindings.QueryDocHeaderText(result.Kind, result.FullName);

    internal static string GetDocNamespaceLineText(string namespaceName)
        => RequiredBindings.QueryDocNamespaceLineText(namespaceName);

    internal static string GetDocSummaryLineText(string summary)
        => RequiredBindings.QueryDocSummaryLineText(summary);

    internal static string GetDocImplementsLineText(string[] baseTypes)
        => RequiredBindings.QueryDocImplementsLineText(baseTypes, baseTypes.Length);

    internal static string GetDocParametersHeaderText()
        => RequiredBindings.QueryDocParametersHeaderText();

    internal static string GetDocParameterLineText(DocParameterResult parameter)
        => RequiredBindings.QueryDocParameterLineText(
            parameter.Name,
            parameter.Type,
            parameter.Summary ?? string.Empty,
            parameter.Summary != null ? 1 : 0);

    internal static string GetDocReturnsLineText(string returnType, string? returnDoc)
        => RequiredBindings.QueryDocReturnsLineText(
            returnType,
            returnDoc ?? string.Empty,
            returnDoc != null ? 1 : 0);

    internal static string GetDocMembersHeaderText(string kind)
        => RequiredBindings.QueryDocMembersHeaderText(kind);

    internal static string GetDocMemberLineText(DocMemberResult member)
        => RequiredBindings.QueryDocMemberLineText(
            member.Kind,
            member.Name,
            member.Parameters ?? string.Empty,
            member.Parameters != null ? 1 : 0,
            member.Type ?? string.Empty,
            member.Type != null ? 1 : 0,
            member.Summary ?? string.Empty,
            member.Summary != null ? 1 : 0);

    internal static string GetDocOverflowLineText(int remaining)
        => RequiredBindings.QueryDocOverflowLineText(remaining);

    internal static string GetNoReferencesText(string symbolName)
        => RequiredBindings.QueryNoReferencesText(symbolName);

    internal static string GetReferencesHeaderText(string symbolName, int count)
        => RequiredBindings.QueryReferencesHeaderText(symbolName, count);

    internal static string GetReferenceLineText(ReferenceResult reference)
        => RequiredBindings.QueryReferenceLineText(
            reference.File,
            reference.Line,
            reference.Column,
            reference.IsDefinition ? 1 : 0,
            reference.Context ?? string.Empty,
            reference.Context != null ? 1 : 0);

    internal static string GetDefinitionLineText(DefinitionResult definition)
        => RequiredBindings.QueryDefinitionLineText(
            definition.Kind,
            definition.Name,
            definition.File,
            definition.Line,
            definition.Column);

    internal static string GetNoDefinitionsText(string name)
        => RequiredBindings.QueryNoDefinitionsText(name);

    internal static string GetDefinitionsHeaderText(string name)
        => RequiredBindings.QueryDefinitionsHeaderText(name);

    internal static string GetDefinitionSearchResultLineText(DefinitionResult definition)
        => RequiredBindings.QueryDefinitionSearchResultLineText(
            definition.Kind,
            definition.Name,
            definition.File,
            definition.Line,
            definition.Column);

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<QueryNoSymbolsText>(
                programType,
                "QueryNoSymbolsText"),
            DogfoodKernelLoader.CreateDelegate<QuerySymbolLineText>(
                programType,
                "QuerySymbolLineText"),
            DogfoodKernelLoader.CreateDelegate<QuerySymbolParametersLineText>(
                programType,
                "QuerySymbolParametersLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryOutlineFileLineText>(
                programType,
                "QueryOutlineFileLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryOutlineImportsLineText>(
                programType,
                "QueryOutlineImportsLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryOutlineEntryLineText>(
                programType,
                "QueryOutlineEntryLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryTypeLocationHeaderText>(
                programType,
                "QueryTypeLocationHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryTypeResultLineText>(
                programType,
                "QueryTypeResultLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryTypeNullabilityLineText>(
                programType,
                "QueryTypeNullabilityLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryTypeDefinedAtLineText>(
                programType,
                "QueryTypeDefinedAtLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryCompletionsHeaderText>(
                programType,
                "QueryCompletionsHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryCompletionReceiverLineText>(
                programType,
                "QueryCompletionReceiverLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryCompletionCategoryLineText>(
                programType,
                "QueryCompletionCategoryLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryCompletionItemLineText>(
                programType,
                "QueryCompletionItemLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryCompletionOverflowLineText>(
                programType,
                "QueryCompletionOverflowLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryInspectHeaderText>(
                programType,
                "QueryInspectHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryInspectSymbolLineText>(
                programType,
                "QueryInspectSymbolLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryInspectNoSymbolText>(
                programType,
                "QueryInspectNoSymbolText"),
            DogfoodKernelLoader.CreateDelegate<QueryInspectTypeLineText>(
                programType,
                "QueryInspectTypeLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryInspectUnknownTypeText>(
                programType,
                "QueryInspectUnknownTypeText"),
            DogfoodKernelLoader.CreateDelegate<QueryInspectDefinitionLineText>(
                programType,
                "QueryInspectDefinitionLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryInspectNoDefinitionText>(
                programType,
                "QueryInspectNoDefinitionText"),
            DogfoodKernelLoader.CreateDelegate<QueryInspectReferencesHeaderText>(
                programType,
                "QueryInspectReferencesHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryInspectReferencesOverflowLineText>(
                programType,
                "QueryInspectReferencesOverflowLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryHoverHeaderText>(
                programType,
                "QueryHoverHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryHoverSignatureLineText>(
                programType,
                "QueryHoverSignatureLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryHoverKindLineText>(
                programType,
                "QueryHoverKindLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryHoverDefinedInLineText>(
                programType,
                "QueryHoverDefinedInLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryHoverDocumentationHeaderText>(
                programType,
                "QueryHoverDocumentationHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryHoverDocumentationLineText>(
                programType,
                "QueryHoverDocumentationLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryCallGraphForHeaderText>(
                programType,
                "QueryCallGraphForHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryCallGraphFullHeaderText>(
                programType,
                "QueryCallGraphFullHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryCallGraphSectionHeaderText>(
                programType,
                "QueryCallGraphSectionHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryCallGraphEdgeLineText>(
                programType,
                "QueryCallGraphEdgeLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryCallGraphTruncatedLineText>(
                programType,
                "QueryCallGraphTruncatedLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryImplementorsHeaderText>(
                programType,
                "QueryImplementorsHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryImplementorLineText>(
                programType,
                "QueryImplementorLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryDocHeaderText>(
                programType,
                "QueryDocHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryDocNamespaceLineText>(
                programType,
                "QueryDocNamespaceLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryDocSummaryLineText>(
                programType,
                "QueryDocSummaryLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryDocImplementsLineText>(
                programType,
                "QueryDocImplementsLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryDocParametersHeaderText>(
                programType,
                "QueryDocParametersHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryDocParameterLineText>(
                programType,
                "QueryDocParameterLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryDocReturnsLineText>(
                programType,
                "QueryDocReturnsLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryDocMembersHeaderText>(
                programType,
                "QueryDocMembersHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryDocMemberLineText>(
                programType,
                "QueryDocMemberLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryDocOverflowLineText>(
                programType,
                "QueryDocOverflowLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryNoReferencesText>(
                programType,
                "QueryNoReferencesText"),
            DogfoodKernelLoader.CreateDelegate<QueryReferencesHeaderText>(
                programType,
                "QueryReferencesHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryReferenceLineText>(
                programType,
                "QueryReferenceLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryDefinitionLineText>(
                programType,
                "QueryDefinitionLineText"),
            DogfoodKernelLoader.CreateDelegate<QueryNoDefinitionsText>(
                programType,
                "QueryNoDefinitionsText"),
            DogfoodKernelLoader.CreateDelegate<QueryDefinitionsHeaderText>(
                programType,
                "QueryDefinitionsHeaderText"),
            DogfoodKernelLoader.CreateDelegate<QueryDefinitionSearchResultLineText>(
                programType,
                "QueryDefinitionSearchResultLineText")));

    private delegate string QueryNoSymbolsText();

    private delegate string QuerySymbolLineText(
        int indent,
        string kindText,
        string name,
        string typeName,
        int hasType,
        string fileName,
        int line,
        string[] modifiers,
        int modifierCount);

    private delegate string QuerySymbolParametersLineText(
        int indent,
        string[] names,
        string[] types,
        int[] hasDefaults,
        string[] defaultValues,
        int requestedCount);

    private delegate string QueryOutlineFileLineText(string fileName);

    private delegate string QueryOutlineImportsLineText(string[] imports, int requestedCount);

    private delegate string QueryOutlineEntryLineText(
        int indent,
        string kindText,
        string name,
        string returnType,
        int hasReturnType,
        int line,
        int endLine);

    private delegate string QueryTypeLocationHeaderText(string fileName, int line, int column);

    private delegate string QueryTypeResultLineText(string name, string resolvedType, string kindText);

    private delegate string QueryTypeNullabilityLineText(string nullability);

    private delegate string QueryTypeDefinedAtLineText(string fileName, int line, int column);

    private delegate string QueryCompletionsHeaderText(string fileName, int line, int column, string contextText);

    private delegate string QueryCompletionReceiverLineText(string receiver, string receiverType, int hasReceiverType);

    private delegate string QueryCompletionCategoryLineText(string category, int count);

    private delegate string QueryCompletionItemLineText(
        string name,
        string parameters,
        int hasParameters,
        string typeName,
        int hasType);

    private delegate string QueryCompletionOverflowLineText(int remaining);

    private delegate string QueryInspectHeaderText(string fileName, int line, int column);

    private delegate string QueryInspectSymbolLineText(string name, string kindText);

    private delegate string QueryInspectNoSymbolText();

    private delegate string QueryInspectTypeLineText(string resolvedType, string kindText);

    private delegate string QueryInspectUnknownTypeText();

    private delegate string QueryInspectDefinitionLineText(
        string kindText,
        string name,
        string fileName,
        int line,
        int column);

    private delegate string QueryInspectNoDefinitionText();

    private delegate string QueryInspectReferencesHeaderText(int count, int definitionCount);

    private delegate string QueryInspectReferencesOverflowLineText(int remaining);

    private delegate string QueryHoverHeaderText(string fileName, int line, int column);

    private delegate string QueryHoverSignatureLineText(string signature);

    private delegate string QueryHoverKindLineText(string kindText);

    private delegate string QueryHoverDefinedInLineText(string definedIn);

    private delegate string QueryHoverDocumentationHeaderText();

    private delegate string QueryHoverDocumentationLineText(string docLine);

    private delegate string QueryCallGraphForHeaderText(string functionName);

    private delegate string QueryCallGraphFullHeaderText();

    private delegate string QueryCallGraphSectionHeaderText(string label, int count);

    private delegate string QueryCallGraphEdgeLineText(string name, string fileName, int line);

    private delegate string QueryCallGraphTruncatedLineText();

    private delegate string QueryImplementorsHeaderText(string interfaceName, int count);

    private delegate string QueryImplementorLineText(string kindText, string typeName, string fileName, int line);

    private delegate string QueryDocHeaderText(string kindText, string fullName);

    private delegate string QueryDocNamespaceLineText(string namespaceName);

    private delegate string QueryDocSummaryLineText(string summary);

    private delegate string QueryDocImplementsLineText(string[] baseTypes, int requestedCount);

    private delegate string QueryDocParametersHeaderText();

    private delegate string QueryDocParameterLineText(
        string name,
        string typeName,
        string summary,
        int hasSummary);

    private delegate string QueryDocReturnsLineText(
        string returnType,
        string returnDoc,
        int hasReturnDoc);

    private delegate string QueryDocMembersHeaderText(string kindText);

    private delegate string QueryDocMemberLineText(
        string kindText,
        string name,
        string parameters,
        int hasParameters,
        string typeName,
        int hasType,
        string summary,
        int hasSummary);

    private delegate string QueryDocOverflowLineText(int remaining);

    private delegate string QueryNoReferencesText(string symbolName);

    private delegate string QueryReferencesHeaderText(string symbolName, int count);

    private delegate string QueryReferenceLineText(
        string fileName,
        int line,
        int column,
        int isDefinition,
        string context,
        int hasContext);

    private delegate string QueryDefinitionLineText(
        string kindText,
        string name,
        string fileName,
        int line,
        int column);

    private delegate string QueryNoDefinitionsText(string name);

    private delegate string QueryDefinitionsHeaderText(string name);

    private delegate string QueryDefinitionSearchResultLineText(
        string kindText,
        string name,
        string fileName,
        int line,
        int column);

    private sealed record Bindings(
        QueryNoSymbolsText QueryNoSymbolsText,
        QuerySymbolLineText QuerySymbolLineText,
        QuerySymbolParametersLineText QuerySymbolParametersLineText,
        QueryOutlineFileLineText QueryOutlineFileLineText,
        QueryOutlineImportsLineText QueryOutlineImportsLineText,
        QueryOutlineEntryLineText QueryOutlineEntryLineText,
        QueryTypeLocationHeaderText QueryTypeLocationHeaderText,
        QueryTypeResultLineText QueryTypeResultLineText,
        QueryTypeNullabilityLineText QueryTypeNullabilityLineText,
        QueryTypeDefinedAtLineText QueryTypeDefinedAtLineText,
        QueryCompletionsHeaderText QueryCompletionsHeaderText,
        QueryCompletionReceiverLineText QueryCompletionReceiverLineText,
        QueryCompletionCategoryLineText QueryCompletionCategoryLineText,
        QueryCompletionItemLineText QueryCompletionItemLineText,
        QueryCompletionOverflowLineText QueryCompletionOverflowLineText,
        QueryInspectHeaderText QueryInspectHeaderText,
        QueryInspectSymbolLineText QueryInspectSymbolLineText,
        QueryInspectNoSymbolText QueryInspectNoSymbolText,
        QueryInspectTypeLineText QueryInspectTypeLineText,
        QueryInspectUnknownTypeText QueryInspectUnknownTypeText,
        QueryInspectDefinitionLineText QueryInspectDefinitionLineText,
        QueryInspectNoDefinitionText QueryInspectNoDefinitionText,
        QueryInspectReferencesHeaderText QueryInspectReferencesHeaderText,
        QueryInspectReferencesOverflowLineText QueryInspectReferencesOverflowLineText,
        QueryHoverHeaderText QueryHoverHeaderText,
        QueryHoverSignatureLineText QueryHoverSignatureLineText,
        QueryHoverKindLineText QueryHoverKindLineText,
        QueryHoverDefinedInLineText QueryHoverDefinedInLineText,
        QueryHoverDocumentationHeaderText QueryHoverDocumentationHeaderText,
        QueryHoverDocumentationLineText QueryHoverDocumentationLineText,
        QueryCallGraphForHeaderText QueryCallGraphForHeaderText,
        QueryCallGraphFullHeaderText QueryCallGraphFullHeaderText,
        QueryCallGraphSectionHeaderText QueryCallGraphSectionHeaderText,
        QueryCallGraphEdgeLineText QueryCallGraphEdgeLineText,
        QueryCallGraphTruncatedLineText QueryCallGraphTruncatedLineText,
        QueryImplementorsHeaderText QueryImplementorsHeaderText,
        QueryImplementorLineText QueryImplementorLineText,
        QueryDocHeaderText QueryDocHeaderText,
        QueryDocNamespaceLineText QueryDocNamespaceLineText,
        QueryDocSummaryLineText QueryDocSummaryLineText,
        QueryDocImplementsLineText QueryDocImplementsLineText,
        QueryDocParametersHeaderText QueryDocParametersHeaderText,
        QueryDocParameterLineText QueryDocParameterLineText,
        QueryDocReturnsLineText QueryDocReturnsLineText,
        QueryDocMembersHeaderText QueryDocMembersHeaderText,
        QueryDocMemberLineText QueryDocMemberLineText,
        QueryDocOverflowLineText QueryDocOverflowLineText,
        QueryNoReferencesText QueryNoReferencesText,
        QueryReferencesHeaderText QueryReferencesHeaderText,
        QueryReferenceLineText QueryReferenceLineText,
        QueryDefinitionLineText QueryDefinitionLineText,
        QueryNoDefinitionsText QueryNoDefinitionsText,
        QueryDefinitionsHeaderText QueryDefinitionsHeaderText,
        QueryDefinitionSearchResultLineText QueryDefinitionSearchResultLineText);

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# query text kernels are unavailable.");
}
