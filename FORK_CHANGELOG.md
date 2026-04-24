# Ghostty Fork 下游改动文档

> 基于 upstream [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) 的 fork，分支点：`6e0b0311e`
>
> 改动时间：2026-04-22 ~ 2026-04-24
>
> 共 66 个 commit，新增/修改 40 个文件，+3780 / -43 行

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
| **Git Worktree 支持** | 右键项目创建 worktree，统一存放在 `~/.super-ghostty-worktrees/`，支持一键删除 |
| **Git Status Badge** | 项目列表显示分支名、dirty 标记、ahead/behind 计数，10 秒轮询更新 |
| **Ask AI 对话框** | `⌘⇧T` 打开浮窗输入问题，选择 AI 工具后在新 tab 执行 |
| **LazyGit 集成** | `⌘⇧L` 一键打开 LazyGit tab，特殊 monospace 样式和分支图标 |
| **项目管理增强** | 项目重命名、归档/取消归档、路径去重 |
| **可配置 Quick Commands** | 每个项目可在 `projects.json` 中自定义快速启动按钮（最多 10 个） |
| **UI 缩放** | `sidebar.uiScale` 全局缩放侧边栏 UI 元素（0.5~2.0） |
| **macOS 通知** | Claude 完成/需要操作时发送系统通知（WIP） |
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

#### `25793735` — Add Cmd+Arrow keybindings for tab and project switching
- **改动**：1 个文件，+20
- **效果**：`⌘←/→` 切换 tab，`⌘↑/↓` 切换 project，与 `⌘H/L` 和 `⌘J/K` 平行

#### `9d3f49e9` — Fix sidebar keybindings: update Key union field names for upstream compat
- **改动**：1 个文件，+4 / -4
- **效果**：upstream 重命名了 `Binding.Trigger.Key` 字段（`translated` → `physical`，`left` → `arrow_left` 等），同步修复编译

#### `a380e43b` — Fix Cmd+Arrow keybindings: move sidebar bindings after defaults to prevent override
- **改动**：1 个文件，+22 / -20
- **效果**：sidebar `⌘Arrow` 绑定放在默认绑定之后，防止被 jump_to_prompt 等默认绑定覆盖

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

#### `83efb376` — Add configurable Quick Commands for project Quick Launch Bar
- **改动**：5 个文件，+74 / -19
- **效果**：每个项目可在 `projects.json` 中自定义 `quickCommands` 数组，替代硬编码的 Claude/Codex/Copilot 按钮
- **实现**：
  - `ProjectConfig.swift` 新增 `QuickCommand` 模型（name、command、icon 字段）
  - `QuickLaunchBar` 读取项目的 `quickCommands`，未配置时 fallback 到默认
  - 支持最多 10 个命令，icon 为可选 SF Symbols 名称

#### `885dd92d` — Fix default Copilot quick command from 'gh copilot' to 'copilot'
- **改动**：2 个文件，+2 / -2
- **效果**：修正 Copilot 默认命令为 `copilot`

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

#### `e28d9858` — Fix indicator showing completed prematurely during subagent execution
- **改动**：1 个文件，+1 / -1
- **效果**：移除 `SubagentStop` 事件的 completed 映射，避免子代理完成时主代理仍在工作却显示绿色

#### `534ef394` — Fix dismissStatus: actionNeeded should set idle, not remove tabId
- **改动**：1 个文件，+25 / -5
- **效果**：dismiss actionNeeded 时设为 idle 而非移除 tabId，修复后续 Stop 事件被丢弃的问题

#### `73947cb2` — Add fallback cleanup for stuck pending indicator on process exit and tab close
- **改动**：4 个文件，+21 / -1
- **效果**：用户中断 Claude（Escape）后 Stop hook 不触发导致 pending 永远卡住
- **实现**：
  - `ProjectToolLauncher` 在 initialInput 末尾链接 SessionEnd 命令，进程退出时自动清理
  - `TerminalController.windowWillClose` 中清除状态

#### `76ee049c` — Add "Clear Status" to tab context menu for manually dismissing stuck indicators
- **改动**：1 个文件，+7
- **效果**：tab 右键菜单新增 "Clear Status"，手动清除卡住的状态指示器

#### `30511f0b` — Fix stuck pending status: dismiss all statuses when user focuses tab
- **改动**：1 个文件，+5 / -10
- **效果**：聚焦 tab 时清除所有状态（含 pending），因为用户能直接看到 Claude 状态

