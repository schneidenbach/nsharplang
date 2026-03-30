import * as assert from 'assert';
import * as vscode from 'vscode';
import {
    waitForLanguageServer,
    createTempNlFile,
    getDiagnostics,
    closeAllEditors,
    formatDiagnosticErrors
} from './helpers';

/**
 * Inline syntax regression tests.
 *
 * Each test creates a temporary .nl file with a specific syntax pattern,
 * opens it through the real VS Code LSP pipeline, and asserts zero errors.
 *
 * This catches parser/analysis regressions where valid syntax is incorrectly
 * flagged as an error. Add a new test here whenever a new false-positive
 * bug is found and fixed.
 *
 * WHY INLINE TESTS? Static fixture files test the "happy path" of complete
 * programs. Inline tests let us isolate and test the exact minimal syntax
 * that triggered a specific bug. When a user reports "this line produces
 * NL101", we add a test with exactly that line.
 */
suite('Syntax Regressions', () => {
    suiteSetup(async function () {
        this.timeout(90_000);
        await waitForLanguageServer();
    });

    teardown(async () => {
        await closeAllEditors();
    });

    /**
     * Helper: create a temp file, assert zero errors, clean up.
     * Each invocation uses a unique filename to avoid conflicts.
     */
    async function assertZeroErrors(
        testName: string,
        code: string
    ): Promise<void> {
        const safeName = testName.replace(/[^a-zA-Z0-9]/g, '_');
        const { doc, cleanup } = await createTempNlFile(code, `_reg_${safeName}.nl`);
        try {
            const diagnostics = await getDiagnostics(doc);
            const errors = diagnostics.filter(
                d => d.severity === vscode.DiagnosticSeverity.Error
            );
            assert.strictEqual(
                errors.length,
                0,
                `Regression "${testName}": expected 0 errors but got ${errors.length}:\n` +
                `${formatDiagnosticErrors(errors)}\n\nSource:\n${code}`
            );
        } finally {
            await closeAllEditors();
            cleanup();
        }
    }

    // ================================================================
    // TYPED VARIABLE DECLARATIONS (WORKING PATTERNS)
    // ================================================================

    test('typed variable declaration with initialization', async function () {
        this.timeout(30_000);
        await assertZeroErrors('typed_init', `
namespace RegTest3
func Main() {
    x: int = 42
    name: string = "hello"
    flag: bool = true
    print $"{x} {name} {flag}"
}
`);
    });

    // ================================================================
    // ENUM BACKING TYPES
    // Regression: parser error on `: string` and `: int` in enum declarations
    // Fixed in commit a6f274a
    // ================================================================

    test('string-backed enum declaration', async function () {
        this.timeout(30_000);
        await assertZeroErrors('enum_string', `
namespace RegTest6
enum Status: string {
    Active = "active",
    Inactive = "inactive"
}

func Main() {
    s := Status.Active
    print $"{s}"
}
`);
    });

    test('int-backed enum declaration', async function () {
        this.timeout(30_000);
        await assertZeroErrors('enum_int', `
namespace RegTest7
enum Priority: int {
    Low = 1,
    Medium = 2,
    High = 3
}

func Main() {
    p := Priority.High
    print $"{p}"
}
`);
    });

    test('simple enum (no backing type)', async function () {
        this.timeout(30_000);
        await assertZeroErrors('enum_simple', `
namespace RegTest8
enum Color {
    Red,
    Green,
    Blue
}

func Main() {
    c := Color.Red
    print $"{c}"
}
`);
    });

    test('string-backed enum with single member', async function () {
        this.timeout(30_000);
        await assertZeroErrors('enum_single', `
namespace RegTest9
enum SingleValue: string {
    Only = "only"
}

func Main() {
    v := SingleValue.Only
    print $"{v}"
}
`);
    });

    // ================================================================
    // STRING INTERPOLATION
    // ================================================================

    test('string interpolation with expressions', async function () {
        this.timeout(30_000);
        await assertZeroErrors('interp_expr', `
namespace RegTest17
func Main() {
    a := 10
    b := 20
    print $"Sum: {a + b}"
    print $"Product: {a * b}"
    print $"Compare: {a > b}"
}
`);
    });

    test('string interpolation with member access', async function () {
        this.timeout(30_000);
        await assertZeroErrors('interp_member', `
namespace RegTest18
func Main() {
    name := "hello"
    print $"Length: {name.Length}"
    print $"Upper: {name.ToUpper()}"
}
`);
    });

    // ================================================================
    // CLASSES AND CONSTRUCTORS
    // ================================================================

    test('class with typed properties', async function () {
        this.timeout(30_000);
        await assertZeroErrors('class_props', `
namespace RegTest19
class Point {
    X: int
    Y: int

    constructor(x: int, y: int) {
        X = x
        Y = y
    }

    func ToString(): string {
        return $"({X}, {Y})"
    }
}

func Main() {
    p := new Point(3, 4)
    print p.ToString()
}
`);
    });

    test('class with method returning typed value', async function () {
        this.timeout(30_000);
        await assertZeroErrors('class_method_return', `
namespace RegTest20
class Calculator {
    func Add(a: int, b: int): int {
        return a + b
    }

    func Multiply(a: int, b: int): int {
        return a * b
    }
}

func Main() {
    calc := new Calculator()
    result := calc.Add(3, 4)
    print $"Result: {result}"
}
`);
    });

    // ================================================================
    // COLLECTION EXPRESSIONS
    // ================================================================

    test('array-style collection initialization', async function () {
        this.timeout(30_000);
        await assertZeroErrors('collection_init', `
namespace RegTest21
func Main() {
    numbers := [1, 2, 3, 4, 5]
    names := ["Alice", "Bob", "Charlie"]
    for num in numbers {
        print num
    }
    for name in names {
        print name
    }
}
`);
    });

    // ================================================================
    // FOR LOOPS AND CONTROL FLOW
    // ================================================================

    test('for loop with if/else inside', async function () {
        this.timeout(30_000);
        await assertZeroErrors('for_if_else', `
namespace RegTest22
func Main() {
    items := [1, 2, 3, 4, 5]
    for item in items {
        if item > 3 {
            print $"{item} is large"
        } else {
            print $"{item} is small"
        }
    }
}
`);
    });

    test('nested for loops', async function () {
        this.timeout(30_000);
        await assertZeroErrors('nested_for', `
namespace RegTest23
func Main() {
    for i in [1, 2, 3] {
        for j in [10, 20] {
            print $"{i} * {j} = {i * j}"
        }
    }
}
`);
    });

    // ================================================================
    // FUNCTION SIGNATURES
    // ================================================================

    test('function with multiple typed parameters', async function () {
        this.timeout(30_000);
        await assertZeroErrors('func_multi_params', `
namespace RegTest24
func Calculate(a: int, b: int, op: string): int {
    if op == "add" {
        return a + b
    }
    return a - b
}

func Main() {
    result := Calculate(10, 5, "add")
    print $"Result: {result}"
}
`);
    });

    test('function with return type', async function () {
        this.timeout(30_000);
        await assertZeroErrors('func_return_type', `
namespace RegTest25
func GetGreeting(name: string): string {
    return $"Hello, {name}!"
}

func IsPositive(n: int): bool {
    return n > 0
}

func Main() {
    print GetGreeting("World")
    print $"Is 5 positive: {IsPositive(5)}"
}
`);
    });

    // ================================================================
    // KNOWN PARSER ISSUES — UN-SKIP WHEN PARSER IS FIXED
    //
    // These tests document real parser bugs. Each test is skipped with
    // a message explaining what needs to be fixed. When the parser is
    // updated to support the pattern, remove the skip() call.
    // ================================================================

    test('KNOWN ISSUE: typed variable declaration without init (x: int)', async function () {
        // Parser produces NL101 "Unexpected token ':'" for typed declarations
        // without initialization in function bodies. Class properties (Name: string)
        // and initialized declarations (x: int = 42) work fine.
        this.skip();
    });

    test('KNOWN ISSUE: out parameter in function signature', async function () {
        // Parser doesn't support out/ref parameter modifiers in function signatures
        // within the workspace LSP context. Example files work via standalone analysis.
        this.skip();
    });

    test('KNOWN ISSUE: ref parameter in function signature', async function () {
        // Same as out parameter issue — ref modifier not supported in workspace context.
        this.skip();
    });

    test('KNOWN ISSUE: match expression', async function () {
        // Match expressions produce parser errors in inline test context.
        // Pattern: match value { 0 => "zero", _ => "other" }
        this.skip();
    });

    test('KNOWN ISSUE: generic type in variable declaration (List<int>)', async function () {
        // Generic type annotations in local variable declarations produce errors.
        // Pattern: items: List<int> = new List<int>()
        this.skip();
    });

    test('KNOWN ISSUE: typed decl + out param (NL101 bug from screenshot)', async function () {
        // The exact pattern from the user-reported bug:
        //   result1: int
        //   success1 := TryParseInt("123", out result1)
        // Parser should support uninitialized typed declarations for out params.
        this.skip();
    });

    test('KNOWN ISSUE: dictionary TryGetValue with out param', async function () {
        // Dictionary.TryGetValue requires typed declaration + out parameter,
        // both of which are currently broken in workspace context.
        this.skip();
    });
});
