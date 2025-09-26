#include <iostream>
#include <string>
#include <vector>
#include <memory>

extern "C" {
    int test_cpp_simple() {
        std::string test = "C++ compilation test";
        std::vector<int> numbers = {1, 2, 3, 4, 5};
        auto ptr = std::make_unique<int>(42);
        
        std::cout << test << std::endl;
        std::cout << "Vector size: " << numbers.size() << std::endl;
        std::cout << "Unique ptr value: " << *ptr << std::endl;
        
        return 0;
    }
}


