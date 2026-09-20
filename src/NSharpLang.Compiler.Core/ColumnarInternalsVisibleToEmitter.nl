namespace NSharpLang.Compiler

import System
import System.Collections.Generic
import System.Reflection
import System.Reflection.Emit


// WRITING THE FRIEND DECLARATIONS OF THE ASSEMBLY BEING EMITTED.
//
// `InternalsVisibleToGrants` is the READER of this rule — it answers what a REFERENCE granted this
// compilation. This is the other direction and the other half of the feature: what THIS project
// grants, declared as `internalsVisibleTo:` in `project.yml` and written onto the produced assembly
// as `[assembly: InternalsVisibleTo("Name")]` rows. Without it an N# library could be a friend but
// never make one, so the rule only worked against C#-authored references.
//
// WHAT A GRANT FROM AN N# ASSEMBLY ACTUALLY EXPOSES, measured by reflection on an emitted assembly
// rather than assumed: N# emits every TYPE as CLR `public` (casing does not change a type's CLR
// accessibility) and every FIELD as `public`, but a camelCase — namespace-private — FUNCTION or
// METHOD is emitted as CLR `assembly`, i.e. `internal`. Those unexported functions and methods are
// therefore exactly what a grant admits out of an N# assembly, and nothing else about the assembly
// changes. `website/docs/types.md` states the same rule for readers.
//
// THE BLOB, NOT THE BUILDER. `new CustomAttributeBuilder(...)` throws under NativeAOT, so every
// attribute this back end writes goes through `SetCustomAttribute(ConstructorInfo, byte[])` with
// the blob spelled by `ColumnarAttributeBlobs`; a friend declaration is a one-string attribute and
// uses the shape already pinned there.
class ColumnarInternalsVisibleToEmitter {

    // A declared grant, as it will be written: the developer's spelling with surrounding whitespace
    // removed. The strong-name key an entry may carry after a comma is PRESERVED here — it is part
    // of the display name a consumer's own tooling may compare — while the reader compares only the
    // simple name in front of it (`InternalsVisibleToGrants.FriendSimpleName`).
    static func NormalizeDeclaredName(declared: string?): string {
        if declared == null {
            return ""
        }

        return declared.Trim()
    }

    // A grant with no simple name in front of the comma names no assembly and would emit a row no
    // reader can ever match, so the project file is refused instead of emitting it.
    static func IsUsableDeclaredName(declared: string?): bool {
        normalized := NormalizeDeclaredName(declared)
        if normalized.Length == 0 {
            return false
        }

        return InternalsVisibleToGrants.FriendSimpleName(normalized).Length > 0
    }

    // The declared grants in project order, normalized, with duplicates of the same SIMPLE name
    // dropped. A repeated grant would write a second identical metadata row; the CLR tolerates it
    // and the reader stops at the first match, so the duplicate is noise in the emitted metadata
    // rather than a second permission.
    static func ResolveDeclaredNames(declared: IReadOnlyList<string>?): List<string> {
        resolved := new List<string>()
        if declared == null {
            return resolved
        }

        seen := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        index := 0
        while index < declared.Count {
            normalized := NormalizeDeclaredName(declared[index])
            if normalized.Length > 0 {
                simple := InternalsVisibleToGrants.FriendSimpleName(normalized)
                if simple.Length > 0 && seen.Add(simple) {
                    resolved.Add(normalized)
                }
            }

            index = index + 1
        }

        return resolved
    }

    // `InternalsVisibleToAttribute(string)`. The attribute lives in the core library beside every
    // other compiler-services attribute this back end writes, and the constructor that takes the
    // display name is its only fixed-argument one.
    static func AttributeConstructor(): ConstructorInfo {
        attributeType := typeof(object).get_Assembly().GetType(InternalsVisibleToGrants.InternalsVisibleToAttributeFullName)
        if attributeType == null {
            throw new InvalidOperationException("The InternalsVisibleToAttribute runtime type was not found.")
        }

        parameters := new Type[](1)
        parameters[0] = typeof(string)
        constructor := attributeType.GetConstructor(parameters)
        if constructor == null {
            throw new InvalidOperationException("The InternalsVisibleToAttribute(string) constructor was not found.")
        }

        return constructor
    }

    // Write one row per declared grant onto the assembly under construction. Nothing declared means
    // nothing written — an assembly with no `internalsVisibleTo:` carries no attribute at all, which
    // is what every assembly N# emitted before this existed carried.
    static func Apply(builder: PersistedAssemblyBuilder, declared: IReadOnlyList<string>?) {
        names := ResolveDeclaredNames(declared)
        if names.Count == 0 {
            return
        }

        constructor := AttributeConstructor()
        index := 0
        while index < names.Count {
            builder.SetCustomAttribute(constructor, ColumnarAttributeBlobs.OneString(names[index]))
            index = index + 1
        }
    }
}
