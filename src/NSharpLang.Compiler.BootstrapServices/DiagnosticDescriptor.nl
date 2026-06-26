namespace NSharpLang.Compiler

public class DiagnosticDescriptor {
    Code: string
    Title: string
    Source: DiagnosticSource
    Category: DiagnosticCategory
    DefaultSeverity: DiagnosticSeverity
    BlocksBuildByDefault: bool
    IsConfigurable: bool
    DocsUrl: string?
    Explanation: string?

    constructor(
        Code: string,
        Title: string,
        Source: DiagnosticSource,
        Category: DiagnosticCategory,
        DefaultSeverity: DiagnosticSeverity,
        BlocksBuildByDefault: bool
    ) {
        this.Code = Code
        this.Title = Title
        this.Source = Source
        this.Category = Category
        this.DefaultSeverity = DefaultSeverity
        this.BlocksBuildByDefault = BlocksBuildByDefault
        this.IsConfigurable = true
        this.DocsUrl = null
        this.Explanation = null
    }

    constructor(
        Code: string,
        Title: string,
        Source: DiagnosticSource,
        Category: DiagnosticCategory,
        DefaultSeverity: DiagnosticSeverity,
        BlocksBuildByDefault: bool,
        IsConfigurable: bool
    ) {
        this.Code = Code
        this.Title = Title
        this.Source = Source
        this.Category = Category
        this.DefaultSeverity = DefaultSeverity
        this.BlocksBuildByDefault = BlocksBuildByDefault
        this.IsConfigurable = IsConfigurable
        this.DocsUrl = null
        this.Explanation = null
    }

    constructor(
        Code: string,
        Title: string,
        Source: DiagnosticSource,
        Category: DiagnosticCategory,
        DefaultSeverity: DiagnosticSeverity,
        BlocksBuildByDefault: bool,
        IsConfigurable: bool,
        DocsUrl: string?,
        Explanation: string?
    ) {
        this.Code = Code
        this.Title = Title
        this.Source = Source
        this.Category = Category
        this.DefaultSeverity = DefaultSeverity
        this.BlocksBuildByDefault = BlocksBuildByDefault
        this.IsConfigurable = IsConfigurable
        this.DocsUrl = DocsUrl
        this.Explanation = Explanation
    }
}
