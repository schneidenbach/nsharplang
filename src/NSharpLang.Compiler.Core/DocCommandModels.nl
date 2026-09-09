namespace NSharpLang.Cli.Commands

import System.Collections.Generic

record DocManifest(IndexPath: string, PageCount: int, Pages: IReadOnlyList<DocPage>) {
}

record DocPage(Name: string, Kind: string, Path: string) {
}
