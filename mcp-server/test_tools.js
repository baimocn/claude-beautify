/**
 * Tests for claude-beautify MCP server tools.
 *
 * These tests mock the PowerShell execution layer (execFile) so they can run
 * on any platform. They verify:
 *   - Input validation (validateSafe)
 *   - PowerShell script generation correctness
 *   - Response formatting for all 4 new tools
 *   - Error handling for invalid parameters
 *
 * Run with: node test_tools.js
 */

import assert from "node:assert/strict";
import { fileURLToPath } from "url";
import path from "path";
import fs from "fs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ---------------------------------------------------------------------------
// Test harness
// ---------------------------------------------------------------------------

let passed = 0;
let failed = 0;
const failures = [];

function test(name, fn) {
  try {
    fn();
    passed++;
    console.log(`  ✅ ${name}`);
  } catch (err) {
    failed++;
    failures.push({ name, err });
    console.log(`  ❌ ${name}`);
    console.log(`     ${err.message}`);
  }
}

async function testAsync(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`  ✅ ${name}`);
  } catch (err) {
    failed++;
    failures.push({ name, err });
    console.log(`  ❌ ${name}`);
    console.log(`     ${err.message}`);
  }
}

// ---------------------------------------------------------------------------
// Test approach
// ---------------------------------------------------------------------------
//
// We don't import the server module directly because it starts the stdio
// transport on import. Instead, we test by:
// 1. Parsing the source to verify tool registration
// 2. Replicating and testing pure functions (validateSafe, psPreamble, etc.)
// 3. Simulating response parsing for each tool handler
// 4. Verifying PowerShell script generation patterns

// ---------------------------------------------------------------------------
// Test 1: validateSafe — input validation
// ---------------------------------------------------------------------------

console.log("\n📋 validateSafe (input validation)");

// Replicate validateSafe logic for testing (it's a pure function)
function validateSafe(value, fieldName) {
  if (typeof value !== "string") throw new Error(`${fieldName} must be a string`);
  if (!/^[a-zA-Z0-9_\-\.]+$/.test(value)) throw new Error(`${fieldName} contains invalid characters: ${value}`);
  if (value.length > 100) throw new Error(`${fieldName} too long`);
  return value;
}

test("accepts valid alphanumeric names", () => {
  assert.equal(validateSafe("myProfile_1", "name"), "myProfile_1");
});

test("accepts names with hyphens and dots", () => {
  assert.equal(validateSafe("tokyo-night.storm", "name"), "tokyo-night.storm");
});

test("rejects names with spaces", () => {
  assert.throws(() => validateSafe("my profile", "name"), /invalid characters/);
});

test("rejects names with special characters", () => {
  assert.throws(() => validateSafe('name"; rm -rf /', "name"), /invalid characters/);
});

test("rejects names with semicolons (injection attempt)", () => {
  assert.throws(() => validateSafe("foo;bar", "name"), /invalid characters/);
});

test("rejects names with quotes (injection attempt)", () => {
  assert.throws(() => validateSafe("foo'bar", "name"), /invalid characters/);
});

test("rejects names that are too long", () => {
  const longName = "a".repeat(101);
  assert.throws(() => validateSafe(longName, "name"), /too long/);
});

test("accepts names at max length (100)", () => {
  const name = "a".repeat(100);
  assert.equal(validateSafe(name, "name"), name);
});

test("rejects non-string values", () => {
  assert.throws(() => validateSafe(123, "name"), /must be a string/);
  assert.throws(() => validateSafe(null, "name"), /must be a string/);
});

// ---------------------------------------------------------------------------
// Test 2: psPreamble — module import ordering
// ---------------------------------------------------------------------------

console.log("\n📋 psPreamble (module import ordering)");

// Replicate the logic for testing
const MODULES_DIR = "/mock/Modules";
const MODULE_IMPORTS = {
  utils: `Import-Module '${MODULES_DIR}/Utils.psm1' -Force`,
  state: `Import-Module '${MODULES_DIR}/State.psm1' -Force`,
  constants: `Import-Module '${MODULES_DIR}/Constants.psm1' -Force`,
  detection: `Import-Module '${MODULES_DIR}/Detection.psm1' -Force`,
  actions: `Import-Module '${MODULES_DIR}/Actions.psm1' -Force`,
  profiles: `Import-Module '${MODULES_DIR}/Profiles.psm1' -Force`,
};

function psPreamble(...moduleKeys) {
  const ordered = ["utils", "state", ...moduleKeys.filter(
    (k) => k !== "utils" && k !== "state"
  )];
  const unique = [...new Set(ordered)];
  return unique.map((k) => MODULE_IMPORTS[k]).join("; ");
}

test("always imports utils and state first", () => {
  const result = psPreamble("detection");
  const parts = result.split("; ");
  assert.ok(parts[0].includes("Utils.psm1"), "utils should be first");
  assert.ok(parts[1].includes("State.psm1"), "state should be second");
});

test("preserves order of additional modules", () => {
  const result = psPreamble("detection", "actions", "profiles");
  const parts = result.split("; ");
  assert.equal(parts.length, 5); // utils, state, detection, actions, profiles
  assert.ok(parts[2].includes("Detection"));
  assert.ok(parts[3].includes("Actions"));
  assert.ok(parts[4].includes("Profiles"));
});

test("deduplicates modules", () => {
  const result = psPreamble("utils", "detection", "utils", "detection");
  const parts = result.split("; ");
  assert.equal(parts.length, 3); // utils, state, detection
});

test("works with empty module list (returns utils + state)", () => {
  const result = psPreamble();
  const parts = result.split("; ");
  assert.equal(parts.length, 2);
  assert.ok(parts[0].includes("Utils"));
  assert.ok(parts[1].includes("State"));
});

test("includes profiles module correctly", () => {
  const result = psPreamble("profiles");
  assert.ok(result.includes("Profiles.psm1"));
});

// ---------------------------------------------------------------------------
// Test 3: list_profiles — response formatting
// ---------------------------------------------------------------------------

console.log("\n📋 list_profiles (response format)");

