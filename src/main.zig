const std = @import("std");

const cmd_list = [_][]const u8{
    "exit", "cd", "pwd", "type", "echo",
    "builtin", "clear", "dirs", "pushd", "popd",
};

const ParsedCommand = struct {
    command: []const u8,
    argv: []const []const u8,
};

pub fn main() !void {
    while (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        // Input reader
        var read_buffer: [1024]u8 = undefined;
        var reader = std.fs.File.stdin().reader(&read_buffer);
        const stdin = &reader.interface;

        try displayPrompt(allocator);

        const input = stdin.takeDelimiterExclusive('\n') catch continue;
        if (input.len == 0) continue;

        try handleCommand(input, allocator);
    }
}

fn displayPrompt(allocator: std.mem.Allocator) !void {

        // To display prompt
        const user = std.posix.getenv("USER") orelse "user";
        var hostname_buf: [64]u8 = undefined;
        const hostname = try std.posix.gethostname(&hostname_buf);

        const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");
        const dir_name = std.fs.path.basename(cwd_path);

        std.debug.print("[{s}@{s} {s}]$ ", .{ user, hostname, dir_name });
}

fn parseCommand(input: []const u8, allocator: std.mem.Allocator) !ParsedCommand {
    var parts = std.mem.splitSequence(u8, input, " ");

    var argvList = std.ArrayListUnmanaged([]const u8){};
    errdefer argvList.deinit(allocator);

    while (parts.next()) |part| {
        if (part.len == 0) continue;
        try argvList.append(allocator, part);
    }

    if (argvList.items.len == 0)
        return error.EmptyCommand;

    const argv = try argvList.toOwnedSlice(allocator);

    return ParsedCommand{
        .command = argv[0],
        .argv = argv,
    };
}

fn handleCommand(input: []const u8, allocator: std.mem.Allocator) !void {
    const parsed = parseCommand(input, allocator) catch |err| {
        if (err == error.EmptyCommand) return;
        return err;
    };
    defer allocator.free(parsed.argv);

    const cmd = parsed.command;

    if (std.mem.eql(u8, cmd, "exit")) {
        exitCommand();
    } else if (std.mem.eql(u8, cmd, "echo")) {
        echoCommand(parsed.argv);
    } else if (std.mem.eql(u8, cmd, "pwd")) {
        try pwdCommand(allocator);
    } else if (std.mem.eql(u8, cmd, "clear")) {
        clearCommand();
    } else if (std.mem.eql(u8, cmd, "cd")) {
        const target = if (parsed.argv.len > 1) parsed.argv[1] else "";
        try cdCommand(target);
    } else if (std.mem.eql(u8, cmd, "builtin")) {
        builtinCommand();
    } else if (std.mem.eql(u8, cmd, "type")) {
        typeCommand(parsed.argv);
    } else {
        executeCommand(allocator, parsed.argv) catch |err| {
            switch (err) {
                error.FileNotFound => {},
                error.AccessDenied => {},
                else => std.debug.print("exec error: {s}\n", .{@errorName(err)}),
            }
        };
    }
}

fn echoCommand(argv: []const []const u8) void {
    if (argv.len <= 1) {
        std.debug.print("\n", .{});
        return;
    }

    for (argv[1..], 0..) |arg, i| {
        if (i > 0) std.debug.print(" ", .{});
        std.debug.print("{s}", .{arg});
    }
    std.debug.print("\n", .{});
}

fn pwdCommand(allocator: std.mem.Allocator) !void {
    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);
    std.debug.print("{s}\n", .{cwd});
}

fn clearCommand() void {
    std.debug.print("\x1B[2J\x1B[H", .{});
}

fn cdCommand(target: []const u8) !void {
    const path =
        if (target.len == 0 or std.mem.eql(u8, target, "~"))
            std.posix.getenv("HOME") orelse {
                std.debug.print("cd: HOME not set\n", .{});
                return error.HomeNotSet;
            }
        else
            target;

    std.posix.chdir(path) catch {
        std.debug.print("cd: {s}: No such directory\n", .{path});
    };
}

fn builtinCommand() void {
    for (cmd_list) |cmd| {
        std.debug.print("{s}\n", .{cmd});
    }
}

fn typeCommand(argv: []const []const u8) void {
    if (argv.len < 2) return;

    for (cmd_list) |builtin| {
        if (std.mem.eql(u8, argv[1], builtin)) {
            std.debug.print("{s} is a builtin\n", .{builtin});
            return;
        }
    }

    std.debug.print("{s} not found\n", .{argv[1]});
}


fn executeCommand(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    const cmd = argv[0];

    // Direct path
    if (std.mem.indexOfScalar(u8, cmd, '/')) |_| {
        try spawnAndWait(allocator, argv);
        return;
    }

    const path = std.posix.getenv("PATH") orelse "/bin:/usr/bin";
    var dirs = std.mem.splitScalar(u8, path, ':');

    while (dirs.next()) |dir| {
        const full = std.fs.path.join(allocator, &.{ dir, cmd }) catch continue;
        defer allocator.free(full);

        if (spawnAndWait(allocator, argv)) {
            return;
        } else |_| {}
    }

    std.debug.print("{s}: command not found\n", .{cmd});
}

fn spawnAndWait(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Inherit;
    child.stderr_behavior = .Inherit;

    try child.spawn();
    _ = try child.wait();
}

fn exitCommand() noreturn {
    std.process.exit(0);
}

//fn dirsCommand(allocator: std.mem.Allocator) !void {
//    _ = allocator;
//
//    if (dirStack.items.len == 0) {
//        std.debug.print("\n", .{});
//        return;
//    }
//
//    for (dirStack.items, 0..) |dir, i| {
//        if (i > 0) std.debug.print(" ", .{});
//        std.debug.print("{s}\n", .{dir});
//    }
//}
//
//fn pushdCommand(target: []const u8, allocator: std.mem.Allocator) !void {
//    const path = if (target.len == 0 or std.mem.eql(u8, target, "~"))
//        std.posix.getenv("HOME") orelse return error.HomeNotSet
//        else
//        target;
//
//    try std.posix.chdir(path);
//
//    const newCwd = try std.fs.cwd().realpathAlloc(allocator, ".");
//    try dirStack.append(allocator, newCwd);
//
//    try dirsCommand(allocator);
//}
