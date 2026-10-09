namespace NSharpLang.GateScriptContracts.Tests

test "the product gate checks every configured example and template project with zero errors and warnings" {
    coreScript := ReadGateScript("test-all-core.sh")

    assert coreScript.Contains("find examples templates -name project.yml"), "Step 10 must enumerate project.yml files under both examples/ and templates/ so nested projects cannot fall through a top-level directory sweep."
    assert coreScript.Contains("s.get('errors',-1),s.get('warnings',-1),s.get('projectFailures',0)"), "Step 10 must read both error and warning counts and reject workspace project failures."
    assert coreScript.Contains("[ \"$errors\" = \"0\" ] && [ \"$warnings\" = \"0\" ] && [ \"$project_failures\" = \"0\" ] && [ \"$is_ok\" = \"true\" ]"), "A project passes Step 10 only when it reports zero errors, zero warnings, no project failures, and an ok result."
}

test "Step 10 checks both projects created by the installed console and web API templates" {
    coreScript := ReadGateScript("test-all-core.sh")

    assert coreScript.Contains("$TEMP_DIR/TestConsoleApp")
    assert coreScript.Contains("$TEMP_DIR/TestWebApiApp")
    assert coreScript.Contains("trap cleanup_on_exit EXIT")
    assert coreScript.Contains("rm -rf \"$TEMP_DIR\""), "The generated projects must remain available through Step 10 and be removed when the gate exits, including failure paths."
}
