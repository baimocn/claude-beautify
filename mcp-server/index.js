/**
 * MCP Server for Claude Terminal Beautify
 *
 * Exposes beautifier operations (install/uninstall/configure) as MCP tools.
 * Communicates via stdio transport.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { execFile } from "child_process";
import { fileURLToPath } from "url";
import path from "path";
import { z } from "zod";

// ---------------------------------------------------------------------------
// Server instance
// ---------------------------------------------------------------------------

const server = new McpServer({
  name: "claude-beautify",
  version: "1.0.0",
});

// ---------------------------------------------------------------------------
// Absolute paths to PowerShell modules
// ---------------------------------------------------------------------------

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const MODULES_DIR = path.join(__dirname, "..", "Modules");

const MODULE_IMPORTS = {
  utils: `Import-Module '${MODULES_DIR}/Utils.psm1' -Force`,
  state: `Import-Module '${MODULES_DIR}/State.psm1' -Force`,
  detection: `Import-Module '${MODULES_DIR}/Detection.psm1' -Force`,
  actions: `Import-Module '${MODULES_DIR}/Actions.psm1' -Force`,
};

// ---------------------------------------------------------------------------
// Helper: run a PowerShell script and return structured result
// ---------------------------------------------------------------------------

/**
 * Execute a PowerShell script string via `powershell.exe`.
 *
 * @param {string} script - The PowerShell script to execute.
 * @returns {Promise<{stdout: string, stderr: string, exitCode: number}>}
 */
function runPS(script) {
  return new Promise((resolve, reject) => {
    execFile(
      "powershell",
      ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
      { encoding: "utf8", timeout: 60_000 },
      (error, stdout, stderr) => {
        if (error && error.killed) {
          reject(new Error("PowerShell process timed out after 60 seconds"));
          return;
        }
        resolve({
          stdout: stdout ?? "",
          stderr: stderr ?? "",
          exitCode: error ? error.code ?? 1 : 0,
        });
      }
    );
  });
}

// ---------------------------------------------------------------------------
// Helper: build a common import preamble for a given module set
// ---------------------------------------------------------------------------

/**
 * Build a PowerShell preamble that imports the requested modules in the
 * correct dependency order (Utils -> State -> everything else).
 *
 * @param  {...string} moduleKeys - Keys from MODULE_IMPORTS to include.
 * @returns {string} Import statements separated by "; ".
 */
function psPreamble(...moduleKeys) {
  // Always import Utils and State first as they are base dependencies.
  const ordered = ["utils", "state", ...moduleKeys.filter(
    (k) => k !== "utils" && k !== "state"
  )];
  const unique = [...new Set(ordered)];
  return unique.map((k) => MODULE_IMPORTS[k]).join("; ");
}

// ---------------------------------------------------------------------------
// Helper: wrap a tool handler result into MCP content format
// ---------------------------------------------------------------------------

/** @param {any} data */
function textContent(data) {
  const text = typeof data === "string" ? data : JSON.stringify(data, null, 2);
  return { content: [{ type: "text", text }] };
}

/** @param {string} message */
function errorContent(message) {
  return { content: [{ type: "text", text: `Error: ${message}` }] };
}

// ===========================================================================
// Input validation
// ===========================================================================

/**
 * Validate that a user-provided string contains only safe characters
 * to prevent PowerShell command injection.
 *
 * @param {string} value - The value to validate.
 * @param {string} fieldName - The field name for error messages.
 * @returns {string} The validated value.
 */
function validateSafe(value, fieldName) {
  if (typeof value !== "string") throw new Error(`${fieldName} must be a string`);
  if (!/^[a-zA-Z0-9_\-\.]+$/.test(value)) throw new Error(`${fieldName} contains invalid characters: ${value}`);
  if (value.length > 100) throw new Error(`${fieldName} too long`);
  return value;
}

// ---------------------------------------------------------------------------
// Component name -> PowerShell function mappings
// ---------------------------------------------------------------------------

const INSTALL_MAP = {
  OhMyPosh: "Install-OhMyPosh",
  NerdFont: "Install-NerdFont",
  WinTerminal: "Install-WindowsTerminal",
  WTConfig: "Apply-WTSettings",
  PSProfile: "Apply-PSProfile",
  StatusLine: "Install-StatusLine",
};

const UNINSTALL_MAP = {
  OhMyPosh: "Uninstall-OhMyPosh",
  NerdFont: "Uninstall-NerdFont",
  WinTerminal: "Uninstall-WindowsTerminal",
  WTConfig: "Uninstall-WTConfig",
  PSProfile: "Uninstall-PSProfile",
  StatusLine: "Uninstall-StatusLine",
};

// ===========================================================================
// Tools
// ===========================================================================

// ---------------------------------------------------------------------------
// get_status - Get installation status of all components
// ---------------------------------------------------------------------------

