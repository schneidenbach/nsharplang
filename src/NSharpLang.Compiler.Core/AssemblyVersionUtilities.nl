namespace NSharpLang.Compiler

import System

class AssemblyVersionUtilities {
    static DefaultAssemblyVersion: Version => new Version(1, 0, 0, 0)

    static func GetAssemblyVersionOrDefault(packageVersion: string?): Version {
        assemblyVersion := AssemblyVersionUtilities.DefaultAssemblyVersion
        if TryGetAssemblyVersion(packageVersion, out assemblyVersion) {
            return assemblyVersion
        }

        return AssemblyVersionUtilities.DefaultAssemblyVersion
    }

    static func TryGetAssemblyVersion(packageVersion: string?, out assemblyVersion: Version): bool {
        assemblyVersion = AssemblyVersionUtilities.DefaultAssemblyVersion

        if packageVersion == null {
            return false
        }

        numericCore := packageVersion.Trim()
        if numericCore.Length == 0 {
            return false
        }

        metadataIndex := FindMetadataIndex(numericCore)
        if metadataIndex >= 0 {
            numericCore = numericCore.Substring(0, metadataIndex)
        }

        parts := numericCore.Split('.')
        if parts.Length < 2 || parts.Length > 4 {
            return false
        }

        values := new int[](4)
        i := 0
        while i < parts.Length {
            componentValue := 0
            if !AssemblyVersionKernels.TryParseComponent(parts[i], out componentValue) {
                return false
            }

            values[i] = componentValue
            i = i + 1
        }

        assemblyVersion = new Version(values[0], values[1], values[2], values[3])
        return true
    }

    static func FindMetadataIndex(value: string): int {
        i := 0
        while i < value.Length {
            ch := value[i]
            if ch == '-' || ch == '+' {
                return i
            }

            i = i + 1
        }

        return -1
    }
}
