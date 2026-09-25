namespace Census.FreeFunctionIdentity.Tests

import System
import System.Collections.Generic
import System.IO
import System.IO.Compression
import System.Reflection.Metadata
import System.Reflection.PortableExecutable

// THE HOLDERS THE SDK SHIPS, ACROSS ASSEMBLIES RATHER than inside one.
//
// The rows beside this file prove a holder per namespace inside ONE emitted assembly. The SDK's
// `tools/` carries several N#-emitted assemblies side by side - `Compiler.dll` and
// `NSharpLang.Compiler.Core.dll` today, eight Compiler.Core slices once it is split - and every C#
// consumer that references two of them resolves `Program` by its namespace. Two assemblies declaring
// `NSharpLang.Compiler.Program` is CS0433 in `Cli`, `LanguageServer` and `Playground`, and an EMPTY
// holder is the same collision with nothing to show for it; both have happened, and both were only
// visible in a seed, because only a seed is built by the compiler it ships. So the rows read what is
// actually shipped: the committed seed's package (or the seed `NSHARP_BOOTSTRAP_DIR` names - set it
// to a scratch reseed's bootstrap directory to hold a STAGE-2 seed to the same rule before it is
// committed), and the payload this tree's `NSharpLang.Build.Tasks` build lays out for the next pack.
class ShippedAssembly {
    Name: string
    Image: byte[]

    constructor(name: string, image: byte[]) {
        Name = name
        Image = image
    }
}

func ShippedRepositoryRoot(): string {
    current: string? = AppContext.BaseDirectory
    while current != null {
        directory := current ?? ""
        if File.Exists(Path.Combine(directory, "AGENTS.md")) && Directory.Exists(Path.Combine(directory, "src")) && Directory.Exists(Path.Combine(directory, "bootstrap")) {
            return directory
        }

        parent := Path.GetDirectoryName(directory)
        if parent == null || parent == "" || parent == directory {
            current = null
        } else {
            current = parent
        }
    }

    throw new InvalidOperationException("Could not locate the N# repository root from " + AppContext.BaseDirectory + ".")
}

func ShippedSeedPackage(): string {
    bootstrap := Environment.GetEnvironmentVariable("NSHARP_BOOTSTRAP_DIR") ?? ""
    if bootstrap.Length == 0 {
        bootstrap = Path.Combine(ShippedRepositoryRoot(), "bootstrap")
    }
    packages := Directory.GetFiles(bootstrap, "NSharpLang.Sdk.*.nupkg")
    if packages.Length != 1 {
        throw new InvalidOperationException("Expected exactly one NSharpLang.Sdk package in " + bootstrap + ", found " + packages.Length.ToString() + ".")
    }
    return packages[0]
}

// Every `.dll` directly under the package's `tools/`, read out of the archive without extracting it.
func ShippedSeedAssemblies(): List<ShippedAssembly> {
    assemblies := new List<ShippedAssembly>()
    archive := ZipFile.OpenRead(ShippedSeedPackage())
    try {
        for entry in archive.Entries {
            fullName := entry.FullName
            if fullName.StartsWith("tools/", StringComparison.Ordinal) && fullName.EndsWith(".dll", StringComparison.Ordinal) && fullName.IndexOf('/', 6) < 0 {
                buffer := new MemoryStream()
                entryStream := entry.Open()
                try {
                    entryStream.CopyTo(buffer)
                } finally {
                    entryStream.Dispose()
                }
                assemblies.Add(new ShippedAssembly(fullName, buffer.ToArray()))
            }
        }
    } finally {
        archive.Dispose()
    }
    return assemblies
}

// The N# assemblies `NSharpLang.Sdk.csproj` packs into `tools/` from the tasks project's output:
// the tasks, the facade, every Compiler.Core slice carved so far and Core itself, and the runtime.
// A payload that is not built is a failure, never an empty pass.
func ShippedPayloadAssemblies(): List<ShippedAssembly> {
    payload := Path.Combine(Path.Combine(Path.Combine(Path.Combine(Path.Combine(ShippedRepositoryRoot(), "src"), "NSharpLang.Build.Tasks"), "bin"), "Debug"), "net10.0")
    assemblies := new List<ShippedAssembly>()
    for name in ["NSharpLang.Build.Tasks.dll", "Compiler.dll", "NSharpLang.Compiler.Model.dll", "NSharpLang.Compiler.Syntax.dll", "NSharpLang.Compiler.Core.dll", "NSharpLang.Compiler.Driver.dll", "NSharpLang.Runtime.dll"] {
        path := Path.Combine(payload, name)
        if !File.Exists(path) {
            throw new InvalidOperationException("The SDK payload is not built: " + path + " is missing (build src/NSharpLang.Build.Tasks first).")
        }
        assemblies.Add(new ShippedAssembly("tools/" + name, File.ReadAllBytes(path)))
    }
    return assemblies
}

