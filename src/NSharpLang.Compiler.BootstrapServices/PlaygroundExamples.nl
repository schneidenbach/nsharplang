namespace NSharpLang.Playground

import System.Collections.Generic

class PlaygroundExamples {
    static All: IReadOnlyList<PlaygroundExample> => BuildAll()
    static Tutorial: IReadOnlyList<PlaygroundTutorialStep> => BuildTutorial()
    static DefaultId: string => "01-hello-world"
    static EstimatedMinutes: int => 15

    static func BuildAll(): PlaygroundExample[] {
        examples := new PlaygroundExample[](10)
        examples[0] = new PlaygroundExample("01-hello-world", "Hello World", "Start with a tiny program, a tested function, and print.", 2, "Change the greeting and use diagnostics to keep the program clean.", Concepts0(), Code0(), Tests0(), "Hello, N#!\n")
        examples[1] = new PlaygroundExample("02-values-functions", "Values and Functions", "Use short declarations, explicit types, immutable bindings, and expression-bodied helpers.", 2, "Make the receipt line read naturally while preserving the tested total.", Concepts1(), Code1(), Tests1(), "Coffee: $27\n")
        examples[2] = new PlaygroundExample("03-types-visibility", "Types and Visibility", "Build records and classes without access-modifier noise.", 2, "Inspect completions on todo. and notice which members are part of the public shape.", Concepts2(), Code2(), Tests2(), "task #1: Try N# (done)\n")
        examples[3] = new PlaygroundExample("04-unions-patterns", "Unions and Match", "Model data that has different shapes, then match exhaustively.", 2, "Add or rename a result case and watch diagnostics point to missing match arms.", Concepts3(), Code3(), Tests3(), "Ada: 99\nMissing player #404\n")
        examples[4] = new PlaygroundExample("05-duck-typing", "Duck Typing", "Use a structural interface without declaring implementation on each type.", 2, "Create another greeter with a Greet method and pass it to Welcome without : IGreeter.", Concepts4(), Code4(), Tests4(), "Welcome, Ada.\nWELCOME, GRACE!\n")
        examples[5] = new PlaygroundExample("06-collections-linq", "Collections and Iteration", "Use array literals, foreach, and CLR collection members.", 1, "Ask for completions after numbers. to see array members through N#.", Concepts5(), Code5(), Tests5(), "Even sum: 12\nCount: 6\n")
        examples[6] = new PlaygroundExample("07-error-handling", "Go-Style Error Capture", "Capture thrown exceptions as values at the call site.", 1, "Use result, err := and keep the happy path readable without swallowing failures.", Concepts6(), Code6(), Tests6(), null)
        examples[7] = new PlaygroundExample("08-async-interop", "Async and .NET Interop", "Call the BCL directly and let async return types stay terse.", 1, "Hover over LoadMessage and await to see async types in the browser tooling loop.", Concepts7(), Code7(), Tests7(), null)
        examples[8] = new PlaygroundExample("09-testing", "Testing", "Write .tests.nl checks next to the code they verify.", 1, "Break Add and check diagnostics to see the tight red-green loop.", Concepts8(), Code8(), Tests8(), "5\n")
        examples[9] = new PlaygroundExample("10-tooling-loop", "The Tooling Loop", "Use diagnostics, completions, hover, and format together.", 1, "This lesson is intentionally ordinary: the point is the browser tooling loop around it.", Concepts9(), Code9(), Tests9(), "nlc check passed\n")
        return examples
    }

