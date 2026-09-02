namespace NSharpLang.Compiler

import System.Collections.Generic
import NSharpLang.Compiler.Ast


// THE CANONICAL CONTRACTS FOR `TaskLikeTypeFacts`, IN N#.
//
// These replace `tests/TaskLikeTypeFactsTests.cs`, the last canonical C# assertion layer over
// `TaskLikeTypeFacts.nl`. The subject decides ONE question the async pipeline cannot get wrong:
// "does this type mean `await` yields nothing?" — and it answers it twice, once over a resolved
// `TypeInfo` and once over an unresolved source `TypeReference`, plus a third entry point that
// extracts `T` out of a `Task<T>`.
//
// WHY THIS ESTATE AND NOT A `tests/native` PROJECT. A `tests/native/*` project reaches its subject
// through a `dll:` dependency, and a dependency-assembly CONSTRUCTED object is not emittable from
// there: `new SimpleTypeInfo("Task")` in argument position declines at `emit.local.initializer`.
// Every input this kernel takes is a constructed `TypeInfo` or `TypeReference`, so the contracts
// belong where the models and the subject are the SAME assembly's own. That is also why these are
// plain `test` declarations rather than `with (…) […]` tables: this estate is compiled by the
// PINNED toolset, which predates them.
//
// THE COVERAGE IS ARM-COMPLETE, WHICH THE C# WAS NOT. The deleted file exercised THREE of the
// TWELVE `TypeInfo` arms (`SimpleTypeInfo`, `GenericTypeInfo`, `ExternalTypeInfo`) and never named
// `IsTaskLikeName` at all. Every arm is asserted here, because a dispatch chain with a missing arm
// is exactly the defect a three-arm spot check cannot see.
//
// THE FOUR THINGS IT IS EASY TO GET WRONG:
//
// (1) "UNIT TASK-LIKE" MEANS ARITY ZERO, NOT "NAMED TASK". `Task` and `Task<T>` are the same NAME
// and opposite answers: the generic arms admit a task-like name ONLY when `TypeArguments.Count`
// is 0, because `Task<string>` yields a `string` and is not a unit.
//
// (2) THE NAME TABLE HAS FOUR EXACT SPELLINGS AND TWO SUFFIX RULES, AND THE SUFFIX RULES NEED THE
// DOT. `Task` and `ValueTask` are exact; so are their two fully-qualified spellings; anything else
// is task-like only if it ENDS WITH `.Task` or `.ValueTask`. `MyTask` is therefore NOT task-like
// while `Acme.Task` is — the dot is what stops `TaskCompletionSource` and `MyTask` from passing.
//
// (3) THE `SoaRowTypeInfo` ARM CAN NEVER ANSWER TRUE. It classifies `Declaration.Name + ".Row"`,
// and a string ending in `.Row` can match neither exact spelling nor either suffix rule. The arm
// is reachable and its answer is constant, which is worth pinning rather than assuming.
//
// (4) A `TypeReference` HAS ONLY TWO ARMS AND A NULL GATE. `IsUnitTaskLikeTypeReference` handles
// `SimpleTypeReference` and `GenericTypeReference`, takes `null` without throwing, and answers
// false for every other reference shape — including an `ArrayTypeReference` over a task-like
// element, which is a `Task[]` and not a `Task`.
func TaskFactsNoInfos(): List<TypeInfo> {
    return new List<TypeInfo>()
}

func TaskFactsInfos1(first: TypeInfo): List<TypeInfo> {
    items := new List<TypeInfo>()
    items.Add(first)
    return items
}

func TaskFactsNoRefs(): List<TypeReference> {
    return new List<TypeReference>()
}

func TaskFactsRefs1(first: TypeReference): List<TypeReference> {
    items := new List<TypeReference>()
    items.Add(first)
    return items
}

func TaskFactsClass(name: string): ClassTypeInfo {
    return new ClassTypeInfo(
        name,
        1,
        1,
        false,
        null,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0),
        true
    )
}

func TaskFactsStruct(name: string): StructTypeInfo {
    return new StructTypeInfo(
        name,
        1,
        1,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0)
    )
}

