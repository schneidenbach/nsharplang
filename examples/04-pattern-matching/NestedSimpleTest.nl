class Address {
    City: string
}

class Person {
    Name: string
    Addr: Address
}

func Test(p: Person): string {
    return match p {
        { Addr: { City: "NYC" } } => "New Yorker",
        _ => "Other"
    }
}

func Main() {
    addr := new Address() { City: "NYC" }
    person := new Person() { Name: "Alice", Addr: addr }
    result := Test(person)
    print result
}
