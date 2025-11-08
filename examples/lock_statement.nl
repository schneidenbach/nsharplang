using System
using System.Threading
using System.Threading.Tasks

// Thread-safe counter using lock statement
class Counter {
    _value: int = 0
    _lock: object = new object()

    func Increment() {
        lock _lock {
            _value++
        }
    }

    func Decrement() {
        lock (_lock) {  // parentheses optional
            _value--
        }
    }

    func GetValue(): int {
        lock _lock {
            return _value
        }
    }

    func Reset() {
        lock _lock {
            _value = 0
        }
    }
}

// Bank account with thread-safe operations
class BankAccount {
    balance: double = 0.0
    _transactionLock: object = new object()
    TransactionCount: int = 0

    func Deposit(amount: double) {
        if amount < 0 {
            throw new ArgumentException("Amount cannot be negative")
        }

        lock _transactionLock {
            balance = balance + amount
            TransactionCount++
            print $"Deposited ${amount:F2}. New balance: ${balance:F2}"
        }
    }

    func Withdraw(amount: double): bool {
        if amount < 0 {
            throw new ArgumentException("Amount cannot be negative")
        }

        lock _transactionLock {
            if balance >= amount {
                balance = balance - amount
                TransactionCount++
                print $"Withdrew ${amount:F2}. New balance: ${balance:F2}"
                return true
            }
            return false
        }
    }

    func GetBalance(): double {
        lock _transactionLock {
            return balance
        }
    }
}

func Main() {
    print "Lock Statement Demo"
    print "==================="
    print ""

    // Counter demo
    print "Thread-safe Counter:"
    counter := new Counter()

    // Simulate concurrent increments
    tasks := [
        Task.Run(() => {
            for i := 0; i < 1000; i++ {
                counter.Increment()
            }
        }),
        Task.Run(() => {
            for i := 0; i < 1000; i++ {
                counter.Increment()
            }
        }),
        Task.Run(() => {
            for i := 0; i < 500; i++ {
                counter.Decrement()
            }
        })
    ]

    Task.WaitAll(tasks)
    print $"Final counter value: {counter.GetValue()}"
    print $"Expected: {1000 + 1000 - 500}"
    print ""

    // Bank account demo
    print "Thread-safe Bank Account:"
    account := new BankAccount()

    account.Deposit(1000.0)
    account.Deposit(500.0)

    success := account.Withdraw(750.0)
    print $"Withdrawal successful: {success}"

    success = account.Withdraw(1000.0)
    print $"Withdrawal successful: {success}"

    print $"Final balance: ${account.GetBalance():F2}"
    print $"Total transactions: {account.TransactionCount}"
}
