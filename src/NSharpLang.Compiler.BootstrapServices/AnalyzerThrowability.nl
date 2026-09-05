namespace NSharpLang.Compiler

import System
import NSharpLang.Compiler.Ast


// WHAT IT MEANS FOR A TYPE TO BE THROWABLE — the one question three N# constructs ask about
// `System.Exception`, and the only thing they share.
//
// Three places in the language hand the analyzer a type and claim it can be thrown or caught: the
// operand of a `throw`, the declared exception type of an `assert throws`, and a `catch` clause's
// exception type. All three asked the SAME predicate, and none of them agrees with any other about
// what to do with the answer — the three reports differ in code, wording, suggestion and span — so
// the predicate is what moves and the reports stay with their own families.
//
// IT IS AN OWNER RATHER THAN A STATIC BECAUSE THE ANSWER IS NOT A FUNCTION OF THE TYPE ALONE. A
// simple NAME is looked up in the SCOPE STACK and re-asked, a declared alias is resolved through the
// DECLARATION CONTEXT, and a source class's base is read under its own owner's substitution through
// the TYPE SUBSTITUTION engine. All three of those collaborators are constructed exactly once by
// `Analyzer.cs` and are never rebuilt with the metadata load context, so holding them is safe.
//
// THE CLR CONVERSION FUNNEL IS PASSED IN AT THE CALL rather than held, for the reason the assignability
// oracle is: `Analyzer.cs` REBUILDS `AnalyzerClrTypeConversion` when the metadata load context opens
// and again when it is disposed, so an owner constructed once may not keep a reference to it. It is
// threaded through the recursion because the recursion is where the funnel is reached.
//
// EVERY ARM IS A SILENCE RULE OR A WIDENING, AND THE ORDER IS BEHAVIOUR. `null` and `never` are
// throwable because a `throw null` is a runtime concern rather than a type error and a `never` value
// cannot exist; `unknown` and an EXTERNAL type are throwable because the analyzer has not finished
// resolving them and a second complaint about a type nothing could name is noise; a nullable answers
// for what it wraps; a reflected type answers by real CLR assignability; a simple name answers by its
// two well-known spellings, then by whatever the scope stack says it declares, then by its CLR twin
// if the funnel can name one, and otherwise NO; and a source class answers for its base class, which
// is what makes a user exception hierarchy work. A type that reaches the end is not throwable.
class AnalyzerThrowability {
    scopesValue: AnalyzerScopeStack
    declarationContextValue: AnalyzerDeclarationContext
    typeSubstitutionValue: AnalyzerTypeSubstitution

    constructor(scopes: AnalyzerScopeStack, declarationContext: AnalyzerDeclarationContext, typeSubstitution: AnalyzerTypeSubstitution) {
        scopesValue = scopes
        declarationContextValue = declarationContext
        typeSubstitutionValue = typeSubstitution
    }

    // WHETHER A VALUE OF THIS TYPE MAY BE THROWN OR CAUGHT. The oblivious unwrap is a LOOP rather
    // than a recursion because each unwrap can expose another alias, and the alias resolve runs on
    // the way in and again after every unwrap.
    func IsThrowable(candidate: TypeInfo, clrTypeConversion: AnalyzerClrTypeConversion): bool {
        resolved := declarationContextValue.ResolveDeclaredAlias(candidate)
        oblivious := resolved as ObliviousTypeInfo
        while oblivious != null {
            resolved = declarationContextValue.ResolveDeclaredAlias(oblivious.InnerType)
            oblivious = resolved as ObliviousTypeInfo
        }

        if BuiltInTypes.Is(resolved, BuiltInTypes.Null) || BuiltInTypes.Is(resolved, BuiltInTypes.Never) {
            return true
        }

        if BuiltInTypes.IsUnknown(resolved) {
            return true
        }

        external := resolved as ExternalTypeInfo
        if external != null {
            return true
        }

        nullable := resolved as NullableTypeInfo
        if nullable != null {
            return IsThrowable(nullable.InnerType, clrTypeConversion)
        }

        reflected := resolved as ReflectionTypeInfo
        if reflected != null {
            return AnalyzerConversionFacts.IsReflectionAssignableFrom(ExceptionRoot(), reflected.Type)
        }

        simple := resolved as SimpleTypeInfo
        if simple != null {
            return IsThrowableSimpleName(simple, resolved, clrTypeConversion)
        }

        classType := resolved as ClassTypeInfo
        if classType != null {
            baseClass := classType.BaseClass
            if baseClass == null {
                return false
            }

            return IsThrowable(typeSubstitutionValue.ResolveTypeForSourceOwner(baseClass, classType, null), clrTypeConversion)
        }

        return false
    }

    // A BARE NAME, ANSWERED IN THREE STEPS. The two well-known spellings are the ones the parser
    // produces for a bare `catch` and for a written `System.Exception`; the scope-stack redirect is
    // guarded against a name that resolves to ITSELF, which would otherwise recurse forever; and the
    // CLR funnel is the last door, so a BCL exception named by an import still answers yes.
    func IsThrowableSimpleName(simple: SimpleTypeInfo, resolved: TypeInfo, clrTypeConversion: AnalyzerClrTypeConversion): bool {
        name := simple.Name
        if name == "Exception" || name == "System.Exception" {
            return true
        }

        namedType := scopesValue.LookupType(name)
        if namedType != null && !Object.ReferenceEquals(namedType, resolved) {
            return IsThrowable(namedType, clrTypeConversion)
        }

        clrType := clrTypeConversion.TryConvertTypeInfoToClrType(resolved)
        if clrType != null {
            return AnalyzerConversionFacts.IsReflectionAssignableFrom(ExceptionRoot(), clrType)
        }

        return false
    }

    // THE RUNTIME IDENTITY EVERY REFLECTED ANSWER IS MEASURED AGAINST. `typeof` resolves this one —
    // unlike the non-generic sequence interfaces the loop family had to name through `Type.GetType`
    // — and it is the RUNTIME `System.Exception`, deliberately: a type loaded into the analyzer's
    // MetadataLoadContext is a different object from its runtime twin and answers NO here, which is
    // exactly what `Analyzer.cs` did.
    static func ExceptionRoot(): Type {
        return typeof(Exception)
    }
}
