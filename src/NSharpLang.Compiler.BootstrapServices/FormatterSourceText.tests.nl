namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Text
import NSharpLang.Compiler.Ast


// THE FORMATTER READ THROUGH ITS OWN FRONT DOOR: SOURCE TEXT IN, CANONICAL SOURCE TEXT OUT.
//
// `Formatter.tests.nl` states the DECLARATION arms one at a time, against hand-built AST nodes.
// This file states the other half — the contract a user actually experiences: give the formatter a
// file of N# and it gives back the canonical spelling of that same file. Both halves are needed and
// neither subsumes the other: an arm contract cannot see the parser's shape choices, and a
// whole-file contract cannot reach a union case with no properties.
//
// EVERY SOURCE AND EVERY EXPECTED TEXT BELOW WAS DECODED OUT OF `tests/FormatterTests.cs`, which
// this file and `FormatterConfig.tests.nl` replace and which is DELETED. That file was the last
// canonical C# assertion layer over an already-N# subject that the estate could route.
//
// THE FORMAT ORACLE'S THREE LEGS LIVE IN THE CORPUS, NOT HERE (`--check`, an estate reformat that
// must be byte-identical, and a DEFORMED estate reformat). What lives here is what the corpus
// cannot state: the EXACT canonical text for a named construct, and the two properties the corpus
// legs assume — that formatting twice is formatting once, and that the formatter's own output
// re-parses.
//
// A NOTE ON SPELLING. Newlines are compared as a visible `|` token so a failing assertion reads as
// one line of text; `FstFormatRaw` is the same pipeline without that substitution, for the
// substring reads. `new Formatter()` and the one-argument `Format(ast)` both omit a defaulted
// parameter, which the estate declines, so both are written at full arity.

func FstUnit(source: string): CompilationUnit {
    parsed := ColumnarParserRecovery.ParseFileAst(source, "test.nl")
    unit := parsed.CompilationUnit
    if unit != null {
        return unit
    }

    // Unreachable for every source below — each one parses. A file the parser cannot read is not a
    // formatting question, and `FormatSafe`'s reparse gate is what states that contract.
    return new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, new List<Declaration>(), 0, 0)
}

func FstShow(text: string): string {
    return text.Replace("\r\n", "\n").Replace("\n", "|")
}

func FstFormatRaw(source: string): string {
    formatter := new Formatter(null)
    return formatter.Format(FstUnit(source), null).Trim()
}

func FstFormat(source: string): string {
    return FstShow(FstFormatRaw(source))
}

func FstFormatWithRaw(source: string, size: int, spaces: bool): string {
    config := new FormatterConfig()
    config.IndentSize = size
    config.UseSpaces = spaces
    formatter := new Formatter(config)
    return formatter.Format(FstUnit(source), null).Trim()
}

func FstFormatWith(source: string, size: int, spaces: bool): string {
    return FstShow(FstFormatWithRaw(source, size, spaces))
}

// The lexer run is not dead: `Tokenize` is called for its EFFECT, which is to populate `Comments`.
// A format that is not given the comment stream drops every comment in the file.
func FstFormatCommentsRaw(source: string): string {
    lexer := new Lexer(source, "test.nl")
    tokens := lexer.Tokenize()
    if tokens.Count == 0 {
        return ""
    }

    formatter := new Formatter(null)
    return formatter.Format(FstUnit(source), lexer.Comments).Trim()
}

func FstFormatComments(source: string): string {
    return FstShow(FstFormatCommentsRaw(source))
}

func FstIdempotent(source: string): bool {
    once := FstFormatRaw(source)
    return FstFormatRaw(once) == once
}

func FstIdempotentComments(source: string): bool {
    once := FstFormatCommentsRaw(source)
    return FstFormatCommentsRaw(once) == once
}

// The formatter's own output must re-parse. This is the gate `FormatSafe` runs, stated directly.
func FstReparseErrors(source: string): int {
    parsed := ColumnarParserRecovery.ParseFileAst(source, "test.nl")
    count := 0
    for error in parsed.Errors {
        if error.Severity == ErrorSeverity.Error {
            count = count + 1
        }
    }

    return count
}

func FstReparseErrorsAfterFormat(source: string): int {
    return FstReparseErrors(FstFormatRaw(source))
}

func FstSafeResult(source: string): FormatResult {
    formatter := new Formatter(null)
    return formatter.FormatSafe(source, FstUnit(source), null, "test.nl")
}

func FstSafeSuccess(source: string): bool {
    return FstSafeResult(source).Success
}

func FstSafeText(source: string): string {
    return FstSafeResult(source).Text
}

func FstSafeWarnings(source: string): int {
    return FstSafeResult(source).Warnings.Count
}

func FstSafeIdempotent(source: string): bool {
    once := FstSafeText(source)
    return FstSafeText(once) == once
}

// `FormatSafe` WITH THE COMMENT STREAM — the pipeline `nlc format` actually runs. The helpers above
// pass a null comment list, which drops every comment in the file and so cannot reach any shape
// whose bug lives in where a comment lands. `Tokenize` is called for its EFFECT (it populates
// `Comments`); the count is read only so the call is not a bare statement.
func FstSafeCommentsResult(source: string): FormatResult {
    lexer := new Lexer(source, "test.nl")
    tokens := lexer.Tokenize()
    if tokens.Count == 0 {
        return new FormatResult()
    }

    formatter := new Formatter(null)
    return formatter.FormatSafe(source, FstUnit(source), lexer.Comments, "test.nl")
}

