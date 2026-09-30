namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO

// WHAT N# REFUSES WHEN A WRITTEN ACCESSIBILITY WORD IS IGNORED, and the exact sentence it refuses
// with.
//
// `tests/native/census-accessibility` runs the POSITIVE half as emitted IL: a derived type reading
// its base's protected state through `this`, a bare name and `base`, and the metadata each word
// produces. A native test only exists if its project compiles, so the refusals — and the wording a
// developer actually reads — can only be pinned here.
//
// Every fixture is a single-file library. The package rule (NL308's other half) needs two packages
// to fire and is pinned in `MultiFileCompilerVisibility.tests.nl`; everything below is one namespace,
// so the only thing that can refuse these reads is the DECLARED accessibility relation.
func AccessDiagDecodedSource(source: string): string {
    if source.StartsWith("\n", StringComparison.Ordinal) {
        decoded := source.Substring(1)
        if decoded.EndsWith("\n", StringComparison.Ordinal) {
            return decoded.Substring(0, decoded.Length - 1)
        }
        return decoded
    }
    return source
}

func AccessDiagTempRoot(tag: string): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-access-" + tag + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return root
}

func AccessDiagWrite(root: string, relativePath: string, source: string) {
    path := Path.Combine(root, relativePath)
    directory := Path.GetDirectoryName(path)
    if directory != null {
        Directory.CreateDirectory(directory)
    }
    File.WriteAllText(path, AccessDiagDecodedSource(source))
}

func AccessDiagProject(root: string) {
    AccessDiagWrite(
        root,
        "project.yml",
        """
name: DeclaredAccessibility
version: 1.0.0
outputType: library
targetFramework: net10.0
"""
    )
}

// The fixture root is deleted before the answer is returned rather than in a `finally`: every block
// below asserts on the LIST, so nothing between here and the assertion can throw and leave the
// directory behind.
func AccessDiagErrors(source: string): List<CompilerError> {
    root := AccessDiagTempRoot("diag")
    AccessDiagProject(root)
    AccessDiagWrite(root, "Program.nl", source)
    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    compiler := new MultiFileCompiler(root, config)
    compiler.CompileForAnalysis()
    reported := new List<CompilerError>()
    all := compiler.AllErrors
    index := 0
    while index < all.Count {
        if all[index].Severity == ErrorSeverity.Error {
            reported.Add(all[index])
        }
        index = index + 1
    }

    if Directory.Exists(root) {
        Directory.Delete(root, true)
    }

    return reported
}

func AccessDiagCodes(errors: List<CompilerError>): string {
    codes := new List<string>()
    index := 0
    while index < errors.Count {
        codes.Add(errors[index].DiagnosticId)
        index = index + 1
    }
    return string.Join(",", codes)
}

func AccessDiagSingle(errors: List<CompilerError>, code: string): CompilerError {
    found: CompilerError? = null
    index := 0
    while index < errors.Count {
        if errors[index].DiagnosticId == code {
            if found != null {
                throw new InvalidOperationException("Expected one " + code + ", got: " + AccessDiagCodes(errors))
            }
            found = errors[index]
        }
        index = index + 1
    }

    if found == null {
        throw new InvalidOperationException("Expected one " + code + ", got: " + AccessDiagCodes(errors))
    }

    return found
}

test "reading a protected field from outside every type is NL308 and names the declaring type" {
    errors := AccessDiagErrors(
        """
namespace Demo

class Seeded {
    protected Seed: int = 3
}

func Read(value: Seeded): int {
    return value.Seed
}
"""
    )

    diagnostic := AccessDiagSingle(errors, "NL308")
    assert diagnostic.Code == ErrorCode.InaccessibleMember
    assert diagnostic.Message == "'Seed' is declared 'protected' on 'Seeded', so only 'Seeded' and the types that derive from it can reach it, through a receiver of the deriving type — this reads it from outside every type"
    assert diagnostic.Line == 8
    assert diagnostic.Column == 18
    assert diagnostic.Length == "Seed".Length
}

