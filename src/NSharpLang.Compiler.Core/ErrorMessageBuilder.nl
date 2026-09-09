namespace NSharpLang.Compiler

import System.Collections.Generic

class ErrorMessageBuilder {

    // NL202, AND THE SENTENCE IS THE CALLER'S. Every reporting site already knows what disagrees with
    // what — the variable and its annotation, the member and its value, the field and its initializer,
    // the `if` and its condition — and says so when it has no source text to underline. The rich shape
    // carries the SAME sentence, so the route that ships is never the one with less to say: the snippet,
    // the caret width, the two type names, the hint and the docs link are ADDED to the sentence rather
    // than substituted for it. A builder that wrote its own headline could only ever write the bare
    // words `Type mismatch`, because the two disagreeing NAMES are not among its arguments.
    static func TypeMismatch(fileName: string, line: int, column: int, sourceSnippet: string, length: int, actualType: string, expectedType: string, message: string): CompilerError {
        humanExplanation := "I am having trouble with this code on line " + IntText(line) + ":"
        contextualHint := TypeConversionSuggester.SuggestConversion(actualType, expectedType)
        if contextualHint == null {
            contextualHint = "These types are not compatible. Check if you need to convert or cast."
        }

        return new CompilerError(ErrorCode.TypeMismatch, message, line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            ActualType: actualType,
            ExpectedType: expectedType,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            DocsUrl: DiagnosticDocs.UrlFor("NL202")
        }
    }

    static func ReturnValueRequiresReturnType(fileName: string, line: int, column: int, sourceSnippet: string, length: int, functionName: string, actualType: string): CompilerError {
        humanExplanation := "Function `" + functionName + "` has no return type annotation, so N# treats it as `void`:"

        addReturnTypeHint := "Add `" + ": " + actualType + "` after the parameter list if `" + functionName + "` should return this value"
        suggestion := "Add `" + ": " + actualType + "` to `" + functionName + "` or remove the returned value"
        if actualType == "null" || actualType == "unknown" {
            addReturnTypeHint = "Add an explicit return type after the parameter list if `" + functionName + "` should return a value"
            suggestion = "Add an explicit return type to `" + functionName + "` or remove the returned value"
        }

        contextualHint := "This code gives back a value of type `" + actualType + "` from a function that currently returns nothing.\n" + addReturnTypeHint + ", " + "or remove the value if the function should stay void."

        return new CompilerError(ErrorCode.TypeMismatch, "Function '" + functionName + "' returns " + actualType + " but has no return type", line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            ActualType: actualType,
            ExpectedType: "void",
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            Suggestion: suggestion,
            DocsUrl: DiagnosticDocs.UrlFor("NL202")
        }
    }

    static func ReturnValueInVoidFunction(fileName: string, line: int, column: int, sourceSnippet: string, length: int, functionName: string, actualType: string): CompilerError {
        humanExplanation := "Function `" + functionName + "` is declared to return `void`, but this code gives back a value:"

        contextualHint := "A `void` function cannot return a value of type `" + actualType + "`. Change the return type if the value matters, " + "or remove the value if the function only performs side effects."

        return new CompilerError(ErrorCode.TypeMismatch, "Function '" + functionName + "' returns a value but is declared void", line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            ActualType: actualType,
            ExpectedType: "void",
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            Suggestion: "Change `" + functionName + "`'s return type or remove the returned value",
            DocsUrl: DiagnosticDocs.UrlFor("NL202")
        }
    }

    static func ReturnTypeMismatch(fileName: string, line: int, column: int, sourceSnippet: string, length: int, functionName: string, actualType: string, expectedType: string): CompilerError {
        contextualHint := TypeConversionSuggester.SuggestConversion(actualType, expectedType)
        if contextualHint == null {
            contextualHint = "`" + functionName + "` is declared to return `" + expectedType + "`, so every returned value must be assignable to `" + expectedType + "`."
        }

        return new CompilerError(ErrorCode.TypeMismatch, "Function '" + functionName + "' should return " + expectedType + " but returns " + actualType, line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            ActualType: actualType,
            ExpectedType: expectedType,
            HumanExplanation: "This return value does not match `" + functionName + "`'s return type:",
            ContextualHint: contextualHint,
            DocsUrl: DiagnosticDocs.UrlFor("NL202")
        }
    }

