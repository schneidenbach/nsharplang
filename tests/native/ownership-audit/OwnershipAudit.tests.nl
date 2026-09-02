namespace NSharpLang.OwnershipAudit

import System
import System.Collections.Generic
import System.IO
import System.Text

class OwnershipFixtureEntryValue {
    Json: string
    Entry: OwnershipManifestEntry

    constructor(json: string, entry: OwnershipManifestEntry) {
        Json = json
        Entry = entry
    }
}

func OwnershipFixtureModels(entries: List<OwnershipFixtureEntryValue>): List<OwnershipManifestEntry> {
    models := new List<OwnershipManifestEntry>()
    i := 0
    while i < entries.Count {
        models.Add(entries[i].Entry)
        i = i + 1
    }
    return models
}

func OwnershipFixtureObserved(path: string, text: string): OwnershipObservedFile {
    classification := OwnershipPolicy.Classify(path)
    return OwnershipFacts.Observe(path, classification, text)
}

func OwnershipFixtureExistingEntry(path: string, text: string, epochBonus: int): OwnershipFixtureEntryValue {
    observed := OwnershipFixtureObserved(path, text)
    return OwnershipFixtureEntry(
        observed,
        "existing-debt",
        observed.Lines + epochBonus,
        observed.NonBlankLines + epochBonus,
        observed.AssertionMarkers + epochBonus,
        observed.Lines,
        observed.NonBlankLines,
        observed.AssertionMarkers,
        0,
        0,
        observed.Fingerprint
    )
}

func OwnershipFixtureRemovedEntry(path: string, epochText: string): OwnershipFixtureEntryValue {
    observed := OwnershipFixtureObserved(path, epochText)
    return OwnershipFixtureEntry(
        observed,
        "removed",
        observed.Lines,
        observed.NonBlankLines,
        observed.AssertionMarkers,
        0,
        0,
        0,
        0,
        0,
        "text-v1:removed"
    )
}

func OwnershipFixtureEntry(
    observed: OwnershipObservedFile,
    state: string,
    epochLines: int,
    epochNonBlankLines: int,
    epochAssertionMarkers: int,
    currentLines: int,
    currentNonBlankLines: int,
    currentAssertionMarkers: int,
    epochBytes: int,
    currentBytes: int,
    fingerprint: string
): OwnershipFixtureEntryValue {
    builder := new StringBuilder()
    builder.Append("{\"path\":\"")
    builder.Append(observed.Path)
    builder.Append("\",\"language\":\"")
    builder.Append(observed.Language)
    builder.Append("\",\"surface\":\"")
    builder.Append(observed.Surface)
    builder.Append("\",\"campaignScope\":\"")
    builder.Append(observed.CampaignScope)
    builder.Append("\",\"state\":\"")
    builder.Append(state)
    builder.Append("\",\"epochLines\":")
    builder.Append(epochLines)
    builder.Append(",\"currentLines\":")
    builder.Append(currentLines)
    builder.Append(",\"epochNonBlankLines\":")
    builder.Append(epochNonBlankLines)
    builder.Append(",\"currentNonBlankLines\":")
    builder.Append(currentNonBlankLines)
    builder.Append(",\"epochAssertionMarkers\":")
    builder.Append(epochAssertionMarkers)
    builder.Append(",\"currentAssertionMarkers\":")
    builder.Append(currentAssertionMarkers)
    builder.Append(",\"epochBytes\":")
    builder.Append(epochBytes)
    builder.Append(",\"currentBytes\":")
    builder.Append(currentBytes)
    builder.Append(",\"currentFingerprint\":\"")
    builder.Append(fingerprint)
    builder.Append("\"}")

    entry := new OwnershipManifestEntry()
    entry.Path = observed.Path
    entry.Language = observed.Language
    entry.Surface = observed.Surface
    entry.CampaignScope = observed.CampaignScope
    entry.State = state
    entry.EpochLines = epochLines
    entry.CurrentLines = currentLines
    entry.EpochNonBlankLines = epochNonBlankLines
    entry.CurrentNonBlankLines = currentNonBlankLines
    entry.EpochAssertionMarkers = epochAssertionMarkers
    entry.CurrentAssertionMarkers = currentAssertionMarkers
    entry.EpochBytes = epochBytes
    entry.CurrentBytes = currentBytes
    entry.CurrentFingerprint = fingerprint
    return new OwnershipFixtureEntryValue(builder.ToString(), entry)
}

