namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections
import System.Collections.Generic
import System.Globalization
import System.Reflection
import System.Text.Json
import NSharpLang.Compiler.Ast


// One parsed file on its way to the `nlc query ast` envelope: the path it was read from and the
// compilation unit that was parsed out of it. This replaces the anonymous C# tuple the CLI used to
// build, so the owner's input is a named type rather than a positional pair.
class AstJsonUnit {
    File: string
    Unit: CompilationUnit

    constructor(filePath: string, unit: CompilationUnit) {
        File = filePath
        Unit = unit
    }
}

// One public instance member of an AST node, lifted out of reflection so fields and properties can be
// merged into a single metadata-token order. `GetFields` reports a derived type's own fields before
// its base type's, and the base type's tokens are lower, so the order the two reflection calls hand
// back is NOT the declaration order the JSON shape is defined in.
class AstJsonMember {
    Token: int
    Name: string
    Value: object?

    constructor(token: int, name: string, value: object?) {
        Token = token
        Name = name
        Value = value
    }
}

// Serializes one or more parsed compilation-unit ASTs to the stable versioned JSON envelope.
//
// Each AST node is emitted as { "node": "<ConcreteNodeType>", <camelCased members> }, recursing into
// child nodes and lists, so the concrete node kind (which a plain polymorphic serialization of the
// Declaration/Statement/Expression bases would drop) is always present. This is the canonical AST
// representation for `nlc query ast` (LLM-first navigation) and for verifying a parser against the
// shape it used to produce. Member order is metadata-token order, which is declaration order with
// base-type members first, and is therefore stable per node type.
class OutputFormatterAstJsonKernels {
    static func CreateAstJsonOptions(): JsonSerializerOptions {
        return new JsonSerializerOptions { WriteIndented: true, MaxDepth: 256 }
    }

    static func AstToJson(units: IReadOnlyList<AstJsonUnit>): string {
        files := new List<object?>()
        index := 0
        while index < units.Count {
            unit := units[index]
            entry := new Dictionary<string, object?>()
            entry["file"] = OutputFormatterNormalizationKernels.NormalizePath(unit.File)
            entry["ast"] = AstValueToJson(unit.Unit)
            files.Add(entry)
            index = index + 1
        }

        envelope := new Dictionary<string, object?>()
        envelope["schemaVersion"] = 1
        envelope["command"] = "query.ast"
        envelope["ok"] = true
        envelope["files"] = files
        return JsonSerializer.Serialize(envelope, CreateAstJsonOptions())
    }

    static func AstValueToJson(value: object?): object? {
        if value == null {
            return null
        }

        text := value as string
        if text != null {
            return text
        }

        valueType := value.GetType()
        if valueType == typeof(bool) {
            return value
        }

        if valueType == typeof(char) {
            return value.ToString()
        }

        if valueType.get_IsEnum() {
            return value.ToString()
        }

        if valueType == typeof(int) || valueType == typeof(long) || valueType == typeof(double) {
            return value
        }

        if valueType.get_IsPrimitive() {
            return Convert.ToString(value, CultureInfo.InvariantCulture)
        }

        list := value as IList
        if list != null {
            items := new List<object?>()
            index := 0
            while index < list.Count {
                items.Add(AstValueToJson(list[index]))
                index = index + 1
            }

            return items
        }

        // An AST node object: N# classes emit data as fields (older records used properties); read
        // both, ordered by metadata token for a stable shape.
        node := new Dictionary<string, object?>()
        node["node"] = valueType.Name
        policy := JsonNamingPolicy.CamelCase
        members := CollectMembers(valueType, value)
        index := 0
        while index < members.Count {
            member := members[index]
            node[policy.ConvertName(member.Name)] = AstValueToJson(member.Value)
            index = index + 1
        }

        return node
    }

    static func CollectMembers(owner: Type, value: object): List<AstJsonMember> {
        flags := BindingFlags.Public | BindingFlags.Instance
        members := new List<AstJsonMember>()
        fields := owner.GetFields(flags)
        for field in fields {
            members.Add(new AstJsonMember(field.get_MetadataToken(), field.get_Name(), field.GetValue(value)))
        }

        properties := owner.GetProperties(flags)
        for property in properties {
            indexParameters := property.GetIndexParameters()
            if indexParameters.Length == 0 && property.get_Name() != "EqualityContract" {
                members.Add(new AstJsonMember(property.get_MetadataToken(), property.get_Name(), property.GetValue(value)))
            }
        }

        SortByToken(members)
        return members
    }

    // Metadata tokens are unique within an assembly, so no two members of one node can tie and the
    // sort's stability is not observable. An insertion sort is used because a node carries a handful
    // of members and the walk visits every node in the tree.
    static func SortByToken(members: List<AstJsonMember>) {
        index := 1
        while index < members.Count {
            current := members[index]
            scan := index - 1
            while scan >= 0 && members[scan].Token > current.Token {
                members[scan + 1] = members[scan]
                scan = scan - 1
            }

            members[scan + 1] = current
            index = index + 1
        }
    }
}