    static func UndefinedVariable(fileName: string, line: int, column: int, sourceSnippet: string, length: int, varName: string, similarNames: List<string>): CompilerError {
        humanExplanation := "I cannot find a `" + varName + "` variable on line " + IntText(line) + ":"
        contextualHint := "Make sure you've declared this variable before using it."
        if HasItems(similarNames) {
            contextualHint = "Variables need to be declared before they can be used. If you meant to\n" + "use a variable from outside this function, make sure it's in scope."
        }

        return new CompilerError(ErrorCode.UndefinedVariable, "Variable '" + varName + "' not found", line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            Suggestions: OptionalNames(similarNames),
            DocsUrl: DiagnosticDocs.UrlFor("NL301")
        }
    }

    static func UndefinedFunction(fileName: string, line: int, column: int, sourceSnippet: string, length: int, functionName: string, similarNames: List<string>): CompilerError {
        humanExplanation := "I cannot find a function named `" + functionName + "` on line " + IntText(line) + ":"
        contextualHint := "Define `func " + functionName + "(...)` before calling it, or import the function if it lives elsewhere."
        if HasItems(similarNames) {
            contextualHint = "Function calls need a function, method, or callable value with this name in scope.\n" + "If this is from another file or namespace, import it before calling it."
        }

        return new CompilerError(ErrorCode.UndefinedFunction, "Function '" + functionName + "' not found", line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            Suggestions: OptionalNames(similarNames),
            DocsUrl: DiagnosticDocs.UrlFor("NL412")
        }
    }

    static func NonExhaustiveMatch(fileName: string, line: int, column: int, sourceSnippet: string, length: int, missingCases: List<string>): CompilerError {
        humanExplanation := "This `match` expression does not cover all possibilities on line " + IntText(line) + ":"

        contextualHint := "You need to handle these cases:\n\n" + IndentedLines(missingCases) + "\n\n" + "Pattern matching in N# must be exhaustive, meaning every possible value\n" + "must be handled. You can either add the missing cases, or use a wildcard '_'\n" + "pattern to catch everything else:\n\n" + "    _ => handleOtherCases()\n\n" + "Why? This helps prevent runtime errors. The compiler checks that you've thought\n" + "about all possibilities!"

        relatedInfo := new Dictionary<string, string>()
        relatedInfo.Add("missingCases", string.Join(", ", missingCases))

        return new CompilerError(ErrorCode.NonExhaustiveMatch, "Pattern matching is not exhaustive", line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            RelatedInfo: relatedInfo,
            DocsUrl: DiagnosticDocs.UrlFor("NL501")
        }
    }

    static func WrongArgumentCount(fileName: string, line: int, column: int, sourceSnippet: string, length: int, functionName: string, expected: int, actual: int): CompilerError {
        humanExplanation := "I am having trouble with this function call on line " + IntText(line) + ":"

        expectedArguments := IntText(expected) + " " + Pluralize(expected, "argument", "arguments")
        contextualHint := "The function `" + functionName + "` expects " + expectedArguments + ", but you are\n" + "passing " + IntText(actual) + ". You may have passed too many arguments."
        if expected > actual {
            contextualHint = "The function `" + functionName + "` expects " + expectedArguments + ", but you are\n" + "passing " + IntText(actual) + ". You may have forgotten to pass some arguments."
        }

        return new CompilerError(ErrorCode.WrongArgumentCount, "Function '" + functionName + "' expects " + expectedArguments + " but got " + IntText(actual), line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            DocsUrl: DiagnosticDocs.UrlFor("NL401")
        }
    }

    static func NoMatchingOverload(fileName: string, line: int, column: int, sourceSnippet: string, length: int, functionName: string, actualArgumentCount: int, argumentTypes: List<string>, candidateSignatures: List<string>): CompilerError {
        argumentText := "no arguments"
        if HasItems(argumentTypes) {
            argumentText = JoinBackticked(argumentTypes)
        }

        signatureText := "No callable overloads were found."
        if HasItems(candidateSignatures) {
            signatureText = "Available overloads:\n" + BulletLines(candidateSignatures)
        }

        argumentCountText := IntText(actualArgumentCount) + " " + Pluralize(actualArgumentCount, "argument", "arguments")
        humanExplanation := "I cannot find an overload of `" + functionName + "` that matches this call:"
        contextualHint := "This call passes " + argumentCountText + ": " + argumentText + ".\n" + signatureText + "\n\n" + "Check the argument count and types. If you meant to reference the method itself, use it in a context with a delegate type instead of calling it."

        return new CompilerError(ErrorCode.NoMatchingOverload, "No overload of '" + functionName + "' accepts " + argumentCountText + " with these types", line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            DocsUrl: DiagnosticDocs.UrlFor("NL402")
        }
    }

