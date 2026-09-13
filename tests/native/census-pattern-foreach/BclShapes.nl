namespace NSharpLang.PatternForeach.Tests

import System
import System.Collections
import System.Collections.Generic
import System.Text.Json


// THE SHAPES `for x in e` HAS TO ITERATE, exercised through the emitted IL rather than described.
//
// Every collection here reaches the loop through ORDINARY member resolution — an accessible
// `GetEnumerator()`, then `IEnumerable<T>`, then `IEnumerable` — and none of them is named anywhere
// in the compiler. Half of them used to be rejected outright ("collection must be enumerable") and
// the other half declined at emission, because the old rule was a table of eighteen unqualified
// type names.
class BclShapes {
    func SumList(values: List<int>): int {
        total := 0
        for value in values {
            total = total + value
        }

        return total
    }

    func SumSpan(values: Span<int>): int {
        total := 0
        for value in values {
            total = total + value
        }

        return total
    }

    func CountVowels(text: ReadOnlySpan<char>): int {
        vowels := 0
        for character in text {
            if character == 'a' || character == 'e' || character == 'i' || character == 'o' || character == 'u' {
                vowels = vowels + 1
            }
        }

        return vowels
    }

    func CountCharacters(text: string): int {
        characters := 0
        for character in text {
            if character != ' ' {
                characters = characters + 1
            }
        }

        return characters
    }

    func SumArray(values: int[]): int {
        total := 0
        for value in values {
            total = total + value
        }

        return total
    }

    // A dictionary iterates its PAIRS, and the pair is what the enumerator's `Current` is rather
    // than something synthesised from the dictionary's name.
    func SumPairs(map: Dictionary<string, int>): int {
        total := 0
        for pair in map {
            total = total + pair.Value + pair.Key.Length
        }

        return total
    }

    func JoinKeys(map: Dictionary<string, int>): string {
        joined := ""
        for key in map.Keys {
            joined = joined + key
        }

        return joined
    }

    func SumValues(map: Dictionary<string, int>): int {
        total := 0
        for value in map.Values {
            total = total + value
        }

        return total
    }

    func SumStack(values: Stack<int>): int {
        total := 0
        for value in values {
            total = total + value
        }

        return total
    }

    func SumQueue(values: Queue<int>): int {
        total := 0
        for value in values {
            total = total + value
        }

        return total
    }

    func SumSet(values: HashSet<int>): int {
        total := 0
        for value in values {
            total = total + value
        }

        return total
    }

    // The SEQUENCE INTERFACE arm: the static type carries no pattern of its own.
    func SumSequence(values: IEnumerable<int>): int {
        total := 0
        for value in values {
            total = total + value
        }

        return total
    }

    func SumReadOnlyList(values: IReadOnlyList<int>): int {
        total := 0
        for value in values {
            total = total + value
        }

        return total
    }

    // The NON-GENERIC remainder: the element type is `object`, exactly as in C#.
    func CountUntyped(values: IEnumerable): int {
        counted := 0
        for value in values {
            if value != null {
                counted = counted + 1
            }
        }

        return counted
    }

    // A struct that implements `IEnumerable<T>` AND carries its own struct enumerator. Seventeen
    // sites in the converted CLI iterate one of these, and every one of them used to be rejected.
    func SumJsonLengths(json: string): int {
        document := JsonDocument.Parse(json)
        total := 0
        for element in document.RootElement.EnumerateArray() {
            total = total + element.GetArrayLength()
        }

        return total
    }

    func JoinJsonPropertyNames(json: string): string {
        document := JsonDocument.Parse(json)
        joined := ""
        for property in document.RootElement.EnumerateObject() {
            joined = joined + property.Name
        }

        return joined
    }
}
