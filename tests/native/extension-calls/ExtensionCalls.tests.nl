namespace NSharpLang.ExtensionCalls.Tests

import System
import System.Collections
import System.IO
import System.Linq
import System.Reflection
import NSharpLang.Compiler

// End-to-end coverage for external extension-method calls. The executed proofs below are compiled
// through the real columnar pipeline (this very project builds with nlc): each `receiver.Method()`
// binds a non-generic BCL extension method, so if the extension resolver mis-selected an overload,
// emitted the wrong receiver, or produced unverifiable IL, this project would fail to build and the
// asserts would never run. Decline cases (no candidate, generic-only candidate) must fail
// compilation and therefore run through the production MultiFileCompiler harness on a fixture that
// references System.Linq exactly as `nlc build` does.
class ExtensionCallCompilation {
    Succeeded: bool
    Diagnostics: string
    FixtureRoot: string
    OutputPath: string
    Config: ProjectConfig

    constructor(
        succeeded: bool,
        diagnostics: string,
        fixtureRoot: string,
        outputPath: string,
        config: ProjectConfig
    ) {
        Succeeded = succeeded
        Diagnostics = diagnostics
        FixtureRoot = fixtureRoot
        OutputPath = outputPath
        Config = config
    }
}

class ExtensionCallRunResult {
    ExitCode: int
    Stdout: string

    constructor(exitCode: int, stdout: string) {
        ExitCode = exitCode
        Stdout = stdout
    }
}

func SetExtensionObject(values: object?[], index: int, value: object?) {
    values[index] = value
}

func ExtensionCoreFrameworkDirectory(): string {
    coreAssembly := typeof(object).get_Assembly()
    coreLocation := coreAssembly.get_Location()
    return Path.GetDirectoryName(coreLocation) ?? ""
}

func CompileExtensionCallFixture(source: string): ExtensionCallCompilation {
    return CompileNamedExtensionCallFixture(
        "ExtensionCallFixture",
        "library",
        source
    )
}

func CompileNamedExtensionCallFixture(
    projectName: string,
    outputType: string,
    source: string
): ExtensionCallCompilation {
    fileNames := new string[](1)
    fileNames[0] = "Program.nl"
    contents := new string[](1)
    contents[0] = source
    return CompileNamedExtensionCallFixtureFiles(
        projectName,
        outputType,
        fileNames,
        contents
    )
}