server.tool(
  "get_status",
  "获取所有组件的安装状态",
  {},
  async () => {
    try {
      const preamble = psPreamble("detection");
      const script = `${preamble}; Update-ComponentStatus; Get-AppData | ConvertTo-Json -Depth 5`;
      const { stdout, stderr, exitCode } = await runPS(script);

      if (exitCode !== 0) {
        return errorContent(stderr || `PowerShell exited with code ${exitCode}`);
      }

      // stdout may be empty or contain JSON
      const trimmed = stdout.trim();
      if (!trimmed) {
        return textContent({ message: "No data returned from Get-AppData" });
      }

      try {
        return textContent(JSON.parse(trimmed));
      } catch {
        // If it's not valid JSON, return as plain text
        return textContent(trimmed);
      }
    } catch (err) {
      return errorContent(err.message);
    }
  }
);

// ---------------------------------------------------------------------------
// install_component - Install a beautifier component
// ---------------------------------------------------------------------------

server.tool(
  "install_component",
  "安装指定的美化组件",
  {
    component: z
      .enum(["OhMyPosh", "NerdFont", "WinTerminal", "WTConfig", "PSProfile", "StatusLine"])
      .describe("要安装的组件名称"),
  },
  async ({ component }) => {
    try {
      const preamble = psPreamble("actions");
      const fn = INSTALL_MAP[component];
      if (!fn) return errorContent(`Unknown component: ${component}`);
      const script = `${preamble}; ${fn}`;
      const { stdout, stderr, exitCode } = await runPS(script);

      if (exitCode !== 0) {
        return errorContent(stderr || `安装 ${component} 失败 (exit code ${exitCode})`);
      }

      return textContent({
        success: true,
        component,
        message: stdout.trim() || `${component} 安装完成`,
      });
    } catch (err) {
      return errorContent(err.message);
    }
  }
);

// ---------------------------------------------------------------------------
// uninstall_component - Uninstall a beautifier component
// ---------------------------------------------------------------------------

server.tool(
  "uninstall_component",
  "卸载指定的美化组件",
  {
    component: z
      .enum(["OhMyPosh", "NerdFont", "WinTerminal", "WTConfig", "PSProfile", "StatusLine"])
      .describe("要卸载的组件名称"),
  },
  async ({ component }) => {
    try {
      const preamble = psPreamble("actions");
      const fn = UNINSTALL_MAP[component];
      if (!fn) return errorContent(`Unknown component: ${component}`);
      const script = `${preamble}; ${fn}`;
      const { stdout, stderr, exitCode } = await runPS(script);

      if (exitCode !== 0) {
        return errorContent(stderr || `卸载 ${component} 失败 (exit code ${exitCode})`);
      }

      return textContent({
        success: true,
        component,
        message: stdout.trim() || `${component} 卸载完成`,
      });
    } catch (err) {
      return errorContent(err.message);
    }
  }
);

// ---------------------------------------------------------------------------
// get_config - Get current terminal configuration
// ---------------------------------------------------------------------------

server.tool(
  "get_config",
  "获取当前终端配置",
  {},
  async () => {
    try {
      const preamble = psPreamble("detection");
      const script = `${preamble}; Update-ComponentStatus; (Get-AppData).Config | ConvertTo-Json -Depth 5`;
      const { stdout, stderr, exitCode } = await runPS(script);

      if (exitCode !== 0) {
        return errorContent(stderr || `获取配置失败 (exit code ${exitCode})`);
      }

      const trimmed = stdout.trim();
      if (!trimmed) {
        return textContent({ message: "No config data returned" });
      }

      try {
        return textContent(JSON.parse(trimmed));
      } catch {
        return textContent(trimmed);
      }
    } catch (err) {
      return errorContent(err.message);
    }
  }
);

// ---------------------------------------------------------------------------
// apply_config - Apply terminal configuration changes
// ---------------------------------------------------------------------------

