namespace NSharpLang.Compiler

import System
import System.Collections.Generic

// THE SEAM BETWEEN A LONG-LIVED PROCESS AND THE CACHES THAT LIVE IN IT.
//
// In a one-shot `nlc` process a cache lives for one command. In the workspace server it lives for
// many, and in the language server for a whole editing session — so whatever a cache keeps across
// commands needs three things from the process that hosts it, and this registry is where it gets
// them without any host knowing which caches exist:
//
//   * CHANGES. The host watches the workspace and reports each changed path. A cache validated by
//     content hash may ignore them; one keyed by path or by time can drop the affected entries.
//   * PRESSURE. Before a host retires for memory, or when asked to shed state, it asks every cache to
//     let go of what it can rebuild.
//   * VISIBILITY. `nlc daemon status` reports each cache's own one-line description.
//
// A cache registers once, from its own static initialisation or first use, with three delegates.
// Registering under a name that is already present replaces that entry, so a cache that is
// re-created does not accumulate stale registrations. Nothing here owns or stores cached data.
class WarmStateRegistry {
    private static gate: object = new object()
    private static names: List<string> = new List<string>()
    private static changeHandlers: List<Action<string>> = new List<Action<string>>()
    private static trimHandlers: List<Action> = new List<Action>()
    private static describers: List<Func<string>> = new List<Func<string>>()

    static func Register(name: string, onPathChanged: Action<string>, onTrim: Action, describe: Func<string>) {
        lock WarmStateRegistry.gate {
            index := WarmStateRegistry.names.IndexOf(name)
            if index >= 0 {
                WarmStateRegistry.changeHandlers[index] = onPathChanged
                WarmStateRegistry.trimHandlers[index] = onTrim
                WarmStateRegistry.describers[index] = describe
                return
            }

            WarmStateRegistry.names.Add(name)
            WarmStateRegistry.changeHandlers.Add(onPathChanged)
            WarmStateRegistry.trimHandlers.Add(onTrim)
            WarmStateRegistry.describers.Add(describe)
        }
    }

    static func Count(): int {
        lock WarmStateRegistry.gate {
            return WarmStateRegistry.names.Count
        }
    }

    // A file under the watched workspace was created, changed, deleted or renamed. A cache that throws
    // must not keep the others from hearing about it.
    static func NotifyPathChanged(path: string) {
        handlers: Action<string>[] = new Action<string>[](0)
        lock WarmStateRegistry.gate {
            handlers = WarmStateRegistry.changeHandlers.ToArray()
        }

        for handler in handlers {
            try {
                handler(path)
            } catch handlerFailure: Exception {
                continue
            }
        }
    }

    static func TrimAll() {
        handlers: Action[] = new Action[](0)
        lock WarmStateRegistry.gate {
            handlers = WarmStateRegistry.trimHandlers.ToArray()
        }

        for handler in handlers {
            try {
                handler()
            } catch handlerFailure: Exception {
                continue
            }
        }
    }

    // `name: description` per registered cache, in registration order.
    static func Describe(): string[] {
        lock WarmStateRegistry.gate {
            lines := new string[](WarmStateRegistry.names.Count)
            index := 0
            while index < lines.Length {
                description := ""
                try {
                    description = WarmStateRegistry.describers[index]()
                } catch describeFailure: Exception {
                    description = "unavailable: " + describeFailure.Message
                }

                lines[index] = WarmStateRegistry.names[index] + ": " + description
                index = index + 1
            }

            return lines
        }
    }
}
