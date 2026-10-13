const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;

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
        \\Prefixes:         0x,  0o,  0b,
        \\
        \\USAGE 
        \\base(prefix###)
        \\
        \\EXAMPLES
        \\
        \\Convert 69 to binary:    bin(69)
        \\Convert 0xFF to decimal: dec(0xFF)
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

            if (command.target == Base.DEC) {
                try stdout_writer.print("{d}\n", .{command.number});
                try stdout_writer.flush();
                continue;
            }

            var number_buffer: [128]u8 = undefined;
            const end_index = convertInt(&command, &number_buffer);

            const answer: []u8 = (number_buffer[0..end_index]);
            std.mem.reverse(u8, answer);
            try stdout_writer.print("{s}\n", .{answer});
            try stdout_writer.flush();
        }
    }
}

pub fn convertInt(command: *Command, number_buffer: []u8) usize {
    const divisor: u64 = baseAsNumber(command.target);
    var quotient: u64 = command.number;
    var i: usize = 0;
    while (quotient != 0) {
        const remainder: u64 = quotient % divisor;
        const ch = std.fmt.digitToChar(@intCast(remainder), std.fmt.Case.upper); // Only support upercase hex
        assert(i < number_buffer.len); // number of digits in u64 will never be more than buffer size
        number_buffer[i] = ch;
        quotient = quotient / divisor;
        i += 1;
    }

    number_buffer[i] = '0';
    i += 1;
    number_buffer[i] =
        switch (command.target) {
            .HEX => 'x',
            .OCT => 'o',
            .BIN => 'b',
            else => unreachable,
        };
    i += 1;
    return i;
}

// I made stdout_writer optional because I don't want to print error messages in the case of tests
pub fn parseCommand(command: *Command, trimmed_input: []const u8, stdout_writer: ?*Io.Writer) !void {
    // std.debug.print("{s}\n", .{trimmed_input});
    const lp_index: usize = std.mem.find(u8, trimmed_input, "(") orelse { // Ohh Guardian!
        if (stdout_writer) |writer| {
            try writer.writeAll("Invalid Command. Missing '('\n");
            try writer.flush();
        }
        return error.InvalidCommand;
    };

    const target_base = trimmed_input[0..lp_index];
    command.target = try matchTargetBase(target_base, stdout_writer);

    const rp_index: usize = std.mem.find(u8, trimmed_input, ")") orelse {
        if (stdout_writer) |writer| {
            try writer.writeAll("Invalid Command. Missing ')'\n");
            try writer.flush();
        }
        return error.InvalidCommand;
    };

    const number = trimmed_input[lp_index + 1 .. rp_index];
    // std.debug.print("{s}\n", .{number});
    if (number.len == 0) {
        if (stdout_writer) |writer| {
            try writer.writeAll("Invalid Command. Missing number\n");
            try writer.flush();
        }
        return error.InvalidCommand;
        // it has to have at least three characters to be a valid command w/prefix
    } else if (number.len >= 3) {
        if (number[0] == '0') {
            switch (number[1]) {
                'x' => {
                    command.current = Base.HEX;
                },
                'o' => {
                    command.current = Base.OCT;
                },
                'b' => {
                    command.current = Base.BIN;
                },
                else => {
                    if (stdout_writer) |writer| {
                        try writer.writeAll("Invalid Command. Decimal number can't have leading zeroes\n");
                        try writer.flush();
                    }
                    return error.InvalidCommand;
                },
            }
        } else {
            command.current = Base.DEC;
        }
        // it has to be one or two char decimal literal or invalid
    } else {
        command.current = Base.DEC;
    }

    if (command.current == Base.DEC) {
        for (number) |ch| {
            if (!std.ascii.isDigit(ch)) {
                if (stdout_writer) |writer| {
                    try writer.print("Invalid command. decimal number contains invalid digit {c}.\n", .{ch});
                    try writer.flush();
                }
                return error.InvalidCommand;
            }
        }
    }

    std.debug.print("passing to func {s}\n", .{number});

    const res = std.zig.parseNumberLiteral(number);
    switch (res) {
        .int => {
            command.number = res.int;
        },
        .big_int => {
            if (stdout_writer) |writer| {
                try writer.writeAll("Invalid command. Your number literal was bigger than 64-bits.\n");
                try writer.flush();
            }
            return error.InvalidCommand;
        },
        .float => {
            if (stdout_writer) |writer| {
                try writer.writeAll("Invalid command. Floats are not supported.\n");
                try writer.flush();
            }
            return error.InvalidCommand;
        },
        .failure => {
            // I don't think it's necessary to switch on this and give more details
            if (stdout_writer) |writer| {
                try writer.writeAll("Invalid command. Your number literal is invalid.\n");
                try writer.flush();
            }
            return error.InvalidCommand;
        },
    }

    if (command.target == command.current) {
        if (stdout_writer) |writer| {
            try writer.writeAll("Invalid command. Can't convert to the same base.\n");
            try writer.flush();
        }
        return error.InvalidCommand;
    }
}

// pub fn name() error.InvalidCommand {
//     std.debug.println("hi I always return error\n");
// }

// pub fn reportError(message, []const u8, writer: *Io.Writer) !void {
//     try writer.writeAll("Invalid command. Can't convert to the same base.\n");
//     try writer.flush();
// }

pub fn baseAsNumber(base: Base) u64 {
    switch (base) {
        .HEX => return 16,
        .DEC => return 10,
        .OCT => return 8,
        .BIN => return 2,
    }
}

pub fn matchTargetBase(target_base: []const u8, stdout_writer: ?*Io.Writer) !Base {
    if (std.mem.eql(u8, target_base, "hex")) {
        return Base.HEX;
    } else if (std.mem.eql(u8, target_base, "dec")) {
        return Base.DEC;
    } else if (std.mem.eql(u8, target_base, "oct")) {
        return Base.OCT;
    } else if (std.mem.eql(u8, target_base, "bin")) {
        return Base.BIN;
    } else {
        if (stdout_writer) |writer| {
            try writer.print("Invalid Command. {s} is not a supported base command\n", .{target_base});
            try writer.flush();
        }
        return error.InvalidCommand;
    }
}

pub fn matchCurrBase(curr_base: []const u8, stdout_writer: ?*Io.Writer) !Base {
    if (std.mem.eql(u8, curr_base, "0x")) {
        return Base.HEX;
    } else if (std.mem.eql(u8, curr_base, "0d")) {
        return Base.DEC;
    } else if (std.mem.eql(u8, curr_base, "0o")) {
        return Base.OCT;
    } else if (std.mem.eql(u8, curr_base, "0b")) {
        return Base.BIN;
    } else {
        if (stdout_writer) |writer| {
            try writer.print("Invalid Command. {s} is not a valid base prefix\n", .{curr_base});
            try writer.flush();
        }
        return error.InvalidCommand;
    }
}

// TODO: Implement tests for all the problems on the slides
// TODO: Implement tests for some parsing errors

// there was a legit error with the space thing
// testing parsing
test "random input" {
    var command: Command = undefined;
    const thing = parseCommand(&command, "random words", null);
    try std.testing.expectEqual(error.InvalidCommand, thing);
}

test "unsupoprted base" {
    var command: Command = undefined;
    const thing = parseCommand(&command, "base(69)", null);
    try std.testing.expectEqual(error.InvalidCommand, thing);
}

test "no prefix" {
    var command: Command = undefined;
    const thing = parseCommand(&command, "dec(FF)", null);
    try std.testing.expectEqual(error.InvalidCommand, thing);
}
