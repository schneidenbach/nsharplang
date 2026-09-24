namespace NSharpLang.CompilerCoreSliceDirection.Tests

import System
import System.Collections.Generic
import System.IO
import System.Text

// THE SLICE DIRECTION OF `src/NSharpLang.Compiler.Core`, READ FROM ITS SOURCE.
//
// Compiler.Core's files sit in eight slice directories, lowest first: Model, Syntax, Semantics,
// Backend.Plan, Backend.Emit, CodeIntel, Tooling, Driver. Each directory is the project a later PR
// carves it into, so a file may read a top-level name declared in its own slice or in a LOWER one,
// and never in a higher one - once the slices are assemblies, a reach upward is a reference cycle
// and the carve-out cannot build. Until they are assemblies nothing but this walk sees such a reach:
// one project compiles every direction alike.
//
// THE WALK IS THE SPLIT PLAN'S OWN NAME GRAPH (census-briefs/fable-split-scripts/pr1-edges.py),
// written in N#. A top-level name is a column-0 `class`/`struct`/`enum`/`record`/`interface`/
// `union`/`type`/`func` declaration; a name declared by exactly one file is OWNED by that file. A
// file reaches an owner when an identifier it writes, not after a `.`, spells the owned name - unless
// the file itself declares that spelling at the top level or as a member (a method, a field or
// property written `Name: Type`, a local written `name := ...`, an enum member), which shadows it.
// Comments and literal text are not code; the holes of an interpolated string are. It is a lexical
// graph and deliberately conservative: it can see a reach the binder would resolve elsewhere, never
// miss one a written name makes.

// The slice directories, in the order a slice may read them: rank k reads ranks 0..k.
func SliceNames(): string[] {
    return ["Model", "Syntax", "Semantics", "Backend.Plan", "Backend.Emit", "CodeIntel", "Tooling", "Driver"]
}

// The slice a Core-relative path (always `/`-separated) sits in, or -1 outside every slice.
func SliceRank(relativePath: string): int {
    separator := relativePath.IndexOf('/')
    if separator <= 0 {
        return -1
    }
    head := relativePath.Substring(0, separator)
    names := SliceNames()
    for rank := 0; rank < names.Length; rank++ {
        if names[rank] == head {
            return rank
        }
    }
    return -1
}

func SliceName(rank: int): string {
    if rank < 0 {
        return "no slice"
    }
    return SliceNames()[rank]
}

// SOURCE TEXT WITH ONLY THE CODE LEFT IN IT.
//
// Every character of a comment, a string, a raw string or a character literal becomes a space, and a
// line break stays a line break, so each line keeps its number and each name its column. The holes
// of an interpolated string (`$"...{expr}..."`, `$"""...{expr}..."""`) are code and are kept.
static class SliceSourceText {
    static func CodeOnly(text: string): string {
        chars := text.ToCharArray()
        ScanCode(chars, 0, false)
        return new string(chars)
    }

    // Scans code from `start`. At the top level it runs to the end of the text; inside a hole it
    // stops at the brace that closes the hole and answers that brace's index.
    static func ScanCode(chars: char[], start: int, inHole: bool): int {
        index := start
        depth := 0
        while index < chars.Length {
            character := chars[index]
            if character == '/' && At(chars, index + 1, '/') {
                index = BlankToLineEnd(chars, index)
            } else if character == '/' && At(chars, index + 1, '*') {
                index = BlankBlockComment(chars, index)
            } else if character == '$' && At(chars, index + 1, '"') {
                chars[index] = ' '
                index = ScanInterpolated(chars, index + 1)
            } else if character == '"' {
                index = BlankString(chars, index)
            } else if character == '\'' {
                index = BlankCharacterLiteral(chars, index)
            } else {
                if inHole && character == '{' {
                    depth = depth + 1
                } else if inHole && character == '}' {
                    if depth == 0 {
                        return index
                    }
                    depth = depth - 1
                }
                index = index + 1
            }
        }
        return chars.Length
    }

    static func At(chars: char[], index: int, expected: char): bool => index < chars.Length && chars[index] == expected

    static func IsTripleQuote(chars: char[], index: int): bool => At(chars, index, '"') && At(chars, index + 1, '"') && At(chars, index + 2, '"')

    static func Blank(chars: char[], index: int) {
        if index < chars.Length && chars[index] != '\n' && chars[index] != '\r' {
            chars[index] = ' '
        }
    }

