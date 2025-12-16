const std = @import("std");

pub fn main() !void {

    while (true) {
        // Allocator
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        // Input commands
        var read_buffer: [1024]u8 = undefined;
        var reader = std.fs.File.stdin().reader(&read_buffer);
        const stdin = &reader.interface;

        std.debug.print("$ ", .{});

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
    } else if (std.mem.eql(u8, command, "cd")) {
        // Get the argument (if any), trim whitespace
        const arg = std.mem.trim(u8, args_split.rest(), &std.ascii.whitespace);
        try cdCommand(arg);
    } else {
        std.debug.print("command: {s} is not found\n", .{command});
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

    const cmd = [_][]const u8{"exit", "cd", "pwd", "type", "echo"};
    for (cmd) |builtin| {
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

    // Use std.os.chdir — safe, simple, no fd issues
    std.posix.chdir(path) catch |err| {
        std.debug.print("cd: {s}: No such file or directory\n", .{path});
        return err;
    };
}

fn exitCommand() !void {
    std.process.exit(0);
}