func OwnershipFixtureManifest(
    entries: List<OwnershipFixtureEntryValue>,
    paths: List<string>,
    schemaVersion: int,
    phase: string,
    countAdjustment: int,
    fingerprintOverride: string
): string {
    fingerprint := fingerprintOverride
    if fingerprint == "" {
        fingerprint = OwnershipFacts.PathSetFingerprint(paths)
    }
    modelEntries := OwnershipFixtureModels(entries)
    epochFacts := OwnershipFacts.EpochFactFingerprint(modelEntries)
    reviewedHead := OwnershipFacts.ReviewedHeadFingerprint(modelEntries)
    builder := new StringBuilder()
    builder.Append("{\"schemaVersion\":")
    builder.Append(schemaVersion)
    builder.Append(",\"phase\":\"")
    builder.Append(phase)
    builder.Append("\",\"epochFileCount\":")
    builder.Append(paths.Count + countAdjustment)
    builder.Append(",\"epochPathFingerprint\":\"")
    builder.Append(fingerprint)
    builder.Append("\",\"epochFactFingerprint\":\"")
    builder.Append(epochFacts)
    builder.Append("\",\"reviewedHeadFingerprint\":\"")
    builder.Append(reviewedHead)
    builder.Append("\",\"files\":[")
    i := 0
    while i < entries.Count {
        if i > 0 {
            builder.Append(",")
        }
        builder.Append(entries[i].Json)
        i = i + 1
    }
    builder.Append("]}")
    return builder.ToString()
}

func OwnershipFixtureOne(path: string, text: string, epochBonus: int): string {
    entries := new List<OwnershipFixtureEntryValue>()
    entries.Add(OwnershipFixtureExistingEntry(path, text, epochBonus))
    paths := new List<string>()
    paths.Add(path)
    return OwnershipFixtureManifest(entries, paths, 1, "growth-ratchet", 0, "")
}

func OwnershipFixtureObservedList(path: string, text: string): List<OwnershipObservedFile> {
    observed := new List<OwnershipObservedFile>()
    observed.Add(OwnershipFixtureObserved(path, text))
    return observed
}

func OwnershipFixtureBinaryEntry(
    path: string,
    bytes: byte[],
    epochByteBonus: int
): OwnershipFixtureEntryValue {
    classification := OwnershipPolicy.Classify(path)
    observed := OwnershipFacts.ObserveBinary(path, classification, bytes)
    return OwnershipFixtureEntry(
        observed,
        "existing-debt",
        0,
        0,
        0,
        0,
        0,
        0,
        bytes.Length + epochByteBonus,
        bytes.Length,
        observed.Fingerprint
    )
}

func OwnershipFixtureBinaryObservedList(path: string, bytes: byte[]): List<OwnershipObservedFile> {
    observed := new List<OwnershipObservedFile>()
    observed.Add(OwnershipFacts.ObserveBinary(path, OwnershipPolicy.Classify(path), bytes))
    return observed
}

test "ownership facts normalize text and compute stable fingerprints" {
    assert OwnershipFacts.Fingerprint("abc") == "text-v1:e71fa2190541574b"
    assert OwnershipFacts.Fingerprint("a\r\nb\r") == OwnershipFacts.Fingerprint("a\nb\n")
    assert OwnershipFacts.CountLines("") == 0
    assert OwnershipFacts.CountLines("one") == 1
    assert OwnershipFacts.CountLines("one\ntwo\n") == 2
    assert OwnershipFacts.CountNonBlankLines("one\n  \n two\n") == 2
}

