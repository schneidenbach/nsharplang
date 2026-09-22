namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic

// THE TYPE A `test` BLOCK IS LOWERED ONTO CARRIES THE IDENTITY OF THE FILE THAT WROTE IT.
//
// A `test` block is already a free function in its file's namespace — that is how the bare names in
// its body resolve — but every lowered row used to land on ONE namespace-less `NSharpTests` type, so
// the fully-qualified name a runner reports, and the only thing `--filter FullyQualifiedName~X` can
// match, was the row's own prose mangled into a method name. `./scripts/dev.sh Columnar` selected 53
// of the 3,116 rows that live in `Columnar*` files, because 53 sentences happen to say "columnar".
//
// The lowered type now spells `<the file's namespace>.<the file's stem>Tests`, which is the same
// identity the body already binds against. A filter naming a file, a type prefix or a namespace
// therefore selects the rows that file, prefix or namespace actually owns. The SIMPLE name still
// ends in `Tests`, and the method names, their attributes and the row count are untouched: this
// changes which container a row is declared on, not the row.
static class ColumnarTestTypeNames {

    // The file's own stem — `src/x/ColumnarIlEmitter.tests.nl` is `ColumnarIlEmitter`. The two
    // suffixes come off in order so a name that carries neither, or only `.nl`, is still answered.
    static func FileStem(fileName: string): string {
        stem := fileName
        separator := stem.LastIndexOf('/')
        backslash := stem.LastIndexOf('\\')
        if backslash > separator {
            separator = backslash
        }

        if separator >= 0 {
            stem = stem.Substring(separator + 1)
        }

        if stem.EndsWith(".nl", StringComparison.Ordinal) {
            stem = stem.Substring(0, stem.Length - 3)
        }

        if stem.EndsWith(".tests", StringComparison.Ordinal) {
            stem = stem.Substring(0, stem.Length - 6)
        }

        return stem
    }

    // A CLR type name cannot carry a dot that is not a namespace separator, nor a hyphen, so the
    // stem is reduced to identifier characters. A stem that reduces to nothing keeps the historical
    // name rather than inventing one.
    static func Identifier(stem: string): string {
        cleaned := ""
        for character in stem {
            if Char.IsLetterOrDigit(character) || character == '_' {
                cleaned = cleaned + character.ToString()
            }
        }

        if cleaned.Length == 0 {
            return "NSharpTests"
        }

        if Char.IsDigit(cleaned[0]) {
            return "_" + cleaned
        }

        return cleaned
    }

    static func TypeNameForFile(fileName: string): string {
        identifier := Identifier(FileStem(fileName))
        if identifier.EndsWith("Tests", StringComparison.Ordinal) {
            return identifier
        }

        return identifier + "Tests"
    }

    // The name handed to `DefineType`, which is the namespace-qualified one. A file that declares no
    // namespace keeps a global type, exactly as before.
    static func QualifiedTypeName(namespaceName: string?, fileName: string): string {
        typeName := TypeNameForFile(fileName)
        qualifier := namespaceName ?? ""
        if qualifier.Length == 0 {
            return typeName
        }

        return qualifier + "." + typeName
    }

    // Two files can reduce to one type name only when they sit in different directories under one
    // namespace. `DefineType` throws on a duplicate, so the second one is disambiguated the same way
    // a duplicate method name is.
    static func UniqueTypeName(taken: HashSet<string>, candidate: string): string {
        if taken.Add(candidate) {
            return candidate
        }

        suffix := 2
        chosen := candidate + "_" + suffix.ToString()
        while !taken.Add(chosen) {
            suffix = suffix + 1
            chosen = candidate + "_" + suffix.ToString()
        }

        return chosen
    }
}
