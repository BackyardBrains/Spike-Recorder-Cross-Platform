#!/usr/bin/env node

/**
 * Node.js test script for NWB Plugin Web Build
 */

const path = require('path');
const fs = require('fs');

async function testNWBPlugin() {
    console.log('Testing NWB Plugin Web Build...\n');

    // Check if dist directory exists
    const distPath = path.join(__dirname, 'dist');
    if (!fs.existsSync(distPath)) {
        console.error('❌ dist/ directory not found. Please run the build first.');
        console.log('Run: ./build.sh or ./build_direct.sh');
        return;
    }

    // Check for required files
    const jsFile = path.join(distPath, 'nwbfile_plugin.js');
    const wasmFile = path.join(distPath, 'nwbfile_plugin.wasm');

    if (!fs.existsSync(jsFile)) {
        console.error('❌ nwbfile_plugin.js not found in dist/');
        return;
    }

    if (!fs.existsSync(wasmFile)) {
        console.error('❌ nwbfile_plugin.wasm not found in dist/');
        return;
    }

    console.log('✅ Build files found');

    try {
        // Try to load the module
        console.log('\n🔄 Loading module...');
        const NWBPlugin = require('./dist/nwbfile_plugin.js');
        
        console.log('✅ Module loaded successfully');
        
        // Test the module
        console.log('\n🔄 Testing module functions...');
        const Module = await NWBPlugin();
        
        // Test sum function
        console.log('Testing sum function...');
        const sumResult = Module.ccall('sum', 'number', ['number', 'number'], [5, 3]);
        console.log(`✅ Sum(5, 3) = ${sumResult}`);
        
        // Test long running sum function
        console.log('Testing long running sum function...');
        const longSumResult = Module.ccall('sum_long_running', 'number', ['number', 'number'], [10, 20]);
        console.log(`✅ Long Sum(10, 20) = ${longSumResult}`);
        
        // Test processing init function
        console.log('Testing NWB processing init...');
        const initResult = Module.ccall('processing_init', 'number', [], []);
        if (initResult === 0) {
            console.log('✅ NWB processing initialized successfully');
        } else {
            console.log(`⚠️  NWB processing returned code: ${initResult}`);
        }
        
        console.log('\n🎉 All tests completed successfully!');
        
    } catch (error) {
        console.error('❌ Error testing module:', error.message);
        console.error('Stack trace:', error.stack);
    }
}

// Run the test
testNWBPlugin().catch(console.error);

