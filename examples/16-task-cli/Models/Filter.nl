namespace TaskCli.Models

// Search and filter criteria for listing tasks
record Filter {
    Query: string
    StatusName: string
    PriorityName: string
    Tag: string

    func HasQuery(): bool {
        return Query.Length > 0
    }

    func HasStatus(): bool {
        return StatusName.Length > 0
    }

    func HasPriority(): bool {
        return PriorityName.Length > 0
    }

    func HasTag(): bool {
        return Tag.Length > 0
    }
}
