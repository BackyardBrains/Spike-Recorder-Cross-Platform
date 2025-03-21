#include "DebuggingLogBYB.h"
// Choose a logging location accessible on macOS
#define LOG_PATH "/tmp/flutter_native_crash.log"

void log_debug(const char* format, ...) {
    static std::ofstream log_file(LOG_PATH, std::ios::app);
    
    // Add timestamp
    time_t now = time(0);
    struct tm* timeinfo = localtime(&now);
    char timestamp[20];
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", timeinfo);
    
    log_file << "[" << timestamp << "] DEBUG: ";
    
    // Format the message
    char buffer[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    
    log_file << buffer << std::endl;
    log_file.flush();
}