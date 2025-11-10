# Task 049: Website Landing Page

**Effort:** Medium (8-10 hours)
**Depends:** Task 044
**Ships:** https://nsharp.dev live

## Goal

Create professional landing page.

## Deliverable

Single-page website with hero, quick start, and download.

## Structure

```
website/
├── index.html
├── style.css
└── favicon.ico
```

**index.html sections:**
1. Hero - "Go for .NET"
2. Quick Start - 3 commands to hello world
3. Features - 4 key highlights
4. Download - install instructions

## Content

**Hero:**
```
N# - Go for .NET
Pragmatic, simple language for the CLR
[Get Started] [View Docs] [GitHub]
```

**Quick Start:**
```bash
# Install
dotnet new install NSharp.Templates

# Create
dotnet new nsharp-console -o MyApp

# Run
cd MyApp && dotnet run
```

**Features:**
- Simple syntax (Go-inspired)
- Full .NET interop
- Modern type system
- Great tooling

**Download:**
```
NuGet: Microsoft.NET.Sdk.NSharp
VS Code Extension: nsharp
GitHub: anthropics/NewCLILang
```

## Hosting

GitHub Pages or Cloudflare Pages (free).

## Done When

- [ ] Site loads at nsharp.dev
- [ ] Mobile responsive
- [ ] Fast (<1s load)
- [ ] Professional design
