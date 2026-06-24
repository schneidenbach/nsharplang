using System;
using System.Collections.Generic;

namespace NSharpLang.Compiler;

/// <summary>
/// Token-stream preprocessor that resolves conditional-compilation directives
/// (<c>#if</c> / <c>#elif</c> / <c>#else</c> / <c>#endif</c>) against a set of
/// defined symbols, dropping the tokens that belong to inactive branches.
///
/// This runs between the lexer and the parser so that every downstream stage
/// (parse, analyze, IL emit) only ever sees the live branch. N# owns
/// conditional compilation rather than passing directives through to the C#
/// compiler — the defined-symbol set comes from the project (<c>project.yml</c>
/// <c>defines:</c>), the CLI (<c>--define</c>), and the build configuration
/// (<c>DEBUG</c> in debug builds).
///
/// Organizational directives (<c>#region</c> / <c>#endregion</c>) and any other
/// unrecognized directive (e.g. <c>#pragma</c>, <c>#nullable</c>) are passed
/// through unchanged when their enclosing branch is live, so they continue to
/// surface as <see cref="Ast.PreprocessorDirective"/> nodes.
/// </summary>
public static class Preprocessor
{
    /// <summary>
    /// Returns a token list with inactive <c>#if</c>/<c>#elif</c>/<c>#else</c>
    /// branches removed. The conditional directive tokens themselves are
    /// dropped; structural/organizational directives are preserved. The trailing
    /// <see cref="TokenType.Eof"/> token is always preserved so the parser
    /// terminates cleanly even when a directive is unbalanced. Malformed
    /// conditions and unbalanced directives are reported via
    /// <paramref name="errors"/> and fail safe (treated as excluded).
    /// </summary>
    public static List<Token> Process(
        IReadOnlyList<Token> tokens,
        IReadOnlySet<string> definedSymbols,
        string? fileName,
        List<CompilerError> errors)
    {
        var result = new List<Token>(tokens.Count);
        var stack = new Stack<Frame>();

        foreach (var token in tokens)
        {
            if (token.Type == TokenType.Eof)
            {
                // Always terminate the stream, even with an unbalanced '#if'.
                if (stack.Count > 0)
                {
                    AddError(errors, fileName, token,
                        "Unterminated '#if' directive: expected a matching '#endif'.");
                    stack.Clear();
                }

                result.Add(token);
                continue;
            }

            if (token.Type != TokenType.PreprocessorDirective)
            {
                if (IsEmitting(stack))
                {
                    result.Add(token);
                }

                continue;
            }

            var (keyword, argument) = SplitDirective(token.Value);
            switch (keyword)
            {
                case "if":
                    HandleIf(stack, argument, definedSymbols, token, fileName, errors);
                    break;
                case "elif":
                    HandleElif(stack, argument, definedSymbols, token, fileName, errors);
                    break;
                case "else":
                    HandleElse(stack, token, fileName, errors);
                    break;
                case "endif":
                    HandleEndif(stack, token, fileName, errors);
                    break;
                default:
                    // '#region'/'#endregion' and any other directive are organizational
                    // pass-through: keep them only when the surrounding branch is live.
                    if (IsEmitting(stack))
                    {
                        result.Add(token);
                    }

                    break;
            }
        }

        return result;
    }

    /// <summary>
    /// Tracks one <c>#if</c>/<c>#elif</c>/<c>#else</c>/<c>#endif</c> chain.
    /// </summary>
    private struct Frame
    {
        /// <summary>Whether the enclosing context was emitting when this chain opened.</summary>
        public bool ParentActive;

        /// <summary>Whether some branch in this chain has already matched.</summary>
        public bool BranchTaken;

        /// <summary>Whether the branch currently in scope emits its tokens.</summary>
        public bool CurrentActive;

        /// <summary>Whether an <c>#else</c> has been seen (no <c>#elif</c>/<c>#else</c> may follow).</summary>
        public bool SeenElse;
    }

    private static bool IsEmitting(Stack<Frame> stack)
        => stack.Count == 0 || stack.Peek().CurrentActive;

