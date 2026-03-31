using NSharpInteropLib.Models;
using Xunit;

namespace NSharpLang.CSharpInteropTests;

/// <summary>
/// Tests that C# code can naturally consume N# records, classes, and enums.
/// This validates that N#'s type emissions are idiomatic and easy to use from C#.
/// </summary>
public class ModelInteropTests
{
    [Fact]
    public void CanCreateRecord()
    {
        var person = new Person { Name = "Alice", Age = 30, Email = "alice@example.com" };

        Assert.Equal("Alice", person.Name);
        Assert.Equal(30, person.Age);
        Assert.Equal("alice@example.com", person.Email);
    }

    [Fact]
    public void RecordMethodsWork()
    {
        var person = new Person { Name = "Bob", Age = 25, Email = "bob@test.com" };

        Assert.Equal("Bob (25)", person.GetDisplayName());
    }

    [Fact]
    public void RecordWithPrimaryConstructor()
    {
        var address = new Address("123 Main St", "Springfield", "62701");

        Assert.Equal("123 Main St, Springfield 62701", address.FullAddress);
    }

    [Fact]
    public void CanUsePersonService()
    {
        var service = new PersonService();
        Assert.Equal(0, service.Count);

        service.Add(new Person { Name = "Alice", Age = 30, Email = "alice@test.com" });
        service.Add(new Person { Name = "Bob", Age = 25, Email = "bob@test.com" });

        Assert.Equal(2, service.Count);

        var people = service.GetAll();
        Assert.Equal(2, people.Count);
        Assert.Equal("Alice", people[0].Name);
        Assert.Equal("Bob", people[1].Name);
    }

    [Fact]
    public void NumericEnumValues()
    {
        Assert.Equal(0, (int)Priority.Low);
        Assert.Equal(1, (int)Priority.Medium);
        Assert.Equal(2, (int)Priority.High);
        Assert.Equal(3, (int)Priority.Critical);
    }

    [Fact]
    public void NumericEnumInSwitch()
    {
        var priority = Priority.High;

        var label = priority switch
        {
            Priority.Low => "low",
            Priority.Medium => "medium",
            Priority.High => "high",
            Priority.Critical => "critical",
            _ => "unknown"
        };

        Assert.Equal("high", label);
    }

    [Fact]
    public void StringEnumValues()
    {
        // N# string-backed enums emit as static classes with const string fields
        Assert.Equal("active", Status.Active);
        Assert.Equal("inactive", Status.Inactive);
        Assert.Equal("pending", Status.Pending);
    }

    [Fact]
    public void RecordEquality()
    {
        var person1 = new Person { Name = "Alice", Age = 30, Email = "alice@test.com" };
        var person2 = new Person { Name = "Alice", Age = 30, Email = "alice@test.com" };
        var person3 = new Person { Name = "Bob", Age = 25, Email = "bob@test.com" };

        Assert.Equal(person1, person2);
        Assert.NotEqual(person1, person3);
    }
}
