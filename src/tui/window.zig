const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const STDOUT_BUFFER_SIZE: usize = 512;

pub const Terminal = struct {
    panel: Panel,
    writer: std.io.BufferedWriter(STDOUT_BUFFER_SIZE, std.fs.File.Writer),
    ansi: AnsiEscape,

    const Self = @This();

    pub fn init() !Self {
        const BufferedStdoutWriter = std.io.BufferedWriter(STDOUT_BUFFER_SIZE, std.fs.File.Writer);
        var bw = BufferedStdoutWriter{ .unbuffered_writer = std.io.getStdOut().writer() };
        var ansi = AnsiEscape{};

        // Enter alternate screen buffer
        try bw.writer().writeAll(ansi.enterAltScreen());

        const screen_size = try getScreenSize();
        const panel = Panel.init(screen_size.width, screen_size.height);
        return .{
            .panel = panel,
            .writer = bw,
            .ansi = ansi,
        };
    }

    pub fn deinit(self: *Self) !void {
        // Exit alternate screen buffer and restore terminal
        try self.writer.writer().writeAll(self.ansi.exitAltScreen());
        try self.flush();
    }

    /// Now draw is just a panel.draw() wrapper
    /// Support window spliting in the future
    pub fn draw(self: *Self) !void {
        try self.panel.draw(self.writer.writer());
        try self.flush();
    }

    pub fn drawTextBox(self: *Self, text: []const u8) !void {
        try self.panel.drawRectangle(self.writer.writer(), &self.ansi, text, Position{ .row = 3, .col = 5 }, Position{ .row = 30, .col = 50 });
    }

    pub fn flush(self: *Self) !void {
        try self.writer.flush();
    }

    /// Get size of terminal area
    pub fn getScreenSize() !ScreenSize {
        if (builtin.os.tag == .linux) {
            const c = @cImport({
                @cInclude("sys/ioctl.h");
                @cInclude("sys/unistd.h");
            });

            var ws: c.winsize = undefined;
            if (c.ioctl(c.STDOUT_FILENO, c.TIOCGWINSZ, &ws) == -1) {
                return ScreenSize{ .width = 80, .height = 24 };
            }

            return .{
                .width = ws.ws_col,
                .height = ws.ws_row,
            };
        } else {
            // Default terminal size
            return .{ .width = 80, .height = 24 };
        }
    }
};

/// Position at terminal
const Position = struct { row: u16, col: u16 };

pub const Panel = struct {
    width: u16,
    height: u16,

    const Self = @This();

    pub fn init(width: u16, height: u16) Self {
        return .{
            .width = width,
            .height = height,
        };
    }

    pub fn draw(self: Self, writer: anytype) !void {
        const ansi = AnsiEscape{};
        try writer.writeAll(ansi.clearScreen());
        try writer.writeAll(ansi.cursorHome());

        try self.drawOutline(writer);
    }

    /// Draw outline border
    fn drawOutline(self: Self, writer: anytype) !void {
        const ansi = AnsiEscape{};

        try self.drawRectangle(writer, &ansi, null, Position{ .row = 1, .col = 1 }, Position{ .row = self.height, .col = self.width });
    }

    pub fn drawRectangle(self: Self, writer: anytype, ansi: *const AnsiEscape, text: ?[]const u8, left_top: Position, right_bottom: Position) !void {
        const width = right_bottom.col - left_top.col + 1;
        const height = right_bottom.row - left_top.row + 1;

        try self.drawRecTopBorder(writer, ansi, width, left_top);
        try self.drawRecSideBorder(writer, ansi, height, Position{ .row = left_top.row, .col = left_top.col });
        try self.drawRecSideBorder(writer, ansi, height, Position{ .row = left_top.row, .col = right_bottom.col });
        try self.drawRecBottomBorder(writer, ansi, width, Position{ .row = right_bottom.row, .col = left_top.col });

        // Basically text starts at second row
        if (text) |txt| {
            try ansi.cursorTo(writer, Position{ .row = left_top.row + 4, .col = left_top.col + 4 });
            try writer.writeAll(txt);
        }
    }

    /// Draw top line to right direction from "start" position
    fn drawRecTopBorder(self: Self, writer: anytype, ansi: *const AnsiEscape, width: u16, start: Position) !void {
        _ = self;

        try ansi.cursorTo(writer, start);
        const end_col = start.col + width - 1;

        var col: u16 = start.col;
        while (col <= end_col) : (col += 1) {
            if (col == start.col) {
                try writer.writeAll(BoxChars.TOP_LEFT);
            } else if (col == end_col) {
                try writer.writeAll(BoxChars.TOP_RIGHT);
            } else {
                try writer.writeAll(BoxChars.HORIZONTAL);
            }
        }
    }

    /// Draw bottom line to right direction from "start" position
    fn drawRecBottomBorder(self: Self, writer: anytype, ansi: *const AnsiEscape, width: u16, start: Position) !void {
        _ = self;

        try ansi.cursorTo(writer, start);
        const end_col = start.col + width - 1;

        var col: u16 = start.col;
        while (col <= end_col) : (col += 1) {
            if (col == start.col) {
                try writer.writeAll(BoxChars.BOTTOM_LEFT);
            } else if (col == end_col) {
                try writer.writeAll(BoxChars.BOTTOM_RIGHT);
            } else {
                try writer.writeAll(BoxChars.HORIZONTAL);
            }
        }
    }

    /// Draw side line
    fn drawRecSideBorder(self: Self, writer: anytype, ansi: *const AnsiEscape, height: u16, start: Position) !void {
        _ = self;
        const end_row = start.row + height - 1;

        var row = start.row + 1;
        while (row <= end_row) : (row += 1) {
            try ansi.cursorTo(writer, Position{ .row = row, .col = start.col });
            try writer.writeAll(BoxChars.VERTICAL);
        }
    }
};

