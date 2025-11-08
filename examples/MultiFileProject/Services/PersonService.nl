namespace MultiFileProject.Services

using System.Collections.Generic
using MultiFileProject.Models
import "../Models/Person"

class PersonService {
    people: List<Person>

    constructor() {
        people = new List<Person>()
    }

    func AddPerson(person: Person) {
        people.Add(person)
        print $"Added: {person.Name}"
    }

    func GetPeople(): List<Person> {
        return people
    }

    Count: int => people.Count
}