func TaskFactsRecord(name: string): RecordTypeInfo {
    return new RecordTypeInfo(
        name,
        1,
        1,
        false,
        new TypeReference[](0),
        new TypeParameter[](0),
        new ParameterDeclarationInfo[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0)
    )
}

func TaskFactsInterface(name: string): InterfaceTypeInfo {
    return new InterfaceTypeInfo(
        name,
        1,
        1,
        false,
        new TypeReference[](0),
        new TypeParameter[](0),
        new DeclaredMemberInfo[](0),
        new NestedTypeInfo[](0)
    )
}

func TaskFactsUnion(name: string): UnionTypeInfo {
    return new UnionTypeInfo(new UnionDeclarationInfo(name, null, new List<UnionCase>(), 1, 1))
}

func TaskFactsEnum(name: string): EnumTypeInfo {
    return new EnumTypeInfo(new EnumDeclarationInfo(name, new List<EnumMemberInfo>(), EnumType.Int, 1, 1))
}

func TaskFactsSoaRecord(name: string): SoaRecordTypeInfo {
    return new SoaRecordTypeInfo(new SoaRecordDeclarationInfo(name, new List<SoaColumnInfo>(), 1, 1))
}

func TaskFactsSoaRow(name: string): SoaRowTypeInfo {
    return new SoaRowTypeInfo(new SoaRecordDeclarationInfo(name, new List<SoaColumnInfo>(), 1, 1))
}

// The C# asserted `Assert.Equal(BuiltInTypes.String, result.SourceResultType)`, which is xUnit's
// structural equality over `TypeInfo`. This is the same question, routed through the product's own
// `BuiltInTypes.Is` — which is null-safe, because the answer may legitimately be absent.
func TaskFactsSameTypeInfo(expected: SimpleTypeInfo, actual: TypeInfo?): bool {
    return BuiltInTypes.Is(actual, expected)
}

// ---- the resolved-type classifier ----------------------------------------------------------------

// Successor to TaskLikeTypeFacts_OwnsUnitTaskLikeClassification's four positive assertions.
test "task like type facts admit the unit task-like resolved types" {
    assert TaskLikeTypeFacts.IsUnitTaskLikeType(new SimpleTypeInfo("Task"))
    assert TaskLikeTypeFacts.IsUnitTaskLikeType(new SimpleTypeInfo("System.Threading.Tasks.ValueTask"))
    assert TaskLikeTypeFacts.IsUnitTaskLikeType(new GenericTypeInfo("Task", TaskFactsNoInfos()))
    assert TaskLikeTypeFacts.IsUnitTaskLikeType(new ExternalTypeInfo("System.Threading.Tasks.Task"))

    // Not in the deleted file: the other two spellings of each exact name, through both the simple
    // and the external arm.
    assert TaskLikeTypeFacts.IsUnitTaskLikeType(new SimpleTypeInfo("ValueTask"))
    assert TaskLikeTypeFacts.IsUnitTaskLikeType(new SimpleTypeInfo("System.Threading.Tasks.Task"))
    assert TaskLikeTypeFacts.IsUnitTaskLikeType(new ExternalTypeInfo("Task"))
    assert TaskLikeTypeFacts.IsUnitTaskLikeType(new ExternalTypeInfo("System.Threading.Tasks.ValueTask"))
    assert TaskLikeTypeFacts.IsUnitTaskLikeType(new GenericTypeInfo("ValueTask", TaskFactsNoInfos()))
}

// Successor to TaskLikeTypeFacts_OwnsUnitTaskLikeClassification's two negative assertions.
test "task like type facts refuse the non unit resolved types" {
    assert !TaskLikeTypeFacts.IsUnitTaskLikeType(new GenericTypeInfo("Task", TaskFactsInfos1(BuiltInTypes.String)))
    assert !TaskLikeTypeFacts.IsUnitTaskLikeType(BuiltInTypes.String)

    // Not in the deleted file: the arity rule holds for the other exact name too, and a name that
    // merely CONTAINS the word is not the word.
    assert !TaskLikeTypeFacts.IsUnitTaskLikeType(new GenericTypeInfo("ValueTask", TaskFactsInfos1(BuiltInTypes.Int)))
    assert !TaskLikeTypeFacts.IsUnitTaskLikeType(new SimpleTypeInfo("TaskCompletionSource"))
    assert !TaskLikeTypeFacts.IsUnitTaskLikeType(new SimpleTypeInfo("MyTask"))
    assert !TaskLikeTypeFacts.IsUnitTaskLikeType(new ExternalTypeInfo("System.Threading.Tasks.Task`1"))
}

