namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import NSharpLang.Compiler.Ast


// ONE STEP THE PROPERTY-PATTERN WALK CANNOT TAKE FOR ITSELF, AND EVERYTHING THAT STEP NEEDS.
//
// The walk owns what an object pattern's property list MEANS — which owner the properties are looked
// up on, whether the scrutinee's generic instantiation supplies a substitution, what each property
// resolves to, whether a property exists at all, and which of the two bindings a property performs.
// What it cannot do is run the analyzer's own pattern walk or declare a symbol into the analyzer's
// scope stack, so it ASKS: one request at a time, each naming a kind and carrying every value the
// step needs. Nothing here is a policy the driver may reinterpret.
//
// The two kinds:
//   1  analyse a NESTED pattern against the property's resolved type
//   2  declare the implicit binding for a property with no nested pattern
class PropertyPatternBindingRequest {
    Kind: int
    Pattern: Pattern?
    Name: string?
    CarriedType: TypeInfo
    Line: int
    Column: int

    constructor(kind: int, carriedType: TypeInfo) {
        Kind = kind
        Pattern = null
        Name = null
        CarriedType = carriedType
        Line = 0
        Column = 0
    }
}

// THE PROPERTY-PATTERN WALK'S WHOLE STATE, SUSPENDED BETWEEN TWO STEPS.
//
// `Index` is the walk's program counter over the property list. The owner and the substitution are
// derived ONCE at `Begin` from the scrutinee, exactly as the C# member derived them once above its
// loop, because they are properties of the scrutinee rather than of any one property pattern.
class PropertyPatternBindingState {
    propertiesValue: List<PropertyPattern>
    valueTypeValue: TypeInfo
    declarationOwnerValue: TypeInfo
    substitutionValue: Dictionary<string, TypeInfo>?
    lineValue: int
    columnValue: int

    Properties: List<PropertyPattern> => propertiesValue
    ValueType: TypeInfo => valueTypeValue
    DeclarationOwner: TypeInfo => declarationOwnerValue
    Substitution: Dictionary<string, TypeInfo>? => substitutionValue
    Line: int => lineValue
    Column: int => columnValue

    Index: int

    constructor(properties: List<PropertyPattern>, valueType: TypeInfo, declarationOwner: TypeInfo, substitution: Dictionary<string, TypeInfo>?, line: int, column: int) {
        propertiesValue = properties
        valueTypeValue = valueType
        declarationOwnerValue = declarationOwner
        substitutionValue = substitution
        lineValue = line
        columnValue = column
        Index = 0
    }
}

// WHAT AN OBJECT PATTERN'S PROPERTY LIST BINDS, and the one diagnostic it produces when a named
// property is not there.
//
// An object pattern — `{ Age: > 3, Name }` — is the only pattern that looks a member up by name on
// an arbitrary scrutinee. For each property in written order it resolves the property's type, and
// then does exactly one of three things: REPORT that the scrutinee has no such property, ANALYSE the
// nested pattern against the resolved type, or DECLARE the implicit binding. It is the pattern
// family's first BINDING state carrier: unlike the shape, comparability and reachability questions
// that moved before it, it writes into the analyzer's scope stack and re-enters the pattern walk.
//
// WHY A REQUEST LOOP RATHER THAN A HOISTED SCHEDULE, AND THE MEASUREMENT DECIDED IT BOTH WAYS.
// The deciding question the two earlier state carriers asked was whether the STEP COUNT depends on
// an answer the walk does not have yet. Here it measurably does NOT. Every property's resolution was
// computed three times in a throwaway instrumented baseline — once for the whole list BEFORE any
// step ran, once at its natural interleaved time, and once for the whole list AFTER the last step —
// over all 72 corpus targets and 275 fixtures: 103 entries, 133 properties, and the three schedules
// agreed on EVERY ONE. Re-entering the pattern walk cannot change what a later property resolves to,
// so unlike slice 24's receiver protocol this walk's operands are count-exact and knowable up front.
//
// What is NOT knowable up front is the DELIVERY, and that is why the schedule is still handed over
// one step at a time. `_errors` is a single ordered list. Of the 82 measured nested analyses 8
// REPORT, and 2 of the 16 declares report as well (a duplicate name, a shadowed outer symbol), so a
// hoisted schedule that emitted this walk's own NL503s while resolving would print them BEFORE
// diagnostics that a preceding property's nested pattern had already produced. `{ Age: < "x",
// Weight: 3 }` emits the relational mismatch and THEN the missing-property report; a hoist emits
// them in the other order. `nlc check` distincts and hides that; the unsorted build transcript does
// not. So the walk keeps its own reporter and yields between steps, and the driver performs exactly
// the one operation it is handed.
//
// THE OWNER IS THE SCRUTINEE, EXCEPT WHEN THE SCRUTINEE IS A CLOSED GENERIC. A `Box<int>` has no
// declared members of its own; its members live on the generic DEFINITION and are typed by a
// substitution built from the instantiation's arguments. Both are derived once, before the first
// property, and a definition that yields no substitution (a mismatched argument count, an
// instantiation of something that is not a source generic) still looks its members up on whatever
// definition resolved — the C# member's `substitution` stayed null in that case rather than falling
// back to the instantiation, and that is preserved.
//
// TWO SOURCES OF A PROPERTY TYPE, ASKED IN THIS ORDER AND NOT INTERCHANGEABLE. A DECLARED shape
// answers first: a class, struct or record's own value members, resolved through the substitution.
// Only if that finds nothing is a REFLECTED scrutinee asked for a public property by name, and its
// type comes back through the nullability-metadata conversion so an external `string?` stays
// nullable. A record's PRIMARY CONSTRUCTOR PARAMETERS are not declared members, so
// `record Item(Name: string, Count: int)` matched `{ Count: 1 }` REPORTS — measured, preserved, and
// pinned by a contract rather than quietly improved here.
//
// THE BINDING NAME'S EXPLICIT ARM IS UNREACHABLE FROM SOURCE AND IS PRESERVED ANYWAY. Both parser
// productions build a `PropertyPattern` with a null `BindingName` — the nested form and the implicit
// `{ value }` form alike — so `BindingName ?? Name` always takes the fallback in production. The
// explicit arm is live code a later parser change can reach; it is pinned by construction in the
// contracts, exactly as slice 27 pinned its two unreachable walk arms.
class AnalyzerPropertyPatternBinding {
    diagnosticsValue: AnalyzerDiagnosticSink
    spansValue: AnalyzerDiagnosticSpans
    declarationContextValue: AnalyzerDeclarationContext
    typeSubstitutionValue: AnalyzerTypeSubstitution

