namespace NSharpLang.Compiler.CodeIntelligence

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast


// CONTRACTS FOR THE PURE HALF OF THE WORDS EVERY ANSWER CARRIES (task 019 slice 13).
//
// Nine members came out of `CodeIntelligenceService.cs` here, and EVERY ONE OF THEM WAS PRIVATE.
// That is why so little below has ever been asserted before: `TypeInfoToKind` decides the `kind`
// string on every hover and every `nlc query type`, and the only way to ask it was to build a
// project, run an analysis and read the field off the far end. Here it is asked directly.
//
// FIVE THINGS THAT WERE UNREACHABLE, PROSE OR VACUOUS ARE STATED HERE AS CONTRACTS:
//   (a) AN ENUM IS ALSO A VALUE TYPE, SO THE TWO REFLECTION TESTS ARE ORDERED. `TypeInfoToKind`
//       asks `IsEnum` before `IsValueType`; reversed, every reflected enum reads back as "struct"
//       and every enum hover in the editor silently changes its kind. Asserted on a real CLR enum.
//   (b) THE MODIFIER CHIPS HAVE A PRINTED ORDER, AND IT IS NOT THE ENUM'S BIT ORDER. `readonly`
//       (512) prints AFTER `override` (65536). The C# encoded this only in statement order.
//   (c) `Modifiers.None` IS NULL, NOT AN EMPTY ARRAY — a distinction every JSON consumer sees.
//   (d) THE TWO UNION SPELLINGS ARE DIFFERENT FUNCTIONS AND BOTH JOIN ON " | ".
//       `GetTypeReferenceName` joins DISPLAY NAMES of type references; `GetTypeDisplayName` joins
//       FORMATTED TYPE INFOS of an anonymous union. Both were `Select(methodGroup)` in C#.
//   (e) `GetExpressionQueryName` UNWRAPS, AND THE UNWRAPPING IS RECURSIVE. A parenthesised await of
//       a call resolves to the callee's name; that composition was never tested.
func CidtSimple(name: string): SimpleTypeReference {
    return new SimpleTypeReference(name, 1, 1)
}

func CidtId(name: string): IdentifierExpression {
    return new IdentifierExpression(name, 1, 1)
}

func CidtChips(modifiers: object): string {
    chips := CodeIntelligenceDisplayText.FormatModifiers(modifiers)
    if chips == null {
        return "<null>"
    }

    joined := ""
    index := 0
    while index < chips.Length {
        if index > 0 {
            joined = joined + ","
        }

        joined = joined + chips[index]
        index = index + 1
    }

    return joined
}

func CidtUnionRef(first: string, second: string): UnionTypeReference {
    arms := new List<TypeReference>()
    arms.Add(CidtSimple(first))
    arms.Add(CidtSimple(second))
    return new UnionTypeReference(arms)
}

// ── The type-reference display names ─────────────────────────────────────

test "FormatTypeReference answers void for the absent return type" {
    assert CodeIntelligenceDisplayText.FormatTypeReference(null) == "void"
    assert CodeIntelligenceDisplayText.FormatTypeReference(CidtSimple("int")) == "int"
}

test "GetTypeReferenceName reads the head name through nullable and array wrappers" {
    assert CodeIntelligenceDisplayText.GetTypeReferenceName(CidtSimple("Widget")) == "Widget"
    assert CodeIntelligenceDisplayText.GetTypeReferenceName(new NullableTypeReference(CidtSimple("Widget"))) == "Widget"
    assert CodeIntelligenceDisplayText.GetTypeReferenceName(new ArrayTypeReference(CidtSimple("Widget"))) == "Widget"
    // Nested: an array of nullables still names the element.
    assert CodeIntelligenceDisplayText.GetTypeReferenceName(
        new ArrayTypeReference(new NullableTypeReference(CidtSimple("Widget")))) == "Widget"
}

test "GetTypeReferenceName answers null for a reference shape it does not name" {
    assert CodeIntelligenceDisplayText.GetTypeReferenceName(null) == null
    assert CodeIntelligenceDisplayText.GetTypeReferenceName(new ByRefTypeReference(CidtSimple("int"))) == null
}

test "(d) a union type REFERENCE joins its arms' display names on ' | '" {
    assert CodeIntelligenceDisplayText.GetTypeReferenceName(CidtUnionRef("int", "string")) == "int | string"
}

