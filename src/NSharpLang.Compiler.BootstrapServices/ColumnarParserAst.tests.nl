namespace NSharpLang.Compiler.Columnar

import System
import System.Collections
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// Task-016 parser-front-end arc, STAGE N+1c (FULL-TREE AST MATERIALIZATION): parity contracts proving
// the owner's `ColumnarParserRecovery.ParseFileAst` constructs a production `CompilationUnit` node-by-node
// equal to the tree Parser.cs's `ParseCompilationUnit` builds.
//
// AstEq.Diff is a reflection-based RECURSIVE deep-structural comparator: it compares two AST node trees by
// runtime type NAME, every registered stored FIELD (read reflectively), and child ORDER (list index),
// recursing through nested nodes and lists. This is the native "compare via reflection" harness the stage
// calls for. A C# harness that calls Parser.cs live is ratchet-blocked (tests/*.cs has near-zero growth
// headroom; a new .cs trips OWN003), and this upstream assembly cannot reference Parser.cs (Compiler
// depends on BootstrapServices, not the reverse) nor load it (MetadataLoadContext cannot execute), so the
// EXPECTED trees are GOLDEN values inventoried from Parser.cs's construction sites (cited per contract) —
// the identical golden-value methodology the 432 diagnostic contracts use. Because Parser.cs and the owner
// now construct the SAME N# node types (post-N+1b), matching the golden proves byte-exact node parity.
//
// TESTS-ONLY: `ParseFileAst` has no production caller; Parser.cs remains the sole production authority
// until the N+2 cutover. Tranche 1 covered the CompilationUnit CONTAINER + preamble + FileImports + the
// empty-body top-level TYPE declarations struct/interface/enum/record; tranche 2 added ClassDeclaration
// (a mis-diagnosed name collision, not an emitter gap — see the Golden.AddClass region note). Tranche 3
// (here) threads MEMBERS through the type bodies: the FieldDeclaration member for the initializer-free
// `name: <simple type>` corpus (with a byte-exact single-token SimpleTypeReference), a POPULATED Members
// list on class/struct/record/interface, and NESTED-type recursion (a nested type lands in its enclosing
// type's Members). Functions/properties/methods/constructors, statements, expressions, initializers, richer
// type-references, parameters, type-params, base-types, modifiers, and attributes are later tranches, so the
// corpus stays within the covered shapes (plain fields + nested types).

public class AstEq {
    // Recursively compare two AST node instances. Returns "" when structurally equal, else a
    // path + mismatch string that points an assert at the exact divergent field.
    public static func Diff(expected: object?, actual: object?, path: string): string {
        if expected == null && actual == null {
            return ""
        }
        if expected == null {
            return path + ": expected null but got " + Describe(actual)
        }
        if actual == null {
            return path + ": expected " + Describe(expected) + " but got null"
        }
        expectedType := expected.GetType().Name
        actualType := actual.GetType().Name
        if expectedType != actualType {
            return path + ": node type " + expectedType + " != " + actualType
        }
        fields := FieldNames(expectedType)
        if fields == null {
            return path + ": unregistered node type '" + expectedType + "' (extend AstEq.FieldNames)"
        }
        index := 0
        while index < fields.Count {
            fieldName := fields[index]
            childDiff := DiffValue(GetMember(expected, fieldName), GetMember(actual, fieldName), path + "." + fieldName)
            if childDiff != "" {
                return childDiff
            }
            index = index + 1
        }
        return ""
    }

    static func DiffValue(expected: object?, actual: object?, path: string): string {
        if expected == null && actual == null {
            return ""
        }
        if expected == null {
            return path + ": expected null but got " + Describe(actual)
        }
        if actual == null {
            return path + ": expected " + Describe(expected) + " but got null"
        }

        expectedList := expected as IList
        if expectedList != null {
            actualList := actual as IList
            if actualList == null {
                return path + ": expected a list but got " + Describe(actual)
            }
            if expectedList.Count != actualList.Count {
                return path + ": list length " + expectedList.Count.ToString() + " != " + actualList.Count.ToString()
            }
            element := 0
            while element < expectedList.Count {
                elementDiff := DiffValue(expectedList[element], actualList[element], path + "[" + element.ToString() + "]")
                if elementDiff != "" {
                    return elementDiff
                }
                element = element + 1
            }
            return ""
        }

        // A nested AST node (has a registered field list) recurses; everything else is a scalar
        // (string / int / bool / enum) compared by value.
        if FieldNames(expected.GetType().Name) != null {
            return Diff(expected, actual, path)
        }

        if expected.Equals(actual) {
            return ""
        }
        return path + ": " + Describe(expected) + " != " + Describe(actual)
    }

