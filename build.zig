const std = @import("std");

pub fn build(b: *std.Build) void {
    // ターゲットプラットフォームの設定
    const target = b.standardTargetOptions(.{});
    
    // 最適化モードの設定
    const optimize = b.standardOptimizeOption(.{});

    // メインの実行ファイル
    const exe = b.addExecutable(.{
        .name = "zterm",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ncurses ライブラリのリンク
    exe.linkSystemLibrary("ncurses");
    exe.linkLibC();

    // インストール設定
    b.installArtifact(exe);

    // 実行コマンドの設定
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the terminal emulator");
    run_step.dependOn(&run_cmd.step);

    // テストの設定
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // デバッグビルドの設定
    const debug_exe = b.addExecutable(.{
        .name = "zterm-debug",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .Debug,
    });
    debug_exe.linkSystemLibrary("ncurses");
    debug_exe.linkLibC();

    const debug_step = b.step("debug", "Build debug version");
    debug_step.dependOn(&b.addInstallArtifact(debug_exe, .{}).step);
} 