// The migrated namespace assertion has two source files. Keep the same production harness and
// compiler route as the single-file canonical programs, while preserving their original file names.
func CompileNamedExtensionCallFixtureFiles(
    projectName: string,
    outputType: string,
    fileNames: string[],
    contents: string[]
): ExtensionCallCompilation {
    if fileNames.Length != contents.Length {
        throw new InvalidOperationException("Fixture file names and contents must have the same length.")
    }
    fixtureRoot := Path.Combine(
        Path.GetTempPath(),
        "nsharp-extension-calls-" + Guid.NewGuid().ToString("N")
    )
    Directory.CreateDirectory(fixtureRoot)
    fileIndex := 0
    while fileIndex < fileNames.Length {
        File.WriteAllText(Path.Combine(fixtureRoot, fileNames[fileIndex]), contents[fileIndex])
        fileIndex = fileIndex + 1
    }

    // Reference the core framework and System.Linq the way `nlc build` resolves the implicit
    // Microsoft.NETCore.App framework, so both live extension hosts (Enumerable) and every core type
    // resolve to runtime handles for analysis and emission.
    coreDirectory := ExtensionCoreFrameworkDirectory()
    coreLib := Path.Combine(coreDirectory, "System.Private.CoreLib.dll")
    runtimeDll := Path.Combine(coreDirectory, "System.Runtime.dll")
    linqDll := Path.Combine(coreDirectory, "System.Linq.dll")
    projectYml := "name: " + projectName + "\nversion: 1.0.0\nbackend: il\noutputType: " + outputType + "\ntargetFramework: net10.0\ndependencies:\n  - dll: " + coreLib + "\n  - dll: " + runtimeDll + "\n  - dll: " + linqDll + "\n"
    File.WriteAllText(Path.Combine(fixtureRoot, "project.yml"), projectYml)

    compilerType := Type.GetType("NSharpLang.Compiler.MultiFileCompiler, NSharpLang.Compiler.BootstrapServices")
    projectFileParserType := Type.GetType(
        "NSharpLang.Compiler.ProjectFileParser, NSharpLang.Compiler.BootstrapServices"
    )
    if compilerType == null || projectFileParserType == null {
        throw new InvalidOperationException("The production compiler types were not loadable.")
    }
    parseParameterTypes := new Type[](1)
    parseParameterTypes[0] = typeof(string)
    parseMethod := projectFileParserType.GetMethod("Parse", parseParameterTypes)
    if parseMethod == null {
        throw new InvalidOperationException("The production project parser was not found.")
    }
    parseArguments := new object?[](1)
    SetExtensionObject(parseArguments, 0, Path.Combine(fixtureRoot, "project.yml"))
    config := parseMethod.Invoke(null, parseArguments)
    if config == null {
        throw new InvalidOperationException("The production project configuration was not parsed.")
    }
    typedConfig := config as ProjectConfig
    if typedConfig == null {
        throw new InvalidOperationException("The production project configuration had the wrong runtime type.")
    }
    projectConfigType := config.GetType()

    constructorTypes := new Type[](2)
    constructorTypes[0] = typeof(string)
    constructorTypes[1] = projectConfigType
    constructor := compilerType.GetConstructor(constructorTypes)
    if constructor == null {
        throw new InvalidOperationException("The production compiler constructor was not found.")
    }
    constructorArguments := new object?[](2)
    SetExtensionObject(constructorArguments, 0, fixtureRoot)
    SetExtensionObject(constructorArguments, 1, config)
    compiler := constructor.Invoke(constructorArguments)

    compileParameterTypes := new Type[](4)
    compileParameterTypes[0] = typeof(string)
    compileParameterTypes[1] = typeof(string)
    compileParameterTypes[2] = typeof(bool)
    compileParameterTypes[3] = typeof(bool)
    compileMethod := compilerType.GetMethod("CompileToIlAssembly", compileParameterTypes)
    if compileMethod == null {
        throw new InvalidOperationException("The production compiler entry point was not found.")
    }

    outputPath := Path.Combine(fixtureRoot, "out/" + projectName + ".dll")
    compileArguments := new object?[](4)
    SetExtensionObject(compileArguments, 0, projectName)
    SetExtensionObject(compileArguments, 1, outputPath)
    SetExtensionObject(compileArguments, 2, false)
    SetExtensionObject(compileArguments, 3, true)
    compilation := compileMethod.Invoke(compiler, compileArguments)
    if compilation == null {
        throw new InvalidOperationException("The production compiler returned no compilation result.")
    }

    compilationType := compilation.GetType()
    successProperty := compilationType.GetProperty("Success")
    errorsProperty := compilationType.GetProperty("Errors")
    if successProperty == null || errorsProperty == null {
        throw new InvalidOperationException("The production compilation result contract was incomplete.")
    }
    successValue := successProperty.GetValue(compilation)
    errorsValue := errorsProperty.GetValue(compilation)
    if successValue == null {
        throw new InvalidOperationException("The production compilation result values were incomplete.")
    }

    succeeded := successValue.ToString() == "True"
    diagnostics := FormatFirstExtensionDiagnostic(errorsValue as IList)
    return new ExtensionCallCompilation(
        succeeded,
        diagnostics,
        fixtureRoot,
        outputPath,
        typedConfig
    )
}

func FormatFirstExtensionDiagnostic(errors: IList?): string {
    if errors == null || errors.Count == 0 {
        return ""
    }
    firstError := errors[0]
    if firstError == null {
        return ""
    }
    errorType := firstError.GetType()
    formatParameterTypes := new Type[](2)
    formatParameterTypes[0] = typeof(bool)
    formatParameterTypes[1] = typeof(bool)
    formatMethod := errorType.GetMethod("FormatForTooling", formatParameterTypes)
    if formatMethod == null {
        return ""
    }
    formatArguments := new object?[](2)
    SetExtensionObject(formatArguments, 0, true)
    SetExtensionObject(formatArguments, 1, false)
    formattedValue := formatMethod.Invoke(firstError, formatArguments)
    if formattedValue == null {
        return ""
    }
    return formattedValue.ToString() ?? ""
}