    private static void HandleIf(
        Stack<Frame> stack,
        string condition,
        IReadOnlySet<string> symbols,
        Token token,
        string? fileName,
        List<CompilerError> errors)
    {
        var parentActive = IsEmitting(stack);

        // Only evaluate (and report) the condition when the enclosing branch is live;
        // a malformed condition nested under an excluded branch must not raise errors.
        var taken = parentActive && EvaluateGuarded(condition, symbols, token, fileName, errors);

        stack.Push(new Frame
        {
            ParentActive = parentActive,
            BranchTaken = parentActive ? taken : true,
            CurrentActive = taken,
            SeenElse = false,
        });
    }

    private static void HandleElif(
        Stack<Frame> stack,
        string condition,
        IReadOnlySet<string> symbols,
        Token token,
        string? fileName,
        List<CompilerError> errors)
    {
        if (stack.Count == 0)
        {
            AddError(errors, fileName, token, "'#elif' directive without a matching '#if'.");
            return;
        }

        var frame = stack.Pop();
        if (frame.SeenElse)
        {
            AddError(errors, fileName, token, "'#elif' directive cannot appear after '#else'.");
            stack.Push(frame);
            return;
        }

        if (!frame.ParentActive)
        {
            frame.CurrentActive = false;
        }
        else if (frame.BranchTaken)
        {
            frame.CurrentActive = false;
        }
        else
        {
            var taken = EvaluateGuarded(condition, symbols, token, fileName, errors);
            frame.CurrentActive = taken;
            frame.BranchTaken = taken;
        }

        stack.Push(frame);
    }

    private static void HandleElse(
        Stack<Frame> stack,
        Token token,
        string? fileName,
        List<CompilerError> errors)
    {
        if (stack.Count == 0)
        {
            AddError(errors, fileName, token, "'#else' directive without a matching '#if'.");
            return;
        }

        var frame = stack.Pop();
        if (frame.SeenElse)
        {
            AddError(errors, fileName, token, "Multiple '#else' directives for a single '#if'.");
            stack.Push(frame);
            return;
        }

        frame.SeenElse = true;
        if (!frame.ParentActive)
        {
            frame.CurrentActive = false;
        }
        else
        {
            // '#else' is live only when no earlier branch in the chain matched.
            frame.CurrentActive = !frame.BranchTaken;
            frame.BranchTaken = true;
        }

        stack.Push(frame);
    }

    private static void HandleEndif(
        Stack<Frame> stack,
        Token token,
        string? fileName,
        List<CompilerError> errors)
    {
        if (stack.Count == 0)
        {
            AddError(errors, fileName, token, "'#endif' directive without a matching '#if'.");
            return;
        }

        stack.Pop();
    }

    private static bool EvaluateGuarded(
        string condition,
        IReadOnlySet<string> symbols,
        Token token,
        string? fileName,
        List<CompilerError> errors)
    {
        try
        {
            return ConditionEvaluator.Evaluate(condition, symbols);
        }
        catch (PreprocessorConditionException ex)
        {
            AddError(errors, fileName, token, ex.Message);
            return false; // fail safe: a malformed condition excludes its branch.
        }
    }

    private static void AddError(List<CompilerError> errors, string? fileName, Token token, string message)
    {
        errors.Add(new CompilerError(
            ErrorCode.InvalidPreprocessorDirective,
            message,
            token.Line,
            token.Column,
            ErrorSeverity.Error)
        {
            FileName = fileName,
            Length = Math.Max(1, token.Value?.Length ?? 1),
        });
    }

    /// <summary>
    /// Splits a raw directive token value (e.g. <c>"#if DEBUG // note"</c>) into its
    /// keyword (<c>"if"</c>) and trimmed argument (<c>"DEBUG"</c>), tolerating
    /// whitespace after <c>#</c> and stripping a trailing line comment.
    /// </summary>
    private static (string Keyword, string Argument) SplitDirective(string raw)
    {
        var span = raw.AsSpan();
        var i = 0;
        if (i < span.Length && span[i] == '#')
        {
            i++;
        }

        while (i < span.Length && char.IsWhiteSpace(span[i]))
        {
            i++;
        }

        var keywordStart = i;
        while (i < span.Length && char.IsLetter(span[i]))
        {
            i++;
        }

        var keyword = span.Slice(keywordStart, i - keywordStart).ToString();

        while (i < span.Length && char.IsWhiteSpace(span[i]))
        {
            i++;
        }

        var argument = span.Slice(i).ToString();
        var commentIndex = argument.IndexOf("//", StringComparison.Ordinal);
        if (commentIndex >= 0)
        {
            argument = argument.Substring(0, commentIndex);
        }

        return (keyword, argument.Trim());
    }

