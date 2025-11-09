import System.Threading.Tasks

package EmployeeApi

// Simple async test to demonstrate async test method generation
test "async test methods are generated correctly" {
    // Simulate async work
    await Task.Delay(1)

    result := 1 + 1
    assert result == 2
}

// Non-async test for comparison
test "sync test methods still work" {
    result := 2 + 2
    assert result == 4
}
