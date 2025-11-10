# Task 048: Format on Save (VS Code)

**Effort:** Small (3-4 hours)
**Depends:** Task 046
**Ships:** VS Code formats .nl files on save

## Goal

Integrate formatter with VS Code extension.

## Deliverable

Format-on-save works in VS Code.

## Implementation

Update `editors/vscode/src/extension.ts`:

```typescript
import { execSync } from 'child_process';
import * as vscode from 'vscode';

export function activate(context: vscode.ExtensionContext) {
    // ... existing code ...

    // Register formatter
    context.subscriptions.push(
        vscode.languages.registerDocumentFormattingEditProvider('nsharp', {
            provideDocumentFormattingEdits(document: vscode.TextDocument): vscode.TextEdit[] {
                const formatted = formatDocument(document);
                const fullRange = new vscode.Range(
                    document.positionAt(0),
                    document.positionAt(document.getText().length)
                );
                return [vscode.TextEdit.replace(fullRange, formatted)];
            }
        })
    );
}

function formatDocument(document: vscode.TextDocument): string {
    const tempFile = `/tmp/${Date.now()}.nl`;
    fs.writeFileSync(tempFile, document.getText());

    try {
        execSync(`nsharp format ${tempFile}`);
        return fs.readFileSync(tempFile, 'utf-8');
    } finally {
        fs.unlinkSync(tempFile);
    }
}
```

**settings.json:**
```json
{
  "[nsharp]": {
    "editor.formatOnSave": true
  }
}
```

## Done When

- [ ] Format on save works
- [ ] Format on demand (Shift+Alt+F)
- [ ] Preserves cursor position
- [ ] Shows errors if format fails
