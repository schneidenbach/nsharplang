namespace NSharpLang.DiagnosticHonesty.Tests

import System
import System.Collections.Generic
import System.Diagnostics
import System.IO


// WHAT THE COMPILER SAYS, MEASURED BY RUNNING IT.
//
// The estate proves the rules; this proves the PRODUCT. Every claim below is made against the bytes
// the shipped `nlc` writes for a program held here as a literal — no harness in the middle, no
// analyzer object constructed in-process, nothing that can be true of a code path a user never
// takes. It is the same instrument `tests/native/error-docs-contract` uses on the documentation
// pages, pointed at the sentences instead.
//
// THE ONE THING A CONTRACT LIKE THIS MUST PROVE ABOUT ITSELF IS THAT IT READS ANYTHING AT ALL. A
// sweep for an absent substring passes trivially when the reader is empty, and the error-docs slice
// found exactly that failure: `nlc check --text` writes its DIAGNOSTICS TO STDERR and only its
// summary to stdout, so a harness reading stdout alone saw nothing and approved everything. Both
// streams are read here, every sweep asserts the run produced diagnostics before it asserts what
// they do not say, and one control asserts the sweep CAN see the forbidden characters when they are
// legitimately present.
class DhProbe {
    static func RepositoryRoot(): string {
        current: string? = Path.GetFullPath(Environment.CurrentDirectory)
        while current != null {
            value := current ?? ""
            if File.Exists(Path.Combine(value, "AGENTS.md")) && Directory.Exists(Path.Combine(value, "src")) && Directory.Exists(Path.Combine(value, "tests")) {
                return value
            }

            parent := Path.GetDirectoryName(value)
            if parent == null || parent == "" || parent == value {
                current = null
            } else {
                current = parent
            }
        }

        throw new InvalidOperationException("Could not locate the repository root above this test tree.")
    }

    static func CliPath(): string {
        root := DhProbe.RepositoryRoot()
        cli := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(root, "src"), "NSharpLang.Cli"), "bin"), "Debug"), "net10.0")
        return Path.Combine(cli, "Cli.dll")
    }

    static func WorkspaceRoot(): string {
        return Path.Combine(Path.GetTempPath(), "nsharp-diagnostic-honesty")
    }

    // `library` so a probe never has to invent a `main` it would then have to explain. `companions`
    // is zero or more further files, each introduced by its own `// FILE <name>.nl` header line —
    // the same shape the error-docs contract uses, so a multi-file rule can be stated here too.
    static func Run(name: string, command: string, source: string, companions: string): string {
        directory := Path.Combine(DhProbe.WorkspaceRoot(), name)
        if Directory.Exists(directory) {
            Directory.Delete(directory, true)
        }

        Directory.CreateDirectory(directory)
        File.WriteAllText(Path.Combine(directory, "project.yml"), "name: DiagnosticHonestyProbe\nversion: 1.0.0\noutputType: library\ntargetFramework: net10.0\n")
        File.WriteAllText(Path.Combine(directory, "Program.nl"), source)
        DhWriteCompanions(directory, companions)

        arguments := "\"" + DhProbe.CliPath() + "\" " + command + " --project \"" + directory + "\" --text"
        startInfo := new ProcessStartInfo("dotnet", arguments)
        startInfo.RedirectStandardOutput = true
        startInfo.RedirectStandardError = true
        startInfo.UseShellExecute = false
        process := new Process { StartInfo: startInfo }
        process.Start()

        // BOTH STREAMS. Diagnostics go to stderr and the summary to stdout; a reader that takes one
        // of them is a contract that reads nothing.
        errorText := process.StandardError.ReadToEnd()
        standardText := process.StandardOutput.ReadToEnd()
        process.WaitForExit()
        process.Dispose()
        Directory.Delete(directory, true)
        return errorText + "\n" + standardText
    }

    static func Check(name: string, source: string): string {
        return DhProbe.Run(name, "check", source, "")
    }
}

