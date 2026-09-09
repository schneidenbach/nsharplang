namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO

// C# raw-string fixtures do not retain the line breaks beside their delimiters. N# multiline
// strings do, so remove exactly that pair while leaving every fixture byte inside it unchanged.
func MfcVisibilityDecodedSource(source: string): string {
    if source.StartsWith("\n", StringComparison.Ordinal) {
        decoded := source.Substring(1)
        if decoded.EndsWith("\n", StringComparison.Ordinal) {
            return decoded.Substring(0, decoded.Length - 1)
        }
        return decoded
    }
    return source
}

func MfcVisibilityTempRoot(tag: string): string {
    root := Path.Combine(
        Path.GetTempPath(),
        "nsharp-mfc-visibility-" + tag + "-" + Guid.NewGuid().ToString("N")
    )
    Directory.CreateDirectory(root)
    return root
}

func MfcVisibilityWrite(root: string, relativePath: string, source: string) {
    path := Path.Combine(root, relativePath)
    directory := Path.GetDirectoryName(path)
    if directory != null {
        Directory.CreateDirectory(directory)
    }
    File.WriteAllText(path, MfcVisibilityDecodedSource(source))
}

func MfcVisibilityCompileForAnalysis(root: string): MultiFileCompiler {
    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    compiler := new MultiFileCompiler(root, config)
    compiler.CompileForAnalysis()
    return compiler
}

func MfcVisibilityAssertIlEmission(root: string, assemblyName: string) {
    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    compiler := new MultiFileCompiler(root, config)
    compiler.AotMode = false
    outputPath := Path.Combine(root, "verification", assemblyName + ".dll")
    result := compiler.CompileToIlAssembly(assemblyName, outputPath, false, true)
    assert result.Success
    assert result.OutputAssemblyPath == outputPath
    assert File.Exists(outputPath)
}

func MfcVisibilityErrorCount(errors: IReadOnlyList<CompilerError>): int {
    count := 0
    index := 0
    while index < errors.Count {
        if errors[index].Severity == ErrorSeverity.Error {
            count = count + 1
        }
        index = index + 1
    }
    return count
}

func MfcVisibilitySingleExactMessage(
    errors: IReadOnlyList<CompilerError>,
    expected: string
): CompilerError {
    found: CompilerError? = null
    count := 0
    index := 0
    while index < errors.Count {
        if errors[index].Message == expected {
            found = errors[index]
            count = count + 1
        }
        index = index + 1
    }
    if found == null || count != 1 {
        throw new InvalidOperationException(
            "Expected one diagnostic message, found " + count.ToString() + ": " + expected
        )
    }
    return found
}

func MfcVisibilityHasMessageFragment(
    errors: IReadOnlyList<CompilerError>,
    fragment: string
): bool {
    index := 0
    while index < errors.Count {
        if errors[index].Message.Contains(fragment, StringComparison.Ordinal) {
            return true
        }
        index = index + 1
    }
    return false
}

test "MultiFileCompiler package import allows the exact PascalCase and explicit exports fixture" {
    root := MfcVisibilityTempRoot("package-exports")
    try {
        MfcVisibilityWrite(
            root,
            "project.yml",
            """
name: PackageVisibility
outputType: exe
targetFramework: net10.0
"""
        )
        MfcVisibilityWrite(
            root,
            "Models/Item.nl",
            """
package Models

class Item {
    func Visible(): string {
        return "visible"
    }
}

public class explicitItem {
    public func visibleExplicit(): string {
        return "explicit"
    }
}

func BuildItem(): Item {
    return new Item()
}

enum Status {
    Ready,
    hidden
}

public func buildExplicit(): explicitItem {
    return new explicitItem()
}
"""
        )
        MfcVisibilityWrite(
            root,
            "Program.nl",
            """
import Models

package App

func Main() {
    item := BuildItem()
    explicitValue := buildExplicit()
    print item.Visible()
    print explicitValue.visibleExplicit()
    print Status.hidden
}
"""
        )

        compiler := MfcVisibilityCompileForAnalysis(root)
        assert MfcVisibilityErrorCount(compiler.AllErrors) == 0
        MfcVisibilityAssertIlEmission(root, "PackageVisibility")
    } finally {
        if Directory.Exists(root) {
            Directory.Delete(root, true)
        }
    }
}

