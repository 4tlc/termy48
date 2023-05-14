// SPDX-License-Identifier: GPL-3.0

// TODO Get the cursor position
// TODO print from center of screen
// TODO generalize the input stuff for all os
// TODO eventually read num_rows, num_cols from arguments

//* Styling *\\
//* TypeName | namespace_name | global_var | functionName | const_name *\\
const std = @import("std");
const Board = @import("Board.zig");
const f = @import("formats.zig");
const errors = @import("errors.zig");
const system = std.os.system;
const out = std.io.getStdOut();
var buf = std.io.bufferedWriter(out.writer());
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

// used in Board.zig
pub const buf_wrtr = buf.writer();
pub const allocator = arena.allocator();

pub fn main() !void {
    defer arena.deinit();
    // defaults
    var num_cols: usize = 7;
    var num_rows: usize = 5;
    // check if there is enough space to start the game
    if (num_cols == 0 or num_rows == 0) {
        try exitGameOnError(errors.insuf_space_for_numbers, .{});
    }
    var piece_height: u8 = 5;
    var piece_width: u8 = 11;
    var tty: ?std.os.fd_t = try std.os.open("/dev/tty", system.O.RDWR, 0);
    var dims: [2]usize = try getDimensions(tty);
    const screen_width = dims[0];
    const screen_height = dims[1];
    // remove weird printing behavior
    // can be fixed by clearing whole page, favor this for faster
    // printing
    const game_width = num_cols * piece_width;
    const game_height = num_rows * piece_height;
    if (game_height > screen_height or game_width > screen_width) {
        try exitGameOnError(errors.insuf_space_for_board, .{});
    }
    const draw_start_x: usize = (screen_width / 2) - (game_width / 2);
    const draw_start_y: usize = (screen_height / 2) - (game_height / 2);
    const board = try Board.init(piece_width, piece_height, num_rows, num_cols, draw_start_x, draw_start_y);
    try runGame(board);

    // Change this in future to hopefully work inline
    // have to save the position as when printing below and
    // the board moves up the restored position is wrong
}

fn runGame(board: Board) !void {
    try buf_wrtr.print(f.hide_cursor, .{});
    defer board.deinit();
    _ = try board.addRandomPiece();
    var orig = try std.os.tcgetattr(std.os.STDIN_FILENO);
    var new = orig;
    // TODO try this on windows, don't think it will work
    // make it it's own branch
    // ISIG: Disable vanilla CTRL-C and CTRL-Z
    // ECHO: Stop the terminal from displaying pressed keys.
    // ICANON: Allows us to read inputs byte-wise instead of line-wise.
    new.lflag &= ~(system.ECHO | system.ICANON | system.ISIG);
    try std.os.tcsetattr(std.os.STDIN_FILENO, std.os.TCSA.FLUSH, new);
    defer std.os.tcsetattr(std.os.STDIN_FILENO, std.os.TCSA.FLUSH, orig) catch {};
    var char: u8 = undefined;
    var reader = std.io.getStdIn().reader();
    try buf_wrtr.print(f.clear_page, .{});
    try buf_wrtr.print(f.set_cursor_pos, .{ 0, 0 });
    try buf.flush();
    var running = true;
    try board.draw();
    try buf.flush();
    while (running) {
        char = try reader.readByte();
        switch (char) {
            'q' => {
                try deinitGame(board, orig);
                exitGame();
            },
            'c' & '\x1F' => {
                try deinitGame(board, orig);
                exitGame();
            },
            'h', 'a' => {
                try board.slideLeft();
                _ = try board.addRandomPiece();
                try board.draw();
                try buf.flush();
            },
            'l', 'd' => {
                try board.slideRight();
                _ = try board.addRandomPiece();
                try board.draw();
                try buf.flush();
            },
            'k', 'w' => {
                try board.slideUp();
                _ = try board.addRandomPiece();
                try board.draw();
                try buf.flush();
            },
            'j', 's' => {
                try board.slideDown();
                _ = try board.addRandomPiece();
                try board.draw();
                try buf.flush();
            },
            else => {},
        }
    }
}

fn getDimensions(tty: ?std.os.fd_t) ![2]usize {
    if (tty == null) {
        return .{ 100, 100 };
    }
    var size = std.mem.zeroes(system.winsize);
    const err = system.ioctl(tty.?, system.T.IOCGWINSZ, @ptrToInt(&size));
    if (std.os.errno(err) != .SUCCESS) {
        return std.os.unexpectedErrno(@intToEnum(system.E, err));
    }
    return .{ size.ws_col, size.ws_row };
}

fn deinitGame(board: Board, orig: std.os.termios) !void {
    try buf_wrtr.print(f.show_cursor, .{});
    try buf.flush();
    board.deinit();
    std.os.tcsetattr(std.os.STDIN_FILENO, std.os.TCSA.FLUSH, orig) catch {};
    arena.deinit();
}

fn exitGame() void {
    std.os.exit(0);
}

pub fn exitGameOnError(comptime format: []const u8, args: anytype) !void {
    try buf_wrtr.print(format, args);
    try buf.flush();
    std.os.exit(1);
}
