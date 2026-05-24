import React from 'react';
import Link from '@docusaurus/Link';
import Layout from '@theme/Layout';
import CodeBlock from '@theme/CodeBlock';

const installCommand = 'curl -fsSL https://raw.githubusercontent.com/schneidenbach/nsharplang/main/scripts/install.sh | bash && . "$HOME/.nsharp/env"';

const csharpCode = `using System;
using System.Linq;

namespace MyApp;

public class Program
{
    public static void Main()
    {
        var name = "World";
        Console.WriteLine($"Hello, {name}!");

        var numbers = new[] { 1, 2, 3, 4, 5 };
        var doubled = numbers
            .Select(x => x * 2)
            .ToList();

        foreach (var num in doubled)
        {
            Console.WriteLine(num);
        }
    }
}`;

const nsharpCode = `import System
import System.Linq



func Main() {
    name := "World"
    print $"Hello, {name}!"

    let numbers = [1, 2, 3, 4, 5]
    doubled := numbers
        .Select(x => x * 2)
        .ToList()

    foreach num in doubled {
        print num
    }
}`;

const features = [
  {
    icon: '\u2726',
    title: 'Discriminated Unions',
    desc: 'First-class union types with exhaustive pattern matching. The compiler catches missing cases at build time.',
    code: `union Shape {
    Circle { radius: double }
    Rect { width: double, height: double }
}

func Area(s: Shape): double {
    return match s {
        Shape.Circle { radius } => 3.14 * radius * radius,
        Shape.Rect { width, height } => width * height
    }
}`,
  },
  {
    icon: '\u2B22',
    title: 'Duck Interfaces',
    desc: 'Structural typing without boilerplate. If a type has the right methods, it matches the interface.',
    code: `duck interface IReader {
    func Read(): string
}

class FileReader {
    func Read(): string {
        return "file contents"
    }
}

// FileReader matches IReader automatically
func Process(r: IReader) {
    print r.Read()
}`,
  },
  {
    icon: '\u25B7',
    title: 'Go-Style Syntax',
    desc: 'Short variable declarations with :=, no semicolons, convention-based visibility. Less noise, more signal.',
    code: `func Main() {
    name := "Alice"             // type inferred
    let items = [1, 2, 3]      // immutable binding
    count: int = 0              // explicit type

    for item in items {
        count += item
    }

    print $"{name}: {count}"   // string interpolation
}`,
  },
  {
    icon: '\u21C4',
    title: 'Pragmatic C# Interop',
    desc: 'Use NuGet packages and call C# libraries in covered interop scenarios. N# is designed for CLR integration, with limitations documented instead of hidden.',
    code: `import Microsoft.AspNetCore.Builder

func main(args: string[]) {
    builder := WebApplication.CreateBuilder(args)
    app := builder.Build()

    app.MapGet("/", () => "Hello from N#!")
    app.MapGet("/json", () => new {
        Message: "Works with ASP.NET Core"
    })

    app.Run()
}`,
  },
];

const toolingItems = [
  {
    icon: '\u2318',
    title: 'nlc CLI',
    desc: 'A broad pre-release CLI surface modeled on Go/Rust inner loops: check, format, lint, test, benchmark, and related project commands.',
    code: 'nlc check && nlc format --check && nlc lint',
  },
  {
    icon: '\u26A1',
    title: 'VS Code Extension',
    desc: 'The public installer adds the N# VS Code extension when the code CLI is available, with the language server bundled for editor features.',
    code: 'code --install-extension nsharp.nsharp',
  },
  {
    icon: '\uD83E\uDD16',
    title: 'LLM-First Queries',
    desc: '`check`, `fix`, `query`, and `lint` default to structured JSON; other commands expose JSON where implemented for automation and AI agents.',
    code: 'nlc query inspect --file main.nl --pos 10:5',
  },
  {
    icon: '\uD83D\uDD27',
    title: 'Auto-Fix',
    desc: 'Compiler-suggested fixes for supported scenarios such as missing imports and cleanup. Use --dry-run in CI or review before applying.',
    code: 'nlc fix --dry-run',
  },
  {
    icon: '\uD83D\uDCE6',
    title: 'Dependency Management',
    desc: 'Add, remove, update, audit, and visualize your NuGet dependencies. Detect unused packages with nlc tidy.',
    code: 'nlc add Serilog@3.1.1 && nlc tree',
  },
  {
    icon: '\uD83C\uDFAF',
    title: 'Static Analysis',
    desc: 'Static analysis covers supported rules such as unused variables, missing imports, async-without-await, and unreachable code. Verify rule coverage against current nlc help/tests.',
    code: 'nlc lint --text',
  },
];

