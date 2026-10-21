namespace NSharpLang.MemberLookup.Tests

import System
import System.Collections.Generic

// MEMBER LOOKUP ON AN INTERFACE TYPE INCLUDES `object`'S MEMBERS (C# §12.5: the base types of an
// interface are its base interfaces and `object`). Metadata never lists them on the interface, so a
// receiver whose static type is `IList<int>` reported NL303 for `ToString()` and `GetType()`, and the
// emitter declined the same call as an unmodeled instance member (GitHub #240).
interface IShape {
    func Area(): int
}

interface IPrintable {
    func ToString(format: string): string

    func Equals(other: object): bool
}

class Square: IShape {
    func Area(): int => 4

    override func ToString(): string => "square"
}

class Printable: IPrintable {
    func ToString(format: string): string => "formatted:" + format

    func Equals(other: object): bool => other.ToString() == "match"
}

func listText(items: IList<int>): string? => items.ToString()

func listTypeName(items: IList<int>): string => items.GetType().Name

func listHash(items: IList<int>): int => items.GetHashCode()

func listEquals(items: IList<int>, other: object): bool => items.Equals(other)

func sequenceTypeName(items: IEnumerable<string>): string => items.GetType().Name

// `IFormattable` declares `ToString(string, IFormatProvider)`; `object.ToString()` stays beside it.
func formattedDefault(value: IFormattable): string? => value.ToString()

func formattedHex(value: IFormattable): string => value.ToString("X", null)

// A type parameter constrained to an interface is that interface for member lookup.
func constrainedText<T>(items: T): string? where T : IList<int> => items.ToString()

func constrainedTypeName<T>(items: T): string where T : IList<int> => items.GetType().Name

// The same lookup over an interface this project declares, which already answered.
func shapeText(shape: IShape): string? => shape.ToString()

func printableDefault(value: IPrintable): string? => value.ToString()

func printableFormat(value: IPrintable): string => value.ToString("hex")

func printableEquals(value: IPrintable, other: object): bool => value.Equals(other)
