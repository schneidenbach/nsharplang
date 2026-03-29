// types.ts — TypeScript discriminated unions that mirror N# unions exactly.
//
// In N# we write:
//   union IssueStatus {
//       Open()
//       InProgress(assigneeId: int)
//       Closed(resolution: string, closedAt: DateTime)
//   }
//
// The N# compiler emits these as a tagged union. On the TypeScript side,
// we model them the same way. This is the interop story: N# unions map
// naturally to TypeScript discriminated unions.

export type IssueStatus =
  | { type: "Open" }
  | { type: "InProgress"; assigneeId: number }
  | { type: "Closed"; resolution: string; closedAt: string };

export type IssueError =
  | { type: "NotFound"; id: number }
  | { type: "InvalidTransition"; from: string; to: string }
  | { type: "ValidationFailed"; field: string; reason: string };

export type Priority = "Low" | "Medium" | "High" | "Critical";

export interface Issue {
  id: number;
  title: string;
  description: string;
  status: IssueStatus;
  priority: Priority;
  createdAt: string;
  tags: string[];
}

// Exhaustive status check — TypeScript's version of N#'s exhaustive match.
// If you add a new IssueStatus variant in N#, this function gets a type error.
export function statusLabel(status: IssueStatus): string {
  switch (status.type) {
    case "Open":
      return "Open";
    case "InProgress":
      return `In Progress (assignee #${status.assigneeId})`;
    case "Closed":
      return `Closed: ${status.resolution}`;
  }
}

export function statusColor(status: IssueStatus): string {
  switch (status.type) {
    case "Open":
      return "#22c55e";
    case "InProgress":
      return "#3b82f6";
    case "Closed":
      return "#6b7280";
  }
}