    static func BlankToLineEnd(chars: char[], start: int): int {
        index := start
        while index < chars.Length && chars[index] != '\n' {
            Blank(chars, index)
            index = index + 1
        }
        return index
    }

    static func BlankBlockComment(chars: char[], start: int): int {
        index := start + 2
        Blank(chars, start)
        Blank(chars, start + 1)
        while index < chars.Length {
            if chars[index] == '*' && At(chars, index + 1, '/') {
                Blank(chars, index)
                Blank(chars, index + 1)
                return index + 2
            }
            Blank(chars, index)
            index = index + 1
        }
        return index
    }

    // A plain string or a raw `"""` one; answers the index after its closing quote. A plain string
    // never crosses a line, so an unterminated one stops at the line break.
    static func BlankString(chars: char[], start: int): int {
        if IsTripleQuote(chars, start) {
            index := start + 3
            Blank(chars, start)
            Blank(chars, start + 1)
            Blank(chars, start + 2)
            while index < chars.Length {
                if IsTripleQuote(chars, index) {
                    Blank(chars, index)
                    Blank(chars, index + 1)
                    Blank(chars, index + 2)
                    return index + 3
                }
                Blank(chars, index)
                index = index + 1
            }
            return index
        }

        Blank(chars, start)
        index := start + 1
        while index < chars.Length && chars[index] != '\n' {
            character := chars[index]
            Blank(chars, index)
            if character == '\\' {
                Blank(chars, index + 1)
                index = index + 2
            } else if character == '"' {
                return index + 1
            } else {
                index = index + 1
            }
        }
        return index
    }

    // `$"` or `$"""` at `quote` (the `$` is already blank). Literal text is blanked; each hole is
    // handed back to `ScanCode`. `{{` and `}}` are literal braces. In a raw literal a brace group that
    // does not close on its own line is literal text, not a hole.
    static func ScanInterpolated(chars: char[], quote: int): int {
        raw := IsTripleQuote(chars, quote)
        index := quote + 1
        Blank(chars, quote)
        if raw {
            Blank(chars, quote + 1)
            Blank(chars, quote + 2)
            index = quote + 3
        }
        while index < chars.Length {
            character := chars[index]
            if raw && IsTripleQuote(chars, index) {
                Blank(chars, index)
                Blank(chars, index + 1)
                Blank(chars, index + 2)
                return index + 3
            }
            if !raw && character == '\n' {
                return index
            }
            if !raw && character == '"' {
                Blank(chars, index)
                return index + 1
            }
            if !raw && character == '\\' {
                Blank(chars, index)
                Blank(chars, index + 1)
                index = index + 2
                continue
            }
            if (character == '{' && At(chars, index + 1, '{')) || (character == '}' && At(chars, index + 1, '}')) {
                Blank(chars, index)
                Blank(chars, index + 1)
                index = index + 2
                continue
            }
            if character == '{' && (!raw || ClosesOnItsLine(chars, index)) {
                Blank(chars, index)
                close := ScanCode(chars, index + 1, true)
                Blank(chars, close)
                index = close + 1
                continue
            }
            Blank(chars, index)
            index = index + 1
        }
        return index
    }

    static func ClosesOnItsLine(chars: char[], open: int): bool {
        index := open + 1
        while index < chars.Length && chars[index] != '\n' {
            if chars[index] == '}' {
                return true
            }
            index = index + 1
        }
        return false
    }

    // `'x'`, `'\n'`, `'A'`. A quote with no partner a few characters along its own line is not
    // a literal and is left alone.
    static func BlankCharacterLiteral(chars: char[], start: int): int {
        index := start + 1
        while index < chars.Length && index <= start + 8 && chars[index] != '\n' {
            if chars[index] == '\\' {
                index = index + 2
            } else if chars[index] == '\'' {
                for blanked := start; blanked <= index; blanked++ {
                    Blank(chars, blanked)
                }
                return index + 1
            } else {
                index = index + 1
            }
        }
        return start + 1
    }
}

// One identifier written in a line of code.
class SliceWord {
    Text: string
    Column: int
    AfterDot: bool

    constructor(text: string, column: int, afterDot: bool) {
        Text = text
        Column = column
        AfterDot = afterDot
    }
}