server.tool(
  "apply_config",
  "应用终端配置更改",
  {
    opacity: z.number().min(0).max(100).optional().describe("窗口不透明度 (0-100)"),
    fontSize: z.number().min(8).max(24).optional().describe("字体大小 (8-24)"),
    useAcrylic: z.boolean().optional().describe("是否启用亚克力效果"),
    cursorShape: z.string().optional().describe("光标形状"),
    colorScheme: z.string().optional().describe("配色方案名称"),
    ompTheme: z.string().optional().describe("Oh My Posh 主题名称"),
  },
  async (params) => {
    try {
      const preamble = psPreamble("actions", "detection");
      const { opacity, fontSize, useAcrylic, cursorShape, colorScheme, ompTheme } = params;

      // Validate string inputs to prevent command injection
      if (cursorShape !== undefined) validateSafe(cursorShape, "cursorShape");
      if (colorScheme !== undefined) validateSafe(colorScheme, "colorScheme");
      if (ompTheme !== undefined) validateSafe(ompTheme, "ompTheme");

      // Build a script that updates config fields and applies settings.
      // We load current AppData, mutate the Config object, save it back,
      // then call the appropriate Apply functions.
      const updates = [];
      if (opacity !== undefined) updates.push(`$app.Config.Opacity = ${opacity}`);
      if (fontSize !== undefined) updates.push(`$app.Config.FontSize = ${fontSize}`);
      if (useAcrylic !== undefined) updates.push(`$app.Config.UseAcrylic = $${useAcrylic}`);
      if (cursorShape !== undefined) updates.push(`$app.Config.CursorShape = '${cursorShape}'`);
      if (colorScheme !== undefined) updates.push(`$app.Config.ColorScheme = '${colorScheme}'`);
      if (ompTheme !== undefined) updates.push(`$app.Config.OmpTheme = '${ompTheme}'`);

      const updateBlock = updates.join("; ");

      // Apply WT settings for visual properties; Apply-PSProfile for theme changes
      const applyCalls = [];
      const hasWTChanges =
        opacity !== undefined ||
        fontSize !== undefined ||
        useAcrylic !== undefined ||
        cursorShape !== undefined ||
        colorScheme !== undefined;
      if (hasWTChanges) applyCalls.push("Apply-WTSettings");
      if (ompTheme !== undefined) applyCalls.push("Apply-PSProfile -ThemeName $app.Config.OmpTheme");

      const applyBlock = applyCalls.join("; ");

      const script = [
        preamble,
        "Update-ComponentStatus",
        "$app = Get-AppData",
        updateBlock,
        "Set-AppData -Data $app",
        applyBlock,
        '$app.Config | ConvertTo-Json -Depth 5',
      ].filter(Boolean).join("; ");

      const { stdout, stderr, exitCode } = await runPS(script);

      if (exitCode !== 0) {
        return errorContent(stderr || `应用配置失败 (exit code ${exitCode})`);
      }

      const trimmed = stdout.trim();
      try {
        return textContent({
          success: true,
          config: trimmed ? JSON.parse(trimmed) : params,
        });
      } catch {
        return textContent({ success: true, config: params, raw: trimmed });
      }
    } catch (err) {
      return errorContent(err.message);
    }
  }
);

// ---------------------------------------------------------------------------
// list_omp_themes - List available Oh My Posh themes
// ---------------------------------------------------------------------------

server.tool(
  "list_omp_themes",
  "列出所有可用的 Oh My Posh 主题",
  {},
  async () => {
    try {
      // $env:POSH_THEMES_PATH is set by Oh My Posh; fall back to default path
      const script = [
        "$themeDir = $env:POSH_THEMES_PATH",
        "if (-not $themeDir) { $themeDir = Join-Path $env:LOCALAPPDATA 'Programs/oh-my-posh/themes' }",
        "if (Test-Path $themeDir) {",
        "  Get-ChildItem -Path $themeDir -Filter '*.omp.json' | ",
        "    Select-Object -ExpandProperty BaseName | ",
        "    ForEach-Object { $_ -replace '\\.omp$', '' } | ",
        "    ConvertTo-Json",
        "} else {",
        "  '[]'  ",
        "}",
      ].join("\n");

      const { stdout, stderr, exitCode } = await runPS(script);

      if (exitCode !== 0) {
        return errorContent(stderr || `列出主题失败 (exit code ${exitCode})`);
      }

      const trimmed = stdout.trim();
      if (!trimmed || trimmed === "[]") {
        return textContent({ themes: [], message: "未找到主题文件，请确认 Oh My Posh 已安装" });
      }

      try {
        const parsed = JSON.parse(trimmed);
        const themes = Array.isArray(parsed) ? parsed : [parsed];
        return textContent({ themes });
      } catch {
        return textContent({ themes: [], raw: trimmed });
      }
    } catch (err) {
      return errorContent(err.message);
    }
  }
);

// ---------------------------------------------------------------------------
// apply_omp_theme - Switch Oh My Posh theme
// ---------------------------------------------------------------------------

server.tool(
  "apply_omp_theme",
  "切换 Oh My Posh 主题",
  {
    theme: z.string().describe("主题名称，如 'tokyonight_storm'"),
  },
  async ({ theme }) => {
    try {
      validateSafe(theme, "theme");
      const preamble = psPreamble("actions", "detection");
      const script = [
        preamble,
        "Update-ComponentStatus",
        "$app = Get-AppData",
        `$app.Config.OmpTheme = '${theme}'`,
        "Set-AppData -Data $app",
        "Apply-PSProfile -ThemeName $app.Config.OmpTheme",
        `$app.Config | ConvertTo-Json -Depth 5`,
      ].join("; ");

      const { stdout, stderr, exitCode } = await runPS(script);

      if (exitCode !== 0) {
        return errorContent(stderr || `切换主题失败 (exit code ${exitCode})`);
      }

      const trimmed = stdout.trim();
      try {
        return textContent({
          success: true,
          theme,
          config: trimmed ? JSON.parse(trimmed) : null,
        });
      } catch {
        return textContent({ success: true, theme, raw: trimmed });
      }
    } catch (err) {
      return errorContent(err.message);
    }
  }
);

// ===========================================================================
// Start server via stdio transport
// ===========================================================================

const transport = new StdioServerTransport();
await server.connect(transport);
