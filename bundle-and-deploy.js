// Bundle from src/Main.lua (module-aware) or fallback to single-file copy, then deploy to %LOCALAPPDATA%\lua
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const titleFile = path.join(__dirname, "title.txt");
const rawTitle = fs.readFileSync(titleFile, "utf8");
const luaFileName = rawTitle.replace(/\uFEFF/g, "").trim();

const buildDir = path.join(__dirname, "build");
const outputPath = path.join(buildDir, luaFileName);
const deployDir = path.join(process.env.LOCALAPPDATA || "", "lua");
const deployPath = path.join(deployDir, luaFileName);

const srcDir = path.join(__dirname, "src");
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

function stripBOM(str) {
	// Global BOM removal (\uFEFF)
	return typeof str === "string" ? str.replace(/\uFEFF/g, "") : str;
}

function buildBundleFromMain(mainFilePath) {
	const moduleCode = new Map();
	const processing = new Set();

	function includeModule(moduleName, moduleFile) {
		if (moduleCode.has(moduleName) || processing.has(moduleName)) {
			return;
		}
		processing.add(moduleName);

		let raw = fs.readFileSync(moduleFile, "utf8");
		raw = stripBOM(raw);
		const transformed = transformRequires(raw, includeModule);
		const stamped = `-- Module: ${moduleName} (${path.relative(process.cwd(), moduleFile).replace(/\\/g, "/")})\n${transformed}`;
		moduleCode.set(moduleName, stamped);
		processing.delete(moduleName);
	}

	let mainRaw = fs.readFileSync(mainFilePath, "utf8");
	mainRaw = stripBOM(mainRaw);
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

	const fullBundle = parts.join("\n");
	const sanitized = stripBOM(fullBundle);

	// Check for any remaining non-ASCII characters
	const nonAsciiMatch = sanitized.match(/[^\x00-\x7F]/);
	if (nonAsciiMatch) {
		console.warn("WARNING: Bundle still contains non-ASCII characters at index " + nonAsciiMatch.index);
		return sanitized.replace(/[\u200B-\u200D\uFEFF]/g, "");
	}

	return sanitized;
}

function runBundle() {
	console.log(`[${new Date().toLocaleTimeString()}] Bundling...`);
	try {
		if (!fs.existsSync(buildDir)) {
			fs.mkdirSync(buildDir, { recursive: true });
		}

		if (fs.existsSync(mainPath)) {
			const bundled = buildBundleFromMain(mainPath);
			fs.writeFileSync(outputPath, bundled, { encoding: "utf8", flag: "w" });
			console.log("Build created:", outputPath);
		} else {
			const entry = resolveSingleEntry();
			if (!entry) {
				console.error("No src/Main.lua and no single file found.");
				return false;
			}
			console.log("Copying single file:", path.basename(entry));
			fs.copyFileSync(entry, outputPath);
		}

		if (!fs.existsSync(deployDir)) {
			fs.mkdirSync(deployDir, { recursive: true });
		}

		let deployContent = fs.readFileSync(outputPath, "utf8");
		deployContent = stripBOM(deployContent);
		fs.writeFileSync(deployPath, deployContent, { encoding: "utf8", flag: "w" });
		console.log("Deployed to:", deployPath);
		return true;
	} catch (err) {
		console.error("Bundle failed:", err.message);
		return false;
	}
}

const args = process.argv.slice(2);
const isWatch = args.includes("--watch") || args.includes("-w");

if (isWatch) {
	console.log("Watching for changes in src/ directory...");
	runBundle();
	let throttleToken = null;
	fs.watch(srcDir, { recursive: true }, (event, filename) => {
		if (filename && filename.endsWith(".lua")) {
			if (throttleToken) clearTimeout(throttleToken);
			throttleToken = setTimeout(() => {
				runBundle();
				throttleToken = null;
			}, 100);
		}
	});
} else {
	const ok = runBundle();
	process.exit(ok ? 0 : 1);
}
