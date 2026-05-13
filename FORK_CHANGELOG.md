# Ghostty Fork 下游改动文档

> 基于 upstream [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) 的 fork，分支点：`6e0b0311e`
>
> 改动时间：2026-04-22 ~ 2026-05-13
>
> 共 260 个 commit，新增/修改 156 个文件，+11549 / -6478 行

---

## 一、功能总览

本 fork 将 Ghostty 终端模拟器扩展为**项目化 AI 开发环境**。核心增加了一个可折叠的 Project Sidebar，支持按项目组织 tab，一键启动 AI 工具（Claude / Codex / Copilot），并通过 Unix socket 实时显示 Claude Code 的运行状态。

### 主要特性

| 特性 | 说明 |
|------|------|
| **Project Sidebar** | 窗口左侧可折叠侧边栏，显示项目列表，点击切换项目，支持 UI 添加/排序 |
| **Tab 按项目分组** | 自定义 `ProjectTabBar` 替代原生 tab bar，只显示当前项目的 tabs |
| **Quick Launch Bar** | 一键启动 Claude(YOLO) / Codex(YOLO) / Copilot / Terminal |
| **键盘导航** | `⌘H/L` 切换 tab，`⌘J/K` 切换 project，`⌘⇧S` toggle sidebar，`⌘⇧C` 新建 Claude tab |
| **Claude 状态指示器** | 通过 Unix socket 接收 Claude Code hook 事件，在 tab/sidebar 上显示 AI 运行状态 |
| **Git Worktree 支持** | 右键项目创建 worktree，统一存放在 `~/.super-ghostty-worktrees/`，支持一键删除，继承父项目 quick commands |
| **Git Status Badge** | 项目列表显示分支名、dirty 标记、ahead/behind 计数，10 秒轮询更新 |
| **Ask AI 对话框** | `⌘⇧T` 打开浮窗输入问题，选择 AI 工具后在新 tab 执行 |
| **LazyGit 集成** | `⌘⇧L` 一键打开 LazyGit tab，特殊 monospace 样式和分支图标 |
| **项目管理增强** | 项目重命名、归档/取消归档、路径去重 |
| **可配置 Quick Commands** | 每个项目可在 `projects.json` 中自定义快速启动按钮（最多 10 个） |
| **Quick Commands 编辑器** | 侧边栏内可视化编辑命令列表，支持拖拽排序、插入默认项、重置 |
| **Tab 拖拽排序** | 自定义 tab bar 支持拖拽重排，顺序持久化 |
| **ReuseTab** | Quick command 可配置复用已有 tab，命令退出后再次点击重新执行 |
| **Close on Complete** | Quick command 可配置命令退出后自动关闭 tab（与 ReuseTab 互斥） |
| **Claude Session 恢复** | 退出时保存 Claude session ID，下次启动自动 `--resume` 恢复对话（跳过归档项目） |
| **Resume Session UI** | QuickLaunchBar Resume 按钮 / `⌘⇧T` 打开 session 选择器，可改大小、半透明、延迟加载 |
| **Project Settings 菜单** | 项目右键 Project Settings，可逐项目开关 Resume / Settings 按钮 |
| **claude-resume CLI** | 跨项目搜索 Claude session 并在正确目录恢复 |
| **UI 缩放** | `sidebar.uiScale` 全局缩放侧边栏 UI 元素（0.5~2.0） |
| **macOS 通知** | Claude 完成/需要操作时发送系统通知（WIP） |
| **窗口位置记忆** | 独立的 UserDefaults key，避免与 upstream Ghostty 冲突 |

---

## 快速上手

1. **编译运行**：
   ```bash
   ./build_test.sh          # Debug 编译，输出 build/Ghostty.app
   open build/Ghostty.app
   ```

2. **添加项目**：侧边栏底部点击 "+" 按钮选择目录，无需手动编辑 JSON 文件。也可以直接编辑 `~/.config/ghostty/projects.json`。

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

#### `fa56b11c` — Project-aware Cmd+T and close-tab focus selection
- **改动**：1 个文件（`TerminalController.swift`），+29 / -8
- **效果**：
  - `Cmd+T` 在 project tab 中新建的 tab 落在 `project.path`（之前因为 `inherit-working-directory=false` 默认值会回到 `$HOME`）
  - 关闭 tab 后聚焦同项目的**邻近** tab（先前一个，再后一个），而不是总跳到 project 的第一个 tab
