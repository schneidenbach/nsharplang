namespace NSharpLang.OwnershipAudit

import System
import System.Collections.Generic
import System.IO

// The delivery row class. Config, MSBuild, shell and binary surfaces ship the product rather than
// implement it, so they are judged by review instead of by size: an exact-match fingerprint, the
// recorded line counts the report quotes, and no ceiling. A new delivery file is admitted only by
// adding its row in a reviewed repin, so it is refused until that row exists.
test "the policy splits code languages from reviewed delivery languages" {
    assert OwnershipPolicy.IsDeliveryLanguage("msbuild")
    assert OwnershipPolicy.IsDeliveryLanguage("shell")
    assert OwnershipPolicy.IsDeliveryLanguage("powershell")
    assert OwnershipPolicy.IsDeliveryLanguage("yaml-config")
    assert OwnershipPolicy.IsDeliveryLanguage("json-config")
    assert OwnershipPolicy.IsDeliveryLanguage("product-config")
    assert OwnershipPolicy.IsDeliveryLanguage("policy-data")
    assert OwnershipPolicy.IsDeliveryLanguage("gradle-config")
    assert OwnershipPolicy.IsDeliveryLanguage("package-binary")
    assert OwnershipPolicy.IsCodeLanguage("csharp")
    assert OwnershipPolicy.IsCodeLanguage("typescript")
    assert OwnershipPolicy.IsCodeLanguage("javascript")
    assert OwnershipPolicy.IsCodeLanguage("python")
    assert OwnershipPolicy.IsCodeLanguage("rust")
    assert OwnershipPolicy.IsCodeLanguage("gradle-kotlin")

    assert OwnershipPolicy.IsDeliveryPath("src/NSharpLang.Sdk/Sdk/Sdk.targets")
    assert OwnershipPolicy.IsDeliveryPath("scripts/lib/packages.sh")
    assert OwnershipPolicy.IsDeliveryPath("bootstrap/NSharpLang.Sdk.0.1.0.nupkg")
    assert !OwnershipPolicy.IsDeliveryPath("src/NSharpLang.Compiler/Parser.cs")
    assert !OwnershipPolicy.IsDeliveryPath("scripts/verify-bootstrap.py")
    assert !OwnershipPolicy.IsDeliveryPath("src/NSharpLang.Compiler.Core/Analyzer.nl")
}

test "a reviewed delivery row accepts its snapshot and always reports drift without a ceiling" {
    path := "src/NSharpLang.Sdk/Sdk/Sdk.targets"
    text := "<Project>\n</Project>\n"
    manifest := OwnershipFixtureOneDelivery(path, text)
    assert OwnershipAudit.AuditSnapshot(manifest, OwnershipFixtureObservedList(path, text), false).Succeeded

    grown := OwnershipAudit.AuditSnapshot(
        manifest,
        OwnershipFixtureObservedList(path, "<Project>\n  <Target Name=\"Pack\" />\n</Project>\n"),
        false
    )
    assert grown.HasCode("OWN005")
    assert !grown.HasCode("OWN004")
    assert grown.Report().Contains("reviewed delivery snapshot drift")

    sameSizeEdit := OwnershipAudit.AuditSnapshot(
        manifest,
        OwnershipFixtureObservedList(path, "<Project>\n</Projects>\n"),
        false
    )
    assert sameSizeEdit.HasCode("OWN005")
}

test "a new delivery file is refused until its row is reviewed" {
    reviewedPath := "scripts/lib/packages.sh"
    text := "echo pack\n"
    manifest := OwnershipFixtureOneDelivery(reviewedPath, text)

    observed := new List<OwnershipObservedFile>()
    observed.Add(OwnershipFixtureObserved(reviewedPath, text))
    observed.Add(OwnershipFixtureObserved("scripts/lib/publish.sh", "echo publish\n"))

    admitted := OwnershipAudit.AuditSnapshot(manifest, observed, false)
    assert admitted.HasCode("OWN003")
    assert admitted.Report().Contains("admitted only by adding its row in a reviewed repin")
}

