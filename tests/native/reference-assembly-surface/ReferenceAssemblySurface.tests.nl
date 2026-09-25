namespace NSharpLang.ReferenceAssemblySurface.Tests

import System.Collections.Generic
import System.IO

// The subject: one class with a public surface, a package-private helper type, a private method, a
// capturing lambda (which synthesizes a display class) and an iterator (which synthesizes a state
// machine). Everything below the public surface exists here so that the rows can say it is gone.
func SurfaceLibrarySource(body: string, signature: string): string {
    return "namespace Surface\n" + "\n" + "import System\n" + "import System.Collections.Generic\n" + "\n" + "class Greeter {\n" + "    Name: string\n" + "\n" + "    constructor(name: string) {\n" + "        Name = name\n" + "    }\n" + "\n" + "    func " + signature + " {\n" + body + "    }\n" + "\n" + "    private func Hidden(): int {\n" + "        return 41\n" + "    }\n" + "\n" + "    func Doubled(values: List<int>): List<int> {\n" + "        factor := 2\n" + "        result := new List<int>()\n" + "        values.ForEach(value => result.Add(value * factor))\n" + "        return result\n" + "    }\n" + "}\n" + "\n" + "class helperState {\n" + "    Count: int\n" + "\n" + "    constructor() {\n" + "        Count = 0\n" + "    }\n" + "}\n"
}

func SurfaceDefaultBody(): string {
    return "        return \"hello \" + Name\n"
}

func SurfaceDefaultSignature(): string {
    return "Greet(): string"
}

test "the emitted reference assembly is a surface: no bodies, no private members, no synthesized types" {
    scratch := SurfaceScratch("surface")
    try {
        SurfaceWriteProject(scratch, "Surface", SurfaceLibrarySource(SurfaceDefaultBody(), SurfaceDefaultSignature()))
        compilation := SurfaceCompile(scratch, "Surface", SurfaceNoExtraReferences())

        assert File.Exists(compilation.ReferencePath)
        implementationBytes := File.ReadAllBytes(compilation.OutputPath)
        referenceBytes := File.ReadAllBytes(compilation.ReferencePath)
        assert referenceBytes.Length < implementationBytes.Length

        attributes := SurfaceAssemblyAttributeNames(compilation.ReferencePath)
        assert SurfaceContains(attributes, "System.Runtime.CompilerServices.ReferenceAssemblyAttribute")

        offenders := SurfaceNonThrowNullBodies(compilation.ReferencePath)
        assert offenders.Count == 0, "bodies survived into the reference assembly: " + string.Join(", ", offenders)

        implementationTypes := SurfaceTypeNames(compilation.OutputPath)
        referenceTypes := SurfaceTypeNames(compilation.ReferencePath)
        assert SurfaceContains(referenceTypes, "Surface.Greeter")
        assert SurfaceCountPrefixed(implementationTypes, "<>") > 0
        assert SurfaceCountPrefixed(referenceTypes, "<>") == 0
        assert SurfaceContains(implementationTypes, "Surface.helperState")
        assert !SurfaceContains(referenceTypes, "Surface.helperState")

        implementationMethods := SurfaceMethodNames(compilation.OutputPath, "Surface.Greeter")
        referenceMethods := SurfaceMethodNames(compilation.ReferencePath, "Surface.Greeter")
        assert SurfaceContains(implementationMethods, "Hidden")
        assert !SurfaceContains(referenceMethods, "Hidden")
        assert SurfaceContains(referenceMethods, "Greet")
        assert SurfaceContains(referenceMethods, "Doubled")
        assert SurfaceContains(referenceMethods, ".ctor")

        // `PersistedAssemblyBuilder` scopes its type references to the implementation core library;
        // the surface names the reference pack instead, or nothing could compile against it.
        scopes := SurfaceTypeReferenceScopeNames(compilation.ReferencePath)
        assert !SurfaceContains(scopes, "System.Private.CoreLib")
        assert SurfaceContains(scopes, "System.Runtime")
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "an implementation-only edit leaves the reference assembly byte-identical and a signature change does not" {
    scratch := SurfaceScratch("stability")
    try {
        SurfaceWriteProject(scratch, "Surface", SurfaceLibrarySource(SurfaceDefaultBody(), SurfaceDefaultSignature()))
        first := SurfaceCompile(scratch, "Surface", SurfaceNoExtraReferences())
        firstReference := File.ReadAllBytes(first.ReferencePath)
        firstImplementation := File.ReadAllBytes(first.OutputPath)

        // Same program, compiled again: the module version id and the timestamp are content-derived,
        // so nothing moves.
        repeated := SurfaceCompile(scratch, "Surface", SurfaceNoExtraReferences())
        assert SurfaceBytesEqual(firstReference, File.ReadAllBytes(repeated.ReferencePath))

        // A BODY ONLY. Different IL, different string literal, same surface.
        SurfaceWriteProject(
            scratch,
            "Surface",
            SurfaceLibrarySource("        return \"a completely different greeting for \" + Name + \"!\"\n", SurfaceDefaultSignature())
        )
        bodyEdit := SurfaceCompile(scratch, "Surface", SurfaceNoExtraReferences())
        assert !SurfaceBytesEqual(firstImplementation, File.ReadAllBytes(bodyEdit.OutputPath))
        assert SurfaceBytesEqual(firstReference, File.ReadAllBytes(bodyEdit.ReferencePath))

        // THE SIGNATURE. One added parameter is a different surface, and the bytes say so.
        SurfaceWriteProject(
            scratch,
            "Surface",
            SurfaceLibrarySource("        return \"hello \" + Name\n", "Greet(times: int): string")
        )
        signatureEdit := SurfaceCompile(scratch, "Surface", SurfaceNoExtraReferences())
        assert !SurfaceBytesEqual(firstReference, File.ReadAllBytes(signatureEdit.ReferencePath))
    } finally {
        Directory.Delete(scratch, true)
    }
}

test "a consumer binds against the reference assembly alone" {
    scratch := SurfaceScratch("consumer")
    try {
        libraryDirectory := Path.Combine(scratch, "Library")
        SurfaceWriteProject(libraryDirectory, "Surface", SurfaceLibrarySource(SurfaceDefaultBody(), SurfaceDefaultSignature()))
        library := SurfaceCompile(libraryDirectory, "Surface", SurfaceNoExtraReferences())

        consumerDirectory := Path.Combine(scratch, "Consumer")
        SurfaceWriteProject(
            consumerDirectory,
            "Consumer",
            "namespace Consumer\n" + "\n" + "import System.Collections.Generic\n" + "import Surface\n" + "\n" + "class Caller {\n" + "    static func Run(): string {\n" + "        greeter := new Greeter(\"world\")\n" + "        doubled := greeter.Doubled(new List<int>())\n" + "        return greeter.Greet() + doubled.Count.ToString()\n" + "    }\n" + "}\n"
        )
        references := new List<string>()
        references.Add(library.ReferencePath)
        diagnostics := SurfaceAnalyze(consumerDirectory, references)
        assert diagnostics.Count == 0, "the consumer did not bind against the reference assembly: " + string.Join(" | ", diagnostics)

        // The same source against the IMPLEMENTATION binds identically, so the surface carried
        // everything the consumer needed and nothing it did not.
        implementationReferences := new List<string>()
        implementationReferences.Add(library.OutputPath)
        implementationDiagnostics := SurfaceAnalyze(consumerDirectory, implementationReferences)
        assert implementationDiagnostics.Count == 0, string.Join(" | ", implementationDiagnostics)
    } finally {
        Directory.Delete(scratch, true)
    }
}