// A companion name may carry a directory (`sub/User.nl`), because the import rule this file
// contracts is ABOUT which directory a path is measured from and cannot be stated in one flat folder.
func DhWriteCompanion(directory: string, name: string, text: string) {
    path := Path.Combine(directory, name)
    parent := Path.GetDirectoryName(path)
    if parent != null {
        Directory.CreateDirectory(parent ?? directory)
    }

    File.WriteAllText(path, text)
}

func DhWriteCompanions(directory: string, companions: string) {
    if companions.Length == 0 {
        return
    }

    header := "// FILE "
    lines := companions.Split('\n')
    currentName := ""
    currentText := ""
    index := 0
    while index < lines.Length {
        line := lines[index]
        if line.StartsWith(header, StringComparison.Ordinal) {
            if currentName.Length > 0 {
                DhWriteCompanion(directory, currentName, currentText)
            }

            currentName = line.Substring(header.Length).Trim()
            currentText = line + "\n"
        } else if currentName.Length > 0 {
            currentText = currentText + line + "\n"
        }

        index = index + 1
    }

    if currentName.Length > 0 {
        DhWriteCompanion(directory, currentName, currentText)
    }
}

// How many diagnostic headers the run printed. The header is matched by CONTENT — a bracketed code,
// a severity word and the file position — rather than by the box-drawing rule it is padded with, so
// the match does not depend on how the child process's bytes survive the pipe.
func DhDiagnosticCount(output: string): int {
    count := 0
    lines := output.Split('\n')
    index := 0
    while index < lines.Length {
        line := lines[index].Replace("\r", "")
        bracket := line.IndexOf("[", StringComparison.Ordinal)
        if bracket >= 0 && line.IndexOf("] ", StringComparison.Ordinal) > bracket && line.IndexOf("Program.nl:", StringComparison.Ordinal) > bracket {
            count = count + 1
        }

        index = index + 1
    }

    return count
}

func DhCodeCount(output: string, code: string): int {
    count := 0
    lines := output.Split('\n')
    marker := "[" + code + "]"
    index := 0
    while index < lines.Length {
        if lines[index].IndexOf(marker, StringComparison.Ordinal) >= 0 {
            count = count + 1
        }

        index = index + 1
    }

    return count
}

func DhCarriesPlaceholder(output: string): bool {
    return output.IndexOf("<error>", StringComparison.Ordinal) >= 0
}

// ═══ THE PLACEHOLDER SWEEP ════════════════════════════════════════════════════════════════════
//
// Each row is `name|source`, and every source is a shape that makes the recovery parser mint its
// `<error>` placeholder — a name it could not read in a parameter list, a field, a declaration head,
// an enum body, a type position. NONE of them contains the characters `<error>` in its own text, so
// any occurrence in the output came from the compiler and not from the echo of a source line.
//
// Before this guard these five printed twenty-three sentences quoting the placeholder between them:
// `Identifier '<error>' starts with a non-letter character`, `A type named '<error>' already
// exists`, `Type '<error>' not found` and `Parameter '<error>' in 'main' is never read`.
func DhPlaceholderPrograms(): List<string> {
    programs := new List<string>()
    programs.Add("parameter|func Add(a: int, 5: int): int {\n    return a\n}\n")
    programs.Add("field|class Box {\n    5: int\n}\n")
    programs.Add("declaration-head|func () {\n}\n")
    programs.Add("class-head|class {\n}\n")
    programs.Add("enum-newlines|enum Color {\n    Red\n    Green\n}\n\nfunc Pick(): Color {\n    return Color.Red\n}\n")
    programs.Add("field-without-type|class User {\n    Name:\n}\n\nfunc Read(user: User): string {\n    return user.Name\n}\n")
    return programs
}

func DhPlaceholderLeaks(): string {
    leaks := ""
    programs := DhPlaceholderPrograms()
    index := 0
    while index < programs.Count {
        row := programs[index]
        separator := row.IndexOf("|", StringComparison.Ordinal)
        name := row.Substring(0, separator)
        source := row.Substring(separator + 1)
        output := DhProbe.Check("placeholder-" + name, source)
        if DhDiagnosticCount(output) == 0 {
            leaks = leaks + name + ":REPORTED-NOTHING-so-this-row-proves-nothing;"
        }

        if DhCarriesPlaceholder(output) {
            leaks = leaks + name + ":PRINTED-THE-PLACEHOLDER;"
        }

        index = index + 1
    }

    return leaks
}