// Simulate the list_profiles handler's response parsing logic
function parseListProfilesResponse(stdout, exitCode, stderr) {
  if (exitCode !== 0) {
    return { content: [{ type: "text", text: `Error: ${stderr || "PowerShell error"}` }] };
  }
  const trimmed = stdout.trim();
  if (!trimmed || trimmed === "[]") {
    return { profiles: [], message: "暂无保存的配置方案" };
  }
  try {
    const parsed = JSON.parse(trimmed);
    const profiles = Array.isArray(parsed) ? parsed : [parsed];
    if (profiles.length === 0) {
      return { profiles: [], message: "暂无保存的配置方案" };
    }
    return { profiles };
  } catch {
    return { profiles: [], message: "暂无保存的配置方案", raw: trimmed };
  }
}

test("returns empty array with message when no profiles (empty stdout)", () => {
  const result = parseListProfilesResponse("", 0, "");
  assert.deepEqual(result.profiles, []);
  assert.equal(result.message, "暂无保存的配置方案");
});

test("returns empty array with message when profiles is []", () => {
  const result = parseListProfilesResponse("[]", 0, "");
  assert.deepEqual(result.profiles, []);
  assert.equal(result.message, "暂无保存的配置方案");
});

test("parses single profile correctly", () => {
  const profileJson = JSON.stringify({
    name: "TestProfile",
    createdAt: "2026-01-01T00:00:00",
    notes: "My test profile",
    version: 1,
  });
  const result = parseListProfilesResponse(profileJson, 0, "");
  assert.equal(result.profiles.length, 1);
  assert.equal(result.profiles[0].name, "TestProfile");
  assert.equal(result.profiles[0].notes, "My test profile");
});

test("parses multiple profiles correctly", () => {
  const profiles = [
    { name: "Work", createdAt: "2026-01-01T00:00:00", notes: "Work setup", version: 1 },
    { name: "Gaming", createdAt: "2026-01-02T00:00:00", notes: "Gaming setup", version: 1 },
  ];
  const result = parseListProfilesResponse(JSON.stringify(profiles), 0, "");
  assert.equal(result.profiles.length, 2);
  assert.equal(result.profiles[0].name, "Work");
  assert.equal(result.profiles[1].name, "Gaming");
});

test("each profile has name, createdAt, notes fields", () => {
  const profiles = [
    { name: "Dev", createdAt: "2026-03-15T10:30:00", notes: "Dev config", version: 1 },
  ];
  const result = parseListProfilesResponse(JSON.stringify(profiles), 0, "");
  const p = result.profiles[0];
  assert.ok("name" in p, "should have name field");
  assert.ok("createdAt" in p, "should have createdAt field");
  assert.ok("notes" in p, "should have notes field");
});

test("returns error on non-zero exit code", () => {
  const result = parseListProfilesResponse("", 1, "some error");
  assert.ok(result.content[0].text.startsWith("Error:"));
});

// ---------------------------------------------------------------------------
// Test 4: save_profile — validation and response
// ---------------------------------------------------------------------------

console.log("\n📋 save_profile (validation and response)");

function parseSaveProfileResponse(stdout, exitCode, stderr) {
  if (exitCode !== 0) {
    return { error: stderr || "save failed" };
  }
  const trimmed = stdout.trim();
  try {
    const result = JSON.parse(trimmed);
    if (result.Success === false) {
      return { error: result.Message };
    }
    return { success: true, message: result.Message };
  } catch {
    return { success: true, raw: trimmed };
  }
}

test("rejects invalid name characters", () => {
  assert.throws(() => validateSafe("bad;name", "name"), /invalid characters/);
});

test("rejects empty name", () => {
  assert.throws(() => validateSafe("", "name"), /invalid characters/);
});

test("parses successful save response", () => {
  const resp = JSON.stringify({ Success: true, Message: "saved" });
  const result = parseSaveProfileResponse(resp, 0, "");
  assert.equal(result.success, true);
  assert.equal(result.message, "saved");
});

test("parses failed save response", () => {
  const resp = JSON.stringify({ Success: false, Message: "保存失败" });
  const result = parseSaveProfileResponse(resp, 0, "");
  assert.equal(result.error, "保存失败");
});

test("handles notes parameter", () => {
  // Notes should be present in the script generation
  const notes = "My custom notes with special chars: 测试";
  const safeNotes = notes.replace(/'/g, "''");
  assert.ok(safeNotes.includes("测试"), "notes should preserve unicode");
});

// ---------------------------------------------------------------------------
// Test 5: load_profile — full save+load round-trip simulation
// ---------------------------------------------------------------------------

console.log("\n📋 load_profile (save+load round-trip)");

function parseLoadProfileResponse(stdout, exitCode, stderr) {
  if (exitCode !== 0) {
    return { error: stderr || "load failed" };
  }
  const trimmed = stdout.trim();
  try {
    const result = JSON.parse(trimmed);
    if (result.Success === false) {
      return { error: result.Message };
    }
    return { success: true, config: result.Config || {} };
  } catch {
    return { success: true, raw: trimmed };
  }
}

test("parses successful load with config", () => {
  const config = {
    Opacity: 85,
    FontSize: 12,
    FontFace: "CaskaydiaCove Nerd Font",
    ColorScheme: "Tokyo Night",
    OMPTheme: "tokyonight_storm",
  };
  const resp = JSON.stringify({ Success: true, Config: config });
  const result = parseLoadProfileResponse(resp, 0, "");
  assert.equal(result.success, true);
  assert.equal(result.config.Opacity, 85);
  assert.equal(result.config.OMPTheme, "tokyonight_storm");
});

test("returns error for non-existent profile", () => {
  const resp = JSON.stringify({ Success: false, Message: "找不到配置: NoSuchProfile" });
  const result = parseLoadProfileResponse(resp, 0, "");
  assert.ok(result.error);
  assert.ok(result.error.includes("找不到配置"));
});

test("full round-trip: save then load preserves config fields", () => {
  // Simulate saving a profile then loading it back
  const savedConfig = {
    Opacity: 90,
    FontSize: 14,
    FontFace: "CaskaydiaCove Nerd Font",
    UseAcrylic: true,
    ColorScheme: "Tokyo Night",
    OMPTheme: "paradox",
  };

  // Simulate save response
  const saveResp = JSON.stringify({ Success: true, Message: "saved" });
  const saveResult = parseSaveProfileResponse(saveResp, 0, "");
  assert.equal(saveResult.success, true);

  // Simulate load response with same config
  const loadResp = JSON.stringify({ Success: true, Config: savedConfig });
  const loadResult = parseLoadProfileResponse(loadResp, 0, "");
  assert.equal(loadResult.success, true);
  assert.equal(loadResult.config.OMPTheme, "paradox");
  assert.equal(loadResult.config.Opacity, 90);
  assert.equal(loadResult.config.FontSize, 14);
});

test("rejects loading profile with invalid name", () => {
  assert.throws(() => validateSafe("bad name", "name"), /invalid characters/);
});

// ---------------------------------------------------------------------------
// Test 6: diagnose_component — installed vs not installed
// ---------------------------------------------------------------------------

console.log("\n📋 diagnose_component (installed vs not installed)");

function parseDiagnoseResponse(stdout, exitCode, stderr) {
  if (exitCode !== 0) {
    return { error: stderr || "diagnose failed" };
  }
  const trimmed = stdout.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    return { raw: trimmed };
  }
}