func FstSafeCommentsSuccess(source: string): bool {
    return FstSafeCommentsResult(source).Success
}

func FstSafeCommentsWarnings(source: string): int {
    return FstSafeCommentsResult(source).Warnings.Count
}

// ---- THE CANONICAL BODY: INDENTATION IS REBUILT, NEVER PRESERVED ---------------------------------

test "a body written with no indentation at all comes back indented one level per depth" {
    assert FstFormat("func main(){print 5}") == "func main() {|    print 5|}"
    assert FstFormat("func Add(x: int, y: int): int {\nreturn x + y\n}") == "func Add(x: int, y: int): int {|    return x + y|}"
    assert FstFormat("func Calculate(x: int): int {\nz := x * 2\nw := z + 1\nreturn w\n}") == "func Calculate(x: int): int {|    z := x * 2|    w := z + 1|    return w|}"
}

test "a nested block indents by exactly one level per depth, and an else chain stays at its opener's depth" {
    assert FstFormat("func Test(x: int): int {\nif x > 0 {\nreturn x\n} else {\nreturn -x\n}\n}") == "func Test(x: int): int {|    if x > 0 {|        return x|    } else {|        return -x|    }|}"
    assert FstFormat("func Test(x: int): string {\nif x > 0 {\nreturn \"positive\"\n} else if x < 0 {\nreturn \"negative\"\n} else {\nreturn \"zero\"\n}\n}") == "func Test(x: int): string {|    if x > 0 {|        return \"positive\"|    } else if x < 0 {|        return \"negative\"|    } else {|        return \"zero\"|    }|}"
}

test "an expression-bodied function stays on ONE line and gains no braces" {
    assert FstFormat("func Double(x: int): int => x * 2") == "func Double(x: int): int => x * 2"
}

// ---- ONE ARM PER DECLARATION KIND ----------------------------------------------------------------

test "a class writes its members one per line, and its methods one block per member" {
    assert FstFormat("class Person {\nName: string\nAge: int\n}") == "class Person {|    Name: string|    Age: int|}"
    assert FstFormat("class MyClass {\nValue: int\n}") == "class MyClass {|    Value: int|}"
    assert FstFormat("class Calculator {\nfunc Add(x: int, y: int): int {\nreturn x + y\n}\n}") == "class Calculator {|    func Add(x: int, y: int): int {|        return x + y|    }|}"
}

test "a record, a record struct and a struct each announce their own keywords" {
    assert FstFormat("record Person {\nName: string\nAge: int\n}") == "record Person {|    Name: string|    Age: int|}"
    assert FstFormat("record struct Point {\nX: int\nY: int\n}") == "record struct Point {|    X: int|    Y: int|}"
    assert FstFormat("struct Point {\nX: int\nY: int\n}") == "struct Point {|    X: int|    Y: int|}"
}

test "a struct's primary constructor parameters survive the format" {
    assert FstFormat("struct Point(x: double, y: double) {\nX: double = x\nY: double = y\n}") == "struct Point(x: double, y: double) {|    X: double = x|    Y: double = y|}"
}

test "a soa record writes one column per line even when the source ran them together" {
    assert FstFormat("soa record NodeTable { kind: int, valueStart: int valueLength: int }") == "soa record NodeTable {|    kind: int|    valueStart: int|    valueLength: int|}"
}

// Regression bug-014: the formatter emitted `Success(value: int)`, which the parser rejects.
// A case with no properties writes no braces at all — the `Point` row below.
test "a union writes its cases with BRACES and never with parentheses" {
    assert FstFormat("union Result {\nSuccess { value: int }\nError { message: string }\n}") == "union Result {|    Success { value: int }|    Error { message: string }|}"
    assert FstFormat("union Shape {\nCircle { radius: float }\nRectangle { width: float, height: float }\nPoint\n}") == "union Shape {|    Circle { radius: float }|    Rectangle { width: float, height: float }|    Point|}"
}

// Regression: the formatter dropped `<T>` from union declarations, silently rewriting
// `union Result<T>` to `union Result` and corrupting generic-union source.
test "a generic union keeps its type parameters, at one and at two" {
    assert FstFormat("union Result<T> {\nSuccess { value: T }\nFailure { error: string }\n}") == "union Result<T> {|    Success { value: T }|    Failure { error: string }|}"
    assert FstFormat("union Either<L, R> {\nLeft { value: L }\nRight { value: R }\n}") == "union Either<L, R> {|    Left { value: L }|    Right { value: R }|}"
}

test "an enum's members are one per line, and a string-backed enum announces its backing type" {
    assert FstFormat("enum Color {\nRed,\nGreen,\nBlue\n}") == "enum Color {|    Red,|    Green,|    Blue|}"
    assert FstFormat("enum Status: string {\nPending = \"pending\",\nActive = \"active\",\nDone = \"done\"\n}") == "enum Status: string {|    Pending = \"pending\",|    Active = \"active\",|    Done = \"done\"|}"
}

test "an interface and a duck interface differ by one keyword" {
    assert FstFormat("interface ICalculator {\nfunc Add(x: int, y: int): int\n}") == "interface ICalculator {|    func Add(x: int, y: int): int|}"
    assert FstFormat("duck interface Printable {\nfunc Print(): string\n}") == "duck interface Printable {|    func Print(): string|}"
}