test "a delivery row cannot carry a ceiling and a code row cannot drop one" {
    deliveryPath := ".github/workflows/publish.yml"
    deliveryText := "name: publish\n"
    deliveryManifest := OwnershipFixtureOneDelivery(deliveryPath, deliveryText)
    deliveryObserved := OwnershipFixtureObservedList(deliveryPath, deliveryText)

    withCeiling := deliveryManifest.Replace("\"state\":\"reviewed\"", "\"state\":\"reviewed\",\"epochLines\":1")
    withCeilingResult := OwnershipAudit.AuditSnapshot(withCeiling, deliveryObserved, false)
    assert withCeilingResult.HasCode("OWN001")
    assert withCeilingResult.Report().Contains("carries no ceiling; remove field 'epochLines'")

    withMarkers := deliveryManifest.Replace(
        "\"state\":\"reviewed\"",
        "\"state\":\"reviewed\",\"currentAssertionMarkers\":0"
    )
    assert OwnershipAudit.AuditSnapshot(withMarkers, deliveryObserved, false).HasCode("OWN001")

    debtState := deliveryManifest.Replace("\"state\":\"reviewed\"", "\"state\":\"existing-debt\"")
    assert OwnershipAudit.AuditSnapshot(debtState, deliveryObserved, false).HasCode("OWN001")

    codePath := "src/NSharpLang.Compiler/Parser.cs"
    codeText := "class Parser {}\n"
    codeManifest := OwnershipFixtureOne(codePath, codeText, 0)
    codeObserved := OwnershipFixtureObservedList(codePath, codeText)

    withoutCeiling := codeManifest.Replace("\"epochAssertionMarkers\":0,", "")
    assert OwnershipAudit.AuditSnapshot(withoutCeiling, codeObserved, false).HasCode("OWN001")

    reviewedState := codeManifest.Replace("\"state\":\"existing-debt\"", "\"state\":\"reviewed\"")
    assert OwnershipAudit.AuditSnapshot(reviewedState, codeObserved, false).HasCode("OWN001")
}

test "a reviewed delivery file cannot disappear and its recorded counts cannot go stale" {
    path := "scripts/pack-nuget.sh"
    text := "echo pack\n"
    manifest := OwnershipFixtureOneDelivery(path, text)

    missing := OwnershipAudit.AuditSnapshot(manifest, new List<OwnershipObservedFile>(), false)
    assert missing.HasCode("OWN006")
    assert missing.Report().Contains("reviewed delivery file disappeared")

    staleCounts := manifest.Replace("\"currentLines\":1", "\"currentLines\":2")
    stale := OwnershipAudit.AuditSnapshot(staleCounts, OwnershipFixtureObservedList(path, text), false)
    assert stale.HasCode("OWN001")
    assert stale.Report().Contains("records stale counts")
}

test "the delivery surfaces the user reviewed are ordinary rows of the live manifest" {
    root := OwnershipAudit.FindRepositoryRoot(Environment.CurrentDirectory) ?? ""
    manifest := File.ReadAllText(Path.Combine(root, "tests/native/ownership-audit/" + OwnershipPolicy.ManifestFileName))

    assert manifest.Contains("\"path\":\"bootstrap/NSharpLang.Runtime.0.1.0.nupkg\"")
    assert manifest.Contains("\"path\":\"bootstrap/NSharpLang.Sdk.0.1.0.nupkg\"")
    assert manifest.Contains("\"path\":\"scripts/lib/packages.sh\"")
    assert manifest.Contains("\"path\":\"scripts/pack-nuget.sh\"")
    assert manifest.Contains("\"path\":\"scripts/verify-bootstrap.py\"")
    assert manifest.Contains("\"path\":\"scripts/verify-release.py\"")
    assert manifest.Contains("\"path\":\"src/NSharpLang.Sdk/NSharpLang.Sdk.csproj\"")
    assert manifest.Contains("\"path\":\"src/NSharpLang.Sdk/Sdk/Sdk.targets\"")
    assert manifest.Contains("\"path\":\"NuGet.config\"")
    assert manifest.Contains("\"path\":\".github/workflows/cleanup-unofficial.yml\"")
    assert manifest.Contains("\"path\":\"tests/NSharpLang.IntegrationTests/ToolchainFixture.cs\"")
    assert manifest.Contains("\"path\":\"tests/scripts/test-release-workflows.py\"")
}