test "binary ownership uses exact bytes and byte ceilings" {
    root := OwnershipAudit.FindRepositoryRoot(Environment.CurrentDirectory) ?? ""
    repositoryBytes := OwnershipManagedFile.ReadAllBytes(Path.Combine(root, "AGENTS.md"))
    assert repositoryBytes.Length > 0
    assert repositoryBytes[0] == (byte)'#'

    iconPath := Path.Combine(root, "editors/vscode/icon.png")
    fileBytes := OwnershipManagedFile.ReadAllBytesWithBufferSize(iconPath, 3)
    defaultBufferBytes := OwnershipManagedFile.ReadAllBytes(iconPath)
    assert fileBytes.Length > 100
    assert fileBytes.Length == defaultBufferBytes.Length
    assert OwnershipFacts.FingerprintBytes(fileBytes) == OwnershipFacts.FingerprintBytes(defaultBufferBytes)
    assert fileBytes[0] == (byte)137
    assert fileBytes[1] == (byte)'P'
    assert fileBytes[2] == (byte)'N'
    assert fileBytes[3] == (byte)'G'
    assert fileBytes[fileBytes.Length - 8] == (byte)'I'
    assert fileBytes[fileBytes.Length - 7] == (byte)'E'
    assert fileBytes[fileBytes.Length - 6] == (byte)'N'
    assert fileBytes[fileBytes.Length - 5] == (byte)'D'
    assert fileBytes[fileBytes.Length - 4] == (byte)174
    assert fileBytes[fileBytes.Length - 3] == (byte)66
    assert fileBytes[fileBytes.Length - 2] == (byte)96
    assert fileBytes[fileBytes.Length - 1] == (byte)130

    path := "website/static/playground/runtime.wasm"
    original := new byte[](1)
    original[0] = (byte)192
    sameDecodedText := new byte[](1)
    sameDecodedText[0] = (byte)193
    grown := new byte[](2)
    grown[0] = (byte)192
    grown[1] = (byte)0

    assert OwnershipFacts.FingerprintBytes(original) != OwnershipFacts.FingerprintBytes(sameDecodedText)

    entries := new List<OwnershipFixtureEntryValue>()
    entries.Add(OwnershipFixtureBinaryEntry(path, original, 0))
    paths := new List<string>()
    paths.Add(path)
    manifest := OwnershipFixtureManifest(entries, paths, 1, "growth-ratchet", 0, "")

    unchanged := OwnershipAudit.AuditSnapshot(
        manifest,
        OwnershipFixtureBinaryObservedList(path, original),
        false
    )
    assert unchanged.Succeeded

    byteDrift := OwnershipAudit.AuditSnapshot(
        manifest,
        OwnershipFixtureBinaryObservedList(path, sameDecodedText),
        false
    )
    assert byteDrift.HasCode("OWN005")
    assert !byteDrift.HasCode("OWN004")

    byteGrowth := OwnershipAudit.AuditSnapshot(
        manifest,
        OwnershipFixtureBinaryObservedList(path, grown),
        false
    )
    assert byteGrowth.HasCode("OWN004")

    binaryTextMetrics := manifest.Replace("\"epochLines\":0", "\"epochLines\":1")
    assert OwnershipAudit.AuditSnapshot(
        binaryTextMetrics,
        OwnershipFixtureBinaryObservedList(path, original),
        false
    ).HasCode("OWN001")

    wrongBinaryPrefix := manifest.Replace("binary-v1:", "text-v1:")
    assert OwnershipAudit.AuditSnapshot(
        wrongBinaryPrefix,
        OwnershipFixtureBinaryObservedList(path, original),
        false
    ).HasCode("OWN001")
}

test "ownership facts count CSharp and TypeScript assertion markers only in tests" {
    csharp := OwnershipFixtureObserved(
        "tests/CompilerTests.cs",
        "[Fact]\nAssert.True(true);\n[Theory]\nvalue.Should();\n"
    )
    assert csharp.AssertionMarkers == 4

    typescript := OwnershipFixtureObserved(
        "editors/vscode/test/suite/hover.test.ts",
        "test('hover', () => expect(value));\nit('works', () => {});\n"
    )
    assert typescript.AssertionMarkers == 3

    product := OwnershipFixtureObserved("src/NSharpLang.Compiler/Parser.cs", "Assert.True(true);\n")
    assert product.AssertionMarkers == 0
}

test "ownership policy derives representative languages and surfaces" {
    compiler := OwnershipPolicy.Classify("src/NSharpLang.Compiler/Parser.cs")
    assert compiler.Included
    assert compiler.Language == "csharp"
    assert compiler.Surface == "compiler-core"
    assert compiler.CampaignScope == "closeout"

    editor := OwnershipPolicy.Classify("editors/vscode/src/extension.ts")
    assert editor.Included
    assert editor.Language == "typescript"
    assert editor.Surface == "editor"

    gate := OwnershipPolicy.Classify("scripts/test-all.sh")
    assert gate.Included
    assert gate.Language == "shell"
    assert gate.Surface == "gate-infrastructure"

    runtime := OwnershipPolicy.Classify("src/NSharpLang.Runtime/Range.cs")
    assert runtime.Included
    assert runtime.CampaignScope == "separate-campaign"
}

