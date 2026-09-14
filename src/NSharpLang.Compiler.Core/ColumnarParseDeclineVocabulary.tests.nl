namespace NSharpLang.Compiler.Columnar

import System


// THE CANONICAL CONTRACTS FOR THE COLUMNAR PARSE-INPUT DECLINE VOCABULARY.
//
// Every row below is PRODUCT TEXT. When the columnar backend cannot model a source shape, the
// primary decline is rendered by `ColumnarDeclineReasonFacts.FormatDetail` into the `NL103` a
// developer reads on their terminal, and the site id is what they search for. Until this slice the
// words lived in `ColumnarProgramInputBuilder.cs` — 49 site ids, 49 sentences and 6 scan-stage
// names, spelled in C#, asserted by nothing, and therefore editable without anyone noticing.
//
// The file that spells them now is `ColumnarDeclineReasons.nl`, beside the record and the two
// renderings that already lived there. THIS file is the wall: 49 rows, both halves each, pinned by
// NAME. Changing a word a user can read now fails a contract that names the row, which is what
// makes it a decision instead of a typo.
//
// THE SITE ID AND THE MESSAGE ARE DIFFERENT PRODUCTS AND BOTH ARE PINNED. The site id is a stable
// machine handle (`parse.property.getter-nodes`) that a user greps and a bug report quotes; the
// message is an English sentence. Nine site ids are deliberately SHARED by more than one row —
// `parse.function` covers three distinct failures, `parse.enum`, `parse.struct`, `parse.union`,
// `parse.test`, `parse.interface`, `parse.interface.params` and `parse.function.constraints` two
// each — so pinning only site ids would leave those rows interchangeable.
func ParseDeclineIsWellFormed(decline: ColumnarParseDecline): bool {
    return decline.SiteId.StartsWith("parse.", StringComparison.Ordinal) && decline.SiteId.Length > "parse.".Length && decline.Message.Length > 0 && !decline.Message.EndsWith(".", StringComparison.Ordinal)
}

test "the columnar parse decline vocabulary — tokenization — is spelled exactly as a user reads it" {
    assert ColumnarParseDeclines.Tokenize.SiteId == "parse.tokenize"
    assert ColumnarParseDeclines.Tokenize.Message == "columnar tokenization failed"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.Tokenize)

    assert ColumnarParseDeclines.TokenizeInvalidResult.SiteId == "parse.tokenize.invalid-result"
    assert ColumnarParseDeclines.TokenizeInvalidResult.Message == "columnar tokenizer returned invalid token counts"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.TokenizeInvalidResult)
}

test "the columnar parse decline vocabulary — per-kind materialization — is spelled exactly as a user reads it" {
    assert ColumnarParseDeclines.FunctionMaterialization.SiteId == "parse.function"
    assert ColumnarParseDeclines.FunctionMaterialization.Message == "function declaration materialization failed"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.FunctionMaterialization)

    assert ColumnarParseDeclines.EnumMaterialization.SiteId == "parse.enum"
    assert ColumnarParseDeclines.EnumMaterialization.Message == "enum declaration materialization failed"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.EnumMaterialization)

    assert ColumnarParseDeclines.StructMaterialization.SiteId == "parse.struct"
    assert ColumnarParseDeclines.StructMaterialization.Message == "struct/class/record declaration materialization failed"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.StructMaterialization)

    assert ColumnarParseDeclines.UnionMaterialization.SiteId == "parse.union"
    assert ColumnarParseDeclines.UnionMaterialization.Message == "union declaration materialization failed"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.UnionMaterialization)

    assert ColumnarParseDeclines.InterfaceMaterialization.SiteId == "parse.interface"
    assert ColumnarParseDeclines.InterfaceMaterialization.Message == "interface declaration materialization failed"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.InterfaceMaterialization)

    assert ColumnarParseDeclines.TestMaterialization.SiteId == "parse.test"
    assert ColumnarParseDeclines.TestMaterialization.Message == "test declaration materialization failed"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.TestMaterialization)

    assert ColumnarParseDeclines.NewtypeMaterialization.SiteId == "parse.newtype"
    assert ColumnarParseDeclines.NewtypeMaterialization.Message == "newtype declaration materialization failed"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.NewtypeMaterialization)
}

