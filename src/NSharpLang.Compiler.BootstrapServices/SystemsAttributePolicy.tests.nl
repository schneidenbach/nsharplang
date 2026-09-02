namespace NSharpLang.Compiler.Performance

import System
import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// Native contracts for WHAT A DECLARATION'S ATTRIBUTES MEAN.
//
// These nine members plus the nested set were 95 lines inside `SystemsAnalyzer.cs`, and their only
// code — NSYS180 — is CORPUS-SILENT and absent from the ordering pin, so these contracts and the
// purpose-built fixtures are the whole pinning.
//
// SEVEN THINGS THIS FAMILY IS EASY TO GET WRONG, ALL STATED BELOW.
//
// (1) THE NAME MATCH STRIPS `Attribute` ORDINALLY AND THEN COMPARES WITHOUT CASE — so
// `[HotAttribute]` is `[hot]` and `[hotattribute]` is not — and it is NOT
// `NominalTypeInfoFactory.AttributeNameEquals`, which is an exact ordinal comparison. The two share a
// name and DISAGREE; a contract below asserts the disagreement so neither can be folded into the
// other.
//
// (2) THE ALLOW SET'S COMPARER IS `OrdinalIgnoreCase`, AND TWO FAMILIES DEPEND ON IT. The walk's
// `IsAllowed` widens on an `effect:` prefix; the callee-policy rule tests membership EXACTLY. Both
// read this one set, so `[allow(ALLOC)]` must silence the exact test.
//
// (3) THE SET CARRIES BOTH FORMS. A named argument contributes its NAME and, when its value is a
// bare word, `name:value` as well — and the second form is the only reason the walk's prefix
// widening has anything to widen onto.
//
// (4) `reason` AND `owner` ARE EXCLUDED ORDINALLY while the attribute name is matched
// case-insensitively, so `[allow(Reason: "x")]` puts `Reason` INTO the effect set. That asymmetry is
// the original's and is preserved rather than harmonised.
//
// (5) A BARE-WORD ARGUMENT IS NOT A STRING ARGUMENT. `[alloc(none)]` claims something and
// `[alloc("none")]` does not.
//
// (6) "PUBLIC" IS THE `public` MODIFIER **OR** THE EXPORTED-IDENTIFIER CONVENTION, which is WIDER
// than `VisibilityConventions.IsExportedIdentifier(name, modifiers)`: an upper-case name carrying
// `private` is public to this rule and not to that helper. A contract asserts the disagreement.
//
// (7) THE TWO WAIVER FINDINGS ARE INDEPENDENT AND BOTH FIRE PER `[allow]`, in declaration order.
func SatArgs(): List<Argument> {
    return new List<Argument>()
}

func SatNamed(arguments: List<Argument>, name: string, value: Expression) {
    arguments.Add(new Argument(name, value, ArgumentModifier.None))
}

func SatPositional(arguments: List<Argument>, value: Expression) {
    arguments.Add(new Argument(null, value, ArgumentModifier.None))
}

func SatWord(text: string): IdentifierExpression {
    return new IdentifierExpression(text, 1, 1)
}

func SatText(text: string): StringLiteralExpression {
    return new StringLiteralExpression(text, 1, 1)
}

func SatAttribute(name: string, arguments: List<Argument>): AttributeNode {
    return new AttributeNode(name, arguments, 1, 1)
}

func SatBare(name: string): AttributeNode {
    return SatAttribute(name, SatArgs())
}

func SatSet(attributes: List<AttributeNode>): SystemsAttributeSet {
    return new SystemsAttributeSet(attributes)
}

func SatList(attribute: AttributeNode): List<AttributeNode> {
    attributes := new List<AttributeNode>()
    attributes.Add(attribute)
    return attributes
}

// `[allow(<argument list>)]` on its own.
func SatAllowSet(arguments: List<Argument>): SystemsAttributeSet {
    return SatSet(SatList(SatAttribute("allow", arguments)))
}

func SatEffects(arguments: List<Argument>): HashSet<string> {
    set := SatAllowSet(arguments)
    return set.AllowEffects()
}

// THE WALK'S WIDENING TEST, WRITTEN OUT so both readings of one set can be asserted side by side.
// `WalkContext.IsAllowed` applies exactly this to `FunctionAllows` before consulting the block-level
// stack; the two-sided differential drives the REAL one.
func SatWidened(effects: HashSet<string>, effect: string): bool {
    if effects.Contains(effect) {
        return true
    }

    prefix := effect + ":"
    for value in effects {
        if value.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) {
            return true
        }
    }

    return false
}

