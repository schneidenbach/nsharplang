namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE ONE EXPRESSION AN EXPRESSION TREE CANNOT HOLD, AND WHAT TO CALL IT.
//
// The finding is a NODE and a DESCRIPTION rather than a bare bool, because the report anchors on the
// offending node's own span — not on the lambda's — and names the shape in the user's words. The
// walk returns the FIRST one it meets in evaluation order, which is what makes a body with two
// problems complain about the one the reader reaches first.
class UnsupportedExpressionTreeFinding {
    expressionValue: Expression
    descriptionValue: string

    Expression: Expression => expressionValue
    Description: string => descriptionValue

    constructor(expression: Expression, description: string) {
        expressionValue = expression
        descriptionValue = description
    }
}

// WHICH LAMBDA BODIES AN EXPRESSION TREE ADMITS.
//
// This is a DIFFERENT SUBJECT from what a lambda MEANS, and it is a separate owner for that reason.
// The lambda walk decides WHEN the question is asked — only for a lambda whose expected type is an
// expression-tree target, only after the body has been walked, and only when nothing else already
// complained about that body. This owner decides WHAT the answer is: which body SHAPE is admissible
// and which expression FORMS may appear inside it.
//
// IT IS ALMOST — BUT NOT ENTIRELY — SYNTACTIC, AND THE EXCEPTION IS THE POINT.
// Fourteen of its fifteen node shapes are decided by the node alone plus the lambda's parameter
// names. The fifteenth is a CALL's receiver, where `x.Trim()` (an instance call on a parameter) and
// `Path.Combine(...)` (a static call through a TYPE NAME) are the same AST shape and are told apart
// only by asking what the receiver's name RESOLVES to. That question needs the scope stack, the
// declaration context's alias resolution, the well-known-type table and the external metadata probe,
// which is why this owner holds four collaborators rather than none. A validator that guessed from
// syntax alone would reject every static call in an expression tree, or admit every captured
// variable dressed as one.
//
// THE ORDER OF THE FOUR RECEIVER PROBES IS OBSERVABLE AND IS PRESERVED: a receiver that starts with
// a VALUE identifier — a lambda parameter or anything the scope stack knows as a symbol — is never a
// static receiver whatever else the name might also mean, so the value question is asked FIRST and
// answers `false` on its own. Only then is the dotted name resolved, and only in the order
// well-known type, declared type (through the alias door), external type.
//
// BOTH REPORTS DEDUPE, AND THAT IS THE ONE THING A PORT MUST NOT LOSE. A lambda can be reached twice
// — once through the expression dispatch and once through a target-typed door — and the second visit
// must not double the sentence. Identity is code + line + column + message, asked of the sink.
class AnalyzerExpressionTreeValidator {
    diagnostics: AnalyzerDiagnosticSink
    spans: AnalyzerDiagnosticSpans
    scopes: AnalyzerScopeStack
    declarationContext: AnalyzerDeclarationContext
    externalTypeProbe: AnalyzerExternalTypeProbe
    wellKnownTypes: AnalyzerWellKnownTypes?

    constructor(diagnosticSink: AnalyzerDiagnosticSink, spansOwner: AnalyzerDiagnosticSpans, scopeStack: AnalyzerScopeStack, declarations: AnalyzerDeclarationContext, probe: AnalyzerExternalTypeProbe, knownTypes: AnalyzerWellKnownTypes?) {
        diagnostics = diagnosticSink
        spans = spansOwner
        scopes = scopeStack
        declarationContext = declarations
        externalTypeProbe = probe
        wellKnownTypes = knownTypes
    }

    // THE BODY SHAPE. An expression tree is a TREE, and a block body is statements — there is no
    // expression to build a tree from. The report fires BEFORE the block is walked, so a block lambda
    // in an expression-tree position is told the shape is wrong before it is told anything about its
    // contents. It anchors on the LAMBDA rather than on the block, because the lambda is what the
    // reader must rewrite.
    func ReportBlockLambdaIfNeeded(lambda: LambdaExpression) {
        message := "Expression-tree lambdas must use an expression body; block bodies are not supported"
        if diagnostics.HasReported(ErrorCode.FeatureNotImplemented, message, lambda.Line, lambda.Column) {
            return
        }

        diagnostics.Report(ErrorCode.FeatureNotImplemented, message, lambda.Line, lambda.Column, "Use 'x => expression' for expression-tree targets, or assign the block lambda to a delegate type such as Func or Action.", spans.GetTokenLength(lambda.Line, lambda.Column))
    }

