using System.ComponentModel.Composition;
using Microsoft.VisualStudio.Text;
using Microsoft.VisualStudio.Text.Classification;
using Microsoft.VisualStudio.Utilities;

namespace NSharp.VisualStudio.Editor
{
    /// <summary>
    /// Classifier provider. It adds the classifier to the set of classifiers.
    /// </summary>
    [Export(typeof(IClassifierProvider))]
    [ContentType("nsharp")]
    internal class NSharpClassifierProvider : IClassifierProvider
    {
        [Import]
        internal IClassificationTypeRegistryService ClassificationRegistry { get; set; }

        public IClassifier GetClassifier(ITextBuffer buffer)
        {
            return buffer.Properties.GetOrCreateSingletonProperty<NSharpClassifier>(
                () => new NSharpClassifier(ClassificationRegistry));
        }
    }

    /// <summary>
    /// Definition of the N# content type.
    /// </summary>
    internal static class NSharpContentTypeDefinition
    {
        [Export]
        [Name("nsharp")]
        [BaseDefinition("code")]
        internal static ContentTypeDefinition NSharpContentType { get; set; }

        [Export]
        [FileExtension(".nl")]
        [ContentType("nsharp")]
        internal static FileExtensionToContentTypeDefinition NSharpFileExtension { get; set; }
    }
}
