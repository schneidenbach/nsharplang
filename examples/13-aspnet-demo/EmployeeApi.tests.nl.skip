import System
import System.Net
import System.Net.Http
import System.Text
import System.Text.Json
import System.Threading.Tasks
import Microsoft.AspNetCore.Mvc.Testing
import Microsoft.EntityFrameworkCore
import Microsoft.Extensions.DependencyInjection
import Microsoft.AspNetCore.Hosting
import System.Linq

package EmployeeApi

// ============================================================================
// Helper function to create test client with in-memory database
// ============================================================================

func CreateTestClient(): HttpClient {
    factory := new WebApplicationFactory<Program>()
        .WithWebHostBuilder(builder => {
            // Suppress static web assets to avoid content root issues
            builder.UseSetting("WebHostDefaults:StaticWebAssetsKey", "")
            builder.UseEnvironment("Testing")  // Use "Testing" environment to signal tests

            builder.ConfigureServices(services => {
                // Remove all existing DbContext-related registrations to avoid conflicts
                appDbContextDescriptor := services.SingleOrDefault(d => d.ServiceType == typeof(AppDbContext))
                if appDbContextDescriptor != null {
                    services.Remove(appDbContextDescriptor)
                }

                dbContextOptionsDescriptor := services.SingleOrDefault(d => d.ServiceType == typeof(DbContextOptions<AppDbContext>))
                if dbContextOptionsDescriptor != null {
                    services.Remove(dbContextOptionsDescriptor)
                }

                // Add unique in-memory database for each test
                dbName := $"TestDb_{Guid.NewGuid()}"
                services.AddDbContext<AppDbContext>(options => {
                    options.UseInMemoryDatabase(dbName)
                })
            })

            builder.UseSetting("Logging:LogLevel:Default", "Warning")
        })

    options := new WebApplicationFactoryClientOptions {
        BaseAddress: new Uri("http://localhost")
    }

    return factory.CreateClient(options)
}

// ============================================================================
// GET /api/employees - Get All Employees
// ============================================================================

test "GET /api/employees returns empty list initially" {
    client := CreateTestClient()

    response := await client.GetAsync("/api/employees")

    assert response.IsSuccessStatusCode

    content := await response.Content.ReadAsStringAsync()
    employees := JsonSerializer.Deserialize<EmployeeEntity[]>(content, new JsonSerializerOptions { PropertyNameCaseInsensitive: true })

    assert employees != null
    assert employees.Length == 0
}

test "GET /api/employees returns all employees" {
    client := CreateTestClient()

    // Create two employees first
    employee1 := new {
        firstName:"John",
        lastName:"Doe",
        email:"john@example.com",
        department:Department.Engineering,
        status: EmploymentStatus.Active,
        hireDate: DateTime.UtcNow,
        salary: 75000
    }

    employee2 := new {
        firstName:"Jane",
        lastName:"Smith",
        email:"jane@example.com",
        department:Department.Sales,
        status: EmploymentStatus.Active,
        hireDate: DateTime.UtcNow,
        salary: 80000
    }

    json1 := JsonSerializer.Serialize(employee1)
    json2 := JsonSerializer.Serialize(employee2)

    await client.PostAsync("/api/employees", new StringContent(json1, Encoding.UTF8, "application/json"))
    await client.PostAsync("/api/employees", new StringContent(json2, Encoding.UTF8, "application/json"))

    // Get all employees
    response := await client.GetAsync("/api/employees")

    assert response.IsSuccessStatusCode

    content := await response.Content.ReadAsStringAsync()
    employees := JsonSerializer.Deserialize<EmployeeEntity[]>(content, new JsonSerializerOptions { PropertyNameCaseInsensitive: true })

    assert employees != null
    assert employees.Length == 2
}

// ============================================================================
// POST /api/employees - Create Employee
// ============================================================================

test "POST /api/employees creates new employee successfully" {
    client := CreateTestClient()

    employeeDto := new {
        firstName:"John",
        lastName:"Doe",
        email:"john.doe@example.com",
        department:Department.Engineering,
        status: EmploymentStatus.Active,
        hireDate: DateTime.UtcNow,
        salary: 75000
    }

    json := JsonSerializer.Serialize(employeeDto)
    content := new StringContent(json, Encoding.UTF8, "application/json")

    response := await client.PostAsync("/api/employees", content)

    assert response.IsSuccessStatusCode
    assert response.StatusCode == HttpStatusCode.Created

    responseBody := await response.Content.ReadAsStringAsync()
    createdEmployee := JsonSerializer.Deserialize<EmployeeEntity>(responseBody, new JsonSerializerOptions { PropertyNameCaseInsensitive: true })

    assert createdEmployee != null
    assert createdEmployee.FirstName == "John"
    assert createdEmployee.LastName == "Doe"
    assert createdEmployee.Email == "john.doe@example.com"
    assert createdEmployee.Department == Department.Engineering
    assert createdEmployee.Id != Guid.Empty
}

