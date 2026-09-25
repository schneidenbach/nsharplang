namespace NSharpLang.LanguageServerHandlers.Tests

import System

test "hover on a keyword explains it as a keyword" {
    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test.nl"
    LshOpen(docs, uri, "func main(): void")

    hover := LshHover(docs, types, uri, 0, 2)

    assert hover != null
    assert hover.Range != null
    content := LshHoverMarkdown(hover)
    assert content.Contains("func", StringComparison.Ordinal)
    assert content.Contains("keyword", StringComparison.Ordinal)
}

test "hover on a primitive type names it as a primitive type" {
    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test.nl"
    LshOpen(docs, uri, "func test(): int")

    hover := LshHover(docs, types, uri, 0, 14)

    assert hover != null
    assert hover.Range != null
    content := LshHoverMarkdown(hover)
    assert content.Contains("int", StringComparison.Ordinal)
    assert content.Contains("primitive type", StringComparison.Ordinal)
}

test "hover on a local variable names the variable" {
    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test.nl"
    source := """
func main(): void
    let count = 42
    print(count)"""
    LshOpen(docs, uri, source)

    hover := LshHover(docs, types, uri, 3, 11)

    assert hover != null
    content := LshHoverMarkdown(hover)
    assert content.Contains("count", StringComparison.Ordinal)
}

test "hover on a function declaration names the function" {
    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test.nl"
    source := """
func greet(name: string): string
    return "Hello, " + name"""
    LshOpen(docs, uri, source)

    hover := LshHover(docs, types, uri, 1, 6)

    assert hover != null
    content := LshHoverMarkdown(hover)
    assert content.Contains("greet", StringComparison.Ordinal)
}

test "hover on a variable holding a system-typed value names the variable" {
    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test.nl"
    source := """
func main(): void
    let numbers = [1, 2, 3]
    print(numbers)"""
    LshOpen(docs, uri, source)

    hover := LshHover(docs, types, uri, 3, 12)

    assert hover != null
    content := LshHoverMarkdown(hover)
    assert content.Contains("numbers", StringComparison.Ordinal)
}

test "hover beyond the end of the document answers nothing" {
    docs := LshNewDocs()
    types := LshNewTypes()
    uri := "file:///test.nl"
    LshOpen(docs, uri, "func main(): void")

    hover := LshHover(docs, types, uri, 10, 50)

    assert hover == null
}

test "signature help at an open call paren describes the N# function being called" {
    docs := LshNewDocs()
    uri := "file:///test.nl"
    source := """
func greet(name: string, times: int): void
    for i in 0..times
        Console.WriteLine(name)

func main(): void
    greet(
"""
    LshOpen(docs, uri, source)

    help := LshSignatureHelp(docs, uri, 6, 10)

    assert help != null
    assert LshSignatureCount(help) > 0
    assert LshHasSignatureContaining(help, "greet")
    signature := LshSignatureContaining(help, "greet")
    assert signature.Label.Contains("name: string", StringComparison.Ordinal)
    assert signature.Label.Contains("times: int", StringComparison.Ordinal)
    assert signature.Label.Contains(": void", StringComparison.Ordinal)
    assert LshParameterCount(signature) == 2
}

test "signature help carries the leading comment block of the called function" {
    docs := LshNewDocs()
    uri := "file:///test/docs-signature.nl"
    source := LshBody(
        """
// Greets someone by name.
// Returns the composed greeting.
func greet(name: string): string
    return name

func main(): void
    greet(
"""
    )
    LshOpen(docs, uri, source)

    help := LshSignatureHelp(docs, uri, 6, 10)

    assert help != null
    assert LshSignatureCount(help) == 1
    signature := LshSignatureAt(help, 0)
    documentation := LshDocumentationText(signature.Documentation)
    assert documentation != null
    assert documentation.Contains("Greets someone by name.", StringComparison.Ordinal)
    assert documentation.Contains("Returns the composed greeting.", StringComparison.Ordinal)
}

test "signature help reports the active parameter after a comma" {
    docs := LshNewDocs()
    uri := "file:///test.nl"
    // Written with escapes so the trailing space after the comma survives formatting.
    source := "\nfunc add(a: int, b: int): int\n    return a + b\n\nfunc main(): void\n    add(1, "
    LshOpen(docs, uri, source)

    help := LshSignatureHelp(docs, uri, 5, 11)

    assert help != null
    assert LshSignatureCount(help) > 0
    assert help.ActiveParameter == 1
}

