const std = @import("std");

var dirStack = std.ArrayListUnmanaged([]u8){};
const cmd_list = [_][]const u8{"exit", "cd", "pwd", "type", "echo", "builtin", "clear", "dirs", "pushd", "popd"};

const status = 0;

pub fn main() !void {

    const initCwd = try std.fs.cwd().realpathAlloc(std.heap.page_allocator, ".");
    try dirStack.append(std.heap.page_allocator, initCwd);

    while (true) {
        // Allocator
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        // Input commands
        var read_buffer: [1024]u8 = undefined;
        var reader = std.fs.File.stdin().reader(&read_buffer);
        const stdin = &reader.interface;

        // Username and Hostname
        const user = std.posix.getenv("USER");
        var hostname_buf: [64]u8 = undefined;
        const hostname = try std.posix.gethostname(&hostname_buf);

        // Directory Display
        const cwdPath = try std.fs.cwd().realpathAlloc(allocator, ".");
        const dirName = std.fs.path.basename(cwdPath);

        std.debug.print("[{?s}@{s} {s}]$ ", .{user, hostname, dirName});

        const input = try stdin.takeDelimiterExclusive('\n');

        if (input.len > 0) {
            if (std.mem.eql(u8, input, "exit")) {
                try exitCommand();
            }
            try handleCommand(input, allocator);
        }
    }
}

fn handleCommand(input: []const u8, allocator: std.mem.Allocator) !void {
    var args_split = std.mem.splitSequence(u8, input, " ");
    const command = args_split.next() orelse return;

    if (std.mem.eql(u8, command, "echo")) {
        try echoCommand(input);
    } else if (std.mem.eql(u8, command, "pwd")) {
        try pwdCommand(allocator);
    } else if (std.mem.eql(u8, command, "exit")) {
        try exitCommand();
    } else if (std.mem.eql(u8, command, "clear")) {
        try clearCommand();
    } else if (std.mem.eql(u8, command, "true")) {
        trueCommand();
    } else if (std.mem.eql(u8, command, "false")) {
        falseCommand();
    } else if (std.mem.eql(u8, command, "cd")) {
        // Trim whitespace
        const arg = std.mem.trim(u8, args_split.rest(), &std.ascii.whitespace);
        try cdCommand(arg);
    } else if (std.mem.eql(u8, command, "builtin")) {
        try builtinCommand();
    } else {
        var argv_list = std.ArrayListUnmanaged([]const u8){};
        defer argv_list.deinit(allocator);

        var it = std.mem.splitSequence(u8, input, " ");
        while (it.next()) |part| {
            try argv_list.append(allocator, part);
        }

        const argv = try argv_list.toOwnedSlice(allocator);
        defer allocator.free(argv);

        executeCommand(allocator, argv) catch |err| {
            switch (err) {
                error.FileNotFound => {}, // already handled inside
                error.AccessDenied => {},
                else => std.debug.print("exec error: {s}\n", .{@errorName(err)}),
            }
        };
    }
}

fn echoCommand(input: []const u8) !void {
    const echo_args = input[5..];
    if (echo_args.len == 0) {
        std.debug.print("\n", .{});
    } else {
        std.debug.print("{s}\n", .{echo_args});
    }
}

fn typeCommand(input: []const u8) !void {
    var args_split = std.mem.splitSequence(u8, input, " ");

    for (cmd_list) |builtin| {
        if (std.mem.eql(u8, args_split.next(), builtin)) {
            std.debug.print("{s} is a builtin\n", .{builtin});
        }
    }
}

fn pwdCommand(allocator: std.mem.Allocator) !void {
    const current_directory = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(current_directory);

    std.debug.print("{s}\n", .{current_directory});
}

fn builtinCommand() !void {
    for (cmd_list) |commands| {
        std.debug.print("{s}\n", .{commands});
    }
}

fn clearCommand() !void {
    const clear_screen = "\x1B[2J\x1B[H";
    std.debug.print("{s}", .{clear_screen});
}

fn cdCommand(target: []const u8) !void {
    const path = if (target.len == 0 or std.mem.eql(u8, target, "~") or std.mem.eql(u8, target, "~/"))
        std.posix.getenv("HOME") orelse {
            std.debug.print("cd: HOME environment variable not set\n", .{});
            return error.HomeNotSet;
        }
        else
        target;

    std.posix.chdir(path) catch |err| {
        std.debug.print("cd: {s}: No such file or directory\n", .{path});
        return err;
    };
}

fn executeCommand(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    if (argv.len == 0) {
        std.debug.print("exec: no command\n", .{});
        return;
    }

    const cmd = argv[0];

    // Direct path if it contains '/'
    if (std.mem.indexOfScalar(u8, cmd, '/')) |_| {
        try spawnAndWait(allocator, argv);
        return;
    }

    // Search in PATH
    const path = std.posix.getenv("PATH") orelse "/bin:/usr/bin:/usr/local/bin";
    var dirs = std.mem.splitScalar(u8, path, ':');

    while (dirs.next()) |dir| {
        const full_path = std.fs.path.join(allocator, &.{dir, cmd}) catch continue;
        defer allocator.free(full_path);

        if (spawnAndWait(allocator, argv)) {
            return;
        } else |err| switch (err) {
            error.FileNotFound => continue,
            error.AccessDenied => {
                std.debug.print("{s}: permission denied\n", .{cmd});
                return;
            },
            else => continue,
        }
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

fn trueCommand() bool {
    status = 0;
}

fn falseCommand() bool {
    status = 1;
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

fn exitCommand() !void {
    std.process.exit(0);
}