test "the built CLI these contracts run their programs through is present" {
    assert File.Exists(DhProbe.CliPath()), DhProbe.CliPath()
}

test "NO shape that makes the parser mint its `<error>` placeholder can print it — six programs, each of which DOES report" {
    assert DhPlaceholderLeaks() == "", DhPlaceholderLeaks()
}

test "the sweep is not vacuous: it SEES the characters when the source itself carries them, because the echoed snippet is deliberately not guarded" {
    source := "func Run() {\n    message := \"<error>\"\n}\n"
    output := DhProbe.Check("placeholder-liveness", source)
    assert DhDiagnosticCount(output) > 0, output
    // The unused-local report survives — its own MESSAGE names `message`, not the placeholder — and
    // its snippet echoes the user's line back verbatim, characters and all. That is what proves the
    // reader above can see these bytes at all.
    assert DhCodeCount(output, "NL001") == 1, output
    assert DhCarriesPlaceholder(output), output
}

test "the suppressed cascade takes NOTHING true with it — the one report that names what the user wrote survives" {
    // `func Add(a: int, 5: int)`: the parser says what it found, at the character it found it.
    parameter := DhProbe.Check("survivor-parameter", "func Add(a: int, 5: int): int {\n    return a\n}\n")
    assert DhCodeCount(parameter, "NL102") == 1, parameter
    assert !DhCarriesPlaceholder(parameter), parameter

    // `class Box { 5: int }`: before the guard this printed three diagnostics, two of them about a
    // type and an identifier named `<error>`. One is left and it is the true one.
    field := DhProbe.Check("survivor-field", "class Box {\n    5: int\n}\n")
    assert DhDiagnosticCount(field) == 1, field
    assert DhCodeCount(field, "NL102") == 1, field

    // A field with no type still reports the genuine consequence — the member does not exist — and
    // no longer reports `Type '<error>' not found` beside it.
    consequence := DhProbe.Check("survivor-consequence", "class User {\n    Name:\n}\n\nfunc Read(user: User): string {\n    return user.Name\n}\n")
    assert DhCodeCount(consequence, "NL102") == 1, consequence
    assert DhCodeCount(consequence, "NL303") == 1, consequence
    assert DhCodeCount(consequence, "NL201") == 0, consequence
    assert !DhCarriesPlaceholder(consequence), consequence
}

test "a well-formed program is untouched by the guard: it reports nothing at all" {
    output := DhProbe.Check("clean", "func Total(prices: int[]): int {\n    sum := 0\n    for price in prices {\n        sum = sum + price\n    }\n\n    return sum\n}\n")
    assert DhDiagnosticCount(output) == 0, output
}

// ═══ NL701 — THE HINT AND THE RESOLVER AGREE ══════════════════════════════════════════════════
//
// A hint is a claim about the compiler, and this one was the opposite of the truth: it said "The
// path should be relative to your project root" while `FileResolver.ResolveFilePath` measures a
// `./` or `../` path from the IMPORTING FILE and everything else from the project root. Every
// example in the language writes the `./` form, so the one sentence a stuck reader had to go on
// sent them the wrong way.
//
// The rule is measured here before it is quoted: three probes, one per arm, from a file that is NOT
// at the project root — which is the only place the two rules can disagree.
func DhImportProbe(name: string, importPath: string): string {
    companions := "// FILE Helper.nl\nnamespace Probe.Helpers\n\nfunc Decorate(value: string): string {\n    return \"<\" + value + \">\"\n}\n"
    companions = companions + "// FILE sub/User.nl\nimport \"" + importPath + "\"\n\nfunc Use(value: string): string {\n    return Decorate(value)\n}\n"
    return DhProbe.Run(name, "check", "func Root(): int {\n    return 1\n}\n", companions)
}