    static func BuildTutorial(): PlaygroundTutorialStep[] {
        steps := new PlaygroundTutorialStep[](7)
        steps[0] = new PlaygroundTutorialStep("welcome", "Welcome", "info", "Hi, welcome to the N# playground! This tutorial is designed for existing software engineers to jump into the language and its features. Let's walk through each of the features now.", "01-hello-world", null)
        steps[1] = new PlaygroundTutorialStep("print-keyword", "The print Keyword", "info", "Let's start by introducing the print keyword. It maps to Console.WriteLine, so small programs can write output without ceremony.", "01-hello-world", null)
        steps[2] = new PlaygroundTutorialStep("print-exercise", "Print Exercise", "exercise", "Change the greeting so the program prints Hello, Playground! Run it before moving on.", "01-hello-world", new PlaygroundTutorialValidation("output", "Hello, Playground!\n", "Playground", "The output matches the expected greeting."))
        steps[3] = new PlaygroundTutorialStep("classes-records", "Classes and Records", "info", "Here's what records and classes look like. Records carry data, classes carry behavior, and both still emit normal CLR-friendly shapes.", "03-types-visibility", null)
        steps[4] = new PlaygroundTutorialStep("visibility", "Visibility", "info", "Here's how visibility works: PascalCase members are exported, while camelCase members stay implementation details. Try completions on todo. or formatter. to see the public shape.", "03-types-visibility", null)
        steps[5] = new PlaygroundTutorialStep("class-exercise", "Class Exercise", "exercise", "Change the formatter prefix from task to issue. Run it and confirm the output reflects the new class state.", "03-types-visibility", new PlaygroundTutorialValidation("output", "issue #1: Try N# (done)\n", "issue", "The formatter now uses the requested prefix."))
        steps[6] = new PlaygroundTutorialStep("tooling-loop", "The Tooling Loop", "info", "The same compiler semantics power diagnostics, formatting, completions, hover, the CLI, and this browser workbench.", "10-tooling-loop", null)
        return steps
    }

    static func Concepts0(): string[] {
        concepts := new string[](4)
        concepts[0] = "entry point"
        concepts[1] = "print"
        concepts[2] = "string interpolation"
        concepts[3] = "tests"
        return concepts
    }

    static func Code0(): string {
        return "package Tutorial\n" + "\n" + "func Greeting(name: string): string {\n" + "    return $\"Hello, {name}!\"\n" + "}\n" + "\n" + "func main() {\n" + "    print Greeting(\"N#\")\n" + "}"
    }

    static func Tests0(): string? {
        return "package Tutorial\n" + "\n" + "test \"greets by name\" {\n" + "    assert Greeting(\"N#\") == \"Hello, N#!\"\n" + "}"
    }

    static func Concepts1(): string[] {
        concepts := new string[](4)
        concepts[0] = "type inference"
        concepts[1] = "let"
        concepts[2] = "explicit types"
        concepts[3] = "expression-bodied functions"
        return concepts
    }

    static func Code1(): string {
        return "package Tutorial\n" + "\n" + "func TotalWithTax(subtotal: double, taxRate: double): double => subtotal + subtotal * taxRate\n" + "\n" + "func ReceiptLine(item: string, subtotal: double): string {\n" + "    let taxRate := 0.08\n" + "    const total: double = TotalWithTax(subtotal, taxRate)\n" + "    return $\"{item}: ${total}\"\n" + "}\n" + "\n" + "func main() {\n" + "    print ReceiptLine(\"Coffee\", 25.0)\n" + "}"
    }

    static func Tests1(): string? {
        return "package Tutorial\n" + "\n" + "test \"computes total with tax\" {\n" + "    assert TotalWithTax(25.0, 0.08) == 27.0\n" + "}"
    }

    static func Concepts2(): string[] {
        concepts := new string[](5)
        concepts[0] = "records"
        concepts[1] = "classes"
        concepts[2] = "properties"
        concepts[3] = "visibility by casing"
        concepts[4] = "with expressions"
        return concepts
    }

    static func Code2(): string {
        return "package Tutorial\n" + "\n" + "record Todo {\n" + "    Id: int\n" + "    Title: string\n" + "    Done: bool\n" + "}\n" + "\n" + "class TodoFormatter(prefix: string) {\n" + "    func Format(todo: Todo): string {\n" + "        status := \"open\"\n" + "        if todo.Done {\n" + "            status = \"done\"\n" + "        }\n" + "        return $\"{prefix} #{todo.Id}: {todo.Title} ({status})\"\n" + "    }\n" + "}\n" + "\n" + "func Complete(todo: Todo): Todo {\n" + "    return todo with { Done: true }\n" + "}\n" + "\n" + "func main() {\n" + "    todo := new Todo { Id: 1, Title: \"Try N#\", Done: false }\n" + "    formatter := new TodoFormatter(\"task\")\n" + "    print formatter.Format(Complete(todo))\n" + "}"
    }

    static func Tests2(): string? {
        return "package Tutorial\n" + "\n" + "test \"complete preserves the title\" {\n" + "    todo := new Todo { Id: 7, Title: \"Ship\", Done: false }\n" + "    done := Complete(todo)\n" + "    assert done.Done == true\n" + "    assert done.Title == \"Ship\"\n" + "}"
    }