    /// <summary>
    /// Evaluates a preprocessor condition (the C#-style boolean grammar:
    /// symbols, <c>true</c>/<c>false</c>, <c>!</c>, <c>&amp;&amp;</c>, <c>||</c>,
    /// and parentheses) against the defined-symbol set.
    /// </summary>
    private sealed class ConditionEvaluator
    {
        private readonly string _text;
        private readonly IReadOnlySet<string> _symbols;
        private int _pos;

        private ConditionEvaluator(string text, IReadOnlySet<string> symbols)
        {
            _text = text;
            _symbols = symbols;
        }

        public static bool Evaluate(string condition, IReadOnlySet<string> symbols)
        {
            if (string.IsNullOrWhiteSpace(condition))
            {
                throw new PreprocessorConditionException(
                    "Missing condition after '#if'/'#elif'. Expected a symbol such as 'DEBUG'.");
            }

            var evaluator = new ConditionEvaluator(condition, symbols);
            var value = evaluator.ParseOr();
            evaluator.SkipWhitespace();
            if (evaluator._pos < evaluator._text.Length)
            {
                throw new PreprocessorConditionException(
                    $"Unexpected character '{evaluator._text[evaluator._pos]}' in preprocessor condition '{condition.Trim()}'.");
            }

            return value;
        }

        private bool ParseOr()
        {
            var value = ParseAnd();
            while (TryConsume("||"))
            {
                // Parse the right-hand side unconditionally so the whole condition is consumed.
                var rhs = ParseAnd();
                value = value || rhs;
            }

            return value;
        }

        private bool ParseAnd()
        {
            var value = ParseUnary();
            while (TryConsume("&&"))
            {
                var rhs = ParseUnary();
                value = value && rhs;
            }

            return value;
        }

        private bool ParseUnary()
        {
            SkipWhitespace();
            if (_pos < _text.Length && _text[_pos] == '!')
            {
                _pos++;
                return !ParseUnary();
            }

            return ParsePrimary();
        }

        private bool ParsePrimary()
        {
            SkipWhitespace();
            if (_pos >= _text.Length)
            {
                throw new PreprocessorConditionException(
                    "Unexpected end of preprocessor condition; expected a symbol.");
            }

            var ch = _text[_pos];
            if (ch == '(')
            {
                _pos++;
                var value = ParseOr();
                SkipWhitespace();
                if (_pos >= _text.Length || _text[_pos] != ')')
                {
                    throw new PreprocessorConditionException("Missing ')' in preprocessor condition.");
                }

                _pos++;
                return value;
            }

            if (char.IsLetter(ch) || ch == '_')
            {
                var start = _pos;
                while (_pos < _text.Length && (char.IsLetterOrDigit(_text[_pos]) || _text[_pos] == '_'))
                {
                    _pos++;
                }

                var name = _text.Substring(start, _pos - start);
                return name switch
                {
                    "true" => true,
                    "false" => false,
                    _ => _symbols.Contains(name),
                };
            }

            throw new PreprocessorConditionException(
                $"Unexpected character '{ch}' in preprocessor condition.");
        }

        private void SkipWhitespace()
        {
            while (_pos < _text.Length && char.IsWhiteSpace(_text[_pos]))
            {
                _pos++;
            }
        }

        private bool TryConsume(string op)
        {
            SkipWhitespace();
            if (_pos + op.Length <= _text.Length && _text.AsSpan(_pos, op.Length).SequenceEqual(op))
            {
                _pos += op.Length;
                return true;
            }

            return false;
        }
    }

    private sealed class PreprocessorConditionException : Exception
    {
        public PreprocessorConditionException(string message)
            : base(message)
        {
        }
    }
}
