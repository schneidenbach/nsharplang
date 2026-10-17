namespace NSharpLang.CensusParamsExpansion.Tests

test "a nullable optional default that has a value fills as that value, wrapped" {
    parameters := AddFileBuilderParameters()
    assert parameters.Length > 0, "Serilog's ILoggingBuilder AddFile overload must be reflectable."

    // The declaration's optional tail, read as the value each omitted argument is filled with:
    // `LogLevel minimumLevel = Information`, `IDictionary<string, LogLevel> levelOverrides = null`,
    // `bool isJson = false`, `long? fileSizeLimitBytes = 1073741824` and
    // `int? retainedFileCountLimit = 31`. The two nullables are the rows this fix added; the three
    // beside them answer as they always did, and a tail that was unfillable anywhere refused the
    // whole overload at every arity.
    // The enum's constant is its underlying `Int32` (`Information` is 2), which is what the
    // metadata row stores.
    expected := "Int32=2 null Boolean=False Int64=1073741824 Int32=31 String="
    assert AddFileOptionalTail().StartsWith(expected), "AddFile's optional tail was " + AddFileOptionalTail()
}