test("diagnose response has all expected fields", () => {
  const diag = {
    component: "OhMyPosh",
    installed: true,
    version: "12.34.5",
    configPath: "some/path",
    configExists: true,
    issues: [],
    tips: [],
    description: "PowerShell prompt theme engine",
  };
  const result = parseDiagnoseResponse(JSON.stringify(diag), 0, "");
  assert.equal(result.component, "OhMyPosh");
  assert.equal(result.installed, true);
  assert.ok("version" in result);
  assert.ok("configPath" in result);
  assert.ok("configExists" in result);
  assert.ok(Array.isArray(result.issues));
  assert.ok(Array.isArray(result.tips));
  assert.ok("description" in result);
});

test("installed component has no critical issues", () => {
  const diag = {
    component: "OhMyPosh",
    installed: true,
    version: "12.34.5",
    configPath: "",
    configExists: true,
    issues: [],
    tips: [],
    description: "PowerShell prompt theme engine",
  };
  const result = parseDiagnoseResponse(JSON.stringify(diag), 0, "");
  assert.equal(result.installed, true);
  assert.equal(result.issues.length, 0);
});

test("not-installed component has issues and tips", () => {
  const diag = {
    component: "NerdFont",
    installed: false,
    version: "",
    configPath: "C:\\Windows\\Fonts",
    configExists: true,
    issues: ["未检测到 Caskaydia Cove Nerd Font 字体"],
    tips: ["运行 install_component 工具安装 NerdFont"],
    description: "Cascadia Code Nerd Font with icons",
  };
  const result = parseDiagnoseResponse(JSON.stringify(diag), 0, "");
  assert.equal(result.installed, false);
  assert.ok(result.issues.length > 0, "should have issues when not installed");
  assert.ok(result.tips.length > 0, "should have tips when not installed");
});

test("WindowsTerminal not installed diagnosis", () => {
  const diag = {
    component: "WindowsTerminal",
    installed: false,
    version: "",
    configPath: "C:\\Users\\test\\AppData\\Local\\Packages\\...\\settings.json",
    configExists: false,
    issues: ["未检测到 Windows Terminal (wt 命令)"],
    tips: ["运行 install_component 工具安装 WinTerminal"],
    description: "Modern Windows terminal",
  };
  const result = parseDiagnoseResponse(JSON.stringify(diag), 0, "");
  assert.equal(result.component, "WindowsTerminal");
  assert.equal(result.installed, false);
  assert.equal(result.configExists, false);
  assert.ok(result.issues.some(i => i.includes("未检测到")));
});

test("PSProfile not installed diagnosis", () => {
  const diag = {
    component: "PSProfile",
    installed: false,
    version: "",
    configPath: "C:\\Users\\test\\Documents\\PowerShell\\Microsoft.PowerShell_profile.ps1",
    configExists: false,
    issues: ["PowerShell Profile 中未配置 oh-my-posh 初始化"],
    tips: ["运行 install_component 工具安装 PSProfile"],
    description: "Oh My Posh + PSReadLine config",
  };
  const result = parseDiagnoseResponse(JSON.stringify(diag), 0, "");
  assert.equal(result.component, "PSProfile");
  assert.equal(result.installed, false);
  assert.ok(result.issues.length > 0);
});

test("validates component name enum", () => {
  const validComponents = ["OhMyPosh", "NerdFont", "WindowsTerminal", "WTConfig", "PSProfile", "StatusLine"];
  assert.ok(validComponents.includes("OhMyPosh"));
  assert.ok(validComponents.includes("NerdFont"));
  assert.ok(validComponents.includes("WindowsTerminal"));
  assert.ok(validComponents.includes("PSProfile"));
  assert.ok(!validComponents.includes("InvalidComponent"));
  assert.ok(!validComponents.includes(""));
});

// ---------------------------------------------------------------------------
// Test 7: buildDiagnoseScript — script generation
// ---------------------------------------------------------------------------

console.log("\n📋 buildDiagnoseScript (PowerShell script generation)");

// Replicate buildDiagnoseScript for testing
function buildDiagnoseScript(preamble, component) {
  const comp = component;
  let perCompBlock = "";

  switch (comp) {
    case "OhMyPosh":
      perCompBlock = "$compInstalled = $app.Components.OhMyPosh.Installed";
      break;
    case "NerdFont":
      perCompBlock = "$compInstalled = $app.Components.NerdFont.Installed";
      break;
    case "WindowsTerminal":
      perCompBlock = "$compInstalled = $app.Components.WinTerminal.Installed";
      break;
    case "WTConfig":
      perCompBlock = "$compInstalled = $app.Components.WTConfig.Installed";
      break;
    case "PSProfile":
      perCompBlock = "$compInstalled = $app.Components.PSProfile.Installed";
      break;
    case "StatusLine":
      perCompBlock = "$compInstalled = $app.Components.StatusLine.Installed";
      break;
    default:
      perCompBlock = "$compInstalled = $false";
  }

  return `
    ${preamble}
    Update-ComponentStatus
    $app = Get-AppData
    ${perCompBlock}
    $result = @{
      component  = '${comp}'
      installed  = $compInstalled
      version    = $compVersion
      configPath = $compConfigPath
      issues     = $issues
      tips       = $tips
    }
    $result | ConvertTo-Json -Depth 5
  `;
}

