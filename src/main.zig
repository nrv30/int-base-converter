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

            // std.debug.print("command-number: {d}\n", .{command.number});
            var number_buffer: [128]u8 = undefined;
            const answer = convertInt(&command, &number_buffer);

            try stdout_writer.print("{s}\n", .{answer});
            try stdout_writer.flush();
        }
    }
}

// number of digits in u64 will never be more than 128. Regardless of Base.
pub fn convertInt(command: *Command, number_buffer: []u8) []u8 {
    var answer: []u8 = undefined;
    if (command.target != Base.DEC) {
        const divisor: u64 = baseAsNumber(command.target);
        var quotient: u64 = command.number;
        var i: usize = 0;
        while (quotient != 0) {
            const remainder: u64 = quotient % divisor;
            const ch = std.fmt.digitToChar(@intCast(remainder), std.fmt.Case.upper);
            assert(i < number_buffer.len); //
            number_buffer[i] = ch;
            quotient = quotient / divisor;
            i += 1;
        }

        number_buffer[i] =
            switch (command.target) {
                .HEX => 'x',
                .OCT => 'o',
                .BIN => 'b',
                else => unreachable,
            };
        i += 1;
        number_buffer[i] = '0';
        i += 1;
        answer = number_buffer[0..i];
        std.mem.reverse(u8, answer);
    } else {
        answer = std.fmt.bufPrint(number_buffer, "{d}", .{command.number}) catch unreachable;
    }
    return answer;
}

pub fn parseCommand(command: *Command, trimmed_input: []const u8, writer: *Io.Writer) !void {
    const lp_index: usize = std.mem.find(u8, trimmed_input, "(") orelse { // Ohh Guardian!
        return reportInvalidCommand("Missing '('", writer);
    };

    const target_base = trimmed_input[0..lp_index];
    command.target = try matchTargetBase(target_base, writer);

    const rp_index: usize = std.mem.find(u8, trimmed_input, ")") orelse {
        return reportInvalidCommand("Missing ')'", writer);
    };

    const number = trimmed_input[lp_index + 1 .. rp_index];
    if (number.len == 0) {
        return reportInvalidCommand("Missing number", writer);
    } else if (number.len >= 3) { // it has to have at least three characters to be a valid command w/prefix
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
                    return reportInvalidCommand("Decimal number can't have leading zeroes", writer);
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
                return reportInvalidCommand("Decimal number contains invalid digit {c}.", writer);
            }
        }
    }

    const res = std.zig.parseNumberLiteral(number);
    switch (res) {
        .int => {
            command.number = res.int;
        },
        .big_int => {
            return reportInvalidCommand("Your number literal was bigger than 64-bits.", writer);
        },
        .float => {
            return reportInvalidCommand("Floats are not supported.", writer);
        },
        .failure => {
            // I don't think it's necessary to switch on this and give more details
            return reportInvalidCommand("Your number literal is invalid.", writer);
        },
    }

    if (command.target == command.current) {
        return reportInvalidCommand("Can't convert to the same base.", writer);
    }
}

pub fn reportInvalidCommand(message: []const u8, writer: *Io.Writer) error{ InvalidCommand, WriteFailed } {
    try writer.print("Invalid command. {s}\n", .{message});
    try writer.flush();
    return error.InvalidCommand;
}

pub fn baseAsNumber(base: Base) u64 {
    switch (base) {
        .HEX => return 16,
        .DEC => return 10,
        .OCT => return 8,
        .BIN => return 2,
    }
}

pub fn matchTargetBase(target_base: []const u8, writer: *Io.Writer) !Base {
    if (std.mem.eql(u8, target_base, "hex")) {
        return Base.HEX;
    } else if (std.mem.eql(u8, target_base, "dec")) {
        return Base.DEC;
    } else if (std.mem.eql(u8, target_base, "oct")) {
        return Base.OCT;
    } else if (std.mem.eql(u8, target_base, "bin")) {
        return Base.BIN;
    } else {
        try writer.print("Invalid Command. {s} is not a supported base command\n", .{target_base});
        try writer.flush();
        return error.InvalidCommand;
    }
}

pub fn matchCurrBase(curr_base: []const u8, writer: *Io.Writer) !Base {
    if (std.mem.eql(u8, curr_base, "0x")) {
        return Base.HEX;
    } else if (std.mem.eql(u8, curr_base, "0d")) {
        return Base.DEC;
    } else if (std.mem.eql(u8, curr_base, "0o")) {
        return Base.OCT;
    } else if (std.mem.eql(u8, curr_base, "0b")) {
        return Base.BIN;
    } else {
        try writer.print("Invalid Command. {s} is not a valid base prefix\n", .{curr_base});
        try writer.flush();
        return error.InvalidCommand;
    }
}

pub fn debugln(message: []const u8) void {
    std.debug.print("{s}\n", .{message});
}

// testing converting
test "exercise 1" {
    var twriter = Io.Writer.Discarding.init(&.{});
    var command: Command = undefined;
    _ = try parseCommand(&command, "dec(0b1_0101_1111)", &twriter.writer);
    var number_buffer: [128]u8 = undefined;
    const answer = convertInt(&command, &number_buffer);
    try std.testing.expectEqualStrings("351", answer);
}