test "reading a private member from another type is NL308 and says where it could be read" {
    errors := AccessDiagErrors(
        """
namespace Demo

class Vault {
    private Secret: int = 9
}

class Thief {
    func Steal(vault: Vault): int {
        return vault.Secret
    }
}
"""
    )

    diagnostic := AccessDiagSingle(errors, "NL308")
    assert diagnostic.Message == "'Secret' is declared 'private' on 'Vault', so only code inside 'Vault' can reach it — this reads it from 'Thief'"
    assert diagnostic.Suggestion == "Move the access inside 'Vault', expose 'Secret' through a member that is not private, or drop 'private' so the package can read it."
}

test "a protected member is refused through a receiver typed as the BASE, even inside a derived type" {
    // The receiver half of the rule (C# §7.5.4). `Derived` may read `this.Seed` and `other.Seed`
    // where `other: Derived`, but not through a `Base`-typed receiver, because at run time that
    // value could be some OTHER type derived from `Base`.
    errors := AccessDiagErrors(
        """
namespace Demo

class Seeded {
    protected Seed: int = 3
}

class Grower: Seeded {
    func Mine(): int {
        return this.Seed
    }

    func Theirs(other: Seeded): int {
        return other.Seed
    }
}
"""
    )

    diagnostic := AccessDiagSingle(errors, "NL308")
    assert diagnostic.Message == "'Seed' is declared 'protected' on 'Seeded', so only 'Seeded' and the types that derive from it can reach it, through a receiver of the deriving type — this reads it from 'Grower'"
    assert diagnostic.Line == 13
    assert diagnostic.Suggestion == "Write the access inside a type that derives from 'Seeded' and read it through 'this' or a receiver of that derived type, or drop 'protected' from 'Seed'."
}

test "a protected member is refused through a SIBLING derived type's receiver" {
    errors := AccessDiagErrors(
        """
namespace Demo

class Seeded {
    protected Seed: int = 3
}

class Left: Seeded {
    func Peek(right: Right): int {
        return right.Seed
    }
}

class Right: Seeded {
}
"""
    )

    diagnostic := AccessDiagSingle(errors, "NL308")
    assert diagnostic.Message == "'Seed' is declared 'protected' on 'Seeded', so only 'Seeded' and the types that derive from it can reach it, through a receiver of the deriving type — this reads it from 'Left'"
}

test "a protected METHOD call is refused by the same relation as a field read" {
    errors := AccessDiagErrors(
        """
namespace Demo

class Seeded {
    protected func Double(value: int): int {
        return value * 2
    }
}

func Call(value: Seeded): int {
    return value.Double(2)
}
"""
    )

    diagnostic := AccessDiagSingle(errors, "NL308")
    assert diagnostic.Message == "'Double' is declared 'protected' on 'Seeded', so only 'Seeded' and the types that derive from it can reach it, through a receiver of the deriving type — this reads it from outside every type"
}

test "a write to a protected member from outside every type is refused too" {
    errors := AccessDiagErrors(
        """
namespace Demo

class Seeded {
    protected Seed: int = 3
}

func Write(value: Seeded) {
    value.Seed = 4
}
"""
    )

    diagnostic := AccessDiagSingle(errors, "NL308")
    assert diagnostic.Code == ErrorCode.InaccessibleMember
    assert diagnostic.Line == 8
}

test "the relation admits every access the language allows, so these fixtures report nothing" {
    // A derived type through `this`, a bare name, `base`, and a receiver of its own type; a private
    // member inside its own declaring type; `protected internal` and an unmarked member from outside
    // every type. Each of these would be a false refusal, which is the failure mode that would make
    // the rule unusable.
    errors := AccessDiagErrors(
        """
namespace Demo

class Seeded {
    protected Seed: int = 3
    private secret: int = 9
    protected internal Shared: int = 5
    Open: int = 7

    func Reveal(): int {
        return secret
    }

    protected func Double(value: int): int {
        return value * 2
    }
}

class Grower: Seeded {
    func Mine(): int {
        return this.Seed + Seed + base.Seed
    }

    func Sibling(other: Grower): int {
        return other.Seed
    }

    func Doubled(): int {
        return this.Double(2) + Double(3) + base.Double(4)
    }
}

class Deeper: Grower {
    func Reach(): int {
        return this.Seed + base.Seed + Double(1)
    }
}

func Outside(value: Seeded): int {
    return value.Shared + value.Open + value.Reveal()
}
"""
    )

    assert AccessDiagCodes(errors) == ""
}
