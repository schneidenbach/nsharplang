namespace NSharpLang.Compiler.Columnar

import System
import System.Collections.Generic


// CONTRACTS FOR THE System.Xml.Linq CATALOG ROWS (task 019 slice 22, stage 1).
//
// `System.Xml.Linq` is the LAST wall in the 019 arc: 21 of `DocQuery.cs`'s 25 extents (360 of 396
// extent lines) are held by it, not by a shape. Before these rows an `import System.Xml.Linq`
// answered NL704, `XDocument` answered NL301, and a `Dictionary<string, XElement>` member answered
// NL201 — all three measured by execution at tip 8f657932a.
//
// THE SURFACE IS EXACTLY WHAT THE WALLED CODE NEEDS, ENUMERATED FROM THE COMPILED BODIES AND NOT
// FROM THE NAMESPACE. An IL census over `DocQuery`'s own method bodies in `Compiler.dll` reports
// FOURTEEN member references and NINE type shapes. Seven types carry them, and one of the seven —
// `XContainer` — is spelled in no source line at all: `Element`, `Elements` and `Nodes` are declared
// there and inherited by `XElement`, so it is the declaring identity every one of those calls binds.
//
// THE TYPES ARE FETCHED BY NAME AND NOT BY `typeof`, AND THAT IS WHY THE SLICE HAS TWO STAGES. This
// file is compiled by the PINNED toolset — the one that does not yet know these rows — so writing
// `typeof(XElement)` here would decline the whole file. Reflection by name is the only spelling
// available until the toolset carries the rows it is publishing. (The `IReadOnlyDictionary` catalog
// file next door was written under the same constraint for the same reason.)
//
// EVERY ROW IS ASKED THREE WAYS: the admission, a CONTROL whose established answer must not have
// moved, and a NEGATIVE that must stay refused. The negatives matter more here than usual, because
// the temptation with a namespace-sized wall is to admit the namespace: `XComment` and `XCData` are
// real, public, exported types in `System.Xml.Linq` that the walled code never touches, and every
// predicate must still refuse them.
//
// WHICH ASSEMBLY. `System.Xml.Linq` is a pure FACADE of type forwarders — a metadata scan of it
// exports ZERO types — so every exact identity names `System.Private.Xml.Linq`, which really carries
// the 23 types.
func XlcAssemblyQualified(fullName: string): string {
    return fullName + ", System.Private.Xml.Linq"
}

func XlcType(fullName: string): Type {
    resolved := Type.GetType(XlcAssemblyQualified(fullName))
    if resolved == null {
        throw new InvalidOperationException("Required Linq-to-XML runtime type '" + fullName + "' was not found.")
    }
    return resolved
}

func XlcNames(): string[] {
    return ["System.Xml.Linq.XDocument", "System.Xml.Linq.XElement", "System.Xml.Linq.XContainer", "System.Xml.Linq.XNode", "System.Xml.Linq.XText", "System.Xml.Linq.XAttribute", "System.Xml.Linq.XName"]
}

func XlcShortNames(): string[] {
    return ["XDocument", "XElement", "XContainer", "XNode", "XText", "XAttribute", "XName"]
}

// Types in the SAME namespace that the walled code never touches. A row that admits these is
// admitting the namespace rather than the surface.
func XlcUnadmittedNames(): string[] {
    return ["System.Xml.Linq.XComment", "System.Xml.Linq.XCData", "System.Xml.Linq.XDeclaration", "System.Xml.Linq.XNamespace", "System.Xml.Linq.XProcessingInstruction"]
}

func XlcOne(value: string): string[] {
    values := new string[](1)
    values[0] = value
    return values
}

func XlcNone(): string[] {
    return new string[](0)
}

func XlcAssertRuntimeTypeRow(canonical: string, expectedFullName: string) {
    resolved := ""
    assert ColumnarExternalBindingPlans.TryGetRuntimeTypeName(canonical, out resolved)
    assert resolved == XlcAssemblyQualified(expectedFullName)

    // The identity a row hands out must really resolve: a name that does not is a row that turns
    // every use of the type into a silent decline rather than an error.
    assert Type.GetType(resolved) != null
    assert Type.GetType(resolved) == XlcType(expectedFullName)
}

// ── the seven type admissions ────────────────────────────────────────────────────────────────

