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
        // N+1c tranche 10 (STATEMENT BODIES): the whole Statement node family plus the two non-Statement
        // list ELEMENTS (CatchClause carries NO Line/Column at all; SwitchCase carries its own two fields
        // rather than an AstNode base). Scalars (Kind / VariableName / Directive / Effects / Reason /
        // Owner / Names) compare by value; every node/list field recurses. OnSubscriptionExpression is an
        // EXPRESSION but lands here — it is only reachable once a block-bodied lambda materializes.
        if typeName == "BlockStatement" {
            return Names("Statements Line Column")
        }
        if typeName == "ExpressionStatement" {
            return Names("Expression Line Column")
        }
        if typeName == "VariableDeclarationStatement" {
            return Names("Name Type Initializer Kind Line Column")
        }
        if typeName == "TupleDeconstructionStatement" {
            return Names("Names Initializer Kind Line Column")
        }
        if typeName == "EmptyStatement" {
            return Names("Line Column")
        }
        if typeName == "IfStatement" {
            return Names("Condition ThenStatement ElseStatement Line Column")
        }
        if typeName == "WhileStatement" {
            return Names("Condition Body Line Column")
        }
        if typeName == "ForStatement" {
            return Names("Initializer Condition Iterator Body Line Column")
        }
        if typeName == "ForeachStatement" {
            return Names("VariableName Collection Body Line Column")
        }
        if typeName == "AwaitForEachStatement" {
            return Names("VariableName Collection Body Line Column")
        }
        if typeName == "ReturnStatement" {
            return Names("Value Line Column")
        }
        if typeName == "YieldStatement" {
            return Names("Value Line Column")
        }
        if typeName == "BreakStatement" {
            return Names("Line Column")
        }
        if typeName == "ContinueStatement" {
            return Names("Line Column")
        }
        if typeName == "ThrowStatement" {
            return Names("Expression Line Column")
        }
        if typeName == "PrintStatement" {
            return Names("Value Line Column")
        }
        if typeName == "PreprocessorDirective" {
            return Names("Directive Line Column")
        }
        if typeName == "OffStatement" {
            return Names("Handle Line Column")
        }
        if typeName == "TryStatement" {
            return Names("TryBlock CatchClauses FinallyBlock Line Column")
        }
        if typeName == "CatchClause" {
            return Names("ExceptionType VariableName Block")
        }
        if typeName == "UsingStatement" {
            return Names("Declaration Expression Body Line Column")
        }
        if typeName == "LockStatement" {
            return Names("LockObject Body Line Column")
        }
        if typeName == "SwitchStatement" {
            return Names("Value Cases Line Column")
        }
        if typeName == "SwitchCase" {
            return Names("Pattern Statements Line Column")
        }
        if typeName == "UnsafeBlockStatement" {
            return Names("Body Line Column")
        }
        if typeName == "AllocBlockStatement" {
            return Names("Body Line Column")
        }
        if typeName == "AllowStatement" {
            return Names("Effects Reason Owner Body Line Column")
        }
        if typeName == "AssertStatement" {
            return Names("Condition Message Line Column")
        }
        if typeName == "AssertThrowsStatement" {
            return Names("ExceptionType Body Line Column")
        }
        if typeName == "OnSubscriptionExpression" {
            return Names("Target Handler Line Column")
        }
        // N+1c tranche 10b (the member-BODY CONSUMERS): the declaration nodes the statement family unlocks.
        // FunctionDeclaration registers its two SourceSpan fields (compared by value) and ReturnLifetime,
        // which Parser.cs sets through an object initializer AFTER construction. GenericConstraint carries no
        // Line/Column. TestDeclaration's TableCases is a list-of-lists — DiffValue recurses through both
        // levels. PreprocessorDeclaration is the top-level/member DECLARATION form (distinct from the
        // PreprocessorDirective STATEMENT above).
        if typeName == "FunctionDeclaration" {
            return Names("Name Parameters ReturnType Body ExpressionBody TypeParameters Constraints Modifiers Attributes IsOperatorOverload OperatorSymbol IsConversionOperator IsImplicitConversion OperatorKeywordSpan OperatorSymbolSpan ReturnLifetime Line Column")
        }
        if typeName == "GenericConstraint" {
            return Names("TypeParameter Constraints SpecialConstraints")
        }
        if typeName == "ConstructorDeclaration" {
            return Names("Parameters Body Initializer Modifiers Attributes Line Column")
        }
        if typeName == "PropertyDeclaration" {
            return Names("Name Type GetBody SetBody ExpressionBody Modifiers PropertyModifier Attributes Line Column")
        }
        if typeName == "IndexerDeclaration" {
            return Names("Parameters Type GetBody SetBody Modifiers Attributes Line Column")
        }
        if typeName == "LocalFunctionStatement" {
            return Names("Function Line Column")
        }
        if typeName == "TestDeclaration" {
            return Names("Description Body TableParameters TableCases SkipReason Line Column")
        }
        if typeName == "SetupDeclaration" {
            return Names("Body Line Column")
        }
        if typeName == "TeardownDeclaration" {
            return Names("Body Line Column")
        }
        if typeName == "PreprocessorDeclaration" {
            return Names("Directive Line Column")
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
    return ColumnarParserRecovery.ParseFileAst(source, "a.nl").CompilationUnit
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

    // ---- N+1c tranche 10: the STATEMENT node family ----
    // Every position below is transcribed from the LIVE Parser.cs AstToJson oracle over the identical
    // source, so `owner == golden` proves `owner == Parser.cs`.

    public static func NoStmts(): List<Statement> {
        return new List<Statement>()
    }

    public static func Add(statements: List<Statement>, statement: Statement) {
        statements.Add(statement)
    }

    public static func Block(statements: List<Statement>, line: int, column: int): BlockStatement {
        return new BlockStatement(statements, line, column)
    }

    // The single-statement block shorthand (the common shape in these contracts).
    public static func Block1(statement: Statement, line: int, column: int): BlockStatement {
        statements := new List<Statement>()
        statements.Add(statement)
        return new BlockStatement(statements, line, column)
    }

    public static func ExprStmt(expression: Expression, line: int, column: int): Statement {
        return new ExpressionStatement(expression, line, column)
    }

    public static func VarDecl(name: string, declaredType: TypeReference?, initializer: Expression?, kind: VariableKind, line: int, column: int): VariableDeclarationStatement {
        return new VariableDeclarationStatement(name, declaredType, initializer, kind, line, column)
    }

    public static func NoNames(): List<string> {
        return new List<string>()
    }

    public static func AddName(names: List<string>, name: string) {
        names.Add(name)
    }

    public static func TupleDecl(names: List<string>, initializer: Expression, kind: VariableKind, line: int, column: int): Statement {
        return new TupleDeconstructionStatement(names, initializer, kind, line, column)
    }

    public static func Empty(line: int, column: int): Statement {
        return new EmptyStatement(line, column)
    }

    public static func If(condition: Expression, thenStatement: Statement, elseStatement: Statement?, line: int, column: int): Statement {
        return new IfStatement(condition, thenStatement, elseStatement, line, column)
    }

    public static func While(condition: Expression, body: Statement, line: int, column: int): Statement {
        return new WhileStatement(condition, body, line, column)
    }

    public static func For(initializer: Statement?, condition: Expression?, iterator: Expression?, body: Statement, line: int, column: int): Statement {
        return new ForStatement(initializer, condition, iterator, body, line, column)
    }

    public static func Foreach(variableName: string, collection: Expression, body: Statement, line: int, column: int): Statement {
        return new ForeachStatement(variableName, collection, body, line, column)
    }

    public static func AwaitForeach(variableName: string, collection: Expression, body: Statement, line: int, column: int): Statement {
        return new AwaitForEachStatement(variableName, collection, body, line, column)
    }

    public static func Return(value: Expression?, line: int, column: int): Statement {
        return new ReturnStatement(value, line, column)
    }

    public static func Yield(value: Expression?, line: int, column: int): Statement {
        return new YieldStatement(value, line, column)
    }

    public static func Break(line: int, column: int): Statement {
        return new BreakStatement(line, column)
    }

    public static func Continue(line: int, column: int): Statement {
        return new ContinueStatement(line, column)
    }

    public static func ThrowStmt(expression: Expression, line: int, column: int): Statement {
        return new ThrowStatement(expression, line, column)
    }

    public static func Print(value: Expression, line: int, column: int): Statement {
        return new PrintStatement(value, line, column)
    }

    public static func Preproc(directive: string, line: int, column: int): Statement {
        return new PreprocessorDirective(directive, line, column)
    }

    public static func Off(handle: Expression, line: int, column: int): Statement {
        return new OffStatement(handle, line, column)
    }

    public static func NoCatches(): List<CatchClause> {
        return new List<CatchClause>()
    }

    public static func AddCatch(catches: List<CatchClause>, exceptionType: TypeReference?, variableName: string?, block: BlockStatement) {
        catches.Add(new CatchClause(exceptionType, variableName, block))
    }

    public static func Try(tryBlock: BlockStatement, catches: List<CatchClause>, finallyBlock: BlockStatement?, line: int, column: int): Statement {
        return new TryStatement(tryBlock, catches, finallyBlock, line, column)
    }

    public static func Using(declaration: VariableDeclarationStatement?, expression: Expression?, body: Statement?, line: int, column: int): Statement {
        return new UsingStatement(declaration, expression, body, line, column)
    }

    public static func Lock(lockObject: Expression, body: BlockStatement, line: int, column: int): Statement {
        return new LockStatement(lockObject, body, line, column)
    }

    public static func NoSwitchCases(): List<SwitchCase> {
        return new List<SwitchCase>()
    }

    public static func AddSwitchCase(cases: List<SwitchCase>, pattern: Pattern?, statements: List<Statement>, line: int, column: int) {
        cases.Add(new SwitchCase(pattern, statements, line, column))
    }

    public static func Switch(value: Expression, cases: List<SwitchCase>, line: int, column: int): Statement {
        return new SwitchStatement(value, cases, line, column)
    }

    public static func UnsafeBlock(body: BlockStatement, line: int, column: int): Statement {
        return new UnsafeBlockStatement(body, line, column)
    }

    public static func AllocBlock(body: BlockStatement, line: int, column: int): Statement {
        return new AllocBlockStatement(body, line, column)
    }

    public static func Allow(effects: List<string>, reason: string?, owner: string?, body: BlockStatement, line: int, column: int): Statement {
        return new AllowStatement(effects, reason, owner, body, line, column)
    }

    public static func Assert(condition: Expression, message: Expression?, line: int, column: int): Statement {
        return new AssertStatement(condition, message, line, column)
    }

    public static func AssertThrows(exceptionType: TypeReference, body: BlockStatement, line: int, column: int): Statement {
        return new AssertThrowsStatement(exceptionType, body, line, column)
    }

    public static func BlockLambda(parameters: List<Parameter>, body: BlockStatement, line: int, column: int): LambdaExpression {
        return new LambdaExpression(parameters, null, body, line, column)
    }

    public static func OnSub(target: Expression, handler: LambdaExpression, line: int, column: int): Expression {
        return new OnSubscriptionExpression(target, handler, line, column)
    }

    // ---- N+1c tranche 10b: the member-BODY declaration builders ----
    // FunctionDeclaration is FULLY QUALIFIED (a local test-helper `class FunctionDeclaration` collides on
    // the simple name under the tests-enabled build, the established tranche-2 idiom).

    public static func Func(name: string, parameters: List<Parameter>, returnType: TypeReference?, body: BlockStatement?, expressionBody: Expression?, typeParameters: List<TypeParameter>?, constraints: List<GenericConstraint>?, modifiers: Modifiers, line: int, column: int): NSharpLang.Compiler.Ast.FunctionDeclaration {
        return new NSharpLang.Compiler.Ast.FunctionDeclaration(name, parameters, returnType, body, expressionBody, typeParameters, constraints, modifiers, new List<AttributeNode>(), false, null, false, false, line, column)
    }

    // The operator-overload / conversion-operator variant, whose two SourceSpan fields Parser.cs sets
    // through an object initializer after construction (:505-506).
    public static func OperatorFunc(name: string, parameters: List<Parameter>, returnType: TypeReference?, body: BlockStatement?, operatorSymbol: string?, keywordSpan: SourceSpan, symbolSpan: SourceSpan, line: int, column: int): NSharpLang.Compiler.Ast.FunctionDeclaration {
        node := new NSharpLang.Compiler.Ast.FunctionDeclaration(name, parameters, returnType, body, null, null, null, Modifiers.None, new List<AttributeNode>(), true, operatorSymbol, false, false, line, column)
        node.OperatorKeywordSpan = keywordSpan
        node.OperatorSymbolSpan = symbolSpan
        return node
    }

    public static func AddFunc(target: List<Declaration>, node: NSharpLang.Compiler.Ast.FunctionDeclaration) {
        target.Add(node)
    }

    public static func NoConstraints(): List<GenericConstraint>? {
        return null
    }

    public static func Constraints1(typeParameter: string, constraintTypes: List<TypeReference>, special: SpecialConstraintKind): List<GenericConstraint> {
        list := new List<GenericConstraint>()
        list.Add(new GenericConstraint(typeParameter, constraintTypes, special))
        return list
    }

    public static func NoTypeRefs(): List<TypeReference> {
        return new List<TypeReference>()
    }

    public static func AddCtor(members: List<Declaration>, parameters: List<Parameter>, body: BlockStatement, initializer: Expression?, line: int, column: int) {
        members.Add(new ConstructorDeclaration(parameters, body, initializer, Modifiers.None, new List<AttributeNode>(), line, column))
    }

    public static func AddProp(members: List<Declaration>, name: string, propertyType: TypeReference, getBody: BlockStatement?, setBody: BlockStatement?, expressionBody: Expression?, modifiers: Modifiers, propertyModifier: PropertyModifier, line: int, column: int) {
        members.Add(new PropertyDeclaration(name, propertyType, getBody, setBody, expressionBody, modifiers, propertyModifier, new List<AttributeNode>(), line, column))
    }

    public static func AddIndexer(members: List<Declaration>, parameters: List<Parameter>, indexerType: TypeReference, getBody: BlockStatement?, setBody: BlockStatement?, line: int, column: int) {
        members.Add(new IndexerDeclaration(parameters, indexerType, getBody, setBody, Modifiers.None, new List<AttributeNode>(), line, column))
    }

    public static func LocalFunc(node: NSharpLang.Compiler.Ast.FunctionDeclaration, line: int, column: int): Statement {
        return new LocalFunctionStatement(node, line, column)
    }

    public static func AddTest(decls: List<Declaration>, description: string, body: BlockStatement, tableParameters: List<Parameter>?, tableCases: List<List<Expression> >?, skipReason: string?, line: int, column: int) {
        decls.Add(new TestDeclaration(description, body, tableParameters, tableCases, skipReason, line, column))
    }

    public static func NoTableParams(): List<Parameter>? {
        return null
    }

    public static func NoTable(): List<List<Expression> >? {
        return null
    }

    public static func Rows1(first: Expression, second: Expression): List<List<Expression> > {
        rows := new List<List<Expression> >()
        firstRow := new List<Expression>()
        firstRow.Add(first)
        rows.Add(firstRow)
        secondRow := new List<Expression>()
        secondRow.Add(second)
        rows.Add(secondRow)
        return rows
    }

    public static func AddSetup(decls: List<Declaration>, body: BlockStatement, line: int, column: int) {
        decls.Add(new SetupDeclaration(body, line, column))
    }

    public static func AddTeardown(decls: List<Declaration>, body: BlockStatement, line: int, column: int) {
        decls.Add(new TeardownDeclaration(body, line, column))
    }

    public static func AddPreproc(decls: List<Declaration>, directive: string, line: int, column: int) {
        decls.Add(new PreprocessorDeclaration(directive, line, column))
    }

    public static func Param(name: string, paramType: TypeReference, defaultValue: Expression?, isThis: bool, modifier: ParameterModifier, line: int, column: int): Parameter {
        return new Parameter(name, paramType, defaultValue, isThis, modifier, null, line, column, false, null)
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

// tranche 10b RETIRES the tranche-4 "default value DECLINES" gate: ParseParameterListRecovery now models
// Parser.cs's FULL parameter grammar (params/ref/out modifier, `this`, scoped/lifetime, DEFAULT value) and
// materializes `new Parameter(name, type, defaultValue, isThis, modifier, attributes, line, column,
// isScoped, lifetime)` (Parser.cs :822).
test "016 N+1c tranche 10: a parameter with a DEFAULT value now materializes Parameter.DefaultValue (Parser.cs :822)" {
    actual := RunAst("record R(x: int = 5) {}\n")
    paramList := Golden.NoParams()
    paramList.Add(new Parameter("x", Golden.SimpleT("int", 1, 13, 16), Golden.IntLit("5", 1, 19), false, ParameterModifier.None, null, 1, 10, false, null))
    decls := new List<Declaration>()
    Golden.AddRecordParams(decls, "R", paramList, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
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

// N+1c tranche 10 RETIRES the tranche-9c block-bodied-lambda decline: the enum-member vehicle now
// materializes `new LambdaExpression(parameters, null, blockBody, line, column)` (Parser.cs :3675) over a
// real BlockStatement, so the LAST expression-side decline is gone.
test "016 N+1c tranche 10: a BLOCK-bodied lambda materializes LambdaExpression.BlockBody (retires the tranche-9c decline)" {
    actual := RunAst("enum E {\n    A = x => { }\n}\n")
    parameters := Golden.NoParams()
    Golden.AddLambdaParam(parameters, "x", 2, 9)
    members := new List<EnumMember>()
    Golden.AddEMemV(members, "A", Golden.BlockLambda(parameters, Golden.Block(Golden.NoStmts(), 2, 14), 2, 9), 2, 5)
    decls := new List<Declaration>()
    Golden.AddEnumM(decls, "E", members, EnumType.Int, Modifiers.None, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
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

// ---- N+1c tranche 10a: STATEMENT BODIES — BlockStatement + the Statement node family ----
// VEHICLE: the block-bodied LAMBDA in a `:=` field initializer —
//     class C {
//         f := x => { <statement> }
//     }
// which the tranche-9c field-initializer consumer already materializes, so a BlockStatement is
// observable from `ParseFileAst` before the member-BODY consumers land (tranche 10b). The vehicle
// itself is the tranche-10 unlock: a block-bodied lambda used to DECLINE (the last expression-side
// decline recorded at the end of tranche 9c) and now materializes
// `new LambdaExpression(parameters, null, blockBody, line, column)` (Parser.cs :3675).
// Every position below is transcribed from the LIVE Parser.cs AstToJson oracle over the identical
// source (owner == golden by these contracts; golden == Parser.cs by the oracle), and every shape was
// additionally diffed owner-vs-live whole-tree through the same serializer.

// The vehicle's fixed anchors: `f` at 2:5, the lambda + its `x` parameter at 2:10, the block's `{` at
// 2:15, and the contained statement starting at 2:17.
func RunBody(inner: string): CompilationUnit {
    return RunAst("class C {\n    f := x => { " + inner + " }\n}\n")
}

func BodyUnit(statements: List<Statement>): CompilationUnit {
    parameters := Golden.NoParams()
    Golden.AddLambdaParam(parameters, "x", 2, 10)
    members := new List<Declaration>()
    Golden.AddFieldInfer(members, "f", Golden.BlockLambda(parameters, Golden.Block(statements, 2, 15), 2, 10), 2, 5)
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    return Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
}

func BodyUnit1(statement: Statement): CompilationUnit {
    statements := Golden.NoStmts()
    Golden.Add(statements, statement)
    return BodyUnit(statements)
}

// A `name()` call-expression statement, the filler used inside nested blocks below.
func CallStmt(name: string, line: int, column: int): Statement {
    return Golden.ExprStmt(Golden.Call(Golden.Ident(name, line, column), Golden.NoArgs(), Golden.NoTypeArgs(), line, column + 1), line, column)
}

test "016 N+1c tranche 10: an empty block-bodied lambda materializes an empty BlockStatement (Parser.cs :2227/:3675)" {
    actual := RunAst("class C {\n    f := x => { }\n}\n")
    expected := BodyUnit(Golden.NoStmts())
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `return 1` materializes ReturnStatement with its value (Parser.cs :2844)" {
    actual := RunBody("return 1")
    expected := BodyUnit1(Golden.Return(Golden.IntLit("1", 2, 24), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a bare `return` materializes a NULL ReturnStatement value" {
    actual := RunBody("return")
    expected := BodyUnit1(Golden.Return(null, 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `let a := 1` materializes VariableDeclarationStatement Kind=Let anchored on the NAME (Parser.cs :2578)" {
    actual := RunBody("let a := 1")
    expected := BodyUnit1(Golden.VarDecl("a", null, Golden.IntLit("1", 2, 26), VariableKind.Let, 2, 21))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `let a: int = 1` materializes the declared TYPE with a byte-exact span (Parser.cs :2564)" {
    actual := RunBody("let a: int = 1")
    expected := BodyUnit1(Golden.VarDecl("a", Golden.SimpleT("int", 2, 24, 27), Golden.IntLit("1", 2, 30), VariableKind.Let, 2, 21))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `const a := 1` carries VariableKind.Const (Parser.cs :2250)" {
    actual := RunBody("const a := 1")
    expected := BodyUnit1(Golden.VarDecl("a", null, Golden.IntLit("1", 2, 28), VariableKind.Const, 2, 23))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `readonly a := 1` carries VariableKind.Readonly (Parser.cs :2252)" {
    actual := RunBody("readonly a := 1")
    expected := BodyUnit1(Golden.VarDecl("a", null, Golden.IntLit("1", 2, 31), VariableKind.Readonly, 2, 26))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: the `a := 1` shorthand anchors on the IDENTIFIER expression (Parser.cs :3640)" {
    actual := RunBody("a := 1")
    expected := BodyUnit1(Golden.VarDecl("a", null, Golden.IntLit("1", 2, 22), VariableKind.Let, 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: the let-less typed declaration `a: int = 1` materializes (Parser.cs :3535)" {
    actual := RunBody("a: int = 1")
    expected := BodyUnit1(Golden.VarDecl("a", Golden.SimpleT("int", 2, 20, 23), Golden.IntLit("1", 2, 26), VariableKind.Let, 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a call becomes an ExpressionStatement anchored on the STATEMENT start (Parser.cs :3643)" {
    actual := RunBody("g()")
    expected := BodyUnit1(CallStmt("g", 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: an assignment statement wraps the AssignmentExpression (Parser.cs :3643)" {
    actual := RunBody("a = 1")
    expected := BodyUnit1(Golden.ExprStmt(Golden.Assign(Golden.Ident("a", 2, 17), AssignmentOperator.Assign, Golden.IntLit("1", 2, 21), 2, 19), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a bare `;` materializes EmptyStatement (Parser.cs :2244)" {
    actual := RunBody(";")
    expected := BodyUnit1(Golden.Empty(2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `if a { b() }` materializes IfStatement with a NULL else (Parser.cs :2659)" {
    actual := RunBody("if a { b() }")
    expected := BodyUnit1(Golden.If(Golden.Ident("a", 2, 20), Golden.Block1(CallStmt("b", 2, 24), 2, 22), null, 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: an if/else materializes both branches as nested BlockStatements" {
    actual := RunBody("if a { b() } else { c() }")
    expected := BodyUnit1(Golden.If(
        Golden.Ident("a", 2, 20),
        Golden.Block1(CallStmt("b", 2, 24), 2, 22),
        Golden.Block1(CallStmt("c", 2, 37), 2, 35),
        2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `while a { b() }` materializes WhileStatement (Parser.cs :2829)" {
    actual := RunBody("while a { b() }")
    expected := BodyUnit1(Golden.While(Golden.Ident("a", 2, 23), Golden.Block1(CallStmt("b", 2, 27), 2, 25), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `for i in items` wraps a ForeachStatement in a NULL-parts ForStatement (Parser.cs :2678)" {
    actual := RunBody("for i in items { b() }")
    inner := Golden.Foreach("i", Golden.Ident("items", 2, 26), Golden.Block1(CallStmt("b", 2, 34), 2, 32), 2, 17)
    expected := BodyUnit1(Golden.For(null, null, null, inner, 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: the C-style for materializes initializer/condition/iterator (Parser.cs :2755)" {
    actual := RunBody("for i := 0; i < 3; i = i + 1 { b() }")
    initializer := Golden.VarDecl("i", null, Golden.IntLit("0", 2, 26), VariableKind.Let, 2, 21)
    condition := Golden.Bin(Golden.Ident("i", 2, 29), BinaryOperator.Less, Golden.IntLit("3", 2, 33), 2, 31)
    iterator := Golden.Assign(Golden.Ident("i", 2, 36), AssignmentOperator.Assign, Golden.Bin(Golden.Ident("i", 2, 40), BinaryOperator.Add, Golden.IntLit("1", 2, 44), 2, 42), 2, 38)
    expected := BodyUnit1(Golden.For(initializer, condition, iterator, Golden.Block1(CallStmt("b", 2, 48), 2, 46), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a `let`-initialized C-style for anchors the declaration on its name (Parser.cs :2708)" {
    actual := RunBody("for let i := 0; i < 3; i = i + 1 { b() }")
    initializer := Golden.VarDecl("i", null, Golden.IntLit("0", 2, 30), VariableKind.Let, 2, 25)
    condition := Golden.Bin(Golden.Ident("i", 2, 33), BinaryOperator.Less, Golden.IntLit("3", 2, 37), 2, 35)
    iterator := Golden.Assign(Golden.Ident("i", 2, 40), AssignmentOperator.Assign, Golden.Bin(Golden.Ident("i", 2, 44), BinaryOperator.Add, Golden.IntLit("1", 2, 48), 2, 46), 2, 42)
    expected := BodyUnit1(Golden.For(initializer, condition, iterator, Golden.Block1(CallStmt("b", 2, 52), 2, 50), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `foreach i in items` materializes a bare ForeachStatement (Parser.cs :2784)" {
    actual := RunBody("foreach i in items { b() }")
    expected := BodyUnit1(Golden.Foreach("i", Golden.Ident("items", 2, 30), Golden.Block1(CallStmt("b", 2, 38), 2, 36), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `await foreach` materializes AwaitForEachStatement anchored on `await` (Parser.cs :2814)" {
    actual := RunBody("await foreach i in items { b() }")
    expected := BodyUnit1(Golden.AwaitForeach("i", Golden.Ident("items", 2, 36), Golden.Block1(CallStmt("b", 2, 44), 2, 42), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `yield 1` materializes YieldStatement with its value (Parser.cs :2870)" {
    actual := RunBody("yield 1")
    expected := BodyUnit1(Golden.Yield(Golden.IntLit("1", 2, 23), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `yield break` materializes a NULL YieldStatement value" {
    actual := RunBody("yield break")
    expected := BodyUnit1(Golden.Yield(null, 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `break` inside a loop materializes BreakStatement (Parser.cs :2901)" {
    actual := RunBody("while a { break }")
    expected := BodyUnit1(Golden.While(Golden.Ident("a", 2, 23), Golden.Block1(Golden.Break(2, 27), 2, 25), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `continue` inside a loop materializes ContinueStatement (Parser.cs :2983)" {
    actual := RunBody("while a { continue }")
    expected := BodyUnit1(Golden.While(Golden.Ident("a", 2, 23), Golden.Block1(Golden.Continue(2, 27), 2, 25), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `throw e` materializes ThrowStatement (Parser.cs :2996)" {
    actual := RunBody("throw e")
    expected := BodyUnit1(Golden.ThrowStmt(Golden.Ident("e", 2, 23), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `print a` materializes PrintStatement (Parser.cs :2883)" {
    actual := RunBody("print a")
    expected := BodyUnit1(Golden.Print(Golden.Ident("a", 2, 23), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `(a, b) := t` materializes TupleDeconstructionStatement (Parser.cs :3625/:2637)" {
    actual := RunBody("(a, b) := t")
    names := Golden.NoNames()
    Golden.AddName(names, "a")
    Golden.AddName(names, "b")
    expected := BodyUnit1(Golden.TupleDecl(names, Golden.Ident("t", 2, 27), VariableKind.Let, 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `let (a, b) := t` anchors the deconstruction on the `(` (Parser.cs :2552)" {
    actual := RunBody("let (a, b) := t")
    names := Golden.NoNames()
    Golden.AddName(names, "a")
    Golden.AddName(names, "b")
    expected := BodyUnit1(Golden.TupleDecl(names, Golden.Ident("t", 2, 31), VariableKind.Let, 2, 21))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: the paren-free `a, b := t` deconstruction materializes (Parser.cs :3583)" {
    actual := RunBody("a, b := t")
    names := Golden.NoNames()
    Golden.AddName(names, "a")
    Golden.AddName(names, "b")
    expected := BodyUnit1(Golden.TupleDecl(names, Golden.Ident("t", 2, 25), VariableKind.Let, 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a nested bare block materializes a nested BlockStatement (Parser.cs :2295)" {
    actual := RunBody("{ a() }")
    expected := BodyUnit1(Golden.Block1(CallStmt("a", 2, 19), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: two statements keep source order in the block's Statements list" {
    actual := RunBody("a() b()")
    statements := Golden.NoStmts()
    Golden.Add(statements, CallStmt("a", 2, 17))
    Golden.Add(statements, CallStmt("b", 2, 21))
    expected := BodyUnit(statements)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- tranche 10a: the STRUCTURED statements ----

test "016 N+1c tranche 10: try/catch materializes TryStatement + a typed CatchClause (Parser.cs :3046/:3056)" {
    actual := RunBody("try { a() } catch (e: Exception) { b() }")
    catches := Golden.NoCatches()
    Golden.AddCatch(catches, Golden.SimpleT("Exception", 2, 39, 48), "e", Golden.Block1(CallStmt("b", 2, 52), 2, 50))
    expected := BodyUnit1(Golden.Try(Golden.Block1(CallStmt("a", 2, 23), 2, 21), catches, null, 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a bare `catch { }` carries a NULL exception type and variable name" {
    actual := RunBody("try { a() } catch { b() }")
    catches := Golden.NoCatches()
    Golden.AddCatch(catches, null, null, Golden.Block1(CallStmt("b", 2, 37), 2, 35))
    expected := BodyUnit1(Golden.Try(Golden.Block1(CallStmt("a", 2, 23), 2, 21), catches, null, 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: try/finally materializes an empty CatchClauses list + the finally block (Parser.cs :3053)" {
    actual := RunBody("try { a() } finally { b() }")
    expected := BodyUnit1(Golden.Try(Golden.Block1(CallStmt("a", 2, 23), 2, 21), Golden.NoCatches(), Golden.Block1(CallStmt("b", 2, 39), 2, 37), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `using let r := open() { }` materializes UsingStatement.Declaration (Parser.cs :3121)" {
    actual := RunBody("using let r := open() { a() }")
    declaration := Golden.VarDecl("r", null, Golden.Call(Golden.Ident("open", 2, 32), Golden.NoArgs(), Golden.NoTypeArgs(), 2, 36), VariableKind.Let, 2, 27)
    expected := BodyUnit1(Golden.Using(declaration, null, Golden.Block1(CallStmt("a", 2, 41), 2, 39), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `using r := open()` synthesizes the declaration on the USING keyword (Parser.cs :3109)" {
    actual := RunBody("using r := open() { a() }")
    declaration := Golden.VarDecl("r", null, Golden.Call(Golden.Ident("open", 2, 28), Golden.NoArgs(), Golden.NoTypeArgs(), 2, 32), VariableKind.Let, 2, 17)
    expected := BodyUnit1(Golden.Using(declaration, null, Golden.Block1(CallStmt("a", 2, 37), 2, 35), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `lock m { }` materializes LockStatement (Parser.cs :3178)" {
    actual := RunBody("lock m { a() }")
    expected := BodyUnit1(Golden.Lock(Golden.Ident("m", 2, 22), Golden.Block1(CallStmt("a", 2, 26), 2, 24), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a single-case switch materializes SwitchStatement + SwitchCase (Parser.cs :3250/:3271)" {
    actual := RunBody("switch v { case 1 => a() }")
    cases := Golden.NoSwitchCases()
    caseStatements := Golden.NoStmts()
    Golden.Add(caseStatements, CallStmt("a", 2, 38))
    Golden.AddSwitchCase(cases, Golden.PLit(Golden.IntLit("1", 2, 33), 2, 33), caseStatements, 2, 28)
    expected := BodyUnit1(Golden.Switch(Golden.Ident("v", 2, 24), cases, 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a BRACED case FLATTENS its block into the case statements and `default` keeps a NULL pattern (Parser.cs :3243)" {
    actual := RunBody("switch v { case 1 => { a() b() } default => c() }")
    cases := Golden.NoSwitchCases()
    bracedStatements := Golden.NoStmts()
    Golden.Add(bracedStatements, CallStmt("a", 2, 40))
    Golden.Add(bracedStatements, CallStmt("b", 2, 44))
    Golden.AddSwitchCase(cases, Golden.PLit(Golden.IntLit("1", 2, 33), 2, 33), bracedStatements, 2, 28)
    defaultStatements := Golden.NoStmts()
    Golden.Add(defaultStatements, CallStmt("c", 2, 61))
    Golden.AddSwitchCase(cases, null, defaultStatements, 2, 50)
    expected := BodyUnit1(Golden.Switch(Golden.Ident("v", 2, 24), cases, 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `unsafe { }` materializes UnsafeBlockStatement (Parser.cs :2396)" {
    actual := RunBody("unsafe { a() }")
    expected := BodyUnit1(Golden.UnsafeBlock(Golden.Block1(CallStmt("a", 2, 26), 2, 24), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `alloc { }` materializes AllocBlockStatement (Parser.cs :2318)" {
    actual := RunBody("alloc { a() }")
    expected := BodyUnit1(Golden.AllocBlock(Golden.Block1(CallStmt("a", 2, 25), 2, 23), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `allow(alloc, reason: \"why\")` strips the reason's quotes (Parser.cs :2370/:6834)" {
    actual := RunBody("allow(alloc, reason: \"why\") { a() }")
    effects := Golden.NoNames()
    Golden.AddName(effects, "alloc")
    expected := BodyUnit1(Golden.Allow(effects, "why", null, Golden.Block1(CallStmt("a", 2, 47), 2, 45), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `assert a` materializes AssertStatement with a NULL message (Parser.cs :2427)" {
    actual := RunBody("assert a")
    expected := BodyUnit1(Golden.Assert(Golden.Ident("a", 2, 24), null, 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `assert a, \"m\"` materializes the optional message expression" {
    actual := RunBody("assert a, \"m\"")
    expected := BodyUnit1(Golden.Assert(Golden.Ident("a", 2, 24), Golden.StrLit("\"m\"", 2, 27), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `assert throws T { }` materializes AssertThrowsStatement (Parser.cs :2411)" {
    actual := RunBody("assert throws Exception { a() }")
    expected := BodyUnit1(Golden.AssertThrows(Golden.SimpleT("Exception", 2, 31, 40), Golden.Block1(CallStmt("a", 2, 43), 2, 41), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `off handle` materializes OffStatement (Parser.cs :2975)" {
    actual := RunBody("off handle")
    expected := BodyUnit1(Golden.Off(Golden.Ident("handle", 2, 21), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: an `on` subscription with a BLOCK handler materializes OnSubscriptionExpression (Parser.cs :2917)" {
    actual := RunBody("s := on t.E (a, b) => { g() }")
    handlerParams := Golden.NoParams()
    Golden.AddLambdaParam(handlerParams, "a", 2, 30)
    Golden.AddLambdaParam(handlerParams, "b", 2, 33)
    handler := Golden.BlockLambda(handlerParams, Golden.Block1(CallStmt("g", 2, 41), 2, 39), 2, 29)
    target := Golden.Member(Golden.Ident("t", 2, 25), "E", false, 2, 26)
    expected := BodyUnit1(Golden.VarDecl("s", null, Golden.OnSub(target, handler, 2, 22), VariableKind.Let, 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a deeply nested loop/branch/try body nests byte-exact" {
    actual := RunBody("while a { for b in c { if d { try { e() } catch { g() } } } }")
    innerTry := Golden.NoCatches()
    Golden.AddCatch(innerTry, null, null, Golden.Block1(CallStmt("g", 2, 67), 2, 65))
    tryStatement := Golden.Try(Golden.Block1(CallStmt("e", 2, 53), 2, 51), innerTry, null, 2, 47)
    ifStatement := Golden.If(Golden.Ident("d", 2, 43), Golden.Block1(tryStatement, 2, 45), null, 2, 40)
    foreachStatement := Golden.Foreach("b", Golden.Ident("c", 2, 36), Golden.Block1(ifStatement, 2, 38), 2, 27)
    forStatement := Golden.For(null, null, null, foreachStatement, 2, 27)
    expected := BodyUnit1(Golden.While(Golden.Ident("a", 2, 23), Golden.Block1(forStatement, 2, 25), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- tranche 10a: negative self-checks (guard vacuous passes) ----

test "016 N+1c tranche 10: AstEq surfaces a wrong VariableKind (Let golden vs Const actual)" {
    actual := RunBody("const a := 1")
    expected := BodyUnit1(Golden.VarDecl("a", null, Golden.IntLit("1", 2, 28), VariableKind.Let, 2, 23))
    assert AstEq.Diff(expected, actual, "unit") != ""
}

test "016 N+1c tranche 10: AstEq surfaces a wrong statement COUNT in a block (guards vacuous list pass)" {
    actual := RunBody("a() b()")
    expected := BodyUnit1(CallStmt("a", 2, 17))
    assert AstEq.Diff(expected, actual, "unit") != ""
}

test "016 N+1c tranche 10: AstEq surfaces a swapped then/else branch" {
    actual := RunBody("if a { b() } else { c() }")
    expected := BodyUnit1(Golden.If(
        Golden.Ident("a", 2, 20),
        Golden.Block1(CallStmt("c", 2, 37), 2, 35),
        Golden.Block1(CallStmt("b", 2, 24), 2, 22),
        2, 17))
    assert AstEq.Diff(expected, actual, "unit") != ""
}

test "016 N+1c tranche 10: AstEq surfaces a wrong ForeachStatement variable name" {
    actual := RunBody("foreach i in items { b() }")
    expected := BodyUnit1(Golden.Foreach("WRONG", Golden.Ident("items", 2, 30), Golden.Block1(CallStmt("b", 2, 38), 2, 36), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") != ""
}

test "016 N+1c tranche 10: AstEq surfaces a wrong allow REASON string" {
    actual := RunBody("allow(alloc, reason: \"why\") { a() }")
    effects := Golden.NoNames()
    Golden.AddName(effects, "alloc")
    expected := BodyUnit1(Golden.Allow(effects, "WRONG", null, Golden.Block1(CallStmt("a", 2, 47), 2, 45), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") != ""
}

// ---- tranche 11: the two tranche-10 pinned DECLINES converted to POSITIVE contracts ----
// Both shapes are malformed sources where Parser.cs materializes a node carrying a synthetic
// `IdentifierExpression("<error>")` / an `<error>` effect string. Tranche 11 REPRODUCES those artifacts
// byte-exact instead of declining, so a consumer (the LSP on a file being edited) sees exactly the tree
// Parser.cs produces today. Both goldens are transcribed from the LIVE Parser.cs AstToJson oracle.

test "016 N+1c tranche 11: `using r { }` (missing ':=') materializes the synthetic <error> initializer (Parser.cs :3895/:3121)" {
    actual := RunBody("using r { a() }")
    declaration := Golden.VarDecl("r", null, Golden.Ident("<error>", 2, 26), VariableKind.Let, 2, 17)
    expected := BodyUnit1(Golden.Using(declaration, null, Golden.Block1(CallStmt("a", 2, 27), 2, 25), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: a non-effect allow value (`dispatch: virtual`) records `dispatch:<error>` (Parser.cs :2370/:6819)" {
    actual := RunBody("allow(dispatch: virtual) { a() }")
    effects := Golden.NoNames()
    Golden.AddName(effects, "dispatch:<error>")
    Golden.AddName(effects, "<error>")
    expected := BodyUnit1(Golden.Allow(effects, null, null, Golden.Block1(CallStmt("a", 2, 44), 2, 42), 2, 17))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- N+1c tranche 10b: the member-BODY CONSUMERS the statement family unlocks ----
// FUNCTION / METHOD / CONSTRUCTOR / PROPERTY / INDEXER bodies (expression-bodied via the tranche-7..9
// expression nodes, block-bodied via the tranche-10a BlockStatement), LOCAL FUNCTIONS, and the whole
// TEST-DSL declaration family (test / setup / teardown), plus the top-level PreprocessorDeclaration.
// The top-level `func` declaration now routes through the SAME full ParseFunctionDeclaration reproduction
// as the member path (retiring the Stage-3 reduced "literal-reaching vehicle"), and the parameter list
// models Parser.cs's FULL grammar (params/ref/out, `this`, scoped/lifetime, default values).
// Every position/span below is transcribed from the LIVE Parser.cs AstToJson oracle over the identical
// source, and every shape was additionally diffed owner-vs-live whole-tree through the same serializer.

test "016 N+1c tranche 10: a top-level expression-bodied func materializes FunctionDeclaration (Parser.cs :503)" {
    actual := RunAst("func add(x: int, y: int): int => x + y\n")
    parameters := Golden.NoParams()
    parameters.Add(Golden.Param("x", Golden.SimpleT("int", 1, 13, 16), null, false, ParameterModifier.None, 1, 10))
    parameters.Add(Golden.Param("y", Golden.SimpleT("int", 1, 21, 24), null, false, ParameterModifier.None, 1, 18))
    body := Golden.Bin(Golden.Ident("x", 1, 34), BinaryOperator.Add, Golden.Ident("y", 1, 38), 1, 36)
    decls := new List<Declaration>()
    Golden.AddFunc(decls, Golden.Func("add", parameters, Golden.SimpleT("int", 1, 27, 30), null, body, null, Golden.NoConstraints(), Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a top-level block-bodied func hangs a BlockStatement on FunctionDeclaration.Body" {
    actual := RunAst("func main() {\n    print 1\n}\n")
    body := Golden.Block1(Golden.Print(Golden.IntLit("1", 2, 11), 2, 5), 1, 13)
    decls := new List<Declaration>()
    Golden.AddFunc(decls, Golden.Func("main", Golden.NoParams(), null, body, null, null, Golden.NoConstraints(), Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a class METHOD materializes into Members with its block body (Parser.cs :1475/:503)" {
    actual := RunAst("class C {\n    func run(): int {\n        return 1\n    }\n}\n")
    body := Golden.Block1(Golden.Return(Golden.IntLit("1", 3, 16), 3, 9), 2, 21)
    members := new List<Declaration>()
    Golden.AddFunc(members, Golden.Func("run", Golden.NoParams(), Golden.SimpleT("int", 2, 17, 20), body, null, null, Golden.NoConstraints(), Modifiers.None, 2, 5))
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a BODY-LESS method (abstract / interface) keeps both bodies null" {
    actual := RunAst("class C {\n    func run(): int\n}\n")
    members := new List<Declaration>()
    Golden.AddFunc(members, Golden.Func("run", Golden.NoParams(), Golden.SimpleT("int", 2, 17, 20), null, null, null, Golden.NoConstraints(), Modifiers.None, 2, 5))
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a generic method materializes TypeParameters + a `where T: class` GenericConstraint (Parser.cs :928)" {
    actual := RunAst("class C {\n    func id<T>(v: T): T where T: class {\n        return v\n    }\n}\n")
    typeParams := new List<TypeParameter>()
    Golden.AddTP(typeParams, "T")
    parameters := Golden.NoParams()
    parameters.Add(Golden.Param("v", Golden.SimpleT("T", 2, 19, 20), null, false, ParameterModifier.None, 2, 16))
    body := Golden.Block1(Golden.Return(Golden.Ident("v", 3, 16), 3, 9), 2, 40)
    constraints := Golden.Constraints1("T", Golden.NoTypeRefs(), SpecialConstraintKind.Class)
    members := new List<Declaration>()
    Golden.AddFunc(members, Golden.Func("id", parameters, Golden.SimpleT("T", 2, 23, 24), body, null, typeParams, constraints, Modifiers.None, 2, 5))
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a constructor materializes ConstructorDeclaration with a NULL initializer (Parser.cs :1572)" {
    actual := RunAst("class C {\n    constructor(x: int) {\n        print x\n    }\n}\n")
    parameters := Golden.NoParams()
    parameters.Add(Golden.Param("x", Golden.SimpleT("int", 2, 20, 23), null, false, ParameterModifier.None, 2, 17))
    members := new List<Declaration>()
    Golden.AddCtor(members, parameters, Golden.Block1(Golden.Print(Golden.Ident("x", 3, 15), 3, 9), 2, 25), null, 2, 5)
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `: base(x)` materializes a CallExpression over BaseExpression anchored on `base` (Parser.cs :1536)" {
    actual := RunAst("class C {\n    constructor(x: int) : base(x) {\n    }\n}\n")
    parameters := Golden.NoParams()
    parameters.Add(Golden.Param("x", Golden.SimpleT("int", 2, 20, 23), null, false, ParameterModifier.None, 2, 17))
    args := Golden.NoArgs()
    Golden.AddArg(args, null, Golden.Ident("x", 2, 32), ArgumentModifier.None)
    initializer := Golden.Call(Golden.BaseE(2, 27), args, Golden.NoTypeArgs(), 2, 27)
    members := new List<Declaration>()
    Golden.AddCtor(members, parameters, Golden.Block(Golden.NoStmts(), 2, 35), initializer, 2, 5)
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: an expression-bodied property materializes PropertyDeclaration.ExpressionBody (Parser.cs :1698)" {
    actual := RunAst("class C {\n    Name: string => \"n\"\n}\n")
    members := new List<Declaration>()
    Golden.AddProp(members, "Name", Golden.SimpleT("string", 2, 11, 17), null, null, Golden.StrLit("\"n\"", 2, 21), Modifiers.None, PropertyModifier.None, 2, 5)
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a get/set property materializes both accessor BlockStatements (Parser.cs :1768)" {
    actual := RunAst("class C {\n    Name: string {\n        get { return v }\n        set { v = 1 }\n    }\n}\n")
    getBody := Golden.Block1(Golden.Return(Golden.Ident("v", 3, 22), 3, 15), 3, 13)
    setBody := Golden.Block1(Golden.ExprStmt(Golden.Assign(Golden.Ident("v", 4, 15), AssignmentOperator.Assign, Golden.IntLit("1", 4, 19), 4, 17), 4, 15), 4, 13)
    members := new List<Declaration>()
    Golden.AddProp(members, "Name", Golden.SimpleT("string", 2, 11, 17), getBody, setBody, null, Modifiers.None, PropertyModifier.None, 2, 5)
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: an indexer materializes IndexerDeclaration with its parameter + get body (Parser.cs :1642)" {
    actual := RunAst("class C {\n    func this[i: int]: int {\n        get { return i }\n    }\n}\n")
    parameters := Golden.NoParams()
    parameters.Add(Golden.Param("i", Golden.SimpleT("int", 2, 18, 21), null, false, ParameterModifier.None, 2, 15))
    getBody := Golden.Block1(Golden.Return(Golden.Ident("i", 3, 22), 3, 15), 3, 13)
    members := new List<Declaration>()
    Golden.AddIndexer(members, parameters, Golden.SimpleT("int", 2, 24, 27), getBody, null, 2, 5)
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a LOCAL function materializes LocalFunctionStatement over its own FunctionDeclaration (Parser.cs :2539)" {
    actual := RunAst("func outer() {\n    func inner(): int {\n        return 1\n    }\n}\n")
    innerBody := Golden.Block1(Golden.Return(Golden.IntLit("1", 3, 16), 3, 9), 2, 23)
    inner := Golden.Func("inner", Golden.NoParams(), Golden.SimpleT("int", 2, 19, 22), innerBody, null, null, Golden.NoConstraints(), Modifiers.None, 2, 5)
    outerBody := Golden.Block1(Golden.LocalFunc(inner, 2, 5), 1, 14)
    decls := new List<Declaration>()
    Golden.AddFunc(decls, Golden.Func("outer", Golden.NoParams(), null, outerBody, null, null, Golden.NoConstraints(), Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `params` / default-valued parameters materialize their modifier + DefaultValue (Parser.cs :822)" {
    actual := RunAst("func f(params xs: int[], y: int = 2) {\n    print y\n}\n")
    parameters := Golden.NoParams()
    parameters.Add(Golden.Param("xs", Golden.ArrayT(Golden.SimpleT("int", 1, 19, 22), 1, 19, 24), null, false, ParameterModifier.Params, 1, 15))
    parameters.Add(Golden.Param("y", Golden.SimpleT("int", 1, 29, 32), Golden.IntLit("2", 1, 35), false, ParameterModifier.None, 1, 26))
    body := Golden.Block1(Golden.Print(Golden.Ident("y", 2, 11), 2, 5), 1, 38)
    decls := new List<Declaration>()
    Golden.AddFunc(decls, Golden.Func("f", parameters, null, body, null, null, Golden.NoConstraints(), Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `ref` / `out` parameter modifiers materialize (Parser.cs :789-798)" {
    actual := RunAst("func f(ref a: int, out b: int) {\n    print a\n}\n")
    parameters := Golden.NoParams()
    parameters.Add(Golden.Param("a", Golden.SimpleT("int", 1, 15, 18), null, false, ParameterModifier.Ref, 1, 12))
    parameters.Add(Golden.Param("b", Golden.SimpleT("int", 1, 27, 30), null, false, ParameterModifier.Out, 1, 24))
    body := Golden.Block1(Golden.Print(Golden.Ident("a", 2, 11), 2, 5), 1, 32)
    decls := new List<Declaration>()
    Golden.AddFunc(decls, Golden.Func("f", parameters, null, body, null, null, Golden.NoConstraints(), Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a `this` extension parameter sets IsThis (Parser.cs :801)" {
    actual := RunAst("func ext(this a: int): int => a\n")
    parameters := Golden.NoParams()
    parameters.Add(Golden.Param("a", Golden.SimpleT("int", 1, 18, 21), null, true, ParameterModifier.None, 1, 15))
    decls := new List<Declaration>()
    Golden.AddFunc(decls, Golden.Func("ext", parameters, Golden.SimpleT("int", 1, 24, 27), null, Golden.Ident("a", 1, 31), null, Golden.NoConstraints(), Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// The declaration node is anchored on the `func` KEYWORD (Parser.cs :375 captures Current AFTER
// ParseModifiers has consumed the leading modifiers), not on the first modifier.
test "016 N+1c tranche 10: `public static async func` accumulates the Modifiers bitmask (Parser.cs :215)" {
    actual := RunAst("class C {\n    public static async func go(): int {\n        return 1\n    }\n}\n")
    body := Golden.Block1(Golden.Return(Golden.IntLit("1", 3, 16), 3, 9), 2, 40)
    modifiers := Golden.Mods2(Golden.Mods2(Modifiers.Public, Modifiers.Static), Modifiers.Async)
    members := new List<Declaration>()
    Golden.AddFunc(members, Golden.Func("go", Golden.NoParams(), Golden.SimpleT("int", 2, 36, 39), body, null, null, Golden.NoConstraints(), modifiers, 2, 25))
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `func*` sets Modifiers.Generator (Parser.cs :411)" {
    actual := RunAst("func* gen(): int {\n    yield 1\n}\n")
    body := Golden.Block1(Golden.Yield(Golden.IntLit("1", 2, 11), 2, 5), 1, 18)
    decls := new List<Declaration>()
    Golden.AddFunc(decls, Golden.Func("gen", Golden.NoParams(), Golden.SimpleT("int", 1, 14, 17), body, null, null, Golden.NoConstraints(), Modifiers.Generator, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: an operator overload materializes its symbol + the two operator SPANS (Parser.cs :505-506)" {
    actual := RunAst("class C {\n    func operator +(a: C, b: C): C {\n        return a\n    }\n}\n")
    parameters := Golden.NoParams()
    parameters.Add(Golden.Param("a", Golden.SimpleT("C", 2, 24, 25), null, false, ParameterModifier.None, 2, 21))
    parameters.Add(Golden.Param("b", Golden.SimpleT("C", 2, 30, 31), null, false, ParameterModifier.None, 2, 27))
    body := Golden.Block1(Golden.Return(Golden.Ident("a", 3, 16), 3, 9), 2, 36)
    members := new List<Declaration>()
    Golden.AddFunc(members, Golden.OperatorFunc("operator +", parameters, Golden.SimpleT("C", 2, 34, 35), body, "+", Golden.SpanOf(2, 10, 18), Golden.SpanOf(2, 19, 20), 2, 5))
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a `readonly` field carries BOTH Modifiers.Readonly and PropertyModifier.Readonly (Parser.cs :1671)" {
    actual := RunAst("class C {\n    readonly Name: string\n}\n")
    members := new List<Declaration>()
    members.Add(new NSharpLang.Compiler.Ast.FieldDeclaration("Name", Golden.SimpleT("string", 2, 20, 26), null, Modifiers.Readonly, PropertyModifier.Readonly, new List<AttributeNode>(), 2, 5))
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a `test` declaration materializes TestDeclaration with its unquoted description (Parser.cs :650)" {
    actual := RunAst("test \"adds\" {\n    assert a\n}\n")
    body := Golden.Block1(Golden.Assert(Golden.Ident("a", 2, 12), null, 2, 5), 1, 13)
    decls := new List<Declaration>()
    Golden.AddTest(decls, "adds", body, Golden.NoTableParams(), Golden.NoTable(), null, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: `skip \"reason\"` lands unquoted in TestDeclaration.SkipReason (Parser.cs :642)" {
    actual := RunAst("test \"adds\" skip \"later\" {\n    assert a\n}\n")
    body := Golden.Block1(Golden.Assert(Golden.Ident("a", 2, 12), null, 2, 5), 1, 26)
    decls := new List<Declaration>()
    Golden.AddTest(decls, "adds", body, Golden.NoTableParams(), Golden.NoTable(), "later", 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a table-driven test materializes TableParameters + the row lists (Parser.cs :585/:608)" {
    actual := RunAst("test \"adds\" with (a: int) [ (1), (2) ] {\n    assert a\n}\n")
    body := Golden.Block1(Golden.Assert(Golden.Ident("a", 2, 12), null, 2, 5), 1, 40)
    tableParams := Golden.NoParams()
    tableParams.Add(Golden.Param("a", Golden.SimpleT("int", 1, 22, 25), null, false, ParameterModifier.None, 1, 19))
    decls := new List<Declaration>()
    Golden.AddTest(decls, "adds", body, tableParams, Golden.Rows1(Golden.IntLit("1", 1, 30), Golden.IntLit("2", 1, 35)), null, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: setup + teardown blocks materialize their declarations (Parser.cs :700/:715)" {
    actual := RunAst("setup {\n    print 1\n}\n\nteardown {\n    print 2\n}\n")
    decls := new List<Declaration>()
    Golden.AddSetup(decls, Golden.Block1(Golden.Print(Golden.IntLit("1", 2, 11), 2, 5), 1, 7), 1, 1)
    Golden.AddTeardown(decls, Golden.Block1(Golden.Print(Golden.IntLit("2", 6, 11), 6, 5), 5, 10), 5, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 10: a top-level preprocessor directive materializes PreprocessorDeclaration (Parser.cs :211)" {
    actual := RunAst("#if DEBUG\nclass C {}\n")
    decls := new List<Declaration>()
    Golden.AddPreproc(decls, "#if DEBUG", 1, 1)
    Golden.AddClass(decls, "C", 2, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- tranche 10b: negative self-checks ----

test "016 N+1c tranche 10: AstEq surfaces a wrong ParameterModifier (Ref golden vs Out actual)" {
    actual := RunAst("func f(out b: int) {\n    print b\n}\n")
    parameters := Golden.NoParams()
    parameters.Add(Golden.Param("b", Golden.SimpleT("int", 1, 15, 18), null, false, ParameterModifier.Ref, 1, 12))
    body := Golden.Block1(Golden.Print(Golden.Ident("b", 2, 11), 2, 5), 1, 20)
    decls := new List<Declaration>()
    Golden.AddFunc(decls, Golden.Func("f", parameters, null, body, null, null, Golden.NoConstraints(), Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") != ""
}

test "016 N+1c tranche 10: AstEq surfaces a swapped get/set property body" {
    actual := RunAst("class C {\n    Name: string {\n        get { return v }\n        set { v = 1 }\n    }\n}\n")
    getBody := Golden.Block1(Golden.Return(Golden.Ident("v", 3, 22), 3, 15), 3, 13)
    setBody := Golden.Block1(Golden.ExprStmt(Golden.Assign(Golden.Ident("v", 4, 15), AssignmentOperator.Assign, Golden.IntLit("1", 4, 19), 4, 17), 4, 15), 4, 13)
    members := new List<Declaration>()
    Golden.AddProp(members, "Name", Golden.SimpleT("string", 2, 11, 17), setBody, getBody, null, Modifiers.None, PropertyModifier.None, 2, 5)
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") != ""
}

test "016 N+1c tranche 10: AstEq surfaces a wrong test table ROW value (guards vacuous row-list pass)" {
    actual := RunAst("test \"adds\" with (a: int) [ (1), (2) ] {\n    assert a\n}\n")
    body := Golden.Block1(Golden.Assert(Golden.Ident("a", 2, 12), null, 2, 5), 1, 40)
    tableParams := Golden.NoParams()
    tableParams.Add(Golden.Param("a", Golden.SimpleT("int", 1, 22, 25), null, false, ParameterModifier.None, 1, 19))
    decls := new List<Declaration>()
    Golden.AddTest(decls, "adds", body, tableParams, Golden.Rows1(Golden.IntLit("1", 1, 30), Golden.IntLit("9", 1, 35)), null, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") != ""
}

// ---- tranche 11: the tranche-10b pinned DECLINE converted to a POSITIVE contract ----
// The conversion-operator shape makes Parser.cs emit an EXTRA `<error>`-named PropertyDeclaration (its
// `: int => 1` tail is re-parsed as a bogus property member over the ConsumeIdentifier `<error>`
// placeholder). Tranche 11 reproduces that synthetic member byte-exact, so the Members lists now agree.
test "016 N+1c tranche 11: a conversion operator emits Parser.cs's synthetic `<error>` property member (:1698/:6819)" {
    actual := RunAst("class C {\n    implicit operator int(c: C): int => 1\n}\n")
    parameters := Golden.NoParams()
    parameters.Add(Golden.Param("c", Golden.SimpleT("C", 2, 30, 31), null, false, ParameterModifier.None, 2, 27))
    conversion := new NSharpLang.Compiler.Ast.FunctionDeclaration("implicit operator", parameters, Golden.SimpleT("int", 2, 23, 26), null, null, null, Golden.NoConstraints(), Modifiers.None, new List<AttributeNode>(), false, null, true, true, 2, 5)
    members := new List<Declaration>()
    members.Add(conversion)
    Golden.AddProp(members, "<error>", Golden.SimpleT("int", 2, 34, 37), null, null, Golden.IntLit("1", 2, 41), Modifiers.None, PropertyModifier.None, 2, 32)
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ============================================================================================
// STAGE N+1c TRANCHE 11 — ERROR-NODE MATERIALIZATION (the MALFORMED-FILE surface)
// ============================================================================================
// Parser.cs never declines on malformed input: at every recovery site it substitutes a SYNTHETIC node —
// `IdentifierExpression("<error>")`, `IdentifierPattern("<error>")`, `SimpleTypeReference("<error>")`, an
// `<error>`-named declaration/member/parameter/property placeholder, or an empty BlockStatement — and keeps
// building the tree around it. The N+2 cutover hands consumers whatever Parser.cs produces TODAY, and an LSP
// serves files that are malformed most of the time they are being edited, so the owner REPRODUCES every one
// of those artifacts byte-exact instead of declining them.
//
// Every golden below is transcribed from the LIVE Parser.cs AstToJson oracle over the identical source, and
// each shape was additionally diffed owner-vs-live whole-tree through the same serializer.
//
// `RunFn` wraps a single statement in a ONE-LINE `func f() { … }` so the golden columns are direct offsets:
// `func f() { ` is 11 characters, so the inner statement starts at column 12 and the body block at column 10.

func RunFn(inner: string): CompilationUnit {
    return RunAst("func f() { " + inner + " }")
}

func FnUnit(statements: List<Statement>): CompilationUnit {
    decls := new List<Declaration>()
    Golden.AddFunc(decls, Golden.Func("f", Golden.NoParams(), null, Golden.Block(statements, 1, 10), null, null, Golden.NoConstraints(), Modifiers.None, 1, 1))
    return Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
}

func FnUnit1(statement: Statement): CompilationUnit {
    statements := Golden.NoStmts()
    Golden.Add(statements, statement)
    return FnUnit(statements)
}

// ---- the DECLARATION-level placeholders ----

test "016 N+1c tranche 11: a stray top-level token materializes Parser.cs's `<error>` ClassDeclaration (:255)" {
    actual := RunAst("import 5\n")
    imports := NoImports()
    Golden.AddImport(imports, "<error>", null, 1, 1)
    decls := new List<Declaration>()
    // Line/Column are read AFTER the skip Advance, so they name the token FOLLOWING the offender (Eof).
    Golden.AddClass(decls, "<error>", 2, 1)
    expected := Golden.Unit(null, imports, NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: `func 5` builds an `<error>` function over an `<error>` parameter and type (:503/:822/:6541)" {
    actual := RunAst("func 5\n")
    parameters := Golden.NoParams()
    parameters.Add(Golden.Param("<error>", Golden.SimpleT("<error>", 1, 6, 7), null, false, ParameterModifier.None, 1, 6))
    decls := new List<Declaration>()
    Golden.AddFunc(decls, Golden.Func("<error>", parameters, null, null, null, null, Golden.NoConstraints(), Modifiers.None, 1, 1))
    Golden.AddClass(decls, "<error>", 2, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: a colon-less field materializes the `<error>` field TYPE (Parser.cs :6577)" {
    actual := RunAst("class C { x }")
    members := new List<Declaration>()
    Golden.AddFieldT(members, "x", Golden.SimpleT("<error>", 1, 11, 12), 1, 11)
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: `test 5 { }` keeps Parser.cs's synthetic `<error>` description (:569)" {
    actual := RunAst("test 5 {\n}\n")
    decls := new List<Declaration>()
    Golden.AddTest(decls, "<error>", Golden.Block(Golden.NoStmts(), 1, 8), Golden.NoTableParams(), Golden.NoTable(), null, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: `ref struct` threads isRefStruct through the two dispatch arms (Parser.cs :224/:1446)" {
    actual := RunAst("ref struct S {\n}\n")
    decls := new List<Declaration>()
    decls.Add(new StructDeclaration("S", null, Golden.NoTypeRefs(), new List<Declaration>(), null, Modifiers.None, new List<AttributeNode>(), 1, 5, true))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- the EXPRESSION-level placeholders ----

test "016 N+1c tranche 11: a dangling binary operator materializes the `<error>` right operand (:3785)" {
    actual := RunFn("x := 1 + ")
    initializer := Golden.Bin(Golden.IntLit("1", 1, 17), BinaryOperator.Add, Golden.Ident("<error>", 1, 20), 1, 19)
    expected := FnUnit1(Golden.VarDecl("x", null, initializer, VariableKind.Let, 1, 12))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: prefix `+` materializes `<error>` anchored on the plus (Parser.cs :3850)" {
    actual := RunFn("x := + 3")
    expected := FnUnit1(Golden.VarDecl("x", null, Golden.Ident("<error>", 1, 17), VariableKind.Let, 1, 12))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: a leading `.` materializes `<error>` anchored on the dot (Parser.cs :6447)" {
    actual := RunFn("x := .Foo")
    expected := FnUnit1(Golden.VarDecl("x", null, Golden.Ident("<error>", 1, 17), VariableKind.Let, 1, 12))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: an unexpected token in expression materializes the terminal `<error>` (:4838)" {
    actual := RunFn("x := * 3")
    statements := Golden.NoStmts()
    Golden.Add(statements, Golden.VarDecl("x", null, Golden.Ident("<error>", 1, 17), VariableKind.Let, 1, 12))
    Golden.Add(statements, Golden.ExprStmt(Golden.IntLit("3", 1, 19), 1, 19))
    expected := FnUnit(statements)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: a missing member name after `.` materializes the `<error>` member (:4451)" {
    actual := RunAst("func f() {\n    x := a.\n}\n")
    initializer := Golden.Member(Golden.Ident("a", 2, 10), "<error>", false, 2, 11)
    decls := new List<Declaration>()
    Golden.AddFunc(decls, Golden.Func("f", Golden.NoParams(), null, Golden.Block1(Golden.VarDecl("x", null, initializer, VariableKind.Let, 2, 5), 1, 10), null, null, Golden.NoConstraints(), Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: a RESERVED-KEYWORD member name materializes the `<error>` member (:4446)" {
    actual := RunFn("x := a.class")
    initializer := Golden.Member(Golden.Ident("a", 1, 17), "<error>", false, 1, 18)
    expected := FnUnit1(Golden.VarDecl("x", null, initializer, VariableKind.Let, 1, 12))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: a missing unary operand materializes `<error>` past the keyword (:3824)" {
    actual := RunFn("x := await")
    initializer := Golden.Await(Golden.Ident("<error>", 1, 22), 1, 17)
    expected := FnUnit1(Golden.VarDecl("x", null, initializer, VariableKind.Let, 1, 12))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: an invalid pattern materializes `IdentifierPattern(\"<error>\")` (Parser.cs :3467)" {
    actual := RunFn("x := match a { + => 1 }")
    cases := Golden.NoCases()
    Golden.AddCase(cases, Golden.PIdent("<error>", 1, 27), null, Golden.Ident("<error>", 1, 27))
    Golden.AddCase(cases, Golden.PIdent("<error>", 1, 29), null, Golden.IntLit("1", 1, 32))
    initializer := Golden.Match(Golden.Ident("a", 1, 23), cases, 1, 17)
    expected := FnUnit1(Golden.VarDecl("x", null, initializer, VariableKind.Let, 1, 12))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: a missing object-initializer `:` materializes the `<error>` value (Parser.cs :5334)" {
    actual := RunFn("x := new T { A 1 }")
    props := Golden.NoProps()
    Golden.AddProp(props, "A", null, Golden.Ident("<error>", 1, 26), 1, 25)
    Golden.AddProp(props, "<error>", null, Golden.Ident("<error>", 1, 28), 1, 27)
    initializer := Golden.NewE(Golden.SimpleT("T", 1, 21, 22), Golden.NoArgs(), Golden.ObjInit(props, 1, 17), null, 1, 17)
    expected := FnUnit1(Golden.VarDecl("x", null, initializer, VariableKind.Let, 1, 12))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- the STRUCTURAL gaps this tranche closed ----

test "016 N+1c tranche 11: a `>>`-split nested generic keeps Parser.cs's MULTI-LINE type span (:1966/:5884)" {
    actual := RunAst("class C {\n    F: Dictionary<string, List<int>>?\n    G: int\n}\n")
    innerArgs := Golden.NoTypeRefs()
    innerArgs.Add(Golden.SimpleT("int", 2, 32, 35))
    inner := Golden.GenericT("List", innerArgs, 2, 27, 36)
    // Parser.cs's `?` postfix fires TWICE here: the owed split `>` is consumed as the first `?` (the
    // ConsumeGreater/Advance split discipline), so the arm is doubly nullable and the OUTER `>` is then
    // missing — Parser.cs's ConsumeGreater returns the NEXT LINE's token, giving a MULTI-LINE span.
    outerArgs := Golden.NoTypeRefs()
    outerArgs.Add(Golden.SimpleT("string", 2, 19, 25))
    outerArgs.Add(Golden.NullableT(Golden.NullableT(inner, 2, 27, 37), 2, 27, 38))
    fieldType := new GenericTypeReference("Dictionary", outerArgs, 2, 8)
    fieldType.Span = new SourceSpan(2, 8, 3, 6)
    members := new List<Declaration>()
    Golden.AddFieldT(members, "F", fieldType, 2, 5)
    Golden.AddFieldT(members, "G", Golden.SimpleT("int", 3, 8, 11), 3, 5)
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: an `is` pattern variable swallows the NEXT LINE's identifier (Parser.cs :4157)" {
    actual := RunAst("func f() {\n    x := a is B\n    y := 1\n}\n")
    statements := Golden.NoStmts()
    isExpr := Golden.Is(Golden.Ident("a", 2, 10), Golden.SimpleT("B", 2, 15, 16), "y", 2, 12)
    Golden.Add(statements, Golden.VarDecl("x", null, isExpr, VariableKind.Let, 2, 5))
    Golden.Add(statements, Golden.ExprStmt(Golden.Ident("<error>", 3, 7), 3, 7))
    Golden.Add(statements, Golden.ExprStmt(Golden.IntLit("1", 3, 10), 3, 10))
    decls := new List<Declaration>()
    Golden.AddFunc(decls, Golden.Func("f", Golden.NoParams(), null, Golden.Block(statements, 1, 10), null, null, Golden.NoConstraints(), Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ---- NEGATIVE self-checks: the harness must reject a WRONG synthetic artifact ----

test "016 N+1c tranche 11 (negative): a WRONG synthetic member name is rejected" {
    actual := RunFn("x := a.class")
    initializer := Golden.Member(Golden.Ident("a", 1, 17), "class", false, 1, 18)
    expected := FnUnit1(Golden.VarDecl("x", null, initializer, VariableKind.Let, 1, 12))
    assert AstEq.Diff(expected, actual, "unit") != ""
}

test "016 N+1c tranche 11 (negative): a WRONG synthetic-operand COLUMN is rejected" {
    actual := RunFn("x := 1 + ")
    initializer := Golden.Bin(Golden.IntLit("1", 1, 17), BinaryOperator.Add, Golden.Ident("<error>", 1, 19), 1, 19)
    expected := FnUnit1(Golden.VarDecl("x", null, initializer, VariableKind.Let, 1, 12))
    assert AstEq.Diff(expected, actual, "unit") != ""
}

test "016 N+1c tranche 11 (negative): a SINGLE-LINE type span is rejected where Parser.cs builds a multi-line one" {
    actual := RunAst("class C {\n    F: Dictionary<string, List<int>>?\n    G: int\n}\n")
    innerArgs := Golden.NoTypeRefs()
    innerArgs.Add(Golden.SimpleT("int", 2, 32, 35))
    outerArgs := Golden.NoTypeRefs()
    outerArgs.Add(Golden.SimpleT("string", 2, 19, 25))
    outerArgs.Add(Golden.NullableT(Golden.NullableT(Golden.GenericT("List", innerArgs, 2, 27, 36), 2, 27, 37), 2, 27, 38))
    members := new List<Declaration>()
    Golden.AddFieldT(members, "F", Golden.GenericT("Dictionary", outerArgs, 2, 8, 39), 2, 5)
    Golden.AddFieldT(members, "G", Golden.SimpleT("int", 3, 8, 11), 3, 5)
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") != ""
}

// ---- the remaining tranche-11 recovery ARTIFACTS (each a Parser.cs substitution, not a decline) ----

test "016 N+1c tranche 11: an UNTERMINATED test description reproduces Parser.cs's `Trim('\"')` (:574)" {
    // The LSP shape: the string literal is still being typed, so it has no closing quote. `Trim('"')`
    // strips EVERY leading and trailing quote — not a paired unwrap — so the description is `par`.
    actual := RunAst("test \"par")
    decls := new List<Declaration>()
    Golden.AddTest(decls, "par", Golden.Block(Golden.NoStmts(), 1, 10), Golden.NoTableParams(), Golden.NoTable(), null, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: an EMPTY type-parameter list `<>` still materializes the declaration (:757)" {
    actual := RunAst("func f<>() { }")
    decls := new List<Declaration>()
    Golden.AddFunc(decls, Golden.Func("f", Golden.NoParams(), null, Golden.Block(Golden.NoStmts(), 1, 12), null, new List<TypeParameter>(), Golden.NoConstraints(), Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: a non-this/base constructor initializer becomes a synthetic empty `this()` (:1559)" {
    actual := RunAst("class C {\n  constructor() : foo() {\n  }\n}\n")
    inner := Golden.NoStmts()
    Golden.Add(inner, Golden.ExprStmt(Golden.Tuple(Golden.NoTupleElems(), 2, 22), 2, 22))
    Golden.Add(inner, Golden.Block(Golden.NoStmts(), 2, 25))
    initializer := Golden.Call(Golden.ThisE(2, 19), Golden.NoArgs(), Golden.NoTypeArgs(), 2, 19)
    members := new List<Declaration>()
    Golden.AddCtor(members, Golden.NoParams(), Golden.Block(inner, 2, 22), initializer, 2, 3)
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: a value-less object-initializer member materializes `<error>` past the `:` (:5376)" {
    actual := RunFn("x := new T { A: }")
    props := Golden.NoProps()
    Golden.AddProp(props, "A", null, Golden.Ident("<error>", 1, 27), 1, 25)
    initializer := Golden.NewE(Golden.SimpleT("T", 1, 21, 22), Golden.NoArgs(), Golden.ObjInit(props, 1, 17), null, 1, 17)
    expected := FnUnit1(Golden.VarDecl("x", null, initializer, VariableKind.Let, 1, 12))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: a body-less LOCAL FUNCTION gets Parser.cs's synthetic empty block (:2530)" {
    actual := RunAst("func f() {\n    func inner(): int\n}\n")
    local := Golden.Func("inner", Golden.NoParams(), Golden.SimpleT("int", 2, 19, 22), Golden.Block(Golden.NoStmts(), 3, 1), null, null, Golden.NoConstraints(), Modifiers.None, 2, 5)
    decls := new List<Declaration>()
    Golden.AddFunc(decls, Golden.Func("f", Golden.NoParams(), null, Golden.Block1(Golden.LocalFunc(local, 2, 5), 1, 10), null, null, Golden.NoConstraints(), Modifiers.None, 1, 1))
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: a non-lambda `on` handler gets the synthetic empty-parameter lambda (:2930)" {
    actual := RunFn("on w.C foo")
    handler := Golden.BlockLambda(Golden.NoParams(), Golden.Block(Golden.NoStmts(), 1, 19), 1, 19)
    subscription := Golden.OnSub(Golden.Member(Golden.Ident("w", 1, 15), "C", false, 1, 16), handler, 1, 12)
    expected := FnUnit1(Golden.ExprStmt(subscription, 1, 12))
    assert AstEq.Diff(expected, actual, "unit") == ""
}

test "016 N+1c tranche 11: an invalid property accessor still materializes the PropertyDeclaration (:1768)" {
    actual := RunAst("class C {\n  X: int {\n    5\n  }\n}\n")
    members := new List<Declaration>()
    Golden.AddProp(members, "X", Golden.SimpleT("int", 2, 6, 9), null, null, null, Modifiers.None, PropertyModifier.None, 2, 3)
    decls := new List<Declaration>()
    Golden.AddClassM(decls, "C", members, 1, 1)
    expected := Golden.Unit(null, NoImports(), NoFileImports(), null, decls, 1, 1)
    assert AstEq.Diff(expected, actual, "unit") == ""
}

// ── 016 N+3 (the Parser.cs DELETION arc) ─────────────────────────────────────
// `FileParseAst.Success` is the last member the retiring C# `ParseResult` record exposed that the
// owner's result did not. It reproduces `CompilationUnit != null && !Errors.Any(e => e.Severity ==
// ErrorSeverity.Error)` exactly, so every consumer that read `ParseResult.Success` reads this
// instead and the C# record retires with `Parser.cs`.
test "016 N+3: FileParseAst.Success is true for a well-formed file" {
    parsed := ColumnarParserRecovery.ParseFileAst("func f(): int {\n    return 1\n}\n", "test.nl")
    assert parsed.Errors.Count == 0
    assert parsed.Success
}

test "016 N+3: FileParseAst.Success is false when any error-severity diagnostic is recorded" {
    parsed := ColumnarParserRecovery.ParseFileAst("func f(name:) {\n}\n", "test.nl")
    assert parsed.Errors.Count > 0
    assert parsed.Errors[0].Severity == ErrorSeverity.Error
    assert !parsed.Success
}

test "016 N+3: FileParseAst.Success ignores diagnostics below error severity" {
    errors := new List<CompilerError>()
    errors.Add(CompilerError.Create(ErrorCode.InvalidSyntax, "warning-shaped", 1, 1, ErrorSeverity.Warning))
    parsed := new FileParseAst(new CompilationUnit(null, new List<ImportDirective>(), new List<Statement>(), null, new List<Declaration>(), 1, 1), errors)
    assert parsed.Errors.Count == 1
    assert parsed.Success
}

test "016 N+3: FileParseAst.Success is false when the CompilationUnit is absent" {
    parsed := new FileParseAst(null, new List<CompilerError>())
    assert !parsed.Success
}
