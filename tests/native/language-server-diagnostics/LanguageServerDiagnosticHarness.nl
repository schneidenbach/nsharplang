namespace NSharpLang.LanguageServerDiagnostics.Tests

import System
import System.Collections
import System.Collections.Generic
import System.IO
import System.Reflection
import NSharpLang.Compiler

func LsdRequiredType(name: string): Type {
    resolved := Type.GetType(name)
    if resolved == null {
        throw new InvalidOperationException("Required type was not found: " + name)
    }
    return resolved
}

func LsdRequiredProperty(value: object, name: string): object {
    property := value.GetType().GetProperty(name)
    if property == null {
        throw new InvalidOperationException("Required property was not found: " + name)
    }
    result := property.GetValue(value)
    if result == null {
        throw new InvalidOperationException("Required property was null: " + name)
    }
    return result
}

func LsdRequiredField(value: object, name: string): object {
    field := value.GetType().GetField(name)
    if field == null {
        throw new InvalidOperationException("Required field was not found: " + name)
    }
    result := field.GetValue(value)
    if result == null {
        throw new InvalidOperationException("Required field was null: " + name)
    }
    return result
}

func LsdFieldText(error: CompilerError, name: string): string {
    text := LsdRequiredField(error, name).ToString()
    if text == null {
        throw new InvalidOperationException("Required field text was null: " + name)
    }
    return text
}

func LsdFieldInt(error: CompilerError, name: string): int {
    return Convert.ToInt32(LsdRequiredField(error, name))
}

func LsdOptionalFieldText(error: CompilerError, name: string): string? {
    field := error.GetType().GetField(name)
    if field == null {
        throw new InvalidOperationException("Required field was not found: " + name)
    }
    value := field.GetValue(error)
    if value == null {
        return null
    }
    text := value.ToString()
    if text == null {
        throw new InvalidOperationException("Required field text was null: " + name)
    }
    return text
}

func LsdPropertyText(error: CompilerError, name: string): string {
    text := LsdRequiredProperty(error, name).ToString()
    if text == null {
        throw new InvalidOperationException("Required property text was null: " + name)
    }
    return text
}

func LsdFormatForTooling(error: CompilerError, includeCode: bool, includeLocation: bool): string {
    parameterTypes := new Type[](2)
    parameterTypes[0] = typeof(bool)
    parameterTypes[1] = typeof(bool)
    method := error.GetType().GetMethod("FormatForTooling", parameterTypes)
    if method == null {
        throw new InvalidOperationException("CompilerError.FormatForTooling was not found.")
    }
    arguments := new object?[](2)
    LsdPut(arguments, 0, includeCode)
    LsdPut(arguments, 1, includeLocation)
    result := method.Invoke(error, arguments)
    if result == null {
        throw new InvalidOperationException("CompilerError.FormatForTooling returned null.")
    }
    text := result.ToString()
    if text == null {
        throw new InvalidOperationException("CompilerError.FormatForTooling text was null.")
    }
    return text
}

func LsdTempRoot(prefix: string): string {
    return Path.Combine(Path.GetTempPath(), prefix + Guid.NewGuid().ToString("N"))
}

func LsdFileUri(path: string): string {
    uriType := LsdRequiredType("System.Uri, System.Private.Uri")
    constructors := uriType.GetConstructors()
    constructor: ConstructorInfo? = null
    matchingConstructors := 0
    index := 0
    while index < constructors.Length {
        parameters := constructors[index].GetParameters()
        if parameters.Length == 1 {
            constructor = constructors[index]
            matchingConstructors = matchingConstructors + 1
        }
        index = index + 1
    }
    if constructor == null || matchingConstructors != 1 {
        throw new InvalidOperationException("Uri(string) constructor was not found.")
    }
    arguments := new object?[](1)
    LsdPut(arguments, 0, path)
    uri := constructor.Invoke(arguments)
    if uri == null {
        throw new InvalidOperationException("Uri construction returned null.")
    }
    value := LsdRequiredProperty(uri, "AbsoluteUri")
    text := value.ToString()
    if text == null {
        throw new InvalidOperationException("File URI was null.")
    }
    return text
}

func LsdPut(values: object?[], index: int, value: object?) {
    values[index] = value
}

