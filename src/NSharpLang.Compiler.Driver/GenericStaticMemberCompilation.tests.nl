namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO

// WHOLE-COMPILER CONTRACTS FOR STATIC MEMBERS ON A USER-DECLARED GENERIC TYPE.
//
// The unit contracts beside this file each state one owner's answer — what the parser builds, what
// the operator resolver selects, what the receiver facts report. Those cannot state the two things a
// user actually experiences, because both are properties of the WHOLE run: that a declaration which
// used to be refused outright now analyses and EMITS with no diagnostic at all, and that the shapes
// which are genuinely wrong still get the ordinary member/argument/arity diagnostic naming the
// CONSTRUCTED type rather than a generic-specific refusal.
//
// `tests/native/generic-static-members` runs the emitted IL and reads values back. This file is the
// half that native project cannot be: a native test only exists if its project compiles, so the
// negative shapes — and the exact text a user sees for them — can only be pinned here.
func GsmDecodedSource(source: string): string {
    if source.StartsWith("\n", StringComparison.Ordinal) {
        decoded := source.Substring(1)
        if decoded.EndsWith("\n", StringComparison.Ordinal) {
            return decoded.Substring(0, decoded.Length - 1)
        }
        return decoded
    }
    return source
}

func GsmTempRoot(tag: string): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-generic-static-" + tag + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return root
}

func GsmWrite(root: string, relativePath: string, source: string) {
    path := Path.Combine(root, relativePath)
    directory := Path.GetDirectoryName(path)
    if directory != null {
        Directory.CreateDirectory(directory)
    }
    File.WriteAllText(path, GsmDecodedSource(source))
}

// Every fixture below is a library: these contracts are about a type's own members, and an entry
// point would only add a second reason for the run to fail.
func GsmProject(root: string) {
    GsmWrite(
        root,
        "project.yml",
        """
name: GenericStaticMembers
version: 1.0.0
outputType: library
targetFramework: net10.0
"""
    )
}

func GsmErrors(root: string): List<CompilerError> {
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
    return reported
}

// Analysis alone would accept a shape the backend then declines, so the positive contracts run the
// IL emission too: "this compiles" means an assembly exists.
func GsmAssertEmits(root: string) {
    result := GsmCompile(root)
    assert result.Success, "the fixture must reach an emitted assembly"
    assert File.Exists(Path.Combine(root, "verification", "GenericStaticMembers.dll")), "the emitted assembly must be written"
}

func GsmCompile(root: string): MultiFileCompilationResult {
    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    compiler := new MultiFileCompiler(root, config)
    compiler.AotMode = false
    return compiler.CompileToIlAssembly("GenericStaticMembers", Path.Combine(root, "verification", "GenericStaticMembers.dll"), false, true)
}

// A backend refusal is not an analysis diagnostic, so a shape the analyzer admits and the backend
// declines only has an answer after a whole compile.
func GsmCompileErrors(root: string): List<CompilerError> {
    reported := new List<CompilerError>()
    for error in GsmCompile(root).Errors {
        if error.Severity == ErrorSeverity.Error {
            reported.Add(error)
        }
    }
    return reported
}

func GsmCodes(errors: List<CompilerError>): string {
    codes := new List<string>()
    index := 0
    while index < errors.Count {
        codes.Add(errors[index].DiagnosticId)
        index = index + 1
    }
    return string.Join(",", codes)
}

func GsmOnlyMessage(errors: List<CompilerError>): string {
    if errors.Count != 1 {
        throw new InvalidOperationException("Expected exactly one error, found " + errors.Count.ToString() + ": " + GsmCodes(errors))
    }
    return errors[0].Message
}

