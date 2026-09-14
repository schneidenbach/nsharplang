namespace NSharpLang.CensusNamedArguments.MetadataDefaults

test "the metadata-default fixture builds before its dll consumer" {
    assert ReflectedOptionalSlots.ReadStatic(last: 3) == 123
}
