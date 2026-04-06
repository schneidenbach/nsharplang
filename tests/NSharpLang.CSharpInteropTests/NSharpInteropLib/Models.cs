// Generated from Models.nl — this is the exact C# that N# emits.
// If the compiler output changes, update this file to match.
#nullable enable annotations

using System;
namespace NSharpInteropLib.Models;

public record Person
{
    public string Name { get; set; }

    public int Age { get; set; }

    public string Email { get; set; }

    public string GetDisplayName()
    {
        return $"{Name} ({Age})";
    }
}

public record Address(string street, string city, string zip)
{
    public string FullAddress => $"{street}, {city} {zip}";
}

public class PersonService
{
    private System.Collections.Generic.List<Person> people { get; set; }

    public PersonService()
    {
        people = new System.Collections.Generic.List<Person>();
    }

    public void Add(Person person)
    {
        people.Add(person);
    }

    public System.Collections.Generic.List<Person> GetAll()
    {
        return people;
    }

    public int Count => people.Count;
}

public enum Priority
{
    Low = 0,
    Medium = 1,
    High = 2,
    Critical = 3
}

public static class Status
{
    public const string Active = "active";
    public const string Inactive = "inactive";
    public const string Pending = "pending";
}