func SatConfig(profile: string, mode: string): ProjectConfig {
    config := ProjectFileParser.CreateDefault("attribute-policy-contract")
    language := config.Language
    language.Profile = profile
    systems := language.Systems
    systems.Mode = mode
    return config
}

func SatSink(profile: string, mode: string): SystemsFindingSink {
    config := SatConfig(profile, mode)
    sink := new SystemsFindingSink()
    sink.BeginAnalysis(config)
    return sink
}

func SatFunction(name: string, modifiers: Modifiers, attributes: List<AttributeNode>): FunctionDeclaration {
    return new FunctionDeclaration(name, new List<Parameter>(), null, null, null, null, null, modifiers, attributes, false, null, false, false, 7, 3)
}

func SatValidate(sink: SystemsFindingSink, name: string, modifiers: Modifiers, attributes: List<AttributeNode>, isHot: bool, isBoundary: bool) {
    policy := new SystemsAttributePolicy(sink)
    function := SatFunction(name, modifiers, attributes)
    policy.ValidateFunctionLevelAllows(SatSet(attributes), function, "attr.nl", "Owner." + name, isHot, isBoundary)
}

// Field readers, one per field a contract asserts on.
func SatCount(sink: SystemsFindingSink): int {
    ordered := sink.Ordered()
    return ordered.Length
}

func SatAt(sink: SystemsFindingSink, index: int): SystemsFinding {
    ordered := sink.Ordered()
    return ordered[index]
}

func SatCode(sink: SystemsFindingSink, index: int): string {
    finding := SatAt(sink, index)
    return finding.Code
}

func SatEffect(sink: SystemsFindingSink, index: int): string {
    finding := SatAt(sink, index)
    return finding.Effect
}

func SatSeverity(sink: SystemsFindingSink, index: int): string {
    finding := SatAt(sink, index)
    return finding.Severity
}

func SatMessage(sink: SystemsFindingSink, index: int): string {
    finding := SatAt(sink, index)
    return finding.Message
}

func SatLine(sink: SystemsFindingSink, index: int): int {
    finding := SatAt(sink, index)
    return finding.Line
}

func SatColumn(sink: SystemsFindingSink, index: int): int {
    finding := SatAt(sink, index)
    return finding.Column
}

func SatLength(sink: SystemsFindingSink, index: int): int {
    finding := SatAt(sink, index)
    return finding.Length
}

test "AN ATTRIBUTE NAME MATCHES WITHOUT ITS SUFFIX AND WITHOUT CASE" {
    assert SystemsAttributeSet.AttributeNameEquals("hot", "hot")
    assert SystemsAttributeSet.AttributeNameEquals("Hot", "hot")
    assert SystemsAttributeSet.AttributeNameEquals("HotAttribute", "hot")
    assert !SystemsAttributeSet.AttributeNameEquals("hotter", "hot")
}

test "THE SUFFIX IS STRIPPED ORDINALLY, SO A LOWER-CASE `attribute` IS PART OF THE NAME" {
    // The strip is ORDINAL and the comparison that follows is not, so `[HotAttribute]` is `[hot]`
    // but `[hotattribute]` and `[Hotattribute]` are attributes named `hotattribute`. This is the
    // original's behaviour and a contract rather than a comment, because the two halves of the rule
    // use different comparisons and reading the member quickly suggests otherwise.
    assert !SystemsAttributeSet.AttributeNameEquals("hotattribute", "hot")
    assert !SystemsAttributeSet.AttributeNameEquals("Hotattribute", "Hot")
    assert SystemsAttributeSet.AttributeNameEquals("hotattribute", "HOTATTRIBUTE")
}

test "THIS IS NOT NominalTypeInfoFactory.AttributeNameEquals, AND THE TWO DISAGREE" {
    // Folding them would make every `[HotAttribute]` and every `[Hot]` stop being read.
    assert SystemsAttributeSet.AttributeNameEquals("HotAttribute", "hot")
    assert !NominalTypeInfoFactory.AttributeNameEquals("HotAttribute", "hot")
    assert SystemsAttributeSet.AttributeNameEquals("Hot", "hot")
    assert !NominalTypeInfoFactory.AttributeNameEquals("Hot", "hot")
}

