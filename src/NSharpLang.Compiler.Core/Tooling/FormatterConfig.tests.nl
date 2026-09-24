namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.IO


// `FormatterConfig` AND `FormatterConfigKernels`: THE FORMATTER'S SETTINGS, AND THE INT PARSER
// THAT READS THEM OFF DISK.
//
// NEITHER TYPE HAD A LINE OF ESTATE COVERAGE BEFORE THIS FILE. Both are N#, both are reached by
// every `nlc format` run and by the editor's formatting handler, and their only assertion layer
// anywhere was `tests/FormatterTests.cs` — a C# file, now DELETED. That makes this file the
// slice-8 `DiagnosticCatalog` shape repeating: the migration is not a move, it is the first time
// these contracts live beside the code they describe.
//
// THREE THINGS ARE STATED HERE THAT WERE ONLY IMPLICIT BEFORE:
//   (a) A PROPERTY REMEMBERS WHETHER IT WAS ASSIGNED. `FormatterConfig` stores a value AND an
//       assigned flag per setting, so "never set" and "set to the default" are the same answer —
//       which is what lets a partial `.editorconfig` leave the other two settings alone.
//   (b) A TAB INDENT IS ONE TAB PER LEVEL, whatever `IndentSize` says. `IndentSize` and
//       `UseSpaces` are not independent knobs on the same string.
//   (c) THE INT PARSER IS EXACT AT THE 32-BIT BOUNDARY IN BOTH DIRECTIONS, including the
//       asymmetric one: `-2147483648` parses and `2147483648` does not.
func FcgDefault(): FormatterConfig {
    return new FormatterConfig()
}

func FcgConfig(size: int, spaces: bool): FormatterConfig {
    config := new FormatterConfig()
    config.IndentSize = size
    config.UseSpaces = spaces
    return config
}

// `FromEditorConfig` walks a real directory looking for a real file, so the contract is stated
// against a real one. The walk itself — the parent search and the `root = true` stop — belongs to
// `LinterConfig` and is stated there.
func FcgWriteEditorConfig(content: string): string {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-formatter-config-" + Guid.NewGuid().ToString())
    Directory.CreateDirectory(directory)
    File.WriteAllText(Path.Combine(directory, ".editorconfig"), content)
    return directory
}

func FcgFromEditorConfig(content: string): FormatterConfig {
    directory := FcgWriteEditorConfig(content)
    config := FormatterConfig.FromEditorConfig(directory)
    Directory.Delete(directory, true)
    return config
}

func FcgParsed(text: string): bool {
    return FormatterConfigKernels.ParseInt(text).HasValue
}

// The C# this replaces compared against `int.TryParse(value, out var expected)`, whose `out` is 0
// when the parse fails. This is that same reading, spelled without an `out`.
func FcgParsedValue(text: string): int {
    parsed := FormatterConfigKernels.ParseInt(text)
    if parsed.HasValue {
        return parsed.Value
    }

    return 0
}

// ---- THE DEFAULTS AND THE INDENT STRING ----------------------------------------------------------

test "the default configuration is four spaces" {
    assert FcgDefault().IndentSize == 4
    assert FcgDefault().UseSpaces
    assert FcgDefault().GetIndentString() == "    "
}

test "a two-space configuration writes two spaces" {
    assert FcgConfig(2, true).GetIndentString() == "  "
}

test "a tab configuration writes ONE tab" {
    assert FcgConfig(4, false).GetIndentString() == "\t"
}

// ---- THE EDITORCONFIG READ -----------------------------------------------------------------------

// `indent_size = +2` is written with a leading sign deliberately: the value goes through
// `FormatterConfigKernels.ParseInt`, and a sign is the one thing a naive digit loop drops.
test "indent_size, indent_style and max_line_length are all read from the [*.nl] section" {
    config := FcgFromEditorConfig("root = true\n\n[*.nl]\nindent_size = +2\nindent_style = tab\nmax_line_length = 120")
    assert config.IndentSize == 2
    assert !config.UseSpaces
    assert config.MaxLineLength == 120
}

// ---- THE INT PARSER, CASE BY CASE ----------------------------------------------------------------

// Ten values, each read twice — once for whether it parsed and once for the value a caller
// would see. The deleted C# compared these against `int.TryParse`; the answers are written
// out here instead, so the contract does not depend on a second parser agreeing.
test "plain, signed, zero and the two 32-bit boundaries parse; the first value past the top does not" {
    assert FcgParsed("42")
    assert FcgParsedValue("42") == 42
    assert FcgParsed(" +7 ")
    assert FcgParsedValue(" +7 ") == 7
    assert FcgParsed("-1")
    assert FcgParsedValue("-1") == -1
    assert FcgParsed("0")
    assert FcgParsedValue("0") == 0
    assert FcgParsed("2147483647")
    assert FcgParsedValue("2147483647") == 2147483647
    assert FcgParsed("-2147483648")
    assert FcgParsedValue("-2147483648") == -2147483648
    assert !FcgParsed("2147483648")
    assert FcgParsedValue("2147483648") == 0
    assert !FcgParsed("not-an-int")
    assert FcgParsedValue("not-an-int") == 0
    assert !FcgParsed("")
    assert FcgParsedValue("") == 0
    assert !FcgParsed("   ")
    assert FcgParsedValue("   ") == 0
}

