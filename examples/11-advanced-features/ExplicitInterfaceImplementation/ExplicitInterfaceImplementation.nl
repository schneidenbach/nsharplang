namespace ExplicitInterfaceImplementation

import System.Collections
import System.Collections.Generic
import System.Linq

// EXPLICIT INTERFACE IMPLEMENTATION: a member that names the interface whose slot it fills.
//
// The reason it exists is `IEnumerable<T>`. It inherits the non-generic `IEnumerable`, and the two
// `GetEnumerator` slots differ ONLY in return type — so an ordinary member can fill one of them and
// nothing else can fill the other. Write the second one with the interface in front of its name.
class Bag: IEnumerable<string> {
    items: List<string> = new List<string>()

    func Add(value: string) {
        items.Add(value)
    }

    // On the type AND in the generic slot: the ordinary way to implement an interface member.
    func GetEnumerator(): IEnumerator<string> {
        generic: IEnumerable<string> = items
        return generic.GetEnumerator()
    }

    // In the non-generic slot ONLY. `bag.GetEnumerator()` never reaches this one.
    func IEnumerable.GetEnumerator(): IEnumerator {
        untyped: IEnumerable = items
        return untyped.GetEnumerator()
    }
}

// The other shape it is for: two interfaces that declare the same member name, one type, two bodies.

interface IReader {
    func Read(): string
}

interface IScanner {
    func Read(): string
}

class Duplex: IReader, IScanner {
    func IReader.Read(): string => "from the reader"

    func IScanner.Read(): string => "from the scanner"
}

// A value member takes the same qualifier. `hidden.Label` does not compile; the interface reaches it.

interface ILabeled {
    Label: string
}

class Hidden: ILabeled {
    ILabeled.Label: string => "reachable only through ILabeled"
}

func main() {
    bag := new Bag()
    bag.Add("alpha")
    bag.Add("beta")

    print "for … in uses the generic slot:"
    for item in bag {
        print "  " + item
    }

    print "the non-generic interface uses the explicit member:"
    untyped: IEnumerable = bag
    walker := untyped.GetEnumerator()
    while walker.MoveNext() {
        print "  " + walker.Current.ToString()
    }

    print "LINQ sees it as the sequence it is:"
    print "  count: " + Enumerable.Count<string>(bag).ToString()

    duplex := new Duplex()
    reader: IReader = duplex
    scanner: IScanner = duplex
    print "one name, two slots:"
    print "  " + reader.Read()
    print "  " + scanner.Read()

    labeled: ILabeled = new Hidden()
    print "a value member: " + labeled.Label
}
