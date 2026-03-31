---
sidebar_label: Debugging
title: Debugging
---

# Debugging N# Code

## Prerequisites

- **VS Code** with the N# extension installed
- **C# extension** -- automatically installed as a dependency of the N# extension (provides the `coreclr` debugger)
- **.NET 9.0 SDK** or later

## Quick Start

1. Open your N# project in VS Code
2. Set a breakpoint in any `.nl` file by clicking the gutter (or pressing F9)
3. Press **F5** to start debugging -- no configuration needed

The N# extension provides a built-in debug configuration. There is no need to create `launch.json` or `tasks.json` manually.

## Setting Breakpoints

Click in the gutter to the left of a line number in any `.nl` file, or place your cursor on a line and press **F9**. A red dot appears to indicate an active breakpoint.

Breakpoints work on executable lines (variable assignments, function calls, control flow statements, etc.). Breakpoints on declarations, blank lines, or comments will not be hit.

## Stepping Through Code

| Action         | Shortcut            |
|----------------|---------------------|
| Step Over      | F10                 |
| Step Into      | F11                 |
| Step Out       | Shift+F11           |
| Continue       | F5                  |
| Stop Debugging | Shift+F5            |

- **Step Over (F10)** -- Execute the current line and move to the next line in the same scope.
- **Step Into (F11)** -- If the current line contains a function call, jump into that function's body.
- **Step Out (Shift+F11)** -- Run the rest of the current function and return to the caller.

## Variable Inspection

**Hover** -- Hover your mouse over any variable while paused at a breakpoint to see its current value and type.

**Variables panel** -- The left sidebar shows local variables, parameters, and `this` (when inside a method) with their current values.

**Watch window** -- Add expressions to the Watch panel to monitor specific values across stepping. Click the `+` icon in the Watch panel and type a variable name or expression.

**Debug Console** -- Evaluate expressions interactively while paused. Open it with Ctrl+Shift+Y (Cmd+Shift+Y on macOS).

## Call Stack

The Call Stack panel shows the chain of function calls that led to the current breakpoint. Each frame displays the `.nl` file name and line number, so you can navigate your N# source directly from the call stack.

Click any frame to jump to that location in the source.

## Conditional Breakpoints

Right-click an existing breakpoint (or the gutter) and select **Add Conditional Breakpoint**. You can set:

- **Expression** -- Break only when a condition is true
- **Hit Count** -- Break after the breakpoint has been hit N times
- **Log Message** -- Print a message to the debug console without stopping

**Note:** Condition expressions are evaluated as C# expressions by the coreclr debugger, since N# compiles to C# at runtime. Use C# syntax for conditions (e.g., `x > 10`, `name == "Alice"`). Variable names match what you see in the Variables panel.

## Attach to Running Process

To debug an already-running N# application:

1. Open the Command Palette (Cmd+Shift+P / Ctrl+Shift+P)
2. Select **Debug: Attach to a .NET 5+ or .NET Core process**
3. Pick the process from the list

This is useful for debugging long-running services, ASP.NET Core applications, or processes launched outside VS Code.

## How It Works

N# compiles to C# via transpilation. The generated C# code includes `#line` directives that map each line back to the original `.nl` source file. When .NET builds the project, the PDB (debug symbols) file records these mappings.

At debug time, the coreclr debugger reads the PDB and shows you the original `.nl` source rather than the generated C# code. Generated scaffolding (entry points, boilerplate) is hidden from the debugger using `#line hidden` directives, so you only step through your own code.

## Troubleshooting

**Breakpoint shows as hollow/unverified circle:**
- Ensure the project builds successfully (`dotnet build`)
- Rebuild after making changes -- breakpoints bind to the last successful build

**F5 does nothing or shows "No configurations":**
- Ensure the N# extension is installed and active (check the Extensions panel)
- Verify the C# extension is installed (should be automatic)
- Reload the VS Code window (Cmd+Shift+P > "Developer: Reload Window")

**Stepping lands in generated C# code:**
- This can happen if the `#line` directives are out of sync. Rebuild the project with `dotnet build`
- If the issue persists, clean and rebuild: `dotnet clean && dotnet build`

**Variables show unexpected names:**
- The debugger shows C# runtime names. Most N# variables map directly, but some generated temporaries may appear with compiler-generated names. Focus on the variables in the Variables panel that match your N# source.

**Cannot attach to process:**
- Ensure the target process was built in Debug configuration (not Release)
- On macOS, you may need to authorize the debugger. VS Code will prompt for your password if needed