- **实现**：`@IBAction func newTab` 在 `self.project` 存在时改走 `TerminalController.newTab(...)` + `SurfaceConfiguration.workingDirectory`；`closeTabImmediately` 捕获关闭前的 index，async 块中按 prev → next → first 顺序挑同项目 tab

#### `d4166307` — Project-aware "+" button in custom ProjectTabBar
- **改动**：1 个文件（`AppDelegate.swift`），+15 / -4
- **效果**：自定义 tab bar 上的 "+" 按钮新建的 tab 现在也落在 project 目录（之前会回到 `$HOME`，因为 `AppDelegate.newTab` 在 surface 创建后才设置 `controller.project`）
- **实现**：`AppDelegate.newTab` 先从 parent controller 取 project，构造带 `workingDirectory` 的 `SurfaceConfiguration` 后再调 `TerminalController.newTab`

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

#### `758b00df` — Fix archived section header button not responding to clicks on blank area
- **改动**：1 个文件，+2 / -1
- **效果**：修复归档区域 header 按钮空白处点击无响应

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

#### `bdf31f979` — Sidebar perf: split status stores, cache project index, drop redundant refresh
- **改动**：4 个文件，+136 / -17
- **效果**：tab 多时切换 / 拖动 sidebar 不再卡顿；Claude 状态推送 / git 轮询不再触发全部 N 个 window 的 sidebar 重渲染
- **实现**：
  - 每个 tab = 一个独立 NSWindow + 一份 SwiftUI 树，原本所有 N 份 ProjectSidebarView 都观察 ProjectSidebarState，每次 status push / git poll 都触发 O(N_windows × P × N_tabs) 重算
  - 拆出 `ClaudeStatusStore` / `GitStatusStore` 单例，高频写不再 invalidate 只关心 projects/layout/width 的 view
  - `ClaudeStatusStore.projectStatuses` cache：tabStatuses 变化时一次性按 project path 分组（O(N_tabs)），sidebar list 直接 O(1) 查表
  - `ProjectTabState.refresh` 末尾调 `notifyTabsChanged()` 保证 cache 在 tab 增删时同步
  - 新增 `SidebarHost` wrapper，drag width 走本地 @State，`updateWidth` 仅在松手时 publish 一次
  - 删 `onChange(of: focusedSurface)` 里的冗余 refresh（focus 在 split / 按键时也会变，不该触发 tab list 重建）

#### `c0974e946` — Sidebar perf P0: visibility gating, parallel git, dismiss dedup
- **改动**：9 个文件，+176 / -28
- **效果**：tab/window 数量大时切换更顺滑；非前台 window 不再参与 sidebar / tab bar 渲染；git 轮询不再阻塞主线程
- **实现**：
  - `KeyWindowTracker` 单例 + `TerminalController.windowDidBecomeKey/Resign` 上报；`TerminalView` 通过 `WindowAccessor` 拿到自己的 NSWindow，`isKeyWindow` 为 false 时跳过 `SidebarHost` / `ProjectTabBarSection`，消除 N-window 级联重渲
  - 删除 git poll 里的 `DispatchQueue.main.sync`（潜在死锁）；poll queue 改 concurrent，`concurrentPerform` + `NSLock` 并行 fetch 各 project 的 git 状态
  - `ProjectListItem` / `TabItemView` / `TabInfo` / `GitStatusInfo` / `SidebarLayout` 加 `Equatable`，配合 `.equatable()` 让 SwiftUI 在输入未变时短路 body
  - `lastDismissedTabId` 去重 `dismissClaudeStatus`（focusedSurface 变化频繁但 tabId 大多不变）

#### `b29933340` — Sidebar regressions + suppress native tab bar
- **改动**：2 个文件，+37 / -4
- **效果**：修复 c0974e946 引入的 sidebar 闪烁回归；隐藏 sidebar 后 titlebar 不再多出空白条
- **实现**：
  - `windowDidResignKey` 不再清 `KeyWindowTracker`：app 失焦 / Cmd+Shift+T / quick launch 时所有 TerminalView 不再瞬间 isKeyWindow=false 卸载 sidebar
  - `windowWillClose` 同步把 tracker 转交给 tab group 里的下一个 window，避免关 tab / quick launch 退出时闪一下
  - `TerminalWindow.addTitlebarAccessoryViewController` override：捕获原生 NSTabBar accessory 后下个 runloop tick 直接 remove 掉，titlebar 不再为它预留高度（仅 isHidden=true 在 macOS 14+ 不可靠）
  - `suppressNativeTabBar()` 复用 `NSWindow.tabBarView` 私有访问器，作为 windowDidBecomeKey/Main 的兜底

