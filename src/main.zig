const std = @import("std");
const print = std.debug.print;
const c = @cImport({
    @cDefine("_GNU_SOURCE", "1");
    @cUndef("_DEFAULT_SOURCE");
    @cUndef("_XOPEN_SOURCE");
    @cInclude("ncurses.h");
});

const terminal_mod = @import("terminal.zig");
const Terminal = terminal_mod.Terminal;
const shell_mod = @import("shell.zig");
const Shell = shell_mod.Shell;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // ncursesの初期化
    _ = c.initscr();
    defer _ = c.endwin();

    // カラー設定の初期化（Gitブランチ表示用）
    if (c.has_colors()) {
        _ = c.start_color();
        // デフォルトカラーの使用を有効化
        _ = c.use_default_colors();
        // ブランチ名表示用のカラーペア（緑色）
        _ = c.init_pair(1, c.COLOR_GREEN, -1);
        // テスト用の追加カラーペア
        _ = c.init_pair(2, c.COLOR_RED, -1);
        _ = c.init_pair(3, c.COLOR_BLUE, -1);
    }

    // カーソルを非表示に
    _ = c.curs_set(0);

    // キー入力の即座認識
    _ = c.cbreak();
    _ = c.noecho();

    // 特殊キーの有効化
    _ = c.keypad(c.stdscr, true);

    // ターミナルエミュレータの初期化
    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // メインループ
    try runMainLoop(&terminal);
}

fn runMainLoop(terminal: *Terminal) !void {
    var running = true;

    while (running) {
        // 画面の描画
        try terminal.draw();

        // キー入力の処理
        const key = c.getch();

        switch (key) {
            // Ctrl+C で終了
            3 => running = false,
            // Ctrl+D で終了
            4 => running = false,
            // ESC で終了
            27 => running = false,
            // Enter
            10, 13 => try terminal.handleEnter(),
            // Backspace
            8, 127, c.KEY_BACKSPACE => try terminal.handleBackspace(),
            // 矢印キー
            c.KEY_UP => try terminal.handleArrowKey(.up),
            c.KEY_DOWN => try terminal.handleArrowKey(.down),
            c.KEY_LEFT => try terminal.handleArrowKey(.left),
            c.KEY_RIGHT => try terminal.handleArrowKey(.right),
            // 通常の文字
            else => {
                if (key >= 32 and key <= 126) {
                    try terminal.handleChar(@intCast(key));
                }
            },
        }
    }
}

test "basic terminal functionality" {
    const testing = std.testing;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // 基本的な機能のテスト
    try testing.expect(terminal.cursor_x == 0);
    try testing.expect(terminal.cursor_y == 0);
}
