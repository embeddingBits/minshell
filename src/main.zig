const std = @import("std");

pub fn main() !void {

    while (true) {
        var read_buffer: [50]u8 = undefined;
        var reader = std.fs.File.stdin().reader(&read_buffer);
        const stdin = &reader.interface;

        std.debug.print(">> ", .{});

        const line = try stdin.takeDelimiterExclusive('\n');
        var args = std.mem.splitScalar(u8, line, ' ');

        if (args.next()) |first| {
            if (std.mem.eql(u8, first, "exit")) {
                std.debug.print("goodbye\n", .{});
                return;
            } 
            if (std.mem.eql(u8, first, "ls")) {
                var dir = try std.fs.cwd().openDir(".", .{.iterate = true});
                defer dir.close();

                var iter = dir.iterate();

                while (try iter.next()) |i| {
                    std.debug.print("{s} ", .{i.name});
                }
                std.debug.print("\n", .{});

            } 
            if (std.mem.eql(u8, first, "pwd")) {
                var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
                defer arena.deinit();
                const alloc = arena.allocator();

                const pwd = try std.fs.cwd().realpathAlloc(alloc, ".");
                std.debug.print("{s}\n", .{pwd});
            } 
            if (std.mem.eql(u8, first, "echo")) {
                while(args.next()) |i| {
                    std.debug.print("{s} ", .{i});
                }
                std.debug.print("\n", .{});
            } 
        }

    }
}