test "the columnar parse decline vocabulary — newtypes and tests — is spelled exactly as a user reads it" {
    assert ColumnarParseDeclines.NewtypeScan.SiteId == "parse.newtype-scan"
    assert ColumnarParseDeclines.NewtypeScan.Message == "newtype declaration scan failed (composed underlying types are not modeled)"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.NewtypeScan)

    assert ColumnarParseDeclines.TestScan.SiteId == "parse.test-scan"
    assert ColumnarParseDeclines.TestScan.Message == "test declaration scan failed"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.TestScan)

    assert ColumnarParseDeclines.TestDeclaration.SiteId == "parse.test"
    assert ColumnarParseDeclines.TestDeclaration.Message == "test declaration could not be parsed into columnar input"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.TestDeclaration)
}

test "the columnar parse decline vocabulary — functions and local functions — is spelled exactly as a user reads it" {
    assert ColumnarParseDeclines.FunctionDeclaration.SiteId == "parse.function"
    assert ColumnarParseDeclines.FunctionDeclaration.Message == "function declaration could not be parsed into columnar input"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.FunctionDeclaration)

    assert ColumnarParseDeclines.FunctionBodyOrSignature.SiteId == "parse.function"
    assert ColumnarParseDeclines.FunctionBodyOrSignature.Message == "function body or signature could not be parsed into columnar input"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.FunctionBodyOrSignature)

    assert ColumnarParseDeclines.FunctionParameterTupleNames.SiteId == "parse.function.param-tuple-names"
    assert ColumnarParseDeclines.FunctionParameterTupleNames.Message == "function parameter tuple-name metadata was invalid"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.FunctionParameterTupleNames)

    assert ColumnarParseDeclines.FunctionReturnTupleNames.SiteId == "parse.function.return-tuple-names"
    assert ColumnarParseDeclines.FunctionReturnTupleNames.Message == "function return tuple-name metadata was invalid"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.FunctionReturnTupleNames)

    assert ColumnarParseDeclines.FunctionBody.SiteId == "parse.function.body"
    assert ColumnarParseDeclines.FunctionBody.Message == "function body was not materialized as a supported block or expression body"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.FunctionBody)

    assert ColumnarParseDeclines.FunctionConstraintsWithoutTypeParameters.SiteId == "parse.function.constraints"
    assert ColumnarParseDeclines.FunctionConstraintsWithoutTypeParameters.Message == "function constraints were present without type parameters"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.FunctionConstraintsWithoutTypeParameters)

    assert ColumnarParseDeclines.FunctionConstraintMetadata.SiteId == "parse.function.constraints"
    assert ColumnarParseDeclines.FunctionConstraintMetadata.Message == "function constraint metadata was invalid"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.FunctionConstraintMetadata)

    assert ColumnarParseDeclines.FunctionBodyNodes.SiteId == "parse.function.body-nodes"
    assert ColumnarParseDeclines.FunctionBodyNodes.Message == "function body node table was invalid"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.FunctionBodyNodes)

    assert ColumnarParseDeclines.FunctionNativeImport.SiteId == "parse.function.native-import"
    assert ColumnarParseDeclines.FunctionNativeImport.Message == "LibraryImport metadata could not be parsed into columnar input"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.FunctionNativeImport)

    assert ColumnarParseDeclines.FunctionLocalFunctionMetadata.SiteId == "parse.function.local-functions"
    assert ColumnarParseDeclines.FunctionLocalFunctionMetadata.Message == "local-function metadata was invalid"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.FunctionLocalFunctionMetadata)

    assert ColumnarParseDeclines.LocalFunction.SiteId == "parse.local-function"
    assert ColumnarParseDeclines.LocalFunction.Message == "local function could not be parsed into columnar input"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.LocalFunction)
}