test "every Linq-to-XML type is admitted under its short and its fully qualified spelling" {
    shortNames := XlcShortNames()
    fullNames := XlcNames()
    assert shortNames.Length == 7
    assert fullNames.Length == 7

    index := 0
    while index < fullNames.Length {
        XlcAssertRuntimeTypeRow(shortNames[index], fullNames[index])
        XlcAssertRuntimeTypeRow(fullNames[index], fullNames[index])
        assert ColumnarExternalBindingPlans.IsSupportedRuntimeTypeName(fullNames[index])
        assert ColumnarExternalBindingPlans.IsXmlLinqTypeName(fullNames[index])
        index = index + 1
    }
}

test "the admitted list is a surface and not a namespace" {
    unadmitted := XlcUnadmittedNames()
    index := 0
    while index < unadmitted.Length {
        name := unadmitted[index]

        // The type is REAL — resolving it proves the negative is not passing by a typo.
        assert Type.GetType(XlcAssemblyQualified(name)) != null

        assert !ColumnarExternalBindingPlans.IsXmlLinqTypeName(name)
        assert !ColumnarExternalBindingPlans.IsSupportedRuntimeTypeName(name)

        resolved := ""
        assert !ColumnarExternalBindingPlans.TryGetRuntimeTypeName(name, out resolved)
        index = index + 1
    }

    // And a name that looks like the family but is nothing at all.
    unknown := ""
    assert !ColumnarExternalBindingPlans.TryGetRuntimeTypeName("XWidget", out unknown)
    assert !ColumnarExternalBindingPlans.IsXmlLinqTypeName("System.Xml.Linq")
    assert !ColumnarExternalBindingPlans.IsXmlLinqTypeName("System.Xml.XmlDocument")
}

test "the exact identity names the implementation assembly and leaves every other family alone" {
    assert ColumnarExternalBindingPlans.XmlLinqAssemblyName() == "System.Private.Xml.Linq"
    assert ColumnarExternalBindingPlans.ExactTypeIdentity("System.Xml.Linq.XElement") == "System.Xml.Linq.XElement, System.Private.Xml.Linq"

    // CONTROLS: the established prefixes must answer exactly as before.
    assert ColumnarExternalBindingPlans.ExactTypeIdentity("System.String") == "System.String, System.Private.CoreLib"
    assert ColumnarExternalBindingPlans.ExactTypeIdentity("System.Text.Json.JsonElement") == "System.Text.Json.JsonElement, System.Text.Json"
    assert ColumnarExternalBindingPlans.ExactTypeIdentity("System.Console") == "System.Console, System.Console"

    // A NEIGHBOURING namespace must not be swept in by the prefix test.
    assert ColumnarExternalBindingPlans.ExactTypeIdentity("System.Xml.XmlDocument") == "System.Xml.XmlDocument, System.Private.CoreLib"
}

// ── the two static call rows ─────────────────────────────────────────────────────────────────

test "XDocument.Load binds the string overload exactly and nothing beside it" {
    plan := ColumnarExternalBindingPlans.GetStaticCallPlan("XDocument", "Load", XlcOne("System.String"))
    assert plan.IsSupported
    assert plan.Kind == ColumnarExternalCallKind.Call
    assert plan.DeclaringTypeName == XlcAssemblyQualified("System.Xml.Linq.XDocument")
    assert plan.MemberName == "Load"
    assert plan.ParameterTypeNames.Length == 1
    assert plan.ParameterTypeNames[0] == "System.String, System.Private.CoreLib"
    assert plan.ReturnTypeName == XlcAssemblyQualified("System.Xml.Linq.XDocument")
    assert plan.TypeArgumentNames.Length == 0

    // The fully qualified owner spelling is the same row.
    qualified := ColumnarExternalBindingPlans.GetStaticCallPlan("System.Xml.Linq.XDocument", "Load", XlcOne("System.String"))
    assert qualified.IsSupported
    assert qualified.DeclaringTypeName == plan.DeclaringTypeName

    // NEGATIVES: the wrong arity, the wrong argument, an un-admitted member, and the wrong owner.
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan("XDocument", "Load", XlcNone()).IsSupported
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan("XDocument", "Load", XlcOne("System.Int32")).IsSupported
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan("XDocument", "Parse", XlcOne("System.String")).IsSupported
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan("XElement", "Load", XlcOne("System.String")).IsSupported
}

