namespace NSharpLang.Compiler.Performance

import System.Collections.Generic
import NSharpLang.Compiler
import NSharpLang.Compiler.Ast

// Native contracts for WHAT A DECLARED SURFACE MAY EXPOSE.
//
// These two rules were 82 lines inside `SystemsAnalyzer.cs` — `CheckFunctionSurface` (60) and
// `CheckRefLikeFields` (22) — reached from three call sites, and between them they decide four of the
// analyzer's codes. Only ONE of the four is live in the 71-target corpus (NSYS070, three findings);
// NSYS080's two arms and NSYS170 are corpus-silent, which is why these contracts and the purpose-built
// fixtures are the direct pinning and the corpus is only a regression pin.
//
// NINE THINGS THIS NEIGHBOURHOOD IS EASY TO GET WRONG, ALL STATED BELOW.
//
// (1) THE GATE IS `[hot]` OR `[boundary]` AND NOTHING ELSE. A plain function's signature is never
// judged, even in a systems project — unlike the balance rules, whose gate the profile opens.
//
// (2) THE PREFIX IS THE RULE'S, NOT THE SINK'S. `[hot]` outranks `[boundary]` in the sentence, and a
// function carrying both reads `[hot]`. The sink's policy LABEL is a different string with a third
// arm; a finding can read `[boundary] parameter ...` while its label says `systems:strict`.
//
// (3) THREE PREFERRED SEVERITIES IN ONE MEMBER. Hostile surface prefers Error in hot and Warning at a
// boundary; the Result-ABI arm prefers a FLAT Warning even in hot; the ref-like-return arm prefers a
// FLAT Error. Folding any of them into the sink's downgrade would change the other two.
//
// (4) THE UNDERLINE IS THE DECLARED NAME'S WIDTH; THE REPORTED FUNCTION IS THE QUALIFIED NAME. A
// finding about `Buf.Fill` underlines four characters, not seven.
//
// (5) A PARAMETER REPORTS AT ITS OWN POSITION AND UNDER ITS OWN WIDTH. Three hostile parameters
// produce three findings, in declaration order.
//
// (6) THE RESULT-ABI ARM IS ASKED OF THE NULLABLE RETURN TYPE DIRECTLY, so a function with no written
// return type reaches it and answers silently rather than being guarded from outside.
//
// (7) THE REF-LIKE-RETURN ARM IS HOT-ONLY AND LIFETIME-CANCELLED. A `[boundary]` returning a `Span`
// is silent; a `[hot]` one is silent too once a `returns` lifetime is written.
//
// (8) A `ref struct` IS NOT ASKED ABOUT ITS FIELDS AT ALL, and a field with no parsed type is skipped
// rather than guessed at.
//
// (9) A FIELD FINDING IS A TYPE FINDING: it names the TYPE as its function and its call path, has no
// `[hot]` label arm, and takes no preferred severity — so it is an error in a default-profile project
// where a function finding would have been downgraded.
func SspConfig(profile: string, mode: string): ProjectConfig {
    config := ProjectFileParser.CreateDefault("surface-policy-contract")
    language := config.Language
    language.Profile = profile
    systems := language.Systems
    systems.Mode = mode
    return config
}

func SspSink(profile: string, mode: string): SystemsFindingSink {
    sink := new SystemsFindingSink()
    sink.BeginAnalysis(SspConfig(profile, mode))
    return sink
}

// `Frame` is a `ref struct` — registered in BOTH sets, as the declaration walk does — and `Vec` is an
// ordinary struct, so a shape built from `Vec` sizes like a struct without also being ref-like.
func SspTypes(): SystemsTypePolicy {
    policy := new SystemsTypePolicy()
    policy.RegisterStructType("Frame")
    policy.RegisterRefStructType("Frame")
    policy.RegisterStructType("Vec")
    return policy
}

func SspPolicy(sink: SystemsFindingSink): SystemsSurfacePolicy {
    return new SystemsSurfacePolicy(SspTypes(), sink)
}

func SspSimple(name: string): SimpleTypeReference {
    return new SimpleTypeReference(name, 1, 1)
}

func SspGeneric(name: string, first: TypeReference, second: TypeReference): GenericTypeReference {
    arguments := new List<TypeReference>()
    arguments.Add(first)
    arguments.Add(second)
    return new GenericTypeReference(name, arguments, 1, 1)
}

func SspGeneric1(name: string, argument: TypeReference): GenericTypeReference {
    arguments := new List<TypeReference>()
    arguments.Add(argument)
    return new GenericTypeReference(name, arguments, 1, 1)
}

