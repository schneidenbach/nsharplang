namespace NSharpLang.CensusGenericParamsExtension.Tests

import System
import System.Diagnostics
import System.IO

func WebFixtureRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "NSharpLang.sln")) && Directory.Exists(Path.Combine(directory, "src")) && Directory.Exists(Path.Combine(directory, "tests")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not locate the repository root above this test tree.")
}

// The project reference built the fixture into its own Debug/net10.0 output. Run THAT executable,
// because its adjacent runtimeconfig is what binds it to the ASP.NET shared framework.
func WebFixtureDll(): string {
    projectDirectory := Path.Combine(Path.Combine(Path.Combine(WebFixtureRepositoryRoot(), "tests"), "fixtures"), "web-generic-middleware")
    outputDirectory := Path.Combine(Path.Combine(Path.Combine(projectDirectory, "bin"), "Debug"), "net10.0")
    path := Path.Combine(outputDirectory, "NSharpLang.WebGenericMiddleware.dll")
    assert File.Exists(path), "The project-referenced web fixture was not built: " + path
    runtimeConfig := Path.Combine(outputDirectory, "NSharpLang.WebGenericMiddleware.runtimeconfig.json")
    assert File.Exists(runtimeConfig), "The project-referenced web fixture has no runtime config: " + runtimeConfig
    assert File.ReadAllText(runtimeConfig).Contains("Microsoft.AspNetCore.App"), "The web fixture must run on the ASP.NET shared framework."
    return path
}

// A SITE THAT WRITES ITS TYPE ARGUMENTS AND REACHES A `params` TAIL. Explicit type arguments skip
// inference, so nothing stops the tail from packing: zero trailing arguments are an empty array and
// several pack in order, and a defaulted fixed slot the site omits fills from metadata before an
// empty tail. `app.UseMiddleware<T>()` and `route.Produces<T>()` are the canonical ASP.NET shapes,
// and this project runs them for real.
test "UseMiddleware<T>() and Produces<T>() bind in a real WebApplication and run" {
    startInfo := new ProcessStartInfo { FileName: "dotnet" }
    startInfo.ArgumentList.Add(WebFixtureDll())
    startInfo.UseShellExecute = false
    startInfo.RedirectStandardOutput = true
    startInfo.RedirectStandardError = true

    process := new Process { StartInfo: startInfo }
    process.Start()
    standardError := process.StandardError.ReadToEndAsync()
    standardOutput := process.StandardOutput.ReadToEnd()
    if !process.WaitForExit(60000) {
        process.Kill(true)
        process.WaitForExit()
        assert false, "The web fixture did not exit within 60 seconds."
    }

    exitCode := process.ExitCode
    process.Dispose()
    errorText := standardError.Result
    assert exitCode == 0, "exit " + exitCode.ToString() + "\n" + standardOutput + errorText
    lines := standardOutput.Replace("\r\n", "\n").Trim().Split('\n')
    assert lines.Length == 4, standardOutput + errorText
    // `UseMiddleware<Stamp>()`: the zero-argument registration ran.
    assert lines[0] == "X-Stamp=stamped", standardOutput
    // `UseMiddleware<Tagged>("blue", 7)`: both packed arguments reached the constructor.
    assert lines[1] == "X-Tag=blue:7", standardOutput
    // The terminal delegate registered after both still ran, so each middleware called `next`.
    assert lines[2] == "Status=204", standardOutput
    // The endpoint's own `string` response comes first, then `Produces<Todo>()` — status and
    // content type from the omitted defaults, an empty tail — then the call that packs one extra
    // content type after its two fixed arguments.
    assert lines[3] == "Produces=200:String:text/plain|200:Todo:application/json|201:Todo:text/plain,application/xml", standardOutput
}
