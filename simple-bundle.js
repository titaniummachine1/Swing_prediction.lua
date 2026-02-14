// Simple Lua bundler that works on any machine
import fs from 'fs';
import path from 'path';

// Read the lua file name from title.txt
const titleFile = path.join(process.cwd(), 'title.txt');
const luaFileName = fs.readFileSync(titleFile, 'utf8').trim();

// Function to read a file and resolve its requires
function processFile(filePath, processedFiles = new Set()) {
    if (processedFiles.has(filePath)) {
        return '';
    }
    processedFiles.add(filePath);
    
    const content = fs.readFileSync(filePath, 'utf8');
    let result = `-- File: ${path.relative(process.cwd(), filePath)}\n`;
    
    // Process each line
    const lines = content.split('\n');
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const requireMatch = line.match(/local\s+(\w+)\s*=\s*require\("([^"]+)"\)/);
        
        if (requireMatch) {
            const [, varName, moduleName] = requireMatch;
            
            // Skip external libraries (lnxlib, immenu)
            if (moduleName === 'lnxlib' || moduleName === 'immenu') {
                result += line + '\n';
            } else {
                // Include local module
                const modulePath = path.join(process.cwd(), 'src', moduleName + '.lua');
                if (fs.existsSync(modulePath)) {
                    result += `-- Including module: ${moduleName}\n`;
                    result += processFile(modulePath, processedFiles);
                    result += `local ${varName} = ${moduleName}\n`;
                } else {
                    result += line + '\n';
                }
            }
        } else {
            result += line + '\n';
        }
    }
    
    return result + '\n';
}

try {
    console.log('Starting simple Lua bundle process...');
    console.log('Using lua file name:', luaFileName);
    
    // Process main file
    const mainPath = path.join(process.cwd(), 'src', 'Main.lua');
    const bundledContent = processFile(mainPath);
    
    // Create build directory if it doesn't exist
    const buildDir = path.join(process.cwd(), 'build');
    if (!fs.existsSync(buildDir)) {
        fs.mkdirSync(buildDir);
    }
    
    // Write bundled file
    const outputPath = path.join(buildDir, luaFileName);
    fs.writeFileSync(outputPath, bundledContent);
    
    console.log('Bundle created at:', outputPath);
    console.log('Bundle completed successfully!');
    process.exit(0);
    
} catch (error) {
    console.error('Bundle failed:', error.message);
    console.error('Stack:', error.stack);
    process.exit(1);
}
