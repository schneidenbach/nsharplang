using System.Collections.Generic;
using System.Linq;

namespace NSharpLang.Playground;

public static class PlaygroundExamples
{
    public static readonly IReadOnlyList<PlaygroundExample> All =
    [
        new(
            "01-hello-world",
            "Hello World",
            "Start with a tiny program, a tested function, and print.",
            2,
            "Change the greeting and use diagnostics to keep the program clean.",
            ["entry point", "print", "string interpolation", "tests"],
            "N# keeps top-level ceremony low: func main() plus print is enough.",
            """
            package Tutorial

            func Greeting(name: string): string {
                return $"Hello, {name}!"
            }

            func main() {
                print Greeting("N#")
            }
            """,
            """
            package Tutorial

            test "greets by name" {
                assert Greeting("N#") == "Hello, N#!"
            }
            """),

        new(
            "02-values-functions",
            "Values and Functions",
            "Use short declarations, explicit types, immutable bindings, and expression-bodied helpers.",
            2,
            "Make the receipt line read naturally while preserving the tested total.",
            ["type inference", "let", "explicit types", "expression-bodied functions"],
            "N# puts parameter types after names and uses := for inferred locals, closer to Go than C#.",
            """
            package Tutorial

            func TotalWithTax(subtotal: double, taxRate: double): double => subtotal + subtotal * taxRate

            func ReceiptLine(item: string, subtotal: double): string {
                let taxRate := 0.08
                const total: double = TotalWithTax(subtotal, taxRate)
                return $"{item}: ${total}"
            }

            func main() {
                print ReceiptLine("Coffee", 25.0)
            }
            """,
            """
            package Tutorial

            test "computes total with tax" {
                assert TotalWithTax(25.0, 0.08) == 27.0
            }
            """),

        new(
            "03-types-visibility",
            "Types and Visibility",
            "Build records and classes without access-modifier noise.",
            2,
            "Inspect completions on todo. and notice which members are part of the public shape.",
            ["records", "classes", "properties", "visibility by casing", "with expressions"],
            "PascalCase declarations are exported; camelCase declarations stay implementation details.",
            """
            package Tutorial

            record Todo {
                Id: int
                Title: string
                Done: bool
            }

            class TodoFormatter(prefix: string) {
                func Format(todo: Todo): string {
                    status := "open"
                    if todo.Done {
                        status = "done"
                    }
                    return $"{prefix} #{todo.Id}: {todo.Title} ({status})"
                }
            }

            func Complete(todo: Todo): Todo {
                return todo with { Done: true }
            }

            func main() {
                todo := new Todo { Id: 1, Title: "Try N#", Done: false }
                formatter := new TodoFormatter("task")
                print formatter.Format(Complete(todo))
            }
            """,
            """
            package Tutorial

            test "complete preserves the title" {
                todo := new Todo { Id: 7, Title: "Ship", Done: false }
                done := Complete(todo)
                assert done.Done == true
                assert done.Title == "Ship"
            }
            """),

        new(
            "04-unions-patterns",
            "Unions and Match",
            "Model data that has different shapes, then match exhaustively.",
            2,
            "Add or rename a result case and watch diagnostics point to missing match arms.",
            ["unions", "pattern matching", "exhaustiveness", "typed errors"],
            "Instead of nullable result objects or string error codes, N# lets the type carry each case.",
            """
            package Tutorial

            union LookupResult {
                Found { name: string, score: int }
                Missing { id: int }
            }

            func Describe(result: LookupResult): string {
                return match result {
                    LookupResult.Found { name, score } => $"{name}: {score}",
                    LookupResult.Missing { id } => $"Missing player #{id}"
                }
            }

            func main() {
                print Describe(new LookupResult.Found("Ada", 99))
                print Describe(new LookupResult.Missing(404))
            }
            """,
            """
            package Tutorial

            test "describes union cases" {
                assert Describe(new LookupResult.Found("Ada", 99)) == "Ada: 99"
                assert Describe(new LookupResult.Missing(7)) == "Missing player #7"
            }
            """),

        new(
            "05-duck-typing",
            "Duck Typing",
            "Use a structural interface without declaring implementation on each type.",
            2,
            "Create another greeter with a Greet method and pass it to Welcome without : IGreeter.",
            ["duck interface", "structural typing", "concrete types", "interop-friendly shape"],
            "C# requires nominal interface implementation; N# duck interfaces match by member shape.",
            """
            package Tutorial

            duck interface IGreeter {
                func Greet(name: string): string
            }

            class FriendlyGreeter {
                func Greet(name: string): string {
                    return $"Welcome, {name}."
                }
            }

            class ExcitedGreeter {
                func Greet(name: string): string {
                    return $"WELCOME, {name.ToUpper()}!"
                }
            }

            func Welcome(greeter: IGreeter, name: string): string {
                return greeter.Greet(name)
            }

            func main() {
                print Welcome(new FriendlyGreeter(), "Ada")
                print Welcome(new ExcitedGreeter(), "Grace")
            }
            """,
            """
            package Tutorial

            test "accepts any matching concrete greeter" {
                assert Welcome(new FriendlyGreeter(), "Ada") == "Welcome, Ada."
                assert Welcome(new ExcitedGreeter(), "Grace") == "WELCOME, GRACE!"
            }
            """),

        new(
            "06-collections-linq",
            "Collections and LINQ",
            "Use array literals, lambdas, LINQ, ranges, and indexes.",
            1,
            "Ask for completions after numbers. or evens. to see .NET members through N#.",
            ["arrays", "LINQ", "lambdas", "ranges", "index from end", "C# interop"],
            "N# keeps .NET collections and LINQ available instead of inventing a separate collection world.",
            """
            import System.Linq

            package Tutorial

            func SumEven(numbers: int[]): int {
                return numbers.Where(n => n % 2 == 0).Sum()
            }

            func Middle(numbers: int[]): int[] {
                return numbers[1..^1]
            }

            func main() {
                numbers := [1, 2, 3, 4, 5, 6]
                print $"Even sum: {SumEven(numbers)}"
                print $"Last item: {numbers[^1]}"
            }
            """,
            """
            package Tutorial

            test "sums even numbers" {
                assert SumEven([1, 2, 3, 4, 5, 6]) == 12
            }
            """),

        new(
            "07-error-handling",
            "Go-Style Error Capture",
            "Capture thrown exceptions as values at the call site.",
            1,
            "Use result, err := and keep the happy path readable without swallowing failures.",
            ["error tuples", "exceptions", "null", "control flow"],
            "N# embraces .NET exceptions but gives a Go-like call-site shape when you want it.",
            """
            import System

            package Tutorial

            func Divide(a: int, b: int): int {
                if b == 0 {
                    throw new Exception("division by zero")
                }

                return a / b
            }

            func SafeDivide(a: int, b: int): string {
                result, err := Divide(a, b)
                if err != null {
                    return err.Message
                }

                return $"result: {result}"
            }

            func main() {
                print SafeDivide(10, 2)
                print SafeDivide(10, 0)
            }
            """,
            """
            package Tutorial

            test "captures divide failures" {
                assert SafeDivide(10, 2) == "result: 5"
                assert SafeDivide(10, 0) == "division by zero"
            }
            """),

        new(
            "08-async-interop",
            "Async and .NET Interop",
            "Call the BCL directly and let async return types stay terse.",
            1,
            "Hover over LoadMessage and Task.Delay to see N# and .NET symbols together.",
            ["async", "await", "Task", ".NET interop", "imports"],
            "N# async functions read tersely while still producing normal .NET tasks for C# callers.",
            """
            import System.Threading.Tasks

            package Tutorial

            async func LoadMessage(name: string): string {
                await Task.Delay(10)
                return $"Loaded profile for {name}"
            }

            async func main() {
                message := await LoadMessage("Ada")
                print message
            }
            """,
            null),

        new(
            "09-testing",
            "Testing",
            "Write .tests.nl checks next to the code they verify.",
            1,
            "Break Add and check diagnostics to see the tight red-green loop.",
            ["testing", "test keyword", "assert", "table-driven tests", "nlc test"],
            "N# tests are part of the language surface, not a pile of ceremony around C# attributes.",
            """
            package Tutorial

            class Calculator {
                static func Add(a: int, b: int): int {
                    return a + b
                }

                static func Clamp(value: int, min: int, max: int): int {
                    if value < min {
                        return min
                    }

                    if value > max {
                        return max
                    }

                    return value
                }
            }

            func main() {
                print Calculator.Add(2, 3)
            }
            """,
            """
            package Tutorial

            test "adds correctly" with (a: int, b: int, expected: int) [
                (1, 2, 3),
                (0, 0, 0),
                (5, 7, 12)
            ] {
                assert Calculator.Add(a, b) == expected
            }

            test "clamps to bounds" {
                assert Calculator.Clamp(-5, 0, 10) == 0
                assert Calculator.Clamp(12, 0, 10) == 10
            }
            """),

        new(
            "10-tooling-loop",
            "The Tooling Loop",
            "Use diagnostics, completions, hover, and format together.",
            1,
            "This lesson is intentionally ordinary: the point is the browser tooling loop around it.",
            ["diagnostics", "completions", "hover", "format", "browser tooling"],
            "The same compiler semantics power the CLI, editor tooling, and hosted browser playground.",
            """
            package Tutorial

            record CommandResult {
                Command: string
                Ok: bool
            }

            func Explain(result: CommandResult): string {
                return match result.Ok {
                    true => $"{result.Command} passed",
                    false => $"{result.Command} needs attention"
                }
            }

            func main() {
                result := new CommandResult { Command: "nlc check", Ok: true }
                print Explain(result)
            }
            """,
            """
            package Tutorial

            test "explains command status" {
                assert Explain(new CommandResult { Command: "nlc check", Ok: true }) == "nlc check passed"
                assert Explain(new CommandResult { Command: "nlc test", Ok: false }) == "nlc test needs attention"
            }
            """)
    ];

    public static string DefaultId => All[0].Id;

    public static int EstimatedMinutes => All.Sum(example => example.Minutes);
}