test "a type alias is one line and needs no body" {
    assert FstFormat("type UserId = int") == "type UserId = int"
}

test "a conversion operator uses the native syntax, not the CLR spelling" {
    assert FstFormat("class Celsius {\nimplicit operator Fahrenheit(c:Celsius){\nreturn new Fahrenheit()\n}\n}") == "class Celsius {|    implicit operator Fahrenheit(c: Celsius) {|        return new Fahrenheit()|    }|}"
}

test "a static top-level function keeps its modifier" {
    assert FstFormat("static func Main() {\nprint \"hello\"\n}") == "static func Main() {|    print \"hello\"|}"
}

test "a generic function and a generic class keep their type parameter lists" {
    assert FstFormat("func Identity<T>(x: T): T {\nreturn x\n}") == "func Identity<T>(x: T): T {|    return x|}"
    assert FstFormat("class Container<T> {\nValue: T\n}") == "class Container<T> {|    Value: T|}"
}

// ---- EVERY LOOP FORM, AND THE ONE THAT IS NORMALIZED ---------------------------------------------

test "`foreach` is normalized to `for ... in`, and `for ... in` is already canonical" {
    assert FstFormat("func Loop(items: int[]) {\nforeach item in items {\nprint item\n}\n}") == "func Loop(items: int[]) {|    for item in items {|        print item|    }|}"
    assert FstFormat("func Loop(items: int[]) {\nfor item in items {\nprint item\n}\n}") == "func Loop(items: int[]) {|    for item in items {|        print item|    }|}"
    assert FstFormat("func Test(items: int[]) {\nfor item in items {\nprint item\n}\n}") == "func Test(items: int[]) {|    for item in items {|        print item|    }|}"
}

// Regression bug-016: the formatter emitted `for i = 0` where the source wrote `for i := 0`.
test "a C-style for loop keeps its three clauses, and `:=` in the initializer stays `:=`" {
    assert FstFormat("func Loop() {\nfor i = 0; i < 10; i = i + 1 {\nprint i\n}\n}") == "func Loop() {|    for i = 0; i < 10; i = i + 1 {|        print i|    }|}"
    assert FstFormat("func Test() {\nfor i = 0; i < 10; i++ {\nprint i\n}\n}") == "func Test() {|    for i = 0; i < 10; i++ {|        print i|    }|}"
    assert FstFormat("func Test() {\nfor i := 0; i < 10; i++ {\nprint i\n}\n}") == "func Test() {|    for i := 0; i < 10; i++ {|        print i|    }|}"
}

test "a while loop indents its body one level" {
    assert FstFormat("func Loop() {\ni := 0\nwhile i < 10 {\nprint i\ni = i + 1\n}\n}") == "func Loop() {|    i := 0|    while i < 10 {|        print i|        i = i + 1|    }|}"
}

// ---- STATEMENTS ----------------------------------------------------------------------------------

test "a typed catch is canonicalized from the CLR spelling to the N# one" {
    assert FstFormat("func Test() {\ntry {\nprint \"trying\"\n} catch (Exception e) {\nprint e\n}\n}") == "func Test() {|    try {|        print \"trying\"|    } catch e: Exception {|        print e|    }|}"
}

test "a bare catch keeps no parentheses" {
    source := "func Test() {\n    try {\n        print \"trying\"\n    } catch {\n        print \"caught\"\n    }\n}"

    assert FstFormatRaw(source).Contains("} catch {")
    assert !FstFormatRaw(source).Contains("catch ()")
}

test "a generator writes its yields one per line" {
    assert FstFormat("func* Generate(): IEnumerable<int> {\nyield 1\nyield 2\nyield 3\n}") == "func* Generate(): IEnumerable<int> {|    yield 1|    yield 2|    yield 3|}"
}

test "a shorthand let gets `:=` and a typed let gets `=`" {
    assert FstFormat("func Test() {\nx := 42\nprint x\n}") == "func Test() {|    x := 42|    print x|}"
    assert FstFormat("func Test() {\nx: int = 42\nprint x\n}") == "func Test() {|    x: int = 42|    print x|}"
}

test "an out argument emits exactly ONE out modifier" {
    assert FstFormat("func Main() {\nnumber := 0\nif TryParseInt(\"123\", out number) {\nprint number\n}\n}") == "func Main() {|    number := 0|    if TryParseInt(\"123\", out number) {|        print number|    }|}"
}

test "the systems policy blocks nest, and the allow header's arguments get their spaces" {
    assert FstFormat("func Test(): void {\nallow(alloc, dispatch:interface, reason: \"diagnostic path\") {\nalloc {\nunsafe {\nprint 1\n}\n}\n}\n}") == "func Test(): void {|    allow(alloc, dispatch: interface, reason: \"diagnostic path\") {|        alloc {|            unsafe {|                print 1|            }|        }|    }|}"
}

// ---- EXPRESSIONS ---------------------------------------------------------------------------------

test "binary operators are spaced whatever the source did" {
    assert FstFormat("func Test(): int {\nx := 1+2*3\nreturn x\n}") == "func Test(): int {|    x := 1 + 2 * 3|    return x|}"
}

