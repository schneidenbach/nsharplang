namespace NSharpLang.IncrementalBuild.Tests

import System
import System.IO
import NSharpLang.Compiler

test "cold body emission keeps changed bodies and stubs unchanged bodies" {
    path := Path.Combine(Path.GetTempPath(), "SelectiveCheckEmission.nl")
    original := "namespace SelectiveCheckEmission\n\nfunc First(): int {\n    return 1000 + 1\n}\n\nfunc Second(): int {\n    return 1000 + 7\n}\n"
    edited := "namespace SelectiveCheckEmission\n\nfunc First(): int {\n    return 1000 + 2\n}\n\nfunc Second(): int {\n    return 1000 + 7\n}\n"
    previous := IncrementalFileSummary.Compute(path, original)
    current := IncrementalFileSummary.Compute(path, edited)
    parsed := current.ParsedSource
    if parsed == null || parsed.CompilationUnit == null {
        throw new InvalidOperationException("the edited source did not parse")
    }
    unit := parsed.CompilationUnit
    tokens := new Lexer(edited, path).Tokenize()
    selective := IncrementalFileSummary.BuildChangedBodyEmissionSource(edited, unit, tokens, current.BodyHashes, previous.BodyHashes)

    assert current.SurfaceHash == previous.SurfaceHash, "body edits must preserve the declaration surface"
    assert current.BodyHashes.Count == 2, "one body hash should be recorded for each function body"
    assert !current.Opaque, "the edited source summary should be complete"
    assert !current.HasPreprocessorDirectives, "the edited source should not contain preprocessor directives"
    assert current.InterfaceSkeleton != null, "the edited source should have a valid interface skeleton"
    assert selective != null, "selective emission source should be created"
    text := selective ?? ""
    assert text.Contains("return 1000 + 2"), "the changed body should remain in the emission source"
    assert text.Contains("return default"), "the unchanged body should be stubbed"
    assert !text.Contains("return 1000 + 7"), "the unchanged body should not be emitted again"
}