    constructor(diagnostics: AnalyzerDiagnosticSink, spans: AnalyzerDiagnosticSpans, declarationContext: AnalyzerDeclarationContext, typeSubstitution: AnalyzerTypeSubstitution) {
        diagnosticsValue = diagnostics
        spansValue = spans
        declarationContextValue = declarationContext
        typeSubstitutionValue = typeSubstitution
    }

    // The owner and the substitution are the scrutinee's, and they are settled here so that no
    // property pattern can observe a different owner than its neighbours.
    func Begin(properties: List<PropertyPattern>, valueType: TypeInfo, line: int, column: int): PropertyPatternBindingState {
        declarationOwner := valueType
        substitution: Dictionary<string, TypeInfo>? = null
        genericValue := valueType as GenericTypeInfo
        if genericValue != null {
            genericDefinition := typeSubstitutionValue.ResolveGenericDefinition(genericValue)
            if genericDefinition != null {
                declarationOwner = genericDefinition
                substitution = declarationContextValue.CreateGenericSubstitution(genericDefinition, genericValue.TypeArguments)
            }
        }

        return new PropertyPatternBindingState(properties, valueType, declarationOwner, substitution, line, column)
    }

    // Advances over the property list until it has a step for the driver, reporting the properties
    // that are not there as it passes them. A null answer means the list is finished.
    func NextStep(state: PropertyPatternBindingState): PropertyPatternBindingRequest? {
        while state.Index < state.Properties.Count {
            property := state.Properties[state.Index]
            state.Index = state.Index + 1

            propertyType := FindPropertyType(state, property.Name)
            if propertyType == null {
                ReportMissingProperty(state, property)
                continue
            }

            resolved: TypeInfo = propertyType
            if property.Pattern != null {
                request := new PropertyPatternBindingRequest(1, resolved)
                request.Pattern = property.Pattern
                return request
            }

            bindingName := property.BindingName
            if bindingName == null {
                bindingName = property.Name
            }

            span := spansValue.GetPropertyPatternNameDiagnosticSpan(property, state.Line, state.Column)
            request := new PropertyPatternBindingRequest(2, resolved)
            request.Name = bindingName
            request.Line = span.Line
            request.Column = span.Column
            return request
        }

        return null
    }

    // The declared shape first, the reflected metadata second; `null` is "this scrutinee has no such
    // property", which is the only thing that reports.
    func FindPropertyType(state: PropertyPatternBindingState, name: string): TypeInfo? {
        sourceShape := new AnalyzerSourceMemberShape()
        if declarationContextValue.TryGetSourceMemberShape(state.DeclarationOwner, state.Substitution, out sourceShape) {
            declaredMember: TypeInfo = BuiltInTypes.Unknown
            if declarationContextValue.TryResolveDeclaredValueMember(sourceShape.Owner, sourceShape.DeclaredMembers, name, state.Substitution, out declaredMember) {
                return declaredMember
            }
        }

        reflectionType := state.ValueType as ReflectionTypeInfo
        if reflectionType != null {
            property := reflectionType.Type.GetProperty(name)
            if property != null {
                return NullabilityMetadataReflection.ConvertProperty(property)
            }
        }

        return null
    }

    // NL503 over the property NAME, anchored on the enclosing pattern when the property carries no
    // position of its own. The scrutinee is rendered by its own `ToString`, so a nullable prints as
    // `Box?` — which is the honest message, because a nullable really has no declared members until
    // it is narrowed.
    func ReportMissingProperty(state: PropertyPatternBindingState, property: PropertyPattern) {
        span := spansValue.GetPropertyPatternNameDiagnosticSpan(property, state.Line, state.Column)
        valueObject := state.ValueType as object
        diagnosticsValue.Report(ErrorCode.InvalidPattern, "'" + valueObject.ToString() + "' doesn't have a property named '" + property.Name + "'", span.Line, span.Column, null, span.Length)
    }
}