test "every comma-separated list gets exactly one space after each comma" {
    assert FstFormat("func Test() {\nresult := Add(1,2,3)\nprint result\n}") == "func Test() {|    result := Add(1, 2, 3)|    print result|}"
    assert FstFormat("func Test() {\np := new Person(\"John\",30)\nreturn p\n}") == "func Test() {|    p := new Person(\"John\", 30)|    return p|}"
    assert FstFormat("func Test() {\narr := [1,2,3]\nprint arr\n}") == "func Test() {|    arr := [1, 2, 3]|    print arr|}"
    assert FstFormat("func Test() {\nt := (1,2,3)\nreturn t\n}") == "func Test() {|    t := (1, 2, 3)|    return t|}"
}

test "a tuple deconstruction LOSES its parentheses, which is the canonical spelling" {
    assert FstFormat("func Test() {\n(x,y) := GetPair()\nreturn x + y\n}") == "func Test() {|    x, y := GetPair()|    return x + y|}"
}

test "a member access chain is written back unchanged" {
    assert FstFormat("func Test() {\nx := person.name.length\nreturn x\n}") == "func Test() {|    x := person.name.length|    return x|}"
}

test "parentheses the source wrote are preserved, nested or not" {
    assert FstFormat("func Test(): int {\n    return 2 * (x + y)\n}") == "func Test(): int {|    return 2 * (x + y)|}"
    assert FstFormat("func Test(): int {\n    return (a + b) * (c + d)\n}") == "func Test(): int {|    return (a + b) * (c + d)|}"
}

test "a lambda keeps its parameter list shape, and a block body indents" {
    assert FstFormat("func Test() {\nf := x => x * 2\nprint f(5)\n}") == "func Test() {|    f := x => x * 2|    print f(5)|}"
    assert FstFormat("func Test() {\nf := x => x * 2\n}") == "func Test() {|    f := x => x * 2|}"
    assert FstFormat("func Test() {\nf := (x, y) => x + y\n}") == "func Test() {|    f := (x, y) => x + y|}"
    assert FstFormat("func Test() {\nf := (x, y) => {\nreturn x + y\n}\n}") == "func Test() {|    f := (x, y) => {|        return x + y|    }|}"
}

test "a target-typed new has NO space and a named new has one" {
    assert FstFormat("func Test(): Person {\nreturn new(\"Alice\", 30)\n}") == "func Test(): Person {|    return new(\"Alice\", 30)|}"
    assert FstFormat("func Test() {\np := new Person(\"Alice\", 30)\n}") == "func Test() {|    p := new Person(\"Alice\", 30)|}"
}

// Regression bug-015: the formatter emitted `return x match {`, which the parser rejects.
test "a match expression indents its cases and keeps the `match` prefix on a return" {
    assert FstFormat("func Test(x: int): string {\nreturn match x {\n0 => \"zero\",\n1 => \"one\",\n_ => \"other\"\n}\n}") == "func Test(x: int): string {|    return match x {|        0 => \"zero\",|        1 => \"one\",|        _ => \"other\"|    }|}"
    assert FstFormat("func Test(x: int): string {\nreturn match x {\n0 => \"zero\",\n_ => \"other\"\n}\n}") == "func Test(x: int): string {|    return match x {|        0 => \"zero\",|        _ => \"other\"|    }|}"
}

test "a match case list is comma separated EXCEPT the last case" {
    source := "func Test(x: int): string {\nreturn match x {\n0 => \"zero\",\n1 => \"one\",\n_ => \"other\"\n}\n}"

    assert FstFormatRaw(source).Contains("0 => \"zero\",")
    assert FstFormatRaw(source).Contains("1 => \"one\",")
    assert FstFormatRaw(source).Contains("_ => \"other\"")
    assert !FstFormatRaw(source).Contains("_ => \"other\",")
}

test "a match case may carry a guard" {
    assert FstFormat("func Test(x: int): string {\nreturn match x {\n_ when x > 0 => \"positive\",\n_ => \"non-positive\"\n}\n}") == "func Test(x: int): string {|    return match x {|        _ when x > 0 => \"positive\",|        _ => \"non-positive\"|    }|}"
}

test "must, with, range, null-coalescing and null-conditional are all written back unchanged" {
    assert FstFormat("func main(input: int?): int{return must input}") == "func main(input: int?): int {|    return must input|}"
    assert FstFormat("func Test(p: Person): Person {\nreturn p with { Age: 30 }\n}") == "func Test(p: Person): Person {|    return p with { Age: 30 }|}"
    assert FstFormat("func Test() {\nr := 0..10\nreturn r\n}") == "func Test() {|    r := 0..10|    return r|}"
    assert FstFormat("func Test(x: string?): string {\nreturn x ?? \"default\"\n}") == "func Test(x: string?): string {|    return x ?? \"default\"|}"
    assert FstFormat("func Test(p: Person?): string? {\nreturn p?.Name\n}") == "func Test(p: Person?): string? {|    return p?.Name|}"
}

test "a function type uses the parser-supported Func syntax" {
    assert FstFormat("func Times(action: Func<int, void>) {\naction(1)\n}") == "func Times(action: Func<int, void>) {|    action(1)|}"
}

test "an interpolated string is not mangled" {
    assert FstFormat("func Test() {\n    name := \"Alice\"\n    print $\"Hello, {name}!\"\n}") == "func Test() {|    name := \"Alice\"|    print $\"Hello, {name}!\"|}"
}

