# Task 042: dotnet build with project.yml

**Effort:** Small (6-8 hours)
**Depends:** Task 041
**Ships:** `dotnet build` works with project.yml

## Goal

Make `dotnet build` recognize and use project.yml files.

## Deliverable

MSBuild SDK that reads project.yml and builds N# projects.

## Implementation

Update MSBuild task to auto-detect project.yml:

**MSBuild.targets:**
```xml
<Project>
  <UsingTask TaskName="NSharpBuild"
             AssemblyFile="$(NSharpTasksPath)/NSharp.Build.Tasks.dll" />

  <Target Name="NSharpCompile" BeforeTargets="CoreCompile">
    <!-- Auto-detect project.yml -->
    <PropertyGroup>
      <NSharpProjectFile Condition="Exists('project.yml')">project.yml</NSharpProjectFile>
    </PropertyGroup>

    <NSharpBuild ProjectFile="$(NSharpProjectFile)"
                 OutputPath="$(IntermediateOutputPath)" />

    <ItemGroup>
      <Compile Include="$(IntermediateOutputPath)/**/*.cs" />
    </ItemGroup>
  </Target>
</Project>
```

**Keep using project.yml:**
```yaml
name: MyApp
version: 1.0.0
targetFramework: net9.0
outputType: exe
entry: Program.nl

dependencies:
  - nuget: Newtonsoft.Json
    version: 13.0.3
```

## Testing

```bash
# Just use project.yml (no XML!)
cat > project.yml <<EOF
name: MyApp
outputType: exe
targetFramework: net9.0
entry: Program.nl
EOF

cat > Program.nl <<EOF
func main() { print "Works!" }
EOF

# Should work with dotnet CLI
dotnet build
dotnet run
# Output: Works!
```

## Done When

- [ ] `dotnet build` finds project.yml automatically
- [ ] All .nl files auto-discovered
- [ ] Test files excluded from main build
- [ ] Dependencies work correctly
- [ ] NO XML REQUIRED!