test "signature help follows a reordered named argument" {
    docs := LshNewDocs()
    uri := "file:///named-signature.nl"
    source := "\nfunc add(a: int, b: int): int\n    return a + b\n\nfunc main(): void\n    add(b: 1, a: "
    LshOpen(docs, uri, source)

    help := LshSignatureHelp(docs, uri, 5, 17)

    assert help != null
    assert LshSignatureCount(help) > 0
    assert help.ActiveParameter == 0
}

test "signature help resolves a named argument on a generic receiver and method" {
    docs := LshNewDocs()
    uri := "file:///generic-receiver-signature.nl"
    source := "namespace Catalog\n\nclass Box<T> {\n    static func Method<U>(first: U, second: int): U { return first }\n}\n\nclass WrongBox {\n    func Other(first: int, second: int): int { return first }\n}\n\nfunc main(): void\n    Box := new WrongBox()\n    Catalog.Box<int>.Method<int>(second: 2, first: "
    LshOpen(docs, uri, source)

    help := LshSignatureHelp(docs, uri, 12, 56)

    assert help != null
    assert LshSignatureCount(help) > 0
    assert help.ActiveParameter == 0
    assert LshHasSignatureContaining(help, "Method")
}

test "signature help keeps the outer call across nested and multiline arguments" {
    docs := LshNewDocs()
    uri := "file:///nested-named-signature.nl"
    source := "\nfunc build(a: int, b: int): int\n    return a + b\n\nfunc outer(first: int, second: int): int\n    return first + second\n\nfunc main(): void\n    outer(\n        second: build(1, 2),\n        first: 0)"
    LshOpen(docs, uri, source)

    help := LshSignatureHelp(docs, uri, 10, 15)

    assert help != null
    assert LshSignatureCount(help) > 0
    assert help.ActiveParameter == 0
}

test "signature help follows a reordered name on an explicit generic call" {
    docs := LshNewDocs()
    uri := "file:///generic-named-signature.nl"
    source := "\nfunc choose<T>(first: T, second: T): T\n    return first\n\nfunc main(): void\n    choose<int>(second: 2, first: 0)"
    LshOpen(docs, uri, source)

    help := LshSignatureHelp(docs, uri, 5, 34)

    assert help != null
    assert LshSignatureCount(help) > 0
    assert help.ActiveParameter == 0
}

test "signature help spells the return type in the signature label" {
    docs := LshNewDocs()
    uri := "file:///test.nl"
    source := """
func multiply(x: double, y: double): double
    return x * y

func main(): void
    multiply(
"""
    LshOpen(docs, uri, source)

    help := LshSignatureHelp(docs, uri, 5, 13)

    assert help != null
    assert LshSignatureCount(help) > 0
    signature := LshSignatureAt(help, 0)
    assert signature.Label.Contains("multiply(x: double, y: double): double", StringComparison.Ordinal)
}

test "signature help for a parameterless function reports no parameters" {
    docs := LshNewDocs()
    uri := "file:///test.nl"
    source := """
func getTime(): string
    return "now"

func main(): void
    getTime(
"""
    LshOpen(docs, uri, source)

    help := LshSignatureHelp(docs, uri, 5, 12)

    assert help != null
    assert LshSignatureCount(help) > 0
    signature := LshSignatureAt(help, 0)
    assert signature.Label == "getTime(): string"
    assert LshParameterCount(signature) == 0
}

test "signature help counts a defaulted parameter as a parameter" {
    docs := LshNewDocs()
    uri := "file:///test.nl"
    source := """
func greet(name: string, greeting: string = "Hello"): void
    Console.WriteLine(greeting + " " + name)

func main(): void
    greet(
"""
    LshOpen(docs, uri, source)

    help := LshSignatureHelp(docs, uri, 5, 10)

    assert help != null
    assert LshSignatureCount(help) > 0
    signature := LshSignatureAt(help, 0)
    assert LshParameterCount(signature) == 2
    assert signature.Label.Contains("name: string", StringComparison.Ordinal)
    assert signature.Label.Contains("greeting: string", StringComparison.Ordinal)
}

// ---------------------------------------------------------------------------
// Signature help beyond the current document.
//
// Signature help used to read only the open buffer's own declaration table, so a
// BCL method, an overload set and a type declared in the file next door all
// answered null. It now resolves through the same project snapshot completion
// uses, and these are the shapes that regression covers.
// ---------------------------------------------------------------------------

test "signature help resolves an external instance method on a typed local" {
    docs := LshNewDocs()
    uri := "file:///external-instance.nl"
    source := "\nfunc main(): void\n    greeting := \"hello\"\n    greeting.CompareTo("
    LshOpen(docs, uri, source)

    help := LshSignatureHelp(docs, uri, 3, 23)

    assert help != null
    assert LshSignatureCount(help) > 0
    assert LshHasSignatureContaining(help, "CompareTo(")
    signature := LshSignatureContaining(help, "CompareTo(")
    assert LshParameterCount(signature) >= 1
}