test "exercise 2" {
    var twriter = Io.Writer.Discarding.init(&.{});
    var command: Command = undefined;
    _ = try parseCommand(&command, "dec(0o7016)", &twriter.writer);
    var number_buffer: [128]u8 = undefined;
    const answer = convertInt(&command, &number_buffer);
    try std.testing.expectEqualStrings("3598", answer);
}

test "exercise 3" {
    var twriter = Io.Writer.Discarding.init(&.{});
    var command: Command = undefined;
    _ = try parseCommand(&command, "dec(0x2AE0B)", &twriter.writer);
    var number_buffer: [128]u8 = undefined;
    const answer = convertInt(&command, &number_buffer);
    try std.testing.expectEqualStrings("175627", answer);
}

test "exercise 4" {
    var twriter = Io.Writer.Discarding.init(&.{});
    var command: Command = undefined;
    _ = try parseCommand(&command, "hex(0b1110_0101)", &twriter.writer);
    var number_buffer: [128]u8 = undefined;
    const answer = convertInt(&command, &number_buffer);
    try std.testing.expectEqualStrings("0xE5", answer);
}

test "exercise 5" {
    var twriter = Io.Writer.Discarding.init(&.{});
    var command: Command = undefined;
    _ = try parseCommand(&command, "oct(12345)", &twriter.writer);
    var number_buffer: [128]u8 = undefined;
    const answer = convertInt(&command, &number_buffer);
    try std.testing.expectEqualStrings("0o30071", answer);
}

test "exercise 6" {
    var twriter = Io.Writer.Discarding.init(&.{});
    var command: Command = undefined;
    _ = try parseCommand(&command, "hex(177130)", &twriter.writer);
    var number_buffer: [128]u8 = undefined;
    const answer = convertInt(&command, &number_buffer);
    try std.testing.expectEqualStrings("0x2B3EA", answer);
}

test "exercise 7" {
    var twriter = Io.Writer.Discarding.init(&.{});
    var command: Command = undefined;
    _ = try parseCommand(&command, "bin(241)", &twriter.writer);
    var number_buffer: [128]u8 = undefined;
    const answer = convertInt(&command, &number_buffer);
    try std.testing.expectEqualStrings("0b11110001", answer);
}

// testing parsing
test "random input" {
    var twriter = Io.Writer.Discarding.init(&.{});
    var command: Command = undefined;
    const thing = parseCommand(&command, "random words", &twriter.writer);
    try std.testing.expectEqual(error.InvalidCommand, thing);
}

test "unsupoprted base" {
    var twriter = Io.Writer.Discarding.init(&.{});
    var command: Command = undefined;
    const thing = parseCommand(&command, "base(69)", &twriter.writer);
    try std.testing.expectEqual(error.InvalidCommand, thing);
}

test "no prefix" {
    var twriter = Io.Writer.Discarding.init(&.{});
    var command: Command = undefined;
    const thing = parseCommand(&command, "dec(FF)", &twriter.writer);
    try std.testing.expectEqual(error.InvalidCommand, thing);
}

test "same base" {
    var twriter = Io.Writer.Discarding.init(&.{});
    var command: Command = undefined;
    const thing = parseCommand(&command, "dec(420)", &twriter.writer);
    try std.testing.expectEqual(error.InvalidCommand, thing);
}

test "no number" {
    var twriter = Io.Writer.Discarding.init(&.{});
    var command: Command = undefined;
    const thing = parseCommand(&command, "dec()", &twriter.writer);
    try std.testing.expectEqual(error.InvalidCommand, thing);
}

test "wrong prefix" {
    var twriter = Io.Writer.Discarding.init(&.{});
    var command: Command = undefined;
    const thing = parseCommand(&command, "dec(0AFF)", &twriter.writer);
    try std.testing.expectEqual(error.InvalidCommand, thing);
}

test "big number" {
    var twriter = Io.Writer.Discarding.init(&.{});
    var command: Command = undefined;
    const thing = parseCommand(&command, "bin(18446744073709551616)", &twriter.writer);
    try std.testing.expectEqual(error.InvalidCommand, thing);
}

test "negative number" {
    var twriter = Io.Writer.Discarding.init(&.{});
    var command: Command = undefined;
    const thing = parseCommand(&command, "-10", &twriter.writer);
    try std.testing.expectEqual(error.InvalidCommand, thing);
}

test "float" {
    var twriter = Io.Writer.Discarding.init(&.{});
    var command: Command = undefined;
    const thing = parseCommand(&command, "bin(10.5)", &twriter.writer);
    try std.testing.expectEqual(error.InvalidCommand, thing);
}

test "unequal parens" {
    var twriter = Io.Writer.Discarding.init(&.{});
    var command: Command = undefined;
    const thing = parseCommand(&command, "bin((0xFF)", &twriter.writer);
    try std.testing.expectEqual(error.InvalidCommand, thing);
}
