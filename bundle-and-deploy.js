// Bundle (multi-file from src/Main.lua or single root file) and deploy to %LOCALAPPDATA%\lua
import fs from "fs";
import path from "path";

const titleFile = path.join(process.cwd(), "title.txt");
const luaFileName = fs.readFileSync(titleFile, "utf8").trim();
const buildDir = path.join(process.cwd(), "build");
const outputPath = path.join(buildDir, luaFileName);
const deployDir = path.join(process.env.LOCALAPPDATA || "", "lua");
const deployPath = path.join(deployDir, luaFileName);

const mainPath = path.join(process.cwd(), "src", "Main.lua");
const singleCandidates = ["A_Swing_Prediction.lua", "Swing_prediction.lua"];

function processFile(filePath, processedFiles = new Set()) {
	if (processedFiles.has(filePath)) {
		return "";
	}
	processedFiles.add(filePath);

	const content = fs.readFileSync(filePath, "utf8");
	let result = `-- File: ${path.relative(process.cwd(), filePath)}\n`;

	const lines = content.split("\n");
	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		const requireMatch = line.match(/local\s+(\w+)\s*=\s*require\("([^"]+)"\)/);

		if (requireMatch) {
			const [, varName, moduleName] = requireMatch;

			if (moduleName === "lnxlib" || moduleName === "immenu") {
				result += line + "\n";
			} else {
				const modulePath = path.join(process.cwd(), "src", moduleName + ".lua");
				if (fs.existsSync(modulePath)) {
					result += `-- Including module: ${moduleName}\n`;
					result += processFile(modulePath, processedFiles);
					result += `local ${varName} = ${moduleName}\n`;
				} else {
					result += line + "\n";
				}
			}
		} else {
			result += line + "\n";
		}
	}

	return result + "\n";
}

function resolveSingleEntry() {
	for (const name of singleCandidates) {
		const p = path.join(process.cwd(), name);
		if (fs.existsSync(p)) {
			return p;
		}
	}
	return null;
}

try {
	if (!fs.existsSync(buildDir)) {
		fs.mkdirSync(buildDir, { recursive: true });
	}

	if (fs.existsSync(mainPath)) {
		console.log("Bundling from src/Main.lua...");
		const bundled = processFile(mainPath);
		fs.writeFileSync(outputPath, bundled);
	} else {
		const entry = resolveSingleEntry();
		if (!entry) {
			console.error(
				"bundle-and-deploy: No src/Main.lua and no single file (" +
					singleCandidates.join(", ") +
					") found."
			);
			process.exit(1);
		}
		console.log("Copying single file:", path.basename(entry));
		fs.copyFileSync(entry, outputPath);
	}

	console.log("Build:", outputPath);

	if (!fs.existsSync(deployDir)) {
		fs.mkdirSync(deployDir, { recursive: true });
	}
	fs.copyFileSync(outputPath, deployPath);
	console.log("Deployed:", deployPath);
	process.exit(0);
} catch (err) {
	console.error("bundle-and-deploy failed:", err.message);
	if (err.stack) {
		console.error(err.stack);
	}
	process.exit(1);
}