test "XName.Get is the conversion N# spells where C# inserts op_Implicit" {
    plan := ColumnarExternalBindingPlans.GetStaticCallPlan("XName", "Get", XlcOne("System.String"))
    assert plan.IsSupported
    assert plan.Kind == ColumnarExternalCallKind.Call
    assert plan.DeclaringTypeName == XlcAssemblyQualified("System.Xml.Linq.XName")
    assert plan.MemberName == "Get"
    assert plan.ParameterTypeNames.Length == 1
    assert plan.ParameterTypeNames[0] == "System.String, System.Private.CoreLib"
    assert plan.ReturnTypeName == XlcAssemblyQualified("System.Xml.Linq.XName")

    // BOTH functions exist on the type, and `Get` is the one the row names. The implicit conversion
    // is NOT admitted: N# has no implicit user conversion, so admitting the operator would publish a
    // spelling the language cannot reach.
    nameType := XlcType("System.Xml.Linq.XName")
    stringArgument := new Type[](1)
    stringArgument[0] = typeof(string)
    assert nameType.GetMethod("Get", stringArgument) != null
    assert nameType.GetMethod("op_Implicit", stringArgument) != null
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan("XName", "op_Implicit", XlcOne("System.String")).IsSupported

    assert !ColumnarExternalBindingPlans.GetStaticCallPlan("XName", "Get", XlcNone()).IsSupported
    assert !ColumnarExternalBindingPlans.GetStaticCallPlan("XName", "Get", XlcOne("System.Int32")).IsSupported
}

// ── the four instance call rows ──────────────────────────────────────────────────────────────

func XlcAssertElementCall(memberName: string, arguments: string[], expectedReturnIdentity: string) {
    plan := ColumnarExternalBindingPlans.GetInstanceCallPlan("System.Xml.Linq.XElement", memberName, arguments)
    assert plan.IsSupported
    assert plan.Kind == ColumnarExternalCallKind.CallVirtual

    // THE DECLARING IDENTITY IS THE RECEIVER'S, NOT THE DECLARER'S. `Element`, `Elements` and
    // `Nodes` are declared on `XContainer`; the resolver validates a plan's declaring identity
    // against the LOOKUP type and admits an inherited declaring type at the candidate check, so a
    // plan that named `XContainer` would be refused before it ever reached the member.
    assert plan.DeclaringTypeName == XlcAssemblyQualified("System.Xml.Linq.XElement")
    assert plan.MemberName == memberName
    assert plan.ParameterTypeNames.Length == arguments.Length
    assert plan.ReturnTypeName == expectedReturnIdentity
    assert plan.TypeArgumentNames.Length == 0

    // The identity must resolve, and the member must really be reachable from the receiver.
    assert Type.GetType(plan.ReturnTypeName) != null
}

test "the element navigation rows bind Element, Elements, Nodes and Attribute" {
    nameArgument := XlcOne("System.Xml.Linq.XName")
    elementIdentity := XlcAssemblyQualified("System.Xml.Linq.XElement")
    attributeIdentity := XlcAssemblyQualified("System.Xml.Linq.XAttribute")

    XlcAssertElementCall("Element", nameArgument, elementIdentity)
    XlcAssertElementCall("Attribute", nameArgument, attributeIdentity)

    elementSequence := ColumnarExternalBindingPlans.GetInstanceCallPlan("System.Xml.Linq.XElement", "Elements", nameArgument)
    assert elementSequence.IsSupported
    nodeSequence := ColumnarExternalBindingPlans.GetInstanceCallPlan("System.Xml.Linq.XElement", "Nodes", XlcNone())
    assert nodeSequence.IsSupported

    // A parameter identity that does not resolve is a row that silently declines, so the argument
    // identity is checked as well as the return.
    assert Type.GetType(elementSequence.ParameterTypeNames[0]) == XlcType("System.Xml.Linq.XName")
}