const exampleCards = [
  {
    title: 'Hello World',
    tag: 'Basics',
    code: `import System

func Main() {
    name := "World"
    print $"Hello, {name}!"
}`,
  },
  {
    title: 'Error Handling',
    tag: 'Go-style',
    code: `func Divide(a: int, b: int): int {
    if b == 0 {
        throw new Exception("divide by zero")
    }
    return a / b
}

func Main() {
    result, err := Divide(10, 0)
    if err != null {
        print $"Error: {err.Message}"
    }
}`,
  },
  {
    title: 'Union + Pattern Matching',
    tag: 'Types',
    code: `union Result {
    Success { value: int }
    Failure { error: string, code: int }
}

func Handle(r: Result): string {
    return match r {
        Result.Success { value } =>
            $"OK: {value}",
        Result.Failure { error, code } =>
            $"Error {code}: {error}"
    }
}`,
  },
  {
    title: 'LINQ Pipeline',
    tag: 'Collections',
    code: `import System.Linq

func Main() {
    let names = ["Alice", "Bob", "Charlie", "Dave"]

    result := names
        .Where(n => n.Length > 3)
        .Select(n => n.ToUpper())
        .ToList()

    foreach name in result {
        print name
    }
}`,
  },
  {
    title: 'Records & Classes',
    tag: 'Types',
    code: `record Point {
    X: int
    Y: int
}

class Logger(name: string) {
    func Log(msg: string) {
        print $"[{name}] {msg}"
    }
}

func Main() {
    p := new Point { X: 10, Y: 20 }
    p2 := p with { X: 30 }
    print $"({p2.X}, {p2.Y})"
}`,
  },
  {
    title: 'Built-in Testing',
    tag: 'Tooling',
    code: `func Add(a: int, b: int): int => a + b

test "Add returns correct sum" {
    assert Add(2, 3) == 5
    assert Add(-1, 1) == 0
    assert Add(0, 0) == 0
}

test "Add handles large numbers" {
    result := Add(1000000, 2000000)
    assert result == 3000000
}`,
  },
];

function FeatureCard({icon, title, desc, code}) {
  return (
    <div className="feature-card">
      <div className="feature-card__icon">{icon}</div>
      <h3 className="feature-card__title">{title}</h3>
      <p className="feature-card__desc">{desc}</p>
      <div className="feature-card__code">
        <CodeBlock language="nsharp">{code}</CodeBlock>
      </div>
    </div>
  );
}

function ToolingCard({icon, title, desc, code}) {
  return (
    <div className="tooling-card">
      <div className="tooling-card__icon">{icon}</div>
      <h3 className="tooling-card__title">{title}</h3>
      <p className="tooling-card__desc">{desc}</p>
      <div className="tooling-card__code">
        <code>{code}</code>
      </div>
    </div>
  );
}

function ExampleCard({title, tag, code}) {
  return (
    <div className="example-card">
      <div className="example-card__header">
        <span className="example-card__title">{title}</span>
        <span className="example-card__tag">{tag}</span>
      </div>
      <div className="example-card__code">
        <CodeBlock language="nsharp">{code}</CodeBlock>
      </div>
    </div>
  );
}