// A NAMED HOSTILE CONSTRUCTOR, whose reason is its own name and does NOT depend on hotness — unlike a
// bare unsummarized name, which a `[boundary]` accepts. Using the named shape is what lets the same
// signature be compared hot against boundary.
func SspHostile(): GenericTypeReference {
    return SspGeneric1("List", SspSimple("int"))
}

func SspParameter(name: string, typeReference: TypeReference, line: int, column: int): Parameter {
    return new Parameter(name, typeReference, null, false, ParameterModifier.None, null, line, column, false, null)
}

func SspNoParameters(): List<Parameter> {
    return new List<Parameter>()
}

func SspOneParameter(parameter: Parameter): List<Parameter> {
    parameters := new List<Parameter>()
    parameters.Add(parameter)
    return parameters
}

func SspFunction(name: string, parameters: List<Parameter>, returnType: TypeReference?): FunctionDeclaration {
    return new FunctionDeclaration(name, parameters, returnType, null, null, null, null, Modifiers.None, new List<AttributeNode>(), false, null, false, false, 12, 5)
}

func SspField(name: string, typeReference: TypeReference?, line: int, column: int): FieldDeclaration {
    return new FieldDeclaration(name, typeReference, null, Modifiers.None, PropertyModifier.None, new List<AttributeNode>(), line, column)
}

func SspMembers(member: Declaration): List<Declaration> {
    members := new List<Declaration>()
    members.Add(member)
    return members
}

// Field readers, one per field a contract asserts on. They exist because a property read chained onto
// a call result does not emit — the recorded chained-read decline — and binding the finding to a local
// in every contract would bury the assertion it is making.
func SspCount(sink: SystemsFindingSink): int {
    ordered := sink.Ordered()
    return ordered.Length
}

func SspAt(sink: SystemsFindingSink, index: int): SystemsFinding {
    ordered := sink.Ordered()
    return ordered[index]
}

func SspCode(sink: SystemsFindingSink): string {
    finding := SspAt(sink, 0)
    return finding.Code
}

func SspSeverity(sink: SystemsFindingSink): string {
    finding := SspAt(sink, 0)
    return finding.Severity
}

func SspMessage(sink: SystemsFindingSink): string {
    finding := SspAt(sink, 0)
    return finding.Message
}

func SspPolicyLabel(sink: SystemsFindingSink): string? {
    finding := SspAt(sink, 0)
    return finding.Policy
}

func SspLine(sink: SystemsFindingSink): int {
    finding := SspAt(sink, 0)
    return finding.Line
}

func SspColumn(sink: SystemsFindingSink): int {
    finding := SspAt(sink, 0)
    return finding.Column
}

func SspLength(sink: SystemsFindingSink): int {
    finding := SspAt(sink, 0)
    return finding.Length
}

func SspFunctionName(sink: SystemsFindingSink): string? {
    finding := SspAt(sink, 0)
    return finding.Function
}

func SspEffect(sink: SystemsFindingSink): string {
    finding := SspAt(sink, 0)
    return finding.Effect
}

func SspMessageAt(sink: SystemsFindingSink, index: int): string {
    finding := SspAt(sink, index)
    return finding.Message
}

func SspColumnAt(sink: SystemsFindingSink, index: int): int {
    finding := SspAt(sink, index)
    return finding.Column
}

func SspCallPathFirst(sink: SystemsFindingSink): string {
    finding := SspAt(sink, 0)
    path := finding.CallPath
    return path[0]
}

// A `[hot]` function taking one hostile parameter, the shape most of these contracts vary.
func SspCheckOneParameter(sink: SystemsFindingSink, parameterType: TypeReference, isHot: bool, isBoundary: bool) {
    policy := SspPolicy(sink)
    parameters := SspOneParameter(SspParameter("items", parameterType, 12, 20))
    policy.CheckFunctionSurface(SspFunction("Fill", parameters, null), "buf.nl", "Buf.Fill", isHot, isBoundary)
}

func SspCheckReturn(sink: SystemsFindingSink, returnType: TypeReference?, isHot: bool, isBoundary: bool) {
    policy := SspPolicy(sink)
    policy.CheckFunctionSurface(SspFunction("Fill", SspNoParameters(), returnType), "buf.nl", "Buf.Fill", isHot, isBoundary)
}

