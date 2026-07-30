namespace NSharpLang.Compiler

import System
import System.Collections.Generic

// The PURE DECISION SURFACE of the analyzer's type-REFERENCE resolver.
//
// `ResolveType(TypeReference)` is a channel walk that reports diagnostics and records into the
// semantic model; the decisions it makes ALONG that walk are not, and this is where they live. Each
// rule here is a total function of its arguments: no analyzer state, no scope stack, no metadata
// probe, no diagnostics, nothing recorded.
//
// Three rules so far, and their exactness matters:
//
//   * BuiltInSimpleType — the sixteen spellings the language resolves before any other channel is
//     consulted. `null`, `never`, `unknown` and the inference/deferred holes are DELIBERATELY absent:
//     they are types the analyzer synthesises, never names a program can write at a type position.
//   * GenericHeadArity — how many type parameters a resolved head takes, or -1 for "unresolved
//     external text, arity cannot be checked here". Zero and -1 are DIFFERENT answers: zero means "I
//     know this head and it is not generic" (which the caller reports), -1 means "I do not know".
//   * VisibleTypeNamespaces — the ordered candidate namespaces for project-wide type discovery: the
//     current one first (as null when the file declares none — the global namespace is a real
//     candidate, not an absence), then each import in IMPORT ORDER, first occurrence winning.
//
// Do not reintroduce any of this in C#, and do not add reporting here.

public class AnalyzerTypeReferenceFacts {

    // The built-in spellings, resolved before the scope stack, file aliases, project types and
    // external metadata are consulted. Null means "not a built-in", not "not a type".
    public static func BuiltInSimpleType(name: string): TypeInfo? {
        if name == "int" { return BuiltInTypes.Int }
        if name == "long" { return BuiltInTypes.Long }
        if name == "float" { return BuiltInTypes.Float }
        if name == "double" { return BuiltInTypes.Double }
        if name == "decimal" { return BuiltInTypes.Decimal }
        if name == "byte" { return BuiltInTypes.Byte }
        if name == "sbyte" { return BuiltInTypes.SByte }
        if name == "short" { return BuiltInTypes.Short }
        if name == "ushort" { return BuiltInTypes.UShort }
        if name == "uint" { return BuiltInTypes.UInt }
        if name == "ulong" { return BuiltInTypes.ULong }
        if name == "char" { return BuiltInTypes.Char }
        if name == "bool" { return BuiltInTypes.Bool }
        if name == "string" { return BuiltInTypes.String }
        if name == "void" { return BuiltInTypes.Void }
        if name == "object" { return BuiltInTypes.Object }
        return null
    }

    // The generic-parameter count for a resolved type head, or -1 when the head is unresolved
    // external text and arity cannot be validated locally.
    public static func GenericHeadArity(resolvedName: TypeInfo): int {
        simple := resolvedName as SimpleTypeInfo
        if simple != null {
            return 0
        }

        classInfo := resolvedName as ClassTypeInfo
        if classInfo != null {
            return classInfo.TypeParameters.Length
        }

        structInfo := resolvedName as StructTypeInfo
        if structInfo != null {
            return structInfo.TypeParameters.Length
        }

        recordInfo := resolvedName as RecordTypeInfo
        if recordInfo != null {
            return recordInfo.TypeParameters.Length
        }

        soaRecordInfo := resolvedName as SoaRecordTypeInfo
        if soaRecordInfo != null {
            return 0
        }

        interfaceInfo := resolvedName as InterfaceTypeInfo
        if interfaceInfo != null {
            return interfaceInfo.TypeParameters.Length
        }

        unionInfo := resolvedName as UnionTypeInfo
        if unionInfo != null {
            unionTypeParameters := unionInfo.Declaration.TypeParameters
            if unionTypeParameters == null {
                return 0
            }
            return unionTypeParameters.Count
        }

        enumInfo := resolvedName as EnumTypeInfo
        if enumInfo != null {
            return 0
        }

        aliasInfo := resolvedName as AliasTypeInfo
        if aliasInfo != null {
            return 0
        }

        newtypeInfo := resolvedName as NewtypeInfo
        if newtypeInfo != null {
            return 0
        }

        reflectionInfo := resolvedName as ReflectionTypeInfo
        if reflectionInfo != null {
            reflectionType := reflectionInfo.Type
            if !reflectionType.get_IsGenericTypeDefinition() {
                return 0
            }
            return reflectionType.GetGenericArguments().Length
        }

        return -1
    }

    // The ordered candidate namespaces for project-wide type and function discovery. A null entry is
    // the GLOBAL namespace and is a genuine candidate: a file with no package/namespace declaration
    // discovers other such files. Imports follow in declaration order, deduplicated against the
    // current namespace and each other.
    public static func VisibleTypeNamespaces(
        currentNamespace: string?,
        usingNamespaces: List<string>): List<string?> {
        seen := new HashSet<string>(StringComparer.Ordinal)
        visible := new List<string?>()

        if currentNamespace == null {
            visible.Add(null)
        } else if seen.Add(currentNamespace) {
            visible.Add(currentNamespace)
        }

        index := 0
        while index < usingNamespaces.Count {
            namespaceName := usingNamespaces[index]
            if seen.Add(namespaceName) {
                visible.Add(namespaceName)
            }
            index = index + 1
        }

        return visible
    }
}
