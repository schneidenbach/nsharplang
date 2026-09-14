namespace NSharpLang.CensusFlowRules.Tests

import System
import System.Text


// A MEMBER'S NULLABILITY IS THE MOST-DERIVED OVERRIDE'S, NOT THE BASE DECLARATION'S.
//
// `object.ToString()` is annotated `string?` in the BCL, and every type that overrides it with a
// non-null `string` says something stronger about itself. Member lookup on a receiver has to answer
// from the override the receiver's STATIC type actually reaches — a source override, an override it
// INHERITS from a source base, or a reflected one in the BCL — or every `x.ToString()` in a
// converted file becomes an NL202 the author cannot act on.
//
// The whole point of this file is that it COMPILES: each function returns a non-nullable `string`
// (or `bool`, or `int`) from a member whose BASE declaration is nullable, so an owner that answered
// from the base would fail here, and the sibling `.tests.nl` runs them. The BOUNDARY — a receiver
// whose chain has NO override at all keeps `object`'s `string?`, and NL202 there is a TRUE positive
// C# warns about too — is stated in the estate, beside `AnalyzerMemberResolution`.
class Labelled {
    Name: string

    constructor(name: string) {
        Name = name
    }

    override func ToString(): string {
        return Name
    }

    override func Equals(other: object?): bool {
        if other is Labelled value {
            return value.Name == Name
        }

        return false
    }

    override func GetHashCode(): int {
        return Name.Length
    }
}

// NO OVERRIDE OF ITS OWN: what it reaches is the BASE's override, and that is still non-null.
class Marked: Labelled {
    Tag: int

    constructor(name: string, tag: int): base(name) {
        Tag = tag
    }
}

func FormatSource(value: Labelled): string => value.ToString()

func FormatInherited(value: Marked): string => value.ToString()

func SourceEquals(left: Labelled, right: Labelled): bool => left.Equals(right)

func SourceHash(value: Labelled): int => value.GetHashCode()

// THE REFLECTED HALF: the BCL's own overrides say `string`, and a receiver typed as one of them
// reaches the override rather than `object`'s declaration.
func FormatBuilder(value: StringBuilder): string => value.ToString()

func FormatException(value: Exception): string => value.ToString()

func FormatVersion(value: Version): string => value.ToString()

func FormatInt(value: int): string => value.ToString()

func FormatString(value: string): string => value.ToString()

func MakeLabelled(name: string): Labelled => new Labelled(name)

func MakeMarked(name: string, tag: int): Marked => new Marked(name, tag)
