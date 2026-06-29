namespace NSharpLang.Cli.Commands

import System.Collections.Generic

public record DocManifest(
    IndexPath: string,
    PageCount: int,
    Pages: IReadOnlyList<DocPage>) {
}

public record DocPage(
    Name: string,
    Kind: string,
    Path: string) {
}
