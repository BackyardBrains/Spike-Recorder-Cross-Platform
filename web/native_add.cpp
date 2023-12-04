
#include <emscripten/bind.h>
using namespace emscripten;

#include <iostream>

extern "C" {
    int add(int a, int b) {
        return a + b;
    }
}

EMSCRIPTEN_BINDINGS(my_module) {
    function("add", &add);
}