func CleanupExtensionCompilation(compilation: ExtensionCallCompilation) {
    if Directory.Exists(compilation.FixtureRoot) {
        Directory.Delete(compilation.FixtureRoot, true)
    }
}

func RunGenericCallProgram(outputPath: string, workingDirectory: string): ExtensionCallRunResult {
    runnerType := Type.GetType(
        "NSharpLang.Cli.DotnetRunner, NSharpLang.Compiler.BootstrapServices"
    )
    if runnerType == null {
        throw new InvalidOperationException("The production dotnet runner was not loadable.")
    }

    candidates := runnerType.GetMethods()
    runMethod: MethodInfo? = null
    matchCount := 0
    candidateIndex := 0
    while candidateIndex < candidates.Length {
        candidate := candidates[candidateIndex]
        if candidate.get_Name() == "Run" && candidate.GetParameters().Length == 4 {
            runMethod = candidate
            matchCount += 1
        }
        candidateIndex += 1
    }
    if runMethod == null || matchCount != 1 {
        throw new InvalidOperationException("The production dotnet runner entry point was not found.")
    }

    arguments := new object?[](4)
    SetExtensionObject(arguments, 0, "\"" + outputPath + "\"")
    SetExtensionObject(arguments, 1, workingDirectory)
    SetExtensionObject(arguments, 2, true)
    SetExtensionObject(arguments, 3, null)
    result := runMethod.Invoke(null, arguments)
    if result == null {
        throw new InvalidOperationException("The production dotnet runner returned no result.")
    }
    resultType := result.GetType()
    exitCodeField := resultType.GetField("ExitCode")
    stdoutField := resultType.GetField("Stdout")
    if exitCodeField == null || stdoutField == null {
        throw new InvalidOperationException("The production dotnet runner result contract was incomplete.")
    }
    exitCodeValue := exitCodeField.GetValue(result)
    stdoutValue := stdoutField.GetValue(result)
    if exitCodeValue == null || stdoutValue == null {
        throw new InvalidOperationException("The production dotnet runner result values were incomplete.")
    }
    exitCodeText := exitCodeValue.ToString() ?? ""
    return new ExtensionCallRunResult(int.Parse(exitCodeText), stdoutValue.ToString() ?? "")
}

func AssertGenericCallProgram(
    projectName: string,
    source: string,
    expectedOutput: string
) {
    compilation := CompileNamedExtensionCallFixture(projectName, "exe", source)
    try {
        assert compilation.Succeeded, compilation.Diagnostics
        CompilationArtifacts.WriteRuntimeConfig(
            compilation.Config,
            compilation.OutputPath
        )

        runResult := RunGenericCallProgram(
            compilation.OutputPath,
            compilation.FixtureRoot
        )
        assert runResult.ExitCode == 0
        assert runResult.Stdout.Replace("\r\n", "\n").Trim() == expectedOutput
    } finally {
        CleanupExtensionCompilation(compilation)
    }
}

// Canonical generic-call integration assertions formerly lived in CompilationBackendTests.cs.
// Each exact program now passes through the production compiler and executes its emitted assembly;
// the focused planner controls separately pin the individual inference and return-shape decisions.
test "generic params array inference compiles and executes" {
    AssertGenericCallProgram(
        "GenericParamsArrayProject",
        """
import System.Collections.Generic

func CreateList<T>(params items: T[]): List<T> {
    list := new List<T>()
    for item in items {
        list.Add(item)
    }

    return list
}

func main() {
    numbers := CreateList(1, 2, 3)
    words := CreateList("a", "b")
    print numbers.Count
    print words.Count
}
""",
        "3\n2"
    )
}

