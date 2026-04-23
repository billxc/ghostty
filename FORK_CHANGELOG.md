# Ghostty Fork 下游改动文档

> 基于 upstream [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) 的 fork，分支点：`6e0b0311e`
>
> 改动时间：2026-04-22 ~ 2026-04-23
>
> 共 31 个 commit，新增/修改 32 个文件，+1862 / -41 行

---

## 一、功能总览

本 fork 将 Ghostty 终端模拟器扩展为**项目化 AI 开发环境**。核心增加了一个可折叠的 Project Sidebar，支持按项目组织 tab，一键启动 AI 工具（Claude / Codex / Copilot），并通过 Unix socket 实时显示 Claude Code 的运行状态。

### 主要特性

| 特性 | 说明 |
|------|------|
| **Project Sidebar** | 窗口左侧可折叠侧边栏，显示项目列表，点击切换项目 |
| **Tab 按项目分组** | 自定义 `ProjectTabBar` 替代原生 tab bar，只显示当前项目的 tabs |
| **Quick Launch Bar** | 一键启动 Claude(YOLO) / Codex(YOLO) / Copilot / Terminal |
| **键盘导航** | `⌘H/L` 切换 tab，`⌘J/K` 切换 project，`⌘⇧S` toggle sidebar，`⌘⇧C` 新建 Claude tab |
| **Claude 状态指示器** | 通过 Unix socket 接收 Claude Code hook 事件，在 tab/sidebar 上显示 AI 运行状态 |
| **窗口位置记忆** | 独立的 UserDefaults key，避免与 upstream Ghostty 冲突 |

---

## 快速上手

