using System;
using System.Collections.Generic;

namespace NSharpLang.Compiler.Columnar;

/// <summary>
/// Splits a $-string literal's TOKEN TEXT (the full `$"…"` span — the lexer emits ONE token with the
/// `$` and the holes inside it) into text segments and holes, mirroring the production parser's
/// re-lex (Parser.ParseInterpolatedString): `{{`/`}}` collapse to literal braces in TEXT, escape
/// pairs stay VERBATIM in text segments (StringLiteralDecoder.DecodeBody decodes at emit, exactly
/// like the backend's emitted interpolation), and a `{…}` hole splits at the first colon into an
/// expression part and a format clause. The modelled HOLE GRAMMAR is identifier chains only —
/// `name` / `name.field.field` — with an optional non-empty `:format`; any richer hole content
/// (calls, operators, ternaries, whitespace, nested strings/braces) returns false and the consumer
/// declines it. The columnar emitter consumes this splitter, so unsupported hole forms cannot enter
/// IL emission through this path.
/// </summary>
internal static class ColumnarInterpolationSplitter
{
    private static readonly Lazy<Bindings?> s_bindings = new(LoadBindings, isThreadSafe: true);
    [ThreadStatic]
    private static Scratch? t_scratch;

    internal readonly struct Part
    {
        internal Part(bool isHole, string text, string? format)
        {
            IsHole = isHole;
            Text = text;
            Format = format;
        }

        /// <summary>False = a TEXT segment (escapes verbatim); true = a hole.</summary>
        internal bool IsHole { get; }

        /// <summary>The text segment, or the hole's identifier chain (`a` / `a.b.c`).</summary>
        internal string Text { get; }

        /// <summary>The hole's format clause (the text after the first `:`), null when absent.</summary>
        internal string? Format { get; }
    }

    internal static bool TrySplit(string literal, List<Part> parts)
    {
        var capacity = literal.Length + 1;
        var scratch = t_scratch ??= new Scratch();
        scratch.EnsureCapacity(capacity);

        var count = RequiredBindings.Split(
            literal,
            scratch.Kinds,
            scratch.Texts,
            scratch.Formats,
            scratch.FormatFlags);
        if (count < 0)
            return false;

        try
        {
            for (var i = 0; i < count; i++)
            {
                var kind = scratch.Kinds[i];
                parts.Add(new Part(
                    kind == 1,
                    scratch.Texts[i],
                    scratch.FormatFlags[i] == 0
                        ? null
                        : scratch.Formats[i]));
            }

            return true;
        }
        finally
        {
            scratch.Clear(count);
        }
    }

    private static Bindings RequiredBindings
        => s_bindings.Value ?? throw new InvalidOperationException("N# columnar interpolation splitter kernel is unavailable.");

    private static Bindings? LoadBindings()
        => DogfoodKernelLoader.TryCreateBindings(programType => new Bindings(
            DogfoodKernelLoader.CreateDelegate<ColumnarInterpolatedStringPartsInto>(
                programType,
                "ColumnarInterpolatedStringPartsInto")));

    private delegate int ColumnarInterpolatedStringPartsInto(
        string literal,
        int[] outKinds,
        string[] outTexts,
        string[] outFormats,
        int[] outFormatFlags);

    private sealed record Bindings(ColumnarInterpolatedStringPartsInto Split);

    private sealed class Scratch
    {
        internal int[] FormatFlags = Array.Empty<int>();
        internal string[] Formats = Array.Empty<string>();
        internal int[] Kinds = Array.Empty<int>();
        internal string[] Texts = Array.Empty<string>();

        internal void EnsureCapacity(int capacity)
        {
            if (Kinds.Length >= capacity)
                return;

            Kinds = new int[capacity];
            Texts = new string[capacity];
            Formats = new string[capacity];
            FormatFlags = new int[capacity];
        }

        internal void Clear(int count)
        {
            Array.Clear(Kinds, 0, count);
            Array.Clear(Texts, 0, count);
            Array.Clear(Formats, 0, count);
            Array.Clear(FormatFlags, 0, count);
        }
    }
}
