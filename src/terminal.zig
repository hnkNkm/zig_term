const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const c = @cImport({
    @cInclude("ncurses.h");
});

const shell_mod = @import("shell.zig");
const Shell = shell_mod.Shell;

pub const ArrowDirection = enum {
    up,
    down,
    left,
    right,
};

pub const Terminal = struct {
    allocator: Allocator,
    width: i32,
    height: i32,
    cursor_x: i32,
    cursor_y: i32,
    lines: ArrayList(ArrayList(u8)),
    current_line: ArrayList(u8),
    command_history: ArrayList(ArrayList(u8)),
    history_index: usize,
    shell: Shell,

    pub fn init(allocator: Allocator) !Terminal {
        var terminal = Terminal{
            .allocator = allocator,
            .width = 0,
            .height = 0,
            .cursor_x = 0,
            .cursor_y = 0,
            .lines = ArrayList(ArrayList(u8)).init(allocator),
            .current_line = ArrayList(u8).init(allocator),
            .command_history = ArrayList(ArrayList(u8)).init(allocator),
            .history_index = 0,
            .shell = try Shell.init(allocator),
        };

        // ターミナルサイズの取得
        terminal.height = c.LINES;
        terminal.width = c.COLS;

        return terminal;
    }

    pub fn deinit(self: *Terminal) void {
        for (self.lines.items) |line| {
            line.deinit();
        }
        self.lines.deinit();
        self.current_line.deinit();
        
        for (self.command_history.items) |cmd| {
            cmd.deinit();
        }
        self.command_history.deinit();
        
        self.shell.deinit();
    }

    pub fn draw(self: *Terminal) !void {
        // 画面クリア
        _ = c.clear();

        // ターミナルサイズの更新
        self.height = c.LINES;
        self.width = c.COLS;

        var y: i32 = 0;
        
        // 過去の行を描画
        for (self.lines.items) |line| {
            if (y >= self.height) break;
            _ = c.mvprintw(y, 0, "%.*s", @as(c_int, @intCast(line.items.len)), line.items.ptr);
            y += 1;
        }

        // 現在の行を描画（プロンプト付き）
        if (y < self.height) {
            const prompt = try self.getPrompt();
            defer self.allocator.free(prompt);
            
            _ = c.mvprintw(y, 0, "%s%.*s", 
                prompt.ptr, 
                @as(c_int, @intCast(self.current_line.items.len)), 
                self.current_line.items.ptr);
            
            // カーソル位置の設定
            _ = c.move(y, @as(c_int, @intCast(prompt.len)) + self.cursor_x);
        }

        // 画面の更新
        _ = c.refresh();
    }

    pub fn handleChar(self: *Terminal, char: u8) !void {
        try self.current_line.insert(@intCast(self.cursor_x), char);
        self.cursor_x += 1;
    }

    pub fn handleBackspace(self: *Terminal) !void {
        if (self.cursor_x > 0) {
            _ = self.current_line.orderedRemove(@intCast(self.cursor_x - 1));
            self.cursor_x -= 1;
        }
    }

    pub fn handleEnter(self: *Terminal) !void {
        // コマンドの実行
        if (self.current_line.items.len > 0) {
            // コマンド履歴に追加
            var cmd_copy = ArrayList(u8).init(self.allocator);
            try cmd_copy.appendSlice(self.current_line.items);
            try self.command_history.append(cmd_copy);
            self.history_index = self.command_history.items.len;

            // 現在の行（プロンプト付き）を履歴に追加
            var full_line = ArrayList(u8).init(self.allocator);
            const prompt = try self.getPrompt();
            defer self.allocator.free(prompt);
            try full_line.appendSlice(prompt);
            try full_line.appendSlice(self.current_line.items);
            try self.lines.append(full_line);

            // コマンドの実行
            const result = try self.shell.execute(self.current_line.items);
            
            // clearコマンドの特別処理
            if (std.mem.eql(u8, result, "\x1b[2J\x1b[H")) {
                // 画面をクリアして行履歴も削除
                for (self.lines.items) |line| {
                    line.deinit();
                }
                self.lines.clearRetainingCapacity();
                self.allocator.free(result);
            } else {
                // 結果の表示
                if (result.len > 0) {
                    var result_lines = std.mem.splitAny(u8, result, "\n");
                    while (result_lines.next()) |line| {
                        if (line.len > 0) {
                            var output_line = ArrayList(u8).init(self.allocator);
                            try output_line.appendSlice(line);
                            try self.lines.append(output_line);
                        }
                    }
                }
                self.allocator.free(result);
            }
        } else {
            // 空行の場合
            var empty_line = ArrayList(u8).init(self.allocator);
            const prompt = try self.getPrompt();
            defer self.allocator.free(prompt);
            try empty_line.appendSlice(prompt);
            try self.lines.append(empty_line);
        }

        // 新しいプロンプトの準備
        self.current_line.clearRetainingCapacity();
        self.cursor_x = 0;
        
        // スクロール処理
        try self.handleScroll();
    }

    pub fn handleArrowKey(self: *Terminal, direction: ArrowDirection) !void {
        switch (direction) {
            .left => {
                if (self.cursor_x > 0) {
                    self.cursor_x -= 1;
                }
            },
            .right => {
                if (self.cursor_x < self.current_line.items.len) {
                    self.cursor_x += 1;
                }
            },
            .up => {
                if (self.history_index > 0) {
                    self.history_index -= 1;
                    const cmd = self.command_history.items[self.history_index];
                    self.current_line.clearRetainingCapacity();
                    try self.current_line.appendSlice(cmd.items);
                    self.cursor_x = @intCast(self.current_line.items.len);
                }
            },
            .down => {
                if (self.history_index < self.command_history.items.len) {
                    self.history_index += 1;
                    self.current_line.clearRetainingCapacity();
                    if (self.history_index < self.command_history.items.len) {
                        const cmd = self.command_history.items[self.history_index];
                        try self.current_line.appendSlice(cmd.items);
                    }
                    self.cursor_x = @intCast(self.current_line.items.len);
                }
            },
        }
    }

    fn handleScroll(self: *Terminal) !void {
        // ターミナルの高さを超えた場合、古い行を削除
        const max_lines = @max(0, self.height - 2); // プロンプト用の行を残す
        while (self.lines.items.len > max_lines) {
            var removed = self.lines.orderedRemove(0);
            removed.deinit();
        }
    }

    fn getPrompt(self: *Terminal) ![]const u8 {
        const cwd = self.shell.cwd.items;
        
        // ホームディレクトリの場合は ~ で表示
        if (std.process.getEnvVarOwned(self.allocator, "HOME")) |home| {
            defer self.allocator.free(home);
            if (std.mem.startsWith(u8, cwd, home)) {
                const relative_path = cwd[home.len..];
                if (relative_path.len == 0) {
                    return try self.allocator.dupe(u8, "~ $ ");
                } else {
                    return try std.fmt.allocPrint(self.allocator, "~{s} $ ", .{relative_path});
                }
            }
        } else |_| {
            // HOME環境変数が取得できない場合は何もしない
        }
        
        // ディレクトリ名のみを表示（フルパスが長い場合）
        if (std.mem.lastIndexOfScalar(u8, cwd, '/')) |last_slash| {
            const dir_name = cwd[last_slash + 1..];
            if (dir_name.len == 0) {
                return try self.allocator.dupe(u8, "/ $ ");
            } else {
                return try std.fmt.allocPrint(self.allocator, "{s} $ ", .{dir_name});
            }
        }
        
        return try std.fmt.allocPrint(self.allocator, "{s} $ ", .{cwd});
    }
}; 