test "explicit nullable generic call compiles and executes" {
    AssertGenericCallProgram(
        "ExplicitNullableGenericProject",
        """
import System.Collections.Generic
import System.Linq

func CreateList<T>(params items: T[]): List<T> {
    list := new List<T>()
    for item in items {
        list.Add(item)
    }

    return list
}

func main() {
    numbers := CreateList<int?>(1, null, 3)
    present := numbers.Where(n => n != null).ToList()
    print $"{numbers.Count}:{present.Count}"
}
""",
        "3:2"
    )
}

test "generic expanded params array call compiles and executes" {
    AssertGenericCallProgram(
        "GenericExpandedParamsProject",
        """
func PrintAll<T>(prefix: string, params items: T[]) {
    for item in items {
        print $"{prefix}{item}"
    }
}

func main() {
    PrintAll("n=", 1, 2, 3, 4, 5)
    PrintAll("s=", "Alice", "Bob")
}
""",
        "n=1\nn=2\nn=3\nn=4\nn=5\ns=Alice\ns=Bob"
    )
}

// Canonical closure-binding integration assertions formerly lived in CompilationBackendTests.cs.
// Each exact program passes through production compilation and the emitted executable, retaining
// the source bytes and its success, process-exit, and normalized-stdout assertions.
test "string join over select with an interpolated lambda compiles and executes" {
    AssertGenericCallProgram(
        "StringJoinSelectProject",
        """
import System.Collections.Generic
import System.Linq

func FormatTags(tags: List<string>): string {
    if tags.Count == 0 {
        return "-"
    }

    return String.Join(" ", tags.Select(tag => $"#{tag}"))
}

func main() {
    tags: List<string> = ["alpha", "beta"]
    print FormatTags(tags)
}
""".Trim(),
        "#alpha #beta"
    )
}

test "task run actions capture a reference and execute" {
    AssertGenericCallProgram(
        "TaskRunActionProject",
        """
import System.Threading.Tasks

class Flags {
    First: int = 0
    Second: int = 0

    func SetFirst() {
        First = 1
    }

    func SetSecond() {
        Second = 2
    }

    func Sum(): int {
        return First + Second
    }
}

func main() {
    flags := new Flags()
    t1 := Task.Run(() => {
        flags.SetFirst()
    })
    t2 := Task.Run(() => {
        flags.SetSecond()
    })

    Task.WaitAll(t1, t2)
    print flags.Sum()
}
""".Trim(),
        "3"
    )
}

// Focused closure-binding regressions. The first proves the StrongBox-backed capture carries
// parent-to-lambda and lambda-to-parent writes through one shared storage location. The second
// retains the established decline for a captured root used in a member-path write: that shape needs
// the box value address and is intentionally not lifted by this ownership area.
test "a contextual capture shares lifted local mutation with its enclosing body" {
    AssertGenericCallProgram(
        "SharedLiftedMutationProject",
        """
import System

func main() {
    value := 1
    mutate: Action = () => {
        value = value + 10
    }
    value = 2
    mutate()
    print value
}
""",
        "12"
    )
}

test "a contextual read-only capture compiles and executes" {
    AssertGenericCallProgram(
        "ContextualCaptureReadProject",
        """
class Cell {
    Value: int = 1
}

func main() {
    cell := new Cell()
    read: Func<int> = () => cell.Value
    print read()
}
""",
        "1"
    )
}

test "a contextual capture with a member-rooted structural write declines" {
    compilation := CompileNamedExtensionCallFixture(
        "StructuralCaptureWriteProject",
        "exe",
        """
class Cell {
    Value: int = 1
}

func main() {
    cell := new Cell()
    read: Func<int> = () => cell.Value
    cell.Value = 99
    print read()
}
"""
    )
    try {
        assert !compilation.Succeeded, compilation.Diagnostics
    } finally {
        CleanupExtensionCompilation(compilation)
    }
}