// ---- STRICTLY STRONGER THAN THE FILE THIS REPLACES ---------------------------------------------

test "assigning a property its DEFAULT value is indistinguishable from never assigning it" {
    // (a). This is what makes a PARTIAL `.editorconfig` safe, and it is also what makes every
    // configured-formatter contract in `FormatterSourceText.tests.nl` legitimate: a helper that
    // sets `IndentSize = 4` explicitly and one that leaves it alone are the same configuration.
    untouched := new FormatterConfig()
    assigned := new FormatterConfig()
    assigned.IndentSize = 4
    assigned.UseSpaces = true
    assigned.MaxLineLength = 100

    assert untouched.IndentSize == assigned.IndentSize
    assert untouched.UseSpaces == assigned.UseSpaces
    assert untouched.MaxLineLength == assigned.MaxLineLength
    assert untouched.GetIndentString() == assigned.GetIndentString()
}

test "a tab indent is ONE tab per level whatever the configured size says" {
    // (b). `IndentSize` is not a tab width. Reading it as one would indent a tab file eight times
    // too far, and no test in the deleted file could have seen it.
    assert FcgConfig(1, false).GetIndentString() == "\t"
    assert FcgConfig(4, false).GetIndentString() == "\t"
    assert FcgConfig(8, false).GetIndentString() == "\t"
    assert FcgConfig(1, true).GetIndentString() == " "
    assert FcgConfig(8, true).GetIndentString() == "        "
}

test "a missing editorconfig leaves every default in place" {
    directory := Path.Combine(Path.GetTempPath(), "nsharp-formatter-config-none-" + Guid.NewGuid().ToString())
    Directory.CreateDirectory(directory)

    config := FormatterConfig.FromEditorConfig(directory)
    assert config.IndentSize == 4
    assert config.UseSpaces
    assert config.MaxLineLength == 100

    Directory.Delete(directory, true)
}

test "a section for another language is not read" {
    config := FcgFromEditorConfig("root = true\n\n[*.cs]\nindent_size = 8\nindent_style = tab\n")
    assert config.IndentSize == 4
    assert config.UseSpaces
}

test "indent_style = space is read as spaces, and any other word is read as tabs" {
    assert FcgFromEditorConfig("root = true\n\n[*.nl]\nindent_style = space\n").UseSpaces
    assert !FcgFromEditorConfig("root = true\n\n[*.nl]\nindent_style = tab\n").UseSpaces
}

test "a max_line_length the parser cannot read leaves the default standing, rather than zeroing it" {
    // The three settings do NOT share one failure rule, and that is a decision: `indent_size` is
    // read with `ParseRequiredInt` and THROWS on a value it cannot read, while `max_line_length`
    // is read with the nullable kernel and is silently skipped. A file whose wrap width is
    // mistyped keeps formatting; a file whose indent is mistyped is a configuration error.
    config := FcgFromEditorConfig("root = true\n\n[*.nl]\nmax_line_length = wide\n")
    assert config.MaxLineLength == 100
}

test "an indent_size the parser cannot read is a configuration ERROR, not a silent default" {
    directory := FcgWriteEditorConfig("root = true\n\n[*.nl]\nindent_size = wide\n")
    assert throws FormatException {
        FormatterConfig.FromEditorConfig(directory)
    }

    Directory.Delete(directory, true)
}

test "the int parser is exact on the far side of both boundaries, which the ten sampled values are not" {
    // (c). `-2147483648` has no positive twin, so the kernel needs a special arm for it, and the
    // arm is reachable ONLY on the last digit of the number. These are the values that prove the
    // arm is not simply `>= 214748364 -> null`.
    assert FcgParsed("-2147483648")
    assert FcgParsedValue("-2147483648") == -2147483648
    assert !FcgParsed("-2147483649")
    assert !FcgParsed("2147483649")
    assert !FcgParsed("21474836480")
    assert FcgParsed("+2147483647")
    assert FcgParsedValue("+2147483647") == 2147483647
}

test "a sign with no digits after it, and a digit run with anything else in it, do not parse" {
    assert !FcgParsed("+")
    assert !FcgParsed("-")
    assert !FcgParsed("12x")
    assert !FcgParsed("x12")
    assert !FcgParsed("4 2")
    assert !FcgParsed("1.5")
    assert !FcgParsed("--1")
}

test "leading zeros, a negative zero and tab-surrounded digits all parse" {
    assert FcgParsedValue("0000000042") == 42
    assert FcgParsedValue("-0") == 0
    assert FcgParsed("-0")
    assert FcgParsedValue("\t42\t") == 42
    assert FcgParsedValue("\n 42 \r") == 42
}