pub const ScreenSize = struct {
    width: u16,
    height: u16,
};

/// AnsiEscape send commands to terminal to edit buffers
const AnsiEscape = struct {
    const Self = @This();
    /// Clear all screen
    pub fn clearScreen(self: Self) []const u8 {
        _ = self;
        return "\x1b[2J";
    }

    /// Move cursor (1, 1)
    pub fn cursorHome(self: Self) []const u8 {
        _ = self;
        return "\x1b[H";
    }

    /// Absoluter cursor positioning
    pub fn cursorTo(self: Self, writer: anytype, position: Position) !void {
        _ = self;
        try writer.print("\x1b[{};{}H", .{ position.row, position.col });
    }

    /// Relative cursor movement
    pub fn cursorUp(self: Self, writer: anytype, n: u16) !void {
        _ = self;
        try writer.print("\x1b[{}A", .{n});
    }

    pub fn cursorDown(self: Self, writer: anytype, n: u16) !void {
        _ = self;
        try writer.print("\x1b[{}B", .{n});
    }

    pub fn cursorRight(self: Self, writer: anytype, n: u16) !void {
        _ = self;
        try writer.print("\x1b[{}C", .{n});
    }

    pub fn cursorLeft(self: Self, writer: anytype, n: u16) !void {
        _ = self;
        try writer.print("\x1b[{}D", .{n});
    }

    // Move to next/previous line
    pub fn nextLine(self: Self, writer: anytype, n: u16) !void {
        _ = self;
        try writer.print("\x1b[{}E", .{n});
    }

    pub fn prevLine(self: Self, writer: anytype, n: u16) !void {
        _ = self;
        try writer.print("\x1b[{}F", .{n});
    }

    // Move to column on current line
    pub fn cursorToCol(self: Self, writer: anytype, col: u16) !void {
        _ = self;
        try writer.print("\x1b[{}G", .{col});
    }
    pub fn enterAltScreen(self: Self) []const u8 {
        _ = self;
        return "\x1b[?1049h"; // Enter alternate screen
    }

    pub fn exitAltScreen(self: Self) []const u8 {
        _ = self;
        return "\x1b[?1049l"; // Exit alternate screen
    }
};

/// Box drawing characters
const BoxChars = struct {
    const TOP_LEFT = "┌";
    const TOP_RIGHT = "┐";
    const BOTTOM_LEFT = "└";
    const BOTTOM_RIGHT = "┘";
    const HORIZONTAL = "─";
    const VERTICAL = "│";

    const DOUBLE_TOP_LEFT = "┏";
    const DOUBLE_TOP_RIGHT = "┓";
    const DOUBLE_BOTTOM_LEFT = "┗";
    const DOUBLE_BOTTOM_RIGHT = "┛";
    const DOUBLE_HORIZONTAL = "━";
    const DOUBLE_VERTICAL = "┃";

    const MIDDLE_DOT = "·";

    // Additional box characters for future use
    const T_DOWN = "┬"; // ┬
    const T_UP = "┴"; // ┴
    const T_RIGHT = "├"; // ├
    const T_LEFT = "┤"; // ┤
    const CROSS = "┼";
};

// try stdout.print("\x1b[1mMAIN TITLE\x1b[0m\n", .{});
//     try stdout.print("═══════════\n", .{});
//
//     // H2 with single underline
//     try stdout.print("\x1b[1mSection Header\x1b[0m\n", .{});
//     try stdout.print("──────────────\n\n", .{});
//
//     // H3 with dots
//     try stdout.print("\x1b[1mSubsection\x1b[0m\n", .{});
//     try stdout.print("··········\n", .{});
//
//     // H4 with dashes
//     try stdout.print("\x1b[1m- Minor Header\x1b[0m\n", .{});
//
//     // H5 with arrows
//     try stdout.print("\x1b[1m→ Small Header\x1b[0m\n", .{});
//
//     // H6 with bullets
//     try stdout.print("\x1b[1m• Tiny Header\x1b[0m\n", .{});
