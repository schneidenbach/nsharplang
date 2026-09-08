namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.IO

// These are the complete emitted-runtime assertions formerly hosted by the 40 successful
// MultiFileCompiler facts in CompilationBackendTests.cs. Every fixture still enters through the
// public MultiFileCompiler API, writes its runtime config with the N# owner, executes the emitted
// assembly through the N# DotnetRunner, and cleans its project directory in a finally block.

test "MultiFileCompiler_CanCompileExecutableProjectToIlAndRun" {
    fileNames := new string[](2)
    contents := new string[](2)
    fileNames[0] = "Program.nl"
    contents[0] = "func main() {\n    print Greeting()\n}"
    fileNames[1] = "Greeting.nl"
    contents[1] = "func Greeting(): string {\n    return \"hello from il backend\"\n}"
    compilation := EmitterCanonicalCompile(
        "IlProject",
        EmitterCanonicalProjectYml("IlProject", "exe"),
        fileNames,
        contents,
        false
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        assert Convert.ToString(compilation.OutputAssemblyPath) == compilation.OutputPath
        assert File.Exists(compilation.OutputPath)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stderr
        assert run.Stdout.Contains("hello from il backend", StringComparison.Ordinal), run.Stdout
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "RecordStruct_EqualityOperators_UseStructuralEquality" {
    compilation := EmitterCanonicalCompileSingle(
        "RecordStructEquality",
        "exe",
        """
record struct Named(id: int, name: string) {
}

func main(): void {
    a := new Named(1, "x")
    b := new Named(1, "x")
    c := new Named(2, "x")
    print $"a.Equals(c)={a.Equals(c)}"
    print $"a==c={a == c}"
    print $"a==b={a == b}"
    print $"a!=c={a != c}"
    print $"a!=b={a != b}"
}
"""
    )
    try {
        assert compilation.Succeeded, EmitterCanonicalDiagnostics(compilation)
        run := EmitterCanonicalRun(compilation)
        assert run.ExitCode == 0, run.Stderr
        assert run.Stdout.Contains("a.Equals(c)=False", StringComparison.Ordinal)
        assert run.Stdout.Contains("a==c=False", StringComparison.Ordinal)
        assert run.Stdout.Contains("a==b=True", StringComparison.Ordinal)
        assert run.Stdout.Contains("a!=c=True", StringComparison.Ordinal)
        assert run.Stdout.Contains("a!=b=False", StringComparison.Ordinal)
    } finally {
        EmitterCanonicalCleanup(compilation)
    }
}

test "MultiFileCompiler_AllowsIdentifierCallsToMethodsOnCurrentType" {
    EmitterCanonicalAssertProgramContains(
        "CurrentTypeCalls",
        """
class MathUtils {
    static func Factorial(n: int): long {
        if n <= 1 {
            return 1
        }

        return n * Factorial(n - 1)
    }
}

func main() {
    print MathUtils.Factorial(5)
}
""",
        "120"
    )
}

test "MultiFileCompiler_CanBuildPackageFirstSourceWithImports" {
    EmitterCanonicalAssertProgramContains(
        "PackageFirstIlProject",
        """
package PackageFirst

import System

func main() {
    print DateTime.UnixEpoch.Year
}
""",
        "1970"
    )
}

test "MultiFileCompiler_CanBuildPackagedNewtypeCallStyleConstruction" {
    EmitterCanonicalAssertProgramContains(
        "NewtypeProject",
        """
package NewtypeProject

type UserId = newtype int

func main() {
    id := UserId(42)
    print id.Value
}
""",
        "42"
    )
}

test "MultiFileCompiler_CanConstructNewtypeThroughFileImportAliasWithCallStyle" {
    fileNames := new string[](2)
    contents := new string[](2)
    fileNames[0] = "ids.nl"
    contents[0] = """
package ids

type UserId = newtype int
"""
    fileNames[1] = "Program.nl"
    contents[1] = """
import "ids" as Ids

func main() {
    id := Ids.UserId(42)
    print id.Value
}
"""
    EmitterCanonicalAssertProgramFilesContain("AliasNewtypeCallStyleProject", fileNames, contents, "42")
}

test "MultiFileCompiler_CanConstructNewtypeThroughFileImportAliasWithNew" {
    fileNames := new string[](2)
    contents := new string[](2)
    fileNames[0] = "ids.nl"
    contents[0] = """
package ids

type UserId = newtype int
"""
    fileNames[1] = "Program.nl"
    contents[1] = """
import "ids" as Ids

func main() {
    id := new Ids.UserId(42)
    print id.Value
}
"""
    EmitterCanonicalAssertProgramFilesContain("AliasNewtypeNewProject", fileNames, contents, "42")
}

test "MultiFileCompiler_CanRunExecutableProjectWithTypeScopedMainEntryPoint" {
    EmitterCanonicalAssertProgramContains(
        "TypeMainProject",
        """
import System

class Program {
    static func Main() {
        print DateTime.UnixEpoch.Year
    }
}
""",
        "1970"
    )
}

test "MultiFileCompiler_CanRunRepeatedBlockLocalWithNamespaceQualifiedType" {
    fileNames := new string[](3)
    contents := new string[](3)
    fileNames[0] = "Models.nl"
    contents[0] = """
namespace RepeatedLocal.Models

record Item {
    Name: string
}
"""
    fileNames[1] = "Services.nl"
    contents[1] = """
namespace RepeatedLocal.Services

import System.Collections.Generic
import System.Linq
import RepeatedLocal.Models

class ItemService {
    items: List<Item>

    constructor() {
        items = new List<Item>()
        items.Add(new Item { Name: "first" })
        items.Add(new Item { Name: "second" })
    }

    func Filter(firstPass: bool, name: string): List<Item> {
        result := items.ToList()

        if firstPass {
            filtered := new List<Item>()
            for item in result {
                filtered.Add(item)
            }

            result = filtered
        }

        normalized := name.ToLower()
        if normalized.Length > 0 {
            filtered := new List<Item>()
            for item in result {
                if item.Name == normalized {
                    filtered.Add(item)
                }
            }

            result = filtered
        }

        return result
    }
}
"""
    fileNames[2] = "Program.nl"
    contents[2] = """
import RepeatedLocal.Services

func main() {
    service := new ItemService()
    print service.Filter(false, "SECOND").Count
}
"""
    EmitterCanonicalAssertProgramFilesContain("RepeatedLocalIlProject", fileNames, contents, "1")
}

test "MultiFileCompiler_EmitsArrayListPatterns" {
    EmitterCanonicalAssertProgramNormalized(
        "ArrayListPatternProject",
        """
func Describe(values: int[]): string {
    result := match values {
        [] => "empty",
        [single] => $"one:{single}",
        [a, b] => $"pair:{a}:{b}",
        [first, .. middle, last] when first == last => $"same:{middle.Length}",
        [first, .. middle, last] => $"range:{first}:{middle.Length}:{last}",
        _ => "other"
    }

    return result
}

func main() {
    print Describe([])
    print Describe([9])
    print Describe([1, 2])
    print Describe([1, 2, 3, 4])
    print Describe([5, 6, 5])
}
""",
        "empty\none:9\npair:1:2\nrange:1:2:4\nsame:1"
    )
}

test "MultiFileCompiler_EmitsBareInstancePropertyAssignmentInMethods" {
    EmitterCanonicalAssertProgramTrimmed(
        "BarePropertyAssignmentProject",
        """
class Account {
    balance: double

    Balance: double {
        get { return balance }
        set { balance = value }
    }

    constructor(initial: double) {
        balance = initial
    }

    func Deposit(amount: double) {
        Balance = Balance + amount
    }
}

func main() {
    account := new Account(100.0)
    account.Deposit(25.0)
    print account.Balance
}
""",
        "125"
    )
}

test "MultiFileCompiler_EmitsBaseMethodCallsInInterpolatedStrings" {
    EmitterCanonicalAssertProgramNormalized(
        "BaseInterpolationProject",
        """
class Person {
    readonly Name: string

    constructor(name: string) {
        Name = name
    }

    func Info(): string {
        return $"person:{Name}"
    }
}

class Employee: Person {
    readonly Id: string

    constructor(name: string, id: string): base(name) {
        Id = id
    }

    func Label(): string {
        return $"{base.Info()}:{Id}"
    }
}

func main() {
    employee := new Employee("Ada", "E-1")
    print employee.Label()
}
""",
        "person:Ada:E-1"
    )
}

test "MultiFileCompiler_EmitsCheckedUncheckedArithmetic" {
    EmitterCanonicalAssertProgramTrimmed(
        "CheckedUncheckedArithmetic",
        """
func main() {
    max := 2147483647
    print unchecked(max + 1)

    try {
        overflow := checked(max + 1)
        print overflow
    } catch ex: OverflowException {
        print "overflow"
    }

    print checked((100 + 50) * 2 - 25)
}
""",
        "-2147483648\noverflow\n275"
    )
}

test "MultiFileCompiler_EmitsConcreteTypeBindingPatterns" {
    EmitterCanonicalAssertProgramNormalized(
        "ConcreteTypePatternProject",
        """
func ClassifyString(value: string): string {
    result := match value {
        string s when s.Length == 0 => "empty",
        string s when s.Length > 10 => "long",
        string s => $"short:{s}"
    }

    return result
}

func ClassifyNumber(value: int): string {
    result := match value {
        int n when n < 0 => "negative",
        int n when n == 0 => "zero",
        int n => $"positive:{n}"
    }

    return result
}

func CheckValue(value: string): string {
    result := match value {
        "special" => "special",
        string s when s.StartsWith("ERR") => "error",
        string s => $"regular:{s}"
    }

    return result
}

func main() {
    print ClassifyString("")
    print ClassifyString("abc")
    print ClassifyString("this is long")
    print ClassifyNumber(-5)
    print ClassifyNumber(0)
    print ClassifyNumber(12)
    print CheckValue("special")
    print CheckValue("ERR42")
    print CheckValue("ok")
}
""",
        "empty\nshort:abc\nlong\nnegative\nzero\npositive:12\nspecial\nerror\nregular:ok"
    )
}

test "MultiFileCompiler_EmitsExpandedParamsCollections" {
    EmitterCanonicalAssertProgramNormalized(
        "ExpandedParamsCollectionsProject",
        """
import System.Collections.Generic

func SumArray(params numbers: int[]): int {
    total := 0
    for number in numbers {
        total = total + number
    }
    return total
}

func SumReadOnlySpan(params numbers: ReadOnlySpan<int>): int {
    total := 0
    for i := 0; i < numbers.Length; i++ {
        total = total + numbers[i]
    }
    return total
}

func CountAll(params items: IEnumerable<string>): int {
    count := 0
    for item in items {
        count = count + 1
    }
    return count
}

func FormatItems(separator: string, params items: IReadOnlyList<string>): string {
    result := items[0]
    for i := 1; i < items.Count; i++ {
        result = result + separator + items[i]
    }
    return result
}

func BuildList(params items: List<int>): List<int> {
    return items
}

func main() {
    print SumArray(1, 2, 3)
    print SumArray()
    print SumReadOnlySpan(4, 5, 6)
    print CountAll("a", "b", "c")
    print FormatItems("-", "left", "right")
    list := BuildList(10, 20, 30)
    print list.Count
}
""",
        "6\n0\n15\n3\nleft-right\n3"
    )
}

test "MultiFileCompiler_EmitsExplicitGenericJsonSerializerSerialize" {
    EmitterCanonicalAssertProgramNormalized(
        "GenericJsonSerializeProject",
        """
import System.Text.Json

func main() {
    options := new JsonSerializerOptions()
    json := JsonSerializer.Serialize<object>(42, options)
    print json
}
""",
        "42"
    )
}

test "MultiFileCompiler_EmitsFileScopedRecordWithDateTimeField" {
    EmitterCanonicalAssertProgramTrimmed(
        "FileScopedDateTimeProject",
        """
file record Stamp {
    When: DateTime
}

func main() {
    print "ok"
}
""",
        "ok"
    )
}

test "MultiFileCompiler_EmitsGenericBodyCollectionConstruction" {
    EmitterCanonicalAssertProgramNormalized(
        "GenericBodyCollectionProject",
        """
import System.Collections.Generic

func CountItems<T>(items: T[]): int {
    list := new List<T>()
    for item in items {
        list.Add(item)
    }

    return list.Count
}

func main() {
    print CountItems<int>(new int[3])
    print CountItems<string>(new string[2])
}
""",
        "3\n2"
    )
}

test "MultiFileCompiler_EmitsGenericParameterInterpolation" {
    EmitterCanonicalAssertProgramNormalized(
        "GenericInterpolationProject",
        """
func Pair<A, B>(a: A, b: B): string => $"({a}, {b})"

func main() {
    print Pair<int, string>(1, "two")
}
""",
        "(1, two)"
    )
}

test "MultiFileCompiler_EmitsGenericStringJoinForArray" {
    EmitterCanonicalAssertProgramNormalized(
        "GenericStringJoinProject",
        """
func main() {
    values := new int[3]
    values[0] = 2
    values[1] = 4
    values[2] = 6
    print String.Join(", ", values)
}
""",
        "2, 4, 6"
    )
}

test "MultiFileCompiler_EmitsGenericUnionPayloadFreeCallStyleAdoption" {
    EmitterCanonicalAssertProgramNormalized(
        "GenericUnionAdoptionProject",
        """
union Option<T> {
    Some { value: T }
    None
}

func FirstAbove(items: int[], threshold: int): Option<int> {
    for item in items {
        if item > threshold {
            return new Option.Some<int>(item)
        }
    }

    return new Option.None()
}

func main() {
    items := [1, 5, 9]
    found := match FirstAbove(items, 8) {
        Option.Some { value } => $"some:{value}",
        Option.None => "none"
    }
    print found

    missing := match FirstAbove(items, 100) {
        Option.Some { value } => $"some:{value}",
        Option.None => "none"
    }
    print missing
}
""",
        "some:9\nnone"
    )
}

test "MultiFileCompiler_EmitsInterpolatedStringCoalesceHole" {
    EmitterCanonicalAssertProgramTrimmed(
        "InterpolatedCoalesceProject",
        """
class Directory {
    func FindEmail(): string? {
        return null
    }
}

func main() {
    directory := new Directory()
    email := directory.FindEmail()
    missing := "not found"
    print $"Retrieved email: {email ?? missing}"
}
""",
        "Retrieved email: not found"
    )
}

test "MultiFileCompiler_EmitsInterpolatedStringIntegerAdditiveHole" {
    EmitterCanonicalAssertProgramTrimmed(
        "InterpolatedIntegerAdditiveProject",
        """
func main() {
    print $"Expected: {1000 + 1000 - 500}"
}
""",
        "Expected: 1500"
    )
}

test "MultiFileCompiler_EmitsLocalFunctionMethodGroupsInEnumerableCalls" {
    EmitterCanonicalAssertProgramNormalized(
        "LocalFunctionEnumerableProject",
        """
import System.Linq

func main() {
    func IsValid(value: int): bool {
        return value > 0 && value < 100
    }

    static func Transform(value: int): int {
        return value * 2
    }

    numbers := [1, 5, 50, 150]
    filtered := numbers.Where(IsValid).Select(Transform).ToArray()
    for item in filtered {
        print item
    }
}
""",
        "2\n10\n100"
    )
}

test "MultiFileCompiler_EmitsLockWithBareFieldPostfix" {
    EmitterCanonicalAssertProgramTrimmed(
        "LockBareFieldPostfixProject",
        """
class Counter {
    count: int = 0
    syncLock: object = new object()

    func Increment() {
        lock syncLock {
            count++
        }
    }

    func GetValue(): int {
        lock syncLock {
            return count
        }
    }
}

func main() {
    counter := new Counter()
    counter.Increment()
    print counter.GetValue()
}
""",
        "1"
    )
}

test "MultiFileCompiler_EmitsMathAtan2StaticCall" {
    EmitterCanonicalAssertProgramContains(
        "MathAtan2Project",
        """
import System

func main() {
    print Math.Atan2(4.0, 3.0)
}
""",
        "0.927"
    )
}

test "MultiFileCompiler_EmitsNestedEnumMembersOnClasses" {
    EmitterCanonicalAssertProgramNormalized(
        "NestedEnumClassProject",
        """
class Account {
    enum Status {
        Active,
        Frozen,
        Closed
    }

    class Transaction {
        Amount: int
    }

    CurrentStatus: Account.Status

    constructor() {
        CurrentStatus = Account.Status.Active
    }

    func Freeze() {
        CurrentStatus = Account.Status.Frozen
    }

    func Label(): string {
        return $"{CurrentStatus}"
    }
}

func main() {
    account := new Account()
    print account.Label()
    account.Freeze()
    print account.Label()
}
""",
        "Active\nFrozen"
    )
}

test "MultiFileCompiler_EmitsNestedPropertyPatterns" {
    EmitterCanonicalAssertProgramNormalized(
        "NestedPropertyPatternProject",
        """
class Address {
    City: string
    State: string
}

class Person {
    Name: string
    Age: int
    Address: Address
}

union Option {
    Some { value: int }
    None
}

union Response {
    Ok { data: Option }
    Error { message: string }
}

func Classify(person: Person): string {
    return match person {
        { Address: { City: "New York", State: "NY" } } => "ny",
        { Address: { City: city, State: "CA" } } => $"ca:{city}",
        { Age: age, Address: { State: "TX" } } => $"tx:{age}",
        _ => "other"
    }
}

func Extract(response: Response): int {
    return match response {
        Response.Ok { data: Option.Some { value } } => value,
        Response.Ok { data: Option.None } => 0,
        Response.Error { message } => -1
    }
}

func main() {
    ny := new Address { City: "New York", State: "NY" }
    ca := new Address { City: "San Francisco", State: "CA" }
    tx := new Address { City: "Austin", State: "TX" }

    print Classify(new Person { Name: "Ada", Age: 37, Address: ny })
    print Classify(new Person { Name: "Grace", Age: 41, Address: ca })
    print Classify(new Person { Name: "Lin", Age: 12, Address: tx })
    print Extract(new Response.Ok(new Option.Some(7)))
    print Extract(new Response.Ok(new Option.None()))
    print Extract(new Response.Error("bad"))
}
""",
        "ny\nca:San Francisco\ntx:12\n7\n0\n-1"
    )
}

test "MultiFileCompiler_EmitsParameterlessValueStructConstruction" {
    EmitterCanonicalAssertProgramNormalized(
        "ParameterlessStructProject",
        """
struct Buffer10 {
    element: int
}

func main() {
    buffer := new Buffer10()
    print "created"
}
""",
        "created"
    )
}

test "MultiFileCompiler_EmitsQualifiedBclExceptionConstruction" {
    EmitterCanonicalAssertProgramTrimmed(
        "QualifiedExceptionProject",
        """
func Divide(a: int, b: int): int {
    if b == 0 {
        throw new System.DivideByZeroException("Cannot divide by zero")
    }

    return a / b
}

func main() {
    print Divide(10, 2)
}
""",
        "5"
    )
}

test "MultiFileCompiler_EmitsRawAndInterpolatedRawStringLiterals" {
    EmitterCanonicalAssertProgramNormalized(
        "RawStringProject",
        "func main() {\n    name := \"Ada\"\n    raw := \"\"\"quote \" slash \\n\"\"\"\n    interp := $\"\"\"Hello {name}\\n{{name}}\"\"\"\n    print raw\n    print interp\n}\n",
        "quote \" slash \\n\nHello Ada\\n{name}"
    )
}

test "MultiFileCompiler_EmitsSortedDictionaryIndexerAccess" {
    EmitterCanonicalAssertProgramNormalized(
        "SortedDictionaryProject",
        """
import System.Collections.Generic

func main() {
    sorted := new SortedDictionary<string, string>()
    sorted["zebra"] = "Striped animal"
    sorted["apple"] = "Red fruit"
    sorted.Add("berry", "Small fruit")
    removed := sorted.Remove("zebra")

    print sorted.Count
    print sorted.ContainsKey("berry")
    print removed
    print sorted["apple"]
}
""",
        "2\nTrue\nTrue\nRed fruit"
    )
}

test "MultiFileCompiler_EmitsSpanIndexReadWrite" {
    EmitterCanonicalAssertProgramNormalized(
        "SpanIndexProject",
        """
func Modify(values: Span<int>) {
    for i := 0; i < values.Length; i++ {
        values[i] = values[i] * 2
    }
}

func main() {
    values := new int[3]
    values[0] = 1
    values[1] = 2
    values[2] = 3
    Modify(values)
    print $"{values[0]}:{values[1]}:{values[2]}"
}
""",
        "2:4:6"
    )
}

test "MultiFileCompiler_EmitsSpreadArgumentForParamsArrayCall" {
    EmitterCanonicalAssertProgramNormalized(
        "SpreadParamsProject",
        """
func Sum(params values: int[]): int {
    total := 0
    for value in values {
        total = total + value
    }
    return total
}

func Format(prefix: string, suffix: string, params values: int[]): string {
    middle := ""
    for i := 0; i < values.Length; i++ {
        if i > 0 {
            middle += ", "
        }
        middle += values[i].ToString()
    }
    return prefix + middle + suffix
}

func PrintAll<T>(prefix: string, params items: T[]) {
    for item in items {
        print $"{prefix}{item}"
    }
}

func main() {
    numbers: int[] = [1, 2, 3, 4, 5]
    print Sum(...numbers)
    print Format("[", "]", ...numbers)
    PrintAll("v=", ...numbers)
}
""",
        "15\n[1, 2, 3, 4, 5]\nv=1\nv=2\nv=3\nv=4\nv=5"
    )
}

test "MultiFileCompiler_EmitsStaticExpandedParamsCall" {
    EmitterCanonicalAssertProgramNormalized(
        "StaticExpandedParamsProject",
        """
class Mathy {
    static func Sum(params values: int[]): int {
        total := 0
        for value in values {
            total = total + value
        }
        return total
    }
}

func main() {
    print Mathy.Sum(1, 2, 3)
    print Mathy.Sum(5)
    print Mathy.Sum()
}
""",
        "6\n5\n0"
    )
}

test "MultiFileCompiler_EmitsStringCompareToInstanceCall" {
    EmitterCanonicalAssertProgramTrimmed(
        "StringCompareProject",
        """
func main() {
    greeting := "hello"
    print greeting.CompareTo("hello")
}
""",
        "0"
    )
}

test "MultiFileCompiler_EmitsStringEnumConstantsAsStrings" {
    EmitterCanonicalAssertProgramNormalized(
        "StringEnumProject",
        """
enum Status: string {
    Active = "active",
    Inactive = "inactive",
    Pending = "pending"
}

func GetDefault(): Status {
    return Status.Active
}

func Echo(value: Status): string {
    return value
}

func main() {
    print GetDefault()
    print Echo(Status.Inactive)
    print Status.Pending
}
""",
        "active\ninactive\npending"
    )
}

test "MultiFileCompiler_EmitsTargetTypedArrayLiteralAndForIn" {
    EmitterCanonicalAssertProgramTrimmed(
        "ArrayLiteralProject",
        """
class Item {
    Value: int
}

func main() {
    items: Item[] = [new Item { Value: 2 }, new Item { Value: 4 }]
    total := 0
    for item in items {
        total = total + item.Value
    }
    print total
}
""",
        "6"
    )
}

test "MultiFileCompiler_EmitsTargetTypedHashSetLiteral" {
    EmitterCanonicalAssertProgramNormalized(
        "HashSetLiteralProject",
        """
import System.Collections.Generic

func main() {
    names: HashSet<string> = ["Alice", "Bob", "Alice"]
    print names.Count
    print names.Contains("Bob")
}
""",
        "2\nTrue"
    )
}

test "MultiFileCompiler_EmitsTargetTypedListLiteral" {
    EmitterCanonicalAssertProgramNormalized(
        "ListLiteralProject",
        """
import System.Collections.Generic

func main() {
    list1: List<int> = [1, 2, 3]
    list2: List<int> = [4, 5]
    lists := new List<List<int>>()
    lists.Add(list1)
    lists.Add(list2)

    print list1.Count
    print list2.Count
    print lists.Count
}
""",
        "3\n2\n2"
    )
}

test "MultiFileCompiler_EmitsTargetTypedNewConstructors" {
    EmitterCanonicalAssertProgramNormalized(
        "TargetTypedNewProject",
        """
class Person {
    readonly Name: string
    readonly Age: int

    constructor(name: string, age: int) {
        Name = name
        Age = age
    }

    func Label(): string {
        return $"{Name}:{Age}"
    }
}

class Box<T> {
    readonly Value: T

    constructor(value: T) {
        Value = value
    }

    func GetValue(): T {
        return Value
    }
}

func CreateDefaultPerson(): Person {
    return new("Default", 0)
}

func main() {
    person: Person = new("Alice", 30)
    intBox: Box<int> = new(42)

    print person.Label()
    print CreateDefaultPerson().Label()
    print intBox.GetValue()
}
""",
        "Alice:30\nDefault:0\n42"
    )
}

test "MultiFileCompiler_EmitsUserDefinedConversionOperators" {
    EmitterCanonicalAssertProgramNormalized(
        "ConversionOperatorProject",
        """
class Raw {
    Value: int

    implicit operator Cooked(r: Raw) {
        return new Cooked { Value: r.Value + 10 }
    }

    explicit operator Done(r: Raw) {
        return new Done { Value: r.Value + 20 }
    }

    func Label(): string {
        return $"raw-{Value}"
    }
}

class Cooked {
    Value: int
}

class Done {
    Value: int
}

struct Score {
    Value: int

    explicit operator int(s: Score) {
        return s.Value + 30
    }
}

struct Ratio {
    Numerator: int
    Denominator: int

    explicit operator double(r: Ratio) {
        return r.Numerator / (double)r.Denominator
    }
}

func main() {
    raw := new Raw { Value: 5 }
    cooked: Cooked = raw
    done := (Done)raw
    score := new Score { Value: 7 }
    value := (int)score
    ratio := new Ratio { Numerator: 3, Denominator: 2 }
    ratioValue := (double)ratio

    print cooked.Value
    print done.Value
    print value
    print $"label: {raw.Label()}"
    print ratioValue
}
""",
        "15\n25\n37\nlabel: raw-5\n1.5"
    )
}