test "NL701's rule, measured: from a file in a subdirectory, `./Helper.nl` FAILS and `../Helper.nl` and the bare `Helper` both resolve" {
    // `./` is measured from the importing file, so a root sibling is NOT beside it. Line 2 of the
    // companion, because its `// FILE` header is line 1 — what the page shows is what runs.
    dotSlash := DhImportProbe("nl701-dot-slash", "./Helper.nl")
    assert DhCodeCount(dotSlash, "NL701") == 1, dotSlash

    // `../` is measured from the importing file too, and reaches the root.
    dotDot := DhImportProbe("nl701-dot-dot", "../Helper.nl")
    assert DhCodeCount(dotDot, "NL701") == 0, dotDot

    // Anything without a leading `./` or `../` is measured from the PROJECT ROOT — and the `.nl`
    // extension is optional, which is the second half of the hint.
    bare := DhImportProbe("nl701-bare", "Helper")
    assert DhCodeCount(bare, "NL701") == 0, bare
}

test "NL701 PRINTS that rule — both halves of it — and no longer prints the one that is false" {
    output := DhProbe.Check("nl701-hint", "import \"./formatting.nl\"\n\nfunc Greet(name: string): string {\n    return \"hello \" + name\n}\n")
    assert DhCodeCount(output, "NL701") == 1, output
    assert output.IndexOf("A path starting with './' or '../' is relative to THIS file; any other path is relative to the project root.", StringComparison.Ordinal) >= 0, output
    assert output.IndexOf("The '.nl' extension is optional", StringComparison.Ordinal) >= 0, output
    assert output.IndexOf("The path should be relative to your project root.", StringComparison.Ordinal) < 0, output
}

// ═══ NL321 AND NL702 — A SUGGESTION IS A SPELLING THE COMPILER ACCEPTS ════════════════════════
//
// The strongest thing a contract can say about a suggested fix is that it BUILDS, so these run the
// suggested text itself. Both diagnostics used to fail that: NL321 offered `new T[] { ... }`, which
// parses and then stops the build at NL103 `parse.function`; NL702 offered "add an alias and qualify
// the symbol", which for a colliding FUNCTION stops at NL103 `emit.call.static-member-unmodeled`.
//
// The refused spellings are pinned as refused, not merely dropped, so that the day the backend
// admits either one the contract fails and asks for the suggestion back.

test "NL321 suggests the array literal, and the array literal COMPILES where `new T[] { ... }` still does not" {
    reported := DhProbe.Check("nl321", "func Make(): int[] {\n    return new int[4](7)\n}\n")
    assert DhCodeCount(reported, "NL321") == 1, reported
    assert reported.IndexOf("write the elements as a list — 'values := [1, 2, 3]'.", StringComparison.Ordinal) >= 0, reported
    assert reported.IndexOf("new T[] { ... }", StringComparison.Ordinal) < 0, reported

    // THE SUGGESTED TEXT, RUN.
    literal := DhProbe.Check("nl321-suggested-literal", "func Values(): int[] {\n    values := [1, 2, 3]\n    return values\n}\n")
    assert DhDiagnosticCount(literal) == 0, literal

    sized := DhProbe.Check("nl321-suggested-sized", "func Zeros(n: int): int[] {\n    return new int[n]\n}\n")
    assert DhDiagnosticCount(sized) == 0, sized

    // THE SPELLING THAT WAS SUGGESTED AND DOES NOT BUILD, pinned as not building.
    refused := DhProbe.Check("nl321-old-suggestion", "func Values(): int[] {\n    return new int[] { 1, 2, 3 }\n}\n")
    assert DhCodeCount(refused, "NL103") == 1, refused
    assert refused.IndexOf("parse.function", StringComparison.Ordinal) >= 0, refused
}

func DhCollisionProbe(name: string, declarationA: string, declarationB: string, program: string): string {
    companions := "// FILE text.nl\nnamespace Lib.Text\n\n" + declarationA
    companions = companions + "// FILE money.nl\nnamespace Lib.Money\n\n" + declarationB
    return DhProbe.Run(name, "check", program, companions)
}