test "generic arms keep the bare head name, not the display name" {
    // GetTypeReferenceName is the QUERY name — `List` — while FormatTypeReference is the DISPLAY
    // name — `List<int>`. The two were adjacent in C# and are easy to confuse.
    args := new List<TypeReference>()
    args.Add(CidtSimple("int"))
    generic := new GenericTypeReference("List", args, 1, 1)
    assert CodeIntelligenceDisplayText.GetTypeReferenceName(generic) == "List"
    assert CodeIntelligenceDisplayText.FormatTypeReference(generic) == "List<int>"
}

test "InterfaceNameMatches is ORDINAL, so case is significant" {
    assert CodeIntelligenceDisplayText.InterfaceNameMatches(CidtSimple("IShape"), "IShape")
    assert CodeIntelligenceDisplayText.InterfaceNameMatches(CidtSimple("IShape"), "ishape") == false
    args := new List<TypeReference>()
    args.Add(CidtSimple("int"))
    assert CodeIntelligenceDisplayText.InterfaceNameMatches(new GenericTypeReference("IShape", args, 1, 1), "IShape")
    // An array of the interface is NOT the interface.
    assert CodeIntelligenceDisplayText.InterfaceNameMatches(new ArrayTypeReference(CidtSimple("IShape")), "IShape") == false
}

// ── The kind string ──────────────────────────────────────────────────────

test "TypeInfoToKind names each modelled type info" {
    assert CodeIntelligenceDisplayText.TypeInfoToKind(new SimpleTypeInfo("int")) == "primitive"
    assert CodeIntelligenceDisplayText.TypeInfoToKind(new ArrayTypeInfo(new SimpleTypeInfo("int"))) == "array"
    assert CodeIntelligenceDisplayText.TypeInfoToKind(new NullableTypeInfo(new SimpleTypeInfo("int"))) == "nullable"
    assert CodeIntelligenceDisplayText.TypeInfoToKind(new ObliviousTypeInfo(new SimpleTypeInfo("int"))) == "oblivious"
    assert CodeIntelligenceDisplayText.TypeInfoToKind(BuiltInTypes.Unknown) == "unknown"
}

test "(a) AN ENUM IS ALSO A VALUE TYPE, AND IsEnum IS ASKED FIRST" {
    // Reverse the two tests and this line reads "struct". Every enum hover in the editor depends on
    // the order, and nothing else in the estate asserts it.
    // `typeof(DayOfWeek)` is not in the columnar typeof catalog; the reflected lookup is.
    reflectedEnum: TypeInfo = new ReflectionTypeInfo(Type.GetType("System.DayOfWeek"))
    reflectedStruct: TypeInfo = new ReflectionTypeInfo(typeof(int))
    reflectedClass: TypeInfo = new ReflectionTypeInfo(typeof(string))
    assert CodeIntelligenceDisplayText.TypeInfoToKind(reflectedEnum) == "enum"
    assert CodeIntelligenceDisplayText.TypeInfoToKind(reflectedStruct) == "struct"
    assert CodeIntelligenceDisplayText.TypeInfoToKind(reflectedClass) == "class"
}

test "both union shapes report the SAME kind, and that is deliberate" {
    arms := new List<TypeInfo>()
    arms.Add(new SimpleTypeInfo("int"))
    arms.Add(new SimpleTypeInfo("string"))
    assert CodeIntelligenceDisplayText.TypeInfoToKind(new AnonymousUnionTypeInfo(arms)) == "union"
}

// ── The display name ─────────────────────────────────────────────────────

test "GetTypeDisplayName falls back when the type info carries no name of its own" {
    assert CodeIntelligenceDisplayText.GetTypeDisplayName(new SimpleTypeInfo("int"), "fallback") == "fallback"
    assert CodeIntelligenceDisplayText.GetTypeDisplayName(BuiltInTypes.Unknown, "fallback") == "fallback"
}

test "GetTypeDisplayName reads a reflected type's SHORT name" {
    reflectedClass: TypeInfo = new ReflectionTypeInfo(typeof(string))
    assert CodeIntelligenceDisplayText.GetTypeDisplayName(reflectedClass, "fallback") == "String"
}

test "(d) an ANONYMOUS UNION type info joins its formatted arms on ' | '" {
    arms := new List<TypeInfo>()
    arms.Add(new SimpleTypeInfo("int"))
    arms.Add(new SimpleTypeInfo("string"))
    assert CodeIntelligenceDisplayText.GetTypeDisplayName(new AnonymousUnionTypeInfo(arms), "fallback") == "int | string"
}

