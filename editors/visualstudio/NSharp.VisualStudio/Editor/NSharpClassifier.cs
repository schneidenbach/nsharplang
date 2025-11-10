using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Classification;

namespace NSharpLang.VisualStudio.Editor
{
    /// <summary>
    /// Classifier that classifies N# code tokens.
    /// </summary>
    internal class NSharpClassifier : IClassifier
    {
        private readonly IClassificationTypeRegistryService _classificationRegistry;
        private readonly IClassificationType _keywordType;
        private readonly IClassificationType _commentType;
        private readonly IClassificationType _stringType;
        private readonly IClassificationType _numberType;
        private readonly IClassificationType _operatorType;

        // N# keywords
        private static readonly string[] Keywords = new[]
        {
            "func", "return", "if", "else", "match", "case", "for", "while", "break", "continue",
            "class", "struct", "interface", "type", "public", "private", "static", "readonly",
            "async", "await", "import", "namespace", "new", "null", "true", "false",
            "var", "let", "const", "in", "is", "as", "typeof", "default", "extends", "implements"
        };

        private static readonly Regex KeywordRegex = new Regex(
            @"\b(" + string.Join("|", Keywords) + @")\b",
            RegexOptions.Compiled);

        private static readonly Regex CommentRegex = new Regex(
            @"//.*$|/\*.*?\*/",
            RegexOptions.Compiled | RegexOptions.Multiline);

        private static readonly Regex StringRegex = new Regex(
            @"""(?:[^""\\]|\\.)*""|'(?:[^'\\]|\\.)*'",
            RegexOptions.Compiled);

        private static readonly Regex NumberRegex = new Regex(
            @"\b\d+\.?\d*\b",
            RegexOptions.Compiled);

        private static readonly Regex OperatorRegex = new Regex(
            @":=|==|!=|<=|>=|&&|\|\||[+\-*/<>=!&|]",
            RegexOptions.Compiled);

        public NSharpClassifier(IClassificationTypeRegistryService registry)
        {
            _classificationRegistry = registry;
            _keywordType = registry.GetClassificationType("keyword");
            _commentType = registry.GetClassificationType("comment");
            _stringType = registry.GetClassificationType("string");
            _numberType = registry.GetClassificationType("number");
            _operatorType = registry.GetClassificationType("operator");
        }

        public IList<ClassificationSpan> GetClassificationSpans(SnapshotSpan span)
        {
            var classifications = new List<ClassificationSpan>();
            var text = span.GetText();
            var snapshot = span.Snapshot;

            // Classify comments
            foreach (Match match in CommentRegex.Matches(text))
            {
                var matchSpan = new SnapshotSpan(snapshot, new Span(span.Start + match.Index, match.Length));
                classifications.Add(new ClassificationSpan(matchSpan, _commentType));
            }

            // Classify strings
            foreach (Match match in StringRegex.Matches(text))
            {
                var matchSpan = new SnapshotSpan(snapshot, new Span(span.Start + match.Index, match.Length));
                classifications.Add(new ClassificationSpan(matchSpan, _stringType));
            }

            // Classify keywords
            foreach (Match match in KeywordRegex.Matches(text))
            {
                var matchSpan = new SnapshotSpan(snapshot, new Span(span.Start + match.Index, match.Length));
                classifications.Add(new ClassificationSpan(matchSpan, _keywordType));
            }

            // Classify numbers
            foreach (Match match in NumberRegex.Matches(text))
            {
                var matchSpan = new SnapshotSpan(snapshot, new Span(span.Start + match.Index, match.Length));
                classifications.Add(new ClassificationSpan(matchSpan, _numberType));
            }

            // Classify operators
            foreach (Match match in OperatorRegex.Matches(text))
            {
                var matchSpan = new SnapshotSpan(snapshot, new Span(span.Start + match.Index, match.Length));
                classifications.Add(new ClassificationSpan(matchSpan, _operatorType));
            }

            return classifications;
        }

#pragma warning disable 67
        public event EventHandler<ClassificationChangedEventArgs> ClassificationChanged;
#pragma warning restore 67
    }
}