test "ownership policy covers every closeout-adjacent ecosystem language" {
    assert OwnershipPolicy.Classify("tools/Sneaky.cs").Language == "csharp"
    assert OwnershipPolicy.Classify("editors/vscode/src/extension.ts").Language == "typescript"
    assert OwnershipPolicy.Classify("website/src/pages/index.js").Language == "javascript"
    assert OwnershipPolicy.Classify("src/NSharpLang.Compiler/Compiler.csproj").Language == "msbuild"
    assert OwnershipPolicy.Classify("scripts/test-all.sh").Language == "shell"
    assert OwnershipPolicy.Classify("tests/scripts/replay.py").Language == "python"
    assert OwnershipPolicy.Classify("editors/rider-plugin/build.gradle.kts").Language == "gradle-kotlin"
    assert OwnershipPolicy.Classify("editors/rider-plugin/gradlew").Language == "gradle-config"
    assert OwnershipPolicy.Classify("editors/vscode/package.json").Language == "json-config"
    assert OwnershipPolicy.Classify(".github/workflows/ci.yml").Language == "yaml-config"
    assert OwnershipPolicy.Classify("tests/Integration/Dockerfile.toolchain").Language == "product-config"
    assert OwnershipPolicy.Classify("NSharpLang.sln").Language == "msbuild"
    assert OwnershipPolicy.Classify("src/NSharpLang.Compiler/new-policy.json").Language == "json-config"
    assert OwnershipPolicy.Classify("src/NSharpLang.Compiler/new-policy.yml").Language == "yaml-config"
    assert OwnershipPolicy.Classify("website/static/playground/runtime.wasm").Language == "wasm-binary"
    assert OwnershipPolicy.Classify("editors/vscode/extension.vsix").Language == "package-binary"
    assert OwnershipPolicy.Classify("scripts/ilverify-baseline.txt").Language == "policy-data"
    assert OwnershipPolicy.Classify("website/static/.nojekyll").Language == "product-config"
    assert OwnershipPolicy.Classify("src/NSharpLang.Compiler/new-policy.txt").Included
    assert OwnershipPolicy.Classify("src/NSharpLang.Compiler/new-policy.dat").Included
    assert OwnershipPolicy.Classify("arbitrary-top-level/new-policy.py").Included
    assert OwnershipPolicy.Classify("arbitrary-top-level/new-policy.swift").Included
    assert OwnershipPolicy.Classify("arbitrary-top-level/new-policy.toml").Included
    assert OwnershipPolicy.Classify("examples/17-issue-tracker/frontend/src/App.tsx").Surface == "examples"
    assert OwnershipPolicy.Classify("ci/templates/github-actions/build.yml").Surface == "ci-infrastructure"
    assert OwnershipPolicy.Classify("ci/templates/docker/Dockerfile.runtime").Language == "product-config"
    assert OwnershipPolicy.Classify("ci/templates/docker/.dockerignore").Language == "product-config"

    benchmark := OwnershipPolicy.Classify("benchmarks/native-comparison/rolling-hash/main.rs")
    assert benchmark.Included
    assert benchmark.Surface == "benchmark-reference"
    assert benchmark.CampaignScope == "separate-campaign"

    assert !OwnershipPolicy.Classify("editors/vscode/LICENSE.txt").Included
    assert !OwnershipPolicy.Classify("tests/fixtures/diagnostics/top25.golden.txt").Included
    assert !OwnershipPolicy.Classify("editors/rider-plugin/src/main/resources/fileTemplates/NSharp File.nl.ft").Included
    assert !OwnershipPolicy.Classify("editors/vscode/nsharp-0.6.0.vsix").Included
    assert OwnershipPolicy.Classify("editors/vscode/future-extension.vsix").Included
    assert !OwnershipPolicy.Classify("examples/14-minimal-api/MinimalApi.g.csproj").Included
    assert !OwnershipPolicy.Classify("examples/17-issue-tracker/backend/IssueTracker.g.csproj").Included
    assert OwnershipPolicy.Classify("src/Hidden.g.csproj").Language == "msbuild"

    assert OwnershipPolicy.Classify("examples/new-policy.unknown").Unknown
    assert OwnershipPolicy.Classify("ci/new-policy.unknown").Unknown
    assert OwnershipPolicy.Classify("benchmarks/new-policy.unknown").Unknown
}

