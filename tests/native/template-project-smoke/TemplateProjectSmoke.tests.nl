namespace NSharpLang.TemplateProjectSmoke.Tests

import System.Collections.Generic
import NSharpLang.Cli


// THE SET ITSELF IS A CONTRACT. A template that stops being discovered stops being built, and a
// row that iterates whatever it finds would go green by finding nothing.
test "every shipped template directory is discovered" {
    names := TemplateSmokeTemplateNames()

    assert names.Count == 6, string.Join(",", names)
    assert names.Contains("nsharp-console"), string.Join(",", names)
    assert names.Contains("nsharp-library"), string.Join(",", names)
    assert names.Contains("nsharp-systems-cli"), string.Join(",", names)
    assert names.Contains("nsharp-systems-lib"), string.Join(",", names)
    assert names.Contains("nsharp-test"), string.Join(",", names)
    assert names.Contains("nsharp-webapi"), string.Join(",", names)
}

// GATE STEP 7, AS A ROW. Every `templates/*/` project is copied out of the tree and built through
// the entry `nlc build` runs — reference resolution and all — and its output file must exist.
test "every shipped template project builds through the compiler's own entry point" {
    failures := TemplateSmokeBuildAllShipped()

    assert failures == "", failures
}

// THE ONE THAT CAUGHT A RESOLVER DEFECT, named on its own so the failure says so. `nsharp-webapi`
// is the only template with `nuget:` dependencies and a framework reference, so it is the only one
// whose build exercises package resolution at all — and a wrong package-version rule in that
// resolver is what the gate's template step found while every other gate step stayed green.
test "the web API template — the one with package references — builds" {
    outcome := TemplateSmokeBuildShippedTemplate("nsharp-webapi")

    assert outcome.Built, outcome.Reason
}

// GATE STEPS 5-6, AS ROWS, AGAINST THE OTHER SOURCE. `dotnet new` scaffolds from `templates/`;
// `nlc new` writes its files from `NewCommandKernels`. They are two different bodies of shipped
// text and a user meets whichever one their first command uses.
test "every project `nlc new` scaffolds builds" {
    scaffolded := new List<string>()
    scaffolded.Add("console")
    scaffolded.Add("library")
    scaffolded.Add("test")
    scaffolded.Add("systems-cli")
    scaffolded.Add("systems-lib")

    failures := ""
    for templateName in scaffolded {
        outcome := TemplateSmokeBuildScaffolded(templateName)
        if !outcome.Built {
            if failures.Length > 0 {
                failures = failures + " ;; "
            }

            failures = failures + outcome.Name + ": " + outcome.Reason
        }
    }

    assert failures == "", failures
}

// A SCAFFOLDED PROJECT IS THE ONE THE COMMAND WOULD HAVE WRITTEN, not an approximation: the
// directory, the `project.yml` path, the two MSBuild-path files and every source file come from the
// kernels the command calls. If `nlc new` grows a file, this row writes it too.
test "the scaffold writes the files the command writes" {
    projectDirectory := TemplateSmokeScaffold("test", "SmokeShape")

    assert System.IO.File.Exists(NewCommandKernels.GetProjectYamlPath(projectDirectory))
    assert System.IO.File.Exists(NewCommandKernels.GetGlobalJsonPath(projectDirectory))
    assert System.IO.File.Exists(NewCommandKernels.GetNuGetConfigPath(projectDirectory))

    kinds := NewCommandKernels.GetTemplateSourceFileKinds("test")
    assert kinds.Length == 2
    index := 0
    while index < kinds.Length {
        assert System.IO.File.Exists(NewCommandKernels.GetTemplateSourceFilePath(projectDirectory, kinds[index]))
        index = index + 1
    }

    // The csproj-free shape the gate asserts in Step 6.
    assert System.IO.Directory.GetFiles(projectDirectory, "*.csproj").Length == 0
}
