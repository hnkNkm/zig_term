const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const c = @cImport({
    @cInclude("ncurses.h");
});

const shell_mod = @import("shell.zig");
const Shell = shell_mod.Shell;
const completion_mod = @import("completion.zig");
const Completer = completion_mod.Completer;
const CompletionResult = completion_mod.CompletionResult;

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
    completer: Completer,
    // 補完表示状態
    showing_completions: bool,
    completion_suggestions: ?CompletionResult,
    completion_selected_index: usize,

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
            .completer = Completer.init(allocator),
            .showing_completions = false,
            .completion_suggestions = null,
            .completion_selected_index = 0,
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
        self.completer.deinit();

        if (self.completion_suggestions) |*suggestions| {
            suggestions.deinit();
        }
    }

    pub fn draw(self: *Terminal) !void {
        // 画面クリア
        _ = c.clear();

        // ターミナルサイズの更新
        self.height = c.LINES;
        self.width = c.COLS;

        var y: i32 = 0;
        const max_content_lines = if (self.showing_completions) self.height - 8 else self.height - 2;

        // 過去の行を描画
        for (self.lines.items) |line| {
            if (y >= max_content_lines) break;
            _ = c.mvprintw(y, 0, "%.*s", @as(c_int, @intCast(line.items.len)), line.items.ptr);
            y += 1;
        }

        // 現在の行を描画（プロンプト付き）
        if (y < max_content_lines) {
            const prompt = try self.getPrompt();
            defer self.allocator.free(prompt);

            // プロンプトを描画し、ブランチのハイライト処理を行う
            _ = c.move(y, 0);
            var visible_prompt_len: usize = 0;

            var i: usize = 0;
            while (i < prompt.len) {
                const START_MARKER = "§START§";
                const END_MARKER = "§END§";

                if (i + START_MARKER.len <= prompt.len and std.mem.eql(u8, prompt[i .. i + START_MARKER.len], START_MARKER)) {
                    // ブランチ名開始マーカー
                    _ = c.attron(c.COLOR_PAIR(1));
                    i += START_MARKER.len;
                } else if (i + END_MARKER.len <= prompt.len and std.mem.eql(u8, prompt[i .. i + END_MARKER.len], END_MARKER)) {
                    // ブランチ名終了マーカー
                    _ = c.attroff(c.COLOR_PAIR(1));
                    i += END_MARKER.len;
                } else {
                    // 通常の文字
                    _ = c.addch(prompt[i]);
                    visible_prompt_len += 1;
                    i += 1;
                }
            }

            // コマンドライン部分を描画
            _ = c.printw("%.*s", @as(c_int, @intCast(self.current_line.items.len)), self.current_line.items.ptr);

            // カーソル位置の設定（マーカーを除いた実際の表示文字数に基づく）
            _ = c.move(y, @as(c_int, @intCast(visible_prompt_len)) + self.cursor_x);

            y += 1;
        }

        // 補完候補を表示
        if (self.showing_completions) {
            try self.drawCompletions(y);
        }

        // 画面の更新
        _ = c.refresh();
    }

    /// 補完候補の描画
    fn drawCompletions(self: *Terminal, start_y: i32) !void {
        if (self.completion_suggestions) |*suggestions| {
            if (suggestions.suggestions.items.len == 0) return;

            // 補完候補のヘッダー
            _ = c.mvprintw(start_y, 0, "Completions:");
            _ = c.attron(c.A_BOLD);
            _ = c.mvprintw(start_y + 1, 0, "---------------------------------------");
            _ = c.attroff(c.A_BOLD);

            const max_suggestions = @min(suggestions.suggestions.items.len, 6); // 最大6つの候補を表示
            const start_index = if (self.completion_selected_index >= 6)
                self.completion_selected_index - 5
            else
                0;

            for (0..max_suggestions) |i| {
                const suggestion_index = start_index + i;
                if (suggestion_index >= suggestions.suggestions.items.len) break;

                const suggestion = suggestions.suggestions.items[suggestion_index];
                const display_y = start_y + 2 + @as(i32, @intCast(i));

                if (suggestion_index == self.completion_selected_index) {
                    // 選択された候補をハイライト
                    _ = c.attron(c.A_REVERSE);
                    _ = c.mvprintw(display_y, 0, " %.*s", @as(c_int, @intCast(suggestion.len)), suggestion.ptr);
                    _ = c.attroff(c.A_REVERSE);
                } else {
                    _ = c.mvprintw(display_y, 0, " %.*s", @as(c_int, @intCast(suggestion.len)), suggestion.ptr);
                }
            }

            // 補完候補の操作説明
            const help_y = start_y + 2 + @as(i32, @intCast(max_suggestions)) + 1;
            _ = c.attron(c.A_DIM);
            _ = c.mvprintw(help_y, 0, "TAB: next  Enter: select  ESC: cancel");
            _ = c.attroff(c.A_DIM);
        }
    }

    pub fn handleChar(self: *Terminal, char: u8) !void {
        // 補完候補が表示されている場合は隠す
        if (self.showing_completions) {
            self.hideCompletions();
        }

        try self.current_line.insert(@intCast(self.cursor_x), char);
        self.cursor_x += 1;
    }

    pub fn handleBackspace(self: *Terminal) !void {
        // 補完候補が表示されている場合は隠す
        if (self.showing_completions) {
            self.hideCompletions();
        }

        if (self.cursor_x > 0) {
            _ = self.current_line.orderedRemove(@intCast(self.cursor_x - 1));
            self.cursor_x -= 1;
        }
    }

    pub fn handleEnter(self: *Terminal) !void {
        // 補完候補が表示されている場合、選択された候補を適用
        if (self.showing_completions) {
            try self.applySelectedCompletion();
            return;
        }

        // 既存のEnter処理
        // コマンドの実行
        if (self.current_line.items.len > 0) {
            // コマンド履歴に追加
            var cmd_copy = ArrayList(u8).init(self.allocator);
            try cmd_copy.appendSlice(self.current_line.items);
            try self.command_history.append(cmd_copy);
            self.history_index = self.command_history.items.len;

            // インタラクティブプログラムの判定
            const command = self.getFirstCommand();
            const is_interactive = self.isInteractiveCommand(command);

            if (!is_interactive) {
                // 非インタラクティブコマンドの場合のみ、現在の行（プロンプト付き）を履歴に追加
                var full_line = ArrayList(u8).init(self.allocator);
                const prompt = try self.getPromptForHistory();
                defer self.allocator.free(prompt);
                try full_line.appendSlice(prompt);
                try full_line.appendSlice(self.current_line.items);
                try self.lines.append(full_line);
            }

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
            } else if (is_interactive) {
                // インタラクティブプログラムの場合は、画面を完全にクリアして再描画
                _ = c.clear();
                _ = c.refresh();
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
            const prompt = try self.getPromptForHistory();
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

    // コマンドラインから最初のコマンドを抽出
    fn getFirstCommand(self: *Terminal) []const u8 {
        if (self.current_line.items.len == 0) return "";

        var it = std.mem.tokenizeAny(u8, self.current_line.items, " \t");
        return it.next() orelse "";
    }

    // インタラクティブコマンドかどうかを判定
    fn isInteractiveCommand(self: *Terminal, command: []const u8) bool {
        _ = self; // suppress unused parameter warning
        const interactive_programs = [_][]const u8{ "vim", "nvim", "nano", "emacs", "less", "more", "man", "top", "htop", "vi", "edit", "pico", "joe", "micro", "helix", "tmux", "screen", "bash", "zsh", "fish", "sh", "csh", "tcsh", "ksh", "dash" };

        for (interactive_programs) |prog| {
            if (std.mem.eql(u8, command, prog)) {
                return true;
            }
        }
        return false;
    }

    pub fn handleArrowKey(self: *Terminal, direction: ArrowDirection) !void {
        switch (direction) {
            .left => {
                // 補完候補が表示されている場合は隠す
                if (self.showing_completions) {
                    self.hideCompletions();
                }

                if (self.cursor_x > 0) {
                    self.cursor_x -= 1;
                }
            },
            .right => {
                // 補完候補が表示されている場合は隠す
                if (self.showing_completions) {
                    self.hideCompletions();
                }

                if (self.cursor_x < self.current_line.items.len) {
                    self.cursor_x += 1;
                }
            },
            .up => {
                if (self.showing_completions) {
                    // 補完候補が表示されている場合、前の候補を選択
                    if (self.completion_suggestions) |*suggestions| {
                        if (suggestions.suggestions.items.len > 0) {
                            if (self.completion_selected_index == 0) {
                                self.completion_selected_index = suggestions.suggestions.items.len - 1;
                            } else {
                                self.completion_selected_index -= 1;
                            }
                        }
                    }
                } else {
                    // 通常のコマンド履歴
                    if (self.history_index > 0) {
                        self.history_index -= 1;
                        const cmd = self.command_history.items[self.history_index];
                        self.current_line.clearRetainingCapacity();
                        try self.current_line.appendSlice(cmd.items);
                        self.cursor_x = @intCast(self.current_line.items.len);
                    }
                }
            },
            .down => {
                if (self.showing_completions) {
                    // 補完候補が表示されている場合、次の候補を選択
                    if (self.completion_suggestions) |*suggestions| {
                        if (suggestions.suggestions.items.len > 0) {
                            self.completion_selected_index = (self.completion_selected_index + 1) % suggestions.suggestions.items.len;
                        }
                    }
                } else {
                    // 通常のコマンド履歴
                    if (self.history_index < self.command_history.items.len) {
                        self.history_index += 1;
                        self.current_line.clearRetainingCapacity();
                        if (self.history_index < self.command_history.items.len) {
                            const cmd = self.command_history.items[self.history_index];
                            try self.current_line.appendSlice(cmd.items);
                        }
                        self.cursor_x = @intCast(self.current_line.items.len);
                    }
                }
            },
        }
    }

    /// ESCキーで補完候補を隠す
    pub fn handleEscape(self: *Terminal) bool {
        if (self.showing_completions) {
            self.hideCompletions();
            return true; // 補完候補が表示されていた
        }
        return false; // 補完候補は表示されていなかった
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

        // Gitブランチ名の取得
        var branch_name_owned: ?[]u8 = null;
        defer if (branch_name_owned) |branch| self.allocator.free(branch);

        // .gitディレクトリの確認
        const dot_git_path = std.fs.path.join(self.allocator, &.{ cwd, ".git" }) catch null;
        defer if (dot_git_path) |path| self.allocator.free(path);

        if (dot_git_path) |git_path| {
            const git_exists = blk: {
                std.fs.cwd().access(git_path, .{}) catch break :blk false;
                break :blk true;
            };
            if (git_exists) {
                // Gitブランチ名の取得
                var child = std.process.Child.init(&.{ "git", "symbolic-ref", "--short", "HEAD" }, self.allocator);

                var cwd_dir = std.fs.cwd().openDir(cwd, .{}) catch null;
                defer if (cwd_dir) |*dir| dir.close();

                if (cwd_dir) |*dir| {
                    child.cwd_dir = dir.*;
                    child.stdout_behavior = .Pipe;
                    child.stderr_behavior = .Ignore;

                    var spawn_succeeded = true;
                    child.spawn() catch {
                        spawn_succeeded = false;
                    };

                    if (spawn_succeeded) {
                        const MAX_BRANCH_NAME_LEN = 64;
                        const raw_branch = child.stdout.?.reader().readAllAlloc(self.allocator, MAX_BRANCH_NAME_LEN) catch null;
                        _ = child.wait() catch {};

                        if (raw_branch) |branch_raw| {
                            const trimmed = std.mem.trim(u8, branch_raw, " \n\r");
                            if (trimmed.len > 0) {
                                branch_name_owned = self.allocator.dupe(u8, trimmed) catch null;
                            }
                            self.allocator.free(branch_raw);
                        }
                    }
                }
            }
        }

        // プロンプトのパス部分を決定
        var path_part: []const u8 = undefined;
        var path_allocated = false;
        defer if (path_allocated) self.allocator.free(path_part);

        // ホームディレクトリの場合は ~ で表示
        if (std.process.getEnvVarOwned(self.allocator, "HOME")) |home| {
            defer self.allocator.free(home);
            if (std.mem.startsWith(u8, cwd, home)) {
                const relative_path = cwd[home.len..];
                if (relative_path.len == 0) {
                    path_part = "~";
                } else {
                    path_part = try std.fmt.allocPrint(self.allocator, "~{s}", .{relative_path});
                    path_allocated = true;
                }
            } else {
                // ディレクトリ名のみを表示（フルパスが長い場合）
                if (std.mem.lastIndexOfScalar(u8, cwd, '/')) |last_slash| {
                    const dir_name = cwd[last_slash + 1 ..];
                    if (dir_name.len == 0) {
                        path_part = "/";
                    } else {
                        path_part = dir_name;
                    }
                } else {
                    path_part = cwd;
                }
            }
        } else |_| {
            // HOME環境変数が取得できない場合
            if (std.mem.lastIndexOfScalar(u8, cwd, '/')) |last_slash| {
                const dir_name = cwd[last_slash + 1 ..];
                if (dir_name.len == 0) {
                    path_part = "/";
                } else {
                    path_part = dir_name;
                }
            } else {
                path_part = cwd;
            }
        }

        // プロンプト文字列の構築
        if (branch_name_owned) |branch_name| {
            // ブランチ情報付きプロンプト
            const START_MARKER = "§START§";
            const END_MARKER = "§END§";
            return try std.fmt.allocPrint(self.allocator, "{s} ({s}{s}{s}) $ ", .{ path_part, START_MARKER, branch_name, END_MARKER });
        } else {
            // 通常のプロンプト
            return try std.fmt.allocPrint(self.allocator, "{s} $ ", .{path_part});
        }
    }

    // 履歴表示用のマーカーなしプロンプトを生成
    fn getPromptForHistory(self: *Terminal) ![]const u8 {
        const cwd = self.shell.cwd.items;

        // Gitブランチ名の取得（getPrompt関数と同じロジック）
        var branch_name_owned: ?[]u8 = null;
        defer if (branch_name_owned) |branch| self.allocator.free(branch);

        const dot_git_path = std.fs.path.join(self.allocator, &.{ cwd, ".git" }) catch null;
        defer if (dot_git_path) |path| self.allocator.free(path);

        if (dot_git_path) |git_path| {
            const git_exists = blk: {
                std.fs.cwd().access(git_path, .{}) catch break :blk false;
                break :blk true;
            };
            if (git_exists) {
                var child = std.process.Child.init(&.{ "git", "symbolic-ref", "--short", "HEAD" }, self.allocator);

                var cwd_dir = std.fs.cwd().openDir(cwd, .{}) catch null;
                defer if (cwd_dir) |*dir| dir.close();

                if (cwd_dir) |*dir| {
                    child.cwd_dir = dir.*;
                    child.stdout_behavior = .Pipe;
                    child.stderr_behavior = .Ignore;

                    var spawn_succeeded = true;
                    child.spawn() catch {
                        spawn_succeeded = false;
                    };

                    if (spawn_succeeded) {
                        const MAX_BRANCH_NAME_LEN = 64;
                        const raw_branch = child.stdout.?.reader().readAllAlloc(self.allocator, MAX_BRANCH_NAME_LEN) catch null;
                        _ = child.wait() catch {};

                        if (raw_branch) |branch_raw| {
                            const trimmed = std.mem.trim(u8, branch_raw, " \n\r");
                            if (trimmed.len > 0) {
                                branch_name_owned = self.allocator.dupe(u8, trimmed) catch null;
                            }
                            self.allocator.free(branch_raw);
                        }
                    }
                }
            }
        }

        // プロンプトのパス部分を決定
        var path_part: []const u8 = undefined;
        var path_allocated = false;
        defer if (path_allocated) self.allocator.free(path_part);

        if (std.process.getEnvVarOwned(self.allocator, "HOME")) |home| {
            defer self.allocator.free(home);
            if (std.mem.startsWith(u8, cwd, home)) {
                const relative_path = cwd[home.len..];
                if (relative_path.len == 0) {
                    path_part = "~";
                } else {
                    path_part = try std.fmt.allocPrint(self.allocator, "~{s}", .{relative_path});
                    path_allocated = true;
                }
            } else {
                if (std.mem.lastIndexOfScalar(u8, cwd, '/')) |last_slash| {
                    const dir_name = cwd[last_slash + 1 ..];
                    if (dir_name.len == 0) {
                        path_part = "/";
                    } else {
                        path_part = dir_name;
                    }
                } else {
                    path_part = cwd;
                }
            }
        } else |_| {
            if (std.mem.lastIndexOfScalar(u8, cwd, '/')) |last_slash| {
                const dir_name = cwd[last_slash + 1 ..];
                if (dir_name.len == 0) {
                    path_part = "/";
                } else {
                    path_part = dir_name;
                }
            } else {
                path_part = cwd;
            }
        }

        // マーカーなしプロンプト文字列の構築
        if (branch_name_owned) |branch_name| {
            return try std.fmt.allocPrint(self.allocator, "{s} ({s}) $ ", .{ path_part, branch_name });
        } else {
            return try std.fmt.allocPrint(self.allocator, "{s} $ ", .{path_part});
        }
    }

    /// TAB補完の処理
    pub fn handleTab(self: *Terminal) !void {
        if (self.showing_completions) {
            // 既に補完候補が表示されている場合、次の候補を選択
            try self.selectNextCompletion();
        } else {
            // 新しい補完を開始
            try self.startCompletion();
        }
    }

    /// 補完処理の開始
    fn startCompletion(self: *Terminal) !void {
        // 既存の補完結果をクリア
        if (self.completion_suggestions) |*suggestions| {
            suggestions.deinit();
            self.completion_suggestions = null;
        }

        // 補完候補を取得
        var result = try self.completer.complete(
            self.current_line.items,
            @intCast(self.cursor_x),
            self.shell.cwd.items,
        );

        if (result.suggestions.items.len == 0) {
            // 候補がない場合
            result.deinit();
            return;
        }

        if (result.suggestions.items.len == 1) {
            // 候補が1つの場合、直接補完
            try self.applyCompletion(result.suggestions.items[0]);
            result.deinit();
        } else {
            // 複数の候補がある場合
            if (result.common_prefix.len > 0) {
                // 共通プレフィックスがある場合、それを適用
                try self.applyCommonPrefix(&result);
            }

            // 補完候補を表示
            self.completion_suggestions = result;
            self.showing_completions = true;
            self.completion_selected_index = 0;
        }
    }

    /// 次の補完候補を選択
    fn selectNextCompletion(self: *Terminal) !void {
        if (self.completion_suggestions) |*suggestions| {
            if (suggestions.suggestions.items.len > 0) {
                self.completion_selected_index = (self.completion_selected_index + 1) % suggestions.suggestions.items.len;
            }
        }
    }

    /// 補完を適用
    fn applyCompletion(self: *Terminal, completion: []const u8) !void {
        // 現在のカーソル位置から単語の開始位置を見つける
        const word_start = self.findCurrentWordStart();

        // 現在の単語を削除
        while (self.cursor_x > word_start) {
            _ = self.current_line.orderedRemove(@intCast(self.cursor_x - 1));
            self.cursor_x -= 1;
        }

        // 補完文字列を挿入
        for (completion) |char| {
            try self.current_line.insert(@intCast(self.cursor_x), char);
            self.cursor_x += 1;
        }

        // 補完状態をリセット
        self.hideCompletions();
    }

    /// 共通プレフィックスを適用
    fn applyCommonPrefix(self: *Terminal, result: *CompletionResult) !void {
        if (result.common_prefix.len == 0) return;

        // 現在の単語の開始位置を見つける
        const word_start = self.findCurrentWordStart();
        const current_word_len = @as(usize, @intCast(self.cursor_x - word_start));

        // 共通プレフィックスが現在の単語より長い場合のみ適用
        if (result.common_prefix.len > current_word_len) {
            const additional_chars = result.common_prefix[current_word_len..];

            for (additional_chars) |char| {
                try self.current_line.insert(@intCast(self.cursor_x), char);
                self.cursor_x += 1;
            }
        }
    }

    /// 現在の単語の開始位置を見つける
    fn findCurrentWordStart(self: *Terminal) i32 {
        var pos = self.cursor_x;

        while (pos > 0) {
            const char = self.current_line.items[@intCast(pos - 1)];
            if (char == ' ' or char == '\t') {
                break;
            }
            pos -= 1;
        }

        return pos;
    }

    /// 補完候補の表示を隠す
    fn hideCompletions(self: *Terminal) void {
        self.showing_completions = false;
        if (self.completion_suggestions) |*suggestions| {
            suggestions.deinit();
            self.completion_suggestions = null;
        }
        self.completion_selected_index = 0;
    }

    /// Enterキーで選択された補完を適用
    pub fn applySelectedCompletion(self: *Terminal) !void {
        if (self.showing_completions) {
            if (self.completion_suggestions) |*suggestions| {
                if (self.completion_selected_index < suggestions.suggestions.items.len) {
                    const selected = suggestions.suggestions.items[self.completion_selected_index];
                    try self.applyCompletion(selected);
                }
            }
        }
    }
};
