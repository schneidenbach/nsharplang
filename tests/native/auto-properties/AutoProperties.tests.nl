namespace NSharpLang.AutoProperties.Tests

import System
import System.Diagnostics
import System.Reflection
import System.Runtime.CompilerServices
import System.Text.Json

func InstanceMembers(): BindingFlags {
    return BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly
}

func StaticMembers(): BindingFlags {
    return BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.DeclaredOnly
}

func IsAutoProperty(owner: Type, name: string): bool {
    property := owner.GetProperty(name, InstanceMembers())
    storage := owner.GetField("<" + name + ">k__BackingField", InstanceMembers())
    return property != null && property.CanRead && property.CanWrite && storage != null && owner.GetField(name, InstanceMembers()) == null
}

func IsField(owner: Type, name: string, flags: BindingFlags): bool {
    return owner.GetField(name, flags) != null && owner.GetProperty(name, flags) == null
}

// ---- the rule ---------------------------------------------------------------------------------

test "an exported instance member of a class is an auto-property, with or without an initializer" {
    assert IsAutoProperty(typeof(Order), "Id")
    assert IsAutoProperty(typeof(Order), "Customer")
    assert IsAutoProperty(typeof(Order), "Notes")
    assert IsAutoProperty(typeof(Order), "Audit")
    assert IsAutoProperty(typeof(Order), "Batch")
}

test "a written word gives both accessors that accessibility" {
    audit := must typeof(Order).GetProperty("Audit", InstanceMembers())
    assert (must audit.GetGetMethod(true)).IsFamily
    assert (must audit.GetSetMethod(true)).IsFamily
    batch := must typeof(Order).GetProperty("Batch", InstanceMembers())
    assert (must batch.GetGetMethod(true)).IsAssembly
    customer := must typeof(Order).GetProperty("Customer", InstanceMembers())
    assert (must customer.GetGetMethod(true)).IsPublic
    assert (must customer.GetSetMethod(true)).IsPublic
}

test "camelCase, private, static, readonly and const members stay fields" {
    assert IsField(typeof(Order), "lines", InstanceMembers())
    assert IsField(typeof(Order), "total", InstanceMembers())
    assert IsField(typeof(Order), "Hidden", InstanceMembers())
    assert IsField(typeof(Order), "Created", StaticMembers())
    assert IsField(typeof(Order), "Stamp", InstanceMembers())
    assert (must typeof(Order).GetField("Stamp", InstanceMembers())).IsInitOnly
    assert (must typeof(Order).GetField("Version", StaticMembers())).IsLiteral
    order := new Order()
    assert order.LinesAndTotal() == 24
    assert order.Stamp == 42
}

test "a struct's and a record struct's members stay fields" {
    assert IsField(typeof(Point), "X", InstanceMembers())
    assert IsField(typeof(Point), "Y", InstanceMembers())
    assert IsField(typeof(Pair), "Left", InstanceMembers())
}

test "a record's members are auto-properties, positional or written in the body" {
    assert IsAutoProperty(typeof(Person), "Name")
    assert IsAutoProperty(typeof(Person), "Age")
    assert IsAutoProperty(typeof(Customer), "Name")
    assert IsAutoProperty(typeof(Customer), "Age")
    customer := new Customer("Ada", 36)
    assert customer.Name == "Ada"
    assert customer.Age == 36
}

test "a class's primary constructor keeps a camelCase capture a field and makes an exported parameter a property" {
    assert IsField(typeof(Service), "secret", InstanceMembers())
    assert IsAutoProperty(typeof(Service), "Label")
    service := new Service("s", "l")
    assert service.Secret() == "s"
    assert service.Label == "l"
}

test "a generic class's members are properties of every instantiation" {
    assert IsAutoProperty(typeof(Box<string>), "Value")
    assert (must typeof(Box<string>).GetProperty("Value")).PropertyType == typeof(string)
    box := new Box<string> { Value: "v", Count: 1 }
    assert box.Add(2) == 3
    assert box.Value == "v"
}