// Canonical reference-coercion integration assertions formerly lived in
// CompilationBackendTests.cs. These exact programs exercise the production conversion sites:
// a source class flowing into a source interface constructor slot, and value/object flows through
// explicit generic LINQ calls. Keep success, process exit, and normalized stdout together.
test "constructor-chain source interface coercion compiles and executes" {
    AssertGenericCallProgram(
        "ConstructorChainArgumentsProject",
        """
interface ICache {
    func Get(key: string): string?
}

class MemoryCache: ICache {
    func Get(key: string): string? {
        return null
    }
}

class Person {
    readonly Name: string
    readonly Age: int
    readonly Email: string

    constructor(name: string, age: int, email: string) {
        Name = name
        Age = age
        Email = email
    }

    constructor(name: string, email: string): this(name, 0, email) {
    }

    constructor(name: string): this(name, 0, "") {
    }

    func Info(): string {
        return $"{Name}:{Age}:{Email}"
    }
}

class Service {
    readonly Cache: ICache
    readonly Config: string

    constructor(cache: ICache, config: string) {
        Cache = cache
        Config = config
    }

    constructor(): this(new MemoryCache(), "default") {
    }

    func Info(): string {
        return Config
    }
}

func main() {
    p1 := new Person("Ada", 37, "ada@example.com")
    p2 := new Person("Bob", "bob@example.com")
    p3 := new Person("Cy")
    service := new Service()

    print p1.Info()
    print p2.Info()
    print p3.Info()
    print service.Info()
}
""".Trim(),
        "Ada:37:ada@example.com\nBob:0:bob@example.com\nCy:0:\ndefault"
    )
}

test "explicit generic LINQ object boxing compiles and executes" {
    AssertGenericCallProgram(
        "GenericLinqProject",
        """
import System.Collections.Generic
import System.Linq

func main() {
    numbers: int[] = [1, 2, 3]
    objects := numbers.Cast<object>().ToList()

    mixed := new List<object>()
    mixed.Add(1)
    mixed.Add("two")
    mixed.Add(3)

    justNumbers := mixed.OfType<int>().ToList()
    justStrings := mixed.OfType<string>().ToList()

    print objects.Count
    print justNumbers.Count
    print justStrings.Count
}
""".Trim(),
        "3\n2\n1"
    )
}

// This is the exact closed Enumerable overload used by SystemsAnalyzer: its source is an
// IEnumerable rather than an array or List, both selector locals have their fixed Func shape,
// and StringComparer must widen to IEqualityComparer<string> at the final argument slot.
test "explicit String ToDictionary over a custom enumerable compiles and executes" {
    AssertGenericCallProgram(
        "ExplicitStringToDictionaryProject",
        """
import System
import System.Collections.Generic
import System.Linq

func* ToDictionaryNames(first: string, second: string): IEnumerable<string> {
    yield first
    yield second
}

func main() {
    source := ToDictionaryNames("Alpha", "Beta")
    keySelector: Func<string, string> = value => value
    valueSelector: Func<string, string> = value => value
    values := Enumerable.ToDictionary<string, string, string>(source, keySelector, valueSelector, StringComparer.OrdinalIgnoreCase)

    print values.Count
    print values["alpha"]
}
""".Trim(),
        "2\nAlpha"
    )
}

// The BCL call remains responsible for duplicate detection. This catches the ArgumentException
// it throws after the second normalized key reaches Dictionary.Add.
test "explicit String ToDictionary preserves duplicate normalized-key failure" {
    AssertGenericCallProgram(
        "ExplicitStringToDictionaryDuplicateProject",
        """
import System
import System.Collections.Generic
import System.Linq

func* ToDictionaryDuplicateNames(first: string, second: string): IEnumerable<string> {
    yield first
    yield second
}

func main() {
    source := ToDictionaryDuplicateNames("Alpha", "alpha")
    keySelector: Func<string, string> = value => value
    valueSelector: Func<string, string> = value => value

    try {
        Enumerable.ToDictionary<string, string, string>(source, keySelector, valueSelector, StringComparer.OrdinalIgnoreCase)
        print "missing duplicate failure"
    } catch error: ArgumentException {
        print "duplicate"
    }
}
""".Trim(),
        "duplicate"
    )
}