#### `942750bb` — Fix indicator cleared instead of pending after permission request
- **改动**：1 个文件，+2 / -2
- **效果**：dismiss actionNeeded 后恢复为 pending（非 idle），因为授权后 AI 继续工作

#### `81bb0994` — Add 2x2 StatusDots grid for multi-tab Claude status display
- **改动**：1 个文件，+46 / -6
- **效果**：替换单个 StatusDot 为最多 4 个点的 2x2 网格，显示多 tab 聚合状态

#### `1f4412db` — Adaptive StatusDots layout (1→6) and fix dismiss on project switch
- **改动**：2 个文件，+58 / -15
- **效果**：StatusDots 根据活跃 dot 数动态调整布局（1 个填满、2 个横排、3~4 个 2x2、5~6 个 3x2）；修复切换项目时未 dismiss 状态的 bug

#### `99fe0dd2` — WIP: Add native macOS notifications for Claude status changes
- **改动**：1 个文件，+81 / -1
- **效果**：Claude tab 完成或需要操作时发送系统通知（前提是 tab 不在前台）
- **状态**：WIP，通知尚未被接收，需要调试

### 2.7 Git Worktree 支持

#### `9b8cfcc3` — Add git worktree support to project sidebar
- **改动**：5 个文件（+2 新建），+374
- **效果**：右键项目可创建 git worktree，worktree 在侧边栏以分支图标显示，右键可删除
- **实现**：
  - 新增 `GitWorktreeManager.swift` — 封装 git 子进程调用（`Process`），支持 create/remove worktree、查询分支等
  - 新增 `NewWorktreeSheet.swift` — 创建 worktree 的 SwiftUI 弹窗（分支名输入 + base branch 选择）
  - 修改 `ProjectConfig.swift` — 添加 `isWorktree: Bool?` 和 `parentRepoPath: String?` 字段
  - 修改 `ProjectSidebarState.swift` — 添加 `createWorktree()`、`deleteWorktree()`、`findTerminalWindow()` 方法
  - 修改 `ProjectSidebarView.swift` — 右键菜单增加 "New Worktree..." 和 "Remove & Delete Worktree"，使用 `.sheet(item:)` 绑定
  - Worktree 统一存放在 `~/.super-ghostty-worktrees/<repo-name>/<branch>/`
  - 创建后自动添加到项目列表并切换，图标为 `arrow.triangle.branch`
  - 删除时弹出确认对话框，执行 `git worktree remove` 并从列表移除

### 2.8 Git Status Badge

#### `a36c2a79` — Add git status badge to project sidebar
- **改动**：4 个文件（+1 新建），+179 / -5
- **效果**：项目列表每行显示分支名、dirty 标记（*）、ahead/behind 计数；非 git 目录显示路径
- **实现**：
  - 新增 `GitStatusManager.swift` — 后台线程 10 秒轮询 git 状态（`git status --porcelain`、`git rev-list --count`）
  - `ProjectListItem` 显示分支名和变更计数
  - hover 时 tooltip 显示完整路径

#### `78a10529` — Add per-project disableGit option to skip git status polling
- **改动**：2 个文件，+7 / -1
- **效果**：大型 repo（如 chromium）可在 `projects.json` 中设置 `"disableGit": true` 跳过 git 状态轮询

### 2.9 Ask AI 对话框

#### `9e840b20` — Add Cmd+Shift+T Ask AI prompt dialog
- **改动**：9 个文件（+1 新建），+139 / -2
- **效果**：`⌘⇧T` 打开无边框浮窗，含文本编辑器和工具选择器（Claude/Codex/Copilot）；`⌘Enter` 提交后在新 tab 启动选中的 CLI 工具并预填问题
- **实现**：
  - 新增 `prompt_ai_tool` action，走完整 Zig → C → Swift pipeline
  - 新增 `AskAISheet.swift` — 浮窗视图
  - `ProjectToolLauncher` 新增 `launchWithPrompt()` 方法
- **已知问题**：中文输入在启动命令中会乱码

### 2.10 LazyGit 集成

#### `d264f447` — Add Cmd+Shift+L shortcut to open lazygit tab and add lazygit to default Quick Launch Bar
- **改动**：9 个文件（+0 新建），+35
- **效果**：`⌘⇧L` 一键打开 LazyGit tab；默认 Quick Launch Bar 增加 LazyGit 按钮
- **实现**：
  - 新增 `new_lazygit_tab` action，走完整 Zig → C → Swift pipeline（第 8 个 action）
  - `QuickLaunchBar` 默认添加 LazyGit 按钮

