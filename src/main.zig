const std = @import("std");

pub fn main() !void {

    while (true) {
        var read_buffer: [50]u8 = undefined;
        var reader = std.fs.File.stdin().reader(&read_buffer);
        const stdin = &reader.interface;

        std.debug.print(">> ", .{});

        const line = try stdin.takeDelimiterExclusive('\n');
        var args = std.mem.splitScalar(u8, line, ' ');

        const cmds = [_][]const u8{"exit", "type", "echo", "pwd", "ls"};

        if (args.next()) |first| {
            if (std.mem.eql(u8, first, "exit")) {
                std.debug.print("goodbye\n", .{});
                return;
            } 
            else if (std.mem.eql(u8, first, "ls")) {
                var dir = try std.fs.cwd().openDir(".", .{.iterate = true});
                defer dir.close();

                var iter = dir.iterate();

                while (try iter.next()) |i| {
                    std.debug.print("{s} ", .{i.name});
                }
                std.debug.print("\n", .{});

            } 
            else if (std.mem.eql(u8, first, "pwd")) {
                var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer arena.deinit();
                const alloc = arena.allocator();

                const pwd = try std.fs.cwd().realpathAlloc(alloc, ".");
                std.debug.print("{s}\n", .{pwd});
            } 
            else if (std.mem.eql(u8, first, "echo")) {
                while(args.next()) |i| {
                    std.debug.print("{s} ", .{i});
                }
                std.debug.print("\n", .{});
            } 
            else if (std.mem.eql(u8, first, "type")) {
                const target = args.next() orelse {
                    std.debug.print("type: missing argument\n", .{});
                    continue;
                };

                var found = false;

                for (cmds) |cmd| {
                    if (std.mem.eql(u8, target, cmd)) {
                        std.debug.print("{s} is a builtin\n", .{target});
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    std.debug.print("type: {s} not found\n", .{target});
                }
            } else {
                std.debug.print("{s} is not found\n", .{first});
            }
        }
    }
}