func DhFormatText(): string {
    return "func Format(value: int): string {\n    return value.ToString()\n}\n"
}

func DhFormatMoney(name: string): string {
    return "func " + name + "(value: int): string {\n    return \"$\" + value.ToString()\n}\n"
}

func DhTagType(memberName: string): string {
    return "class Tag {\n    " + memberName + ": string\n\n    constructor(value: string) {\n        " + memberName + " = value\n    }\n}\n"
}

test "NL702 on a colliding FUNCTION suggests a rename, and the rename COMPILES where the alias-qualified call still does not" {
    collision := DhCollisionProbe("nl702-function", DhFormatText(), DhFormatMoney("Format"), "import \"./text.nl\"\nimport \"./money.nl\"\n\nfunc Describe(value: int): string {\n    return Format(value)\n}\n")
    assert DhCodeCount(collision, "NL702") == 1, collision
    assert collision.IndexOf("Rename one of the two 'Format' declarations", StringComparison.Ordinal) >= 0, collision

    // THE SUGGESTED FIX, RUN.
    renamed := DhCollisionProbe("nl702-renamed", DhFormatText(), DhFormatMoney("FormatMoney"), "import \"./text.nl\"\nimport \"./money.nl\"\n\nfunc Describe(value: int): string {\n    return Format(value)\n}\n\nfunc DescribePrice(value: int): string {\n    return FormatMoney(value)\n}\n")
    assert DhDiagnosticCount(renamed) == 0, renamed

    // THE FIX THAT WAS SUGGESTED AND DOES NOT BUILD, pinned as not building — the alias clears
    // NL702 and the call through it then stops the build.
    aliased := DhCollisionProbe("nl702-aliased-call", DhFormatText(), DhFormatMoney("Format"), "import \"./text.nl\"\nimport \"./money.nl\" as Money\n\nfunc Describe(value: int): string {\n    return Format(value)\n}\n\nfunc DescribePrice(value: int): string {\n    return Money.Format(value)\n}\n")
    assert DhCodeCount(aliased, "NL702") == 0, aliased
    assert DhCodeCount(aliased, "NL103") == 1, aliased
    assert aliased.IndexOf("emit.call.static-member-unmodeled", StringComparison.Ordinal) >= 0, aliased
}

test "NL702 on a colliding TYPE keeps the alias, because an alias-qualified TYPE does compile" {
    collision := DhCollisionProbe("nl702-type", DhTagType("Name"), DhTagType("Code"), "import \"./text.nl\"\nimport \"./money.nl\"\n\nfunc Make(name: string): Tag {\n    return new Tag(name)\n}\n")
    assert DhCodeCount(collision, "NL702") == 1, collision
    assert collision.IndexOf("write the type as `Alias.Tag`", StringComparison.Ordinal) >= 0, collision

    // THE SUGGESTED FIX, RUN — the alias-qualified type in a signature AND at a `new`.
    aliased := DhCollisionProbe("nl702-type-aliased", DhTagType("Name"), DhTagType("Code"), "import \"./text.nl\"\nimport \"./money.nl\" as Money\n\nfunc MakeText(name: string): Tag {\n    return new Tag(name)\n}\n\nfunc MakeMoney(code: string): Money.Tag {\n    return new Money.Tag(code)\n}\n")
    assert DhDiagnosticCount(aliased) == 0, aliased
}

// ═══ NL001 / NL012 — "NEVER READ" NOW MEANS NEVER READ ════════════════════════════════════════
//
// Both rules print "never read", and both used to measure whether the name was MENTIONED again:
// `total := 0` followed by `total = 5` and nothing else was ACCEPTED. What follows runs the shapes
// through the shipped `nlc check` — the rule, and the four boundaries that keep it from becoming a
// false positive.
func DhNL001(output: string): int {
    return DhCodeCount(output, "NL001")
}