// ReferenceEqualityComparer must preserve reference identity even when the source key type supplies
// value equality. Its contravariant IEqualityComparer<object> implementation is the exact comparer
// passed to the SystemsAnalyzer dictionary and set constructors.
test "ReferenceEqualityComparer Instance preserves distinct value-equal keys" {
    AssertGenericCallProgram(
        "ReferenceEqualityComparerProject",
        """
import System
import System.Collections.Generic

class ReferenceIdentityNode {
    Value: string

    constructor(value: string) {
        Value = value
    }

    override func Equals(value: object): bool {
        other := value as ReferenceIdentityNode
        return other != null && Value == other.Value
    }

    override func GetHashCode(): int {
        return Value.GetHashCode()
    }
}

func main() {
    first := new ReferenceIdentityNode("same")
    second := new ReferenceIdentityNode("same")

    valueSet := new HashSet<ReferenceIdentityNode>()
    valueSet.Add(first)
    valueSet.Add(second)

    identitySet := new HashSet<ReferenceIdentityNode>(ReferenceEqualityComparer.Instance)
    identitySet.Add(first)
    identitySet.Add(second)

    identityMap := new Dictionary<ReferenceIdentityNode, int>(ReferenceEqualityComparer.Instance)
    identityMap.Add(first, 1)
    identityMap.Add(second, 2)

    print valueSet.Count
    print identitySet.Count
    print identityMap.Count
}
""".Trim(),
        "1\n2\n2"
    )
}

// Canonical constructor-declaration integration assertions formerly lived in
// CompilationBackendTests.cs. Each exact program uses the existing full production compiler/run
// harness, retaining compilation success, process exit, and its original stdout assertion.
test "readonly class fields initialized by a constructor compile and execute" {
    AssertGenericCallProgram(
        "ReadonlyClassFields",
        """
class Person {
    readonly Name: string
    readonly Age: int

    constructor(name: string, age: int) {
        Name = name
        Age = age
    }

    func GetInfo(): string {
        return $"{Name}:{Age}"
    }
}

func main() {
    person := new Person("Ada", 37)
    print person.GetInfo()
}
""".Trim(),
        "Ada:37"
    )
}

test "instance field initializers with an explicit constructor compile and execute" {
    AssertGenericCallProgram(
        "InstanceFieldInitializers",
        """
class Logger {
    Prefix: string = "[LOG]"
}

class Application {
    logger: Logger = new Logger()
    readonly Name: string

    constructor(name: string) {
        Name = name
    }

    func Describe(): string {
        return $"{logger.Prefix}:{Name}"
    }
}

func main() {
    app := new Application("FileScopedDemo")
    print app.Describe()
}
""".Trim(),
        "[LOG]:FileScopedDemo"
    )
}

test "a double instance field initializer compiles and executes" {
    AssertGenericCallProgram(
        "DoubleInstanceFieldInitializer",
        """
class Account {
    balance: double = 0.0

    func GetBalance(): double {
        return balance
    }
}

func main() {
    account := new Account()
    print account.GetBalance()
}
""".Trim(),
        "0"
    )
}

test "struct primary constructor parameters remain available to members" {
    AssertGenericCallProgram(
        "StructPrimaryCtorMembers",
        """
import System

struct Point(x: double, y: double) {
    func Distance(): double {
        return Math.Sqrt(x * x + y * y)
    }

    func Label(): string {
        return $"Point({x}, {y})"
    }
}

func main() {
    point := new Point(3.0, 4.0)
    print point.Distance()
    print point.Label()
}
""".Trim(),
        "5\nPoint(3, 4)"
    )
}

test "record primary constructor parameters remain available to members" {
    compilation := CompileNamedExtensionCallFixture(
        "RecordPrimaryCtorMembers",
        "exe",
        """
record Address(street: string, city: string, zip: string) {
    FullAddress: string => $"{street}, {city} {zip}"
}

func main() {
    address := new Address("123 Main St", "Springfield", "62701")
    print address.FullAddress
}
""".Trim()
    )
    try {
        assert compilation.Succeeded, compilation.Diagnostics
        CompilationArtifacts.WriteRuntimeConfig(
            compilation.Config,
            compilation.OutputPath
        )
        runResult := RunGenericCallProgram(
            compilation.OutputPath,
            compilation.FixtureRoot
        )
        assert runResult.ExitCode == 0
        assert runResult.Stdout.Contains("123 Main St, Springfield 62701")
    } finally {
        CleanupExtensionCompilation(compilation)
    }
}

