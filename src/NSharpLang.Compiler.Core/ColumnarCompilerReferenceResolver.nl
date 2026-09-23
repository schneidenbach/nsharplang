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
        for loadedAssembly in loadedAssemblies {
            loadedType := loadedAssembly.GetType(fullTypeName, false)
            if loadedType != null {
                return loadedType
            }
        }

        if referenceAssemblyPaths != null {
            referenceEnumerator := GetReferencePathEnumerator(referenceAssemblyPaths)
            referenceMovement := referenceEnumerator as IEnumerator
            try {
                while referenceMovement.MoveNext() {
                    referencePath := referenceEnumerator.get_Current()
                    fileName := Path.GetFileNameWithoutExtension(referencePath)
                    if !TestFrameworkReferenceSet.IsFrameworkAssemblyName(fileName) {
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

        // The test framework is the HOST's assembly, not a file in the project's closure, so this
        // last resort is the owner's documented by-name route into the default context rather than
        // a fourth `Assembly.Load` of its own.
        for assemblyName in assemblyNames {
            try {
                assemblyIdentity := new AssemblyName(assemblyName)
                assembly := ExternalAssemblyScan.TryLoadHostAssemblyByName(assemblyIdentity)
                if assembly != null {
                    loadedType := assembly.GetType(fullTypeName, false)
                    if loadedType != null {
                        return loadedType
                    }
                }
            } catch {

                // A name this host cannot spell, or a type whose own dependencies will not load, is
                // not the answer; the next candidate name is.
            }
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

        // The same snapshot the owner reads, rather than a fourth walk of the process's assemblies:
        // membership and order are identical to the `AppDomain` call this replaced, so which type a
        // program binds here is unchanged.
        assemblies := ExternalAssemblyScan.LoadedAcrossContexts()
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

    // ONE OWNER DECIDES WHICH RUNTIME ASSEMBLY A REFERENCE PATH MEANS, and it is
    // `ExternalAssemblyScan`. This walk used to call `Assembly.LoadFrom` itself, which is a SECOND
    // answer to that question and therefore a second LOAD CONTEXT: the owner's rule puts a reference
    // the default context does not already answer for into the compiler's owned context, so a path
    // loaded here into the DEFAULT context produced a second copy of the same types. Types from two
    // contexts share their names and nothing else, so the AspNet route residual's synthesized
    // `Func<HttpContext, Task>` stopped matching the `HttpContext` the lambda's parameter had
    // resolved to -- measured on `tests/fixtures/issue-tracker`, where the residual emitted the
    // pattern string, declined at the handler, and a later tier emitted the whole call again over
    // the leftover: `ilverify` refused `Routes::Map` with `StackUnexpected` and `ReturnVoid`.
    //
    // Asking the owner costs one `AssemblyName.GetAssemblyName` and answers with whatever context
    // already holds that exact identity, so this walk and the scan can no longer disagree.
    static func TryLoadTypeFromReferencePath(referencePath: string, fullTypeName: string, out result: Type): bool {
        result = null
        try {
            identity := AssemblyName.GetAssemblyName(referencePath).FullName
            loadedAssembly := ExternalAssemblyScan.TryLoadExactIdentityAssembly(referencePath, identity)
            if loadedAssembly == null {
                return false
            }

            loadedType := loadedAssembly.GetType(fullTypeName, false)
            if loadedType != null {
                result = loadedType
                return true
            }
        } catch {

            // A path with no readable identity, or an image with no executable handle, is not an
            // answer; the caller's next reference path is.
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