func SspCheckReturnLifetime(sink: SystemsFindingSink, returnType: TypeReference?, lifetime: string?, isHot: bool, isBoundary: bool) {
    policy := SspPolicy(sink)
    function := SspFunction("Fill", SspNoParameters(), returnType)
    function.ReturnLifetime = lifetime
    policy.CheckFunctionSurface(function, "buf.nl", "Buf.Fill", isHot, isBoundary)
}

func SspCheckField(sink: SystemsFindingSink, typeReference: TypeReference?, isRefStruct: bool) {
    policy := SspPolicy(sink)
    policy.CheckRefLikeFields("frame.nl", "Holder", isRefStruct, SspMembers(SspField("view", typeReference, 30, 9)))
}

// A `Result<T,E>` whose payloads push the copy shape past the v1 hot-path guidance of 128 bytes: two
// nested `Result<Vec,Vec>` at 16 + 32 + 32 each, so 16 + 80 + 80 = 176.
func SspWideResult(): GenericTypeReference {
    return SspGeneric("Result", SspGeneric("Result", SspSimple("Vec"), SspSimple("Vec")), SspGeneric("Result", SspSimple("Vec"), SspSimple("Vec")))
}

test "A FUNCTION THAT PROMISES NEITHER HOT NOR BOUNDARY IS NOT ASKED AT ALL" {
    sink := SspSink("systems", "strict")
    SspCheckOneParameter(sink, SspHostile(), false, false)
    assert SspCount(sink) == 0
}

test "A HOT SIGNATURE REPORTS THE HOSTILE PARAMETER AS AN ERROR" {
    sink := SspSink("systems", "strict")
    SspCheckOneParameter(sink, SspHostile(), true, false)
    assert SspCount(sink) == 1
    assert SspCode(sink) == "NSYS070"
    assert SspEffect(sink) == "boundaryLeak"
    assert SspSeverity(sink) == "error"
}

test "A BOUNDARY SIGNATURE REPORTS THE SAME PARAMETER AS A WARNING" {
    sink := SspSink("systems", "strict")
    SspCheckOneParameter(sink, SspHostile(), false, true)
    assert SspCount(sink) == 1
    assert SspSeverity(sink) == "warning"
}

test "THE PREFIX SAYS HOT WHEN THE FUNCTION IS BOTH HOT AND BOUNDARY" {
    sink := SspSink("systems", "strict")
    SspCheckOneParameter(sink, SspHostile(), true, true)
    assert SspMessage(sink) == "[hot] parameter 'items' exposes a systems-hostile type: List"
    assert SspSeverity(sink) == "error"
}

test "THE PREFIX SAYS BOUNDARY WHEN ONLY BOUNDARY IS PROMISED" {
    sink := SspSink("systems", "strict")
    SspCheckOneParameter(sink, SspHostile(), false, true)
    assert SspMessage(sink) == "[boundary] parameter 'items' exposes a systems-hostile type: List"
}

test "THE PREFIX IS NOT THE POLICY LABEL AND THE TWO CAN DISAGREE" {
    // The sentence reads `[boundary]` while the label reads the project's mode: they are different
    // strings decided by different owners, and a reader sees both.
    sink := SspSink("systems", "strict")
    SspCheckOneParameter(sink, SspHostile(), false, true)
    assert SspMessage(sink) == "[boundary] parameter 'items' exposes a systems-hostile type: List"
    assert SspPolicyLabel(sink) == "systems:strict"
}

test "A HOT FINDING WEARS THE HOT LABEL AND THE HOT PREFIX TOGETHER" {
    sink := SspSink("systems", "strict")
    SspCheckOneParameter(sink, SspHostile(), true, false)
    assert SspPolicyLabel(sink) == "[hot]"
}

test "THE PARAMETER FINDING IS REPORTED AT THE PARAMETER'S OWN POSITION AND WIDTH" {
    sink := SspSink("systems", "strict")
    SspCheckOneParameter(sink, SspHostile(), true, false)
    assert SspLine(sink) == 12
    assert SspColumn(sink) == 20
    assert SspLength(sink) == 5
}

test "EVERY HOSTILE PARAMETER REPORTS, IN DECLARATION ORDER" {
    sink := SspSink("systems", "strict")
    policy := SspPolicy(sink)
    parameters := new List<Parameter>()
    parameters.Add(SspParameter("a", SspGeneric1("List", SspSimple("int")), 12, 20))
    parameters.Add(SspParameter("b", SspSimple("int"), 12, 30))
    parameters.Add(SspParameter("c", SspGeneric("Dictionary", SspSimple("string"), SspSimple("int")), 12, 40))
    policy.CheckFunctionSurface(SspFunction("Fill", parameters, null), "buf.nl", "Buf.Fill", true, false)
    assert SspCount(sink) == 2
    assert SspMessageAt(sink, 0) == "[hot] parameter 'a' exposes a systems-hostile type: List"
    assert SspColumnAt(sink, 0) == 20
    assert SspMessageAt(sink, 1) == "[hot] parameter 'c' exposes a systems-hostile type: Dictionary"
    assert SspColumnAt(sink, 1) == 40
}

