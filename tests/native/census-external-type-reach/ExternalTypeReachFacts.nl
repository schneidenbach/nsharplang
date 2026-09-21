namespace Census.ExternalTypeReach

import System

// REACHING A TYPE THE FRAMEWORK FORWARDS OUT OF `System.Runtime`.
//
// `System.Uri` is declared in `System.Private.Uri` and reaches a program through a type forwarder in
// `System.Runtime`, which is the reference surface every project compiles against. A forwarder can
// only be followed when the assembly it names is something the resolver can open, so a back end
// whose resolver held a fixed list of files could not see `Uri` at all — while the analyzer, which
// resolves from the runtime and shared-framework directories, accepted the same program. These
// helpers exercise the FIVE positions a type name can appear in, each of which was its own decline.
class ExternalTypeReachFacts {

    // 1. A TYPED LOCAL, and the nullable form of one.
    static func RoundTrip(text: string): string {
        parsed: Uri? = null
        if Uri.TryCreate(text, UriKind.Absolute, out parsed) {
            return parsed.AbsoluteUri
        }

        return ""
    }

    // 2. CONSTRUCTION.
    static func Host(text: string): string {
        built := new Uri(text)
        return built.Host
    }

    // 3. INSTANCE MEMBERS, more than one hop of them.
    static func PathAndQuery(text: string): string {
        built := new Uri(text)
        return built.AbsolutePath + built.Query
    }

    static func LocalPath(text: string): string {
        return new Uri(text).LocalPath
    }

    // 4. A STATIC CALL, including the `out`-argument overload used above.
    static func Escaped(text: string): string {
        return Uri.EscapeDataString(text)
    }

    static func IsWellFormed(text: string): bool {
        return Uri.IsWellFormedUriString(text, UriKind.Absolute)
    }

    // 5. `typeof`.
    static func TypeName(): string {
        return typeof(Uri).Name
    }

    static func TypeNamespace(): string {
        return typeof(Uri).Namespace ?? ""
    }

    // AN ENUM FORWARDED THE SAME WAY, held in a typed local and compared.
    static func KindIsAbsolute(): bool {
        kind: UriKind = UriKind.Absolute
        return kind == UriKind.Absolute
    }

    // MORE THAN ONE TYPE OUT OF THE SAME FORWARDED ASSEMBLY, so the rows are not a fact about one
    // name: `UriBuilder` and `UriFormatException` are declared beside `Uri` in `System.Private.Uri`.
    static func BuiltUri(host: string, path: string): string {
        builder := new UriBuilder("https", host)
        builder.Path = path
        return builder.Uri.AbsoluteUri
    }

    static func MalformedIsReported(text: string): bool {
        try {
            built := new Uri(text)
            return built.Host.Length < 0
        } catch ex: UriFormatException {
            return ex.Message.Length > 0
        }
    }
}
