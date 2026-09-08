namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Net.Http

class HttpClientTimeoutEvaluationState {
    Events: string
    ReceiverCount: int
    ValueCount: int

    constructor() {
        Events = ""
        ReceiverCount = 0
        ValueCount = 0
    }

    func Receiver(client: HttpClient): HttpClient {
        ReceiverCount = ReceiverCount + 1
        Events = Events + "receiver"
        return client
    }

    func Minutes(value: double): double {
        ValueCount = ValueCount + 1
        Events = Events + "|value"
        return value
    }
}

class HttpClientTimeoutEmitFacts {
    static func Assign(client: HttpClient): HttpClient {
        client.Timeout = TimeSpan.FromMinutes(2)
        return client
    }

    static func AssignEvaluated(
        state: HttpClientTimeoutEvaluationState,
        client: HttpClient,
        minutes: double
    ): HttpClient {
        state.Receiver(client).Timeout = TimeSpan.FromMinutes(state.Minutes(minutes))
        return client
    }
}