test "A HOSTILE RETURN TYPE REPORTS AT THE FUNCTION AND UNDER THE DECLARED NAME'S WIDTH" {
    // The reported function is the QUALIFIED name; the underline is the DECLARED name — `Fill`, four
    // characters, not the seven of `Buf.Fill`.
    sink := SspSink("systems", "strict")
    SspCheckReturn(sink, SspHostile(), true, false)
    assert SspCount(sink) == 1
    assert SspMessage(sink) == "[hot] return type exposes a systems-hostile shape: List"
    assert SspFunctionName(sink) == "Buf.Fill"
    assert SspLine(sink) == 12
    assert SspColumn(sink) == 5
    assert SspLength(sink) == 4
}

test "A FUNCTION WITH NO WRITTEN RETURN TYPE HAS NO RETURN SURFACE TO JUDGE" {
    sink := SspSink("systems", "strict")
    SspCheckReturn(sink, null, true, false)
    assert SspCount(sink) == 0
}

test "AN OVERSIZED RESULT PREFERS A WARNING EVEN IN A HOT FUNCTION" {
    // The one arm whose severity does not follow hotness: guidance, not a broken promise.
    sink := SspSink("systems", "strict")
    SspCheckReturn(sink, SspWideResult(), true, false)
    assert SspCount(sink) == 1
    assert SspCode(sink) == "NSYS170"
    assert SspEffect(sink) == "resultAbi"
    assert SspSeverity(sink) == "warning"
}

test "THE RESULT-ABI SENTENCE IS THE TYPE POLICY'S OWN AND CARRIES THE ESTIMATED SIZE" {
    sink := SspSink("systems", "strict")
    SspCheckReturn(sink, SspWideResult(), true, false)
    assert SspMessage(sink) == "Result<T,E> copy shape is estimated at 176 bytes, above the v1 hot-path guidance of 128 bytes"
}

test "A HOT FUNCTION RETURNING A REF-LIKE VIEW WITHOUT A LIFETIME IS AN ERROR" {
    sink := SspSink("systems", "strict")
    SspCheckReturnLifetime(sink, SspSimple("Span"), null, true, false)
    assert SspCount(sink) == 1
    assert SspCode(sink) == "NSYS080"
    assert SspEffect(sink) == "lifetime"
    assert SspSeverity(sink) == "error"
    assert SspMessage(sink) == "[hot] function returns a ref-like value with an unknown lifetime"
}

test "A WRITTEN RETURN LIFETIME CANCELS THE REF-LIKE RETURN RULE" {
    sink := SspSink("systems", "strict")
    SspCheckReturnLifetime(sink, SspSimple("Span"), "'a", true, false)
    assert SspCount(sink) == 0
}

test "A WHITESPACE RETURN LIFETIME DOES NOT COUNT AS A WRITTEN ONE" {
    sink := SspSink("systems", "strict")
    SspCheckReturnLifetime(sink, SspSimple("Span"), "   ", true, false)
    assert SspCount(sink) == 1
    assert SspCode(sink) == "NSYS080"
}

test "A BOUNDARY RETURNING A REF-LIKE VIEW IS NOT ASKED ABOUT ITS LIFETIME" {
    // The gate admits boundaries; this arm re-tests hotness itself, and that is why it is silent.
    sink := SspSink("systems", "strict")
    SspCheckReturnLifetime(sink, SspSimple("Span"), null, false, true)
    assert SspCount(sink) == 0
}

test "A LOCALLY DECLARED REF STRUCT IS REF-LIKE FOR THE RETURN RULE TOO" {
    sink := SspSink("systems", "strict")
    SspCheckReturnLifetime(sink, SspSimple("Frame"), null, true, false)
    assert SspCount(sink) == 1
    assert SspCode(sink) == "NSYS080"
}