    static func MethodGroupUsedAsValue(fileName: string, line: int, column: int, sourceSnippet: string, length: int, methodName: string): CompilerError {
        humanExplanation := "`" + methodName + "` names a method, not a value:"
        contextualHint := "Methods need a call site like `name()` before they produce a value.\n" + "A bare method name is only valid when the surrounding API expects a delegate."

        return new CompilerError(ErrorCode.MethodGroupUsedAsValue, "Method '" + methodName + "' must be called or passed to a delegate", line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            Suggestion: "If you meant to use the result, call `" + methodName + "(...)`. If you meant to pass the method itself, pass it to a parameter with a delegate type.",
            DocsUrl: DiagnosticDocs.UrlFor("NL411")
        }
    }

    static func InvalidExpressionStatement(fileName: string, line: int, column: int, sourceSnippet: string, length: int, expressionDescription: string): CompilerError {
        humanExplanation := "This expression is written as a statement, but it does not do anything by itself:"
        contextualHint := "The expression `" + expressionDescription + "` produces a value or names a member, but the value is ignored.\n" + "Only assignments, calls, increments, decrements, await expressions, and object construction can be used as statements."

        return new CompilerError(ErrorCode.InvalidExpressionStatement, "This expression statement has no effect", line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            Suggestion: "Use the value by assigning it, printing it, passing it to a call, or remove the expression. If you meant to call a method, add parentheses with the required arguments.",
            DocsUrl: DiagnosticDocs.UrlFor("NL313")
        }
    }

    static func InvalidForIteratorExpression(fileName: string, line: int, column: int, sourceSnippet: string, length: int, expressionDescription: string): CompilerError {
        humanExplanation := "This expression appears in the update clause of a for loop, but it does not do anything by itself:"
        contextualHint := "The expression `" + expressionDescription + "` produces a value or names a member, but the value is ignored.\n" + "Only assignments, calls, increments, decrements, await expressions, and object construction can be used as for-loop iterators."

        return new CompilerError(ErrorCode.InvalidExpressionStatement, "This for-loop iterator has no effect", line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            Suggestion: "Use an assignment such as `i = i + 1`, an increment/decrement such as `i++`, a side-effecting call, or remove the iterator.",
            DocsUrl: DiagnosticDocs.UrlFor("NL313")
        }
    }

    static func ImportNotFound(fileName: string, line: int, column: int, sourceSnippet: string, length: int, importPath: string): CompilerError {
        humanExplanation := "I cannot find the file you're trying to import on line " + IntText(line) + ":"

        // THE TWO RULES, IN THE ORDER `FileResolver.ResolveFilePath` ASKS THEM. This hint used to say
        // "The path should be relative to your project root", which is the opposite of what happens
        // for the `./` form the message is quoting — the form every example writes — so the one
        // sentence a stuck reader had to go on sent them the wrong way.
        contextualHint := "Make sure the file exists at the path '" + importPath + "'.\n" + "A path starting with './' or '../' is relative to THIS file; any other path is relative to the project root.\n" + "The '.nl' extension is optional — 'Helper' and 'Helper.nl' name the same file.\n\n" + "Common issues:\n" + "  - Check for typos in the file path\n" + "  - Check whether the path should start with './' (beside this file) or not (from the project root)\n" + "  - Verify the file is in the expected directory"

        return new CompilerError(ErrorCode.ImportNotFound, "Cannot find import '" + importPath + "'", line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            DocsUrl: DiagnosticDocs.UrlFor("NL701")
        }
    }

    static func CircularImport(fileName: string, line: int, column: int, sourceSnippet: string, length: int, importPath: string): CompilerError {
        humanExplanation := "I found a circular import on line " + IntText(line) + ":"

        contextualHint := "The file '" + importPath + "' creates an import cycle back to this file.\n\n" + "Circular imports are not allowed because they make it impossible to determine\n" + "the correct order of symbol resolution.\n\n" + "To fix this, reorganize your code so imports flow in one direction. Consider:\n" + "  - Moving shared types to a separate file that both files import\n" + "  - Combining the files if they are tightly coupled"

        return new CompilerError(ErrorCode.CircularImport, "Circular import: '" + importPath + "' creates a cycle", line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            DocsUrl: DiagnosticDocs.UrlFor("NL703")
        }
    }

