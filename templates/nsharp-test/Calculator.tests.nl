test "adds two numbers" {
    result := Calculator.Add(2, 3)
    assert result == 5
}

test "subtracts two numbers" {
    result := Calculator.Subtract(7, 4)
    assert result == 3
}
