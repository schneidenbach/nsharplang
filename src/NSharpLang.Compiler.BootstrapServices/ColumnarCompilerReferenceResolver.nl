namespace NSharpLang.Compiler

import System
import System.Collections
import System.Collections.Generic
import System.IO
import System.Reflection

// Owns the compiler's runtime reference lookup order. Reference-path walks use the inherited
// IEnumerable<string> enumerator explicitly so early success and every failure still run Dispose.
class ColumnarCompilerReferenceResolver {
    static func ResolveTestFrameworkType(
        fullTypeName: string,
        referenceAssemblyPaths: IReadOnlyList<string>?,
        assemblyNames: string[]
    ): Type {
        loadedAssemblies := ExternalAssemblyScan.Loaded()
        loadedIndex := 0
        while loadedIndex < loadedAssemblies.Length {
            loadedType := loadedAssemblies[loadedIndex].GetType(fullTypeName, false)
            if loadedType != null {
                return loadedType
            }
            loadedIndex = loadedIndex + 1
        }

        if referenceAssemblyPaths != null {
            referenceEnumerator := GetReferencePathEnumerator(referenceAssemblyPaths)
            referenceMovement := referenceEnumerator as IEnumerator
            try {
                while referenceMovement.MoveNext() {
                    referencePath := referenceEnumerator.get_Current()
                    fileName := Path.GetFileNameWithoutExtension(referencePath)
                    if !fileName.StartsWith("xunit", StringComparison.OrdinalIgnoreCase) && !fileName.StartsWith("nunit", StringComparison.OrdinalIgnoreCase) {
                        continue
                    }
                    loadedType: Type = null
                    if TryLoadTypeFromReferencePath(referencePath, fullTypeName, out loadedType) {
                        return loadedType
                    }
                }
            } finally {
                referenceDisposable := referenceEnumerator as IDisposable
                if referenceDisposable != null {
                    referenceDisposable.Dispose()
                }
            }
        }

        assemblyIndex := 0
        while assemblyIndex < assemblyNames.Length {
            assemblyName := assemblyNames[assemblyIndex]
            try {
                assemblyIdentity := new AssemblyName(assemblyName)
                assembly := Assembly.Load(assemblyIdentity)
                loadedType := assembly.GetType(fullTypeName, false)
                if loadedType != null {
                    return loadedType
                }
            } catch {
            }
            assemblyIndex = assemblyIndex + 1
        }

        throw new InvalidOperationException("Could not resolve required test framework type " + fullTypeName)
    }

    static func TryResolveReferencedType(
        referenceAssemblyPaths: IReadOnlyList<string>?,
        assemblySimpleName: string,
        fullTypeName: string,
        out result: Type
    ): bool {
        result = null
        if referenceAssemblyPaths == null {
            return false
        }

        referenceEnumerator := GetReferencePathEnumerator(referenceAssemblyPaths)
        referenceMovement := referenceEnumerator as IEnumerator
        try {
            while referenceMovement.MoveNext() {
                referencePath := referenceEnumerator.get_Current()
                if !string.Equals(Path.GetFileNameWithoutExtension(referencePath), assemblySimpleName, StringComparison.OrdinalIgnoreCase) {
                    continue
                }
                loadedType: Type = null
                if TryLoadTypeFromReferencePath(referencePath, fullTypeName, out loadedType) {
                    result = loadedType
                    return true
                }
            }
        } finally {
            referenceDisposable := referenceEnumerator as IDisposable
            if referenceDisposable != null {
                referenceDisposable.Dispose()
            }
        }

        return false
    }

    static func TryResolveLoadedExternalType(canonical: string, out result: Type): bool {
        result = null
        fullName: string? = null
        if canonical == "WebApplication" {
            fullName = "Microsoft.AspNetCore.Builder.WebApplication"
        } else if canonical == "WebApplicationBuilder" {
            fullName = "Microsoft.AspNetCore.Builder.WebApplicationBuilder"
        } else if canonical == "HttpContext" {
            fullName = "Microsoft.AspNetCore.Http.HttpContext"
        } else if canonical == "HttpRequest" {
            fullName = "Microsoft.AspNetCore.Http.HttpRequest"
        } else if canonical == "HttpResponse" {
            fullName = "Microsoft.AspNetCore.Http.HttpResponse"
        } else if canonical == "RequestDelegate" {
            fullName = "Microsoft.AspNetCore.Http.RequestDelegate"
        } else if canonical == "IResult" {
            fullName = "Microsoft.AspNetCore.Http.IResult"
        } else if canonical.Contains(".", StringComparison.Ordinal) {
            fullName = canonical
        }
        if fullName == null {
            return false
        }

        assemblies := AppDomain.CurrentDomain.GetAssemblies()
        assemblyIndex := 0
        while assemblyIndex < assemblies.Length {
            assembly := assemblies[assemblyIndex]
            candidate: Type? = null
            try {
                candidate = assembly.GetType(fullName, false)
            } catch {
                assemblyIndex = assemblyIndex + 1
                continue
            }
            if candidate != null && ColumnarTypeOfPlanner.IsSupportedExternalType(candidate) {
                result = candidate
                return true
            }
            assemblyIndex = assemblyIndex + 1
        }
        return false
    }

    static func GetReferencePathEnumerator(referenceAssemblyPaths: IEnumerable<string>): IEnumerator<string> {
        return referenceAssemblyPaths.GetEnumerator()
    }

    static func TryLoadTypeFromReferencePath(referencePath: string, fullTypeName: string, out result: Type): bool {
        result = null
        try {
            loadedAssembly := Assembly.LoadFrom(referencePath)
            loadedType := loadedAssembly.GetType(fullTypeName, false)
            if loadedType != null {
                result = loadedType
                return true
            }
        } catch {
        }
        return false
    }

    static func TryResolveAspNetReferencedType(
        referenceAssemblyPaths: IReadOnlyList<string>?,
        assemblySimpleName: string,
        fullTypeName: string,
        out result: Type
    ): bool {
        return TryResolveReferencedType(referenceAssemblyPaths, assemblySimpleName, fullTypeName, out result) || TryResolveLoadedExternalType(fullTypeName, out result)
    }

    static func TryResolveAspNetHttpContextType(
        referenceAssemblyPaths: IReadOnlyList<string>?,
        out result: Type
    ): bool {
        return TryResolveAspNetReferencedType(
            referenceAssemblyPaths,
            "Microsoft.AspNetCore.Http.Abstractions",
            "Microsoft.AspNetCore.Http.HttpContext",
            out result
        ) || TryResolveAspNetReferencedType(
            referenceAssemblyPaths,
            "Microsoft.AspNetCore.Http",
            "Microsoft.AspNetCore.Http.HttpContext",
            out result
        )
    }
}
