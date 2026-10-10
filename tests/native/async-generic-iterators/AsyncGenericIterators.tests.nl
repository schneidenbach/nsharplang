namespace NSharpLang.AsyncGenericIterators.Tests

import NSharpLang.AsyncIteratorFixtures

test "a generic async iterator function carries its method parameter into the machine" {
    sequence := LocalPending<string>("generic")
    boxed: object = sequence
    machineArguments := boxed.GetType().GetGenericArguments()
    assert machineArguments.Length == 1
    assert machineArguments[0] == typeof(string)

    joined := ""
    await foreach value in sequence {
        joined = joined + value
    }
    assert joined == "genericgeneric"
}

test "a generic async member carries enclosing and method parameters" {
    shelf := new GenericAsyncShelf<int>(12, "shelf")
    sequence := shelf.Echo<string>("method")
    boxed: object = sequence
    machineArguments := boxed.GetType().GetGenericArguments()
    assert machineArguments.Length == 2
    assert machineArguments[0] == typeof(int)
    assert machineArguments[1] == typeof(string)

    joined := ""
    await foreach value in sequence {
        joined = joined + value
    }
    assert joined == "methodmethod"
}

test "a generic enclosing type parameter flows through an async instance iterator" {
    shelf := new GenericAsyncShelf<int>(5, "shelf")
    sequence := shelf.Values()
    boxed: object = sequence
    machineArguments := boxed.GetType().GetGenericArguments()
    assert machineArguments.Length == 1
    assert machineArguments[0] == typeof(int)

    total := 0
    await foreach value in sequence {
        total = total * 10 + value
    }
    assert total == 55
}

test "generic async iterators are consumable across an assembly boundary" {
    joined := ""
    await foreach value in CrossPending<string>("external") {
        joined = joined + value
    }
    assert joined == "externalexternal"

    shelf := new CrossAsyncShelf<int>(3)
    genericMember := shelf.Stream<bool>(true)
    boxed: object = genericMember
    machineArguments := boxed.GetType().GetGenericArguments()
    assert machineArguments.Length == 2
    assert machineArguments[0] == typeof(int)
    assert machineArguments[1] == typeof(bool)

    observed := false
    count := 0
    await foreach value in genericMember {
        observed = value
        count = count + 1
    }
    assert observed
    assert count == 2
}
