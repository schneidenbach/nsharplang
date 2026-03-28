namespace MultiFileProject

import System
import System.Linq
import MultiFileProject.Models
import MultiFileProject.Services
import "Models/Person"
import "Services/PersonService"

func Main() {
    print "=== Multi-File Project Demo ==="
    print ""

    // Create service
    service := new PersonService()

    // Add people
    service.AddPerson(new Person() { Name: "Alice", Age: 30, Email: "alice@example.com" })

    service.AddPerson(new Person() { Name: "Bob", Age: 25, Email: "bob@example.com" })

    service.AddPerson(new Person() { Name: "Charlie", Age: 35, Email: "charlie@example.com" })

    print ""
    print $"Total people: {service.Count}"
    print ""

    // Display all people
    print "All people:"
    people := service.GetPeople()
    for person in people {
        print $"  - {person.GetInfo()}"
    }

    print ""
    print "Active status: " + Status.Active
    print "Demo complete!"
}
