// ProductService.nl — Uses Product and Category without file imports.
// Types are auto-discovered from the project.

namespace AutoDiscovery.Services

import System.Collections.Generic

class ProductService {
    readonly products: List<Product>

    constructor() {
        products = new List<Product>()
    }

    func AddProduct(product: Product) {
        products.Add(product)
        print $"Added: {product.Display()}"
    }

    func GetProducts(): List<Product> {
        return products
    }

    Count: int => products.Count
}
