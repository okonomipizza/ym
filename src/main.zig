const std = @import("std");
const lib = @import("ym_lib");
const Terminal = lib.Terminal;
const BoxSyleTypes = lib.BoxStyleType;

pub fn main() !void {
    var terminal = try Terminal.init();
    while (true) {
        try terminal.draw();
        try terminal.drawTextBox("Hello world!", BoxSyleTypes.double);
        try terminal.flush();
        std.time.sleep(50000000000);
    }
    try terminal.deinit();
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "use other module" {
    try std.testing.expectEqual(@as(i32, 150), lib.add(100, 50));
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
