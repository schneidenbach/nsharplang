namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE TWO RULES A FIELD INITIALIZER ANSWERS TO — NL328 AND NL329.
//
// A FIELD INITIALIZER CANNOT REACH THE OBJECT BEING CONSTRUCTED — NL328.
//
// Instance field initializers run at the very start of every constructor that reaches the base
// constructor, BEFORE the base constructor call, because that is the order that lets a base
// constructor observe the derived state a virtual call reaches. At that point the object is not yet
// an object: its base half has not run, so `this` names storage no member may read, and calling an
// instance method on it is not even verifiable IL.
//
// So the rule is C#'s (CS0027 / CS0236): an initializer may name no part of the instance — not
// `this`, not `base`, and not a bare instance field, method or property of the containing type. The
// two repairs are the ones C# offers: move the work into a constructor, where the object exists, or
// make the member it needs `static`.
//
// A STATIC field's initializer is exempt: it runs in the type initializer, where there is no
// instance to reach in the first place, and a bare instance member there is already NL301/NL327.
//
// Lambda parameters shadow: `items: Func<int,int> = x => x` names no member even in a type with a
// field called `x`, so every lambda parameter written anywhere in the initializer is collected
// before the walk reports.
// AND A STRUCT TAKES NO INSTANCE FIELD INITIALIZER AT ALL — NL329.
//
// A struct value can always be produced without running any constructor: `default(Point)`, an array
// element, an uninitialized field, a `new T()` behind an unconstrained type parameter. An instance
// initializer on a struct would therefore run for some of the values that exist and not for the
// rest, which is a rule that holds only sometimes — so N# refuses the initializer instead of
// emitting one. A struct's STATIC field initializers are unaffected: they run in the type
// initializer, which every use of the type reaches.
class AnalyzerFieldInitializerRules {
    static func ReportStructInitializerIfNeeded(field: FieldDeclaration, initializer: Expression, scopes: AnalyzerScopeStack, spans: AnalyzerDiagnosticSpans, diagnostics: AnalyzerDiagnosticSink) {
        if AnalyzerDefiniteAssignment.HasStaticModifier(field.Modifiers) {
            return
        }

        declaringType := scopes.CurrentTypeScope()
        typeName := StructTypeNameOrEmpty(declaringType)
        if typeName.Length == 0 {
            return
        }

        span := spans.GetExpressionDiagnosticSpan(initializer)
        message := "'" + typeName + "' is a struct, so the initializer of '" + field.Name + "' cannot run for every value of it"
        suggestion := "Assign '" + field.Name + "' in a constructor of '" + typeName + "'."
        sourceSnippet := diagnostics.SourceSnippet(span.Line)
        currentFilePath := diagnostics.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnostics.ReportBuilt(ErrorMessageBuilder.StructFieldInitializer(currentFilePath, span.Line, span.Column, sourceSnippet, span.Length, typeName, field.Name))
            return
        }

        diagnostics.Report(ErrorCode.StructFieldInitializer, message, span.Line, span.Column, suggestion, span.Length)
    }

    // A value type's written name, or "" when the enclosing scope is not one. A `record struct` is a
    // struct for this rule for exactly the same reason a `struct` is.
    static func StructTypeNameOrEmpty(declaringType: TypeInfo?): string {
        structType := declaringType as StructTypeInfo
        if structType != null {
            return structType.Name
        }

        recordType := declaringType as RecordTypeInfo
        if recordType != null && recordType.IsStruct {
            return recordType.Name
        }

        return ""
    }

    static func ReportIfNeeded(field: FieldDeclaration, initializer: Expression, scopes: AnalyzerScopeStack, diagnostics: AnalyzerDiagnosticSink) {
        if AnalyzerDefiniteAssignment.HasStaticModifier(field.Modifiers) {
            return
        }

        declaringType := scopes.CurrentTypeScope()
        classType := declaringType as ClassTypeInfo
        recordType := declaringType as RecordTypeInfo
        if classType == null && recordType == null {
            return
        }

        declaredMembers := classType != null ? classType.DeclaredMembers : recordType.DeclaredMembers
        instanceMemberNames := new HashSet<string>(StringComparer.Ordinal)
        for member in declaredMembers {
            if !member.IsStatic {
                instanceMemberNames.Add(member.Name)
            }
        }

        // A PRIMARY CONSTRUCTOR PARAMETER IS NOT PART OF THE INSTANCE, even when a field of the same
        // name is declared from it. It is an argument the constructor was called with, available
        // before the object is, which is why C# lets a record's positional parameters appear in a
        // field initializer and why `class Box(value: int) { Doubled: int = value * 2 }` is fine.
        shadowedNames := new HashSet<string>(StringComparer.Ordinal)
        primaryParameters := classType != null ? classType.PrimaryConstructorParameters : recordType.PrimaryConstructorParameters
        for parameter in primaryParameters {
            shadowedNames.Add(parameter.Name)
        }

        CollectLambdaParameterNames(initializer, shadowedNames)
        Walk(initializer, instanceMemberNames, shadowedNames, field.Name, diagnostics)
    }

    static func CollectLambdaParameterNames(node: object, names: HashSet<string>) {
        lambda := node as LambdaExpression
        if lambda != null {
            for parameter in lambda.Parameters {
                names.Add(parameter.Name)
            }
        }

        for child in AstChildrenCore.Of(node) {
            CollectLambdaParameterNames(child, names)
        }
    }

    static func Walk(node: object, instanceMemberNames: HashSet<string>, shadowedNames: HashSet<string>, fieldName: string, diagnostics: AnalyzerDiagnosticSink) {
        thisExpression := node as ThisExpression
        if thisExpression != null {
            Report("this", fieldName, thisExpression.Line, thisExpression.Column, 4, diagnostics)
            return
        }

        baseExpression := node as BaseExpression
        if baseExpression != null {
            Report("base", fieldName, baseExpression.Line, baseExpression.Column, 4, diagnostics)
            return
        }

        identifier := node as IdentifierExpression
        if identifier != null {
            if instanceMemberNames.Contains(identifier.Name) && !shadowedNames.Contains(identifier.Name) {
                Report(identifier.Name, fieldName, identifier.Line, identifier.Column, identifier.Name.Length, diagnostics)
            }

            return
        }

        for child in AstChildrenCore.Of(node) {
            Walk(child, instanceMemberNames, shadowedNames, fieldName, diagnostics)
        }
    }

    static func Report(reference: string, fieldName: string, line: int, column: int, length: int, diagnostics: AnalyzerDiagnosticSink) {
        message := "The initializer of '" + fieldName + "' cannot use '" + reference + "': field initializers run before the object exists"
        suggestion := "Assign '" + fieldName + "' in a constructor, where the object is built, or make '" + reference + "' static."
        sourceSnippet := diagnostics.SourceSnippet(line)
        currentFilePath := diagnostics.CurrentFilePath
        if sourceSnippet != null && currentFilePath != null {
            diagnostics.ReportBuilt(ErrorMessageBuilder.FieldInitializerUsesInstance(currentFilePath, line, column, sourceSnippet, length, reference, fieldName))
            return
        }

        diagnostics.Report(ErrorCode.FieldInitializerUsesInstance, message, line, column, suggestion, length)
    }
}