test "every static member kind on a generic type analyses and emits with no diagnostic" {
    root := GsmTempRoot("accepted")
    try {
        GsmProject(root)
        GsmWrite(
            root,
            "Members.nl",
            """
class PerTypeState<T> {
    static Count: int

    static Current: int => Count

    static func Increment(): int {
        Count = Count + 1
        return Count
    }
}

class Seeded<T> {
    static readonly Origin: int = 7
    static Slot: int = 3

    static Total: int => Origin + Slot
}

class Counter<T> {
    static count: int

    static Value: int {
        get {
            return count
        }
        set {
            count = value
        }
    }
}

struct Box<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    static func Create(value: T): Box<T> {
        return new Box<T>(value)
    }

    static func unwrap(source: Box<T>): T {
        return source.Value
    }

    static func Read(source: Box<T>): T {
        return unwrap(source)
    }

    func Copy(): Box<T> {
        return new Box<T>(unwrap(new Box<T>(Value)))
    }
}

struct Tagged<T> {
    Tag: int

    constructor(tag: int) {
        Tag = tag
    }

    static func operator ==(left: Tagged<T>, right: Tagged<T>): bool {
        return left.Tag == right.Tag
    }

    static func operator !=(left: Tagged<T>, right: Tagged<T>): bool {
        return left.Tag != right.Tag
    }

    static func operator <(left: Tagged<T>, right: Tagged<T>): bool {
        return left.Tag < right.Tag
    }

    static func operator >(left: Tagged<T>, right: Tagged<T>): bool {
        return left.Tag > right.Tag
    }

    static func operator -(value: Tagged<T>): Tagged<T> {
        return new Tagged<T>(0 - value.Tag)
    }

    static func operator +(left: Tagged<T>, right: Tagged<T>): Tagged<T> {
        return new Tagged<T>(left.Tag + right.Tag)
    }
}

func UseAll(): int {
    PerTypeState<int>.Count = 0
    PerTypeState<string>.Count = 0
    Counter<int>.Value = Seeded<int>.Total
    boxed := Box<int>.Create(PerTypeState<int>.Increment())
    same := new Tagged<int>(1) == new Tagged<int>(1)
    ordered := new Tagged<int>(1) < new Tagged<int>(2) && new Tagged<int>(2) > new Tagged<int>(1)
    summed := new Tagged<int>(4) + -new Tagged<int>(1)
    return same && ordered ? Box<int>.Read(boxed.Copy()) + Counter<int>.Value + summed.Tag : 0
}
"""
        )

        errors := GsmErrors(root)

        assert errors.Count == 0, "static members on a generic type must analyse silently, got: " + GsmCodes(errors)
        GsmAssertEmits(root)
    } finally {
        if Directory.Exists(root) {
            Directory.Delete(root, true)
        }
    }
}

// A conversion operator is a static member under a reserved name, and it is the one static member
// that can ONLY be declared on the generic end: `implicit operator Wrap<T>(value: T)` converts FROM
// whatever the instantiation supplies, and `int` declares nothing about `Wrap`. So the conversion
// search asks both ends of a conversion, not only the source.
test "a conversion operator declared by a constructed generic converts into and out of it" {
    root := GsmTempRoot("conversions")
    try {
        GsmProject(root)
        GsmWrite(
            root,
            "Conversions.nl",
            """
struct Wrap<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    implicit operator Wrap<T>(value: T) => new Wrap<T>(value)

    explicit operator T(wrapped: Wrap<T>) => wrapped.Value
}

func Take(wrapped: Wrap<int>): int {
    return wrapped.Value
}

func Use(): int {
    assigned: Wrap<int> = 5
    text: Wrap<string> = "hello"
    unwrapped := (int)assigned
    return Take(unwrapped) + text.Value.Length
}
"""
        )

        errors := GsmErrors(root)

        assert errors.Count == 0, "conversion operators on a generic type must analyse silently, got: " + GsmCodes(errors)
        GsmAssertEmits(root)
    } finally {
        if Directory.Exists(root) {
            Directory.Delete(root, true)
        }
    }
}

