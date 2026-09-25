namespace NSharpLang.Cli.Commands

class UpdateArgumentSummary {
    TargetPackage: string?
    DryRun: bool
    ShowHelp: bool

    constructor(targetPackage: string?, dryRun: bool, showHelp: bool) {
        TargetPackage = targetPackage
        DryRun = dryRun
        ShowHelp = showHelp
    }
}

class UpdateCommandKernels {
    static func GetArgumentSummary(args: string[]): UpdateArgumentSummary {
        targetPackage: string? = null
        dryRun := false
        showHelp := false

        i := 0
        while i < args.Length {
            arg := args[i]
            if i == 0 && arg == "help" {
                showHelp = true
            }

            if arg == "--dry-run" {
                dryRun = true
            }

            if arg == "--help" || arg == "-h" {
                showHelp = true
            }

            if targetPackage == null {
                if arg.Length == 0 {
                    targetPackage = arg
                } else if arg[0] != '-' {
                    targetPackage = arg
                }
            }

            i = i + 1
        }

        return new UpdateArgumentSummary(targetPackage, dryRun, showHelp)
    }

    static func GetHelpText(): string {
        return "N# Update Dependencies\n" + "\n" + "Usage: nlc update [package] [options]\n" + "\n" + "Update NuGet dependencies to their latest versions. If a package name is\n" + "given, only that package is updated. Otherwise all NuGet dependencies\n" + "are checked.\n" + "\n" + "Options:\n" + "  --dry-run       Show what would change without modifying files\n" + "  --help, -h      Show this help text\n" + "\n" + "Examples:\n" + "  nlc update\n" + "  nlc update Newtonsoft.Json\n" + "  nlc update --dry-run\n" + "\n" + "Exit codes:\n" + "  0  Update completed successfully\n" + "  1  Update failed"
    }

    static func GetMissingProjectFileMessage(): string {
        return "No project.yml found."
    }

    static func GetNoNuGetDependenciesMessage(): string {
        return "No NuGet dependencies to update."
    }

    static func GetPackageNotFoundMessage(packageName: string): string {
        return "Package '" + packageName + "' not found in dependencies."
    }

    static func GetResolveLatestFailureMessage(packageName: string): string {
        return "  Could not resolve latest version for " + packageName
    }

    static func GetPackageUpToDateMessage(packageName: string, version: string): string {
        return "  " + packageName + "@" + version + " is up to date"
    }

    static func GetPackageUpdateMessage(packageName: string, currentVersion: string, latestVersion: string): string {
        version := currentVersion
        if version.Length == 0 {
            version = "unversioned"
        }

        return "  " + packageName + ": " + version + " -> " + latestVersion
    }

    static func GetUpdatedPackagesMessage(updatedCount: int): string {
        suffix := "s"
        if updatedCount == 1 {
            suffix = ""
        }

        return "Updated " + updatedCount.ToString() + " package" + suffix + "."
    }

    static func GetDryRunMessage(): string {
        return "(dry run — no changes made)"
    }

    static func GetAllPackagesUpToDateMessage(): string {
        return "All packages are up to date."
    }

    static func GetFailedMessage(message: string): string {
        return "Update failed: " + message
    }
}