test "ownership policy rejects noncanonical paths and unknown product code" {
    assert OwnershipPolicy.IsCanonicalManifestPath("src/NSharpLang.Compiler/Parser.cs")
    assert !OwnershipPolicy.IsCanonicalManifestPath("../Parser.cs")
    assert !OwnershipPolicy.IsCanonicalManifestPath("src/**/Parser.cs")
    assert !OwnershipPolicy.IsCanonicalManifestPath("src\\Parser.cs")

    unknown := OwnershipPolicy.Classify("src/NSharpLang.Compiler/Policy.magic")
    assert unknown.Unknown
    assert !unknown.Included

    assert OwnershipPolicy.ShouldSkipDirectory("editors/vscode/out")
    assert OwnershipPolicy.ShouldSkipDirectory("examples/demo/.nsharp")
    assert OwnershipPolicy.ShouldSkipDirectory(".claude")
    assert !OwnershipPolicy.ShouldSkipDirectory("src/NSharpLang.Compiler/out")
    assert !OwnershipPolicy.ShouldSkipDirectory("src/NSharpLang.Compiler/server")
}

test "strict schema accepts unchanged files and reviewed reductions" {
    path := "src/NSharpLang.Compiler/Parser.cs"
    text := "class Parser {}\n"
    unchanged := OwnershipAudit.AuditSnapshot(
        OwnershipFixtureOne(path, text, 0),
        OwnershipFixtureObservedList(path, text),
        false
    )
    assert unchanged.Succeeded

    reduced := OwnershipAudit.AuditSnapshot(
        OwnershipFixtureOne(path, text, 12),
        OwnershipFixtureObservedList(path, text),
        false
    )
    assert reduced.Succeeded
}

test "strict schema rejects malformed unsupported and extensible manifests" {
    path := "src/NSharpLang.Compiler/Parser.cs"
    text := "class Parser {}\n"
    observed := OwnershipFixtureObservedList(path, text)

    malformed := OwnershipAudit.AuditSnapshot("{", observed, false)
    assert malformed.HasCode("OWN001")

    unsupported := OwnershipFixtureOne(path, text, 0).Replace("\"schemaVersion\":1", "\"schemaVersion\":2")
    assert OwnershipAudit.AuditSnapshot(unsupported, observed, false).HasCode("OWN001")

    unknownRoot := OwnershipFixtureOne(path, text, 0).Replace(
        "\"phase\":",
        "\"unknown\":true,\"phase\":"
    )
    assert OwnershipAudit.AuditSnapshot(unknownRoot, observed, false).HasCode("OWN001")

    unknownEntry := OwnershipFixtureOne(path, text, 0).Replace(
        "\"state\":",
        "\"verdict\":\"approved\",\"state\":"
    )
    assert OwnershipAudit.AuditSnapshot(unknownEntry, observed, false).HasCode("OWN001")

    badFingerprint := OwnershipFixtureOne(path, text, 0).Replace(
        OwnershipFacts.Fingerprint(text),
        "text-v1:ABCDEF0123456789"
    )
    assert OwnershipAudit.AuditSnapshot(badFingerprint, observed, false).HasCode("OWN001")

    textByteMetrics := OwnershipFixtureOne(path, text, 0).Replace(
        "\"epochBytes\":0",
        "\"epochBytes\":1"
    )
    assert OwnershipAudit.AuditSnapshot(textByteMetrics, observed, false).HasCode("OWN001")

    wrongTextPrefix := OwnershipFixtureOne(path, text, 0).Replace("text-v1:", "binary-v1:")
    assert OwnershipAudit.AuditSnapshot(wrongTextPrefix, observed, false).HasCode("OWN001")
}

test "schema v1 cannot bless a survivor or mechanical exception" {
    path := "src/NSharpLang.Compiler/Parser.cs"
    text := "class Parser {}\n"
    observed := OwnershipFixtureObservedList(path, text)
    survivor := OwnershipFixtureOne(path, text, 0).Replace("existing-debt", "survivor")
    mechanical := OwnershipFixtureOne(path, text, 0).Replace("existing-debt", "mechanical")
    approved := OwnershipFixtureOne(path, text, 0).Replace("existing-debt", "approved")
    assert OwnershipAudit.AuditSnapshot(survivor, observed, false).HasCode("OWN001")
    assert OwnershipAudit.AuditSnapshot(mechanical, observed, false).HasCode("OWN001")
    assert OwnershipAudit.AuditSnapshot(approved, observed, false).HasCode("OWN001")
}

