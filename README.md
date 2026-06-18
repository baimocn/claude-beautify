# Claude Code Terminal Beautify

> 一键美化 Claude Code 终端：可视化管理器 + 状态栏 + Oh My Posh + Nerd Font + Tokyo Night

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Windows%2010%2F11-blue?style=flat-square" />
  <img src="https://img.shields.io/badge/PowerShell-5.1+-blue?style=flat-square" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" />
  <img src="https://img.shields.io/badge/Version-1.0.0-orange?style=flat-square" />
</p>

## ✨ 功能特性

### 🖥️ 可视化管理器（WPF 桌面应用）
- **仪表盘** — 一目了然查看所有组件安装状态
- **组件管理** — 勾选式安装/卸载，支持批量操作
- **设置面板** — 滑块实时调参（透明度、字体、光标），带终端预览
- **主题切换** — 浏览 140+ Oh My Posh 主题，实时预览
- **配置方案** — 保存/加载/导入/导出多套配置

### 🎨 美化组件
| 组件 | 说明 |
|------|------|
| **Oh My Posh** | PowerShell 彩色提示符引擎，显示目录、Git 状态、时间 |
| **Tokyo Night Storm** | 深蓝黑 + 柔和高对比主题 |
| **Cascadia Code Nerd Font** | 带图标的等宽字体，支持连字和 Nerd Font 图标 |
| **Windows Terminal 配置** | Tokyo Night 配色 + 亚克力透明 + 自定义光标 |
| **PowerShell Profile** | Oh My Posh 主题 + PSReadLine 历史预测 |
| **Claude Code Status Bar** | 上下文窗口使用量 + Token 消耗 + Git 分支实时监控 |

### 🔌 MCP Server（可选）
内置 MCP Server，让 Claude Code 直接操控美化工具：
```
get_status          — 获取组件安装状态
install_component   — 安装指定组件
uninstall_component — 卸载指定组件
get_config          — 读取当前配置
apply_config        — 应用配置更改
list_omp_themes     — 列出可用主题
apply_omp_theme     — 切换主题
```

## 📦 安装

### 方式一：一键脚本（推荐）

```powershell
# 1. 确保已安装 Chocolatey
Set-ExecutionPolicy Bypass -Scope Process -Force
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# 2. 克隆项目
git clone https://github.com/baimocn/claude-beautify.git
cd claude-beautify

# 3. 运行安装脚本
powershell -ExecutionPolicy Bypass -File install.ps1
```

### 方式二：可视化管理器

```powershell
# 直接启动 GUI 管理器
powershell -ExecutionPolicy Bypass -File ClaudeBeautify.ps1
```

### 方式三：MCP Server（给 Claude Code 用）

在 `~/.claude/.mcp.json` 中添加：
```json
{
  "mcpServers": {
    "beautify": {
      "command": "node",
      "args": ["<项目路径>/mcp-server/index.js"]
    }
  }
}
```

## 🖼️ 效果预览

```
┌─────────────────────────────────────────────────────────────────┐
│  35955@DESKTOP  ~/projects/my-app  main ≡  12:34:56             │  ← Oh My Posh 彩色提示符
│  $ _                                                           │
│                                                                 │
│  Claude Opus 4 | ★ main | my-app | win:1.0M                   │  ← Claude Code 状态栏
│  CTX [########----] 42.5% | in:85.0K out:3.2K cache:72.0K     │
└─────────────────────────────────────────────────────────────────┘
       ↑ Tokyo Night 深蓝黑背景 + 85% 亚克力透明
```

## 📁 项目结构

```
claude-beautify/
├── ClaudeBeautify.ps1          # GUI 管理器入口
├── install.ps1                 # 一键安装脚本
├── uninstall.ps1               # 一键卸载脚本
├── statusline.sh               # Claude Code 状态栏脚本
├── profile.ps1                 # PowerShell Profile 模板
├── terminal-settings.json      # Windows Terminal 配置模板
│
├── Modules/                    # PowerShell 功能模块
│   ├── Utils.psm1              # 工具函数（日志、提权、JSON）
│   ├── State.psm1              # 全局状态管理
│   ├── Detection.psm1          # 组件安装检测
│   ├── Actions.psm1            # 安装/卸载/应用操作
│   ├── Preview.psm1            # 终端预览渲染引擎
│   └── Profiles.psm1           # 配置方案管理
│
├── Views/                      # WPF 视图文件
│   ├── MainWindow.xaml         # 主窗口（侧边栏导航）
│   ├── DashboardView.xaml      # 仪表盘
│   ├── ComponentsView.xaml     # 组件管理
│   ├── ConfigView.xaml         # 设置面板
│   ├── ThemeSwitcherView.xaml  # 主题切换
│   └── ProfilesView.xaml       # 配置方案
│
├── Templates/                  # 默认配置模板
└── mcp-server/                 # MCP Server（Node.js）
    ├── package.json
    └── index.js
```

## ⚙️ 自定义

### 进度条宽度
编辑 `statusline.sh`：
```python
filled = int(pct / 5)   # /5 = 20格, /10 = 10格, /2 = 50格
```

### Oh My Posh 主题
在 GUI 管理器的主题切换页面直接选择，或手动编辑 `profile.ps1`：
```powershell
oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\tokyonight_storm.omp.json" | Invoke-Expression
```

### 透明度 / 字体 / 光标
在 GUI 管理器的设置面板拖动滑块实时调整。

## 🔧 环境要求

- Windows 10/11
- PowerShell 5.1+（系统自带）
- [Chocolatey](https://chocolatey.org/install)（包管理器）
- Git（用于克隆项目和状态栏功能）
- Node.js（仅 MCP Server 需要）

## 🗑️ 卸载

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```

或在 GUI 管理器的组件管理页面取消勾选后点击"应用更改"。

## ❓ 常见问题

**Q: Oh My Posh 图标显示为方块？**
A: 在 Windows Terminal 设置中确认字体为 `CaskaydiaCove Nerd Font`，重启终端。

**Q: 亚克力透明不生效？**
A: 确保 Windows 设置 > 个性化 > 颜色 中开启了"透明效果"。

**Q: Claude Code 状态栏没有颜色？**
A: CTX 进度条的 `#` 和 `-` 可能在某些主题下不明显，可编辑 `statusline.sh` 调整颜色编号。

**Q: PowerShell 提示符没变化？**
A: 检查 `$PROFILE` 路径是否正确，运行 `. $PROFILE` 重新加载。

## 📄 License

MIT