test "MultiFileCompiler package import rejects the exact camelCase types members and functions fixture" {
    root := MfcVisibilityTempRoot("package-hidden")
    try {
        MfcVisibilityWrite(
            root,
            "project.yml",
            """
name: PackageVisibility
outputType: exe
targetFramework: net10.0
"""
        )
        MfcVisibilityWrite(
            root,
            "Models/Item.nl",
            """
package Models

class Item {
    func hiddenMethod(): string {
        return "hidden"
    }
}

private class SecretPascal {
}

class hiddenThing {
}

union Outcome {
    Ok
    hidden
}

func hiddenFunction(): string {
    return "hidden"
}
"""
        )
        MfcVisibilityWrite(
            root,
            "Program.nl",
            """
import Models

package App

func Main() {
    thing := new hiddenThing()
    secret := new SecretPascal()
    item := new Item()
    print item.hiddenMethod()
    print Outcome.hidden
    print hiddenFunction()
}
"""
        )

        errors := MfcVisibilityCompileForAnalysis(root).AllErrors
        assert MfcVisibilityErrorCount(errors) == 5
        assert MfcVisibilitySingleExactMessage(
            errors,
            "'hiddenThing' is not exported from package/namespace 'Models' — use PascalCase for cross-package visibility or keep camelCase members inside the declaring package"
        ).Code == ErrorCode.InaccessibleMember
        assert MfcVisibilitySingleExactMessage(
            errors,
            "'SecretPascal' is not exported from package/namespace 'Models' — use PascalCase for cross-package visibility or keep camelCase members inside the declaring package"
        ).Code == ErrorCode.InaccessibleMember
        assert MfcVisibilitySingleExactMessage(
            errors,
            "'hiddenMethod' is not exported from package/namespace 'Models' — use PascalCase for cross-package visibility or keep camelCase members inside the declaring package"
        ).Code == ErrorCode.InaccessibleMember
        assert MfcVisibilitySingleExactMessage(
            errors,
            "'hidden' is not exported from package/namespace 'Models' — use PascalCase for cross-package visibility or keep camelCase members inside the declaring package"
        ).Code == ErrorCode.InaccessibleMember
        assert MfcVisibilitySingleExactMessage(
            errors,
            "'hiddenFunction' is not exported from package/namespace 'Models' — use PascalCase for cross-package visibility or keep camelCase members inside the declaring package"
        ).Code == ErrorCode.InaccessibleMember
    } finally {
        if Directory.Exists(root) {
            Directory.Delete(root, true)
        }
    }
}

test "MultiFileCompiler inaccessible member preserves the exact NL308 member span" {
    root := MfcVisibilityTempRoot("member-span")
    try {
        MfcVisibilityWrite(
            root,
            "project.yml",
            """
name: InaccessibleSpan
outputType: exe
targetFramework: net10.0
"""
        )
        MfcVisibilityWrite(
            root,
            "Models/Widget.nl",
            """
package Models

class Widget {
    func secretMethod(): string {
        return "x"
    }
}
"""
        )
        MfcVisibilityWrite(
            root,
            "Program.nl",
            """
import "Models/Widget"

package App

func Main() {
    w := new Widget()
    print w.secretMethod()
}
"""
        )

        errors := MfcVisibilityCompileForAnalysis(root).AllErrors
        diagnostic := MfcVisibilitySingleExactMessage(
            errors,
            "'secretMethod' is not exported from package/namespace 'Models' — use PascalCase for cross-package visibility or keep camelCase members inside the declaring package"
        )
        assert diagnostic.Code == ErrorCode.InaccessibleMember
        assert diagnostic.DiagnosticId == "NL308"
        assert diagnostic.Line == 7
        assert diagnostic.Column == 13
        assert diagnostic.Length == "secretMethod".Length
    } finally {
        if Directory.Exists(root) {
            Directory.Delete(root, true)
        }
    }
}

test "MultiFileCompiler package import selects the imported duplicate before project ambiguity" {
    root := MfcVisibilityTempRoot("duplicate-export")
    try {
        MfcVisibilityWrite(
            root,
            "project.yml",
            """
name: PackageVisibility
outputType: exe
targetFramework: net10.0
"""
        )
        MfcVisibilityWrite(
            root,
            "Models/Item.nl",
            """
package Models

class Item {
}
"""
        )
        MfcVisibilityWrite(
            root,
            "Other/Item.nl",
            """
package Other

class Item {
}
"""
        )
        MfcVisibilityWrite(
            root,
            "Program.nl",
            """
import Models

package App

func Main() {
    _item := new Item()
}
"""
        )

        compiler := MfcVisibilityCompileForAnalysis(root)
        assert MfcVisibilityErrorCount(compiler.AllErrors) == 0
        MfcVisibilityAssertIlEmission(root, "PackageVisibility")
    } finally {
        if Directory.Exists(root) {
            Directory.Delete(root, true)
        }
    }
}

