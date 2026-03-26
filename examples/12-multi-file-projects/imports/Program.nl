// Program.nl - Uses imports to access types from Models.nl

import "./Models"
import System

func Main() {
    person := new Person("Alice", 30)
    print person.GetInfo()

    status := Status.Active
    print $"Status: {status}"
}
