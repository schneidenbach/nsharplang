# Task 042: .nlproj Project Files

**Effort:** Small (6-8 hours)
**Depends:** Task 041
**Ships:** .nlproj files recognized by dotnet

## Goal

Create MSBuild SDK that enables .nlproj project files.

## Deliverable

SDK with Sdk.props and Sdk.targets that dotnet recognizes.

## Implementation

Create `sdk/Microsoft.NET.Sdk.NSharp/Sdk/`:

**Sdk.props:**
```xml
<Project>
  <PropertyGroup>
    <TargetFramework Condition="'$(TargetFramework)' == ''">net9.0</TargetFramework>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
  </PropertyGroup>

  <ItemGroup>
    <NSharpCompile Include="**/*.nl" Exclude="**/*.tests.nl" />
  </ItemGroup>
</Project>
```

**Sdk.targets:**
```xml
<Project>
  <UsingTask TaskName="NSharpCompile"
             AssemblyFile="$(NSharpTasksPath)/NSharp.Build.Tasks.dll" />

  <Target Name="CoreNSharpCompile"
          BeforeTargets="CoreCompile">
    <NSharpCompile Sources="@(NSharpCompile)"
                   References="@(ReferencePath)"
                   OutputPath="$(IntermediateOutputPath)" />

    <ItemGroup>
      <Compile Include="$(IntermediateOutputPath)/**/*.cs" />
    </ItemGroup>
  </Target>
</Project>
```

**Example .nlproj:**
```xml
<Project Sdk="Microsoft.NET.Sdk.NSharp">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
  </PropertyGroup>
</Project>
```

## Testing

```bash
cat > MyApp.nlproj <<EOF
<Project Sdk="Microsoft.NET.Sdk.NSharp">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
  </PropertyGroup>
</Project>
EOF

cat > Program.nl <<EOF
func main() { print "Works!" }
EOF

dotnet build
dotnet run
# Output: Works!
```

## Done When

- [ ] .nlproj files build with dotnet
- [ ] All .nl files auto-discovered
- [ ] Test files excluded from main build
- [ ] References work correctly