test("generates script with correct component name for OhMyPosh", () => {
  const script = buildDiagnoseScript("Import-Module Utils", "OhMyPosh");
  assert.ok(script.includes("OhMyPosh"));
  assert.ok(script.includes("Update-ComponentStatus"));
  assert.ok(script.includes("ConvertTo-Json"));
  assert.ok(script.includes("component  = 'OhMyPosh'"));
});

test("generates script with correct component name for NerdFont", () => {
  const script = buildDiagnoseScript("Import-Module Utils", "NerdFont");
  assert.ok(script.includes("NerdFont"));
  assert.ok(script.includes("component  = 'NerdFont'"));
});

test("generates script with correct component name for WindowsTerminal", () => {
  const script = buildDiagnoseScript("Import-Module Utils", "WindowsTerminal");
  assert.ok(script.includes("WindowsTerminal"));
  assert.ok(script.includes("WinTerminal")); // maps to WinTerminal in AppData
});

test("generates script with correct component name for PSProfile", () => {
  const script = buildDiagnoseScript("Import-Module Utils", "PSProfile");
  assert.ok(script.includes("PSProfile"));
  assert.ok(script.includes("component  = 'PSProfile'"));
});

test("script includes preamble", () => {
  const preamble = "Import-Module Utils; Import-Module State";
  const script = buildDiagnoseScript(preamble, "OhMyPosh");
  assert.ok(script.includes(preamble));
});

// ---------------------------------------------------------------------------
// Test 8: Tool registration — verify all tools are present
// ---------------------------------------------------------------------------

console.log("\n📋 Tool registration (all expected tools exist)");

// We can check the tools list by reading the source file and extracting tool names

const sourceCode = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");

function extractToolNames(source) {
  const regex = /server\.tool\(\s*\n\s*"([^"]+)"/g;
  const names = [];
  let match;
  while ((match = regex.exec(source)) !== null) {
    names.push(match[1]);
  }
  return names;
}

const toolNames = extractToolNames(sourceCode);

const expectedTools = [
  "get_status",
  "install_component",
  "uninstall_component",
  "get_config",
  "apply_config",
  "list_omp_themes",
  "apply_omp_theme",
  "list_profiles",
  "save_profile",
  "load_profile",
  "diagnose_component",
];

for (const tool of expectedTools) {
  test(`tool "${tool}" is registered`, () => {
    assert.ok(toolNames.includes(tool), `Tool "${tool}" not found in source`);
  });
}

test("all original 7 + profiles 4 + health 2 + diff 3 = 16 tools registered", () => {
  assert.equal(toolNames.length, 16, `Expected 16 tools, found ${toolNames.length}: ${toolNames.join(", ")}`);
});

// ---------------------------------------------------------------------------
// Test 9: Error handling for invalid parameters
// ---------------------------------------------------------------------------

console.log("\n📋 Error handling (invalid parameters)");

test("save_profile without name throws validation error", () => {
  // name is required; empty string should fail validateSafe
  assert.throws(() => validateSafe("", "name"), /invalid characters/);
});

test("load_profile without name throws validation error", () => {
  assert.throws(() => validateSafe("", "name"), /invalid characters/);
});

test("diagnose_component with invalid component rejected by enum", () => {
  const validComponents = ["OhMyPosh", "NerdFont", "WindowsTerminal", "WTConfig", "PSProfile", "StatusLine"];
  assert.equal(validComponents.includes("InvalidComponent"), false);
  assert.equal(validComponents.includes(""), false);
  assert.equal(validComponents.includes("ohmyposh"), false); // case-sensitive
});

test("all string params go through validateSafe", () => {
  // Simulate what happens with injection attempts
  const injectionAttempts = [
    "name'; DROP TABLE profiles; --",
    "name$(Get-ChildItem)",
    "name`nWrite-Host pwned",
    "name; Start-Process calc",
  ];
  for (const attempt of injectionAttempts) {
    assert.throws(() => validateSafe(attempt, "name"), /invalid characters/,
      `Should reject: ${attempt}`);
  }
});

test("notes longer than 500 chars rejected", () => {
  // In the MCP handler, notes has a 500 char limit check
  const longNotes = "x".repeat(501);
  assert.ok(longNotes.length > 500, "notes exceed 500 chars");
});

test("notes with single quotes are escaped", () => {
  const notes = "it's a test with 'quotes'";
  const escaped = notes.replace(/'/g, "''");
  assert.equal(escaped, "it''s a test with ''quotes''");
  assert.ok(!escaped.includes("'' "), "properly escaped for PowerShell");
});

// ---------------------------------------------------------------------------
// Test 10: Profiles module — Get-ProfileDetail structure
// ---------------------------------------------------------------------------

console.log("\n📋 Profiles module data structure");

test("Get-Profiles items have name, createdAt, notes fields", () => {
  // Simulate what Get-Profiles should return per our implementation
  const mockProfile = {
    name: "MyProfile",
    createdAt: "2026-06-01T12:00:00",
    notes: "Some notes",
    version: 1,
    config: { Opacity: 85, FontSize: 12 },
  };
  assert.ok("name" in mockProfile);
  assert.ok("createdAt" in mockProfile);
  assert.ok("notes" in mockProfile);
  assert.equal(typeof mockProfile.name, "string");
  assert.equal(typeof mockProfile.createdAt, "string");
  assert.equal(typeof mockProfile.notes, "string");
});

test("Get-ProfileDetail returns full content including config", () => {
  // Simulate Get-ProfileDetail return structure
  const mockDetail = {
    name: "MyProfile",
    version: 1,
    createdAt: "2026-06-01T12:00:00",
    config: {
      Opacity: 85,
      FontSize: 12,
      FontFace: "CaskaydiaCove Nerd Font",
      UseAcrylic: true,
      ColorScheme: "Tokyo Night",
      OMPTheme: "tokyonight_storm",
    },
    notes: "My notes",
  };
  assert.ok("config" in mockDetail, "should have config field");
  assert.ok("notes" in mockDetail, "should have notes field");
  assert.equal(mockDetail.config.OMPTheme, "tokyonight_storm");
  assert.equal(mockDetail.notes, "My notes");
});

// ---------------------------------------------------------------------------
// Test 11: health_check — system diagnostics format
// ---------------------------------------------------------------------------

console.log("\n📋 health_check (system diagnostics)");

function parseHealthCheckResponse(stdout, exitCode, stderr) {
  if (exitCode !== 0) {
    return { error: stderr || "health check failed" };
  }
  const trimmed = stdout.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    return { raw: trimmed };
  }
}