test "HAS AND GET ANSWER FOR THE FIRST ATTRIBUTE OF THE NAME" {
    attributes := new List<AttributeNode>()
    attributes.Add(SatBare("boundary"))
    attributes.Add(SatBare("HotAttribute"))
    set := SatSet(attributes)
    assert set.Has("hot")
    assert set.Has("boundary")
    assert !set.Has("trusted")
    first := set.Get("hot")
    assert first != null
}

test "GET RETURNS NULL AND GETALL RETURNS EMPTY WHEN THE NAME IS ABSENT" {
    set := SatSet(new List<AttributeNode>())
    assert set.Get("hot") == null
    assert set.GetAll("allow").Count == 0
}

test "GETALL RETURNS EVERY MATCH IN DECLARATION ORDER" {
    attributes := new List<AttributeNode>()
    first := SatArgs()
    SatNamed(first, "reason", SatText("\"a\""))
    second := SatArgs()
    SatNamed(second, "reason", SatText("\"b\""))
    attributes.Add(SatAttribute("allow", first))
    attributes.Add(SatAttribute("AllowAttribute", second))
    set := SatSet(attributes)
    all := set.GetAll("allow")
    assert all.Count == 2
    assert SystemsAttributeSet.AttributeString(all[0], "reason") == "a"
    assert SystemsAttributeSet.AttributeString(all[1], "reason") == "b"
}

test "A BARE-WORD ARGUMENT CLAIMS SOMETHING AND A STRING ARGUMENT DOES NOT" {
    bare := SatArgs()
    SatPositional(bare, SatWord("none"))
    assert SatSet(SatList(SatAttribute("alloc", bare))).AttributeHasArgument("alloc", "none")

    quoted := SatArgs()
    SatPositional(quoted, SatText("\"none\""))
    assert !SatSet(SatList(SatAttribute("alloc", quoted))).AttributeHasArgument("alloc", "none")
}

test "AN ARGUMENT TEST ON AN ABSENT ATTRIBUTE IS FALSE, NOT AN ERROR" {
    assert !SatSet(new List<AttributeNode>()).AttributeHasArgument("alloc", "none")
}

test "THE ARGUMENT NAME IS MATCHED WITHOUT CASE" {
    arguments := SatArgs()
    SatPositional(arguments, SatWord("NONE"))
    assert SatSet(SatList(SatAttribute("alloc", arguments))).AttributeHasArgument("alloc", "none")
}

test "A STRING-VALUED ARGUMENT ARRIVES UNQUOTED" {
    arguments := SatArgs()
    SatNamed(arguments, "reason", SatText("\"needed for the parser\""))
    attribute := SatAttribute("trusted", arguments)
    assert SystemsAttributeSet.AttributeString(attribute, "reason") == "needed for the parser"
    assert SystemsAttributeSet.AttributeString(attribute, "REASON") == "needed for the parser"
    assert SystemsAttributeSet.AttributeString(attribute, "owner") == null
}

test "A NON-STRING ARGUMENT IS NOT A REASON, AND THE FIRST MATCH STOPS THE SEARCH" {
    arguments := SatArgs()
    SatNamed(arguments, "reason", SatWord("bare"))
    SatNamed(arguments, "reason", SatText("\"real\""))
    assert SystemsAttributeSet.AttributeString(SatAttribute("allow", arguments), "reason") == null
}

test "UNQUOTING NEEDS BOTH ENDS AND AT LEAST TWO CHARACTERS" {
    assert SystemsAttributeSet.Unquote("\"x\"") == "x"
    assert SystemsAttributeSet.Unquote("\"\"") == ""
    assert SystemsAttributeSet.Unquote("\"") == "\""
    assert SystemsAttributeSet.Unquote("\"x") == "\"x"
    assert SystemsAttributeSet.Unquote("x") == "x"
}

test "AN UNNAMED BARE WORD IS THE EFFECT" {
    arguments := SatArgs()
    SatPositional(arguments, SatWord("alloc"))
    effects := SatEffects(arguments)
    assert effects.Count == 1
    assert effects.Contains("alloc")
}

