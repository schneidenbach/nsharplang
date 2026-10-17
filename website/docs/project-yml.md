---
sidebar_label: project.yml Reference
title: project.yml Reference
---

# project.yml Reference

An N# project is a directory with a `project.yml` file in it. Everything about the project lives in
that file: its name, its output type, and the assemblies it depends on. `nlc build`, `nlc run`,
`nlc check`, `nlc test`, the language server and the MSBuild SDK (`dotnet build`) all read the same
file. Never put build settings in a `.csproj`. If a project has one, it is a single line:
`<Project Sdk="NSharpLang.Sdk" />`.

```yaml
name: Orders
version: 1.2.0
entry: Program.nl
outputType: exe
targetFramework: net10.0

dependencies:
  - nuget: Serilog
    version: 3.1.1
  - framework: Microsoft.NETCore.App
  - project: ../Orders.Domain/project.yml
  - dll: libs/Vendor.Pricing.dll
```

## Top-level keys

| Key | Values | Default | Meaning |
|-----|--------|---------|---------|
| `name` | text | the directory name | The assembly name, so `name: Orders` builds `Orders.dll`. |
| `version` | `major.minor.patch[-suffix]` | none | Assembly, file and package version. |
| `entry` | path | none | The file that holds `main`. If you set it, the file must exist. |
| `outputType` | `exe`, `library` | `exe` | Whether the build makes a program or a library. Only these two lowercase spellings are accepted. |
| `targetFramework` | `net10.0`, … | `net10.0` | The target framework moniker. It decides which shared-framework version and which NuGet assets are used. |
| `sdk` | MSBuild SDK id | `Microsoft.NET.Sdk` | The base SDK. `Microsoft.NET.Sdk.Web` (any id that contains `Web`) also references `Microsoft.AspNetCore.App`. See [Shared frameworks](#shared-frameworks-framework). |
| `dependencies` | list | empty | Packages, frameworks, projects and DLLs. See [Dependencies](#dependencies). |
| `testDependencies` | list of NuGet entries | empty | Packages that only test builds (`nlc test`) see. |
| `testFramework` | `xunit`, `nunit` | `xunit` | The test framework `nlc test` and `dotnet test` use. |
| `defines` | list of symbols | empty | Conditional-compilation symbols for `#if`. See the [CLI reference](./cli-reference.md). |
| `exclude` | list of glob patterns | empty | `.nl` files to leave out of the build. Patterns are matched against paths relative to the project directory and support `*` and `**/`. |
| `debugType` | `none`, `portable`, `embedded`, `full`, `pdbonly` | `none` | Passed to MSBuild as `DebugType` when you build with `dotnet build`. |
| `internalsVisibleTo` | list of assembly names | empty | Friend assemblies that can see this project's `internal` members. See [Types](./types.md). |
| `language` | mapping | — | `profile`, `asyncDefaultType` and the `systems` policy. See [Language settings](./getting-started.md#language-settings) and [the Systems Profile](./systems.md). |
| `package` | mapping | — | NuGet metadata for `nlc pack`: `id`, `author`, `description`, `tags`, `license`, `repository`, `icon`, `readme`. |

## Dependencies

`dependencies:` is a list. Each entry has exactly one kind: `nuget`, `framework`, `project` or `dll`.
You can edit the list by hand or with [`nlc add`](./cli-reference.md):

| Command | Writes |
|---------|--------|
| `nlc add Serilog@3.1.1` | `- Serilog@3.1.1` |
| `nlc add Serilog` | the latest stable version on nuget.org, for example `- Serilog@4.2.0` |
| `nlc add Microsoft.AspNetCore.App --framework` | `- framework: Microsoft.AspNetCore.App` |
| `nlc add --path ../Orders.Domain` | `- project: ../Orders.Domain/project.yml` |

### NuGet packages (`nuget`)

A package and its version can be written in three ways. All three mean the same thing:

```yaml
dependencies:
  - Newtonsoft.Json@13.0.3        # short form, the one `nlc add` writes

  - nuget: Newtonsoft.Json@13.0.3 # the same, with the kind spelled out

  - nuget: Newtonsoft.Json        # name and version as separate keys
    version: 13.0.3
```

- **Always write a version.** It has to be an exact version; ranges such as `[13.0,)` are not
  supported. If you leave the version out, `nlc` uses the highest version already in your NuGet
  global packages folder, or the latest stable version on nuget.org if there is none, but
  `dotnet build` refuses the entry with `error NU1015: The following PackageReference item(s) do not
  have a version specified`. `nlc add` always writes a version.
- The packages a package depends on come along automatically. When two packages ask for different
  versions of the same package, NuGet's rules decide which one wins: a direct reference first, then
  the nearest one.
- Packages are downloaded into the NuGet global packages folder (`~/.nuget/packages`, or
  `$NUGET_PACKAGES`). After a package is restored, its assemblies are copied next to your program.

### Shared frameworks (`framework`)

```yaml
dependencies:
  - framework: Microsoft.AspNetCore.App
```

A `framework:` entry names a .NET shared framework: `Microsoft.NETCore.App`,
`Microsoft.AspNetCore.App`, or another one installed under `<dotnet>/shared/`. The project can then
see every assembly in that framework, using the installed version that matches `targetFramework`.
`nlc` stops with an error if no matching version is installed. `sdk: Microsoft.NET.Sdk.Web` adds
`Microsoft.AspNetCore.App` for you.

### Other N# projects (`project`)

```yaml
dependencies:
  - project: ../Orders.Domain/project.yml
```

A `project:` entry is the path to another N# project's `project.yml`, relative to this project's
directory. The path has to name the file. A bare directory is rejected with an error that shows the
entry to write instead. `nlc add --path ../Orders.Domain` accepts the directory and writes the
`project.yml` path for you.

- `nlc build` builds the referenced project first, compiles against its output, and copies that
  output next to yours. You can also use the referenced project's own `project:` dependencies
  (A → B → C means A can use C's types), the same way MSBuild handles references between projects.
- Reference cycles are reported as errors, and the error shows the whole chain.
- `nlc check --use-built-references` compiles against the referenced project's existing build
  output instead of rebuilding it, and reports an error if that output is missing or out of date.
- `dotnet build` turns each entry into an MSBuild `ProjectReference` to the `.csproj` next to the
  referenced `project.yml`, so each referenced project needs its own one-line `.csproj`.
  `dotnet build` also accepts a `.csproj` path. `nlc` accepts only N# projects. To reference a
  prebuilt C# library from `nlc`, use a `dll:` entry.

### Prebuilt assemblies (`dll`)

```yaml
dependencies:
  - dll: libs/Vendor.Pricing.dll
```

A `dll:` entry is the path to an assembly file, absolute or relative to the project directory. The
file must exist. The project compiles against it, and both `nlc build` and `dotnet build` copy it
next to the output. With `dotnet build` it is also listed in the program's `.deps.json`.

## What a project can see without any dependencies

If a project has no `dependencies:`, `nlc` compiles it against a **fixed set of assemblies** from the
.NET runtime it runs on. That is **not** all of `Microsoft.NETCore.App`. The set is:

<!-- implicit-assemblies:start -->
- `System.Runtime`
- `System.Console`
- `System.Collections`
- `System.Linq`
- `System.Linq.Queryable`
- `System.Net.Http`
- `System.Text.Json`
- `System.Threading`
- `System.Threading.Tasks`
- `System.IO.FileSystem`
- `System.Text.RegularExpressions`
- `System.ComponentModel.Annotations`
- `System.Collections.Concurrent`
- `System.Diagnostics.Debug`
- `System.Diagnostics.Process`
- `System.Runtime.InteropServices`
- `System.ObjectModel`
- `System.Linq.Expressions`
- `System.Memory`
- `System.IO.Pipes`
- `System.Net.Primitives`
- `System.Net.Sockets`
- `System.Security.Cryptography`
- `System.Text.Encoding.Extensions`
- `System.Xml.ReaderWriter`
- `System.Private.CoreLib`
- `System.Private.Xml.Linq`
- `System.Reflection.Metadata`
- `System.IO.FileSystem.Watcher`
- `System.IO.Compression`
- `System.IO.Compression.ZipFile`
- `System.Reflection.Emit`
- `System.IO.Pipelines`
<!-- implicit-assemblies:end -->

Together these cover the everyday library: primitive types, collections, LINQ, `Task`, files and
streams, `Stopwatch`, `ArrayPool<T>`, regular expressions, `HttpClient`, `System.Text.Json`,
`SHA256` and so on. Every N# program also
gets the N# runtime library (`NSharpLang.Runtime`).

Types in other `Microsoft.NETCore.App` assemblies are **not** visible by default. Using one gives
`NL201 Type '…' not found`, and importing its namespace gives `NL704 I can't find namespace`.
Common examples:

| Type or namespace | Assembly it lives in |
|-------------------|----------------------|
| `System.IServiceProvider` | `System.ComponentModel` |
| `System.Security.Claims` (`ClaimsIdentity`, `ClaimsPrincipal`) | `System.Security.Claims` |
| `System.Xml` (`XmlDocument`) | `System.Private.Xml` |
| `System.Numerics.BigInteger` | `System.Runtime.Numerics` |
| `System.Collections.Immutable` | `System.Collections.Immutable` |
| `System.Threading.Channels` | `System.Threading.Channels` |
| `System.Diagnostics.Activity`, `System.Diagnostics.Metrics` | `System.Diagnostics.DiagnosticSource` |
| `System.ComponentModel.TypeConverter` | `System.ComponentModel.TypeConverter` |
| `System.Data` (`DataTable`) | `System.Data.Common` |

### Seeing all of Microsoft.NETCore.App

To compile against the whole base framework, add it as a framework dependency:

```yaml
dependencies:
  - framework: Microsoft.NETCore.App
```

For example, this program fails on a project with no dependencies and builds once the entry above is
added:

```n#
import System
import System.Security.Claims

func main() {
    sp: IServiceProvider? = null
    id := new ClaimsIdentity()
    print (sp == null).ToString()
    print id.IsAuthenticated.ToString()
}
```

Without the entry, `nlc build` reports:

```text
error NL704: I can't find namespace 'System.Security.Claims' — check the spelling and make sure the assembly is referenced
error NL201: Type 'IServiceProvider' not found
error NL201: Type 'ClaimsIdentity' not found
```

`dotnet build` already references `Microsoft.NETCore.App` implicitly, as every .NET SDK project
does, so it compiles this program even without the entry. Add the entry anyway so that `nlc build`,
`nlc check` and the editor agree with `dotnet build`. The SDK does not pass this entry on to MSBuild,
so it does not cause the NETSDK1086 warning.

### ASP.NET Core projects

`Microsoft.AspNetCore.App` adds the ASP.NET Core assemblies only. **It does not include the rest of
Microsoft.NETCore.App** under `nlc`. An ASP.NET Core project that uses `IServiceProvider`, claims or
any other type from the table above needs both frameworks:

```yaml
sdk: Microsoft.NET.Sdk.Web          # implies framework: Microsoft.AspNetCore.App

dependencies:
  - framework: Microsoft.NETCore.App
```

Libraries and console programs that use `Microsoft.Extensions.*` packages that ship in ASP.NET Core
(dependency injection, hosting, configuration, logging) need `framework: Microsoft.AspNetCore.App`,
or `sdk: Microsoft.NET.Sdk.Web`, or the matching `nuget:` packages.

## How the two build commands read dependencies

| | `nlc build` / `nlc check` / editor | `dotnet build` (NSharpLang.Sdk) |
|---|---|---|
| No dependencies | The fixed set of assemblies listed above | All of `Microsoft.NETCore.App` |
| `nuget:` | Restored and resolved by `nlc` | `PackageReference` |
| `framework:` | Every assembly in the shared framework | `FrameworkReference` (`Microsoft.NETCore.App` is already implicit) |
| `project:` | Builds the referenced N# project | `ProjectReference` to the referenced `.csproj` |
| `dll:` | Compile reference, copied to the output | `Reference`, copied to the output and listed in `.deps.json` |

Unless you add `framework: Microsoft.NETCore.App`, the first row is the only difference between the
two. With that entry in place, both commands compile your code against the same set of assemblies.