test "the columnar parse decline vocabulary — enums, structs, classes, records and unions — is spelled exactly as a user reads it" {
    assert ColumnarParseDeclines.EnumDeclaration.SiteId == "parse.enum"
    assert ColumnarParseDeclines.EnumDeclaration.Message == "enum declaration could not be parsed into columnar input"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.EnumDeclaration)

    assert ColumnarParseDeclines.StructInvalidCount.SiteId == "parse.struct.invalid-count"
    assert ColumnarParseDeclines.StructInvalidCount.Message == "struct/class/record declaration count was invalid"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.StructInvalidCount)

    assert ColumnarParseDeclines.StructDeclaration.SiteId == "parse.struct"
    assert ColumnarParseDeclines.StructDeclaration.Message == "struct/class/record declaration could not be parsed into columnar input"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.StructDeclaration)

    assert ColumnarParseDeclines.StructMethod.SiteId == "parse.struct.method"
    assert ColumnarParseDeclines.StructMethod.Message == "struct/class/record method could not be parsed into columnar input"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.StructMethod)

    assert ColumnarParseDeclines.StructConstructor.SiteId == "parse.struct.constructor"
    assert ColumnarParseDeclines.StructConstructor.Message == "constructor could not be parsed into columnar input"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.StructConstructor)

    assert ColumnarParseDeclines.StructProperty.SiteId == "parse.struct.property"
    assert ColumnarParseDeclines.StructProperty.Message == "property could not be parsed into columnar input"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.StructProperty)

    assert ColumnarParseDeclines.UnionDeclaration.SiteId == "parse.union"
    assert ColumnarParseDeclines.UnionDeclaration.Message == "union declaration could not be parsed into columnar input"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.UnionDeclaration)
}

test "the columnar parse decline vocabulary — constructors — is spelled exactly as a user reads it" {
    assert ColumnarParseDeclines.Constructor.SiteId == "parse.constructor"
    assert ColumnarParseDeclines.Constructor.Message == "constructor body or signature could not be parsed into columnar input"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.Constructor)

    assert ColumnarParseDeclines.ConstructorBody.SiteId == "parse.constructor.body"
    assert ColumnarParseDeclines.ConstructorBody.Message == "constructor body was not materialized as a supported block"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.ConstructorBody)

    assert ColumnarParseDeclines.ConstructorChain.SiteId == "parse.constructor.chain"
    assert ColumnarParseDeclines.ConstructorChain.Message == "constructor chain-argument metadata was invalid"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.ConstructorChain)

    assert ColumnarParseDeclines.ConstructorBodyNodes.SiteId == "parse.constructor.body-nodes"
    assert ColumnarParseDeclines.ConstructorBodyNodes.Message == "constructor body node table was invalid"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.ConstructorBodyNodes)
}

test "the columnar parse decline vocabulary — properties — is spelled exactly as a user reads it" {
    assert ColumnarParseDeclines.PropertyDeclaration.SiteId == "parse.property"
    assert ColumnarParseDeclines.PropertyDeclaration.Message == "property declaration could not be parsed into columnar input"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.PropertyDeclaration)

    assert ColumnarParseDeclines.PropertyGetter.SiteId == "parse.property.getter"
    assert ColumnarParseDeclines.PropertyGetter.Message == "property getter body was not materialized as a supported body"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.PropertyGetter)

    assert ColumnarParseDeclines.PropertyGetterNodes.SiteId == "parse.property.getter-nodes"
    assert ColumnarParseDeclines.PropertyGetterNodes.Message == "property getter node table was invalid"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.PropertyGetterNodes)

    assert ColumnarParseDeclines.PropertySetter.SiteId == "parse.property.setter"
    assert ColumnarParseDeclines.PropertySetter.Message == "property setter body was not materialized as a supported block"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.PropertySetter)

    assert ColumnarParseDeclines.PropertySetterNodes.SiteId == "parse.property.setter-nodes"
    assert ColumnarParseDeclines.PropertySetterNodes.Message == "property setter node table was invalid"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.PropertySetterNodes)

    assert ColumnarParseDeclines.PropertyAccessorKind.SiteId == "parse.property.accessor-kind"
    assert ColumnarParseDeclines.PropertyAccessorKind.Message == "property accessor kind was invalid"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.PropertyAccessorKind)
}

