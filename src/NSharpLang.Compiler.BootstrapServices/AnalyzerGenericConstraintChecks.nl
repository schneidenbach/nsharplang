namespace NSharpLang.Compiler

import System
import System.Collections.Generic


// WHETHER A TYPE ARGUMENT SATISFIES A `where` CLAUSE, ASKED THE SAME WAY FOR BOTH OWNERS.
//
// NL208 has been reported at CALL sites since generic functions were written, and it was reported
// nowhere else: `new Box<string>()` under `class Box<T> where T : struct` was accepted in silence,
// because the predicates and the sentences lived inside `AnalyzerSyntheticCallValidator` and only a
// `CallExpression` could reach them. They are here now, so a type-argument site asks exactly the
// question a call site asks and gets exactly the same sentence back with its own owner's name.
//
// THE MESSAGES ARE SHARED AND THE SUGGESTIONS ARE NOT, deliberately. A violation is the same fact
// whoever wrote it, so the sentence that states it must not drift between the two reporters. What to
// DO about it differs: a call site passes an argument, a type-argument site writes one, and telling
// someone to "pass" a type they wrote in a field declaration would be a small lie.
class AnalyzerGenericConstraintChecks {

    // Violation kinds. 0 is "satisfied", and the three others name the special constraint that failed.
    static func ViolationNone(): int {
        return 0
    }

    static func ViolationClass(): int {
        return 1
    }

    static func ViolationStruct(): int {
        return 2
    }

    static func ViolationNew(): int {
        return 3
    }

    // The three special constraints, in the order the CLR records them. At most one is reported per
    // parameter: a bound type that fails `class` will also fail `new()` often enough that reporting
    // both would bury the cause.
    static func SpecialViolationKind(special: int, bound: TypeInfo): int {
        classFlag := Convert.ToInt32(SpecialConstraintKind.Class)
        structFlag := Convert.ToInt32(SpecialConstraintKind.Struct)
        newFlag := Convert.ToInt32(SpecialConstraintKind.New)

        if (special & classFlag) == classFlag {
            if !AnalyzerConversionFacts.IsReferenceType(bound) {
                return ViolationClass()
            }
        }

        if (special & structFlag) == structFlag {
            boundNullable := bound as NullableTypeInfo
            if AnalyzerConversionFacts.IsReferenceType(bound) || boundNullable != null {
                return ViolationStruct()
            }
        }

        if (special & newFlag) == newFlag {
            if !HasParameterlessConstructor(bound) {
                return ViolationNew()
            }
        }

        return ViolationNone()
    }

    // Whether a type satisfies the `new()` constraint.
    //
    // Every value type has one implicitly, declared or not — that covers structs, record structs and
    // every CLR value type. A record CLASS is the one that can lose it: a primary constructor with
    // parameters suppresses the default constructor. An unknown type is assumed to satisfy: a
    // constraint report about a type the analyzer could not resolve is noise on top of the
    // resolution failure the user already has.
    static func HasParameterlessConstructor(candidate: TypeInfo): bool {
        structType := candidate as StructTypeInfo
        if structType != null {
            return true
        }

        classType := candidate as ClassTypeInfo
        if classType != null {
            return classType.HasParameterlessConstructor
        }

        recordType := candidate as RecordTypeInfo
        if recordType != null {
            if recordType.IsStruct {
                return true
            }

            return recordType.PrimaryConstructorParameters.Length == 0
        }

        reflectionType := candidate as ReflectionTypeInfo
        if reflectionType != null {
            clrType := reflectionType.Type
            if clrType.get_IsValueType() {
                return true
            }

            return clrType.GetConstructor(new Type[](0)) != null
        }

        return true
    }

    // ── The sentences ───────────────────────────────────────────────────────────────────────────
    static func SpecialViolationMessage(kind: int, boundText: string, typeParameter: string, ownerName: string): string {
        if kind == ViolationClass() {
            return "`" + boundText + "` is a value type, but type parameter `" + typeParameter + "` of `" + ownerName + "` requires a reference type (the `class` constraint)"
        }

        if kind == ViolationStruct() {
            return "`" + boundText + "` is not a non-nullable value type, but type parameter `" + typeParameter + "` of `" + ownerName + "` requires one (the `struct` constraint)"
        }

        return "`" + boundText + "` has no parameterless constructor, but type parameter `" + typeParameter + "` of `" + ownerName + "` requires one (the `new()` constraint)"
    }

    static func TypeConstraintMessage(boundText: string, closedText: string, typeParameter: string, ownerName: string): string {
        return "`" + boundText + "` does not implement `" + closedText + "`, which type parameter `" + typeParameter + "` of `" + ownerName + "` requires"
    }