// ── The modifier chips ───────────────────────────────────────────────────

test "(c) Modifiers.None is NULL and not an empty array" {
    assert CodeIntelligenceDisplayText.FormatModifiers(Modifiers.None) == null
    assert CidtChips(Modifiers.None) == "<null>"
}

test "a null modifier value is read as None" {
    assert CodeIntelligenceDisplayText.FormatModifiers(null) == null
}

test "(b) THE CHIPS HAVE A PRINTED ORDER AND IT IS NOT THE ENUM'S BIT ORDER" {
    // readonly is bit 512 and override is bit 65536, yet `readonly` prints LAST. The C# recorded
    // this only as the order of eleven `if` statements.
    assert CidtChips(Modifiers.Readonly) == "readonly"
    assert CidtChips(Modifiers.Override) == "override"
    assert CidtChips(Modifiers.Public) == "pub"
    assert CidtChips(Modifiers.Private) == "priv"
}

test "(b) every chip in one mask, in the printed order" {
    assert CidtChips(Modifiers.Public | Modifiers.Static | Modifiers.Async | Modifiers.Readonly)
        == "pub,static,async,readonly"
}

test "a modifier the chip list does not name contributes nothing" {
    // Partial (256), Const (1024), Generator (4096), Required (8192), Init (16384) and File (32768)
    // have no chip. A mask of ONLY those is not None, and still answers null.
    assert CodeIntelligenceDisplayText.FormatModifiers(Modifiers.Partial) == null
    assert CidtChips(Modifiers.Partial | Modifiers.Public) == "pub"
}

// ── The names read off expressions ───────────────────────────────────────

test "ExtractCalleeName reads identifiers and member names, and nothing else" {
    assert CodeIntelligenceDisplayText.ExtractCalleeName(CidtId("run")) == "run"
    assert CodeIntelligenceDisplayText.ExtractCalleeName(
        new MemberAccessExpression(CidtId("widget"), "Run", false, 1, 1)) == "Run"
    assert CodeIntelligenceDisplayText.ExtractCalleeName(new IntLiteralExpression("1", 1, 1)) == null
}

test "GetExpressionQueryName reads the name a type query should look up" {
    assert CodeIntelligenceDisplayText.GetExpressionQueryName(null) == null
    assert CodeIntelligenceDisplayText.GetExpressionQueryName(CidtId("widget")) == "widget"
    assert CodeIntelligenceDisplayText.GetExpressionQueryName(
        new MemberAccessExpression(CidtId("widget"), "Name", false, 1, 1)) == "Name"
    assert CodeIntelligenceDisplayText.GetExpressionQueryName(new IntLiteralExpression("1", 1, 1)) == null
}

test "(e) THE UNWRAPPING IS RECURSIVE, AND THE COMPOSITION IS THE POINT" {
    // ( await ( run() ) ) resolves to `run`. Each arm was one line in a C# switch; that they compose
    // was never asked.
    call := new CallExpression(CidtId("run"), new List<Argument>(), null, 1, 1)
    awaited := new AwaitExpression(call, 1, 1)
    parenthesized := new ParenthesizedExpression(awaited, 1, 1)
    assert CodeIntelligenceDisplayText.GetExpressionQueryName(parenthesized) == "run"
}

test "a new expression and a cast both name their TYPE, not a value" {
    assert CodeIntelligenceDisplayText.GetExpressionQueryName(
        new NewExpression(CidtSimple("Widget"), new List<Argument>(), null, 1, 1)) == "Widget"
    assert CodeIntelligenceDisplayText.GetExpressionQueryName(
        new CastExpression(CidtId("value"), CidtSimple("Widget"), CastKind.Hard, 1, 1)) == "Widget"
}

// ── The suggestion line ──────────────────────────────────────────────────

test "FormatSuggestions distinguishes absent from empty, and both answer null" {
    assert CodeIntelligenceDisplayText.FormatSuggestions(null) == null
    assert CodeIntelligenceDisplayText.FormatSuggestions(new List<string>()) == null
}

test "FormatSuggestions joins on '; ' and a single suggestion carries no separator" {
    one := new List<string>()
    one.Add("use `let`")
    assert CodeIntelligenceDisplayText.FormatSuggestions(one) == "use `let`"

    two := new List<string>()
    two.Add("use `let`")
    two.Add("or remove it")
    assert CodeIntelligenceDisplayText.FormatSuggestions(two) == "use `let`; or remove it"
}
