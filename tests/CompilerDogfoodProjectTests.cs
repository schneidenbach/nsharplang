using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.RegularExpressions;
using NSharpLang.Cli;
using NSharpLang.Compiler;
using NSharpLang.Compiler.Ast;
using NSharpLang.Compiler.CodeIntelligence;
using Xunit;

namespace NSharpLang.Tests;

public class CompilerDogfoodProjectTests
{
    [Fact]
    public void CodeIntelligenceDogfoodAdapter_LoadsPackagedNSharpAssembly()
    {
        var source = """
func main() {
    value := input.Count

    print value
}
""";
        var filePath = Path.GetFullPath(Path.Combine(Path.GetTempPath(), $"dogfood-adapter-{Guid.NewGuid():N}.nl"));
        var snapshot = new ProjectSnapshot(
            Path.GetTempPath(),
            new Dictionary<string, CompilationUnit>(),
            new Dictionary<string, SemanticModel>(),
            Array.Empty<CompilerError>(),
            new Analyzer(),
            new[] { filePath },
            sourceTexts: new Dictionary<string, string> { [filePath] = source });

        var adapterType = typeof(CodeIntelligenceService).Assembly.GetType(
                "NSharpLang.Compiler.CodeIntelligence.NSharpCodeIntelligenceDogfoodAdapter")
            ?? throw new InvalidOperationException("Dogfood code-intelligence adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var semanticModel = new SemanticModel();
        var rootScope = semanticModel.OpenScope(-1, 1, 1);
        semanticModel.RecordScopedVariable(rootScope, "x", BuiltInTypes.Int);
        semanticModel.RecordScopedVariable(rootScope, "y", BuiltInTypes.String);
        var innerScope = semanticModel.OpenScope(rootScope, 4, 1);
        semanticModel.RecordScopedVariable(innerScope, "x", BuiltInTypes.Bool);
        semanticModel.RecordScopedVariable(innerScope, "z", BuiltInTypes.Double);
        semanticModel.CloseScope(innerScope, 8, 120);
        semanticModel.CloseScope(rootScope, 12, 120);
        semanticModel.RecordProperty("Name", BuiltInTypes.String);

        var tryGetVisibleVariablesAtPosition = adapterType.GetMethod(
                "TryGetVisibleVariablesAtPosition",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryGetVisibleVariablesAtPosition.");
        var visibleArgs = new object?[] { semanticModel, 5, 10, null };
        Assert.True((bool)(tryGetVisibleVariablesAtPosition.Invoke(null, visibleArgs) ?? false));
        var visibleVariables = Assert.IsType<Dictionary<string, NSharpLang.Compiler.TypeInfo>>(visibleArgs[3]);
        Assert.Equal("bool", visibleVariables["x"].ToString());
        Assert.Equal("string", visibleVariables["y"].ToString());
        Assert.Equal("double", visibleVariables["z"].ToString());

        var tryLookupIdentifierAtPosition = adapterType.GetMethod(
                "TryLookupIdentifierAtPosition",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryLookupIdentifierAtPosition.");

        var innerLookupArgs = new object?[] { semanticModel, "x", 5, 10, null };
        Assert.True((bool)(tryLookupIdentifierAtPosition.Invoke(null, innerLookupArgs) ?? false));
        Assert.Equal("bool", innerLookupArgs[4]?.ToString());

        var outerLookupArgs = new object?[] { semanticModel, "y", 5, 10, null };
        Assert.True((bool)(tryLookupIdentifierAtPosition.Invoke(null, outerLookupArgs) ?? false));
        Assert.Equal("string", outerLookupArgs[4]?.ToString());

        var propertyLookupArgs = new object?[] { semanticModel, "Name", 5, 10, null };
        Assert.True((bool)(tryLookupIdentifierAtPosition.Invoke(null, propertyLookupArgs) ?? false));
        Assert.Equal("string", propertyLookupArgs[4]?.ToString());

        var missingLookupArgs = new object?[] { semanticModel, "missing", 5, 10, null };
        Assert.True((bool)(tryLookupIdentifierAtPosition.Invoke(null, missingLookupArgs) ?? false));
        Assert.Null(missingLookupArgs[4]);

        var tryExtractIdentifierName = adapterType.GetMethod(
                "TryExtractIdentifierName",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryExtractIdentifierName.");
        var identifierArgs = new object?[] { snapshot, filePath, source, 2, 15, null };
        Assert.True((bool)(tryExtractIdentifierName.Invoke(null, identifierArgs) ?? false));
        Assert.Equal("input", identifierArgs[5]);

        var tryExtractEditorIdentifierSpan = adapterType.GetMethod(
                "TryExtractEditorIdentifierSpan",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryExtractEditorIdentifierSpan.");
        var editorSpanArgs = new object?[] { source, 2, 15, null };
        Assert.True((bool)(tryExtractEditorIdentifierSpan.Invoke(null, editorSpanArgs) ?? false));
        var editorSpan = Assert.IsType<ValueTuple<int, int, string>>(editorSpanArgs[3]);
        Assert.Equal(14, editorSpan.Item1);
        Assert.Equal(18, editorSpan.Item2);
        Assert.Equal("input", editorSpan.Item3);

        var editorPunctuationArgs = new object?[] { source, 2, 19, null };
        Assert.True((bool)(tryExtractEditorIdentifierSpan.Invoke(null, editorPunctuationArgs) ?? false));
        Assert.Null(editorPunctuationArgs[3]);

        Assert.True(CodeIntelligenceTextUtilities.TryGetEditorIdentifierSpanAtPosition(source, 1, 14, out var publicEditorSpan));
        Assert.Equal("input", publicEditorSpan.Name);
        Assert.Equal(13, publicEditorSpan.StartCharacter);
        Assert.Equal(18, publicEditorSpan.EndCharacter);
        Assert.Equal("Count", CodeIntelligenceTextUtilities.GetEditorWordAtPosition(source, 1, 999));
        Assert.False(CodeIntelligenceTextUtilities.TryGetEditorIdentifierSpanAtPosition(source, 1, 18, out _));

        var trySelectedSpanMatchesDeclarationName = adapterType.GetMethod(
                "TrySelectedSpanMatchesDeclarationName",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TrySelectedSpanMatchesDeclarationName.");
        var declarationMatchArgs = new object?[] { snapshot, filePath, source, 2, 5, "value", 5, 9, null };
        Assert.True((bool)(trySelectedSpanMatchesDeclarationName.Invoke(null, declarationMatchArgs) ?? false));
        Assert.Equal(true, declarationMatchArgs[8]);

        var declarationMismatchArgs = new object?[] { snapshot, filePath, source, 2, 5, "value", 14, 18, null };
        Assert.True((bool)(trySelectedSpanMatchesDeclarationName.Invoke(null, declarationMismatchArgs) ?? false));
        Assert.Equal(false, declarationMismatchArgs[8]);

        var tryFindIdentifierNameColumn = adapterType.GetMethod(
                "TryFindIdentifierNameColumn",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryFindIdentifierNameColumn.");
        var declarationColumnArgs = new object?[] { source, "value", 2, 1, 0 };
        Assert.True((bool)(tryFindIdentifierNameColumn.Invoke(null, declarationColumnArgs) ?? false));
        Assert.Equal(5, declarationColumnArgs[4]);

        var tryExtractMemberReceiverName = adapterType.GetMethod(
                "TryExtractMemberReceiverName",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryExtractMemberReceiverName.");
        var receiverArgs = new object?[] { snapshot, filePath, source, 2, 20, null };
        Assert.True((bool)(tryExtractMemberReceiverName.Invoke(null, receiverArgs) ?? false));
        Assert.Equal("input", receiverArgs[5]);

        var tryExtractSourceContext = adapterType.GetMethod(
                "TryExtractSourceContext",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryExtractSourceContext.");

        var contextArgs = new object?[] { snapshot, filePath, source, 2, null };
        Assert.True((bool)(tryExtractSourceContext.Invoke(null, contextArgs) ?? false));
        Assert.Equal("value := input.Count", contextArgs[4]);

        var blankContextArgs = new object?[] { snapshot, filePath, source, 3, null };
        Assert.True((bool)(tryExtractSourceContext.Invoke(null, blankContextArgs) ?? false));
        Assert.Equal(string.Empty, blankContextArgs[4]);

        var tryExtractSourceLine = adapterType.GetMethod(
                "TryExtractSourceLine",
                BindingFlags.Static | BindingFlags.NonPublic,
                binder: null,
                types: new[] { typeof(ProjectSnapshot), typeof(string), typeof(string), typeof(int), typeof(string).MakeByRefType() },
                modifiers: null)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit snapshot TryExtractSourceLine.");

        var rawLineArgs = new object?[] { snapshot, filePath, source, 2, null };
        Assert.True((bool)(tryExtractSourceLine.Invoke(null, rawLineArgs) ?? false));
        Assert.Equal("    value := input.Count", rawLineArgs[4]);

        var blankLineArgs = new object?[] { snapshot, filePath, source, 3, null };
        Assert.True((bool)(tryExtractSourceLine.Invoke(null, blankLineArgs) ?? false));
        Assert.Equal(string.Empty, blankLineArgs[4]);

        var tryExtractDocComment = adapterType.GetMethod(
                "TryExtractDocComment",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryExtractDocComment.");

        var docSource = """
// First line
//   Second line~~

func documented(): int {
    return 1
}
""".Replace('~', ' ');
        var docFilePath = Path.GetFullPath(Path.Combine(Path.GetTempPath(), $"dogfood-adapter-doc-{Guid.NewGuid():N}.nl"));
        var docCommentArgs = new object?[] { snapshot, docFilePath, docSource, 4, null };
        Assert.True((bool)(tryExtractDocComment.Invoke(null, docCommentArgs) ?? false));
        Assert.Equal("First line\nSecond line", docCommentArgs[4]);

        var tryExtractCompletionPrefix = adapterType.GetMethod(
                "TryExtractCompletionPrefix",
                BindingFlags.Static | BindingFlags.NonPublic,
                binder: null,
                types: new[] { typeof(ProjectSnapshot), typeof(string), typeof(string), typeof(int), typeof(int), typeof(string).MakeByRefType() },
                modifiers: null)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryExtractCompletionPrefix.");

        var prefixArgs = new object?[] { snapshot, filePath, source, 2, 9, null };
        Assert.True((bool)(tryExtractCompletionPrefix.Invoke(null, prefixArgs) ?? false));
        Assert.Equal("    value", prefixArgs[5]);

        var pastEndPrefixArgs = new object?[] { snapshot, filePath, source, 2, 999, null };
        Assert.True((bool)(tryExtractCompletionPrefix.Invoke(null, pastEndPrefixArgs) ?? false));
        Assert.Equal("    value := input.Count", pastEndPrefixArgs[5]);

        var tryClassifyCompletionReceiver = adapterType.GetMethod(
                "TryClassifyCompletionReceiver",
                BindingFlags.Static | BindingFlags.NonPublic,
                binder: null,
                types: new[] { typeof(string), typeof(bool).MakeByRefType(), typeof(string).MakeByRefType() },
                modifiers: null)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryClassifyCompletionReceiver.");

        var completionReceiverArgs = new object?[] { "    factory.Create(name).", null, null };
        Assert.True((bool)(tryClassifyCompletionReceiver.Invoke(null, completionReceiverArgs) ?? false));
        Assert.Equal(true, completionReceiverArgs[1]);
        Assert.Equal("factory.Create()", completionReceiverArgs[2]);

        var identifierCompletionArgs = new object?[] { "    return value", null, null };
        Assert.True((bool)(tryClassifyCompletionReceiver.Invoke(null, identifierCompletionArgs) ?? false));
        Assert.Equal(false, identifierCompletionArgs[1]);
        Assert.Null(identifierCompletionArgs[2]);

        var tryAddGroupedCompletionItemsByKind = adapterType.GetMethod(
                "TryAddGroupedCompletionItemsByKind",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryAddGroupedCompletionItemsByKind.");
        var completionItems = new List<CompletionItem>
        {
            new("WriteLine", "method", "void", "()", null, true),
            new("Length", "property", "int", null, null, false),
            new("ToString", "method", "string", "()", null, false),
            new("MaxValue", "field", "int", null, null, true),
            new("Count", "property", "int", null, null, false)
        };
        var groupedCompletions = new Dictionary<string, List<CompletionItem>>();
        var groupingAdapterArgs = new object?[] { completionItems, groupedCompletions };
        Assert.True((bool)(tryAddGroupedCompletionItemsByKind.Invoke(null, groupingAdapterArgs) ?? false));
        Assert.Equal(new[] { "methods", "properties", "fields" }, groupedCompletions.Keys.ToArray());
        Assert.Equal(new[] { "WriteLine", "ToString" }, groupedCompletions["methods"].Select(static item => item.Name));
        Assert.Equal(new[] { "Length", "Count" }, groupedCompletions["properties"].Select(static item => item.Name));
        Assert.Equal("MaxValue", Assert.Single(groupedCompletions["fields"]).Name);

        var tryGroupReflectionMethodsByName = adapterType.GetMethod(
                "TryGroupReflectionMethodsByName",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryGroupReflectionMethodsByName.");
        var completionMethods = typeof(CompletionMethodGroupingFixture).GetMethods(
            BindingFlags.Public | BindingFlags.Instance | BindingFlags.Static);
        var methodGroupingArgs = new object?[] { completionMethods, null };
        Assert.True((bool)(tryGroupReflectionMethodsByName.Invoke(null, methodGroupingArgs) ?? false));
        var methodGrouping = methodGroupingArgs[1]
            ?? throw new InvalidOperationException("Dogfood adapter did not return method grouping.");
        var methodGroupingType = methodGrouping.GetType();
        var expectedMethodGroups = completionMethods
            .Where(static method => !method.IsSpecialName && method.DeclaringType?.FullName != "System.Object")
            .GroupBy(static method => method.Name)
            .ToList();
        var methodGroupCount = (int)(methodGroupingType.GetProperty("GroupCount")?.GetValue(methodGrouping) ?? -1);
        var methodNameIds = Assert.IsType<int[]>(methodGroupingType.GetProperty("NameIds")?.GetValue(methodGrouping));
        var methodFirstIndices = Assert.IsType<int[]>(methodGroupingType.GetProperty("FirstIndices")?.GetValue(methodGrouping));
        var methodCounts = Assert.IsType<int[]>(methodGroupingType.GetProperty("Counts")?.GetValue(methodGrouping));
        Assert.Equal(expectedMethodGroups.Count, methodGroupCount);
        for (var groupIndex = 0; groupIndex < expectedMethodGroups.Count; groupIndex++)
        {
            var expectedGroup = expectedMethodGroups[groupIndex];
            Assert.True(methodNameIds[groupIndex] > 0);
            Assert.Equal(expectedGroup.Key, completionMethods[methodFirstIndices[groupIndex]].Name);
            Assert.Equal(Array.IndexOf(completionMethods, expectedGroup.First()), methodFirstIndices[groupIndex]);
            Assert.Equal(expectedGroup.Count(), methodCounts[groupIndex]);
        }

        var tryExtractVariableDeclarationName = adapterType.GetMethod(
                "TryExtractVariableDeclarationName",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryExtractVariableDeclarationName.");

        var variableNameArgs = new object?[] { snapshot, filePath, source, 2, null };
        Assert.True((bool)(tryExtractVariableDeclarationName.Invoke(null, variableNameArgs) ?? false));
        Assert.Equal("value", variableNameArgs[4]);

        var noVariableNameArgs = new object?[] { snapshot, filePath, source, 3, null };
        Assert.True((bool)(tryExtractVariableDeclarationName.Invoke(null, noVariableNameArgs) ?? false));
        Assert.Null(noVariableNameArgs[4]);

        var tryClassifyDiagnosticClusterTraits = adapterType.GetMethod(
                "TryClassifyDiagnosticClusterTraits",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryClassifyDiagnosticClusterTraits.");
        var diagnostics = BuildDiagnosticClusterTraitDiagnostics();
        var classificationArgs = new object?[] { diagnostics, null, null };
        Assert.True((bool)(tryClassifyDiagnosticClusterTraits.Invoke(null, classificationArgs) ?? false));
        Assert.Equal(new[] { 1, 0, 2, 3, 4, 5, 6, 7 }, Assert.IsType<int[]>(classificationArgs[1]));
        Assert.Equal(new[] { 1, 0, 4, 0, 2, 5, 7, 8 }, Assert.IsType<int[]>(classificationArgs[2]));

        var tryGroupDiagnosticClusters = adapterType.GetMethod(
                "TryGroupDiagnosticClusters",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryGroupDiagnosticClusters.");
        var groupingDiagnostics = new List<DiagnosticResult>
        {
            BuildDiagnosticWithSeverity("error", 10) with
            {
                Code = "NL102",
                File = "B.nl",
                Column = 5,
                Message = "Expected token '}'"
            },
            BuildDiagnosticWithSeverity("error", 8) with
            {
                Code = "NL102",
                File = "A.nl",
                Column = 3,
                Message = "Expected token '}'"
            },
            BuildDiagnosticWithSeverity("warning", 1) with
            {
                Code = "NL301",
                File = "C.nl",
                Column = 1,
                Message = "Undefined variable 'value'"
            }
        };
        var groupingArgs = new object?[]
        {
            groupingDiagnostics,
            new[] { 1, 1, 3 },
            new[] { 0, 0, 0 },
            new[] { "Expected token {value}", "Expected token {value}", "Undefined variable {value}" },
            null
        };
        Assert.True((bool)(tryGroupDiagnosticClusters.Invoke(null, groupingArgs) ?? false));
        var grouping = groupingArgs[4] ?? throw new InvalidOperationException("Dogfood adapter did not return a grouping result.");
        var groupingType = grouping.GetType();
        Assert.Equal(2, (int)(groupingType.GetProperty("GroupCount")?.GetValue(grouping) ?? -1));
        Assert.Equal(new[] { 1, 2 }, Assert.IsType<int[]>(groupingType.GetProperty("RootIndices")?.GetValue(grouping)).Take(2));
        Assert.Equal(new[] { 2, 1 }, Assert.IsType<int[]>(groupingType.GetProperty("Counts")?.GetValue(grouping)).Take(2));
        Assert.Equal(new[] { 0, 2 }, Assert.IsType<int[]>(groupingType.GetProperty("MemberStarts")?.GetValue(grouping)).Take(2));
        Assert.Equal(new[] { 1, 0, 2 }, Assert.IsType<int[]>(groupingType.GetProperty("MemberIndices")?.GetValue(grouping)).Take(3));

        var tryDeduplicateDiagnostics = adapterType.GetMethod(
                "TryDeduplicateDiagnostics",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryDeduplicateDiagnostics.");
        var deduplicationDiagnostics = new List<DiagnosticResult>
        {
            BuildDiagnosticWithSeverity("error", 10) with
            {
                Code = "NL102",
                File = "B.nl",
                Column = 5,
                Message = "Expected token '}'",
                SourceSnippet = "first duplicate wins"
            },
            BuildDiagnosticWithSeverity("error", 2) with
            {
                Code = "NL301",
                File = "A.nl",
                Column = 3,
                Message = "Undefined variable 'value'"
            },
            BuildDiagnosticWithSeverity("error", 10) with
            {
                Code = "NL102",
                File = "B.nl",
                Column = 5,
                Message = "Expected token '}'",
                SourceSnippet = "duplicate should be ignored"
            },
            BuildDiagnosticWithSeverity("warning", 2) with
            {
                Code = "NL201",
                File = "A.nl",
                Column = 1,
                Message = "Type is inferred"
            },
            BuildDiagnosticWithSeverity("error", 2) with
            {
                Code = "NL301",
                File = "A.nl",
                Column = 3,
                Message = "Undefined variable 'value'"
            }
        };
        var deduplicationArgs = new object?[] { deduplicationDiagnostics, null, null };
        Assert.True((bool)(tryDeduplicateDiagnostics.Invoke(null, deduplicationArgs) ?? false));
        Assert.Equal(3, Assert.IsType<int>(deduplicationArgs[2]));
        Assert.Equal(new[] { 3, 1, 0 }, Assert.IsType<int[]>(deduplicationArgs[1]).Take(3));

        var tryDeduplicateDiagnosticsPreservingOrder = adapterType.GetMethod(
                "TryDeduplicateDiagnosticsPreservingOrder",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryDeduplicateDiagnosticsPreservingOrder.");
        var stableDeduplicationArgs = new object?[] { deduplicationDiagnostics, null, null };
        Assert.True((bool)(tryDeduplicateDiagnosticsPreservingOrder.Invoke(null, stableDeduplicationArgs) ?? false));
        Assert.Equal(3, Assert.IsType<int>(stableDeduplicationArgs[2]));
        Assert.Equal(new[] { 0, 1, 3 }, Assert.IsType<int[]>(stableDeduplicationArgs[1]).Take(3));

        var tryDeduplicateReferences = adapterType.GetMethod(
                "TryDeduplicateReferences",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryDeduplicateReferences.");
        var references = new List<ReferenceResult>
        {
            new("B.nl", 10, 5, 5, "first duplicate wins", IsDefinition: true),
            new("A.nl", 2, 3, 5, "first A reference", IsDefinition: false),
            new("B.nl", 10, 5, 5, "duplicate should be ignored", IsDefinition: false),
            new("A.nl", 2, 1, 5, "earlier column sorts first", IsDefinition: false),
            new("A.nl", 2, 3, 5, "duplicate A reference", IsDefinition: false)
        };
        var referenceDeduplicationArgs = new object?[] { references, null, null };
        Assert.True((bool)(tryDeduplicateReferences.Invoke(null, referenceDeduplicationArgs) ?? false));
        Assert.Equal(3, Assert.IsType<int>(referenceDeduplicationArgs[2]));
        Assert.Equal(new[] { 3, 1, 0 }, Assert.IsType<int[]>(referenceDeduplicationArgs[1]).Take(3));

        var tryBuildInspectSummaryReferenceFiles = adapterType.GetMethod(
                "TryBuildInspectSummaryReferenceFiles",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryBuildInspectSummaryReferenceFiles.");
        var summaryReferences = new List<ReferenceResult>
        {
            new(@"src\B.nl", 10, 5, 5, "B reference", IsDefinition: true),
            new("src/A.nl", 2, 3, 5, "A reference", IsDefinition: false),
            new("src/B.nl", 12, 5, 5, "normalized duplicate", IsDefinition: false),
            new(@"src\C.nl", 4, 1, 5, "C reference", IsDefinition: false),
            new("src/A.nl", 2, 8, 5, "duplicate A", IsDefinition: false)
        };
        var referenceFileSummaryArgs = new object?[] { summaryReferences, null };
        Assert.True((bool)(tryBuildInspectSummaryReferenceFiles.Invoke(null, referenceFileSummaryArgs) ?? false));
        Assert.Equal(
            summaryReferences
                .Select(reference => reference.File.Replace('\\', '/'))
                .Distinct(StringComparer.Ordinal)
                .OrderBy(file => file, StringComparer.Ordinal)
                .ToArray(),
            Assert.IsType<string[]>(referenceFileSummaryArgs[1]));

        var tryBuildDiagnosticClusterFiles = adapterType.GetMethod(
                "TryBuildDiagnosticClusterFiles",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryBuildDiagnosticClusterFiles.");
        var clusterDiagnostics = new List<DiagnosticResult>
        {
            BuildDiagnosticWithSeverity("error", 1) with { File = "src/B.nl" },
            BuildDiagnosticWithSeverity("error", 2) with { File = "src/a.nl" },
            BuildDiagnosticWithSeverity("error", 3) with { File = "SRC/A.NL" },
            BuildDiagnosticWithSeverity("error", 4) with { File = "src/C.nl" },
            BuildDiagnosticWithSeverity("error", 5) with { File = "src/b.NL" }
        };
        var diagnosticClusterFileArgs = new object?[] { clusterDiagnostics, null };
        Assert.True((bool)(tryBuildDiagnosticClusterFiles.Invoke(null, diagnosticClusterFileArgs) ?? false));
        Assert.Equal(
            clusterDiagnostics
                .Select(diagnostic => diagnostic.File)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .OrderBy(file => file, StringComparer.OrdinalIgnoreCase)
                .ToArray(),
            Assert.IsType<string[]>(diagnosticClusterFileArgs[1]));

        var tryGetBindingCandidateColumns = adapterType.GetMethod(
                "TryGetBindingCandidateColumns",
                BindingFlags.Static | BindingFlags.NonPublic,
                binder: null,
                types: new[]
                {
                    typeof(int),
                    typeof(Nullable<ValueTuple<int, int>>),
                    typeof(int[]).MakeByRefType()
                },
                modifiers: null)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryGetBindingCandidateColumns.");
        var candidateColumnArgs = new object?[] { 5, (ValueTuple<int, int>?)new ValueTuple<int, int>(3, 7), null };
        Assert.True((bool)(tryGetBindingCandidateColumns.Invoke(null, candidateColumnArgs) ?? false));
        Assert.Equal(new[] { 5, 4, 6, 3, 7 }, Assert.IsType<int[]>(candidateColumnArgs[2]));

        var noSpanCandidateColumnArgs = new object?[] { 1, null, null };
        Assert.True((bool)(tryGetBindingCandidateColumns.Invoke(null, noSpanCandidateColumnArgs) ?? false));
        Assert.Equal(new[] { 1, 2 }, Assert.IsType<int[]>(noSpanCandidateColumnArgs[2]));

        var tryResolveBindingDeclaration = adapterType.GetMethod(
                "TryResolveBindingDeclaration",
                BindingFlags.Static | BindingFlags.NonPublic,
                binder: null,
                types: new[]
                {
                    typeof(BindingMap),
                    typeof(string),
                    typeof(int),
                    typeof(int[]),
                    typeof(SymbolDeclaration).MakeByRefType()
                },
                modifiers: null)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryResolveBindingDeclaration.");
        var bindingMap = new BindingMap();
        var bDeclaration = new SymbolDeclaration("bValue", "B.nl", 10, 5, "variable");
        var aDeclaration = new SymbolDeclaration("aValue", "A.nl", 2, 3, "variable");
        bindingMap.RecordDeclaration(bDeclaration);
        bindingMap.RecordDeclaration(aDeclaration);
        bindingMap.RecordBinding("A.nl", 7, 9, 6, bDeclaration);
        bindingMap.RecordBinding("A.nl", 2, 3, 6, bDeclaration);

        var bindingUsageArgs = new object?[] { bindingMap, "A.nl", 7, new[] { 9 }, null };
        Assert.True((bool)(tryResolveBindingDeclaration.Invoke(null, bindingUsageArgs) ?? false));
        Assert.Equal(bDeclaration, Assert.IsType<SymbolDeclaration>(bindingUsageArgs[4]));

        var bindingDeclarationFirstArgs = new object?[] { bindingMap, "A.nl", 2, new[] { 3 }, null };
        Assert.True((bool)(tryResolveBindingDeclaration.Invoke(null, bindingDeclarationFirstArgs) ?? false));
        Assert.Equal(aDeclaration, Assert.IsType<SymbolDeclaration>(bindingDeclarationFirstArgs[4]));

        var bindingMissArgs = new object?[] { bindingMap, "A.nl", 99, new[] { 1, 2, 3 }, null };
        Assert.True((bool)(tryResolveBindingDeclaration.Invoke(null, bindingMissArgs) ?? false));
        Assert.Null(bindingMissArgs[4]);

        var tryFindNearestBindingDeclarationByName = adapterType.GetMethod(
                "TryFindNearestBindingDeclarationByName",
                BindingFlags.Static | BindingFlags.NonPublic,
                binder: null,
                types: new[]
                {
                    typeof(BindingMap),
                    typeof(string),
                    typeof(string),
                    typeof(int),
                    typeof(SymbolDeclaration).MakeByRefType()
                },
                modifiers: null)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryFindNearestBindingDeclarationByName.");
        var firstLocal = new SymbolDeclaration("local", "A.nl", 2, 3, "variable");
        var earlierSameLineLocal = new SymbolDeclaration("local", "A.nl", 8, 1, "variable");
        var nearestLocal = new SymbolDeclaration("local", "A.nl", 8, 4, "variable");
        var otherFileLocal = new SymbolDeclaration("local", "B.nl", 20, 1, "variable");
        bindingMap.RecordDeclaration(firstLocal);
        bindingMap.RecordDeclaration(earlierSameLineLocal);
        bindingMap.RecordDeclaration(nearestLocal);
        bindingMap.RecordDeclaration(otherFileLocal);

        var nearestAtLineArgs = new object?[] { bindingMap, "A.nl", "local", 8, null };
        Assert.True((bool)(tryFindNearestBindingDeclarationByName.Invoke(null, nearestAtLineArgs) ?? false));
        Assert.Equal(nearestLocal, Assert.IsType<SymbolDeclaration>(nearestAtLineArgs[4]));

        var nearestBeforeLineArgs = new object?[] { bindingMap, "A.nl", "local", 7, null };
        Assert.True((bool)(tryFindNearestBindingDeclarationByName.Invoke(null, nearestBeforeLineArgs) ?? false));
        Assert.Equal(firstLocal, Assert.IsType<SymbolDeclaration>(nearestBeforeLineArgs[4]));

        var nearestMissArgs = new object?[] { bindingMap, "A.nl", "local", 1, null };
        Assert.True((bool)(tryFindNearestBindingDeclarationByName.Invoke(null, nearestMissArgs) ?? false));
        Assert.Null(nearestMissArgs[4]);

        var unknownNameArgs = new object?[] { bindingMap, "A.nl", "missing", 99, null };
        Assert.True((bool)(tryFindNearestBindingDeclarationByName.Invoke(null, unknownNameArgs) ?? false));
        Assert.Null(unknownNameArgs[4]);

        var trySummarizeDiagnosticSeverities = adapterType.GetMethod(
                "TrySummarizeDiagnosticSeverities",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TrySummarizeDiagnosticSeverities.");
        var summaryArgs = new object?[] { BuildDiagnosticSeveritySummaryDiagnostics(), null };
        Assert.True((bool)(trySummarizeDiagnosticSeverities.Invoke(null, summaryArgs) ?? false));
        var summary = Assert.IsType<DiagnosticSummary>(summaryArgs[1]);
        Assert.Equal(2, summary.Errors);
        Assert.Equal(1, summary.Warnings);
        Assert.Equal(2, summary.Info);

        var trySuppressLintShadowingDiagnostics = adapterType.GetMethod(
                "TrySuppressLintShadowingDiagnostics",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TrySuppressLintShadowingDiagnostics.");
        var shadowDiagnostics = BuildDiagnosticShadowSuppressionDiagnostics();
        var shadowedFiles = new[] { "SRC/a.nl", "src/c.nl", "src/c.nl" };
        var shadowArgs = new object?[] { shadowDiagnostics, shadowedFiles, null, 0 };
        Assert.True((bool)(trySuppressLintShadowingDiagnostics.Invoke(null, shadowArgs) ?? false));
        var shadowIndices = Assert.IsType<int[]>(shadowArgs[2]);
        var shadowCount = Assert.IsType<int>(shadowArgs[3]);
        var expectedShadowIndices = ExpectedDiagnosticShadowSuppressionIndices(shadowDiagnostics, shadowedFiles);
        Assert.Equal(expectedShadowIndices, shadowIndices.Take(shadowCount).ToArray());

        var tryFilterSymbolsByKind = adapterType.GetMethod(
                "TryFilterSymbolsByKind",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryFilterSymbolsByKind.");
        var symbols = BuildSymbolKindFilterSymbols();
        var filterArgs = new object?[] { symbols, SymbolKind.Function, null };
        Assert.True((bool)(tryFilterSymbolsByKind.Invoke(null, filterArgs) ?? false));
        var filteredSymbols = Assert.IsType<List<SymbolResult>>(filterArgs[2]);
        Assert.Equal(
            symbols.Where(symbol => symbol.Kind == SymbolKind.Function).Select(symbol => symbol.Name),
            filteredSymbols.Select(symbol => symbol.Name));
    }

    [Fact]
    public void CodeIntelligenceDogfoodAdapter_DeduplicatesStableStringsOrdinalIgnoreCase()
    {
        var adapterType = typeof(CodeIntelligenceService).Assembly.GetType(
                "NSharpLang.Compiler.CodeIntelligence.NSharpCodeIntelligenceDogfoodAdapter")
            ?? throw new InvalidOperationException("Dogfood code-intelligence adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryDeduplicateStableStrings = adapterType.GetMethod(
                "TryDeduplicateStableStringsOrdinalIgnoreCase",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryDeduplicateStableStringsOrdinalIgnoreCase.");
        var names = new[]
        {
            "System.Console",
            "system.console",
            "System.Text.Json",
            "SYSTEM.TEXT.JSON",
            "Custom.Library"
        };
        var args = new object?[] { names, null };

        Assert.True((bool)(tryDeduplicateStableStrings.Invoke(null, args) ?? false));
        Assert.Equal(
            new[] { "System.Console", "System.Text.Json", "Custom.Library" },
            Assert.IsType<string[]>(args[1]));
    }

    [Fact]
    public void CodeIntelligenceDogfoodAdapter_DeduplicatesStableTypes()
    {
        var adapterType = typeof(CodeIntelligenceService).Assembly.GetType(
                "NSharpLang.Compiler.CodeIntelligence.NSharpCodeIntelligenceDogfoodAdapter")
            ?? throw new InvalidOperationException("Dogfood code-intelligence adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryDeduplicateStableTypes = adapterType.GetMethod(
                "TryDeduplicateStableTypes",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryDeduplicateStableTypes.");
        var types = new[]
        {
            typeof(string),
            typeof(int),
            typeof(string),
            typeof(Console),
            typeof(int)
        };
        var args = new object?[] { types, null };

        Assert.True((bool)(tryDeduplicateStableTypes.Invoke(null, args) ?? false));
        Assert.Equal(
            new[] { typeof(string), typeof(int), typeof(Console) },
            Assert.IsType<Type[]>(args[1]));
    }

    [Fact]
    public void PerformanceDogfoodAdapter_ChecksStructCopyFieldReadonlyShape()
    {
        var adapterType = typeof(NSharpLang.Compiler.Performance.StructCopyAnalysis).Assembly.GetType(
                "NSharpLang.Compiler.Performance.NSharpPerformanceDogfoodAdapter")
            ?? throw new InvalidOperationException("Performance dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryAllInstanceFieldsAreInitOnly = adapterType.GetMethod(
                "TryAllInstanceFieldsAreInitOnly",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryAllInstanceFieldsAreInitOnly.");

        var readonlyFields = new[]
        {
            new NSharpLang.Compiler.Performance.StructCopyAnalysis.StructFieldDescriptor(
                typeof(double),
                IsInitOnly: false,
                IsStatic: true),
            new NSharpLang.Compiler.Performance.StructCopyAnalysis.StructFieldDescriptor(
                typeof(double),
                IsInitOnly: true,
                IsStatic: false),
            new NSharpLang.Compiler.Performance.StructCopyAnalysis.StructFieldDescriptor(
                typeof(double),
                IsInitOnly: true,
                IsStatic: false)
        };
        var readonlyArgs = new object?[] { readonlyFields, false };
        Assert.True((bool)(tryAllInstanceFieldsAreInitOnly.Invoke(null, readonlyArgs) ?? false));
        Assert.Equal(true, readonlyArgs[1]);

        var mutableFields = new[]
        {
            new NSharpLang.Compiler.Performance.StructCopyAnalysis.StructFieldDescriptor(
                typeof(double),
                IsInitOnly: true,
                IsStatic: false),
            new NSharpLang.Compiler.Performance.StructCopyAnalysis.StructFieldDescriptor(
                typeof(double),
                IsInitOnly: false,
                IsStatic: false)
        };
        var mutableArgs = new object?[] { mutableFields, true };
        Assert.True((bool)(tryAllInstanceFieldsAreInitOnly.Invoke(null, mutableArgs) ?? false));
        Assert.Equal(false, mutableArgs[1]);
    }

    [Fact]
    public void CompilerDogfoodAdapter_CompactsParserTokens()
    {
        var source = """
package CompilerDogfood.Tests

func main(): int {
    value := 1
    return value
}
""";
        var tokens = new Lexer(source, "test.nl").Tokenize();
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryCompactParserTokens = adapterType.GetMethod(
                "TryCompactParserTokens",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryCompactParserTokens.");
        var compactArgs = new object?[] { tokens, null };
        Assert.True((bool)(tryCompactParserTokens.Invoke(null, compactArgs) ?? false));
        var compactedTokens = Assert.IsType<List<Token>>(compactArgs[1]);

        var expectedTokens = tokens.Where(static token => token.Type != TokenType.Newline).ToList();
        Assert.Equal(expectedTokens.Select(static token => token.Type), compactedTokens.Select(static token => token.Type));
        Assert.Equal(expectedTokens.Select(static token => token.Value), compactedTokens.Select(static token => token.Value));
        Assert.DoesNotContain(compactedTokens, static token => token.Type == TokenType.Newline);
    }

    [Fact]
    public void CompilerDogfoodAdapter_ChecksAnonymousUnionShimEligibility()
    {
        static SimpleTypeReference Simple(string name) => new(name);
        static UnionTypeReference Union(params TypeReference[] arms) => new(arms.ToList());

        static bool IsTwoArmAnonymousUnion(TypeReference typeReference)
        {
            if (typeReference is not UnionTypeReference)
                return false;

            var count = 0;
            CountFlattenedUnionArms(typeReference, ref count);
            return count == 2;
        }

        static void CountFlattenedUnionArms(TypeReference typeReference, ref int count)
        {
            if (count > 2)
                return;

            if (typeReference is UnionTypeReference union)
            {
                foreach (var arm in union.Arms)
                {
                    CountFlattenedUnionArms(arm, ref count);
                    if (count > 2)
                        return;
                }

                return;
            }

            count++;
        }

        static Parameter Parameter(
            string name,
            TypeReference type,
            NSharpLang.Compiler.Ast.ParameterModifier modifier = NSharpLang.Compiler.Ast.ParameterModifier.None) =>
            new(name, type, DefaultValue: null, IsThis: false, modifier);

        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryDeclaresAnonymousUnionShims = adapterType.GetMethod(
                "TryDeclaresAnonymousUnionShims",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryDeclaresAnonymousUnionShims.");

        var eligibleUnion = Union(Simple("int"), Simple("string"));
        var threeArmUnion = Union(Simple("int"), Union(Simple("string"), Simple("bool")));

        var eligibleParameters = new[]
        {
            Parameter("prefix", Simple("int")),
            Parameter("value", eligibleUnion),
            Parameter("suffix", Simple("string"))
        };
        var eligibleArgs = new object?[]
        {
            eligibleParameters,
            (Func<TypeReference, bool>)IsTwoArmAnonymousUnion,
            false
        };
        Assert.True((bool)(tryDeclaresAnonymousUnionShims.Invoke(null, eligibleArgs) ?? false));
        Assert.Equal(true, eligibleArgs[2]);

        var disallowedParameters = new[]
        {
            Parameter("value", eligibleUnion),
            Parameter("output", eligibleUnion, NSharpLang.Compiler.Ast.ParameterModifier.Out)
        };
        var disallowedArgs = new object?[]
        {
            disallowedParameters,
            (Func<TypeReference, bool>)IsTwoArmAnonymousUnion,
            true
        };
        Assert.True((bool)(tryDeclaresAnonymousUnionShims.Invoke(null, disallowedArgs) ?? false));
        Assert.Equal(false, disallowedArgs[2]);

        var noShimParameters = new[]
        {
            Parameter("value", Simple("int")),
            Parameter("wide", threeArmUnion)
        };
        var noShimArgs = new object?[]
        {
            noShimParameters,
            (Func<TypeReference, bool>)IsTwoArmAnonymousUnion,
            true
        };
        Assert.True((bool)(tryDeclaresAnonymousUnionShims.Invoke(null, noShimArgs) ?? false));
        Assert.Equal(false, noShimArgs[2]);
    }

    [Fact]
    public void CompilerDogfoodAdapter_DeduplicatesFirstTypeKeys()
    {
        var types = new[]
        {
            typeof(IList<string>),
            typeof(IEnumerable<string>),
            typeof(IList<string>),
            typeof(IDictionary<string, int>),
            typeof(IEnumerable<string>),
            typeof(IDictionary<string, int>)
        };
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryDeduplicateFirstTypeKeys = adapterType.GetMethod(
                "TryDeduplicateFirstTypeKeys",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryDeduplicateFirstTypeKeys.");
        var args = new object?[]
        {
            types,
            (Func<Type, string>)(type => type.FullName ?? type.Name),
            null
        };
        Assert.True((bool)(tryDeduplicateFirstTypeKeys.Invoke(null, args) ?? false));
        var deduplicatedTypes = Assert.IsType<List<Type>>(args[2]);

        Assert.Equal(new[]
        {
            typeof(IList<string>),
            typeof(IEnumerable<string>),
            typeof(IDictionary<string, int>)
        }, deduplicatedTypes);
    }

    [Fact]
    public void CompilerDogfoodAdapter_DeduplicatesFirstStringsOrdinalIgnoreCase()
    {
        var paths = new[]
        {
            "/repo/src/App.nl",
            "/repo/src/Shared.nl",
            "/REPO/SRC/app.nl",
            "/repo/src/Feature.nl",
            "/repo/src/shared.nl"
        };
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryDeduplicateFirstStringsOrdinalIgnoreCase = adapterType.GetMethod(
                "TryDeduplicateFirstStringsOrdinalIgnoreCase",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryDeduplicateFirstStringsOrdinalIgnoreCase.");
        var args = new object?[] { paths, null };
        Assert.True((bool)(tryDeduplicateFirstStringsOrdinalIgnoreCase.Invoke(null, args) ?? false));
        var deduplicatedPaths = Assert.IsType<List<string>>(args[1]);

        Assert.Equal(new[]
        {
            "/repo/src/App.nl",
            "/repo/src/Shared.nl",
            "/repo/src/Feature.nl"
        }, deduplicatedPaths);
    }

    [Fact]
    public void CompilerDogfoodAdapter_DistinctOrdersStringsOrdinal()
    {
        var names = new[]
        {
            "Zeta",
            "Alpha",
            "Zeta",
            "Beta",
            "alpha"
        };
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryDistinctOrderStringsOrdinal = adapterType.GetMethod(
                "TryDistinctOrderStringsOrdinal",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryDistinctOrderStringsOrdinal.");
        var args = new object?[] { names, null };
        Assert.True((bool)(tryDistinctOrderStringsOrdinal.Invoke(null, args) ?? false));
        var orderedNames = Assert.IsType<string[]>(args[1]);

        Assert.Equal(new[]
        {
            "Alpha",
            "Beta",
            "Zeta",
            "alpha"
        }, orderedNames);
    }

    [Fact]
    public void MultiFileCompiler_DeduplicatesSourceFilesOrdinalIgnoreCase()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-dogfood-source-dedup-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var sourceFile = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(sourceFile, "func main(): int { return 0 }");

            var compiler = new MultiFileCompiler(
                new[] { sourceFile, sourceFile.ToUpperInvariant(), sourceFile },
                tempDir,
                ProjectFileParser.CreateDefault());

            var source = Assert.Single(compiler.SourceFiles);
            Assert.Equal(Path.GetFullPath(sourceFile), source);
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void CompilationStubEmitter_DeduplicatesSourceFilesBeforeParsing()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-dogfood-stub-dedup-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var sourceFile = Path.Combine(tempDir, "Program.nl");
            File.WriteAllText(sourceFile, """
func helper(): int {
    return 1
}
""");

            var stub = CompilationStubEmitter.Generate(
                ProjectFileParser.CreateDefault(),
                new[] { sourceFile, sourceFile });

            Assert.Equal(1, CountOccurrences(stub, "internal static int helper("));
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void CompilationStubEmitter_UsesDogfoodNamespaceImportOrdering()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), $"nsharp-dogfood-stub-namespace-order-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDir);
        try
        {
            var zetaFile = Path.Combine(tempDir, "Zeta.nl");
            File.WriteAllText(zetaFile, """
namespace Zeta

class ZetaType {
}
""");
            var alphaFile = Path.Combine(tempDir, "Alpha.nl");
            File.WriteAllText(alphaFile, """
namespace Alpha

class AlphaType {
}
""");
            var duplicateZetaFile = Path.Combine(tempDir, "DuplicateZeta.nl");
            File.WriteAllText(duplicateZetaFile, """
namespace Zeta

class OtherZetaType {
}
""");

            var stub = CompilationStubEmitter.Generate(
                ProjectFileParser.CreateDefault(),
                new[] { zetaFile, alphaFile, duplicateZetaFile });

            Assert.Equal(1, CountOccurrences(stub, "using Alpha;"));
            Assert.Equal(1, CountOccurrences(stub, "using Zeta;"));
            Assert.True(
                stub.IndexOf("using Alpha;", StringComparison.Ordinal)
                    < stub.IndexOf("using Zeta;", StringComparison.Ordinal));
        }
        finally
        {
            Directory.Delete(tempDir, recursive: true);
        }
    }

    [Fact]
    public void CompilerDogfoodAdapter_LooksUpUniqueDeclaredTypeBySuffix()
    {
        var declaredTypes = new Dictionary<string, Type>(StringComparer.Ordinal)
        {
            ["Demo.Models.Customer"] = typeof(string),
            ["Demo.Tiny.Foo"] = typeof(decimal),
            ["Demo.Core.Shared"] = typeof(int),
            ["Demo.Other.Shared"] = typeof(long)
        };
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryLookupUniqueDeclaredTypeBySuffix = adapterType.GetMethod(
                "TryLookupUniqueDeclaredTypeBySuffix",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryLookupUniqueDeclaredTypeBySuffix.");
        var genericLookup = tryLookupUniqueDeclaredTypeBySuffix.MakeGenericMethod(typeof(Type));

        var uniqueArgs = new object?[] { declaredTypes, "Customer", null, false };
        Assert.True((bool)(genericLookup.Invoke(null, uniqueArgs) ?? false));
        Assert.Equal(true, uniqueArgs[3]);
        Assert.Same(typeof(string), uniqueArgs[2]);

        var tinyArgs = new object?[] { declaredTypes, "Foo", null, false };
        Assert.True((bool)(genericLookup.Invoke(null, tinyArgs) ?? false));
        Assert.Equal(true, tinyArgs[3]);
        Assert.Same(typeof(decimal), tinyArgs[2]);

        var exactArgs = new object?[] { declaredTypes, "Demo.Core.Shared", null, false };
        Assert.True((bool)(genericLookup.Invoke(null, exactArgs) ?? false));
        Assert.Equal(true, exactArgs[3]);
        Assert.Same(typeof(int), exactArgs[2]);

        var missingArgs = new object?[] { declaredTypes, "Missing", null, false };
        Assert.True((bool)(genericLookup.Invoke(null, missingArgs) ?? false));
        Assert.Equal(false, missingArgs[3]);
        Assert.Null(missingArgs[2]);

        var ambiguousArgs = new object?[] { declaredTypes, "Shared", null, false };
        Assert.True((bool)(genericLookup.Invoke(null, ambiguousArgs) ?? false));
        Assert.Equal(false, ambiguousArgs[3]);
        Assert.Null(ambiguousArgs[2]);
    }

    [Fact]
    public void CompilerDogfoodAdapter_SelectsDeclaredTypeNameCandidate()
    {
        static ClassDeclaration TypeDeclaration(string name) => new(
            name,
            TypeParameters: null,
            BaseClass: null,
            Interfaces: new List<TypeReference>(),
            Members: new List<Declaration>(),
            PrimaryConstructorParameters: null,
            Modifiers: Modifiers.Public,
            Attributes: new List<AttributeNode>(),
            Line: 1,
            Column: 1);

        var compilationUnit = new CompilationUnit(
            Namespace: null,
            Imports: new List<ImportDirective>
            {
                new("Demo.Imported", Alias: null, Line: 1, Column: 1)
            },
            FileImports: new List<Statement>(),
            Package: null,
            Declarations: new List<Declaration>
            {
                TypeDeclaration("Demo.Imported.Customer"),
                TypeDeclaration("Demo.Other.Customer"),
                TypeDeclaration("Demo.Local.Invoice"),
                TypeDeclaration("Demo.Tiny.Foo"),
                TypeDeclaration("Demo.Alpha.Shared"),
                TypeDeclaration("Demo.Beta.Shared")
            },
            Line: 1,
            Column: 1);
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var trySelectDeclaredTypeNameCandidate = adapterType.GetMethod(
                "TrySelectDeclaredTypeNameCandidate",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TrySelectDeclaredTypeNameCandidate.");

        var importedSuffixArgs = new object?[] { compilationUnit, "Customer", null };
        Assert.True((bool)(trySelectDeclaredTypeNameCandidate.Invoke(null, importedSuffixArgs) ?? false));
        Assert.Equal("Demo.Imported.Customer", importedSuffixArgs[2]);

        var uniqueSuffixArgs = new object?[] { compilationUnit, "Invoice", null };
        Assert.True((bool)(trySelectDeclaredTypeNameCandidate.Invoke(null, uniqueSuffixArgs) ?? false));
        Assert.Equal("Demo.Local.Invoice", uniqueSuffixArgs[2]);

        var tinySuffixArgs = new object?[] { compilationUnit, "Foo", null };
        Assert.True((bool)(trySelectDeclaredTypeNameCandidate.Invoke(null, tinySuffixArgs) ?? false));
        Assert.Equal("Demo.Tiny.Foo", tinySuffixArgs[2]);

        var exactArgs = new object?[] { compilationUnit, "Demo.Local.Invoice", null };
        Assert.True((bool)(trySelectDeclaredTypeNameCandidate.Invoke(null, exactArgs) ?? false));
        Assert.Equal("Demo.Local.Invoice", exactArgs[2]);

        var ambiguousArgs = new object?[] { compilationUnit, "Shared", null };
        Assert.True((bool)(trySelectDeclaredTypeNameCandidate.Invoke(null, ambiguousArgs) ?? false));
        Assert.Null(ambiguousArgs[2]);

        var missingArgs = new object?[] { compilationUnit, "Missing", null };
        Assert.True((bool)(trySelectDeclaredTypeNameCandidate.Invoke(null, missingArgs) ?? false));
        Assert.Null(missingArgs[2]);
    }

    [Fact]
    public void CompilerDogfoodAdapter_OrdersTypesByDescendingKeyDotCount()
    {
        var types = new[]
        {
            typeof(string),
            typeof(int),
            typeof(decimal),
            typeof(DateTime),
            typeof(Guid)
        };
        var keys = new Dictionary<Type, string>
        {
            [typeof(string)] = "Root",
            [typeof(int)] = "Root.Nested",
            [typeof(decimal)] = "Root.Nested.Deep",
            [typeof(DateTime)] = "Other.Deep",
            [typeof(Guid)] = "Root.Nested.Deep.More"
        };
        var adapterType = typeof(Parser).Assembly.GetType("NSharpLang.Compiler.NSharpCompilerDogfoodAdapter")
            ?? throw new InvalidOperationException("Compiler dogfood adapter type was not emitted.");

        var isAvailable = (bool)(adapterType.GetProperty(
                "IsAvailable",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?.GetValue(null) ?? false);
        Assert.True(isAvailable, "The production test output must carry NSharpLang.Compiler.Dogfood.dll.");

        var tryOrderTypesByDescendingKeyDotCount = adapterType.GetMethod(
                "TryOrderTypesByDescendingKeyDotCount",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("Dogfood adapter did not emit TryOrderTypesByDescendingKeyDotCount.");
        var genericOrder = tryOrderTypesByDescendingKeyDotCount.MakeGenericMethod(typeof(Type));
        var args = new object?[]
        {
            types,
            (Func<Type, string>)(type => keys[type]),
            null
        };

        Assert.True((bool)(genericOrder.Invoke(null, args) ?? false));
        var orderedTypes = Assert.IsType<List<Type>>(args[2]);
        Assert.Equal(new[]
        {
            typeof(Guid),
            typeof(decimal),
            typeof(int),
            typeof(DateTime),
            typeof(string)
        }, orderedTypes);
    }

    [Fact]
    public void LexerTokenKindScanner_ProjectCompilesAndMatchesProductionLexer()
    {
        var repoRoot = FindRepoRoot();
        var projectRoot = Path.Combine(repoRoot, "src", "NSharpLang.Compiler.Dogfood");
        var config = ProjectFileParser.Parse(Path.Combine(projectRoot, "project.yml"));
        var outputPath = Path.Combine(
            Path.GetTempPath(),
            $"NSharpLang.Compiler.Dogfood.Tests.{Guid.NewGuid():N}.dll");

        try
        {
            var compiler = new MultiFileCompiler(projectRoot, config);
            var result = compiler.CompileToIlAssembly("NSharpLang.Compiler.Dogfood", outputPath);

            Assert.True(result.Success, string.Join(Environment.NewLine, result.Errors.Select(error => error.Message)));
            Assert.True(File.Exists(outputPath));

            var assembly = Assembly.Load(File.ReadAllBytes(outputPath));
            var programType = assembly.GetType("Program")
                ?? throw new InvalidOperationException("Dogfood assembly did not emit Program.");
            var tokenizeCount = programType.GetMethod(
                    "TokenizeCount",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TokenizeCount.");
            var tokenizeKinds = programType.GetMethod(
                    "TokenizeKinds",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TokenizeKinds.");
            var tokenizeKindsInto = programType.GetMethod(
                    "TokenizeKindsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TokenizeKindsInto.");
            var tokenizeMetadataInto = programType.GetMethod(
                    "TokenizeMetadataInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TokenizeMetadataInto.");
            var parserTokenCompactionIndicesInto = programType.GetMethod(
                    "ParserTokenCompactionIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit ParserTokenCompactionIndicesInto.");
            var parserTokenCompactionChecksumInto = programType.GetMethod(
                    "ParserTokenCompactionChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit ParserTokenCompactionChecksumInto.");
            var splitLogicalLines = programType.GetMethod(
                    "SplitLogicalLines",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SplitLogicalLines.");
            var splitLogicalLineRangesInto = programType.GetMethod(
                    "SplitLogicalLineRangesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SplitLogicalLineRangesInto.");
            var buildLogicalLineStartsInto = programType.GetMethod(
                    "BuildLogicalLineStartsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BuildLogicalLineStartsInto.");
            var getLineIndexFromOffset = programType.GetMethod(
                    "GetLineIndexFromOffset",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit GetLineIndexFromOffset.");
            var getColumnFromOffset = programType.GetMethod(
                    "GetColumnFromOffset",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit GetColumnFromOffset.");
            var getOffsetFromLineColumn = programType.GetMethod(
                    "GetOffsetFromLineColumn",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit GetOffsetFromLineColumn.");
            var lineMapCachedChecksumInto = programType.GetMethod(
                    "LineMapCachedChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit LineMapCachedChecksumInto.");
            var lineMapCachedQueryChecksumInto = programType.GetMethod(
                    "LineMapCachedQueryChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit LineMapCachedQueryChecksumInto.");
            var lineMapTrustedCachedQueryChecksumInto = programType.GetMethod(
                    "LineMapTrustedCachedQueryChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit LineMapTrustedCachedQueryChecksumInto.");
            var codeIntelligenceIdentifierSpanChecksumInto = programType.GetMethod(
                    "CodeIntelligenceIdentifierSpanChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceIdentifierSpanChecksumInto.");
            var codeIntelligenceIdentifierSpansInto = programType.GetMethod(
                    "CodeIntelligenceIdentifierSpansInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceIdentifierSpansInto.");
            var buildCodeIntelligenceLineRangesInto = programType.GetMethod(
                    "BuildCodeIntelligenceLineRangesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BuildCodeIntelligenceLineRangesInto.");
            var codeIntelligenceEditorIdentifierSpanChecksumInto = programType.GetMethod(
                    "CodeIntelligenceEditorIdentifierSpanChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceEditorIdentifierSpanChecksumInto.");
            var codeIntelligenceEditorIdentifierSpansInto = programType.GetMethod(
                    "CodeIntelligenceEditorIdentifierSpansInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceEditorIdentifierSpansInto.");
            var codeIntelligenceDeclarationNameMatchChecksumInto = programType.GetMethod(
                    "CodeIntelligenceDeclarationNameMatchChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceDeclarationNameMatchChecksumInto.");
            var codeIntelligenceDeclarationNameMatchesFromLinesInto = programType.GetMethod(
                    "CodeIntelligenceDeclarationNameMatchesFromLinesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceDeclarationNameMatchesFromLinesInto.");
            var codeIntelligenceIdentifierNameColumnChecksumInto = programType.GetMethod(
                    "CodeIntelligenceIdentifierNameColumnChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceIdentifierNameColumnChecksumInto.");
            var codeIntelligenceIdentifierNameColumnsInto = programType.GetMethod(
                    "CodeIntelligenceIdentifierNameColumnsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceIdentifierNameColumnsInto.");
            var codeIntelligenceIdentifierNameColumnsFromLinesInto = programType.GetMethod(
                    "CodeIntelligenceIdentifierNameColumnsFromLinesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceIdentifierNameColumnsFromLinesInto.");
            var codeIntelligenceMemberReceiverChecksumInto = programType.GetMethod(
                    "CodeIntelligenceMemberReceiverChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceMemberReceiverChecksumInto.");
            var codeIntelligenceMemberReceiversInto = programType.GetMethod(
                    "CodeIntelligenceMemberReceiversInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceMemberReceiversInto.");
            var codeIntelligenceMemberReceiverCachedChecksumInto = programType.GetMethod(
                    "CodeIntelligenceMemberReceiverCachedChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceMemberReceiverCachedChecksumInto.");
            var codeIntelligenceMemberReceiversCachedInto = programType.GetMethod(
                    "CodeIntelligenceMemberReceiversCachedInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceMemberReceiversCachedInto.");
            var codeIntelligenceSourceContextChecksumInto = programType.GetMethod(
                    "CodeIntelligenceSourceContextChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceSourceContextChecksumInto.");
            var codeIntelligenceSourceContextsInto = programType.GetMethod(
                    "CodeIntelligenceSourceContextsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceSourceContextsInto.");
            var codeIntelligenceSourceLineChecksumInto = programType.GetMethod(
                    "CodeIntelligenceSourceLineChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceSourceLineChecksumInto.");
            var codeIntelligenceSourceLinesInto = programType.GetMethod(
                    "CodeIntelligenceSourceLinesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceSourceLinesInto.");
            var codeIntelligenceSourceLinesFromLinesInto = programType.GetMethod(
                    "CodeIntelligenceSourceLinesFromLinesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceSourceLinesFromLinesInto.");
            var codeIntelligencePathMatches = programType.GetMethod(
                    "CodeIntelligencePathMatches",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligencePathMatches.");
            var codeIntelligencePathMatchChecksumInto = programType.GetMethod(
                    "CodeIntelligencePathMatchChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligencePathMatchChecksumInto.");
            var codeIntelligenceCompletionPrefixChecksumInto = programType.GetMethod(
                    "CodeIntelligenceCompletionPrefixChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceCompletionPrefixChecksumInto.");
            var codeIntelligenceCompletionPrefixesInto = programType.GetMethod(
                    "CodeIntelligenceCompletionPrefixesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceCompletionPrefixesInto.");
            var codeIntelligenceCompletionPrefixesFromLinesInto = programType.GetMethod(
                    "CodeIntelligenceCompletionPrefixesFromLinesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceCompletionPrefixesFromLinesInto.");
            var codeIntelligenceCompletionReceiverChecksumInto = programType.GetMethod(
                    "CodeIntelligenceCompletionReceiverChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceCompletionReceiverChecksumInto.");
            var codeIntelligenceCompletionReceiversInto = programType.GetMethod(
                    "CodeIntelligenceCompletionReceiversInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceCompletionReceiversInto.");
            var completionItemKindGroupsInto = programType.GetMethod(
                    "CompletionItemKindGroupsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CompletionItemKindGroupsInto.");
            var completionItemKindGroupChecksumInto = programType.GetMethod(
                    "CompletionItemKindGroupChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CompletionItemKindGroupChecksumInto.");
            var completionMethodOverloadGroupsInto = programType.GetMethod(
                    "CompletionMethodOverloadGroupsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CompletionMethodOverloadGroupsInto.");
            var completionMethodOverloadGroupChecksumInto = programType.GetMethod(
                    "CompletionMethodOverloadGroupChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CompletionMethodOverloadGroupChecksumInto.");
            var cliTryParsePositionInto = programType.GetMethod(
                    "CliTryParsePositionInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliTryParsePositionInto.");
            var cliQueryPositionsInto = programType.GetMethod(
                    "CliQueryPositionsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliQueryPositionsInto.");
            var cliQueryPositionChecksumInto = programType.GetMethod(
                    "CliQueryPositionChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliQueryPositionChecksumInto.");
            var cliPositionalArgIndicesInto = programType.GetMethod(
                    "CliPositionalArgIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliPositionalArgIndicesInto.");
            var cliBuildOperandIndicesInto = programType.GetMethod(
                    "CliBuildOperandIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliBuildOperandIndicesInto.");
            var cliBuildOperandSummaryInto = programType.GetMethod(
                    "CliBuildOperandSummaryInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliBuildOperandSummaryInto.");
            var cliBuildFirstOperandIndexInto = programType.GetMethod(
                    "CliBuildFirstOperandIndexInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliBuildFirstOperandIndexInto.");
            var cliExportCSharpFirstOperandIndexInto = programType.GetMethod(
                    "CliExportCSharpFirstOperandIndexInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliExportCSharpFirstOperandIndexInto.");
            var cliExportCSharpFirstOperandChecksumInto = programType.GetMethod(
                    "CliExportCSharpFirstOperandChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliExportCSharpFirstOperandChecksumInto.");
            var cliFirstPositionalArgIndex = programType.GetMethod(
                    "CliFirstPositionalArgIndex",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFirstPositionalArgIndex.");
            var cliPositionalArgChecksumInto = programType.GetMethod(
                    "CliPositionalArgChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliPositionalArgChecksumInto.");
            var cliFixSafetyFilterIndicesInto = programType.GetMethod(
                    "CliFixSafetyFilterIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFixSafetyFilterIndicesInto.");
            var cliFixSafetyFilterChecksumInto = programType.GetMethod(
                    "CliFixSafetyFilterChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFixSafetyFilterChecksumInto.");
            var cliFixEditFlattenIndicesInto = programType.GetMethod(
                    "CliFixEditFlattenIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFixEditFlattenIndicesInto.");
            var cliFixEditFlattenChecksumInto = programType.GetMethod(
                    "CliFixEditFlattenChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFixEditFlattenChecksumInto.");
            var cliFixSkippedIndicesInto = programType.GetMethod(
                    "CliFixSkippedIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFixSkippedIndicesInto.");
            var cliFixSkippedChecksumInto = programType.GetMethod(
                    "CliFixSkippedChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFixSkippedChecksumInto.");
            var cliFixAppliedFileGroupsInto = programType.GetMethod(
                    "CliFixAppliedFileGroupsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFixAppliedFileGroupsInto.");
            var cliFixAppliedFileGroupChecksumInto = programType.GetMethod(
                    "CliFixAppliedFileGroupChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliFixAppliedFileGroupChecksumInto.");
            var cliUnifiedDiffHunkRangesInto = programType.GetMethod(
                    "CliUnifiedDiffHunkRangesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliUnifiedDiffHunkRangesInto.");
            var cliUnifiedDiffHunkRangeChecksumInto = programType.GetMethod(
                    "CliUnifiedDiffHunkRangeChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliUnifiedDiffHunkRangeChecksumInto.");
            var cliCleanArtifactDirectoryIndicesInto = programType.GetMethod(
                    "CliCleanArtifactDirectoryIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliCleanArtifactDirectoryIndicesInto.");
            var cliCleanArtifactDirectoryChecksumInto = programType.GetMethod(
                    "CliCleanArtifactDirectoryChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliCleanArtifactDirectoryChecksumInto.");
            var cliUpdateAllNuGetDependencyIndicesInto = programType.GetMethod(
                    "CliUpdateAllNuGetDependencyIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliUpdateAllNuGetDependencyIndicesInto.");
            var cliUpdateAllNuGetDependencyChecksumInto = programType.GetMethod(
                    "CliUpdateAllNuGetDependencyChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliUpdateAllNuGetDependencyChecksumInto.");
            var cliUpdateTargetNuGetDependencyIndicesInto = programType.GetMethod(
                    "CliUpdateTargetNuGetDependencyIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliUpdateTargetNuGetDependencyIndicesInto.");
            var cliUpdateTargetNuGetDependencyChecksumInto = programType.GetMethod(
                    "CliUpdateTargetNuGetDependencyChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliUpdateTargetNuGetDependencyChecksumInto.");
            var cliReferenceTypeFilterIndicesInto = programType.GetMethod(
                    "CliReferenceTypeFilterIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliReferenceTypeFilterIndicesInto.");
            var cliReferenceTypeFilterChecksumInto = programType.GetMethod(
                    "CliReferenceTypeFilterChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliReferenceTypeFilterChecksumInto.");
            var cliDocSymbolOrderCountingIndicesInto = programType.GetMethod(
                    "CliDocSymbolOrderCountingIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliDocSymbolOrderCountingIndicesInto.");
            var cliDocSymbolOrderCountingChecksumInto = programType.GetMethod(
                    "CliDocSymbolOrderCountingChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliDocSymbolOrderCountingChecksumInto.");
            var cliDocSlugsInto = programType.GetMethod(
                    "CliDocSlugsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliDocSlugsInto.");
            var cliSymbolNameGlobFilterIndicesInto = programType.GetMethod(
                    "CliSymbolNameGlobFilterIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliSymbolNameGlobFilterIndicesInto.");
            var symbolKindFilterIndicesInto = programType.GetMethod(
                    "SymbolKindFilterIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SymbolKindFilterIndicesInto.");
            var symbolKindFilterChecksumInto = programType.GetMethod(
                    "SymbolKindFilterChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SymbolKindFilterChecksumInto.");
            var docQueryBestTypeIndex = programType.GetMethod(
                    "DocQueryBestTypeIndex",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DocQueryBestTypeIndex.");
            var docQueryBestTypeChecksumInto = programType.GetMethod(
                    "DocQueryBestTypeChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DocQueryBestTypeChecksumInto.");
            var docQueryMemberOrderIndicesInto = programType.GetMethod(
                    "DocQueryMemberOrderIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DocQueryMemberOrderIndicesInto.");
            var docQueryMemberOrderChecksumInto = programType.GetMethod(
                    "DocQueryMemberOrderChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DocQueryMemberOrderChecksumInto.");
            var typoSuggestionIndicesInto = programType.GetMethod(
                    "TypoSuggestionIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TypoSuggestionIndicesInto.");
            var typoSuggestionChecksumInto = programType.GetMethod(
                    "TypoSuggestionChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TypoSuggestionChecksumInto.");
            var aotRequirementGroupsInto = programType.GetMethod(
                    "AotRequirementGroupsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit AotRequirementGroupsInto.");
            var aotRequirementGroupChecksumInto = programType.GetMethod(
                    "AotRequirementGroupChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit AotRequirementGroupChecksumInto.");
            var cliBatchDuplicateIdRanksInto = programType.GetMethod(
                    "CliBatchDuplicateIdRanksInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliBatchDuplicateIdRanksInto.");
            var cliBatchDuplicateIdRankChecksumInto = programType.GetMethod(
                    "CliBatchDuplicateIdRankChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliBatchDuplicateIdRankChecksumInto.");
            var cliTreeDependencyDeduplicateIndicesInto = programType.GetMethod(
                    "CliTreeDependencyDeduplicateIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliTreeDependencyDeduplicateIndicesInto.");
            var cliTreeDependencyDeduplicateChecksumInto = programType.GetMethod(
                    "CliTreeDependencyDeduplicateChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CliTreeDependencyDeduplicateChecksumInto.");
            var textEditOrderIndicesInto = programType.GetMethod(
                    "TextEditOrderIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TextEditOrderIndicesInto.");
            var textEditOrderChecksumInto = programType.GetMethod(
                    "TextEditOrderChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TextEditOrderChecksumInto.");
            var codeIntelligenceDocCommentChecksumInto = programType.GetMethod(
                    "CodeIntelligenceDocCommentChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceDocCommentChecksumInto.");
            var codeIntelligenceDocCommentLinesInto = programType.GetMethod(
                    "CodeIntelligenceDocCommentLinesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceDocCommentLinesInto.");
            var codeIntelligenceDocCommentLinesFromLinesInto = programType.GetMethod(
                    "CodeIntelligenceDocCommentLinesFromLinesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceDocCommentLinesFromLinesInto.");
            var codeIntelligenceVariableDeclarationNameChecksumInto = programType.GetMethod(
                    "CodeIntelligenceVariableDeclarationNameChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceVariableDeclarationNameChecksumInto.");
            var codeIntelligenceVariableDeclarationNamesInto = programType.GetMethod(
                    "CodeIntelligenceVariableDeclarationNamesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceVariableDeclarationNamesInto.");
            var buildCodeIntelligenceVariableDeclarationNameCacheInto = programType.GetMethod(
                    "BuildCodeIntelligenceVariableDeclarationNameCacheInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BuildCodeIntelligenceVariableDeclarationNameCacheInto.");
            var codeIntelligenceVariableDeclarationNamesFromCacheInto = programType.GetMethod(
                    "CodeIntelligenceVariableDeclarationNamesFromCacheInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit CodeIntelligenceVariableDeclarationNamesFromCacheInto.");
            var diagnosticSeveritySummaryInto = programType.GetMethod(
                    "DiagnosticSeveritySummaryInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticSeveritySummaryInto.");
            var diagnosticSeveritySummaryChecksumInto = programType.GetMethod(
                    "DiagnosticSeveritySummaryChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticSeveritySummaryChecksumInto.");
            var diagnosticSeverityFilterIndicesInto = programType.GetMethod(
                    "DiagnosticSeverityFilterIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticSeverityFilterIndicesInto.");
            var diagnosticSeverityFilterChecksumInto = programType.GetMethod(
                    "DiagnosticSeverityFilterChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticSeverityFilterChecksumInto.");
            var diagnosticShadowSuppressionIndicesInto = programType.GetMethod(
                    "DiagnosticShadowSuppressionIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticShadowSuppressionIndicesInto.");
            var diagnosticShadowSuppressionChecksumInto = programType.GetMethod(
                    "DiagnosticShadowSuppressionChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticShadowSuppressionChecksumInto.");
            var diagnosticClusterTraitsInto = programType.GetMethod(
                    "DiagnosticClusterTraitsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterTraitsInto.");
            var diagnosticClusterTraitChecksumInto = programType.GetMethod(
                    "DiagnosticClusterTraitChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterTraitChecksumInto.");
            var diagnosticClusterTraitPatternChecksumInto = programType.GetMethod(
                    "DiagnosticClusterTraitPatternChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterTraitPatternChecksumInto.");
            var diagnosticClusterTraitsAndPatternsInto = programType.GetMethod(
                    "DiagnosticClusterTraitsAndPatternsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterTraitsAndPatternsInto.");
            var diagnosticClusterIdsInto = programType.GetMethod(
                    "DiagnosticClusterIdsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterIdsInto.");
            var diagnosticClusterIdChecksumInto = programType.GetMethod(
                    "DiagnosticClusterIdChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterIdChecksumInto.");
            var diagnosticClusterNextCommandsInto = programType.GetMethod(
                    "DiagnosticClusterNextCommandsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterNextCommandsInto.");
            var diagnosticClusterNextCommandChecksumInto = programType.GetMethod(
                    "DiagnosticClusterNextCommandChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterNextCommandChecksumInto.");
            var diagnosticClusterCompactGroupsInto = programType.GetMethod(
                    "DiagnosticClusterCompactGroupsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterCompactGroupsInto.");
            var diagnosticClusterCompactGroupChecksumInto = programType.GetMethod(
                    "DiagnosticClusterCompactGroupChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterCompactGroupChecksumInto.");
            var diagnosticClusterCompactGroupMembersInto = programType.GetMethod(
                    "DiagnosticClusterCompactGroupMembersInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterCompactGroupMembersInto.");
            var diagnosticClusterCompactGroupMemberChecksumInto = programType.GetMethod(
                    "DiagnosticClusterCompactGroupMemberChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticClusterCompactGroupMemberChecksumInto.");
            var diagnosticDeduplicateCompactInto = programType.GetMethod(
                    "DiagnosticDeduplicateCompactInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticDeduplicateCompactInto.");
            var diagnosticDeduplicateCompactChecksumInto = programType.GetMethod(
                    "DiagnosticDeduplicateCompactChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticDeduplicateCompactChecksumInto.");
            var diagnosticDeduplicateStableInto = programType.GetMethod(
                    "DiagnosticDeduplicateStableInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticDeduplicateStableInto.");
            var diagnosticDeduplicateStableChecksumInto = programType.GetMethod(
                    "DiagnosticDeduplicateStableChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DiagnosticDeduplicateStableChecksumInto.");
            var referenceDeduplicateCompactInto = programType.GetMethod(
                    "ReferenceDeduplicateCompactInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit ReferenceDeduplicateCompactInto.");
            var referenceDeduplicateCompactChecksumInto = programType.GetMethod(
                    "ReferenceDeduplicateCompactChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit ReferenceDeduplicateCompactChecksumInto.");
            var referenceFileSummaryRanksInto = programType.GetMethod(
                    "ReferenceFileSummaryRanksInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit ReferenceFileSummaryRanksInto.");
            var referenceFileSummaryChecksumInto = programType.GetMethod(
                    "ReferenceFileSummaryChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit ReferenceFileSummaryChecksumInto.");
            var bindingLookupCandidateColumnsInto = programType.GetMethod(
                    "BindingLookupCandidateColumnsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BindingLookupCandidateColumnsInto.");
            var bindingLookupCandidateColumnChecksumInto = programType.GetMethod(
                    "BindingLookupCandidateColumnChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BindingLookupCandidateColumnChecksumInto.");
            var bindingLookupBuildSlotsInto = programType.GetMethod(
                    "BindingLookupBuildSlotsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BindingLookupBuildSlotsInto.");
            var bindingLookupQueryDeclarationIndicesInto = programType.GetMethod(
                    "BindingLookupQueryDeclarationIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BindingLookupQueryDeclarationIndicesInto.");
            var bindingLookupQueryChecksumInto = programType.GetMethod(
                    "BindingLookupQueryChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BindingLookupQueryChecksumInto.");
            var bindingLookupBuildNearestDeclarationIndexInto = programType.GetMethod(
                    "BindingLookupBuildNearestDeclarationIndexInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BindingLookupBuildNearestDeclarationIndexInto.");
            var bindingLookupBuildNearestDeclarationIndexChecksumInto = programType.GetMethod(
                    "BindingLookupBuildNearestDeclarationIndexChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BindingLookupBuildNearestDeclarationIndexChecksumInto.");
            var bindingLookupFindNearestDeclarationIndicesInto = programType.GetMethod(
                    "BindingLookupFindNearestDeclarationIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BindingLookupFindNearestDeclarationIndicesInto.");
            var bindingLookupFindNearestDeclarationChecksumInto = programType.GetMethod(
                    "BindingLookupFindNearestDeclarationChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit BindingLookupFindNearestDeclarationChecksumInto.");
            var semanticScopeVisibleSymbolIndicesInto = programType.GetMethod(
                    "SemanticScopeVisibleSymbolIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SemanticScopeVisibleSymbolIndicesInto.");
            var semanticScopeVisibleSymbolChecksumInto = programType.GetMethod(
                    "SemanticScopeVisibleSymbolChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SemanticScopeVisibleSymbolChecksumInto.");
            var semanticScopeBuildSortedIndexInto = programType.GetMethod(
                    "SemanticScopeBuildSortedIndexInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SemanticScopeBuildSortedIndexInto.");
            var semanticScopeBuildSortedIndexChecksumInto = programType.GetMethod(
                    "SemanticScopeBuildSortedIndexChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SemanticScopeBuildSortedIndexChecksumInto.");
            var semanticScopeBuildDepthsInto = programType.GetMethod(
                    "SemanticScopeBuildDepthsInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SemanticScopeBuildDepthsInto.");
            var semanticScopeBuildDepthChecksumInto = programType.GetMethod(
                    "SemanticScopeBuildDepthChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SemanticScopeBuildDepthChecksumInto.");
            var semanticScopeLookupSymbolIndicesInto = programType.GetMethod(
                    "SemanticScopeLookupSymbolIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SemanticScopeLookupSymbolIndicesInto.");
            var semanticScopeLookupSymbolChecksumInto = programType.GetMethod(
                    "SemanticScopeLookupSymbolChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SemanticScopeLookupSymbolChecksumInto.");
            var declaredTypeUniqueSuffixValueRank = programType.GetMethod(
                    "DeclaredTypeUniqueSuffixValueRank",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DeclaredTypeUniqueSuffixValueRank.");
            var declaredTypeUniqueSuffixValueRankChecksum = programType.GetMethod(
                    "DeclaredTypeUniqueSuffixValueRankChecksum",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DeclaredTypeUniqueSuffixValueRankChecksum.");
            var declaredTypeNameCandidateIndex = programType.GetMethod(
                    "DeclaredTypeNameCandidateIndex",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DeclaredTypeNameCandidateIndex.");
            var declaredTypeNameCandidateChecksum = programType.GetMethod(
                    "DeclaredTypeNameCandidateChecksum",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit DeclaredTypeNameCandidateChecksum.");
            var typeCreationOrderIndicesInto = programType.GetMethod(
                    "TypeCreationOrderIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TypeCreationOrderIndicesInto.");
            var typeCreationOrderChecksumInto = programType.GetMethod(
                    "TypeCreationOrderChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit TypeCreationOrderChecksumInto.");

            const string source = """"
import System
package CompilerDogfood.Tests

func score(value: int): int {
    if value == 0 {
        return 1
    }

    text := $"score:{value}"
    raw := """
hello
world
"""
    return text.Length + raw.Length + value
}
"""";
            AssertTokenizesLikeProductionLexer(source, tokenizeCount, tokenizeKinds, tokenizeKindsInto);
            AssertTokenMetadataLikeProductionLexer(source, tokenizeMetadataInto);
            AssertParserTokenCompactionLikeProduction(
                source,
                parserTokenCompactionIndicesInto,
                parserTokenCompactionChecksumInto);

            const string keywordSource = """
func class struct interface duck union record enum namespace using import package let must const readonly
if else for foreach while in return yield match switch case default break continue throw try catch finally
new this base true false null is as typeof nameof sizeof print where when and or not
virtual override abstract sealed partial static public private internal protected async await immutable
with type assert operator required init ref out lock file params checked unchecked implicit explicit newtype
throws
""";
            AssertTokenizesLikeProductionLexer(keywordSource, tokenizeCount, tokenizeKinds, tokenizeKindsInto);
            AssertTokenMetadataLikeProductionLexer(keywordSource, tokenizeMetadataInto);
            AssertParserTokenCompactionLikeProduction(
                keywordSource,
                parserTokenCompactionIndicesInto,
                parserTokenCompactionChecksumInto);

            const string metadataSource = """
package CompilerDogfood.Metadata

func values(): int {
    decimal := 1_234
    hex := 0xCA_FE
    binary := 0b1010_0101
    floating := 1.5_0e+2
    /* block
       comment */
    return decimal + hex + binary + floating
}
""";
            AssertTokenMetadataLikeProductionLexer(metadataSource, tokenizeMetadataInto);
            AssertParserTokenCompactionLikeProduction(
                metadataSource,
                parserTokenCompactionIndicesInto,
                parserTokenCompactionChecksumInto);

            AssertSourceTextLineMapLikeProduction(
                "",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);
            AssertSourceTextLineMapLikeProduction(
                "one",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);
            AssertSourceTextLineMapLikeProduction(
                "one\n",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);
            AssertSourceTextLineMapLikeProduction(
                "one\r\n",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);
            AssertSourceTextLineMapLikeProduction(
                "one\rtwo",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);
            AssertSourceTextLineMapLikeProduction(
                "one\r\ntwo\rthree\n",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);
            AssertSourceTextLineMapLikeProduction(
                "\r\n\r\n\n\r",
                splitLogicalLines,
                splitLogicalLineRangesInto,
                buildLogicalLineStartsInto,
                getLineIndexFromOffset,
                getColumnFromOffset,
                getOffsetFromLineColumn,
                lineMapCachedChecksumInto,
                lineMapCachedQueryChecksumInto,
                lineMapTrustedCachedQueryChecksumInto);

            AssertIdentifierSpansLikeProduction(
                """
func main() {
    value := input.Count
    print value
}
""",
                codeIntelligenceIdentifierSpanChecksumInto,
                codeIntelligenceIdentifierSpansInto);
            AssertIdentifierSpansLikeProduction(
                "package CompilerDogfood.Tests\r\nfunc main(): int {\r\n    return value\r\n}\r\n",
                codeIntelligenceIdentifierSpanChecksumInto,
                codeIntelligenceIdentifierSpansInto);
            AssertIdentifierSpansLikeProduction(
                "func main() {\r    value := input.Count\r}\n",
                codeIntelligenceIdentifierSpanChecksumInto,
                codeIntelligenceIdentifierSpansInto);
            AssertIdentifierSpansLikeProduction(
                "func main() {\n    café42 := résumé.Count\n    print café42\n}\n",
                codeIntelligenceIdentifierSpanChecksumInto,
                codeIntelligenceIdentifierSpansInto);
            AssertEditorIdentifierSpansLikeProduction(
                """
func main() {
    value := input.Count
    print value
}
""",
                codeIntelligenceEditorIdentifierSpanChecksumInto,
                codeIntelligenceEditorIdentifierSpansInto);
            AssertEditorIdentifierSpansLikeProduction(
                "func main() {\n    café42 := résumé.Count\n    print café42\n}\n",
                codeIntelligenceEditorIdentifierSpanChecksumInto,
                codeIntelligenceEditorIdentifierSpansInto);
            AssertDeclarationNameMatchesLikeProduction(
                """
func main() {
    value := value + 1
    prefixvalue := 0
    café := café
}
""",
                codeIntelligenceDeclarationNameMatchChecksumInto,
                codeIntelligenceDeclarationNameMatchesFromLinesInto);
            AssertIdentifierNameColumnsLikeProduction(
                "func main() {\r\n    prefixvalue := value\r\n    café := café + value\r\n    spaced    := 4\r\n}\r\n",
                codeIntelligenceIdentifierNameColumnChecksumInto,
                codeIntelligenceIdentifierNameColumnsInto,
                buildCodeIntelligenceLineRangesInto,
                codeIntelligenceIdentifierNameColumnsFromLinesInto);

            AssertMemberReceiversLikeProduction(
                """
func main(customer: Customer, résumé: Profile) {
    print customer.Name
    print customer   .Name
    print customer?.Name
    print résumé.Count
}
""",
                codeIntelligenceMemberReceiverChecksumInto,
                codeIntelligenceMemberReceiversInto,
                codeIntelligenceMemberReceiverCachedChecksumInto,
                codeIntelligenceMemberReceiversCachedInto);
            AssertSourceContextsLikeProduction(
                "  first line  \n\tsecond line\r\n   \n\n café42  \n",
                codeIntelligenceSourceContextChecksumInto,
                codeIntelligenceSourceContextsInto);
            AssertSourceLinesLikeProduction(
                "  first line  \n\tsecond line\r\n   \n\n café42  \n",
                codeIntelligenceSourceLineChecksumInto,
                codeIntelligenceSourceLinesInto,
                codeIntelligenceSourceLinesFromLinesInto);
            AssertPathMatchingLikeProduction(
                codeIntelligencePathMatches,
                codeIntelligencePathMatchChecksumInto);
            AssertCompletionPrefixesLikeProduction(
                "  first line  \n\tsecond line\r\n   \n\n café42  \n",
                codeIntelligenceCompletionPrefixChecksumInto,
                codeIntelligenceCompletionPrefixesInto,
                codeIntelligenceCompletionPrefixesFromLinesInto);
            AssertCompletionReceiversLikeProduction(
                codeIntelligenceCompletionReceiverChecksumInto,
                codeIntelligenceCompletionReceiversInto);
            AssertCompletionItemGroupingLikeProduction(
                completionItemKindGroupsInto,
                completionItemKindGroupChecksumInto);
            AssertCompletionMethodGroupingLikeProduction(
                completionMethodOverloadGroupsInto,
                completionMethodOverloadGroupChecksumInto);
            AssertCliQueryPositionsLikeProduction(
                cliTryParsePositionInto,
                cliQueryPositionsInto,
                cliQueryPositionChecksumInto);
            AssertCliBuildOperandsLikeProduction(
                cliBuildOperandIndicesInto,
                cliBuildOperandSummaryInto,
                cliBuildFirstOperandIndexInto);
            AssertCliExportCSharpInputOperandLikeProduction(
                cliExportCSharpFirstOperandIndexInto,
                cliExportCSharpFirstOperandChecksumInto);
            AssertCliPositionalArgsLikeProduction(
                cliPositionalArgIndicesInto,
                cliFirstPositionalArgIndex,
                cliPositionalArgChecksumInto);
            AssertCliFixSafetyFilteringLikeProduction(
                cliFixSafetyFilterIndicesInto,
                cliFixSafetyFilterChecksumInto,
                cliFixEditFlattenIndicesInto,
                cliFixEditFlattenChecksumInto,
                cliFixSkippedIndicesInto,
                cliFixSkippedChecksumInto);
            AssertCliFixAppliedFileGroupingLikeProduction(
                cliFixAppliedFileGroupsInto,
                cliFixAppliedFileGroupChecksumInto);
            AssertCliUnifiedDiffHunkRangesLikeProduction(
                cliUnifiedDiffHunkRangesInto,
                cliUnifiedDiffHunkRangeChecksumInto);
            AssertCliCleanArtifactDirectoryOrderingLikeProduction(
                cliCleanArtifactDirectoryIndicesInto,
                cliCleanArtifactDirectoryChecksumInto);
            AssertCliUpdateAllNuGetDependencyFilteringLikeProduction(
                cliUpdateAllNuGetDependencyIndicesInto,
                cliUpdateAllNuGetDependencyChecksumInto);
            AssertCliUpdateTargetNuGetDependencyFilteringLikeProduction(
                cliUpdateTargetNuGetDependencyIndicesInto,
                cliUpdateTargetNuGetDependencyChecksumInto);
            AssertCliReferenceTypeFilteringLikeProduction(
                cliReferenceTypeFilterIndicesInto,
                cliReferenceTypeFilterChecksumInto);
            AssertCliDocSymbolOrderingLikeProduction(
                cliDocSymbolOrderCountingIndicesInto,
                cliDocSymbolOrderCountingChecksumInto);
            AssertCliDocMemberOrderingLikeProduction(
                cliDocSymbolOrderCountingIndicesInto,
                cliDocSymbolOrderCountingChecksumInto);
            AssertCliDocSlugsLikeProduction(cliDocSlugsInto);
            AssertCliSymbolNameGlobFilteringLikeProduction(cliSymbolNameGlobFilterIndicesInto);
            AssertSymbolKindFilteringLikeProduction(
                symbolKindFilterIndicesInto,
                symbolKindFilterChecksumInto);
            AssertDocQueryBestTypeSelectionLikeProduction(
                docQueryBestTypeIndex,
                docQueryBestTypeChecksumInto);
            AssertDocQueryMemberOrderingLikeProduction(
                docQueryMemberOrderIndicesInto,
                docQueryMemberOrderChecksumInto);
            AssertTypoSuggestionsLikeProduction(
                typoSuggestionIndicesInto,
                typoSuggestionChecksumInto);
            AssertAotRequirementGroupingLikeProduction(
                aotRequirementGroupsInto,
                aotRequirementGroupChecksumInto);
            AssertCliBatchDuplicateIdsLikeProduction(
                cliBatchDuplicateIdRanksInto,
                cliBatchDuplicateIdRankChecksumInto);
            AssertCliTreeDependencyDeduplicationLikeProduction(
                cliTreeDependencyDeduplicateIndicesInto,
                cliTreeDependencyDeduplicateChecksumInto);
            AssertTextEditOrderingLikeProduction(
                textEditOrderIndicesInto,
                textEditOrderChecksumInto);
            AssertDocCommentsLikeProduction(
                """
// ignored

// First line
///   Second line~~
//// Third line
~~~~
func documented(): int {
    return 1
}

// Nearest line only

// Skipped because blank follows comment
func another(): int {
    return 2
}

// Empty follows
///
func emptyDoc(): int {
    return 3
}
""".Replace('~', ' '),
                codeIntelligenceDocCommentChecksumInto,
                codeIntelligenceDocCommentLinesInto,
                codeIntelligenceDocCommentLinesFromLinesInto);
            AssertVariableDeclarationNamesLikeProduction(
                """
func main() {
    value := 1
	résumé_42 := value
    customer.Name := "Ada"
    spaced    := 4
    := missing
    noAssign
}
""",
                codeIntelligenceVariableDeclarationNameChecksumInto,
                codeIntelligenceVariableDeclarationNamesInto,
                buildCodeIntelligenceVariableDeclarationNameCacheInto,
                codeIntelligenceVariableDeclarationNamesFromCacheInto);
            AssertDiagnosticClusterTraitsLikeProduction(
                diagnosticClusterTraitsInto,
                diagnosticClusterTraitChecksumInto,
                diagnosticClusterTraitPatternChecksumInto,
                diagnosticClusterTraitsAndPatternsInto);
            AssertDiagnosticClusterIdsLikeProduction(
                diagnosticClusterIdsInto,
                diagnosticClusterIdChecksumInto);
            AssertDiagnosticClusterNextCommandsLikeProduction(
                diagnosticClusterNextCommandsInto,
                diagnosticClusterNextCommandChecksumInto);
            AssertDiagnosticClusterGroupsLikeProduction(
                diagnosticClusterCompactGroupsInto,
                diagnosticClusterCompactGroupChecksumInto,
                diagnosticClusterCompactGroupMembersInto,
                diagnosticClusterCompactGroupMemberChecksumInto);
            AssertDiagnosticDeduplicationLikeProduction(
                diagnosticDeduplicateCompactInto,
                diagnosticDeduplicateCompactChecksumInto,
                diagnosticDeduplicateStableInto,
                diagnosticDeduplicateStableChecksumInto);
            AssertReferenceDeduplicationLikeProduction(
                referenceDeduplicateCompactInto,
                referenceDeduplicateCompactChecksumInto);
            AssertReferenceFileSummaryLikeProduction(
                referenceFileSummaryRanksInto,
                referenceFileSummaryChecksumInto);
            AssertBindingLookupLikeProduction(
                bindingLookupCandidateColumnsInto,
                bindingLookupCandidateColumnChecksumInto,
                bindingLookupBuildSlotsInto,
                bindingLookupQueryDeclarationIndicesInto,
                bindingLookupQueryChecksumInto,
                bindingLookupBuildNearestDeclarationIndexInto,
                bindingLookupBuildNearestDeclarationIndexChecksumInto,
                bindingLookupFindNearestDeclarationIndicesInto,
                bindingLookupFindNearestDeclarationChecksumInto);
            AssertSemanticScopeVisibleVariablesLikeProduction(
                semanticScopeVisibleSymbolIndicesInto,
                semanticScopeVisibleSymbolChecksumInto,
                semanticScopeBuildSortedIndexInto,
                semanticScopeBuildSortedIndexChecksumInto,
                semanticScopeBuildDepthsInto,
                semanticScopeBuildDepthChecksumInto,
                semanticScopeLookupSymbolIndicesInto,
                semanticScopeLookupSymbolChecksumInto);
            AssertDiagnosticSeveritySummaryLikeProduction(
                diagnosticSeveritySummaryInto,
                diagnosticSeveritySummaryChecksumInto);
            AssertDiagnosticSeverityFilteringLikeProduction(
                diagnosticSeverityFilterIndicesInto,
                diagnosticSeverityFilterChecksumInto);
            AssertDiagnosticShadowSuppressionLikeProduction(
                diagnosticShadowSuppressionIndicesInto,
                diagnosticShadowSuppressionChecksumInto);
        }
        finally
        {
            if (File.Exists(outputPath))
            {
                File.Delete(outputPath);
            }
        }
    }

    private static void AssertTokenizesLikeProductionLexer(
        string source,
        MethodInfo tokenizeCount,
        MethodInfo tokenizeKinds,
        MethodInfo tokenizeKindsInto)
    {
        var expectedKinds = new Lexer(source, "dogfood-test.nl")
            .Tokenize()
            .Select(static token => (int)token.Type)
            .ToArray();

        var count = (int)(tokenizeCount.Invoke(null, new object[] { source }) ?? -1);
        var kinds = (int[])(tokenizeKinds.Invoke(null, new object[] { source })
            ?? throw new InvalidOperationException("TokenizeKinds returned null."));
        var buffer = new int[source.Length + 1];
        var bufferedCount = (int)(tokenizeKindsInto.Invoke(null, new object[] { source, buffer }) ?? -1);

        Assert.Equal(expectedKinds.Length, count);
        Assert.Equal(expectedKinds, kinds);
        Assert.Equal(expectedKinds.Length, bufferedCount);
        Assert.Equal(expectedKinds, buffer.Take(bufferedCount).ToArray());
    }

    private static void AssertTokenMetadataLikeProductionLexer(
        string source,
        MethodInfo tokenizeMetadataInto)
    {
        var expectedTokens = new Lexer(source, "dogfood-test.nl").Tokenize();
        var capacity = source.Length + 1;
        var kinds = new int[capacity];
        var starts = new int[capacity];
        var valueLengths = new int[capacity];
        var lines = new int[capacity];
        var columns = new int[capacity];

        var count = (int)(tokenizeMetadataInto.Invoke(
            null,
            new object[] { source, kinds, starts, valueLengths, lines, columns }) ?? -1);

        Assert.Equal(expectedTokens.Count, count);

        var lineStarts = BuildLineStarts(source);
        for (var i = 0; i < expectedTokens.Count; i++)
        {
            var token = expectedTokens[i];
            Assert.Equal((int)token.Type, kinds[i]);
            Assert.Equal(TokenStartFromLineColumn(lineStarts, token.Line, token.Column, source.Length), starts[i]);
            Assert.Equal(token.Value.Length, valueLengths[i]);
            Assert.Equal(token.Line, lines[i]);
            Assert.Equal(token.Column, columns[i]);
        }
    }

    private static void AssertParserTokenCompactionLikeProduction(
        string source,
        MethodInfo parserTokenCompactionIndicesInto,
        MethodInfo parserTokenCompactionChecksumInto)
    {
        var tokenKinds = new Lexer(source, "dogfood-test.nl")
            .Tokenize()
            .Select(static token => (int)token.Type)
            .ToArray();
        var expectedIndices = tokenKinds
            .Select((kind, index) => (kind, index))
            .Where(static item => item.kind != (int)TokenType.Newline)
            .Select(static item => item.index)
            .ToArray();

        var actualIndices = new int[tokenKinds.Length];
        var actualCount = (int)(parserTokenCompactionIndicesInto.Invoke(
            null,
            new object[] { tokenKinds, actualIndices }) ?? -1);

        Assert.Equal(expectedIndices.Length, actualCount);
        Assert.Equal(expectedIndices, actualIndices.Take(actualCount).ToArray());

        var checksumIndices = new int[tokenKinds.Length];
        var actualChecksum = (int)(parserTokenCompactionChecksumInto.Invoke(
            null,
            new object[] { tokenKinds, checksumIndices }) ?? -1);
        var expectedChecksum = ParserTokenCompactionChecksum(expectedIndices, tokenKinds);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedIndices, checksumIndices.Take(expectedIndices.Length).ToArray());
    }

    private static int ParserTokenCompactionChecksum(int[] orderedIndices, int[] tokenKinds)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            checksum += (i + 1) * 97 + tokenKinds[orderedIndices[i]] * 17;
        }

        return checksum;
    }

    private static int[] BuildLineStarts(string source)
    {
        var starts = new List<int> { 0 };
        var position = 0;
        while (position < source.Length)
        {
            if (source[position] == '\r')
            {
                position++;
                if (position < source.Length && source[position] == '\n')
                {
                    position++;
                }

                starts.Add(position);
                continue;
            }

            if (source[position] == '\n')
            {
                position++;
                starts.Add(position);
                continue;
            }

            position++;
        }

        return starts.ToArray();
    }

    private static int TokenStartFromLineColumn(int[] lineStarts, int line, int column, int sourceLength)
    {
        var lineIndex = line - 1;
        if (lineIndex < 0 || lineIndex >= lineStarts.Length)
        {
            return sourceLength;
        }

        return Math.Min(sourceLength, lineStarts[lineIndex] + column - 1);
    }

    private static void AssertSourceTextLineMapLikeProduction(
        string source,
        MethodInfo splitLogicalLines,
        MethodInfo splitLogicalLineRangesInto,
        MethodInfo buildLogicalLineStartsInto,
        MethodInfo getLineIndexFromOffset,
        MethodInfo getColumnFromOffset,
        MethodInfo getOffsetFromLineColumn,
        MethodInfo lineMapCachedChecksumInto,
        MethodInfo lineMapCachedQueryChecksumInto,
        MethodInfo lineMapTrustedCachedQueryChecksumInto)
    {
        var expected = SourceTextLines.SplitLogicalLines(source);
        var actual = (string[])(splitLogicalLines.Invoke(null, new object[] { source })
            ?? throw new InvalidOperationException("SplitLogicalLines returned null."));

        Assert.Equal(expected, actual);

        var starts = new int[source.Length + 1];
        var lengths = new int[source.Length + 1];
        var count = (int)(splitLogicalLineRangesInto.Invoke(null, new object[] { source, starts, lengths }) ?? -1);
        Assert.Equal(expected.Length, count);
        for (var i = 0; i < count; i++)
        {
            Assert.Equal(expected[i], source.Substring(starts[i], lengths[i]));
        }

        var expectedStarts = BuildLineStarts(source);
        var startOnlyBuffer = new int[source.Length + 1];
        var startOnlyCount = (int)(buildLogicalLineStartsInto.Invoke(null, new object[] { source, startOnlyBuffer }) ?? -1);
        Assert.Equal(expectedStarts.Length, startOnlyCount);
        Assert.Equal(expectedStarts, startOnlyBuffer.Take(startOnlyCount).ToArray());

        for (var offset = -1; offset <= source.Length + 1; offset++)
        {
            var expectedLineIndex = LineIndexFromOffset(expectedStarts, source.Length, offset);
            var expectedColumn = ColumnFromOffset(expectedStarts, source.Length, offset);
            var actualLineIndex = (int)(getLineIndexFromOffset.Invoke(
                null,
                new object[] { startOnlyBuffer, startOnlyCount, source.Length, offset }) ?? -1);
            var actualColumn = (int)(getColumnFromOffset.Invoke(
                null,
                new object[] { startOnlyBuffer, startOnlyCount, source.Length, offset }) ?? -1);

            Assert.Equal(expectedLineIndex, actualLineIndex);
            Assert.Equal(expectedColumn, actualColumn);
        }

        for (var line = 1; line <= expected.Length; line++)
        {
            var lineLength = expected[line - 1].Length;
            for (var column = 0; column <= lineLength; column++)
            {
                var actualOffset = (int)(getOffsetFromLineColumn.Invoke(
                    null,
                    new object[] { starts, lengths, count, source.Length, line, column }) ?? -2);
                Assert.Equal(expectedStarts[line - 1] + column, actualOffset);
            }

            var invalidColumnOffset = (int)(getOffsetFromLineColumn.Invoke(
                null,
                new object[] { starts, lengths, count, source.Length, line, lineLength + 1 }) ?? -2);
            Assert.Equal(-1, invalidColumnOffset);
        }

        var invalidLineOffset = (int)(getOffsetFromLineColumn.Invoke(
            null,
            new object[] { starts, lengths, count, source.Length, expected.Length + 1, 0 }) ?? -2);
        Assert.Equal(-1, invalidLineOffset);

        var offsets = Enumerable.Range(-1, source.Length + 3).ToArray();
        var queryLines = new List<int>();
        var queryColumns = new List<int>();
        for (var line = 1; line <= expected.Length; line++)
        {
            var lineLength = expected[line - 1].Length;
            for (var column = 0; column <= lineLength + 1; column++)
            {
                queryLines.Add(line);
                queryColumns.Add(column);
            }
        }

        queryLines.Add(0);
        queryColumns.Add(0);
        queryLines.Add(expected.Length + 1);
        queryColumns.Add(0);

        var expectedChecksum = expected.Length;
        foreach (var offset in offsets)
        {
            var expectedLineIndex = LineIndexFromOffset(expectedStarts, source.Length, offset);
            var expectedColumn = ColumnFromOffset(expectedStarts, source.Length, offset);
            expectedChecksum += expectedLineIndex * 31 + expectedColumn;
        }

        for (var i = 0; i < queryLines.Count; i++)
        {
            var line = queryLines[i];
            var column = queryColumns[i];
            var expectedOffset = -1;
            if (line >= 1 && line <= expected.Length && column >= 0 && column <= expected[line - 1].Length)
            {
                expectedOffset = expectedStarts[line - 1] + column;
            }

            expectedChecksum += expectedOffset * 17;
        }

        var cachedStarts = new int[source.Length + 1];
        var cachedLengths = new int[source.Length + 1];
        var offsetLineIndices = new int[source.Length + 1];
        var cachedChecksum = (int)(lineMapCachedChecksumInto.Invoke(
            null,
            new object[]
            {
                source,
                cachedStarts,
                cachedLengths,
                offsetLineIndices,
                offsets,
                queryLines.ToArray(),
                queryColumns.ToArray()
            }) ?? -1);

        Assert.Equal(expectedChecksum, cachedChecksum);

        var queryOffsetLineIndices = BuildOffsetLineIndices(expectedStarts, expected.Length, source.Length);
        var queryChecksum = (int)(lineMapCachedQueryChecksumInto.Invoke(
            null,
            new object[]
            {
                expectedStarts,
                lengths,
                expected.Length,
                source.Length,
                queryOffsetLineIndices,
                offsets,
                queryLines.ToArray(),
                queryColumns.ToArray()
            }) ?? -1);

        Assert.Equal(expectedChecksum, queryChecksum);

        var trustedOffsets = Enumerable.Range(0, source.Length + 1).ToArray();
        var trustedQueryLines = new List<int>();
        var trustedQueryColumns = new List<int>();
        for (var line = 1; line <= expected.Length; line++)
        {
            var lineLength = expected[line - 1].Length;
            for (var column = 0; column <= lineLength; column++)
            {
                trustedQueryLines.Add(line);
                trustedQueryColumns.Add(column);
            }
        }

        var trustedQueryLineArray = trustedQueryLines.ToArray();
        var trustedQueryColumnArray = trustedQueryColumns.ToArray();
        var expectedTrustedChecksum = expected.Length;
        foreach (var offset in trustedOffsets)
        {
            var expectedLineIndex = LineIndexFromOffset(expectedStarts, source.Length, offset);
            var expectedColumn = ColumnFromOffset(expectedStarts, source.Length, offset);
            expectedTrustedChecksum += expectedLineIndex * 31 + expectedColumn;
        }

        for (var i = 0; i < trustedQueryLineArray.Length; i++)
        {
            expectedTrustedChecksum += (expectedStarts[trustedQueryLineArray[i] - 1] + trustedQueryColumnArray[i]) * 17;
        }

        var trustedChecksum = (int)(lineMapTrustedCachedQueryChecksumInto.Invoke(
            null,
            new object[]
            {
                expectedStarts,
                expected.Length,
                queryOffsetLineIndices,
                trustedOffsets,
                trustedQueryLineArray,
                trustedQueryColumnArray
            }) ?? -1);

        Assert.Equal(expectedTrustedChecksum, trustedChecksum);
    }

    private static void AssertIdentifierSpansLikeProduction(
        string source,
        MethodInfo codeIntelligenceIdentifierSpanChecksumInto,
        MethodInfo codeIntelligenceIdentifierSpansInto)
    {
        var lines = source.Split('\n');
        var queries = new List<(int Line, int Column)>
        {
            (0, 0),
            (lines.Length + 1, 1)
        };

        for (var lineIndex = 0; lineIndex < lines.Length; lineIndex++)
        {
            var line = lineIndex + 1;
            var lineText = lines[lineIndex];
            queries.Add((line, 0));
            queries.Add((line, 1));
            queries.Add((line, lineText.Length));
            queries.Add((line, lineText.Length + 8));

            var identifier = FindFirstIdentifierSpan(lineText);
            queries.Add((line, identifier.StartColumn));
            queries.Add((line, Math.Max(1, identifier.StartColumn - 1)));
            queries.Add((line, Math.Min(Math.Max(1, lineText.Length), identifier.StartColumn + identifier.Length)));
            queries.Add((line, Math.Min(Math.Max(1, lineText.Length), identifier.StartColumn + identifier.Length + 1)));
        }

        var queryLines = queries.Select(static query => query.Line).ToArray();
        var queryColumns = queries.Select(static query => query.Column).ToArray();
        var expectedStarts = new int[queries.Count];
        var expectedLengths = new int[queries.Count];
        var expectedChecksum = 0;
        var expectedCount = 0;
        for (var i = 0; i < queries.Count; i++)
        {
            var span = ExtractIdentifierSpanAtPosition(source, queryLines[i], queryColumns[i]);
            var start = span?.StartColumn ?? -1;
            var length = span?.Length ?? 0;
            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
            if (start >= 0)
                expectedCount++;
        }

        var lineStarts = new int[source.Length + 1];
        var lineLengths = new int[source.Length + 1];
        var actualStarts = new int[queries.Count];
        var actualLengths = new int[queries.Count];
        var actualChecksum = (int)(codeIntelligenceIdentifierSpanChecksumInto.Invoke(
            null,
            new object[] { source, lineStarts, lineLengths, queryLines, queryColumns, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queries.Count];
        var productionLengths = new int[queries.Count];
        var actualCount = (int)(codeIntelligenceIdentifierSpansInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                queryColumns,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);
    }

    private static void AssertEditorIdentifierSpansLikeProduction(
        string source,
        MethodInfo codeIntelligenceEditorIdentifierSpanChecksumInto,
        MethodInfo codeIntelligenceEditorIdentifierSpansInto)
    {
        var lines = source.Split('\n');
        var queries = new List<(int Line, int Column)>
        {
            (0, 0),
            (lines.Length + 1, 1)
        };

        for (var lineIndex = 0; lineIndex < lines.Length; lineIndex++)
        {
            var line = lineIndex + 1;
            var lineText = lines[lineIndex];
            queries.Add((line, 0));
            queries.Add((line, 1));
            queries.Add((line, lineText.Length));
            queries.Add((line, lineText.Length + 8));

            var identifier = FindFirstIdentifierSpan(lineText);
            queries.Add((line, identifier.StartColumn));
            queries.Add((line, identifier.StartColumn + Math.Max(0, identifier.Length - 1)));
            queries.Add((line, identifier.StartColumn + identifier.Length));
        }

        var queryLines = queries.Select(static query => query.Line).ToArray();
        var queryColumns = queries.Select(static query => query.Column).ToArray();
        var expectedStarts = new int[queries.Count];
        var expectedLengths = new int[queries.Count];
        var expectedChecksum = 0;
        var expectedCount = 0;
        for (var i = 0; i < queries.Count; i++)
        {
            var span = ExtractEditorIdentifierSpanAtPosition(source, queryLines[i], queryColumns[i]);
            var start = span?.StartColumn ?? -1;
            var length = span?.Length ?? 0;
            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
            if (start >= 0)
                expectedCount++;
        }

        var lineStarts = new int[source.Length + 1];
        var lineLengths = new int[source.Length + 1];
        var actualStarts = new int[queries.Count];
        var actualLengths = new int[queries.Count];
        var actualChecksum = (int)(codeIntelligenceEditorIdentifierSpanChecksumInto.Invoke(
            null,
            new object[] { source, lineStarts, lineLengths, queryLines, queryColumns, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queries.Count];
        var productionLengths = new int[queries.Count];
        var actualCount = (int)(codeIntelligenceEditorIdentifierSpansInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                queryColumns,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);
    }

    private static void AssertDeclarationNameMatchesLikeProduction(
        string source,
        MethodInfo codeIntelligenceDeclarationNameMatchChecksumInto,
        MethodInfo codeIntelligenceDeclarationNameMatchesFromLinesInto)
    {
        var lines = source.Split('\n');
        var firstValueColumn = FindNameStartColumn(lines[1], "value", 1);
        var secondValueColumn = FindNameStartColumn(lines[1], "value", firstValueColumn + "value".Length);
        var prefixValueColumn = FindNameStartColumn(lines[2], "value", 1);
        var cafeColumn = FindNameStartColumn(lines[3], "café", 1);

        var queries = new List<(int Line, int DeclarationColumn, string Name, int SelectedStart, int SelectedEnd)>
        {
            (0, 1, "value", 1, 5),
            (lines.Length + 1, 1, "value", 1, 5),
            (2, firstValueColumn, "value", firstValueColumn, firstValueColumn + "value".Length - 1),
            (2, firstValueColumn, "value", secondValueColumn, secondValueColumn + "value".Length - 1),
            (2, secondValueColumn, "value", secondValueColumn, secondValueColumn + "value".Length - 1),
            (3, 1, "value", prefixValueColumn, prefixValueColumn + "value".Length - 1),
            (3, prefixValueColumn + "value".Length, "value", prefixValueColumn, prefixValueColumn + "value".Length - 1),
            (4, cafeColumn, "café", cafeColumn, cafeColumn + "café".Length - 1),
            (4, cafeColumn, "missing", cafeColumn, cafeColumn + "café".Length - 1)
        };

        var queryLines = queries.Select(static query => query.Line).ToArray();
        var declarationColumns = queries.Select(static query => query.DeclarationColumn).ToArray();
        var declarationNames = queries.Select(static query => query.Name).ToArray();
        var selectedStartColumns = queries.Select(static query => query.SelectedStart).ToArray();
        var selectedEndColumns = queries.Select(static query => query.SelectedEnd).ToArray();
        var expectedMatches = new int[queries.Count];
        var expectedChecksum = 0;
        var expectedCount = 0;

        for (var i = 0; i < queries.Count; i++)
        {
            var query = queries[i];
            var matches = SelectedSpanMatchesDeclarationName(
                source,
                query.Line,
                query.DeclarationColumn,
                query.Name,
                query.SelectedStart,
                query.SelectedEnd);
            expectedMatches[i] = matches ? 1 : 0;
            expectedChecksum += expectedMatches[i] * (i + 1);
            if (matches)
            {
                expectedCount++;
            }
        }

        var lineStarts = new int[source.Length + 1];
        var lineLengths = new int[source.Length + 1];
        var actualMatches = new int[queries.Count];
        var actualChecksum = (int)(codeIntelligenceDeclarationNameMatchChecksumInto.Invoke(
            null,
            new object[]
            {
                source,
                lineStarts,
                lineLengths,
                queryLines,
                declarationColumns,
                declarationNames,
                selectedStartColumns,
                selectedEndColumns,
                actualMatches
            }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedMatches, actualMatches);

        var cachedLineStarts = new int[source.Length + 1];
        var cachedLineLengths = new int[source.Length + 1];
        var lineCount = BuildLineRanges(source, cachedLineStarts, cachedLineLengths);
        var cachedMatches = new int[queries.Count];
        var cachedCount = (int)(codeIntelligenceDeclarationNameMatchesFromLinesInto.Invoke(
            null,
            new object[]
            {
                source,
                cachedLineStarts,
                cachedLineLengths,
                lineCount,
                queryLines,
                declarationColumns,
                declarationNames,
                selectedStartColumns,
                selectedEndColumns,
                cachedMatches
            }) ?? -1);

        Assert.Equal(expectedCount, cachedCount);
        Assert.Equal(expectedMatches, cachedMatches);
    }

    private static void AssertIdentifierNameColumnsLikeProduction(
        string source,
        MethodInfo codeIntelligenceIdentifierNameColumnChecksumInto,
        MethodInfo codeIntelligenceIdentifierNameColumnsInto,
        MethodInfo buildCodeIntelligenceLineRangesInto,
        MethodInfo codeIntelligenceIdentifierNameColumnsFromLinesInto)
    {
        var lines = source.Split('\n');
        var prefixLineText = lines[1].TrimEnd('\r');
        var cafeLineText = lines[2].TrimEnd('\r');
        var spacedLineText = lines[3].TrimEnd('\r');
        var prefixValueColumn = FindWholeIdentifierColumn(prefixLineText, "value", 1);
        var prefixIdentifierColumn = FindWholeIdentifierColumn(prefixLineText, "prefixvalue", 1);
        var cafeColumn = FindWholeIdentifierColumn(cafeLineText, "café", 1);
        var secondCafeColumn = FindWholeIdentifierColumn(cafeLineText, "café", cafeColumn + "café".Length);
        var cafeValueColumn = FindWholeIdentifierColumn(cafeLineText, "value", 1);
        var spacedColumn = FindWholeIdentifierColumn(spacedLineText, "spaced", 1);

        var queries = new List<(int Line, string Name, int FallbackColumn)>
        {
            (0, "value", 99),
            (lines.Length + 1, "value", 7),
            (2, "value", 1),
            (2, "prefixvalue", prefixIdentifierColumn),
            (2, "value", prefixValueColumn),
            (3, "café", secondCafeColumn),
            (3, "value", 1),
            (4, "spaced", spacedColumn + 20),
            (4, "missing", 6)
        };

        var queryLines = queries.Select(static query => query.Line).ToArray();
        var names = queries.Select(static query => query.Name).ToArray();
        var fallbackColumns = queries.Select(static query => query.FallbackColumn).ToArray();
        var expectedColumns = new int[queries.Count];
        var expectedCount = 0;

        for (var i = 0; i < queries.Count; i++)
        {
            var query = queries[i];
            if (TryFindIdentifierNameColumn(source, query.Name, query.Line, query.FallbackColumn, out var column))
            {
                expectedCount++;
            }

            expectedColumns[i] = column;
        }

        Assert.Equal(prefixValueColumn, expectedColumns[2]);
        Assert.Equal(secondCafeColumn, expectedColumns[5]);
        Assert.Equal(cafeValueColumn, expectedColumns[6]);
        Assert.Equal(fallbackColumns[8], expectedColumns[8]);

        var expectedChecksum = expectedCount;
        for (var i = 0; i < queries.Count; i++)
        {
            expectedChecksum += expectedColumns[i] * 31 + fallbackColumns[i] * 17;
        }

        var lineStarts = new int[source.Length + 1];
        var lineLengths = new int[source.Length + 1];
        var actualColumns = new int[queries.Count];
        var actualChecksum = (int)(codeIntelligenceIdentifierNameColumnChecksumInto.Invoke(
            null,
            new object[] { source, lineStarts, lineLengths, queryLines, names, fallbackColumns, actualColumns }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedColumns, actualColumns);

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionColumns = new int[queries.Count];
        var actualCount = (int)(codeIntelligenceIdentifierNameColumnsInto.Invoke(
            null,
            new object[] { source, productionLineStarts, productionLineLengths, queryLines, names, fallbackColumns, productionColumns }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedColumns, productionColumns);

        var cachedLineStarts = new int[source.Length + 1];
        var cachedLineLengths = new int[source.Length + 1];
        var lineCount = (int)(buildCodeIntelligenceLineRangesInto.Invoke(
            null,
            new object[] { source, cachedLineStarts, cachedLineLengths }) ?? -1);
        var cachedColumns = new int[queries.Count];
        var cachedCount = (int)(codeIntelligenceIdentifierNameColumnsFromLinesInto.Invoke(
            null,
            new object[]
            {
                source,
                cachedLineStarts,
                cachedLineLengths,
                lineCount,
                queryLines,
                names,
                fallbackColumns,
                cachedColumns
            }) ?? -1);

        Assert.Equal(expectedCount, cachedCount);
        Assert.Equal(expectedColumns, cachedColumns);
    }

    private static void AssertMemberReceiversLikeProduction(
        string source,
        MethodInfo codeIntelligenceMemberReceiverChecksumInto,
        MethodInfo codeIntelligenceMemberReceiversInto,
        MethodInfo codeIntelligenceMemberReceiverCachedChecksumInto,
        MethodInfo codeIntelligenceMemberReceiversCachedInto)
    {
        var lines = source.Split('\n');
        var queries = new List<(int Line, int MemberStartColumn)>
        {
            (0, 0),
            (lines.Length + 1, 1)
        };

        for (var lineIndex = 0; lineIndex < lines.Length; lineIndex++)
        {
            var line = lineIndex + 1;
            var lineText = lines[lineIndex];
            queries.Add((line, 0));
            queries.Add((line, 1));
            queries.Add((line, lineText.Length + 8));

            for (var i = 0; i < lineText.Length - 1; i++)
            {
                if (lineText[i] == '.' && IsIdentifierChar(lineText[i + 1]))
                {
                    queries.Add((line, i + 2));
                }
            }
        }

        var queryLines = queries.Select(static query => query.Line).ToArray();
        var memberStartColumns = queries.Select(static query => query.MemberStartColumn).ToArray();
        var expectedStarts = new int[queries.Count];
        var expectedLengths = new int[queries.Count];
        var expectedChecksum = 0;
        var expectedCount = 0;
        for (var i = 0; i < queries.Count; i++)
        {
            var span = ExtractMemberReceiverSpan(source, queryLines[i], memberStartColumns[i]);
            var start = span?.StartColumn ?? -1;
            var length = span?.Length ?? 0;
            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
            if (start >= 0)
                expectedCount++;
        }

        var lineStarts = new int[source.Length + 1];
        var lineLengths = new int[source.Length + 1];
        var actualStarts = new int[queries.Count];
        var actualLengths = new int[queries.Count];
        var actualChecksum = (int)(codeIntelligenceMemberReceiverChecksumInto.Invoke(
            null,
            new object[] { source, lineStarts, lineLengths, queryLines, memberStartColumns, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queries.Count];
        var productionLengths = new int[queries.Count];
        var actualCount = (int)(codeIntelligenceMemberReceiversInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                memberStartColumns,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);

        var cachedLineStarts = new int[source.Length + 1];
        var cachedLineLengths = new int[source.Length + 1];
        var receiverStartsBySeparator = new int[source.Length + 1];
        var receiverLengthsBySeparator = new int[source.Length + 1];
        var cachedStarts = new int[queries.Count];
        var cachedLengths = new int[queries.Count];
        var cachedChecksum = (int)(codeIntelligenceMemberReceiverCachedChecksumInto.Invoke(
            null,
            new object[]
            {
                source,
                cachedLineStarts,
                cachedLineLengths,
                receiverStartsBySeparator,
                receiverLengthsBySeparator,
                queryLines,
                memberStartColumns,
                cachedStarts,
                cachedLengths
            }) ?? -1);

        Assert.Equal(expectedChecksum, cachedChecksum);
        Assert.Equal(expectedStarts, cachedStarts);
        Assert.Equal(expectedLengths, cachedLengths);

        var productionCachedLineStarts = new int[source.Length + 1];
        var productionCachedLineLengths = new int[source.Length + 1];
        var productionReceiverStartsBySeparator = new int[source.Length + 1];
        var productionReceiverLengthsBySeparator = new int[source.Length + 1];
        var productionCachedStarts = new int[queries.Count];
        var productionCachedLengths = new int[queries.Count];
        var actualCachedCount = (int)(codeIntelligenceMemberReceiversCachedInto.Invoke(
            null,
            new object[]
            {
                source,
                productionCachedLineStarts,
                productionCachedLineLengths,
                productionReceiverStartsBySeparator,
                productionReceiverLengthsBySeparator,
                queryLines,
                memberStartColumns,
                productionCachedStarts,
                productionCachedLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCachedCount);
        Assert.Equal(expectedStarts, productionCachedStarts);
        Assert.Equal(expectedLengths, productionCachedLengths);
    }

    private static void AssertSourceContextsLikeProduction(
        string source,
        MethodInfo codeIntelligenceSourceContextChecksumInto,
        MethodInfo codeIntelligenceSourceContextsInto)
    {
        var lines = source.Split('\n');
        var queries = new List<int> { 0, lines.Length + 1 };
        for (var line = 1; line <= lines.Length; line++)
        {
            queries.Add(line);
        }

        var queryLines = queries.ToArray();
        var expectedStarts = new int[queryLines.Length];
        var expectedLengths = new int[queryLines.Length];
        var expectedChecksum = 0;
        var expectedCount = 0;
        var lineStarts = BuildLfLineStarts(source);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var start = -1;
            var length = 0;

            if (line >= 1 && line <= lines.Length)
            {
                var lineText = lines[line - 1];
                var trimStart = 0;
                var trimEnd = lineText.Length - 1;
                while (trimStart <= trimEnd && char.IsWhiteSpace(lineText[trimStart]))
                {
                    trimStart++;
                }

                while (trimEnd >= trimStart && char.IsWhiteSpace(lineText[trimEnd]))
                {
                    trimEnd--;
                }

                start = lineStarts[line - 1] + trimStart;
                if (trimEnd >= trimStart)
                {
                    length = trimEnd - trimStart + 1;
                }

                expectedCount++;
            }

            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
        }

        var rangeStarts = new int[source.Length + 1];
        var rangeLengths = new int[source.Length + 1];
        var actualStarts = new int[queryLines.Length];
        var actualLengths = new int[queryLines.Length];
        var actualChecksum = (int)(codeIntelligenceSourceContextChecksumInto.Invoke(
            null,
            new object[] { source, rangeStarts, rangeLengths, queryLines, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var expectedContext = line >= 1 && line <= lines.Length
                ? lines[line - 1].Trim()
                : null;
            var actualContext = actualStarts[i] >= 0
                ? source.Substring(actualStarts[i], actualLengths[i])
                : null;
            Assert.Equal(expectedContext, actualContext);
        }

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queryLines.Length];
        var productionLengths = new int[queryLines.Length];
        var actualCount = (int)(codeIntelligenceSourceContextsInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);
    }

    private static void AssertSourceLinesLikeProduction(
        string source,
        MethodInfo codeIntelligenceSourceLineChecksumInto,
        MethodInfo codeIntelligenceSourceLinesInto,
        MethodInfo codeIntelligenceSourceLinesFromLinesInto)
    {
        var lines = source.Split('\n');
        var queries = new List<int> { 0, lines.Length + 1 };
        for (var line = 1; line <= lines.Length; line++)
        {
            queries.Add(line);
        }

        var queryLines = queries.ToArray();
        var expectedStarts = new int[queryLines.Length];
        var expectedLengths = new int[queryLines.Length];
        var expectedChecksum = 0;
        var expectedCount = 0;
        var lineStarts = BuildLfLineStarts(source);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var start = -1;
            var length = 0;

            if (line >= 1 && line <= lines.Length)
            {
                start = lineStarts[line - 1];
                length = lines[line - 1].Length;
                expectedCount++;
            }

            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
        }

        var rangeStarts = new int[source.Length + 1];
        var rangeLengths = new int[source.Length + 1];
        var actualStarts = new int[queryLines.Length];
        var actualLengths = new int[queryLines.Length];
        var actualChecksum = (int)(codeIntelligenceSourceLineChecksumInto.Invoke(
            null,
            new object[] { source, rangeStarts, rangeLengths, queryLines, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var expectedLine = line >= 1 && line <= lines.Length
                ? lines[line - 1]
                : null;
            var actualLine = actualStarts[i] >= 0
                ? source.Substring(actualStarts[i], actualLengths[i])
                : null;
            Assert.Equal(expectedLine, actualLine);
        }

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queryLines.Length];
        var productionLengths = new int[queryLines.Length];
        var actualCount = (int)(codeIntelligenceSourceLinesInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);

        var cachedLineStarts = new int[source.Length + 1];
        var cachedLineLengths = new int[source.Length + 1];
        var cachedStarts = new int[queryLines.Length];
        var cachedLengths = new int[queryLines.Length];
        var lineCount = BuildLineRanges(source, cachedLineStarts, cachedLineLengths);
        var cachedCount = (int)(codeIntelligenceSourceLinesFromLinesInto.Invoke(
            null,
            new object[]
            {
                cachedLineStarts,
                cachedLineLengths,
                lineCount,
                queryLines,
                cachedStarts,
                cachedLengths
            }) ?? -1);

        Assert.Equal(expectedCount, cachedCount);
        Assert.Equal(expectedStarts, cachedStarts);
        Assert.Equal(expectedLengths, cachedLengths);
    }

    private static void AssertPathMatchingLikeProduction(
        MethodInfo codeIntelligencePathMatches,
        MethodInfo codeIntelligencePathMatchChecksumInto)
    {
        var fullPaths = new[]
        {
            "/repo/src/Program.nl",
            "/repo/src/features/Handler.nl",
            "/repo/src/OldProgram.nl",
            @"C:\repo\src\Generated\File.nl",
            "/repo/src/",
            "",
            "/repo/src/cafe/résumé.nl",
            "/repo/src/nested/File.nl"
        };
        var queryPaths = new[]
        {
            @"\REPO\SRC\program.NL",
            @"features\handler.nl",
            "Program.nl",
            "/src/generated/file.nl",
            "",
            "",
            "cafe/RÉSUMÉ.nl",
            "nested/Other.nl"
        };

        var expectedFlags = new int[fullPaths.Length];
        var expectedChecksum = expectedFlags.Length;
        for (var i = 0; i < fullPaths.Length; i++)
        {
            expectedFlags[i] = MatchesFilePathLikeProduction(fullPaths[i], queryPaths[i]) ? 1 : 0;
            expectedChecksum += expectedFlags[i] * (i + 1) * 31;

            var actualFlag = (int)(codeIntelligencePathMatches.Invoke(
                null,
                new object[] { fullPaths[i], queryPaths[i] }) ?? -1);
            Assert.Equal(expectedFlags[i], actualFlag);
        }

        var resultFlags = new int[fullPaths.Length];
        var actualChecksum = (int)(codeIntelligencePathMatchChecksumInto.Invoke(
            null,
            new object[] { fullPaths, queryPaths, resultFlags }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedFlags, resultFlags);
    }

    private static bool MatchesFilePathLikeProduction(string fullPath, string queryPath)
    {
        var normalizedFull = fullPath.Replace('\\', '/');
        var normalizedQuery = queryPath.Replace('\\', '/');

        if (normalizedFull.Equals(normalizedQuery, StringComparison.OrdinalIgnoreCase))
            return true;

        if (!normalizedFull.EndsWith(normalizedQuery, StringComparison.OrdinalIgnoreCase))
            return false;

        var charBefore = normalizedFull[normalizedFull.Length - normalizedQuery.Length - 1];
        return charBefore == '/';
    }

    private static void AssertCompletionPrefixesLikeProduction(
        string source,
        MethodInfo codeIntelligenceCompletionPrefixChecksumInto,
        MethodInfo codeIntelligenceCompletionPrefixesInto,
        MethodInfo codeIntelligenceCompletionPrefixesFromLinesInto)
    {
        var lines = source.Split('\n');
        var queryLinesList = new List<int> { 0, lines.Length + 1 };
        var queryColumnsList = new List<int> { 1, 1 };

        for (var line = 1; line <= lines.Length; line++)
        {
            var lineLength = lines[line - 1].Length;
            queryLinesList.Add(line);
            queryColumnsList.Add(0);
            queryLinesList.Add(line);
            queryColumnsList.Add(1);
            queryLinesList.Add(line);
            queryColumnsList.Add(lineLength);
            queryLinesList.Add(line);
            queryColumnsList.Add(lineLength + 1);
        }

        var queryLines = queryLinesList.ToArray();
        var queryColumns = queryColumnsList.ToArray();
        var expectedStarts = new int[queryLines.Length];
        var expectedLengths = new int[queryLines.Length];
        var expectedChecksum = 0;
        var expectedCount = 0;
        var lineStarts = BuildLfLineStarts(source);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var column = queryColumns[i];
            var start = -1;
            var length = 0;

            if (line >= 1 && line <= lines.Length)
            {
                start = lineStarts[line - 1];
                length = lines[line - 1].Length;
                if (column > 0 && column <= length)
                {
                    length = column;
                }

                expectedCount++;
            }

            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
        }

        var rangeStarts = new int[source.Length + 1];
        var rangeLengths = new int[source.Length + 1];
        var actualStarts = new int[queryLines.Length];
        var actualLengths = new int[queryLines.Length];
        var actualChecksum = (int)(codeIntelligenceCompletionPrefixChecksumInto.Invoke(
            null,
            new object[] { source, rangeStarts, rangeLengths, queryLines, queryColumns, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var column = queryColumns[i];
            var expectedPrefix = line >= 1 && line <= lines.Length
                ? ExtractCompletionPrefix(source, line, column)
                : null;
            var actualPrefix = actualStarts[i] >= 0
                ? source.Substring(actualStarts[i], actualLengths[i])
                : null;
            Assert.Equal(expectedPrefix, actualPrefix);
        }

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queryLines.Length];
        var productionLengths = new int[queryLines.Length];
        var actualCount = (int)(codeIntelligenceCompletionPrefixesInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                queryColumns,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);

        var cachedLineStarts = new int[source.Length + 1];
        var cachedLineLengths = new int[source.Length + 1];
        var cachedStarts = new int[queryLines.Length];
        var cachedLengths = new int[queryLines.Length];
        var lineCount = BuildLineRanges(source, cachedLineStarts, cachedLineLengths);
        var cachedCount = (int)(codeIntelligenceCompletionPrefixesFromLinesInto.Invoke(
            null,
            new object[]
            {
                cachedLineStarts,
                cachedLineLengths,
                lineCount,
                queryLines,
                queryColumns,
                cachedStarts,
                cachedLengths
            }) ?? -1);

        Assert.Equal(expectedCount, cachedCount);
        Assert.Equal(expectedStarts, cachedStarts);
        Assert.Equal(expectedLengths, cachedLengths);
    }

    private static void AssertCompletionReceiversLikeProduction(
        MethodInfo codeIntelligenceCompletionReceiverChecksumInto,
        MethodInfo codeIntelligenceCompletionReceiversInto)
    {
        var isMemberAccessContext = typeof(CompletionEngine).GetMethod(
                "IsMemberAccessContext",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("CompletionEngine did not emit IsMemberAccessContext.");
        var extractReceiver = typeof(CompletionEngine).GetMethod(
                "ExtractReceiver",
                BindingFlags.Static | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException("CompletionEngine did not emit ExtractReceiver.");

        var prefixes = new[]
        {
            "people.",
            "people.Add",
            "factory.Create(name).",
            "factory.Create(name, other.Value).Co",
            "System.Console.",
            "message.ToUpper().",
            "message.ToUpper().Len",
            "    \"abc\".",
            "    $\"hello {name}\".",
            "    \"a.b\".Len",
            "    \"\"\"hello\"\"\".",
            "    \"unterminated.",
            "    true.",
            "    false.ToString().",
            "    42.",
            "    1.5.",
            "    0xCAFE.",
            "    'x'.",
            "    return people",
            "    name",
            "    call(value.withDot).",
            "    namespace.Type.Member",
            "    Console.WriteLine(factory.Create(name, other.Value)).",
            "    items.Where(item => item.Enabled).",
            "/// <summary>A representative lexer service input.</summary>.0xCAFE.",
            "    résumé.Count"
        };

        var expectedContexts = new int[prefixes.Length];
        var expectedReceivers = Enumerable.Repeat(string.Empty, prefixes.Length).ToArray();
        var expectedChecksum = prefixes.Length;

        for (var i = 0; i < prefixes.Length; i++)
        {
            var isMemberAccess = (bool)(isMemberAccessContext.Invoke(null, new object[] { prefixes[i] }) ?? false);
            var receiver = isMemberAccess
                ? (string?)extractReceiver.Invoke(null, new object[] { prefixes[i] }) ?? string.Empty
                : string.Empty;

            expectedContexts[i] = isMemberAccess ? 1 : 0;
            expectedReceivers[i] = receiver;
            expectedChecksum += expectedContexts[i] * 31 + receiver.Length * 17;
        }

        var checksumContexts = new int[prefixes.Length];
        var checksumReceivers = Enumerable.Repeat(string.Empty, prefixes.Length).ToArray();
        var actualChecksum = (int)(codeIntelligenceCompletionReceiverChecksumInto.Invoke(
            null,
            new object[] { prefixes, checksumContexts, checksumReceivers }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedContexts, checksumContexts);
        Assert.Equal(expectedReceivers, checksumReceivers);

        var actualContexts = new int[prefixes.Length];
        var actualReceivers = Enumerable.Repeat(string.Empty, prefixes.Length).ToArray();
        var actualCount = (int)(codeIntelligenceCompletionReceiversInto.Invoke(
            null,
            new object[] { prefixes, actualContexts, actualReceivers }) ?? -1);

        Assert.Equal(prefixes.Length, actualCount);
        Assert.Equal(expectedContexts, actualContexts);
        Assert.Equal(expectedReceivers, actualReceivers);
    }

    private static void AssertCompletionItemGroupingLikeProduction(
        MethodInfo completionItemKindGroupsInto,
        MethodInfo completionItemKindGroupChecksumInto)
    {
        var kindIds = new[] { 2, 1, 2, 3, 1 };
        var kindCounts = new int[4];
        var kindOffsets = new int[4];
        var resultKindIds = new int[kindIds.Length];
        var resultStarts = new int[kindIds.Length];
        var resultCounts = new int[kindIds.Length];
        var resultIndices = new int[kindIds.Length];

        var groupCount = (int)(completionItemKindGroupsInto.Invoke(
            null,
            new object[] { kindIds, kindCounts, kindOffsets, resultKindIds, resultStarts, resultCounts, resultIndices }) ?? -1);

        Assert.Equal(3, groupCount);
        Assert.Equal(new[] { 2, 1, 3 }, resultKindIds.Take(groupCount));
        Assert.Equal(new[] { 0, 2, 4 }, resultStarts.Take(groupCount));
        Assert.Equal(new[] { 2, 2, 1 }, resultCounts.Take(groupCount));
        Assert.Equal(new[] { 0, 2, 1, 4, 3 }, resultIndices);

        var checksumKindCounts = new int[4];
        var checksumKindOffsets = new int[4];
        var checksumResultKindIds = new int[kindIds.Length];
        var checksumResultStarts = new int[kindIds.Length];
        var checksumResultCounts = new int[kindIds.Length];
        var checksumResultIndices = new int[kindIds.Length];
        var expectedChecksum = CompletionItemKindGroupingChecksum(
            resultKindIds,
            resultStarts,
            resultCounts,
            resultIndices,
            groupCount);
        var actualChecksum = (int)(completionItemKindGroupChecksumInto.Invoke(
            null,
            new object[]
            {
                kindIds,
                checksumKindCounts,
                checksumKindOffsets,
                checksumResultKindIds,
                checksumResultStarts,
                checksumResultCounts,
                checksumResultIndices
            }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(resultKindIds, checksumResultKindIds);
        Assert.Equal(resultStarts, checksumResultStarts);
        Assert.Equal(resultCounts, checksumResultCounts);
        Assert.Equal(resultIndices, checksumResultIndices);
    }

    private static int CompletionItemKindGroupingChecksum(
        int[] resultKindIds,
        int[] resultStarts,
        int[] resultCounts,
        int[] resultIndices,
        int groupCount)
    {
        var checksum = groupCount;
        for (var groupIndex = 0; groupIndex < groupCount; groupIndex++)
        {
            var start = resultStarts[groupIndex];
            var count = resultCounts[groupIndex];
            checksum += resultKindIds[groupIndex] * 97 + start * 31 + count * 17;

            for (var itemIndex = 0; itemIndex < count; itemIndex++)
            {
                var sourceIndex = resultIndices[start + itemIndex];
                checksum += (sourceIndex + 1) * 13 + (itemIndex + 1) * 7;
            }
        }

        return checksum;
    }

    private static void AssertCompletionMethodGroupingLikeProduction(
        MethodInfo completionMethodOverloadGroupsInto,
        MethodInfo completionMethodOverloadGroupChecksumInto)
    {
        var nameIds = new[] { 2, 1, 2, 3, 1, 0, 2 };
        var includeFlags = new[] { 1, 1, 1, 1, 1, 0, 1 };
        var nameCounts = new int[4];
        var resultNameIds = new int[nameIds.Length];
        var resultFirstIndices = new int[nameIds.Length];
        var resultCounts = new int[nameIds.Length];

        var groupCount = (int)(completionMethodOverloadGroupsInto.Invoke(
            null,
            new object[] { nameIds, includeFlags, nameCounts, resultNameIds, resultFirstIndices, resultCounts }) ?? -1);

        Assert.Equal(3, groupCount);
        Assert.Equal(new[] { 2, 1, 3 }, resultNameIds.Take(groupCount));
        Assert.Equal(new[] { 0, 1, 3 }, resultFirstIndices.Take(groupCount));
        Assert.Equal(new[] { 3, 2, 1 }, resultCounts.Take(groupCount));

        var checksumNameCounts = new int[4];
        var checksumResultNameIds = new int[nameIds.Length];
        var checksumResultFirstIndices = new int[nameIds.Length];
        var checksumResultCounts = new int[nameIds.Length];
        var expectedChecksum = CompletionMethodOverloadGroupingChecksum(
            resultNameIds,
            resultFirstIndices,
            resultCounts,
            groupCount);
        var actualChecksum = (int)(completionMethodOverloadGroupChecksumInto.Invoke(
            null,
            new object[]
            {
                nameIds,
                includeFlags,
                checksumNameCounts,
                checksumResultNameIds,
                checksumResultFirstIndices,
                checksumResultCounts
            }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(resultNameIds, checksumResultNameIds);
        Assert.Equal(resultFirstIndices, checksumResultFirstIndices);
        Assert.Equal(resultCounts, checksumResultCounts);
    }

    private static int CompletionMethodOverloadGroupingChecksum(
        int[] resultNameIds,
        int[] resultFirstIndices,
        int[] resultCounts,
        int groupCount)
    {
        var checksum = groupCount;
        for (var groupIndex = 0; groupIndex < groupCount; groupIndex++)
        {
            checksum += resultNameIds[groupIndex] * 97
                + resultFirstIndices[groupIndex] * 31
                + resultCounts[groupIndex] * 17
                + (groupIndex + 1) * 13;
        }

        return checksum;
    }

    private static void AssertCliQueryPositionsLikeProduction(
        MethodInfo cliTryParsePositionInto,
        MethodInfo cliQueryPositionsInto,
        MethodInfo cliQueryPositionChecksumInto)
    {
        var positions = new[]
        {
            "1:1",
            "42:17",
            " 42 : 17 ",
            "+64:+10",
            "-1:5",
            "2147483647:2147483647",
            "-2147483648:-2147483648",
            "0:0",
            "12:",
            ":34",
            "12:abc",
            "abc:12",
            "12:34:56",
            "2147483648:1",
            "1:-2147483649",
            "1_000:2",
            "7 :\t8"
        };
        var expectedLines = new int[positions.Length];
        var expectedColumns = new int[positions.Length];
        var expectedChecksum = positions.Length;

        for (var i = 0; i < positions.Length; i++)
        {
            var parsed = TryParseCliPositionWithSplit(positions[i], out var line, out var column);
            expectedLines[i] = line;
            expectedColumns[i] = column;
            expectedChecksum += (parsed ? 1 : 0) * 97 + line * 31 + column * 17;

            var singleResult = new int[2];
            var actualParsed = (int)(cliTryParsePositionInto.Invoke(
                null,
                new object[] { positions[i], singleResult }) ?? -1);
            Assert.Equal(parsed ? 1 : 0, actualParsed);
            Assert.Equal(line, singleResult[0]);
            Assert.Equal(column, singleResult[1]);
        }

        var actualLines = new int[positions.Length];
        var actualColumns = new int[positions.Length];
        var actualCount = (int)(cliQueryPositionsInto.Invoke(
            null,
            new object[] { positions, actualLines, actualColumns }) ?? -1);

        Assert.Equal(positions.Length, actualCount);
        Assert.Equal(expectedLines, actualLines);
        Assert.Equal(expectedColumns, actualColumns);

        var checksumLines = new int[positions.Length];
        var checksumColumns = new int[positions.Length];
        var actualChecksum = (int)(cliQueryPositionChecksumInto.Invoke(
            null,
            new object[] { positions, checksumLines, checksumColumns }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedLines, checksumLines);
        Assert.Equal(expectedColumns, checksumColumns);
    }

    private static bool TryParseCliPositionWithSplit(string position, out int line, out int column)
    {
        line = 0;
        column = 0;
        var parts = position.Split(':');
        if (parts.Length != 2)
            return false;

        return int.TryParse(parts[0], out line) && int.TryParse(parts[1], out column);
    }

    private static void AssertCliBuildOperandsLikeProduction(
        MethodInfo cliBuildOperandIndicesInto,
        MethodInfo cliBuildOperandSummaryInto,
        MethodInfo cliBuildFirstOperandIndexInto)
    {
        var cases = new[]
        {
            new[]
            {
                "--release",
                "--verbose",
                "--timings",
                "--perf-report",
                "--aot",
                "--output",
                "dist",
                "-o",
                "bin/out",
                "--backend",
                "il",
                "--project",
                "samples/demo",
                "Program.nl"
            },
            new[] { "--output", "--release", "Program.nl" },
            new[] { "--output", "--backend", "il", "Program.nl" },
            new[] { "--project" },
            new[] { "--backend", "il", "--project", "samples/demo" },
            new[] { "Program.nl", "--release", "--backend", "il", "Extra.nl" },
            Array.Empty<string>()
        };

        foreach (var args in cases)
        {
            var expected = CreateExpectedCliBuildOperandIndices(args);
            var kindIds = new int[args.Length];
            var nextIndices = new int[args.Length];
            var previousIndices = new int[args.Length];
            var nextOptionIndices = new int[args.Length];
            var resultIndices = new int[args.Length];
            var actualCount = (int)(cliBuildOperandIndicesInto.Invoke(
                null,
                new object[] { args, kindIds, nextIndices, previousIndices, nextOptionIndices, resultIndices }) ?? -1);

            Assert.Equal(expected.Length, actualCount);
            Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

            Array.Clear(kindIds);
            Array.Clear(nextIndices);
            Array.Clear(previousIndices);
            Array.Clear(nextOptionIndices);
            Array.Clear(resultIndices);
            var summaryCount = (int)(cliBuildOperandSummaryInto.Invoke(
                null,
                new object[] { args, kindIds, nextIndices, previousIndices, nextOptionIndices, resultIndices }) ?? -1);

            Assert.Equal(expected.Length, summaryCount);
            if (expected.Length == 0)
            {
                Assert.True(resultIndices.Length == 0 || resultIndices[0] == -1);
            }
            else
            {
                Assert.Equal(expected[0], resultIndices[0]);
            }

            Array.Clear(kindIds);
            Array.Clear(nextIndices);
            Array.Clear(previousIndices);
            Array.Clear(nextOptionIndices);
            Array.Clear(resultIndices);
            var firstOperandIndex = (int)(cliBuildFirstOperandIndexInto.Invoke(
                null,
                new object[] { args, kindIds, nextIndices, previousIndices, nextOptionIndices, resultIndices }) ?? -2);

            Assert.Equal(expected.Length == 0 ? -1 : expected[0], firstOperandIndex);
        }
    }

    private static int[] CreateExpectedCliBuildOperandIndices(string[] args)
    {
        var remaining = args
            .Select((arg, index) => (arg, index))
            .Where(entry => entry.arg is not "--release" and not "--verbose" and not "--timings" and not "--perf-report" and not "--aot")
            .ToArray();

        remaining = StripExpectedBuildOptionWithValue(remaining, "--output");
        remaining = StripExpectedBuildOptionWithValue(remaining, "-o");
        remaining = StripExpectedBuildOptionWithValue(remaining, "--backend");
        remaining = StripExpectedBuildOptionWithValue(remaining, "--project");
        return remaining.Select(entry => entry.index).ToArray();
    }

    private static (string arg, int index)[] StripExpectedBuildOptionWithValue(
        (string arg, int index)[] args,
        string flag)
    {
        var result = new List<(string arg, int index)>();
        for (var i = 0; i < args.Length; i++)
        {
            if (args[i].arg == flag && i + 1 < args.Length)
            {
                i++;
                continue;
            }

            result.Add(args[i]);
        }

        return result.ToArray();
    }

    private static void AssertCliExportCSharpInputOperandLikeProduction(
        MethodInfo cliExportCSharpFirstOperandIndexInto,
        MethodInfo cliExportCSharpFirstOperandChecksumInto)
    {
        var cases = new[]
        {
            new[] { "Program.nl" },
            new[] { "--output", "dist", "Program.nl" },
            new[] { "-o", "bin/out", "--project", "samples/demo", "Program.nl" },
            new[] { "--project", "samples/demo" },
            new[] { "--project" },
            new[] { "--unknown", "value-after-unknown" },
            new[] { "-o", "--output", "file" },
            new[] { "--output", "-o", "file" },
            new[] { "--project", "--output", "file" },
            new[] { "--output", "--project", "file" },
            new[] { string.Empty, "--project", "samples/demo" },
            Array.Empty<string>()
        };

        foreach (var args in cases)
        {
            var expected = CreateExpectedCliExportCSharpInputOperandIndex(args);
            var expectedChecksum = ChecksumCliExportCSharpInputOperand(args, expected);
            var kindIds = new int[args.Length];
            var nextIndices = new int[args.Length];
            var previousIndices = new int[args.Length];
            var nextOptionIndices = new int[args.Length];
            var resultIndices = new int[args.Length];
            var actualChecksum = (int)(cliExportCSharpFirstOperandChecksumInto.Invoke(
                null,
                new object[] { args, kindIds, nextIndices, previousIndices, nextOptionIndices, resultIndices }) ?? -3);

            Assert.Equal(expectedChecksum, actualChecksum);

            Array.Clear(kindIds);
            Array.Clear(nextIndices);
            Array.Clear(previousIndices);
            Array.Clear(nextOptionIndices);
            Array.Clear(resultIndices);
            var actual = (int)(cliExportCSharpFirstOperandIndexInto.Invoke(
                null,
                new object[] { args, kindIds, nextIndices, previousIndices, nextOptionIndices, resultIndices }) ?? -3);

            Assert.Equal(expected, actual);
        }
    }

    private static int CreateExpectedCliExportCSharpInputOperandIndex(string[] args)
    {
        var remaining = args
            .Select((arg, index) => (arg, index))
            .ToArray();

        remaining = StripExpectedBuildOptionWithValue(remaining, "--output");
        remaining = StripExpectedBuildOptionWithValue(remaining, "-o");
        remaining = StripExpectedBuildOptionWithValue(remaining, "--project");

        foreach (var (arg, index) in remaining)
        {
            if (!arg.StartsWith("-", StringComparison.Ordinal))
                return index;
        }

        return -1;
    }

    private static int ChecksumCliExportCSharpInputOperand(string[] args, int sourceIndex)
    {
        var checksum = sourceIndex + 1;
        if (sourceIndex < 0)
            return checksum;

        var arg = args[sourceIndex];
        checksum += arg.Length * 31;
        for (var i = 0; i < arg.Length; i++)
        {
            checksum += arg[i] * (i + 1);
        }

        return checksum;
    }

    private static void AssertCliPositionalArgsLikeProduction(
        MethodInfo cliPositionalArgIndicesInto,
        MethodInfo cliFirstPositionalArgIndex,
        MethodInfo cliPositionalArgChecksumInto)
    {
        var args = new[]
        {
            "src/App.nl",
            "--project",
            "samples/demo",
            "--check",
            "--unknown",
            "README.md",
            "--output",
            "dist",
            "-o",
            "bin/out",
            "--stdin",
            string.Empty,
            "examples/hello.nl",
            "--backend",
            "il",
            "--verify-no-changes",
            "tests/fixture.nl",
            "--diff",
            "--verbose",
            "relative/path.nl",
            "-x",
            "value-after-unknown",
            "help",
            "--"
        };
        var optionsWithValues = new[] { "--project", "--output", "-o", "--backend" };
        var expected = CreateExpectedCliPositionalArgIndices(args, optionsWithValues);
        var expectedChecksum = expected.Length;
        for (var i = 0; i < expected.Length; i++)
        {
            var sourceIndex = expected[i];
            expectedChecksum += (i + 1) * 97 + (sourceIndex + 1) * 31 + args[sourceIndex].Length * 17;
        }

        var checksumResultIndices = new int[args.Length];
        var actualChecksum = (int)(cliPositionalArgChecksumInto.Invoke(
            null,
            new object[] { args, optionsWithValues, checksumResultIndices }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length));

        var resultIndices = new int[args.Length];
        var actualCount = (int)(cliPositionalArgIndicesInto.Invoke(
            null,
            new object[] { args, optionsWithValues, resultIndices }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount));

        var firstArgCases = new[]
        {
            args,
            new[] { "--project", "samples/demo", "--check", "src/App.nl" },
            new[] { "--project" },
            new[] { "--unknown", "value-after-unknown" },
            new[] { "--stdin", string.Empty, "Program.nl" },
            Array.Empty<string>()
        };

        foreach (var firstArgCase in firstArgCases)
        {
            var expectedFirst = CreateExpectedFirstCliPositionalArgIndex(firstArgCase, optionsWithValues);
            var actualFirst = (int)(cliFirstPositionalArgIndex.Invoke(
                null,
                new object[] { firstArgCase, optionsWithValues }) ?? -2);

            Assert.Equal(expectedFirst, actualFirst);
        }
    }

    private static int[] CreateExpectedCliPositionalArgIndices(
        string[] args,
        string[] optionsWithValues)
    {
        var positional = new List<int>();
        var options = new HashSet<string>(optionsWithValues, StringComparer.Ordinal);

        for (var i = 0; i < args.Length; i++)
        {
            if (options.Contains(args[i]))
            {
                i++;
                continue;
            }

            if (args[i] is "--check" or "--verify-no-changes" or "--diff" or "--stdin" or "--verbose")
                continue;

            if (!args[i].StartsWith("-", StringComparison.Ordinal))
                positional.Add(i);
        }

        return positional.ToArray();
    }

    private static int CreateExpectedFirstCliPositionalArgIndex(
        string[] args,
        string[] optionsWithValues)
    {
        var options = new HashSet<string>(optionsWithValues, StringComparer.Ordinal);

        for (var i = 0; i < args.Length; i++)
        {
            if (options.Contains(args[i]))
            {
                i++;
                continue;
            }

            if (args[i] is "--check" or "--verify-no-changes" or "--diff" or "--stdin" or "--verbose")
                continue;

            if (!args[i].StartsWith("-", StringComparison.Ordinal))
                return i;
        }

        return -1;
    }

    private static void AssertCliFixSafetyFilteringLikeProduction(
        MethodInfo cliFixSafetyFilterIndicesInto,
        MethodInfo cliFixSafetyFilterChecksumInto,
        MethodInfo cliFixEditFlattenIndicesInto,
        MethodInfo cliFixEditFlattenChecksumInto,
        MethodInfo cliFixSkippedIndicesInto,
        MethodInfo cliFixSkippedChecksumInto)
    {
        var safetyRanks = new[]
        {
            1,
            2,
            3,
            1,
            0,
            2,
            3,
            1,
            2
        };

        foreach (var includeReviewNeeded in new[] { false, true })
        {
            var expected = CreateExpectedCliFixSafetyIndices(safetyRanks, includeReviewNeeded);
            var includeFlag = includeReviewNeeded ? 1 : 0;

            var actualIndices = new int[safetyRanks.Length];
            var actualCount = (int)(cliFixSafetyFilterIndicesInto.Invoke(
                null,
                new object[] { safetyRanks, includeFlag, actualIndices }) ?? -1);

            Assert.Equal(expected.Length, actualCount);
            Assert.Equal(expected, actualIndices.Take(actualCount).ToArray());

            var checksumIndices = new int[safetyRanks.Length];
            var actualChecksum = (int)(cliFixSafetyFilterChecksumInto.Invoke(
                null,
                new object[] { safetyRanks, includeFlag, checksumIndices }) ?? -1);
            var expectedChecksum = CliFixSafetyFilterChecksum(expected, safetyRanks);

            Assert.Equal(expectedChecksum, actualChecksum);
            Assert.Equal(expected, checksumIndices.Take(expected.Length).ToArray());

            var expectedSkipped = CreateExpectedCliFixSkippedIndices(safetyRanks, includeReviewNeeded);
            var actualSkippedIndices = new int[safetyRanks.Length];
            var actualSkippedCount = (int)(cliFixSkippedIndicesInto.Invoke(
                null,
                new object[] { safetyRanks, includeFlag, actualSkippedIndices }) ?? -1);

            Assert.Equal(expectedSkipped.Length, actualSkippedCount);
            Assert.Equal(expectedSkipped, actualSkippedIndices.Take(actualSkippedCount).ToArray());

            var skippedChecksumIndices = new int[safetyRanks.Length];
            var actualSkippedChecksum = (int)(cliFixSkippedChecksumInto.Invoke(
                null,
                new object[] { safetyRanks, includeFlag, skippedChecksumIndices }) ?? -1);
            var expectedSkippedChecksum = CliFixSafetyFilterChecksum(expectedSkipped, safetyRanks);

            Assert.Equal(expectedSkippedChecksum, actualSkippedChecksum);
            Assert.Equal(expectedSkipped, skippedChecksumIndices.Take(expectedSkipped.Length).ToArray());
        }

        AssertCliFixEditFlatteningLikeProduction(
            cliFixEditFlattenIndicesInto,
            cliFixEditFlattenChecksumInto);
    }

    private static void AssertCliFixAppliedFileGroupingLikeProduction(
        MethodInfo cliFixAppliedFileGroupsInto,
        MethodInfo cliFixAppliedFileGroupChecksumInto)
    {
        var files = new[]
        {
            "src/B.nl",
            "src/A.nl",
            "src/B.nl",
            "src/C.nl",
            "src/A.nl",
            "src/B.nl",
            "src/D.nl",
            "src/C.nl",
            "src/A.nl"
        };
        var ranksByFile = new Dictionary<string, int>(StringComparer.Ordinal);
        var fileRanks = new int[files.Length];
        for (var i = 0; i < files.Length; i++)
        {
            if (!ranksByFile.TryGetValue(files[i], out var rank))
            {
                rank = ranksByFile.Count + 1;
                ranksByFile.Add(files[i], rank);
            }

            fileRanks[i] = rank;
        }

        var expectedGroups = Enumerable.Range(0, files.Length)
            .GroupBy(i => files[i])
            .ToArray();
        var expectedRanks = expectedGroups
            .Select(group => ranksByFile[group.Key])
            .ToArray();
        var expectedStarts = new int[expectedGroups.Length];
        var expectedCounts = new int[expectedGroups.Length];
        var expectedIndices = new int[files.Length];
        var offset = 0;
        for (var groupIndex = 0; groupIndex < expectedGroups.Length; groupIndex++)
        {
            var members = expectedGroups[groupIndex].ToArray();
            expectedStarts[groupIndex] = offset;
            expectedCounts[groupIndex] = members.Length;
            Array.Copy(members, 0, expectedIndices, offset, members.Length);
            offset += members.Length;
        }

        var expectedChecksum = expectedGroups.Length;
        for (var groupIndex = 0; groupIndex < expectedGroups.Length; groupIndex++)
        {
            var rank = expectedRanks[groupIndex];
            var start = expectedStarts[groupIndex];
            var count = expectedCounts[groupIndex];
            expectedChecksum += (groupIndex + 1) * 97 + rank * 31 + (start + 1) * 17 + count * 13;

            for (var i = 0; i < count; i++)
            {
                var sourceIndex = expectedIndices[start + i];
                expectedChecksum += (sourceIndex + 1) * 11 + fileRanks[sourceIndex] * 7 + (i + 1) * 5;
            }
        }

        var checksumCountsByRank = new int[ranksByFile.Count + 1];
        var checksumOffsetsByRank = new int[ranksByFile.Count + 1];
        var checksumWriteOffsetsByRank = new int[ranksByFile.Count + 1];
        var checksumResultRanks = new int[files.Length];
        var checksumResultStarts = new int[files.Length];
        var checksumResultCounts = new int[files.Length];
        var checksumResultIndices = new int[files.Length];
        var actualChecksum = (int)(cliFixAppliedFileGroupChecksumInto.Invoke(
            null,
            new object[]
            {
                fileRanks,
                ranksByFile.Count,
                checksumCountsByRank,
                checksumOffsetsByRank,
                checksumWriteOffsetsByRank,
                checksumResultRanks,
                checksumResultStarts,
                checksumResultCounts,
                checksumResultIndices
            }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);

        var countsByRank = new int[ranksByFile.Count + 1];
        var offsetsByRank = new int[ranksByFile.Count + 1];
        var writeOffsetsByRank = new int[ranksByFile.Count + 1];
        var resultRanks = new int[files.Length];
        var resultStarts = new int[files.Length];
        var resultCounts = new int[files.Length];
        var resultIndices = new int[files.Length];
        var actualGroupCount = (int)(cliFixAppliedFileGroupsInto.Invoke(
            null,
            new object[]
            {
                fileRanks,
                ranksByFile.Count,
                countsByRank,
                offsetsByRank,
                writeOffsetsByRank,
                resultRanks,
                resultStarts,
                resultCounts,
                resultIndices
            }) ?? -1);

        Assert.Equal(expectedGroups.Length, actualGroupCount);
        Assert.Equal(expectedRanks, resultRanks.Take(actualGroupCount).ToArray());
        Assert.Equal(expectedStarts, resultStarts.Take(actualGroupCount).ToArray());
        Assert.Equal(expectedCounts, resultCounts.Take(actualGroupCount).ToArray());
        Assert.Equal(expectedIndices, resultIndices);
    }

    private static void AssertCliUnifiedDiffHunkRangesLikeProduction(
        MethodInfo cliUnifiedDiffHunkRangesInto,
        MethodInfo cliUnifiedDiffHunkRangeChecksumInto)
    {
        var kindIds = new[]
        {
            0, 0, 2, 1, 0, 0, 0, 0, 2, 0, 1, 1, 0, 0, 0, 2, 2, 1, 0
        };
        var oldLines = new int[kindIds.Length];
        var newLines = new int[kindIds.Length];
        var oldLine = 1;
        var newLine = 1;
        for (var i = 0; i < kindIds.Length; i++)
        {
            if (kindIds[i] == 1)
            {
                oldLines[i] = oldLine;
                newLines[i] = newLine;
                newLine++;
            }
            else if (kindIds[i] == 2)
            {
                oldLines[i] = oldLine;
                newLines[i] = newLine;
                oldLine++;
            }
            else
            {
                oldLines[i] = oldLine;
                newLines[i] = newLine;
                oldLine++;
                newLine++;
            }
        }

        const int ContextLines = 1;
        var expected = CreateExpectedCliUnifiedDiffHunkRanges(kindIds, oldLines, newLines, ContextLines);
        var expectedChecksum = CliUnifiedDiffHunkRangeChecksum(expected);

        var starts = new int[kindIds.Length];
        var lengths = new int[kindIds.Length];
        var oldStarts = new int[kindIds.Length];
        var oldCounts = new int[kindIds.Length];
        var newStarts = new int[kindIds.Length];
        var newCounts = new int[kindIds.Length];
        var actualCount = (int)(cliUnifiedDiffHunkRangesInto.Invoke(
            null,
            new object[]
            {
                kindIds,
                oldLines,
                newLines,
                ContextLines,
                starts,
                lengths,
                oldStarts,
                oldCounts,
                newStarts,
                newCounts
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected.Select(range => range.Start), starts.Take(actualCount));
        Assert.Equal(expected.Select(range => range.Length), lengths.Take(actualCount));
        Assert.Equal(expected.Select(range => range.OldStart), oldStarts.Take(actualCount));
        Assert.Equal(expected.Select(range => range.OldCount), oldCounts.Take(actualCount));
        Assert.Equal(expected.Select(range => range.NewStart), newStarts.Take(actualCount));
        Assert.Equal(expected.Select(range => range.NewCount), newCounts.Take(actualCount));

        Array.Clear(starts);
        Array.Clear(lengths);
        Array.Clear(oldStarts);
        Array.Clear(oldCounts);
        Array.Clear(newStarts);
        Array.Clear(newCounts);
        var actualChecksum = (int)(cliUnifiedDiffHunkRangeChecksumInto.Invoke(
            null,
            new object[]
            {
                kindIds,
                oldLines,
                newLines,
                ContextLines,
                starts,
                lengths,
                oldStarts,
                oldCounts,
                newStarts,
                newCounts
            }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected.Select(range => range.Start), starts.Take(expected.Length));
        Assert.Equal(expected.Select(range => range.Length), lengths.Take(expected.Length));
        Assert.Equal(expected.Select(range => range.OldStart), oldStarts.Take(expected.Length));
        Assert.Equal(expected.Select(range => range.OldCount), oldCounts.Take(expected.Length));
        Assert.Equal(expected.Select(range => range.NewStart), newStarts.Take(expected.Length));
        Assert.Equal(expected.Select(range => range.NewCount), newCounts.Take(expected.Length));

        var tooSmallStarts = new int[kindIds.Length - 1];
        var failedCount = (int)(cliUnifiedDiffHunkRangesInto.Invoke(
            null,
            new object[]
            {
                kindIds,
                oldLines,
                newLines,
                ContextLines,
                tooSmallStarts,
                new int[kindIds.Length],
                new int[kindIds.Length],
                new int[kindIds.Length],
                new int[kindIds.Length],
                new int[kindIds.Length]
            }) ?? 0);

        Assert.Equal(-1, failedCount);
    }

    private static (int Start, int Length, int OldStart, int OldCount, int NewStart, int NewCount)[]
        CreateExpectedCliUnifiedDiffHunkRanges(
            int[] kindIds,
            int[] oldLines,
            int[] newLines,
            int contextLines)
    {
        var ranges = new List<(int Start, int End)>();
        var rangeStart = -1;
        var rangeEnd = -1;
        for (var i = 0; i < kindIds.Length; i++)
        {
            if (kindIds[i] == 0)
                continue;

            var nextStart = Math.Max(0, i - contextLines);
            var nextEnd = Math.Min(kindIds.Length - 1, i + contextLines);
            if (rangeStart < 0)
            {
                rangeStart = nextStart;
                rangeEnd = nextEnd;
            }
            else if (nextStart <= rangeEnd + 1)
            {
                rangeEnd = Math.Max(rangeEnd, nextEnd);
            }
            else
            {
                ranges.Add((rangeStart, rangeEnd));
                rangeStart = nextStart;
                rangeEnd = nextEnd;
            }
        }

        if (rangeStart >= 0)
            ranges.Add((rangeStart, rangeEnd));

        return ranges
            .Select(range =>
            {
                var oldStart = 0;
                var newStart = 0;
                var oldCount = 0;
                var newCount = 0;
                for (var i = range.Start; i <= range.End; i++)
                {
                    if (oldStart == 0 && oldLines[i] > 0)
                        oldStart = oldLines[i];
                    if (newStart == 0 && newLines[i] > 0)
                        newStart = newLines[i];
                    if (kindIds[i] != 1)
                        oldCount++;
                    if (kindIds[i] != 2)
                        newCount++;
                }

                if (oldStart == 0)
                    oldStart = 1;
                if (newStart == 0)
                    newStart = 1;

                return (
                    range.Start,
                    range.End - range.Start + 1,
                    oldStart,
                    oldCount,
                    newStart,
                    newCount);
            })
            .ToArray();
    }

    private static int CliUnifiedDiffHunkRangeChecksum(
        (int Start, int Length, int OldStart, int OldCount, int NewStart, int NewCount)[] ranges)
    {
        var checksum = ranges.Length;
        for (var i = 0; i < ranges.Length; i++)
        {
            checksum += (i + 1) * 97
                + (ranges[i].Start + 1) * 31
                + ranges[i].Length * 17
                + ranges[i].OldStart * 13
                + ranges[i].OldCount * 11
                + ranges[i].NewStart * 7
                + ranges[i].NewCount * 5;
        }

        return checksum;
    }

    private static void AssertCliFixEditFlatteningLikeProduction(
        MethodInfo cliFixEditFlattenIndicesInto,
        MethodInfo cliFixEditFlattenChecksumInto)
    {
        var editCounts = new[]
        {
            1,
            0,
            3,
            8,
            9,
            2
        };
        var expected = CreateExpectedCliFixEditPairs(editCounts);

        var actionIndices = new int[expected.Length];
        var editIndices = new int[expected.Length];
        var actualCount = (int)(cliFixEditFlattenIndicesInto.Invoke(
            null,
            new object[] { editCounts, actionIndices, editIndices }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected.Select(pair => pair.ActionIndex), actionIndices.Take(actualCount));
        Assert.Equal(expected.Select(pair => pair.EditIndex), editIndices.Take(actualCount));

        Array.Clear(actionIndices);
        Array.Clear(editIndices);
        var actualChecksum = (int)(cliFixEditFlattenChecksumInto.Invoke(
            null,
            new object[] { editCounts, actionIndices, editIndices }) ?? -1);

        Assert.Equal(CliFixEditFlattenChecksum(expected, editCounts), actualChecksum);
        Assert.Equal(expected.Select(pair => pair.ActionIndex), actionIndices.Take(expected.Length));
        Assert.Equal(expected.Select(pair => pair.EditIndex), editIndices.Take(expected.Length));

        var tooSmallActions = new int[expected.Length - 1];
        var tooSmallEdits = new int[expected.Length];
        var failedCount = (int)(cliFixEditFlattenIndicesInto.Invoke(
            null,
            new object[] { editCounts, tooSmallActions, tooSmallEdits }) ?? 0);

        Assert.Equal(-1, failedCount);
    }

    private static (int ActionIndex, int EditIndex)[] CreateExpectedCliFixEditPairs(int[] editCounts)
    {
        var expected = new List<(int ActionIndex, int EditIndex)>();
        for (var actionIndex = 0; actionIndex < editCounts.Length; actionIndex++)
        {
            for (var editIndex = 0; editIndex < editCounts[actionIndex]; editIndex++)
            {
                expected.Add((actionIndex, editIndex));
            }
        }

        return expected.ToArray();
    }

    private static int CliFixEditFlattenChecksum(
        (int ActionIndex, int EditIndex)[] pairs,
        int[] editCounts)
    {
        var checksum = pairs.Length;
        for (var i = 0; i < pairs.Length; i++)
        {
            var (actionIndex, editIndex) = pairs[i];
            checksum += (i + 1) * 97
                + (actionIndex + 1) * 31
                + (editIndex + 1) * 17
                + editCounts[actionIndex] * 13;
        }

        return checksum;
    }

    private static int[] CreateExpectedCliFixSafetyIndices(int[] safetyRanks, bool includeReviewNeeded)
    {
        var maxAppliedRank = includeReviewNeeded ? 2 : 1;
        return safetyRanks
            .Select((rank, index) => (rank, index))
            .Where(item => item.rank > 0 && item.rank <= maxAppliedRank)
            .Select(item => item.index)
            .ToArray();
    }

    private static int[] CreateExpectedCliFixSkippedIndices(int[] safetyRanks, bool includeReviewNeeded)
    {
        var maxAppliedRank = includeReviewNeeded ? 2 : 1;
        return safetyRanks
            .Select((rank, index) => (rank, index))
            .Where(item => item.rank == 0 || item.rank > maxAppliedRank)
            .Select(item => item.index)
            .ToArray();
    }

    private static int CliFixSafetyFilterChecksum(int[] orderedIndices, int[] safetyRanks)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97 + (index + 1) * 31 + safetyRanks[index] * 17;
        }

        return checksum;
    }

    private static void AssertCliCleanArtifactDirectoryOrderingLikeProduction(
        MethodInfo cliCleanArtifactDirectoryIndicesInto,
        MethodInfo cliCleanArtifactDirectoryChecksumInto)
    {
        var kindRanks = new[]
        {
            1, 2, 0, 3, 1, 2, 1, 3, 2, 1
        };
        var nodeModuleFlags = new[]
        {
            0, 0, 0, 0, 1, 0, 0, 0, 0, 0
        };
        var pathRanks = new[]
        {
            1, 2, 3, 4, 5, 6, 1, 7, 8, 9
        };
        var pathLengths = new[]
        {
            30, 35, 20, 42, 50, 25, 30, 42, 35, 10
        };
        var expected = new[] { 3, 7, 1, 8, 0, 5, 9 };

        var resultIndices = new int[kindRanks.Length];
        var actualCount = (int)(cliCleanArtifactDirectoryIndicesInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nodeModuleFlags,
                pathRanks,
                pathLengths,
                new int[pathRanks.Max() + 1],
                new int[pathLengths.Max() + 1],
                new int[pathLengths.Max() + 1],
                new int[kindRanks.Length],
                resultIndices
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

        var checksumResultIndices = new int[kindRanks.Length];
        var actualChecksum = (int)(cliCleanArtifactDirectoryChecksumInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nodeModuleFlags,
                pathRanks,
                pathLengths,
                new int[pathRanks.Max() + 1],
                new int[pathLengths.Max() + 1],
                new int[pathLengths.Max() + 1],
                new int[kindRanks.Length],
                checksumResultIndices
            }) ?? -1);
        var expectedChecksum = CliCleanArtifactDirectoryChecksum(expected, kindRanks, pathRanks, pathLengths);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
    }

    private static int CliCleanArtifactDirectoryChecksum(
        int[] orderedIndices,
        int[] kindRanks,
        int[] pathRanks,
        int[] pathLengths)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97
                + (index + 1) * 31
                + kindRanks[index] * 17
                + pathRanks[index] * 13
                + pathLengths[index] * 7;
        }

        return checksum;
    }

    private static void AssertCliUpdateTargetNuGetDependencyFilteringLikeProduction(
        MethodInfo cliUpdateTargetNuGetDependencyIndicesInto,
        MethodInfo cliUpdateTargetNuGetDependencyChecksumInto)
    {
        var nameRanks = new[]
        {
            1, 0, 2, 1, 0, 3, 2, 0
        };
        var cases = new[]
        {
            (TargetNameRank: 1, Expected: new[] { 0, 3 }),
            (TargetNameRank: 2, Expected: new[] { 2, 6 }),
            (TargetNameRank: -1, Expected: Array.Empty<int>()),
            (TargetNameRank: 0, Expected: Array.Empty<int>())
        };

        foreach (var (targetNameRank, expected) in cases)
        {
            var resultIndices = new int[nameRanks.Length];
            var actualCount = (int)(cliUpdateTargetNuGetDependencyIndicesInto.Invoke(
                null,
                new object[] { nameRanks, targetNameRank, resultIndices }) ?? -1);

            Assert.Equal(expected.Length, actualCount);
            Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

            var checksumResultIndices = new int[nameRanks.Length];
            var actualChecksum = (int)(cliUpdateTargetNuGetDependencyChecksumInto.Invoke(
                null,
                new object[] { nameRanks, targetNameRank, checksumResultIndices }) ?? -1);
            var expectedChecksum = CliUpdateTargetNuGetDependencyChecksum(expected, nameRanks);

            Assert.Equal(expectedChecksum, actualChecksum);
            Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
        }
    }

    private static void AssertCliUpdateAllNuGetDependencyFilteringLikeProduction(
        MethodInfo cliUpdateAllNuGetDependencyIndicesInto,
        MethodInfo cliUpdateAllNuGetDependencyChecksumInto)
    {
        var nugetFlags = new[]
        {
            1, 0, 1, 1, 0, 0, 1, 0
        };
        var expected = new[] { 0, 2, 3, 6 };

        var resultIndices = new int[nugetFlags.Length];
        var actualCount = (int)(cliUpdateAllNuGetDependencyIndicesInto.Invoke(
            null,
            new object[] { nugetFlags, resultIndices }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

        var checksumResultIndices = new int[nugetFlags.Length];
        var actualChecksum = (int)(cliUpdateAllNuGetDependencyChecksumInto.Invoke(
            null,
            new object[] { nugetFlags, checksumResultIndices }) ?? -1);
        var expectedChecksum = CliUpdateAllNuGetDependencyChecksum(expected, nugetFlags);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
    }

    private static int CliUpdateAllNuGetDependencyChecksum(
        int[] orderedIndices,
        int[] nugetFlags)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97
                + (index + 1) * 31
                + nugetFlags[index] * 17;
        }

        return checksum;
    }

    private static int CliUpdateTargetNuGetDependencyChecksum(
        int[] orderedIndices,
        int[] nameRanks)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97
                + (index + 1) * 31
                + 17
                + nameRanks[index] * 13;
        }

        return checksum;
    }

    private static void AssertCliReferenceTypeFilteringLikeProduction(
        MethodInfo cliReferenceTypeFilterIndicesInto,
        MethodInfo cliReferenceTypeFilterChecksumInto)
    {
        var typeRanks = new[]
        {
            1, 3, 2, 4, 1, 0, 4, 2, 3, 1
        };
        var cases = new[]
        {
            (TargetTypeRank: 1, Expected: new[] { 0, 4, 9 }),
            (TargetTypeRank: 2, Expected: new[] { 2, 7 }),
            (TargetTypeRank: 3, Expected: new[] { 1, 8 }),
            (TargetTypeRank: 4, Expected: new[] { 3, 6 }),
            (TargetTypeRank: 0, Expected: Array.Empty<int>()),
            (TargetTypeRank: -1, Expected: Array.Empty<int>()),
            (TargetTypeRank: 99, Expected: Array.Empty<int>())
        };

        foreach (var (targetTypeRank, expected) in cases)
        {
            var resultIndices = new int[typeRanks.Length];
            var actualCount = (int)(cliReferenceTypeFilterIndicesInto.Invoke(
                null,
                new object[] { typeRanks, targetTypeRank, resultIndices }) ?? -1);

            Assert.Equal(expected.Length, actualCount);
            Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

            var checksumResultIndices = new int[typeRanks.Length];
            var actualChecksum = (int)(cliReferenceTypeFilterChecksumInto.Invoke(
                null,
                new object[] { typeRanks, targetTypeRank, checksumResultIndices }) ?? -1);
            var expectedChecksum = CliReferenceTypeFilterChecksum(expected, typeRanks);

            Assert.Equal(expectedChecksum, actualChecksum);
            Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
        }
    }

    private static int CliReferenceTypeFilterChecksum(
        int[] orderedIndices,
        int[] typeRanks)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97
                + (index + 1) * 31
                + typeRanks[index] * 17;
        }

        return checksum;
    }

    private static void AssertCliSymbolNameGlobFilteringLikeProduction(
        MethodInfo cliSymbolNameGlobFilterIndicesInto)
    {
        var names = new[]
        {
            "UserService",
            "OrderService",
            "UserQuery",
            "RenderPipeline",
            "CurrentUser",
            "DataSet",
            "DataQuerySet",
            "BuildGraph",
            "queryRunner",
            "USER_INDEX"
        };
        var cases = new[]
        {
            (Pattern: "*Service", Limit: 200),
            (Pattern: "User*", Limit: 200),
            (Pattern: "*Query*", Limit: 200),
            (Pattern: "Data*Set", Limit: 200),
            (Pattern: "*", Limit: 3),
            (Pattern: "No*Match", Limit: 200)
        };

        foreach (var (pattern, limit) in cases)
        {
            var expectedIndices = ExpectedCliSymbolNameGlobFilterIndices(names, pattern, limit);
            var actualIndices = new int[Math.Min(limit, names.Length)];
            var actualCount = (int)(cliSymbolNameGlobFilterIndicesInto.Invoke(
                null,
                new object[] { names, pattern, limit, actualIndices }) ?? -1);

            Assert.Equal(expectedIndices.Length, actualCount);
            Assert.Equal(expectedIndices, actualIndices.Take(actualCount).ToArray());
        }
    }

    private static int[] ExpectedCliSymbolNameGlobFilterIndices(
        string[] names,
        string pattern,
        int limit)
    {
        var regex = BuildCliSymbolNameFilterRegex(pattern);
        return names
            .Select((name, index) => (name, index))
            .Where(item => regex.IsMatch(item.name))
            .Take(limit)
            .Select(item => item.index)
            .ToArray();
    }

    private static Regex BuildCliSymbolNameFilterRegex(string pattern)
    {
        if (pattern.Contains('*'))
        {
            var regexPattern = "^" + Regex.Escape(pattern).Replace("\\*", ".*") + "$";
            return new Regex(regexPattern, RegexOptions.IgnoreCase, TimeSpan.FromMilliseconds(200));
        }

        return new Regex(Regex.Escape(pattern), RegexOptions.IgnoreCase, TimeSpan.FromMilliseconds(200));
    }

    private static void AssertCliDocSymbolOrderingLikeProduction(
        MethodInfo cliDocSymbolOrderCountingIndicesInto,
        MethodInfo cliDocSymbolOrderCountingChecksumInto)
    {
        var symbols = new[]
        {
            (Kind: SymbolKind.Method, Name: "zeta"),
            (Kind: SymbolKind.Function, Name: "alpha"),
            (Kind: SymbolKind.Variable, Name: "ignoredVariable"),
            (Kind: SymbolKind.Class, Name: "Customer"),
            (Kind: SymbolKind.Parameter, Name: "ignoredParameter"),
            (Kind: SymbolKind.Function, Name: "alpha"),
            (Kind: SymbolKind.Enum, Name: "OrderState"),
            (Kind: SymbolKind.Property, Name: "Name"),
            (Kind: SymbolKind.Method, Name: "alpha"),
            (Kind: SymbolKind.TypeAlias, Name: "Amount"),
            (Kind: SymbolKind.Class, Name: "Account")
        };
        var expected = symbols
            .Select((symbol, index) => (symbol.Kind, symbol.Name, Index: index))
            .Where(symbol => symbol.Kind is not SymbolKind.Variable and not SymbolKind.Parameter)
            .OrderBy(symbol => symbol.Kind.ToString(), StringComparer.Ordinal)
            .ThenBy(symbol => symbol.Name, StringComparer.Ordinal)
            .Select(symbol => symbol.Index)
            .ToArray();

        var kindRanks = new int[symbols.Length];
        var nameRanks = new int[symbols.Length];
        var includeFlags = new int[symbols.Length];
        var nameRankMap = symbols
            .Select(symbol => symbol.Name)
            .Distinct(StringComparer.Ordinal)
            .OrderBy(name => name, StringComparer.Ordinal)
            .Select((name, index) => (name, rank: index + 1))
            .ToDictionary(item => item.name, item => item.rank, StringComparer.Ordinal);
        var kindRankMap = Enum.GetValues<SymbolKind>()
            .OrderBy(kind => kind.ToString(), StringComparer.Ordinal)
            .Select((kind, index) => (kind, rank: index + 1))
            .ToDictionary(item => item.kind, item => item.rank);

        for (var i = 0; i < symbols.Length; i++)
        {
            kindRanks[i] = kindRankMap[symbols[i].Kind];
            nameRanks[i] = nameRankMap[symbols[i].Name];
            includeFlags[i] = symbols[i].Kind is SymbolKind.Variable or SymbolKind.Parameter ? 0 : 1;
        }

        var resultIndices = new int[symbols.Length];
        var tempIndices = new int[symbols.Length];
        var actualCount = (int)(cliDocSymbolOrderCountingIndicesInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nameRanks,
                includeFlags,
                new int[symbols.Length + 1],
                new int[symbols.Length + 1],
                new int[32],
                new int[32],
                tempIndices,
                resultIndices
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

        var checksumResultIndices = new int[symbols.Length];
        var actualChecksum = (int)(cliDocSymbolOrderCountingChecksumInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nameRanks,
                includeFlags,
                new int[symbols.Length + 1],
                new int[symbols.Length + 1],
                new int[32],
                new int[32],
                new int[symbols.Length],
                checksumResultIndices
            }) ?? -1);
        var expectedChecksum = CliDocSymbolOrderChecksum(expected, kindRanks, nameRanks);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
    }

    private static int CliDocSymbolOrderChecksum(
        IReadOnlyList<int> orderedIndices,
        int[] kindRanks,
        int[] nameRanks)
    {
        var checksum = orderedIndices.Count;
        for (var i = 0; i < orderedIndices.Count; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97 + (index + 1) * 31 + kindRanks[index] * 17 + nameRanks[index] * 13;
        }

        return checksum;
    }

    private static void AssertCliDocMemberOrderingLikeProduction(
        MethodInfo cliDocSymbolOrderCountingIndicesInto,
        MethodInfo cliDocSymbolOrderCountingChecksumInto)
    {
        var members = new[]
        {
            (Kind: SymbolKind.Method, Name: "zeta"),
            (Kind: SymbolKind.Function, Name: "alpha"),
            (Kind: SymbolKind.Variable, Name: "value"),
            (Kind: SymbolKind.Parameter, Name: "customer"),
            (Kind: SymbolKind.Class, Name: "Customer"),
            (Kind: SymbolKind.Property, Name: "Name"),
            (Kind: SymbolKind.Method, Name: "alpha"),
            (Kind: SymbolKind.Field, Name: "Amount")
        };
        var expected = members
            .Select((member, index) => (member.Kind, member.Name, Index: index))
            .OrderBy(member => member.Kind.ToString(), StringComparer.Ordinal)
            .ThenBy(member => member.Name, StringComparer.Ordinal)
            .Select(member => member.Index)
            .ToArray();

        var kindRanks = new int[members.Length];
        var nameRanks = new int[members.Length];
        var includeFlags = Enumerable.Repeat(1, members.Length).ToArray();
        var nameRankMap = members
            .Select(member => member.Name)
            .Distinct(StringComparer.Ordinal)
            .OrderBy(name => name, StringComparer.Ordinal)
            .Select((name, index) => (name, rank: index + 1))
            .ToDictionary(item => item.name, item => item.rank, StringComparer.Ordinal);
        var kindRankMap = Enum.GetValues<SymbolKind>()
            .OrderBy(kind => kind.ToString(), StringComparer.Ordinal)
            .Select((kind, index) => (kind, rank: index + 1))
            .ToDictionary(item => item.kind, item => item.rank);

        for (var i = 0; i < members.Length; i++)
        {
            kindRanks[i] = kindRankMap[members[i].Kind];
            nameRanks[i] = nameRankMap[members[i].Name];
        }

        var resultIndices = new int[members.Length];
        var actualCount = (int)(cliDocSymbolOrderCountingIndicesInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nameRanks,
                includeFlags,
                new int[members.Length + 1],
                new int[members.Length + 1],
                new int[32],
                new int[32],
                new int[members.Length],
                resultIndices
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

        var checksumResultIndices = new int[members.Length];
        var actualChecksum = (int)(cliDocSymbolOrderCountingChecksumInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nameRanks,
                includeFlags,
                new int[members.Length + 1],
                new int[members.Length + 1],
                new int[32],
                new int[32],
                new int[members.Length],
                checksumResultIndices
            }) ?? -1);
        var expectedChecksum = CliDocSymbolOrderChecksum(expected, kindRanks, nameRanks);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
    }

    private static void AssertCliDocSlugsLikeProduction(MethodInfo cliDocSlugsInto)
    {
        var rawSlugs = new[]
        {
            "Class-Customer-/tmp/Customer.nl",
            "Method-GetById-Service.Core.nl",
            "TypeAlias-Result<T>-Errors.nl",
            "Function-R\u00e9sum\u00e9_Count-Reports 2026.nl",
            "Property-HTTPClient2-API.Client.nl"
        };
        var expectedSlugs = rawSlugs.Select(CreateExpectedCliDocSlug).ToArray();

        var directSlugs = new string[rawSlugs.Length];
        var directCount = (int)(cliDocSlugsInto.Invoke(
            null,
            new object[] { rawSlugs, directSlugs }) ?? -1);

        Assert.Equal(rawSlugs.Length, directCount);
        Assert.Equal(expectedSlugs, directSlugs);
    }

    private static string CreateExpectedCliDocSlug(string raw)
    {
        var chars = raw
            .ToLowerInvariant()
            .Select(ch => char.IsLetterOrDigit(ch) ? ch : '-')
            .ToArray();
        return string.Join(string.Empty, new string(chars).Split('-', StringSplitOptions.RemoveEmptyEntries));
    }

    private static void AssertCliTreeDependencyDeduplicationLikeProduction(
        MethodInfo cliTreeDependencyDeduplicateIndicesInto,
        MethodInfo cliTreeDependencyDeduplicateChecksumInto)
    {
        var dependencies = new[]
        {
            (Kind: "nuget", Name: "Serilog"),
            (Kind: "framework", Name: "Microsoft.AspNetCore.App"),
            (Kind: "nuget", Name: "serilog"),
            (Kind: "project", Name: "../Shared/Shared.csproj"),
            (Kind: "nuget", Name: "Newtonsoft.Json"),
            (Kind: "framework", Name: "microsoft.aspnetcore.app"),
            (Kind: "dll", Name: "Lib/Analyzers.dll"),
            (Kind: "nuget", Name: "System.Text.Json")
        };
        var firstIndices = new List<int>();
        for (var i = 0; i < dependencies.Length; i++)
        {
            var duplicate = false;
            for (var j = 0; j < i; j++)
            {
                if (string.Equals(dependencies[i].Kind, dependencies[j].Kind, StringComparison.Ordinal) &&
                    string.Equals(dependencies[i].Name, dependencies[j].Name, StringComparison.OrdinalIgnoreCase))
                {
                    duplicate = true;
                    break;
                }
            }

            if (!duplicate)
                firstIndices.Add(i);
        }

        var expected = firstIndices
            .OrderBy(index => dependencies[index].Kind, StringComparer.Ordinal)
            .ThenBy(index => dependencies[index].Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        var kindRanks = new int[dependencies.Length];
        var nameRanks = new int[dependencies.Length];
        var kindRankMap = dependencies
            .Select(dependency => dependency.Kind)
            .Distinct(StringComparer.Ordinal)
            .OrderBy(kind => kind, StringComparer.Ordinal)
            .Select((kind, index) => (kind, rank: index + 1))
            .ToDictionary(item => item.kind, item => item.rank, StringComparer.Ordinal);
        var nameRankMap = dependencies
            .Select(dependency => dependency.Name)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(name => name, StringComparer.OrdinalIgnoreCase)
            .Select((name, index) => (name, rank: index + 1))
            .ToDictionary(item => item.name, item => item.rank, StringComparer.OrdinalIgnoreCase);

        for (var i = 0; i < dependencies.Length; i++)
        {
            kindRanks[i] = kindRankMap[dependencies[i].Kind];
            nameRanks[i] = nameRankMap[dependencies[i].Name];
        }

        var resultIndices = new int[dependencies.Length];
        var actualCount = (int)(cliTreeDependencyDeduplicateIndicesInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nameRanks,
                new int[nameRankMap.Count + 1],
                new int[nameRankMap.Count + 1],
                new int[kindRankMap.Count + 1],
                new int[kindRankMap.Count + 1],
                new int[dependencies.Length],
                new int[dependencies.Length],
                resultIndices
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

        var checksumResultIndices = new int[dependencies.Length];
        var actualChecksum = (int)(cliTreeDependencyDeduplicateChecksumInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nameRanks,
                new int[nameRankMap.Count + 1],
                new int[nameRankMap.Count + 1],
                new int[kindRankMap.Count + 1],
                new int[kindRankMap.Count + 1],
                new int[dependencies.Length],
                new int[dependencies.Length],
                checksumResultIndices
            }) ?? -1);
        var expectedChecksum = CliDocSymbolOrderChecksum(expected, kindRanks, nameRanks);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
    }

    private static void AssertDocQueryBestTypeSelectionLikeProduction(
        MethodInfo docQueryBestTypeIndex,
        MethodInfo docQueryBestTypeChecksumInto)
    {
        var scores = new[] { 410, 2400, 900, 2400, 2400, 1300, 2400 };
        var namespaceLengths = new[] { 12, 6, 8, 6, 6, 4, 6 };
        var fullNames = new[]
        {
            "NSharpLang.Compiler.DocQuery",
            "System.ConsoleZ",
            "System.Text.StringBuilder",
            "System.ConsoleA",
            "system.consolea",
            "System.IO.File",
            "System.Collections.List"
        };
        var expected = Enumerable.Range(0, scores.Length)
            .OrderByDescending(i => scores[i])
            .ThenBy(i => namespaceLengths[i])
            .ThenBy(i => fullNames[i], StringComparer.OrdinalIgnoreCase)
            .First();

        var actual = (int)(docQueryBestTypeIndex.Invoke(
            null,
            new object[] { scores, namespaceLengths, fullNames, scores.Length }) ?? -1);

        Assert.Equal(expected, actual);

        var actualChecksum = (int)(docQueryBestTypeChecksumInto.Invoke(
            null,
            new object[] { scores, namespaceLengths, fullNames, scores.Length }) ?? -1);
        var expectedChecksum = (expected + 1) * 97 + scores[expected] * 31 + namespaceLengths[expected] * 17;

        Assert.Equal(expectedChecksum, actualChecksum);

        var empty = (int)(docQueryBestTypeIndex.Invoke(
            null,
            new object[] { scores, namespaceLengths, fullNames, 0 }) ?? 0);

        Assert.Equal(-1, empty);
    }

    private static void AssertDocQueryMemberOrderingLikeProduction(
        MethodInfo docQueryMemberOrderIndicesInto,
        MethodInfo docQueryMemberOrderChecksumInto)
    {
        var kinds = new[]
        {
            "method",
            "property",
            "constructor",
            "field",
            "event",
            "nested type",
            "method",
            "property",
            "method"
        };
        var names = new[]
        {
            "ToString",
            "Count",
            "Sample()",
            "value",
            "Changed",
            "Enumerator",
            "add",
            "count",
            "Add"
        };
        var kindRanks = kinds.Select(GetDocQueryMemberKindRank).ToArray();
        var sortedNames = names.ToArray();
        Array.Sort(sortedNames, StringComparer.OrdinalIgnoreCase);

        var nameRankMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var nextRank = 1;
        foreach (var name in sortedNames)
        {
            if (!nameRankMap.ContainsKey(name))
            {
                nameRankMap[name] = nextRank;
                nextRank++;
            }
        }

        var nameRanks = names.Select(name => nameRankMap[name]).ToArray();
        var expected = Enumerable.Range(0, names.Length)
            .OrderBy(i => kinds[i])
            .ThenBy(i => names[i], StringComparer.OrdinalIgnoreCase)
            .ToArray();

        var resultIndices = new int[names.Length];
        var actualCount = (int)(docQueryMemberOrderIndicesInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nameRanks,
                new int[nameRankMap.Count + 1],
                new int[nameRankMap.Count + 1],
                new int[16],
                new int[16],
                new int[names.Length],
                resultIndices
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

        var checksumResultIndices = new int[names.Length];
        var actualChecksum = (int)(docQueryMemberOrderChecksumInto.Invoke(
            null,
            new object[]
            {
                kindRanks,
                nameRanks,
                new int[nameRankMap.Count + 1],
                new int[nameRankMap.Count + 1],
                new int[16],
                new int[16],
                new int[names.Length],
                checksumResultIndices
            }) ?? -1);
        var expectedChecksum = CliDocSymbolOrderChecksum(expected, kindRanks, nameRanks);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
    }

    private static int GetDocQueryMemberKindRank(string kind) =>
        kind switch
        {
            "constructor" => 1,
            "event" => 2,
            "field" => 3,
            "method" => 4,
            "nested type" => 5,
            "property" => 6,
            _ => 0
        };

    private static void AssertTextEditOrderingLikeProduction(
        MethodInfo textEditOrderIndicesInto,
        MethodInfo textEditOrderChecksumInto)
    {
        var edits = new[]
        {
            new TextEdit(1, 0, 1, 0, "line1"),
            new TextEdit(3, 5, 3, 5, "line3-col5-first"),
            new TextEdit(3, 5, 3, 5, "line3-col5-second"),
            new TextEdit(2, 10, 2, 12, "line2"),
            new TextEdit(3, 3, 3, 4, "line3-col3"),
            new TextEdit(4, 1, 5, 0, "multiline")
        };
        var expected = edits
            .Select((edit, index) => (edit, index))
            .OrderByDescending(item => item.edit.StartLine)
            .ThenByDescending(item => item.edit.StartColumn)
            .ThenBy(item => item.edit.EndLine)
            .ThenBy(item => item.edit.EndColumn)
            .ThenByDescending(item => item.index)
            .Select(item => item.index)
            .ToArray();

        var startPositionRanks = BuildTextEditPositionRanks(
            edits,
            edit => (edit.StartLine, edit.StartColumn),
            out var startPositionRankCount);
        var endPositionRanks = BuildTextEditPositionRanks(
            edits,
            edit => (edit.EndLine, edit.EndColumn),
            out var endPositionRankCount);
        var bucketCapacity = Math.Max(startPositionRankCount, endPositionRankCount) + 1;

        var resultIndices = new int[edits.Length];
        var actualCount = (int)(textEditOrderIndicesInto.Invoke(
            null,
            new object[]
            {
                startPositionRanks,
                endPositionRanks,
                startPositionRankCount,
                endPositionRankCount,
                new int[bucketCapacity],
                new int[bucketCapacity],
                new int[edits.Length],
                resultIndices
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount).ToArray());

        var checksumResultIndices = new int[edits.Length];
        var actualChecksum = (int)(textEditOrderChecksumInto.Invoke(
            null,
            new object[]
            {
                startPositionRanks,
                endPositionRanks,
                startPositionRankCount,
                endPositionRankCount,
                new int[bucketCapacity],
                new int[bucketCapacity],
                new int[edits.Length],
                checksumResultIndices
            }) ?? -1);
        var expectedChecksum = TextEditOrderChecksum(
            expected,
            startPositionRanks,
            endPositionRanks);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length).ToArray());
    }

    private static int[] BuildTextEditPositionRanks(
        TextEdit[] edits,
        Func<TextEdit, (int Line, int Column)> selector,
        out int rankCount)
    {
        var rankMap = edits
            .Select(selector)
            .Distinct()
            .OrderBy(value => value)
            .Select((value, index) => (value, rank: index + 1))
            .ToDictionary(item => item.value, item => item.rank);
        var ranks = new int[edits.Length];
        for (var i = 0; i < edits.Length; i++)
        {
            ranks[i] = rankMap[selector(edits[i])];
        }

        rankCount = rankMap.Count;
        return ranks;
    }

    private static int TextEditOrderChecksum(
        int[] orderedIndices,
        int[] startPositionRanks,
        int[] endPositionRanks)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97 + (index + 1) * 31;
            checksum += startPositionRanks[index] * 17 + endPositionRanks[index] * 13;
        }

        return checksum;
    }

    private static void AssertTypoSuggestionsLikeProduction(
        MethodInfo typoSuggestionIndicesInto,
        MethodInfo typoSuggestionChecksumInto)
    {
        var candidates = new[]
        {
            "customer",
            "customerName",
            "orderTotal",
            "invoiceNumber",
            "StringBuilder",
            "DateTime",
            "ResolveSymbol",
            "LookupIdentifier",
            "WriteLine"
        };
        var typos = new[]
        {
            "custmer",
            "customerNmae",
            "ordrTotal",
            "StringBuiler",
            "DateTiem",
            "ResolveSymbl",
            "LookupIdentifer",
            "unknown"
        };
        var expectedStarts = new int[typos.Length];
        var expectedCounts = new int[typos.Length];
        var expectedIndices = new int[typos.Length * 3];
        var candidateIndices = candidates
            .Select((candidate, index) => (candidate, index))
            .ToDictionary(item => item.candidate, item => item.index, StringComparer.Ordinal);
        var suggester = new SmartSuggester(candidates.ToList());

        var writeIndex = 0;
        for (var i = 0; i < typos.Length; i++)
        {
            var suggestions = suggester.SuggestSimilarNames(typos[i], 3);
            expectedStarts[i] = writeIndex;
            expectedCounts[i] = suggestions.Count;
            foreach (var suggestion in suggestions)
            {
                expectedIndices[writeIndex] = candidateIndices[suggestion];
                writeIndex++;
            }
        }

        var maxCandidateLength = candidates.Max(candidate => candidate.Length);
        var previousDistances = new int[maxCandidateLength + 1];
        var currentDistances = new int[maxCandidateLength + 1];
        var actualStarts = new int[typos.Length];
        var actualCounts = new int[typos.Length];
        var actualIndices = new int[typos.Length * 3];
        var actualTotal = (int)(typoSuggestionIndicesInto.Invoke(
            null,
            new object[]
            {
                typos,
                candidates,
                3,
                previousDistances,
                currentDistances,
                actualStarts,
                actualCounts,
                actualIndices
            }) ?? -1);

        Assert.Equal(writeIndex, actualTotal);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedCounts, actualCounts);
        Assert.Equal(expectedIndices, actualIndices);

        var checksumStarts = new int[typos.Length];
        var checksumCounts = new int[typos.Length];
        var checksumIndices = new int[typos.Length * 3];
        var actualChecksum = (int)(typoSuggestionChecksumInto.Invoke(
            null,
            new object[]
            {
                typos,
                candidates,
                3,
                previousDistances,
                currentDistances,
                checksumStarts,
                checksumCounts,
                checksumIndices
            }) ?? -1);
        var expectedChecksum = TypoSuggestionChecksum(writeIndex, expectedStarts, expectedCounts, expectedIndices);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, checksumStarts);
        Assert.Equal(expectedCounts, checksumCounts);
        Assert.Equal(expectedIndices, checksumIndices);
    }

    private static int TypoSuggestionChecksum(
        int total,
        int[] starts,
        int[] counts,
        int[] indices)
    {
        var checksum = total;
        for (var i = 0; i < counts.Length; i++)
        {
            var start = starts[i];
            var count = counts[i];
            checksum += start * 7 + count * 97;
            for (var j = 0; j < count; j++)
            {
                checksum += indices[start + j] * 31 + (j + 1) * 17;
            }
        }

        return checksum;
    }

    private static void AssertAotRequirementGroupingLikeProduction(
        MethodInfo aotRequirementGroupsInto,
        MethodInfo aotRequirementGroupChecksumInto)
    {
        var declarationRanks = new[] { 1, 1, 0, 2, 1, 3, 2, 3, 2, 1 };
        var kindIds = new[] { 1, 2, 1, 3, 1, 2, 1, 0, 2, 3 };
        var constructRanks = new[] { 4, 2, 0, 5, 1, 3, 2, 4, 1, 5 };
        const int uniqueDeclarationCount = 3;
        const int uniqueConstructCount = 5;

        var expectedDeclarationRanks = new[] { 1, 2, 3 };
        var expectedRequiresUnreferenced = new[] { 1, 1, 0 };
        var expectedRequiresDynamic = new[] { 1, 1, 1 };
        var expectedConstructStarts = new[] { 0, 3, 6 };
        var expectedConstructCounts = new[] { 3, 3, 2 };
        var expectedConstructRanks = new[] { 1, 2, 4, 1, 2, 5, 3, 4, 0 };

        var declarationCounts = new int[uniqueDeclarationCount + 1];
        var requiresUnreferencedByRank = new int[uniqueDeclarationCount + 1];
        var requiresDynamicByRank = new int[uniqueDeclarationCount + 1];
        var constructSeen = new int[(uniqueDeclarationCount + 1) * (uniqueConstructCount + 1)];
        var resultDeclarationRanks = new int[uniqueDeclarationCount];
        var resultRequiresUnreferenced = new int[uniqueDeclarationCount];
        var resultRequiresDynamic = new int[uniqueDeclarationCount];
        var resultConstructStarts = new int[uniqueDeclarationCount];
        var resultConstructCounts = new int[uniqueDeclarationCount];
        var resultConstructRanks = new int[uniqueDeclarationCount * 3];
        var actualCount = (int)(aotRequirementGroupsInto.Invoke(
            null,
            new object[]
            {
                declarationRanks,
                kindIds,
                constructRanks,
                uniqueDeclarationCount,
                uniqueConstructCount,
                declarationCounts,
                requiresUnreferencedByRank,
                requiresDynamicByRank,
                constructSeen,
                resultDeclarationRanks,
                resultRequiresUnreferenced,
                resultRequiresDynamic,
                resultConstructStarts,
                resultConstructCounts,
                resultConstructRanks
            }) ?? -1);

        Assert.Equal(expectedDeclarationRanks.Length, actualCount);
        Assert.Equal(expectedDeclarationRanks, resultDeclarationRanks);
        Assert.Equal(expectedRequiresUnreferenced, resultRequiresUnreferenced);
        Assert.Equal(expectedRequiresDynamic, resultRequiresDynamic);
        Assert.Equal(expectedConstructStarts, resultConstructStarts);
        Assert.Equal(expectedConstructCounts, resultConstructCounts);
        Assert.Equal(expectedConstructRanks, resultConstructRanks);

        Array.Clear(declarationCounts);
        Array.Clear(requiresUnreferencedByRank);
        Array.Clear(requiresDynamicByRank);
        Array.Clear(constructSeen);
        Array.Clear(resultDeclarationRanks);
        Array.Clear(resultRequiresUnreferenced);
        Array.Clear(resultRequiresDynamic);
        Array.Clear(resultConstructStarts);
        Array.Clear(resultConstructCounts);
        Array.Clear(resultConstructRanks);
        var actualChecksum = (int)(aotRequirementGroupChecksumInto.Invoke(
            null,
            new object[]
            {
                declarationRanks,
                kindIds,
                constructRanks,
                uniqueDeclarationCount,
                uniqueConstructCount,
                declarationCounts,
                requiresUnreferencedByRank,
                requiresDynamicByRank,
                constructSeen,
                resultDeclarationRanks,
                resultRequiresUnreferenced,
                resultRequiresDynamic,
                resultConstructStarts,
                resultConstructCounts,
                resultConstructRanks
            }) ?? -1);

        Assert.Equal(
            AotRequirementGroupingChecksum(
                expectedDeclarationRanks,
                expectedRequiresUnreferenced,
                expectedRequiresDynamic,
                expectedConstructStarts,
                expectedConstructCounts,
                expectedConstructRanks),
            actualChecksum);
        Assert.Equal(expectedDeclarationRanks, resultDeclarationRanks);
        Assert.Equal(expectedRequiresUnreferenced, resultRequiresUnreferenced);
        Assert.Equal(expectedRequiresDynamic, resultRequiresDynamic);
        Assert.Equal(expectedConstructStarts, resultConstructStarts);
        Assert.Equal(expectedConstructCounts, resultConstructCounts);
        Assert.Equal(expectedConstructRanks, resultConstructRanks);
    }

    private static int AotRequirementGroupingChecksum(
        int[] declarationRanks,
        int[] requiresUnreferenced,
        int[] requiresDynamic,
        int[] constructStarts,
        int[] constructCounts,
        int[] constructRanks)
    {
        var checksum = declarationRanks.Length;
        for (var groupIndex = 0; groupIndex < declarationRanks.Length; groupIndex++)
        {
            var start = constructStarts[groupIndex];
            var count = constructCounts[groupIndex];
            checksum += (groupIndex + 1) * 97
                + declarationRanks[groupIndex] * 31
                + requiresUnreferenced[groupIndex] * 17
                + requiresDynamic[groupIndex] * 13
                + count * 7;

            for (var offset = 0; offset < count; offset++)
            {
                checksum += constructRanks[start + offset] * (offset + 1) * 11;
            }
        }

        return checksum;
    }

    private static void AssertCliBatchDuplicateIdsLikeProduction(
        MethodInfo cliBatchDuplicateIdRanksInto,
        MethodInfo cliBatchDuplicateIdRankChecksumInto)
    {
        var ids = new[]
        {
            "zeta",
            "alpha",
            string.Empty,
            "beta",
            "alpha",
            " \t",
            "zeta",
            "résumé",
            "beta",
            "single",
            "Alpha"
        };
        var uniqueIds = ids
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Distinct(StringComparer.Ordinal)
            .OrderBy(id => id, StringComparer.Ordinal)
            .ToArray();
        var ranksById = uniqueIds
            .Select((id, index) => new { id, rank = index + 1 })
            .ToDictionary(item => item.id, item => item.rank, StringComparer.Ordinal);
        var idRanks = ids
            .Select(id => string.IsNullOrWhiteSpace(id) ? 0 : ranksById[id])
            .ToArray();
        var idLengthsByRank = new int[uniqueIds.Length + 1];
        for (var i = 0; i < uniqueIds.Length; i++)
        {
            idLengthsByRank[i + 1] = uniqueIds[i].Length;
        }

        var expectedRanks = ids
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .GroupBy(id => id, StringComparer.Ordinal)
            .Where(group => group.Count() > 1)
            .Select(group => ranksById[group.Key])
            .OrderBy(rank => rank)
            .ToArray();
        var expectedChecksum = expectedRanks.Length;
        foreach (var rank in expectedRanks)
        {
            expectedChecksum += rank * 31 + idLengthsByRank[rank] * 17;
        }

        var checksumCountsByRank = new int[uniqueIds.Length + 1];
        var checksumResultRanks = new int[ids.Length];
        var actualChecksum = (int)(cliBatchDuplicateIdRankChecksumInto.Invoke(
            null,
            new object[] { idRanks, uniqueIds.Length, checksumCountsByRank, checksumResultRanks, idLengthsByRank }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedRanks, checksumResultRanks.Take(expectedRanks.Length));

        var countsByRank = new int[uniqueIds.Length + 1];
        var resultRanks = new int[ids.Length];
        var actualCount = (int)(cliBatchDuplicateIdRanksInto.Invoke(
            null,
            new object[] { idRanks, uniqueIds.Length, countsByRank, resultRanks }) ?? -1);

        Assert.Equal(expectedRanks.Length, actualCount);
        Assert.Equal(expectedRanks, resultRanks.Take(actualCount));
    }

    private static void AssertDocCommentsLikeProduction(
        string source,
        MethodInfo codeIntelligenceDocCommentChecksumInto,
        MethodInfo codeIntelligenceDocCommentLinesInto,
        MethodInfo codeIntelligenceDocCommentLinesFromLinesInto)
    {
        var lines = source.Split('\n');
        var queryLines = new List<int> { 0, lines.Length + 1 };
        for (var line = 1; line <= lines.Length; line++)
        {
            queryLines.Add(line);
        }

        var queries = queryLines.ToArray();
        var expectedLineCounts = new int[queries.Length];
        var expectedTextLengths = new int[queries.Length];
        var expectedChecksum = 0;

        for (var i = 0; i < queries.Length; i++)
        {
            var spans = ExtractDocCommentSpans(source, queries[i]);
            var textLength = spans.Count == 0 ? -1 : spans.Sum(span => span.Length) + spans.Count - 1;
            expectedLineCounts[i] = spans.Count;
            expectedTextLengths[i] = textLength;
            expectedChecksum += spans.Count * 13 + textLength * 7;
        }

        var lineStarts = new int[source.Length + 1];
        var lineLengths = new int[source.Length + 1];
        var actualLineCounts = new int[queries.Length];
        var actualTextLengths = new int[queries.Length];
        var actualChecksum = (int)(codeIntelligenceDocCommentChecksumInto.Invoke(
            null,
            new object[] { source, lineStarts, lineLengths, queries, actualLineCounts, actualTextLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedLineCounts, actualLineCounts);
        Assert.Equal(expectedTextLengths, actualTextLengths);

        var cachedLineStarts = new int[source.Length + 1];
        var cachedLineLengths = new int[source.Length + 1];
        var lineCount = BuildLineRanges(source, cachedLineStarts, cachedLineLengths);

        foreach (var query in queries)
        {
            var expected = ExtractDocComment(source, query);
            var expectedSpans = ExtractDocCommentSpans(source, query);

            var directStarts = new int[source.Length + 1];
            var directLengths = new int[source.Length + 1];
            var directLineStarts = new int[source.Length + 1];
            var directLineLengths = new int[source.Length + 1];
            var directCount = (int)(codeIntelligenceDocCommentLinesInto.Invoke(
                null,
                new object[] { source, directLineStarts, directLineLengths, query, directStarts, directLengths }) ?? -1);

            Assert.Equal(expectedSpans.Count, directCount);
            Assert.Equal(expected, MaterializeDocComment(source, directStarts, directLengths, directCount));

            var cachedStarts = new int[source.Length + 1];
            var cachedLengths = new int[source.Length + 1];
            var cachedCount = (int)(codeIntelligenceDocCommentLinesFromLinesInto.Invoke(
                null,
                new object[]
                {
                    source,
                    cachedLineStarts,
                    cachedLineLengths,
                    lineCount,
                    query,
                    cachedStarts,
                    cachedLengths
                }) ?? -1);

            Assert.Equal(expectedSpans.Count, cachedCount);
            Assert.Equal(expected, MaterializeDocComment(source, cachedStarts, cachedLengths, cachedCount));
        }
    }

    private static void AssertVariableDeclarationNamesLikeProduction(
        string source,
        MethodInfo codeIntelligenceVariableDeclarationNameChecksumInto,
        MethodInfo codeIntelligenceVariableDeclarationNamesInto,
        MethodInfo buildCodeIntelligenceVariableDeclarationNameCacheInto,
        MethodInfo codeIntelligenceVariableDeclarationNamesFromCacheInto)
    {
        var lines = source.Split('\n');
        var queries = new List<int> { 0, lines.Length + 1 };
        for (var line = 1; line <= lines.Length; line++)
        {
            queries.Add(line);
        }

        var queryLines = queries.ToArray();
        var expectedStarts = new int[queryLines.Length];
        var expectedLengths = new int[queryLines.Length];
        var expectedChecksum = 0;
        var expectedCount = 0;

        for (var i = 0; i < queryLines.Length; i++)
        {
            var span = ExtractVariableDeclarationNameSpan(source, queryLines[i]);
            var start = span?.StartColumn ?? -1;
            var length = span?.Length ?? 0;
            expectedStarts[i] = start;
            expectedLengths[i] = length;
            expectedChecksum += start * 31 + length * 17;
            if (start >= 0)
            {
                expectedCount++;
            }
        }

        var rangeStarts = new int[source.Length + 1];
        var rangeLengths = new int[source.Length + 1];
        var actualStarts = new int[queryLines.Length];
        var actualLengths = new int[queryLines.Length];
        var actualChecksum = (int)(codeIntelligenceVariableDeclarationNameChecksumInto.Invoke(
            null,
            new object[] { source, rangeStarts, rangeLengths, queryLines, actualStarts, actualLengths }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedStarts, actualStarts);
        Assert.Equal(expectedLengths, actualLengths);

        for (var i = 0; i < queryLines.Length; i++)
        {
            var line = queryLines[i];
            var expectedName = ExtractVariableDeclarationName(source, line);
            var actualName = actualStarts[i] >= 0
                ? lines[line - 1].Substring(actualStarts[i] - 1, actualLengths[i])
                : null;
            Assert.Equal(expectedName, actualName);
        }

        var productionLineStarts = new int[source.Length + 1];
        var productionLineLengths = new int[source.Length + 1];
        var productionStarts = new int[queryLines.Length];
        var productionLengths = new int[queryLines.Length];
        var actualCount = (int)(codeIntelligenceVariableDeclarationNamesInto.Invoke(
            null,
            new object[]
            {
                source,
                productionLineStarts,
                productionLineLengths,
                queryLines,
                productionStarts,
                productionLengths
            }) ?? -1);

        Assert.Equal(expectedCount, actualCount);
        Assert.Equal(expectedStarts, productionStarts);
        Assert.Equal(expectedLengths, productionLengths);

        var cachedLineStarts = new int[source.Length + 1];
        var cachedLineLengths = new int[source.Length + 1];
        var cachedNameStartsByLine = new int[source.Length + 1];
        var cachedNameLengthsByLine = new int[source.Length + 1];
        var cachedStarts = new int[queryLines.Length];
        var cachedLengths = new int[queryLines.Length];
        var lineCount = BuildLineRanges(source, cachedLineStarts, cachedLineLengths);
        var cachedDeclarationCount = (int)(buildCodeIntelligenceVariableDeclarationNameCacheInto.Invoke(
            null,
            new object[]
            {
                source,
                cachedLineStarts,
                cachedLineLengths,
                lineCount,
                cachedNameStartsByLine,
                cachedNameLengthsByLine
            }) ?? -1);

        Assert.Equal(expectedCount, cachedDeclarationCount);

        var cachedMatchCount = (int)(codeIntelligenceVariableDeclarationNamesFromCacheInto.Invoke(
            null,
            new object[]
            {
                lineCount,
                cachedNameStartsByLine,
                cachedNameLengthsByLine,
                queryLines,
                cachedStarts,
                cachedLengths
            }) ?? -1);

        Assert.Equal(expectedCount, cachedMatchCount);
        Assert.Equal(expectedStarts, cachedStarts);
        Assert.Equal(expectedLengths, cachedLengths);
    }

    private static void AssertDiagnosticSeveritySummaryLikeProduction(
        MethodInfo diagnosticSeveritySummaryInto,
        MethodInfo diagnosticSeveritySummaryChecksumInto)
    {
        var diagnostics = BuildDiagnosticSeveritySummaryDiagnostics();
        var severities = diagnostics.Select(static diagnostic => diagnostic.Severity).ToArray();
        var expectedCounts = new[]
        {
            diagnostics.Count(static diagnostic => diagnostic.Severity == "error"),
            diagnostics.Count(static diagnostic => diagnostic.Severity == "warning"),
            diagnostics.Count(static diagnostic => diagnostic.Severity == "info")
        };

        var actualCounts = new int[3];
        var actualCount = (int)(diagnosticSeveritySummaryInto.Invoke(
            null,
            new object[] { severities, severities.Length, actualCounts }) ?? -1);

        Assert.Equal(severities.Length, actualCount);
        Assert.Equal(expectedCounts, actualCounts);

        var checksumCounts = new int[3];
        var actualChecksum = (int)(diagnosticSeveritySummaryChecksumInto.Invoke(
            null,
            new object[] { severities, severities.Length, checksumCounts }) ?? -1);
        var expectedChecksum = severities.Length + expectedCounts[0] * 31 + expectedCounts[1] * 17 + expectedCounts[2] * 13;

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedCounts, checksumCounts);

        var paddedSeverities = severities.Concat(new[] { "error", "warning", "info" }).ToArray();
        var paddedCounts = new int[3];
        var paddedCount = (int)(diagnosticSeveritySummaryInto.Invoke(
            null,
            new object[] { paddedSeverities, severities.Length, paddedCounts }) ?? -1);

        Assert.Equal(severities.Length, paddedCount);
        Assert.Equal(expectedCounts, paddedCounts);
    }

    private static void AssertDiagnosticSeverityFilteringLikeProduction(
        MethodInfo diagnosticSeverityFilterIndicesInto,
        MethodInfo diagnosticSeverityFilterChecksumInto)
    {
        var severities = new[] { "error", "warning", "info", "Error", "hint", "ERROR", "warning" };
        const string targetSeverity = "eRrOr";
        var ranks = BuildDiagnosticSeverityRanks(severities, targetSeverity, out var targetRank);
        var expectedIndices = severities
            .Select((severity, index) => (severity, index))
            .Where(item => item.severity.Equals(targetSeverity, StringComparison.OrdinalIgnoreCase))
            .Select(item => item.index)
            .ToArray();

        var actualIndices = new int[severities.Length];
        var actualCount = (int)(diagnosticSeverityFilterIndicesInto.Invoke(
            null,
            new object[] { ranks, targetRank, actualIndices }) ?? -1);

        Assert.Equal(expectedIndices.Length, actualCount);
        Assert.Equal(expectedIndices, actualIndices.Take(actualCount).ToArray());

        var checksumIndices = new int[severities.Length];
        var actualChecksum = (int)(diagnosticSeverityFilterChecksumInto.Invoke(
            null,
            new object[] { ranks, targetRank, checksumIndices }) ?? -1);
        var expectedChecksum = DiagnosticSeverityFilterChecksum(expectedIndices, ranks);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedIndices, checksumIndices.Take(expectedIndices.Length).ToArray());

        var missingTargetRank = ranks.Max() + 1;
        var missingIndices = new int[severities.Length];
        var missingCount = (int)(diagnosticSeverityFilterIndicesInto.Invoke(
            null,
            new object[] { ranks, missingTargetRank, missingIndices }) ?? -1);

        Assert.Equal(0, missingCount);
    }

    private static int[] BuildDiagnosticSeverityRanks(
        string[] severities,
        string targetSeverity,
        out int targetRank)
    {
        var ranksBySeverity = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

        void AddSeverity(string severity)
        {
            if (!ranksBySeverity.ContainsKey(severity))
            {
                ranksBySeverity.Add(severity, ranksBySeverity.Count + 1);
            }
        }

        AddSeverity(targetSeverity);
        foreach (var severity in severities)
        {
            AddSeverity(severity);
        }

        targetRank = ranksBySeverity[targetSeverity];
        return severities.Select(severity => ranksBySeverity[severity]).ToArray();
    }

    private static int DiagnosticSeverityFilterChecksum(int[] orderedIndices, int[] severityRanks)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97 + (index + 1) * 31 + severityRanks[index] * 17;
        }

        return checksum;
    }

    private static void AssertDiagnosticShadowSuppressionLikeProduction(
        MethodInfo diagnosticShadowSuppressionIndicesInto,
        MethodInfo diagnosticShadowSuppressionChecksumInto)
    {
        var diagnostics = BuildDiagnosticShadowSuppressionDiagnostics();
        var shadowedFiles = new[] { "SRC/a.nl", "src/c.nl", "src/c.nl" };
        var expectedIndices = ExpectedDiagnosticShadowSuppressionIndices(diagnostics, shadowedFiles);
        var (codeIds, fileRanks, targetCodeId, shadowFileFlags) =
            BuildDiagnosticShadowSuppressionRanks(diagnostics, shadowedFiles);

        var actualIndices = new int[diagnostics.Count];
        var actualCount = (int)(diagnosticShadowSuppressionIndicesInto.Invoke(
            null,
            new object[] { codeIds, fileRanks, targetCodeId, shadowFileFlags, actualIndices }) ?? -1);

        Assert.Equal(expectedIndices.Length, actualCount);
        Assert.Equal(expectedIndices, actualIndices.Take(actualCount).ToArray());

        var checksumIndices = new int[diagnostics.Count];
        var actualChecksum = (int)(diagnosticShadowSuppressionChecksumInto.Invoke(
            null,
            new object[] { codeIds, fileRanks, targetCodeId, shadowFileFlags, checksumIndices }) ?? -1);
        var expectedChecksum = DiagnosticShadowSuppressionChecksum(expectedIndices, codeIds, fileRanks);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedIndices, checksumIndices.Take(expectedIndices.Length).ToArray());

        var missingTargetIndices = new int[diagnostics.Count];
        var missingTargetCount = (int)(diagnosticShadowSuppressionIndicesInto.Invoke(
            null,
            new object[] { codeIds, fileRanks, 0, shadowFileFlags, missingTargetIndices }) ?? -1);

        Assert.Equal(diagnostics.Count, missingTargetCount);
        Assert.Equal(Enumerable.Range(0, diagnostics.Count), missingTargetIndices.Take(missingTargetCount));
    }

    private static List<DiagnosticResult> BuildDiagnosticShadowSuppressionDiagnostics()
    {
        return new List<DiagnosticResult>
        {
            BuildDiagnosticWithSeverity("warning", 1) with { Code = "NL020", File = "src/A.nl" },
            BuildDiagnosticWithSeverity("warning", 2) with { Code = "NL020", File = "src/B.nl" },
            BuildDiagnosticWithSeverity("warning", 3) with { Code = "NL021", File = "src/A.nl" },
            BuildDiagnosticWithSeverity("warning", 4) with { Code = "NL020", File = "src/c.nl" },
            BuildDiagnosticWithSeverity("warning", 5) with { Code = "NL0200", File = "src/c.nl" },
            BuildDiagnosticWithSeverity("warning", 6) with { Code = "NL020", File = "src/D.nl" },
            BuildDiagnosticWithSeverity("warning", 7) with { Code = "NL020", File = "SRC/A.NL" }
        };
    }

    private static int[] ExpectedDiagnosticShadowSuppressionIndices(
        IReadOnlyList<DiagnosticResult> diagnostics,
        IReadOnlyList<string> shadowedFiles)
    {
        var shadowedFileSet = shadowedFiles.ToHashSet(StringComparer.OrdinalIgnoreCase);
        return diagnostics
            .Select((diagnostic, index) => (diagnostic, index))
            .Where(item => item.diagnostic.Code != "NL020" || !shadowedFileSet.Contains(item.diagnostic.File))
            .Select(item => item.index)
            .ToArray();
    }

    private static (int[] CodeIds, int[] FileRanks, int TargetCodeId, int[] ShadowFileFlags)
        BuildDiagnosticShadowSuppressionRanks(
            IReadOnlyList<DiagnosticResult> diagnostics,
            IReadOnlyList<string> shadowedFiles)
    {
        var codeRanks = new Dictionary<string, int>(StringComparer.Ordinal);
        var fileRanks = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var uniqueFiles = new List<string>();

        int GetCodeId(string code)
        {
            if (codeRanks.TryGetValue(code, out var id))
                return id;

            id = codeRanks.Count + 1;
            codeRanks.Add(code, id);
            return id;
        }

        void AddFile(string file)
        {
            if (fileRanks.ContainsKey(file))
                return;

            fileRanks.Add(file, 0);
            uniqueFiles.Add(file);
        }

        var targetCodeId = GetCodeId("NL020");
        foreach (var diagnostic in diagnostics)
        {
            GetCodeId(diagnostic.Code);
            AddFile(diagnostic.File);
        }

        foreach (var shadowedFile in shadowedFiles)
        {
            AddFile(shadowedFile);
        }

        uniqueFiles.Sort(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < uniqueFiles.Count; i++)
        {
            fileRanks[uniqueFiles[i]] = i + 1;
        }

        var codeIds = diagnostics.Select(diagnostic => codeRanks[diagnostic.Code]).ToArray();
        var diagnosticFileRanks = diagnostics.Select(diagnostic => fileRanks[diagnostic.File]).ToArray();
        var shadowFileFlags = new int[uniqueFiles.Count + 1];
        foreach (var shadowedFile in shadowedFiles)
        {
            shadowFileFlags[fileRanks[shadowedFile]] = 1;
        }

        return (codeIds, diagnosticFileRanks, targetCodeId, shadowFileFlags);
    }

    private static int DiagnosticShadowSuppressionChecksum(
        int[] orderedIndices,
        int[] codeIds,
        int[] fileRanks)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97 + (index + 1) * 31 + codeIds[index] * 17 + fileRanks[index] * 13;
        }

        return checksum;
    }

    private static void AssertSymbolKindFilteringLikeProduction(
        MethodInfo symbolKindFilterIndicesInto,
        MethodInfo symbolKindFilterChecksumInto)
    {
        var symbols = BuildSymbolKindFilterSymbols();
        var kindIds = symbols.Select(static symbol => (int)symbol.Kind).ToArray();
        var targetKindId = (int)SymbolKind.Function;
        var expectedIndices = symbols
            .Select((symbol, index) => (symbol, index))
            .Where(item => item.symbol.Kind == SymbolKind.Function)
            .Select(item => item.index)
            .ToArray();

        var actualIndices = new int[symbols.Count];
        var actualCount = (int)(symbolKindFilterIndicesInto.Invoke(
            null,
            new object[] { kindIds, targetKindId, actualIndices }) ?? -1);

        Assert.Equal(expectedIndices.Length, actualCount);
        Assert.Equal(expectedIndices, actualIndices.Take(actualCount).ToArray());

        var checksumIndices = new int[symbols.Count];
        var actualChecksum = (int)(symbolKindFilterChecksumInto.Invoke(
            null,
            new object[] { kindIds, targetKindId, checksumIndices }) ?? -1);
        var expectedChecksum = SymbolKindFilterChecksum(expectedIndices, kindIds);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedIndices, checksumIndices.Take(expectedIndices.Length).ToArray());

        var missingIndices = new int[symbols.Count];
        var missingCount = (int)(symbolKindFilterIndicesInto.Invoke(
            null,
            new object[] { kindIds, 99, missingIndices }) ?? -1);

        Assert.Equal(0, missingCount);
    }

    private static int SymbolKindFilterChecksum(int[] orderedIndices, int[] kindIds)
    {
        var checksum = orderedIndices.Length;
        for (var i = 0; i < orderedIndices.Length; i++)
        {
            var index = orderedIndices[i];
            checksum += (i + 1) * 97 + (index + 1) * 31 + kindIds[index] * 17;
        }

        return checksum;
    }

    private static void AssertDiagnosticClusterTraitsLikeProduction(
        MethodInfo diagnosticClusterTraitsInto,
        MethodInfo diagnosticClusterTraitChecksumInto,
        MethodInfo diagnosticClusterTraitPatternChecksumInto,
        MethodInfo diagnosticClusterTraitsAndPatternsInto)
    {
        var diagnostics = BuildDiagnosticClusterTraitDiagnostics();
        var codes = diagnostics.Select(static diagnostic => diagnostic.Code).ToArray();
        var messages = diagnostics.Select(static diagnostic => diagnostic.Message).ToArray();
        var snippets = diagnostics.Select(static diagnostic => diagnostic.SourceSnippet ?? string.Empty).ToArray();
        var expectedCategories = new[] { 1, 0, 2, 3, 4, 5, 6, 7 };
        var expectedSourceConstructs = new[] { 1, 0, 4, 0, 2, 5, 7, 8 };
        var expectedPatterns = new[]
        {
            "Expected token {value} at line #",
            "Missing semicolon after {value}",
            "Circular import detected",
            "Undefined variable {value}",
            "Type not found {value}",
            "Type mismatch: expected Int##",
            "Member {value} does not exist",
            "unknown-message"
        };

        var checksumCategories = new int[diagnostics.Count];
        var checksumSourceConstructs = new int[diagnostics.Count];
        var actualChecksum = (int)(diagnosticClusterTraitChecksumInto.Invoke(
            null,
            new object[]
            {
                codes,
                messages,
                snippets,
                checksumCategories,
                checksumSourceConstructs
            }) ?? -1);

        var expectedChecksum = diagnostics.Count;
        for (var i = 0; i < diagnostics.Count; i++)
        {
            expectedChecksum += expectedCategories[i] * 31 + expectedSourceConstructs[i] * 17;
        }

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedCategories, checksumCategories);
        Assert.Equal(expectedSourceConstructs, checksumSourceConstructs);

        var actualCategories = new int[diagnostics.Count];
        var actualSourceConstructs = new int[diagnostics.Count];
        var actualTraitCount = (int)(diagnosticClusterTraitsInto.Invoke(
            null,
            new object[]
            {
                codes,
                messages,
                snippets,
                actualCategories,
                actualSourceConstructs
            }) ?? -1);

        Assert.Equal(diagnostics.Count, actualTraitCount);
        Assert.Equal(expectedCategories, actualCategories);
        Assert.Equal(expectedSourceConstructs, actualSourceConstructs);

        var patternChecksumCategories = new int[diagnostics.Count];
        var patternChecksumSourceConstructs = new int[diagnostics.Count];
        var patternChecksumPatterns = new string[diagnostics.Count];
        var actualPatternChecksum = (int)(diagnosticClusterTraitPatternChecksumInto.Invoke(
            null,
            new object[]
            {
                codes,
                messages,
                snippets,
                patternChecksumCategories,
                patternChecksumSourceConstructs,
                patternChecksumPatterns
            }) ?? -1);

        var expectedPatternChecksum = diagnostics.Count;
        for (var i = 0; i < diagnostics.Count; i++)
        {
            expectedPatternChecksum += expectedCategories[i] * 31 + expectedSourceConstructs[i] * 17 + expectedPatterns[i].Length;
        }

        Assert.Equal(expectedPatternChecksum, actualPatternChecksum);
        Assert.Equal(expectedCategories, patternChecksumCategories);
        Assert.Equal(expectedSourceConstructs, patternChecksumSourceConstructs);
        Assert.Equal(expectedPatterns, patternChecksumPatterns);

        var actualPatterns = new string[diagnostics.Count];
        var actualCount = (int)(diagnosticClusterTraitsAndPatternsInto.Invoke(
            null,
            new object[]
            {
                codes,
                messages,
                snippets,
                actualCategories,
                actualSourceConstructs,
                actualPatterns
            }) ?? -1);

        Assert.Equal(diagnostics.Count, actualCount);
        Assert.Equal(expectedCategories, actualCategories);
        Assert.Equal(expectedSourceConstructs, actualSourceConstructs);
        Assert.Equal(expectedPatterns, actualPatterns);
    }

    private static List<DiagnosticResult> BuildDiagnosticClusterTraitDiagnostics()
    {
        return new List<DiagnosticResult>
        {
            new(
                "NL102",
                "error",
                "Expected token '}' at line 7",
                "Program.nl",
                1,
                1,
                1,
                "static func Run() {",
                null,
                null,
                null,
                null,
                null,
                null),
            new(
                "NL102",
                "error",
                "Missing semicolon after \"value\"",
                "Program.nl",
                2,
                5,
                1,
                "let value = 1",
                null,
                null,
                null,
                null,
                null,
                null),
            new(
                "NL703",
                "error",
                "Circular import detected",
                "Imports.nl",
                1,
                1,
                1,
                "import Foo",
                null,
                null,
                null,
                null,
                null,
                null),
            new(
                "NL301",
                "error",
                "Undefined variable 'foo'",
                "Program.nl",
                3,
                14,
                7,
                "    value := foo",
                null,
                null,
                null,
                null,
                null,
                null),
            new(
                "NL201",
                "error",
                "Type not found 'Widget'",
                "Models.nl",
                1,
                7,
                6,
                "class Person {",
                null,
                null,
                null,
                null,
                null,
                null),
            new(
                "NL202",
                "error",
                "Type mismatch: expected Int32",
                "Program.nl",
                4,
                12,
                5,
                "return value",
                null,
                null,
                null,
                "Int32",
                "string",
                null),
            new(
                "NL303",
                "error",
                "Member 'Absent' does not exist",
                "Program.nl",
                5,
                14,
                7,
                "customer.Name()",
                null,
                null,
                null,
                null,
                null,
                null),
            new(
                "NL999",
                "warning",
                "   ",
                "Program.nl",
                6,
                1,
                1,
                "   ",
                null,
                null,
                null,
                null,
                null,
                null)
        };
    }

    private static void AssertDiagnosticClusterIdsLikeProduction(
        MethodInfo diagnosticClusterIdsInto,
        MethodInfo diagnosticClusterIdChecksumInto)
    {
        var codes = new[] { "NL102", "NL703", "NL301", "NL202" };
        var severities = new[] { "error", "error", "warning", "error" };
        var categories = new[]
        {
            "syntax-missing-delimiter",
            "import-cycle",
            "identifier-resolution",
            "type-mismatch"
        };
        var sourceConstructs = new[]
        {
            "function-declaration",
            "import",
            "variable-declaration",
            "return-statement"
        };
        var recipes = new[]
        {
            "syntax:delimiter-balancing",
            "architecture:extract-shared-module-or-invert-dependency",
            "symbols:missing-import-or-qualification",
            "refactor:signature-or-expression-shape"
        };
        var messagePatterns = new[]
        {
            "Expected token {value} at line #",
            "Circular import detected",
            "Undefined variable {value}",
            "Type mismatch: expected Int##"
        };
        var expectedIds = Enumerable.Range(0, codes.Length)
            .Select(i => CreateExpectedDiagnosticClusterId(
                codes[i],
                severities[i],
                categories[i],
                sourceConstructs[i],
                recipes[i],
                messagePatterns[i]))
            .ToArray();

        var checksumIds = new string[codes.Length];
        var actualChecksum = (int)(diagnosticClusterIdChecksumInto.Invoke(
            null,
            new object[]
            {
                codes,
                severities,
                categories,
                sourceConstructs,
                recipes,
                messagePatterns,
                checksumIds
            }) ?? -1);

        var expectedChecksum = codes.Length;
        foreach (var id in expectedIds)
        {
            expectedChecksum += id.Length * 31;
        }

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedIds, checksumIds);

        var actualIds = new string[codes.Length];
        var actualCount = (int)(diagnosticClusterIdsInto.Invoke(
            null,
            new object[]
            {
                codes,
                severities,
                categories,
                sourceConstructs,
                recipes,
                messagePatterns,
                actualIds
            }) ?? -1);

        Assert.Equal(codes.Length, actualCount);
        Assert.Equal(expectedIds, actualIds);
    }

    private static string CreateExpectedDiagnosticClusterId(
        string code,
        string severity,
        string category,
        string sourceConstruct,
        string recipe,
        string messagePattern)
    {
        var key = $"{code}|{severity}|{category}|{sourceConstruct}|{recipe}|{messagePattern}";
        var hash = 17;
        foreach (var c in key)
        {
            hash = (hash * 31) + c;
        }

        return $"diag-{Math.Abs(hash):x}";
    }

    private static void AssertDiagnosticClusterNextCommandsLikeProduction(
        MethodInfo diagnosticClusterNextCommandsInto,
        MethodInfo diagnosticClusterNextCommandChecksumInto)
    {
        var files = new[]
        {
            "/repo/src/Main.nl",
            "/repo/src/Has Space.nl",
            """C:\repo\quoted"name.nl""",
            "   ",
            "/repo/src/café.nl"
        };
        var lines = new[] { 12, 3, 44, 1, 9 };
        var columns = new[] { 8, 1, 17, 1, 5 };
        var expectedCommands = Enumerable.Range(0, files.Length)
            .Select(i => CreateExpectedDiagnosticClusterNextCommand(files[i], lines[i], columns[i]))
            .ToArray();

        var checksumCommands = new string[files.Length];
        var actualChecksum = (int)(diagnosticClusterNextCommandChecksumInto.Invoke(
            null,
            new object[] { files, lines, columns, checksumCommands }) ?? -1);

        var expectedChecksum = files.Length;
        foreach (var command in expectedCommands)
        {
            expectedChecksum += command.Length * 31;
        }

        Assert.Equal(expectedCommands, checksumCommands);
        Assert.Equal(expectedChecksum, actualChecksum);

        var actualCommands = new string[files.Length];
        var actualCount = (int)(diagnosticClusterNextCommandsInto.Invoke(
            null,
            new object[] { files, lines, columns, actualCommands }) ?? -1);

        Assert.Equal(files.Length, actualCount);
        Assert.Equal(expectedCommands, actualCommands);
    }

    private static string CreateExpectedDiagnosticClusterNextCommand(string file, int line, int column)
    {
        return $"nlc query inspect --file {EscapeExpectedCommandArgument(file)} --pos {line}:{column}";
    }

    private static string EscapeExpectedCommandArgument(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
            return "\"\"";

        if (value.All(c => char.IsLetterOrDigit(c) || c is '/' or '.' or '_' or '-'))
            return value;

        return $"\"{value.Replace("\\", "\\\\").Replace("\"", "\\\"")}\"";
    }

    private static void AssertDiagnosticClusterGroupsLikeProduction(
        MethodInfo diagnosticClusterGroupsInto,
        MethodInfo diagnosticClusterGroupChecksumInto,
        MethodInfo diagnosticClusterGroupMembersInto,
        MethodInfo diagnosticClusterGroupMemberChecksumInto)
    {
        var codes = new[] { "NL102", "NL301", "NL102", "NL703", "NL301", "NL102", "NL102" };
        var codeIds = new[] { 102, 301, 102, 703, 301, 102, 102 };
        var severities = new[] { "error", "warning", "error", "error", "warning", "error", "error" };
        var severityIds = new[] { 1, 2, 1, 1, 2, 1, 1 };
        var categories = new[]
        {
            "syntax-missing-delimiter",
            "identifier-resolution",
            "syntax-missing-delimiter",
            "import-cycle",
            "identifier-resolution",
            "syntax-missing-delimiter",
            "syntax-missing-delimiter"
        };
        var categoryIds = new[] { 1, 2, 1, 3, 2, 1, 1 };
        var sourceConstructs = new[]
        {
            "function-declaration",
            "variable-declaration",
            "function-declaration",
            "import",
            "variable-declaration",
            "function-declaration",
            "function-declaration"
        };
        var sourceConstructIds = new[] { 1, 2, 1, 3, 2, 1, 1 };
        var recipes = new[]
        {
            "syntax:delimiter-balancing",
            "symbols:missing-import-or-qualification",
            "syntax:delimiter-balancing",
            "architecture:extract-shared-module-or-invert-dependency",
            "symbols:missing-import-or-qualification",
            "syntax:delimiter-balancing",
            "syntax:delimiter-balancing"
        };
        var recipeIds = new[] { 1, 2, 1, 3, 2, 1, 1 };
        var risks = new[] { "high", "medium", "high", "high", "medium", "high", "high" };
        var riskIds = new[] { 1, 2, 1, 1, 2, 1, 1 };
        var messagePatterns = new[]
        {
            "Expected token {value}",
            "Undefined variable {value}",
            "Expected token {value}",
            "Circular import detected",
            "Undefined variable {value}",
            "Expected token {value}",
            "Expected token {value}"
        };
        var messagePatternIds = new[] { 1, 2, 1, 3, 2, 1, 1 };
        var files = new[]
        {
            "/repo/B.nl",
            "/repo/C.nl",
            "/repo/A.nl",
            "/repo/Imports.nl",
            "/repo/C.nl",
            "/repo/D.nl",
            "/repo/a.nl"
        };
        var lines = new[] { 10, 3, 10, 1, 2, 8, 10 };
        var columns = new[] { 5, 7, 3, 1, 9, 1, 2 };
        var expected = CreateExpectedDiagnosticClusterGroups(
            codes,
            severities,
            categories,
            sourceConstructs,
            recipes,
            risks,
            messagePatterns,
            files,
            lines,
            columns);

        var checksumRootIndices = new int[codes.Length];
        var checksumCounts = new int[codes.Length];
        var checksumSlotGroups = new int[codes.Length * 2 + 1];
        var checksumGroupKeyIndices = new int[codes.Length];
        var actualChecksum = (int)(diagnosticClusterGroupChecksumInto.Invoke(
            null,
            new object[]
            {
                codeIds,
                severityIds,
                categoryIds,
                sourceConstructIds,
                recipeIds,
                riskIds,
                messagePatternIds,
                files,
                lines,
                columns,
                checksumSlotGroups,
                checksumGroupKeyIndices,
                checksumRootIndices,
                checksumCounts
            }) ?? -1);

        var expectedChecksum = expected.RootIndices.Length;
        for (var i = 0; i < expected.RootIndices.Length; i++)
        {
            expectedChecksum += (expected.RootIndices[i] + 1) * 31 + expected.Counts[i] * 17;
        }

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected.RootIndices, checksumRootIndices.Take(expected.RootIndices.Length));
        Assert.Equal(expected.Counts, checksumCounts.Take(expected.Counts.Length));

        var actualRootIndices = new int[codes.Length];
        var actualCounts = new int[codes.Length];
        var actualSlotGroups = new int[codes.Length * 2 + 1];
        var actualGroupKeyIndices = new int[codes.Length];
        var actualCount = (int)(diagnosticClusterGroupsInto.Invoke(
            null,
            new object[]
            {
                codeIds,
                severityIds,
                categoryIds,
                sourceConstructIds,
                recipeIds,
                riskIds,
                messagePatternIds,
                files,
                lines,
                columns,
                actualSlotGroups,
                actualGroupKeyIndices,
                actualRootIndices,
                actualCounts
            }) ?? -1);

        Assert.Equal(expected.RootIndices.Length, actualCount);
        Assert.Equal(expected.RootIndices, actualRootIndices.Take(actualCount));
        Assert.Equal(expected.Counts, actualCounts.Take(actualCount));

        var checksumMemberStarts = new int[codes.Length];
        var checksumMemberIndices = new int[codes.Length];
        var checksumMemberSlotGroups = new int[codes.Length * 2 + 1];
        var checksumGroupFirstMemberIndices = new int[codes.Length];
        var checksumMemberNextIndices = new int[codes.Length];
        var actualMemberChecksum = (int)(diagnosticClusterGroupMemberChecksumInto.Invoke(
            null,
            new object[]
            {
                codeIds,
                severityIds,
                categoryIds,
                sourceConstructIds,
                recipeIds,
                riskIds,
                messagePatternIds,
                files,
                lines,
                columns,
                expected.RootIndices,
                expected.Counts,
                expected.RootIndices.Length,
                checksumMemberSlotGroups,
                checksumGroupFirstMemberIndices,
                checksumMemberNextIndices,
                checksumMemberStarts,
                checksumMemberIndices
            }) ?? -1);

        var expectedMemberChecksum = expected.MemberIndices.Length;
        for (var i = 0; i < expected.RootIndices.Length; i++)
        {
            expectedMemberChecksum += (expected.MemberStarts[i] + 1) * 31 + expected.Counts[i] * 17;
        }

        foreach (var index in expected.MemberIndices)
        {
            expectedMemberChecksum += (index + 1) * 13 + lines[index] * 7 + columns[index] * 5;
        }

        Assert.Equal(expectedMemberChecksum, actualMemberChecksum);
        Assert.Equal(expected.MemberStarts, checksumMemberStarts.Take(expected.MemberStarts.Length));
        Assert.Equal(expected.MemberIndices, checksumMemberIndices.Take(expected.MemberIndices.Length));

        var actualMemberStarts = new int[codes.Length];
        var actualMemberIndices = new int[codes.Length];
        var actualMemberSlotGroups = new int[codes.Length * 2 + 1];
        var actualGroupFirstMemberIndices = new int[codes.Length];
        var actualMemberNextIndices = new int[codes.Length];
        var actualMemberCount = (int)(diagnosticClusterGroupMembersInto.Invoke(
            null,
            new object[]
            {
                codeIds,
                severityIds,
                categoryIds,
                sourceConstructIds,
                recipeIds,
                riskIds,
                messagePatternIds,
                files,
                lines,
                columns,
                actualRootIndices,
                actualCounts,
                actualCount,
                actualMemberSlotGroups,
                actualGroupFirstMemberIndices,
                actualMemberNextIndices,
                actualMemberStarts,
                actualMemberIndices
            }) ?? -1);

        Assert.Equal(expected.MemberIndices.Length, actualMemberCount);
        Assert.Equal(expected.MemberStarts, actualMemberStarts.Take(expected.MemberStarts.Length));
        Assert.Equal(expected.MemberIndices, actualMemberIndices.Take(expected.MemberIndices.Length));
    }

    private static (int[] RootIndices, int[] Counts, int[] MemberStarts, int[] MemberIndices) CreateExpectedDiagnosticClusterGroups(
        string[] codes,
        string[] severities,
        string[] categories,
        string[] sourceConstructs,
        string[] recipes,
        string[] risks,
        string[] messagePatterns,
        string[] files,
        int[] lines,
        int[] columns)
    {
        var groups = Enumerable.Range(0, codes.Length)
            .GroupBy(i => new
            {
                Severity = severities[i],
                Code = codes[i],
                Category = categories[i],
                SourceConstruct = sourceConstructs[i],
                Recipe = recipes[i],
                Risk = risks[i],
                MessagePattern = messagePatterns[i]
            })
            .Select(group =>
            {
                var members = group
                    .OrderBy(i => lines[i])
                    .ThenBy(i => columns[i])
                    .ThenBy(i => files[i], StringComparer.OrdinalIgnoreCase)
                    .ToArray();
                return new
                {
                    RootIndex = members[0],
                    Count = members.Length,
                    Members = members
                };
            })
            .OrderByDescending(group => group.Count)
            .ThenBy(group => files[group.RootIndex], StringComparer.OrdinalIgnoreCase)
            .ThenBy(group => lines[group.RootIndex])
            .ThenBy(group => columns[group.RootIndex])
            .ToArray();

        var memberStarts = new int[groups.Length];
        var memberIndices = new List<int>(codes.Length);
        for (var i = 0; i < groups.Length; i++)
        {
            memberStarts[i] = memberIndices.Count;
            memberIndices.AddRange(groups[i].Members);
        }

        return (
            groups.Select(static group => group.RootIndex).ToArray(),
            groups.Select(static group => group.Count).ToArray(),
            memberStarts,
            memberIndices.ToArray());
    }

    private static void AssertDiagnosticDeduplicationLikeProduction(
        MethodInfo diagnosticDeduplicateCompactInto,
        MethodInfo diagnosticDeduplicateCompactChecksumInto,
        MethodInfo diagnosticDeduplicateStableInto,
        MethodInfo diagnosticDeduplicateStableChecksumInto)
    {
        var codes = new[] { "NL102", "NL301", "NL102", "NL201", "NL301", "NL302" };
        var files = new[] { "B.nl", "A.nl", "B.nl", "A.nl", "A.nl", "A.nl" };
        var lines = new[] { 10, 2, 10, 2, 2, 2 };
        var columns = new[] { 5, 3, 5, 1, 3, 3 };
        var messages = new[]
        {
            "Expected token '}'",
            "Undefined variable 'value'",
            "Expected token '}'",
            "Type is inferred",
            "Undefined variable 'value'",
            "Different diagnostic at same location"
        };
        var codeIds = CreateOrdinalIds(codes);
        var fileRanks = CreateSortedFileRanks(files);
        var fileIds = CreateOrdinalIds(files);
        var messageIds = CreateOrdinalIds(messages);
        var expected = CreateExpectedDiagnosticDeduplication(codes, files, lines, columns, messages);
        var expectedStable = CreateExpectedStableDiagnosticDeduplication(codes, files, lines, columns, messages);

        var checksumSlotIndices = new int[codes.Length * 2 + 1];
        var checksumResultIndices = new int[codes.Length];
        var actualChecksum = (int)(diagnosticDeduplicateCompactChecksumInto.Invoke(
            null,
            new object[]
            {
                codeIds,
                fileRanks,
                lines,
                columns,
                messageIds,
                checksumSlotIndices,
                checksumResultIndices
            }) ?? -1);

        var expectedChecksum = expected.Length;
        for (var i = 0; i < expected.Length; i++)
        {
            var index = expected[i];
            expectedChecksum += (index + 1) * 31 + lines[index] * 17 + columns[index] * 13;
        }

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length));

        var slotIndices = new int[codes.Length * 2 + 1];
        var resultIndices = new int[codes.Length];
        var actualCount = (int)(diagnosticDeduplicateCompactInto.Invoke(
            null,
            new object[]
            {
                codeIds,
                fileRanks,
                lines,
                columns,
                messageIds,
                slotIndices,
                resultIndices
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount));

        var stableChecksumSlotIndices = new int[codes.Length * 2 + 1];
        var stableChecksumResultIndices = new int[codes.Length];
        var actualStableChecksum = (int)(diagnosticDeduplicateStableChecksumInto.Invoke(
            null,
            new object[]
            {
                codeIds,
                fileIds,
                lines,
                columns,
                messageIds,
                stableChecksumSlotIndices,
                stableChecksumResultIndices
            }) ?? -1);

        var expectedStableChecksum = expectedStable.Length;
        for (var i = 0; i < expectedStable.Length; i++)
        {
            var index = expectedStable[i];
            expectedStableChecksum += (index + 1) * 31 + lines[index] * 17 + columns[index] * 13;
        }

        Assert.Equal(expectedStableChecksum, actualStableChecksum);
        Assert.Equal(expectedStable, stableChecksumResultIndices.Take(expectedStable.Length));

        var stableSlotIndices = new int[codes.Length * 2 + 1];
        var stableResultIndices = new int[codes.Length];
        var actualStableCount = (int)(diagnosticDeduplicateStableInto.Invoke(
            null,
            new object[]
            {
                codeIds,
                fileIds,
                lines,
                columns,
                messageIds,
                stableSlotIndices,
                stableResultIndices
            }) ?? -1);

        Assert.Equal(expectedStable.Length, actualStableCount);
        Assert.Equal(expectedStable, stableResultIndices.Take(actualStableCount));
    }

    private static int[] CreateExpectedDiagnosticDeduplication(
        string[] codes,
        string[] files,
        int[] lines,
        int[] columns,
        string[] messages)
    {
        return Enumerable.Range(0, codes.Length)
            .GroupBy(i => (codes[i], files[i], lines[i], columns[i], messages[i]))
            .Select(group => group.First())
            .OrderBy(i => files[i])
            .ThenBy(i => lines[i])
            .ThenBy(i => columns[i])
            .ToArray();
    }

    private static int[] CreateExpectedStableDiagnosticDeduplication(
        string[] codes,
        string[] files,
        int[] lines,
        int[] columns,
        string[] messages)
    {
        return Enumerable.Range(0, codes.Length)
            .GroupBy(i => (codes[i], files[i], lines[i], columns[i], messages[i]))
            .Select(group => group.First())
            .ToArray();
    }

    private static void AssertReferenceDeduplicationLikeProduction(
        MethodInfo referenceDeduplicateCompactInto,
        MethodInfo referenceDeduplicateCompactChecksumInto)
    {
        var files = new[] { "B.nl", "A.nl", "B.nl", "A.nl", "A.nl", "C.nl" };
        var lines = new[] { 10, 2, 10, 2, 2, 1 };
        var columns = new[] { 5, 3, 5, 1, 3, 1 };
        var fileRanks = CreateSortedFileRanks(files);
        var expected = CreateExpectedReferenceDeduplication(files, lines, columns);

        var checksumSlotIndices = new int[files.Length * 2 + 1];
        var checksumResultIndices = new int[files.Length];
        var actualChecksum = (int)(referenceDeduplicateCompactChecksumInto.Invoke(
            null,
            new object[]
            {
                fileRanks,
                lines,
                columns,
                checksumSlotIndices,
                checksumResultIndices
            }) ?? -1);

        var expectedChecksum = expected.Length;
        for (var i = 0; i < expected.Length; i++)
        {
            var index = expected[i];
            expectedChecksum += (index + 1) * 31 + lines[index] * 17 + columns[index] * 13;
        }

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices.Take(expected.Length));

        var slotIndices = new int[files.Length * 2 + 1];
        var resultIndices = new int[files.Length];
        var actualCount = (int)(referenceDeduplicateCompactInto.Invoke(
            null,
            new object[]
            {
                fileRanks,
                lines,
                columns,
                slotIndices,
                resultIndices
            }) ?? -1);

        Assert.Equal(expected.Length, actualCount);
        Assert.Equal(expected, resultIndices.Take(actualCount));
    }

    private static int[] CreateExpectedReferenceDeduplication(
        string[] files,
        int[] lines,
        int[] columns)
    {
        return Enumerable.Range(0, files.Length)
            .GroupBy(i => (files[i], lines[i], columns[i]))
            .Select(group => group.First())
            .OrderBy(i => files[i])
            .ThenBy(i => lines[i])
            .ThenBy(i => columns[i])
            .ToArray();
    }

    private static void AssertReferenceFileSummaryLikeProduction(
        MethodInfo referenceFileSummaryRanksInto,
        MethodInfo referenceFileSummaryChecksumInto)
    {
        var files = new[]
        {
            @"src\B.nl",
            "src/A.nl",
            "src/B.nl",
            @"src\C.nl",
            "src/A.nl",
            "src/[weird]/File.nl",
            @"src\zeta\File.nl",
            "src/zeta/File.nl"
        };
        var normalizedFiles = files.Select(file => file.Replace('\\', '/')).ToArray();
        var uniqueFiles = normalizedFiles
            .Distinct(StringComparer.Ordinal)
            .OrderBy(file => file, StringComparer.Ordinal)
            .ToArray();
        var ranksByFile = uniqueFiles
            .Select((file, index) => (file, rank: index + 1))
            .ToDictionary(item => item.file, item => item.rank, StringComparer.Ordinal);
        var fileRanks = normalizedFiles.Select(file => ranksByFile[file]).ToArray();
        var fileLengthsByRank = new int[uniqueFiles.Length + 1];
        for (var i = 0; i < uniqueFiles.Length; i++)
        {
            fileLengthsByRank[i + 1] = uniqueFiles[i].Length;
        }

        var expectedRanks = Enumerable.Range(1, uniqueFiles.Length).ToArray();
        var expectedChecksum = expectedRanks.Length;
        for (var i = 0; i < expectedRanks.Length; i++)
        {
            var rank = expectedRanks[i];
            expectedChecksum += rank * 31 + fileLengthsByRank[rank] * 17 + (i + 1) * 13;
        }

        var checksumCountsByRank = new int[uniqueFiles.Length + 1];
        var checksumResultRanks = new int[files.Length];
        var actualChecksum = (int)(referenceFileSummaryChecksumInto.Invoke(
            null,
            new object[] { fileRanks, uniqueFiles.Length, checksumCountsByRank, checksumResultRanks, fileLengthsByRank }) ?? -1);

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expectedRanks, checksumResultRanks.Take(expectedRanks.Length));

        var countsByRank = new int[uniqueFiles.Length + 1];
        var resultRanks = new int[files.Length];
        var actualCount = (int)(referenceFileSummaryRanksInto.Invoke(
            null,
            new object[] { fileRanks, uniqueFiles.Length, countsByRank, resultRanks }) ?? -1);

        Assert.Equal(expectedRanks.Length, actualCount);
        Assert.Equal(expectedRanks, resultRanks.Take(actualCount));
    }

    private static void AssertBindingLookupLikeProduction(
        MethodInfo bindingLookupCandidateColumnsInto,
        MethodInfo bindingLookupCandidateColumnChecksumInto,
        MethodInfo bindingLookupBuildSlotsInto,
        MethodInfo bindingLookupQueryDeclarationIndicesInto,
        MethodInfo bindingLookupQueryChecksumInto,
        MethodInfo bindingLookupBuildNearestDeclarationIndexInto,
        MethodInfo bindingLookupBuildNearestDeclarationIndexChecksumInto,
        MethodInfo bindingLookupFindNearestDeclarationIndicesInto,
        MethodInfo bindingLookupFindNearestDeclarationChecksumInto)
    {
        var candidateQueryColumns = new[] { 5, 1, 0, -3, 10, 1000 };
        var candidateSpanStarts = new[] { 3, -1, 1, -1, 8, 3 };
        var candidateSpanEnds = new[] { 7, -1, 1, -1, 12, 5 };
        var expectedCandidateColumns = BuildExpectedBindingCandidateColumns(
            candidateQueryColumns,
            candidateSpanStarts,
            candidateSpanEnds);
        var expectedCandidateStarts = new int[candidateQueryColumns.Length];
        var expectedCandidateCounts = new int[candidateQueryColumns.Length];
        var expectedFlatCandidateColumns = FlattenExpectedBindingCandidateColumns(
            expectedCandidateColumns,
            expectedCandidateStarts,
            expectedCandidateCounts);

        var candidateStarts = new int[candidateQueryColumns.Length];
        var candidateCounts = new int[candidateQueryColumns.Length];
        var candidateColumns = new int[expectedFlatCandidateColumns.Length];
        var actualCandidateTotal = (int)(bindingLookupCandidateColumnsInto.Invoke(
            null,
            new object[]
            {
                candidateQueryColumns,
                candidateSpanStarts,
                candidateSpanEnds,
                candidateStarts,
                candidateCounts,
                candidateColumns
            }) ?? -1);

        Assert.Equal(expectedFlatCandidateColumns.Length, actualCandidateTotal);
        Assert.Equal(expectedCandidateStarts, candidateStarts);
        Assert.Equal(expectedCandidateCounts, candidateCounts);
        Assert.Equal(expectedFlatCandidateColumns, candidateColumns);

        var checksumStarts = new int[candidateQueryColumns.Length];
        var checksumCounts = new int[candidateQueryColumns.Length];
        var checksumColumns = new int[expectedFlatCandidateColumns.Length];
        var actualCandidateChecksum = (int)(bindingLookupCandidateColumnChecksumInto.Invoke(
            null,
            new object[]
            {
                candidateQueryColumns,
                candidateSpanStarts,
                candidateSpanEnds,
                checksumStarts,
                checksumCounts,
                checksumColumns
            }) ?? -1);
        var expectedCandidateChecksum = CandidateColumnChecksum(
            expectedFlatCandidateColumns.Length,
            expectedCandidateStarts,
            expectedCandidateCounts,
            expectedFlatCandidateColumns);

        Assert.Equal(expectedCandidateChecksum, actualCandidateChecksum);
        Assert.Equal(expectedCandidateStarts, checksumStarts);
        Assert.Equal(expectedCandidateCounts, checksumCounts);
        Assert.Equal(expectedFlatCandidateColumns, checksumColumns);

        var declarationFileRanks = new[] { 2, 1, 3 };
        var declarationLines = new[] { 10, 2, 1 };
        var declarationColumns = new[] { 5, 3, 1 };
        var declarationNameLengths = new[] { 6, 6, 6 };
        var declarationSlots = new int[declarationFileRanks.Length * 2 + 1];

        var bindingFileRanks = new[] { 1, 2, 1 };
        var bindingLines = new[] { 7, 12, 2 };
        var bindingColumns = new[] { 9, 4, 3 };
        var bindingDeclarationIndices = new[] { 0, 2, 0 };
        var bindingSlots = new int[bindingFileRanks.Length * 2 + 1];

        Assert.Equal(declarationFileRanks.Length, (int)(bindingLookupBuildSlotsInto.Invoke(
            null,
            new object[] { declarationFileRanks, declarationLines, declarationColumns, declarationSlots }) ?? -1));
        Assert.Equal(bindingFileRanks.Length, (int)(bindingLookupBuildSlotsInto.Invoke(
            null,
            new object[] { bindingFileRanks, bindingLines, bindingColumns, bindingSlots }) ?? -1));

        var queryFileRanks = new[] { 1, 1, 2, 3 };
        var queryLines = new[] { 2, 7, 12, 99 };
        var queryColumns = new[] { 3, 9, 4, 1 };
        var expected = new[] { 1, 0, 2, -1 };

        var resultIndices = new int[queryFileRanks.Length];
        var actualCount = (int)(bindingLookupQueryDeclarationIndicesInto.Invoke(
            null,
            new object[]
            {
                declarationFileRanks,
                declarationLines,
                declarationColumns,
                declarationSlots,
                bindingFileRanks,
                bindingLines,
                bindingColumns,
                bindingDeclarationIndices,
                bindingSlots,
                queryFileRanks,
                queryLines,
                queryColumns,
                resultIndices
            }) ?? -1);

        Assert.Equal(3, actualCount);
        Assert.Equal(expected, resultIndices);

        var checksumResultIndices = new int[queryFileRanks.Length];
        var actualChecksum = (int)(bindingLookupQueryChecksumInto.Invoke(
            null,
            new object[]
            {
                declarationFileRanks,
                declarationLines,
                declarationColumns,
                declarationNameLengths,
                declarationSlots,
                bindingFileRanks,
                bindingLines,
                bindingColumns,
                bindingDeclarationIndices,
                bindingSlots,
                queryFileRanks,
                queryLines,
                queryColumns,
                checksumResultIndices
            }) ?? -1);

        var expectedChecksum = 3;
        foreach (var declarationIndex in expected.Where(index => index >= 0))
        {
            expectedChecksum += declarationLines[declarationIndex] * 31
                + declarationColumns[declarationIndex] * 17
                + declarationNameLengths[declarationIndex] * 13;
        }

        Assert.Equal(expectedChecksum, actualChecksum);
        Assert.Equal(expected, checksumResultIndices);

        var unsortedNameIds = new[] { 2, 1, 1, 1, 1 };
        var unsortedFileRanks = new[] { 1, 1, 1, 1, 2 };
        var unsortedLines = new[] { 3, 2, 8, 8, 10 };
        var unsortedColumns = new[] { 1, 3, 1, 4, 1 };
        var expectedSortOrder = new[] { 1, 2, 3, 4, 0 };
        var builtNameIds = new int[unsortedNameIds.Length];
        var builtFileRanks = new int[unsortedNameIds.Length];
        var builtLines = new int[unsortedNameIds.Length];
        var builtColumns = new int[unsortedNameIds.Length];
        var builtDeclarationIndices = new int[unsortedNameIds.Length];
        var buildCount = (int)(bindingLookupBuildNearestDeclarationIndexInto.Invoke(
            null,
            new object[]
            {
                unsortedNameIds,
                unsortedFileRanks,
                unsortedLines,
                unsortedColumns,
                new int[unsortedNameIds.Length],
                new int[unsortedNameIds.Length],
                builtNameIds,
                builtFileRanks,
                builtLines,
                builtColumns,
                builtDeclarationIndices
            }) ?? -1);

        Assert.Equal(unsortedNameIds.Length, buildCount);
        Assert.Equal(expectedSortOrder, builtDeclarationIndices);
        Assert.Equal(expectedSortOrder.Select(index => unsortedNameIds[index]).ToArray(), builtNameIds);
        Assert.Equal(expectedSortOrder.Select(index => unsortedFileRanks[index]).ToArray(), builtFileRanks);
        Assert.Equal(expectedSortOrder.Select(index => unsortedLines[index]).ToArray(), builtLines);
        Assert.Equal(expectedSortOrder.Select(index => unsortedColumns[index]).ToArray(), builtColumns);

        var buildChecksum = (int)(bindingLookupBuildNearestDeclarationIndexChecksumInto.Invoke(
            null,
            new object[]
            {
                unsortedNameIds,
                unsortedFileRanks,
                unsortedLines,
                unsortedColumns,
                new int[unsortedNameIds.Length],
                new int[unsortedNameIds.Length],
                new int[unsortedNameIds.Length],
                new int[unsortedNameIds.Length],
                new int[unsortedNameIds.Length],
                new int[unsortedNameIds.Length],
                new int[unsortedNameIds.Length]
            }) ?? -1);
        var expectedBuildChecksum = unsortedNameIds.Length * 17;
        for (var i = 0; i < expectedSortOrder.Length; i++)
        {
            var declarationIndex = expectedSortOrder[i];
            expectedBuildChecksum += (i + 1) * 97
                + unsortedNameIds[declarationIndex] * 31
                + unsortedFileRanks[declarationIndex] * 23
                + unsortedLines[declarationIndex] * 13
                + unsortedColumns[declarationIndex] * 7
                + declarationIndex * 3;
        }

        Assert.Equal(expectedBuildChecksum, buildChecksum);

        var uniqueNameIds = new[] { 1, 2, 3 };
        var uniqueFileRanks = new[] { 1, 1, 1 };
        var uniqueLines = new[] { 1, 2, 3 };
        var uniqueColumns = new[] { 1, 1, 1 };
        var uniqueBuiltIndices = new int[uniqueNameIds.Length];
        var uniqueBuildCount = (int)(bindingLookupBuildNearestDeclarationIndexInto.Invoke(
            null,
            new object[]
            {
                uniqueNameIds,
                uniqueFileRanks,
                uniqueLines,
                uniqueColumns,
                new int[uniqueNameIds.Length + 1],
                new int[uniqueNameIds.Length + 1],
                new int[uniqueNameIds.Length],
                new int[uniqueNameIds.Length],
                new int[uniqueNameIds.Length],
                new int[uniqueNameIds.Length],
                uniqueBuiltIndices
            }) ?? -1);

        Assert.Equal(uniqueNameIds.Length, uniqueBuildCount);
        Assert.Equal(new[] { 0, 1, 2 }, uniqueBuiltIndices);

        var outOfOrderBuildCount = (int)(bindingLookupBuildNearestDeclarationIndexInto.Invoke(
            null,
            new object[]
            {
                new[] { 1, 1 },
                new[] { 1, 1 },
                new[] { 8, 2 },
                new[] { 1, 1 },
                new int[2],
                new int[2],
                new int[2],
                new int[2],
                new int[2],
                new int[2],
                new int[2]
            }) ?? -2);

        Assert.Equal(-1, outOfOrderBuildCount);

        var sortedNameIds = new[] { 1, 1, 1, 1, 2 };
        var sortedFileRanks = new[] { 1, 1, 1, 2, 1 };
        var sortedLines = new[] { 2, 8, 8, 10, 3 };
        var sortedColumns = new[] { 3, 1, 4, 1, 1 };
        var sortedDeclarationIndices = new[] { 0, 1, 2, 4, 3 };
        var nearestQueryNameIds = new[] { 1, 1, 1, 2, 3, 1 };
        var nearestQueryFileRanks = new[] { 1, 1, 1, 1, 1, 2 };
        var nearestQueryLines = new[] { 1, 7, 8, 99, 99, 10 };
        var expectedNearest = new[] { -1, 0, 2, 3, -1, 4 };

        var nearestResultIndices = new int[nearestQueryNameIds.Length];
        var nearestCount = (int)(bindingLookupFindNearestDeclarationIndicesInto.Invoke(
            null,
            new object[]
            {
                sortedNameIds,
                sortedFileRanks,
                sortedLines,
                sortedColumns,
                sortedDeclarationIndices,
                nearestQueryNameIds,
                nearestQueryFileRanks,
                nearestQueryLines,
                nearestResultIndices
            }) ?? -1);

        Assert.Equal(4, nearestCount);
        Assert.Equal(expectedNearest, nearestResultIndices);

        var nearestChecksumResultIndices = new int[nearestQueryNameIds.Length];
        var nearestChecksum = (int)(bindingLookupFindNearestDeclarationChecksumInto.Invoke(
            null,
            new object[]
            {
                sortedNameIds,
                sortedFileRanks,
                sortedLines,
                sortedColumns,
                sortedDeclarationIndices,
                nearestQueryNameIds,
                nearestQueryFileRanks,
                nearestQueryLines,
                nearestChecksumResultIndices
            }) ?? -1);

        var expectedNearestChecksum = 4;
        foreach (var declarationIndex in expectedNearest.Where(index => index >= 0))
        {
            var sortedIndex = Array.IndexOf(sortedDeclarationIndices, declarationIndex);
            expectedNearestChecksum += sortedNameIds[sortedIndex] * 13
                + sortedLines[sortedIndex] * 31
                + sortedColumns[sortedIndex] * 17
                + declarationIndex;
        }

        Assert.Equal(expectedNearestChecksum, nearestChecksum);
        Assert.Equal(expectedNearest, nearestChecksumResultIndices);
    }

    private static int[][] BuildExpectedBindingCandidateColumns(
        int[] queryColumns,
        int[] spanStartColumns,
        int[] spanEndColumns)
    {
        var result = new int[queryColumns.Length][];
        for (var i = 0; i < queryColumns.Length; i++)
        {
            var column = queryColumns[i];
            var seen = new HashSet<int>();
            if (column > 0)
                seen.Add(column);
            if (column > 1)
                seen.Add(column - 1);
            seen.Add(column + 1);

            var spanStart = spanStartColumns[i];
            var spanEnd = spanEndColumns[i];
            if (spanStart > 0 && spanEnd >= spanStart)
            {
                for (var candidate = spanStart; candidate <= spanEnd; candidate++)
                {
                    seen.Add(candidate);
                }
            }

            result[i] = seen.OrderBy(candidate => Math.Abs(candidate - column)).ToArray();
        }

        return result;
    }

    private static int[] FlattenExpectedBindingCandidateColumns(
        int[][] expectedColumns,
        int[] starts,
        int[] counts)
    {
        var total = expectedColumns.Sum(columns => columns.Length);
        var flat = new int[total];
        var offset = 0;
        for (var i = 0; i < expectedColumns.Length; i++)
        {
            starts[i] = offset;
            counts[i] = expectedColumns[i].Length;
            Array.Copy(expectedColumns[i], 0, flat, offset, expectedColumns[i].Length);
            offset += expectedColumns[i].Length;
        }

        return flat;
    }

    private static int CandidateColumnChecksum(
        int total,
        int[] starts,
        int[] counts,
        int[] columns)
    {
        var checksum = total;
        for (var i = 0; i < counts.Length; i++)
        {
            var start = starts[i];
            var count = counts[i];
            checksum += count * 97 + start * 7;
            for (var j = 0; j < count; j++)
            {
                checksum += columns[start + j] * 31 + (j + 1) * 17;
            }
        }

        return checksum;
    }

    private static void AssertSemanticScopeVisibleVariablesLikeProduction(
        MethodInfo semanticScopeVisibleSymbolIndicesInto,
        MethodInfo semanticScopeVisibleSymbolChecksumInto,
        MethodInfo semanticScopeBuildSortedIndexInto,
        MethodInfo semanticScopeBuildSortedIndexChecksumInto,
        MethodInfo semanticScopeBuildDepthsInto,
        MethodInfo semanticScopeBuildDepthChecksumInto,
        MethodInfo semanticScopeLookupSymbolIndicesInto,
        MethodInfo semanticScopeLookupSymbolChecksumInto)
    {
        var model = new SemanticModel();
        var root = model.OpenScope(-1, 1, 1);
        model.RecordScopedVariable(root, "x", BuiltInTypes.Int);
        model.RecordScopedVariable(root, "y", BuiltInTypes.String);

        var inner = model.OpenScope(root, 5, 1);
        model.RecordScopedVariable(inner, "x", BuiltInTypes.Bool);
        model.RecordScopedVariable(inner, "z", BuiltInTypes.Double);
        model.RecordScopedFunction(inner, "localFunc", new SimpleTypeInfo("fn"));
        model.CloseScope(inner, 10, 120);

        var sibling = model.OpenScope(root, 12, 1);
        model.RecordScopedVariable(sibling, "sibling", BuiltInTypes.Char);
        model.CloseScope(sibling, 15, 120);

        var open = model.OpenScope(root, 18, 1);
        model.RecordScopedVariable(open, "openOnly", BuiltInTypes.Object);
        model.CloseScope(root, 20, 120);

        var scopeParentIds = new[] { -1, 0, 0, 0 };
        var scopeStartLines = new[] { 1, 5, 12, 18 };
        var scopeStartColumns = new[] { 1, 1, 1, 1 };
        var scopeEndLines = new[] { 20, 10, 15, 0 };
        var scopeEndColumns = new[] { 120, 120, 120, 0 };
        var scopeDepths = new[] { 0, 1, 1, 1 };
        var scopeSymbolStarts = new[] { 0, 2, 5, 6 };
        var scopeSymbolCounts = new[] { 2, 3, 1, 1 };
        var symbolNames = new[] { "x", "y", "x", "z", "localFunc", "sibling", "openOnly" };
        var symbolTypeNames = new[] { "int", "string", "bool", "double", "fn", "char", "object" };
        var symbolNameIds = CreateOrdinalIds(symbolNames);
        var symbolNameLengths = symbolNames.Select(static name => name.Length).ToArray();
        var symbolTypeNameLengths = symbolTypeNames.Select(static name => name.Length).ToArray();
        var sortedScopeIds = new[] { 0, 1, 2, 3 };
        var sortedScopeStartLines = sortedScopeIds.Select(id => scopeStartLines[id]).ToArray();
        var sortedScopeStartColumns = sortedScopeIds.Select(id => scopeStartColumns[id]).ToArray();
        var sortedScopeMaxEndLines = BuildPrefixMaxEndLines(sortedScopeIds, scopeEndLines);

        var builtScopeDepths = new int[scopeParentIds.Length];
        var builtDepthCount = (int)(semanticScopeBuildDepthsInto.Invoke(
            null,
            new object[] { scopeParentIds, builtScopeDepths }) ?? -1);
        Assert.Equal(scopeParentIds.Length, builtDepthCount);
        Assert.Equal(scopeDepths, builtScopeDepths);

        var nestedScopeParentIds = new[] { -1, 0, 1, 2, 1, 4 };
        var expectedNestedScopeDepths = new[] { 0, 1, 2, 3, 2, 3 };
        var actualNestedScopeDepths = new int[nestedScopeParentIds.Length];
        var nestedDepthCount = (int)(semanticScopeBuildDepthsInto.Invoke(
            null,
            new object[] { nestedScopeParentIds, actualNestedScopeDepths }) ?? -1);
        Assert.Equal(nestedScopeParentIds.Length, nestedDepthCount);
        Assert.Equal(expectedNestedScopeDepths, actualNestedScopeDepths);

        var actualDepthChecksum = (int)(semanticScopeBuildDepthChecksumInto.Invoke(
            null,
            new object[] { nestedScopeParentIds, new int[nestedScopeParentIds.Length] }) ?? -1);
        var expectedDepthChecksum = nestedScopeParentIds.Length * 17;
        for (var i = 0; i < expectedNestedScopeDepths.Length; i++)
        {
            expectedDepthChecksum += (i + 1) * 31 + expectedNestedScopeDepths[i] * 7;
        }

        Assert.Equal(expectedDepthChecksum, actualDepthChecksum);

        var shuffledScopeStartLines = new[] { 12, 1, 18, 5 };
        var shuffledScopeStartColumns = new[] { 1, 1, 1, 1 };
        var shuffledScopeEndLines = new[] { 15, 20, 0, 10 };
        var shuffledResultIds = new int[4];
        var shuffledResultStartLines = new int[4];
        var shuffledResultStartColumns = new int[4];
        var shuffledResultMaxEndLines = new int[4];
        var shuffledCount = (int)(semanticScopeBuildSortedIndexInto.Invoke(
            null,
            new object[]
            {
                shuffledScopeStartLines,
                shuffledScopeStartColumns,
                shuffledScopeEndLines,
                new int[4],
                new int[4],
                new int[4],
                shuffledResultIds,
                shuffledResultStartLines,
                shuffledResultStartColumns,
                shuffledResultMaxEndLines
            }) ?? -1);

        Assert.Equal(4, shuffledCount);
        Assert.Equal(new[] { 1, 3, 0, 2 }, shuffledResultIds);
        Assert.Equal(new[] { 1, 5, 12, 18 }, shuffledResultStartLines);
        Assert.Equal(new[] { 1, 1, 1, 1 }, shuffledResultStartColumns);
        Assert.Equal(new[] { 20, 20, 20, 20 }, shuffledResultMaxEndLines);

        var actualIndexChecksum = (int)(semanticScopeBuildSortedIndexChecksumInto.Invoke(
            null,
            new object[]
            {
                scopeStartLines,
                scopeStartColumns,
                scopeEndLines,
                new int[scopeStartLines.Length],
                new int[scopeStartLines.Length],
                new int[scopeStartLines.Length],
                new int[scopeStartLines.Length],
                new int[scopeStartLines.Length],
                new int[scopeStartLines.Length],
                new int[scopeStartLines.Length]
            }) ?? -1);
        var expectedIndexChecksum = scopeStartLines.Length * 17;
        for (var i = 0; i < sortedScopeIds.Length; i++)
        {
            expectedIndexChecksum += (i + 1) * 97
                + (sortedScopeIds[i] + 1) * 31
                + sortedScopeStartLines[i] * 13
                + sortedScopeStartColumns[i] * 7
                + sortedScopeMaxEndLines[i] * 3;
        }

        Assert.Equal(expectedIndexChecksum, actualIndexChecksum);

        var queryLines = new[] { 2, 6, 13, 19, 30 };
        var queryColumns = new[] { 10, 10, 10, 10, 10 };
        var expectedScopeIds = new[] { 0, 1, 2, 0, -1 };
        var expectedVisibleNames = new[]
        {
            model.GetVisibleVariablesAtPosition(2, 10).Keys.ToArray(),
            model.GetVisibleVariablesAtPosition(6, 10).Keys.ToArray(),
            model.GetVisibleVariablesAtPosition(13, 10).Keys.ToArray(),
            model.GetVisibleVariablesAtPosition(19, 10).Keys.ToArray(),
            Array.Empty<string>()
        };

        var resultScopeIds = new int[queryLines.Length];
        var resultStarts = new int[queryLines.Length];
        var resultCounts = new int[queryLines.Length];
        var resultSymbolIndices = new int[64];
        var slotNameIds = new int[symbolNames.Length * 2 + 1];
        var touchedSlots = new int[symbolNames.Length];
        var total = (int)(semanticScopeVisibleSymbolIndicesInto.Invoke(
            null,
            new object[]
            {
                scopeParentIds,
                scopeStartLines,
                scopeStartColumns,
                scopeEndLines,
                scopeEndColumns,
                scopeDepths,
                scopeSymbolStarts,
                scopeSymbolCounts,
                symbolNameIds,
                sortedScopeIds,
                sortedScopeStartLines,
                sortedScopeStartColumns,
                sortedScopeMaxEndLines,
                queryLines,
                queryColumns,
                resultScopeIds,
                resultStarts,
                resultCounts,
                resultSymbolIndices,
                slotNameIds,
                touchedSlots
            }) ?? -1);

        Assert.Equal(expectedScopeIds, resultScopeIds);
        Assert.Equal(expectedVisibleNames.Sum(static names => names.Length), total);
        for (var queryIndex = 0; queryIndex < queryLines.Length; queryIndex++)
        {
            var actualNames = resultSymbolIndices
                .Skip(resultStarts[queryIndex])
                .Take(resultCounts[queryIndex])
                .Select(index => symbolNames[index])
                .ToArray();
            Assert.Equal(expectedVisibleNames[queryIndex], actualNames);
        }

        Array.Clear(resultScopeIds);
        Array.Clear(resultStarts);
        Array.Clear(resultCounts);
        Array.Clear(resultSymbolIndices);
        Array.Clear(slotNameIds);
        Array.Clear(touchedSlots);

        var actualChecksum = (int)(semanticScopeVisibleSymbolChecksumInto.Invoke(
            null,
            new object[]
            {
                scopeParentIds,
                scopeStartLines,
                scopeStartColumns,
                scopeEndLines,
                scopeEndColumns,
                scopeDepths,
                scopeSymbolStarts,
                scopeSymbolCounts,
                symbolNameIds,
                symbolNameLengths,
                symbolTypeNameLengths,
                sortedScopeIds,
                sortedScopeStartLines,
                sortedScopeStartColumns,
                sortedScopeMaxEndLines,
                queryLines,
                queryColumns,
                resultScopeIds,
                resultStarts,
                resultCounts,
                resultSymbolIndices,
                slotNameIds,
                touchedSlots
            }) ?? -1);
        var expectedChecksum = total * 17;
        for (var queryIndex = 0; queryIndex < queryLines.Length; queryIndex++)
        {
            expectedChecksum += (expectedScopeIds[queryIndex] + 1) * 31;
            for (var i = 0; i < resultCounts[queryIndex]; i++)
            {
                var symbolIndex = resultSymbolIndices[resultStarts[queryIndex] + i];
                expectedChecksum += symbolNameLengths[symbolIndex] * 13
                    + symbolTypeNameLengths[symbolIndex] * 7
                    + (i + 1);
            }
        }

        Assert.Equal(expectedChecksum, actualChecksum);

        var lookupQueryNames = new[] { "x", "y", "z", "localFunc", "sibling", "openOnly", "x", "missing" };
        var lookupQueryLines = new[] { 6, 6, 6, 6, 13, 19, 19, 30 };
        var lookupQueryColumns = new[] { 10, 10, 10, 10, 10, 10, 10, 10 };
        var lookupQueryNameIds = CreateQueryNameIds(symbolNames, symbolNameIds, lookupQueryNames);
        var expectedLookupScopeIds = new[] { 1, 1, 1, 1, 2, 0, 0, -1 };
        var lookupResultScopeIds = new int[lookupQueryNames.Length];
        var lookupResultSymbolIndices = new int[lookupQueryNames.Length];

        var found = (int)(semanticScopeLookupSymbolIndicesInto.Invoke(
            null,
            new object[]
            {
                scopeParentIds,
                scopeStartLines,
                scopeStartColumns,
                scopeEndLines,
                scopeEndColumns,
                scopeDepths,
                scopeSymbolStarts,
                scopeSymbolCounts,
                symbolNameIds,
                sortedScopeIds,
                sortedScopeStartLines,
                sortedScopeStartColumns,
                sortedScopeMaxEndLines,
                lookupQueryNameIds,
                lookupQueryLines,
                lookupQueryColumns,
                lookupResultScopeIds,
                lookupResultSymbolIndices
            }) ?? -1);

        var expectedLookupTypes = lookupQueryNames
            .Select((name, index) => model.LookupIdentifierAtPosition(name, lookupQueryLines[index], lookupQueryColumns[index]))
            .ToArray();
        Assert.Equal(expectedLookupTypes.Count(static type => type != null), found);
        Assert.Equal(expectedLookupScopeIds, lookupResultScopeIds);
        for (var queryIndex = 0; queryIndex < lookupQueryNames.Length; queryIndex++)
        {
            var expectedType = expectedLookupTypes[queryIndex];
            var symbolIndex = lookupResultSymbolIndices[queryIndex];
            if (expectedType == null)
            {
                Assert.Equal(-1, symbolIndex);
            }
            else
            {
                Assert.InRange(symbolIndex, 0, symbolTypeNames.Length - 1);
                Assert.Equal(expectedType.ToString(), symbolTypeNames[symbolIndex]);
            }
        }

        Array.Clear(lookupResultScopeIds);
        Array.Clear(lookupResultSymbolIndices);

        var actualLookupChecksum = (int)(semanticScopeLookupSymbolChecksumInto.Invoke(
            null,
            new object[]
            {
                scopeParentIds,
                scopeStartLines,
                scopeStartColumns,
                scopeEndLines,
                scopeEndColumns,
                scopeDepths,
                scopeSymbolStarts,
                scopeSymbolCounts,
                symbolNameIds,
                symbolNameLengths,
                symbolTypeNameLengths,
                sortedScopeIds,
                sortedScopeStartLines,
                sortedScopeStartColumns,
                sortedScopeMaxEndLines,
                lookupQueryNameIds,
                lookupQueryLines,
                lookupQueryColumns,
                lookupResultScopeIds,
                lookupResultSymbolIndices
            }) ?? -1);

        var expectedLookupChecksum = found * 17;
        for (var queryIndex = 0; queryIndex < lookupQueryNames.Length; queryIndex++)
        {
            expectedLookupChecksum += (expectedLookupScopeIds[queryIndex] + 1) * 31;
            var expectedType = expectedLookupTypes[queryIndex];
            if (expectedType != null)
            {
                expectedLookupChecksum += lookupQueryNames[queryIndex].Length * 13
                    + expectedType.ToString().Length * 7;
            }
        }

        Assert.Equal(expectedLookupChecksum, actualLookupChecksum);
    }

    private static int[] BuildPrefixMaxEndLines(int[] sortedScopeIds, int[] scopeEndLines)
    {
        var result = new int[sortedScopeIds.Length];
        var max = 0;
        for (var i = 0; i < sortedScopeIds.Length; i++)
        {
            var endLine = scopeEndLines[sortedScopeIds[i]];
            if (endLine > max)
                max = endLine;

            result[i] = max;
        }

        return result;
    }

    private static int[] CreateOrdinalIds(string[] values)
    {
        var idsByValue = new Dictionary<string, int>(StringComparer.Ordinal);
        var ids = new int[values.Length];
        for (var i = 0; i < values.Length; i++)
        {
            if (!idsByValue.TryGetValue(values[i], out var id))
            {
                id = idsByValue.Count + 1;
                idsByValue.Add(values[i], id);
            }

            ids[i] = id;
        }

        return ids;
    }

    private static int[] CreateQueryNameIds(string[] symbolNames, int[] symbolNameIds, string[] queryNames)
    {
        var idsByValue = new Dictionary<string, int>(StringComparer.Ordinal);
        var maxId = 0;
        for (var i = 0; i < symbolNames.Length; i++)
        {
            idsByValue.TryAdd(symbolNames[i], symbolNameIds[i]);
            if (symbolNameIds[i] > maxId)
                maxId = symbolNameIds[i];
        }

        var ids = new int[queryNames.Length];
        for (var i = 0; i < queryNames.Length; i++)
        {
            if (!idsByValue.TryGetValue(queryNames[i], out var id))
            {
                id = ++maxId;
                idsByValue.Add(queryNames[i], id);
            }

            ids[i] = id;
        }

        return ids;
    }

    private static int[] CreateSortedFileRanks(string[] files)
    {
        var uniqueFiles = files.Distinct(StringComparer.Ordinal).ToArray();
        Array.Sort(uniqueFiles, Comparer<string>.Default);

        var ranksByFile = new Dictionary<string, int>(StringComparer.Ordinal);
        for (var i = 0; i < uniqueFiles.Length; i++)
        {
            ranksByFile.Add(uniqueFiles[i], i + 1);
        }

        var ranks = new int[files.Length];
        for (var i = 0; i < files.Length; i++)
        {
            ranks[i] = ranksByFile[files[i]];
        }

        return ranks;
    }

    private static List<DiagnosticResult> BuildDiagnosticSeveritySummaryDiagnostics()
    {
        return new List<DiagnosticResult>
        {
            BuildDiagnosticWithSeverity("error", 1),
            BuildDiagnosticWithSeverity("warning", 2),
            BuildDiagnosticWithSeverity("info", 3),
            BuildDiagnosticWithSeverity("hint", 4),
            BuildDiagnosticWithSeverity("info", 5),
            BuildDiagnosticWithSeverity("error", 6)
        };
    }

    private static List<SymbolResult> BuildSymbolKindFilterSymbols()
    {
        return new List<SymbolResult>
        {
            BuildSymbol("main", SymbolKind.Function, 1),
            BuildSymbol("Customer", SymbolKind.Class, 5),
            BuildSymbol("Name", SymbolKind.Property, 7),
            BuildSymbol("helper", SymbolKind.Function, 12),
            BuildSymbol("value", SymbolKind.Variable, 13),
            BuildSymbol("render", SymbolKind.Method, 18),
            BuildSymbol("calculate", SymbolKind.Function, 24)
        };
    }

    private static SymbolResult BuildSymbol(string name, SymbolKind kind, int line)
    {
        return new SymbolResult(
            name,
            kind,
            "Program.nl",
            line,
            1,
            null,
            null,
            null,
            null);
    }

    private static DiagnosticResult BuildDiagnosticWithSeverity(string severity, int line)
    {
        return new DiagnosticResult(
            "NL900",
            severity,
            $"Synthetic {severity} diagnostic",
            "Program.nl",
            line,
            1,
            1,
            "value := input",
            null,
            null,
            null,
            null,
            null,
            null);
    }

    private static (int StartColumn, int Length) FindFirstIdentifierSpan(string lineText)
    {
        for (var i = 0; i < lineText.Length; i++)
        {
            if (!IsIdentifierChar(lineText[i]))
                continue;

            var start = i;
            while (i + 1 < lineText.Length && IsIdentifierChar(lineText[i + 1]))
                i++;

            return (start + 1, i - start + 1);
        }

        return (1, 1);
    }

    private static (int StartColumn, int Length)? ExtractIdentifierSpanAtPosition(string source, int line, int col)
    {
        try
        {
            var lines = source.Split('\n');
            if (line <= 0 || line > lines.Length)
                return null;

            var lineText = lines[line - 1];
            if (lineText.Length == 0)
                return null;

            var index = FindNearestIdentifierIndex(lineText, Math.Clamp(col - 1, 0, lineText.Length - 1));
            if (index < 0)
                return null;

            var start = index;
            while (start > 0 && IsIdentifierChar(lineText[start - 1]))
                start--;

            var end = index;
            while (end + 1 < lineText.Length && IsIdentifierChar(lineText[end + 1]))
                end++;

            return (start + 1, end - start + 1);
        }
        catch
        {
            return null;
        }
    }

    private static (int StartColumn, int Length)? ExtractEditorIdentifierSpanAtPosition(string source, int line, int col)
    {
        try
        {
            var lines = source.Split('\n');
            if (line <= 0 || line > lines.Length || col <= 0)
                return null;

            var lineText = lines[line - 1];
            if (lineText.Length == 0)
                return null;

            var index = col - 1;
            if (index >= lineText.Length)
            {
                index = lineText.Length - 1;
                if (!IsIdentifierChar(lineText[index]))
                    return null;
            }
            else if (!IsIdentifierChar(lineText[index]))
            {
                return null;
            }

            var start = index;
            while (start > 0 && IsIdentifierChar(lineText[start - 1]))
                start--;

            var end = index;
            while (end + 1 < lineText.Length && IsIdentifierChar(lineText[end + 1]))
                end++;

            return (start + 1, end - start + 1);
        }
        catch
        {
            return null;
        }
    }

    private static int FindNearestIdentifierIndex(string lineText, int index)
    {
        if (lineText.Length == 0)
            return -1;

        if (index >= 0 && index < lineText.Length && IsIdentifierChar(lineText[index]))
            return index;

        const int MaxDistance = 3;
        for (var distance = 1; distance <= MaxDistance; distance++)
        {
            var left = index - distance;
            if (left >= 0 && IsIdentifierChar(lineText[left]) && IsSnapFriendlyNeighbor(lineText, left + 1, index))
                return left;

            var right = index + distance;
            if (right < lineText.Length && IsIdentifierChar(lineText[right]) && IsSnapFriendlyNeighbor(lineText, index, right - 1))
                return right;
        }

        return -1;
    }

    private static bool IsIdentifierChar(char ch) => char.IsLetterOrDigit(ch) || ch == '_';

    private static bool IsSnapFriendlyNeighbor(string lineText, int start, int end)
    {
        if (start > end)
            return true;

        for (var i = start; i <= end; i++)
        {
            if (i < 0 || i >= lineText.Length)
                continue;

            var ch = lineText[i];
            if (char.IsWhiteSpace(ch))
                continue;

            if (ch is '.' or '?' or '(' or ')' or '[' or ']' or '{' or '}' or ',' or ';' or ':')
                continue;

            return false;
        }

        return true;
    }

    private static int FindNameStartColumn(string lineText, string name, int searchStartColumn)
    {
        var searchStart = Math.Max(0, searchStartColumn - 1);
        var index = lineText.IndexOf(name, searchStart, StringComparison.Ordinal);
        Assert.True(index >= 0, $"Expected to find {name} in {lineText} at or after column {searchStartColumn}.");
        return index + 1;
    }

    private static int FindWholeIdentifierColumn(string lineText, string name, int searchStartColumn)
    {
        var index = FindWholeIdentifier(lineText, name, searchStartColumn - 1);
        Assert.True(index >= 0, $"Expected to find whole identifier {name} in {lineText} at or after column {searchStartColumn}.");
        return index + 1;
    }

    private static bool TryFindIdentifierNameColumn(
        string? sourceText,
        string name,
        int line,
        int fallbackColumn,
        out int column)
    {
        column = fallbackColumn;
        if (string.IsNullOrWhiteSpace(sourceText) || line <= 0)
            return false;

        var lines = sourceText.Split('\n');
        if (line > lines.Length)
            return false;

        var lineText = lines[line - 1].TrimEnd('\r');
        if (lineText.Length == 0)
            return false;

        var start = Math.Clamp(fallbackColumn - 1, 0, lineText.Length);
        var index = FindWholeIdentifier(lineText, name, start);
        if (index < 0)
        {
            index = FindWholeIdentifier(lineText, name, 0);
        }

        if (index < 0)
            return false;

        column = index + 1;
        return true;
    }

    private static int FindWholeIdentifier(string line, string name, int startIndex)
    {
        var searchStart = Math.Clamp(startIndex, 0, line.Length);
        while (searchStart <= line.Length)
        {
            var index = line.IndexOf(name, searchStart, StringComparison.Ordinal);
            if (index < 0)
                return -1;

            var before = index > 0 ? line[index - 1] : '\0';
            var afterIndex = index + name.Length;
            var after = afterIndex < line.Length ? line[afterIndex] : '\0';
            if (!IsIdentifierChar(before) && !IsIdentifierChar(after))
                return index;

            searchStart = index + Math.Max(1, name.Length);
        }

        return -1;
    }

    private static bool SelectedSpanMatchesDeclarationName(
        string source,
        int line,
        int declarationColumn,
        string declarationName,
        int selectedStartColumn,
        int selectedEndColumn)
    {
        var lines = source.Split('\n');
        if (line <= 0 || line > lines.Length)
            return false;

        var lineText = lines[line - 1];
        var searchStart = Math.Max(0, Math.Min(declarationColumn - 1, lineText.Length));
        var nameIndex = lineText.IndexOf(declarationName, searchStart, StringComparison.Ordinal);
        if (nameIndex < 0)
            return false;

        var nameStartColumn = nameIndex + 1;
        var nameEndColumn = nameStartColumn + declarationName.Length - 1;
        return selectedStartColumn == nameStartColumn && selectedEndColumn == nameEndColumn;
    }

    private static (int StartColumn, int Length)? ExtractMemberReceiverSpan(string source, int line, int memberStartColumn)
    {
        try
        {
            var lines = source.Split('\n');
            if (line <= 0 || line > lines.Length)
                return null;

            var lineText = lines[line - 1];
            var memberStartIndex = memberStartColumn - 1;
            if (memberStartIndex <= 0 || memberStartIndex > lineText.Length)
                return null;

            var separatorIndex = memberStartIndex - 1;
            if (separatorIndex >= 0 && lineText[separatorIndex] == '.')
            {
                var receiverEnd = separatorIndex - 1;
                while (receiverEnd >= 0 && char.IsWhiteSpace(lineText[receiverEnd]))
                    receiverEnd--;
                if (receiverEnd < 0)
                    return null;

                var receiverStart = receiverEnd;
                while (receiverStart >= 0 && IsIdentifierChar(lineText[receiverStart]))
                    receiverStart--;

                receiverStart++;
                return receiverStart <= receiverEnd
                    ? (receiverStart + 1, receiverEnd - receiverStart + 1)
                    : null;
            }

            if (separatorIndex >= 1 && lineText[separatorIndex - 1] == '?' && lineText[separatorIndex] == '.')
            {
                var receiverEnd = separatorIndex - 2;
                while (receiverEnd >= 0 && char.IsWhiteSpace(lineText[receiverEnd]))
                    receiverEnd--;
                if (receiverEnd < 0)
                    return null;

                var receiverStart = receiverEnd;
                while (receiverStart >= 0 && IsIdentifierChar(lineText[receiverStart]))
                    receiverStart--;

                receiverStart++;
                return receiverStart <= receiverEnd
                    ? (receiverStart + 1, receiverEnd - receiverStart + 1)
                    : null;
            }

            return null;
        }
        catch
        {
            return null;
        }
    }

    private static string? ExtractCompletionPrefix(string source, int line, int column)
    {
        var lines = source.Split('\n');
        if (line <= 0 || line > lines.Length)
            return null;

        var lineText = lines[line - 1];
        return column > 0 && column <= lineText.Length
            ? lineText.Substring(0, column)
            : lineText;
    }

    private static string? ExtractDocComment(string source, int definitionLine)
    {
        var spans = ExtractDocCommentSpans(source, definitionLine);
        return spans.Count > 0
            ? string.Join("\n", spans.Select(span => source.Substring(span.Start, span.Length)))
            : null;
    }

    private static List<(int Start, int Length)> ExtractDocCommentSpans(string source, int definitionLine)
    {
        var spans = new List<(int Start, int Length)>();
        var lines = source.Split('\n');
        if (definitionLine <= 1 || definitionLine > lines.Length)
            return spans;

        var startLine = -1;
        var commentCount = 0;
        for (var i = definitionLine - 2; i >= 0; i--)
        {
            var trimmed = lines[i].Trim();
            if (trimmed.StartsWith("//", StringComparison.Ordinal))
            {
                startLine = i;
                commentCount++;
            }
            else if (string.IsNullOrWhiteSpace(trimmed) && commentCount == 0)
            {
                continue;
            }
            else
            {
                break;
            }
        }

        if (startLine < 0)
            return spans;

        var lineStarts = BuildLfLineStarts(source);
        for (var i = startLine; i <= definitionLine - 2; i++)
        {
            var span = ExtractDocCommentContentSpan(lines[i], lineStarts[i]);
            if (span != null)
            {
                spans.Add(span.Value);
            }
        }

        return spans;
    }

    private static (int Start, int Length)? ExtractDocCommentContentSpan(string lineText, int lineStart)
    {
        var trimStart = 0;
        var trimEnd = lineText.Length - 1;

        while (trimStart <= trimEnd && char.IsWhiteSpace(lineText[trimStart]))
            trimStart++;

        while (trimEnd >= trimStart && char.IsWhiteSpace(lineText[trimEnd]))
            trimEnd--;

        if (trimStart + 1 > trimEnd || lineText[trimStart] != '/' || lineText[trimStart + 1] != '/')
            return null;

        while (trimStart <= trimEnd && lineText[trimStart] == '/')
            trimStart++;

        while (trimStart <= trimEnd && char.IsWhiteSpace(lineText[trimStart]))
            trimStart++;

        while (trimEnd >= trimStart && char.IsWhiteSpace(lineText[trimEnd]))
            trimEnd--;

        return trimEnd < trimStart
            ? (lineStart + trimStart, 0)
            : (lineStart + trimStart, trimEnd - trimStart + 1);
    }

    private static string? MaterializeDocComment(string source, int[] starts, int[] lengths, int count)
    {
        if (count <= 0)
            return null;

        return string.Join("\n", Enumerable.Range(0, count).Select(i => source.Substring(starts[i], lengths[i])));
    }

    private static string? ExtractVariableDeclarationName(string source, int line)
    {
        var span = ExtractVariableDeclarationNameSpan(source, line);
        if (span == null)
            return null;

        var lineText = source.Split('\n')[line - 1];
        return lineText.Substring(span.Value.StartColumn - 1, span.Value.Length);
    }

    private static (int StartColumn, int Length)? ExtractVariableDeclarationNameSpan(string source, int line)
    {
        try
        {
            var lines = source.Split('\n');
            if (line <= 0 || line > lines.Length)
                return null;

            var lineText = lines[line - 1];
            var assignIndex = lineText.IndexOf(":=", StringComparison.Ordinal);
            if (assignIndex <= 0)
                return null;

            var end = assignIndex - 1;
            while (end >= 0 && char.IsWhiteSpace(lineText[end]))
                end--;
            if (end < 0)
                return null;

            var start = end;
            while (start >= 0 && IsIdentifierChar(lineText[start]))
                start--;

            start++;
            return start <= end
                ? (start + 1, end - start + 1)
                : null;
        }
        catch
        {
            return null;
        }
    }

    private static int BuildLineRanges(string source, int[] starts, int[] lengths)
    {
        var lineStart = 0;
        var count = 0;

        for (var position = 0; position < source.Length; position++)
        {
            if (source[position] != '\n')
                continue;

            starts[count] = lineStart;
            lengths[count] = position - lineStart;
            count++;
            lineStart = position + 1;
        }

        starts[count] = lineStart;
        lengths[count] = source.Length - lineStart;
        return count + 1;
    }

    private static int LineIndexFromOffset(int[] starts, int sourceLength, int offset)
    {
        if (offset < 0)
        {
            offset = 0;
        }

        if (offset > sourceLength)
        {
            offset = sourceLength;
        }

        var result = 0;
        for (var i = 0; i < starts.Length; i++)
        {
            if (starts[i] <= offset)
            {
                result = i;
            }
        }

        return result;
    }

    private static int ColumnFromOffset(int[] starts, int sourceLength, int offset)
    {
        if (offset < 0)
        {
            offset = 0;
        }

        if (offset > sourceLength)
        {
            offset = sourceLength;
        }

        return offset - starts[LineIndexFromOffset(starts, sourceLength, offset)];
    }

    private static int[] BuildOffsetLineIndices(int[] starts, int lineCount, int sourceLength)
    {
        var offsetLineIndices = new int[sourceLength + 1];
        for (var lineIndex = 0; lineIndex < lineCount; lineIndex++)
        {
            var lineStart = starts[lineIndex];
            var endExclusive = lineIndex + 1 < lineCount ? starts[lineIndex + 1] : sourceLength + 1;
            for (var offset = lineStart; offset < endExclusive && offset <= sourceLength; offset++)
            {
                offsetLineIndices[offset] = lineIndex;
            }
        }

        return offsetLineIndices;
    }

    private static int[] BuildLfLineStarts(string source)
    {
        var starts = new List<int> { 0 };
        for (var i = 0; i < source.Length; i++)
        {
            if (source[i] == '\n')
            {
                starts.Add(i + 1);
            }
        }

        return starts.ToArray();
    }

    private static int CountOccurrences(string text, string value)
    {
        var count = 0;
        var startIndex = 0;
        while (true)
        {
            var index = text.IndexOf(value, startIndex, StringComparison.Ordinal);
            if (index < 0)
                return count;

            count++;
            startIndex = index + value.Length;
        }
    }

    private static string FindRepoRoot()
    {
        var dir = AppContext.BaseDirectory;
        while (dir != null)
        {
            if (File.Exists(Path.Combine(dir, "NSharpLang.sln")))
            {
                return dir;
            }

            dir = Path.GetDirectoryName(dir);
        }

        throw new InvalidOperationException(
            "Could not find repository root (NSharpLang.sln). "
                + $"Searched upward from {AppContext.BaseDirectory}");
    }

    private sealed class CompletionMethodGroupingFixture
    {
        public int Size { get; set; }

        public void Alpha()
        {
        }

        public void Alpha(int value)
        {
        }

        public string Beta(string value) => value;

        public static void Gamma()
        {
        }
    }
}