    static func Concepts3(): string[] {
        concepts := new string[](4)
        concepts[0] = "unions"
        concepts[1] = "pattern matching"
        concepts[2] = "exhaustiveness"
        concepts[3] = "typed errors"
        return concepts
    }

    static func Code3(): string {
        return "package Tutorial\n" + "\n" + "union LookupResult {\n" + "    Found { name: string, score: int }\n" + "    Missing { id: int }\n" + "}\n" + "\n" + "func Describe(result: LookupResult): string {\n" + "    return match result {\n" + "        LookupResult.Found { name, score } => $\"{name}: {score}\",\n" + "        LookupResult.Missing { id } => $\"Missing player #{id}\"\n" + "    }\n" + "}\n" + "\n" + "func main() {\n" + "    print Describe(new LookupResult.Found(\"Ada\", 99))\n" + "    print Describe(new LookupResult.Missing(404))\n" + "}"
    }

    static func Tests3(): string? {
        return "package Tutorial\n" + "\n" + "test \"describes union cases\" {\n" + "    assert Describe(new LookupResult.Found(\"Ada\", 99)) == \"Ada: 99\"\n" + "    assert Describe(new LookupResult.Missing(7)) == \"Missing player #7\"\n" + "}"
    }

    static func Concepts4(): string[] {
        concepts := new string[](4)
        concepts[0] = "duck interface"
        concepts[1] = "structural typing"
        concepts[2] = "concrete types"
        concepts[3] = "interop-friendly shape"
        return concepts
    }

    static func Code4(): string {
        return "package Tutorial\n" + "\n" + "duck interface IGreeter {\n" + "    func Greet(name: string): string\n" + "}\n" + "\n" + "class FriendlyGreeter {\n" + "    func Greet(name: string): string {\n" + "        return $\"Welcome, {name}.\"\n" + "    }\n" + "}\n" + "\n" + "class ExcitedGreeter {\n" + "    func Greet(name: string): string {\n" + "        return $\"WELCOME, {name.ToUpper()}!\"\n" + "    }\n" + "}\n" + "\n" + "func Welcome(greeter: IGreeter, name: string): string {\n" + "    return greeter.Greet(name)\n" + "}\n" + "\n" + "func main() {\n" + "    print Welcome(new FriendlyGreeter(), \"Ada\")\n" + "    print Welcome(new ExcitedGreeter(), \"Grace\")\n" + "}"
    }

    static func Tests4(): string? {
        return "package Tutorial\n" + "\n" + "test \"accepts any matching concrete greeter\" {\n" + "    assert Welcome(new FriendlyGreeter(), \"Ada\") == \"Welcome, Ada.\"\n" + "    assert Welcome(new ExcitedGreeter(), \"Grace\") == \"WELCOME, GRACE!\"\n" + "}"
    }

    static func Concepts5(): string[] {
        concepts := new string[](4)
        concepts[0] = "arrays"
        concepts[1] = "foreach"
        concepts[2] = "collection members"
        concepts[3] = ".NET interop"
        return concepts
    }

    static func Code5(): string {
        return "package Tutorial\n" + "\n" + "func SumEven(numbers: int[]): int {\n" + "    total := 0\n" + "    foreach number in numbers {\n" + "        if number % 2 == 0 {\n" + "            total = total + number\n" + "        }\n" + "    }\n" + "    return total\n" + "}\n" + "\n" + "func main() {\n" + "    numbers := [1, 2, 3, 4, 5, 6]\n" + "    print $\"Even sum: {SumEven(numbers)}\"\n" + "    print $\"Count: {numbers.Length}\"\n" + "}"
    }

    static func Tests5(): string? {
        return "package Tutorial\n" + "\n" + "test \"sums even numbers\" {\n" + "    assert SumEven([1, 2, 3, 4, 5, 6]) == 12\n" + "}"
    }

    static func Concepts6(): string[] {
        concepts := new string[](4)
        concepts[0] = "error tuples"
        concepts[1] = "exceptions"
        concepts[2] = "null"
        concepts[3] = "control flow"
        return concepts
    }

