#!/bin/bash

# Comprehensive setup script for NWB Plugin Web Build

set -e

echo "🚀 NWB Plugin Web Build Setup"
echo "=============================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if we're on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    print_status "Detected macOS"
    
    # Check if Homebrew is installed
    if ! command -v brew &> /dev/null; then
        print_warning "Homebrew not found. Installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    else
        print_success "Homebrew found"
    fi
    
    # Install CMake if not present
    if ! command -v cmake &> /dev/null; then
        print_status "Installing CMake..."
        brew install cmake
    else
        print_success "CMake found"
    fi
    
    # Install Node.js if not present
    if ! command -v node &> /dev/null; then
        print_status "Installing Node.js..."
        brew install node
    else
        print_success "Node.js found"
    fi

elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    print_status "Detected Linux"
    
    # Check if apt is available
    if command -v apt-get &> /dev/null; then
        print_status "Installing dependencies with apt..."
        sudo apt-get update
        sudo apt-get install -y cmake nodejs npm git curl
    elif command -v yum &> /dev/null; then
        print_status "Installing dependencies with yum..."
        sudo yum install -y cmake nodejs npm git curl
    else
        print_error "Unsupported package manager. Please install cmake, nodejs, and git manually."
        exit 1
    fi
else
    print_warning "Unsupported OS. Please install dependencies manually."
fi

# Check for Emscripten
if ! command -v emcc &> /dev/null; then
    print_status "Emscripten not found. Installing..."
    
    # Clone emsdk if not present
    if [ ! -d "emsdk" ]; then
        git clone https://github.com/emscripten-core/emsdk.git
    fi
    
    cd emsdk
    
    # Install and activate latest Emscripten
    ./emsdk install latest
    ./emsdk activate latest
    
    # Source the environment
    source ./emsdk_env.sh
    
    cd ..
    
    print_success "Emscripten installed and activated"
else
    print_success "Emscripten found"
fi

# Make build scripts executable
print_status "Making build scripts executable..."
chmod +x build.sh
chmod +x build_direct.sh
chmod +x test_node.js

# Create necessary directories
print_status "Creating build directories..."
mkdir -p dist
mkdir -p build

print_success "Setup completed successfully!"
echo ""
echo "Next steps:"
echo "1. Run: ./build.sh (for CMake build)"
echo "   or: ./build_direct.sh (for direct Emscripten build)"
echo "2. Test the build: node test_node.js"
echo "3. Open test.html in a web browser to test in browser"
echo ""
echo "Note: If you're in a new terminal session, you may need to activate Emscripten:"
echo "source emsdk/emsdk_env.sh"

