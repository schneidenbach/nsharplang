// Example demonstrating properties with custom get/set and nested types
import System

class BankAccount {

    // Private backing fields
    balance: double
    accountNumber: string
    transactionCount: int

    // Nested enum for account status
    enum Status {
        Active,
        Frozen,
        Closed
    }

    // Nested class for transaction records
    class Transaction {
        Amount: double
        Date: DateTime
        Description: string
    }

    // Property with custom get/set
    Balance: double {
        get {
            return balance
        }
        set {
            if value < 0 {
                throw new Exception("Balance cannot be negative")
            }

            balance = value
            transactionCount++
        }
    }

    // Read-only property
    AccountNumber: string {
        get {
            return accountNumber
        }
    }

    // Property with validation
    TransactionCount: int {
        get {
            return transactionCount
        }
    }

    // Account status field using nested enum
    CurrentStatus: BankAccount.Status

    constructor(accountNumber: string, initialBalance: double) {
        this.accountNumber = accountNumber
        balance = initialBalance
        transactionCount = 0
        CurrentStatus = BankAccount.Status.Active
    }

    func Deposit(amount: double) {
        if CurrentStatus != BankAccount.Status.Active {
            throw new Exception("Account is not active")
        }

        Balance = Balance + amount
        print $"Deposited {amount}. New balance: {Balance}"
    }

    func Withdraw(amount: double) {
        if CurrentStatus != BankAccount.Status.Active {
            throw new Exception("Account is not active")
        }

        if Balance < amount {
            throw new Exception("Insufficient funds")
        }

        Balance = Balance - amount
        print $"Withdrew {amount}. New balance: {Balance}"
    }

    func Freeze() {
        CurrentStatus = BankAccount.Status.Frozen
        print "Account frozen"
    }

    func Close() {
        if Balance > 0 {
            throw new Exception("Cannot close account with positive balance")
        }

        CurrentStatus = BankAccount.Status.Closed
        print "Account closed"
    }
}

// Example usage
func Main() {
    print "=== Bank Account Example ==="

    account := new BankAccount("ACC-12345", 1000.0)

    print $"Account Number: {account.AccountNumber}"
    print $"Initial Balance: {account.Balance}"
    print $"Status: {account.CurrentStatus}"

    account.Deposit(500.0)
    account.Withdraw(200.0)

    print $"Transaction Count: {account.TransactionCount}"

    account.Freeze()

    // This will throw an exception because account is frozen
    _, err := account.Deposit(100.0)
    if err != null {
        print $"Error: {err.Message}"
    }

    print "\nExample completed successfully!"
}
