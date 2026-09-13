namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic
import System.Reflection
import NSharpLang.Compiler


// THE EMITTER'S IDENTITY FOR A FREE FUNCTION IS (NAMESPACE, NAME) (census 2026-09-13, §EMIT3).
//
// These build a REAL multi-file columnar program, emit it, and then ask the emitted metadata and the
// executed IL what the calls actually reached — because the bug this rule closes produced clean
// `check` and `build` output and the wrong answer at runtime.
func FreeFunctionScopeProgram(namespaces: string[], sources: string[]): ColumnarProgramInput {
    texts := new List<string>()
    names := new List<string>()
    index := 0
    while index < sources.Length {
        prefix := ""
        if namespaces[index].Length > 0 {
            prefix = "namespace " + namespaces[index] + "\n\n"
        }
        texts.Add(prefix + sources[index])
        names.Add("/tmp/FreeFunctionScopeProbe" + index.ToString() + ".nl")
        index = index + 1
    }
    program: ColumnarProgramInput = null
    assert ColumnarProgramInputBuilder.TryBuildMultiFile(texts, names, "/tmp", out program)
    return program
}

func FreeFunctionScopeAssembly(namespaces: string[], sources: string[]): Assembly {
    program := FreeFunctionScopeProgram(namespaces, sources)
    bytes: byte[] = null
    assert ColumnarIlEmitter.TryEmitColumnarAssembly("FreeFunctionScope" + Guid.NewGuid().ToString("N"), "Program", program, false, out bytes, null, null)
    return Assembly.Load(bytes)
}

func FreeFunctionScopeCall(assembly: Assembly, holderName: string, methodName: string): string {
    holder := assembly.GetType(holderName)
    assert holder != null
    method := holder.GetMethod(methodName, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static)
    assert method != null
    value := method.Invoke(null, null)
    if value == null {
        return "<null>"
    }
    return value.ToString() ?? "<null>"
}

func FreeFunctionScopeMethodCount(assembly: Assembly, holderName: string, methodName: string): int {
    holder := assembly.GetType(holderName)
    if holder == null {
        return -1
    }
    matched := 0
    for candidate in holder.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.DeclaredOnly) {
        if candidate.Name == methodName {
            matched = matched + 1
        }
    }
    return matched
}

test "a namespace's holder type name is its namespace plus Program, and the global one is bare" {
    assert ColumnarFreeFunctionScope.HolderTypeName("X", "Program") == "X.Program"
    assert ColumnarFreeFunctionScope.HolderTypeName("A.B.C", "Program") == "A.B.C.Program"
    assert ColumnarFreeFunctionScope.HolderTypeName("", "Program") == "Program"
    assert ColumnarFreeFunctionScope.HolderTypeName(null, "Program") == "Program"
}

test "two namespaces that declare the same function name each emit their own holder and method" {
    assembly := FreeFunctionScopeAssembly(
        ["X", "Y"],
        [
            "func Helper(): string {\n    return \"X\"\n}\n\nfunc Use(): string {\n    return Helper()\n}\n",
            "func Helper(): string {\n    return \"Y\"\n}\n\nfunc Use(): string {\n    return Helper()\n}\n"
        ]
    )

    // The bare-name map used to leave BOTH `Use` bodies calling the first `Helper`.
    assert FreeFunctionScopeCall(assembly, "X.Program", "Use") == "X"
    assert FreeFunctionScopeCall(assembly, "Y.Program", "Use") == "Y"

    // And one holder per namespace, each declaring the name once.
    assert FreeFunctionScopeMethodCount(assembly, "X.Program", "Helper") == 1
    assert FreeFunctionScopeMethodCount(assembly, "Y.Program", "Helper") == 1

    // No global holder: nothing was declared in the global namespace, so none was created.
    assert assembly.GetType("Program") == null
}

test "a bare call climbs to the enclosing namespace and stops at the nearest declaration" {
    assembly := FreeFunctionScopeAssembly(
        ["A", "A.Inner", "A.Own"],
        [
            "func Helper(): string {\n    return \"A\"\n}\n",
            "func Use(): string {\n    return Helper()\n}\n",
            "func Helper(): string {\n    return \"A.Own\"\n}\n\nfunc Use(): string {\n    return Helper()\n}\n"
        ]
    )

    assert FreeFunctionScopeCall(assembly, "A.Inner.Program", "Use") == "A"
    assert FreeFunctionScopeCall(assembly, "A.Own.Program", "Use") == "A.Own"
}

test "an import reaches an exported function in a sibling namespace" {
    assembly := FreeFunctionScopeAssembly(
        ["Left", "Right"],
        [
            "func Render(): string {\n    return \"left\"\n}\n",
            "import Left\n\nfunc Use(): string {\n    return Render()\n}\n"
        ]
    )

    assert FreeFunctionScopeCall(assembly, "Right.Program", "Use") == "left"
}

test "a file-private camelCase function is reached by its own file and shadows nothing elsewhere" {
    assembly := FreeFunctionScopeAssembly(
        ["X", "Y"],
        [
            "func helper(): string {\n    return \"x\"\n}\n\nfunc Use(): string {\n    return helper()\n}\n",
            "func helper(): string {\n    return \"y\"\n}\n\nfunc Use(): string {\n    return helper()\n}\n"
        ]
    )

    assert FreeFunctionScopeCall(assembly, "X.Program", "Use") == "x"
    assert FreeFunctionScopeCall(assembly, "Y.Program", "Use") == "y"
}

test "a global-namespace program still emits exactly one bare Program holder" {
    assembly := FreeFunctionScopeAssembly(
        ["", ""],
        [
            "func Helper(): string {\n    return \"root\"\n}\n",
            "func Use(): string {\n    return Helper()\n}\n"
        ]
    )

    assert FreeFunctionScopeCall(assembly, "Program", "Use") == "root"
    assert FreeFunctionScopeMethodCount(assembly, "Program", "Helper") == 1
}

test "a `public` word exports a camelCase function, and it outranks a nearer non-exported one" {
    // `Mine` declares a camelCase `render` in a file the caller is not in — file-private, so the
    // analyzer does not let the caller see it — while the import supplies one whose `public` word
    // exports it despite the same casing. The emitter has to reach the SAME declaration the analyzer
    // resolved, which is the exported one, even though it sits in a farther namespace.
    assembly := FreeFunctionScopeAssembly(
        ["Mine", "Far", "Mine"],
        [
            "func render(): string {\n    return \"near-private\"\n}\n",
            "public func render(): string {\n    return \"far\"\n}\n",
            "import Far\n\nfunc Use(): string {\n    return render()\n}\n"
        ]
    )

    assert FreeFunctionScopeCall(assembly, "Mine.Program", "Use") == "far"
}

test "an `internal` word un-exports a PascalCase function, so another namespace never reaches it" {
    // The mirror of the rule above, and the reason the visibility word is read at all: casing alone
    // would have made this one a candidate everywhere.
    program := FreeFunctionScopeProgram(
        ["Far"],
        ["internal func Render(): string {\n    return \"far\"\n}\n"]
    )

    assert program.Functions[0].VisibilityModifierFlags == 4
    assert !VisibilityConventions.IsExportedIdentifierWithFlags("Render", program.Functions[0].VisibilityModifierFlags)
    assert VisibilityConventions.IsExportedIdentifierWithFlags("Render", 0)
    assert VisibilityConventions.IsExportedIdentifierWithFlags("render", 1)
    assert !VisibilityConventions.IsExportedIdentifierWithFlags("render", 0)
}