test "manifest paths reject traversal wildcards duplicates aliases and noncanonical ordering" {
    firstPath := "src/NSharpLang.Compiler/A.cs"
    secondPath := "src/NSharpLang.Compiler/B.cs"
    text := "class A {}\n"

    wildcard := OwnershipFixtureOne(firstPath, text, 0).Replace(firstPath, "src/NSharpLang.Compiler/*.cs")
    assert OwnershipAudit.AuditSnapshot(wildcard, new List<OwnershipObservedFile>(), false).HasCode("OWN002")

    traversal := OwnershipFixtureOne(firstPath, text, 0).Replace(firstPath, "src/../Parser.cs")
    assert OwnershipAudit.AuditSnapshot(traversal, new List<OwnershipObservedFile>(), false).HasCode("OWN002")

    duplicateEntries := new List<OwnershipFixtureEntryValue>()
    duplicateEntries.Add(OwnershipFixtureExistingEntry(firstPath, text, 0))
    duplicateEntries.Add(OwnershipFixtureExistingEntry(firstPath, text, 0))
    duplicatePaths := new List<string>()
    duplicatePaths.Add(firstPath)
    duplicatePaths.Add(firstPath)
    duplicateManifest := OwnershipFixtureManifest(duplicateEntries, duplicatePaths, 1, "growth-ratchet", 0, "")
    assert OwnershipAudit.AuditSnapshot(duplicateManifest, OwnershipFixtureObservedList(firstPath, text), false).HasCode("OWN002")

    unorderedEntries := new List<OwnershipFixtureEntryValue>()
    unorderedEntries.Add(OwnershipFixtureExistingEntry(secondPath, text, 0))
    unorderedEntries.Add(OwnershipFixtureExistingEntry(firstPath, text, 0))
    unorderedPaths := new List<string>()
    unorderedPaths.Add(secondPath)
    unorderedPaths.Add(firstPath)
    unorderedObserved := new List<OwnershipObservedFile>()
    unorderedObserved.Add(OwnershipFixtureObserved(firstPath, text))
    unorderedObserved.Add(OwnershipFixtureObserved(secondPath, text))
    unorderedManifest := OwnershipFixtureManifest(unorderedEntries, unorderedPaths, 1, "growth-ratchet", 0, "")
    assert OwnershipAudit.AuditSnapshot(unorderedManifest, unorderedObserved, false).HasCode("OWN002")

    aliasEntries := new List<OwnershipFixtureEntryValue>()
    aliasEntries.Add(OwnershipFixtureExistingEntry(firstPath, text, 0))
    aliasEntries.Add(OwnershipFixtureExistingEntry("src/NSharpLang.Compiler/a.cs", text, 0))
    aliasPaths := new List<string>()
    aliasPaths.Add(firstPath)
    aliasPaths.Add("src/NSharpLang.Compiler/a.cs")
    aliasManifest := OwnershipFixtureManifest(aliasEntries, aliasPaths, 1, "growth-ratchet", 0, "")
    assert OwnershipAudit.AuditSnapshot(aliasManifest, new List<OwnershipObservedFile>(), false).HasCode("OWN002")
}

test "manifest classification is derived and cannot be self-declared" {
    path := "src/NSharpLang.Compiler/Parser.cs"
    text := "class Parser {}\n"
    observed := OwnershipFixtureObservedList(path, text)
    wrongLanguage := OwnershipFixtureOne(path, text, 0).Replace("\"language\":\"csharp\"", "\"language\":\"typescript\"")
    wrongSurface := OwnershipFixtureOne(path, text, 0).Replace("\"surface\":\"compiler-core\"", "\"surface\":\"editor\"")
    wrongScope := OwnershipFixtureOne(path, text, 0).Replace("\"campaignScope\":\"closeout\"", "\"campaignScope\":\"separate-campaign\"")
    assert OwnershipAudit.AuditSnapshot(wrongLanguage, observed, false).HasCode("OWN002")
    assert OwnershipAudit.AuditSnapshot(wrongSurface, observed, false).HasCode("OWN002")
    assert OwnershipAudit.AuditSnapshot(wrongScope, observed, false).HasCode("OWN002")
}

test "growth ratchet rejects new files metric growth assertion growth and fingerprint drift" {
    path := "tests/CompilerTests.cs"
    original := "[Fact]\nclass Tests {}\n"
    manifest := OwnershipFixtureOne(path, original, 0)

    addedPath := "tests/NewCompilerTests.cs"
    newFile := OwnershipAudit.AuditSnapshot(
        manifest,
        OwnershipFixtureObservedList(addedPath, "[Fact]\nclass NewTests {}\n"),
        false
    )
    assert newFile.HasCode("OWN003")

    grown := OwnershipAudit.AuditSnapshot(
        manifest,
        OwnershipFixtureObservedList(path, original + "class More {}\n"),
        false
    )
    assert grown.HasCode("OWN004")

    assertionGrowth := OwnershipAudit.AuditSnapshot(
        manifest,
        OwnershipFixtureObservedList(path, "[Fact]\n[Theory]\n"),
        false
    )
    assert assertionGrowth.HasCode("OWN004")

    drift := OwnershipAudit.AuditSnapshot(
        manifest,
        OwnershipFixtureObservedList(path, "[Fact]\nclass Other {}\n"),
        false
    )
    assert drift.HasCode("OWN005")
}