func DhNL012(output: string): int {
    return DhCodeCount(output, "NL012")
}

test "a local that is only WRITTEN is NL001, and the sentence it prints is the true one" {
    output := DhProbe.Check("nl001-write-only", "func Run() {\n    total := 0\n    total = 5\n}\n")
    assert DhNL001(output) == 1, output
    assert output.IndexOf("Variable 'total' is declared but never read", StringComparison.Ordinal) >= 0, output
}

test "a by-value PARAMETER that is only written is NL012" {
    output := DhProbe.Check("nl012-write-only", "func Run(x: int) {\n    x = 5\n}\n")
    assert DhNL012(output) == 1, output
    assert output.IndexOf("Parameter 'x' in 'Run' is never read", StringComparison.Ordinal) >= 0, output
}

test "the three shapes that really DO read the name are untouched: compound assignment, an element write, a member write" {
    compound := DhProbe.Check("nl001-compound", "func Run(): int {\n    a := 1\n    a += 1\n    return a\n}\n")
    assert DhDiagnosticCount(compound) == 0, compound

    // An element write reads the receiver to find where to store, so `values` is used.
    element := DhProbe.Check("nl001-element", "func Run(): int {\n    values := new int[3]\n    values[0] = 1\n    return values[0]\n}\n")
    assert DhDiagnosticCount(element) == 0, element

    // A member write reads the receiver for the same reason.
    member := DhProbe.Check("nl001-member", "class Holder {\n    Value: int\n}\n\nfunc Run(): int {\n    box := new Holder()\n    box.Value = 7\n    return box.Value\n}\n")
    assert DhDiagnosticCount(member) == 0, member
}

test "a `ref` or `out` parameter's write is its USE, because the store escapes to the caller" {
    // `func Read(out value: int) { value = 23 }` is the entire purpose of an `out` parameter, and
    // reading one before assignment is not even legal — so the write has to count.
    byRef := DhProbe.Check("nl012-byref", "func Read(out value: int) {\n    value = 23\n}\n\nfunc Increment(ref count: int) {\n    count = count + 10\n}\n")
    assert DhDiagnosticCount(byRef) == 0, byRef

    // The exemption is for the WRITE, not for the modifier: a by-reference parameter nothing
    // mentions at all is still reported, and a by-VALUE neighbour on the same signature still is.
    mixed := DhProbe.Check("nl012-byref-mixed", "func Ignore(out value: int, unusedByValue: int) {\n    value = 1\n}\n")
    assert DhNL012(mixed) == 1, mixed
    assert mixed.IndexOf("Parameter 'unusedByValue' in 'Ignore'", StringComparison.Ordinal) >= 0, mixed
}

test "the `_` opt-out both rules point at still works on a write-only binding" {
    output := DhProbe.Check("nl001-underscore", "func Run() {\n    _total := 0\n    _total = 5\n}\n\nfunc Take(_x: int) {\n    _x = 5\n}\n")
    assert DhDiagnosticCount(output) == 0, output
}

// ═══ NL010 — A `catch` CLAUSE'S TYPE IS A MENTION ═════════════════════════════════════════════
//
// The last written-type slot the lint walk did not reach. A file whose only mention of `System` was
// `catch (e: InvalidOperationException)` reported NL010 against the import it needs — an ERROR that
// fails `nlc check` on correct source, and whose `nlc fix` deletes the line.

test "an import used ONLY by a `catch` clause's exception type is not reported unused" {
    output := DhProbe.Check("nl010-catch", "import System\n\nfunc Run() {\n    try {\n        print(\"body\")\n    } catch (e: InvalidOperationException) {\n        print(\"caught\")\n    }\n}\n")
    assert DhDiagnosticCount(output) == 0, output
}

test "the same slot asks the OPPOSITE question too: a catch type with no import is NL002" {
    output := DhProbe.Check("nl010-catch-missing", "func Run() {\n    try {\n        print(\"body\")\n    } catch (e: StringBuilder) {\n        print(\"caught\")\n    }\n}\n")
    assert DhCodeCount(output, "NL002") == 1, output
}