test "the columnar parse decline vocabulary — interfaces — is spelled exactly as a user reads it" {
    assert ColumnarParseDeclines.InterfaceDeclaration.SiteId == "parse.interface"
    assert ColumnarParseDeclines.InterfaceDeclaration.Message == "interface declaration could not be parsed into columnar input"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.InterfaceDeclaration)

    assert ColumnarParseDeclines.InterfaceTypeParameterMetadata.SiteId == "parse.interface.type-params"
    assert ColumnarParseDeclines.InterfaceTypeParameterMetadata.Message == "interface type parameter metadata was invalid"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.InterfaceTypeParameterMetadata)

    assert ColumnarParseDeclines.InterfaceTypeParameterName.SiteId == "parse.interface.type-param"
    assert ColumnarParseDeclines.InterfaceTypeParameterName.Message == "interface type parameter name was invalid"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.InterfaceTypeParameterName)

    assert ColumnarParseDeclines.InterfaceFlatParameterMetadata.SiteId == "parse.interface.params"
    assert ColumnarParseDeclines.InterfaceFlatParameterMetadata.Message == "interface flat parameter metadata was invalid"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.InterfaceFlatParameterMetadata)

    assert ColumnarParseDeclines.InterfaceParameterCount.SiteId == "parse.interface.params"
    assert ColumnarParseDeclines.InterfaceParameterCount.Message == "interface parameter metadata did not consume the expected count"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.InterfaceParameterCount)

    assert ColumnarParseDeclines.InterfaceMethodParameterMetadata.SiteId == "parse.interface.method-params"
    assert ColumnarParseDeclines.InterfaceMethodParameterMetadata.Message == "interface method parameter metadata was invalid"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.InterfaceMethodParameterMetadata)

    assert ColumnarParseDeclines.InterfaceMethodBody.SiteId == "parse.interface.method-body"
    assert ColumnarParseDeclines.InterfaceMethodBody.Message == "default interface method body could not be parsed into columnar input"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.InterfaceMethodBody)

    assert ColumnarParseDeclines.InterfaceMethodBodyFlag.SiteId == "parse.interface.method-body-flag"
    assert ColumnarParseDeclines.InterfaceMethodBodyFlag.Message == "interface method body flag was invalid"
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.InterfaceMethodBodyFlag)
}

test "the declaration-scan decline decodes all six of the kernel's own negative return codes" {
    // -2 … -6 are the codes `ColumnarProgramDeclarationIndicesInto` itself returns; anything else
    // is the generic stage, which is what makes the row total rather than a lookup that can miss.
    assert ColumnarParseDeclines.DeclarationScan(-2).SiteId == "parse.declaration-scan"
    assert ColumnarParseDeclines.DeclarationScan(-2).Message == "top-level declaration scan failed at function scan; the source may contain an unmodeled declaration shape such as setup or teardown"

    assert ColumnarParseDeclines.DeclarationScan(-3).Message == "top-level declaration scan failed at declaration name spans mismatched the declaration count; the source may contain an unmodeled declaration shape such as setup or teardown"
    assert ColumnarParseDeclines.DeclarationScan(-4).Message == "top-level declaration scan failed at duplicate top-level type names; the source may contain an unmodeled declaration shape such as setup or teardown"
    assert ColumnarParseDeclines.DeclarationScan(-5).Message == "top-level declaration scan failed at nominal (enum/union/interface) scan; the source may contain an unmodeled declaration shape such as setup or teardown"
    assert ColumnarParseDeclines.DeclarationScan(-6).Message == "top-level declaration scan failed at struct-like scan; the source may contain an unmodeled declaration shape such as setup or teardown"

    // The generic stage covers -1, every code past -6, and (defensively) any non-negative value.
    assert ColumnarParseDeclines.DeclarationScan(-1).Message == "top-level declaration scan failed at declaration scan; the source may contain an unmodeled declaration shape such as setup or teardown"
    assert ColumnarParseDeclines.DeclarationScan(-7).Message == "top-level declaration scan failed at declaration scan; the source may contain an unmodeled declaration shape such as setup or teardown"
    assert ColumnarParseDeclines.DeclarationScan(0).Message == "top-level declaration scan failed at declaration scan; the source may contain an unmodeled declaration shape such as setup or teardown"

    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.DeclarationScan(-2))
    assert ParseDeclineIsWellFormed(ColumnarParseDeclines.DeclarationScan(-1))
}