test "active debt must become removed and removed paths can never reappear" {
    path := "src/NSharpLang.Compiler/Parser.cs"
    text := "class Parser {}\n"
    missing := OwnershipAudit.AuditSnapshot(
        OwnershipFixtureOne(path, text, 0),
        new List<OwnershipObservedFile>(),
        false
    )
    assert missing.HasCode("OWN006")

    entries := new List<OwnershipFixtureEntryValue>()
    entries.Add(OwnershipFixtureRemovedEntry(path, text))
    paths := new List<string>()
    paths.Add(path)
    removedManifest := OwnershipFixtureManifest(entries, paths, 1, "growth-ratchet", 0, "")
    absent := OwnershipAudit.AuditSnapshot(removedManifest, new List<OwnershipObservedFile>(), false)
    assert absent.Succeeded

    reappeared := OwnershipAudit.AuditSnapshot(
        removedManifest,
        OwnershipFixtureObservedList(path, text),
        false
    )
    assert reappeared.HasCode("OWN007")
}

test "epoch count and path-set fingerprint are immutable facts" {
    path := "src/NSharpLang.Compiler/Parser.cs"
    text := "class Parser {}\n"
    observed := OwnershipFixtureObservedList(path, text)

    wrongCount := OwnershipFixtureOne(path, text, 0).Replace("\"epochFileCount\":1", "\"epochFileCount\":2")
    assert OwnershipAudit.AuditSnapshot(wrongCount, observed, false).HasCode("OWN008")

    wrongFingerprint := OwnershipFixtureOne(path, text, 0).Replace(
        "pathset-v1:",
        "pathset-v1:tampered-"
    )
    assert OwnershipAudit.AuditSnapshot(wrongFingerprint, observed, false).HasCode("OWN008")

    liveIdentity := OwnershipAudit.AuditSnapshot(OwnershipFixtureOne(path, text, 0), observed, true)
    assert liveIdentity.HasCode("OWN008")
}

