namespace NSharpLang.Compiler.Columnar

import System
import System.Runtime.Loader


// ONE TYPE NAME, TWO LOADS.
//
// Two `Type` objects can agree on every name a developer can read -- namespace, simple name, and the
// assembly's full identity down to its version and public key -- and still be two types, because the
// same assembly was loaded twice (two files, or one file into two load contexts). The emitter then
// finds no conversion between them, and the decline used to say nothing but "could not be emitted":
// `AssignabilityWithWellKnownTypes(context)` declined in Core's estate on every Linux CI runner with
// `local initializer expression emission declined`, and the reason -- `Compiler.Model`'s
// `MetadataLoadContext` was a second copy of the compiler's -- was only visible to a debugger.
//
// This names the split: which file each side was loaded from and which load context holds it. It is
// EMPTY for every other pair, including two genuinely different types, so it only ever adds a reason
// where the ordinary wording ("does not match") would read as a contradiction.
class ColumnarSplitTypeIdentityFacts {
    static func Describe(actual: Type?, expected: Type?): string {
        if actual == null || expected == null || Object.ReferenceEquals(actual, expected) {
            return ""
        }

        actualName := SafeAssemblyQualifiedName(actual)
        if actualName.Length == 0 || actualName != SafeAssemblyQualifiedName(expected) {
            return ""
        }

        return "'" + SafeFullName(actual) + "' is one type name from two loads of '" + SafeAssemblyIdentity(actual) + "': " + DescribeLoad(actual) + " versus " + DescribeLoad(expected)
    }

    // Where one side came from: the file it was loaded from and the load context that holds it.
    static func DescribeLoad(type: Type): string {
        location := SafeLocation(type)
        if location.Length == 0 {
            location = "<no file>"
        }

        contextName := SafeLoadContextName(type)
        if contextName.Length == 0 {
            contextName = "<no load context>"
        }

        return "'" + location + "' in load context '" + contextName + "'"
    }

    static func SafeLocation(type: Type): string {
        try {
            assembly := type.Assembly
            if assembly.IsDynamic {
                return ""
            }
            return assembly.Location ?? ""
        } catch {
            // A type whose assembly cannot answer still has a name; say what is known.
            return ""
        }
    }

    static func SafeLoadContextName(type: Type): string {
        try {
            context := AssemblyLoadContext.GetLoadContext(type.Assembly)
            if context == null {
                return ""
            }
            return context.Name ?? ""
        } catch {
            return ""
        }
    }

    static func SafeAssemblyQualifiedName(type: Type): string {
        try {
            return type.AssemblyQualifiedName ?? ""
        } catch {
            // An unbaked builder cannot answer; it is never one side of a split load.
            return ""
        }
    }

    static func SafeFullName(type: Type): string {
        try {
            return type.FullName ?? type.Name
        } catch {
            return type.Name
        }
    }

    static func SafeAssemblyIdentity(type: Type): string {
        try {
            return type.Assembly.FullName ?? ""
        } catch {
            return ""
        }
    }
}