#### `14a928b9` — Add special LazyGit tab styling with monospace title and branch icon
- **改动**：4 个文件，+42 / -10
- **效果**：LazyGit tab 使用等宽字体标题、分支图标和橙色强调色
- **实现**：
  - `ProjectToolLauncher` 检测 lazygit 命令，设置 `isLazygitTab` 标记和 `titleOverride`
  - `ProjectTabBar` 为 LazyGit tab 渲染特殊样式
  - `ProjectTabState.TabInfo` 追踪 `isLazygit` 标记

### 2.11 项目管理增强

#### `36a51f01` — Deduplicate projects by path and add project rename support
- **改动**：1 个文件，+34 / -1
- **效果**：加载时按路径去重，防止重复项目破坏 `⌘J/K` 导航；右键菜单支持重命名

#### `1d4ec439` — Add rename UI and multi-status dots to ProjectSidebarView
- **改动**：1 个文件，+41 / -1
- **效果**：新增 Rename 右键菜单项，使用 NSAlert 文本输入框；状态显示从单 dot 切换到 dots 数组

#### `f1f2c459` — Add archive/unarchive project feature to sidebar
- **改动**：4 个文件，+112 / -3
- **效果**：项目右键菜单新增 "Archive"，归档后移到侧边栏底部可折叠的 "Archived" 区域
- **实现**：
  - `ProjectConfig` 新增 `isArchived` 字段
  - `ProjectSidebarState` 新增 `archiveProject()`、`unarchiveProject()` 方法
  - `ProjectSidebarView` 渲染 "Archived" 折叠区域，点击归档项目自动取消归档

### 2.12 UI 打磨和性能优化

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

#### `743493e0` — Add configurable uiScale for sidebar UI percentage scaling
- **改动**：7 个文件，+179 / -66
- **效果**：引入 `SidebarLayout` 结构体集中管理所有 sidebar 尺寸常量，通过 `projects.json` 的 `sidebar.uiScale`（0.5~2.0）全局缩放
- **实现**：
  - `ProjectConfig` 新增 `SidebarLayout` 和 `uiScale` 配置
  - `ProjectSidebarView`、`ProjectListItem`、`ProjectTabBar`、`QuickLaunchBar`、`StatusDot` 中所有硬编码尺寸替换为 layout 派生值

#### `c2dec544` — Improve StatusDot visibility: larger size, saturated colors, independent opacity
- **改动**：2 个文件，+18 / -5
- **效果**：状态圆点更大、颜色更饱和、不透明度独立于背景

### 2.13 窗口和环境

#### `7e09d3c6` — Use separate UserDefaults key for window position
- **改动**：1 个文件，+1 / -6
- **效果**：使用 `SuperGhosttyWindowLastPosition` 替代 `NSWindowLastPosition`，避免与 upstream Ghostty 共用 UserDefaults

#### `cf0dd498` — Fix window position saving (0,0) during setup
- **改动**：1 个文件，+5
- **效果**：跳过窗口初始化时 origin 为 (0,0) 的保存，防止窗口被固定到左下角

### 2.14 构建脚本

#### `e2b7e364` — Add build_and_install.sh for Release builds with ad-hoc re-signing
- **改动**：1 个文件，+29
- **效果**：Release 编译 → 拷贝到 ~/Applications → ad-hoc 重签名（修复 Sparkle framework Team ID 不匹配）

#### `bf0426b6` — Fix build_and_install.sh to compile Zig core before Xcode build
- **改动**：1 个文件，+3
- **效果**：修复 Release 构建链接到 Debug Zig 库（384MB）的问题，添加 `zig build -Doptimize=ReleaseFast`

#### `5ea05c6a` — Add debug build script and fix build_and_install.sh paths
- **改动**：2 个文件，+18 / -1
- **效果**：添加 `build_debug.sh`，输出到 `build/Debug/`

#### `74cfdce2` — Use native xcframework-target in build_and_install.sh to skip x86_64 build
- **改动**：1 个文件，+1 / -1
- **效果**：使用 zig build 的原生 xcframework-target 参数，跳过不需要的 x86_64 编译

#### `e43af020` — Add --universal flag to build_and_install.sh for universal binary support
- **改动**：1 个文件，+21 / -4
- **效果**：默认只编译 arm64（快速），`--universal` 编译 arm64 + x86_64

### 2.15 其他

#### `1e18b797` — ignore claude
- `.gitignore` 添加 Claude 相关路径

#### `04551c5f` — Consolidate CLAUDE.md: merge fork sidebar docs into root file
- 将 fork sidebar 文档合并到根目录 `CLAUDE.md`