test "MultiFileCompiler package import reports the hidden imported duplicate before ambiguity" {
    root := MfcVisibilityTempRoot("duplicate-hidden")
    try {
        MfcVisibilityWrite(
            root,
            "project.yml",
            """
name: PackageVisibility
outputType: exe
targetFramework: net10.0
"""
        )
        MfcVisibilityWrite(
            root,
            "Models/Item.nl",
            """
package Models

class hiddenThing {
}
"""
        )
        MfcVisibilityWrite(
            root,
            "Other/Item.nl",
            """
package Other

class hiddenThing {
}
"""
        )
        MfcVisibilityWrite(
            root,
            "Program.nl",
            """
import Models

package App

func Main() {
    thing := new hiddenThing()
}
"""
        )

        errors := MfcVisibilityCompileForAnalysis(root).AllErrors
        assert MfcVisibilitySingleExactMessage(
            errors,
            "'hiddenThing' is not exported from package/namespace 'Models' — use PascalCase for cross-package visibility or keep camelCase members inside the declaring package"
        ).Code == ErrorCode.InaccessibleMember
        assert !MfcVisibilityHasMessageFragment(errors, "defined in multiple files")
    } finally {
        if Directory.Exists(root) {
            Directory.Delete(root, true)
        }
    }
}

test "MultiFileCompiler namespace import rejects the exact camelCase types members and functions fixture" {
    root := MfcVisibilityTempRoot("namespace-hidden")
    try {
        MfcVisibilityWrite(
            root,
            "project.yml",
            """
name: NamespaceVisibility
outputType: exe
targetFramework: net10.0
"""
        )
        MfcVisibilityWrite(
            root,
            "Models/Item.nl",
            """
namespace Models

class Item {
    func hiddenMethod(): string {
        return "hidden"
    }
}

private class SecretPascal {
}

class hiddenThing {
}

enum Status {
    Ready,
    hidden
}

union Outcome {
    Ok
    hidden
}

func hiddenFunction(): string {
    return "hidden"
}
"""
        )
        MfcVisibilityWrite(
            root,
            "Program.nl",
            """
namespace App

import Models

func Main() {
    thing := new hiddenThing()
    secret := new SecretPascal()
    item := new Item()
    print item.hiddenMethod()
    print Outcome.hidden
    print hiddenFunction()
}
"""
        )

        errors := MfcVisibilityCompileForAnalysis(root).AllErrors
        assert MfcVisibilityErrorCount(errors) == 5
        assert MfcVisibilitySingleExactMessage(
            errors,
            "'hiddenThing' is not exported from package/namespace 'Models' — use PascalCase for cross-package visibility or keep camelCase members inside the declaring package"
        ).Code == ErrorCode.InaccessibleMember
        assert MfcVisibilitySingleExactMessage(
            errors,
            "'SecretPascal' is not exported from package/namespace 'Models' — use PascalCase for cross-package visibility or keep camelCase members inside the declaring package"
        ).Code == ErrorCode.InaccessibleMember
        assert MfcVisibilitySingleExactMessage(
            errors,
            "'hiddenMethod' is not exported from package/namespace 'Models' — use PascalCase for cross-package visibility or keep camelCase members inside the declaring package"
        ).Code == ErrorCode.InaccessibleMember
        assert MfcVisibilitySingleExactMessage(
            errors,
            "'hidden' is not exported from package/namespace 'Models' — use PascalCase for cross-package visibility or keep camelCase members inside the declaring package"
        ).Code == ErrorCode.InaccessibleMember
        assert MfcVisibilitySingleExactMessage(
            errors,
            "'hiddenFunction' is not exported from package/namespace 'Models' — use PascalCase for cross-package visibility or keep camelCase members inside the declaring package"
        ).Code == ErrorCode.InaccessibleMember
    } finally {
        if Directory.Exists(root) {
            Directory.Delete(root, true)
        }
    }
}