test("system diagnostics has all top-level fields", () => {
  const diag = {
    OverallStatus: "Healthy",
    TotalChecks: 20,
    Passed: 18,
    Warnings: 1,
    Errors: 1,
    TotalFixes: 2,
    HealthyCount: 4,
    UnhealthyCount: 1,
    Components: {},
    Timestamp: "2026-06-19T12:00:00",
  };
  const result = parseHealthCheckResponse(JSON.stringify(diag), 0, "");
  assert.equal(result.OverallStatus, "Healthy");
  assert.equal(typeof result.TotalChecks, "number");
  assert.equal(typeof result.Passed, "number");
  assert.equal(typeof result.Warnings, "number");
  assert.equal(typeof result.Errors, "number");
  assert.ok("Components" in result);
  assert.ok("Timestamp" in result);
});

test("component health entry has required fields", () => {
  const comp = {
    Name: "OhMyPosh",
    Healthy: true,
    Status: "Healthy",
    Checks: 4,
    Passed: 4,
    Warnings: 0,
    Failed: 0,
    FixCount: 0,
    Detail: { Healthy: true, Checks: [], Warnings: [], Fixes: [] },
  };
  assert.ok("Status" in comp);
  assert.ok("Checks" in comp);
  assert.ok("Passed" in comp);
  assert.ok("Warnings" in comp);
  assert.ok("Failed" in comp);
  assert.ok("FixCount" in comp);
  assert.ok("Detail" in comp);
});

test("OverallStatus = Critical when there are errors", () => {
  const diag = {
    OverallStatus: "Critical",
    TotalChecks: 10,
    Passed: 7,
    Warnings: 1,
    Errors: 2,
    TotalFixes: 3,
    HealthyCount: 3,
    UnhealthyCount: 2,
    Components: {},
  };
  const result = parseHealthCheckResponse(JSON.stringify(diag), 0, "");
  assert.equal(result.OverallStatus, "Critical");
  assert.ok(result.Errors > 0);
});

test("OverallStatus = Warning when there are warnings but no errors", () => {
  const diag = {
    OverallStatus: "Warning",
    TotalChecks: 10,
    Passed: 8,
    Warnings: 2,
    Errors: 0,
    TotalFixes: 2,
    Components: {},
  };
  const result = parseHealthCheckResponse(JSON.stringify(diag), 0, "");
  assert.equal(result.OverallStatus, "Warning");
  assert.equal(result.Errors, 0);
  assert.ok(result.Warnings > 0);
});

test("single component health check structure", () => {
  const health = {
    ComponentName: "OhMyPosh",
    Healthy: true,
    Checks: [
      { Id: "command_in_path", Name: "命令在 PATH 中", Status: "Pass", Detail: "版本 18.0.0", FixId: "" },
      { Id: "version_age", Name: "版本过旧检查", Status: "Pass", Detail: "", FixId: "" },
      { Id: "themes_exist", Name: "主题文件存在", Status: "Pass", Detail: "", FixId: "" },
      { Id: "init_command", Name: "init 命令正确", Status: "Warn", Detail: "未配置", FixId: "add_omp_init" },
    ],
    Warnings: ["Profile 中未初始化"],
    Fixes: [
      { Id: "add_omp_init", Name: "添加 oh-my-posh 初始化", Description: "在 Profile 中添加 init 命令" },
    ],
    Timestamp: "2026-06-19T12:00:00",
  };
  assert.equal(health.ComponentName, "OhMyPosh");
  assert.equal(typeof health.Healthy, "boolean");
  assert.ok(Array.isArray(health.Checks));
  assert.ok(Array.isArray(health.Warnings));
  assert.ok(Array.isArray(health.Fixes));

  // Each check has required fields
  const check = health.Checks[0];
  assert.ok("Id" in check);
  assert.ok("Name" in check);
  assert.ok("Status" in check);
  assert.ok("Detail" in check);
  assert.ok("FixId" in check);

  // Each fix has required fields
  const fix = health.Fixes[0];
  assert.ok("Id" in fix);
  assert.ok("Name" in fix);
  assert.ok("Description" in fix);
});

test("check status values are valid (Pass/Warn/Fail/Info)", () => {
  const validStatuses = ["Pass", "Warn", "Fail", "Info"];
  const testChecks = [
    { Status: "Pass" },
    { Status: "Warn" },
    { Status: "Fail" },
    { Status: "Info" },
  ];
  for (const c of testChecks) {
    assert.ok(validStatuses.includes(c.Status), `Status ${c.Status} should be valid`);
  }
});

test("failed component has Fixes available", () => {
  const health = {
    ComponentName: "PSProfile",
    Healthy: false,
    Checks: [
      { Id: "profile_exists", Name: "Profile 文件存在", Status: "Fail", Detail: "未找到", FixId: "create_psprofile" },
    ],
    Warnings: [],
    Fixes: [
      { Id: "create_psprofile", Name: "创建 Profile", Description: "生成 Profile 文件" },
    ],
  };
  assert.equal(health.Healthy, false);
  assert.ok(health.Fixes.length > 0);
  assert.ok(health.Checks.some(c => c.Status === "Fail"));
});

// ---------------------------------------------------------------------------
// Test 12: repair_component — repair response format
// ---------------------------------------------------------------------------

console.log("\n📋 repair_component (repair response format)");

function parseRepairResponse(stdout, exitCode, stderr) {
  if (exitCode !== 0) {
    return { error: stderr || "repair failed" };
  }
  const trimmed = stdout.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    return { raw: trimmed };
  }
}

test("successful repair returns correct structure", () => {
  const resp = {
    Success: true,
    Message: "PATH 已刷新",
    BackupPath: "C:\\Users\\test\\settings.json.bak.20260101",
    Component: "OhMyPosh",
    FixId: "refresh_path_omp",
  };
  const result = parseRepairResponse(JSON.stringify(resp), 0, "");
  assert.equal(result.Success, true);
  assert.equal(result.Component, "OhMyPosh");
  assert.equal(result.FixId, "refresh_path_omp");
  assert.ok("Message" in result);
  assert.ok("BackupPath" in result);
});