test "AUDIT MODE DOWNGRADES THE HOT SIGNATURE FINDING THE RULE PREFERRED AS AN ERROR" {
    // The rule's preference is unchanged; the sink is what turns it into a warning.
    sink := SspSink("systems", "audit")
    SspCheckOneParameter(sink, SspHostile(), true, false)
    assert SspCount(sink) == 1
    assert SspSeverity(sink) == "warning"
    assert SspMessage(sink) == "[hot] parameter 'items' exposes a systems-hostile type: List"
}

test "A REF-LIKE FIELD OUTSIDE A REF STRUCT IS REPORTED AS A TYPE FINDING" {
    sink := SspSink("systems", "strict")
    SspCheckField(sink, SspSimple("Span"), false)
    assert SspCount(sink) == 1
    assert SspCode(sink) == "NSYS080"
    assert SspEffect(sink) == "lifetime"
    assert SspMessage(sink) == "ref-like field 'view' is only allowed inside a ref struct"
    assert SspLine(sink) == 30
    assert SspColumn(sink) == 9
    assert SspLength(sink) == 4
}

test "THE FIELD FINDING NAMES THE TYPE AS ITS FUNCTION AND AS ITS WHOLE CALL PATH" {
    sink := SspSink("systems", "strict")
    SspCheckField(sink, SspSimple("Span"), false)
    assert SspFunctionName(sink) == "Holder"
    assert SspCallPathFirst(sink) == "Holder"
}

test "A REF STRUCT IS NOT ASKED ABOUT ITS FIELDS AT ALL" {
    sink := SspSink("systems", "strict")
    SspCheckField(sink, SspSimple("Span"), true)
    assert SspCount(sink) == 0
}

test "A FIELD WITH NO PARSED TYPE IS SKIPPED RATHER THAN GUESSED AT" {
    sink := SspSink("systems", "strict")
    SspCheckField(sink, null, false)
    assert SspCount(sink) == 0
}

test "A FIELD WHOSE TYPE IS NOT REF-LIKE IS SILENT" {
    sink := SspSink("systems", "strict")
    SspCheckField(sink, SspSimple("int"), false)
    assert SspCount(sink) == 0
}

test "A NON-FIELD MEMBER IS NOT A FIELD AND IS SKIPPED" {
    sink := SspSink("systems", "strict")
    policy := SspPolicy(sink)
    policy.CheckRefLikeFields("frame.nl", "Holder", false, SspMembers(SspFunction("Fill", SspNoParameters(), SspSimple("Span"))))
    assert SspCount(sink) == 0
}

test "A TYPE FINDING HAS NO HOT LABEL ARM AND KEEPS ITS ERROR WHERE A FUNCTION FINDING WOULD NOT" {
    // In a default-profile project the label reads `local` and the severity is still `error`, because
    // the type door takes no preferred severity and has no boundary to downgrade from.
    sink := SspSink("default", "strict")
    SspCheckField(sink, SspSimple("Span"), false)
    assert SspCount(sink) == 1
    assert SspPolicyLabel(sink) == "local"
    assert SspSeverity(sink) == "error"
}

test "AUDIT MODE DOWNGRADES A TYPE FINDING TOO" {
    sink := SspSink("systems", "audit")
    SspCheckField(sink, SspSimple("Span"), false)
    assert SspCount(sink) == 1
    assert SspSeverity(sink) == "warning"
    assert SspPolicyLabel(sink) == "systems:audit"
}

test "THE FOUR ARMS ALL FIRE FOR ONE SIGNATURE AND ARE READ IN THE ORDER THE RULE ASKS" {
    // Parameters, then the return type, then the Result ABI, then the ref-like return — and the sort
    // is stable, so one position keeps the order the rule met them in.
    sink := SspSink("systems", "strict")
    policy := SspPolicy(sink)
    parameters := SspOneParameter(SspParameter("a", SspHostile(), 12, 5))
    inner := SspGeneric("Result", SspGeneric("Result", SspSimple("Frame"), SspSimple("Frame")), SspSimple("Vec"))
    function := SspFunction("Fill", parameters, SspGeneric("Result", SspHostile(), inner))
    policy.CheckFunctionSurface(function, "buf.nl", "Buf.Fill", true, false)
    assert SspCount(sink) == 4
    assert SspMessageAt(sink, 0) == "[hot] parameter 'a' exposes a systems-hostile type: List"
    assert SspMessageAt(sink, 1) == "[hot] return type exposes a systems-hostile shape: List"
    assert SspMessageAt(sink, 2) == "Result<T,E> copy shape is estimated at 176 bytes, above the v1 hot-path guidance of 128 bytes"
    assert SspMessageAt(sink, 3) == "[hot] function returns a ref-like value with an unknown lifetime"
}
