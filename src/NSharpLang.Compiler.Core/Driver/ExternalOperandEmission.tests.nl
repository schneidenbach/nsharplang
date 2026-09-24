namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO
import System.Reflection.Metadata
import System.Reflection.PortableExecutable


// A REFERENCED ASSEMBLY'S TYPES TAKE THE SAME OPERATORS AND ARGUMENTS A SOURCE TYPE DOES — over real
// projects.
//
// Carving a slice out of `Compiler.Core` turns thousands of source-type uses into referenced-type uses
// without changing a character of them, and the columnar emitter declined six families of them: `==`
// between two referenced reference values (G1), and a referenced constructor given an enum `==` (G2), an
// object initializer over composite arguments (G3), an enum cast (G4), nested `new`/call/`as` arguments
// (G5) or a narrowed nullable member (G6). A library is emitted here and referenced by a consumer in the
// library's own namespace, and each consumer is compiled by the ANALYSIS path and by the EMIT-ONLY path
// the compiler's own source takes. `tests/native/census-external-operands` runs the same shapes.
func XopRoot(tag: string): string {
    root := Path.Combine(Path.GetTempPath(), "nsharp-external-operands-" + tag + "-" + Guid.NewGuid().ToString("N"))
    Directory.CreateDirectory(root)
    return root
}

func XopWrite(root: string, relativePath: string, source: string) {
    path := Path.Combine(root, relativePath)
    directory := Path.GetDirectoryName(path)
    if directory != null {
        Directory.CreateDirectory(directory)
    }
    File.WriteAllText(path, source)
}

func XopLibrarySource(): string {
    return "namespace Xop\n\nenum Modifier {\n    None,\n    Ref,\n    Out\n}\n\nenum Flags {\n    None = 0,\n    Class = 1,\n    Struct = 2\n}\n\nclass Shape {\n    Name: string\n\n    constructor(name: string) {\n        Name = name\n    }\n}\n\nclass Alias: Shape {\n    constructor(name: string): base(name) {\n    }\n}\n\nclass ByRef: Shape {\n    IsOut: bool\n\n    constructor(inner: Shape, isOut: bool = false): base(inner.Name) {\n        IsOut = isOut\n    }\n}\n\nrecord Report(code: Modifier, message: string, line: int) {\n    FileName: string?\n    Length: int\n}\n\nclass Constraint {\n    Flags: Flags\n\n    constructor(name: string, flags: Flags = 0) {\n        Flags = flags\n    }\n}\n\nclass TypeRef {\n    Name: string\n\n    constructor(name: string, line: int = 0, column: int = 0) {\n        Name = name\n    }\n}\n\nclass Node {\n    Line: int\n\n    constructor(line: int) {\n        Line = line\n    }\n}\n\nclass Block: Node {\n    constructor(line: int): base(line) {\n    }\n}\n\nclass Guard: Node {\n    Body: Block?\n\n    constructor(body: Block?, handlers: System.Collections.Generic.List<string>, line: int): base(line) {\n        Body = body\n    }\n}\n\nclass Holder {\n    Label: string?\n    Owner: Node?\n}\n\nclass Tally {\n    Count: int\n\n    constructor(count: int) {\n        Count = count\n    }\n\n    static func operator ==(left: Tally, right: Tally): bool => left.Count == right.Count\n\n    static func operator !=(left: Tally, right: Tally): bool => left.Count != right.Count\n}\n"
}

func XopEmitLibrary(root: string): string {
    libraryRoot := Path.Combine(root, "library")
    Directory.CreateDirectory(libraryRoot)
    XopWrite(libraryRoot, "project.yml", "name: XopLib\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n")
    XopWrite(libraryRoot, "Lib.nl", XopLibrarySource())
    config := ProjectFileParser.Parse(Path.Combine(libraryRoot, "project.yml"))
    compiler := new MultiFileCompiler(libraryRoot, config)
    compiler.AotMode = false
    outputPath := Path.Combine(libraryRoot, "XopLib.dll")
    result := compiler.CompileToIlAssembly("XopLib", outputPath, false, true)
    assert result.Success, XopText(result)
    return outputPath
}

// A consumer in the library's own namespace — the shape a carved slice leaves behind. It is a SIBLING
// of the library's directory, never its parent: a project compiles every `.nl` file under its root, so
// a consumer above the library would compile the library's source into itself and meet every type as a
// SOURCE type again.
func XopConsumer(tag: string, body: string): string {
    workspace := XopRoot(tag)
    libraryPath := XopEmitLibrary(workspace)
    root := Path.Combine(workspace, "consumer")
    Directory.CreateDirectory(root)
    XopWrite(root, "project.yml", "name: XopConsumer\nversion: 1.0.0\nbackend: il\noutputType: library\ntargetFramework: net10.0\n\ndependencies:\n  - dll: " + libraryPath + "\n")
    imports := body.Contains("List<") ? "import System.Collections.Generic\n\n" : ""
    XopWrite(root, "Consumer.nl", "namespace Xop\n\n" + imports + "class Uses {\n" + body + "}\n")
    return root
}

func XopText(result: MultiFileCompilationResult): string {
    text := ""
    for error in result.Errors {
        text = text + error.DiagnosticId + " " + error.Message + "\n"
    }
    return text
}

