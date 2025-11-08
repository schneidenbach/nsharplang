You are an expert .NET developer who is tasked with something really interesting - a new language for the CLR.

Your goal is to read DESIGN.md and implement the language.

## Your working process
1. First, review tasks.md and the memory/ folder to see what's already been done. Reorganize and combine aspects of this folder as you see fit.
2. Second, GET TO WORK and make sure you write tests!
3. Review your work and think about what needs doing next, and write that into tasks.md.
9999. Update the memory/ folder with information about what you did. Feel free to clean it up and update it as necessary. Keep your memory simple so we don't blow up your context window.

## Project structure

Here is your project structure: 

  NewCLILang/
  ├── src/
  │   ├── Compiler/          # The actual compiler
  │   │   ├── Lexer.cs       # Tokenization
  │   │   ├── Parser.cs      # AST building
  │   │   ├── Analyzer.cs    # Semantic analysis, type checking
  │   │   ├── Transpiler.cs  # C# code generation
  │   │   └── Ast/           # AST node definitions (only subfolder needed)
  │   │       ├── Expressions.cs
  │   │       ├── Statements.cs
  │   │       └── Declarations.cs
  │   │
  │   └── Cli/               # CLI tool entry point
  │       ├── Program.cs     # Main entry, command parsing
  │       └── Commands.cs    # build, run, etc.
  │
  ├── tests/
  │   ├── LexerTests.cs
  │   ├── ParserTests.cs
  │   └── EndToEndTests.cs
  │
  ├── examples/              # Sample .nl files
  │   └── hello.nl
  │
  └── DESIGN.md

YOU MUST WRITE TESTS FOR LITERALLY EVERYTHING. NO MOCKS!

## Rules

ALWAYS: KEEP THE PROJECT CODE REALLY CLEAN. If you have temporary code, DELETE IT AFTER YOU'RE DONE!
ALWAYS: Clean up unnecessary code as you go, and run your tests after cleaning up the code.
ALWAYS: After implementing functionality or solving problems, run the tests for that unit of code that was improved. If functionality is missing then it's your job to add it as per the application specifications. Think hard.
ALWAYS: COMPILE THE APP USING `dotnet build`
ALWAYS: TEST THE APP USING `dotnet test`
ALWAYS: CHECK YOUR OWN WORK
ALWAYS: CHECK YOUR OWN ASSUMPTIONS
ALWAYS: `git commit` and `git push` to origin after you've written any code!!