// -----------------------------------------------------------------------------------------------
// Executed proofs (compiled through the columnar pipeline as this project builds).
// -----------------------------------------------------------------------------------------------

// A single extension call on an interface-typed receiver: `int[]` implements `IEnumerable<int>`, so
// `values.Sum()` binds the non-generic Enumerable.Sum(IEnumerable<int>) extension and executes.
func SumOfNumbers(values: int[]): int {
    return values.Sum()
}

func MaxOfNumbers(values: int[]): int {
    return values.Max()
}

func MinOfNumbers(values: int[]): int {
    return values.Min()
}

func MakeNumbers(): int[] {
    return [4, 8, 15]
}

// A chained receiver: the extension receiver is itself a call result, not a bound local. This
// proves the receiver-value emission handles a composed expression.
func ChainedSum(): int {
    return MakeNumbers().Sum()
}

test "an extension call on an interface-typed array receiver executes" {
    values := [10, 20, 30]
    assert SumOfNumbers(values) == 60, "int[].Sum() must bind Enumerable.Sum and total the array."
    assert MaxOfNumbers(values) == 30, "int[].Max() must bind Enumerable.Max and return the maximum."
    assert MinOfNumbers(values) == 10, "int[].Min() must bind Enumerable.Min and return the minimum."
}

test "a chained extension call on a call-result receiver executes" {
    assert ChainedSum() == 27, "MakeNumbers().Sum() must bind Sum on the call-result receiver."
}

// -----------------------------------------------------------------------------------------------
// Decline cases (must fail compilation, so they run through the MultiFileCompiler harness).
// -----------------------------------------------------------------------------------------------

test "a member call with no matching instance or extension method declines" {
    compilation := CompileExtensionCallFixture(
        """
import System.Linq

class Consumer {
    func Run(): int {
        numbers := [1, 2, 3]
        return numbers.NonexistentExtensionXyz()
    }
}
"""
    )
    assert !compilation.Succeeded, compilation.Diagnostics
    CleanupExtensionCompilation(compilation)
}

test "a generic-only extension candidate is not bound and declines" {
    // Enumerable.Distinct<T>(IEnumerable<T>) is generic; the index build excludes generic methods,
    // so the bare `Distinct()` call must decline rather than binding a generic extension.
    compilation := CompileExtensionCallFixture(
        """
import System.Linq

class Consumer {
    func Run(): int[] {
        numbers := [1, 2, 2, 3]
        return numbers.Distinct()
    }
}
"""
    )
    assert !compilation.Succeeded, compilation.Diagnostics
    CleanupExtensionCompilation(compilation)
}

// Canonical interface-realization integration assertions migrated from CompilationBackendTests.cs.
// They run the complete production compiler and retain the source programs plus runtime/type-output
// assertions that exercised the old C# owner.
func CreateExtensionCollectibleLoadContext(): object {
    contextType := Type.GetType(
        "System.Runtime.Loader.AssemblyLoadContext, System.Runtime.Loader"
    )
    if contextType == null {
        throw new InvalidOperationException("AssemblyLoadContext was not loadable.")
    }
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = typeof(bool)
    constructor := contextType.GetConstructor(parameterTypes)
    if constructor == null {
        throw new InvalidOperationException("The collectible AssemblyLoadContext constructor was not found.")
    }
    arguments := new object?[](2)
    SetExtensionObject(arguments, 0, "nsharp-interface-realization-" + Guid.NewGuid().ToString("N"))
    SetExtensionObject(arguments, 1, true)
    context := constructor.Invoke(arguments)
    if context == null {
        throw new InvalidOperationException("The collectible AssemblyLoadContext was not created.")
    }
    return context
}

func LoadExtensionFixtureAssembly(context: object, outputPath: string): Assembly {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    loadMethod := context.GetType().GetMethod("LoadFromAssemblyPath", parameterTypes)
    if loadMethod == null {
        throw new InvalidOperationException("AssemblyLoadContext.LoadFromAssemblyPath(string) was not found.")
    }
    arguments := new object?[](1)
    SetExtensionObject(arguments, 0, outputPath)
    loaded := loadMethod.Invoke(context, arguments)
    assembly := loaded as Assembly
    if assembly == null {
        throw new InvalidOperationException("The compiled fixture assembly was not loadable.")
    }
    return assembly
}

