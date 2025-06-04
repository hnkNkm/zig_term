const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const CompletionResult = struct {
    suggestions: ArrayList([]const u8),
    common_prefix: []const u8,
    allocator: Allocator,

    pub fn init(allocator: Allocator) CompletionResult {
        return CompletionResult{
            .suggestions = ArrayList([]const u8).init(allocator),
            .common_prefix = "",
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CompletionResult) void {
        for (self.suggestions.items) |suggestion| {
            self.allocator.free(suggestion);
        }
        self.suggestions.deinit();
        if (self.common_prefix.len > 0) {
            self.allocator.free(self.common_prefix);
        }
    }

    pub fn addSuggestion(self: *CompletionResult, suggestion: []const u8) !void {
        const owned_suggestion = try self.allocator.dupe(u8, suggestion);
        try self.suggestions.append(owned_suggestion);
    }

    pub fn setCommonPrefix(self: *CompletionResult, prefix: []const u8) !void {
        if (self.common_prefix.len > 0) {
            self.allocator.free(self.common_prefix);
        }
        self.common_prefix = try self.allocator.dupe(u8, prefix);
    }
};

pub const Completer = struct {
    allocator: Allocator,
    builtin_commands: []const []const u8,
    git_subcommands: []const []const u8,

    pub fn init(allocator: Allocator) Completer {
        const builtin_commands = [_][]const u8{
            "cd", "pwd", "ls", "echo", "clear", "help", "exit",
        };

        const git_subcommands = [_][]const u8{
            "add",    "branch", "checkout", "clone",  "commit", "diff",        "fetch",
            "init",   "log",    "merge",    "pull",   "push",   "rebase",      "reset",
            "status", "tag",    "remote",   "config", "stash",  "cherry-pick",
        };

        return Completer{
            .allocator = allocator,
            .builtin_commands = &builtin_commands,
            .git_subcommands = &git_subcommands,
        };
    }

    pub fn deinit(self: *Completer) void {
        _ = self;
    }

    /// メインの補完関数：現在の入力内容に基づいて補完候補を生成
    pub fn complete(self: *Completer, input: []const u8, cursor_pos: usize, current_dir: []const u8) !CompletionResult {
        var result = CompletionResult.init(self.allocator);

        if (input.len == 0) {
            // 空の入力の場合、全てのコマンドを候補として返す
            try self.completeCommands(&result, "");
            return result;
        }

        // カーソル位置までの入力を解析
        const active_input = if (cursor_pos <= input.len) input[0..cursor_pos] else input;

        // 入力をトークンに分割
        var tokens = std.mem.tokenizeAny(u8, active_input, " \t");
        var token_list = ArrayList([]const u8).init(self.allocator);
        defer token_list.deinit();

        while (tokens.next()) |token| {
            try token_list.append(token);
        }

        if (token_list.items.len == 0) {
            // トークンがない場合、コマンド補完
            try self.completeCommands(&result, "");
        } else if (token_list.items.len == 1) {
            // 最初のトークン（コマンド名）の補完
            const partial_command = token_list.items[0];

            // 入力の最後が空白でない場合、コマンド名補完
            if (active_input[active_input.len - 1] != ' ' and active_input[active_input.len - 1] != '\t') {
                try self.completeCommands(&result, partial_command);
            } else {
                // 空白で終わる場合、引数補完
                try self.completeArguments(&result, partial_command, "", current_dir);
            }
        } else {
            // 複数のトークンがある場合、引数補完
            const command = token_list.items[0];
            const last_token = token_list.items[token_list.items.len - 1];

            // 入力の最後が空白かどうかで処理を分ける
            if (active_input[active_input.len - 1] == ' ' or active_input[active_input.len - 1] == '\t') {
                try self.completeArguments(&result, command, "", current_dir);
            } else {
                try self.completeArguments(&result, command, last_token, current_dir);
            }
        }

        // 共通プレフィックスを計算
        try self.calculateCommonPrefix(&result);

        return result;
    }

    /// コマンド名の補完
    fn completeCommands(self: *Completer, result: *CompletionResult, prefix: []const u8) !void {
        // 内蔵コマンドの補完
        for (self.builtin_commands) |cmd| {
            if (std.mem.startsWith(u8, cmd, prefix)) {
                try result.addSuggestion(cmd);
            }
        }

        // システムコマンドの補完（PATH環境変数から）
        try self.completeSystemCommands(result, prefix);
    }

    /// システムコマンドの補完
    fn completeSystemCommands(self: *Completer, result: *CompletionResult, prefix: []const u8) !void {
        const env_path = std.process.getEnvVarOwned(self.allocator, "PATH") catch return;
        defer self.allocator.free(env_path);

        var path_it = std.mem.splitScalar(u8, env_path, ':');
        while (path_it.next()) |path_dir| {
            var dir = std.fs.openDirAbsolute(path_dir, .{ .iterate = true }) catch continue;
            defer dir.close();

            var iterator = dir.iterate();
            while (iterator.next() catch null) |entry| {
                if (entry.kind == .file or entry.kind == .sym_link) {
                    if (std.mem.startsWith(u8, entry.name, prefix)) {
                        // 実行権限の確認
                        const stat = dir.statFile(entry.name) catch continue;
                        if (stat.mode & 0o111 != 0) { // 実行権限があるか
                            try result.addSuggestion(entry.name);
                        }
                    }
                }
            }
        }
    }

    /// 引数の補完（コマンド固有）
    fn completeArguments(self: *Completer, result: *CompletionResult, command: []const u8, partial_arg: []const u8, current_dir: []const u8) !void {
        if (std.mem.eql(u8, command, "git")) {
            try self.completeGitArguments(result, partial_arg, current_dir);
        } else if (std.mem.eql(u8, command, "cd") or std.mem.eql(u8, command, "ls")) {
            try self.completeFilePath(result, partial_arg, current_dir, true); // ディレクトリのみ
        } else {
            // デフォルトはファイル・ディレクトリパス補完
            try self.completeFilePath(result, partial_arg, current_dir, false);
        }
    }

    /// Gitコマンドの引数補完
    fn completeGitArguments(self: *Completer, result: *CompletionResult, partial_arg: []const u8, current_dir: []const u8) !void {
        // Gitサブコマンドの補完
        for (self.git_subcommands) |subcmd| {
            if (std.mem.startsWith(u8, subcmd, partial_arg)) {
                try result.addSuggestion(subcmd);
            }
        }

        // Gitブランチ名の補完
        try self.completeGitBranches(result, partial_arg, current_dir);
    }

    /// Gitブランチ名の補完
    fn completeGitBranches(self: *Completer, result: *CompletionResult, prefix: []const u8, current_dir: []const u8) !void {
        var child = std.process.Child.init(&.{ "git", "branch", "--format=%(refname:short)" }, self.allocator);

        var cwd_dir = std.fs.cwd().openDir(current_dir, .{}) catch return;
        defer cwd_dir.close();

        child.cwd_dir = cwd_dir;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;

        child.spawn() catch return;

        const MAX_OUTPUT = 4096;
        const output = child.stdout.?.reader().readAllAlloc(self.allocator, MAX_OUTPUT) catch "";
        defer self.allocator.free(output);

        _ = child.wait() catch {};

        var lines = std.mem.splitScalar(u8, output, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len > 0 and std.mem.startsWith(u8, trimmed, prefix)) {
                try result.addSuggestion(trimmed);
            }
        }
    }

    /// ファイル・ディレクトリパスの補完
    fn completeFilePath(self: *Completer, result: *CompletionResult, partial_path: []const u8, current_dir: []const u8, dirs_only: bool) !void {
        var search_dir: []const u8 = current_dir;
        var file_prefix: []const u8 = partial_path;
        var path_allocated = false;

        defer if (path_allocated) self.allocator.free(search_dir);

        // パスに'/'が含まれている場合、ディレクトリ部分とファイル名部分に分割
        if (std.mem.lastIndexOfScalar(u8, partial_path, '/')) |last_slash| {
            const dir_part = partial_path[0..last_slash];
            file_prefix = partial_path[last_slash + 1 ..];

            if (dir_part.len > 0 and dir_part[0] == '/') {
                // 絶対パス
                search_dir = dir_part;
            } else {
                // 相対パス
                var path_buf = ArrayList(u8).init(self.allocator);
                defer path_buf.deinit();

                try path_buf.appendSlice(current_dir);
                if (current_dir[current_dir.len - 1] != '/') {
                    try path_buf.append('/');
                }
                try path_buf.appendSlice(dir_part);

                search_dir = try self.allocator.dupe(u8, path_buf.items);
                path_allocated = true;
            }
        }

        var dir = std.fs.openDirAbsolute(search_dir, .{ .iterate = true }) catch return;
        defer dir.close();

        var iterator = dir.iterate();
        while (iterator.next() catch null) |entry| {
            if (std.mem.startsWith(u8, entry.name, file_prefix)) {
                if (dirs_only and entry.kind != .directory) {
                    continue;
                }

                var full_suggestion = ArrayList(u8).init(self.allocator);
                defer full_suggestion.deinit();

                // ディレクトリパス部分を含める
                if (std.mem.lastIndexOfScalar(u8, partial_path, '/')) |last_slash| {
                    try full_suggestion.appendSlice(partial_path[0 .. last_slash + 1]);
                }
                try full_suggestion.appendSlice(entry.name);

                // ディレクトリの場合は末尾に'/'を追加
                if (entry.kind == .directory) {
                    try full_suggestion.append('/');
                }

                try result.addSuggestion(full_suggestion.items);
            }
        }
    }

    /// 補完候補の共通プレフィックスを計算
    fn calculateCommonPrefix(self: *Completer, result: *CompletionResult) !void {
        _ = self; // suppress unused parameter warning

        if (result.suggestions.items.len == 0) {
            return;
        }

        if (result.suggestions.items.len == 1) {
            try result.setCommonPrefix(result.suggestions.items[0]);
            return;
        }

        // 最初の候補を基準に共通プレフィックスを見つける
        const first = result.suggestions.items[0];
        var common_len: usize = first.len;

        for (result.suggestions.items[1..]) |suggestion| {
            var i: usize = 0;
            while (i < common_len and i < suggestion.len and first[i] == suggestion[i]) {
                i += 1;
            }
            common_len = i;
        }

        if (common_len > 0) {
            try result.setCommonPrefix(first[0..common_len]);
        }
    }
};