static class SliceLines {
    static func IsIdentifierStart(character: char): bool => (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') || character == '_'

    static func IsIdentifierPart(character: char): bool => IsIdentifierStart(character) || (character >= '0' && character <= '9')

    // Every identifier in the line, in order. A word that starts with a digit is a number, not a name.
    static func Words(line: string): List<SliceWord> {
        words := new List<SliceWord>()
        index := 0
        while index < line.Length {
            if !IsIdentifierPart(line[index]) {
                index = index + 1
                continue
            }
            end := index
            while end < line.Length && IsIdentifierPart(line[end]) {
                end = end + 1
            }
            if IsIdentifierStart(line[index]) {
                words.Add(new SliceWord(line.Substring(index, end - index), index, index > 0 && line[index - 1] == '.'))
            }
            index = end
        }
        return words
    }

    static func IsIndented(line: string): bool => line.Length > 0 && (line[0] == ' ' || line[0] == '\t')

    static func IsImportOrNamespace(line: string): bool {
        trimmed := line.TrimStart()
        return StartsWithWord(trimmed, "import") || StartsWithWord(trimmed, "namespace")
    }

    static func StartsWithWord(text: string, word: string): bool => text.StartsWith(word, StringComparison.Ordinal) && text.Length > word.Length && (text[word.Length] == ' ' || text[word.Length] == '\t')

    static func IsDeclarationModifier(word: string): bool {
        for modifier in ["public", "private", "internal", "protected", "sealed", "abstract", "static", "partial", "readonly", "ref", "extern", "duck", "soa", "async", "unsafe", "override", "virtual", "let"] {
            if word == modifier {
                return true
            }
        }
        return false
    }

    static func IsTypeKeyword(word: string): bool {
        for keyword in ["class", "struct", "enum", "record", "interface", "union", "type"] {
            if word == keyword {
                return true
            }
        }
        return false
    }

    // The name a column-0 line declares at the top level, or "".
    static func TopLevelName(line: string): string {
        if line.Length == 0 || IsIndented(line) {
            return ""
        }
        words := Words(line)
        position := 0
        while position < words.Count && IsDeclarationModifier(words[position].Text) {
            position = position + 1
        }
        if position + 1 < words.Count && (IsTypeKeyword(words[position].Text) || words[position].Text == "func") {
            return words[position + 1].Text
        }
        return ""
    }

    // The name an indented line declares as a member of what encloses it, or "": `func Name`,
    // `Name: Type`, `name := value`, or an enum member alone on its line.
    static func MemberName(line: string): string {
        if !IsIndented(line) {
            return ""
        }
        trimmed := line.Trim()
        words := Words(trimmed)
        if words.Count == 0 || words[0].Column != 0 {
            return ""
        }
        position := 0
        while position < words.Count && IsDeclarationModifier(words[position].Text) {
            position = position + 1
        }
        if position < words.Count && words[position].Text == "func" {
            if position + 1 < words.Count {
                return words[position + 1].Text
            }
            return ""
        }
        if position < words.Count {
            candidate := words[position]
            rest := trimmed.Substring(candidate.Column + candidate.Text.Length).TrimStart()
            if rest.StartsWith(":", StringComparison.Ordinal) {
                return candidate.Text
            }
        }
        if words.Count == 1 && Char.IsUpper(words[0].Text[0]) {
            tail := trimmed.Substring(words[0].Text.Length).Trim()
            if tail.Length == 0 || tail == "," {
                return words[0].Text
            }
        }
        return ""
    }
}

class SliceSourceFile {
    RelativePath: string
    Rank: int
    IsEstate: bool
    Lines: string[]
    Declared: HashSet<string>
    Shadowed: HashSet<string>

    constructor(relativePath: string, text: string) {
        RelativePath = relativePath
        Rank = SliceRank(relativePath)
        IsEstate = relativePath.EndsWith(".tests.nl", StringComparison.Ordinal)
        Lines = SliceSourceText.CodeOnly(text).Replace("\r", "").Split('\n')
        Declared = new HashSet<string>(StringComparer.Ordinal)
        Shadowed = new HashSet<string>(StringComparer.Ordinal)
        for line in Lines {
            topLevel := SliceLines.TopLevelName(line)
            if topLevel.Length > 0 {
                Declared.Add(topLevel)
                Shadowed.Add(topLevel)
            }
            member := SliceLines.MemberName(line)
            if member.Length > 0 {
                Shadowed.Add(member)
            }
        }
    }
}

// One written name that resolves to a top-level name another file owns.
class SliceReference {
    From: SliceSourceFile
    To: SliceSourceFile
    Name: string
    Line: int

