namespace MultiFileTest

import System

func Main() {
    person := new Person("Alice", 30)
    print person.GetInfo()
    print $"Is adult: {person.IsAdult()}"
}
