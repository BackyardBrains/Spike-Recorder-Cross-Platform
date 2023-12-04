// This file is required because when compiling using emcc command we need "-pthread -s PROXY_TO_PTHREAD" to enable SharedArrayBuffer in WASM.
// and for threading WASM compiler needs main function as entry point.

#include <emscripten/val.h>
#include <emscripten/bind.h>
#include <emscripten.h>
using namespace emscripten;

#ifndef MAIN_ENTRY_FILE
#define MAIN_ENTRY_FILE

#ifdef __cplusplus
#define EXTERNC extern "C"
#else
#define EXTERNC
#endif

#if defined(__GNUC__)
#define FUNCTION_ATTRIBUTE __attribute__((visibility("default"))) __attribute__((used))
#elif defined(_MSC_VER)
#define FUNCTION_ATTRIBUTE __declspec(dllexport)
#endif

EXTERNC int main()
{
    return 0;
}

#endif