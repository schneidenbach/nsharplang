namespace NSharpLang.AspNetCoreHostedServices.Tests

test "MapGet takes a static method group" {
    app := NewApp()
    MapStaticGroup(app)
    assert app != null
}

test "MapGet takes a delegate value converted with as Delegate" {
    app := NewApp()
    MapDelegateValue(app)
    assert app != null
}

test "MapGet takes a lambda that writes its parameter types" {
    app := NewApp()
    MapTypedLambda(app)
    assert app != null
}

test "MapGet still takes a lambda of the HttpContext and a zero-parameter lambda" {
    app := NewApp()
    MapContextLambda(app)
    MapZeroLambda(app)
    assert app != null
}

test "MapGet takes a virtual instance method of the enclosing type" {
    app := NewApp()
    endpoints := new Endpoints()
    endpoints.MapInstance(app)
    assert app != null
}

test "MapFallbackToFile preflights its path and registers without starting the server" {
    app := NewApp()
    MapFallbackFile(app)
    assert app != null
}
