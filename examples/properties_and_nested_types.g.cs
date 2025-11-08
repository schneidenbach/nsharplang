using System;

class BankAccount
{
    private double balance { get; set; }

    private string accountNumber { get; set; }

    private int transactionCount { get; set; }

    public enum Status
    {
        Active,
        Frozen,
        Closed
    }

    public class Transaction
    {
        public double Amount { get; set; }

        public DateTime Date { get; set; }

        public string Description { get; set; }

    }

    public double Balance
    {
        get
        {
            return balance;
        }
        set
        {
            if ((value < 0))
            {
                throw new Exception("Balance cannot be negative");
            }
            balance = value;
            (transactionCount++);
        }
    }

    public string AccountNumber
    {
        get
        {
            return accountNumber;
        }
    }

    public int TransactionCount
    {
        get
        {
            return transactionCount;
        }
    }

    public BankAccount.Status CurrentStatus { get; set; }

    public BankAccount(string accountNumber, double initialBalance)
    {
        this.accountNumber = accountNumber;
        balance = initialBalance;
        transactionCount = 0;
        CurrentStatus = BankAccount.Status.Active;
    }

    public void Deposit(double amount)
    {
        if ((CurrentStatus != BankAccount.Status.Active))
        {
            throw new Exception("Account is not active");
        }
        Balance = (Balance + amount);
        Console.WriteLine($"Deposited {amount}. New balance: {Balance}");
    }

    public void Withdraw(double amount)
    {
        if ((CurrentStatus != BankAccount.Status.Active))
        {
            throw new Exception("Account is not active");
        }
        if ((Balance < amount))
        {
            throw new Exception("Insufficient funds");
        }
        Balance = (Balance - amount);
        Console.WriteLine($"Withdrew {amount}. New balance: {Balance}");
    }

    public void Freeze()
    {
        CurrentStatus = BankAccount.Status.Frozen;
        Console.WriteLine("Account frozen");
    }

    public void Close()
    {
        if ((Balance > 0))
        {
            throw new Exception("Cannot close account with positive balance");
        }
        CurrentStatus = BankAccount.Status.Closed;
        Console.WriteLine("Account closed");
    }

}

internal static class _TopLevel
{
    internal static void Main()
    {
        Console.WriteLine("=== Bank Account Example ===");
        var account = new BankAccount("ACC-12345", 1000.0);
        Console.WriteLine($"Account Number: {account.AccountNumber}");
        Console.WriteLine($"Initial Balance: {account.Balance}");
        Console.WriteLine($"Status: {account.CurrentStatus}");
        account.Deposit(500.0);
        account.Withdraw(200.0);
        Console.WriteLine($"Transaction Count: {account.TransactionCount}");
        account.Freeze();
        object? result = null;
        Exception? err = null;
        try
        {
            result = account.Deposit(100.0);
        }
        catch (Exception ex)
        {
            err = ex;
        }
        if ((err != null))
        {
            Console.WriteLine($"Error: {err.Message}");
        }
        Console.WriteLine("\nExample completed successfully!");
    }

}