test "an interpolated RAW string keeps its delimiters and its content, and is idempotent" {
    source := "func Test(name: string) {\n    html := $\"\"\"\n    <h1>{name}</h1>\n    \"\"\"\n}"

    assert FstFormatRaw(source).Contains("$\"\"\"")
    assert FstFormatRaw(source).Contains("<h1>{name}</h1>")
    assert FstIdempotent(source)
}

// ---- THE VISIBILITY MODIFIERS: THE CASING IS THE DEFAULT, THE KEYWORD IS THE OVERRIDE ------------

test "public and private are DROPPED when the name's casing already says the same thing" {
    assert FstFormat("public class Account {\nprivate id: string\npublic func GetId(): string {\nreturn id\n}\n}") == "class Account {|    id: string|    func GetId(): string {|        return id|    }|}"
}

test "public and private are PRESERVED when they contradict the name's casing" {
    assert FstFormat("package Models\n\npublic class legacyCamel {\npublic func visibleExplicit(): string {\nreturn \"ok\"\n}\npublic valueExplicit: string\n}") == "package Models||public class legacyCamel {|    public func visibleExplicit(): string {|        return \"ok\"|    }|    public valueExplicit: string|}"
    assert FstFormat("public func legacyTop(): string {\nreturn \"ok\"\n}\n\nprivate func SecretTop(): string {\nreturn \"hidden\"\n}") == "public func legacyTop(): string {|    return \"ok\"|}||private func SecretTop(): string {|    return \"hidden\"|}"
    assert FstFormat("private class SecretPascal {\nprivate func HiddenMethod(): string {\nreturn \"nope\"\n}\nprivate HiddenValue: string\n}") == "private class SecretPascal {|    private func HiddenMethod(): string {|        return \"nope\"|    }|    private HiddenValue: string|}"
}

// `operator +` has no casing to read, so the casing rule cannot apply and the modifier goes.
test "an operator overload drops them even though its name is lowercase" {
    assert FstFormat("class Vector {\npublic static func operator +(left: Vector, right: Vector): Vector {\nreturn left\n}\n}") == "class Vector {|    static func operator +(left: Vector, right: Vector): Vector {|        return left|    }|}"
}

test "the interop modifiers — internal, protected, virtual — are never dropped" {
    assert FstFormat("internal class HostBridge {\nprotected virtual func OnStart() {\n}\n}") == "internal class HostBridge {|    protected virtual func OnStart() {|    }|}"
}

test "async sits next to func, and override comes before it" {
    assert FstFormat("async func GetData(): Task<string> {\nresult := await FetchData()\nreturn result\n}") == "async func GetData(): Task<string> {|    result := await FetchData()|    return result|}"
    assert FstFormat("class Repository : BaseRepository {\noverride async func GetData(): Task<string> {\nreturn FetchData()\n}\n}") == "class Repository: BaseRepository {|    override async func GetData(): Task<string> {|        return FetchData()|    }|}"
}

// ---- ATTRIBUTES ----------------------------------------------------------------------------------

test "declaration attributes are preserved, one per line, above their declaration" {
    assert FstFormat("class Person {\n[Column(\"Last Name\")]\n[StringLength(19)]\nIdNumber: string = null\n}") == "class Person {|    [Column(\"Last Name\")]|    [StringLength(19)]|    IdNumber: string = null|}"
}

test "parameter attributes stay INLINE with their parameter" {
    assert FstFormat("class UsersController {\nfunc Create([FromBody] [FromRoute(\"id\")] id: int, [Required] user: CreateUserRequest): IActionResult {\nreturn null\n}\n}") == "class UsersController {|    func Create([FromBody] [FromRoute(\"id\")] id: int, [Required] user: CreateUserRequest): IActionResult {|        return null|    }|}"
}

// ---- THE FILE HEAD -------------------------------------------------------------------------------

test "package, imports, and imports written before the package" {
    assert FstFormat("package MyApp.Core\n\nfunc Main() {\nprint \"hello\"\n}") == "package MyApp.Core||func Main() {|    print \"hello\"|}"
    assert FstFormat("import System.Collections.Generic\nimport System.Linq\n\nfunc Main() {\nprint \"hello\"\n}") == "import System.Collections.Generic|import System.Linq||func Main() {|    print \"hello\"|}"
    assert FstFormat("import System.Linq\n\npackage Tutorial\n\nfunc Main() {\nprint \"hello\"\n}") == "import System.Linq||package Tutorial||func Main() {|    print \"hello\"|}"
}

test "imports are sorted with the System family first, each group keeping alphabetical order" {
    assert FstFormat("import MyApp.Utils\nimport System.Linq\nimport System\nimport ThirdParty.Lib\n\nfunc Main() {\n    print \"hello\"\n}") == "import System|import System.Linq|import MyApp.Utils|import ThirdParty.Lib||func Main() {|    print \"hello\"|}"
}

// ---- COMMENTS AND BLANK LINES --------------------------------------------------------------------

test "a comment before a declaration, inside a body and between two declarations all survive" {
    assert FstFormatComments("// This is a helper function\nfunc Add(x: int, y: int): int {\n    return x + y\n}") == "// This is a helper function|func Add(x: int, y: int): int {|    return x + y|}"
    assert FstFormatComments("func Test() {\n    // Calculate result\n    x := 1 + 2\n    print x\n}") == "func Test() {|    // Calculate result|    x := 1 + 2|    print x|}"
    assert FstFormatComments("// First function\nfunc First() {\n    print 1\n}\n\n// Second function\nfunc Second() {\n    print 2\n}") == "// First function|func First() {|    print 1|}||// Second function|func Second() {|    print 2|}"
}

