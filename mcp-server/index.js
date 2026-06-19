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
  constants: `Import-Module '${MODULES_DIR}/Constants.psm1' -Force`,
  detection: `Import-Module '${MODULES_DIR}/Detection.psm1' -Force`,
  actions: `Import-Module '${MODULES_DIR}/Actions.psm1' -Force`,
  profiles: `Import-Module '${MODULES_DIR}/Profiles.psm1' -Force`,
  healthcheck: `Import-Module '${MODULES_DIR}/HealthCheck.psm1' -Force`,
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

// ---------------------------------------------------------------------------
// list_profiles - List all saved configuration profiles
// ---------------------------------------------------------------------------

server.tool(
  "list_profiles",
  "列出所有已保存的配置方案",
  {},
  async () => {
    try {
      const preamble = psPreamble("profiles");
      const script = `${preamble}; Get-Profiles | ConvertTo-Json -Depth 5`;
      const { stdout, stderr, exitCode } = await runPS(script);

      if (exitCode !== 0) {
        return errorContent(stderr || `获取方案列表失败 (exit code ${exitCode})`);
      }

      const trimmed = stdout.trim();
      if (!trimmed || trimmed === "[]") {
        return textContent({ profiles: [], message: "暂无保存的配置方案" });
      }

      try {
        const parsed = JSON.parse(trimmed);
        const profiles = Array.isArray(parsed) ? parsed : [parsed];
        if (profiles.length === 0) {
          return textContent({ profiles: [], message: "暂无保存的配置方案" });
        }
        return textContent({ profiles });
      } catch {
        return textContent({ profiles: [], message: "暂无保存的配置方案", raw: trimmed });
      }
    } catch (err) {
      return errorContent(err.message);
    }
  }
);

// ---------------------------------------------------------------------------
// save_profile - Save current config as a named profile
// ---------------------------------------------------------------------------