test "A NAMED ARGUMENT CONTRIBUTES BOTH FORMS, AND THE SECOND IS WHAT THE WALK WIDENS ONTO" {
    arguments := SatArgs()
    SatNamed(arguments, "alloc", SatWord("pooled"))
    effects := SatEffects(arguments)
    assert effects.Count == 2
    assert effects.Contains("alloc")
    assert effects.Contains("alloc:pooled")
    // BOTH TESTERS, ONE SET: exact membership and the walk's prefix widening.
    assert SatWidened(effects, "alloc")
}

test "A NAMED ARGUMENT WITH A STRING VALUE CONTRIBUTES ONLY ITS NAME" {
    arguments := SatArgs()
    SatNamed(arguments, "alloc", SatText("\"pooled\""))
    effects := SatEffects(arguments)
    assert effects.Count == 1
    assert effects.Contains("alloc")
}

test "THE SET'S COMPARER IS OrdinalIgnoreCase, WHICH IS WHAT MAKES THE EXACT TEST FORGIVING" {
    arguments := SatArgs()
    SatPositional(arguments, SatWord("ALLOC"))
    effects := SatEffects(arguments)
    // The callee-policy rule asks exactly this question at the merge site.
    assert effects.Contains("alloc")
    assert SatWidened(effects, "alloc")
}

test "THE EXACT TEST IS NOT THE WIDENING TEST, AND ONE SET SHOWS BOTH ANSWERS" {
    arguments := SatArgs()
    SatNamed(arguments, "alloc", SatWord("pooled"))
    effects := SatEffects(arguments)
    // A set built only from `alloc:pooled` would separate them; the two-form insertion is what keeps
    // the exact test answering, and removing it would silently un-waive every callee rule.
    assert effects.Contains("alloc:pooled")
    assert SatWidened(effects, "alloc")
    assert !effects.Contains("pool")
    assert !SatWidened(effects, "pool")
}

test "reason AND owner ARE EXCLUDED, AND EXCLUDED ORDINALLY" {
    arguments := SatArgs()
    SatNamed(arguments, "reason", SatText("\"why\""))
    SatNamed(arguments, "owner", SatText("\"who\""))
    SatPositional(arguments, SatWord("alloc"))
    effects := SatEffects(arguments)
    assert effects.Count == 1
    assert effects.Contains("alloc")

    // The attribute NAME is matched without case but these two argument names are not: `Reason`
    // becomes an effect. Preserved, not harmonised.
    capitalised := SatArgs()
    SatNamed(capitalised, "Reason", SatText("\"why\""))
    capitalisedEffects := SatEffects(capitalised)
    assert capitalisedEffects.Count == 1
    assert capitalisedEffects.Contains("Reason")
}

test "AN ARGUMENT THAT IS NEITHER NAMED NOR A BARE WORD CONTRIBUTES NOTHING" {
    arguments := SatArgs()
    SatPositional(arguments, SatText("\"alloc\""))
    assert SatEffects(arguments).Count == 0
}

test "EVERY [allow] ON THE DECLARATION CONTRIBUTES TO ONE SET" {
    attributes := new List<AttributeNode>()
    first := SatArgs()
    SatPositional(first, SatWord("alloc"))
    second := SatArgs()
    SatPositional(second, SatWord("pool"))
    attributes.Add(SatAttribute("allow", first))
    attributes.Add(SatAttribute("allow", second))
    effects := SatSet(attributes).AllowEffects()
    assert effects.Count == 2
    assert effects.Contains("alloc")
    assert effects.Contains("pool")
}

test "A DECLARATION WITH NO [allow] HAS AN EMPTY EFFECT SET" {
    assert SatSet(SatList(SatBare("hot"))).AllowEffects().Count == 0
}

test "A FUNCTION-LEVEL [allow] WITH NO REASON IS AN ERROR AT THE DECLARATION" {
    arguments := SatArgs()
    SatPositional(arguments, SatWord("alloc"))
    sink := SatSink("systems", "strict")
    SatValidate(sink, "load", Modifiers.None, SatList(SatAttribute("allow", arguments)), false, false)
    assert SatCount(sink) == 1
    assert SatCode(sink, 0) == "NSYS180"
    assert SatEffect(sink, 0) == "effectPolicy"
    assert SatSeverity(sink, 0) == "error"
    assert SatMessage(sink, 0) == "function-level [allow] requires a reason"
    assert SatLine(sink, 0) == 7
    assert SatColumn(sink, 0) == 3
    assert SatLength(sink, 0) == 4
}

