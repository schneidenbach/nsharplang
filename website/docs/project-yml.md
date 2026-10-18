---
sidebar_label: project.yml Reference
title: project.yml Reference
displayed_sidebar: docsSidebar
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
  - project: ../Orders.Domain/project.yml
  - dll: libs/Vendor.Pricing.dll
```

## Top-level keys

| Key | Values | Default | Meaning |
|-----|--------|---------|---------|
| `name` | text | see meaning | The assembly name, so `name: Orders` builds `Orders.dll`. **Always set it.** When it is missing, `nlc build` names the assembly after the project directory, but `dotnet build`, `nlc pack` and a project that references this one use the name of the *current working directory* instead, so the two only agree when you run from the project directory. |
| `version` | `major.minor.patch[-suffix]` | none | Assembly, file and package version. |
| `entry` | path | none | The file that holds `main`. If you set it, the file must exist. |
| `outputType` | `exe`, `library` | `exe` | Whether the build makes a program or a library. Only these two lowercase spellings are accepted. |
| `targetFramework` | `net10.0`, … | `net10.0` | The target framework moniker. It decides which shared-framework version and which NuGet assets are used. |
| `sdk` | MSBuild SDK id | `Microsoft.NET.Sdk` | The base MSBuild SDK `dotnet build` uses. `Microsoft.NET.Sdk.Web` also references `Microsoft.AspNetCore.App`, under both `nlc` and `dotnet build`; no other SDK id does. See [What a project can see](#what-a-project-can-see). |
| `backend` | `il` | `il` | The code generator. `il` is the only value. |
| `dependencies` | list | empty | Packages, frameworks, projects and DLLs. See [Dependencies](#dependencies). |
| `testDependencies` | list of NuGet entries | empty | Packages that only test builds (`nlc test`) see. |
| `testFramework` | `xunit`, `nunit` | `xunit` | The test framework `nlc test` and `dotnet test` use. |
| `excludeTests` | `true`, `false` | `false` | `true` leaves `*.tests.nl` files out of `dotnet build`. `nlc build` never compiles test files; `nlc test` does. |
| `defines` | list of symbols | empty | Conditional-compilation symbols for `#if`. See the [CLI reference](./cli-reference.md). |
| `exclude` | list of glob patterns | empty | `.nl` files to leave out of the build. Patterns are matched against paths relative to the project directory and support `*` and `**/`. |
| `debugType` | `none`, `portable`, `embedded`, `full`, `pdbonly` | `none` | Passed to MSBuild as `DebugType` when you build with `dotnet build`. |
| `internalsVisibleTo` | list of assembly names | empty | Friend assemblies that can see this project's `internal` members. See [Types](./types.md). |
| `language` | mapping | — | `profile`, `asyncDefaultType` and the `systems` policy. See [Language settings](./getting-started.md#language-settings) and [the Systems Profile](./systems.md). |
| `package` | mapping | — | NuGet metadata for `nlc pack`: `id`, `author`, `description`, `tags`, `license`, `repository`, `icon`, `readme`. |

## Dependencies

`dependencies:` is a list. Each entry has exactly one kind: `nuget`, `framework`, `project` or `dll`,
and a `nuget` entry may also have a `version`. Anything else is refused when the project is read,
with the entry's position: two kinds in one entry, a key that is not one of these five (keys are not
case-sensitive), `version` on a non-NuGet entry, or a nested value:

```text
Invalid dependencies entry 2: 'nugget' is not a dependency key. Each entry names exactly one of nuget, framework, project or dll, and a nuget entry may also give a version.
```

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
  have a version specified` (measured with the .NET 10 SDK). `nlc add` always writes a version.
- The packages a package depends on come along automatically. When more than one version of the
  same package is asked for, a version you list directly in `dependencies:` always wins. Otherwise
  the **highest** version asked for anywhere in the graph wins, however deep it is, which is what
  `dotnet restore` resolves.
- Packages are downloaded into the NuGet global packages folder (`~/.nuget/packages`, or
  `$NUGET_PACKAGES`). After a package is restored, its assemblies are copied next to your program.

### Shared frameworks (`framework`)

```yaml
dependencies:
  - framework: Microsoft.AspNetCore.App
```

A `framework:` entry names a .NET shared framework installed under `<dotnet>/shared/`, such as
`Microsoft.AspNetCore.App`. The project can then use every assembly in that framework, from the
installed version that matches `targetFramework`. `nlc` stops with an error if no matching version is
installed.

You only need an entry for a framework **beyond what the project already gets**. Every project gets
all of `Microsoft.NETCore.App`, and a `sdk: Microsoft.NET.Sdk.Web` project also gets
`Microsoft.AspNetCore.App` (see [What a project can see](#what-a-project-can-see)). The usual reason
to write one is a library or console program that uses ASP.NET Core without the Web SDK.

Writing a framework the project already gets is harmless: `- framework: Microsoft.NETCore.App` adds
nothing, and neither does `- framework: Microsoft.AspNetCore.App` in a Web SDK project. The SDK does
not pass these entries on to MSBuild, so they cause no NETSDK1086 warning under `dotnet build`.

### Other N# projects (`project`)

```yaml
dependencies:
  - project: ../Orders.Domain/project.yml