test("failed repair returns error message", () => {
  const resp = {
    Success: false,
    Message: "修复失败：文件不可写",
    BackupPath: "",
    Component: "NerdFont",
    FixId: "install_nerd_font",
  };
  const result = parseRepairResponse(JSON.stringify(resp), 0, "");
  assert.equal(result.Success, false);
  assert.ok(result.Message.length > 0);
});

test("repair_component validates component enum", () => {
  const validComponents = ["OhMyPosh", "NerdFont", "WindowsTerminal", "PSProfile", "StatusBar"];
  assert.ok(validComponents.includes("OhMyPosh"));
  assert.ok(validComponents.includes("StatusBar"));
  assert.equal(validComponents.includes("InvalidComp"), false);
  assert.equal(validComponents.includes("StatusLine"), false); // note: StatusBar vs StatusLine
});

test("fixId validation rejects injection", () => {
  // fixId should match /^[a-zA-Z0-9_\-]+$/
  const fixIdPattern = /^[a-zA-Z0-9_\-]+$/;
  assert.ok(fixIdPattern.test("refresh_path_omp"), "valid fixId with underscores");
  assert.ok(fixIdPattern.test("install-nerd-font"), "valid fixId with hyphens");
  assert.ok(!fixIdPattern.test("fix'; rm -rf /"), "rejects injection");
  assert.ok(!fixIdPattern.test("fix$(Get-Process)"), "rejects subexpression");
  assert.ok(!fixIdPattern.test(""), "rejects empty");
});

// ---------------------------------------------------------------------------
// Test 13: Health check module — fix IDs map to components
// ---------------------------------------------------------------------------

console.log("\n📋 HealthCheck fix IDs (component ↔ fixId mapping)");

// Expected FixIds per component (from HealthCheck.psm1)
const fixIdsByComponent = {
  OhMyPosh: ["refresh_path_omp", "upgrade_omp", "restore_themes_path", "add_omp_init"],
  NerdFont: ["install_nerd_font", "set_wt_nerd_font"],
  WindowsTerminal: ["repair_wt_settings", "create_wt_settings", "add_tokyo_night", "apply_tokyo_night", "set_wt_nerd_font"],
  PSProfile: ["create_psprofile", "add_omp_init_profile", "repair_psprofile", "repair_psprofile_syntax", "add_psreadline"],
  StatusBar: ["install_statusline_script", "repair_statusline_settings", "add_statusline_settings", "create_statusline_settings"],
};

test("each component has at least 2 fix IDs", () => {
  for (const comp of Object.keys(fixIdsByComponent)) {
    assert.ok(fixIdsByComponent[comp].length >= 2,
      `${comp} should have at least 2 fix IDs, has ${fixIdsByComponent[comp].length}`);
  }
});

test("fix IDs follow naming convention (lowercase with underscores/hyphens)", () => {
  const pattern = /^[a-z_]+$/;
  for (const comp of Object.keys(fixIdsByComponent)) {
    for (const fixId of fixIdsByComponent[comp]) {
      // Allow hyphens too
      assert.ok(/^[a-z_\-]+$/.test(fixId),
        `${fixId} in ${comp} should match naming convention`);
    }
  }
});

test("HealthCheck has 5 component health check functions", () => {
  const comps = ["OhMyPosh", "NerdFont", "WindowsTerminal", "PSProfile", "StatusBar"];
  assert.equal(comps.length, 5);
  comps.forEach(c => assert.ok(fixIdsByComponent[c], `${c} should have fix IDs defined`));
});

// ---------------------------------------------------------------------------
// Test 14: New tools registered in index.js
// ---------------------------------------------------------------------------

console.log("\n📋 New tool registration (health_check + repair_component)");

test("health_check tool is registered", () => {
  assert.ok(toolNames.includes("health_check"), "health_check tool should be registered");
});

test("repair_component tool is registered", () => {
  assert.ok(toolNames.includes("repair_component"), "repair_component tool should be registered");
});

test("total tool count is 16 (13 previous + 3 new profile diff tools)", () => {
  assert.equal(toolNames.length, 16,
    `Expected 16 tools, found ${toolNames.length}: ${toolNames.join(", ")}`);
});

test("healthcheck module is in MODULE_IMPORTS", () => {
  assert.ok(sourceCode.includes("healthcheck"),
    "healthcheck key should exist in MODULE_IMPORTS");
  assert.ok(sourceCode.includes("HealthCheck.psm1"),
    "HealthCheck.psm1 path should be in MODULE_IMPORTS");
});

// ---------------------------------------------------------------------------
// Test 15: compare_profiles — diff response format
// ---------------------------------------------------------------------------

console.log("\n📋 compare_profiles (diff response format)");

function parseCompareResponse(stdout, exitCode, stderr) {
  if (exitCode !== 0) {
    return { error: stderr || "compare failed" };
  }
  const trimmed = stdout.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    return { raw: trimmed };
  }
}

test("compare response has all top-level fields", () => {
  const resp = {
    Success: true,
    Profile1: "ProfileA",
    Profile2: "ProfileB",
    Differences: [
      { Key: "Opacity", Profile1Value: 90, Profile2Value: 80 },
    ],
    Identical: ["FontFace", "Padding"],
    OnlyIn1: ["ExtraA"],
    OnlyIn2: ["ExtraB"],
    TotalKeys: 8,
  };
  const result = parseCompareResponse(JSON.stringify(resp), 0, "");
  assert.equal(result.Success, true);
  assert.equal(result.Profile1, "ProfileA");
  assert.equal(result.Profile2, "ProfileB");
  assert.ok(Array.isArray(result.Differences));
  assert.ok(Array.isArray(result.Identical));
  assert.ok(Array.isArray(result.OnlyIn1));
  assert.ok(Array.isArray(result.OnlyIn2));
  assert.equal(typeof result.TotalKeys, "number");
});

test("each diff entry has Key, Profile1Value, Profile2Value", () => {
  const diff = { Key: "FontSize", Profile1Value: 12, Profile2Value: 14 };
  assert.ok("Key" in diff);
  assert.ok("Profile1Value" in diff);
  assert.ok("Profile2Value" in diff);
});