    // AST data members emit as public fields (older records exposed them as properties) — read either.
    static func GetMember(owner: object, name: string): object? {
        property := owner.GetType().GetProperty(name)
        if property != null {
            return property.GetValue(owner)
        }
        field := owner.GetType().GetField(name)
        if field != null {
            return field.GetValue(owner)
        }
        throw new InvalidOperationException("AstEq: '" + owner.GetType().Name + "' has no member '" + name + "'")
    }

    static func Describe(value: object?): string {
        if value == null {
            return "null"
        }
        typeName := value.GetType().Name
        if FieldNames(typeName) != null {
            return typeName
        }
        return typeName + "(" + value.ToString() + ")"
    }

    // Per-node field registry: the exact STORED data members compared for each node type (in construction
    // order + the AstNode base Line/Column). Computed properties (FileImport.DiagnosticColumn/Length) are
    // deliberately excluded — only fields Parser.cs actually sets are compared.
    static func FieldNames(typeName: string): List<string>? {
        if typeName == "CompilationUnit" {
            return Names("Namespace Imports FileImports Package Declarations Line Column")
        }
        if typeName == "NamespaceDeclaration" {
            return Names("Name Line Column")
        }
        if typeName == "PackageDeclaration" {
            return Names("Name Line Column")
        }
        if typeName == "ImportDirective" {
            return Names("Namespace Alias Line Column")
        }
        if typeName == "FileImport" {
            return Names("Path Alias PathColumn PathLength Line Column")
        }
        if typeName == "ClassDeclaration" {
            return Names("Name TypeParameters BaseClass Interfaces Members PrimaryConstructorParameters Modifiers Attributes Line Column")
        }
        if typeName == "StructDeclaration" {
            return Names("Name TypeParameters Interfaces Members PrimaryConstructorParameters Modifiers Attributes IsRefStruct Line Column")
        }
        if typeName == "RecordDeclaration" {
            return Names("Name TypeParameters Interfaces Members PrimaryConstructorParameters IsStruct Modifiers Attributes Line Column")
        }
        if typeName == "InterfaceDeclaration" {
            return Names("Name TypeParameters BaseInterfaces Members Modifiers IsDuckInterface Attributes Line Column")
        }
        if typeName == "EnumDeclaration" {
            return Names("Name Members Type Modifiers Attributes Line Column")
        }
        // N+1c tranche 3 (members): the FIELD member + its type reference. FieldDeclaration's Type recurses
        // into the SimpleTypeReference; PropertyModifier is compared as a scalar (enum). SimpleTypeReference's
        // Span (a SourceSpan) is compared by value — SourceSpan is unregistered, so DiffValue falls to its
        // by-value .Equals (the 4 ints). NameSpan is a computed property and is deliberately not registered.
        if typeName == "FieldDeclaration" {
            return Names("Name Type Initializer Modifiers PropertyModifier Attributes Line Column")
        }
        if typeName == "SimpleTypeReference" {
            return Names("Name Line Column Span")
        }
        return null
    }

    static func Names(spaceSeparated: string): List<string> {
        result := new List<string>()
        parts := spaceSeparated.Split(' ')
        index := 0
        while index < parts.Length {
            if parts[index].Length > 0 {
                result.Add(parts[index])
            }
            index = index + 1
        }
        return result
    }
}

// ---- corpus harness helpers ----

func RunAst(source: string): CompilationUnit {
    return ColumnarParserRecovery.ParseFileAst(source, "a.nl")
}

func NoDecls(): List<Declaration> {
    return new List<Declaration>()
}

func NoImports(): List<ImportDirective> {
    return new List<ImportDirective>()
}

func NoFileImports(): List<Statement> {
    return new List<Statement>()
}

// Golden-tree builders as static methods on a class. Each Add* constructs its node in `.Add(...)`
// argument position and returns void, mirroring the owner's own construction sites, so no user AST node
// is bound to a local/return slot.
public class Golden {
    public static func Unit(ns: NamespaceDeclaration?, imports: List<ImportDirective>, fileImports: List<Statement>, pkg: PackageDeclaration?, decls: List<Declaration>, line: int, column: int): CompilationUnit {
        return new CompilationUnit(ns, imports, fileImports, pkg, decls, line, column)
    }

