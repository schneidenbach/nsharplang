namespace NSharpLang.ReflectionEmitBootstrap.Tests

import System
import System.Net.Http

func HttpClientTimeoutRequiredText(client: HttpClient): string {
    property := typeof(HttpClient).GetProperty(nameof(HttpClient.Timeout))
    if property == null {
        throw new InvalidOperationException("HttpClient.Timeout was not found.")
    }
    value := property.GetValue(client)
    if value == null {
        throw new InvalidOperationException("HttpClient.Timeout returned null.")
    }
    return value.ToString() ?? ""
}

func HttpClientTimeoutAssignmentFailure(
    state: HttpClientTimeoutEvaluationState,
    client: HttpClient
): Exception? {
    try {
        _assigned := HttpClientTimeoutEmitFacts.AssignEvaluated(state, client, -2)
    } catch error: Exception {
        return error
    }
    return null
}

test "HttpClient Timeout assignment preserves receiver identity and receiver-before-value evaluation" {
    client := new HttpClient()
    try {
        assigned := HttpClientTimeoutEmitFacts.Assign(client)
        assert Object.ReferenceEquals(assigned, client)
        assert HttpClientTimeoutRequiredText(client) == "00:02:00"

        state := new HttpClientTimeoutEvaluationState()
        evaluated := HttpClientTimeoutEmitFacts.AssignEvaluated(state, client, 3)
        assert Object.ReferenceEquals(evaluated, client)
        assert state.Events == "receiver|value"
        assert state.ReceiverCount == 1
        assert state.ValueCount == 1
        assert HttpClientTimeoutRequiredText(client) == "00:03:00"
    } finally {
        client.Dispose()
    }
}

test "HttpClient Timeout assignment preserves the CLR failure and prior value" {
    client := new HttpClient()
    try {
        client.Timeout = TimeSpan.FromMinutes(4)
        state := new HttpClientTimeoutEvaluationState()
        failure := HttpClientTimeoutAssignmentFailure(state, client)
        if failure == null {
            throw new InvalidOperationException("The invalid HttpClient.Timeout assignment succeeded.")
        }
        captured: Exception = failure
        rangeFailure := captured as ArgumentOutOfRangeException
        assert rangeFailure != null
        assert state.Events == "receiver|value"
        assert state.ReceiverCount == 1
        assert state.ValueCount == 1
        assert HttpClientTimeoutRequiredText(client) == "00:04:00"
    } finally {
        client.Dispose()
    }
}