export default function Home() {
  return (
    <Layout
      title="Simple by design. Powerful by .NET."
      description="N# — A pragmatic language with Go-inspired syntax, discriminated unions, duck interfaces, and practical C# interop.">

      {/* Hero */}
      <header className="hero--nsharp">
        <div className="container hero__inner">
          <div className="hero__intro">
            <div className="hero__badge">Open source language for .NET</div>
            <h1 className="hero__title">N#</h1>
            <p className="hero__lede">Simple by design. Powerful by .NET.</p>
            <div className="hero__buttons">
              <Link className="btn--primary" to="/docs/getting-started">Get started</Link>
              <Link className="btn--secondary" to="/examples">Examples</Link>
              <a className="btn--secondary" href="https://github.com/schneidenbach/nsharplang" target="_blank" rel="noopener noreferrer">GitHub</a>
            </div>
          </div>

          {/* C# vs N# comparison */}
          <div className="comparison">
            <div className="comparison__grid">
              <div className="comparison__panel">
                <div className="comparison__header">
                  <span className="comparison__header-dot comparison__header-dot--csharp" />
                  C#
                </div>
                <div className="comparison__code">
                  <CodeBlock language="csharp">{csharpCode}</CodeBlock>
                </div>
              </div>
              <div className="comparison__panel">
                <div className="comparison__header">
                  <span className="comparison__header-dot comparison__header-dot--nsharp" />
                  N#
                </div>
                <div className="comparison__code">
                  <CodeBlock language="nsharp">{nsharpCode}</CodeBlock>
                </div>
              </div>
            </div>
          </div>
        </div>
      </header>

      <main>
        {/* Features */}
        <section className="section section--alt">
          <div className="section__header">
            <h2 className="section__title">Why N#?</h2>
            <p className="section__subtitle">
              The best parts of Go's simplicity, built for the .NET ecosystem.
            </p>
          </div>
          <div className="features-grid">
            {features.map((f, i) => <FeatureCard key={i} {...f} />)}
          </div>
        </section>

        {/* Tooling */}
        <section className="section">
          <div className="section__header">
            <h2 className="section__title">Tooling That Is Becoming the Product</h2>
            <p className="section__subtitle">
              A broad pre-release CLI surface modeled on Go/Rust inner loops, with structured JSON on the key automation commands used by agents.
            </p>
          </div>
          <div className="tooling-grid">
            {toolingItems.map((t, i) => <ToolingCard key={i} {...t} />)}
          </div>
        </section>

        {/* Quick Start */}
        <section className="section section--alt">
          <div className="section__header">
            <h2 className="section__title">Quick Start</h2>
            <p className="section__subtitle">One copied command installs nlc, templates, SDK restore support, the language server, and VS Code tooling when VS Code is on PATH.</p>
          </div>
          <div className="quickstart">
            <div className="quickstart__block">
              <div className="quickstart__header">
                <span className="quickstart__title">Install</span>
              </div>
              <div className="quickstart__codeblock">
                <CodeBlock language="bash">{installCommand}</CodeBlock>
              </div>
              <div className="quickstart__followup">
                <CodeBlock language="bash">{`nlc doctor
nlc new MyApp
cd MyApp
nlc run`}</CodeBlock>
              </div>
            </div>
          </div>
        </section>

        {/* Code Examples */}
        <section className="section">
          <div className="section__header">
            <h2 className="section__title">N# in Action</h2>
            <p className="section__subtitle">Real code, real syntax. No pseudocode.</p>
          </div>
          <div className="examples-grid">
            {exampleCards.map((e, i) => <ExampleCard key={i} {...e} />)}
          </div>
          <div className="section__action">
            <Link className="btn--secondary" to="/examples">
              See all examples →
            </Link>
          </div>
        </section>
      </main>
    </Layout>
  );
}
