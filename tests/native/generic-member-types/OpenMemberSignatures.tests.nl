namespace NSharpLang.GenericMemberTypes.Tests

import System
import System.Collections.Generic
import System.Reflection


test "a static member takes and returns open shapes over the declaring type's parameter" {
    words := new List<string>()
    words.Add("a")
    words.Add("b")
    shelf := Shelf<string>.Gather(words)
    assert shelf.Items.Count == 2
    assert shelf.Items[1] == "b"

    single := Shelf<int>.Single(4)
    assert single.Count == 1
    assert single[0] == 4

    index := Shelf<string>.Index(words)
    assert index[0] == "a"
    assert index[1] == "b"

    groups := new List<List<string>>()
    groups.Add(words)
    groups.Add(words)
    assert Shelf<string>.CountAll(groups) == 4
}

test "an instance member takes and returns open shapes over the declaring type's parameter" {
    shelf := new Shelf<int>()
    more := new List<int>()
    more.Add(1)
    more.Add(2)
    assert shelf.AddAll(more) == 2
    assert shelf.Snapshot().Count == 2
    assert shelf.Grouped()[2][1] == 2
}

// THE METADATA HALF: the open definition's static member is typed by the parameter itself, and each
// constructed type sees it with its own argument substituted.
func StaticReturnOf(owner: Type, name: string): Type {
    method := owner.GetMethod(name, BindingFlags.Public | BindingFlags.Static)
    if method == null {
        return typeof(object)
    }
    return method.get_ReturnType()
}

func StaticFirstParameterOf(owner: Type, name: string): Type {
    method := owner.GetMethod(name, BindingFlags.Public | BindingFlags.Static)
    if method == null {
        return typeof(object)
    }
    parameters := method.GetParameters()
    if parameters.Length == 0 {
        return typeof(object)
    }
    return parameters[0].get_ParameterType()
}

test "an open static signature is the constructed external generic seen per instantiation" {
    assert StaticReturnOf(typeof(Shelf<int>), "Single") == typeof(List<int>)
    assert StaticReturnOf(typeof(Shelf<string>), "Single") == typeof(List<string>)
    assert StaticFirstParameterOf(typeof(Shelf<int>), "Gather") == typeof(IEnumerable<int>)
    assert StaticReturnOf(typeof(Shelf<string>), "Index") == typeof(Dictionary<int, string>)

    definition := typeof(Shelf<int>).GetGenericTypeDefinition()
    parameter := definition.GetGenericArguments()[0]
    openReturn := StaticReturnOf(definition, "Single")
    assert openReturn.GetGenericTypeDefinition() == typeof(List<int>).GetGenericTypeDefinition()
    assert openReturn.GetGenericArguments()[0] == parameter
}
