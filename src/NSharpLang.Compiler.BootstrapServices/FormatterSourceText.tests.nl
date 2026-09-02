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

test "a long initializer the author wrote on ONE line stays on one line, and a wrapped one stays wrapped" {
    // THIS CONTRACT USED TO SAY THE OPPOSITE, and it is the width rule's obituary. The formatter used
    // to measure the inline form against `MaxLineLength` and break this initializer apart because it
    // did not fit. It no longer measures anything: the author's line decides.
    onOneLine := "func Test() {\n    options := new JsonSerializerOptions() { PropertyNameCaseInsensitive: true, PropertyNamingPolicy: someLongValue }\n}"
    wrapped := "func Test() {\n    options := new JsonSerializerOptions() {\n        PropertyNameCaseInsensitive: true,\n        PropertyNamingPolicy: someLongValue\n    }\n}"

    assert FstFormat(onOneLine) == "func Test() {|    options := new JsonSerializerOptions { PropertyNameCaseInsensitive: true, PropertyNamingPolicy: someLongValue }|}", FstFormat(onOneLine)
    assert FstFormat(wrapped) == "func Test() {|    options := new JsonSerializerOptions {|        PropertyNameCaseInsensitive: true,|        PropertyNamingPolicy: someLongValue|    }|}", FstFormat(wrapped)
    assert FstIdempotent(onOneLine)
    assert FstIdempotent(wrapped)
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

// THIS CONTRACT USED TO ASSERT THAT THE FORMATTER NORMALISES AN ATTRIBUTE'S ARGUMENT SPACING —
// `[Column("Last Name",19,true)]` becoming `[Column("Last Name", 19, true)]`. IT NO LONGER DOES, and
// the loss of that polish is bought deliberately. Normalising means RE-RENDERING the arguments from
// the tree, and re-rendering is exactly what turned `[aotSafe(mono-wasm)]` into `[aotSafe(mono -
// wasm)]` and joined a five-line `[trusted(...)]` onto one line, taking
// `tests/native/systems-proof-corpus` to 42/44 when the `trusted` census could no longer see its
// site. There is no version of "re-render, but carefully" that survives an argument grammar the
// formatter does not own: an attribute is an ANNOTATION read by policy readers, so its interior
// belongs to the author and the formatter owns the line it starts on.
test "an attribute's interior is the author's, and the formatter owns only the line it starts on" {
    // Both attribute positions take the same span rule — on a member, and on a parameter.
    assert FstFormat("class Person {\n[Column(\"Last Name\",19,true)]\nIdNumber: string\n}") == "class Person {|    [Column(\"Last Name\",19,true)]|    IdNumber: string|}"
    assert FstFormat("class UsersController {\nfunc Create([FromRoute(\"id\",1)] id: int): IActionResult {\nreturn null\n}\n}") == "class UsersController {|    func Create([FromRoute(\"id\",1)] id: int): IActionResult {|        return null|    }|}"

    // An author who wrote the spaces keeps them, which is the same rule and not a second one.
    assert FstFormat("class Person {\n[Column(\"Last Name\", 19, true)]\nIdNumber: string\n}") == "class Person {|    [Column(\"Last Name\", 19, true)]|    IdNumber: string|}"

    // THE INDENTATION OF THE ATTRIBUTE'S OWN LINE IS STILL THE FORMATTER'S, which is the half of the
    // rule that keeps a file looking formatted at all.
    assert FstFormat("class Person {\n        [Column(\"a\")]\nIdNumber: string\n}") == "class Person {|    [Column(\"a\")]|    IdNumber: string|}"
}

// ---- THE ARGUMENT-LIST WRAPPING RULE --------------------------------------------------------------
//
// gofmt's model, author-preserving: a list written on ONE source line stays on one line however long
// (there is no width limit in the formatter); a list that SPANS more than one source line is
// canonicalised to one element per line, block indented one level, closer alone at the opening line's
// indent, and no trailing comma because N# rejects one. These contracts are stated HERE and not in
// `FormatterWalk.tests.nl` because the rule reads the SOURCE, and a hand-built tree has none.
//
// EVERY SOURCE BELOW IS INDENTED, AND THAT IS LOAD-BEARING RATHER THAN COSMETIC. The parser ends an
// argument list at a continuation token sitting at or left of the statement's recovery boundary column
// (`IsContinuationRecoveryBoundary`), so a wrapped element must be strictly right of the line that
// opened the list. The canonical shape always is — it indents one level past the opening line — which
// is why the formatter can never emit a wrap the parser then refuses to read back.

test "a call argument list written on one line stays on one line, however long" {
    long := "func Test() {\n    x := Compute(alpha, beta, gamma, delta, epsilon, zeta, eta, theta, iota, kappa, lambda, mu)\n}"
    assert FstFormat(long) == "func Test() {|    x := Compute(alpha, beta, gamma, delta, epsilon, zeta, eta, theta, iota, kappa, lambda, mu)|}", FstFormat(long)
    assert FstIdempotent(long)
}

test "a call argument list the author wrapped becomes one argument per line with the closer alone" {
    source := "func Test() {\n    x := Foo(\n        a,\n        b\n    )\n}"
    assert FstFormat(source) == "func Test() {|    x := Foo(|        a,|        b|    )|}", FstFormat(source)
    assert FstIdempotent(source)
}

test "arguments that shared a line inside a wrapped list are given a line each" {
    source := "func Test() {\n    x := Foo(a, b,\n        c)\n}"
    assert FstFormat(source) == "func Test() {|    x := Foo(|        a,|        b,|        c|    )|}", FstFormat(source)
    assert FstIdempotent(source)
}

test "a closing parenthesis left on its own line is an author line break and is preserved as a wrap" {
    // The rule is delimiter-to-delimiter, not element-to-element: this list spans two source lines
    // even though both arguments fit on the opening one.
    source := "func Test() {\n    x := Foo(a, b\n    )\n}"
    assert FstFormat(source) == "func Test() {|    x := Foo(|        a,|        b|    )|}", FstFormat(source)
    assert FstIdempotent(source)
}

test "an empty argument list stays empty on one line" {
    source := "func Test() {\n    x := Foo(\n    )\n}"
    assert FstFormat(source) == "func Test() {|    x := Foo()|}", FstFormat(source)
}

test "the named and out spellings survive a wrap" {
    source := "func Test(a: int) {\n    Foo(\n        name: 1,\n        out a,\n        b\n    )\n}"
    assert FstFormat(source) == "func Test(a: int) {|    Foo(|        name: 1,|        out a,|        b|    )|}", FstFormat(source)
    assert FstIdempotent(source)
}

test "a REF argument keeps its list on one line, because `ref` cannot begin a continuation line" {
    // `ref` is a DECLARATION keyword, and the parser ends an argument list at a continuation token
    // that starts a declaration. Wrapping this list would put `ref b` at the head of a line and the
    // output would not re-parse — at which point `FormatSafe` returns the original source and the
    // file silently stops being formatted at all. The wrap is refused instead; nothing is lost.
    source := "func Test(a: int, b: int) {\n    Foo(a, ref b\n    )\n}"
    assert FstFormat(source) == "func Test(a: int, b: int) {|    Foo(a, ref b)|}", FstFormat(source)
    assert FstIdempotent(source)
    assert FstReparseErrorsAfterFormat(source) == 0
}

// NESTING. A wrapped inner list pushes the outer closer onto a later line, so the outer wraps too —
// EXCEPT for the hug, where every outer element starts on the opening line and the last one is the
// wrapped list. Both shapes are idempotent, which is the property the whole rule turns on.

test "a wrapped call hugs when it is the last argument and every argument starts on the opening line" {
    source := "func Test() {\n    x := Foo(a, Bar(\n        b\n    ))\n}"
    assert FstFormat(source) == "func Test() {|    x := Foo(a, Bar(|        b|    ))|}", FstFormat(source)
    assert FstIdempotent(source)
}

test "a wrapped call that is NOT the last argument makes the outer list wrap too" {
    source := "func Test() {\n    x := Foo(Bar(\n        b\n    ), c)\n}"
    assert FstFormat(source) == "func Test() {|    x := Foo(|        Bar(|            b|        ),|        c|    )|}", FstFormat(source)
    assert FstIdempotent(source)
}

test "a block-bodied lambda hugs the call that holds it — the callback shape" {
    // THIS IS THE CASE THAT CAUGHT THE FIRST VERSION OF THE RULE. `Task.Run(() => { … })` spans lines
    // because the lambda's BODY does, not because anything is a wrapped list, and an exemption that
    // only knew about lists tore every callback in the estate into five lines.
    source := "func Test() {\n    t := Task.Run(() => {\n        Work()\n    })\n}"
    assert FstFormat(source) == "func Test() {|    t := Task.Run(() => {|        Work()|    })|}", FstFormat(source)
    assert FstIdempotent(source)
}

test "a lambda hugs even with arguments before it, and does not when the author broke the list" {
    hugged := "func Test() {\n    Run(items, x => {\n        Work(x)\n    })\n}"
    assert FstFormat(hugged) == "func Test() {|    Run(items, x => {|        Work(x)|    })|}", FstFormat(hugged)
    assert FstIdempotent(hugged)

    // The author put the first argument on its own line, so the list is wrapped and the lambda goes
    // with it. The hug only ever protects a list the author kept on the opening line.
    broken := "func Test() {\n    Run(\n        items,\n        x => {\n            Work(x)\n        }\n    )\n}"
    assert FstFormat(broken) == "func Test() {|    Run(|        items,|        x => {|            Work(x)|        }|    )|}", FstFormat(broken)
    assert FstIdempotent(broken)
}

test "a match expression hugs the call that holds it" {
    source := "func Test(x: int) {\n    Show(match x {\n        0 => \"zero\",\n        _ => \"other\"\n    })\n}"
    assert FstFormat(source) == "func Test(x: int) {|    Show(match x {|        0 => \"zero\",|        _ => \"other\"|    })|}", FstFormat(source)
    assert FstIdempotent(source)
}

test "an object initializer hugs the call that holds it" {
    source := "func Test() {\n    x := Add(new Foo {\n        A: 1\n    })\n}"
    assert FstFormat(source) == "func Test() {|    x := Add(new Foo {|        A: 1|    })|}", FstFormat(source)
    assert FstIdempotent(source)
}

// THE TWO LISTS A `new` CARRIES ARE INDEPENDENT. The initializer is anchored on its OWN braces, so a
// wrapped constructor argument list does not drag a one-line initializer apart, and the reverse.

test "a wrapped constructor argument list leaves a one-line initializer on one line" {
    source := "func Test() {\n    x := new Foo(\n        a\n    ) { X: 1 }\n}"
    assert FstFormat(source) == "func Test() {|    x := new Foo(|        a|    ) { X: 1 }|}", FstFormat(source)
    assert FstIdempotent(source)
}

test "a wrapped initializer leaves a one-line constructor argument list on one line" {
    source := "func Test() {\n    x := new Foo(a) {\n        X: 1\n    }\n}"
    assert FstFormat(source) == "func Test() {|    x := new Foo(a) {|        X: 1|    }|}", FstFormat(source)
    assert FstIdempotent(source)
}

test "an object initializer written on one line stays on one line, however long" {
    long := "func Test() {\n    x := new Foo { Alpha: 1, Beta: 2, Gamma: 3, Delta: 4, Epsilon: 5, Zeta: 6, Eta: 7, Theta: 8 }\n}"
    assert FstFormat(long) == "func Test() {|    x := new Foo { Alpha: 1, Beta: 2, Gamma: 3, Delta: 4, Epsilon: 5, Zeta: 6, Eta: 7, Theta: 8 }|}", FstFormat(long)
    assert FstIdempotent(long)
}

test "an array literal follows the same rule in both directions" {
    flat := "func Test() {\n    xs := [1, 2, 3]\n}"
    wrapped := "func Test() {\n    xs := [\n        1,\n        2\n    ]\n}"
    assert FstFormat(flat) == "func Test() {|    xs := [1, 2, 3]|}", FstFormat(flat)
    assert FstFormat(wrapped) == "func Test() {|    xs := [|        1,|        2|    ]|}", FstFormat(wrapped)
    assert FstIdempotent(wrapped)
}

// PARAMETER LISTS. A declaration's `(` and `)` belong to the declaration and are not stamped, so the
// test here is the ELEMENTS: a parameter below the declaration's own line is a wrapped list.

test "a parameter list the author wrapped becomes one parameter per line" {
    source := "func Test(\n    a: int,\n    b: string\n) {\n}"
    assert FstFormat(source) == "func Test(|    a: int,|    b: string|) {|}", FstFormat(source)
    assert FstIdempotent(source)
}

test "a parameter list on one line stays on one line, however long" {
    long := "func Test(alpha: int, beta: int, gamma: int, delta: int, epsilon: int, zeta: int, eta: int) {\n}"
    assert FstFormat(long) == "func Test(alpha: int, beta: int, gamma: int, delta: int, epsilon: int, zeta: int, eta: int) {|}", FstFormat(long)
}

test "a constructor's parameter list wraps by the same rule" {
    source := "class Box {\n    constructor(\n        a: int,\n        b: int\n    ) {\n    }\n}"
    assert FstFormat(source) == "class Box {|    constructor(|        a: int,|        b: int|    ) {|    }|}", FstFormat(source)
    assert FstIdempotent(source)
}

// COMMENTS. A comment inside a list cannot be written on one line, so it FORCES the wrap and is
// emitted on a line of its own above the element that follows it — which is where the formatter's
// leading-comment model puts every other comment in the file.

test "a comment between two arguments is kept, on its own line, above the argument it preceded" {
    source := "func Test() {\n    x := Foo(\n        // why\n        a,\n        b\n    )\n}"
    assert FstFormatComments(source) == "func Test() {|    x := Foo(|        // why|        a,|        b|    )|}", FstFormatComments(source)
    assert FstIdempotentComments(source)
}

test "a comment after the last argument is kept above the closing delimiter" {
    source := "func Test() {\n    x := Foo(\n        a\n        // trailing\n    )\n}"
    assert FstFormatComments(source) == "func Test() {|    x := Foo(|        a|        // trailing|    )|}", FstFormatComments(source)
    assert FstIdempotentComments(source)
}

test "a comment inside a HUGGED inner list is kept, and the hug still holds" {
    // THE FIRST VERSION OF THIS CONTRACT ASSERTED THE OPPOSITE — that a comment anywhere between the
    // two delimiters forced the outer list to wrap. That clause was wrong: it could not tell a comment
    // standing between two ARGUMENTS from one inside a nested block, and it tore a hugged callback
    // apart in `examples/17-issue-tracker`. The comment belongs to the inner list and the inner list
    // emits it; nothing about the outer list changes.
    source := "func Test() {\n    x := Foo(a, Bar( // why\n        b\n    ))\n}"
    assert FstFormatComments(source) == "func Test() {|    x := Foo(a, Bar(|        // why|        b|    ))|}", FstFormatComments(source)
    assert FstIdempotentComments(source)
}

test "a comment inside a hugged lambda body stays put, and the callback keeps hugging" {
    // The exact shape that caught the clause: a comment inside the block body of a hugged lambda.
    source := "func Test() {\n    Run(items, x => {\n        // why\n        Work(x)\n    })\n}"
    assert FstFormatComments(source) == "func Test() {|    Run(items, x => {|        // why|        Work(x)|    })|}", FstFormatComments(source)
    assert FstIdempotentComments(source)
}

// ---- ATTRIBUTES ARE ANNOTATIONS, AND THE FORMATTER WRITES THEM BACK VERBATIM ---------------------
//
// THE DEFECT THESE STATE BROKE A PRODUCT CONTRACT, NOT JUST A SPELLING. Re-rendering an attribute
// from `AttributeNode.Name` + `Arguments` loses two different things, and the estate reformat lost
// both in the same pass:
//
//   * AN ARGUMENT IS STORED AS AN EXPRESSION. `[aotSafe(mono-wasm)]` parses as a subtraction, so it
//     was written back as `[aotSafe(mono - wasm)]` — a policy token turned into arithmetic.
//   * THE NODE HOLDS NO LINE STRUCTURE. A `[trusted(...)]` written over five lines was joined onto
//     one, and `tests/native/systems-proof-corpus` fell to 42/44 because the `trusted` census could
//     no longer see the site it was asserting on.
//
// The named-argument spelling was wrong as well, and the comment in the walk asserted the error was
// deliberate: `ParseAttributes` parses its arguments with the same `ParseArgumentList()` a call uses,
// so `name: value` is the grammar and every ` = ` the formatter wrote was output no parser could have
// produced. The fix is one rule that covers all three and every future member of the class — emit the
// `[`-to-`]` span the parser stamped, and normalise only the indentation of the line it starts on.

test "a multi-line attribute keeps every line the author wrote" {
    // The exact shape from `docs/design/systems-samples/proofs/45-trusted-audit/Program.nl`, which
    // this reformat joined onto one line.
    source := "class C {\n    [memory(safe)]\n    [trusted(\n        reason: \"handle is never exposed\",\n        owner: \"interop\",\n        review: \"2026-12-01\",\n        expires: \"2027-06-01\"\n    )]\n    static func Wrap(): int {\n        return 1\n    }\n}"
    assert FstFormatRaw(source) == source, FstFormatRaw(source)
    assert FstSafeSuccess(source)
    assert FstIdempotent(source)
}

test "an attribute argument that only looks like an expression is not re-rendered as one" {
    // `mono-wasm` is a policy token. It PARSES as `mono - wasm`, and every re-render from the tree
    // writes the spaces back in.
    source := "class C {\n    [hot]\n    [aotSafe(mono-wasm)]\n    static func Run(): int {\n        return 1\n    }\n}"
    assert FstFormatRaw(source) == source, FstFormatRaw(source)

    // The single-argument policy attributes the systems corpus is built from, unchanged.
    memory := "class C {\n    [memory(safe)]\n    static func Run(): int {\n        return 1\n    }\n}"
    assert FstFormatRaw(memory) == memory, FstFormatRaw(memory)

    bare := "class C {\n    [hot]\n    static func Run(): int {\n        return 1\n    }\n}"
    assert FstFormatRaw(bare) == bare, FstFormatRaw(bare)

    assert FstIdempotent(source)
    assert FstIdempotent(memory)
}

test "a named attribute argument keeps the colon the parser reads, and an equals sign is not a named argument" {
    // `:` is the named-argument spelling in an attribute exactly as in a call, because it is the same
    // `ParseArgumentList`.
    named := "class C {\n    [Name(a, b: c)]\n    static func Run(): int {\n        return 1\n    }\n}"
    assert FstFormatRaw(named) == named, FstFormatRaw(named)

    // `b = c` is NOT the named form — it parses as an ASSIGNMENT EXPRESSION in argument position, and
    // the analyzer rejects it (NL310, "attribute arguments must be compile-time constants"). It is
    // written here only to state what the span rule guarantees: whatever the author wrote comes back,
    // including a shape the formatter has no opinion about.
    assigned := "class C {\n    [Name(a, b = c)]\n    static func Run(): int {\n        return 1\n    }\n}"
    assert FstFormatRaw(assigned) == assigned, FstFormatRaw(assigned)
}

// ---- RAW STRING LITERALS: THE SPELLING IS THE VALUE ----------------------------------------------
//
// THE DEFECT THESE STATE WAS SILENT DATA LOSS, NOT A DECLINE, AND IT REACHED USERS THROUGH
// FORMAT-ON-SAVE. `Lexer.ReadTripleQuoteString` consumes both `"""` delimiters and appends neither,
// so a raw literal's `StringLiteralExpression.Value` is the bare content — and the formatter wrote
// that content back. Wherever the content is itself a legal expression, BOTH of `FormatSafe`'s gates
// pass and the file is rewritten: `v := """abc"""` became `v := abc` on disk, and
// `DocumentFormattingHandler` calls the same `FormatSafe`, so an editor save did it too. Only where
// the bare content failed to re-read did the reparse gate catch it, which is why the whole visible
// symptom was eight declining files rather than a corpus of quietly broken strings.
//
// EVERY ASSERTION BELOW IS AN EXACT ROUND TRIP. That is the contract worth having: a raw literal's
// content is significant to the byte, so "the formatter did not change it" is the only correct
// answer, and `IsRaw` + verbatim re-emission is what produces it.

test "a single-line raw string literal keeps its delimiters in every position it can stand in" {
    // The four shapes that were REWRITTEN rather than declined. Each is its own position in the
    // expression walk, and each one emitted a bare identifier before.
    declaration := "func Test() {\n    v := \"\"\"abc\"\"\"\n}"
    assert FstFormat(declaration) == "func Test() {|    v := \"\"\"abc\"\"\"|}", FstFormat(declaration)

    argument := "func Test() {\n    Use(\"\"\"abc\"\"\")\n}"
    assert FstFormat(argument) == "func Test() {|    Use(\"\"\"abc\"\"\")|}", FstFormat(argument)

    returned := "func Test(): string {\n    return \"\"\"abc\"\"\"\n}"
    assert FstFormat(returned) == "func Test(): string {|    return \"\"\"abc\"\"\"|}", FstFormat(returned)

    operand := "func Test(): string {\n    return \"a\" + \"\"\"b\"\"\"\n}"
    assert FstFormat(operand) == "func Test(): string {|    return \"a\" + \"\"\"b\"\"\"|}", FstFormat(operand)

    // Both of `FormatSafe`'s gates, and the format-twice property the corpus sweep assumes.
    assert FstSafeSuccess(declaration)
    assert FstSafeSuccess(argument)
    assert FstSafeSuccess(returned)
    assert FstSafeSuccess(operand)
    assert FstIdempotent(declaration)
    assert FstIdempotent(returned)
}

test "a multi-line raw string literal keeps its newlines and its indentation, and the statement after it keeps its own spacing" {
    // N# raw strings do NOT strip a common indent — the content is everything between the
    // delimiters — so the interior lines come back at column 0 and the indented one keeps its two
    // spaces. Re-synthesising the literal from a decoded value could not produce this.
    source := "func Test(): string {\n    v := \"\"\"\nline one\n  indented\n\"\"\"\n    return v\n}"
    assert FstFormat(source) == "func Test(): string {|    v := \"\"\"|line one|  indented|\"\"\"|    return v|}", FstFormat(source)
    assert FstSafeSuccess(source)
    assert FstIdempotent(source)

    // AND NO BLANK LINE APPEARS ABOVE `return v`. The literal is one token spanning four lines, so a
    // statement `EndLine` stamped from the token's START line made the next statement look like it
    // stood across a gap; the formatter then wrote a blank the author never had, on every format.
    // `TokenEndLine` is what makes this an exact round trip rather than a growing file.
    interpolated := "func Test(x: int): string {\n    v := $\"\"\"\nline {x}\n\"\"\"\n    return v\n}"
    assert FstFormat(interpolated) == "func Test(x: int): string {|    v := $\"\"\"|line {x}|\"\"\"|    return v|}", FstFormat(interpolated)
    assert FstIdempotent(interpolated)
}

test "the lexer ends a raw literal at the FIRST triple quote, and the formatter writes exactly that back" {
    // THERE IS NO FOUR-OR-MORE-DELIMITER FORM IN N#, and this is the contract to write instead of
    // one. `ReadTripleQuoteString` returns at the first `"""` it sees, so a literal's content
    // provably contains no `"""` and provably does not END in a quote — which is exactly what makes
    // `"""` + content + `"""` an exact reconstruction rather than a re-spelling.
    one := "func Test(): string {\n    return \"\"\"he said \"hi\" ok\"\"\"\n}"
    assert FstFormat(one) == "func Test(): string {|    return \"\"\"he said \"hi\" ok\"\"\"|}", FstFormat(one)

    // AND THE CONTENT CANNOT END IN A QUOTE, which is the same fact seen from the other side: the
    // fourth quote of `"""he said "hi""""` closes the literal and the last one is left over, so the
    // file does not lex. That is the guarantee the re-emission rests on — there is no content the
    // formatter can be handed for which `"""` + content + `"""` is ambiguous.
    unterminated := "func Test(): string {\n    return \"\"\"he said \"hi\"\"\"\"\n}"
    assert FstReparseErrors(unterminated) > 0

    two := "func Test(): string {\n    return \"\"\"a \"\"b\"\"\"\n}"
    assert FstFormat(two) == "func Test(): string {|    return \"\"\"a \"\"b\"\"\"|}", FstFormat(two)

    // A fourth opening quote is not a longer delimiter: three open the literal and the fourth is the
    // first character of its content.
    four := "func Test(): string {\n    return \"\"\"\"abc\"\"\"\n}"
    assert FstFormat(four) == "func Test(): string {|    return \"\"\"\"abc\"\"\"|}", FstFormat(four)

    assert FstSafeSuccess(one)
    assert FstSafeSuccess(two)
    assert FstSafeSuccess(four)
}

test "a multi-line raw literal inside a wrapped argument list survives the wrap verbatim" {
    // The shape of all seven raw-string decliners: a fixture source handed to a compile helper. The
    // wrapping rule reshapes the CALL because its `)` is below its `(`; the literal's own lines are
    // inside one token and the walk does not touch them.
    source := "func Test() {\n    Compile(\n        \"\"\"\nclass C {\n    func Go(): int {\n        return 1\n    }\n}\n\"\"\"\n    )\n}"
    assert FstSafeSuccess(source)
    assert FstIdempotent(source)
    assert FstReparseErrorsAfterFormat(source) == 0
    assert FstFormatRaw(source).Contains("\"\"\"\nclass C {\n    func Go(): int {\n        return 1\n    }\n}\n\"\"\"")
}

test "let is preserved where the author wrote it and supplied where the parser needs it" {
    // PRESERVATION. `let x: T = v` and the bare `x: T = v` are the same `VariableKind.Let`, so
    // without `HasLetKeyword` the keyword was simply deleted from every file that used it.
    written := "func Test(): int {\n    let n: int = 3\n    return n\n}"
    assert FstFormat(written) == "func Test(): int {|    let n: int = 3|    return n|}", FstFormat(written)

    // AND THE BARE SPELLING STAYS BARE. `let` is not canonicalisation: the estate is written without
    // it and must not churn.
    bare := "func Test(): int {\n    n: int = 3\n    return n\n}"
    assert FstFormat(bare) == "func Test(): int {|    n: int = 3|    return n|}", FstFormat(bare)

    // SOUNDNESS. `ParseExpressionStatement`'s no-`let` arm needs the type to open on an IDENTIFIER
    // token, so a tuple type — which opens on `(` — cannot be written without the keyword. Dropping
    // it produced `Unexpected token ':' in expression` and the whole file stopped being formatted.
    tuple := "func Test(): int {\n    let pair: (x: int, y: int) = (1, 2)\n    return pair.x\n}"
    assert FstFormat(tuple) == "func Test(): int {|    let pair: (x: int, y: int) = (1, 2)|    return pair.x|}", FstFormat(tuple)
    assert FstSafeSuccess(tuple)
    assert FstReparseErrorsAfterFormat(tuple) == 0

    // The same arm requires an `=` after the type, so a typed declaration with NO initializer is the
    // second member of that family and equally unwritable without `let`.
    uninitialized := "func Test(): int {\n    let n: int\n    n = 3\n    return n\n}"
    assert FstFormat(uninitialized) == "func Test(): int {|    let n: int|    n = 3|    return n|}", FstFormat(uninitialized)
    assert FstReparseErrorsAfterFormat(uninitialized) == 0

    assert FstIdempotent(written)
    assert FstIdempotent(bare)
    assert FstIdempotent(tuple)
}

test "a numeric literal comes back spelled the way the author wrote it, separators included" {
    // THE SAME DEFECT CLASS AS THE RAW STRING, WITH A QUIETER SYMPTOM. `Lexer.ReadNumber` drops every
    // `_` so the value it hands on is a numeral `Parse` accepts; the formatter wrote that value back,
    // so `2_147_483_647` came out as `2147483647`. The program is identical and the author's source is
    // gone — and because it re-parses and is idempotent, no gate ever objected. It surfaced only when
    // `tests/native/scalar-code-plan/ScalarCodePlan.tests.nl` stopped declining on its raw string and
    // became formattable for the first time; that file holds the estate's only bare separated
    // numerals, one of them in a function named `ReturnSeparatedMinimumIntLiteral`.
    decimalLiteral := "func Test(): int {\n    return 2_147_483_647\n}"
    assert FstFormat(decimalLiteral) == "func Test(): int {|    return 2_147_483_647|}", FstFormat(decimalLiteral)

    hex := "func Test(): int {\n    return 0x7fff_ffff\n}"
    assert FstFormat(hex) == "func Test(): int {|    return 0x7fff_ffff|}", FstFormat(hex)

    binary := "func Test(): int {\n    return 0b1010_0101\n}"
    assert FstFormat(binary) == "func Test(): int {|    return 0b1010_0101|}", FstFormat(binary)

    floating := "func Test(): double {\n    return 1_2.5_0e1D\n}"
    assert FstFormat(floating) == "func Test(): double {|    return 1_2.5_0e1D|}", FstFormat(floating)

    // A separated literal in an index-from-end, which reaches the same node through a different arm.
    indexed := "func Test(values: int[]): int {\n    return values[^1_0]\n}"
    assert FstFormat(indexed) == "func Test(values: int[]): int {|    return values[^1_0]|}", FstFormat(indexed)

    // AND AN UNSEPARATED NUMERAL IS UNTOUCHED — the spelling is null and the value is written, which
    // is the arm every other file in the estate takes.
    plain := "func Test(): int {\n    return 2147483647\n}"
    assert FstFormat(plain) == "func Test(): int {|    return 2147483647|}", FstFormat(plain)

    assert FstIdempotent(decimalLiteral)
    assert FstIdempotent(floating)
    assert FstSafeSuccess(decimalLiteral)
    assert FstSafeSuccess(floating)
}
