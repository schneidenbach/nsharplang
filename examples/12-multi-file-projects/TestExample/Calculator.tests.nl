namespace TestExample

import "Calculator"

test "should add two positive numbers" {
    result := Calculator.Add(2, 3)
    assert result == 5
    assert result > 0
}

test "should subtract numbers correctly" {
    result := Calculator.Subtract(10, 4)
    assert result == 6
}

test "should multiply numbers" {
    result := Calculator.Multiply(3, 4)
    assert result == 12
}

test "should divide numbers" {
    result := Calculator.Divide(10, 2)
    assert result == 5
}

test "should throw exception when dividing by zero" {
    _, err := Calculator.Divide(10, 0)
    assert err != null
}

test "should handle negative numbers" {
    result := Calculator.Add(-5, 3)
    assert result == -2
    assert result < 0
}
