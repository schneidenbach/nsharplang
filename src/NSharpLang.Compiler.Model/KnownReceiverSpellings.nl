namespace NSharpLang.Compiler.CodeIntelligence

import System


// THE RECEIVER SPELLINGS AN EDITOR CAN REFLECT OVER WITHOUT A PROJECT.
//
// Two lookups from a written name -- in its N# spelling or its CLR one -- to the runtime `Type` a
// completion reflects over: the non-generic receivers, and the generic definitions a receiver is
// most often typed as. Completion, signature help and the editor's type catalog all ask the same
// question, and the catalog sits below the completion engine, so the table lives here rather than
// in either of them.
class KnownReceiverSpellings {

    // The receivers a completion knows how to reflect over by NAME, in both the N# spelling and the
    // CLR one. Anything else is not a reflection receiver.
    //
    // `Console` and `Math` are loaded by METADATA NAME rather than written as `typeof(Console)`,
    // because `typeof` OF A STATIC CLASS DOES NOT EMIT — measured, not assumed, and it is the type
    // being `abstract sealed` that decides, not which assembly it lives in. `System.Math` is in the
    // core library so its name resolves unqualified; `System.Console` is not, so its name carries
    // its assembly. Both answer the same `Type` object `typeof` would have, and the contracts pin
    // that identity against the live `typeof` from the C# side.
    static func KnownReceiverType(name: string): Type? {
        if name == "string" || name == "System.String" {
            return typeof(string)
        }
        if name == "int" || name == "System.Int32" {
            return typeof(int)
        }
        if name == "long" || name == "System.Int64" {
            return typeof(long)
        }
        if name == "bool" || name == "System.Boolean" {
            return typeof(bool)
        }
        if name == "double" || name == "System.Double" {
            return typeof(double)
        }
        if name == "float" || name == "System.Single" {
            return typeof(float)
        }
        if name == "char" || name == "System.Char" {
            return typeof(char)
        }
        if name == "object" || name == "System.Object" {
            return typeof(object)
        }
        if name == "Console" || name == "System.Console" {
            return Type.GetType("System.Console, System.Console")
        }
        if name == "Math" || name == "System.Math" {
            return Type.GetType("System.Math")
        }
        if name == "DateTime" || name == "System.DateTime" {
            return typeof(DateTime)
        }

        return null
    }

    // The generic definitions a completion knows how to close, in both spellings. The four
    // collection interfaces and the two awaitables are here because a receiver is very often typed
    // as one of them rather than as the concrete type.
    //
    // EVERY DEFINITION IS LOADED BY METADATA NAME, and that is one uniform rule rather than fifteen
    // spellings picked one at a time. An OPEN `typeof(List<>)` DOES NOT PARSE and several of the
    // closed forms do not EMIT, so a `typeof`-based table would be a minefield of special cases
    // whose membership only a build can tell you. A metadata name is the same runtime `Type` object
    // in every case — the contracts pin all fifteen against the live `typeof` — and it says out
    // loud which assembly each definition really lives in: everything here is core-library or
    // forwarded to it EXCEPT `Stack`, which is in `System.Collections` and so carries its assembly.
    static func KnownReceiverGenericDefinition(name: string): Type? {
        if name == "List" || name == "System.Collections.Generic.List" {
            return Type.GetType("System.Collections.Generic.List`1")
        }
        if name == "IEnumerable" || name == "System.Collections.Generic.IEnumerable" {
            return Type.GetType("System.Collections.Generic.IEnumerable`1")
        }
        if name == "ICollection" || name == "System.Collections.Generic.ICollection" {
            return Type.GetType("System.Collections.Generic.ICollection`1")
        }
        if name == "IList" || name == "System.Collections.Generic.IList" {
            return Type.GetType("System.Collections.Generic.IList`1")
        }
        if name == "IReadOnlyCollection" || name == "System.Collections.Generic.IReadOnlyCollection" {
            return Type.GetType("System.Collections.Generic.IReadOnlyCollection`1")
        }
        if name == "IReadOnlyList" || name == "System.Collections.Generic.IReadOnlyList" {
            return Type.GetType("System.Collections.Generic.IReadOnlyList`1")
        }
        if name == "Dictionary" || name == "System.Collections.Generic.Dictionary" {
            return Type.GetType("System.Collections.Generic.Dictionary`2")
        }
        if name == "IDictionary" || name == "System.Collections.Generic.IDictionary" {
            return Type.GetType("System.Collections.Generic.IDictionary`2")
        }
        if name == "IReadOnlyDictionary" || name == "System.Collections.Generic.IReadOnlyDictionary" {
            return Type.GetType("System.Collections.Generic.IReadOnlyDictionary`2")
        }
        if name == "HashSet" || name == "System.Collections.Generic.HashSet" {
            return Type.GetType("System.Collections.Generic.HashSet`1")
        }
        if name == "Queue" || name == "System.Collections.Generic.Queue" {
            return Type.GetType("System.Collections.Generic.Queue`1")
        }
        if name == "Stack" || name == "System.Collections.Generic.Stack" {
            return Type.GetType("System.Collections.Generic.Stack`1, System.Collections")
        }
        if name == "Nullable" || name == "System.Nullable" {
            return Type.GetType("System.Nullable`1")
        }
        if name == "Task" || name == "System.Threading.Tasks.Task" {
            return Type.GetType("System.Threading.Tasks.Task`1")
        }
        if name == "ValueTask" || name == "System.Threading.Tasks.ValueTask" {
            return Type.GetType("System.Threading.Tasks.ValueTask`1")
        }

        return null
    }
}
