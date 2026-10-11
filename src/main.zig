const std = @import("std");
const Io = std.Io;

const int_converter = @import("int_converter");

const Base = enum {
    HEX,
    BIN,
    DEC,
    OCT,
};

const Command = struct {
    target: Base,
    current: Base,
    number: u64,
};

pub fn main(init: std.process.Init) !void {
    // In order to do I/O operations need an `Io` instance.
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    const max_line_size: u32 = 128;
    var stdin_buffer: [max_line_size]u8 = undefined;
    var stdin_file_reader: Io.File.Reader = .init(.stdin(), io, &stdin_buffer);
    const stdin_reader = &stdin_file_reader.interface;

    const usage =
        \\INFO
        \\Limited to 64-bit unsigned integers
        \\
        \\Base Commands:    hex, oct, bin, dec
        \\
        \\Prefixes:         0x,  0o,  0b,  (no prefix)
        \\
        \\USAGE 
        \\base(prefix###)
        \\
        \\EXAMPLES
        \\
        \\"Convert 69 to binary:"    bin(69)
        \\"Convert 0xFF to decimal:" dec(0xFF)
    ;

    // REPL main loop
    // This should probably be command-line utility not repl? idk I'm in too deep atp to change
    var should_quit: bool = false;
    while (!should_quit) {
        try stdout_writer.writeAll(">>> ");
        try stdout_writer.flush();

        const input = stdin_reader.takeDelimiterExclusive('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                const input_size: usize = try stdin_reader.discardDelimiterInclusive('\n');
                const diff: usize = input_size - max_line_size;
                try stdout_writer.print("Your input was {d} bytes too long. The max is {d}.\n", .{ diff, max_line_size });
                try stdout_writer.flush();
                continue;
            },
            else => |e| return e,
        };
        stdin_reader.toss(1);

        const trimmed_input = std.mem.trim(u8, input, " \n\r\t");

        // TODO: add a command to clear the terminal screen
        if (std.mem.eql(u8, trimmed_input, "exit")) {
            should_quit = true;
        } else if (std.mem.eql(u8, trimmed_input, "help")) {
            try stdout_writer.print("{s}\n", .{usage});
            try stdout_writer.flush();
            continue;
        } else {
            // it's a command, still could be invalid though
            var command: Command = undefined;
            parseCommand(&command, trimmed_input, stdout_writer) catch |err| switch (err) {
                error.InvalidCommand => {
                    try stdout_writer.writeAll("Type 'help' for usage info\n");
                    try stdout_writer.flush();
                    continue;
                },
                else => |e| return e,
            };
        }
    }
}

pub fn parseCommand(command: *Command, trimmed_input: []const u8, stdout_writer: *Io.Writer) !void {
    const lp_index: usize = std.mem.find(u8, trimmed_input, "(") orelse { // Ohh Guardian!
        try stdout_writer.writeAll("Invalid Command. Missing '('\n");
        try stdout_writer.flush();
        return error.InvalidCommand;
    };

    const target_base = trimmed_input[0..lp_index];
    command.target = try matchTargetBase(target_base, stdout_writer);

    const rp_index: usize = std.mem.find(u8, trimmed_input, ")") orelse {
        try stdout_writer.writeAll("Invalid Command. Missing ')'\n");
        try stdout_writer.flush();
        return error.InvalidCommand;
    };

    const number = trimmed_input[lp_index + 1 .. rp_index];
    if (number.len == 0) {
        try stdout_writer.writeAll("Invalid Command. Missing number\n");
        try stdout_writer.flush();
        return error.InvalidCommand;
        // now I can check if it has a base
    } else if (number.len > 3) {
        if (number[0] == '0') {
            switch (number[1]) {
                'x' => {
                    command.target = Base.HEX;
                },
                'o' => {
                    command.target = Base.OCT;
                },
                'b' => {
                    command.target = Base.BIN;
                },
                // not a base prefix, has to be decimal or invalid
                else => {
                    command.target = Base.DEC;
                },
            }
            // it has to be one or two char decimal literal or invalid
        } else {
            command.target = Base.DEC;
        }
    }

    const res = std.zig.parseNumberLiteral(number);
    switch (res) {
        .int => {
            command.number = res.int;
        },
        .big_int => {
            try stdout_writer.writeAll("Invalid command. Your number literal was bigger than 64-bits.\n");
            try stdout_writer.flush();
            return error.InvalidCommand;
        },
        .float => {
            try stdout_writer.writeAll("Invalid command. Floats are not supported.\n");
            try stdout_writer.flush();
            return error.InvalidCommand;
        },
        .failure => {
            // I don't think it's necessary to switch on this and give more details
            try stdout_writer.writeAll("Invalid command. Your number literal is invalid.\n");
            try stdout_writer.flush();
            return error.InvalidCommand;
        },
    }

    const tb = std.enums.tagName(Base, command.current) orelse "";
    const cb = std.enums.tagName(Base, command.target) orelse "";
    std.debug.print("Target Base:{s}, Current Base: {s}, Number{d}\n", .{ tb, cb, command.number });
}

pub fn matchTargetBase(target_base: []const u8, stdout_writer: *Io.Writer) !Base {
    if (std.mem.eql(u8, target_base, "hex")) {
        return Base.HEX;
    } else if (std.mem.eql(u8, target_base, "dec")) {
        return Base.DEC;
    } else if (std.mem.eql(u8, target_base, "oct")) {
        return Base.OCT;
    } else if (std.mem.eql(u8, target_base, "bin")) {
        return Base.BIN;
    } else {
        try stdout_writer.print("Invalid Command. {s} is not a supported base command\n", .{target_base});
        try stdout_writer.flush();
        return error.InvalidCommand;
    }
}

pub fn matchCurrBase(curr_base: []const u8, stdout_writer: *Io.Writer) !Base {
    if (std.mem.eql(u8, curr_base, "0x")) {
        return Base.HEX;
    } else if (std.mem.eql(u8, curr_base, "0d")) {
        return Base.DEC;
    } else if (std.mem.eql(u8, curr_base, "0o")) {
        return Base.OCT;
    } else if (std.mem.eql(u8, curr_base, "0b")) {
        return Base.BIN;
    } else {
        try stdout_writer.print("Invalid Command. {s} is not a valid base prefix\n", .{curr_base});
        try stdout_writer.flush();
        return error.InvalidCommand;
    }
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