test "POST /api/employees returns 400 for invalid data" {
    client := CreateTestClient()

    // Missing required fields
    invalidDto := new {
        firstName:"",
        lastName:"",
        email:""
    }

    json := JsonSerializer.Serialize(invalidDto)
    content := new StringContent(json, Encoding.UTF8, "application/json")

    response := await client.PostAsync("/api/employees", content)

    assert response.StatusCode == HttpStatusCode.BadRequest
}

// ============================================================================
// GET /api/employees/{id} - Get Employee by ID
// ============================================================================

test "GET /api/employees/{id} returns employee by ID" {
    client := CreateTestClient()

    // Create an employee first
    employeeDto := new {
        firstName:"Jane",
        lastName:"Smith",
        email:"jane@example.com",
        department:Department.Sales,
        status: EmploymentStatus.Active,
        hireDate: DateTime.UtcNow,
        salary: 80000
    }

    json := JsonSerializer.Serialize(employeeDto)
    createResponse := await client.PostAsync("/api/employees", new StringContent(json, Encoding.UTF8, "application/json"))

    createBody := await createResponse.Content.ReadAsStringAsync()
    created := JsonSerializer.Deserialize<EmployeeEntity>(createBody, new JsonSerializerOptions { PropertyNameCaseInsensitive: true })

    // Get by ID
    response := await client.GetAsync($"/api/employees/{created.Id}")

    assert response.IsSuccessStatusCode

    content := await response.Content.ReadAsStringAsync()
    employee := JsonSerializer.Deserialize<EmployeeEntity>(content, new JsonSerializerOptions { PropertyNameCaseInsensitive: true })

    assert employee != null
    assert employee.Id == created.Id
    assert employee.FirstName == "Jane"
    assert employee.LastName == "Smith"
}

test "GET /api/employees/{id} returns 404 for non-existent ID" {
    client := CreateTestClient()

    nonExistentId := Guid.NewGuid()
    response := await client.GetAsync($"/api/employees/{nonExistentId}")

    assert response.StatusCode == HttpStatusCode.NotFound
}

// ============================================================================
// PUT /api/employees/{id} - Update Employee
// ============================================================================

test "PUT /api/employees/{id} updates employee successfully" {
    client := CreateTestClient()

    // Create an employee
    createDto := new {
        firstName:"Bob",
        lastName:"Johnson",
        email:"bob@example.com",
        department:Department.Engineering,
        status: EmploymentStatus.Active,
        hireDate: DateTime.UtcNow,
        salary: 70000
    }

    json := JsonSerializer.Serialize(createDto)
    createResponse := await client.PostAsync("/api/employees", new StringContent(json, Encoding.UTF8, "application/json"))
    createBody := await createResponse.Content.ReadAsStringAsync()
    created := JsonSerializer.Deserialize<EmployeeEntity>(createBody, new JsonSerializerOptions { PropertyNameCaseInsensitive: true })

    // Update the employee
    updateDto := new {
        firstName:"Robert",
        salary: 85000
    }

    updateJson := JsonSerializer.Serialize(updateDto)
    updateResponse := await client.PutAsync($"/api/employees/{created.Id}", new StringContent(updateJson, Encoding.UTF8, "application/json"))

    assert updateResponse.IsSuccessStatusCode

    updateBody := await updateResponse.Content.ReadAsStringAsync()
    updated := JsonSerializer.Deserialize<EmployeeEntity>(updateBody, new JsonSerializerOptions { PropertyNameCaseInsensitive: true })

    assert updated != null
    assert updated.FirstName == "Robert"
    assert updated.Salary == 85000
    assert updated.LastName == "Johnson"  // Should be unchanged
}

test "PUT /api/employees/{id} returns 404 for non-existent ID" {
    client := CreateTestClient()

    updateDto := new {
        firstName:"Test"
    }

    json := JsonSerializer.Serialize(updateDto)
    nonExistentId := Guid.NewGuid()
    response := await client.PutAsync($"/api/employees/{nonExistentId}", new StringContent(json, Encoding.UTF8, "application/json"))

    assert response.StatusCode == HttpStatusCode.NotFound
}

