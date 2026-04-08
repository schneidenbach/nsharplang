namespace MultiFileTest

import System
import "editors/vscode/test/fixtures/multi-file/Models/Person.nl"

func Main() {
    person := new Person("Alice", 30)
    print person.GetInfo()
    print $"Is adult: {person.IsAdult()}"
}
