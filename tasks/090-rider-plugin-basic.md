# Task 090: Rider Plugin (Basic)

**Effort:** Large (25-30 hours)
**Depends:** Tasks 042, 056
**Ships:** Rider recognizes .nlproj files

## Goal

Create JetBrains Rider plugin with basic support.

## Deliverable

Plugin that provides syntax highlighting and project support.

## Implementation

Create IntelliJ Platform plugin:

**plugin.xml:**
```xml
<idea-plugin>
  <id>com.nsharp.rider</id>
  <name>N# Language Support</name>
  <vendor>N# Team</vendor>

  <depends>com.intellij.modules.rider</depends>

  <extensions defaultExtensionNs="com.intellij">
    <fileType
        name="N#"
        implementationClass="com.nsharp.NSharpFileType"
        fieldName="INSTANCE"
        language="NSharp"
        extensions="nl"/>

    <lang.syntaxHighlighterFactory
        language="NSharp"
        implementationClass="com.nsharp.NSharpSyntaxHighlighterFactory"/>
  </extensions>
</idea-plugin>
```

## Features (Phase 1)

- [ ] Syntax highlighting
- [ ] .nlproj project recognition
- [ ] Build integration (calls dotnet build)
- [ ] Run configurations

## Done When

- [ ] Plugin installs in Rider
- [ ] .nl files have syntax highlighting
- [ ] Can build projects
- [ ] Can run projects
- [ ] Published to JetBrains Marketplace
