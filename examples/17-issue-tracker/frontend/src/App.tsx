import { useEffect, useState } from "react";
import type { CSSProperties } from "react";
import type { Issue, Priority } from "./types";
import { statusLabel, statusColor } from "./types";
import "./App.css";

const starterIssues: Issue[] = [
  {
    id: 1,
    title: "Prove N# can ship an ASP.NET app",
    description:
      "The backend is N# Minimal API code, the frontend is ordinary React, and the route contract is JSON over HTTP.",
    status: { type: "Open" },
    priority: "Critical",
    createdAt: new Date().toISOString(),
    tags: ["aspnet", "demo"],
  },
  {
    id: 2,
    title: "Pattern-match issue workflow states",
    description:
      "IssueStatus is a real union: Open has no payload, InProgress carries an assignee, Closed carries a resolution and timestamp.",
    status: { type: "InProgress", assigneeId: 7 },
    priority: "High",
    createdAt: new Date().toISOString(),
    tags: ["unions", "patterns"],
  },
  {
    id: 3,
    title: "Keep the project flat and readable",
    description:
      "Records, services, workflow, and endpoints live in a Go-like package layout instead of ceremony-heavy folders.",
    status: {
      type: "Closed",
      resolution: "Flagship example polished",
      closedAt: new Date().toISOString(),
    },
    priority: "Medium",
    createdAt: new Date().toISOString(),
    tags: ["records", "cli", "vscode"],
  },
];

const featureCards = [
  {
    title: "Visibility by casing",
    body: "PascalCase members are public. camelCase helpers are private. No public/private keyword soup.",
    code: `static func Transition(...) { ... }\nstatic func isValid(...) { ... }`,
  },
  {
    title: "Unions + exhaustive matches",
    body: "IssueStatus carries different data per case. Workflow code matches variants instead of parsing strings.",
    code: `match status {\n  IssueStatus.Open => "Open"\n  IssueStatus.Closed { resolution } => resolution\n}`,
  },
  {
    title: "ASP.NET without pretending",
    body: "The backend uses WebApplication, Minimal API routes, static files, and ordinary .NET JSON serialization.",
    code: `app.MapGet("/api/issues", () => service.GetAll())\napp.MapFallbackToFile("index.html")`,
  },
];

function normalizeIssues(data: Issue[]): Issue[] {
  return data.length === 0 ? starterIssues : data;
}

export function App() {
  const [issues, setIssues] = useState<Issue[]>(starterIssues);
  const [title, setTitle] = useState("Show VS Code tasks running nlc build/test");
  const [description, setDescription] = useState(
    "This app is meant to be demoed from the browser, CLI, and editor without hand-waving.",
  );
  const [priority, setPriority] = useState<Priority>("High");
  const [tags, setTags] = useState("vscode, cli, proof");
  const [error, setError] = useState<string | null>(null);
  const [apiState, setApiState] = useState("checking");

  useEffect(() => {
    fetch("/api/issues")
      .then((r) => {
        if (!r.ok) {
          throw new Error(`GET /api/issues returned ${r.status}`);
        }
        return r.json();
      })
      .then((data) => {
        setIssues(normalizeIssues(data));
        setApiState("live");
      })
      .catch(() => {
        setApiState("demo data");
        setError("Backend is not reachable yet; showing built-in demo issues.");
      });
  }, []);

  const createIssue = async () => {
    setError(null);
    const nextTags = tags
      .split(",")
      .map((tag) => tag.trim())
      .filter(Boolean);

    const res = await fetch("/api/issues", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title, description, priority, tags: nextTags }),
    });

    if (!res.ok) {
      const text = await res.text();
      setError(text);
      return;
    }

    const data = await res.json();
    setIssues((prev) => {
      const withoutStarter = apiState === "live" ? prev.filter((issue) => issue.id < data.id) : prev;
      return [...withoutStarter, data];
    });
    setApiState("live");
    setTitle("");
    setDescription("");
    setTags("");
  };

  return (
    <main className="app-shell">
      <section className="hero">
        <div className="hero-copy">
          <p className="kicker">N# flagship demo · full stack · no smoke and mirrors</p>
          <h1>A real issue tracker written in N#.</h1>
          <p className="hero-lede">
            This example is the proof path: N# records and unions model the domain,
            ASP.NET serves the API, React consumes the contract, and the same project
            is buildable from the CLI or VS Code tasks.
          </p>
          <div className="hero-actions" aria-label="demo highlights">
            <span className="pill success">/api/issues backend path</span>
            <span className="pill">records + unions</span>
            <span className="pill">visibility by casing</span>
            <span className="pill dark">nlc build/test ready</span>
          </div>
        </div>

        <section className="tracker-card" aria-label="issue tracker">
          <div className="tracker-header">
            <div>
              <h2>Live issue board</h2>
              <p>Create an issue to hit the N# backend and render the JSON response.</p>
            </div>
            <span className="health-badge">API: {apiState}</span>
          </div>

          <div className="issue-form">
            <input
              aria-label="Issue title"
              placeholder="Title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
            />
            <textarea
              aria-label="Issue description"
              placeholder="Description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
            />
            <input
              aria-label="Comma separated tags"
              placeholder="Tags, comma separated"
              value={tags}
              onChange={(e) => setTags(e.target.value)}
            />
            <div className="form-row">
              <select
                aria-label="Priority"
                value={priority}
                onChange={(e) => setPriority(e.target.value as Priority)}
              >
                <option>Low</option>
                <option>Medium</option>
                <option>High</option>
                <option>Critical</option>
              </select>
              <button className="primary-button" onClick={createIssue} type="button">
                Create via N# API
              </button>
            </div>
            {error && <div className="error-banner">{error}</div>}
          </div>

          <div className="issue-list">
            {issues.map((issue) => (
              <article
                className="issue-card"
                key={`${issue.id}-${issue.title}`}
                style={{ "--status-color": statusColor(issue.status) } as CSSProperties}
              >
                <div className="issue-topline">
                  <strong>#{issue.id} {issue.title}</strong>
                  <span className="status-chip">{statusLabel(issue.status)}</span>
                </div>
                <p className="issue-description">{issue.description}</p>
                <div className="issue-meta">
                  <span className="priority-chip">{issue.priority} priority</span>
                  {issue.tags.map((tag) => (
                    <span className="tag-chip" key={tag}>#{tag}</span>
                  ))}
                </div>
              </article>
            ))}
          </div>
        </section>
      </section>

      <section className="showcase-grid" aria-label="N# feature showcase">
        {featureCards.map((card) => (
          <article className="showcase-card" key={card.title}>
            <h3>{card.title}</h3>
            <p>{card.body}</p>
            <code className="code-block">{card.code}</code>
          </article>
        ))}
      </section>

      <section className="demo-card">
        <h2>Demo path</h2>
        <p>
          Run <code>./scripts/demo.sh</code> from this folder. It installs dependencies,
          builds the React assets, restores/builds the N# backend, runs backend tests,
          starts ASP.NET, curls the API, and tells you exactly what to open in the browser.
        </p>
        <ol className="demo-steps">
          <li><span>1</span>CLI: <code>nlc restore</code>, <code>nlc test</code>, <code>dotnet build</code></li>
          <li><span>2</span>Backend: ASP.NET Minimal API at <code>/api/issues</code></li>
          <li><span>3</span>Browser: polished React UI served by the N# app</li>
          <li><span>4</span>Editor: VS Code tasks for build, test, and full demo</li>
        </ol>
      </section>
    </main>
  );
}