    // THE BODY'S CONTENTS. ANSWERS whether it reported, which is how the caller distinguishes "this
    // body is fine" from "this body was already complained about". A deduped report answers FALSE:
    // the sentence exists either way, and the caller's question is whether THIS visit added one.
    func ReportUnsupportedExpressionIfNeeded(expression: Expression, parameterNames: HashSet<string>): bool {
        unsupported := FindUnsupportedExpression(expression, parameterNames)
        if unsupported == null {
            return false
        }

        span := spans.GetExpressionDiagnosticSpan(unsupported.Expression)
        message := "Expression-tree lambda body contains unsupported " + unsupported.Description
        if diagnostics.HasReported(ErrorCode.FeatureNotImplemented, message, span.Line, span.Column) {
            return false
        }

        diagnostics.Report(ErrorCode.FeatureNotImplemented, message, span.Line, span.Column, "Use a lambda parameter, member access, literal, conditional expression, supported binary expression, supported unary expression, positional instance/static call, or anonymous-object projection.", span.Length)
        return true
    }

    // THE FIRST INADMISSIBLE NODE IN EVALUATION ORDER, or null when the whole subtree is admissible.
    //
    // The admissible set is small and closed on purpose: parameters, member access, index access,
    // parentheses, the nine literal-ish forms, supported binary and unary operators, the ternary,
    // hard and safe casts, positional non-generic calls, and anonymous-object projection. EVERYTHING
    // ELSE is named and refused, and the default arm names it by its node type rather than staying
    // silent — an unnamed refusal is a worse diagnostic than a clumsy one.
    func FindUnsupportedExpression(expression: Expression, parameterNames: HashSet<string>): UnsupportedExpressionTreeFinding? {
        identifier := expression as IdentifierExpression
        if identifier != null {
            if parameterNames.Contains(identifier.Name) {
                return null
            }

            return new UnsupportedExpressionTreeFinding(identifier, "captured or static identifier '" + identifier.Name + "'")
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null {
            if memberAccess.IsNullConditional {
                return new UnsupportedExpressionTreeFinding(memberAccess, "null-conditional member access")
            }

            return FindUnsupportedExpression(memberAccess.Object, parameterNames)
        }

        indexAccess := expression as IndexAccessExpression
        if indexAccess != null {
            if indexAccess.IsNullConditional {
                return new UnsupportedExpressionTreeFinding(indexAccess, "null-conditional index access")
            }

            inObject := FindUnsupportedExpression(indexAccess.Object, parameterNames)
            if inObject != null {
                return inObject
            }

            return FindUnsupportedExpression(indexAccess.Index, parameterNames)
        }

        parenthesized := expression as ParenthesizedExpression
        if parenthesized != null {
            return FindUnsupportedExpression(parenthesized.Inner, parameterNames)
        }

        if IsAdmissibleLeaf(expression) {
            return null
        }

        binary := expression as BinaryExpression
        if binary != null {
            if !OperatorFacts.IsSupportedExpressionTreeBinaryOperator(binary.Operator) {
                return new UnsupportedExpressionTreeFinding(binary, "binary operator '" + OperatorFacts.GetBinaryText(binary.Operator) + "'")
            }

            inLeft := FindUnsupportedExpression(binary.Left, parameterNames)
            if inLeft != null {
                return inLeft
            }

            return FindUnsupportedExpression(binary.Right, parameterNames)
        }

        unary := expression as UnaryExpression
        if unary != null {
            if !OperatorFacts.IsSupportedExpressionTreeUnaryOperator(unary.Operator) {
                return new UnsupportedExpressionTreeFinding(unary, "unary operator '" + OperatorFacts.GetUnaryText(unary.Operator) + "'")
            }

            return FindUnsupportedExpression(unary.Operand, parameterNames)
        }

        ternary := expression as TernaryExpression
        if ternary != null {
            inCondition := FindUnsupportedExpression(ternary.Condition, parameterNames)
            if inCondition != null {
                return inCondition
            }

            inThen := FindUnsupportedExpression(ternary.ThenExpression, parameterNames)
            if inThen != null {
                return inThen
            }

            return FindUnsupportedExpression(ternary.ElseExpression, parameterNames)
        }

        cast := expression as CastExpression
        if cast != null {
            if cast.Kind != CastKind.Hard && cast.Kind != CastKind.Safe {
                return new UnsupportedExpressionTreeFinding(cast, "cast expression")
            }

            return FindUnsupportedExpression(cast.Expression, parameterNames)
        }

        call := expression as CallExpression
        if call != null {
            return FindUnsupportedCallExpression(call, parameterNames)
        }

        newExpression := expression as NewExpression
        if newExpression != null {
            return FindUnsupportedObjectCreation(newExpression, parameterNames)
        }

        return new UnsupportedExpressionTreeFinding(expression, DescribeExpression(expression))
    }

    // THE NINE FORMS THAT ARE ADMISSIBLE AND HAVE NOTHING INSIDE THEM WORTH WALKING. `default`,
    // `nameof` and `typeof` join the six literals here because all three are decided before runtime:
    // an expression tree holds their VALUE, never their evaluation. Note that `default`, `nameof` and
    // `typeof` ALSO appear in the description table below — admissible here, named there for the
    // shapes that reach the default arm by another route.
    static func IsAdmissibleLeaf(expression: Expression): bool {
        intLiteral := expression as IntLiteralExpression
        if intLiteral != null {
            return true
        }

        floatLiteral := expression as FloatLiteralExpression
        if floatLiteral != null {
            return true
        }

        charLiteral := expression as CharLiteralExpression
        if charLiteral != null {
            return true
        }

        stringLiteral := expression as StringLiteralExpression
        if stringLiteral != null {
            return true
        }

        boolLiteral := expression as BoolLiteralExpression
        if boolLiteral != null {
            return true
        }

        nullLiteral := expression as NullLiteralExpression
        if nullLiteral != null {
            return true
        }

        defaultExpression := expression as DefaultExpression
        if defaultExpression != null {
            return true
        }

        nameofExpression := expression as NameofExpression
        if nameofExpression != null {
            return true
        }

        typeOfExpression := expression as TypeOfExpression
        if typeOfExpression != null {
            return true
        }

        return false
    }

    // A CALL, AND THE FIVE THINGS THAT DISQUALIFY ONE BEFORE ITS ARGUMENTS ARE EVEN LOOKED AT: a
    // callee that is not a member access at all, a null-conditional one, explicit type arguments, a
    // `ref`/`out` argument and a NAMED argument. The order is the order the reader meets them.
    //
    // THE RECEIVER IS DECIDED LAST AND IS THE ONE NON-SYNTACTIC QUESTION IN THE FAMILY: a receiver
    // that names a TYPE is a static call and the receiver is not walked at all, because a type name
    // is not a value an expression tree has to capture.
    func FindUnsupportedCallExpression(call: CallExpression, parameterNames: HashSet<string>): UnsupportedExpressionTreeFinding? {
        memberCall := call.Callee as MemberAccessExpression
        if memberCall == null {
            return new UnsupportedExpressionTreeFinding(call, "non-instance method call")
        }

        if memberCall.IsNullConditional {
            return new UnsupportedExpressionTreeFinding(memberCall, "null-conditional method call")
        }

        typeArguments := call.TypeArguments
        if typeArguments != null && typeArguments.Count > 0 {
            return new UnsupportedExpressionTreeFinding(call, "generic method call")
        }

        argumentIndex := 0
        while argumentIndex < call.Arguments.Count {
            if call.Arguments[argumentIndex].Modifier != ArgumentModifier.None {
                return new UnsupportedExpressionTreeFinding(call, "ref/out method argument")
            }

            argumentIndex = argumentIndex + 1
        }

        namedIndex := 0
        while namedIndex < call.Arguments.Count {
            if call.Arguments[namedIndex].Name != null {
                return new UnsupportedExpressionTreeFinding(call, "named method argument")
            }

            namedIndex = namedIndex + 1
        }

        valueIndex := 0
        while valueIndex < call.Arguments.Count {
            inArgument := FindUnsupportedExpression(call.Arguments[valueIndex].Value, parameterNames)
            if inArgument != null {
                return inArgument
            }

            valueIndex = valueIndex + 1
        }

        if IsStaticCallReceiver(memberCall.Object, parameterNames) {
            return null
        }

        return FindUnsupportedExpression(memberCall.Object, parameterNames)
    }

    // OBJECT CREATION, WHICH AN EXPRESSION TREE ADMITS IN EXACTLY ONE SHAPE: the anonymous-object
    // projection `new { A = x.A }`. Anything with a written type, a constructor argument, a
    // positional initializer property or an indexed one is ordinary construction and is refused.
    func FindUnsupportedObjectCreation(newExpression: NewExpression, parameterNames: HashSet<string>): UnsupportedExpressionTreeFinding? {
        initializer := newExpression.Initializer
        // The second clause can never be the deciding one — `IsAnonymousObjectCreation` already
        // answers false for a missing initializer — and it is written out so the property walk below
        // reads a non-null initializer without an unwrap.
        if !IsAnonymousObjectCreation(newExpression) || initializer == null {
            return new UnsupportedExpressionTreeFinding(newExpression, "object construction")
        }

        propertyIndex := 0
        while propertyIndex < initializer.Properties.Count {
            inProperty := FindUnsupportedExpression(initializer.Properties[propertyIndex].Value, parameterNames)
            if inProperty != null {
                return inProperty
            }

            propertyIndex = propertyIndex + 1
        }

        return null
    }

    // IS THIS RECEIVER A TYPE RATHER THAN A VALUE? The value question is asked first and is decisive:
    // a name the scope stack knows as a symbol, or a lambda parameter, is a VALUE even when a type of
    // the same name also exists, so shadowing resolves the way the rest of the language resolves it.
    func IsStaticCallReceiver(expression: Expression, parameterNames: HashSet<string>): bool {
        if ReceiverStartsWithValueIdentifier(expression, parameterNames) {
            return false
        }

        name := ""
        if !AnalyzerMemberAccess.TryGetQualifiedExpressionTreeName(expression, out name) {
            return false
        }

        if AnalyzerWellKnownTypeFacts.BuiltInMetadataClrType(wellKnownTypes, name) != null {
            return true
        }

        looked := scopes.LookupType(name)
        candidate: TypeInfo = BuiltInTypes.Unknown
        if looked != null {
            candidate = looked
        }

        resolvedType := declarationContext.ResolveDeclaredAlias(candidate)
        if !BuiltInTypes.IsUnknown(resolvedType) {
            return true
        }

        external := externalTypeProbe.ResolveExternalType(name)
        reflected := external as ReflectionTypeInfo
        return reflected != null
    }

    // DOES THE DOTTED CHAIN BOTTOM OUT IN A VALUE? Only a plain identifier and a non-null-conditional
    // member access can continue the chain; anything else is not a name at all, and a name is the
    // only thing a type could be spelled as.
    func ReceiverStartsWithValueIdentifier(expression: Expression, parameterNames: HashSet<string>): bool {
        identifier := expression as IdentifierExpression
        if identifier != null {
            if parameterNames.Contains(identifier.Name) {
                return true
            }

            return scopes.LookupSymbol(identifier.Name) != null
        }

        memberAccess := expression as MemberAccessExpression
        if memberAccess != null && !memberAccess.IsNullConditional {
            return ReceiverStartsWithValueIdentifier(memberAccess.Object, parameterNames)
        }

        return false
    }

    // AN ANONYMOUS-OBJECT PROJECTION: no written type, no constructor arguments, an initializer, and
    // every property NAMED and not indexed.
    static func IsAnonymousObjectCreation(newExpression: NewExpression): bool {
        if newExpression.Type != null {
            return false
        }

        if newExpression.ConstructorArguments.Count != 0 {
            return false
        }

        initializer := newExpression.Initializer
        if initializer == null {
            return false
        }

        index := 0
        while index < initializer.Properties.Count {
            property := initializer.Properties[index]
            if property.Name == null || property.IndexExpression != null {
                return false
            }

            index = index + 1
        }

        return true
    }

    // WHAT TO CALL A NODE THE TREE CANNOT HOLD. Seventeen shapes get a phrase of their own; anything
    // else is named by its AST node type, which is a worse sentence than the others but a better one
    // than silence.
    static func DescribeExpression(expression: Expression): string {
        assignment := expression as AssignmentExpression
        if assignment != null {
            return "assignment expression"
        }

        awaitExpression := expression as AwaitExpression
        if awaitExpression != null {
            return "await expression"
        }

        cast := expression as CastExpression
        if cast != null {
            return "cast expression"
        }

        checkedExpression := expression as CheckedExpression
        if checkedExpression != null {
            return "checked expression"
        }

        defaultExpression := expression as DefaultExpression
        if defaultExpression != null {
            return "default expression"
        }

        interpolated := expression as InterpolatedStringExpression
        if interpolated != null {
            return "interpolated string"
        }

        lambda := expression as LambdaExpression
        if lambda != null {
            return "nested lambda"
        }

        matchExpression := expression as MatchExpression
        if matchExpression != null {
            return "match expression"
        }

        mustExpression := expression as MustExpression
        if mustExpression != null {
            return "must expression"
        }

        nameofExpression := expression as NameofExpression
        if nameofExpression != null {
            return "nameof expression"
        }

        rangeExpression := expression as RangeExpression
        if rangeExpression != null {
            return "range expression"
        }

        sizeOfExpression := expression as SizeOfExpression
        if sizeOfExpression != null {
            return "sizeof expression"
        }

        spreadExpression := expression as SpreadExpression
        if spreadExpression != null {
            return "spread expression"
        }

        throwExpression := expression as ThrowExpression
        if throwExpression != null {
            return "throw expression"
        }

        tupleExpression := expression as TupleExpression
        if tupleExpression != null {
            return "tuple expression"
        }

        typeOfExpression := expression as TypeOfExpression
        if typeOfExpression != null {
            return "typeof expression"
        }

        uncheckedExpression := expression as UncheckedExpression
        if uncheckedExpression != null {
            return "unchecked expression"
        }

        withExpression := expression as WithExpression
        if withExpression != null {
            return "with expression"
        }

        // The `GetType()` receiver is cast to `object` first — the columnar backend declines a
        // `GetType()` call on a typed receiver (the recorded emitter gap).
        boxed := expression as object
        return boxed.GetType().Name
    }
}