test "an import nothing mentions at all is STILL NL010, so the widening did not silence the rule" {
    output := DhProbe.Check("nl010-live", "import System.Text\n\nfunc Run() {\n    print(\"body\")\n}\n")
    assert DhCodeCount(output, "NL010") == 1, output
}

// ═══ NL011 — EVERY OPTION THE SUGGESTION NAMES ACTUALLY CLEARS IT ═════════════════════════════
//
// The old text invited the reader to "add a comment explaining why it's safe to ignore". A comment
// is not a statement, so the reader took the advice, re-ran, and got the same error. Each option the
// new text names is run here, and so is the one it removed.
func DhCatch(name: string, body: string): string {
    return DhProbe.Run(name, "check", "import System\n\nfunc ParseCount(text: string): int {\n    try {\n        return int.Parse(text)\n    } catch (error: FormatException) {\n" + body + "    }\n\n    return 0\n}\n", "")
}

test "NL011's suggestion names four fixes and a suppression, and every one of them clears it" {
    reported := DhCatch("nl011-empty", "")
    assert DhCodeCount(reported, "NL011") == 1, reported
    assert reported.IndexOf("Log it, handle it, return a fallback, or wrap it in a `throw new ...`.", StringComparison.Ordinal) >= 0, reported
    assert reported.IndexOf("nlc:ignore NL011", StringComparison.Ordinal) >= 0, reported

    logged := DhCatch("nl011-logged", "        print(\"bad number\")\n")
    assert DhDiagnosticCount(logged) == 0, logged

    // These two END the function, so they are written without the template's trailing `return 0` —
    // which would otherwise be unreachable and report NL312 instead.
    fallback := DhProbe.Check("nl011-fallback", "import System\n\nfunc ParseCount(text: string): int {\n    try {\n        return int.Parse(text)\n    } catch (error: FormatException) {\n        return -1\n    }\n}\n")
    assert DhDiagnosticCount(fallback) == 0, fallback

    wrapped := DhProbe.Check("nl011-wrapped", "import System\n\nfunc ParseCount(text: string): int {\n    try {\n        return int.Parse(text)\n    } catch (error: FormatException) {\n        throw new InvalidOperationException(\"bad\", error)\n    }\n}\n")
    assert DhDiagnosticCount(wrapped) == 0, wrapped

    suppressed := DhProbe.Check("nl011-suppressed", "import System\n\nfunc ParseCount(text: string): int {\n    try {\n        return int.Parse(text)\n    // nlc:ignore NL011\n    } catch (error: FormatException) {\n    }\n\n    return 0\n}\n")
    assert DhDiagnosticCount(suppressed) == 0, suppressed
}

test "the option the suggestion no longer names is the one that does not work, and it still does not" {
    commented := DhCatch("nl011-comment-only", "        // not a number; zero is fine\n")
    assert DhCodeCount(commented, "NL011") == 1, commented
    assert commented.IndexOf("add a comment explaining why it's safe to ignore", StringComparison.Ordinal) < 0, commented
}

test "a bare `throw` is not an N# re-throw form, which is why the suggestion says `throw new ...`" {
    bare := DhCatch("nl011-bare-throw", "        throw\n")
    assert DhCodeCount(bare, "NL102") == 1, bare
    assert bare.IndexOf("Expected an exception expression after 'throw'", StringComparison.Ordinal) >= 0, bare
}

// ═══ THE NULL CHECK THAT CANNOT BE NULL — BOTH HALVES, AND NEITHER TWICE ══════════════════════
//
// NL003 reads the LITERAL half (`3 == null`) and needs no types to do it. The other half — a name
// whose TYPE cannot be null — the linter cannot see at all, so `count != null` on an `int` typed as
// `bool`, reached the backend and died there as `NL103 … Declined at emit.if.condition`: a sentence
// about the compiler's internals for a mistake the type system can name. The analyzer now names it
// in the linter's own words, and the two owners partition the shape rather than overlapping.

