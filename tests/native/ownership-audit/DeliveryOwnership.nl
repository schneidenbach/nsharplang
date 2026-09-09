namespace NSharpLang.OwnershipAudit

import System.Collections.Generic

// User-requested delivery repair, September 9, 2026. These exact snapshots are
// outside compiler migration E0; no directory, language, or compiler exemption.
// Every later edit requires an explicit review of this record, including deletions.
class DeliveryOwnershipPolicy {
    static func Paths(): string[] {
        return [
            ".github/workflows/build.yml",
            ".github/workflows/cleanup-unofficial.yml",
            ".github/workflows/deploy-website.yml",
            ".github/workflows/publish.yml",
            ".gitignore",
            "NuGet.config",
            "bootstrap/NSharpLang.Runtime.0.1.0.nupkg",
            "bootstrap/NSharpLang.Sdk.0.1.0.nupkg",
            "scripts/lib/packages.sh",
            "scripts/pack-nuget.sh",
            "scripts/verify-bootstrap.py",
            "scripts/verify-release.py",
            "tests/NSharpLang.IntegrationTests/ToolchainFixture.cs",
            "tests/scripts/test-all.sh",
            "tests/scripts/test-release-workflows.py"
        ]
    }

    static func Fingerprint(path: string): string {
        if path == ".github/workflows/build.yml" {
            return "text-v1:010774f9d772cfb5"
        }
        if path == ".github/workflows/cleanup-unofficial.yml" {
            return "text-v1:7338cd13d4fc1ef4"
        }
        if path == ".github/workflows/deploy-website.yml" {
            return "text-v1:2fe571c209b4ceac"
        }
        if path == ".github/workflows/publish.yml" {
            return "text-v1:0342dc609d15164d"
        }
        if path == ".gitignore" {
            return "text-v1:c69cf41855be1019"
        }
        if path == "NuGet.config" {
            return "text-v1:3d3d168339548fa7"
        }
        if path == "bootstrap/NSharpLang.Runtime.0.1.0.nupkg" {
            return "binary-v1:2e0fa24ab2748f34"
        }
        if path == "bootstrap/NSharpLang.Sdk.0.1.0.nupkg" {
            return "binary-v1:0d797850166417f8"
        }
        if path == "scripts/lib/packages.sh" {
            return "text-v1:a14472510bd75cac"
        }
        if path == "scripts/pack-nuget.sh" {
            return "text-v1:4a62685e3e4e0eba"
        }
        if path == "scripts/verify-bootstrap.py" {
            return "text-v1:ef150868dd33b873"
        }
        if path == "scripts/verify-release.py" {
            return "text-v1:f7a190da83e1642f"
        }
        if path == "tests/NSharpLang.IntegrationTests/ToolchainFixture.cs" {
            return "text-v1:9240fa0e545cc152"
        }
        if path == "tests/scripts/test-all.sh" {
            return "text-v1:731255217cac719a"
        }
        if path == "tests/scripts/test-release-workflows.py" {
            return "text-v1:51739369e5a2e5db"
        }
        return ""
    }

    static func ValidatePresence(observed: List<OwnershipObservedFile>, result: OwnershipAuditResult) {
        paths := Paths()
        for path in paths {
            found := false
            for observedFile in observed {
                if observedFile.Path == path {
                    found = true
                }
            }
            if !found {
                result.Add("OWN006", path, "reviewed delivery file disappeared; review its retirement explicitly")
            }
        }
    }
}
