namespace NSharpLang.AnonymousObjects.Tests

import System
import System.Linq
import System.Reflection
import System.Runtime.CompilerServices

// WHAT AN ANONYMOUS OBJECT IS AT RUN TIME.
//
// `new { Name: "Alice", Age: 30 }` compiles to C#'s anonymous-type contract: one sealed, internal,
// GENERIC class per ordered list of property names, read-only properties over `initonly` fields, value
// equality, and the `{ Name = Alice, Age = 30 }` rendering. The behavioural tests read the values back
// through every boundary the program can hand one across; the metadata tests read the emitted type.
test "a property reads back the value it was written with" {
    person := new { Name: "Alice", Age: 30 }
    assert person.Name == "Alice"
    assert person.Age == 30
    assert person.Age + 1 == 31
}

test "ToString renders every property in written order, the way C# does" {
    person := new { Name: "Alice", Age: 30 }
    assert person.ToString() == "{ Name = Alice, Age = 30 }"
    assert $"{person.Name} is {person.Age}" == "Alice is 30"
    assert $"person: {person}" == "person: { Name = Alice, Age = 30 }"
}

test "an anonymous object with no properties renders as empty braces" {
    empty := new { }
    assert empty.ToString() == "{ }"
}

test "a nested anonymous object renders inside its parent" {
    nested := new { Inner: new { X: 1 }, Tag: "t" }
    assert nested.Inner.X == 1
    assert nested.ToString() == "{ Inner = { X = 1 }, Tag = t }"
}

test "Equals and GetHashCode compare by VALUE, == compares the references" {
    first := new { Name: "Alice", Age: 30 }
    second := new { Name: "Alice", Age: 30 }
    different := new { Name: "Alice", Age: 31 }
    assert first.Equals(second)
    assert first.GetHashCode() == second.GetHashCode()
    assert !first.Equals(different)
    assert !(first == second)
    assert first == first
}

test "value equality is what LINQ's Contains and Distinct use" {
    rows := [new { A: 1 }, new { A: 1 }, new { A: 2 }]
    assert rows.Distinct().Count() == 2
    assert rows.Contains(new { A: 2 })
}

test "an anonymous object passes through an object parameter and a generic one" {
    person := new { Name: "Alice", Age: 30 }
    assert Describe(person) == "{ Name = Alice, Age = 30 }"
    same := Echo(person)
    assert same.Name == "Alice"
    assert Object.ReferenceEquals(same, person)
}

test "a property can hold a value of the creating method's own type parameter" {
    assert Boxed(42).ToString() == "{ Value = 42 }"
    assert Boxed("text").ToString() == "{ Value = text }"
}

test "the same shape created in two functions is the same type and compares equal" {
    assert Person("Alice", 30).Equals(Person("Alice", 30))
    local := new { Name: "Alice", Age: 30 }
    assert Person("Alice", 30).Equals(local)
}

test "an array literal and a foreach carry the anonymous element type" {
    people := [new { Name: "Alice" }, new { Name: "Bob" }]
    names := ""
    for person in people {
        names = names + person.Name
    }
    assert names == "AliceBob"
}

test "LINQ projections into anonymous objects keep their property types" {
    evens := Squares(5)
    assert evens.Count == 2
    assert evens[0] == 2
    assert evens[1] == 4
    assert LetterCounts(["apple", "avocado", "banana"]) == "a=2;b=1;"
}

test "a lambda captures an anonymous object and reads its properties" {
    person := new { Name: "Alice", Age: 30 }
    read: Func<string> = () => person.Name
    assert read() == "Alice"
}

test "a conditional picks between two objects of the same shape" {
    adult := true
    label := adult ? new { Text: "adult" } : new { Text: "minor" }
    assert label.Text == "adult"
}

test "`with` copies an anonymous object and replaces only the named properties" {
    assert Older() == "{ Name = Alice, Age = 30 } -> { Name = Alice, Age = 31 }"
}

test "a property pattern reads an anonymous object's properties" {
    assert Classify(30) == "Bea is thirty"
    assert Classify(31) == "other"
}

test "a member of a source class creates and renders an anonymous object" {
    assert new Inventory("hey").Summary() == "{ Label = hey, Length = 3 }"
}

test "nameof names an anonymous property" {
    person := new { Name: "Alice" }
    assert nameof(person.Name) == "Name"
}

// ---- the emitted type ----------------------------------------------------------------------------

test "the synthesized type is a sealed, internal, compiler-generated generic class" {
    person: object = new { Name: "Alice", Age: 30 }
    personType := person.GetType()
    assert personType.IsGenericType
    assert personType.IsSealed
    assert !personType.IsPublic
    assert personType.GetGenericTypeDefinition().GetGenericArguments().Length == 2
    assert personType.GetCustomAttribute<CompilerGeneratedAttribute>() != null
}

test "the properties are read-only over initonly fields" {
    person: object = new { Name: "Alice", Age: 30 }
    personType := person.GetType()
    nameProperty := personType.GetProperty("Name")
    assert nameProperty != null
    assert nameProperty?.CanWrite == false
    assert nameProperty?.PropertyType == typeof(string)
    for field in personType.GetFields(BindingFlags.Instance | BindingFlags.NonPublic) {
        assert field.IsInitOnly
    }
}

test "one template serves every instantiation of the same property names" {
    first: object = new { Name: "Alice", Age: 30 }
    second: object = new { Name: 1.5, Age: "x" }
    other: object = new { Age: 30, Name: "Alice" }
    assert first.GetType().GetGenericTypeDefinition() == second.GetType().GetGenericTypeDefinition()
    assert first.GetType() != second.GetType()
    assert first.GetType().GetGenericTypeDefinition() != other.GetType().GetGenericTypeDefinition()
}