test "signature help shows every overload of an external instance method" {
    docs := LshNewDocs()
    uri := "file:///external-overloads.nl"
    source := "\nfunc main(): void\n    greeting := \"hello\"\n    greeting.IndexOf("
    LshOpen(docs, uri, source)

    help := LshSignatureHelp(docs, uri, 3, 21)

    assert help != null
    // `string.IndexOf` is an overload set, and the old current-document path could
    // only ever answer one signature for a name.
    assert LshSignatureCount(help) > 1
}

test "signature help resolves an external static method" {
    docs := LshNewDocs()
    uri := "file:///external-static.nl"
    source := "\nfunc main(): void\n    Console.WriteLine("
    LshOpen(docs, uri, source)

    help := LshSignatureHelp(docs, uri, 2, 22)

    assert help != null
    assert LshSignatureCount(help) > 0
    assert LshHasSignatureContaining(help, "WriteLine(")
}

test "signature help follows the active parameter into an external overload" {
    docs := LshNewDocs()
    uri := "file:///external-active-parameter.nl"
    source := "\nfunc main(): void\n    Math.Max(1, "
    LshOpen(docs, uri, source)

    help := LshSignatureHelp(docs, uri, 2, 16)

    assert help != null
    assert LshSignatureCount(help) > 0
    assert help.ActiveParameter == 1
}

test "signature help names the active parameter of an external overload by its own name" {
    docs := LshNewDocs()
    uri := "file:///external-parameter-rows.nl"
    source := "\nfunc main(): void\n    Math.Max(1, "
    LshOpen(docs, uri, source)

    help := LshSignatureHelp(docs, uri, 2, 16)

    assert help != null
    signature := LshSignatureAt(help, help.ActiveSignature ?? 0)
    assert LshParameterCount(signature) == 2
    // Reflected rows carry the declared parameter NAME, not a positional placeholder.
    assert signature.Label.Contains("val1", StringComparison.Ordinal)
    assert signature.Label.Contains("val2", StringComparison.Ordinal)
}

test "signature help resolves a method on a type declared in another file" {
    docs := LshNewDocs()
    root := LshTempRoot("nsharp-lsp-signature-cross-file-")
    try {
        LshWrite(root, "Greeter.nl", LshRaw(
            """
namespace CrossFileSignature

class Greeter {
    func Greet(name: string, times: int): string {
        return name
    }
}
"""
        ))
        usePath := LshWrite(root, "UseGreeter.nl", LshRaw(
            """
namespace CrossFileSignature

func main(): void
    greeter := new Greeter()
    greeter.Greet(
"""
        ))

        docs.ScanWorkspaceDirectory(root)
        useUri := LshFileUri(usePath)

        help := LshSignatureHelp(docs, useUri, 4, 18)

        assert help != null
        assert LshSignatureCount(help) > 0
        signature := LshSignatureContaining(help, "Greet(")
        assert signature.Label.Contains("name: string", StringComparison.Ordinal)
        assert signature.Label.Contains("times: int", StringComparison.Ordinal)
        assert signature.Label.Contains(": string", StringComparison.Ordinal)
        assert LshParameterCount(signature) == 2
    } finally {
        LshDeleteTree(root)
    }
}

test "signature help resolves a constructor of a type declared in another file" {
    docs := LshNewDocs()
    root := LshTempRoot("nsharp-lsp-signature-cross-file-ctor-")
    try {
        LshWrite(root, "Person.nl", LshRaw(
            """
namespace CrossFileConstructor

class Person {
    Name: string

    constructor(name: string, age: int) {
        Name = name
    }
}
"""
        ))
        usePath := LshWrite(root, "UsePerson.nl", LshRaw(
            """
namespace CrossFileConstructor

func main(): void
    person := new Person(
"""
        ))

        docs.ScanWorkspaceDirectory(root)
        useUri := LshFileUri(usePath)

        help := LshSignatureHelp(docs, useUri, 3, 25)

        assert help != null
        assert LshSignatureCount(help) > 0
        signature := LshSignatureContaining(help, "Person(")
        assert signature.Label.Contains("name: string", StringComparison.Ordinal)
        assert signature.Label.Contains("age: int", StringComparison.Ordinal)
        assert LshParameterCount(signature) == 2
    } finally {
        LshDeleteTree(root)
    }
}