test "reviewed policy constants prevent manifest-only epoch and head rebaselines" {
    path := "src/NSharpLang.Compiler/Parser.cs"
    originalText := "class Parser {}\n"
    paths := new List<string>()
    paths.Add(path)

    originalEntries := new List<OwnershipFixtureEntryValue>()
    originalEntries.Add(OwnershipFixtureExistingEntry(path, originalText, 5))
    originalModels := OwnershipFixtureModels(originalEntries)
    expectedPath := OwnershipFacts.PathSetFingerprint(paths)
    expectedEpoch := OwnershipFacts.EpochFactFingerprint(originalModels)
    expectedHead := OwnershipFacts.ReviewedHeadFingerprint(originalModels)
    originalManifest := OwnershipFixtureManifest(originalEntries, paths, 1, "growth-ratchet", 0, "")
    original := OwnershipAudit.AuditSnapshotAgainstPolicy(
        originalManifest,
        OwnershipFixtureObservedList(path, originalText),
        1,
        expectedPath,
        expectedEpoch,
        expectedHead
    )
    assert original.Succeeded

    originalObserved := OwnershipFixtureObserved(path, originalText)
    overCeilingEntries := new List<OwnershipFixtureEntryValue>()
    overCeilingEntries.Add(OwnershipFixtureEntry(
        originalObserved,
        "existing-debt",
        0,
        0,
        0,
        originalObserved.Lines,
        originalObserved.NonBlankLines,
        originalObserved.AssertionMarkers,
        0,
        0,
        originalObserved.Fingerprint
    ))
    overCeilingManifest := OwnershipFixtureManifest(overCeilingEntries, paths, 1, "growth-ratchet", 0, "")
    assert OwnershipAudit.AuditSnapshot(
        overCeilingManifest,
        OwnershipFixtureObservedList(path, originalText),
        false
    ).HasCode("OWN004")

    editedEpochEntries := new List<OwnershipFixtureEntryValue>()
    editedEpochEntries.Add(OwnershipFixtureExistingEntry(path, originalText, 6))
    editedEpochManifest := OwnershipFixtureManifest(editedEpochEntries, paths, 1, "growth-ratchet", 0, "")
    assert OwnershipAudit.AuditSnapshot(
        editedEpochManifest,
        OwnershipFixtureObservedList(path, originalText),
        false
    ).Succeeded
    editedEpoch := OwnershipAudit.AuditSnapshotAgainstPolicy(
        editedEpochManifest,
        OwnershipFixtureObservedList(path, originalText),
        1,
        expectedPath,
        expectedEpoch,
        expectedHead
    )
    assert editedEpoch.HasCode("OWN008")

    regrownText := "class Parser {}\nclass More {}\n"
    regrownObserved := OwnershipFixtureObserved(path, regrownText)
    originalEntry := originalEntries[0].Entry
    regrownEntry := OwnershipFixtureEntry(
        regrownObserved,
        "existing-debt",
        originalEntry.EpochLines,
        originalEntry.EpochNonBlankLines,
        originalEntry.EpochAssertionMarkers,
        regrownObserved.Lines,
        regrownObserved.NonBlankLines,
        regrownObserved.AssertionMarkers,
        0,
        0,
        regrownObserved.Fingerprint
    )
    regrownEntries := new List<OwnershipFixtureEntryValue>()
    regrownEntries.Add(regrownEntry)
    regrownManifest := OwnershipFixtureManifest(regrownEntries, paths, 1, "growth-ratchet", 0, "")
    regrownObservedList := OwnershipFixtureObservedList(path, regrownText)
    assert OwnershipAudit.AuditSnapshot(regrownManifest, regrownObservedList, false).Succeeded
    regrown := OwnershipAudit.AuditSnapshotAgainstPolicy(
        regrownManifest,
        regrownObservedList,
        1,
        expectedPath,
        expectedEpoch,
        expectedHead
    )
    assert regrown.HasCode("OWN008")

    removedEntries := new List<OwnershipFixtureEntryValue>()
    removedEntries.Add(OwnershipFixtureRemovedEntry(path, originalText))
    removedModels := OwnershipFixtureModels(removedEntries)
    removedEpoch := OwnershipFacts.EpochFactFingerprint(removedModels)
    removedHead := OwnershipFacts.ReviewedHeadFingerprint(removedModels)
    reintroducedEntries := new List<OwnershipFixtureEntryValue>()
    reintroducedEntries.Add(OwnershipFixtureExistingEntry(path, originalText, 0))
    reintroducedManifest := OwnershipFixtureManifest(reintroducedEntries, paths, 1, "growth-ratchet", 0, "")
    reintroducedObserved := OwnershipFixtureObservedList(path, originalText)
    assert OwnershipAudit.AuditSnapshot(reintroducedManifest, reintroducedObserved, false).Succeeded
    reintroduced := OwnershipAudit.AuditSnapshotAgainstPolicy(
        reintroducedManifest,
        reintroducedObserved,
        1,
        expectedPath,
        removedEpoch,
        removedHead
    )
    assert reintroduced.HasCode("OWN008")
}

test "runtime and native-reference surfaces are explicit campaign exclusions not survivors" {
    runtime := OwnershipPolicy.Classify("src/NSharpLang.Runtime/Index.cs")
    nativeReference := OwnershipPolicy.Classify("tests/native-benchmarks/range/reference.c")
    assert runtime.Included
    assert runtime.Surface == "runtime"
    assert runtime.CampaignScope == "separate-campaign"
    assert nativeReference.Included
    assert nativeReference.Language == "native"
    assert nativeReference.CampaignScope == "separate-campaign"
}

test "multi-error reports are deterministic complete and actionable" {
    firstPath := "src/NSharpLang.Compiler/A.cs"
    secondPath := "src/NSharpLang.Compiler/B.cs"
    manifest := OwnershipFixtureOne(firstPath, "class A {}\n", 0)
    result := OwnershipAudit.AuditSnapshot(
        manifest,
        OwnershipFixtureObservedList(secondPath, "class B {}\n"),
        false
    )
    expected := "N# ownership growth audit failed with 2 violation(s):\n" + "  OWN006 [src/NSharpLang.Compiler/A.cs]: active debt entry disappeared; mark it removed in the same deletion commit\n" + "  OWN003 [src/NSharpLang.Compiler/B.cs]: new unclassified non-N# file; implement this behavior in N# or remove the file. Do not add it to the E0 debt epoch\n"
    assert result.Report() == expected
}

test "repository non-NSharp ownership matches the E0 growth baseline" {
    result := OwnershipAudit.AuditLiveRepository()
    if !result.Succeeded {
        throw new System.InvalidOperationException(result.Report())
    }
    assert result.Succeeded
}
