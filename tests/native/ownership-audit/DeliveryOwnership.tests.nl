namespace NSharpLang.OwnershipAudit

import System.Collections.Generic

test "delivery review has exact paths and never admits compiler or adjacent files" {
    assert DeliveryOwnershipPolicy.Fingerprint(".github/workflows/build.yml") != ""
    assert DeliveryOwnershipPolicy.Fingerprint(".github/workflows/another.yml") == ""
    assert DeliveryOwnershipPolicy.Fingerprint("src/NSharpLang.Compiler/Compiler.cs") == ""
    assert DeliveryOwnershipPolicy.Fingerprint("scripts/another.py") == ""
    assert DeliveryOwnershipPolicy.Fingerprint(".github/workflows/../workflows/build.yml") == ""
    assert DeliveryOwnershipPolicy.Fingerprint("bootstrap/NSharpLang.Sdk.0.2.0.nupkg") == ""
}

test "delivery review rejects missing files including the seed packages" {
    observed := new List<OwnershipObservedFile>()
    result := new OwnershipAuditResult()
    DeliveryOwnershipPolicy.ValidatePresence(observed, result)
    assert !result.Succeeded
    assert result.Diagnostics.Count == DeliveryOwnershipPolicy.Paths().Length
}

test "delivery snapshot changes cannot borrow the historical epoch fingerprint" {
    path := ".github/workflows/build.yml"
    text := "name: changed\n"
    observed := new List<OwnershipObservedFile>()
    observed.Add(OwnershipFacts.Observe(path, OwnershipPolicy.Classify(path), text))
    manifest := OwnershipFixtureOne(path, text, 0)
    result := OwnershipAudit.AuditSnapshot(manifest, observed, false)
    assert !result.Succeeded
    assert result.Report().Contains("reviewed delivery snapshot drift")
}
