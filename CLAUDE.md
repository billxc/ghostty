# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ghostty is a fast, native, feature-rich terminal emulator. The core is written in Zig with platform-native UIs: SwiftUI on macOS, GTK 4 on Linux/FreeBSD. A public C library (`libghostty-vt`) provides embeddable terminal emulation.

This fork adds a **Project Sidebar** feature, turning the terminal into a project-organized AI development environment.

## Project Sidebar (Fork)

### 核心功能
- **Project Sidebar** — 窗口左侧可折叠侧边栏，项目列表来自 `~/.config/ghostty/projects.json`
- **Tab 按项目分组** — 自定义 `ProjectTabBar` 替代原生 tab bar，只显示当前 project 的 tabs
- **Quick Launch Bar** — 一键启动 Terminal / Claude(YOLO) / Codex(YOLO) / Copilot
- **键盘导航** — `⌘H/L` 切换 tab，`⌘J/K` 切换 project，`⌘⇧S` toggle sidebar

### 改动范围
- **Zig 核心层（5 文件）**: action.zig, Binding.zig, command.zig, Surface.zig, Config.zig — 注册 5 个新 action
- **C API（1 文件）**: ghostty.h — 新增 5 个 GHOSTTY_ACTION_ enum
- **Swift/macOS（8 文件修改 + 6 文件新增）**: ProjectSidebar/ 目录，TerminalView, AppDelegate, TerminalController, Ghostty.App, GhosttyPackage, TerminalWindow 等

### 关键技术决策
- Tool 命令使用 `initialInput`（非 `config.command`），让 login shell 加载 PATH（解决 Homebrew 找不到命令的问题）
- 所有 tabs 保留在同一个 NSWindowTabGroup 中，原生 tab bar 隐藏，用自定义 ProjectTabBar 过滤显示
- 快捷键通过完整的 Zig keybind pipeline 分发（非 SwiftUI 层 hack）
- projects 列表第一个就是默认 project，启动时自动打开；右键 "Move to Top" 调整顺序

### 已知问题
1. 启动时原生 tab bar 可能短暂闪现
2. `macos-titlebar-style = tabs` 与自定义 tab bar 冲突，不要设置
3. Ctrl+Tab 是系统级快捷键，仍切换所有 tabs

## Build Commands

**Requires Zig 0.15.2+. macOS requires Xcode 26 with macOS 26 SDK.**

| Command | Description |
|---|---|
| `zig build` | Debug build (default) |
| `zig build run` | Build and run Ghostty |
| `zig build test` | Run all Zig unit tests (slow) |
| `zig build test -Dtest-filter=<name>` | Run tests matching filter (preferred) |
| `zig build test-lib-vt -Dtest-filter=<name>` | Test libghostty-vt only |
| `zig build run-valgrind` | Run under Valgrind (Linux) |
| `zig build update-translations` | Update i18n strings |
| `zig build dist` / `distcheck` | Source tarball |

**macOS-specific:**
- Skip app bundle for faster builds: `zig build -Demit-macos-app=false`
- Build macOS app: `macos/build.nu [--scheme Ghostty] [--configuration Debug] [--action build]`
- Run macOS tests: `macos/build.nu --action test`
- If Zig core code (`src/`) was modified, run `zig build -Demit-macos-app=false` before `macos/build.nu`

**Fork 构建脚本:**
- `./build_test.sh` — Debug 编译（Zig + Swift），输出到 `build/Ghostty.app`
- `./build_test.sh --swift-only` — 只编译 Swift，跳过 Zig（只改了 `macos/Sources/` 时用）
- `./build_and_install.sh` — Release 编译并部署到 ~/Applications（仅在用户明确要求部署时运行）

**libghostty-vt:**
- Build: `zig build -Demit-lib-vt`
- Build WASM: `zig build -Demit-lib-vt -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall`

## Formatting and Linting

All enforced in CI:

| Tool | Scope | Command |
|---|---|---|
| `zig fmt` | Zig code | `zig fmt .` |
| SwiftLint | Swift code | `swiftlint lint --strict --fix` |
| Prettier | HTML, Markdown, JSON, YAML | `prettier --write .` |
| Alejandra | Nix files | `alejandra .` |
| ShellCheck | Shell scripts | `shellcheck --check-sourced --severity=warning` |

## Architecture

**Three-layer design:**

1. **libghostty-vt** (`src/terminal/`, `include/ghostty/vt/`) — Zero-dependency terminal emulation library. VT parser state machine, screen/grid management, scrollback. Public C API. Targets macOS, Linux, Windows, WASM.