test "a blank line between two statements is preserved" {
    assert FstFormat("func Test() {\n    x := 1\n\n    y := 2\n    print x + y\n}") == "func Test() {|    x := 1||    y := 2|    print x + y|}"
}

test "the blank line between a header comment and a namespace FOLLOWS THE SOURCE, in both directions" {
    assert FstFormatCommentsRaw("// File header comment\n\nnamespace MyApp").Contains("// File header comment\n\nnamespace MyApp")
    assert FstFormatComments("// File header comment\nnamespace MyApp") == "// File header comment|namespace MyApp"
}

test "a lock statement with a leading comment inside it is idempotent" {
    assert FstIdempotentComments("func Decrement() {\nlock _lock {\n// parentheses optional\n_value--\n}\n}")
}

// ---- THE FILE HEAD'S OWN BLANK LINES ARE ACCOUNTED FOR ------------------------------------------
//
// `Format` writes a blank line after the namespace, after the import block and after the package
// UNCONDITIONALLY: they are the language's spelling, not the source's. Each one is an output line
// with no source line behind it, so each one advances the gap tracker
// (`FormatterWalkState.AccountForEmittedBlankLine`).
//
// WITHOUT THAT ACCOUNTING THE TRACKER LIES BY EXACTLY ONE LINE, and a file whose first comment sits
// DIRECTLY under its last import grows a blank line on every format — pass 1 writes one, pass 2
// reads the gap the blank created and writes a second. `FormatSafe`'s idempotence gate then rejects
// the file and `nlc format` refuses to touch it at all. That was true of exactly one file in the
// repository (`ColumnarIteratorPlanner.tests.nl`, whose `import System.Reflection.Emit` is followed
// on the next line by its header comment), and it was true of all three separators.
//
// The three rows below assert the FIXED POINT and the canonical text together, because the fixed
// point alone would also be satisfied by a formatter that wrote two blanks every time.

test "an import block followed IMMEDIATELY by a comment is a fixed point, at ONE blank line" {
    source := "import System\n// header\nclass C {\n}"

    assert FstFormatComments(source) == "import System||// header|class C {|}"
    assert FstIdempotentComments(source)
    assert FstSafeCommentsSuccess(source)
    assert FstSafeCommentsWarnings(source) == 0
}

test "a namespace followed IMMEDIATELY by a comment is a fixed point, at ONE blank line" {
    source := "namespace N\n// header\nclass C {\n}"

    assert FstFormatComments(source) == "namespace N||// header|class C {|}"
    assert FstIdempotentComments(source)
    assert FstSafeCommentsSuccess(source)
}

test "a package followed IMMEDIATELY by a comment is a fixed point, at ONE blank line" {
    source := "package p\n// header\nclass C {\n}"

    assert FstFormatComments(source) == "package p||// header|class C {|}"
    assert FstIdempotentComments(source)
    assert FstSafeCommentsSuccess(source)
}

// The namespace separator is read by the IMPORT loop as well as by the declaration loop, so a
// comment standing between the namespace and the first import exercises a second reader of the
// same tracker.
test "a comment between the namespace and the first import is a fixed point" {
    source := "namespace N\n// header\nimport System\nclass C {\n}"

    assert FstFormatComments(source) == "namespace N||// header|import System||class C {|}"
    assert FstIdempotentComments(source)
}

// THE TWO SPELLINGS CONVERGE, AND A WIDER GAP IS STILL PRESERVED. A source that already carries the
// blank line formats to the same text as one that does not — that is what makes the fix a
// normalisation rather than a deletion — while a source with TWO blank lines keeps both, which is
// the spelling the whole contract estate is written in and which must not move.
test "the gap between the imports and the first comment normalises to one blank and saturates at two" {
    assert FstFormatComments("import System\n\n// header\nclass C {\n}") == "import System||// header|class C {|}"
    assert FstFormatComments("import System\n\n\n// header\nclass C {\n}") == "import System|||// header|class C {|}"
    assert FstIdempotentComments("import System\n\n// header\nclass C {\n}")
    assert FstIdempotentComments("import System\n\n\n// header\nclass C {\n}")
}

// ---- OBJECT INITIALIZERS: THE ONE PLACE THE FORMATTER MEASURES A LINE ----------------------------

// A SINGLE property stays inline however long the line is — wrapping one property buys nothing.
test "a short initializer stays on one line and its empty constructor parentheses go" {
    assert FstFormat("func Test() {\n    x := new Foo() { A: 1, B: 2 }\n}") == "func Test() {|    x := new Foo { A: 1, B: 2 }|}"
    assert FstFormat("func Test() {\n    x := new SomeVeryLongTypeName() { SomeVeryLongPropertyNameThatExceedsLimit: true }\n}") == "func Test() {|    x := new SomeVeryLongTypeName { SomeVeryLongPropertyNameThatExceedsLimit: true }|}"
}

test "constructor parentheses STAY when the constructor has arguments" {
    assert FstFormat("func Test() {\n    x := new Foo(1) { A: 1 }\n}") == "func Test() {|    x := new Foo(1) { A: 1 }|}"
}

