# Task 043: dotnet new Console Template

**Effort:** Small (4-5 hours)
**Depends:** Task 042
**Ships:** `dotnet new nsharp-console` works

## Goal

Create console app template for dotnet new.

## Deliverable

Template that creates working N# console app.

## Implementation

Create `templates/console/.template.config/template.json`:

```json
{
  "$schema": "http://json.schemastore.org/template",
  "author": "N# Team",
  "classifications": ["Console"],
  "identity": "NSharp.Console",
  "name": "N# Console Application",
  "shortName": "nsharp-console",
  "tags": {
    "language": "N#",
    "type": "project"
  },
  "sourceName": "ConsoleApp",
  "preferNameDirectory": true
}
```

**Program.nl:**
```n#
func main(args: string[]) {
    print "Hello, World!"
}
```

**project.yml:**
```yaml
name: ConsoleApp
version: 1.0.0
entry: Program.nl
outputType: exe
targetFramework: net10.0
```

## Testing

```bash
dotnet new install templates/console
dotnet new nsharp-console -o MyApp
cd MyApp
dotnet run
# Output: Hello, World!
```

## Done When

- [ ] Template creates valid project
- [ ] Project builds without errors
- [ ] App runs and prints output
- [ ] Template on NuGet (later task)
