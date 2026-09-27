namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection


// A MEMBER OF THE ENCLOSING TYPE HIDES A FREE FUNCTION OF THE SAME NAME.
//
// Inside a type body a bare name is looked up in the type BEFORE it is looked up in the namespace,
// exactly as C# looks a simple name up in the enclosing type before the enclosing namespace. So in
//
//     func Label(): string => "free"
//     class Widget {
//         func Label(): string => "member"
//         func Show(): string => Label()
//     }
//
// `Show` calls the MEMBER. The analyzer reads it that way — the enclosing type's members answer
// before any free function (`AnalyzerIdentifierResolution.EnclosingTypeHasMember`) — while the
// emitter asked its sibling table first and called the free function: a silent wrong program, `check`
// clean and `run` printing "free".
//
// THE RULE IS BY NAME, NOT BY SIGNATURE. Any member of that name hides every free function of that
// name, whatever its arity or kind, which is C#'s hide-by-name rule for a nested scope: `Label("x")`
// inside `Widget` is an arity error against the member (NL401), never a quiet fall-through to a
// `func Label(s: string)` outside. A non-invocable member (a `string` field or property) hides too:
// the call is refused rather than quietly reaching past the member to the free function.
//
// WHICH MEMBERS COUNT is the same set the analyzer's member resolution answers from:
//   - every member the SOURCE chain declares — methods, fields, properties, events and constants,
//     instance and static alike — own or inherited from a source base;
//   - every member an EXTERNAL base the chain ends in exposes to a derived type: public and
//     protected, never private and never `assembly` (the base lives in another assembly).
// A source type with no written base inherits nothing here: `object`'s members do not hide a free
// function of the same name, which is also what the analyzer answers for them.
//
// WHERE THE FREE FUNCTION CAME FROM DOES NOT MATTER. The sibling table holds the caller's own file's
// functions, its namespace's functions from every other file, and a referenced assembly's free
// functions (`ColumnarFreeFunctionScope.BuildViews`); a member hides all three the same way.
//
// A CLOSURE DISPLAY IS NOT AN ENCLOSING TYPE, BUT IT LEADS TO ONE. A lambda body is handed its
// display, or its parent's display when it is nested in another lambda, and a display's own fields are
// captured locals the body already resolves as bindings. So the walk follows `ClosureEnclosingDef` out
// to the type the source was written in, and a lambda in a member body hides exactly what the member
// body does. A display with no enclosing receiver — a lambda written in a FREE function — has no type
// around it and hides nothing.
class ColumnarSiblingHiding {
    static func IsHiddenByEnclosingMember(enclosingType: ColumnarStructDef?, name: string): bool {
        if name == null || name.Length == 0 {
            return false
        }

        declaringType := enclosingType
        while declaringType != null && declaringType.IsClosureDisplay {
            declaringType = declaringType.ClosureEnclosingDef
        }
        if declaringType == null {
            return false
        }

        current: ColumnarStructDef? = declaringType
        while current != null {
            candidate := current
            if DeclaresMember(candidate, name) {
                return true
            }
            current = candidate.BaseDef
        }

        return ExposesToDerivedType(ColumnarInheritedExternalBase.Resolve(declaringType, null), name)
    }

    static func DeclaresMember(definition: ColumnarStructDef, name: string): bool {
        return definition.Methods.ContainsKey(name) || definition.MethodOverloads.ContainsKey(name) || definition.StaticMethods.ContainsKey(name) || definition.Fields.ContainsKey(name) || definition.StaticFields.ContainsKey(name) || definition.StaticIntConstants.ContainsKey(name) || definition.Properties.ContainsKey(name) || definition.StaticProperties.ContainsKey(name) || definition.Events.ContainsKey(name)
    }

    // A member's NAME does not depend on the base's type arguments, and a base closed over a type
    // this compilation is still writing (`List<Widget>`) answers no reflection question — so the
    // question is asked of the generic definition, which always can.
    static func ExposesToDerivedType(externalBase: Type?, name: string): bool {
        if externalBase == null {
            return false
        }

        owner := externalBase
        if owner.IsGenericType && !owner.IsGenericTypeDefinition {
            owner = owner.GetGenericTypeDefinition()
        }

        members := owner.GetMember(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.Static | BindingFlags.FlattenHierarchy)
        for member in members {
            if IsReachableFromDerivedType(member) {
                return true
            }
        }

        return false
    }

    static func IsReachableFromDerivedType(member: MemberInfo): bool {
        method := member as MethodBase
        if method != null {
            return IsReachableAccessor(method)
        }

        field := member as FieldInfo
        if field != null {
            return field.IsPublic || field.IsFamily || field.IsFamilyOrAssembly
        }

        property := member as PropertyInfo
        if property != null {
            return IsReachableAccessor(property.GetGetMethod(true)) || IsReachableAccessor(property.GetSetMethod(true))
        }

        eventInfo := member as EventInfo
        if eventInfo != null {
            return IsReachableAccessor(eventInfo.GetAddMethod(true))
        }

        return false
    }

    static func IsReachableAccessor(method: MethodBase?): bool {
        return method != null && (method.IsPublic || method.IsFamily || method.IsFamilyOrAssembly)
    }
}