    static func Code6(): string {
        return "package Tutorial\n" + "\n" + "func Divide(a: int, b: int): int {\n" + "    if b == 0 {\n" + "        throw new Exception(\"division by zero\")\n" + "    }\n" + "\n" + "    return a / b\n" + "}\n" + "\n" + "func SafeDivide(a: int, b: int): string {\n" + "    result, err := Divide(a, b)\n" + "    if err != null {\n" + "        return err.Message\n" + "    }\n" + "\n" + "    return $\"result: {result}\"\n" + "}\n" + "\n" + "func main() {\n" + "    print SafeDivide(10, 2)\n" + "    print SafeDivide(10, 0)\n" + "}"
    }

    static func Tests6(): string? {
        return "package Tutorial\n" + "\n" + "test \"captures divide failures\" {\n" + "    assert SafeDivide(10, 2) == \"result: 5\"\n" + "    assert SafeDivide(10, 0) == \"division by zero\"\n" + "}"
    }

    static func Concepts7(): string[] {
        concepts := new string[](4)
        concepts[0] = "async"
        concepts[1] = "await"
        concepts[2] = "Task"
        concepts[3] = ".NET interop"
        return concepts
    }

    static func Code7(): string {
        return "package Tutorial\n" + "\n" + "import System.Threading.Tasks\n" + "\n" + "async func LoadMessage(name: string): string {\n" + "    await Task.Delay(10)\n" + "    return $\"Loaded profile for {name}\"\n" + "}\n" + "\n" + "async func main() {\n" + "    message := await LoadMessage(\"Ada\")\n" + "    print message\n" + "}"
    }

    static func Tests7(): string? {
        return null
    }

    static func Concepts8(): string[] {
        concepts := new string[](5)
        concepts[0] = "testing"
        concepts[1] = "test keyword"
        concepts[2] = "assert"
        concepts[3] = "table-driven tests"
        concepts[4] = "nlc test"
        return concepts
    }

    static func Code8(): string {
        return "package Tutorial\n" + "\n" + "class Calculator {\n" + "    static func Add(a: int, b: int): int {\n" + "        return a + b\n" + "    }\n" + "\n" + "    static func Clamp(value: int, min: int, max: int): int {\n" + "        if value < min {\n" + "            return min\n" + "        }\n" + "\n" + "        if value > max {\n" + "            return max\n" + "        }\n" + "\n" + "        return value\n" + "    }\n" + "}\n" + "\n" + "func main() {\n" + "    print Calculator.Add(2, 3)\n" + "}"
    }

    static func Tests8(): string? {
        return "package Tutorial\n" + "\n" + "test \"adds correctly\" with (a: int, b: int, expected: int) [\n" + "    (1, 2, 3),\n" + "    (0, 0, 0),\n" + "    (5, 7, 12)\n" + "] {\n" + "    assert Calculator.Add(a, b) == expected\n" + "}\n" + "\n" + "test \"clamps to bounds\" {\n" + "    assert Calculator.Clamp(-5, 0, 10) == 0\n" + "    assert Calculator.Clamp(12, 0, 10) == 10\n" + "}"
    }

    static func Concepts9(): string[] {
        concepts := new string[](5)
        concepts[0] = "diagnostics"
        concepts[1] = "completions"
        concepts[2] = "hover"
        concepts[3] = "format"
        concepts[4] = "browser tooling"
        return concepts
    }

    static func Code9(): string {
        return "package Tutorial\n" + "\n" + "record CommandResult {\n" + "    Command: string\n" + "    Ok: bool\n" + "}\n" + "\n" + "func Explain(result: CommandResult): string {\n" + "    return match result.Ok {\n" + "        true => $\"{result.Command} passed\",\n" + "        false => $\"{result.Command} needs attention\"\n" + "    }\n" + "}\n" + "\n" + "func main() {\n" + "    result := new CommandResult { Command: \"nlc check\", Ok: true }\n" + "    print Explain(result)\n" + "}"
    }

    static func Tests9(): string? {
        return "package Tutorial\n" + "\n" + "test \"explains command status\" {\n" + "    assert Explain(new CommandResult { Command: \"nlc check\", Ok: true }) == \"nlc check passed\"\n" + "    assert Explain(new CommandResult { Command: \"nlc test\", Ok: false }) == \"nlc test needs attention\"\n" + "}"
    }
}
