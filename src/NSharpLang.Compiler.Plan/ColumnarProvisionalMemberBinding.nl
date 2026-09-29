namespace NSharpLang.Compiler.Columnar

import System
import System.Reflection


// THE PLAN'S PROVISIONAL MEMBER BINDING AFTER NL209.
//
// N# rejects a bare name whenever both an enclosing type member group and a visible free-function
// group have that name. The analyzer records the member as the provisional semantic binding for
// navigation and for suppressing cascaded diagnostics; this owner keeps downstream planning aligned
// with that binding if a plan is requested while errors are present. A clean product compilation
// never relies on this rule to choose between the two groups.
//
// WHICH MEMBERS COUNT is the same set the analyzer's member resolution answers from:
//   - every member the SOURCE chain declares — methods, fields, properties, events and constants,
//     instance and static alike — own or inherited from a source base;
//   - every member an EXTERNAL base the chain ends in exposes to a derived type: public and
//     protected, never private and never `assembly` (the base lives in another assembly).
// A source type with no written base inherits nothing here: `object`'s implicit members do not
// create a collision.
//
// WHERE THE FREE FUNCTION CAME FROM DOES NOT MATTER. The sibling table holds the caller's own file's
// functions, its namespace's functions from every other file, and a referenced assembly's free
// functions (`ColumnarFreeFunctionScope.BuildViews`); all three participate in the analyzer's NL209
// check. This helper only keeps the planner's provisional binding consistent.
//
// A CLOSURE DISPLAY IS NOT AN ENCLOSING TYPE, BUT IT LEADS TO ONE. A lambda body is handed its
// display, or its parent's display when it is nested in another lambda, and a display's own fields are
// captured locals the body already resolves as bindings. So the walk follows `ClosureEnclosingDef` out
// to the type the source was written in, so a lambda in a member body reaches the same provisional
// binding and ambiguity check as its enclosing member. A display with no enclosing receiver — a
// lambda written in a FREE function — has no type around it and can only see free functions.
class ColumnarProvisionalMemberBinding {
    static func HasEnclosingMember(enclosingType: ColumnarStructDef?, name: string): bool {
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