test "the two sequence rows carry a resolvable closed IEnumerable identity" {
    elementSequenceName := ColumnarExternalBindingPlans.XmlLinqSequenceName("System.Xml.Linq.XElement")
    nodeSequenceName := ColumnarExternalBindingPlans.XmlLinqSequenceName("System.Xml.Linq.XNode")
    assert elementSequenceName == "System.Collections.Generic.IEnumerable`1[[System.Xml.Linq.XElement, System.Private.Xml.Linq]]"
    assert nodeSequenceName == "System.Collections.Generic.IEnumerable`1[[System.Xml.Linq.XNode, System.Private.Xml.Linq]]"

    // THE ELEMENT MUST BE ASSEMBLY-QUALIFIED INSIDE THE BRACKETS. The closure is resolved from
    // CoreLib's context, and CoreLib cannot find a type that lives in the Linq-to-XML assembly, so
    // the shorter `[System.Xml.Linq.XElement]` spelling resolves to NOTHING. That is the difference
    // between a working row and a row that declines every walk over `Elements`.
    elementSequence := ColumnarExternalBindingPlans.GetInstanceCallPlan("System.Xml.Linq.XElement", "Elements", XlcOne("System.Xml.Linq.XName"))
    nodeSequence := ColumnarExternalBindingPlans.GetInstanceCallPlan("System.Xml.Linq.XElement", "Nodes", XlcNone())
    elementSequenceType := Type.GetType(elementSequence.ReturnTypeName)
    nodeSequenceType := Type.GetType(nodeSequence.ReturnTypeName)
    assert elementSequenceType != null
    assert nodeSequenceType != null
    assert Type.GetType("System.Collections.Generic.IEnumerable`1[System.Xml.Linq.XElement], System.Private.CoreLib") == null

    definition := Type.GetType("System.Collections.Generic.IEnumerable`1, System.Private.CoreLib")
    assert definition != null
    assert elementSequenceType.GetGenericTypeDefinition() == definition
    assert elementSequenceType.GetGenericArguments()[0] == XlcType("System.Xml.Linq.XElement")
    assert nodeSequenceType.GetGenericArguments()[0] == XlcType("System.Xml.Linq.XNode")
}

test "the instance rows refuse the wrong receiver, the wrong argument and the wrong member" {
    nameArgument := XlcOne("System.Xml.Linq.XName")

    // A STRING argument is what the C# source writes; the CLR signature takes an XName, and the
    // plan must refuse the string rather than widen it — the conversion is `XName.Get`'s job.
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan("System.Xml.Linq.XElement", "Element", XlcOne("System.String")).IsSupported
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan("System.Xml.Linq.XElement", "Elements", XlcOne("System.String")).IsSupported
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan("System.Xml.Linq.XElement", "Attribute", XlcOne("System.String")).IsSupported

    // The receiver set is exactly `XElement`: the doc walk holds nothing else when it navigates.
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan("System.Xml.Linq.XDocument", "Element", nameArgument).IsSupported
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan("System.Xml.Linq.XContainer", "Element", nameArgument).IsSupported
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan("System.Xml.Linq.XNode", "Nodes", XlcNone()).IsSupported

    // Un-admitted members of an admitted receiver stay refused.
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan("System.Xml.Linq.XElement", "Descendants", nameArgument).IsSupported
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan("System.Xml.Linq.XElement", "Attributes", nameArgument).IsSupported
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan("System.Xml.Linq.XElement", "Remove", XlcNone()).IsSupported

    // The wrong arity on an admitted member.
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan("System.Xml.Linq.XElement", "Nodes", nameArgument).IsSupported
    assert !ColumnarExternalBindingPlans.GetInstanceCallPlan("System.Xml.Linq.XElement", "Element", XlcNone()).IsSupported
}

// ── the six instance property rows ───────────────────────────────────────────────────────────

func XlcAssertProperty(receiverFullName: string, member: string, expectedResultFullName: string) {
    receiverType := XlcType(receiverFullName)
    assert ColumnarRuntimeInstanceMemberResolver.CanOwnReceiver(receiverType)

    selection := ColumnarRuntimeInstanceMemberSelection.Empty()
    assert ColumnarRuntimeInstanceMemberResolver.TrySelect(receiverType, member, out selection)
    assert !selection.IsField
    assert selection.Getter != null
    assert selection.ReceiverIsReference
    assert selection.DeclaringType == receiverType
    if expectedResultFullName == "System.String" {
        assert selection.ResultType == typeof(string)
    } else {
        assert selection.ResultType == XlcType(expectedResultFullName)
    }
}

test "the six xml doc property reads select their exact result" {
    XlcAssertProperty("System.Xml.Linq.XDocument", "Root", "System.Xml.Linq.XElement")
    XlcAssertProperty("System.Xml.Linq.XElement", "Name", "System.Xml.Linq.XName")
    XlcAssertProperty("System.Xml.Linq.XElement", "Value", "System.String")
    XlcAssertProperty("System.Xml.Linq.XAttribute", "Value", "System.String")
    XlcAssertProperty("System.Xml.Linq.XText", "Value", "System.String")
    XlcAssertProperty("System.Xml.Linq.XName", "LocalName", "System.String")
}

