// ghostty-welcome — minimal PTY child used as a placeholder when a Ghostty
// window has no project / no real tab. Renders an ANSI welcome screen and
// blocks on stdin. No shell, no rc files, no allocations.
//
// Replaces the cost of spawning `zsh -l` (oh-my-zsh, PATH scans, etc.) for
// the empty-window case. Real shells are still spawned for actual tabs.

const std = @import("std");
const posix = std.posix;
const builtin = @import("builtin");

const ESC = "\x1b[";
const CLEAR = ESC ++ "2J" ++ ESC ++ "H";
const RESET = ESC ++ "0m";
const BOLD = ESC ++ "1m";
const DIM = ESC ++ "2m";
const CYAN = ESC ++ "36m";
const YELLOW = ESC ++ "33m";
const HIDE_CURSOR = ESC ++ "?25l";
const SHOW_CURSOR = ESC ++ "?25h";

const SCREEN =
    CLEAR ++ HIDE_CURSOR ++
    "\n" ++
    "  " ++ CYAN ++ BOLD ++ "👻  Ghostty" ++ RESET ++ "\n" ++
    "  " ++ DIM ++ "ready when you are" ++ RESET ++ "\n" ++
    "\n" ++
    "  " ++ YELLOW ++ "⌘T" ++ RESET ++ "          New tab in current project\n" ++
    "  " ++ YELLOW ++ "⌘⇧S" ++ RESET ++ "         Toggle sidebar\n" ++
    "  " ++ YELLOW ++ "⌘J / ⌘K" ++ RESET ++ "     Switch project\n" ++
    "  " ++ YELLOW ++ "⌘H / ⌘L" ++ RESET ++ "     Switch tab\n" ++
    "\n" ++
    "  " ++ DIM ++ "Pick a project from the sidebar, or use the quick" ++ RESET ++ "\n" ++
    "  " ++ DIM ++ "launch buttons to start Claude / Codex / Copilot." ++ RESET ++ "\n" ++
    "\n" ++
    "  " ++ DIM ++ "Press " ++ RESET ++ YELLOW ++ "Enter" ++ RESET ++ DIM ++ " for a shell." ++ RESET ++ "\n";

var redraw_pending: std.atomic.Value(u8) = .init(1);

fn onWinch(_: c_int) callconv(.c) void {
    redraw_pending.store(1, .seq_cst);
}

fn writeAll(fd: posix.fd_t, bytes: []const u8) void {
    var i: usize = 0;
    while (i < bytes.len) {
        const n = posix.write(fd, bytes[i..]) catch return;
        if (n == 0) return;
        i += n;
    }
}

pub fn main() !void {
    const out_fd = posix.STDOUT_FILENO;
    const in_fd = posix.STDIN_FILENO;

    var sa: posix.Sigaction = .{
        .handler = .{ .handler = onWinch },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    posix.sigaction(posix.SIG.WINCH, &sa, null);

    var buf: [256]u8 = undefined;
    while (true) {
        if (redraw_pending.swap(0, .seq_cst) == 1) writeAll(out_fd, SCREEN);

        // Block on stdin. EINTR (from SIGWINCH) loops back and triggers a
        // redraw. ENTER → exit cleanly so the Swift side knows the
        // user wants a real shell and can replace this tab. Other input is
        // drained and ignored so typing doesn't accumulate.
        const n = posix.read(in_fd, &buf) catch |err| switch (err) {
            error.WouldBlock => continue,
            error.Unexpected => continue, // signal interrupt
            else => break,
        };
        if (n == 0) break; // EOF / pty closed

        for (buf[0..n]) |c| {
            if (c == '\r' or c == '\n') {
                writeAll(out_fd, SHOW_CURSOR ++ RESET);
                std.process.exit(0);
            }
        }
    }

    writeAll(out_fd, SHOW_CURSOR ++ RESET);
}