    static func UnexpectedToken(fileName: string, line: int, column: int, sourceSnippet: string, length: int, unexpectedToken: string, expectedToken: string? = null): CompilerError {
        humanExplanation := "I found something unexpected on line " + IntText(line) + ":"

        contextualHint := "The token `" + unexpectedToken + "` is not valid here.\n" + "Check your syntax - you may be missing a semicolon, closing brace, or parenthesis."
        message := "Unexpected token: " + unexpectedToken
        if expectedToken != null {
            contextualHint = "I was expecting to see " + expectedToken + ", but I found " + unexpectedToken + " instead.\n" + "Check for missing semicolons, parentheses, or other syntax elements."
            message = "Expected " + expectedToken + " but found " + unexpectedToken
        }

        return new CompilerError(ErrorCode.UnexpectedToken, message, line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            DocsUrl: DiagnosticDocs.UrlFor("NL101")
        }
    }

    static func MissingReturn(fileName: string, line: int, column: int, sourceSnippet: string, length: int, returnType: string): CompilerError {
        humanExplanation := "This function is declared to return `" + returnType + "`, but not all code paths return a value:"

        contextualHint := "Every code path through this function must end with a `return` statement that\n" + "provides a `" + returnType + "` value. If you don't need to return anything, change the\n" + "return type to `void`."

        return new CompilerError(ErrorCode.MissingReturn, "Not all code paths return a value of type '" + returnType + "'", line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            ExpectedType: returnType,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            Suggestion: "Add a `return` statement, or change the return type to `void`",
            DocsUrl: DiagnosticDocs.UrlFor("NL305")
        }
    }

    static func WrongArgumentTypeMessage(argumentDescription: string, functionName: string, actualTypePhrase: string, parameterName: string?, expectedType: string): string {
        if parameterName != null {
            return argumentDescription + " to '" + functionName + "' is " + actualTypePhrase + ", but parameter '" + parameterName + "' expects '" + expectedType + "'"
        }

        return argumentDescription + " to '" + functionName + "' is " + actualTypePhrase + ", but this parameter expects '" + expectedType + "'"
    }

    static func WrongArgumentType(fileName: string, line: int, column: int, sourceSnippet: string, length: int, functionName: string, argIndex: int, paramName: string, actualType: string, expectedType: string): CompilerError {
        humanExplanation := "Argument " + IntText(argIndex) + " in the call to `" + functionName + "` has the wrong type:"

        contextualHint := TypeConversionSuggester.SuggestConversion(actualType, expectedType)
        if contextualHint == null {
            contextualHint = "The parameter `" + paramName + "` expects a `" + expectedType + "` value, but you passed a\n" + "`" + actualType + "`. These types are not compatible."
        }

        return new CompilerError(ErrorCode.TypeMismatch, "Cannot pass `" + actualType + "` as argument for parameter `" + paramName + "` of type `" + expectedType + "`", line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            ActualType: actualType,
            ExpectedType: expectedType,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            DocsUrl: DiagnosticDocs.UrlFor("NL202")
        }
    }

    static func DuplicateDeclaration(fileName: string, line: int, column: int, sourceSnippet: string, length: int, name: string, kind: string): CompilerError {
        humanExplanation := "I found a duplicate " + kind + " named `" + name + "` on line " + IntText(line) + ":"

        contextualHint := "The name `" + name + "` is already defined. Each " + kind + " must have a unique name\n" + "within its scope. Rename one of the declarations to fix this."

        return new CompilerError(ErrorCode.DuplicateDeclaration, "Duplicate " + kind + " '" + name + "'", line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            DocsUrl: DiagnosticDocs.UrlFor("NL306")
        }
    }

    static func ControlTransferOutOfFinally(fileName: string, line: int, column: int, sourceSnippet: string, length: int, keyword: string): CompilerError {
        humanExplanation := "This `" + keyword + "` would leave the enclosing `finally` block:"

        target := "a loop outside the `finally`"
        if keyword == "return" {
            target = "the function"
        }

        contextualHint := "Control cannot leave a `finally` block — the runtime must always finish running it,\n" + "whether the `try` completed normally or an exception is in flight. This `" + keyword + "`\n" + "would exit the `finally` early to reach " + target + ", which the CLR forbids.\n" + "`throw` is allowed, and loops opened inside the `finally` can still `break`/`continue`."

        return new CompilerError(ErrorCode.ControlTransferOutOfFinally, "Control cannot leave a 'finally' block with '" + keyword + "'", line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            Suggestion: "Move the `" + keyword + "` outside the `finally` block (e.g. set a flag in the finally and act on it afterwards)",
            DocsUrl: DiagnosticDocs.UrlFor("NL319")
        }
    }

