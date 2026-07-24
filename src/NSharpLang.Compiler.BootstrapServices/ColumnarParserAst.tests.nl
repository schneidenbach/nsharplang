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
// until the N+2 cutover. Tranche 1 covers the CompilationUnit CONTAINER + the preamble + FileImports + the
// empty-body / modifier-free top-level TYPE declarations struct/interface/enum/record. ClassDeclaration is
// deferred (an emitter gap — see the Golden.AddStruct region note). Functions, members, statements,
// expressions, type-references, parameters, type-params, base-types, modifiers, and attributes are later
// tranches, so the corpus stays within the covered shapes.

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