    // N+1c tranche 2: ClassDeclaration is now materialized. The tranche-1 "constructor-planner gap on the
    // BaseClass param" was a MISDIAGNOSIS: the real cause is a SIMPLE-NAME TYPE COLLISION —
    // `AnalyzerDeclarationContext.tests.nl` defines a local test-helper `class ClassDeclaration` (namespace
    // `NSharpLang.Compiler`) that collides, under the tests-enabled build, with the real
    // `NSharpLang.Compiler.Ast.ClassDeclaration`. This file imports BOTH namespaces, so the simple name
    // resolves ambiguously and the columnar planner declines. Fully qualifying the type resolves it
    // uniquely — byte-exact, no planner change, no wall. (struct/record/interface/enum have no colliding
    // helper, which is why tranche 1 saw only ClassDeclaration decline.)
    public static func AddClass(decls: List<Declaration>, name: string, line: int, column: int) {
        decls.Add(new NSharpLang.Compiler.Ast.ClassDeclaration(name, null, null, new List<TypeReference>(), new List<Declaration>(), null, Modifiers.None, new List<AttributeNode>(), line, column))
    }

    public static func AddStruct(decls: List<Declaration>, name: string, line: int, column: int) {
        decls.Add(new StructDeclaration(name, null, new List<TypeReference>(), new List<Declaration>(), null, Modifiers.None, new List<AttributeNode>(), line, column, false))
    }

    public static func AddInterface(decls: List<Declaration>, name: string, isDuck: bool, line: int, column: int) {
        decls.Add(new InterfaceDeclaration(name, null, new List<TypeReference>(), new List<Declaration>(), Modifiers.None, isDuck, new List<AttributeNode>(), line, column))
    }

    public static func AddEnum(decls: List<Declaration>, name: string, enumType: EnumType, line: int, column: int) {
        decls.Add(new EnumDeclaration(name, new List<EnumMember>(), enumType, Modifiers.None, new List<AttributeNode>(), line, column))
    }

    public static func AddRecord(decls: List<Declaration>, name: string, isStruct: bool, line: int, column: int) {
        decls.Add(new RecordDeclaration(name, null, new List<TypeReference>(), new List<Declaration>(), null, isStruct, Modifiers.None, new List<AttributeNode>(), line, column))
    }

    // N+1c tranche 3 (members): member-bearing type builders. Each hangs a pre-built `members` list on its
    // declaration node (mirroring the owner, where ParseTypeBody returns the parsed member list). The
    // ClassDeclaration/FieldDeclaration names are FULLY QUALIFIED to dodge the tests-enabled simple-name
    // collision with the local test-helper classes in AnalyzerDeclarationContext.tests.nl.
    public static func AddClassM(decls: List<Declaration>, name: string, members: List<Declaration>, line: int, column: int) {
        decls.Add(new NSharpLang.Compiler.Ast.ClassDeclaration(name, null, null, new List<TypeReference>(), members, null, Modifiers.None, new List<AttributeNode>(), line, column))
    }

    public static func AddStructM(decls: List<Declaration>, name: string, members: List<Declaration>, line: int, column: int) {
        decls.Add(new StructDeclaration(name, null, new List<TypeReference>(), members, null, Modifiers.None, new List<AttributeNode>(), line, column, false))
    }

    public static func AddInterfaceM(decls: List<Declaration>, name: string, isDuck: bool, members: List<Declaration>, line: int, column: int) {
        decls.Add(new InterfaceDeclaration(name, null, new List<TypeReference>(), members, Modifiers.None, isDuck, new List<AttributeNode>(), line, column))
    }

    public static func AddRecordM(decls: List<Declaration>, name: string, isStruct: bool, members: List<Declaration>, line: int, column: int) {
        decls.Add(new RecordDeclaration(name, null, new List<TypeReference>(), members, null, isStruct, Modifiers.None, new List<AttributeNode>(), line, column))
    }

    // N+1c tranche 3 (members): append a plain FieldDeclaration `name: <simple type>` to a members list,
    // byte-exact to Parser.cs :1771 — Type is a single-token SimpleTypeReference whose Span is
    // SpanFromTokens(t,t) ≡ FromStartAndLength(typeLine, typeColumn, typeName.Length); Initializer null;
    // Modifiers.None; PropertyModifier.None; no attributes.
    public static func AddFieldTo(members: List<Declaration>, name: string, typeName: string, typeLine: int, typeColumn: int, line: int, column: int) {
        simple := new SimpleTypeReference(typeName, typeLine, typeColumn)
        simple.Span = SourceSpan.FromStartAndLength(typeLine, typeColumn, typeName.Length)
        members.Add(new NSharpLang.Compiler.Ast.FieldDeclaration(name, simple, null, Modifiers.None, PropertyModifier.None, new List<AttributeNode>(), line, column))
    }

