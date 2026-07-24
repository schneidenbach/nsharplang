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
        // N+1c tranche 5 (richer TypeReference forms): the full stage-15 type-node family. Each derived node
        // registers its stored data members + the base TypeReference `Span` (a SourceSpan, compared by value —
        // SourceSpan is unregistered, so DiffValue falls to its .Equals over the 4 ints). Computed `NameSpan`
        // (Simple/Generic) is a pure function of Name/Line/Column/Span and is deliberately not registered.
        // TupleTypeElement is NOT a TypeReference (no Span) — its Type recurses, Name is a scalar (string?).
        if typeName == "GenericTypeReference" {
            return Names("Name TypeArguments Line Column Span")
        }
        if typeName == "ArrayTypeReference" {
            return Names("ElementType Span")
        }
        if typeName == "NullableTypeReference" {
            return Names("InnerType Span")
        }
        if typeName == "TupleTypeReference" {
            return Names("Elements Span")
        }
        if typeName == "TupleTypeElement" {
            return Names("Type Name")
        }
        if typeName == "FunctionTypeReference" {
            return Names("ParameterTypes ReturnType Span")
        }
        if typeName == "UnionTypeReference" {
            return Names("Arms Span")
        }
        if typeName == "ByRefTypeReference" {
            return Names("InnerType Span")
        }
        // N+1c tranche 4 (modifiers + primary-ctor params): the Parameter node (compared element-by-element
        // inside a declaration's PrimaryConstructorParameters list) and the AttributeNode (compared inside a
        // declaration's Attributes list). Parameter.Type recurses into its SimpleTypeReference; Modifier /
        // IsThis / IsScoped / DefaultValue / Attributes / Lifetime are compared as scalars (null/enum/bool).
        // AttributeNode.Arguments is an empty Argument list for the argument-free materialized shape.
        if typeName == "Parameter" {
            return Names("Name Type DefaultValue IsThis Modifier Attributes Line Column IsScoped Lifetime")
        }
        if typeName == "AttributeNode" {
            return Names("Name Arguments Line Column")
        }
        // N+1c tranche 6 (type-param lists + base/interface lists + the remaining type bodies): the leaf/body
        // node types. TypeParameter carries ONLY Name (no AstNode base — no Line/Column). UnionDeclaration's
        // Cases + SoaRecordDeclaration's Columns + UnionCase's Properties recurse element-by-element;
        // EnumMember.Value / UnionCaseProperty.Type / *.Type recurse or compare as scalars. The declaration
        // registries (Class/Struct/Record/Interface/Enum) already carry TypeParameters + BaseClass/Interfaces.
        if typeName == "TypeParameter" {
            return Names("Name")
        }
        if typeName == "UnionDeclaration" {
            return Names("Name TypeParameters Cases Modifiers Attributes Line Column")
        }
        if typeName == "UnionCase" {
            return Names("Name Properties Line Column")
        }
        if typeName == "UnionCaseProperty" {
            return Names("Name Type")
        }
        if typeName == "SoaRecordDeclaration" {
            return Names("Name Columns Modifiers Attributes Line Column")
        }
        if typeName == "SoaColumnDeclaration" {
            return Names("Name Type Line Column")
        }
        if typeName == "EnumMember" {
            return Names("Name Value Line Column")
        }
        if typeName == "TypeAliasDeclaration" {
            return Names("Name Type Line Column")
        }
        if typeName == "NewtypeDeclaration" {
            return Names("Name UnderlyingType Line Column")
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

    // N+1c tranche 4 (primary-ctor params): append a byte-exact simple-typed Parameter to a params list,
    // mirroring Parser.cs :811 (`new Parameter(name, type, null, false, ParameterModifier.None, null, line,
    // column, false, null)`). The Type is a single-token SimpleTypeReference whose Span is
    // SpanFromTokens(t,t) ≡ FromStartAndLength(typeLine, typeColumn, typeName.Length) — the same construction
    // as a field type (Parser.cs :1959).
    public static func AddParam(paramList: List<Parameter>, name: string, typeName: string, typeLine: int, typeColumn: int, line: int, column: int) {
        simple := new SimpleTypeReference(typeName, typeLine, typeColumn)
        simple.Span = SourceSpan.FromStartAndLength(typeLine, typeColumn, typeName.Length)
        paramList.Add(new Parameter(name, simple, null, false, ParameterModifier.None, null, line, column, false, null))
    }

    // ---- N+1c tranche 5: richer TypeReference golden builders ----
    // Each builds one node of the stage-15 type-node family with its Span hard-coded from the LIVE Parser.cs
    // oracle (`nlc query ast` / the AstToJson serializer over Parser.cs's tree). A single-line span
    // [startLine, startColumn .. startLine, endColumn] is FromStartAndLength(startLine, startColumn, endColumn -
    // startColumn) (byte-identical to Parser.cs SpanFromTokens/ExtendSpan on one line). Passing the ORACLE's
    // endColumn (not re-deriving it) keeps golden == Parser.cs, so owner == golden proves owner == Parser.cs.
    public static func SpanOf(startLine: int, startColumn: int, endColumn: int): SourceSpan {
        return SourceSpan.FromStartAndLength(startLine, startColumn, endColumn - startColumn)
    }

    public static func SimpleT(name: string, line: int, column: int, endColumn: int): TypeReference {
        node := new SimpleTypeReference(name, line, column)
        node.Span = Golden.SpanOf(line, column, endColumn)
        return node
    }

    // A SimpleTypeReference whose Span start differs from its Line/Column — the single-unnamed-tuple unwrap
    // `(int)`, where Parser.cs resets the inner type's Span to the whole parenthesized extent but leaves
    // Line/Column on the inner name token (Parser.cs :1990).
    public static func SimpleTSpan(name: string, line: int, column: int, spanStartColumn: int, spanEndColumn: int): TypeReference {
        node := new SimpleTypeReference(name, line, column)
        node.Span = Golden.SpanOf(line, spanStartColumn, spanEndColumn)
        return node
    }

    public static func GenericT(name: string, args: List<TypeReference>, line: int, column: int, endColumn: int): TypeReference {
        node := new GenericTypeReference(name, args, line, column)
        node.Span = Golden.SpanOf(line, column, endColumn)
        return node
    }

    public static func ArrayT(element: TypeReference, startLine: int, startColumn: int, endColumn: int): TypeReference {
        node := new ArrayTypeReference(element)
        node.Span = Golden.SpanOf(startLine, startColumn, endColumn)
        return node
    }

    public static func NullableT(inner: TypeReference, startLine: int, startColumn: int, endColumn: int): TypeReference {
        node := new NullableTypeReference(inner)
        node.Span = Golden.SpanOf(startLine, startColumn, endColumn)
        return node
    }

    public static func ByRefT(inner: TypeReference, startLine: int, startColumn: int, endColumn: int): TypeReference {
        node := new ByRefTypeReference(inner)
        node.Span = Golden.SpanOf(startLine, startColumn, endColumn)
        return node
    }

    public static func UnionT(arms: List<TypeReference>, startLine: int, startColumn: int, endColumn: int): TypeReference {
        node := new UnionTypeReference(arms)
        node.Span = Golden.SpanOf(startLine, startColumn, endColumn)
        return node
    }

    public static func FuncT(paramTypes: List<TypeReference>, returnType: TypeReference, startLine: int, startColumn: int, endColumn: int): TypeReference {
        node := new FunctionTypeReference(paramTypes, returnType)
        node.Span = Golden.SpanOf(startLine, startColumn, endColumn)
        return node
    }

    public static func TupleElem(typeRef: TypeReference, name: string?): TupleTypeElement {
        return new TupleTypeElement(typeRef, name)
    }

    public static func TupleT(elements: List<TupleTypeElement>, startLine: int, startColumn: int, endColumn: int): TypeReference {
        node := new TupleTypeReference(elements)
        node.Span = Golden.SpanOf(startLine, startColumn, endColumn)
        return node
    }

    // Append a field / parameter carrying a PRE-BUILT rich type reference (the tranche-5 unlock).
    public static func AddFieldT(members: List<Declaration>, name: string, fieldType: TypeReference, line: int, column: int) {
        members.Add(new NSharpLang.Compiler.Ast.FieldDeclaration(name, fieldType, null, Modifiers.None, PropertyModifier.None, new List<AttributeNode>(), line, column))
    }

    public static func AddParamT(paramList: List<Parameter>, name: string, paramType: TypeReference, line: int, column: int) {
        paramList.Add(new Parameter(name, paramType, null, false, ParameterModifier.None, null, line, column, false, null))
    }

    // N+1c tranche 4: a record with a primary-constructor parameter list (empty body, no interfaces/generics,
    // no attributes) — the public-positional-record real-corpus shape. Modifiers is the threaded value.
    public static func AddRecordParams(decls: List<Declaration>, name: string, paramList: List<Parameter>, modifiers: Modifiers, line: int, column: int) {
        decls.Add(new RecordDeclaration(name, null, new List<TypeReference>(), new List<Declaration>(), paramList, false, modifiers, new List<AttributeNode>(), line, column))
    }

    // N+1c tranche 4: a struct with threaded modifiers + attributes, no primary-ctor params (null), empty body.
    public static func AddStructFull(decls: List<Declaration>, name: string, modifiers: Modifiers, attrs: List<AttributeNode>, line: int, column: int) {
        decls.Add(new StructDeclaration(name, null, new List<TypeReference>(), new List<Declaration>(), null, modifiers, attrs, line, column, false))
    }

    // N+1c tranche 4: a class with threaded modifiers + attributes, no primary-ctor params (null), empty body.
    // FQN'd to dodge the tests-enabled `class ClassDeclaration` test-helper collision.
    public static func AddClassFull(decls: List<Declaration>, name: string, modifiers: Modifiers, attrs: List<AttributeNode>, line: int, column: int) {
        decls.Add(new NSharpLang.Compiler.Ast.ClassDeclaration(name, null, null, new List<TypeReference>(), new List<Declaration>(), null, modifiers, attrs, line, column))
    }

    // N+1c tranche 4: append an argument-free AttributeNode (Parser.cs :292 — empty Argument list; line = the
    // `[` line, column = the `[` column + 1).
    public static func AddAttr(attrs: List<AttributeNode>, name: string, line: int, column: int) {
        attrs.Add(new AttributeNode(name, new List<Argument>(), line, column))
    }

    // N+1c tranche 4: build the exact multi-flag Modifiers value (e.g. public sealed = Public | Sealed = 129)
    // via the int-bitmask + `(Modifiers)value` idiom, matching what the owner's ParseModifiers produces.
    public static func Mods2(a: Modifiers, b: Modifiers): Modifiers {
        value := System.Convert.ToInt32(a) | System.Convert.ToInt32(b)
        return (Modifiers)value
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

    // ---- N+1c tranche 6: type-parameter lists + base/interface lists + the remaining type bodies ----
    // All golden positions/spans below are transcribed from the LIVE Parser.cs oracle (the AstToJson
    // serializer over Parser.cs's parse tree); owner == golden proves owner == Parser.cs.

    // A TypeParameter carries ONLY its Name (Parser.cs :755).
    public static func AddTP(tps: List<TypeParameter>, name: string) {
        tps.Add(new TypeParameter(name))
    }

    // ---- base/interface lists (no generics) ----
    // A class's `: T, U` splits [0]→BaseClass, [1..]→Interfaces (Parser.cs :977-978).
    public static func AddClassBase(decls: List<Declaration>, name: string, baseClass: TypeReference?, interfaces: List<TypeReference>, line: int, column: int) {
        decls.Add(new NSharpLang.Compiler.Ast.ClassDeclaration(name, null, baseClass, interfaces, new List<Declaration>(), null, Modifiers.None, new List<AttributeNode>(), line, column))
    }

    // A struct's `: T, U` is a pure interface list (Parser.cs :1008-1015).
    public static func AddStructIface(decls: List<Declaration>, name: string, interfaces: List<TypeReference>, line: int, column: int) {
        decls.Add(new StructDeclaration(name, null, interfaces, new List<Declaration>(), null, Modifiers.None, new List<AttributeNode>(), line, column, false))
    }

    // An interface's `: T, U` is its BaseInterfaces list (Parser.cs :1160-1168).
    public static func AddInterfaceBase(decls: List<Declaration>, name: string, baseInterfaces: List<TypeReference>, line: int, column: int) {
        decls.Add(new InterfaceDeclaration(name, null, baseInterfaces, new List<Declaration>(), Modifiers.None, false, new List<AttributeNode>(), line, column))
    }

    // ---- type-parameter lists on declarations ----
    public static func AddClassGP(decls: List<Declaration>, name: string, typeParams: List<TypeParameter>, line: int, column: int) {
        decls.Add(new NSharpLang.Compiler.Ast.ClassDeclaration(name, typeParams, null, new List<TypeReference>(), new List<Declaration>(), null, Modifiers.None, new List<AttributeNode>(), line, column))
    }

    public static func AddStructGP(decls: List<Declaration>, name: string, typeParams: List<TypeParameter>, line: int, column: int) {
        decls.Add(new StructDeclaration(name, typeParams, new List<TypeReference>(), new List<Declaration>(), null, Modifiers.None, new List<AttributeNode>(), line, column, false))
    }

    // A record with generics + an interface list + positional params (Parser.cs :1066). interfaces empty when absent.
    public static func AddRecordGP(decls: List<Declaration>, name: string, typeParams: List<TypeParameter>, interfaces: List<TypeReference>, paramList: List<Parameter>, mods: Modifiers, line: int, column: int) {
        decls.Add(new RecordDeclaration(name, typeParams, interfaces, new List<Declaration>(), paramList, false, mods, new List<AttributeNode>(), line, column))
    }

    // A class with generics + base/interface split + modifiers (Parser.cs :984). FQN'd (test-stub collision).
    public static func AddClassGPBase(decls: List<Declaration>, name: string, typeParams: List<TypeParameter>, baseClass: TypeReference?, interfaces: List<TypeReference>, mods: Modifiers, line: int, column: int) {
        decls.Add(new NSharpLang.Compiler.Ast.ClassDeclaration(name, typeParams, baseClass, interfaces, new List<Declaration>(), null, mods, new List<AttributeNode>(), line, column))
    }

    // ---- union bodies ----
    public static func AddUnion(decls: List<Declaration>, name: string, cases: List<UnionCase>, line: int, column: int) {
        decls.Add(new UnionDeclaration(name, null, cases, Modifiers.None, new List<AttributeNode>(), line, column))
    }

    // A bare union case (no payload) — Properties null (Parser.cs :1223).
    public static func AddUCaseBare(cases: List<UnionCase>, name: string, line: int, column: int) {
        cases.Add(new UnionCase(name, null, line, column))
    }

    // A union case with a `{ prop: Type, … }` payload (Parser.cs :1223).
    public static func AddUCaseProps(cases: List<UnionCase>, name: string, props: List<UnionCaseProperty>, line: int, column: int) {
        cases.Add(new UnionCase(name, props, line, column))
    }

    public static func AddUProp(props: List<UnionCaseProperty>, name: string, typeRef: TypeReference) {
        props.Add(new UnionCaseProperty(name, typeRef))
    }

    // ---- enum members ----
    public static func AddEnumM(decls: List<Declaration>, name: string, members: List<EnumMember>, enumType: EnumType, mods: Modifiers, line: int, column: int) {
        decls.Add(new EnumDeclaration(name, members, enumType, mods, new List<AttributeNode>(), line, column))
    }

    // A valueless enum member — Value null (Parser.cs :1310).
    public static func AddEMem(members: List<EnumMember>, name: string, line: int, column: int) {
        members.Add(new EnumMember(name, null, line, column))
    }

    // ---- soa record bodies ----
    public static func AddSoa(decls: List<Declaration>, name: string, columns: List<SoaColumnDeclaration>, line: int, column: int) {
        decls.Add(new SoaRecordDeclaration(name, columns, Modifiers.None, new List<AttributeNode>(), line, column))
    }

    public static func AddSCol(columns: List<SoaColumnDeclaration>, name: string, typeRef: TypeReference, line: int, column: int) {
        columns.Add(new SoaColumnDeclaration(name, typeRef, line, column))
    }

    // ---- type-alias underlying type ----
    // FQN'd: a test-helper `class TypeAliasDeclaration` in NSharpLang.Compiler.TestStubs shares the simple name.
    public static func AddTypeAlias(decls: List<Declaration>, name: string, typeRef: TypeReference, line: int, column: int) {
        decls.Add(new NSharpLang.Compiler.Ast.TypeAliasDeclaration(name, typeRef, line, column))
    }

    public static func AddNewtype(decls: List<Declaration>, name: string, underlyingType: TypeReference, line: int, column: int) {
        decls.Add(new NewtypeDeclaration(name, underlyingType, line, column))
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

// ============================================================================
// tranche 4: MODIFIERS + PRIMARY-CONSTRUCTOR PARAMETERS + argument-free ATTRIBUTES.
// All golden positions/modifiers below are triangulated against the LIVE Parser.cs via `nlc query ast` on
// the identical source (owner == golden by these contracts; golden == Parser.cs by the query-ast oracle).
// ============================================================================

// ---- MODIFIERS ----

test "016 N+1c tranche 4: a public struct carries Modifiers.Public (Parser.cs :298/:1010)" {
    actual := RunAst("namespace N\n\npublic struct S {}\n")
    decls := new List<Declaration>()
    Golden.AddStructFull(decls, "S", Modifiers.Public, new List<AttributeNode>(), 3, 8)
    expected := Golden.Unit(Golden.Ns("N", 1, 1), NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 4: `public sealed class` accumulates the flag bitmask Public|Sealed (Parser.cs :298)" {
    actual := RunAst("namespace N\n\npublic sealed class C {}\n")
    decls := new List<Declaration>()
    Golden.AddClassFull(decls, "C", Golden.Mods2(Modifiers.Public, Modifiers.Sealed), new List<AttributeNode>(), 3, 15)
    expected := Golden.Unit(Golden.Ns("N", 1, 1), NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- ARGUMENT-FREE ATTRIBUTES ----

test "016 N+1c tranche 4: `[Foo] struct S` materializes an argument-free AttributeNode (Parser.cs :292)" {
    actual := RunAst("namespace N\n\n[Foo] struct S {}\n")
    attrs := new List<AttributeNode>()
    Golden.AddAttr(attrs, "Foo", 3, 2)
    decls := new List<Declaration>()
    Golden.AddStructFull(decls, "S", Modifiers.None, attrs, 3, 7)
    expected := Golden.Unit(Golden.Ns("N", 1, 1), NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- PRIMARY-CONSTRUCTOR PARAMETERS ----

test "016 N+1c tranche 4: a record materializes its positional parameters (Parser.cs :811/:1039/:1055)" {
    actual := RunAst("namespace N\n\nrecord R(a: int, b: string) {}\n")
    paramList := new List<Parameter>()
    Golden.AddParam(paramList, "a", "int", 3, 13, 3, 10)
    Golden.AddParam(paramList, "b", "string", 3, 21, 3, 18)
    decls := new List<Declaration>()
    Golden.AddRecordParams(decls, "R", paramList, Modifiers.None, 3, 1)
    expected := Golden.Unit(Golden.Ns("N", 1, 1), NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- WHOLE-FILE REAL-CORPUS EQUALITY (THE MILESTONE) ----
// The source strings below are the EXACT byte content of the in-repo real-corpus files.

test "016 N+1c tranche 4: WHOLE-FILE equality on PlaygroundWasmModels.nl (public positional record)" {
    actual := RunAst("namespace NSharpLang.Playground.Wasm\n\npublic record PlaygroundVersionResponse(\n    SchemaVersion: int,\n    Compiler: string,\n    WasmHost: string) {\n}\n")
    paramList := new List<Parameter>()
    Golden.AddParam(paramList, "SchemaVersion", "int", 4, 20, 4, 5)
    Golden.AddParam(paramList, "Compiler", "string", 5, 15, 5, 5)
    Golden.AddParam(paramList, "WasmHost", "string", 6, 15, 6, 5)
    decls := new List<Declaration>()
    Golden.AddRecordParams(decls, "PlaygroundVersionResponse", paramList, Modifiers.Public, 3, 8)
    expected := Golden.Unit(Golden.Ns("NSharpLang.Playground.Wasm", 1, 1), NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 4: WHOLE-FILE equality on SystemsAotReport.nl (string/bool positional record)" {
    actual := RunAst("namespace NSharpLang.Compiler.Performance\n\npublic record SystemsAotReport(\n    Target: string,\n    Analysis: string,\n    NativeImageEmitted: bool,\n    TrimSafe: bool) {\n}\n")
    paramList := new List<Parameter>()
    Golden.AddParam(paramList, "Target", "string", 4, 13, 4, 5)
    Golden.AddParam(paramList, "Analysis", "string", 5, 15, 5, 5)
    Golden.AddParam(paramList, "NativeImageEmitted", "bool", 6, 25, 6, 5)
    Golden.AddParam(paramList, "TrimSafe", "bool", 7, 15, 7, 5)
    decls := new List<Declaration>()
    Golden.AddRecordParams(decls, "SystemsAotReport", paramList, Modifiers.Public, 3, 8)
    expected := Golden.Unit(Golden.Ns("NSharpLang.Compiler.Performance", 1, 1), NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 4: WHOLE-FILE equality on SystemsReportSummary.nl (7-field int positional record)" {
    actual := RunAst("namespace NSharpLang.Compiler.Performance\n\npublic record SystemsReportSummary(\n    Functions: int,\n    HotFunctions: int,\n    BoundaryFunctions: int,\n    Findings: int,\n    Errors: int,\n    Warnings: int,\n    TrustedSites: int) {\n}\n")
    paramList := new List<Parameter>()
    Golden.AddParam(paramList, "Functions", "int", 4, 16, 4, 5)
    Golden.AddParam(paramList, "HotFunctions", "int", 5, 19, 5, 5)
    Golden.AddParam(paramList, "BoundaryFunctions", "int", 6, 24, 6, 5)
    Golden.AddParam(paramList, "Findings", "int", 7, 15, 7, 5)
    Golden.AddParam(paramList, "Errors", "int", 8, 13, 8, 5)
    Golden.AddParam(paramList, "Warnings", "int", 9, 15, 9, 5)
    Golden.AddParam(paramList, "TrustedSites", "int", 10, 19, 10, 5)
    decls := new List<Declaration>()
    Golden.AddRecordParams(decls, "SystemsReportSummary", paramList, Modifiers.Public, 3, 8)
    expected := Golden.Unit(Golden.Ns("NSharpLang.Compiler.Performance", 1, 1), NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ============================================================================
// tranche 5: the RICHER TypeReference node family (Generic / qualified-dotted Simple / Array / Nullable /
// Tuple / Func / Union / ByRef). Every golden Span below is transcribed from the LIVE Parser.cs oracle
// (the AstToJson serializer over Parser.cs's parse tree — `nlc query ast`); owner == golden proves owner ==
// Parser.cs. Each field/parameter type that was DEFERRED-and-declined in tranche 4 now materializes.
// ============================================================================

test "016 N+1c tranche 5: a generic field type materializes GenericTypeReference<SimpleTypeReference> (Parser.cs :1951)" {
    actual := RunAst("struct S {\n    tags: List<int>\n}")
    args := new List<TypeReference>()
    args.Add(Golden.SimpleT("int", 2, 16, 19))
    members := new List<Declaration>()
    Golden.AddFieldT(members, "tags", Golden.GenericT("List", args, 2, 11, 20), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 5: a qualified dotted field type materializes a dot-joined SimpleTypeReference (Parser.cs :1918/:1959)" {
    actual := RunAst("struct S {\n    id: A.B.C\n}")
    members := new List<Declaration>()
    Golden.AddFieldT(members, "id", Golden.SimpleT("A.B.C", 2, 9, 14), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 5: a nullable field type materializes NullableTypeReference (Parser.cs :1857)" {
    actual := RunAst("struct S {\n    name: string?\n}")
    inner := Golden.SimpleT("string", 2, 11, 17)
    members := new List<Declaration>()
    Golden.AddFieldT(members, "name", Golden.NullableT(inner, 2, 11, 18), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 5: an array field type materializes ArrayTypeReference (Parser.cs :1825)" {
    actual := RunAst("struct S {\n    xs: int[]\n}")
    inner := Golden.SimpleT("int", 2, 9, 12)
    members := new List<Declaration>()
    Golden.AddFieldT(members, "xs", Golden.ArrayT(inner, 2, 9, 14), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 5: a nested generic materializes GenericTypeReference nesting with split-`>>` spans (Parser.cs :2107)" {
    actual := RunAst("struct S {\n    m: List<List<int>>\n}")
    innerArgs := new List<TypeReference>()
    innerArgs.Add(Golden.SimpleT("int", 2, 18, 21))
    outerArgs := new List<TypeReference>()
    outerArgs.Add(Golden.GenericT("List", innerArgs, 2, 13, 22))
    members := new List<Declaration>()
    Golden.AddFieldT(members, "m", Golden.GenericT("List", outerArgs, 2, 8, 23), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 5: a named tuple field type materializes TupleTypeReference with named elements (Parser.cs :1994)" {
    actual := RunAst("struct S {\n    p: (x: int, y: int)\n}")
    elements := new List<TupleTypeElement>()
    elements.Add(Golden.TupleElem(Golden.SimpleT("int", 2, 12, 15), "x"))
    elements.Add(Golden.TupleElem(Golden.SimpleT("int", 2, 20, 23), "y"))
    members := new List<Declaration>()
    Golden.AddFieldT(members, "p", Golden.TupleT(elements, 2, 8, 24), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 5: a single unnamed tuple element UNWRAPS to the inner type with the paren-extent span (Parser.cs :1988-1992)" {
    actual := RunAst("struct S {\n    p: (int)\n}")
    members := new List<Declaration>()
    Golden.AddFieldT(members, "p", Golden.SimpleTSpan("int", 2, 9, 8, 13), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 5: a union field type materializes UnionTypeReference (Parser.cs :1808)" {
    actual := RunAst("struct S {\n    u: int | string\n}")
    arms := new List<TypeReference>()
    arms.Add(Golden.SimpleT("int", 2, 8, 11))
    arms.Add(Golden.SimpleT("string", 2, 14, 20))
    members := new List<Declaration>()
    Golden.AddFieldT(members, "u", Golden.UnionT(arms, 2, 8, 20), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 5: a Func field type materializes FunctionTypeReference (last type = return) (Parser.cs :2017)" {
    actual := RunAst("struct S {\n    f: Func<int, string>\n}")
    fnParams := new List<TypeReference>()
    fnParams.Add(Golden.SimpleT("int", 2, 13, 16))
    members := new List<Declaration>()
    Golden.AddFieldT(members, "f", Golden.FuncT(fnParams, Golden.SimpleT("string", 2, 18, 24), 2, 8, 25), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 5: a byref field type materializes ByRefTypeReference (Parser.cs :1890)" {
    actual := RunAst("struct S {\n    r: &int\n}")
    inner := Golden.SimpleT("int", 2, 9, 12)
    members := new List<Declaration>()
    Golden.AddFieldT(members, "r", Golden.ByRefT(inner, 2, 8, 12), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 5: a nullable-array field type nests ArrayTypeReference over NullableTypeReference (Parser.cs :1835/:1847)" {
    actual := RunAst("struct S {\n    q: int?[]\n}")
    inner := Golden.SimpleT("int", 2, 8, 11)
    nullable := Golden.NullableT(inner, 2, 8, 12)
    members := new List<Declaration>()
    Golden.AddFieldT(members, "q", Golden.ArrayT(nullable, 2, 8, 14), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 5: a class with two richer-typed fields (generic + nullable) nests byte-exact" {
    actual := RunAst("class Box {\n    tags: List<int>\n    label: string?\n}")
    genArgs := new List<TypeReference>()
    genArgs.Add(Golden.SimpleT("int", 2, 16, 19))
    members := new List<Declaration>()
    Golden.AddFieldT(members, "tags", Golden.GenericT("List", genArgs, 2, 11, 20), 2, 5)
    Golden.AddFieldT(members, "label", Golden.NullableT(Golden.SimpleT("string", 3, 12, 18), 3, 12, 19), 3, 5)
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "Box", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// A generic PARAMETER type now materializes (the tranche-4 "richer parameter type DECLINES" gate is RELAXED).
test "016 N+1c tranche 5: a generic parameter type now MATERIALIZES the record (was the tranche-4 decline gate)" {
    actual := RunAst("record R(x: List<int>) {}")
    args := new List<TypeReference>()
    args.Add(Golden.SimpleT("int", 1, 18, 21))
    paramList := new List<Parameter>()
    Golden.AddParamT(paramList, "x", Golden.GenericT("List", args, 1, 13, 22), 1, 10)
    decls := new List<Declaration>()
    Golden.AddRecordParams(decls, "R", paramList, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- WHOLE-FILE REAL-CORPUS EQUALITY on richer-typed records (tranche 5 unlock) ----
// EXACT byte content of in-repo pure-data files that carry nullable / generic parameter types — declined by
// tranche 4, now fully materialized. Positions triangulated against LIVE Parser.cs via the AstToJson oracle.

test "016 N+1c tranche 5: WHOLE-FILE equality on CodeIntelligenceParameterResult.nl (nullable param type)" {
    actual := RunAst("namespace NSharpLang.Compiler.CodeIntelligence\n\npublic record ParameterResult(\n    Name: string,\n    Type: string,\n    HasDefault: bool,\n    DefaultValue: string?) {\n}\n")
    paramList := new List<Parameter>()
    Golden.AddParamT(paramList, "Name", Golden.SimpleT("string", 4, 11, 17), 4, 5)
    Golden.AddParamT(paramList, "Type", Golden.SimpleT("string", 5, 11, 17), 5, 5)
    Golden.AddParamT(paramList, "HasDefault", Golden.SimpleT("bool", 6, 17, 21), 6, 5)
    Golden.AddParamT(paramList, "DefaultValue", Golden.NullableT(Golden.SimpleT("string", 7, 19, 25), 7, 19, 26), 7, 5)
    decls := new List<Declaration>()
    Golden.AddRecordParams(decls, "ParameterResult", paramList, Modifiers.Public, 3, 8)
    expected := Golden.Unit(Golden.Ns("NSharpLang.Compiler.CodeIntelligence", 1, 1), NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 5: WHOLE-FILE equality on DocCommandModels.nl (generic param + two records)" {
    actual := RunAst("namespace NSharpLang.Cli.Commands\n\nimport System.Collections.Generic\n\npublic record DocManifest(\n    IndexPath: string,\n    PageCount: int,\n    Pages: IReadOnlyList<DocPage>) {\n}\n\npublic record DocPage(\n    Name: string,\n    Kind: string,\n    Path: string) {\n}\n")
    manifestParams := new List<Parameter>()
    Golden.AddParamT(manifestParams, "IndexPath", Golden.SimpleT("string", 6, 16, 22), 6, 5)
    Golden.AddParamT(manifestParams, "PageCount", Golden.SimpleT("int", 7, 16, 19), 7, 5)
    pagesArgs := new List<TypeReference>()
    pagesArgs.Add(Golden.SimpleT("DocPage", 8, 26, 33))
    Golden.AddParamT(manifestParams, "Pages", Golden.GenericT("IReadOnlyList", pagesArgs, 8, 12, 34), 8, 5)
    pageParams := new List<Parameter>()
    Golden.AddParamT(pageParams, "Name", Golden.SimpleT("string", 12, 11, 17), 12, 5)
    Golden.AddParamT(pageParams, "Kind", Golden.SimpleT("string", 13, 11, 17), 13, 5)
    Golden.AddParamT(pageParams, "Path", Golden.SimpleT("string", 14, 11, 17), 14, 5)
    imports := new List<ImportDirective>()
    Golden.AddImport(imports, "System.Collections.Generic", null, 3, 1)
    decls := new List<Declaration>()
    Golden.AddRecordParams(decls, "DocManifest", manifestParams, Modifiers.Public, 5, 8)
    Golden.AddRecordParams(decls, "DocPage", pageParams, Modifiers.Public, 11, 8)
    expected := Golden.Unit(Golden.Ns("NSharpLang.Cli.Commands", 1, 1), imports, NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 5: WHOLE-FILE equality on CodeIntelligenceImplementorModels.nl (nullable + generic params)" {
    actual := RunAst("namespace NSharpLang.Compiler.CodeIntelligence\n\nimport System.Collections.Generic\n\npublic record ImplementorResult(\n    TypeName: string,\n    Kind: string,\n    File: string?,\n    Line: int,\n    Column: int) {\n}\n\npublic record ImplementorsResult(\n    Interface: string,\n    Results: List<ImplementorResult>) {\n}\n")
    resultParams := new List<Parameter>()
    Golden.AddParamT(resultParams, "TypeName", Golden.SimpleT("string", 6, 15, 21), 6, 5)
    Golden.AddParamT(resultParams, "Kind", Golden.SimpleT("string", 7, 11, 17), 7, 5)
    Golden.AddParamT(resultParams, "File", Golden.NullableT(Golden.SimpleT("string", 8, 11, 17), 8, 11, 18), 8, 5)
    Golden.AddParamT(resultParams, "Line", Golden.SimpleT("int", 9, 11, 14), 9, 5)
    Golden.AddParamT(resultParams, "Column", Golden.SimpleT("int", 10, 13, 16), 10, 5)
    resultsArgs := new List<TypeReference>()
    resultsArgs.Add(Golden.SimpleT("ImplementorResult", 15, 19, 36))
    implsParams := new List<Parameter>()
    Golden.AddParamT(implsParams, "Interface", Golden.SimpleT("string", 14, 16, 22), 14, 5)
    Golden.AddParamT(implsParams, "Results", Golden.GenericT("List", resultsArgs, 15, 14, 37), 15, 5)
    imports := new List<ImportDirective>()
    Golden.AddImport(imports, "System.Collections.Generic", null, 3, 1)
    decls := new List<Declaration>()
    Golden.AddRecordParams(decls, "ImplementorResult", resultParams, Modifiers.Public, 5, 8)
    Golden.AddRecordParams(decls, "ImplementorsResult", implsParams, Modifiers.Public, 13, 8)
    expected := Golden.Unit(Golden.Ns("NSharpLang.Compiler.CodeIntelligence", 1, 1), imports, NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- NO-STUB DECLINE GATES (the owner declines rather than partially comparing) ----
// These prove the RETAINED materialization gates: a declaration carrying a STILL-DEFERRED feature (a
// parameter default value, a generic type-parameter list ON the declaration, or an argument-bearing
// attribute) is NOT materialized, so the owner's Declarations stays empty rather than emitting a
// partial/wrong node. (Parser.cs DOES materialize these; the empty result is the owner's intentional no-stub
// deferral, not a Parser.cs-parity claim.) The tranche-4 "richer parameter TYPE declines" gate is now RELAXED
// (see the tranche-5 positive contract above) — richer field/parameter types materialize.

test "016 N+1c tranche 4: a parameter with a default value DECLINES record materialization (no-stub)" {
    actual := RunAst("record R(x: int = 5) {}\n")
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, NoDecls(), 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// tranche 6 CONVERTED the tranche-4 "generic type-parameter list DECLINES" gate to a positive
// materialization: a generic declaration now materializes its TypeParameter list (Parser.cs :1033/:755).
test "016 N+1c tranche 6: a generic type-parameter list now MATERIALIZES the record (was the tranche-4 decline gate)" {
    actual := RunAst("record R<T>(x: int) {}\n")
    tps := new List<TypeParameter>()
    Golden.AddTP(tps, "T")
    paramList := new List<Parameter>()
    Golden.AddParamT(paramList, "x", Golden.SimpleT("int", 1, 16, 19), 1, 13)
    decls := new List<Declaration>()
    Golden.AddRecordGP(decls, "R", tps, new List<TypeReference>(), paramList, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 4: an argument-bearing attribute DECLINES declaration materialization (no-stub)" {
    actual := RunAst("[Attr(1)] struct S {}\n")
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, NoDecls(), 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- NEGATIVE SELF-CHECKS (guard the new comparison paths against a vacuous pass) ----

test "016 N+1c tranche 4: AstEq.Diff catches a mismatched Modifiers value rather than passing vacuously" {
    actual := RunAst("namespace N\n\npublic struct S {}\n")
    decls := new List<Declaration>()
    Golden.AddStructFull(decls, "S", Modifiers.None, new List<AttributeNode>(), 3, 8)
    expected := Golden.Unit(Golden.Ns("N", 1, 1), NoImports(), NoFileImports(), null, decls, 1, 1)
    diff := AstEq.Diff(expected, actual, "unit")
    assert diff != ""
    assert diff == "unit.Declarations[0].Modifiers: Modifiers(None) != Modifiers(Public)"
}

test "016 N+1c tranche 4: AstEq.Diff catches a mismatched parameter type rather than passing vacuously" {
    actual := RunAst("namespace N\n\nrecord R(a: int) {}\n")
    paramList := new List<Parameter>()
    Golden.AddParam(paramList, "a", "long", 3, 13, 3, 10)
    decls := new List<Declaration>()
    Golden.AddRecordParams(decls, "R", paramList, Modifiers.None, 3, 1)
    expected := Golden.Unit(Golden.Ns("N", 1, 1), NoImports(), NoFileImports(), null, decls, 1, 1)
    diff := AstEq.Diff(expected, actual, "unit")
    assert diff != ""
    assert diff == "unit.Declarations[0].PrimaryConstructorParameters[0].Type.Name: String(long) != String(int)"
}

// tranche 5: guard the GenericTypeReference.TypeArguments recursion — a wrong type-argument name is caught.
test "016 N+1c tranche 5: AstEq.Diff catches a mismatched generic type argument rather than passing vacuously" {
    actual := RunAst("struct S {\n    tags: List<int>\n}")
    args := new List<TypeReference>()
    args.Add(Golden.SimpleT("long", 2, 16, 19))
    members := new List<Declaration>()
    Golden.AddFieldT(members, "tags", Golden.GenericT("List", args, 2, 11, 20), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    diff := AstEq.Diff(expected, actual, "unit")
    assert diff != ""
    assert diff == "unit.Declarations[0].Members[0].Type.TypeArguments[0].Name: String(long) != String(int)"
}

// tranche 5: guard the wrapper-vs-simple distinction — a NullableTypeReference is not a SimpleTypeReference.
test "016 N+1c tranche 5: AstEq.Diff catches a nullable node compared against a simple node rather than passing vacuously" {
    actual := RunAst("struct S {\n    name: string?\n}")
    members := new List<Declaration>()
    Golden.AddFieldT(members, "name", Golden.SimpleT("string", 2, 11, 18), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    diff := AstEq.Diff(expected, actual, "unit")
    assert diff != ""
    assert diff == "unit.Declarations[0].Members[0].Type: node type SimpleTypeReference != NullableTypeReference"
}

// ============================================================================
// tranche 6: TYPE-PARAMETER LISTS + BASE/INTERFACE LISTS + the remaining TYPE BODIES (union cases, enum
// members, soa columns, type-alias underlying type). Every golden position/span below is transcribed from the
// LIVE Parser.cs oracle (the AstToJson serializer over Parser.cs's parse tree); owner == golden proves owner ==
// Parser.cs (verified whole-tree owner==Parser.cs on all 24 shapes via a throwaway ProjectReference probe).
// The `hasTypeParams` / `hasBaseList` gates are RELAXED; RETAINED: param defaults, per-param/argument-bearing
// attributes, field property-modifiers/initializers/accessors, and everything body-shaped (function/property/
// method/ctor bodies — statement/expression materialization). Value-bearing enum members still decline (Value
// is an Expression).
// ============================================================================

// ---- BASE / INTERFACE LISTS ----

test "016 N+1c tranche 6: a class base type materializes BaseClass with empty Interfaces (Parser.cs :977)" {
    actual := RunAst("class C: Base {}")
    decls := new List<Declaration>()
    Golden.AddClassBase(decls, "C", Golden.SimpleT("Base", 1, 10, 14), new List<TypeReference>(), 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 6: a class base + interface splits BaseClass=first, Interfaces=rest (Parser.cs :977-978)" {
    actual := RunAst("class C: Base, IFoo {}")
    ifaces := new List<TypeReference>()
    ifaces.Add(Golden.SimpleT("IFoo", 1, 16, 20))
    decls := new List<Declaration>()
    Golden.AddClassBase(decls, "C", Golden.SimpleT("Base", 1, 10, 14), ifaces, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 6: a struct interface list materializes as Interfaces with no BaseClass split (Parser.cs :1008)" {
    actual := RunAst("struct S: IFoo {}")
    ifaces := new List<TypeReference>()
    ifaces.Add(Golden.SimpleT("IFoo", 1, 11, 15))
    decls := new List<Declaration>()
    Golden.AddStructIface(decls, "S", ifaces, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 6: an interface base list materializes as BaseInterfaces (Parser.cs :1160)" {
    actual := RunAst("interface I: IBase {}")
    ifaces := new List<TypeReference>()
    ifaces.Add(Golden.SimpleT("IBase", 1, 14, 19))
    decls := new List<Declaration>()
    Golden.AddInterfaceBase(decls, "I", ifaces, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- TYPE-PARAMETER LISTS ----

test "016 N+1c tranche 6: a generic class materializes a TypeParameter list (Parser.cs :755)" {
    actual := RunAst("class C<T> {}")
    tps := new List<TypeParameter>()
    Golden.AddTP(tps, "T")
    decls := new List<Declaration>()
    Golden.AddClassGP(decls, "C", tps, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 6: a two-parameter generic struct materializes both TypeParameters in order (Parser.cs :744-756)" {
    actual := RunAst("struct S<T, U> {}")
    tps := new List<TypeParameter>()
    Golden.AddTP(tps, "T")
    Golden.AddTP(tps, "U")
    decls := new List<Declaration>()
    Golden.AddStructGP(decls, "S", tps, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 6: a generic record materializes TypeParameters + a param typed by T (Parser.cs :1033/:811)" {
    actual := RunAst("record R<T>(x: T) {}")
    tps := new List<TypeParameter>()
    Golden.AddTP(tps, "T")
    paramList := new List<Parameter>()
    Golden.AddParamT(paramList, "x", Golden.SimpleT("T", 1, 16, 17), 1, 13)
    decls := new List<Declaration>()
    Golden.AddRecordGP(decls, "R", tps, new List<TypeReference>(), paramList, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 6: a generic record with an interface list materializes TypeParameters + Interfaces + params (Parser.cs :1033/:1043)" {
    actual := RunAst("record R<T>(x: T): IFoo {}")
    tps := new List<TypeParameter>()
    Golden.AddTP(tps, "T")
    ifaces := new List<TypeReference>()
    ifaces.Add(Golden.SimpleT("IFoo", 1, 20, 24))
    paramList := new List<Parameter>()
    Golden.AddParamT(paramList, "x", Golden.SimpleT("T", 1, 16, 17), 1, 13)
    decls := new List<Declaration>()
    Golden.AddRecordGP(decls, "R", tps, ifaces, paramList, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 6: a public generic class with base + interface materializes all four (Parser.cs :984)" {
    actual := RunAst("public class Box<T>: IFoo, IBar {}")
    tps := new List<TypeParameter>()
    Golden.AddTP(tps, "T")
    ifaces := new List<TypeReference>()
    ifaces.Add(Golden.SimpleT("IBar", 1, 28, 32))
    decls := new List<Declaration>()
    Golden.AddClassGPBase(decls, "Box", tps, Golden.SimpleT("IFoo", 1, 22, 26), ifaces, Modifiers.Public, 1, 8)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- UNION BODIES ----

test "016 N+1c tranche 6: a union materializes bare newline-separated cases (Parser.cs :1223/:1247)" {
    actual := RunAst("union U {\n    A\n    B\n}")
    cases := new List<UnionCase>()
    Golden.AddUCaseBare(cases, "A", 2, 5)
    Golden.AddUCaseBare(cases, "B", 3, 5)
    decls := new List<Declaration>()
    Golden.AddUnion(decls, "U", cases, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 6: a union case with a payload materializes UnionCaseProperty (Parser.cs :1212)" {
    actual := RunAst("union U {\n    A { x: int }\n    B\n}")
    props := new List<UnionCaseProperty>()
    Golden.AddUProp(props, "x", Golden.SimpleT("int", 2, 12, 15))
    cases := new List<UnionCase>()
    Golden.AddUCaseProps(cases, "A", props, 2, 5)
    Golden.AddUCaseBare(cases, "B", 3, 5)
    decls := new List<Declaration>()
    Golden.AddUnion(decls, "U", cases, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 6: a multi-property + mixed-case union materializes byte-exact (Parser.cs :1179-1247)" {
    actual := RunAst("union LookupResult {\n    Found { name: string, score: int }\n    Missing { id: int }\n}")
    foundProps := new List<UnionCaseProperty>()
    Golden.AddUProp(foundProps, "name", Golden.SimpleT("string", 2, 19, 25))
    Golden.AddUProp(foundProps, "score", Golden.SimpleT("int", 2, 34, 37))
    missingProps := new List<UnionCaseProperty>()
    Golden.AddUProp(missingProps, "id", Golden.SimpleT("int", 3, 19, 22))
    cases := new List<UnionCase>()
    Golden.AddUCaseProps(cases, "Found", foundProps, 2, 5)
    Golden.AddUCaseProps(cases, "Missing", missingProps, 3, 5)
    decls := new List<Declaration>()
    Golden.AddUnion(decls, "LookupResult", cases, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- ENUM MEMBERS ----

test "016 N+1c tranche 6: an enum materializes valueless members in order (Parser.cs :1310)" {
    actual := RunAst("enum E {\n    A,\n    B,\n    C\n}")
    members := new List<EnumMember>()
    Golden.AddEMem(members, "A", 2, 5)
    Golden.AddEMem(members, "B", 3, 5)
    Golden.AddEMem(members, "C", 4, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 6: a string-backed enum materializes valueless members with EnumType.String (Parser.cs :1125/:1310)" {
    actual := RunAst("enum Color: string {\n    Red,\n    Green\n}")
    members := new List<EnumMember>()
    Golden.AddEMem(members, "Red", 2, 5)
    Golden.AddEMem(members, "Green", 3, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "Color", members, EnumType.String, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- SOA RECORD BODIES ----

test "016 N+1c tranche 6: a soa record materializes its columns (Parser.cs :1108/:1136)" {
    actual := RunAst("soa record R {\n    x: int\n    y: int\n}")
    columns := new List<SoaColumnDeclaration>()
    Golden.AddSCol(columns, "x", Golden.SimpleT("int", 2, 8, 11), 2, 5)
    Golden.AddSCol(columns, "y", Golden.SimpleT("int", 3, 8, 11), 3, 5)
    decls := new List<Declaration>()
    Golden.AddSoa(decls, "R", columns, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- TYPE-ALIAS UNDERLYING TYPE ----

test "016 N+1c tranche 6: a type alias materializes TypeAliasDeclaration with a simple underlying type (Parser.cs :1361)" {
    actual := RunAst("type T = int")
    decls := new List<Declaration>()
    Golden.AddTypeAlias(decls, "T", Golden.SimpleT("int", 1, 10, 13), 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 6: a type alias to a union underlying type materializes UnionTypeReference (Parser.cs :1808/:1361)" {
    actual := RunAst("type T = int | string")
    arms := new List<TypeReference>()
    arms.Add(Golden.SimpleT("int", 1, 10, 13))
    arms.Add(Golden.SimpleT("string", 1, 16, 22))
    decls := new List<Declaration>()
    Golden.AddTypeAlias(decls, "T", Golden.UnionT(arms, 1, 10, 22), 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 6: a type alias to a generic underlying type materializes GenericTypeReference (Parser.cs :1951/:1361)" {
    actual := RunAst("type T = List<int>")
    args := new List<TypeReference>()
    args.Add(Golden.SimpleT("int", 1, 15, 18))
    decls := new List<Declaration>()
    Golden.AddTypeAlias(decls, "T", Golden.GenericT("List", args, 1, 10, 19), 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 6: a newtype materializes NewtypeDeclaration with its underlying type (Parser.cs :1356)" {
    actual := RunAst("type T = newtype int")
    decls := new List<Declaration>()
    Golden.AddNewtype(decls, "T", Golden.SimpleT("int", 1, 18, 21), 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- WHOLE-FILE REAL-CORPUS EQUALITY (tranche-6 unlock: valueless enums + generic/nullable records) ----
// EXACT byte content of in-repo pure-data files. The enum files are the DIRECT tranche-6 unlock (real
// EnumMember lists); the callgraph file broadens the generic/nullable record coverage. Positions triangulated
// against LIVE Parser.cs via the AstToJson oracle (owner == golden == Parser.cs).

test "016 N+1c tranche 6: WHOLE-FILE equality on ErrorSeverity.nl (public 2-member enum)" {
    actual := RunAst("namespace NSharpLang.Compiler\n\npublic enum ErrorSeverity {\n    Warning,\n    Error\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMem(members, "Warning", 4, 5)
    Golden.AddEMem(members, "Error", 5, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "ErrorSeverity", members, EnumType.Int, Modifiers.Public, 3, 8)
    expected := Golden.Unit(Golden.Ns("NSharpLang.Compiler", 1, 1), NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 6: WHOLE-FILE equality on DiagnosticSeverity.nl (public 3-member enum)" {
    actual := RunAst("namespace NSharpLang.Compiler\n\npublic enum DiagnosticSeverity {\n    Warning,\n    Error,\n    Info\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMem(members, "Warning", 4, 5)
    Golden.AddEMem(members, "Error", 5, 5)
    Golden.AddEMem(members, "Info", 6, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "DiagnosticSeverity", members, EnumType.Int, Modifiers.Public, 3, 8)
    expected := Golden.Unit(Golden.Ns("NSharpLang.Compiler", 1, 1), NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 6: WHOLE-FILE equality on CodeIntelligenceCallGraphModels.nl (two records, generic + nullable params)" {
    actual := RunAst("namespace NSharpLang.Compiler.CodeIntelligence\n\nimport System.Collections.Generic\n\npublic record CallSiteResult(\n    Name: string,\n    File: string?,\n    Line: int,\n    Column: int) {\n}\n\npublic record CallGraphResult(\n    Function: string?,\n    Callers: List<CallSiteResult>,\n    Callees: List<CallSiteResult>,\n    Truncated: bool) {\n}\n")
    siteParams := new List<Parameter>()
    Golden.AddParamT(siteParams, "Name", Golden.SimpleT("string", 6, 11, 17), 6, 5)
    Golden.AddParamT(siteParams, "File", Golden.NullableT(Golden.SimpleT("string", 7, 11, 17), 7, 11, 18), 7, 5)
    Golden.AddParamT(siteParams, "Line", Golden.SimpleT("int", 8, 11, 14), 8, 5)
    Golden.AddParamT(siteParams, "Column", Golden.SimpleT("int", 9, 13, 16), 9, 5)
    callersArgs := new List<TypeReference>()
    callersArgs.Add(Golden.SimpleT("CallSiteResult", 14, 19, 33))
    calleesArgs := new List<TypeReference>()
    calleesArgs.Add(Golden.SimpleT("CallSiteResult", 15, 19, 33))
    graphParams := new List<Parameter>()
    Golden.AddParamT(graphParams, "Function", Golden.NullableT(Golden.SimpleT("string", 13, 15, 21), 13, 15, 22), 13, 5)
    Golden.AddParamT(graphParams, "Callers", Golden.GenericT("List", callersArgs, 14, 14, 34), 14, 5)
    Golden.AddParamT(graphParams, "Callees", Golden.GenericT("List", calleesArgs, 15, 14, 34), 15, 5)
    Golden.AddParamT(graphParams, "Truncated", Golden.SimpleT("bool", 16, 16, 20), 16, 5)
    imports := new List<ImportDirective>()
    Golden.AddImport(imports, "System.Collections.Generic", null, 3, 1)
    decls := new List<Declaration>()
    Golden.AddRecordParams(decls, "CallSiteResult", siteParams, Modifiers.Public, 5, 8)
    Golden.AddRecordParams(decls, "CallGraphResult", graphParams, Modifiers.Public, 12, 8)
    expected := Golden.Unit(Golden.Ns("NSharpLang.Compiler.CodeIntelligence", 1, 1), imports, NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- NEGATIVE SELF-CHECKS (guard the new tranche-6 recursion paths against a vacuous pass) ----

test "016 N+1c tranche 6: AstEq.Diff catches a mismatched type-parameter name rather than passing vacuously" {
    actual := RunAst("class C<T> {}")
    tps := new List<TypeParameter>()
    Golden.AddTP(tps, "U")
    decls := new List<Declaration>()
    Golden.AddClassGP(decls, "C", tps, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    diff := AstEq.Diff(expected, actual, "unit")
    assert diff != ""
    assert diff == "unit.Declarations[0].TypeParameters[0].Name: String(U) != String(T)"
}

test "016 N+1c tranche 6: AstEq.Diff catches a mismatched union case name rather than passing vacuously" {
    actual := RunAst("union U {\n    A\n    B\n}")
    cases := new List<UnionCase>()
    Golden.AddUCaseBare(cases, "A", 2, 5)
    Golden.AddUCaseBare(cases, "WRONG", 3, 5)
    decls := new List<Declaration>()
    Golden.AddUnion(decls, "U", cases, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    diff := AstEq.Diff(expected, actual, "unit")
    assert diff != ""
    assert diff == "unit.Declarations[0].Cases[1].Name: String(WRONG) != String(B)"
}

test "016 N+1c tranche 6: AstEq.Diff catches a mismatched base-class node against an interface list slot" {
    actual := RunAst("class C: Base {}")
    decls := new List<Declaration>()
    Golden.AddClassBase(decls, "C", Golden.SimpleT("WRONG", 1, 10, 14), new List<TypeReference>(), 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    diff := AstEq.Diff(expected, actual, "unit")
    assert diff != ""
    assert diff == "unit.Declarations[0].BaseClass.Name: String(WRONG) != String(Base)"
}

// ---- RETAINED-GATE DECLINES (tranche 6 leaves these body-shaped / expression families deferred) ----
// A value-bearing enum member declines (Value is an Expression, a later tranche); the owner's Declarations
// stays empty rather than emitting a wrong node. (Parser.cs DOES materialize it; the empty result is the
// owner's intentional no-stub deferral.)

test "016 N+1c tranche 6: a value-bearing enum member DECLINES enum materialization (no-stub)" {
    actual := RunAst("enum E {\n    A = 1\n}\n")
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, NoDecls(), 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}