    constructor(from: SliceSourceFile, to: SliceSourceFile, name: string, line: int) {
        From = from
        To = to
        Name = name
        Line = line
    }

    IsUpward: bool => To.Rank > From.Rank

    Text: string => From.RelativePath + ":" + Line.ToString() + " [" + SliceName(From.Rank) + "] reaches `" + Name + "` in " + To.RelativePath + " [" + SliceName(To.Rank) + "]"
}

class SliceGraph {
    Files: List<SliceSourceFile>
    ProductReferences: List<SliceReference>
    EstateReferences: List<SliceReference>

    constructor(files: List<SliceSourceFile>) {
        Files = files
        ProductReferences = new List<SliceReference>()
        EstateReferences = new List<SliceReference>()

        // A product file reads product names only; an estate file reads either, and a name declared
        // by two files of either kind has no owner.
        productOwners := Owners(files, false)
        allOwners := Owners(files, true)
        for file in files {
            owners := file.IsEstate ? allOwners : productOwners
            references := file.IsEstate ? EstateReferences : ProductReferences
            for lineIndex := 0; lineIndex < file.Lines.Length; lineIndex++ {
                line := file.Lines[lineIndex]
                if SliceLines.IsImportOrNamespace(line) {
                    continue
                }
                for word in SliceLines.Words(line) {
                    if word.AfterDot || file.Shadowed.Contains(word.Text) {
                        continue
                    }
                    owner: SliceSourceFile? = null
                    if owners.TryGetValue(word.Text, out owner) && owner != null && !Object.ReferenceEquals(owner, file) {
                        references.Add(new SliceReference(file, owner, word.Text, lineIndex + 1))
                    }
                }
            }
        }
    }

    // Each top-level name declared by exactly one file, mapped to that file.
    static func Owners(files: List<SliceSourceFile>, includeEstate: bool): Dictionary<string, SliceSourceFile> {
        owners := new Dictionary<string, SliceSourceFile>(StringComparer.Ordinal)
        ambiguous := new HashSet<string>(StringComparer.Ordinal)
        for file in files {
            if file.IsEstate && !includeEstate {
                continue
            }
            for name in file.Declared {
                if owners.ContainsKey(name) {
                    ambiguous.Add(name)
                } else {
                    owners[name] = file
                }
            }
        }
        for name in ambiguous {
            owners.Remove(name)
        }
        return owners
    }

    // Every `.nl` file under `coreRoot` except build output, in ordinal path order.
    static func Load(coreRoot: string): SliceGraph {
        paths := new List<string>()
        for path in Directory.GetFiles(coreRoot, "*.nl", SearchOption.AllDirectories) {
            relative := Path.GetRelativePath(coreRoot, path).Replace('\\', '/')
            if !relative.StartsWith("bin/", StringComparison.Ordinal) && !relative.StartsWith("obj/", StringComparison.Ordinal) && relative.IndexOf("/bin/", StringComparison.Ordinal) < 0 && relative.IndexOf("/obj/", StringComparison.Ordinal) < 0 {
                paths.Add(relative)
            }
        }
        paths.Sort(StringComparer.Ordinal)
        files := new List<SliceSourceFile>()
        for relative in paths {
            files.Add(new SliceSourceFile(relative, File.ReadAllText(Path.Combine(coreRoot, relative))))
        }
        return new SliceGraph(files)
    }

    func Unplaced(): List<string> {
        unplaced := new List<string>()
        for file in Files {
            if file.Rank < 0 {
                unplaced.Add(file.RelativePath)
            }
        }
        return unplaced
    }

    func ProductFileCount(rank: int): int {
        count := 0
        for file in Files {
            if !file.IsEstate && file.Rank == rank {
                count = count + 1
            }
        }
        return count
    }

    static func Upward(references: List<SliceReference>): List<SliceReference> {
        upward := new List<SliceReference>()
        for reference in references {
            if reference.IsUpward {
                upward.Add(reference)
            }
        }
        return upward
    }

    // At most `limit` references, one per line, then how many more there were.
    static func Report(references: List<SliceReference>, limit: int): string {
        builder := new StringBuilder()
        shown := 0
        for reference in references {
            if shown == limit {
                break
            }
            builder.Append("\n  ").Append(reference.Text)
            shown = shown + 1
        }
        if references.Count > shown {
            builder.Append("\n  ... and ").Append((references.Count - shown).ToString()).Append(" more")
        }
        return builder.ToString()
    }
}