#### `03efa6028` — Git poll: per-project staggered + dedup publishes
- **改动**：1 个文件，+38 / -11
- **效果**：git 轮询不再扎堆在分钟整点；无变化时 0 次 SwiftUI body 评估
- **实现**：
  - 主 timer 改 5s tick；每个 project 自带 60s 周期，相位偏移 = `abs(path.hashValue) % 60`，启动锚点 `gitPollEpoch + offset` 决定首次触发
  - merge 时逐项 `!=` 比较，整体没变就不赋值 `gitStatuses`，`@Published` 不发布

### 2.13 窗口和环境

#### `7e09d3c6` — Use separate UserDefaults key for window position
- **改动**：1 个文件，+1 / -6
- **效果**：使用 `SuperGhosttyWindowLastPosition` 替代 `NSWindowLastPosition`，避免与 upstream Ghostty 共用 UserDefaults

#### `cf0dd498` — Fix window position saving (0,0) during setup
- **改动**：1 个文件，+5
- **效果**：跳过窗口初始化时 origin 为 (0,0) 的保存，防止窗口被固定到左下角

#### `637e5b7a` — Default *-inherit-working-directory to false
- **改动**：1 个文件（`src/config/Config.zig`），+3 / -3
- **效果**：新 tab/window/split 不再继承前一个 surface 的 cwd；改为使用 project path（或全局 `working-directory`）。fork 已经按 project 组织 tab，继承 cwd 会让新 tab 落在意料之外的子目录
- **实现**：将 `window-inherit-working-directory`、`tab-inherit-working-directory`、`split-inherit-working-directory` 三个默认值从 `true` 改为 `false`

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

#### `7137cb83` — Inject git commit hash into About dialog via build scripts
- **改动**：2 个文件，+14
- **效果**：`build_test.sh` 和 `build_and_install.sh` 在编译后用 PlistBuddy 写入 git short hash，About 窗口显示当前 commit

### 2.15 Quick Commands 编辑器

#### `8ca1e204` — Centralize quick command defaults and enhance editor with reorder/reset
- **改动**：5 个文件（+2 新建），+338 / -21
- **效果**：新建 `QuickCommandDefaults.swift` 集中管理默认命令；新增 `QuickCommandsEditor.swift` 可视化编辑界面
- **实现**：
  - 移除散落在各文件的硬编码默认命令
  - 编辑器支持：添加/删除/上下移动命令、"Insert Defaults to Front"、"Reset to Defaults"
  - AskAISheet、ProjectToolLauncher、QuickLaunchBar 引用集中化的默认值

#### `7ef26fbe` — Use separate projects.json for Debug builds and show hidden files in picker
- **改动**：2 个文件，+7 / -1
- **效果**：Debug 构建读取 `~/.config/ghostty-debug/projects.json`，避免干扰 Release 配置

### 2.16 Tab 拖拽排序

#### `3f8428e9` — Add drag-and-drop tab reordering in ProjectTabBar
- **改动**：2 个文件，+110 / -2
- **效果**：Tab 支持拖拽重排，顺序通过 stable merge 持久化（用户顺序跨 tab 开关保持）

#### `39108e91` — Make tab navigation (Cmd+H/L) respect drag-reorder
- **改动**：1 个文件，+5 / -3
- **效果**：`⌘H/L` 切换 tab 时使用用户拖拽后的顺序而非窗口默认顺序

#### `3a36576b` — Remember last active tab per project when switching projects
- **改动**：2 个文件，+28 / -2
- **效果**：切换项目时恢复到上次活跃的 tab，而非总是跳到第一个

#### `8e1146c1` — Unify tab ordering: goto_tab, move_tab, close-right all use ProjectTabState
- **改动**：1 个文件，+55 / -20
- **效果**：`⌘1/2/3`（goto_tab）、move tab left/right、close tabs to the right 全部使用 ProjectTabState 的视觉顺序

### 2.17 ReuseTab 功能