func LsdNewDocumentManager(): object {
    managerType := LsdRequiredType("NSharpLang.LanguageServer.Services.DocumentManager, LanguageServer")
    loggerDefinition := LsdRequiredType("Microsoft.Extensions.Logging.Abstractions.NullLogger`1, Microsoft.Extensions.Logging.Abstractions")
    loggerArguments := new Type[](1)
    loggerArguments[0] = managerType
    loggerType := loggerDefinition.MakeGenericType(loggerArguments)
    instanceField := loggerType.GetField("Instance")
    if instanceField == null {
        throw new InvalidOperationException("NullLogger.Instance was not found.")
    }
    logger := instanceField.GetValue(null)
    constructors := managerType.GetConstructors()
    if constructors.Length != 1 {
        throw new InvalidOperationException("DocumentManager constructor count changed.")
    }
    arguments := new object?[](1)
    LsdPut(arguments, 0, logger)
    created := constructors[0].Invoke(arguments)
    if created == null {
        throw new InvalidOperationException("DocumentManager construction returned null.")
    }
    return created
}

func LsdUpdateDocument(manager: object, uri: string, source: string) {
    parameterTypes := new Type[](3)
    parameterTypes[0] = typeof(string)
    parameterTypes[1] = typeof(string)
    parameterTypes[2] = typeof(int)
    method := manager.GetType().GetMethod("UpdateDocument", parameterTypes)
    if method == null {
        throw new InvalidOperationException("DocumentManager.UpdateDocument was not found.")
    }
    arguments := new object?[](3)
    LsdPut(arguments, 0, uri)
    LsdPut(arguments, 1, source)
    LsdPut(arguments, 2, 1)
    ignored := method.Invoke(manager, arguments)
    _ = ignored
}

func LsdInvokeStringArgument(manager: object, methodName: string, value: string): object? {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    method := manager.GetType().GetMethod(methodName, parameterTypes)
    if method == null {
        throw new InvalidOperationException("Required DocumentManager method was not found: " + methodName)
    }
    arguments := new object?[](1)
    LsdPut(arguments, 0, value)
    return method.Invoke(manager, arguments)
}

func LsdCopyCompilerErrors(value: object): List<CompilerError> {
    sourceItems := value as IList
    if sourceItems == null {
        throw new InvalidOperationException("Compiler diagnostics did not implement IList.")
    }
    errors := new List<CompilerError>()
    index := 0
    while index < sourceItems.Count {
        error := sourceItems[index] as CompilerError
        if error == null {
            throw new InvalidOperationException("Compiler diagnostics contained a non-compiler item.")
        }
        errors.Add(error)
        index = index + 1
    }
    return errors
}

func LsdGetDocument(manager: object, uri: string): object {
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(string)
    method := manager.GetType().GetMethod("GetDocument", parameterTypes)
    if method == null {
        throw new InvalidOperationException("DocumentManager.GetDocument was not found.")
    }
    arguments := new object?[](1)
    LsdPut(arguments, 0, uri)
    document := method.Invoke(manager, arguments)
    if document == null {
        throw new InvalidOperationException("DocumentManager did not retain the updated document.")
    }
    return document
}

func LsdCompilerDiagnostics(uri: string, source: string): List<CompilerError> {
    manager := LsdNewDocumentManager()
    LsdUpdateDocument(manager, uri, source)
    document := LsdGetDocument(manager, uri)
    return LsdCopyCompilerErrors(LsdRequiredProperty(document, "Diagnostics"))
}

func LsdPublishedCompilerDiagnostics(uri: string, source: string): List<CompilerError> {
    manager := LsdNewDocumentManager()
    ignored := LsdInvokeStringArgument(manager, "MarkEditorOpen", uri)
    _ = ignored
    LsdUpdateDocument(manager, uri, source)
    publicationsValue := LsdInvokeStringArgument(manager, "GetDiagnosticsToPublish", uri)
    if publicationsValue == null {
        throw new InvalidOperationException("DocumentManager.GetDiagnosticsToPublish returned null.")
    }
    publications := publicationsValue as IList
    if publications == null || publications.Count != 1 {
        throw new InvalidOperationException("Expected exactly one diagnostics publication.")
    }
    publication := publications[0]
    if publication == null {
        throw new InvalidOperationException("Diagnostics publication was null.")
    }
    return LsdCopyCompilerErrors(LsdRequiredProperty(publication, "CompilerDiagnostics"))
}

func LsdMessageMatches(message: string, fragment: string?): bool {
    if fragment == null {
        return true
    }
    return message.Contains(fragment, StringComparison.Ordinal)
}

func LsdSingle(
    errors: IReadOnlyList<CompilerError>,
    codeName: string,
    messageFragment: string?
): CompilerError {
    found: CompilerError? = null
    count := 0
    index := 0
    while index < errors.Count {
        error := errors[index]
        actualCodeName := LsdFieldText(error, "Code")
        if actualCodeName == codeName {
            message := LsdFieldText(error, "Message")
            if LsdMessageMatches(message, messageFragment) {
                found = error
                count = count + 1
            }
        }
        index = index + 1
    }
    if found == null || count != 1 {
        throw new InvalidOperationException(
            "Expected one " + codeName + " diagnostic, found " + count.ToString() + "."
        )
    }
    return found
}

