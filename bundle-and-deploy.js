// Bundle from src/Main.lua (module-aware) or fallback to single-file copy, then deploy to %LOCALAPPDATA%\lua
import fs from "fs";
import path from "path";

const titleFile = path.join(process.cwd(), "title.txt");
const luaFileName = fs.readFileSync(titleFile, "utf8").trim();
const buildDir = path.join(process.cwd(), "build");
const outputPath = path.join(buildDir, luaFileName);
const deployDir = path.join(process.env.LOCALAPPDATA || "", "lua");
const deployPath = path.join(deployDir, luaFileName);

const srcDir = path.join(process.cwd(), "src");
const mainPath = path.join(srcDir, "Main.lua");
const singleCandidates = ["A_Swing_Prediction.lua", "Swing_prediction.lua"];
const externalModules = new Set(["lnxlib", "immenu"]);

function resolveSingleEntry() {
	for (const name of singleCandidates) {
		const p = path.join(process.cwd(), name);
		if (fs.existsSync(p)) {
			return p;
		}
	}
	return null;
}

function normalizeModulePath(moduleName) {
	return moduleName.replace(/\./g, "/") + ".lua";
}

function resolveModuleFile(moduleName) {
	const moduleFile = path.join(srcDir, normalizeModulePath(moduleName));
	return fs.existsSync(moduleFile) ? moduleFile : null;
}

function transformRequires(content, includeModule) {
	const lines = content.split(/\r?\n/);
	const out = [];
	const requireAssignRe = /^\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*require\((['"])([^'"]+)\2\)\s*;?\s*$/;

	for (const line of lines) {
		const match = line.match(requireAssignRe);
		if (!match) {
			out.push(line);
			continue;
		}

		const [, varName, , moduleName] = match;
		if (externalModules.has(moduleName)) {
			out.push(line);
			continue;
		}

		const moduleFile = resolveModuleFile(moduleName);
		if (!moduleFile) {
			out.push(line);
			continue;
		}

		includeModule(moduleName, moduleFile);
		const indent = line.match(/^\s*/)?.[0] || "";
		out.push(`${indent}local ${varName} = __MODULES[${JSON.stringify(moduleName)}]`);
	}

	return out.join("\n");
}

function buildBundleFromMain(mainFilePath) {
	const moduleCode = new Map();
	const processing = new Set();

	function includeModule(moduleName, moduleFile) {
		if (moduleCode.has(moduleName) || processing.has(moduleName)) {
			return;
		}
		processing.add(moduleName);

		const raw = fs.readFileSync(moduleFile, "utf8");
		const transformed = transformRequires(raw, includeModule);
		const stamped = `-- Module: ${moduleName} (${path.relative(process.cwd(), moduleFile).replace(/\\/g, "/")})\n${transformed}`;
		moduleCode.set(moduleName, stamped);
		processing.delete(moduleName);
	}

	const mainRaw = fs.readFileSync(mainFilePath, "utf8");
	const mainTransformed = transformRequires(mainRaw, includeModule);

	const parts = [];
	parts.push("-- Auto-generated bundle from src/Main.lua");
	parts.push("local __MODULES = {}\n");

	for (const [moduleName, code] of moduleCode) {
		parts.push(`__MODULES[${JSON.stringify(moduleName)}] = (function()\n${code}\nend)()\n`);
	}

	parts.push(`-- Entry: ${path.relative(process.cwd(), mainFilePath).replace(/\\/g, "/")}`);
	parts.push(mainTransformed);
	parts.push("");

	return parts.join("\n");
}

try {
	if (!fs.existsSync(buildDir)) {
		fs.mkdirSync(buildDir, { recursive: true });
	}

	if (fs.existsSync(mainPath)) {
		console.log("Bundling from src/Main.lua...");
		const bundled = buildBundleFromMain(mainPath);
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