// NOT IN THE DELETED FILE AT ALL. Nine of the twelve dispatch arms were never reached by the C#.
test "task like type facts reach every declared type arm" {
    assert TaskLikeTypeFacts.IsUnitTaskLikeType(TaskFactsClass("Task"))
    assert TaskLikeTypeFacts.IsUnitTaskLikeType(TaskFactsStruct("ValueTask"))
    assert TaskLikeTypeFacts.IsUnitTaskLikeType(TaskFactsRecord("Acme.Task"))
    assert TaskLikeTypeFacts.IsUnitTaskLikeType(TaskFactsInterface("System.Threading.Tasks.Task"))
    assert TaskLikeTypeFacts.IsUnitTaskLikeType(TaskFactsUnion("Task"))
    assert TaskLikeTypeFacts.IsUnitTaskLikeType(TaskFactsEnum("ValueTask"))
    assert TaskLikeTypeFacts.IsUnitTaskLikeType(TaskFactsSoaRecord("Task"))

    assert !TaskLikeTypeFacts.IsUnitTaskLikeType(TaskFactsClass("Widget"))
    assert !TaskLikeTypeFacts.IsUnitTaskLikeType(TaskFactsStruct("Point"))
    assert !TaskLikeTypeFacts.IsUnitTaskLikeType(TaskFactsRecord("Person"))
    assert !TaskLikeTypeFacts.IsUnitTaskLikeType(TaskFactsInterface("IShape"))
    assert !TaskLikeTypeFacts.IsUnitTaskLikeType(TaskFactsUnion("Shape"))
    assert !TaskLikeTypeFacts.IsUnitTaskLikeType(TaskFactsEnum("Color"))
    assert !TaskLikeTypeFacts.IsUnitTaskLikeType(TaskFactsSoaRecord("Points"))

    // The row arm classifies `Name + ".Row"`, which no rule in the table can admit — so this arm
    // is reachable and CONSTANT, even when the record itself is named `Task`.
    assert !TaskLikeTypeFacts.IsUnitTaskLikeType(TaskFactsSoaRow("Task"))
    assert !TaskLikeTypeFacts.IsUnitTaskLikeType(TaskFactsSoaRow("Points"))

    // The fallback: a shape with no arm at all answers false rather than throwing.
    assert !TaskLikeTypeFacts.IsUnitTaskLikeType(new FunctionTypeInfo())
}

// ---- the source-reference classifier ------------------------------------------------------------

// Successor to TaskLikeTypeFacts_OwnsTaskLikeTypeReferenceClassification — all five of its
// assertions, in order.
test "task like type facts classify unresolved task-like type references" {
    assert TaskLikeTypeFacts.IsUnitTaskLikeTypeReference(new SimpleTypeReference("ValueTask"))
    assert TaskLikeTypeFacts.IsUnitTaskLikeTypeReference(new GenericTypeReference("System.Threading.Tasks.Task", TaskFactsNoRefs()))

    assert !TaskLikeTypeFacts.IsUnitTaskLikeTypeReference(new GenericTypeReference("Task", TaskFactsRefs1(new SimpleTypeReference("string"))))
    assert !TaskLikeTypeFacts.IsUnitTaskLikeTypeReference(new SimpleTypeReference("string"))
    assert !TaskLikeTypeFacts.IsUnitTaskLikeTypeReference(null)

    // Not in the deleted file: the other reference shapes have no arm, and a `Task[]` is not a
    // `Task` even though its ELEMENT is one.
    assert !TaskLikeTypeFacts.IsUnitTaskLikeTypeReference(new ArrayTypeReference(new SimpleTypeReference("Task")))
    assert !TaskLikeTypeFacts.IsUnitTaskLikeTypeReference(new NullableTypeReference(new SimpleTypeReference("Task")))
    assert TaskLikeTypeFacts.IsUnitTaskLikeTypeReference(new SimpleTypeReference("Acme.ValueTask"))
}

