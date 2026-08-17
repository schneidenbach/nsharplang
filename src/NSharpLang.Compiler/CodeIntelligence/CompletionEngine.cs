using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.IO;

namespace NSharpLang.Compiler.CodeIntelligence;

/// <summary>
/// Snapshot plumbing for completions, shared by the CLI, the daemon and the playground.
/// </summary>
/// <remarks>
/// This type holds no completion policy: everything here is reading a file's compilation unit,
/// semantic model and source text out of a snapshot and handing them to N#.
///
/// Every decision belongs elsewhere. <c>CompletionEngineKernels</c> decides whether a position is
/// after a dot and answers an identifier position; <c>CompletionReceiverFacts</c> answers a
/// member-access position; <c>CodeIntelligenceSourceTextKernels</c> extracts the prefix; and since
/// slice 21 the file lookup is <c>CodeIntelligenceNavigation.FindCompilationUnit</c> — the same
/// walk the service uses, where this type used to keep a second copy of it.
/// </remarks>
public class CompletionEngine
{
    /// <summary>
    /// Get completions at a position in a project.
    /// By default, identifier completions exclude keywords/primitives/modifiers (LLMs don't need them).
    /// Set includeKeywords=true to include them (for human/IDE use).
    /// </summary>
    public CompletionResult GetCompletions(ProjectSnapshot snapshot, string file, int line, int col, bool includeKeywords = false)
    {
        var match = CodeIntelligenceNavigation.FindCompilationUnit(snapshot, file);
        var filePath = match.FilePath;
        var cu = match.Unit;
        if (cu == null)
        {
            return EmptyResult(CompletionContext.Unknown);
        }

        snapshot.SemanticModels.TryGetValue(filePath, out var semanticModel);

        string? sourceText = null;
        if (!snapshot.SourceTexts.TryGetValue(filePath, out sourceText))
        {
            sourceText = File.ReadAllText(filePath);
        }

        if (sourceText == null)
        {
            return EmptyResult(CompletionContext.Unknown);
        }

        if (!TryExtractCompletionPrefix(snapshot, filePath, sourceText, line, col, out var beforeCursor))
        {
            return EmptyResult(CompletionContext.Unknown);
        }

        var completionReceiver = CompletionEngineKernels.ClassifyCompletionReceiver(beforeCursor);
        if (completionReceiver.IsMemberAccess)
        {
            return CompletionReceiverFacts.GetMemberAccessCompletions(
                cu,
                semanticModel,
                completionReceiver.Receiver,
                line,
                col,
                snapshot.SemanticModels.Values);
        }

        return CompletionEngineKernels.GetIdentifierCompletions(cu, semanticModel, includeKeywords, line, col);
    }

    private static bool TryExtractCompletionPrefix(
        ProjectSnapshot snapshot,
        string filePath,
        string sourceText,
        int line,
        int col,
        [NotNullWhen(true)] out string? beforeCursor)
    {
        if (!CodeIntelligenceSourceTextKernels.TryExtractCompletionPrefix(
                snapshot,
                filePath,
                sourceText,
                line,
                col,
                out var dogfoodPrefix))
            throw new InvalidOperationException("N# completion prefix kernel rejected the source.");

        beforeCursor = dogfoodPrefix;
        return beforeCursor != null;
    }

    private static CompletionResult EmptyResult(CompletionContext context)
    {
        return new CompletionResult(context, null, null, new Dictionary<string, List<CompletionItem>>());
    }
}
