// Program.nl — No file imports needed!
// Product, Category, and ProductService are auto-discovered from the project.

namespace AutoDiscovery

func Main() {
    print "=== Auto-Discovery Demo ==="
    print "No file imports needed - types found automatically!"
    print ""

    service := new ProductService()

    service.AddProduct(new Product { Id: 1, Name: "Laptop", Price: 999 })
    service.AddProduct(new Product { Id: 2, Name: "Book", Price: 29 })

    print ""
    print $"Total products: {service.Count}"

    products := service.GetProducts()
    for product in products {
        print $"  - {product.Display()}"
    }

    print ""
    electronics := Category.Electronics
    print $"Category: {electronics}"
    print "Demo complete!"
}
