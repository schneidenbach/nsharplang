namespace NSharpLang.GateScriptContracts.Tests

import System.IO

// ─── THE SHIPPED MSBUILD SDK'S INTERMEDIATE PATHS AND EMIT STAMP ──────────────────────────────
//
// Read as TEXT, like every other row in this project. Nothing here builds anything.
//
// The N# emit is incremental on an identity carried in the CONTENT of `nsharp.emit.stamp`
// (`Sdk.targets`), and that identity includes `@(NSharpTestFiles)` on purpose: commit 643717ef0
// added it so a product-only assembly could never satisfy a tests-included build and let the gate
// pass on a stale artifact. That guard is load-bearing and these rows keep it verbatim.
//
// What changed is only WHERE the two configurations write. They used to share one `obj`, so each
// one's stamp evicted the other's and both directions of the flip cost a full re-emit — 133.07 s
// and 273.27 s as 643717ef0 measured them, against 0.58 s for a rebuild that finds its own stamp.
// `scripts/dev.sh` alternates product-only then tests-included on every single run, so it paid both.
// With `NSharpExcludeTests=false` pointed at its own intermediate root, the product build and the
// tests build leave two distinct assemblies under two distinct stamps and neither can satisfy the
// other's — by path AND by content identity.
func ReadSdkFile(name: string): string {
    return File.ReadAllText(Path.Combine(RepositoryRoot(), "src", "NSharpLang.Sdk", "Sdk", name))
}

test "the tests-included configuration emits into its own intermediate tree, decided before the base SDK's props" {
    props := ReadSdkFile("Sdk.props")

    split := RequireMatch(
        props,
        "<PropertyGroup Condition=\"'\\$\\(EnableNSharpCompilation\\)' == 'true' And '\\$\\(NSharpExcludeTests\\)' == 'false'[^\"]*\">\\s*\\n\\s*<BaseIntermediateOutputPath>(?<path>[^<]+)</BaseIntermediateOutputPath>",
        "The shipped SDK must give the tests-included configuration its own BaseIntermediateOutputPath, or a product build and a tests build evict each other's emit stamp and each flip costs a FULL re-emit of every file."
    )

    path := split.Groups["path"].Value
    assert path != "obj/" && path != "obj\\\\", "The tests-included intermediate root must differ from the product one; found '" + path + "'."
    assert path.EndsWith("/") || path.EndsWith("\\\\"), "An intermediate root must end in a separator; found '" + path + "'."

    // It has to be decided before the base SDK's props, which is where MSBuildProjectExtensionsPath
    // and the restore outputs are pinned to it.
    splitIndex := props.IndexOf("<BaseIntermediateOutputPath>")
    baseImportIndex := props.IndexOf("<Import Project=\"Sdk.props\" Sdk=\"$(_NSharpBaseSdk)\" />")
    assert baseImportIndex >= 0, "Could not find the base SDK props import in Sdk.props."
    assert splitIndex >= 0 && splitIndex < baseImportIndex, "The intermediate-path split must be evaluated BEFORE the base SDK's props import, or restore has already been pointed at the shared obj."

    // The discriminator fires on an EXPLICIT false only — what the gate and dev.sh pass. A project
    // that never mentions the property keeps the layout it has today.
    assert !props.Contains("'$(NSharpExcludeTests)' != 'true'\">\n    <BaseIntermediateOutputPath>"), "The split must not fire for every project that merely leaves NSharpExcludeTests unset."
}

test "splitting the intermediate paths did not relax the emit stamp's content identity" {
    targets := ReadSdkFile("Sdk.targets")

    // The identity, verbatim: which files, TESTS IN OR OUT, project file, configuration, defines,
    // and the legacy-analysis switch, hashed into the stamp's content.
    assert targets.Contains("<_NSharpEmitKey>@(NSharpCompile);@(NSharpTestFiles);$(NSharpProjectFile);$(Configuration);$(DefineConstants);$(NSharpEmitValidateWithLegacyAnalysis)</_NSharpEmitKey>"), "The emit stamp's content identity must stay exactly as 643717ef0 wrote it: it is what stops a product-only assembly satisfying a tests-included build."
    assert targets.Contains("StableStringHash($(_NSharpEmitKey), 'Sha256')")
    RequireMatch(
        targets,
        "<Delete Files=\"\\$\\(_NSharpEmitStamp\\)\"[^>]*'@\\(_NSharpEmitPrevId\\)' != '\\$\\(_NSharpEmitId\\)'",
        "A stamp whose recorded identity differs from this build's must still be deleted before the emit's up-to-date check reads it."
    )

    // Both the stamp and the assembly hang off $(IntermediateOutputPath), so two intermediate roots
    // mean two stamps AND two assemblies: neither build can read, satisfy or overwrite the other's.
    assert targets.Contains("<_NSharpEmitStamp>$(IntermediateOutputPath)nsharp.emit.stamp</_NSharpEmitStamp>")
    assert targets.Contains("<IntermediateAssembly Include=\"$(IntermediateOutputPath)$(TargetName)$(TargetExt)\" />")

    // And the emit is still keyed on both source sets plus the stamp, not on timestamps alone.
    emit := RequireMatch(targets, "<Target Name=\"EmitNSharpIlAssembly\"(?<body>.*?)>", "Could not find the EmitNSharpIlAssembly target in Sdk.targets.").Groups["body"].Value
    assert emit.Contains("Inputs=\"@(NSharpCompile);@(NSharpTestFiles);")
    assert emit.Contains("Outputs=\"$(_NSharpEmitStamp);@(IntermediateAssembly)\"")
}