#### `9adbc905` — Add build/ to .gitignore
- `.gitignore` 添加 `build/` 目录

#### `a2999678` — Add fork documentation to README with project sidebar features and quick start guide
- README 增加 fork 功能介绍和快速上手指南

#### `fe21dc65` — Add project sidebar screenshot to README
- README 增加 sidebar 截图

---

## 三、改动文件清单

### Zig 核心层（5 文件）

| 文件 | 改动说明 |
|------|----------|
| `src/input/Binding.zig` | +8 个 binding 枚举值（toggle_project_sidebar, sidebar_prev/next_project, sidebar_prev/next_tab, new_claude_tab, new_lazygit_tab, prompt_ai_tool） |
| `src/input/command.zig` | +8 个命令映射 |
| `src/apprt/action.zig` | +8 个 action 枚举值 |
| `src/Surface.zig` | 转发 8 个 action 到 apprt |
| `src/config/Config.zig` | 注册默认快捷键（⌘H/J/K/L、⌘⇧S/C/L/T、⌘Arrow），重映射冲突的 ⌘J/K |

### C API（1 文件）

| 文件 | 改动说明 |
|------|----------|
| `include/ghostty.h` | +8 个 `GHOSTTY_ACTION_` 枚举值 |

### Swift/macOS（新增 13 文件 + 修改 9 文件）

**新增文件：**

| 文件 | 说明 |
|------|------|
| `ProjectSidebar/ProjectConfig.swift` | 项目配置读写（`projects.json`），含 SidebarLayout 和 QuickCommand |
| `ProjectSidebar/ProjectListItem.swift` | 项目列表行视图 + 状态指示器 + StatusDots 网格 |
| `ProjectSidebar/ProjectSidebarState.swift` | 侧边栏状态管理（宽度、活跃项目、持久化、worktree、rename、archive） |
| `ProjectSidebar/ProjectSidebarView.swift` | 侧边栏主视图（含 Archived 折叠区域） |
| `ProjectSidebar/ProjectTabBar.swift` | 自定义 tab bar（过滤显示当前项目 tab，LazyGit 特殊样式） |
| `ProjectSidebar/ProjectTabState.swift` | Tab 列表和选择状态单例 |
| `ProjectSidebar/QuickLaunchBar.swift` | AI 工具快速启动栏（支持自定义 Quick Commands） |
| `ProjectSidebar/ProjectToolLauncher.swift` | 工具启动逻辑（Quick Launch Bar、快捷键、Ask AI 共用） |
| `ProjectSidebar/ClaudeStatusServer.swift` | Unix socket 服务器，接收 Claude Code 状态事件 + macOS 通知 |
| `ProjectSidebar/GitWorktreeManager.swift` | Git 子进程封装，worktree 创建/删除/分支查询 |
| `ProjectSidebar/NewWorktreeSheet.swift` | 创建 worktree 的 SwiftUI 弹窗 |
| `ProjectSidebar/GitStatusManager.swift` | Git 状态轮询（分支名、dirty、ahead/behind） |
| `ProjectSidebar/AskAISheet.swift` | Ask AI 对话框（⌘⇧T） |

**修改文件：**

| 文件 | 改动说明 |
|------|----------|
| `AppDelegate.swift` | 加载项目配置、创建项目 tab、重映射 ⌘H |
| `TerminalController.swift` | 项目作用域 tab 切换、关闭后聚焦、tab bar 刷新 |
| `TerminalView.swift` | 嵌入侧边栏、主题颜色传递、action 处理 |
| `TerminalWindow.swift` | tab bar accessory 隐藏支持 |
| `TitlebarTabsTahoeTerminalWindow.swift` | 侧边栏 tab bar 偏移 |
| `TitlebarTabsVenturaTerminalWindow.swift` | 侧边栏 tab bar 偏移 |
| `Ghostty.App.swift` | 接收 8 个 sidebar/tool action，直接调用导航/启动逻辑 |
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
| `build_and_install.sh` | Release 编译 + 部署到 ~/Applications + ad-hoc 重签名（支持 --universal） |

### 文档和资源

| 文件 | 说明 |
|------|------|
| `README.md` | 增加 fork 功能介绍、快速上手指南和 sidebar 截图 |
| `screenshot.png` | Project Sidebar 截图 |

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
4. **Ask AI 中文输入** — `⌘⇧T` 对话框提交的中文在启动命令中会乱码
5. **macOS 通知未生效** — Claude 完成/需要操作时的系统通知功能为 WIP，尚未调通
