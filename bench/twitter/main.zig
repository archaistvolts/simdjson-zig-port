const std = @import("std");

const dom = @import("simdjzon").dom;

pub const read_buf_cap = 4096;

pub fn main(init: std.process.Init) !u8 {
    var arenastate = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arenastate.deinit();
    const arena = arenastate.allocator();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 2) {
        std.debug.print("USAGE: ./simdjson <file.json>\n", .{});
    }
    var parser = try dom.Parser.initFile(arena, init.io, args[1], .{});
    defer parser.deinit();
    parser.parse() catch |err| {
        std.log.err("parse failed. {s}", .{@errorName(err)});
        return 1;
    };
    const statuses = try parser.element().at_pointer("/statuses");
    const array = try statuses.get_array();
    var i: usize = 0;
    while (array.at(i)) |status| : (i += 1) {
        const id = try status.at_pointer("/id");
        std.mem.doNotOptimizeAway(id);
        // std.debug.print("{}\n", .{try id.get_int64()});
    }
    // std.debug.print("i={}\n", .{i});
    if (i != 100) {
        std.debug.print("error. expected i=100. found i={}\n", .{i});
        return 1;
    }
    return 0;
}