```

A `project:` entry is the path to another N# project's `project.yml`, relative to this project's
directory. The path has to name the file. A bare directory is rejected with an error that shows the
entry to write instead. `nlc add --path ../Orders.Domain` accepts the directory and writes the
`project.yml` path for you, with `/` separators. It refuses a path that does not exist, a directory
without a `project.yml`, and any other file such as a `.csproj`, and it treats different spellings
of the same file (`../Orders.Domain`, `../Orders.Domain/./project.yml`, an absolute path) as one
reference.

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

Point `dll:` at an implementation assembly (the one from a `lib/` folder or a project's `bin/`),
not at a reference assembly from a `ref/` folder. Reference assemblies have no code to run, and the
two build commands handle them differently: `nlc build` swaps a NuGet-style `ref/<tfm>/` path for the
matching `lib/<tfm>/` implementation when one exists, while `dotnet build` compiles against and copies
exactly the file you named, and .NET refuses to load a reference assembly at run time.

## What a project can see

Every project compiles against the same shared frameworks under `nlc` (`build`, `run`, `check`,
`test`, the editor) as under `dotnet build`:

| `sdk:` | Shared frameworks the project sees without a `framework:` entry |
|--------|------------------------------------------------------------------|
| `Microsoft.NET.Sdk` (the default) | `Microsoft.NETCore.App` |
| `Microsoft.NET.Sdk.Web` | `Microsoft.NETCore.App` and `Microsoft.AspNetCore.App` |
| any other SDK id | `Microsoft.NETCore.App` |

`Microsoft.NETCore.App` is the whole base library: every assembly in its reference pack (the
`packs/Microsoft.NETCore.App.Ref` directory of your .NET installation), the same list `dotnet build`
compiles against. So a project with no `dependencies:` can use, for example:

<!-- default-framework-namespaces:start -->
| Type or namespace | Import |
|-------------------|--------|
| `IServiceProvider` | `System` |
| `ClaimsIdentity`, `ClaimsPrincipal` | `System.Security.Claims` |
| `XmlDocument` | `System.Xml` |
| `BigInteger` | `System.Numerics` |
| `ImmutableArray<T>`, `ImmutableDictionary<K, V>` | `System.Collections.Immutable` |
| `Channel<T>` | `System.Threading.Channels` |
| `Meter`, `Counter<T>` | `System.Diagnostics.Metrics` |
| `TypeConverter` | `System.ComponentModel` |
| `DataTable` | `System.Data` |
<!-- default-framework-namespaces:end -->

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

A fully-qualified name works without an import too, as it does in C#:
`total := System.Numerics.BigInteger.Parse("123456789012345678901234567890")`.

Every N# program also gets the N# runtime library (`NSharpLang.Runtime`).

`sdk:` is matched exactly, as MSBuild matches it. `Microsoft.NET.Sdk.BlazorWebAssembly` and
`Microsoft.NET.Sdk.WebAssembly` contain `Web` in their names, but `dotnet build` gives them no
ASP.NET Core framework, so `nlc` does not either. A project that wants ASP.NET Core under one of
them, or under `Microsoft.NET.Sdk`, adds `- framework: Microsoft.AspNetCore.App`.

### How fast is the whole framework?

`nlc` reads which namespaces each `Microsoft.NETCore.App` assembly defines once per process, and
loads an assembly's types only when your code imports one of its namespaces or spells one of its
types fully qualified. A project pays for the parts of the framework it uses, not for all of it.

### ASP.NET Core projects

A `sdk: Microsoft.NET.Sdk.Web` project sees both frameworks with no `dependencies:` at all:

```yaml
sdk: Microsoft.NET.Sdk.Web
```

Writing `- framework: Microsoft.AspNetCore.App` as well, as the `nsharp-webapi` template does, is
harmless: `nlc` reads it once and `dotnet build` does not see it twice.

Libraries and console programs that use `Microsoft.Extensions.*` packages that ship in ASP.NET Core
(dependency injection, hosting, configuration, logging) need `framework: Microsoft.AspNetCore.App`,
or `sdk: Microsoft.NET.Sdk.Web`, or the matching `nuget:` packages.

## How the two build commands read dependencies

| | `nlc build` / `nlc check` / editor | `dotnet build` (NSharpLang.Sdk) |
|---|---|---|
| No dependencies | All of `Microsoft.NETCore.App`, plus `Microsoft.AspNetCore.App` under `sdk: Microsoft.NET.Sdk.Web` | The same |
| `nuget:` | Restored and resolved by `nlc` | `PackageReference` |
| `framework:` | Every assembly in the shared framework; a framework the project already gets adds nothing | `FrameworkReference`, except a framework MSBuild already references (`Microsoft.NETCore.App`; `Microsoft.AspNetCore.App` under `sdk: Microsoft.NET.Sdk.Web`) |
| `project:` | Builds the referenced N# project | `ProjectReference` to the referenced `.csproj` |
| `dll:` | Compile reference, copied to the output | `Reference`, copied to the output and listed in `.deps.json` |

Both commands compile your code against the same set of assemblies.
