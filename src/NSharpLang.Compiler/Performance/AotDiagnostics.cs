using System;
using System.Collections.Generic;
using System.Linq;

namespace NSharpLang.Compiler.Performance;

/// <summary>
/// Turns <see cref="AotBlocker"/> facts into Elm-quality compiler diagnostics. Under
/// <c>--aot</c> the diagnostics are emitted as build-blocking errors with a clear
/// "why this blocks AOT / what to do" explanation; otherwise the same facts feed the
/// advisory perf report. See docs/design/performance-compiler-refactor.md "Native AOT".
/// </summary>
public static class AotDiagnostics
{
    /// <summary>
    /// Build an Elm-style diagnostic for an AOT blocker. <paramref name="asError"/> controls
    /// whether the diagnostic blocks the build (true under <c>--aot</c>) or is advisory info.
    /// </summary>
    public static CompilerError ToDiagnostic(AotBlocker blocker, string? sourceSnippet, bool asError)
    {
        var severity = asError ? ErrorSeverity.Error : ErrorSeverity.Warning;
        var (title, why, fix) = Describe(blocker);

        var humanExplanation = asError
            ? $"This code blocks Native AOT, but you asked for an AOT-safe build (`--aot`):"
            : $"This code blocks Native AOT and trimming:";

        return new CompilerError(blocker.DiagnosticCode, title, blocker.Line, blocker.Column, severity)
        {
            FileName = blocker.File,
            SourceSnippet = sourceSnippet,
            Length = Math.Max(1, blocker.Length),
            HumanExplanation = humanExplanation,
            ContextualHint = why,
            Suggestion = fix,
            DocsUrl = DiagnosticCatalog.DocsUrlFor(blocker.DiagnosticCode.ToDiagnosticId()),
        };
    }

    private static (string Title, string Why, string Fix) Describe(AotBlocker blocker)
    {
        return blocker.DiagnosticCode switch
        {
            ErrorCode.AotReflectionUse => (
                $"`{blocker.Construct}` uses reflection, which blocks AOT",
                "Native AOT and the trimmer analyze your program statically. Reflection looks up\n" +
                "members by name at runtime, so the trimmer cannot tell which members you touch and\n" +
                "may strip them, and AOT cannot resolve them ahead of time.",
                $"Replace the reflective `{blocker.Construct}` with a direct, statically-typed call. " +
                "If you only need a member name, use `nameof(...)`. If you must keep reflection, mark the " +
                "API with `[RequiresUnreferencedCode]` and exclude it from your AOT build."),

            ErrorCode.AotMakeGenericType => (
                $"`{blocker.Construct}` instantiates a generic at runtime, which blocks AOT",
                "Native AOT only compiles the generic type and method combinations it can see at\n" +
                "compile time. Building one at runtime needs the JIT, which AOT does not ship.",
                $"Construct the generic statically (e.g. `List<T>` written out in source) instead of `{blocker.Construct}`. " +
                "If the set of type arguments is fixed, switch over them and call the concrete instantiations directly."),

            ErrorCode.AotDynamicCode => (
                $"`{blocker.Construct}` generates code at runtime, which blocks AOT",
                "Native AOT has no JIT. Activator, dynamic delegate creation, and Reflection.Emit all\n" +
                "produce or invoke code at runtime, which cannot run in an AOT image.",
                $"Replace `{blocker.Construct}` with a direct constructor call or a statically-bound delegate. " +
                "For factories, prefer a `switch` over known types that calls each constructor directly."),

            ErrorCode.AotExpressionTree => (
                $"`{blocker.Construct}` uses an expression tree, which blocks AOT",
                "Compiling a LINQ expression tree emits IL and JIT-compiles it at runtime. Native AOT\n" +
                "cannot emit or JIT code, so the compile step fails.",
                $"Rewrite `{blocker.Construct}` as an ordinary delegate (a lambda whose type is `Func<...>`/`Action<...>`), " +
                "which compiles ahead of time. Reserve `Expression<...>` for code paths excluded from AOT."),

            _ => (
                blocker.Construct,
                "This construct prevents Native AOT.",
                "Remove or guard the construct, or exclude this code path from your AOT build."),
        };
    }

    /// <summary>
    /// Produce diagnostics for a set of blockers. <paramref name="snippetLookup"/> supplies the
    /// source line for a given (file, line) so the diagnostic can render a caret.
    /// </summary>
    public static List<CompilerError> ToDiagnostics(
        IEnumerable<AotBlocker> blockers,
        Func<string, int, string?> snippetLookup,
        bool asError)
    {
        return blockers
            .Select(blocker => ToDiagnostic(blocker, snippetLookup(blocker.File, blocker.Line), asError))
            .ToList();
    }
}

internal static class ErrorCodeDiagnosticIdExtensions
{
    public static string ToDiagnosticId(this ErrorCode code) => $"NL{(int)code:D3}";
}