func XopCompile(root: string, validateWithLegacyAnalysis: bool): MultiFileCompilationResult {
    config := ProjectFileParser.Parse(Path.Combine(root, "project.yml"))
    compiler := new MultiFileCompiler(root, config)
    compiler.AotMode = false
    folder := validateWithLegacyAnalysis ? "analysed" : "out"
    return compiler.CompileToIlAssembly("XopConsumer", Path.Combine(root, folder, "XopConsumer.dll"), validateWithLegacyAnalysis, validateWithLegacyAnalysis)
}

// Both paths emit the consumer, and neither reports anything.
func XopBothPathsEmit(tag: string, body: string): string {
    root := XopConsumer(tag, body)
    analysed := XopCompile(root, true)
    assert analysed.Success, XopText(analysed)
    assert XopText(analysed) == "", XopText(analysed)
    emitted := XopCompile(root, false)
    assert emitted.Success, XopText(emitted)
    return root
}

// The names of the members the emit-only consumer REFERENCES, read from its metadata tables, so what
// it calls is asserted without loading it.
func XopMemberReferenceNames(root: string): List<string> {
    names := new List<string>()
    stream := File.OpenRead(Path.Combine(root, "out", "XopConsumer.dll"))
    try {
        reader := new PEReader(stream)
        try {
            metadata := reader.GetMetadataReader()
            for handle in metadata.MemberReferences {
                reference := metadata.GetMemberReference(handle)
                names.Add(metadata.GetString(reference.Name))
            }
        } finally {
            reader.Dispose()
        }
    } finally {
        stream.Dispose()
    }
    return names
}

test "G1: == and != between referenced reference types emit as identity on both paths" {
    root := XopBothPathsEmit("identity", "    static func Same(left: Shape, right: Shape): bool {\n        return left == right\n    }\n\n    static func Differs(resolved: Shape, owner: Alias): bool {\n        return resolved != owner\n    }\n\n    static func Objects(left: object, right: object): bool {\n        return left == right\n    }\n\n    static func Guarded(left: Node, right: Node): int {\n        if left == right {\n            return 1\n        }\n        return 0\n    }\n")
    // Identity is `ceq`, not a call: nothing named like an operator is referenced.
    names := XopMemberReferenceNames(root)
    assert !names.Contains("op_Equality"), string.Join(",", names)
    assert !names.Contains("op_Inequality"), string.Join(",", names)
}

test "G1: a referenced type's declared == is still called rather than replaced by identity" {
    root := XopBothPathsEmit("declared-operator", "    static func Match(left: Tally, right: Tally): bool {\n        return left == right\n    }\n\n    static func Mismatch(left: Tally, right: Tally): bool {\n        return left != right\n    }\n")
    names := XopMemberReferenceNames(root)
    assert names.Contains("op_Equality"), string.Join(",", names)
    assert names.Contains("op_Inequality"), string.Join(",", names)
}

test "G2: an enum == is a referenced constructor's argument on both paths" {
    _ = XopBothPathsEmit("enum-equality-argument", "    static func Make(inner: Shape, modifier: Modifier): ByRef {\n        return new ByRef(inner, modifier == Modifier.Out)\n    }\n")
}

test "G3: a referenced record takes an object initializer over composite arguments on both paths" {
    _ = XopBothPathsEmit("record-initializer", "    static func Make(name: string, detail: string?, line: int): Report {\n        return new Report(Modifier.Ref, Detail(\"required '\" + name + \"'\", detail), line) {\n            FileName: name + \".nl\",\n            Length: name.Length\n        }\n    }\n\n    static func Detail(message: string, detail: string?): string {\n        return detail == null ? message : message + \" \" + detail\n    }\n")
}

test "G4: an enum cast is a referenced constructor's argument on both paths" {
    _ = XopBothPathsEmit("enum-cast-argument", "    static func Make(bits: int): Constraint {\n        return new Constraint(\"T\", (Flags)bits)\n    }\n\n    static func Defaulted(): Constraint {\n        return new Constraint(\"U\")\n    }\n")
}

test "G5: nested new, call, as and concatenation arguments reach a referenced constructor on both paths" {
    _ = XopBothPathsEmit("composite-arguments", "    static func Depth(index: int, line: int): TypeRef {\n        return new TypeRef(\"Depth\" + (index - 1).ToString(), line, 5)\n    }\n\n    static func Nested(line: int): Guard {\n        return new Guard(Body(line) as Block, new List<string>(), line + 1)\n    }\n\n    static func Body(line: int): Node {\n        return new Block(line)\n    }\n")
}

test "G6: a narrowed nullable referenced member is an argument on both paths" {
    _ = XopBothPathsEmit("narrowed-member", "    static func LabelLength(holder: Holder): int {\n        label := holder.Label\n        if label == null {\n            return -1\n        }\n        return Measure(label)\n    }\n\n    static func Measure(text: string): int {\n        return text.Length\n    }\n\n    static func OwnerLine(holder: Holder): int {\n        owner := holder.Owner\n        if owner == null {\n            return 0\n        }\n        return Line(owner)\n    }\n\n    static func Line(node: Node): int {\n        return node.Line\n    }\n")
}