test "a vocabulary row renders into the sentence NL103 shows, through the owner that already renders declines" {
    // The two halves are not read in isolation by anyone: the product joins them. This is the
    // whole rendered artefact, with and without the member clause and the location.
    bare := new ColumnarDeclineReason(
        ColumnarParseDeclines.FunctionBody.SiteId,
        ColumnarParseDeclines.FunctionBody.Message,
        -1,
        0,
        ""
    )
    assert ColumnarDeclineReasonFacts.FormatDetail(bare, null, 0, 0) == "Declined at parse.function.body: function body was not materialized as a supported block or expression body."

    located := new ColumnarDeclineReason(
        ColumnarParseDeclines.PropertySetterNodes.SiteId,
        ColumnarParseDeclines.PropertySetterNodes.Message,
        42,
        6,
        "Widget.Size"
    )
    assert ColumnarDeclineReasonFacts.FormatDetail(located, "Program.nl", 12, 5) == "Declined at parse.property.setter-nodes: property setter node table was invalid in 'Widget.Size' (Program.nl:12:5)."

    scan := new ColumnarDeclineReason(
        ColumnarParseDeclines.DeclarationScan(-6).SiteId,
        ColumnarParseDeclines.DeclarationScan(-6).Message,
        0,
        1,
        ""
    )
    assert ColumnarDeclineReasonFacts.FormatDetail(scan, "Program.nl", 1, 1) == "Declined at parse.declaration-scan: top-level declaration scan failed at struct-like scan; the source may contain an unmodeled declaration shape such as setup or teardown (Program.nl:1:1)."
}

test "the shared site ids are shared on purpose, and the rows that share them stay distinguishable" {
    assert ColumnarParseDeclines.FunctionMaterialization.SiteId == ColumnarParseDeclines.FunctionDeclaration.SiteId
    assert ColumnarParseDeclines.FunctionDeclaration.SiteId == ColumnarParseDeclines.FunctionBodyOrSignature.SiteId
    assert ColumnarParseDeclines.FunctionMaterialization.Message != ColumnarParseDeclines.FunctionDeclaration.Message
    assert ColumnarParseDeclines.FunctionDeclaration.Message != ColumnarParseDeclines.FunctionBodyOrSignature.Message

    assert ColumnarParseDeclines.FunctionConstraintsWithoutTypeParameters.SiteId == ColumnarParseDeclines.FunctionConstraintMetadata.SiteId
    assert ColumnarParseDeclines.FunctionConstraintsWithoutTypeParameters.Message != ColumnarParseDeclines.FunctionConstraintMetadata.Message

    assert ColumnarParseDeclines.InterfaceFlatParameterMetadata.SiteId == ColumnarParseDeclines.InterfaceParameterCount.SiteId
    assert ColumnarParseDeclines.InterfaceFlatParameterMetadata.Message != ColumnarParseDeclines.InterfaceParameterCount.Message

    assert ColumnarParseDeclines.TestMaterialization.SiteId == ColumnarParseDeclines.TestDeclaration.SiteId
    assert ColumnarParseDeclines.TestMaterialization.Message != ColumnarParseDeclines.TestDeclaration.Message

    assert ColumnarParseDeclines.EnumMaterialization.SiteId == ColumnarParseDeclines.EnumDeclaration.SiteId
    assert ColumnarParseDeclines.EnumMaterialization.Message != ColumnarParseDeclines.EnumDeclaration.Message

    assert ColumnarParseDeclines.StructMaterialization.SiteId == ColumnarParseDeclines.StructDeclaration.SiteId
    assert ColumnarParseDeclines.StructMaterialization.Message != ColumnarParseDeclines.StructDeclaration.Message

    assert ColumnarParseDeclines.UnionMaterialization.SiteId == ColumnarParseDeclines.UnionDeclaration.SiteId
    assert ColumnarParseDeclines.UnionMaterialization.Message != ColumnarParseDeclines.UnionDeclaration.Message

    assert ColumnarParseDeclines.InterfaceMaterialization.SiteId == ColumnarParseDeclines.InterfaceDeclaration.SiteId
    assert ColumnarParseDeclines.InterfaceMaterialization.Message != ColumnarParseDeclines.InterfaceDeclaration.Message

    // The scan sites are the ones a user greps for after a `setup`/`teardown` block, and they are
    // NOT the same site as the materialization that follows a successful scan.
    assert ColumnarParseDeclines.NewtypeScan.SiteId != ColumnarParseDeclines.NewtypeMaterialization.SiteId
    assert ColumnarParseDeclines.TestScan.SiteId != ColumnarParseDeclines.TestMaterialization.SiteId
    assert ColumnarParseDeclines.Tokenize.SiteId != ColumnarParseDeclines.TokenizeInvalidResult.SiteId
}