// ---- C#'s metadata, row for row ---------------------------------------------------------------

test "the accessors and the backing field carry C#'s compiler-generated rows" {
    property := must typeof(Order).GetProperty("Customer")
    getter := must property.GetGetMethod()
    setter := must property.GetSetMethod()
    assert getter.IsDefined(typeof(CompilerGeneratedAttribute), false)
    assert setter.IsDefined(typeof(CompilerGeneratedAttribute), false)
    assert getter.IsSpecialName && setter.IsSpecialName
    assert !getter.IsVirtual
    assert setter.ReturnParameter.GetRequiredCustomModifiers().Length == 0

    storage := must typeof(Order).GetField("<Customer>k__BackingField", InstanceMembers())
    assert storage.IsDefined(typeof(CompilerGeneratedAttribute), false)
    browsable := storage.GetCustomAttribute(typeof(DebuggerBrowsableAttribute)) as DebuggerBrowsableAttribute
    assert browsable != null && browsable.State == DebuggerBrowsableState.Never
    assert !storage.IsPublic
}

test "a nullable member's annotation is on the property" {
    context := new NullabilityInfoContext()
    notes := context.Create(must typeof(Order).GetProperty("Notes"))
    assert notes.ReadState == NullabilityState.Nullable
    customer := context.Create(must typeof(Order).GetProperty("Customer"))
    assert customer.ReadState == NullabilityState.NotNull
}

// ---- the frameworks the rule exists for --------------------------------------------------------

test "System.Text.Json round-trips a class's bare members and ignores its fields" {
    order := new Order { Id: 7, Customer: "Ada", Notes: null }
    json := JsonSerializer.Serialize<Order>(order)
    assert json.Contains("\"Id\":7")
    assert json.Contains("\"Customer\":\"Ada\"")
    assert !json.Contains("lines")
    assert !json.Contains("Stamp")
    back := must JsonSerializer.Deserialize<Order>("{\"Id\":9,\"Customer\":\"Grace\",\"Notes\":\"n\"}")
    assert back.Id == 9
    assert back.Customer == "Grace"
    assert back.Notes == "n"
}

test "System.Text.Json round-trips a record's bare and positional members" {
    json := JsonSerializer.Serialize<Person>(new Person { Name: "Ada", Age: 36 })
    person := must JsonSerializer.Deserialize<Person>(json)
    assert person.Name == "Ada"
    assert person.Age == 36
    customer := must JsonSerializer.Deserialize<Customer>("{\"Name\":\"Lin\",\"Age\":5}")
    assert customer.Name == "Lin"
    assert customer.Age == 5
}

test "EF Core populates a DbContext's DbSet properties" {
    shop := new Shop()
    assert shop.People != null
    assert shop.Orders != null
}

// ---- reads, writes and copies --------------------------------------------------------------------

test "compound assignment and steps work on an auto-property inside and outside its type" {
    board := new Scoreboard()
    assert board.Score(5) == 11
    board.Total += 4
    board.Total++
    assert board.Total == 16
    board.Label += "!"
    assert board.Label == "game!"
    overtime := new Overtime()
    assert overtime.Extra() == 99
}

test "a struct-typed auto-property is read as a copy, a struct field is storage" {
    board := new Scoreboard()
    assert board.BumpBoth() == "0/1"
    board.Home.Bump()
    assert board.Home.Read() == 0
    home := board.Home
    home.Bump()
    board.Home = home
    assert board.Home.Read() == 1
}

test "an object initializer and with fill auto-properties" {
    order := new Order { Id: 1, Customer: "a" }
    assert order.Id == 1
    person := new Person { Name: "a", Age: 1 }
    older := person with { Age: 2 }
    assert older.Age == 2
    assert older.Name == "a"
    assert person.Age == 1
    assert person.Equals(new Person { Name: "a", Age: 1 })
    assert !person.Equals(older)
}
