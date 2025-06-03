const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const ChildProcess = std.process.Child;

pub const Shell = struct {
    allocator: Allocator,
    cwd: ArrayList(u8),
    env: std.process.EnvMap,

    pub fn init(allocator: Allocator) !Shell {
        const env = try std.process.getEnvMap(allocator);
        
        var cwd = ArrayList(u8).init(allocator);
        const current_dir = std.fs.cwd().realpathAlloc(allocator, ".") catch |err| switch (err) {
            error.FileNotFound => try allocator.dupe(u8, "/"),
            else => return err,
        };
        defer allocator.free(current_dir);
        try cwd.appendSlice(current_dir);

        return Shell{
            .allocator = allocator,
            .cwd = cwd,
            .env = env,
        };
    }

    pub fn deinit(self: *Shell) void {
        self.cwd.deinit();
        self.env.deinit();
    }

    pub fn execute(self: *Shell, command_line: []const u8) ![]const u8 {
        if (command_line.len == 0) {
            return "";
        }

        // コマンドラインの解析
        var args = ArrayList([]const u8).init(self.allocator);
        defer {
            for (args.items) |arg| {
                self.allocator.free(arg);
            }
            args.deinit();
        }

        var it = std.mem.tokenizeAny(u8, command_line, " \t");
        while (it.next()) |token| {
            try args.append(try self.allocator.dupe(u8, token));
        }

        if (args.items.len == 0) {
            return "";
        }

        const command = args.items[0];

        // 内蔵コマンドの処理
        if (std.mem.eql(u8, command, "cd")) {
            return try self.handleCd(args.items);
        } else if (std.mem.eql(u8, command, "pwd")) {
            return try self.handlePwd();
        } else if (std.mem.eql(u8, command, "exit")) {
            std.process.exit(0);
        } else if (std.mem.eql(u8, command, "echo")) {
            return try self.handleEcho(args.items);
        } else if (std.mem.eql(u8, command, "ls")) {
            return try self.handleLs(args.items);
        } else if (std.mem.eql(u8, command, "clear")) {
            return try self.handleClear();
        } else if (std.mem.eql(u8, command, "help")) {
            return try self.handleHelp();
        }

        // 外部コマンドの実行
        return try self.executeExternal(args.items);
    }

    fn handleCd(self: *Shell, args: []const []const u8) ![]const u8 {
        const target_dir = if (args.len > 1) args[1] else {
            // HOMEディレクトリに移動
            if (std.process.getEnvVarOwned(self.allocator, "HOME")) |home_dir| {
                defer self.allocator.free(home_dir);
                self.cwd.clearRetainingCapacity();
                try self.cwd.appendSlice(home_dir);
                return "";
            } else |_| {
                return try self.allocator.dupe(u8, "cd: HOME environment variable not set");
            }
        };

        // パスの正規化
        var target_path: []const u8 = undefined;
        var should_free_target_path = false;
        
        if (target_dir[0] == '/') {
            // 絶対パス
            target_path = target_dir;
        } else {
            // 相対パス - 現在のディレクトリから解決
            var new_path = ArrayList(u8).init(self.allocator);
            defer new_path.deinit();
            
            try new_path.appendSlice(self.cwd.items);
            if (self.cwd.items[self.cwd.items.len - 1] != '/') {
                try new_path.append('/');
            }
            try new_path.appendSlice(target_dir);
            
            target_path = try self.allocator.dupe(u8, new_path.items);
            should_free_target_path = true;
        }
        defer if (should_free_target_path) self.allocator.free(target_path);

        // ディレクトリの存在確認とパスの正規化
        const real_path = std.fs.realpathAlloc(self.allocator, target_path) catch {
            return try std.fmt.allocPrint(self.allocator, "cd: {s}: No such file or directory", .{target_dir});
        };
        defer self.allocator.free(real_path);

        // ディレクトリかどうかの確認
        const stat = std.fs.cwd().statFile(real_path) catch {
            return try std.fmt.allocPrint(self.allocator, "cd: {s}: Permission denied", .{target_dir});
        };
        
        if (stat.kind != .directory) {
            return try std.fmt.allocPrint(self.allocator, "cd: {s}: Not a directory", .{target_dir});
        }

        // cwdの更新
        self.cwd.clearRetainingCapacity();
        try self.cwd.appendSlice(real_path);

        return "";
    }

    fn handlePwd(self: *Shell) ![]const u8 {
        return try self.allocator.dupe(u8, self.cwd.items);
    }

    fn handleEcho(self: *Shell, args: []const []const u8) ![]const u8 {
        if (args.len <= 1) {
            return try self.allocator.dupe(u8, "");
        }

        var result = ArrayList(u8).init(self.allocator);
        defer result.deinit();

        for (args[1..], 0..) |arg, i| {
            if (i > 0) try result.append(' ');
            try result.appendSlice(arg);
        }

        return try self.allocator.dupe(u8, result.items);
    }

    fn handleLs(self: *Shell, args: []const []const u8) ![]const u8 {
        const target_dir = if (args.len > 1) args[1] else ".";
        
        // パスの解決
        var full_path: []const u8 = undefined;
        var should_free_path = false;
        
        if (target_dir[0] == '/') {
            // 絶対パス
            full_path = target_dir;
        } else if (std.mem.eql(u8, target_dir, ".")) {
            // カレントディレクトリ
            full_path = self.cwd.items;
        } else {
            // 相対パス - 現在のディレクトリから解決
            var path_buf = ArrayList(u8).init(self.allocator);
            defer path_buf.deinit();
            
            try path_buf.appendSlice(self.cwd.items);
            if (self.cwd.items[self.cwd.items.len - 1] != '/') {
                try path_buf.append('/');
            }
            try path_buf.appendSlice(target_dir);
            
            full_path = try self.allocator.dupe(u8, path_buf.items);
            should_free_path = true;
        }
        defer if (should_free_path) self.allocator.free(full_path);
        
        var dir = std.fs.openDirAbsolute(full_path, .{ .iterate = true }) catch {
            return try std.fmt.allocPrint(self.allocator, "ls: {s}: No such file or directory", .{target_dir});
        };
        defer dir.close();

        var result = ArrayList(u8).init(self.allocator);
        defer result.deinit();

        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            try result.appendSlice(entry.name);
            switch (entry.kind) {
                .directory => try result.append('/'),
                .sym_link => try result.append('@'),
                else => {},
            }
            try result.append('\n');
        }

        return try self.allocator.dupe(u8, result.items);
    }

    fn handleClear(self: *Shell) ![]const u8 {
        // clearコマンドは特別な処理が必要なので、ターミナル側で処理するための特別なマーカーを返す
        return try self.allocator.dupe(u8, "\x1b[2J\x1b[H");
    }

    fn handleHelp(self: *Shell) ![]const u8 {
        const help_text =
            \\ZTerm - Zig Terminal Emulator
            \\
            \\Built-in commands:
            \\  cd [dir]    - Change directory
            \\  pwd         - Show current directory
            \\  ls [dir]    - List directory contents
            \\  echo [text] - Display text
            \\  clear       - Clear screen
            \\  help        - Show this help
            \\  exit        - Exit terminal
            \\
            \\Key bindings:
            \\  Ctrl+C, Ctrl+D, ESC - Exit
            \\  Up/Down arrows - Command history
            \\  Left/Right arrows - Cursor movement
            \\  Backspace - Delete character
            \\
        ;
        return try self.allocator.dupe(u8, help_text);
    }

    fn executeExternal(self: *Shell, args: []const []const u8) ![]const u8 {
        var process = ChildProcess.init(args, self.allocator);
        
        // shell内部の現在のディレクトリを作業ディレクトリとして設定
        process.cwd_dir = std.fs.openDirAbsolute(self.cwd.items, .{}) catch null;
        defer if (process.cwd_dir) |*dir| dir.close();
        
        process.stdout_behavior = .Pipe;
        process.stderr_behavior = .Pipe;

        process.spawn() catch {
            return try std.fmt.allocPrint(self.allocator, "{s}: command not found", .{args[0]});
        };

        const stdout = process.stdout.?.reader().readAllAlloc(self.allocator, 1024 * 1024) catch "";
        const stderr = process.stderr.?.reader().readAllAlloc(self.allocator, 1024 * 1024) catch "";
        
        const term = process.wait() catch {
            return try std.fmt.allocPrint(self.allocator, "{s}: failed to execute process", .{args[0]});
        };

        var result = ArrayList(u8).init(self.allocator);
        defer result.deinit();

        if (stdout.len > 0) {
            try result.appendSlice(stdout);
        }
        if (stderr.len > 0) {
            if (result.items.len > 0) try result.append('\n');
            try result.appendSlice(stderr);
        }

        self.allocator.free(stdout);
        self.allocator.free(stderr);

        switch (term) {
            .Exited => |code| {
                if (code != 0 and result.items.len == 0) {
                    try result.appendSlice(try std.fmt.allocPrint(self.allocator, "Process exited with code {d}", .{code}));
                }
            },
            else => {
                try result.appendSlice("Process terminated abnormally");
            },
        }

        return try self.allocator.dupe(u8, result.items);
    }
}; 