1. **配置项目列表**：创建 `~/.config/ghostty/projects.json`
   ```json
   {
     "projects": [
       { "name": "My App", "path": "/path/to/my-app" },
       { "name": "Backend", "path": "/path/to/backend", "icon": "server.rack" }
     ]
   }
   ```
   `icon` 字段可选，值为 [SF Symbols](https://developer.apple.com/sf-symbols/) 名称，默认 `folder.fill`。

2. **编译运行**：
   ```bash
   ./build_test.sh          # Debug 编译，输出 build/Ghostty.app
   open build/Ghostty.app
   ```

3. **安装 Claude 状态 hook**（可选）：
   ```bash
   bash macos/hooks/install-hooks.sh
   ```
   安装后 Claude Code 的运行状态会实时显示在 tab 上。

4. **快捷键**：`⌘⇧S` 切换侧边栏 · `⌘H/L` 切换 tab · `⌘J/K` 切换 project · `⌘⇧C` 新建 Claude tab

> **注意**：本 fork 重映射了 `⌘H`（原系统隐藏→`⌘⇧H`）、`⌘J`（原 scroll_to_selection→`⌘⇧J`）、`⌘K`（原 clear_screen→`⌘⇧K`）。这些重映射始终生效，即使不使用侧边栏。

---

## 二、Commit 详细记录

按时间正序排列，按功能模块分组。

### 2.1 Project Sidebar 基础功能

#### `6e11d7be` — Add project sidebar for organizing terminal tabs by project
- **改动**：10 个文件，+640 / -35
- **效果**：增加窗口左侧可折叠的项目侧边栏
- **实现**：
  - 新增 `ProjectConfig.swift` — 读写 `~/.config/ghostty/projects.json` 配置文件
  - 新增 `ProjectSidebarState.swift` — 侧边栏状态管理（宽度、活跃项目、持久化）
  - 新增 `ProjectSidebarView.swift` — 侧边栏 SwiftUI 视图
  - 新增 `ProjectListItem.swift` — 项目列表行视图
  - 修改 `AppDelegate.swift` — 启动时加载项目配置，点击项目创建新 tab 并执行 `claude` 命令
  - 修改 `TerminalView.swift` — 嵌入侧边栏，tab 按项目过滤
  - 修改 `TerminalController.swift` — 新 tab 继承当前项目关联
  - 修改 `GhosttyPackage.swift` — 添加 sidebar 相关通知名
  - 修改 Tahoe/Ventura 窗口样式 — tab bar 偏移支持
- **配置格式**：
  ```json
  {
    "projects": [
      { "name": "My Project", "path": "/path/to/project", "icon": "folder" }
    ],
    "sidebar": { "width": 200, "visible": true, "activeProjectPath": "..." }
  }
  ```

#### `5233c9be` — Remove Unassigned group, simplify project navigation
- **改动**：5 个文件，+67 / -71
- **效果**：移除"未分配"虚拟分组，项目列表顺序即导航顺序
- **实现**：
  - 添加右键菜单 "Move to Top" 调整项目顺序
  - 启动时默认选中第一个项目
  - 无项目配置时 fallback 到用户 home 目录
  - 新增 `build_test.sh` debug 编译脚本

#### `1ccd377a` — Fix initial window using default project and persist Move to Top immediately
- **改动**：2 个文件，+32 / -3
- **效果**：首次窗口打开在第一个项目的目录下；"Move to Top" 立即持久化（绕过 3 秒 debounce）

### 2.2 自定义 Tab Bar

#### `6c455ea1` — Custom tab bar with native styling, hide native tab bar when sidebar visible
- **改动**：4 个文件，+205 / -123
- **效果**：用 macOS 原生风格的自定义 tab bar 替换原生 tab bar
- **实现**：
  - 新增 `ProjectTabBar.swift` — 自定义 tab bar 视图（圆角背景、阴影、分隔线、hover 关闭按钮）
  - 侧边栏可见时隐藏原生 tab bar，显示自定义的过滤后 tab bar
  - 清理 `ProjectSidebarState` 中的调试日志和未使用代码

#### `86dfc33b` — better tab
- **改动**：1 个文件，+76 / -31
- **效果**：改进 tab bar 的样式和交互

#### `a5d89291` — Refactor tab state into ProjectTabState to reduce re-render scope
- **改动**：6 个文件，+138 / -91
- **效果**：将 tab 列表和选择状态提取到 `ProjectTabState` 单例，减少重绘范围
- **实现**：
  - 新增 `ProjectTabState.swift` — 独立的 tab 状态管理
  - 隔离 tab bar + quick launch 到 `ProjectTabBarSection`，tab 变化不触发整个 TerminalView 重绘
  - 拖拽 resize 使用 drag-end 持久化，替代逐帧 updateWidth

### 2.3 键盘导航（Zig → C → Swift 全链路）

#### `7bd64c5a` — Add sidebar navigation keybinds (Cmd+H/J/K/L)
- **改动**：9 个文件，+169 / -2
- **效果**：注册 4 个新 action：`sidebar_prev_project`、`sidebar_next_project`、`sidebar_prev_tab`、`sidebar_next_tab`
- **实现**：
  - `src/input/Binding.zig` — 添加 4 个 binding 枚举值
  - `src/input/command.zig` — 添加 4 个命令映射
  - `src/apprt/action.zig` — 添加 4 个 action 枚举值
  - `src/Surface.zig` — 转发 4 个 action 到 apprt
  - `src/config/Config.zig` — 注册默认快捷键 `⌘H/J/K/L`，重映射冲突的 `⌘J`(scroll_to_selection) 和 `⌘K`(clear_screen) 到 `⌘⇧J/K`
  - `include/ghostty.h` — C API 添加 4 个 `GHOSTTY_ACTION_` 枚举
  - `Ghostty.App.swift` — Swift 层接收并执行 action
  - `TerminalView.swift` — 通过 NotificationCenter 通知 sidebar 导航
  - `GhosttyPackage.swift` — 添加通知名

#### `95d9d40e` — Add sidebar keybinds via Zig pipeline, titlebar tabs, quick launch bar
- **改动**：10 个文件，+170 / -55
- **效果**：`⌘⇧S` toggle sidebar 通过完整 Zig keybind pipeline 分发
- **实现**：
  - 注册 `toggle_project_sidebar` action（第 5 个 Zig action）
  - 自定义 tab bar 移到 titlebar 区域（`NSTitlebarAccessoryViewController`）
  - 新增 `QuickLaunchBar.swift` — Claude / Codex / Copilot / Terminal 快速启动栏
  - 移除旧的菜单项切换方式

#### `2c461477` — Fix sidebar keybind mapping: H/L for tabs, J/K for projects
- **改动**：1 个文件（`Config.zig`），+4 / -4
- **效果**：修正快捷键映射，`⌘H/L` 水平切换 tab，`⌘J/K` 垂直切换 project，匹配空间布局

#### `364be491` — Remap system Cmd+H to Cmd+Shift+H for sidebar navigation
- **改动**：1 个文件（`AppDelegate.swift`），+8
- **效果**：将系统 "隐藏" 快捷键从 `⌘H` 移到 `⌘⇧H`，释放 `⌘H` 给 sidebar 导航

#### `0837e3db` — Add Cmd+Shift+C shortcut to open Claude tab
- **改动**：10 个文件（+1 新建），+97 / -46
- **效果**：`⌘⇧C` 直接打开 Claude tab（等同于 Quick Launch Bar 的 Claude 按钮）
- **实现**：
  - 新增 `new_claude_tab` action，走完整 Zig → C → Swift pipeline（6 层同步）
  - 新增 `ProjectToolLauncher.swift` — 提取工具启动逻辑，Quick Launch Bar 和快捷键共用
  - `QuickLaunchBar.swift` 重构为调用 `ProjectToolLauncher`

### 2.4 Tab 作用域和切换

#### `c1a01942` — Scope tab switching and close-focus to current project
- **改动**：1 个文件（`TerminalController.swift`），+33 / -1
- **效果**：侧边栏可见时，`Ctrl+Tab` 只在同项目 tab 间循环；关闭 tab 时聚焦同项目的下一个 tab

#### `cc57a3e5` — Fix native tab bar intercepting title bar drags when sidebar is visible
- **改动**：3 个文件，+41 / -82
- **效果**：修复原生 tab bar 隐藏后仍拦截标题栏拖拽事件
- **实现**：隐藏 `NSTitlebarAccessoryViewController` 的 `isHidden` 属性（而非仅隐藏 NSTabBar 子视图），从布局和 hit testing 中完全移除

#### `8b1eb627` — Use tabGroup.selectedWindow for tab switching in sidebar
- **改动**：1 个文件，+8 / -7
- **效果**：用 `tabGroup.selectedWindow` 替代 `makeKeyAndOrderFront` 切换 tab，使用正确的 API

#### `5edffea8` — Refresh tab bar highlight after gotoTab (⌘1/2/3)
- **改动**：1 个文件，+2
- **效果**：修复 `⌘1/2/3` 跳转 tab 后自定义 tab bar 高亮不更新

#### `17d39deb` — Refresh tab bar highlight after closeTab (⌘W)
- **改动**：1 个文件，+8
- **效果**：修复关闭 tab 后自定义 tab bar 高亮不跟踪新聚焦的 tab

### 2.5 Quick Launch Bar 和工具启动

#### `5eb150ea` — Use initialInput for tool launch commands with YOLO flags
- **改动**：2 个文件，+8 / -5
- **效果**：通过 `initialInput`（而非 `config.command`）启动 CLI 工具，确保 login shell 加载 PATH（解决 Homebrew 找不到命令的问题）
- **启动命令**：
  - Claude: `claude --dangerously-skip-permissions\n`
  - Codex: `codex --full-auto\n`

#### `19930657` — Default project tabs to plain terminal instead of Claude
- **改动**：3 个文件，+4 / -4
- **效果**：项目默认打开普通终端而非 Claude

#### `c6e54f79` — Add hover highlight to quick launch buttons
- **改动**：1 个文件，+38 / -17
- **效果**：按钮 hover 时增加高亮效果

### 2.6 Claude Code 状态指示器

#### `9b65478d` — Add Claude Code running status indicator via Unix socket
- **改动**：13 个文件，+487 / -10
- **效果**：在 tab bar 和 sidebar 上实时显示 Claude Code 运行状态
- **实现**：
  - 新增 `ClaudeStatusServer.swift` — Unix socket 服务器，监听 `/tmp/ghostty-claude/<pid>.sock`
  - QuickLaunchBar 启动时注入 `GHOSTTY_SOCKET` 和 `GHOSTTY_TAB_ID` 环境变量
  - 状态模型（per tab）：
    - `idle` — 无指示器
    - `pending` — 橙色脉冲圆点（AI 思考中）
    - `completed` — 绿色圆点 + 提示音（AI 完成）
    - `actionNeeded` — 红色圆点 + 提示音（需要用户操作）
  - Sidebar 显示项目级聚合状态；tab bar 显示单 tab 状态
  - 切换到 tab 时自动清除 completed/actionNeeded 状态
  - 切换项目时优先选中有通知的 tab
  - 新增 hook 脚本：`ghostty-claude-status.sh`（Claude Code hook，通过 stdin 接收事件 JSON，映射为 Ghostty 状态）
  - 辅助脚本：`install-hooks.sh`、`uninstall-hooks.sh`、`test-status.sh`
- **Hook 事件 JSON 格式**（Claude Code 通过 stdin 发送）：
  ```json
  { "hook_event_name": "UserPromptSubmit" }
  ```
  支持的事件：`UserPromptSubmit` → pending，`Stop`/`SubagentStop` → completed，`PermissionRequest` → actionNeeded

#### `4df95bde` — Per-tab AI indicator and skip pending tabs on project switch
- **改动**：4 个文件，+16 / -11
- **效果**：每个 tab 显示独立的 Claude 状态指示器（替代项目级聚合状态）；切换项目时跳过 pending 状态的 tab
- **实现**：
  - 移除基于标题的 "claude" 检查 — 任何有活跃状态的 tab 都显示指示器
  - 项目切换自动选择时跳过 pending tab（AI 还未响应）

### 2.7 UI 打磨和性能优化

#### `9399160f` — Polish sidebar UI: theme-aware colors, tab styling, and remove Terminal from quick launch
- **改动**：5 个文件，+21 / -12
- **效果**：sidebar/tab bar/quick launch bar 使用主题背景色；tab 样式从圆角矩形改为全高矩形

#### `3c66dfd4` — Use theme backgroundOpacity for sidebar UI and debounce persistence
- **改动**：5 个文件，+31 / -12
- **效果**：sidebar UI 颜色跟随用户的 `background-opacity` 配置；持久化改为 3 秒 debounce

#### `5b372f13` — Debounce sidebar persistence and optimize drag resize
- **改动**：1 个文件，+40 / -24
- **效果**：后台线程 3 秒 debounce 持久化，替代同步主线程 I/O；拖拽 resize 时只在松手后写盘

#### `baf58ba3` — Move sidebar navigation from SwiftUI NotificationCenter to direct calls
- **改动**：4 个文件，+59 / -77
- **效果**：navigation 从 NotificationCenter 改为 Ghostty.App action handler 直接调用，移除 5 个未使用的通知名

### 2.8 窗口和环境

#### `7e09d3c6` — Use separate UserDefaults key for window position
- **改动**：1 个文件，+1 / -6
- **效果**：使用 `SuperGhosttyWindowLastPosition` 替代 `NSWindowLastPosition`，避免与 upstream Ghostty 共用 UserDefaults

#### `cf0dd498` — Fix window position saving (0,0) during setup
- **改动**：1 个文件，+5
- **效果**：跳过窗口初始化时 origin 为 (0,0) 的保存，防止窗口被固定到左下角

### 2.9 构建脚本

#### `e2b7e364` — Add build_and_install.sh for Release builds with ad-hoc re-signing
- **改动**：1 个文件，+29
- **效果**：Release 编译 → 拷贝到 ~/Applications → ad-hoc 重签名（修复 Sparkle framework Team ID 不匹配）

#### `bf0426b6` — Fix build_and_install.sh to compile Zig core before Xcode build
- **改动**：1 个文件，+3
- **效果**：修复 Release 构建链接到 Debug Zig 库（384MB）的问题，添加 `zig build -Doptimize=ReleaseFast`

#### `5ea05c6a` — Add debug build script and fix build_and_install.sh paths
- **改动**：2 个文件，+18 / -1
- **效果**：添加 `build_debug.sh`，输出到 `build/Debug/`

### 2.10 其他

#### `1e18b797` — ignore claude
- `.gitignore` 添加 Claude 相关路径

#### `04551c5f` — Consolidate CLAUDE.md: merge fork sidebar docs into root file
- 将 fork sidebar 文档合并到根目录 `CLAUDE.md`

---

## 三、改动文件清单

### Zig 核心层（5 文件，+134 / -2）

| 文件 | 改动说明 |
|------|----------|
| `src/input/Binding.zig` | +6 个 binding 枚举值（toggle_project_sidebar, sidebar_prev/next_project, sidebar_prev/next_tab, new_claude_tab） |
| `src/input/command.zig` | +6 个命令映射 |
| `src/apprt/action.zig` | +6 个 action 枚举值 |
| `src/Surface.zig` | 转发 6 个 action 到 apprt |
| `src/config/Config.zig` | 注册默认快捷键，重映射冲突的 ⌘J/K |

### C API（1 文件）

| 文件 | 改动说明 |
|------|----------|
| `include/ghostty.h` | +6 个 `GHOSTTY_ACTION_` 枚举值 |

### Swift/macOS（新增 8 文件 + 修改 9 文件，+1345 / -39）

**新增文件：**

| 文件 | 说明 |
|------|------|
| `ProjectSidebar/ProjectConfig.swift` | 项目配置读写（`projects.json`） |
| `ProjectSidebar/ProjectListItem.swift` | 项目列表行视图 + 状态指示器 |
| `ProjectSidebar/ProjectSidebarState.swift` | 侧边栏状态管理（宽度、活跃项目、持久化、debounce） |
| `ProjectSidebar/ProjectSidebarView.swift` | 侧边栏主视图 |
| `ProjectSidebar/ProjectTabBar.swift` | 自定义 tab bar（过滤显示当前项目 tab） |
| `ProjectSidebar/ProjectTabState.swift` | Tab 列表和选择状态单例 |
| `ProjectSidebar/QuickLaunchBar.swift` | AI 工具快速启动栏 |
| `ProjectSidebar/ProjectToolLauncher.swift` | 工具启动逻辑（Quick Launch Bar 和快捷键共用） |
| `ProjectSidebar/ClaudeStatusServer.swift` | Unix socket 服务器，接收 Claude Code 状态事件 |

**修改文件：**

| 文件 | 改动说明 |
|------|----------|
| `AppDelegate.swift` | 加载项目配置、创建项目 tab、重映射 ⌘H |
| `TerminalController.swift` | 项目作用域 tab 切换、关闭后聚焦、tab bar 刷新 |
| `TerminalView.swift` | 嵌入侧边栏、主题颜色传递、action 处理 |
| `TerminalWindow.swift` | tab bar accessory 隐藏支持 |
| `TitlebarTabsTahoeTerminalWindow.swift` | 侧边栏 tab bar 偏移 |
| `TitlebarTabsVenturaTerminalWindow.swift` | 侧边栏 tab bar 偏移 |
| `Ghostty.App.swift` | 接收 6 个 sidebar/tool action，直接调用导航/启动逻辑 |
| `GhosttyPackage.swift` | sidebar 通知名 |
| `LastWindowPosition.swift` | 独立 UserDefaults key + (0,0) 保护 |

### Hook 脚本（4 文件）

| 文件 | 说明 |
|------|------|
| `macos/hooks/ghostty-claude-status.sh` | Claude Code hook，映射事件到 Ghostty 状态 |
| `macos/hooks/install-hooks.sh` | 安装 hook 到 `~/.claude/hooks/` |
| `macos/hooks/uninstall-hooks.sh` | 卸载 hook |
| `macos/hooks/test-status.sh` | 测试脚本，模拟状态事件 |

### 构建脚本（3 文件）

| 文件 | 说明 |
|------|------|
| `build_test.sh` | Debug 编译（Zig + Swift），输出 `build/Ghostty.app` |
| `build_debug.sh` | Debug 编译，输出 `build/Debug/` |
| `build_and_install.sh` | Release 编译 + 部署到 ~/Applications + ad-hoc 重签名 |

---

## 四、关键技术决策

### 4.1 为什么用 `initialInput` 而非 `config.command`

`config.command` 启动的进程是直接 exec，不走 login shell，导致 PATH 不包含 Homebrew (`/opt/homebrew/bin`)，`claude` 和 `codex` 命令找不到。改用 `initialInput` 相当于在 login shell 里输入命令并回车，环境变量完整。

### 4.2 为什么保留所有 tab 在同一个 NSWindowTabGroup

macOS 原生 tab 管理依赖 `NSWindowTabGroup`。如果把不同项目的 tab 分到不同窗口，会破坏 Ghostty 的单窗口模型和窗口合并逻辑。因此选择隐藏原生 tab bar，用自定义 `ProjectTabBar` 做项目过滤显示。

### 4.3 为什么快捷键走完整 Zig keybind pipeline

在 SwiftUI 层直接拦截快捷键会绕过 Ghostty 的按键处理逻辑（包括 key repeat、mode 检测等），可能在终端输入模式下误触发。通过 Zig 层注册，快捷键遵循与所有其他 Ghostty 快捷键相同的分发路径。

### 4.4 Claude 状态指示器的 Unix socket 方案

Claude Code 支持 hook 机制，可以在特定生命周期事件触发时执行脚本。选择 Unix socket（而非文件轮询或 HTTP）是因为：
- 零延迟，适合实时状态更新
- 天然绑定到进程生命周期（Ghostty 退出时 socket 文件自动失效）
- 通过 `GHOSTTY_SOCKET` 和 `GHOSTTY_TAB_ID` 环境变量精确路由到对应的 Ghostty 实例和 tab

### 4.5 独立的 UserDefaults key

Fork 和 upstream 共用同一个 bundle identifier (`com.mitchellh.ghostty`)，因此共享 UserDefaults domain。使用 `SuperGhosttyWindowLastPosition` 替代 `NSWindowLastPosition`，避免窗口位置互相覆盖。

---

## 五、已知限制

1. **原生 tab bar 闪现** — 启动时原生 tab bar 可能短暂显示后被隐藏
2. **titlebar-style 冲突** — `macos-titlebar-style = tabs` 与自定义 tab bar 冲突，不要在配置中设置
3. **Ctrl+Tab 全局** — `Ctrl+Tab` 是系统级快捷键，仍会切换所有 tab（不限于当前项目）
4. **单 remote** — 目前只有 `origin`（billxc/ghostty），未跟踪 upstream remote