test "A REASON SILENCES THE FIRST ARM AND A WHITESPACE REASON DOES NOT" {
    good := SatArgs()
    SatNamed(good, "reason", SatText("\"measured\""))
    quiet := SatSink("systems", "strict")
    SatValidate(quiet, "load", Modifiers.None, SatList(SatAttribute("allow", good)), false, false)
    assert SatCount(quiet) == 0

    blank := SatArgs()
    SatNamed(blank, "reason", SatText("\"   \""))
    loud := SatSink("systems", "strict")
    SatValidate(loud, "load", Modifiers.None, SatList(SatAttribute("allow", blank)), false, false)
    assert SatCount(loud) == 1
}

test "A PUBLIC WAIVER ALSO NEEDS AN OWNER, AND THE TWO ARMS ARE INDEPENDENT" {
    arguments := SatArgs()
    SatNamed(arguments, "reason", SatText("\"measured\""))
    sink := SatSink("systems", "strict")
    SatValidate(sink, "Load", Modifiers.Public, SatList(SatAttribute("allow", arguments)), false, false)
    assert SatCount(sink) == 1
    assert SatMessage(sink, 0) == "public function-level [allow] requires an owner"
}

test "A WAIVER WITH NEITHER FIELD REPORTS BOTH, REASON FIRST" {
    sink := SatSink("systems", "strict")
    SatValidate(sink, "Load", Modifiers.Public, SatList(SatBare("allow")), false, false)
    assert SatCount(sink) == 2
    assert SatMessage(sink, 0) == "function-level [allow] requires a reason"
    assert SatMessage(sink, 1) == "public function-level [allow] requires an owner"
}

test "TWO WAIVERS REPORT TWICE, IN DECLARATION ORDER" {
    attributes := new List<AttributeNode>()
    attributes.Add(SatBare("allow"))
    attributes.Add(SatBare("allow"))
    sink := SatSink("systems", "strict")
    SatValidate(sink, "load", Modifiers.None, attributes, false, false)
    assert SatCount(sink) == 2
}

test "AN UPPER-CASE NAME IS PUBLIC WITHOUT THE MODIFIER" {
    arguments := SatArgs()
    SatNamed(arguments, "reason", SatText("\"measured\""))
    sink := SatSink("systems", "strict")
    SatValidate(sink, "Load", Modifiers.None, SatList(SatAttribute("allow", arguments)), false, false)
    assert SatCount(sink) == 1
}

test "THE PUBLIC TEST IS WIDER THAN VisibilityConventions.IsExportedIdentifier(name, modifiers)" {
    // An upper-case name carrying `private` is NOT exported by the two-argument helper, but IS
    // public to this rule — a waiver on `Load` is worth an owner however the file spells visibility.
    assert !VisibilityConventions.IsExportedIdentifier("Load", Modifiers.Private)
    assert SystemsAttributePolicy.IsPublicApi(SatFunction("Load", Modifiers.Private, new List<AttributeNode>()))
    assert VisibilityConventions.IsExportedIdentifier("Load")
}

test "A LOWER-CASE NAME WITH NO MODIFIER IS NOT PUBLIC" {
    assert !SystemsAttributePolicy.IsPublicApi(SatFunction("load", Modifiers.None, new List<AttributeNode>()))
    assert SystemsAttributePolicy.IsPublicApi(SatFunction("load", Modifiers.Public, new List<AttributeNode>()))
}

test "THE SINK STILL DOWNGRADES ON TOP OF A FLAT ERROR" {
    boundary := SatSink("systems", "strict")
    SatValidate(boundary, "load", Modifiers.None, SatList(SatBare("allow")), false, true)
    assert SatSeverity(boundary, 0) == "warning"

    hotBoundary := SatSink("systems", "strict")
    SatValidate(hotBoundary, "load", Modifiers.None, SatList(SatBare("allow")), true, true)
    assert SatSeverity(hotBoundary, 0) == "error"

    audit := SatSink("systems", "audit")
    SatValidate(audit, "load", Modifiers.None, SatList(SatBare("allow")), true, false)
    assert SatSeverity(audit, 0) == "warning"
}