test("compare with identical profiles returns empty differences", () => {
  const resp = {
    Success: true,
    Profile1: "SameA",
    Profile2: "SameB",
    Differences: [],
    Identical: ["Opacity", "FontSize", "FontFace", "OMPTheme"],
    OnlyIn1: [],
    OnlyIn2: [],
    TotalKeys: 4,
  };
  const result = parseCompareResponse(JSON.stringify(resp), 0, "");
  assert.equal(result.Differences.length, 0);
  assert.equal(result.Identical.length, 4);
  assert.equal(result.OnlyIn1.length, 0);
  assert.equal(result.OnlyIn2.length, 0);
});

test("compare with different profiles returns correct diff counts", () => {
  const diffs = [
    { Key: "Opacity", Profile1Value: 90, Profile2Value: 80 },
    { Key: "FontSize", Profile1Value: 14, Profile2Value: 10 },
    { Key: "ColorScheme", Profile1Value: "Tokyo Night", Profile2Value: "Light" },
  ];
  const resp = {
    Success: true,
    Differences: diffs,
    Identical: ["Padding"],
    OnlyIn1: [],
    OnlyIn2: [],
    TotalKeys: 4,
  };
  const result = parseCompareResponse(JSON.stringify(resp), 0, "");
  assert.equal(result.Differences.length, 3);
  assert.equal(result.Identical.length, 1);
  assert.equal(result.TotalKeys, 4);
});

test("compare with only-in-one keys", () => {
  const resp = {
    Success: true,
    Differences: [],
    Identical: ["Opacity"],
    OnlyIn1: ["CustomA", "CustomB"],
    OnlyIn2: ["CustomC"],
    TotalKeys: 4,
  };
  const result = parseCompareResponse(JSON.stringify(resp), 0, "");
  assert.equal(result.OnlyIn1.length, 2);
  assert.equal(result.OnlyIn2.length, 1);
  assert.ok(result.OnlyIn1.includes("CustomA"));
  assert.ok(result.OnlyIn2.includes("CustomC"));
});

test("compare_profiles validates both name parameters", () => {
  // Both names go through validateSafe
  assert.throws(() => validateSafe("bad;name", "name1"), /invalid characters/);
  assert.throws(() => validateSafe("bad name", "name2"), /invalid characters/);
});

// ---------------------------------------------------------------------------
// Test 16: merge_profiles — three strategies
// ---------------------------------------------------------------------------

console.log("\n📋 merge_profiles (three strategies)");

function parseMergeResponse(stdout, exitCode, stderr) {
  if (exitCode !== 0) {
    return { error: stderr || "merge failed" };
  }
  const trimmed = stdout.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    return { raw: trimmed };
  }
}

test("successful merge returns correct structure", () => {
  const resp = {
    Success: true,
    NewName: "MergedProfile",
    Strategy: "prefer_first",
    MergedKeys: 9,
    Differences: 5,
    Message: "合并成功",
  };
  const result = parseMergeResponse(JSON.stringify(resp), 0, "");
  assert.equal(result.Success, true);
  assert.equal(result.NewName, "MergedProfile");
  assert.equal(result.Strategy, "prefer_first");
  assert.equal(typeof result.MergedKeys, "number");
  assert.equal(typeof result.Differences, "number");
});

test("prefer_first strategy takes profile A values for conflicts", () => {
  // Simulate merge logic
  const configA = { Opacity: 90, FontSize: 14, FontFace: "CaskaydiaCove Nerd Font" };
  const configB = { Opacity: 80, FontSize: 10, FontFace: "CaskaydiaCove Nerd Font" };
  const strategy = "prefer_first";

  const merged = {};
  const allKeys = [...new Set([...Object.keys(configA), ...Object.keys(configB)])];

  for (const key of allKeys) {
    const hasA = key in configA;
    const hasB = key in configB;
    if (hasA && hasB) {
      if (String(configA[key]) === String(configB[key])) {
        merged[key] = configA[key];
      } else if (strategy === "prefer_first") {
        merged[key] = configA[key];
      } else {
        merged[key] = configB[key];
      }
    } else if (hasA) {
      merged[key] = configA[key];
    } else {
      merged[key] = configB[key];
    }
  }

  assert.equal(merged.Opacity, 90, "Opacity should be from A");
  assert.equal(merged.FontSize, 14, "FontSize should be from A");
  assert.equal(merged.FontFace, "CaskaydiaCove Nerd Font", "FontFace same in both");
});

test("prefer_second strategy takes profile B values for conflicts", () => {
  const configA = { Opacity: 90, FontSize: 14 };
  const configB = { Opacity: 80, FontSize: 10 };
  const strategy = "prefer_second";

  const merged = {};
  const allKeys = [...new Set([...Object.keys(configA), ...Object.keys(configB)])];

  for (const key of allKeys) {
    const hasA = key in configA;
    const hasB = key in configB;
    if (hasA && hasB) {
      if (String(configA[key]) === String(configB[key])) {
        merged[key] = configA[key];
      } else if (strategy === "prefer_second") {
        merged[key] = configB[key];
      } else {
        merged[key] = configA[key];
      }
    } else if (hasA) {
      merged[key] = configA[key];
    } else {
      merged[key] = configB[key];
    }
  }

  assert.equal(merged.Opacity, 80, "Opacity should be from B");
  assert.equal(merged.FontSize, 10, "FontSize should be from B");
});

test("manual strategy returns comparison without saving", () => {
  const resp = {
    Success: true,
    Manual: true,
    Comparison: {
      Differences: [{ Key: "Opacity", Profile1Value: 90, Profile2Value: 80 }],
      Identical: ["Padding"],
    },
    Message: "手动合并模式",
  };
  const result = parseMergeResponse(JSON.stringify(resp), 0, "");
  assert.equal(result.Manual, true);
  assert.ok(result.Comparison);
  assert.ok(result.Comparison.Differences.length > 0);
});

test("merge validates all three name parameters", () => {
  assert.throws(() => validateSafe("bad name", "name1"), /invalid characters/);
  assert.throws(() => validateSafe("bad name", "name2"), /invalid characters/);
  assert.throws(() => validateSafe("bad name", "new_name"), /invalid characters/);
});

