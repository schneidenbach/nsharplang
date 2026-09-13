namespace NSharpLang.CensusUsingStatement.Tests

import System.Collections.Generic

test "each of the five written using forms binds its resource and releases it after the body" {
    inferred := new List<string>()
    assert InferredBinding(inferred) == "inferred"
    assert inferred.Count == 1
    assert inferred[0] == "inferred"

    annotated := new List<string>()
    assert AnnotatedBinding(annotated) == "annotated"
    assert annotated.Count == 1
    assert annotated[0] == "annotated"

    letForm := new List<string>()
    assert LetBinding(letForm) == "let"
    assert letForm.Count == 1
    assert letForm[0] == "let"

    unbound := new List<string>()
    assert UnboundResource(unbound) == "unbound"
    assert unbound.Count == 1
    assert unbound[0] == "unbound"
}

test "a using DECLARATION guards the REST of its block, so the release comes after the statements that follow it" {
    log := new List<string>()
    DeclarationForm(log)

    assert log.Count == 2
    assert log[0] == "after declared"
    assert log[1] == "declared"
}

test "nested using blocks release innermost first" {
    log := new List<string>()
    NestedBlocks(log)

    assert log.Count == 3
    assert log[0] == "body"
    assert log[1] == "inner"
    assert log[2] == "outer"
}

test "using DECLARATIONS in one block release in reverse declaration order" {
    log := new List<string>()
    ReverseDeclarationOrder(log)

    assert log.Count == 4
    assert log[0] == "body"
    assert log[1] == "third"
    assert log[2] == "second"
    assert log[3] == "first"
}

test "the release runs when the body throws, and it runs BEFORE the handler outside it" {
    log := new List<string>()
    assert ReleasesWhenTheBodyThrows(log) == "boom"

    assert log.Count == 2
    assert log[0] == "throwing"
    assert log[1] == "caught boom"
}

test "an exception thrown by the release propagates — a finally is not a catch" {
    log := new List<string>()
    assert ReleaseExceptionPropagates(log) == "dispose failed"

    assert log.Count == 1
    assert log[0] == "body"
}

test "a struct resource is released exactly once, after its body" {
    log := new List<string>()
    StructResource(log)

    assert log.Count == 2
    assert log[0] == "body"
    assert log[1] == "struct"
}

test "a null resource skips the release instead of throwing" {
    log := new List<string>()
    assert NullResource(log) == "survived"

    assert log.Count == 1
    assert log[0] == "body"
}

test "a resource with only a Dispose MEMBER — no interface — is released through it" {
    log := new List<string>()
    StructuralResource(log)

    assert log.Count == 2
    assert log[0] == "body"
    assert log[1] == "pattern"
}

test "a using around two yields releases when the sequence ENDS, not when it suspends" {
    log := new List<string>()
    total := 0
    for value in GeneratorResource(log) {
        total = total + value
        // The release must not have happened yet: the machine is suspended INSIDE the region.
        assert !log.Contains("generator")
    }

    assert total == 3
    assert log.Count == 2
    assert log[0] == "between"
    assert log[1] == "generator"
}

test "a consumer that abandons a generator early still gets the release" {
    log := new List<string>()
    assert AbandonGenerator(log) == 1

    // Nothing between the yields ran, and the resource was still released.
    assert log.Count == 1
    assert log[0] == "generator"
}

test "a using inside a lambda and inside a local function releases on the way out of each" {
    lambdaLog := new List<string>()
    assert LambdaResource(lambdaLog) == 7
    assert lambdaLog.Count == 1
    assert lambdaLog[0] == "lambda"

    localLog := new List<string>()
    assert LocalFunctionResource(localLog) == 9
    assert localLog.Count == 1
    assert localLog[0] == "localfn"
}

test "await using releases through IAsyncDisposable" {
    log := new List<string>()
    assert AsyncUsingResource(log).Result == 11

    assert log.Count == 1
    assert log[0] == "async"
}

test "writing THROUGH the resource stays legal — only rebinding the name is refused" {
    log := new List<string>()
    assert WritesThroughTheResource(log) == 3

    assert log.Count == 1
    assert log[0] == "mutable:3"
}