test "a null check on a value-typed NAME is reported by the analyzer, in NL003's words, where it used to be an opaque emit decline" {
    output := DhProbe.Check("nullcheck-name", "func Budget(count: int): int {\n    if count != null {\n        return 1\n    }\n\n    return 0\n}\n")
    assert DhCodeCount(output, "NL202") == 1, output
    assert output.IndexOf("This null check is unnecessary — 'int' is a value type and can never be null", StringComparison.Ordinal) >= 0, output
    assert output.IndexOf("declare it as 'int?'", StringComparison.Ordinal) >= 0, output
    // The decline it replaces is gone, not accompanied.
    assert DhCodeCount(output, "NL103") == 0, output
}

test "the two owners PARTITION the shape: a literal is NL003 alone, a name is NL202 alone, never both on one line" {
    literal := DhProbe.Check("nullcheck-literal", "func RetryBudget(): int {\n    if 3 == null {\n        return 0\n    }\n\n    return 3\n}\n")
    assert DhCodeCount(literal, "NL003") == 1, literal
    assert DhCodeCount(literal, "NL202") == 0, literal

    name := DhProbe.Check("nullcheck-name-only", "func Budget(count: int): int {\n    if count != null {\n        return 1\n    }\n\n    return 0\n}\n")
    assert DhCodeCount(name, "NL202") == 1, name
    assert DhCodeCount(name, "NL003") == 0, name
}

test "an enum, a struct and a record struct are value types too, and the suggested `?` spelling COMPILES" {
    valueTypes := DhProbe.Check("nullcheck-valuetypes", "enum Color {\n    Red,\n    Green\n}\n\nstruct Point {\n    X: int\n}\n\nfunc FromEnum(color: Color): int {\n    if color != null {\n        return 1\n    }\n\n    return 0\n}\n\nfunc FromStruct(point: Point): int {\n    if point != null {\n        return 1\n    }\n\n    return 0\n}\n")
    assert DhCodeCount(valueTypes, "NL202") == 2, valueTypes

    // THE SUGGESTED FIX, RUN.
    nullable := DhProbe.Check("nullcheck-suggested", "func Budget(count: int?): int {\n    if count != null {\n        return 1\n    }\n\n    return 0\n}\n")
    assert DhDiagnosticCount(nullable) == 0, nullable
}

test "THE NEGATIVES: a type parameter, a reference, `object` and a string are all silent" {
    // A bare `T` may be instantiated with a class, so accusing `value == null` inside a generic
    // function would be accusing correct code. This is the load-bearing negative.
    generic := DhProbe.Check("nullcheck-generic", "func Generic<T>(value: T): int {\n    if value == null {\n        return 0\n    }\n\n    return 1\n}\n")
    assert DhDiagnosticCount(generic) == 0, generic

    reference := DhProbe.Check("nullcheck-reference", "import System.Text\n\nfunc Reference(builder: StringBuilder): int {\n    if builder != null {\n        return 1\n    }\n\n    return 0\n}\n")
    assert DhDiagnosticCount(reference) == 0, reference

    boxed := DhProbe.Check("nullcheck-object", "func Boxed(value: object): int {\n    if value != null {\n        return 1\n    }\n\n    return 0\n}\n")
    assert DhDiagnosticCount(boxed) == 0, boxed

    text := DhProbe.Check("nullcheck-string", "func Text(value: string): int {\n    if value != null {\n        return 1\n    }\n\n    return 0\n}\n")
    assert DhDiagnosticCount(text) == 0, text
}

test "a type that defines its own equality keeps it — the overload is resolved BEFORE this rule is asked" {
    output := DhProbe.Check("nullcheck-overload", "struct Key {\n    Value: int\n\n    static func operator ==(left: Key, right: Key): bool {\n        return left.Value == right.Value\n    }\n\n    static func operator !=(left: Key, right: Key): bool {\n        return left.Value != right.Value\n    }\n}\n\nfunc CompareKeys(left: Key, right: Key): bool {\n    return left == right && left != right\n}\n")
    assert DhDiagnosticCount(output) == 0, output
}