test "a long initializer wraps one property per line, and a wrapped one stays wrapped" {
    source := "func Test() {\n    options := new JsonSerializerOptions() { PropertyNameCaseInsensitive: true, PropertyNamingPolicy: someLongValue }\n}"

    assert FstFormat(source) == "func Test() {|    options := new JsonSerializerOptions {|        PropertyNameCaseInsensitive: true,|        PropertyNamingPolicy: someLongValue|    }|}"
    assert FstFormat("func Test() {\n    options := new JsonSerializerOptions() {\n        PropertyNameCaseInsensitive: true,\n        PropertyNamingPolicy: someLongValue\n    }\n}") == "func Test() {|    options := new JsonSerializerOptions {|        PropertyNameCaseInsensitive: true,|        PropertyNamingPolicy: someLongValue|    }|}"
    assert FstIdempotent(source)
}

// ---- IDEMPOTENCE: FORMATTING TWICE IS FORMATTING ONCE --------------------------------------------

// This is the property that makes `nlc format` safe to run on save: a second run must produce
// no diff. `FormatSafe`'s second gate exists to catch a violation of exactly this.
test "a function, a class with members, a union and a match are all stable under a second format" {
    assert FstIdempotent("func Add(x: int, y: int): int {\n    return x + y\n}")
    assert FstIdempotent("class Calculator {\n    func Add(x: int, y: int): int {\n        return x + y\n    }\n\n    func Sub(x: int, y: int): int {\n        return x - y\n    }\n}")
    assert FstIdempotent("union Result {\n    Success { value: int }\n    Error { message: string }\n}")
    assert FstIdempotent("func Test(x: int): string {\n    return match x {\n        0 => \"zero\",\n        1 => \"one\",\n        _ => \"other\"\n    }\n}")
}

test "every loop form is stable under a second format" {
    assert FstIdempotent("func Test() {\n    for i := 0; i < 10; i++ {\n        print i\n    }\n}")
    assert FstIdempotent("func Test(items: int[]) {\n    for item in items {\n        print item\n    }\n}")
    assert FstIdempotent("func Test() {\n    i := 0\n    while i < 10 {\n        print i\n        i = i + 1\n    }\n}")
}

// ---- THE REPARSE ROUND TRIP: THE FORMATTER'S OWN OUTPUT MUST PARSE -------------------------------

test "a union, a match and a shorthand for loop all re-parse after formatting" {
    assert FstReparseErrorsAfterFormat("union Result {\nSuccess { value: int }\nError { message: string }\n}") == 0
    assert FstReparseErrorsAfterFormat("func Test(x: int): string {\nreturn match x {\n0 => \"zero\",\n1 => \"one\",\n_ => \"other\"\n}\n}") == 0
    assert FstReparseErrorsAfterFormat("func Test() {\nfor i := 0; i < 10; i++ {\nprint i\n}\n}") == 0
}

// ---- FORMATSAFE: THE TWO GATES OVER REAL FILES ---------------------------------------------------

test "valid code comes back formatted, with no warnings" {
    assert FstSafeSuccess("func main(){print 5}")
    assert FstSafeText("func main(){print 5}").Contains("func main() {")
    assert FstSafeWarnings("func main(){print 5}") == 0
}

test "FormatSafe's output is itself a fixed point" {
    source := "func Test(x: int): string {\n    return match x {\n        0 => \"zero\",\n        _ => \"other\"\n    }\n}"

    assert FstSafeSuccess(source)
    assert FstSafeSuccess(FstSafeText(source))
    assert FstSafeIdempotent(source)
}

test "imports written before the package survive both gates and keep their order" {
    source := "import System.Threading.Tasks\n\npackage Tutorial\n\nasync func Main() {\n    await Task.Delay(10)\n}"

    assert FstSafeSuccess(source)
    assert FstSafeText(source).StartsWith("import System.Threading.Tasks", StringComparison.Ordinal)
    assert FstSafeText(source).Contains("package Tutorial")
}

// Regression bug-005 / bug-009: the formatter emitted a union-case pattern with parentheses
// instead of braces, so its own output failed the reparse gate:
// "Expected '=>'. Expected 'arrow', got '('".
test "a union-case pattern inside a match passes both gates" {
    source := "union Shape {\n    Circle { radius: float }\n    Rect { w: float, h: float }\n}\n\nfunc Describe(s: Shape): string {\n    return match s {\n        Circle { radius: r } => \"circle\",\n        Rect { w: w, h: h } => \"rect\"\n    }\n}"

    assert FstSafeSuccess(source)
    assert FstSafeSuccess(FstSafeText(source))
    assert FstSafeIdempotent(source)
}

test "a typed catch is canonicalized by FormatSafe too" {
    source := "func Test() {\n    try {\n        print \"trying\"\n    } catch (Exception ex) {\n        print ex\n    }\n}"

    assert FstSafeSuccess(source)
    assert FstSafeText(source).Contains("catch ex: Exception")
}

// Regression bug-070.
test "several pattern kinds in one match pass both gates" {
    source := "func Classify(x: int): string {\n    return match x {\n        0 => \"zero\",\n        > 0 => \"positive\",\n        _ => \"negative\"\n    }\n}"

    assert FstSafeSuccess(source)
    assert FstSafeSuccess(FstSafeText(source))
    assert FstSafeIdempotent(source)
}

