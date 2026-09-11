namespace NSharpLang.ColumnarEmitFacts.Tests

import System
import System.Collections.Generic


// This is deliberately an exact CLR signature, rather than an interface-shaped substitute.  The
// shared element predicate is consumed when a Dictionary<string, Type> is the element of the
// public SZ-array parameter and return value, then the emitted body actually allocates, writes,
// reads, and enumerates that array.
func CatalogReferenceArrayFirst(
    values: Dictionary<string, Type>[]
): Dictionary<string, Type> {
    return values[0]
}

func CatalogReferenceArrayRoundTrip(
    values: Dictionary<string, Type>[]
): Dictionary<string, Type>[] {
    seen := 0
    for value in values {
        marker := value["marker"]
        if marker == typeof(int) || marker == typeof(string) {
            seen = seen + 1
        }
    }
    if seen != values.Length {
        throw new InvalidOperationException("Dictionary<Type> array enumeration lost an entry.")
    }
    return values
}

test "closed Dictionary string Type arrays retain their exact runtime operations" {
    values := new Dictionary<string, Type>[](2)
    first := new Dictionary<string, Type>()
    second := new Dictionary<string, Type>()
    first["marker"] = typeof(int)
    second["marker"] = typeof(string)
    values[0] = first
    values[1] = second

    returned := CatalogReferenceArrayRoundTrip(values)
    returnedObject: object = returned
    valuesObject: object = values
    firstObject: object = first
    selectedObject: object = CatalogReferenceArrayFirst(returned)
    assert Object.ReferenceEquals(returnedObject, valuesObject)
    assert Object.ReferenceEquals(selectedObject, firstObject)
    assert returned[0]["marker"] == typeof(int)
    assert returned[1]["marker"] == typeof(string)

    // This is the existing non-explicit generic Array.Fill lowering. It infers the exact
    // Dictionary<string,Type> element from the same array shape before calling MakeGenericMethod.
    filled := new Dictionary<string, Type>[](2)
    Array.Fill(filled, first)
    filledFirst: object = filled[0]
    filledSecond: object = filled[1]
    assert Object.ReferenceEquals(filledFirst, firstObject)
    assert Object.ReferenceEquals(filledSecond, firstObject)
}

test "closed Dictionary string Type arrays preserve CLR short and null failures" {
    shortValues := new Dictionary<string, Type>[](0)
    assert throws IndexOutOfRangeException {
        CatalogReferenceArrayFirst(shortValues)
    }

    nullValues: Dictionary<string, Type>[] = null
    assert throws NullReferenceException {
        CatalogReferenceArrayFirst(nullValues)
    }
}