    public static func AddImport(imports: List<ImportDirective>, ns: string, alias: string?, line: int, column: int) {
        imports.Add(new ImportDirective(ns, alias, line, column))
    }

    public static func AddFileImport(fileImports: List<Statement>, path: string, alias: string?, pathColumn: int, pathLength: int, line: int, column: int) {
        fileImport := new FileImport(path, alias, line, column)
        fileImport.PathColumn = pathColumn
        fileImport.PathLength = pathLength
        fileImports.Add(fileImport)
    }

    public static func Ns(name: string, line: int, column: int): NamespaceDeclaration {
        return new NamespaceDeclaration(name, line, column)
    }

    public static func Pkg(name: string, line: int, column: int): PackageDeclaration {
        return new PackageDeclaration(name, line, column)
    }
}

// ---- contracts ----

test "016 N+1c: an empty-body struct materializes IsRefStruct=false (Parser.cs :1010)" {
    actual := RunAst("struct S {}")
    decls := new List<Declaration>()
    Golden.AddStruct(decls, "S", 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: an empty-body interface materializes IsDuckInterface=false (Parser.cs :1150-return)" {
    actual := RunAst("interface I {}")
    decls := new List<Declaration>()
    Golden.AddInterface(decls, "I", false, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: a duck interface anchors Line/Column on the 'duck' keyword and sets IsDuckInterface=true (Parser.cs :1130-1136)" {
    actual := RunAst("duck interface I {}")
    decls := new List<Declaration>()
    Golden.AddInterface(decls, "I", true, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: an empty enum defaults to EnumType.Int with no members (Parser.cs :1114/:1189)" {
    actual := RunAst("enum E {}")
    decls := new List<Declaration>()
    Golden.AddEnum(decls, "E", EnumType.Int, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: a string-backed empty enum selects EnumType.String (Parser.cs :1125)" {
    actual := RunAst("enum E: string {}")
    decls := new List<Declaration>()
    Golden.AddEnum(decls, "E", EnumType.String, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: an empty record materializes IsStruct=false (Parser.cs ParseRecordDeclaration)" {
    actual := RunAst("record R {}")
    decls := new List<Declaration>()
    Golden.AddRecord(decls, "R", false, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: a 'record struct' sets IsStruct=true with Line/Column on the record keyword (Parser.cs :1021)" {
    actual := RunAst("record struct R {}")
    decls := new List<Declaration>()
    Golden.AddRecord(decls, "R", true, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: an empty-body class materializes null TypeParameters/BaseClass/PrimaryConstructorParameters (Parser.cs :973)" {
    actual := RunAst("class C {}")
    decls := new List<Declaration>()
    Golden.AddClass(decls, "C", 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: a class alongside a struct preserves declaration order and per-line anchoring (Parser.cs :80-90/:973/:1010)" {
    actual := RunAst("class C {}\nstruct S {}")
    decls := new List<Declaration>()
    Golden.AddClass(decls, "C", 1, 1)
    Golden.AddStruct(decls, "S", 2, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: a file-scoped namespace becomes CompilationUnit.Namespace (Parser.cs :37-40/:127)" {
    actual := RunAst("namespace Foo.Bar")
    expected := Golden.Unit(Golden.Ns("Foo.Bar", 1, 1), NoImports(), NoFileImports(), null, NoDecls(), 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: a package plus namespace-import fills Package + Imports (Parser.cs :64/:71/:136)" {
    actual := RunAst("package Acme\nimport System.Text as Text")
    imports := new List<ImportDirective>()
    Golden.AddImport(imports, "System.Text", "Text", 2, 1)
    expected := Golden.Unit(null, imports, NoFileImports(), Golden.Pkg("Acme", 1, 1), NoDecls(), 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: a file import becomes a FileImport in FileImports with PathColumn/PathLength anchored on the literal (Parser.cs :159-163)" {
    actual := RunAst("import \"lib/util.nl\" as Util")
    fileImports := new List<Statement>()
    Golden.AddFileImport(fileImports, "lib/util.nl", "Util", 8, 13, 1, 1)
    expected := Golden.Unit(null, NoImports(), fileImports, null, NoDecls(), 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: two top-level structs preserve declaration order with per-line anchoring (Parser.cs :80-90)" {
    actual := RunAst("struct A {}\nstruct B {}")
    decls := new List<Declaration>()
    Golden.AddStruct(decls, "A", 1, 1)
    Golden.AddStruct(decls, "B", 2, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: a whole file with namespace + import + file-import + two declarations builds the full container (Parser.cs :111)" {
    actual := RunAst("namespace App\nimport System\nimport \"helpers.nl\"\ninterface Widget {}\nstruct Point {}")
    imports := new List<ImportDirective>()
    Golden.AddImport(imports, "System", null, 2, 1)
    fileImports := new List<Statement>()
    Golden.AddFileImport(fileImports, "helpers.nl", null, 8, 12, 3, 1)
    decls := new List<Declaration>()
    Golden.AddInterface(decls, "Widget", false, 4, 1)
    Golden.AddStruct(decls, "Point", 5, 1)
    expected := Golden.Unit(Golden.Ns("App", 1, 1), imports, fileImports, null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- tranche 3: MEMBERS threaded through type bodies ----
// Golden positions below are triangulated against the LIVE Parser.cs via `nlc query ast` on the identical
// source (owner == golden by these contracts; golden == Parser.cs by the query-ast oracle).

test "016 N+1c: a struct materializes a simple initializer-free field member (Parser.cs :1771/:1959)" {
    actual := RunAst("struct S {\n    x: int\n}")
    members := new List<Declaration>()
    Golden.AddFieldTo(members, "x", "int", 2, 8, 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: a struct materializes multiple fields in declaration order with per-line anchoring" {
    actual := RunAst("struct S {\n    x: int\n    y: int\n}")
    members := new List<Declaration>()
    Golden.AddFieldTo(members, "x", "int", 2, 8, 2, 5)
    Golden.AddFieldTo(members, "y", "int", 3, 8, 3, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: a class field carries a user-named simple type with a byte-exact NameSpan (Parser.cs :1961)" {
    actual := RunAst("class Box {\n    item: Widget\n}")
    members := new List<Declaration>()
    Golden.AddFieldTo(members, "item", "Widget", 2, 11, 2, 5)
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "Box", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: an interface body materializes a field member" {
    actual := RunAst("interface I {\n    id: int\n}")
    members := new List<Declaration>()
    Golden.AddFieldTo(members, "id", "int", 2, 9, 2, 5)
    decls := new List<Declaration>()
    Golden.AddInterfaceM(decls, "I", false, members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: a record body materializes a field member" {
    actual := RunAst("record R {\n    id: int\n}")
    members := new List<Declaration>()
    Golden.AddFieldTo(members, "id", "int", 2, 9, 2, 5)
    decls := new List<Declaration>()
    Golden.AddRecordM(decls, "R", false, members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: a nested empty struct lands in the enclosing class's Members, not the top level" {
    actual := RunAst("class Outer {\n    struct Inner {}\n}")
    outerMembers := new List<Declaration>()
    Golden.AddStruct(outerMembers, "Inner", 2, 5)
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "Outer", outerMembers, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c: a field and a nested field-bearing struct nest byte-exact (Parser.cs :80-90/:973/:1010/:1771)" {
    actual := RunAst("class Outer {\n    tag: int\n    struct Inner {\n        v: int\n    }\n}")
    innerMembers := new List<Declaration>()
    Golden.AddFieldTo(innerMembers, "v", "int", 4, 12, 4, 9)
    outerMembers := new List<Declaration>()
    Golden.AddFieldTo(outerMembers, "tag", "int", 2, 10, 2, 5)
    Golden.AddStructM(outerMembers, "Inner", innerMembers, 3, 5)
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "Outer", outerMembers, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// A negative self-check: the comparator MUST detect a divergence (guards against a vacuous "" pass).
test "016 N+1c: AstEq.Diff reports a mismatched declaration name rather than passing vacuously" {
    actual := RunAst("struct C {}")
    decls := new List<Declaration>()
    Golden.AddStruct(decls, "WRONG", 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    diff := AstEq.Diff(expected, actual, "unit")
    assert diff != ""
    assert diff == "unit.Declarations[0].Name: String(WRONG) != String(C)"
}

// A negative self-check for the NEW field-member comparison path: a wrong field type name must be caught
// (guards the tranche-3 SimpleTypeReference recursion against a vacuous pass).
test "016 N+1c: AstEq.Diff reports a mismatched field type rather than passing vacuously" {
    actual := RunAst("struct S {\n    x: int\n}")
    members := new List<Declaration>()
    Golden.AddFieldTo(members, "x", "long", 2, 8, 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    diff := AstEq.Diff(expected, actual, "unit")
    assert diff != ""
    assert diff == "unit.Declarations[0].Members[0].Type.Name: String(long) != String(int)"
}