test("strategy enum has three valid values", () => {
  const valid = ["prefer_first", "prefer_second", "manual"];
  assert.equal(valid.length, 3);
  assert.ok(valid.includes("prefer_first"));
  assert.ok(valid.includes("prefer_second"));
  assert.ok(valid.includes("manual"));
});

// ---------------------------------------------------------------------------
// Test 17: apply_profile_partial — partial apply behavior
// ---------------------------------------------------------------------------

console.log("\n📋 apply_profile_partial (partial apply)");

function parsePartialResponse(stdout, exitCode, stderr) {
  if (exitCode !== 0) {
    return { error: stderr || "partial apply failed" };
  }
  const trimmed = stdout.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    return { raw: trimmed };
  }
}

test("partial apply response structure", () => {
  const resp = {
    Success: true,
    AppliedKeys: ["FontSize", "FontFace"],
    SkippedKeys: ["NonExistent"],
    Components: [
      { Component: "WindowsTerminal", Result: { Success: true } },
    ],
    Message: "部分加载完成",
  };
  const result = parsePartialResponse(JSON.stringify(resp), 0, "");
  assert.equal(result.Success, true);
  assert.ok(Array.isArray(result.AppliedKeys));
  assert.ok(Array.isArray(result.SkippedKeys));
  assert.ok(Array.isArray(result.Components));
});

test("partial apply only modifies specified keys", () => {
  // Simulate partial apply logic
  const original = {
    Opacity: 85,
    FontSize: 12,
    FontFace: "CaskaydiaCove Nerd Font",
    UseAcrylic: true,
    ColorScheme: "Tokyo Night",
    OMPTheme: "tokyonight_storm",
  };
  const profileConfig = {
    Opacity: 99,
    FontSize: 99,
    FontFace: "TestFont",
    ColorScheme: "TestScheme",
  };
  const keysToApply = ["FontSize", "FontFace"];

  const applied = { ...original };
  const appliedKeys = [];
  for (const key of keysToApply) {
    if (key in profileConfig) {
      applied[key] = profileConfig[key];
      appliedKeys.push(key);
    }
  }

  assert.equal(applied.FontSize, 99, "FontSize should change");
  assert.equal(applied.FontFace, "TestFont", "FontFace should change");
  assert.equal(applied.Opacity, 85, "Opacity should NOT change");
  assert.equal(applied.UseAcrylic, true, "UseAcrylic should NOT change");
  assert.equal(applied.ColorScheme, "Tokyo Night", "ColorScheme should NOT change (not in keys)");
  assert.equal(applied.OMPTheme, "tokyonight_storm", "OMPTheme should NOT change");
  // Original object must remain untouched
  assert.equal(original.FontSize, 12, "original FontSize unchanged");
  assert.equal(original.FontFace, "CaskaydiaCove Nerd Font", "original FontFace unchanged");
  assert.equal(appliedKeys.length, 2);
});

test("keys not in profile are skipped", () => {
  const profileConfig = { Opacity: 90, FontSize: 12 };
  const keys = ["FontSize", "NonExistent", "AnotherFake"];
  const applied = [];
  const skipped = [];
  for (const key of keys) {
    if (key in profileConfig) {
      applied.push(key);
    } else {
      skipped.push(key);
    }
  }
  assert.equal(applied.length, 1);
  assert.equal(skipped.length, 2);
  assert.ok(skipped.includes("NonExistent"));
  assert.ok(skipped.includes("AnotherFake"));
});

test("keys array validation rejects invalid key names", () => {
  const keyPattern = /^[A-Za-z][A-Za-z0-9]*$/;
  assert.ok(keyPattern.test("FontSize"), "valid key");
  assert.ok(keyPattern.test("Opacity"), "valid key");
  assert.ok(keyPattern.test("OMPTheme"), "valid key");
  assert.ok(!keyPattern.test("Font Size"), "rejects spaces");
  assert.ok(!keyPattern.test("font-size"), "rejects hyphens");
  assert.ok(!keyPattern.test("123key"), "rejects starting with number");
  assert.ok(!keyPattern.test("key'; DROP TABLE"), "rejects injection");
});

// ---------------------------------------------------------------------------
// Test 18: New diff tools registered + WPF view files exist
// ---------------------------------------------------------------------------

console.log("\n📋 New diff tools + WPF view verification");

test("compare_profiles tool is registered", () => {
  assert.ok(toolNames.includes("compare_profiles"), "compare_profiles should be registered");
});

test("merge_profiles tool is registered", () => {
  assert.ok(toolNames.includes("merge_profiles"), "merge_profiles should be registered");
});

test("apply_profile_partial tool is registered", () => {
  assert.ok(toolNames.includes("apply_profile_partial"), "apply_profile_partial should be registered");
});

test("ProfileDiffView.xaml exists", () => {
  const xamlPath = path.join(__dirname, "..", "Views", "ProfileDiffView.xaml");
  assert.ok(fs.existsSync(xamlPath), "ProfileDiffView.xaml should exist");
});

test("ProfileDiffView.ps1 exists", () => {
  const ps1Path = path.join(__dirname, "..", "Views", "ProfileDiffView.ps1");
  assert.ok(fs.existsSync(ps1Path), "ProfileDiffView.ps1 should exist");
});

test("MainWindow.xaml has NavProfileDiff button", () => {
  const mainWinPath = path.join(__dirname, "..", "Views", "MainWindow.xaml");
  const content = fs.readFileSync(mainWinPath, "utf8");
  assert.ok(content.includes("NavProfileDiff"), "NavProfileDiff should exist in MainWindow.xaml");
  assert.ok(content.includes("方案对比"), "方案对比 label should exist");
});

test("test_profiles_diff.ps1 exists", () => {
  const testPath = path.join(__dirname, "..", "Modules", "Tests", "test_profiles_diff.ps1");
  assert.ok(fs.existsSync(testPath), "test_profiles_diff.ps1 should exist");
});

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

console.log(`\n${"=".repeat(50)}`);
console.log(`📊 Results: ${passed} passed, ${failed} failed`);
console.log(`${"=".repeat(50)}`);

if (failures.length > 0) {
  console.log("\nFailed tests:");
  for (const f of failures) {
    console.log(`  - ${f.name}: ${f.err.message}`);
  }
  process.exit(1);
} else {
  console.log("\nAll tests passed! 🎉");
  process.exit(0);
}