// Regression bug-096: the formatter could not handle a normal real-world app.
test "a real application combining try/catch and match passes both gates" {
    source := "func ProcessRequest(req: Request): Response {\n    try {\n        result := match req.Type {\n            \"GET\" => HandleGet(req),\n            \"POST\" => HandlePost(req),\n            _ => BadRequest()\n        }\n        return result\n    } catch (HttpException ex) {\n        return ErrorResponse(ex.StatusCode)\n    } catch (Exception ex) {\n        return ErrorResponse(500)\n    }\n}"

    assert FstSafeSuccess(source)
    assert FstSafeText(source).Contains("catch ex: HttpException")
    assert FstSafeText(source).Contains("catch ex: Exception")
    assert FstSafeSuccess(FstSafeText(source))
    assert FstSafeIdempotent(source)
}

// ---- THE CONFIGURATION REACHES THE WHOLE-FILE ENTRY POINT ----------------------------------------

test "a two-space configuration and a tab configuration both reach the body" {
    assert FstFormatWith("func main(){print 5}", 2, true) == "func main() {|  print 5|}"
    assert FstFormatWith("func main(){print 5}", 4, false) == "func main() {|\tprint 5|}"
}

// ---- STRICTLY STRONGER THAN THE FILE THIS REPLACES ---------------------------------------------
//
// The deleted C# read three of its answers through SUBSTRINGS — `Assert.Contains("} catch {")`,
// `Assert.Contains("$\"\"\"")` — which cannot see what the rest of the line says. Each one is
// restated here as the WHOLE canonical text, which is the assertion the substring was reaching for.

test "the bare catch's whole canonical text, not just the substring the C# could reach" {
    assert FstFormat("func Test() {\n    try {\n        print \"trying\"\n    } catch {\n        print \"caught\"\n    }\n}") == "func Test() {|    try {|        print \"trying\"|    } catch {|        print \"caught\"|    }|}"
}

test "the raw interpolated string's whole canonical text" {
    assert FstFormat("func Test(name: string) {\n    html := $\"\"\"\n    <h1>{name}</h1>\n    \"\"\"\n}") == "func Test(name: string) {|    html := $\"\"\"|    <h1>{name}</h1>|    \"\"\"|}"
}

test "the match case list's whole canonical text, which is what the four substring reads meant" {
    assert FstFormat("func Test(x: int): string {\nreturn match x {\n0 => \"zero\",\n1 => \"one\",\n_ => \"other\"\n}\n}") == "func Test(x: int): string {|    return match x {|        0 => \"zero\",|        1 => \"one\",|        _ => \"other\"|    }|}"
}

// THE REPARSE GATE WAS ASSERTED FOR THREE SHAPES AND IS TRUE FOR EVERY SHAPE IN THIS FILE. The
// three below are the ones whose formatted output the deleted file never re-parsed at all, and each
// is a construct whose canonical spelling differs from at least one source spelling it accepts.

test "a canonicalized foreach, a canonicalized typed catch and a deconstruction all re-parse" {
    assert FstReparseErrorsAfterFormat("func Loop(items: int[]) {\nforeach item in items {\nprint item\n}\n}") == 0
    assert FstReparseErrorsAfterFormat("func Test() {\ntry {\nprint \"trying\"\n} catch (Exception e) {\nprint e\n}\n}") == 0
    assert FstReparseErrorsAfterFormat("func Test() {\n(x,y) := GetPair()\nreturn x + y\n}") == 0
}

// THE COMMENT STREAM IS LOAD-BEARING, AND THE DELETED FILE NEVER SAID SO. Every comment contract in
// it ran through the commented pipeline, so none of them could show what the other pipeline does.

test "a format given NO comment stream drops the comments, which is why the lexer run is not dead" {
    withComments := FstFormatComments("// This is a helper function\nfunc Add(x: int, y: int): int {\n    return x + y\n}")
    without := FstFormat("// This is a helper function\nfunc Add(x: int, y: int): int {\n    return x + y\n}")
    assert withComments == "// This is a helper function|func Add(x: int, y: int): int {|    return x + y|}"
    assert without == "func Add(x: int, y: int): int {|    return x + y|}"
}

// AN ATTRIBUTE WITH MORE THAN ONE ARGUMENT — THE HOLE THE MUTATION PROOF FOUND. Every attribute in
// the deleted file carried exactly ONE argument (`[Column("Last Name")]`, `[StringLength(19)]`,
// `[FromRoute("id")]`), so the separator branch inside the attribute walk was never executed by any
// contract in the estate: deleting the space after its comma changed nothing and 5,568 contracts
// stayed green. A declaration attribute and a parameter attribute are written by DIFFERENT arms,
// so both are stated.

test "an attribute with several arguments separates them with a comma and one space" {
    assert FstFormat("class Person {\n[Column(\"Last Name\",19,true)]\nIdNumber: string\n}") == "class Person {|    [Column(\"Last Name\", 19, true)]|    IdNumber: string|}"
    assert FstFormat("class UsersController {\nfunc Create([FromRoute(\"id\",1)] id: int): IActionResult {\nreturn null\n}\n}") == "class UsersController {|    func Create([FromRoute(\"id\", 1)] id: int): IActionResult {|        return null|    }|}"
}