    // A CALL site's suggestion: the reader is passing an argument.
    static func CallSuggestion(kind: int, boundText: string, typeParameter: string, ownerName: string): string {
        if kind == ViolationClass() {
            return "Pass a class instance for `" + typeParameter + "`, or relax the `class` constraint on `" + ownerName + "`."
        }

        if kind == ViolationStruct() {
            return "Pass a non-nullable value type for `" + typeParameter + "`, or relax the `struct` constraint on `" + ownerName + "`."
        }

        return "Give `" + boundText + "` a parameterless constructor, or relax the `new()` constraint on `" + ownerName + "`."
    }

    static func CallTypeConstraintSuggestion(boundText: string, closedText: string, ownerName: string): string {
        return "Implement `" + closedText + "` on `" + boundText + "`, or relax the constraint on `" + ownerName + "`."
    }

    // A TYPE-ARGUMENT site's suggestion: the reader wrote the argument in a type reference, so the fix
    // is to write a different one — there is nothing being passed.
    static func TypeArgumentSuggestion(kind: int, boundText: string, typeParameter: string, ownerName: string): string {
        if kind == ViolationClass() {
            return "Use a reference type for `" + typeParameter + "`, or relax the `class` constraint on `" + ownerName + "`."
        }

        if kind == ViolationStruct() {
            return "Use a non-nullable value type for `" + typeParameter + "`, or relax the `struct` constraint on `" + ownerName + "`."
        }

        return "Give `" + boundText + "` a parameterless constructor, or relax the `new()` constraint on `" + ownerName + "`."
    }

    static func TypeArgumentTypeConstraintSuggestion(boundText: string, closedText: string, ownerName: string): string {
        return "Implement `" + closedText + "` on `" + boundText + "`, or relax the constraint on `" + ownerName + "`."
    }

    // ── The TYPE-ARGUMENT reporter ──────────────────────────────────────────────────────────────
    //
    // `new Box<string>()` under `class Box<T> where T : struct` was accepted in SILENCE: NL208 existed
    // only at call sites. This is the sibling, and it asks the same questions of the same kernel — the
    // only differences are the owner's name in the sentence and a suggestion that says "use" rather
    // than "pass", because nothing is being passed.
    //
    // The substitution comes from the declaration context, so a constraint that names another of the
    // owner's own parameters (`where V : IComparable<K>`) closes against the arguments actually written.
    static func ConstraintsOf(definition: TypeInfo): GenericConstraint[] {
        classType := definition as ClassTypeInfo
        if classType != null {
            return classType.Constraints
        }

        structType := definition as StructTypeInfo
        if structType != null {
            return structType.Constraints
        }

        recordType := definition as RecordTypeInfo
        if recordType != null {
            return recordType.Constraints
        }

        interfaceType := definition as InterfaceTypeInfo
        if interfaceType != null {
            return interfaceType.Constraints
        }

        unionType := definition as UnionTypeInfo
        if unionType != null {
            return unionType.Declaration.Constraints
        }

        return new GenericConstraint[](0)
    }

    static func ReportTypeArgumentViolations(constraints: GenericConstraint[], substitution: Dictionary<string, TypeInfo>?, ownerName: string, typeResolver: AnalyzerTypeResolver, assignability: AnalyzerAssignability, diagnostics: AnalyzerDiagnosticSink, line: int, column: int, length: int) {
        if constraints.Length == 0 || substitution == null || substitution.Count == 0 {
            return
        }

        index := 0
        while index < constraints.Length {
            constraint := constraints[index]
            index = index + 1

            boundType: TypeInfo = BuiltInTypes.Unknown
            if !substitution.TryGetValue(constraint.TypeParameter, out boundType) {
                continue
            }

            boundObject := boundType as object
            boundText := boundObject.ToString()
            specialKind := SpecialViolationKind(Convert.ToInt32(constraint.SpecialConstraints), boundType)
            if specialKind != ViolationNone() {
                diagnostics.Report(ErrorCode.GenericConstraintViolation, SpecialViolationMessage(specialKind, boundText, constraint.TypeParameter, ownerName), line, column, TypeArgumentSuggestion(specialKind, boundText, constraint.TypeParameter, ownerName), length)
            }

            typeIndex := 0
            while typeIndex < constraint.Constraints.Count {
                written := constraint.Constraints[typeIndex]
                typeIndex = typeIndex + 1
                resolvedWritten := typeResolver.ResolveType(written)
                closed := AnalyzerSyntheticCallFacts.ApplyGenericBindings(resolvedWritten, substitution)
                if BuiltInTypes.IsUnknown(closed) {
                    continue
                }

                if !assignability.IsSubtypeOf(boundType, closed) && !assignability.IsAssignable(closed, boundType) {
                    closedObject := closed as object
                    closedText := closedObject.ToString()
                    diagnostics.Report(ErrorCode.GenericConstraintViolation, TypeConstraintMessage(boundText, closedText, constraint.TypeParameter, ownerName), line, column, TypeArgumentTypeConstraintSuggestion(boundText, closedText, ownerName), length)
                }
            }
        }
    }
}