server.tool(
  "save_profile",
  "将当前配置保存为命名方案",
  {
    name: z.string().describe("方案名称"),
    notes: z.string().optional().describe("方案备注说明"),
  },
  async ({ name, notes }) => {
    try {
      validateSafe(name, "name");
      if (notes !== undefined && notes.length > 500) {
        return errorContent("notes 内容过长（最大 500 字符）");
      }

      // Escape single quotes in notes for PowerShell string safety
      const safeNotes = notes !== undefined ? String(notes).replace(/'/g, "''") : "";

      const preamble = psPreamble("profiles");
      const script = `${preamble}; Save-Profile -Name '${name}' -Notes '${safeNotes}' | ConvertTo-Json -Depth 5`;
      const { stdout, stderr, exitCode } = await runPS(script);

      if (exitCode !== 0) {
        return errorContent(stderr || `保存方案失败 (exit code ${exitCode})`);
      }

      const trimmed = stdout.trim();
      try {
        const result = JSON.parse(trimmed);
        if (result.Success === false) {
          return errorContent(result.Message || "保存方案失败");
        }
        return textContent({
          success: true,
          name,
          message: result.Message || `方案 "${name}" 保存成功`,
        });
      } catch {
        return textContent({ success: true, name, raw: trimmed });
      }
    } catch (err) {
      return errorContent(err.message);
    }
  }
);

// ---------------------------------------------------------------------------
// load_profile - Load a named profile and apply its config
// ---------------------------------------------------------------------------

server.tool(
  "load_profile",
  "加载指定配置方案并应用",
  {
    name: z.string().describe("要加载的方案名称"),
  },
  async ({ name }) => {
    try {
      validateSafe(name, "name");

      const preamble = psPreamble("profiles", "detection", "actions");
      const script = [
        preamble,
        `$result = Load-Profile -Name '${name}'`,
        "if ($result.Success) {",
        "  Update-ComponentStatus",
        "  $config = Get-AppConfig",
        "  @{ Success = $true; Config = $config } | ConvertTo-Json -Depth 5",
        "} else {",
        "  $result | ConvertTo-Json -Depth 5",
        "}",
      ].join("; ");

      const { stdout, stderr, exitCode } = await runPS(script);

      if (exitCode !== 0) {
        return errorContent(stderr || `加载方案失败 (exit code ${exitCode})`);
      }

      const trimmed = stdout.trim();
      try {
        const result = JSON.parse(trimmed);
        if (result.Success === false) {
          return errorContent(result.Message || `方案 "${name}" 加载失败`);
        }
        return textContent({
          success: true,
          name,
          config: result.Config || {},
          message: `方案 "${name}" 已加载并应用`,
        });
      } catch {
        return textContent({ success: true, name, raw: trimmed });
      }
    } catch (err) {
      return errorContent(err.message);
    }
  }
);

// ---------------------------------------------------------------------------
// diagnose_component - Diagnose a component's installation status and issues
// ---------------------------------------------------------------------------

const DIAGNOSE_COMPONENTS = ["OhMyPosh", "NerdFont", "WindowsTerminal", "WTConfig", "PSProfile", "StatusLine"];

server.tool(
  "diagnose_component",
  "诊断指定组件的安装状态和常见问题",
  {
    component: z
      .enum(DIAGNOSE_COMPONENTS)
      .describe("要诊断的组件名称，如 OhMyPosh、NerdFont、WindowsTerminal、PSProfile"),
  },
  async ({ component }) => {
    try {
      const preamble = psPreamble("detection", "constants");
      const script = buildDiagnoseScript(preamble, component);
      const { stdout, stderr, exitCode } = await runPS(script);

      if (exitCode !== 0) {
        return errorContent(stderr || `诊断失败 (exit code ${exitCode})`);
      }

      const trimmed = stdout.trim();
      try {
        const result = JSON.parse(trimmed);
        return textContent(result);
      } catch {
        return textContent({ component, installed: false, raw: trimmed });
      }
    } catch (err) {
      return errorContent(err.message);
    }
  }
);

/**
 * Build a PowerShell script that diagnoses a specific component and
 * returns a detailed JSON result.
 *
 * @param {string} preamble - Module import preamble.
 * @param {string} component - Component key name.
 * @returns {string} PowerShell script string.
 */
function buildDiagnoseScript(preamble, component) {
  const comp = component;

  // Component-specific diagnostic blocks. Each sets:
  //   $compInstalled, $compVersion, $compConfigPath, $configExists, $issues, $tips
  let perCompBlock = "";

  switch (comp) {
    case "OhMyPosh":
      perCompBlock = `
        $compInstalled = $app.Components.OhMyPosh.Installed
        $compVersion   = $app.Components.OhMyPosh.Version
        $compConfigPath = ""
        $configExists   = $false
        $issues = @()
        $tips   = @()

        # Check profile for omp init (PSProfile also checks this but we do a quick version here)
        $profilePaths = @(
          (Join-Path $env:USERPROFILE "Documents\\PowerShell\\Microsoft.PowerShell_profile.ps1"),
          (Join-Path $env:USERPROFILE "Documents\\WindowsPowerShell\\Microsoft.PowerShell_profile.ps1")
        )
        $ompInProfile = $false
        foreach ($pp in $profilePaths) {
          if (Test-Path $pp) {
            $content = Get-Content -Path $pp -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($content -match "oh-my-posh init") { $ompInProfile = $true; break }
          }
        }

        if (-not $compInstalled) {
          $issues += "oh-my-posh 命令未找到，组件未安装"
          $tips   += "运行 install_component 工具安装 OhMyPosh，或手动执行: winget install oh-my-posh"
        } elseif (-not $ompInProfile) {
          $issues += "Oh My Posh 已安装但 PowerShell Profile 中未初始化"
          $tips   += "安装 PSProfile 组件以自动配置，或手动在 Profile 中添加 oh-my-posh init 命令"
        }

        if ($compInstalled -and -not $env:POSH_THEMES_PATH) {
          $tips += "环境变量 POSH_THEMES_PATH 未设置，可能影响主题加载"
        }
      `;
      break;

    case "NerdFont":
      perCompBlock = `
        $compInstalled = $app.Components.NerdFont.Installed
        $compVersion   = $app.Components.NerdFont.Version
        $compConfigPath = "C:\\Windows\\Fonts"
        $configExists   = (Test-Path "C:\\Windows\\Fonts")
        $issues = @()
        $tips   = @()

        if (-not $compInstalled) {
          $issues += "未检测到 Caskaydia Cove Nerd Font 字体"
          $tips   += "运行 install_component 工具安装 NerdFont，需要管理员权限"
          $tips   += "或手动下载: https://github.com/ryanoasis/nerd-fonts/releases"
        }

        # Check if WT config references a nerd font
        $wtSettingsPath = Get-WTSettingsPath
        $wtSettings = Read-JsonFile $wtSettingsPath
        if ($null -ne $wtSettings -and $wtSettings.profiles -and $wtSettings.profiles.defaults -and $wtSettings.profiles.defaults.font -and $wtSettings.profiles.defaults.font.face) {
          $fontFace = $wtSettings.profiles.defaults.font.face
          if ($fontFace -notmatch "Nerd|Caskaydia|NF") {
            if ($compInstalled) {
              $issues += "Nerd Font 已安装但 Windows Terminal 配置中使用的字体不是 Nerd Font: $fontFace"
              $tips   += "在 Windows Terminal 设置中将字体改为 CaskaydiaCove Nerd Font 以正确显示图标"
            }
          }
        }
      `;
      break;

    case "WindowsTerminal":
      perCompBlock = `
        $compInstalled = $app.Components.WinTerminal.Installed
        $compVersion   = $app.Components.WinTerminal.Version
        $compConfigPath = Get-WTSettingsPath
        $configExists   = (Test-Path $compConfigPath)
        $issues = @()
        $tips   = @()

        if (-not $compInstalled) {
          $issues += "未检测到 Windows Terminal (wt 命令)"
          $tips   += "运行 install_component 工具安装 WinTerminal，或从 Microsoft Store 安装"
        } elseif (-not $configExists) {
          $issues += "Windows Terminal 已安装但找不到 settings.json 配置文件"
          $tips   += "启动一次 Windows Terminal 以生成默认配置文件，路径: $compConfigPath"
        }
      `;
      break;

    case "WTConfig":
      perCompBlock = `
        $wtSettingsPath = Get-WTSettingsPath
        $wtSettings = Read-JsonFile $wtSettingsPath
        $compInstalled = $app.Components.WTConfig.Installed
        $compVersion   = $app.Components.WTConfig.Theme
        $compConfigPath = $wtSettingsPath
        $configExists   = (Test-Path $wtSettingsPath)
        $issues = @()
        $tips   = @()

        if (-not $configExists) {
          $issues += "找不到 Windows Terminal 配置文件: $wtSettingsPath"
          $tips   += "请先安装 Windows Terminal 并启动一次以生成配置"
        } elseif (-not $compInstalled) {
          $issues += "Windows Terminal 配置中未设置美化主题"
          $tips   += "运行 apply_config 工具或在 WPF 管理器中应用 Tokyo Night 主题"
        }

        # Check Tokyo Night scheme
        if ($configExists -and $null -ne $wtSettings) {
          $hasTokyoNight = $false
          if ($wtSettings.schemes -and $wtSettings.schemes -is [System.Collections.IList]) {
            foreach ($s in $wtSettings.schemes) {
              if ($s.name -eq "Tokyo Night") { $hasTokyoNight = $true; break }
            }
          }
          if ($compInstalled -and -not $hasTokyoNight) {
            $issues += "配色方案标记为已配置但 schemes 数组中未找到 Tokyo Night"
            $tips   += "可能配置已被手动修改，建议重新应用配置"
          }
        }
      `;
      break;

    case "PSProfile":
      perCompBlock = `
        $compInstalled = $app.Components.PSProfile.Installed
        $compVersion   = $app.Components.PSProfile.Theme
        $profilePaths = @(
          (Join-Path $env:USERPROFILE "Documents\\PowerShell\\Microsoft.PowerShell_profile.ps1"),
          (Join-Path $env:USERPROFILE "Documents\\WindowsPowerShell\\Microsoft.PowerShell_profile.ps1")
        )
        $compConfigPath = $profilePaths -join ";"
        $configExists   = $false
        foreach ($pp in $profilePaths) { if (Test-Path $pp) { $configExists = $true; break } }
        $issues = @()
        $tips   = @()

        if (-not $compInstalled) {
          $issues += "PowerShell Profile 中未配置 oh-my-posh 初始化"
          $tips   += "运行 install_component 工具安装 PSProfile"
          $tips   += "或手动编辑 $($profilePaths[0]) 添加 oh-my-posh init 命令"
        }

        # Check if oh-my-posh is actually installed
        $ompCmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
        if ($compInstalled -and $null -eq $ompCmd) {
          $issues += "Profile 中有 oh-my-posh 配置但命令本身未安装"
          $tips   += "请先安装 OhMyPosh 组件，否则启动 PowerShell 时会报错"
        }
      `;
      break;

    case "StatusLine":
      perCompBlock = `
        $compInstalled = $app.Components.StatusLine.Installed
        $compVersion   = if ($compInstalled) { "Active" } else { "" }
        $scriptPath = Join-Path $env:USERPROFILE ".claude\\statusline-command.sh"
        $settingsPath = Join-Path $env:USERPROFILE ".claude\\settings.json"
        $compConfigPath = $scriptPath
        $scriptExists = Test-Path $scriptPath
        $settingsExists = Test-Path $settingsPath
        $configExists = $scriptExists -or $settingsExists
        $issues = @()
        $tips   = @()

        if (-not $compInstalled) {
          $issues += "Claude Code 状态栏未配置"
          $tips   += "运行 install_component 工具安装 StatusLine"
        } else {
          if (-not $scriptExists) {
            $issues += "statusline-command.sh 脚本不存在"
            $tips   += "状态栏命令脚本缺失，状态栏可能无法正常工作"
          }
          if (-not $settingsExists) {
            $issues += "Claude Code settings.json 不存在"
            $tips   += "状态栏配置依赖 settings.json 中的 statusLine 字段"
          }
        }
      `;
      break;

    default:
      perCompBlock = `
        $compInstalled = $false
        $compVersion   = ""
        $compConfigPath = ""
        $configExists   = $false
        $issues = @("不支持的组件: ${comp}")
        $tips   = @()
      `;
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
      configExists = $configExists
      issues     = $issues
      tips       = $tips
      description = $app.Components.${comp}.Description
    }
    $result | ConvertTo-Json -Depth 5
  `;
}

// ---------------------------------------------------------------------------
// health_check — Run full system health diagnostics
// ---------------------------------------------------------------------------

server.tool(
  "health_check",
  "运行全系统组件健康诊断，返回各组件的详细检查结果、警告和可修复项",
  {
    component: z
      .string()
      .optional()
      .describe("指定单个组件进行诊断（可选），不填则诊断全部组件"),
  },
  async ({ component }) => {
    try {
      const preamble = psPreamble("healthcheck", "detection", "actions", "constants");

      let script;
      if (component && component.trim()) {
        validateSafe(component, "component");
        script = `${preamble}; Test-ComponentHealth -ComponentName '${component}' | ConvertTo-Json -Depth 10`;
      } else {
        script = `${preamble}; Get-SystemDiagnostics | ConvertTo-Json -Depth 10`;
      }

      const { stdout, stderr, exitCode } = await runPS(script);

      if (exitCode !== 0) {
        return errorContent(stderr || `健康检查失败 (exit code ${exitCode})`);
      }

      const trimmed = stdout.trim();
      try {
        const result = JSON.parse(trimmed);
        return textContent(result);
      } catch {
        return textContent({ raw: trimmed, note: "无法解析诊断结果为 JSON" });
      }
    } catch (err) {
      return errorContent(err.message);
    }
  }
);

// ---------------------------------------------------------------------------
// repair_component — Auto-repair a specific component issue
// ---------------------------------------------------------------------------

server.tool(
  "repair_component",
  "自动修复指定组件的特定问题（FixId 来自 health_check 返回的 Fixes 列表）",
  {
    component: z
      .enum(["OhMyPosh", "NerdFont", "WindowsTerminal", "PSProfile", "StatusBar"])
      .describe("要修复的组件名称"),
    fixId: z.string().describe("修复项 ID，从 health_check 的 Fixes 列表中获取"),
  },
  async ({ component, fixId }) => {
    try {
      // fixId 允许包含下划线和字母数字，做宽松校验
      if (!/^[a-zA-Z0-9_\-]+$/.test(fixId)) {
        return errorContent("fixId 包含无效字符，仅允许字母、数字、下划线和连字符");
      }
      if (fixId.length > 100) {
        return errorContent("fixId 过长");
      }

      const preamble = psPreamble("healthcheck", "detection", "actions", "constants");
      const script = `${preamble}; Repair-Component -ComponentName '${component}' -FixId '${fixId}' | ConvertTo-Json -Depth 5`;
      const { stdout, stderr, exitCode } = await runPS(script);

      if (exitCode !== 0) {
        return errorContent(stderr || `修复失败 (exit code ${exitCode})`);
      }

      const trimmed = stdout.trim();
      try {
        const result = JSON.parse(trimmed);
        if (result.Success === false) {
          return errorContent(result.Message || "修复失败");
        }
        return textContent({
          success: true,
          component,
          fixId,
          message: result.Message || "修复成功",
          backupPath: result.BackupPath || "",
        });
      } catch {
        return textContent({ success: true, component, fixId, raw: trimmed });
      }
    } catch (err) {
      return errorContent(err.message);
    }
  }
);

// ---------------------------------------------------------------------------
// compare_profiles — Compare two configuration profiles
// ---------------------------------------------------------------------------

server.tool(
  "compare_profiles",
  "对比两个配置方案的差异，返回差异字段、相同字段和仅存在于单方的字段",
  {
    name1: z.string().describe("第一个方案的名称"),
    name2: z.string().describe("第二个方案的名称"),
  },
  async ({ name1, name2 }) => {
    try {
      validateSafe(name1, "name1");
      validateSafe(name2, "name2");

      const preamble = psPreamble("profiles");
      const script = `${preamble}; Compare-Profiles -Name1 '${name1}' -Name2 '${name2}' | ConvertTo-Json -Depth 10`;
      const { stdout, stderr, exitCode } = await runPS(script);

      if (exitCode !== 0) {
        return errorContent(stderr || `对比失败 (exit code ${exitCode})`);
      }

      const trimmed = stdout.trim();
      try {
        const result = JSON.parse(trimmed);
        if (result.Success === false) {
          return errorContent(result.Message || "对比失败");
        }
        return textContent(result);
      } catch {
        return textContent({ raw: trimmed });
      }
    } catch (err) {
      return errorContent(err.message);
    }
  }
);

// ---------------------------------------------------------------------------
// merge_profiles — Merge two profiles into a new one
// ---------------------------------------------------------------------------

server.tool(
  "merge_profiles",
  "合并两个配置方案生成新方案，支持优先使用方案A/B或手动选择",
  {
    name1: z.string().describe("第一个方案的名称"),
    name2: z.string().describe("第二个方案的名称"),
    new_name: z.string().describe("新方案的名称"),
    strategy: z
      .enum(["prefer_first", "prefer_second", "manual"])
      .describe("合并策略：prefer_first(优先方案A)、prefer_second(优先方案B)、manual(手动模式仅返回差异)"),
  },
  async ({ name1, name2, new_name, strategy }) => {
    try {
      validateSafe(name1, "name1");
      validateSafe(name2, "name2");
      validateSafe(new_name, "new_name");

      const preamble = psPreamble("profiles", "detection", "actions");
      const script = `${preamble}; Merge-Profiles -Name1 '${name1}' -Name2 '${name2}' -NewName '${new_name}' -Strategy '${strategy}' | ConvertTo-Json -Depth 10`;
      const { stdout, stderr, exitCode } = await runPS(script);

      if (exitCode !== 0) {
        return errorContent(stderr || `合并失败 (exit code ${exitCode})`);
      }

      const trimmed = stdout.trim();
      try {
        const result = JSON.parse(trimmed);
        if (result.Success === false) {
          return errorContent(result.Message || "合并失败");
        }
        return textContent(result);
      } catch {
        return textContent({ raw: trimmed });
      }
    } catch (err) {
      return errorContent(err.message);
    }
  }
);

// ---------------------------------------------------------------------------
// apply_profile_partial — Partially apply a profile (specific keys only)
// ---------------------------------------------------------------------------

server.tool(
  "apply_profile_partial",
  "部分加载配置方案，仅覆盖指定的配置字段，其他保持不变",
  {
    name: z.string().describe("要加载的方案名称"),
    keys: z
      .array(z.string())
      .describe("要应用的配置字段名数组，如 [\"FontSize\", \"FontFace\", \"Opacity\"]"),
  },
  async ({ name, keys }) => {
    try {
      validateSafe(name, "name");

      // Validate each key (alphanumeric + underscores, reasonable length)
      for (const key of keys) {
        if (!/^[A-Za-z][A-Za-z0-9]*$/.test(key)) {
          return errorContent(`无效的配置字段名: ${key}`);
        }
        if (key.length > 50) {
          return errorContent(`字段名过长: ${key}`);
        }
      }

      // Build PowerShell array from keys
      const keysArray = keys.map(k => `'${k}'`).join(", ");

      const preamble = psPreamble("profiles", "detection", "actions", "constants");
      const script = `${preamble}; Apply-ProfilePartial -Name '${name}' -Keys @(${keysArray}) | ConvertTo-Json -Depth 10`;
      const { stdout, stderr, exitCode } = await runPS(script);

      if (exitCode !== 0) {
        return errorContent(stderr || `部分加载失败 (exit code ${exitCode})`);
      }

      const trimmed = stdout.trim();
      try {
        const result = JSON.parse(trimmed);
        if (result.Success === false) {
          return errorContent(result.Message || "部分加载失败");
        }
        return textContent(result);
      } catch {
        return textContent({ raw: trimmed });
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