#### `6f7422b3` — Add reuseTab support for quick commands: reuse existing tab and re-run exited commands
- **改动**：8 个文件，+101 / -13
- **效果**：Quick command 新增 `reuseTab` 配置项；点击已存在的 tab 会切换过去，命令退出后再次点击重新执行
- **实现**：
  - `QuickCommand` 新增 `reuseTab: Bool?` 字段，编辑器新增 "Reuse" checkbox
  - `TerminalController` 追踪 `quickCommandName` 和命令退出状态
  - LazyGit 默认 `reuseTab=true`

#### `00d561f1` — Fix reuseTab re-run: use text: action to bypass bracketed paste, add shellIsIdle fallback
- **改动**：5 个文件，+227 / -3
- **效果**：修复重新执行命令时 bracketed paste mode 阻止执行的问题
- **实现**：
  - 改用 `perform(action: "text:...\\x0d")` 直接写 PTY
  - 添加 `needsConfirmQuit` 作为命令退出检测的 fallback
  - 新增 `ClaudeSessionPersistence.swift`：Claude 命令注入 `--session-id`，退出时保存以便恢复

#### `275c127b` — Remove cleanup command from reuseTab re-run, rely on shellIsIdle fallback
- **改动**：1 个文件，+1 / -3
- **效果**：移除 SessionEnd cleanup 命令链接，依赖 shellIsIdle 检测退出

#### `2be449c6` — Remove SessionEnd cleanup chain from initialInput
- **改动**：1 个文件，+1 / -3
- **效果**：完全移除 initialInput 末尾的 SessionEnd 通知命令

#### `b8ba09e2` — Remove commandExited flag, use shellIsIdle (needsConfirmQuit) everywhere
- **改动**：4 个文件，+3 / -17
- **效果**：废弃 `commandExited` 标记，统一使用 shell integration (OSC 133) 的 `needsConfirmQuit` 检测命令是否退出

#### `ac9994d5` — Copy parent project's quick commands when creating worktree
- **改动**：1 个文件，+2 / -1
- **效果**：创建 worktree 时继承父项目的 quick commands 配置

#### `ed2fd117` — Add Close on Complete option for quick commands
- **改动**：5 个文件，+65 / -2
- **效果**：quick command 新增 `closeOnComplete` 字段，命令退出后自动关闭对应 tab
- **实现**：依赖 shell integration 的 `needsConfirmQuit` 信号，在编辑器中以 toggle 暴露

#### `a85f8038` — Make Reuse and Close on Complete mutually exclusive
- **改动**：1 个文件，+8 / -2
- **效果**：在 QuickCommandsEditor 中，开启一个 toggle 自动关闭另一个，避免行为冲突

### 2.18 Claude Session 恢复

#### `00d561f1` — Add ClaudeSessionPersistence for session-id injection and save/restore
- **改动**：（包含在 reuseTab fix commit 中）
- **效果**：新增 `ClaudeSessionPersistence.swift`，实现 Claude session 自动恢复
- **实现**：
  - 启动 Claude 命令时注入 `--session-id <uuid>`
  - 退出时保存所有活跃的 Claude session 到 `~/.config/ghostty/claude-sessions.json`
  - 下次启动时用 `--resume <id>` 恢复对话（24 小时超时保护）

#### `623430fc` — Fix session persistence: save earlier, drop needsConfirmQuit filter, lowercase UUIDs
- **改动**：2 个文件，+5 / -6
- **效果**：将 save 从 `applicationWillTerminate` 移到 `applicationShouldTerminate`（窗口还活着时保存）；移除 needsConfirmQuit 过滤；UUID 改为小写以匹配 claude CLI 格式

#### `ed5e3338` — Add claude-resume CLI tool for cross-project session discovery and resume
- **改动**：1 个文件（新增），+246
- **效果**：独立 Python CLI 工具，跨所有 `~/.claude/projects/` 搜索 session 并在正确目录恢复
- **功能**：
  - `claude-resume <id>` — partial ID 匹配，自动 chdir + resume
  - `claude-resume --list [query]` — 列出最近 30 个 session
  - `claude-resume <id> --fork` — fork 为新 session

#### `15b1e7d2` — Remove 24h timeout from session persistence, update docs
- **改动**：3 个文件，+28 / -37
- **效果**：移除 24 小时 session 超时限制，文档同步更新

#### `064817af` — Skip archived projects when restoring Claude sessions on launch
- **改动**：1 个文件，+6
- **效果**：启动恢复时跳过归档项目，避免被 archive 的项目意外打开 tab