// One line per top-level holder - `Program` or the reserved `<Program>` - as
// `<assembly>|<namespace>.<name>|<empty or not>`. A nested type is never a holder.
func ShippedHolders(assemblies: List<ShippedAssembly>): List<string> {
    holders := new List<string>()
    for assembly in assemblies {
        reader := new PEReader(new MemoryStream(assembly.Image))
        try {
            if !reader.HasMetadata {
                continue
            }
            metadata := reader.GetMetadataReader()
            for handle in metadata.TypeDefinitions {
                typeDefinition := metadata.GetTypeDefinition(handle)
                name := metadata.GetString(typeDefinition.Name)
                if (name == "Program" || name == "<Program>") && typeDefinition.GetDeclaringType().IsNil {
                    empty := typeDefinition.GetMethods().Count == 0 && typeDefinition.GetFields().Count == 0
                    holders.Add(assembly.Name + "|" + metadata.GetString(typeDefinition.Namespace) + "." + name + "|" + (empty ? "empty" : "declares"))
                }
            }
        } finally {
            reader.Dispose()
        }
    }
    return holders
}

// Returns the violations: a namespace's holder declared by two shipped assemblies, or a holder that
// declares nothing.
func ShippedHolderViolations(assemblies: List<ShippedAssembly>): List<string> {
    violations := new List<string>()
    owners := new Dictionary<string, string>(StringComparer.Ordinal)
    for holder in ShippedHolders(assemblies) {
        parts := holder.Split('|')
        previous: string? = null
        if owners.TryGetValue(parts[1], out previous) {
            violations.Add(parts[1] + " is declared by both " + (previous ?? "") + " and " + parts[0])
        } else {
            owners[parts[1]] = parts[0]
        }
        if parts[2] == "empty" {
            violations.Add(parts[1] + " in " + parts[0] + " declares nothing")
        }
    }
    return violations
}

test "no two assemblies the seed SDK ships declare a holder for one namespace, and none it ships is empty" {
    assemblies := ShippedSeedAssemblies()
    names := new List<string>()
    for assembly in assemblies {
        names.Add(assembly.Name)
    }
    // Anti-vacuity: the seed carries the two N#-emitted compiler assemblies, and they DO hold free
    // functions - the global namespace's parser kernels - so an empty holder list is a broken read.
    assert names.Contains("tools/Compiler.dll") && names.Contains("tools/NSharpLang.Compiler.Core.dll"), string.Join(",", names)
    assert ShippedHolders(assemblies).Count > 0, string.Join(",", names)

    violations := ShippedHolderViolations(assemblies)
    assert violations.Count == 0, string.Join("; ", violations)
}

test "the payload this tree lays out for the next SDK pack keeps one holder per namespace, none of them empty" {
    assemblies := ShippedPayloadAssemblies()
    assert ShippedHolders(assemblies).Count > 0
    violations := ShippedHolderViolations(assemblies)
    assert violations.Count == 0, string.Join("; ", violations)
}

// The rule's own control: this assembly's image, which declares real holders, shipped under two
// names must be reported for every namespace it holds.
test "a holder shipped by two assemblies is reported" {
    ownImage := File.ReadAllBytes(typeof(IdentityFacts).get_Assembly().Location)
    twice := new List<ShippedAssembly>()
    twice.Add(new ShippedAssembly("tools/First.dll", ownImage))
    twice.Add(new ShippedAssembly("tools/Second.dll", ownImage))
    violations := ShippedHolderViolations(twice)
    assert string.Join("; ", violations).Contains("Census.FreeFunctionIdentity.X.Program is declared by both tools/First.dll and tools/Second.dll"), string.Join("; ", violations)
}
