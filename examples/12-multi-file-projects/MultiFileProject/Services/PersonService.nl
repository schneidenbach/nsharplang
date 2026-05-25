namespace MultiFileProject.Services

import System.Collections.Generic
import MultiFileProject.Models

class PersonService {
    readonly people: List<Person>

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
