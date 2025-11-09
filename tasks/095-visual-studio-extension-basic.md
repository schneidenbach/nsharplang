# Task 095: Visual Studio Extension (Basic)

**Effort:** Very Large (40-50 hours)
**Depends:** Tasks 042, 056
**Ships:** VS recognizes project.yml files

## Goal

Create Visual Studio extension with basic support.

## Deliverable

VSIX extension with project system integration.

## Implementation

**VSPackage structure:**
```
NSharp.VisualStudio/
├── NSharpPackage.cs
├── ProjectSystem/
│   ├── NSharpProjectFactory.cs
│   └── NSharpProjectNode.cs
├── Editor/
│   ├── NSharpClassifier.cs
│   └── NSharpTokenTag.cs
└── source.extension.vsixmanifest
```

**NSharpPackage.cs:**
```csharp
[PackageRegistration(UseManagedResourcesOnly = true)]
[InstalledProductRegistration("#110", "#112", "1.0")]
[ProvideProjectFactory(typeof(NSharpProjectFactory),
    "N#", "N# Project Files (project.yml)", "yml", "yml",
    @"Templates\Projects", LanguageVsTemplate = "NSharp")]
[Guid(PackageGuidString)]
public sealed class NSharpPackage : AsyncPackage
{
    public const string PackageGuidString = "...";

    protected override async Task InitializeAsync(
        CancellationToken cancellationToken,
        IProgress<ServiceProgressData> progress)
    {
        await JoinableTaskFactory.SwitchToMainThreadAsync(cancellationToken);
        // Register services
    }
}
```

## Features (Phase 1)

- [ ] Syntax highlighting
- [ ] project.yml in "New Project" dialog
- [ ] Solution Explorer integration
- [ ] Build/Run from toolbar
- [ ] Error list integration

## Done When

- [ ] Extension installs in VS 2022
- [ ] Can create N# projects
- [ ] Build works (F5)
- [ ] Basic syntax colors
- [ ] Published to VS Marketplace