test "THE WAIVER FINDING IS REPORTED IN A DEFAULT-PROFILE PROJECT TOO" {
    // The rule prefers Error unconditionally; it is not gated on the systems profile the way the
    // policy-labelled rules are.
    sink := SatSink("default", "strict")
    SatValidate(sink, "load", Modifiers.None, SatList(SatBare("allow")), false, false)
    assert SatCount(sink) == 1
    assert SatSeverity(sink, 0) == "error"
}

// Native contracts for THE WAIVER STACK and for the three declaration arms F18 moved.
//
// SEVEN THINGS THESE ARE EASY TO GET WRONG.
//
// (1) THE PREFIX WIDENING IS REACHABLE ONLY THROUGH A BLOCK-LEVEL WAIVER, and the reason is the
// two-form insertion above: `AllowEffects()` always puts the bare name in beside `name:value`, so a
// function-level set never NEEDS the prefix arm, while a block's written word list has no bare-name
// companion and always does.
//
// (2) EVERY LEVEL IS CASE-INSENSITIVE, block-level included, and the block sets are built here
// rather than handed in — a set built with the wrong comparer would silently stop waiving.
//
// (3) POP REMOVES EXACTLY THE LAST PUSH and an unmatched pop is tolerated, because a walk that pops
// more than it pushed is a bug in the walk and not a reason to throw at the user.
//
// (4) THE TWO STATE-MACHINE ARMS ARE INDEPENDENT AND BOTH FIRE ON AN `async` ITERATOR, at one
// position, async first.
//
// (5) THE STATE-MACHINE MODIFIERS ARE READ AS BITS TAKEN FROM THE ENUM MEMBERS, not from written
// numbers, and the contracts construct declarations with `Modifiers.Async` and `Modifiers.Generator`
// themselves — so the mapping is pinned end to end rather than assumed at both ends.
//
// (6) THE `[trusted]` METADATA ARM IS ONE FINDING FOR ANY MISSING FIELD, not one per field, and
// `expires` is not one of the fields.
//
// (7) THE UNSAFE-BLOCK ARM IS THE ONLY ONE OF THE THREE THAT A WAIVER CAN SILENCE. The two
// declaration arms prefer `Error` unconditionally, because `[trusted]` IS the waiver mechanism.

func SatAllows(): SystemsAllowStack {
    return new SystemsAllowStack(new HashSet<string>(StringComparer.OrdinalIgnoreCase))
}

func SatAllowsOf(effect: string): SystemsAllowStack {
    effects := new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    effects.Add(effect)
    return new SystemsAllowStack(effects)
}

func SatWords(word: string): List<string> {
    words := new List<string>()
    words.Add(word)
    return words
}

test "THE ALLOW STACK ANSWERS FROM THE FUNCTION-LEVEL SET, WITHOUT CASE" {
    allows := SatAllowsOf("ALLOC")
    assert allows.IsAllowed("alloc")
    assert allows.IsAllowed("Alloc")
    assert !allows.IsAllowed("pool")
}

test "A BLOCK-LEVEL WAIVER ANSWERS WHILE IT IS PUSHED AND STOPS ANSWERING WHEN IT IS POPPED" {
    allows := SatAllows()
    assert !allows.IsAllowed("trap")
    allows.Push(SatWords("trap"))
    assert allows.IsAllowed("trap")
    allows.Pop()
    assert !allows.IsAllowed("trap")
}

test "A BLOCK-LEVEL WAIVER IS CASE-INSENSITIVE TOO" {
    allows := SatAllows()
    allows.Push(SatWords("TRAP"))
    assert allows.IsAllowed("trap")
}

test "NESTED BLOCKS BOTH ANSWER, AND ONE POP REMOVES EXACTLY THE LAST" {
    allows := SatAllows()
    allows.Push(SatWords("alloc"))
    allows.Push(SatWords("trap"))
    assert allows.IsAllowed("alloc")
    assert allows.IsAllowed("trap")
    allows.Pop()
    assert allows.IsAllowed("alloc")
    assert !allows.IsAllowed("trap")
}

test "AN UNMATCHED POP IS TOLERATED AND CHANGES NOTHING" {
    allows := SatAllowsOf("alloc")
    allows.Pop()
    allows.Pop()
    assert allows.IsAllowed("alloc")
}

test "THE PREFIX WIDENING IS REACHABLE THROUGH A BLOCK-LEVEL WAIVER" {
    allows := SatAllows()
    allows.Push(SatWords("trap:proved"))
    assert allows.IsAllowed("trap")
    assert !allows.IsAllowed("alloc")
}

