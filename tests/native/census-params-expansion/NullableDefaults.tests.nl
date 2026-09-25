namespace NSharpLang.CensusParamsExpansion.Tests

test "a nullable optional default that has a value fills as that value, wrapped" {
    parameters := AddFileBuilderParameters()
    assert parameters.Length > 0, "Serilog's ILoggingBuilder AddFile overload must be reflectable."

    // The declaration's optional tail, read as the fill kind and constant each parameter offers:
    // `LogLevel minimumLevel = Information`, `IDictionary<string, LogLevel> levelOverrides = null`,
    // `bool isJson = false`, `long? fileSizeLimitBytes = 1073741824` and
    // `int? retainedFileCountLimit = 31`. The two nullables are the rows this fix added; the three
    // beside them answer as they always did, and a tail that was unfillable anywhere refused the
    // whole overload at every arity.
    expected := Int32Kind().ToString() + "=Information " + NullReferenceKind().ToString() + "=<none> " + Int32Kind().ToString() + "=False " + NullableValueKind().ToString() + "=1073741824 " + NullableValueKind().ToString() + "=31 " + StringKind().ToString() + "="
    assert AddFileOptionalTail().StartsWith(expected), "AddFile's optional tail was " + AddFileOptionalTail()
}
