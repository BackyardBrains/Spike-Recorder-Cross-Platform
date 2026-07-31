const fs = require('fs');
const path = require('path');

// Load the compiled module
const NWBPlugin = require('./dist/nwbfile_plugin.js');

async function testNWBFileData() {
    console.log('🧪 Testing NWB File Data Access...\n');
    
    try {
        // Initialize the module
        const Module = await NWBPlugin();
        console.log('✅ Module loaded successfully');
        
        // Test basic functions first
        console.log('\n📊 Testing basic functions...');
        const sumResult = Module.ccall('sum', 'number', ['number', 'number'], [5, 3]);
        console.log(`Sum(5, 3) = ${sumResult}`);
        
        // Run NWB processing to generate file data
        console.log('\n🔧 Running NWB processing...');
        const initResult = Module.ccall('processing_init', 'number', [], []);
        console.log(`NWB processing result: ${initResult}`);
        
        if (initResult === 0) {
            console.log('✅ NWB processing completed successfully');
            
            // Test getting file size
            console.log('\n📏 Getting NWB file size...');
            const fileSize = Module.ccall('get_nwb_file_size', 'number', [], []);
            console.log(`File size: ${fileSize} bytes`);
            
            if (fileSize > 0) {
                // Test getting file data
                console.log('\n📄 Getting NWB file data...');
                
                // Allocate memory using Emscripten's malloc
                const bufferPtr = Module.ccall('malloc', 'number', ['number'], [fileSize]);
                const bytesRead = Module.ccall('get_nwb_file_data', 'number', ['number', 'number'], [bufferPtr, fileSize]);
                
                if (bytesRead > 0) {
                    // Convert buffer to string
                    const fileData = Module.UTF8ToString(bufferPtr, bytesRead);
                    console.log(`✅ Successfully retrieved ${bytesRead} bytes of file data`);
                    console.log('\n📋 File content:');
                    console.log('=' .repeat(50));
                    console.log(fileData);
                    console.log('=' .repeat(50));
                    
                    // Create a downloadable file
                    const outputPath = path.join(__dirname, 'generated_example_recording.nwb');
                    fs.writeFileSync(outputPath, fileData);
                    console.log(`\n💾 File saved to: ${outputPath}`);
                } else {
                    console.log(`❌ Failed to read file data. Error code: ${bytesRead}`);
                }
                
                // Free memory
                Module.ccall('free', null, ['number'], [bufferPtr]);
                
            } else if (fileSize === -1) {
                console.log('❌ File data is not ready. Please run NWB processing first.');
            } else {
                console.log(`❌ Failed to get file size. Error code: ${fileSize}`);
            }
            
        } else {
            console.log(`❌ NWB processing failed with code: ${initResult}`);
        }
        
    } catch (error) {
        console.error('❌ Error:', error.message);
    }
}

// Run the test
testNWBFileData();