func UnloadExtensionFixtureContext(context: object) {
    parameterTypes := new Type[](0)
    unloadMethod := context.GetType().GetMethod("Unload", parameterTypes)
    if unloadMethod == null {
        throw new InvalidOperationException("AssemblyLoadContext.Unload() was not found.")
    }
    arguments := new object?[](0)
    unloadMethod.Invoke(context, arguments)
}

func ExtensionFixtureAssemblyHasType(assembly: Assembly, fullName: string): bool {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    getTypeMethod := typeof(Assembly).GetMethod("GetType", parameterTypes)
    if getTypeMethod == null {
        throw new InvalidOperationException("Assembly.GetType(string) was not found.")
    }
    arguments := new object?[](1)
    SetExtensionObject(arguments, 0, fullName)
    return getTypeMethod.Invoke(assembly, arguments) != null
}

func AssertNamespaceInterfaceFixtureTypes(outputPath: string) {
    context := CreateExtensionCollectibleLoadContext()
    try {
        assembly := LoadExtensionFixtureAssembly(context, outputPath)
        assert ExtensionFixtureAssemblyHasType(assembly, "InteropLib.MathUtils")
        assert ExtensionFixtureAssemblyHasType(assembly, "InteropLib.Geometry.IShape")
        assert ExtensionFixtureAssemblyHasType(assembly, "InteropLib.Geometry.Square")
    } finally {
        UnloadExtensionFixtureContext(context)
    }
}

test "interface method returning a user struct compiles and executes" {
    AssertGenericCallProgram(
        "InterfaceUserStructProject",
        """
file struct ValidationResult {
    IsValid: bool
}

file interface IValidator {
    func Validate(input: string): ValidationResult
}

file class UsernameValidator: IValidator {
    func Validate(input: string): ValidationResult {
        if input.Length > 0 {
            return new ValidationResult { IsValid: true }
        }

        return new ValidationResult { IsValid: false }
    }
}

func main() {
    validator: IValidator = new UsernameValidator()
    result := validator.Validate("abc")
    print result.IsValid
}
""",
        "True"
    )
}

test "async executable entrypoint compiles and writes its completed output" {
    compilation := CompileNamedExtensionCallFixture(
        "AsyncMainIlProject",
        "exe",
        """
import System.Threading.Tasks

async func main() {
    await Task.CompletedTask
    print "async entrypoint works"
}
"""
    )
    try {
        assert compilation.Succeeded, compilation.Diagnostics
        CompilationArtifacts.WriteRuntimeConfig(
            compilation.Config,
            compilation.OutputPath
        )
        runResult := RunGenericCallProgram(
            compilation.OutputPath,
            compilation.FixtureRoot
        )
        assert runResult.ExitCode == 0
        assert runResult.Stdout.Contains("async entrypoint works")
    } finally {
        CleanupExtensionCompilation(compilation)
    }
}

test "namespace-qualified interface project emits every declared type" {
    fileNames := new string[](2)
    fileNames[0] = "MathUtils.nl"
    fileNames[1] = "Geometry.nl"
    contents := new string[](2)
    contents[0] = """
namespace InteropLib

class MathUtils {
    static func Add(a: int, b: int): int {
        return a + b
    }
}
"""
    contents[1] = """
namespace InteropLib.Geometry

interface IShape {
    func Area(): double
}

class Square : IShape {
    Side: double

    constructor(side: double) {
        Side = side
    }

    func Area(): double {
        return Side * Side
    }
}
"""

    compilation := CompileNamedExtensionCallFixtureFiles(
        "NamespaceIlProject",
        "library",
        fileNames,
        contents
    )
    try {
        assert compilation.Succeeded, compilation.Diagnostics
        AssertNamespaceInterfaceFixtureTypes(compilation.OutputPath)
    } finally {
        CleanupExtensionCompilation(compilation)
    }
}