test "THE PREFIX WIDENING IS NOT REACHABLE THROUGH ANY SET AllowEffects CAN BUILD" {
    arguments := SatArgs()
    SatNamed(arguments, "alloc", SatWord("pooled"))
    effects := SatEffects(arguments)
    allows := new SystemsAllowStack(effects)
    assert effects.Contains("alloc")
    assert effects.Contains("alloc:pooled")
    assert allows.IsAllowed("alloc")
    assert SatWidened(effects, "alloc")
}

test "A QUALIFIED BLOCK WAIVER DOES NOT WIDEN ACROSS EFFECTS" {
    allows := SatAllows()
    allows.Push(SatWords("alloc:pooled"))
    assert allows.IsAllowed("alloc")
    assert !allows.IsAllowed("pool")
    assert !allows.IsAllowed("allocation")
}

test "A [hot] ASYNC FUNCTION ALLOCATES AND IS TOLD SO AT ITS OWN DECLARATION" {
    sink := SatSink("systems", "strict")
    policy := new SystemsAttributePolicy(sink)
    function := SatFunction("Read", Modifiers.Async, new List<AttributeNode>())
    assert policy.ValidateHotStateMachines(function, "attr.nl", "Owner.Read", true, false)
    assert SatCount(sink) == 1
    assert SatCode(sink, 0) == "NSYS010"
    assert SatEffect(sink, 0) == "allocation"
    assert SatMessage(sink, 0) == "[hot] async functions allocate or require async machinery in Systems N# v1"
    assert SatSeverity(sink, 0) == "error"
    assert SatLine(sink, 0) == 7
    assert SatColumn(sink, 0) == 3
    assert SatLength(sink, 0) == 4
}

test "A [hot] ITERATOR IS THE SECOND ARM AND ITS SENTENCE IS NOT THE FIRST ONE'S" {
    sink := SatSink("systems", "strict")
    policy := new SystemsAttributePolicy(sink)
    function := SatFunction("Walk", Modifiers.Generator, new List<AttributeNode>())
    assert policy.ValidateHotStateMachines(function, "attr.nl", "Owner.Walk", true, false)
    assert SatCount(sink) == 1
    assert SatMessage(sink, 0) == "[hot] iterator functions allocate state machines in Systems N# v1"
}

test "A [hot] ASYNC ITERATOR GETS BOTH ARMS AT ONE POSITION, ASYNC FIRST" {
    sink := SatSink("systems", "strict")
    policy := new SystemsAttributePolicy(sink)
    both := Modifiers.Async | Modifiers.Generator
    function := SatFunction("Stream", both, new List<AttributeNode>())
    assert policy.ValidateHotStateMachines(function, "attr.nl", "Owner.Stream", true, false)
    assert SatCount(sink) == 2
    assert SatMessage(sink, 0) == "[hot] async functions allocate or require async machinery in Systems N# v1"
    assert SatMessage(sink, 1) == "[hot] iterator functions allocate state machines in Systems N# v1"
    assert SatLine(sink, 0) == SatLine(sink, 1)
}

test "A COLD ASYNC FUNCTION IS SILENT AND DOES NOT ALLOCATE A STATE MACHINE FOR THIS RULE" {
    sink := SatSink("systems", "strict")
    policy := new SystemsAttributePolicy(sink)
    function := SatFunction("Read", Modifiers.Async, new List<AttributeNode>())
    assert !policy.ValidateHotStateMachines(function, "attr.nl", "Owner.Read", false, false)
    assert SatCount(sink) == 0
}

test "A [hot] FUNCTION WITH NEITHER MODIFIER IS SILENT" {
    sink := SatSink("systems", "strict")
    policy := new SystemsAttributePolicy(sink)
    function := SatFunction("Read", Modifiers.Public, new List<AttributeNode>())
    assert !policy.ValidateHotStateMachines(function, "attr.nl", "Owner.Read", true, false)
    assert SatCount(sink) == 0
}

