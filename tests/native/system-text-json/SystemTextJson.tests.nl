namespace NSharpLang.SystemTextJson.Tests

import System
import System.Linq
import System.Text.Json
import System.Text.Json.Nodes

test "Serialize infers its type argument and omits the options" {
    assert JsonSerializer.Serialize("x") == "\"x\""
    assert JsonSerializer.Serialize(42) == "42"
    assert JsonSerializer.Serialize([1, 2, 3]) == "[1,2,3]"
}

test "a source class round-trips through Serialize and Deserialize" {
    order := new Order { Id: 7, Customer: "Bea", Lines: ["tea", "cake"] }
    json := JsonSerializer.Serialize(order)
    assert json == "{\"Id\":7,\"Customer\":\"Bea\",\"Lines\":[\"tea\",\"cake\"]}"
    back := must JsonSerializer.Deserialize<Order>(json)
    assert back.Id == 7
    assert back.Customer == "Bea"
    assert back.Lines.Length == 2
    assert back.Lines[1] == "cake"
}

test "an anonymous object serializes its properties in written order" {
    payload := new { Name: "Alice", Age: 30, Tags: ["a", "b"], Address: new { City: "Oslo" } }
    json := JsonSerializer.Serialize(payload)
    assert json == "{\"Name\":\"Alice\",\"Age\":30,\"Tags\":[\"a\",\"b\"],\"Address\":{\"City\":\"Oslo\"}}"
}

test "an anonymous object round-trips into a class of the same shape" {
    json := JsonSerializer.Serialize(new { Id: 3, Customer: "Cy", Lines: ["pie"] })
    order := must JsonSerializer.Deserialize<Order>(json)
    assert order.Id == 3
    assert order.Customer == "Cy"
    assert order.Lines[0] == "pie"
}

test "an anonymous object round-trips into its own anonymous type" {
    original := new { Name: "Alice", Age: 30 }
    back := must ParseLike(JsonSerializer.Serialize(original), new { Name: "", Age: 0 })
    assert back.Name == "Alice"
    assert back.Age == 30
    assert back.Equals(original)
}

test "a list of source objects and a list of anonymous objects serialize as arrays" {
    orders := [new Order { Id: 1, Customer: "A", Lines: ["x"] }, new Order { Id: 2, Customer: "B", Lines: ["y"] }]
    assert JsonSerializer.Serialize(orders) == "[{\"Id\":1,\"Customer\":\"A\",\"Lines\":[\"x\"]},{\"Id\":2,\"Customer\":\"B\",\"Lines\":[\"y\"]}]"
    rows := orders.Select(o => new { Id: o.Id }).ToList()
    assert JsonSerializer.Serialize(rows) == "[{\"Id\":1},{\"Id\":2}]"
}

test "Serialize inside a lambda closes over the lambda's own values" {
    render: Func<int, string> = n => JsonSerializer.Serialize(new { N: n, Twice: n * 2 })
    assert render(4) == "{\"N\":4,\"Twice\":8}"
    orders := [new Order { Id: 5, Customer: "L", Lines: ["z"] }]
    lines := orders.Select(o => JsonSerializer.Serialize(o)).ToArray()
    assert lines[0] == "{\"Id\":5,\"Customer\":\"L\",\"Lines\":[\"z\"]}"
}

test "Serialize closes over the calling function's type parameter" {
    assert ToJson(new { A: 1 }) == "{\"A\":1}"
    assert ToJson(new Order { Id: 1, Customer: "T", Lines: ["t"] }) == "{\"Id\":1,\"Customer\":\"T\",\"Lines\":[\"t\"]}"
}

test "Serialize takes a static member, a method's parameter and written options" {
    assert JsonSerializer.Serialize(Holder.Current) == "{\"Id\":9,\"Customer\":\"Static\",\"Lines\":[\"s\"]}"
    assert new Holder().Render(Holder.Current) == "{\"Id\":9,\"Customer\":\"Static\",\"Lines\":[\"s\"]}"
    indented := new JsonSerializerOptions { WriteIndented: true }
    assert JsonSerializer.Serialize(new { A: 1 }, indented).Contains("\n")
}

test "other inferred generic calls with omitted options emit too" {
    assert JsonSerializer.SerializeToUtf8Bytes(new { A: 1 }).Length == 7
    node := JsonValue.Create(5)
    assert node.ToJsonString() == "5"
}
