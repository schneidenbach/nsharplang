using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
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
            var semanticScopeLookupSymbolIndicesInto = programType.GetMethod(
                    "SemanticScopeLookupSymbolIndicesInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SemanticScopeLookupSymbolIndicesInto.");
            var semanticScopeLookupSymbolChecksumInto = programType.GetMethod(
                    "SemanticScopeLookupSymbolChecksumInto",
                    BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
                ?? throw new InvalidOperationException("Dogfood assembly did not emit SemanticScopeLookupSymbolChecksumInto.");

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
            AssertCompletionPrefixesLikeProduction(
                "  first line  \n\tsecond line\r\n   \n\n café42  \n",
                codeIntelligenceCompletionPrefixChecksumInto,
                codeIntelligenceCompletionPrefixesInto,
                codeIntelligenceCompletionPrefixesFromLinesInto);
            AssertCompletionReceiversLikeProduction(
                codeIntelligenceCompletionReceiverChecksumInto,
                codeIntelligenceCompletionReceiversInto);
            AssertCliQueryPositionsLikeProduction(
                cliTryParsePositionInto,
                cliQueryPositionsInto,
                cliQueryPositionChecksumInto);
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
            AssertBindingLookupLikeProduction(
                bindingLookupBuildSlotsInto,
                bindingLookupQueryDeclarationIndicesInto,
                bindingLookupQueryChecksumInto,
                bindingLookupFindNearestDeclarationIndicesInto,
                bindingLookupFindNearestDeclarationChecksumInto);
            AssertSemanticScopeVisibleVariablesLikeProduction(
                semanticScopeVisibleSymbolIndicesInto,
                semanticScopeVisibleSymbolChecksumInto,
                semanticScopeLookupSymbolIndicesInto,
                semanticScopeLookupSymbolChecksumInto);
            AssertDiagnosticSeveritySummaryLikeProduction(
                diagnosticSeveritySummaryInto,
                diagnosticSeveritySummaryChecksumInto);
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

    private static void AssertBindingLookupLikeProduction(
        MethodInfo bindingLookupBuildSlotsInto,
        MethodInfo bindingLookupQueryDeclarationIndicesInto,
        MethodInfo bindingLookupQueryChecksumInto,
        MethodInfo bindingLookupFindNearestDeclarationIndicesInto,
        MethodInfo bindingLookupFindNearestDeclarationChecksumInto)
    {
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

    private static void AssertSemanticScopeVisibleVariablesLikeProduction(
        MethodInfo semanticScopeVisibleSymbolIndicesInto,
        MethodInfo semanticScopeVisibleSymbolChecksumInto,
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
}
