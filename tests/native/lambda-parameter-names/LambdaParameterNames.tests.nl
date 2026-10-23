namespace NSharpLang.LambdaParameterNames.Tests

import System
import System.Collections.Generic
import System.Linq
import Microsoft.AspNetCore.Http
import NSharpLang.LambdaParameterNames

// A LAMBDA'S SYNTHESIZED METHOD CARRIES ITS SOURCE PARAMETER NAMES, AS C# DOES (issue #216).
//
// Before the fix every method a lambda lowered to had no `Param` rows, so
// `handler.Method.GetParameters()[0].Name` was null and ASP.NET Core failed every request to a
// Minimal-API handler with a parameter: "Encountered a parameter of type 'System.Int32' without a
// name. Parameters must have a name." Each row below names one lowering path.
test "a free function's lambda names every parameter" {
    assert ParameterNames(StaticLambda()) == "count,label"
}

test "a lambda with written parameter types names them" {
    assert ParameterNames(TypedLambda()) == "value"
}

test "a block-bodied lambda names its parameters" {
    assert ParameterNames(BlockLambda()) == "left,right"
}

test "an async lambda's kickoff method keeps the user's parameter names" {
    handler := AsyncLambda()
    assert ParameterNames(handler) == "delayMs"
    assert handler.Method.ReturnType == typeof(System.Threading.Tasks.Task<int>)
}

test "a capturing lambda's display-class method names the user's parameters from sequence one" {
    handler := CapturingLambda(10)
    assert ParameterNames(handler) == "input"
    assert !handler.Method.IsStatic
    assert handler(5) == 15
}

test "a lambda inferred at a declaration is named after its signature is set" {
    assert ParameterNames(InferredLambda()) == "quantity,unit"
}

test "a lambda written in a generator body names its parameter" {
    handlers := GeneratorLambdas().ToList()
    assert handlers.Count == 1
    assert ParameterNames(handlers[0]) == "itemId"
}

test "a lambda bound to the enclosing instance names its parameter" {
    scale := new Scaler(3).Scale()
    assert ParameterNames(scale) == "amount"
    assert scale(4) == 12
}

test "a capture-free lambda inside a type names its parameter" {
    assert ParameterNames(new Scaler(1).Describe()) == "text"
}

test "every parameter of a lambda method reports its position and a name" {
    for parameter in StaticLambda().Method.GetParameters() {
        assert parameter.Name != null
        assert parameter.Position >= 0
    }
}

// RequestDelegateFactory is what MapGet runs on a handler; asking it directly isolates the metadata
// from the route table.
test "RequestDelegateFactory binds a lambda's route value by its parameter name" {
    app := BuildApp()
    handler: Func<int, string> = (id: int) => "factory " + id.ToString()
    result := RequestDelegateFactory.Create(handler)
    routeValues := new Dictionary<string, string>()
    routeValues["id"] = "9"
    response := await Invoke(app, result.RequestDelegate, "/factory/9", routeValues, "")
    assert response == "200 factory 9"
}

test "a MapGet lambda binds an int route value" {
    app := BuildApp()
    routeValues := new Dictionary<string, string>()
    routeValues["id"] = "42"
    response := await Invoke(app, EndpointFor(app, "/todos/{id}"), "/todos/42", routeValues, "")
    assert response == "200 todo 42"
}

test "a capturing MapGet lambda binds a string route value" {
    app := BuildApp()
    routeValues := new Dictionary<string, string>()
    routeValues["name"] = "ada"
    response := await Invoke(app, EndpointFor(app, "/greet/{name}"), "/greet/ada", routeValues, "")
    assert response == "200 hello ada"
}

test "a two-parameter MapGet lambda binds both route values by name" {
    app := BuildApp()
    routeValues := new Dictionary<string, string>()
    routeValues["left"] = "3"
    routeValues["right"] = "4"
    response := await Invoke(app, EndpointFor(app, "/sum/{left}/{right}"), "/sum/3/4", routeValues, "")
    assert response == "200 7"
}

test "a MapGet lambda parameter absent from the route binds from the query string" {
    app := BuildApp()
    response := await Invoke(app, EndpointFor(app, "/search"), "/search", new Dictionary<string, string>(), "?term=lambdas")
    assert response == "200 searching lambdas"
}

test "a MapGet lambda taking HttpContext receives the request" {
    app := BuildApp()
    response := await Invoke(app, EndpointFor(app, "/context"), "/context", new Dictionary<string, string>(), "")
    assert response == "200 context /context"
}

test "an async MapGet lambda taking HttpContext runs" {
    app := BuildApp()
    response := await Invoke(app, EndpointFor(app, "/async-context"), "/async-context", new Dictionary<string, string>(), "")
    assert response == "200 async context"
}

// `f as Delegate` and `(Delegate)f` are not lambdas, and the route-handler lowering used to emit the
// route string before discovering that — the general extension tier then emitted the arguments again
// and the program lost its receiver (InvalidProgramException the moment `buildApp` ran).
test "a typed delegate passed as Delegate binds its route value" {
    app := BuildApp()
    routeValues := new Dictionary<string, string>()
    routeValues["orderId"] = "5"
    response := await Invoke(app, EndpointFor(app, "/orders/{orderId}"), "/orders/5", routeValues, "")
    assert response == "200 order 5"
}

test "a typed delegate cast to Delegate binds its route value" {
    app := BuildApp()
    routeValues := new Dictionary<string, string>()
    routeValues["orderId"] = "6"
    response := await Invoke(app, EndpointFor(app, "/receipts/{orderId}"), "/receipts/6", routeValues, "")
    assert response == "200 order 6"
}