#### `7d7706a9` — Also skip archived projects when saving Claude sessions on quit
- **改动**：1 个文件，+5
- **效果**：退出保存时也跳过归档项目，与 restore 逻辑对称

#### `ca5d0224` — Fix --resume flag accumulating across save/restore cycles
- **改动**：2 个文件，+35 / -7
- **效果**：修复多次 save/restore 后命令行里 `--resume` 反复累积的问题

### 2.20 Resume Claude Session UI

#### `6d653a58` — Replace Cmd+Shift+T Ask AI sheet with Resume Claude Session UI
- **改动**：12 个文件，+649 / -168
- **效果**：`⌘⇧T` 打开的 Ask AI 浮窗替换为 Claude Session 选择器，列出当前项目最近的 session 并支持 `--resume`
- **实现**：新增 `ClaudeSessionScanner.swift`、`ResumeSessionView.swift`，复用现有 sheet 框架

#### `3c7d7c3e` — Make Resume Session sheet resizable with proper translucent background
- **改动**：2 个文件，+34 / -7
- **效果**：Resume sheet 支持拖拽改变大小，使用原生 vibrancy 半透明背景

#### `7c16b358` — Add Resume Claude session button to QuickLaunchBar
- **改动**：1 个文件，+11
- **效果**：QuickLaunchBar 增加 Resume 按钮，无需走 `⌘⇧T` 即可直接打开 session 选择器

#### `a7dff64e` — Move Resume/Settings buttons to left of QuickLaunchBar with hover feedback
- **改动**：1 个文件，+49 / -22
- **效果**：Resume/Settings 按钮迁移到 QuickLaunchBar 左侧，hover 时高亮反馈

#### `9ab9c119` — Resume Session: lazy metadata loading, resizable window, translucent material
- **改动**：2 个文件，+121 / -91
- **效果**：session 列表元数据延迟加载，sheet 打开瞬间不卡顿；支持 resize；半透明 material 背景

### 2.21 Sidebar 与 Project Settings 增强

#### `08456a46` — Sidebar: hover feedback for bottom buttons, right-click to add by path
- **改动**：1 个文件，+99 / -7
- **效果**：底部按钮 hover 高亮；"+" 按钮右键弹出输入框，可直接粘贴路径添加项目

#### `2ae36fb3` — Add toggles for Resume/Settings buttons and Project Settings context menu
- **改动**：4 个文件，+42 / -14
- **效果**：项目右键菜单新增 Project Settings 入口，可逐项目开关 Resume / Settings 按钮显隐

### 2.19 其他

#### `1e18b797` — ignore claude
- `.gitignore` 添加 Claude 相关路径

#### `04551c5f` — Consolidate CLAUDE.md: merge fork sidebar docs into root file
- 将 fork sidebar 文档合并到根目录 `CLAUDE.md`

### 2.22 SuperGhostty 品牌

#### `fa2825f4` — Rebrand to SuperGhostty (name, bundle ID, icon)
- **改动**：8 个文件，product name + bundle ID + 图标
- **效果**：
  - App 文件名 `Ghostty.app` → `SuperGhostty.app`
  - `CFBundleDisplayName` → `SuperGhostty`（Debug 为 `SuperGhostty[DEBUG]`）
  - `CFBundleIdentifier` → `com.billxc.superghostty`（Debug 为 `.debug` 后缀）
  - 替换主 icon 为 full-bleed 版本（Icon Composer 自动套 macOS squircle mask）
  - `images/Ghostty.icon/icon.json` 简化为单层（移除原 5 层合成：gloss/screen/bevel/etc.）
  - `Assets.xcassets/AppIconImage.imageset/` 同步更新 1024/512/256 三个尺寸
  - `build_test.sh` / `build_and_install.sh` 路径更新为 `SuperGhostty.app`
- **意图**：方便与 upstream Ghostty 并存安装；fork 数据隔离

#### `9adbc905` — Add build/ to .gitignore
- `.gitignore` 添加 `build/` 目录

#### `a2999678` — Add fork documentation to README with project sidebar features and quick start guide
- README 增加 fork 功能介绍和快速上手指南

#### `fe21dc65` — Add project sidebar screenshot to README
- README 增加 sidebar 截图

#### `e4114245` — Add macos/.build/ and .harness/ to .gitignore
- `.gitignore` 添加 `macos/.build/` 和 `.harness/` 目录

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

### Swift/macOS（新增 16 文件 + 修改 9 文件）