2. **Rendering** (`src/renderer/`) — Metal on macOS (`src/renderer/metal/`), OpenGL on Linux (`src/renderer/opengl/`). Font handling in `src/font/` uses CoreText (macOS) or Fontconfig (Linux).

3. **Application Runtime** (`src/apprt/`) — Platform abstraction. GTK implementation in `src/apprt/gtk/`. macOS UI is in `macos/Sources/` (SwiftUI, builds via Xcode/build.nu, not zig build).

**Key source paths:**
- `src/terminal/Parser.zig` — VT sequence parser (state machine)
- `src/terminal/Terminal.zig` — Main terminal structure
- `src/terminal/Screen.zig` — Screen/grid management
- `src/config/` — Configuration parsing
- `src/input/` — Input handling (keyboard, mouse, IME)
- `src/Surface.zig` — Terminal surface/window
- `src/App.zig` — Main GUI app
- `src/build/` — Modular build system (split from build.zig)
- `pkg/` — 25+ C/C++ dependency definitions
- `macos/Sources/Features/ProjectSidebar/` — Project Sidebar feature (fork)

**Threading model:** Dedicated threads for PTY read, PTY write, and GPU rendering. Main thread handles events.

**C enum convention:** All C enums in `include/ghostty/vt/` must have `_MAX_VALUE = GHOSTTY_ENUM_MAX_VALUE` as last entry (pre-C23 portability).

**Detailed architecture docs:** See `.claude/knowledge_base/` for deep dives into each subsystem (Zig core, macOS Swift, rendering, config, font, input, build, shell integration, CI).

## Logging

Debug builds log to stderr. Control with `GHOSTTY_LOG` env var: `stderr`, `macos` (unified log), combine with commas, prefix `no-` to disable. macOS logs: `sudo log stream --level debug --predicate 'subsystem=="com.mitchellh.ghostty"'`.

## Fork Changelog 维护

本 fork 的所有下游改动记录在 `FORK_CHANGELOG.md` 中。**每次 commit 涉及 fork 功能的改动后，必须同步更新该文件。**

### 更新规则

1. **新增 commit 时**：在对应功能模块的 section（2.1 ~ 2.10）中追加 commit 记录，格式：
   ```markdown
   #### `<短hash>` — <commit message>
   - **改动**：N 个文件，+X / -Y
   - **效果**：<一句话说明用户可感知的变化>
   - **实现**：（可选，仅非显而易见的实现需要说明）
   ```
2. **更新头部统计**：修改文件头部的 commit 数、文件数、行数（运行 `git diff --stat <merge-base>..main` 获取最新数字）
3. **新增文件时**：在第三节「改动文件清单」的对应表格中添加条目
4. **新增功能模块时**：在第二节新建 `### 2.X` 子节
5. **技术决策变更时**：更新第四节「关键技术决策」
6. **已知限制变更时**：更新第五节

### 什么时候不需要更新

- 仅修改 `CLAUDE.md`、`.claude/` 目录、`.gitignore` 等非功能文件时不需要更新
- 仅修改构建脚本且不影响功能时，在 2.9 节简单追加即可

## Issue and PR Policy

Never create issues or PRs on behalf of the user. AI usage must be disclosed per CONTRIBUTING.md.

## Work Tracking System

所有 Claude session 必须使用 `.claude/tracking/` 来管理工作状态。

### 目录结构

```
.claude/tracking/
├── SESSIONS.md          # session 注册表（活跃/已完成）
├── TODO.md              # 共享待办，认领时标注 session ID
├── SUMMARY.md           # 共享汇总，完成后追加写入
├── KNOWLEDGE.md         # 共享知识库，发现时追加写入
└── sessions/
    ├── _template.md     # session 文件模板
    └── <session-id>.md  # 各 session 独立状态文件
```

### Session 生命周期

1. **启动**: 读取 `SESSIONS.md` 了解当前活跃 session，避免冲突
2. **注册**: 复制 `sessions/_template.md` 创建 `sessions/<日期>-<关键词>.md`（如 `0422-sidebar-fix.md`），并在 `SESSIONS.md` 的 Active Sessions 中添加条目
3. **工作中**: 在自己的 session 文件中更新 Working 状态；从 `TODO.md` 认领任务时标注 `@session-id`
4. **结束**: 将成果追加写入 `SUMMARY.md` 和 `KNOWLEDGE.md`，session 文件状态改为 done，从 Active 移到 Completed

### 多 Session 协作规则

- **TODO.md**: 共享，认领任务标注 `@session-id`，先到先得
- **SUMMARY.md / KNOWLEDGE.md**: append-only，写入时标注 `@session-id`
- **sessions/*.md**: 每个 session 只写自己的文件，天然隔离
- 开始工作前先读取共享文件，了解其他 session 的进展，避免重复劳动