// ---- the result-type extractor ------------------------------------------------------------------

// Successor to TaskLikeTypeFacts_OwnsTaskLikeResultTypeExtraction — all four of its assertions.
test "task like type facts extract the awaited result type" {
    sourceResult := TaskLikeTypeFacts.GetTaskLikeResultType(new GenericTypeInfo("Task", TaskFactsInfos1(BuiltInTypes.String)))

    assert sourceResult.Found
    assert TaskFactsSameTypeInfo(BuiltInTypes.String, sourceResult.SourceResultType)

    none := TaskLikeTypeFacts.GetTaskLikeResultType(BuiltInTypes.String)

    assert !none.Found
    assert none.SourceResultType == null
}

// NOT IN THE DELETED FILE. The extractor's arity gate is the mirror of the classifier's: exactly
// one argument, and a `Task` with none carries no result at all.
test "task like type facts refuse a result type without exactly one argument" {
    unit := TaskLikeTypeFacts.GetTaskLikeResultType(new GenericTypeInfo("Task", TaskFactsNoInfos()))
    assert !unit.Found
    assert unit.SourceResultType == null

    unnamed := TaskLikeTypeFacts.GetTaskLikeResultType(new GenericTypeInfo("List", TaskFactsInfos1(BuiltInTypes.Int)))
    assert !unnamed.Found

    simple := TaskLikeTypeFacts.GetTaskLikeResultType(new SimpleTypeInfo("Task"))
    assert !simple.Found

    valueTask := TaskLikeTypeFacts.GetTaskLikeResultType(new GenericTypeInfo("System.Threading.Tasks.ValueTask", TaskFactsInfos1(BuiltInTypes.Int)))
    assert valueTask.Found
    assert TaskFactsSameTypeInfo(BuiltInTypes.Int, valueTask.SourceResultType)
}

// ---- the name table -----------------------------------------------------------------------------

// NOT IN THE DELETED FILE. Every arm above funnels into this one predicate, so this is where the
// table actually lives: four exact spellings, two suffix rules, and the dot that makes them rules.
test "task like type facts name every task-like spelling and refuse the rest" {
    assert TaskLikeTypeFacts.IsTaskLikeName("Task")
    assert TaskLikeTypeFacts.IsTaskLikeName("ValueTask")
    assert TaskLikeTypeFacts.IsTaskLikeName("System.Threading.Tasks.Task")
    assert TaskLikeTypeFacts.IsTaskLikeName("System.Threading.Tasks.ValueTask")

    assert TaskLikeTypeFacts.IsTaskLikeName("Acme.Task")
    assert TaskLikeTypeFacts.IsTaskLikeName("Acme.ValueTask")
    assert TaskLikeTypeFacts.IsTaskLikeName("a.b.c.Task")

    assert !TaskLikeTypeFacts.IsTaskLikeName("MyTask")
    assert !TaskLikeTypeFacts.IsTaskLikeName("MyValueTask")
    assert !TaskLikeTypeFacts.IsTaskLikeName("TaskCompletionSource")
    assert !TaskLikeTypeFacts.IsTaskLikeName("Task2")
    assert !TaskLikeTypeFacts.IsTaskLikeName("Tasks")
    assert !TaskLikeTypeFacts.IsTaskLikeName("task")
    assert !TaskLikeTypeFacts.IsTaskLikeName("Acme.task")
    assert !TaskLikeTypeFacts.IsTaskLikeName(".Row")
    assert !TaskLikeTypeFacts.IsTaskLikeName("")
}

// ---- the result carrier -------------------------------------------------------------------------

// NOT IN THE DELETED FILE. `TaskLikeResultType` is the extractor's answer shape, and both of its
// factories are product-reachable.
test "task like result type carries its two factory shapes" {
    absent := TaskLikeResultType.None()
    assert !absent.Found
    assert absent.SourceResultType == null

    present := TaskLikeResultType.Source(BuiltInTypes.Int)
    assert present.Found
    assert TaskFactsSameTypeInfo(BuiltInTypes.Int, present.SourceResultType)
}