**新增文件：**

| 文件 | 说明 |
|------|------|
| `ProjectSidebar/ProjectConfig.swift` | 项目配置读写（`projects.json`），含 SidebarLayout 和 QuickCommand |
| `ProjectSidebar/ProjectListItem.swift` | 项目列表行视图 + 状态指示器 + StatusDots 网格 |
| `ProjectSidebar/ProjectSidebarState.swift` | 侧边栏状态管理（宽度、活跃项目、持久化、worktree、rename、archive） |
| `ProjectSidebar/ProjectSidebarView.swift` | 侧边栏主视图（含 Archived 折叠区域） |
| `ProjectSidebar/ProjectTabBar.swift` | 自定义 tab bar（过滤显示当前项目 tab，拖拽排序，LazyGit 特殊样式） |
| `ProjectSidebar/ProjectTabState.swift` | Tab 列表和选择状态单例 |
| `ProjectSidebar/QuickLaunchBar.swift` | AI 工具快速启动栏（支持自定义 Quick Commands） |
| `ProjectSidebar/ProjectToolLauncher.swift` | 工具启动逻辑（Quick Launch Bar、快捷键、Ask AI 共用） |
| `ProjectSidebar/ClaudeStatusServer.swift` | Unix socket 服务器，接收 Claude Code 状态事件 + macOS 通知 |
| `ProjectSidebar/GitWorktreeManager.swift` | Git 子进程封装，worktree 创建/删除/分支查询 |
| `ProjectSidebar/NewWorktreeSheet.swift` | 创建 worktree 的 SwiftUI 弹窗 |
| `ProjectSidebar/GitStatusManager.swift` | Git 状态轮询（分支名、dirty、ahead/behind） |
| `ProjectSidebar/AskAISheet.swift` | Ask AI 对话框（⌘⇧T） |
| `ProjectSidebar/ClaudeSessionPersistence.swift` | Claude session 保存/恢复（退出时保存 session ID，启动时 --resume） |
| `ProjectSidebar/QuickCommandDefaults.swift` | 集中管理默认 quick commands 和 AI 工具列表 |
| `ProjectSidebar/QuickCommandsEditor.swift` | Quick commands 可视化编辑器（添加/删除/排序/重置） |

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

### 构建脚本和工具（4 文件）

| 文件 | 说明 |
|------|------|
| `build_test.sh` | Debug 编译（Zig + Swift），输出 `build/Ghostty.app`，注入 git hash |
| `build_debug.sh` | Debug 编译，输出 `build/Debug/` |
| `build_and_install.sh` | Release 编译 + 部署到 ~/Applications + ad-hoc 重签名（支持 --universal），注入 git hash |
| `claude-resume` | Python CLI，跨项目搜索 Claude session 并在正确目录恢复 |

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

### 4.6 ReuseTab 检测命令退出的方式演进

最初通过在 `initialInput` 末尾链接 `printf SessionEnd | nc` 通知 ClaudeStatusServer 命令退出。后发现此方案在 bracketed paste mode 下不可靠，且增加了命令复杂度。最终方案使用 Ghostty 原生的 shell integration (OSC 133) —— `needsConfirmQuit` 属性检测 shell 是否处于 idle 状态（即光标在 prompt 上），完全去除了外部通知机制。

### 4.7 Claude Session 恢复的 `applicationShouldTerminate` 时机

最初在 `applicationWillTerminate` 中保存 session，但此时窗口和进程已开始销毁，`TerminalController.all` 可能为空。移到 `applicationShouldTerminate` 时窗口仍然完整存活，能正确收集所有活跃的 Claude session ID。

---

## 五、已知限制

1. **原生 tab bar 闪现** — 启动时原生 tab bar 可能短暂显示后被隐藏
2. **titlebar-style 冲突** — `macos-titlebar-style = tabs` 与自定义 tab bar 冲突，不要在配置中设置
3. **Ctrl+Tab 全局** — `Ctrl+Tab` 是系统级快捷键，仍会切换所有 tab（不限于当前项目）
4. **Ask AI 中文输入** — `⌘⇧T` 对话框提交的中文在启动命令中会乱码
5. **macOS 通知未生效** — Claude 完成/需要操作时的系统通知功能为 WIP，尚未调通
6. **Session 恢复 24h 超时** — 保存超过 24 小时的 Claude session 不会自动恢复（防止恢复过期对话）