// THE NEGATIVE HALF. Removing a refusal is only correct if the shapes that were ALWAYS wrong keep
// their ordinary diagnostic — and if that diagnostic names the CONSTRUCTED type, which is what the
// user wrote and the only name under which the member either exists or does not.
test "an unknown static member on a constructed generic reports the ordinary member diagnostic" {
    root := GsmTempRoot("unknown-member")
    try {
        GsmProject(root)
        GsmWrite(
            root,
            "Unknown.nl",
            """
struct Box<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    static func Create(value: T): Box<T> {
        return new Box<T>(value)
    }
}

func Use(): Box<int> {
    return Box<int>.Missing(42)
}
"""
        )

        errors := GsmErrors(root)

        assert GsmCodes(errors) == "NL303"
        assert GsmOnlyMessage(errors) == "Member 'Missing' not found on type 'Box<int>'"
    } finally {
        if Directory.Exists(root) {
            Directory.Delete(root, true)
        }
    }
}

test "a wrong argument type through a constructed generic names the substituted parameter type" {
    root := GsmTempRoot("wrong-argument")
    try {
        GsmProject(root)
        GsmWrite(
            root,
            "WrongArgument.nl",
            """
struct Box<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    static func Create(value: T): Box<T> {
        return new Box<T>(value)
    }
}

func Use(): Box<int> {
    return Box<int>.Create("text")
}
"""
        )

        errors := GsmErrors(root)

        assert GsmCodes(errors) == "NL202"

        // `int`, not `T`: the receiver's type arguments are carried through overload resolution, so
        // the message states the parameter type the user's own instantiation produced.
        assert GsmOnlyMessage(errors) == "Cannot pass `string` as argument for parameter `value` of type `int`"
    } finally {
        if Directory.Exists(root) {
            Directory.Delete(root, true)
        }
    }
}

test "a wrong arity through a constructed generic reports the ordinary arity diagnostic" {
    root := GsmTempRoot("wrong-arity")
    try {
        GsmProject(root)
        GsmWrite(
            root,
            "WrongArity.nl",
            """
struct Box<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }

    static func Create(value: T): Box<T> {
        return new Box<T>(value)
    }
}

func Use(): Box<int> {
    return Box<int>.Create(1, 2)
}
"""
        )

        errors := GsmErrors(root)

        assert GsmCodes(errors) == "NL401"
        assert GsmOnlyMessage(errors) == "Function 'Create' expects 1 argument but got 2"
    } finally {
        if Directory.Exists(root) {
            Directory.Delete(root, true)
        }
    }
}

// An INSTANCE member reached through the type name is refused, and refused the SAME WAY a
// non-generic type refuses it. The shared answer is the contract: the refusal belongs to
// "instance member, no instance", not to "generic type", so the generic case must not acquire a
// diagnostic of its own.
test "an instance member reached through a constructed generic is refused exactly as through a plain type" {
    genericRoot := GsmTempRoot("instance-through-generic")
    plainRoot := GsmTempRoot("instance-through-plain")
    try {
        GsmProject(genericRoot)
        GsmWrite(
            genericRoot,
            "Instance.nl",
            """
struct Box<T> {
    Value: T

    constructor(value: T) {
        Value = value
    }
}

func Use(): int {
    return Box<int>.Value
}
"""
        )
        GsmProject(plainRoot)
        GsmWrite(
            plainRoot,
            "Instance.nl",
            """
struct Plain {
    Value: int

    constructor(value: int) {
        Value = value
    }
}

func Use(): int {
    return Plain.Value
}
"""
        )

        // Both are silent to ANALYSIS: the refusal is the backend's, and it is the same backend
        // refusal for both, which is the point — the generic case acquires no diagnostic of its own.
        assert GsmCodes(GsmErrors(genericRoot)) == ""
        assert GsmCodes(GsmErrors(plainRoot)) == ""

        genericErrors := GsmCompileErrors(genericRoot)
        plainErrors := GsmCompileErrors(plainRoot)

        assert GsmCodes(genericErrors) == GsmCodes(plainErrors)
        assert GsmCodes(genericErrors) == "NL103"
    } finally {
        if Directory.Exists(genericRoot) {
            Directory.Delete(genericRoot, true)
        }
        if Directory.Exists(plainRoot) {
            Directory.Delete(plainRoot, true)
        }
    }
}
