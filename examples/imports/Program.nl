// Program.nl - Uses imports to access types from Models.nl

import "./Models"
import System

func Main() {
    person := new Person("Alice", 30)
    Console.WriteLine(person.GetInfo())

    status := Status.Active
    Console.WriteLine($"Status: {status}")
}