test "the property rows admit only the five receivers the doc walk holds" {
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedXmlLinqReceiver(XlcType("System.Xml.Linq.XDocument"))
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedXmlLinqReceiver(XlcType("System.Xml.Linq.XElement"))
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedXmlLinqReceiver(XlcType("System.Xml.Linq.XName"))
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedXmlLinqReceiver(XlcType("System.Xml.Linq.XAttribute"))
    assert ColumnarRuntimeInstanceMemberResolver.IsSupportedXmlLinqReceiver(XlcType("System.Xml.Linq.XText"))

    // `XContainer` and `XNode` are admitted TYPES — they carry declaring identities and cross
    // signatures — but nothing reads a property THROUGH them, so neither is a receiver.
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedXmlLinqReceiver(XlcType("System.Xml.Linq.XContainer"))
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedXmlLinqReceiver(XlcType("System.Xml.Linq.XNode"))
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedXmlLinqReceiver(XlcType("System.Xml.Linq.XComment"))
}

test "an un-admitted property of an admitted receiver still selects nothing" {
    element := XlcType("System.Xml.Linq.XElement")
    document := XlcType("System.Xml.Linq.XDocument")

    // Each of these is a REAL public property on the receiver — the negatives are refusals, not
    // spelling mistakes.
    assert element.GetProperty("FirstAttribute") != null
    assert element.GetProperty("IsEmpty") != null
    assert document.GetProperty("Declaration") != null

    selection := ColumnarRuntimeInstanceMemberSelection.Empty()
    assert !ColumnarRuntimeInstanceMemberResolver.TrySelect(element, "FirstAttribute", out selection)
    assert !ColumnarRuntimeInstanceMemberResolver.TrySelect(element, "IsEmpty", out selection)
    assert !ColumnarRuntimeInstanceMemberResolver.TrySelect(document, "Declaration", out selection)
    assert !ColumnarRuntimeInstanceMemberResolver.TrySelect(element, "Root", out selection)
    assert !ColumnarRuntimeInstanceMemberResolver.TrySelect(document, "Value", out selection)
    assert !ColumnarRuntimeInstanceMemberResolver.TrySelect(XlcType("System.Xml.Linq.XName"), "Namespace", out selection)
}

// ── the emit-side assembly scan ──────────────────────────────────────────────────────────────

test "the emit-side common assembly list carries the implementation assembly, not the facade" {
    names := ExternalAssemblyScan.CommonAssemblyNames()
    assert names.Length == 27

    found := false
    facade := false
    index := 0
    while index < names.Length {
        if names[index] == "System.Private.Xml.Linq" {
            found = true
        }

        if names[index] == "System.Xml.Linq" {
            facade = true
        }

        index = index + 1
    }

    // PUBLISHING THE EMITTER'S TYPE ROWS IS NOT PUBLISHING ITS ASSEMBLY SCAN — that is the lesson
    // finding 90.8 recorded for the analyser half, and it holds a third time here: with the type
    // rows in place and this name absent, `XDocument` still resolved to nothing at emit time and the
    // decline was SILENT (no site recorded), reported only as the enclosing local initializer.
    assert found

    // The facade is deliberately NOT here: a metadata scan of it exports zero types, so the entry
    // would add a resolver path and resolve no name.
    assert !facade

    // CONTROL: the established names are untouched and in place.
    assert names[0] == "System.Runtime"
    assert names[6] == "System.Text.Json"
    assert names[25] == "System.Private.CoreLib"
}

test "the admitted types are admitted VALUE types, which is what lets them be locals and fields" {
    names := XlcNames()
    index := 0
    while index < names.Length {
        admitted := XlcType(names[index])
        assert ColumnarRuntimeInstanceMemberResolver.IsAdmittedValueType(admitted)
        assert ColumnarRuntimeInstanceMemberResolver.IsSupportedElementType(admitted)
        index = index + 1
    }

    // CONTROL: the established answer for a CoreLib reference type has not moved.
    assert ColumnarRuntimeInstanceMemberResolver.IsAdmittedValueType(typeof(string))

    // NEGATIVE: an un-admitted sibling in the same namespace is still not a value type the emitter
    // will declare.
    assert !ColumnarRuntimeInstanceMemberResolver.IsAdmittedValueType(XlcType("System.Xml.Linq.XComment"))
    assert !ColumnarRuntimeInstanceMemberResolver.IsSupportedElementType(XlcType("System.Xml.Linq.XCData"))
}