    static func LockRequiresReferenceType(fileName: string, line: int, column: int, sourceSnippet: string, length: int, typeName: string, isTypeParameter: bool = false): CompilerError {
        humanExplanation := "This `lock` statement needs a reference type, but `" + typeName + "` is a value type:"
        if isTypeParameter {
            humanExplanation = "This `lock` statement needs a reference type, but `" + typeName + "` is a type parameter that may be a value type:"
        }

        contextualHint := "`Monitor` locks on object IDENTITY. A value type has no stable identity: it would be\n" + "boxed into a fresh object on every `lock`, so no two threads would ever contend on\n" + "the same lock — the lock would guard nothing."
        suggestion := "Lock on a dedicated `object` field instead: `sync: object = new object()`"
        if isTypeParameter {
            contextualHint = "`Monitor` locks on object IDENTITY. If `" + typeName + "` is instantiated with a value type, the\n" + "value would be boxed into a fresh object on every `lock`, so no two threads would ever\n" + "contend on the same lock — the lock would guard nothing."
            suggestion = "Constrain `" + typeName + "` to a reference type (`where " + typeName + ": class`), or lock on a dedicated `object` field instead: `sync: object = new object()`"
        }

        return new CompilerError(ErrorCode.LockRequiresReferenceType, "'" + typeName + "' is not a reference type as required by the lock statement", line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            ActualType: typeName,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            Suggestion: suggestion,
            DocsUrl: DiagnosticDocs.UrlFor("NL320")
        }
    }

    static func MemberWriteThroughValueCopy(fileName: string, line: int, column: int, sourceSnippet: string, length: int, memberName: string, receiverTypeName: string, receiverDescription: string): CompilerError {
        return new CompilerError(ErrorCode.MemberWriteThroughValueCopy, "Cannot assign to '" + memberName + "' because its receiver is a temporary copy of '" + receiverTypeName + "', not a variable", line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            ActualType: receiverTypeName,
            HumanExplanation: "This assignment writes through " + receiverDescription + ", but `" + receiverTypeName + "` is a value type:",
            ContextualHint: "A value type is copied every time it is returned from a call, an indexer, or a\n" + "property. This write would land in that temporary copy and be thrown away with it —\n" + "the original value would never change.",
            Suggestion: "Copy the value into a local first, modify the local, then store the whole value back (e.g. `tmp := …` / `tmp." + memberName + " = …` / store `tmp`)",
            DocsUrl: DiagnosticDocs.UrlFor("NL322")
        }
    }

    static func UndefinedMember(fileName: string, line: int, column: int, sourceSnippet: string, length: int, memberName: string, typeName: string, similarMembers: List<string>): CompilerError {
        humanExplanation := "I cannot find a member called `" + memberName + "` on type `" + typeName + "`:"

        contextualHint := "The type `" + typeName + "` does not have a member named `" + memberName + "`.\n" + "Check the type's documentation for available members."
        if HasItems(similarMembers) {
            contextualHint = "The type `" + typeName + "` does not have a member named `" + memberName + "`.\n" + "Check for typos, or make sure you're accessing the right type."
        }

        return new CompilerError(ErrorCode.UndefinedMember, "Member '" + memberName + "' not found on type '" + typeName + "'", line, column, ErrorSeverity.Error) {
            FileName: fileName,
            SourceSnippet: sourceSnippet,
            Length: length,
            HumanExplanation: humanExplanation,
            ContextualHint: contextualHint,
            Suggestions: OptionalNames(similarMembers),
            DocsUrl: DiagnosticDocs.UrlFor("NL303")
        }
    }

    static func Pluralize(count: int, singular: string, plural: string): string {
        if count == 1 {
            return singular
        }

        return plural
    }

    static func IntText(value: int): string {
        return value.ToString()
    }

    static func HasItems(values: List<string>): bool {
        return values.Count > 0
    }

    static func OptionalNames(values: List<string>): List<string>? {
        if values.Count > 0 {
            return values
        }

        return null
    }

    static func IndentedLines(values: List<string>): string {
        result := ""
        i := 0
        while i < values.Count {
            if i > 0 {
                result = result + "\n"
            }

            result = result + "    " + values[i]
            i = i + 1
        }

        return result
    }

    static func JoinBackticked(values: List<string>): string {
        result := ""
        i := 0
        while i < values.Count {
            if i > 0 {
                result = result + ", "
            }

            result = result + "`" + values[i] + "`"
            i = i + 1
        }

        return result
    }

    static func BulletLines(values: List<string>): string {
        result := ""
        i := 0
        while i < values.Count {
            if i > 0 {
                result = result + "\n"
            }

            result = result + "  - " + values[i]
            i = i + 1
        }

        return result
    }
}