// ============================================================================
// DELETE /api/employees/{id} - Delete Employee
// ============================================================================

test "DELETE /api/employees/{id} deletes employee successfully" {
    client := CreateTestClient()

    // Create an employee
    employeeDto := new {
        firstName:"Alice",
        lastName:"Williams",
        email:"alice@example.com",
        department:Department.HR,
        status: EmploymentStatus.Active,
        hireDate: DateTime.UtcNow,
        salary: 65000
    }

    json := JsonSerializer.Serialize(employeeDto)
    createResponse := await client.PostAsync("/api/employees", new StringContent(json, Encoding.UTF8, "application/json"))
    createBody := await createResponse.Content.ReadAsStringAsync()
    created := JsonSerializer.Deserialize<EmployeeEntity>(createBody, new JsonSerializerOptions { PropertyNameCaseInsensitive: true })

    // Delete the employee
    deleteResponse := await client.DeleteAsync($"/api/employees/{created.Id}")

    assert deleteResponse.StatusCode == HttpStatusCode.NoContent

    // Verify it's deleted
    getResponse := await client.GetAsync($"/api/employees/{created.Id}")
    assert getResponse.StatusCode == HttpStatusCode.NotFound
}

test "DELETE /api/employees/{id} returns 404 for non-existent ID" {
    client := CreateTestClient()

    nonExistentId := Guid.NewGuid()
    response := await client.DeleteAsync($"/api/employees/{nonExistentId}")

    assert response.StatusCode == HttpStatusCode.NotFound
}

// ============================================================================
// GET /api/employees/status/{status} - Get by Status
// ============================================================================

test "GET /api/employees/status/{status} returns employees by status" {
    client := CreateTestClient()

    // Create employees with different statuses
    activeEmployee := new {
        firstName:"Active",
        lastName:"Employee",
        email:"active@example.com",
        department:Department.Engineering,
        status: EmploymentStatus.Active,
        hireDate: DateTime.UtcNow,
        salary: 70000
    }

    onLeaveEmployee := new {
        firstName:"OnLeave",
        lastName:"Employee",
        email:"onleave@example.com",
        department:Department.Sales,
        status: EmploymentStatus.OnLeave,
        hireDate: DateTime.UtcNow,
        salary: 75000
    }

    await client.PostAsync("/api/employees", new StringContent(JsonSerializer.Serialize(activeEmployee), Encoding.UTF8, "application/json"))
    await client.PostAsync("/api/employees", new StringContent(JsonSerializer.Serialize(onLeaveEmployee), Encoding.UTF8, "application/json"))

    // Get employees with "active" status
    response := await client.GetAsync($"/api/employees/status/{EmploymentStatus.Active}")

    assert response.IsSuccessStatusCode

    content := await response.Content.ReadAsStringAsync()
    employees := JsonSerializer.Deserialize<EmployeeEntity[]>(content, new JsonSerializerOptions { PropertyNameCaseInsensitive: true })

    assert employees != null
    assert employees.Length == 1
    assert employees[0].Status == EmploymentStatus.Active
}

// ============================================================================
// GET /api/employees/department/{department} - Get by Department
// ============================================================================

test "GET /api/employees/department/{department} returns employees by department" {
    client := CreateTestClient()

    // Create employees in different departments
    engEmployee := new {
        firstName:"Eng",
        lastName:"Employee",
        email:"eng@example.com",
        department:Department.Engineering,
        status: EmploymentStatus.Active,
        hireDate: DateTime.UtcNow,
        salary: 70000
    }

    salesEmployee := new {
        firstName:"Sales",
        lastName:"Employee",
        email:"sales@example.com",
        department:Department.Sales,
        status: EmploymentStatus.Active,
        hireDate: DateTime.UtcNow,
        salary: 75000
    }

    await client.PostAsync("/api/employees", new StringContent(JsonSerializer.Serialize(engEmployee), Encoding.UTF8, "application/json"))
    await client.PostAsync("/api/employees", new StringContent(JsonSerializer.Serialize(salesEmployee), Encoding.UTF8, "application/json"))

    // Get employees in Engineering department
    response := await client.GetAsync($"/api/employees/department/{Department.Engineering}")

    assert response.IsSuccessStatusCode

    content := await response.Content.ReadAsStringAsync()
    employees := JsonSerializer.Deserialize<EmployeeEntity[]>(content, new JsonSerializerOptions { PropertyNameCaseInsensitive: true })

    assert employees != null
    assert employees.Length == 1
    assert employees[0].Department == Department.Engineering
}
