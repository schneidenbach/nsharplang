namespace NSharpLang.Compiler

// THE ONE PLACE THE PRODUCT SPELLS A DIAGNOSTIC'S DOCUMENTATION URL.
//
// Every diagnostic `nlc` prints ends with "Read more: <url>", and before this class there were
// THIRTY-ONE independent spellings of that URL across the estate — `DiagnosticCatalog`,
// `ParserErrorDiagnostics`, `AnalyzerDiagnostics`, `ImportGraphModels`, `SystemsFindingDiagnostics`
// and ~25 literals in `ErrorMessageBuilder` — plus a SECOND, INCOMPATIBLE shape pinned by
// `DiagnosticGoldenSuite` (`errors/<category>/<code>`, as in `errors/parser/NL101`). All of them
// pointed at `docs.n-sharp.dev`, which is NXDOMAIN: the domain has never been provisioned, so every
// "Read more:" link the compiler has ever printed was dead on arrival, including the links on the
// five codes that DO have pages.
//
// `Base` is the real published site, measured rather than assumed: the deployed Docusaurus serves
// `https://schneidenbach.github.io/nsharplang/docs/<doc-id>` (verified live on `docs/quick-start`
// and `docs/language-tour`), and a page at `website/docs/errors/NL319.md` therefore routes to
// `.../docs/errors/NL319`.
//
// IF THE OWNER LATER PROVISIONS `docs.n-sharp.dev`, THIS CONSTANT IS THE ONLY EDIT. Nothing else in
// the product spells a documentation host. Do not reintroduce a literal URL anywhere; call `UrlFor`.
class DiagnosticDocs {
    static Base: string => "https://schneidenbach.github.io/nsharplang/docs/errors/"

    // `code` is a diagnostic id exactly as it is printed — `NL320`, `NSYS010`. The page that
    // answers it is `website/docs/errors/<code>.md`, and `tests/native/error-docs-contract`
    // refuses a code that has no such page.
    static func UrlFor(code: string): string {
        prefix := DiagnosticDocs.Base
        return prefix + code
    }
}
