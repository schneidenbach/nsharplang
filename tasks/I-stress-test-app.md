# Task I: Real-World Stress Test — Build a Non-Trivial N# App

## Context

The best way to find compiler bugs is to USE the language. Build something real that exercises every major feature. Document every rough edge.

## What to build

A CLI task manager (think mini-Jira / Todoist from the terminal):

```
$ taskr add "Write unit tests" --priority high --tag backend
Created task #1: Write unit tests [HIGH] #backend

$ taskr list
 #  Status      Priority  Title                    Tags       Due
 1  ○ Todo      HIGH      Write unit tests         #backend   -
 2  ○ Todo      MEDIUM    Review PR                #frontend  Mar 30
 3  ● InProgress LOW      Update docs              #docs      -

$ taskr done 1
✓ Completed task #1: Write unit tests

$ taskr stats
Tasks: 3 total, 1 done, 1 in progress, 1 todo
Completion: 33%
By priority: HIGH: 1/1 done, MEDIUM: 0/1, LOW: 0/1
By tag: #backend: 1 task, #frontend: 1 task, #docs: 1 task

$ taskr search "test"
 1  ✓ Done  HIGH  Write unit tests  #backend
```

### Project structure

```
examples/16-task-cli/
├── project.yml
├── Program.nl              # CLI entry: argument parsing, command dispatch
├── Models/
│   ├── Task.nl             # Task record, Priority enum, Status union
│   └── Filter.nl           # Search/filter criteria record
├── Services/
│   ├── Store.nl            # JSON file persistence (async I/O)
│   ├── TaskService.nl      # Business logic, LINQ queries
│   └── Formatter.nl        # Pretty-print tables, colors
├── Commands/
│   ├── AddCommand.nl       # taskr add
│   ├── ListCommand.nl      # taskr list (with filters)
│   ├── DoneCommand.nl      # taskr done / taskr start
│   ├── DeleteCommand.nl    # taskr delete
│   └── StatsCommand.nl     # taskr stats
└── Program.tests.nl        # Tests for commands
```

### Language features to exercise

- **Unions**: `union Status { Todo, InProgress, Done }` — with pattern matching
- **Records**: `record Task { Id: int, Title: string, Status: Status, Priority: Priority, Tags: string[], DueDate: DateTime? }`
- **Enums**: `enum Priority { Low = 0, Medium = 1, High = 2 }`
- **Pattern matching**: match on Status union, Priority enum, filter criteria
- **Async I/O**: read/write JSON file with async File methods
- **LINQ**: filter, sort, group tasks
- **String interpolation**: formatted output
- **Error handling**: `result, err := ...` tuple style for file operations
- **Extension methods**: string helpers, date formatting
- **Generics**: generic service patterns
- **Null handling**: `?.`, `??` operators for optional fields
- **Type aliases**: `type TaskId = int`
- **Tests**: `.tests.nl` with assert statements

### After building

1. **Compile**: `dotnet build` must succeed with zero errors/warnings
2. **Run**: Exercise every command, verify output
3. **nlc check**: Run `nlc check --project examples/16-task-cli` — should report zero issues
4. **nlc query**: Test code intelligence:
   - `nlc query definition` on a Status union usage → should resolve to Models/Task.nl
   - `nlc query references` on TaskService → should find all files that use it
   - `nlc query completions` after `task.` → should show all Task record members
5. **nlc format**: Run formatter, verify output is clean
6. **Document bugs**: Create `examples/16-task-cli/BUGS-FOUND.md` listing ANY compiler issues:
   - Syntax that should work but doesn't
   - Error messages that are confusing
   - IDE features that don't work
   - Missing type inference
   - Performance issues

**DO NOT fix compiler bugs in this task.** Just document them. The point is to surface issues.

## Follow the standard verification protocol in tasks/STANDARD-SUFFIX.md