func LsdContains(errors: IReadOnlyList<CompilerError>, codeName: string, messageFragment: string?): bool {
    index := 0
    while index < errors.Count {
        error := errors[index]
        actualCodeName := LsdFieldText(error, "Code")
        if actualCodeName == codeName {
            message := LsdFieldText(error, "Message")
            if LsdMessageMatches(message, messageFragment) {
                return true
            }
        }
        index = index + 1
    }
    return false
}

func LsdContainsAt(
    errors: IReadOnlyList<CompilerError>,
    codeName: string,
    messageFragment: string?,
    line: int,
    column: int,
    length: int
): bool {
    index := 0
    while index < errors.Count {
        error := errors[index]
        if LsdFieldText(error, "Code") == codeName && LsdFieldInt(error, "Line") == line && LsdFieldInt(error, "Column") == column && LsdFieldInt(error, "Length") == length && LsdMessageMatches(LsdFieldText(error, "Message"), messageFragment) {
            return true
        }
        index = index + 1
    }
    return false
}

func LsdContainsMessage(errors: IReadOnlyList<CompilerError>, messageFragment: string): bool {
    index := 0
    while index < errors.Count {
        if LsdFieldText(errors[index], "Message").Contains(messageFragment, StringComparison.Ordinal) {
            return true
        }
        index = index + 1
    }
    return false
}

func LsdSingleAt(
    errors: IReadOnlyList<CompilerError>,
    codeName: string,
    messageFragment: string?,
    line: int,
    column: int
): CompilerError {
    found: CompilerError? = null
    count := 0
    index := 0
    while index < errors.Count {
        error := errors[index]
        matchesLine := line < 0 || LsdFieldInt(error, "Line") == line
        matchesColumn := column < 0 || LsdFieldInt(error, "Column") == column
        if LsdFieldText(error, "Code") == codeName && matchesLine && matchesColumn {
            if LsdMessageMatches(LsdFieldText(error, "Message"), messageFragment) {
                found = error
                count = count + 1
            }
        }
        index = index + 1
    }
    if found == null || count != 1 {
        throw new InvalidOperationException(
            "Expected one " + codeName + " diagnostic at the requested position, found " + count.ToString() + "."
        )
    }
    return found
}

func LsdAssertSpan(error: CompilerError, line: int, column: int, length: int) {
    assert LsdFieldInt(error, "Line") == line
    assert LsdFieldInt(error, "Column") == column
    assert LsdFieldInt(error, "Length") == length
}

func LsdAssertLspRange(error: CompilerError, line0: int, startCharacter: int, endCharacter: int) {
    converterType := LsdRequiredType("NSharpLang.LanguageServer.Services.LspDiagnosticConverter, LanguageServer")
    parameterTypes := new Type[](1)
    parameterTypes[0] = typeof(CompilerError)
    method := converterType.GetMethod("FromCompilerError", parameterTypes)
    if method == null {
        throw new InvalidOperationException("LspDiagnosticConverter.FromCompilerError was not found.")
    }
    arguments := new object?[](1)
    LsdPut(arguments, 0, error)
    converted := method.Invoke(null, arguments)
    if converted == null {
        throw new InvalidOperationException("Compiler diagnostic conversion returned null.")
    }
    range := LsdRequiredProperty(converted, "Range")
    start := LsdRequiredProperty(range, "Start")
    finish := LsdRequiredProperty(range, "End")
    assert Convert.ToInt32(LsdRequiredProperty(start, "Line")) == line0
    assert Convert.ToInt32(LsdRequiredProperty(start, "Character")) == startCharacter
    assert Convert.ToInt32(LsdRequiredProperty(finish, "Line")) == line0
    assert Convert.ToInt32(LsdRequiredProperty(finish, "Character")) == endCharacter
}

func LsdDecodedSource(source: string): string {
    if source.StartsWith("\n", StringComparison.Ordinal) {
        decoded := source.Substring(1)
        if decoded.EndsWith("\n", StringComparison.Ordinal) {
            return decoded.Substring(0, decoded.Length - 1)
        }
        return decoded
    }
    return source
}

func LsdLeadingNewlineSource(source: string): string {
    if source.EndsWith("\n", StringComparison.Ordinal) {
        return source.Substring(0, source.Length - 1)
    }
    return source
}
