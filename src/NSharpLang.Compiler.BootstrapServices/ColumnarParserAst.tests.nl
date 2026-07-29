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
        // N+1c tranche 7 (BEGIN EXPRESSION MATERIALIZATION): the LEAF/PRIMARY expression tier. Each literal
        // carries its Value scalar (int/float/char/string = string; bool = bool) + the AstNode base Line/Column;
        // null/default/this/base carry only Line/Column; IdentifierExpression carries Name; ParenthesizedExpression
        // recurses into Inner. These land in EnumMember.Value (the tranche-7 value-bearing-member unlock).
        if typeName == "IntLiteralExpression" {
            return Names("Value Line Column")
        }
        if typeName == "FloatLiteralExpression" {
            return Names("Value Line Column")
        }
        if typeName == "CharLiteralExpression" {
            return Names("Value Line Column")
        }
        if typeName == "StringLiteralExpression" {
            return Names("Value Line Column")
        }
        if typeName == "BoolLiteralExpression" {
            return Names("Value Line Column")
        }
        if typeName == "NullLiteralExpression" {
            return Names("Line Column")
        }
        if typeName == "IdentifierExpression" {
            return Names("Name Line Column")
        }
        if typeName == "DefaultExpression" {
            return Names("Line Column")
        }
        if typeName == "ThisExpression" {
            return Names("Line Column")
        }
        if typeName == "BaseExpression" {
            return Names("Line Column")
        }
        if typeName == "ParenthesizedExpression" {
            return Names("Inner Line Column")
        }
        // N+1c tranche 8 (COMPOSED OPERATOR TIERS): the operator-composing nodes. Each recurses into its
        // operand expression fields; Operator is a scalar enum (BinaryOperator / UnaryOperator /
        // AssignmentOperator) compared by value. RangeExpression's Start/End are nullable (open ranges).
        if typeName == "BinaryExpression" {
            return Names("Left Operator Right Line Column")
        }
        if typeName == "UnaryExpression" {
            return Names("Operator Operand Line Column")
        }
        if typeName == "TernaryExpression" {
            return Names("Condition ThenExpression ElseExpression Line Column")
        }
        if typeName == "AssignmentExpression" {
            return Names("Target Operator Value Line Column")
        }
        if typeName == "RangeExpression" {
            return Names("Start End Line Column")
        }
        // N+1c tranche 9a (SINGLE-OPERAND / TYPE-CARRYING postfix + keyword primaries): the postfix member /
        // index-access nodes, is/as, await/must/throw, and the typeof/nameof/sizeof/checked/unchecked/cast/
        // spread keyword primaries. Each recurses into its operand Expression / TypeReference fields (a
        // TypeReference's Span compares by value — SourceSpan is unregistered). MemberName / IsNullConditional /
        // VariableName / Kind are scalars (string / bool / string? / enum). CastExpression is the SHARED node
        // for BOTH `as` (Kind=Safe) and `(T)expr` (Kind=Hard), distinguished by Kind.
        if typeName == "MemberAccessExpression" {
            return Names("Object MemberName IsNullConditional Line Column")
        }
        if typeName == "IndexAccessExpression" {
            return Names("Object Index IsNullConditional Line Column")
        }
        if typeName == "IsExpression" {
            return Names("Expression Type VariableName Line Column")
        }
        if typeName == "CastExpression" {
            return Names("Expression TargetType Kind Line Column")
        }
        if typeName == "AwaitExpression" {
            return Names("Expression Line Column")
        }
        if typeName == "MustExpression" {
            return Names("Expression Line Column")
        }
        if typeName == "ThrowExpression" {
            return Names("Expression Line Column")
        }
        if typeName == "TypeOfExpression" {
            return Names("Type Line Column")
        }
        if typeName == "NameofExpression" {
            return Names("Target Line Column")
        }
        if typeName == "SizeOfExpression" {
            return Names("Type Line Column")
        }
        if typeName == "CheckedExpression" {
            return Names("Expression Line Column")
        }
        if typeName == "UncheckedExpression" {
            return Names("Expression Line Column")
        }
        if typeName == "SpreadExpression" {
            return Names("Expression Line Column")
        }
        // N+1c tranche 9b (ARGUMENT/ELEMENT-LIST forms): the list-bearing expression nodes plus the three
        // non-AstNode list ELEMENTS (Argument / TupleElement / PropertyInitializer carry no Line/Column base —
        // PropertyInitializer stores its own NameLine/NameColumn instead, and its IsIndexerInitializer is a
        // computed property, deliberately unregistered). CallExpression.TypeArguments is null for a
        // non-generic call and a TypeReference list for `M<T>(…)`; IsResultFactory is a stored `bool?` no
        // parser path sets (null on both sides) and is registered so a future divergence would surface.
        if typeName == "CallExpression" {
            return Names("Callee Arguments TypeArguments IsResultFactory Line Column")
        }
        if typeName == "Argument" {
            return Names("Name Value Modifier")
        }
        if typeName == "WithExpression" {
            return Names("Target Properties Line Column")
        }
        if typeName == "PropertyInitializer" {
            return Names("Name IndexExpression Value NameLine NameColumn")
        }
        if typeName == "NewExpression" {
            return Names("Type ConstructorArguments Initializer ArrayLengthExpression Line Column")
        }
        if typeName == "ObjectInitializerExpression" {
            return Names("Properties Line Column")
        }
        if typeName == "TupleExpression" {
            return Names("Elements Line Column")
        }
        if typeName == "TupleElement" {
            return Names("Name Value")
        }
        if typeName == "ArrayLiteralExpression" {
            return Names("Elements IsImmutable Line Column")
        }
        if typeName == "AllocExpression" {
            return Names("Expression Line Column")
        }
        if typeName == "StackAllocExpression" {
            return Names("ElementType LengthExpression Line Column")
        }
        // N+1c tranche 9c (MATCH/PATTERNS + INTERPOLATION + LAMBDA): the last expression families.
        // LambdaExpression's BlockBody is always null here (a block-bodied lambda declines until the
        // statement-body tranche); its Parameters are the implicit `var`-typed Parameter nodes. MatchExpression
        // stores IsExhaustive (a later-phase field, false on both sides). The Pattern family has its OWN
        // Line/Column base (Pattern is not an AstNode but carries the same two fields), and PropertyPattern is a
        // non-Pattern element with Name/Pattern/BindingName/Line/Column. InterpolatedStringPart splits into
        // Text (a literal run) and Hole (an Expression + optional format clause).
        if typeName == "LambdaExpression" {
            return Names("Parameters ExpressionBody BlockBody Line Column")
        }
        if typeName == "MatchExpression" {
            return Names("Value Cases IsExhaustive Line Column")
        }
        if typeName == "MatchCase" {
            return Names("Pattern Guard Expression")
        }
        if typeName == "IdentifierPattern" {
            return Names("Name Line Column")
        }
        if typeName == "LiteralPattern" {
            return Names("Literal Line Column")
        }
        if typeName == "TypePattern" {
            return Names("Type BindingName Line Column")
        }
        if typeName == "UnionCasePattern" {
            return Names("CaseName Properties Line Column")
        }
        if typeName == "PropertyPattern" {
            return Names("Name Pattern BindingName Line Column")
        }
        if typeName == "RelationalPattern" {
            return Names("Operator Value Line Column")
        }
        if typeName == "AndPattern" {
            return Names("Left Right Line Column")
        }
        if typeName == "OrPattern" {
            return Names("Left Right Line Column")
        }
        if typeName == "NotPattern" {
            return Names("Pattern Line Column")
        }
        if typeName == "PositionalPattern" {
            return Names("Patterns Line Column")
        }
        if typeName == "ObjectPattern" {
            return Names("Properties Line Column")
        }
        if typeName == "ListPattern" {
            return Names("Elements Line Column")
        }
        if typeName == "SlicePattern" {
            return Names("BindingName Line Column")
        }
        if typeName == "InterpolatedStringExpression" {
            return Names("Parts IsRaw Line Column")
        }
        if typeName == "InterpolatedStringText" {
            return Names("Text Line Column")
        }
        if typeName == "InterpolatedStringHole" {
            return Names("Expression FormatClause Line Column")
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

    // ---- N+1c tranche 7: leaf/primary expression builders ----
    // Each mirrors a Parser.cs ParsePrimaryExpression construction site; the returned node is nested directly
    // into an EnumMember.Value argument (the tranche-7 value-bearing-member unlock), never bound to a local in
    // a contract. A value-returning builder is the same idiom as Golden.SimpleT (tranche 5).
    public static func IntLit(value: string, line: int, column: int): Expression {
        return new IntLiteralExpression(value, line, column)
    }

    public static func FloatLit(value: string, line: int, column: int): Expression {
        return new FloatLiteralExpression(value, line, column)
    }

    public static func CharLit(value: string, line: int, column: int): Expression {
        return new CharLiteralExpression(value, line, column)
    }

    public static func StrLit(value: string, line: int, column: int): Expression {
        return new StringLiteralExpression(value, line, column)
    }

    public static func BoolLit(value: bool, line: int, column: int): Expression {
        return new BoolLiteralExpression(value, line, column)
    }

    public static func NullLit(line: int, column: int): Expression {
        return new NullLiteralExpression(line, column)
    }

    public static func Ident(name: string, line: int, column: int): Expression {
        return new IdentifierExpression(name, line, column)
    }

    public static func DefaultE(line: int, column: int): Expression {
        return new DefaultExpression(line, column)
    }

    public static func ThisE(line: int, column: int): Expression {
        return new ThisExpression(line, column)
    }

    public static func BaseE(line: int, column: int): Expression {
        return new BaseExpression(line, column)
    }

    public static func Paren(inner: Expression, line: int, column: int): Expression {
        return new ParenthesizedExpression(inner, line, column)
    }

    // A value-bearing enum member — Value is the materialized expression (Parser.cs :1310).
    public static func AddEMemV(members: List<EnumMember>, name: string, value: Expression, line: int, column: int) {
        members.Add(new EnumMember(name, value, line, column))
    }

    // ---- N+1c tranche 8: composed operator-tier builders ----
    // Each mirrors a Parser.cs Parse*Expression construction site (anchored on the OPERATOR token, except
    // TernaryExpression on the `?`). Every position is transcribed from the LIVE Parser.cs AstToJson oracle.
    public static func Bin(left: Expression, op: BinaryOperator, right: Expression, line: int, column: int): Expression {
        return new BinaryExpression(left, op, right, line, column)
    }

    public static func Un(op: UnaryOperator, operand: Expression, line: int, column: int): Expression {
        return new UnaryExpression(op, operand, line, column)
    }

    public static func Tern(condition: Expression, thenExpr: Expression, elseExpr: Expression, line: int, column: int): Expression {
        return new TernaryExpression(condition, thenExpr, elseExpr, line, column)
    }

    public static func Assign(target: Expression, op: AssignmentOperator, value: Expression, line: int, column: int): Expression {
        return new AssignmentExpression(target, op, value, line, column)
    }

    public static func Rng(start: Expression?, end: Expression?, line: int, column: int): Expression {
        return new RangeExpression(start, end, line, column)
    }

    // A field member WITH an initializer (Parser.cs :1782 — explicit type) — the tranche-8 field consumer.
    public static func AddFieldInit(members: List<Declaration>, name: string, fieldType: TypeReference, initializer: Expression, line: int, column: int) {
        members.Add(new NSharpLang.Compiler.Ast.FieldDeclaration(name, fieldType, initializer, Modifiers.None, PropertyModifier.None, new List<AttributeNode>(), line, column))
    }

    // A `Name := value` type-inference field (Parser.cs :1686 — null Type + initializer).
    public static func AddFieldInfer(members: List<Declaration>, name: string, initializer: Expression, line: int, column: int) {
        members.Add(new NSharpLang.Compiler.Ast.FieldDeclaration(name, null, initializer, Modifiers.None, PropertyModifier.None, new List<AttributeNode>(), line, column))
    }

    // ---- N+1c tranche 9a: single-operand / type-carrying postfix + keyword-primary builders ----
    // Each mirrors a Parser.cs construction site (member/index on the dot/bracket token, is/as on the is/as
    // token, await/must/throw and the typeof/nameof/sizeof/checked/unchecked/cast/spread primaries on their
    // keyword / `(` / `...` token). Every position was transcribed from the LIVE Parser.cs AstToJson oracle.
    public static func Member(obj: Expression, memberName: string, isNullConditional: bool, line: int, column: int): Expression {
        return new MemberAccessExpression(obj, memberName, isNullConditional, line, column)
    }

    public static func Index(obj: Expression, index: Expression, isNullConditional: bool, line: int, column: int): Expression {
        return new IndexAccessExpression(obj, index, isNullConditional, line, column)
    }

    public static func Is(expr: Expression, typeRef: TypeReference, variableName: string?, line: int, column: int): Expression {
        return new IsExpression(expr, typeRef, variableName, line, column)
    }

    public static func Cast(expr: Expression, targetType: TypeReference, kind: CastKind, line: int, column: int): Expression {
        return new CastExpression(expr, targetType, kind, line, column)
    }

    public static func Await(expr: Expression, line: int, column: int): Expression {
        return new AwaitExpression(expr, line, column)
    }

    public static func Must(expr: Expression, line: int, column: int): Expression {
        return new MustExpression(expr, line, column)
    }

    public static func Throw(expr: Expression, line: int, column: int): Expression {
        return new ThrowExpression(expr, line, column)
    }

    public static func TypeOf(typeRef: TypeReference, line: int, column: int): Expression {
        return new TypeOfExpression(typeRef, line, column)
    }

    public static func Nameof(target: Expression, line: int, column: int): Expression {
        return new NameofExpression(target, line, column)
    }

    public static func SizeOf(typeRef: TypeReference, line: int, column: int): Expression {
        return new SizeOfExpression(typeRef, line, column)
    }

    public static func Checked(expr: Expression, line: int, column: int): Expression {
        return new CheckedExpression(expr, line, column)
    }

    public static func Unchecked(expr: Expression, line: int, column: int): Expression {
        return new UncheckedExpression(expr, line, column)
    }

    public static func Spread(expr: Expression, line: int, column: int): Expression {
        return new SpreadExpression(expr, line, column)
    }

    // ---- N+1c tranche 9b: argument/element-LIST builders ----
    // Each mirrors a Parser.cs construction site: the CALL on the `(` token (Parser.cs :4492/:4499), `with` on
    // the `with` keyword (:4533), `new` / its ObjectInitializer on the `new` keyword (:5286/:5353/:5283/:5350),
    // tuple + array on their opening `(` / `[` (:5449/:5483/:5497/:5436), and alloc / stackalloc on their
    // keyword (:5196/:5217). The list ELEMENTS (Argument / TupleElement / PropertyInitializer) carry no
    // position of their own except PropertyInitializer's NameLine/NameColumn. Every position below was
    // transcribed from the LIVE Parser.cs AstToJson oracle.
    public static func NoArgs(): List<Argument> {
        return new List<Argument>()
    }

    // A typed null for a NON-generic call's TypeArguments (Parser.cs :4499).
    public static func NoTypeArgs(): List<TypeReference>? {
        return null
    }

    public static func AddArg(args: List<Argument>, name: string?, value: Expression, modifier: ArgumentModifier) {
        args.Add(new Argument(name, value, modifier))
    }

    public static func Call(callee: Expression, args: List<Argument>, typeArgs: List<TypeReference>?, line: int, column: int): Expression {
        return new CallExpression(callee, args, typeArgs, line, column)
    }

    public static func NoProps(): List<PropertyInitializer> {
        return new List<PropertyInitializer>()
    }

    public static func AddProp(props: List<PropertyInitializer>, name: string?, indexExpression: Expression?, value: Expression, nameLine: int, nameColumn: int) {
        props.Add(new PropertyInitializer(name, indexExpression, value, nameLine, nameColumn))
    }

    public static func With(target: Expression, props: List<PropertyInitializer>, line: int, column: int): Expression {
        return new WithExpression(target, props, line, column)
    }

    public static func ObjInit(props: List<PropertyInitializer>, line: int, column: int): ObjectInitializerExpression {
        return new ObjectInitializerExpression(props, line, column)
    }

    public static func NewE(typeRef: TypeReference?, args: List<Argument>, initializer: ObjectInitializerExpression?, arrayLength: Expression?, line: int, column: int): Expression {
        return new NewExpression(typeRef, args, initializer, line, column, arrayLength)
    }

    public static func NoTupleElems(): List<TupleElement> {
        return new List<TupleElement>()
    }

    public static func AddTupleElem(elements: List<TupleElement>, name: string?, value: Expression) {
        elements.Add(new TupleElement(name, value))
    }

    public static func Tuple(elements: List<TupleElement>, line: int, column: int): Expression {
        return new TupleExpression(elements, line, column)
    }

    public static func NoExprs(): List<Expression> {
        return new List<Expression>()
    }

    public static func AddExpr(elements: List<Expression>, value: Expression) {
        elements.Add(value)
    }

    public static func ArrayLit(elements: List<Expression>, isImmutable: bool, line: int, column: int): Expression {
        return new ArrayLiteralExpression(elements, isImmutable, line, column)
    }

    public static func AllocE(inner: Expression, line: int, column: int): Expression {
        return new AllocExpression(inner, line, column)
    }

    public static func StackAllocE(elementType: TypeReference, length: Expression, line: int, column: int): Expression {
        return new StackAllocExpression(elementType, length, line, column)
    }

    // A declaration whose Attributes list carries ARGUMENT-bearing attributes (the tranche-9b unlock — the
    // tranche-4 argument-bearing decline is retired). Parser.cs :292 anchors the AttributeNode on the `[`
    // line and the `[` column + 1.
    public static func AddAttrArgs(attrs: List<AttributeNode>, name: string, args: List<Argument>, line: int, column: int) {
        attrs.Add(new AttributeNode(name, args, line, column))
    }

    // ---- N+1c tranche 9c: lambda / match+pattern / interpolated-string builders ----
    // A position-FREE SimpleTypeReference (Line/Column 0, invalid Span) — Parser.cs builds the implicit lambda
    // parameter type (:3676/:5520) and the TypePattern type (:3444) with the ctor's defaults, so neither
    // carries a source position.
    public static func BareT(name: string): TypeReference {
        return new SimpleTypeReference(name, 0, 0)
    }

    public static func NoParams(): List<Parameter> {
        return new List<Parameter>()
    }

    public static func AddLambdaParam(parameters: List<Parameter>, name: string, line: int, column: int) {
        parameters.Add(new Parameter(name, Golden.BareT("var"), null, false, ParameterModifier.None, null, line, column, false, null))
    }

    // An EXPRESSION-bodied lambda (a block-bodied one carries a BlockStatement and declines until the
    // statement-body tranche).
    public static func Lambda(parameters: List<Parameter>, body: Expression, line: int, column: int): Expression {
        return new LambdaExpression(parameters, body, null, line, column)
    }

    public static func NoCases(): List<MatchCase> {
        return new List<MatchCase>()
    }

    public static func AddCase(cases: List<MatchCase>, pattern: Pattern, guard: Expression?, body: Expression) {
        cases.Add(new MatchCase(pattern, guard, body))
    }

    public static func Match(value: Expression, cases: List<MatchCase>, line: int, column: int): Expression {
        return new MatchExpression(value, cases, line, column)
    }

    public static func NoPatterns(): List<Pattern> {
        return new List<Pattern>()
    }

    public static func AddPattern(patterns: List<Pattern>, pattern: Pattern) {
        patterns.Add(pattern)
    }

    public static func NoPatProps(): List<PropertyPattern> {
        return new List<PropertyPattern>()
    }

    public static func AddPatProp(props: List<PropertyPattern>, name: string, pattern: Pattern?, bindingName: string?, line: int, column: int) {
        props.Add(new PropertyPattern(name, pattern, bindingName, line, column))
    }

    public static func PIdent(name: string, line: int, column: int): Pattern {
        return new IdentifierPattern(name, line, column)
    }

    public static func PLit(literal: Expression, line: int, column: int): Pattern {
        return new LiteralPattern(literal, line, column)
    }

    public static func PType(typeRef: TypeReference, bindingName: string?, line: int, column: int): Pattern {
        return new TypePattern(typeRef, bindingName, line, column)
    }

    public static func PUnion(caseName: string, props: List<PropertyPattern>?, line: int, column: int): Pattern {
        return new UnionCasePattern(caseName, props, line, column)
    }

    public static func PRel(op: string, value: Expression, line: int, column: int): Pattern {
        return new RelationalPattern(op, value, line, column)
    }

    public static func PAnd(left: Pattern, right: Pattern, line: int, column: int): Pattern {
        return new AndPattern(left, right, line, column)
    }

    public static func POr(left: Pattern, right: Pattern, line: int, column: int): Pattern {
        return new OrPattern(left, right, line, column)
    }

    public static func PNot(inner: Pattern, line: int, column: int): Pattern {
        return new NotPattern(inner, line, column)
    }

    public static func PPos(patterns: List<Pattern>, line: int, column: int): Pattern {
        return new PositionalPattern(patterns, line, column)
    }

    public static func PObj(props: List<PropertyPattern>, line: int, column: int): Pattern {
        return new ObjectPattern(props, line, column)
    }

    public static func PList(elements: List<Pattern>, line: int, column: int): Pattern {
        return new ListPattern(elements, line, column)
    }

    public static func PSlice(bindingName: string?, line: int, column: int): Pattern {
        return new SlicePattern(bindingName, line, column)
    }

    public static func NoParts(): List<InterpolatedStringPart> {
        return new List<InterpolatedStringPart>()
    }

    public static func AddText(parts: List<InterpolatedStringPart>, text: string, line: int, column: int) {
        parts.Add(new InterpolatedStringText(text, line, column))
    }

    public static func AddHole(parts: List<InterpolatedStringPart>, expr: Expression, formatClause: string?, line: int, column: int) {
        parts.Add(new InterpolatedStringHole(expr, formatClause, line, column))
    }

    public static func Interp(parts: List<InterpolatedStringPart>, isRaw: bool, line: int, column: int): Expression {
        return new InterpolatedStringExpression(parts, line, column, isRaw)
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

// tranche 9b CONVERTED the tranche-4 "argument-bearing attribute DECLINES" gate to a positive
// materialization: ParseArgumentList now returns the byte-exact List<Argument> Parser.cs stores (:284/:288).
test "016 N+1c tranche 9b: an argument-bearing attribute materializes its Argument list (Parser.cs :288/:292)" {
    actual := RunAst("[Attr(1)] struct S {}\n")
    attrArgs := new List<Argument>()
    Golden.AddArg(attrArgs, null, Golden.IntLit("1", 1, 7), ArgumentModifier.None)
    attrs := new List<AttributeNode>()
    Golden.AddAttrArgs(attrs, "Attr", attrArgs, 1, 2)
    decls := new List<Declaration>()
    Golden.AddStructFull(decls, "S", Modifiers.None, attrs, 1, 11)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a NAMED attribute argument materializes Argument.Name (Parser.cs :4592/:4617)" {
    actual := RunAst("[Attr(x: 1)] struct S {}\n")
    attrArgs := new List<Argument>()
    Golden.AddArg(attrArgs, "x", Golden.IntLit("1", 1, 10), ArgumentModifier.None)
    attrs := new List<AttributeNode>()
    Golden.AddAttrArgs(attrs, "Attr", attrArgs, 1, 2)
    decls := new List<Declaration>()
    Golden.AddStructFull(decls, "S", Modifiers.None, attrs, 1, 14)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
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

// ---- N+1c tranche 7: BEGIN EXPRESSION MATERIALIZATION — the LEAF/PRIMARY tier ----
// ParseExprValue now RETURNS the Expression node it parses for the leaf atoms (int/float/char/string/bool/
// null/identifier/default/this/base) and the single-expression parenthesized form; a composed operator tier
// or a non-leaf primary leaves the node null. The value-bearing ENUM MEMBER (`A = <expr>`) is the tranche-7
// consumer: EnumMember.Value is the materialized node when the value is a leaf/paren atom. Each value node's
// Line/Column is byte-exact to Parser.cs (`line`/`column` captured at ParsePrimaryExpression entry = the value
// token) and TRIANGULATED against LIVE Parser.cs via the AstToJson oracle. The tranche-6 "value-bearing enum
// member DECLINES" test is CONVERTED to the positive int-literal materialization below.

test "016 N+1c tranche 7: a value-bearing enum member materializes an IntLiteralExpression Value (Parser.cs :1301/:4649)" {
    actual := RunAst("enum E {\n    A = 1\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.IntLit("1", 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 7: a mixed valued/valueless member list materializes per-member (Parser.cs :1296/:1310)" {
    actual := RunAst("enum E {\n    A = 1,\n    B\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.IntLit("1", 2, 9), 2, 5)
    Golden.AddEMem(members, "B", 3, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 7: a float-literal value materializes FloatLiteralExpression (Parser.cs :4652)" {
    actual := RunAst("enum E {\n    A = 1.5\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.FloatLit("1.5", 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 7: a char-literal value materializes CharLiteralExpression with quotes (Parser.cs :4658)" {
    actual := RunAst("enum E {\n    A = 'x'\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.CharLit("'x'", 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 7: a first string-literal value materializes StringLiteralExpression AND infers EnumType.String (Parser.cs :4669/:1304)" {
    actual := RunAst("enum E {\n    A = \"x\"\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.StrLit("\"x\"", 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.String, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 7: an explicit int backing type is NOT overridden by a string first-value (Parser.cs :1272/:1304 !hasExplicitType)" {
    actual := RunAst("enum E: int {\n    A = \"x\"\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.StrLit("\"x\"", 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 7: a 'true' value materializes BoolLiteralExpression(true) (Parser.cs :4675)" {
    actual := RunAst("enum E {\n    A = true\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.BoolLit(true, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 7: a 'false' value materializes BoolLiteralExpression(false) (Parser.cs :4681)" {
    actual := RunAst("enum E {\n    A = false\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.BoolLit(false, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 7: a 'null' value materializes NullLiteralExpression (Parser.cs :4687)" {
    actual := RunAst("enum E {\n    A = null\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.NullLit(2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 7: an identifier value materializes IdentifierExpression (Parser.cs :4821)" {
    actual := RunAst("enum E {\n    A = B\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Ident("B", 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 7: a 'default' value materializes DefaultExpression (Parser.cs :4694)" {
    actual := RunAst("enum E {\n    A = default\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.DefaultE(2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 7: a 'this' value materializes ThisExpression (Parser.cs :4701; enum is the reachable syntactic vehicle)" {
    actual := RunAst("enum E {\n    A = this\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.ThisE(2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 7: a 'base' value materializes BaseExpression (Parser.cs :4707; enum is the reachable syntactic vehicle)" {
    actual := RunAst("enum E {\n    A = base\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.BaseE(2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 7: a parenthesized leaf value materializes ParenthesizedExpression wrapping the inner node (Parser.cs :5502)" {
    actual := RunAst("enum E {\n    A = (1)\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Paren(Golden.IntLit("1", 2, 10), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- NEGATIVE SELF-CHECKS (guard the new tranche-7 value-materialization paths against a vacuous pass) ----

test "016 N+1c tranche 7: AstEq.Diff catches a wrong literal Value rather than passing vacuously" {
    actual := RunAst("enum E {\n    A = 1\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.IntLit("2", 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    diff := AstEq.Diff(expected, actual, "unit")
    assert diff != ""
    assert diff == "unit.Declarations[0].Members[0].Value.Value: String(2) != String(1)"
}

test "016 N+1c tranche 7: AstEq.Diff catches a wrong value NODE TYPE (Int golden vs Identifier actual)" {
    actual := RunAst("enum E {\n    A = B\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.IntLit("B", 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    diff := AstEq.Diff(expected, actual, "unit")
    assert diff != ""
    assert diff == "unit.Declarations[0].Members[0].Value: node type IntLiteralExpression != IdentifierExpression"
}

// ---- N+1c tranche 8: COMPOSED OPERATOR TIERS materialize (the tranche-7 binary/unary declines CONVERTED) ----
// The tranche-7 "1 + 2 / -1 DECLINE" tests are now POSITIVE materializations (the composed tiers landed). Every
// position/operator below is transcribed from the LIVE Parser.cs AstToJson oracle and re-verified whole-tree by
// the throwaway fresh-Compiler probe (34/34 synthetic + whole-file shapes MATCH owner==Parser.cs). The
// enum-member value (`A = <expr>`) is the reachable ParseExprValue vehicle (as in tranche 7); the operator
// anchor is the OPERATOR token except TernaryExpression (the `?`) and the RangeExpression `..`.

test "016 N+1c tranche 8: an additive enum value (1 + 2) materializes BinaryExpression(Add) anchored on '+' (Parser.cs :4240)" {
    actual := RunAst("enum E {\n    A = 1 + 2\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.IntLit("1", 2, 9), BinaryOperator.Add, Golden.IntLit("2", 2, 13), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a multiplicative enum value (2 * 3) materializes BinaryExpression(Multiply) (Parser.cs :4285)" {
    actual := RunAst("enum E {\n    A = 2 * 3\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.IntLit("2", 2, 9), BinaryOperator.Multiply, Golden.IntLit("3", 2, 13), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a subtract enum value (5 - 1) materializes BinaryExpression(Subtract) (Parser.cs :4240)" {
    actual := RunAst("enum E {\n    A = 5 - 1\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.IntLit("5", 2, 9), BinaryOperator.Subtract, Golden.IntLit("1", 2, 13), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a left-shift enum value (1 << 4) materializes BinaryExpression(LeftShift) (Parser.cs :4225) — the flag-enum idiom" {
    actual := RunAst("enum E {\n    A = 1 << 4\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.IntLit("1", 2, 9), BinaryOperator.LeftShift, Golden.IntLit("4", 2, 14), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a right-shift enum value (8 >> 1) materializes BinaryExpression(RightShift) (Parser.cs :4225)" {
    actual := RunAst("enum E {\n    A = 8 >> 1\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.IntLit("8", 2, 9), BinaryOperator.RightShift, Golden.IntLit("1", 2, 14), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a bitwise-or enum value (1 | 2) materializes BinaryExpression(BitwiseOr) (Parser.cs :4094)" {
    actual := RunAst("enum E {\n    A = 1 | 2\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.IntLit("1", 2, 9), BinaryOperator.BitwiseOr, Golden.IntLit("2", 2, 13), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a bitwise-and enum value (6 & 2) materializes BinaryExpression(BitwiseAnd) (Parser.cs :4122)" {
    actual := RunAst("enum E {\n    A = 6 & 2\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.IntLit("6", 2, 9), BinaryOperator.BitwiseAnd, Golden.IntLit("2", 2, 13), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a bitwise-xor enum value (5 ^ 1) materializes BinaryExpression(BitwiseXor) (Parser.cs :4108)" {
    actual := RunAst("enum E {\n    A = 5 ^ 1\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.IntLit("5", 2, 9), BinaryOperator.BitwiseXor, Golden.IntLit("1", 2, 13), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: an equality enum value (1 == 2) materializes BinaryExpression(Equal) (Parser.cs :4137)" {
    actual := RunAst("enum E {\n    A = 1 == 2\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.IntLit("1", 2, 9), BinaryOperator.Equal, Golden.IntLit("2", 2, 14), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: an inequality enum value (1 != 2) materializes BinaryExpression(NotEqual) (Parser.cs :4137)" {
    actual := RunAst("enum E {\n    A = 1 != 2\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.IntLit("1", 2, 9), BinaryOperator.NotEqual, Golden.IntLit("2", 2, 14), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a relational enum value (1 < 2) materializes BinaryExpression(Less) (Parser.cs :4209)" {
    actual := RunAst("enum E {\n    A = 1 < 2\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.IntLit("1", 2, 9), BinaryOperator.Less, Golden.IntLit("2", 2, 13), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a relational enum value (1 <= 2) materializes BinaryExpression(LessOrEqual) (Parser.cs :4209)" {
    actual := RunAst("enum E {\n    A = 1 <= 2\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.IntLit("1", 2, 9), BinaryOperator.LessOrEqual, Golden.IntLit("2", 2, 14), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a relational enum value (1 >= 2) materializes BinaryExpression(GreaterOrEqual) (Parser.cs :4209)" {
    actual := RunAst("enum E {\n    A = 1 >= 2\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.IntLit("1", 2, 9), BinaryOperator.GreaterOrEqual, Golden.IntLit("2", 2, 14), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a logical-and enum value (a && b) materializes BinaryExpression(And) (Parser.cs :4080)" {
    actual := RunAst("enum E {\n    A = a && b\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.Ident("a", 2, 9), BinaryOperator.And, Golden.Ident("b", 2, 14), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a logical-or enum value (a || b) materializes BinaryExpression(Or) (Parser.cs :4066)" {
    actual := RunAst("enum E {\n    A = a || b\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.Ident("a", 2, 9), BinaryOperator.Or, Golden.Ident("b", 2, 14), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a null-coalesce enum value (a ?? b) materializes BinaryExpression(NullCoalesce) (Parser.cs :4052)" {
    actual := RunAst("enum E {\n    A = a ?? b\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.Ident("a", 2, 9), BinaryOperator.NullCoalesce, Golden.Ident("b", 2, 14), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: precedence composes bottom-up (1 + 2 * 3 = Add(1, Multiply(2,3))) (Parser.cs :4240/:4285)" {
    actual := RunAst("enum E {\n    A = 1 + 2 * 3\n}\n")
    members := new List<EnumMember>()
    inner := Golden.Bin(Golden.IntLit("2", 2, 13), BinaryOperator.Multiply, Golden.IntLit("3", 2, 17), 2, 15)
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.IntLit("1", 2, 9), BinaryOperator.Add, inner, 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: same-tier composes left-associatively (1 + 2 + 3 = Add(Add(1,2),3)) (Parser.cs :4240)" {
    actual := RunAst("enum E {\n    A = 1 + 2 + 3\n}\n")
    members := new List<EnumMember>()
    inner := Golden.Bin(Golden.IntLit("1", 2, 9), BinaryOperator.Add, Golden.IntLit("2", 2, 13), 2, 11)
    Golden.AddEMemV(members, "A", Golden.Bin(inner, BinaryOperator.Add, Golden.IntLit("3", 2, 17), 2, 15), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a prefix-negate enum value (-1) materializes UnaryExpression(Negate) anchored on '-' (Parser.cs :4380)" {
    actual := RunAst("enum E {\n    A = -1\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Un(UnaryOperator.Negate, Golden.IntLit("1", 2, 10), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a prefix-not enum value (!a) materializes UnaryExpression(Not) (Parser.cs :4380)" {
    actual := RunAst("enum E {\n    A = !a\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Un(UnaryOperator.Not, Golden.Ident("a", 2, 10), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a prefix-bitwise-not enum value (~1) materializes UnaryExpression(BitwiseNot) (Parser.cs :4380)" {
    actual := RunAst("enum E {\n    A = ~1\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Un(UnaryOperator.BitwiseNot, Golden.IntLit("1", 2, 10), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a ternary enum value (a ? b : c) materializes TernaryExpression anchored on '?' (Parser.cs :4038)" {
    actual := RunAst("enum E {\n    A = a ? b : c\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Tern(Golden.Ident("a", 2, 9), Golden.Ident("b", 2, 13), Golden.Ident("c", 2, 17), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a two-operand range enum value (a..b) materializes RangeExpression anchored on '..' (Parser.cs :4321)" {
    actual := RunAst("enum E {\n    A = a..b\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Rng(Golden.Ident("a", 2, 9), Golden.Ident("b", 2, 12), 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: an open-start range enum value (..b) materializes RangeExpression(null, b) (Parser.cs :4305)" {
    actual := RunAst("enum E {\n    A = ..b\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Rng(null, Golden.Ident("b", 2, 11), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: an assignment enum value (b = 1) materializes AssignmentExpression(Assign) (Parser.cs :3752)" {
    actual := RunAst("enum E {\n    A = b = 1\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Assign(Golden.Ident("b", 2, 9), AssignmentOperator.Assign, Golden.IntLit("1", 2, 13), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a compound-assignment enum value (b += 1) materializes AssignmentExpression(AddAssign) (Parser.cs :3752)" {
    actual := RunAst("enum E {\n    A = b += 1\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Assign(Golden.Ident("b", 2, 9), AssignmentOperator.AddAssign, Golden.IntLit("1", 2, 14), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a parenthesized COMPOSED value ((1 + 2)) now wraps a BinaryExpression (tranche 7 wrapped only leaves)" {
    actual := RunAst("enum E {\n    A = (1 + 2)\n}\n")
    members := new List<EnumMember>()
    innerBin := Golden.Bin(Golden.IntLit("1", 2, 10), BinaryOperator.Add, Golden.IntLit("2", 2, 14), 2, 12)
    Golden.AddEMemV(members, "A", Golden.Paren(innerBin, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- NEGATIVE SELF-CHECKS (guard the tranche-8 composed paths against a vacuous pass) ----

test "016 N+1c tranche 8: AstEq.Diff catches a wrong BinaryOperator (Add golden vs Subtract actual)" {
    actual := RunAst("enum E {\n    A = 5 - 1\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.IntLit("5", 2, 9), BinaryOperator.Add, Golden.IntLit("1", 2, 13), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    diff := AstEq.Diff(expected, actual, "unit")
    assert diff != ""
    assert diff == "unit.Declarations[0].Members[0].Value.Operator: BinaryOperator(Add) != BinaryOperator(Subtract)"
}

test "016 N+1c tranche 8: AstEq.Diff catches a wrong composed NODE TYPE (Binary golden vs Unary actual)" {
    actual := RunAst("enum E {\n    A = -1\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Bin(Golden.IntLit("1", 2, 10), BinaryOperator.Subtract, Golden.IntLit("1", 2, 10), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    diff := AstEq.Diff(expected, actual, "unit")
    assert diff != ""
    assert diff == "unit.Declarations[0].Members[0].Value: node type BinaryExpression != UnaryExpression"
}

// ---- N+1c tranche 8: FIELD INITIALIZERS (the second consumer — FieldDeclaration.Initializer) ----
// A `X: Type = <expr>` / `X := <expr>` field now materializes its Initializer node (Parser.cs :1782/:1686) when
// the initializer expression materializes. A struct with only initialized fields fully materializes → whole-file.

test "016 N+1c tranche 8: a field literal initializer (X: int = 5) materializes FieldDeclaration.Initializer (Parser.cs :1782)" {
    actual := RunAst("struct S {\n    X: int = 5\n}\n")
    members := new List<Declaration>()
    Golden.AddFieldInit(members, "X", Golden.SimpleT("int", 2, 8, 11), Golden.IntLit("5", 2, 14), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a field composed initializer (X: int = 1 + 2) materializes a BinaryExpression Initializer" {
    actual := RunAst("struct S {\n    X: int = 1 + 2\n}\n")
    members := new List<Declaration>()
    initBin := Golden.Bin(Golden.IntLit("1", 2, 14), BinaryOperator.Add, Golden.IntLit("2", 2, 18), 2, 16)
    Golden.AddFieldInit(members, "X", Golden.SimpleT("int", 2, 8, 11), initBin, 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 8: a type-inference field (X := 5) materializes a null-Type FieldDeclaration with Initializer (Parser.cs :1686)" {
    actual := RunAst("struct S {\n    X := 5\n}\n")
    members := new List<Declaration>()
    Golden.AddFieldInfer(members, "X", Golden.IntLit("5", 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- WHOLE-FILE EQUALITY (the DIRECT tranche-8 field-initializer unlock: a field-only struct) ----
// A complete file (namespace + a struct whose members are ALL initialized fields) now fully materializes —
// EVERY member must materialize for whole-tree equality (a declining member would shorten the list vs
// Parser.cs). Positions transcribed from the LIVE Parser.cs AstToJson oracle (probe: owner == Parser.cs).

test "016 N+1c tranche 8: WHOLE-FILE equality on a field-only struct with literal + computed initializers" {
    actual := RunAst("namespace Demo\n\nstruct Config {\n    Width: int = 80\n    Height: int = 24\n    Ratio: int = 4 * 3\n}\n")
    members := new List<Declaration>()
    Golden.AddFieldInit(members, "Width", Golden.SimpleT("int", 4, 12, 15), Golden.IntLit("80", 4, 18), 4, 5)
    Golden.AddFieldInit(members, "Height", Golden.SimpleT("int", 5, 13, 16), Golden.IntLit("24", 5, 19), 5, 5)
    ratioInit := Golden.Bin(Golden.IntLit("4", 6, 18), BinaryOperator.Multiply, Golden.IntLit("3", 6, 22), 6, 20)
    Golden.AddFieldInit(members, "Ratio", Golden.SimpleT("int", 6, 12, 15), ratioInit, 6, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "Config", members, 3, 1)
    expected := Golden.Unit(Golden.Ns("Demo", 1, 1), NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- RETAINED-GATE DECLINES (with tranche 9c landed, the LAST expression-side decline is the BLOCK-bodied
//      lambda, whose body is a BlockStatement — the statement-body tranche) ----
// A value whose sub-part is a still-deferred form leaves ParseExprValue().Node null → decline, no-stub.
// (The tranche-9b match / lambda / interpolated-string declines are now POSITIVE materializations below.)

test "016 N+1c tranche 9c: a BLOCK-bodied lambda still DECLINES (BlockStatement deferred to the statement tranche, no-stub)" {
    actual := RunAst("enum E {\n    A = x => { }\n}\n")
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, NoDecls(), 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- N+1c tranche 9a: SINGLE-OPERAND / TYPE-CARRYING postfix + keyword-primary forms materialize ----
// The postfix member/index access, is/as, await/must/throw, and the typeof/nameof/sizeof/checked/unchecked/
// cast/spread primaries now RETURN their byte-exact Expression node. Consumer = the value-bearing enum member
// (`A = <expr>`) except the field-init cases below. Every Line/Column + Span was transcribed from the LIVE
// Parser.cs AstToJson oracle (a throwaway fresh-Compiler probe ran BOTH live Parser.cs and the owner's
// ParseFileAst through the identical OutputFormatter.AstToJson serializer and diffed — 24/24 whole-tree MATCH).

test "016 N+1c tranche 9a: a member-access enum value (a.b) materializes MemberAccessExpression on the '.' (Parser.cs :4453)" {
    actual := RunAst("enum E {\n    A = a.b\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Member(Golden.Ident("a", 2, 9), "b", false, 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: a null-conditional member (a?.b) materializes IsNullConditional=true (Parser.cs :4431/:4453)" {
    actual := RunAst("enum E {\n    A = a?.b\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Member(Golden.Ident("a", 2, 9), "b", true, 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: a member chain (a.b.c) nests left-to-right, each anchored on its own '.' (Parser.cs :4453)" {
    actual := RunAst("enum E {\n    A = a.b.c\n}\n")
    members := new List<EnumMember>()
    inner := Golden.Member(Golden.Ident("a", 2, 9), "b", false, 2, 10)
    Golden.AddEMemV(members, "A", Golden.Member(inner, "c", false, 2, 12), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: an index access (a[0]) materializes IndexAccessExpression on the '[' (Parser.cs :4461)" {
    actual := RunAst("enum E {\n    A = a[0]\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Index(Golden.Ident("a", 2, 9), Golden.IntLit("0", 2, 11), false, 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: a null-conditional index (a?[0]) materializes IsNullConditional=true (Parser.cs :4457/:4461)" {
    actual := RunAst("enum E {\n    A = a?[0]\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Index(Golden.Ident("a", 2, 9), Golden.IntLit("0", 2, 12), true, 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: an index over a member (a.b[0]) composes IndexAccess(MemberAccess) (Parser.cs :4453/:4461)" {
    actual := RunAst("enum E {\n    A = a.b[0]\n}\n")
    members := new List<EnumMember>()
    obj := Golden.Member(Golden.Ident("a", 2, 9), "b", false, 2, 10)
    Golden.AddEMemV(members, "A", Golden.Index(obj, Golden.IntLit("0", 2, 13), false, 2, 12), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: an is-type value (a is int) materializes IsExpression anchored on 'is', VariableName null (Parser.cs :4162)" {
    actual := RunAst("enum E {\n    A = a is int\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Is(Golden.Ident("a", 2, 9), Golden.SimpleT("int", 2, 14, 17), null, 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: an is-pattern value (a is int x) captures the pattern variable name (Parser.cs :4159/:4162)" {
    actual := RunAst("enum E {\n    A = a is int x\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Is(Golden.Ident("a", 2, 9), Golden.SimpleT("int", 2, 14, 17), "x", 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: an is-generic value (a is List<int>) threads the full type grammar (Parser.cs :4154/:4162)" {
    actual := RunAst("enum E {\n    A = a is List<int>\n}\n")
    members := new List<EnumMember>()
    args := new List<TypeReference>()
    args.Add(Golden.SimpleT("int", 2, 19, 22))
    Golden.AddEMemV(members, "A", Golden.Is(Golden.Ident("a", 2, 9), Golden.GenericT("List", args, 2, 14, 23), null, 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: an as-cast value (a as string) materializes CastExpression(Safe) anchored on 'as' (Parser.cs :4168)" {
    actual := RunAst("enum E {\n    A = a as string\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Cast(Golden.Ident("a", 2, 9), Golden.SimpleT("string", 2, 14, 20), CastKind.Safe, 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: an await value (await x) materializes AwaitExpression anchored on 'await' (Parser.cs :4390)" {
    actual := RunAst("enum E {\n    A = await x\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Await(Golden.Ident("x", 2, 15), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: a must value (must x) materializes MustExpression anchored on 'must' (Parser.cs :4400)" {
    actual := RunAst("enum E {\n    A = must x\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Must(Golden.Ident("x", 2, 14), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: a throw value (throw x) materializes ThrowExpression anchored on 'throw' (Parser.cs :4410)" {
    actual := RunAst("enum E {\n    A = throw x\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Throw(Golden.Ident("x", 2, 15), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: a typeof value (typeof(int)) materializes TypeOfExpression wrapping the type (Parser.cs :4717)" {
    actual := RunAst("enum E {\n    A = typeof(int)\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.TypeOf(Golden.SimpleT("int", 2, 16, 19), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: a nameof value (nameof(x)) materializes NameofExpression wrapping the expression (Parser.cs :4726)" {
    actual := RunAst("enum E {\n    A = nameof(x)\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Nameof(Golden.Ident("x", 2, 16), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: a sizeof value (sizeof(int)) materializes SizeOfExpression wrapping the type (Parser.cs :4735)" {
    actual := RunAst("enum E {\n    A = sizeof(int)\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.SizeOf(Golden.SimpleT("int", 2, 16, 19), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: a checked value (checked(x)) materializes CheckedExpression wrapping the expression (Parser.cs :4745)" {
    actual := RunAst("enum E {\n    A = checked(x)\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Checked(Golden.Ident("x", 2, 17), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: an unchecked value (unchecked(x)) materializes UncheckedExpression (Parser.cs :4755)" {
    actual := RunAst("enum E {\n    A = unchecked(x)\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Unchecked(Golden.Ident("x", 2, 19), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: a hard cast value ((int)x) materializes CastExpression(Hard) anchored on '(' (Parser.cs :4800)" {
    actual := RunAst("enum E {\n    A = (int)x\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Cast(Golden.Ident("x", 2, 14), Golden.SimpleT("int", 2, 10, 13), CastKind.Hard, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: a spread value (...x) materializes SpreadExpression anchored on '...' (Parser.cs :4814)" {
    actual := RunAst("enum E {\n    A = ...x\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Spread(Golden.Ident("x", 2, 12), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// Field-init consumer (the OTHER Expression-capturing site): both the `X := <expr>` inference form and the
// typed `X: T = <expr>` form materialize these nodes into FieldDeclaration.Initializer.

test "016 N+1c tranche 9a: a `:=` field materializes a member-access initializer (Parser.cs :1686/:4453)" {
    actual := RunAst("struct S {\n    X := a.b\n}\n")
    members := new List<Declaration>()
    Golden.AddFieldInfer(members, "X", Golden.Member(Golden.Ident("a", 2, 10), "b", false, 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: a typed field materializes an is-expression initializer (Parser.cs :1782/:4162)" {
    actual := RunAst("struct S {\n    X: bool = a is int\n}\n")
    members := new List<Declaration>()
    Golden.AddFieldInit(members, "X", Golden.SimpleT("bool", 2, 8, 12), Golden.Is(Golden.Ident("a", 2, 15), Golden.SimpleT("int", 2, 20, 23), null, 2, 17), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9a: a `:=` field materializes a typeof initializer (Parser.cs :1686/:4717)" {
    actual := RunAst("struct S {\n    X := typeof(int)\n}\n")
    members := new List<Declaration>()
    Golden.AddFieldInfer(members, "X", Golden.TypeOf(Golden.SimpleT("int", 2, 17, 20), 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// A WHOLE-FILE multi-member enum mixing three tranche-9a forms (member / is / typeof), comma-separated, every
// member materializing its distinct node type — the strongest single-file owner==golden==Parser.cs proof.
test "016 N+1c tranche 9a: WHOLE-FILE enum mixing member-access, is-type, and typeof values across three members" {
    actual := RunAst("enum E {\n    A = a.b,\n    B = a is int,\n    C = typeof(int)\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Member(Golden.Ident("a", 2, 9), "b", false, 2, 10), 2, 5)
    Golden.AddEMemV(members, "B", Golden.Is(Golden.Ident("a", 3, 9), Golden.SimpleT("int", 3, 14, 17), null, 3, 11), 3, 5)
    Golden.AddEMemV(members, "C", Golden.TypeOf(Golden.SimpleT("int", 4, 16, 19), 4, 9), 4, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// Negative self-checks — guard the new recursion paths against a vacuous pass (a wrong scalar / node-type in
// the golden MUST surface as a non-empty Diff).
test "016 N+1c tranche 9a: AstEq surfaces a wrong member name (guards vacuous member-access pass)" {
    actual := RunAst("enum E {\n    A = a.b\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Member(Golden.Ident("a", 2, 9), "WRONG", false, 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") != ""
}

test "016 N+1c tranche 9a: AstEq surfaces a wrong IsNullConditional flag (guards vacuous member-access pass)" {
    actual := RunAst("enum E {\n    A = a.b\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Member(Golden.Ident("a", 2, 9), "b", true, 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") != ""
}

test "016 N+1c tranche 9a: AstEq surfaces a wrong node TYPE (Is golden vs TypeOf actual) — guards vacuous keyword-primary pass" {
    actual := RunAst("enum E {\n    A = typeof(int)\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Is(Golden.Ident("a", 2, 9), Golden.SimpleT("int", 2, 16, 19), null, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") != ""
}

// ---- WHOLE-FILE REAL-CORPUS EQUALITY (the DIRECT tranche-7 unlock: value-bearing int-literal enums) ----
// EXACT byte content of the in-repo pure-enum file DeclarationEnums.nl (5 public enums; ParameterModifier +
// EnumType valueless, SpecialConstraintKind + PropertyModifier + Modifiers int-literal-valued — 26 valued
// members total). Every EnumMember.Value is an IntLiteralExpression whose Line/Column + Value were transcribed
// from the LIVE Parser.cs AstToJson oracle; owner == golden == Parser.cs whole-tree (the whole-file MATCH was
// also confirmed against the file on disk via the throwaway AstToJson probe).

test "016 N+1c tranche 7: WHOLE-FILE equality on DeclarationEnums.nl (5 public enums, 26 int-literal-valued members)" {
    actual := RunAst("namespace NSharpLang.Compiler.Ast\n\npublic enum ParameterModifier {\n    None,\n    Ref,\n    Out,\n    Params\n}\n\npublic enum EnumType {\n    Int,\n    String\n}\n\npublic enum SpecialConstraintKind {\n    None = 0,\n    Class = 1,\n    Struct = 2,\n    New = 4\n}\n\npublic enum PropertyModifier {\n    None = 0,\n    Required = 1,\n    Init = 2,\n    Readonly = 4\n}\n\npublic enum Modifiers {\n    None = 0,\n    Public = 1,\n    Private = 2,\n    Internal = 4,\n    Protected = 8,\n    Static = 16,\n    Virtual = 32,\n    Abstract = 64,\n    Sealed = 128,\n    Partial = 256,\n    Readonly = 512,\n    Const = 1024,\n    Async = 2048,\n    Generator = 4096,\n    Required = 8192,\n    Init = 16384,\n    File = 32768,\n    Override = 65536\n}\n")

    paramMods := new List<EnumMember>()
    Golden.AddEMem(paramMods, "None", 4, 5)
    Golden.AddEMem(paramMods, "Ref", 5, 5)
    Golden.AddEMem(paramMods, "Out", 6, 5)
    Golden.AddEMem(paramMods, "Params", 7, 5)

    enumTypeMembers := new List<EnumMember>()
    Golden.AddEMem(enumTypeMembers, "Int", 11, 5)
    Golden.AddEMem(enumTypeMembers, "String", 12, 5)

    constraintMembers := new List<EnumMember>()
    Golden.AddEMemV(constraintMembers, "None", Golden.IntLit("0", 16, 12), 16, 5)
    Golden.AddEMemV(constraintMembers, "Class", Golden.IntLit("1", 17, 13), 17, 5)
    Golden.AddEMemV(constraintMembers, "Struct", Golden.IntLit("2", 18, 14), 18, 5)
    Golden.AddEMemV(constraintMembers, "New", Golden.IntLit("4", 19, 11), 19, 5)

    propMods := new List<EnumMember>()
    Golden.AddEMemV(propMods, "None", Golden.IntLit("0", 23, 12), 23, 5)
    Golden.AddEMemV(propMods, "Required", Golden.IntLit("1", 24, 16), 24, 5)
    Golden.AddEMemV(propMods, "Init", Golden.IntLit("2", 25, 12), 25, 5)
    Golden.AddEMemV(propMods, "Readonly", Golden.IntLit("4", 26, 16), 26, 5)

    modifiers := new List<EnumMember>()
    Golden.AddEMemV(modifiers, "None", Golden.IntLit("0", 30, 12), 30, 5)
    Golden.AddEMemV(modifiers, "Public", Golden.IntLit("1", 31, 14), 31, 5)
    Golden.AddEMemV(modifiers, "Private", Golden.IntLit("2", 32, 15), 32, 5)
    Golden.AddEMemV(modifiers, "Internal", Golden.IntLit("4", 33, 16), 33, 5)
    Golden.AddEMemV(modifiers, "Protected", Golden.IntLit("8", 34, 17), 34, 5)
    Golden.AddEMemV(modifiers, "Static", Golden.IntLit("16", 35, 14), 35, 5)
    Golden.AddEMemV(modifiers, "Virtual", Golden.IntLit("32", 36, 15), 36, 5)
    Golden.AddEMemV(modifiers, "Abstract", Golden.IntLit("64", 37, 16), 37, 5)
    Golden.AddEMemV(modifiers, "Sealed", Golden.IntLit("128", 38, 14), 38, 5)
    Golden.AddEMemV(modifiers, "Partial", Golden.IntLit("256", 39, 15), 39, 5)
    Golden.AddEMemV(modifiers, "Readonly", Golden.IntLit("512", 40, 16), 40, 5)
    Golden.AddEMemV(modifiers, "Const", Golden.IntLit("1024", 41, 13), 41, 5)
    Golden.AddEMemV(modifiers, "Async", Golden.IntLit("2048", 42, 13), 42, 5)
    Golden.AddEMemV(modifiers, "Generator", Golden.IntLit("4096", 43, 17), 43, 5)
    Golden.AddEMemV(modifiers, "Required", Golden.IntLit("8192", 44, 16), 44, 5)
    Golden.AddEMemV(modifiers, "Init", Golden.IntLit("16384", 45, 12), 45, 5)
    Golden.AddEMemV(modifiers, "File", Golden.IntLit("32768", 46, 12), 46, 5)
    Golden.AddEMemV(modifiers, "Override", Golden.IntLit("65536", 47, 16), 47, 5)

    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "ParameterModifier", paramMods, EnumType.Int, Modifiers.Public, 3, 8)
    Golden.AddEnumM(decls, "EnumType", enumTypeMembers, EnumType.Int, Modifiers.Public, 10, 8)
    Golden.AddEnumM(decls, "SpecialConstraintKind", constraintMembers, EnumType.Int, Modifiers.Public, 15, 8)
    Golden.AddEnumM(decls, "PropertyModifier", propMods, EnumType.Int, Modifiers.Public, 22, 8)
    Golden.AddEnumM(decls, "Modifiers", modifiers, EnumType.Int, Modifiers.Public, 29, 8)
    expected := Golden.Unit(Golden.Ns("NSharpLang.Compiler.Ast", 1, 1), NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- N+1c tranche 9b: the ARGUMENT/ELEMENT-LIST expression forms materialize ----
// Postfix CALL (incl. the generic-call type arguments and every argument shape), `with`, `new` (target-typed /
// traditional / sized-array / object-vs-collection initializer), tuples, array + immutable-array literals, and
// the alloc / stackalloc primaries now RETURN their byte-exact Expression node. Consumer = the value-bearing
// enum member (`A = <expr>`) except the field-init / attribute cases. Every Line/Column + Span was transcribed
// from the LIVE Parser.cs AstToJson oracle (a throwaway fresh-Compiler probe ran BOTH live Parser.cs and the
// owner's ParseFileAst through the identical OutputFormatter.AstToJson serializer and diffed — 48/48 whole-tree
// MATCH; the 3 tranche-9c forms correctly show live-materializes-vs-owner-declines).

test "016 N+1c tranche 9b: an argument-free call (F()) materializes CallExpression anchored on '(' (Parser.cs :4499)" {
    actual := RunAst("enum E {\n    A = F()\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Call(Golden.Ident("F", 2, 9), Golden.NoArgs(), Golden.NoTypeArgs(), 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a one-argument call materializes a single Argument (Parser.cs :4617)" {
    actual := RunAst("enum E {\n    A = F(1)\n}\n")
    args := new List<Argument>()
    Golden.AddArg(args, null, Golden.IntLit("1", 2, 11), ArgumentModifier.None)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Call(Golden.Ident("F", 2, 9), args, Golden.NoTypeArgs(), 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a two-argument call materializes both Arguments in source order (Parser.cs :4619)" {
    actual := RunAst("enum E {\n    A = F(1, x)\n}\n")
    args := new List<Argument>()
    Golden.AddArg(args, null, Golden.IntLit("1", 2, 11), ArgumentModifier.None)
    Golden.AddArg(args, null, Golden.Ident("x", 2, 14), ArgumentModifier.None)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Call(Golden.Ident("F", 2, 9), args, Golden.NoTypeArgs(), 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a named argument (F(n: 1)) materializes Argument.Name (Parser.cs :4592)" {
    actual := RunAst("enum E {\n    A = F(n: 1)\n}\n")
    args := new List<Argument>()
    Golden.AddArg(args, "n", Golden.IntLit("1", 2, 14), ArgumentModifier.None)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Call(Golden.Ident("F", 2, 9), args, Golden.NoTypeArgs(), 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a spread argument (F(...x)) wraps the value in SpreadExpression (Parser.cs :4604)" {
    actual := RunAst("enum E {\n    A = F(...x)\n}\n")
    args := new List<Argument>()
    Golden.AddArg(args, null, Golden.Spread(Golden.Ident("x", 2, 14), 2, 11), ArgumentModifier.None)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Call(Golden.Ident("F", 2, 9), args, Golden.NoTypeArgs(), 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a ref argument materializes ArgumentModifier.Ref (Parser.cs :4560)" {
    actual := RunAst("enum E {\n    A = F(ref x)\n}\n")
    args := new List<Argument>()
    Golden.AddArg(args, null, Golden.Ident("x", 2, 15), ArgumentModifier.Ref)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Call(Golden.Ident("F", 2, 9), args, Golden.NoTypeArgs(), 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: an out argument materializes ArgumentModifier.Out (Parser.cs :4565)" {
    actual := RunAst("enum E {\n    A = F(out x)\n}\n")
    args := new List<Argument>()
    Golden.AddArg(args, null, Golden.Ident("x", 2, 15), ArgumentModifier.Out)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Call(Golden.Ident("F", 2, 9), args, Golden.NoTypeArgs(), 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// The inline-out NL103 arm still builds a REAL Argument in Parser.cs (:4582) — an IdentifierExpression over the
// SECOND identifier — so the owner materializes it byte-exact alongside the diagnostic (not synthetic content).
test "016 N+1c tranche 9b: an inline-out argument (F(out T x)) materializes the second identifier (Parser.cs :4582)" {
    actual := RunAst("enum E {\n    A = F(out T x)\n}\n")
    args := new List<Argument>()
    Golden.AddArg(args, null, Golden.Ident("x", 2, 17), ArgumentModifier.Out)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Call(Golden.Ident("F", 2, 9), args, Golden.NoTypeArgs(), 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a bare alloc keyword argument becomes an IdentifierExpression (Parser.cs :4610)" {
    actual := RunAst("enum E {\n    A = F(alloc)\n}\n")
    args := new List<Argument>()
    Golden.AddArg(args, null, Golden.Ident("alloc", 2, 11), ArgumentModifier.None)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Call(Golden.Ident("F", 2, 9), args, Golden.NoTypeArgs(), 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a method call (a.b(1)) nests the MemberAccess callee (Parser.cs :4453/:4499)" {
    actual := RunAst("enum E {\n    A = a.b(1)\n}\n")
    args := new List<Argument>()
    Golden.AddArg(args, null, Golden.IntLit("1", 2, 13), ArgumentModifier.None)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Call(Golden.Member(Golden.Ident("a", 2, 9), "b", false, 2, 10), args, Golden.NoTypeArgs(), 2, 12), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a chained call (f()(2)) nests CallExpression as its own callee (Parser.cs :4499)" {
    actual := RunAst("enum E {\n    A = f()(2)\n}\n")
    outerArgs := new List<Argument>()
    Golden.AddArg(outerArgs, null, Golden.IntLit("2", 2, 13), ArgumentModifier.None)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Call(Golden.Call(Golden.Ident("f", 2, 9), Golden.NoArgs(), Golden.NoTypeArgs(), 2, 10), outerArgs, Golden.NoTypeArgs(), 2, 12), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a nested call argument (f(g(1))) recurses through the Argument value" {
    actual := RunAst("enum E {\n    A = f(g(1))\n}\n")
    innerArgs := new List<Argument>()
    Golden.AddArg(innerArgs, null, Golden.IntLit("1", 2, 13), ArgumentModifier.None)
    outerArgs := new List<Argument>()
    Golden.AddArg(outerArgs, null, Golden.Call(Golden.Ident("g", 2, 11), innerArgs, Golden.NoTypeArgs(), 2, 12), ArgumentModifier.None)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Call(Golden.Ident("f", 2, 9), outerArgs, Golden.NoTypeArgs(), 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a generic call (M<int>(1)) materializes TypeArguments anchored on '(' (Parser.cs :4492)" {
    actual := RunAst("enum E {\n    A = M<int>(1)\n}\n")
    typeArgs := new List<TypeReference>()
    typeArgs.Add(Golden.SimpleT("int", 2, 11, 14))
    args := new List<Argument>()
    Golden.AddArg(args, null, Golden.IntLit("1", 2, 16), ArgumentModifier.None)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Call(Golden.Ident("M", 2, 9), args, typeArgs, 2, 15), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a two-type-argument generic call keeps both TypeArguments (Parser.cs :2104)" {
    actual := RunAst("enum E {\n    A = M<int, string>()\n}\n")
    typeArgs := new List<TypeReference>()
    typeArgs.Add(Golden.SimpleT("int", 2, 11, 14))
    typeArgs.Add(Golden.SimpleT("string", 2, 16, 22))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Call(Golden.Ident("M", 2, 9), Golden.NoArgs(), typeArgs, 2, 23), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// The split-`>>` discipline: `M<List<int>>()` closes TWO generic scopes on one RightShift token.
test "016 N+1c tranche 9b: a nested generic call (M<List<int>>()) materializes through the split-'>>' close" {
    actual := RunAst("enum E {\n    A = M<List<int>>()\n}\n")
    innerArgs := new List<TypeReference>()
    innerArgs.Add(Golden.SimpleT("int", 2, 16, 19))
    typeArgs := new List<TypeReference>()
    typeArgs.Add(Golden.GenericT("List", innerArgs, 2, 11, 20))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Call(Golden.Ident("M", 2, 9), Golden.NoArgs(), typeArgs, 2, 21), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a with-expression materializes WithExpression + PropertyInitializer (Parser.cs :4524/:4533)" {
    actual := RunAst("enum E {\n    A = r with { X: 1 }\n}\n")
    props := new List<PropertyInitializer>()
    Golden.AddProp(props, "X", null, Golden.IntLit("1", 2, 21), 2, 18)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.With(Golden.Ident("r", 2, 9), props, 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a two-property with-expression keeps both PropertyInitializers in order" {
    actual := RunAst("enum E {\n    A = r with { X: 1, Y: 2 }\n}\n")
    props := new List<PropertyInitializer>()
    Golden.AddProp(props, "X", null, Golden.IntLit("1", 2, 21), 2, 18)
    Golden.AddProp(props, "Y", null, Golden.IntLit("2", 2, 27), 2, 24)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.With(Golden.Ident("r", 2, 9), props, 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a target-typed new() materializes a null Type with empty arguments (Parser.cs :5353)" {
    actual := RunAst("enum E {\n    A = new()\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.NewE(null, Golden.NoArgs(), null, null, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a target-typed new(1) materializes its constructor arguments (Parser.cs :5235)" {
    actual := RunAst("enum E {\n    A = new(1)\n}\n")
    args := new List<Argument>()
    Golden.AddArg(args, null, Golden.IntLit("1", 2, 13), ArgumentModifier.None)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.NewE(null, args, null, null, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a typed new T() materializes NewExpression anchored on 'new' (Parser.cs :5353)" {
    actual := RunAst("enum E {\n    A = new T()\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.NewE(Golden.SimpleT("T", 2, 13, 14), Golden.NoArgs(), null, null, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a typed new T(1, 2) materializes both constructor arguments (Parser.cs :5262)" {
    actual := RunAst("enum E {\n    A = new T(1, 2)\n}\n")
    args := new List<Argument>()
    Golden.AddArg(args, null, Golden.IntLit("1", 2, 15), ArgumentModifier.None)
    Golden.AddArg(args, null, Golden.IntLit("2", 2, 18), ArgumentModifier.None)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.NewE(Golden.SimpleT("T", 2, 13, 14), args, null, null, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a typed object initializer materializes ObjectInitializerExpression on 'new' (Parser.cs :5350)" {
    actual := RunAst("enum E {\n    A = new T { X: 1 }\n}\n")
    props := new List<PropertyInitializer>()
    Golden.AddProp(props, "X", null, Golden.IntLit("1", 2, 20), 2, 17)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.NewE(Golden.SimpleT("T", 2, 13, 14), Golden.NoArgs(), Golden.ObjInit(props, 2, 9), null, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a target-typed object initializer (new { X: 1 }) keeps Type null (Parser.cs :5237)" {
    actual := RunAst("enum E {\n    A = new { X: 1 }\n}\n")
    props := new List<PropertyInitializer>()
    Golden.AddProp(props, "X", null, Golden.IntLit("1", 2, 18), 2, 15)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.NewE(null, Golden.NoArgs(), Golden.ObjInit(props, 2, 9), null, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: an indexer initializer (new T { [0] = 1 }) materializes IndexExpression (Parser.cs :5317)" {
    actual := RunAst("enum E {\n    A = new T { [0] = 1 }\n}\n")
    props := new List<PropertyInitializer>()
    Golden.AddProp(props, null, Golden.IntLit("0", 2, 18), Golden.IntLit("1", 2, 23), 0, 0)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.NewE(Golden.SimpleT("T", 2, 13, 14), Golden.NoArgs(), Golden.ObjInit(props, 2, 9), null, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// The sized-array `new T[2]` wraps the element type in an ArrayTypeReference whose Span is the ELEMENT's span
// (Parser.cs :5253 — `{ Span = type.Span }`), and carries the length in ArrayLengthExpression (:5286).
test "016 N+1c tranche 9b: a sized array (new T[2]) materializes ArrayLengthExpression + the span-preserving array type" {
    actual := RunAst("enum E {\n    A = new T[2]\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.NewE(Golden.ArrayT(Golden.SimpleT("T", 2, 13, 14), 2, 13, 14), Golden.NoArgs(), null, Golden.IntLit("2", 2, 15), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a sized-array initializer (new T[2] { a, b }) materializes bare-value PropertyInitializers (Parser.cs :5276)" {
    actual := RunAst("enum E {\n    A = new T[2] { a, b }\n}\n")
    props := new List<PropertyInitializer>()
    Golden.AddProp(props, null, null, Golden.Ident("a", 2, 20), 0, 0)
    Golden.AddProp(props, null, null, Golden.Ident("b", 2, 23), 0, 0)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.NewE(Golden.ArrayT(Golden.SimpleT("T", 2, 13, 14), 2, 13, 14), Golden.NoArgs(), Golden.ObjInit(props, 2, 9), Golden.IntLit("2", 2, 15), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// `new T[] { a, b }` parses `T[]` as the TYPE (span through the `]`), so Parser.cs takes the COLLECTION
// initializer branch (`type is ArrayTypeReference`, :5294) — bare values, no property names. The owner now
// makes the same decision from the materialized type (the previous "does not know array-ness" approximation
// reported two spurious missing-colon NL102s here).
test "016 N+1c tranche 9b: an array-typed collection initializer (new T[] { a, b }) takes the bare-value branch (Parser.cs :5306)" {
    actual := RunAst("enum E {\n    A = new T[] { a, b }\n}\n")
    props := new List<PropertyInitializer>()
    Golden.AddProp(props, null, null, Golden.Ident("a", 2, 19), 0, 0)
    Golden.AddProp(props, null, null, Golden.Ident("b", 2, 22), 0, 0)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.NewE(Golden.ArrayT(Golden.SimpleT("T", 2, 13, 14), 2, 13, 16), Golden.NoArgs(), Golden.ObjInit(props, 2, 9), null, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a generic new (new List<int>()) materializes GenericTypeReference as the new type" {
    actual := RunAst("enum E {\n    A = new List<int>()\n}\n")
    typeArgs := new List<TypeReference>()
    typeArgs.Add(Golden.SimpleT("int", 2, 18, 21))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.NewE(Golden.GenericT("List", typeArgs, 2, 13, 22), Golden.NoArgs(), null, null, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: an empty tuple (()) materializes TupleExpression with no elements (Parser.cs :5449)" {
    actual := RunAst("enum E {\n    A = ()\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Tuple(Golden.NoTupleElems(), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: an unnamed tuple ((1, 2)) materializes null-named TupleElements (Parser.cs :5497)" {
    actual := RunAst("enum E {\n    A = (1, 2)\n}\n")
    elements := new List<TupleElement>()
    Golden.AddTupleElem(elements, null, Golden.IntLit("1", 2, 10))
    Golden.AddTupleElem(elements, null, Golden.IntLit("2", 2, 13))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Tuple(elements, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a named tuple ((a: 1, b: 2)) takes each element name from the identifier (Parser.cs :5471/:5479)" {
    actual := RunAst("enum E {\n    A = (a: 1, b: 2)\n}\n")
    elements := new List<TupleElement>()
    Golden.AddTupleElem(elements, "a", Golden.IntLit("1", 2, 13))
    Golden.AddTupleElem(elements, "b", Golden.IntLit("2", 2, 19))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Tuple(elements, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: an empty array literal ([]) materializes IsImmutable=false (Parser.cs :5436)" {
    actual := RunAst("enum E {\n    A = []\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.ArrayLit(Golden.NoExprs(), false, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: an array literal ([1, 2, 3]) materializes its elements in order" {
    actual := RunAst("enum E {\n    A = [1, 2, 3]\n}\n")
    elements := Golden.NoExprs()
    Golden.AddExpr(elements, Golden.IntLit("1", 2, 10))
    Golden.AddExpr(elements, Golden.IntLit("2", 2, 13))
    Golden.AddExpr(elements, Golden.IntLit("3", 2, 16))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.ArrayLit(elements, false, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// `immutable [1, 2]` sets IsImmutable=true and anchors the node on the `[`, NOT the `immutable` keyword.
test "016 N+1c tranche 9b: an immutable array literal sets IsImmutable=true anchored on '[' (Parser.cs :4784)" {
    actual := RunAst("enum E {\n    A = immutable [1, 2]\n}\n")
    elements := Golden.NoExprs()
    Golden.AddExpr(elements, Golden.IntLit("1", 2, 20))
    Golden.AddExpr(elements, Golden.IntLit("2", 2, 23))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.ArrayLit(elements, true, 2, 19), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: alloc new T() wraps the NewExpression in AllocExpression (Parser.cs :5196)" {
    actual := RunAst("enum E {\n    A = alloc new T()\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.AllocE(Golden.NewE(Golden.SimpleT("T", 2, 19, 20), Golden.NoArgs(), null, null, 2, 15), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: alloc [1, 2] wraps the ArrayLiteralExpression in AllocExpression (Parser.cs :5199)" {
    actual := RunAst("enum E {\n    A = alloc [1, 2]\n}\n")
    elements := Golden.NoExprs()
    Golden.AddExpr(elements, Golden.IntLit("1", 2, 16))
    Golden.AddExpr(elements, Golden.IntLit("2", 2, 19))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.AllocE(Golden.ArrayLit(elements, false, 2, 15), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: alloc x wraps the general unary operand in AllocExpression (Parser.cs :5205)" {
    actual := RunAst("enum E {\n    A = alloc x\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.AllocE(Golden.Ident("x", 2, 15), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: stackalloc byte[64] materializes ElementType + LengthExpression (Parser.cs :5217)" {
    actual := RunAst("enum E {\n    A = stackalloc byte[64]\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.StackAllocE(Golden.SimpleT("byte", 2, 20, 24), Golden.IntLit("64", 2, 25), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// Field-init consumer (the OTHER Expression-capturing site).

test "016 N+1c tranche 9b: a `:=` field materializes a call initializer (Parser.cs :1686/:4499)" {
    actual := RunAst("struct S {\n    X := F(1)\n}\n")
    args := new List<Argument>()
    Golden.AddArg(args, null, Golden.IntLit("1", 2, 12), ArgumentModifier.None)
    fields := new List<Declaration>()
    Golden.AddFieldInfer(fields, "X", Golden.Call(Golden.Ident("F", 2, 10), args, Golden.NoTypeArgs(), 2, 11), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", fields, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a typed field materializes a new-expression initializer (Parser.cs :1782/:5353)" {
    actual := RunAst("struct S {\n    X: T = new T(1)\n}\n")
    args := new List<Argument>()
    Golden.AddArg(args, null, Golden.IntLit("1", 2, 18), ArgumentModifier.None)
    fields := new List<Declaration>()
    Golden.AddFieldInit(fields, "X", Golden.SimpleT("T", 2, 8, 9), Golden.NewE(Golden.SimpleT("T", 2, 16, 17), args, null, null, 2, 12), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", fields, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a `:=` field materializes an array-literal initializer (Parser.cs :1686/:5436)" {
    actual := RunAst("struct S {\n    X := [1, 2]\n}\n")
    elements := Golden.NoExprs()
    Golden.AddExpr(elements, Golden.IntLit("1", 2, 11))
    Golden.AddExpr(elements, Golden.IntLit("2", 2, 14))
    fields := new List<Declaration>()
    Golden.AddFieldInfer(fields, "X", Golden.ArrayLit(elements, false, 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", fields, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9b: a `:=` field materializes a tuple initializer (Parser.cs :1686/:5497)" {
    actual := RunAst("struct S {\n    X := (1, 2)\n}\n")
    elements := new List<TupleElement>()
    Golden.AddTupleElem(elements, null, Golden.IntLit("1", 2, 11))
    Golden.AddTupleElem(elements, null, Golden.IntLit("2", 2, 14))
    fields := new List<Declaration>()
    Golden.AddFieldInfer(fields, "X", Golden.Tuple(elements, 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", fields, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// A WHOLE-FILE multi-member enum mixing three tranche-9b list forms (call / new-with-object-initializer /
// array literal), comma-separated, every member materializing a distinct node type.
test "016 N+1c tranche 9b: WHOLE-FILE enum mixing call, new-object-initializer, and array-literal values" {
    actual := RunAst("enum E {\n    A = F(1),\n    B = new T { X: 2 },\n    C = [1, 2]\n}\n")
    callArgs := new List<Argument>()
    Golden.AddArg(callArgs, null, Golden.IntLit("1", 2, 11), ArgumentModifier.None)
    initProps := new List<PropertyInitializer>()
    Golden.AddProp(initProps, "X", null, Golden.IntLit("2", 3, 20), 3, 17)
    arrayElements := Golden.NoExprs()
    Golden.AddExpr(arrayElements, Golden.IntLit("1", 4, 10))
    Golden.AddExpr(arrayElements, Golden.IntLit("2", 4, 13))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Call(Golden.Ident("F", 2, 9), callArgs, Golden.NoTypeArgs(), 2, 10), 2, 5)
    Golden.AddEMemV(members, "B", Golden.NewE(Golden.SimpleT("T", 3, 13, 14), Golden.NoArgs(), Golden.ObjInit(initProps, 3, 9), null, 3, 9), 3, 5)
    Golden.AddEMemV(members, "C", Golden.ArrayLit(arrayElements, false, 4, 9), 4, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// Negative self-checks — guard the new list-recursion paths against a vacuous pass (a wrong scalar, a wrong
// list LENGTH, or a wrong element name in the golden MUST surface as a non-empty Diff).
test "016 N+1c tranche 9b: AstEq surfaces a wrong Argument.Modifier (guards vacuous argument-list pass)" {
    actual := RunAst("enum E {\n    A = F(x)\n}\n")
    args := new List<Argument>()
    Golden.AddArg(args, null, Golden.Ident("x", 2, 11), ArgumentModifier.Ref)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Call(Golden.Ident("F", 2, 9), args, Golden.NoTypeArgs(), 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") != ""
}

test "016 N+1c tranche 9b: AstEq surfaces a wrong argument-list LENGTH (guards vacuous list-count pass)" {
    actual := RunAst("enum E {\n    A = F(1, 2)\n}\n")
    args := new List<Argument>()
    Golden.AddArg(args, null, Golden.IntLit("1", 2, 11), ArgumentModifier.None)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Call(Golden.Ident("F", 2, 9), args, Golden.NoTypeArgs(), 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") != ""
}

test "016 N+1c tranche 9b: AstEq surfaces a wrong TupleElement name (guards vacuous named-tuple pass)" {
    actual := RunAst("enum E {\n    A = (a: 1, b: 2)\n}\n")
    elements := new List<TupleElement>()
    Golden.AddTupleElem(elements, "a", Golden.IntLit("1", 2, 13))
    Golden.AddTupleElem(elements, "WRONG", Golden.IntLit("2", 2, 19))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Tuple(elements, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") != ""
}

test "016 N+1c tranche 9b: AstEq surfaces a wrong IsImmutable flag (guards vacuous array-literal pass)" {
    actual := RunAst("enum E {\n    A = [1]\n}\n")
    elements := Golden.NoExprs()
    Golden.AddExpr(elements, Golden.IntLit("1", 2, 10))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.ArrayLit(elements, true, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") != ""
}

// ---- N+1c tranche 9c: MATCH/PATTERNS, INTERPOLATED STRINGS, and LAMBDA literals materialize ----
// The last expression families. Every Line/Column + Span was transcribed from the LIVE Parser.cs AstToJson
// oracle (the throwaway fresh-Compiler probe diffed live Parser.cs against the owner's ParseFileAst —
// 79/80 whole-tree MATCH; the sole non-match is the BLOCK-bodied lambda, the intended no-stub deferral).

test "016 N+1c tranche 9c: a single-parameter lambda materializes LambdaExpression + the implicit `var` parameter (Parser.cs :3686)" {
    actual := RunAst("enum E {\n    A = x => 1\n}\n")
    parameters := Golden.NoParams()
    Golden.AddLambdaParam(parameters, "x", 2, 9)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Lambda(parameters, Golden.IntLit("1", 2, 14), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: a multi-parameter lambda ((x, y) => 1) materializes both parameters (Parser.cs :5542)" {
    actual := RunAst("enum E {\n    A = (x, y) => 1\n}\n")
    parameters := Golden.NoParams()
    Golden.AddLambdaParam(parameters, "x", 2, 10)
    Golden.AddLambdaParam(parameters, "y", 2, 13)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Lambda(parameters, Golden.IntLit("1", 2, 19), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: an empty-parameter lambda (() => 1) materializes an empty Parameters list" {
    actual := RunAst("enum E {\n    A = () => 1\n}\n")
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Lambda(Golden.NoParams(), Golden.IntLit("1", 2, 15), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: a literal-pattern match materializes MatchExpression + MatchCase (Parser.cs :5404/:5415)" {
    actual := RunAst("enum E {\n    A = match x { 1 => 2 }\n}\n")
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.PLit(Golden.IntLit("1", 2, 19), 2, 19), null, Golden.IntLit("2", 2, 24))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Match(Golden.Ident("x", 2, 15), cases, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: a two-case match keeps both MatchCases in source order" {
    actual := RunAst("enum E {\n    A = match x { 1 => 2, 2 => 3 }\n}\n")
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.PLit(Golden.IntLit("1", 2, 19), 2, 19), null, Golden.IntLit("2", 2, 24))
    Golden.AddCase(cases, Golden.PLit(Golden.IntLit("2", 2, 27), 2, 27), null, Golden.IntLit("3", 2, 32))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Match(Golden.Ident("x", 2, 15), cases, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: an identifier pattern materializes IdentifierPattern (Parser.cs :3448)" {
    actual := RunAst("enum E {\n    A = match x { y => 2 }\n}\n")
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.PIdent("y", 2, 19), null, Golden.IntLit("2", 2, 24))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Match(Golden.Ident("x", 2, 15), cases, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// The TypePattern's SimpleTypeReference carries NO source position (Parser.cs :3444 uses the ctor defaults).
test "016 N+1c tranche 9c: a type pattern (int n) materializes TypePattern with a position-free type (Parser.cs :3444)" {
    actual := RunAst("enum E {\n    A = match x { int n => 2 }\n}\n")
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.PType(Golden.BareT("int"), "n", 2, 19), null, Golden.IntLit("2", 2, 28))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Match(Golden.Ident("x", 2, 15), cases, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: a qualified-name pattern (A.B) joins the segments with dots (Parser.cs :3417)" {
    actual := RunAst("enum E {\n    A = match x { A.B => 2 }\n}\n")
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.PIdent("A.B", 2, 19), null, Golden.IntLit("2", 2, 26))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Match(Golden.Ident("x", 2, 15), cases, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: a guarded case (when b > 1) materializes MatchCase.Guard (Parser.cs :5389)" {
    actual := RunAst("enum E {\n    A = match x { y when b > 1 => 2 }\n}\n")
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.PIdent("y", 2, 19), Golden.Bin(Golden.Ident("b", 2, 26), BinaryOperator.Greater, Golden.IntLit("1", 2, 30), 2, 28), Golden.IntLit("2", 2, 35))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Match(Golden.Ident("x", 2, 15), cases, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: an or-pattern (1 or 2) materializes OrPattern anchored on 'or' (Parser.cs :3290)" {
    actual := RunAst("enum E {\n    A = match x { 1 or 2 => 3 }\n}\n")
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.POr(Golden.PLit(Golden.IntLit("1", 2, 19), 2, 19), Golden.PLit(Golden.IntLit("2", 2, 24), 2, 24), 2, 21), null, Golden.IntLit("3", 2, 29))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Match(Golden.Ident("x", 2, 15), cases, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: an and-pattern (a and b) materializes AndPattern anchored on 'and' (Parser.cs :3306)" {
    actual := RunAst("enum E {\n    A = match x { a and b => 3 }\n}\n")
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.PAnd(Golden.PIdent("a", 2, 19), Golden.PIdent("b", 2, 25), 2, 21), null, Golden.IntLit("3", 2, 30))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Match(Golden.Ident("x", 2, 15), cases, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: a not-pattern (not a) materializes NotPattern anchored on 'not' (Parser.cs :3320)" {
    actual := RunAst("enum E {\n    A = match x { not a => 3 }\n}\n")
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.PNot(Golden.PIdent("a", 2, 23), 2, 19), null, Golden.IntLit("3", 2, 28))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Match(Golden.Ident("x", 2, 15), cases, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// The relational pattern's Operator is the RAW token text (`>`), not an enum (Parser.cs :3340).
test "016 N+1c tranche 9c: a relational pattern (> 5) materializes the raw operator text (Parser.cs :3340)" {
    actual := RunAst("enum E {\n    A = match x { > 5 => 3 }\n}\n")
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.PRel(">", Golden.IntLit("5", 2, 21), 2, 19), null, Golden.IntLit("3", 2, 26))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Match(Golden.Ident("x", 2, 15), cases, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: a list pattern ([1, 2]) materializes ListPattern (Parser.cs :3383)" {
    actual := RunAst("enum E {\n    A = match x { [1, 2] => 3 }\n}\n")
    elements := Golden.NoPatterns()
    Golden.AddPattern(elements, Golden.PLit(Golden.IntLit("1", 2, 20), 2, 20))
    Golden.AddPattern(elements, Golden.PLit(Golden.IntLit("2", 2, 23), 2, 23))
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.PList(elements, 2, 19), null, Golden.IntLit("3", 2, 29))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Match(Golden.Ident("x", 2, 15), cases, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// A SlicePattern is anchored on the PRIMARY-PATTERN entry position (the `[`), not on its own `..` token
// (Parser.cs :3373 reuses the enclosing `line`/`column`).
test "016 N+1c tranche 9c: a slice pattern ([1, .. rest]) anchors on the '[' and keeps the binding name (Parser.cs :3373)" {
    actual := RunAst("enum E {\n    A = match x { [1, .. rest] => 3 }\n}\n")
    elements := Golden.NoPatterns()
    Golden.AddPattern(elements, Golden.PLit(Golden.IntLit("1", 2, 20), 2, 20))
    Golden.AddPattern(elements, Golden.PSlice("rest", 2, 19))
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.PList(elements, 2, 19), null, Golden.IntLit("3", 2, 35))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Match(Golden.Ident("x", 2, 15), cases, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: a positional pattern ((1, 2)) materializes PositionalPattern (Parser.cs :3401)" {
    actual := RunAst("enum E {\n    A = match x { (1, 2) => 3 }\n}\n")
    elements := Golden.NoPatterns()
    Golden.AddPattern(elements, Golden.PLit(Golden.IntLit("1", 2, 20), 2, 20))
    Golden.AddPattern(elements, Golden.PLit(Golden.IntLit("2", 2, 23), 2, 23))
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.PPos(elements, 2, 19), null, Golden.IntLit("3", 2, 29))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Match(Golden.Ident("x", 2, 15), cases, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: an object pattern ({ N: 1 }) materializes ObjectPattern + PropertyPattern (Parser.cs :3416/:3487)" {
    actual := RunAst("enum E {\n    A = match x { { N: 1 } => 3 }\n}\n")
    props := Golden.NoPatProps()
    Golden.AddPatProp(props, "N", Golden.PLit(Golden.IntLit("1", 2, 24), 2, 24), null, 2, 21)
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.PObj(props, 2, 19), null, Golden.IntLit("3", 2, 31))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Match(Golden.Ident("x", 2, 15), cases, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: an implicit-binding property pattern ({ N }) leaves Pattern null (Parser.cs :3494)" {
    actual := RunAst("enum E {\n    A = match x { { N } => 3 }\n}\n")
    props := Golden.NoPatProps()
    Golden.AddPatProp(props, "N", null, null, 2, 21)
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.PObj(props, 2, 19), null, Golden.IntLit("3", 2, 28))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Match(Golden.Ident("x", 2, 15), cases, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: a union-case pattern (Some { N: 1 }) materializes UnionCasePattern (Parser.cs :3435)" {
    actual := RunAst("enum E {\n    A = match x { Some { N: 1 } => 3 }\n}\n")
    props := Golden.NoPatProps()
    Golden.AddPatProp(props, "N", Golden.PLit(Golden.IntLit("1", 2, 29), 2, 29), null, 2, 26)
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.PUnion("Some", props, 2, 19), null, Golden.IntLit("3", 2, 36))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Match(Golden.Ident("x", 2, 15), cases, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: a single-hole interpolated string materializes InterpolatedStringHole (Parser.cs :5163/:5183)" {
    actual := RunAst("enum E {\n    A = $\"{x}\"\n}\n")
    parts := Golden.NoParts()
    Golden.AddHole(parts, Golden.Ident("x", 2, 12), null, 2, 11)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Interp(parts, false, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: text around a hole ($\"ab{x}cd\") emits text/hole/text parts (Parser.cs :4988)" {
    actual := RunAst("enum E {\n    A = $\"ab{x}cd\"\n}\n")
    parts := Golden.NoParts()
    Golden.AddText(parts, "ab", 2, 11)
    Golden.AddHole(parts, Golden.Ident("x", 2, 14), null, 2, 13)
    Golden.AddText(parts, "cd", 2, 16)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Interp(parts, false, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: a hole-free interpolated string emits a single text part (Parser.cs :5180)" {
    actual := RunAst("enum E {\n    A = $\"abc\"\n}\n")
    parts := Golden.NoParts()
    Golden.AddText(parts, "abc", 2, 11)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Interp(parts, false, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: two holes with separating text keep part order and positions" {
    actual := RunAst("enum E {\n    A = $\"{x}-{y}\"\n}\n")
    parts := Golden.NoParts()
    Golden.AddHole(parts, Golden.Ident("x", 2, 12), null, 2, 11)
    Golden.AddText(parts, "-", 2, 14)
    Golden.AddHole(parts, Golden.Ident("y", 2, 16), null, 2, 15)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Interp(parts, false, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: a format specifier ($\"{x:F2}\") lands in InterpolatedStringHole.FormatClause (Parser.cs :5129)" {
    actual := RunAst("enum E {\n    A = $\"{x:F2}\"\n}\n")
    parts := Golden.NoParts()
    Golden.AddHole(parts, Golden.Ident("x", 2, 12), "F2", 2, 11)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Interp(parts, false, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// `{{` / `}}` each append ONE brace to the text run while advancing TWO source columns (Parser.cs :4997/:5007).
test "016 N+1c tranche 9c: brace escapes ($\"{{x}}\") collapse to a single literal text part" {
    actual := RunAst("enum E {\n    A = $\"{{x}}\"\n}\n")
    parts := Golden.NoParts()
    Golden.AddText(parts, "{x}", 2, 11)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Interp(parts, false, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: a composed hole expression ($\"{a + b}\") sub-parses into a BinaryExpression" {
    actual := RunAst("enum E {\n    A = $\"{a + b}\"\n}\n")
    parts := Golden.NoParts()
    Golden.AddHole(parts, Golden.Bin(Golden.Ident("a", 2, 12), BinaryOperator.Add, Golden.Ident("b", 2, 16), 2, 14), null, 2, 11)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Interp(parts, false, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// Field-init consumer.

test "016 N+1c tranche 9c: a `:=` field materializes a lambda initializer (Parser.cs :1686/:3686)" {
    actual := RunAst("struct S {\n    X := x => 1\n}\n")
    parameters := Golden.NoParams()
    Golden.AddLambdaParam(parameters, "x", 2, 10)
    fields := new List<Declaration>()
    Golden.AddFieldInfer(fields, "X", Golden.Lambda(parameters, Golden.IntLit("1", 2, 15), 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", fields, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: a `:=` field materializes a match initializer (Parser.cs :1686/:5415)" {
    actual := RunAst("struct S {\n    X := match a { 1 => 2 }\n}\n")
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.PLit(Golden.IntLit("1", 2, 20), 2, 20), null, Golden.IntLit("2", 2, 25))
    fields := new List<Declaration>()
    Golden.AddFieldInfer(fields, "X", Golden.Match(Golden.Ident("a", 2, 16), cases, 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", fields, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 9c: a `:=` field materializes an interpolated-string initializer (Parser.cs :1686/:5183)" {
    actual := RunAst("struct S {\n    X := $\"v{a}\"\n}\n")
    parts := Golden.NoParts()
    Golden.AddText(parts, "v", 2, 12)
    Golden.AddHole(parts, Golden.Ident("a", 2, 14), null, 2, 13)
    fields := new List<Declaration>()
    Golden.AddFieldInfer(fields, "X", Golden.Interp(parts, false, 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddStructM(decls, "S", fields, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// Negative self-checks for the tranche-9c recursion paths.
test "016 N+1c tranche 9c: AstEq surfaces a wrong Pattern node TYPE (Identifier golden vs Literal actual)" {
    actual := RunAst("enum E {\n    A = match x { 1 => 2 }\n}\n")
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.PIdent("1", 2, 19), null, Golden.IntLit("2", 2, 24))
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Match(Golden.Ident("x", 2, 15), cases, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") != ""
}

test "016 N+1c tranche 9c: AstEq surfaces a wrong interpolated TEXT run (guards vacuous part-list pass)" {
    actual := RunAst("enum E {\n    A = $\"ab{x}\"\n}\n")
    parts := Golden.NoParts()
    Golden.AddText(parts, "WRONG", 2, 11)
    Golden.AddHole(parts, Golden.Ident("x", 2, 14), null, 2, 13)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Interp(parts, false, 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") != ""
}

test "016 N+1c tranche 9c: AstEq surfaces a wrong lambda parameter name (guards vacuous parameter-list pass)" {
    actual := RunAst("enum E {\n    A = x => 1\n}\n")
    parameters := Golden.NoParams()
    Golden.AddLambdaParam(parameters, "WRONG", 2, 9)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.Lambda(parameters, Golden.IntLit("1", 2, 14), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") != ""
}