test "A [trusted] WRAPPER MISSING ANY ONE FIELD GETS ONE METADATA FINDING, NOT THREE" {
    sink := SatSink("systems", "strict")
    policy := new SystemsAttributePolicy(sink)
    function := SatFunction("Copy", Modifiers.None, new List<AttributeNode>())
    policy.ValidateTrustedFunction(null, "team", "2026-01-01", true, function, "attr.nl", "Owner.Copy", false, false)
    assert SatCount(sink) == 1
    assert SatCode(sink, 0) == "NSYS100"
    assert SatEffect(sink, 0) == "memorySafety"
    assert SatMessage(sink, 0) == "[trusted] requires reason, owner, and review metadata"
    assert SatLength(sink, 0) == 4
}

test "A BLANK FIELD IS A MISSING FIELD, AND expires IS NOT ONE OF THE THREE" {
    blank := SatSink("systems", "strict")
    policyBlank := new SystemsAttributePolicy(blank)
    function := SatFunction("Copy", Modifiers.None, new List<AttributeNode>())
    policyBlank.ValidateTrustedFunction("   ", "team", "2026-01-01", true, function, "attr.nl", "Owner.Copy", false, false)
    assert SatCount(blank) == 1
    complete := SatSink("systems", "strict")
    policyComplete := new SystemsAttributePolicy(complete)
    policyComplete.ValidateTrustedFunction("why", "team", "2026-01-01", true, function, "attr.nl", "Owner.Copy", false, false)
    assert SatCount(complete) == 0
}

test "THE TWO TRUSTED ARMS ARE INDEPENDENT AND BOTH FIRE AT ONE POSITION" {
    sink := SatSink("systems", "strict")
    policy := new SystemsAttributePolicy(sink)
    function := SatFunction("Copy", Modifiers.None, new List<AttributeNode>())
    policy.ValidateTrustedFunction(null, null, null, false, function, "attr.nl", "Owner.Copy", false, false)
    assert SatCount(sink) == 2
    assert SatMessage(sink, 0) == "[trusted] requires reason, owner, and review metadata"
    assert SatMessage(sink, 1) == "[trusted] wrappers must declare [memory(safe)] for Systems N# v1"
    assert SatLine(sink, 0) == SatLine(sink, 1)
}

test "AN UNSAFE BLOCK IS SILENT ONLY INSIDE A TRUSTED MEMORY-SAFE WRAPPER" {
    quiet := SatSink("systems", "strict")
    policyQuiet := new SystemsAttributePolicy(quiet)
    policyQuiet.ReportUnsafeBlock(true, true, SatAllows(), 5, 9, "attr.nl", "Owner.Copy", false, false)
    assert SatCount(quiet) == 0
    halfTrusted := SatSink("systems", "strict")
    policyHalf := new SystemsAttributePolicy(halfTrusted)
    policyHalf.ReportUnsafeBlock(true, false, SatAllows(), 5, 9, "attr.nl", "Owner.Copy", false, false)
    assert SatCount(halfTrusted) == 1
    assert SatCode(halfTrusted, 0) == "NSYS100"
    assert SatEffect(halfTrusted, 0) == "memorySafety"
    assert SatMessage(halfTrusted, 0) == "unsafe block requires a [trusted] memory-safe wrapper in systems code"
    assert SatLine(halfTrusted, 0) == 5
    assert SatColumn(halfTrusted, 0) == 9
    assert SatLength(halfTrusted, 0) == 1
}

test "THE UNSAFE-BLOCK ARM IS A POLICY FINDING WHILE THE TRUSTED ARMS ARE NOT" {
    waived := SatSink("systems", "strict")
    policyWaived := new SystemsAttributePolicy(waived)
    policyWaived.ReportUnsafeBlock(false, false, SatAllowsOf("memorySafety"), 5, 9, "attr.nl", "Owner.Copy", false, false)
    assert SatCount(waived) == 0
    downgraded := SatSink("systems", "strict")
    policyDowngraded := new SystemsAttributePolicy(downgraded)
    policyDowngraded.ReportUnsafeBlock(false, false, SatAllows(), 5, 9, "attr.nl", "Owner.Copy", false, true)
    assert SatCount(downgraded) == 1
    assert SatSeverity(downgraded, 0) == "warning"
    function := SatFunction("Copy", Modifiers.None, new List<AttributeNode>())
    unwaived := SatSink("systems", "strict")
    policyUnwaived := new SystemsAttributePolicy(unwaived)
    policyUnwaived.ValidateTrustedFunction(null, null, null, false, function, "attr.nl", "Owner.Copy", false, false)
    assert SatCount(unwaived) == 2
}
