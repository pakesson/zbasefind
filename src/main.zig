const std = @import("std");

const mem = std.mem;
const os = std.os;
const ascii = std.ascii;
const process = std.process;

const Allocator = mem.Allocator;
const AutoHashMap = std.AutoHashMap;

const AddressMatches = struct {
    address: u32,
    matches: usize,
};

pub const FirmwareFile = struct {
    allocator: Allocator,
    size: usize,
    pointers: AutoHashMap(u32, u32), // address, count
    strings: AutoHashMap(u32, []const u8), // address, string
    buffer: []const u8,

    pub const Error = error{
    };

    pub fn open(allocator: Allocator, path: []const u8) !FirmwareFile {
        const file = try std.fs.cwd().openFile(
            path,
            .{.mode = .read_only},
        );
        defer file.close();

        const stat = try file.stat();
        const size = stat.size;

        var buf = try file.readToEndAlloc(allocator, 100_000_000);
        errdefer allocator.free(buf);

        std.log.info("File size = {}", .{size});
        std.log.info("Buffer size = {}", .{buf.len});

        return FirmwareFile{
            .allocator = allocator,
            .size = size,
            .pointers = AutoHashMap(u32, u32).init(allocator),
            .strings = AutoHashMap(u32, []const u8).init(allocator),
            .buffer = buf,
        };
    }

    pub fn deinit(self: *FirmwareFile) void {
        self.pointers.deinit();
        self.strings.deinit();
        self.allocator.free(self.buffer);
    }

    pub fn get_pointers(self: *FirmwareFile) !void {
        const wordnum = self.size / 4;
        const ptrs = @ptrCast([*]const u32, @alignCast(@alignOf(u32), self.buffer))[0..wordnum];

        for (ptrs) |ptr| {
            const key: u32 = ptr;
            if (!self.pointers.contains(key)) {
                try self.pointers.put(key, 1);
            } else {
                const old = self.pointers.get(key).?;
                try self.pointers.put(key, old + 1);
            }
        }

        std.log.info("Number of pointers: {}", .{self.pointers.count()});
    }

    // Find null-terminated strings
    pub fn find_strings(self: *FirmwareFile, minLength: usize) !void {
        var inString: bool = false;
        var startIdx: u32 = 0;
        for (self.buffer) |val, i| {
            if (val == 0 and inString) {
                if (i-startIdx >= minLength) {
                    const s = mem.span(self.buffer[startIdx..i]);
                    try self.strings.put(startIdx, s);
                }
                inString = false;
                continue;
            }
            if (ascii.isPrint(val)) {
                if (!inString) startIdx = @truncate(u32, i);
                inString = true;
            } else {
                inString = false;
            }
        }

        std.log.info("Number of strings: {}", .{self.strings.count()});
    }

    pub fn find_base_address(self: *FirmwareFile) !u32 {
        // TODO
        const ADDR_MAX = 0xFFFF_0000;
        const ADDR_STEP = 0x10_000;

        var queue = std.PriorityDequeue(AddressMatches, void, struct {
            fn order(context: void, a: AddressMatches, b: AddressMatches) std.math.Order {
                _ = context;
                return std.math.order(a.matches, b.matches);
            }
        }.order).init(self.allocator, {});
        defer queue.deinit();

        var baseAddrCandidate: u32 = 0;
        while (baseAddrCandidate < ADDR_MAX) : (baseAddrCandidate += ADDR_STEP) {
            var numMatches: u32 = 0;

            const max_test = std.math.maxInt(@TypeOf(baseAddrCandidate)) - baseAddrCandidate;

            var stringIterator = self.strings.iterator();
            while (stringIterator.next()) |entry| {
                if (entry.key_ptr.* > max_test) continue;

                var adjustedAddress: u32 = 0;
                _ = @addWithOverflow(u32, entry.key_ptr.*, @truncate(u32, baseAddrCandidate), &adjustedAddress);

                if (self.pointers.contains(adjustedAddress)) {
                    numMatches += self.pointers.get(adjustedAddress).?;
                }
            }

            if (queue.len < 5) {
                try queue.add(.{ .address = baseAddrCandidate, .matches = numMatches});
            } else if (numMatches > queue.peekMin().?.matches) {
                _ = queue.removeMin();
                try queue.add(.{ .address = baseAddrCandidate, .matches = numMatches});
            }
        }

        std.log.info("Best base address candidates:", .{});

        while (queue.len > 0) {
            const e = queue.removeMax();
            std.log.info("Base address: {x:0>8}, matches: {}", .{e.address, e.matches});
        }

        return 0;
    }
};

pub fn main() anyerror!void {
    var gpalloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpalloc.deinit());
    const allocator = gpalloc.allocator();

    const stdout = std.io.getStdOut().writer();

    var args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    if (args.len != 2) {
        try stdout.print("Usage: {s} FIRMWARE_FILE\n", .{args[0]});
        return;
    }

    const firmware_path = args[1];

    var firmwareFile = try FirmwareFile.open(allocator, firmware_path);
    defer firmwareFile.deinit();

    std.log.info("Loaded firmware file {s}", .{firmware_path});

    try firmwareFile.get_pointers();
    try firmwareFile.find_strings(6);

    _ = try firmwareFile.find_base_address();    
}
