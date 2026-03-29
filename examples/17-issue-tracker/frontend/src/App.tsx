import { useEffect, useState } from "react";
import type { Issue, Priority } from "./types";
import { statusLabel, statusColor } from "./types";

export function App() {
  const [issues, setIssues] = useState<Issue[]>([]);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [priority, setPriority] = useState<Priority>("Medium");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch("/api/issues")
      .then((r) => r.json())
      .then((data) => setIssues(data))
      .catch(() => setError("Failed to load issues"));
  }, []);

  const createIssue = async () => {
    setError(null);
    const res = await fetch("/api/issues", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title, description, priority, tags: [] }),
    });
    if (!res.ok) {
      const text = await res.text();
      setError(text);
      return;
    }
    const data = await res.json();
    setIssues((prev) => [...prev, data]);
    setTitle("");
    setDescription("");
  };

  return (
    <div style={{ maxWidth: 720, margin: "2rem auto", fontFamily: "system-ui" }}>
      <h1>Issue Tracker</h1>
      <p style={{ color: "#6b7280" }}>
        Powered by N# — a Go-inspired language for .NET
      </p>

      <div style={{ marginBottom: "1.5rem", padding: "1rem", background: "#f9fafb", borderRadius: 8 }}>
        <h3 style={{ marginTop: 0 }}>New Issue</h3>
        <input
          placeholder="Title"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          style={{ display: "block", width: "100%", marginBottom: 8, padding: 8, boxSizing: "border-box" }}
        />
        <textarea
          placeholder="Description"
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          style={{ display: "block", width: "100%", marginBottom: 8, padding: 8, boxSizing: "border-box" }}
          rows={3}
        />
        <select
          value={priority}
          onChange={(e) => setPriority(e.target.value as Priority)}
          style={{ marginRight: 8, padding: 8 }}
        >
          <option>Low</option>
          <option>Medium</option>
          <option>High</option>
          <option>Critical</option>
        </select>
        <button onClick={createIssue} style={{ padding: "8px 16px" }}>
          Create
        </button>
        {error && <p style={{ color: "red", marginTop: 8 }}>{error}</p>}
      </div>

      <h3>Issues ({issues.length})</h3>
      {issues.length === 0 && <p style={{ color: "#9ca3af" }}>No issues yet.</p>}
      {issues.map((issue) => (
        <div
          key={issue.id}
          style={{
            padding: "0.75rem 1rem",
            marginBottom: 8,
            border: "1px solid #e5e7eb",
            borderRadius: 8,
            borderLeft: `4px solid ${statusColor(issue.status)}`,
          }}
        >
          <strong>#{issue.id}</strong> {issue.title}
          <span
            style={{
              marginLeft: 8,
              fontSize: "0.8em",
              color: statusColor(issue.status),
            }}
          >
            {statusLabel(issue.status)}
          </span>
          <div style={{ fontSize: "0.85em", color: "#6b7280", marginTop: 4 }}>
            {issue.priority} priority
            {issue.tags.length > 0 && ` · ${issue.tags.join(", ")}`}
          </div>
        </div>
      ))}
    </div>
  );
}
