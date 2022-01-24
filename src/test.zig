const std = @import("std");
const hxa = @import("HxA.zig");

const allocator = std.testing.allocator;

test "Load and free HxA file v1" {
    // Load and free
    const teapot_v1 = try hxa.load(allocator, &try std.fs.cwd().openFile("Test/teapot_v1.hxa", .{ .read = true }));
    defer hxa.free(allocator, teapot_v1);
}

test "Load and free HxA file v3" {
    // Load and free
    const teapot_v3 = try hxa.load(allocator, &try std.fs.cwd().openFile("Test/teapot_v3.hxa", .{ .read = true }));
    defer hxa.free(allocator, teapot_v3);
}

test "Load, save v1" {
    // Load and Save
    const teapot_v1 = try hxa.load(allocator, &try std.fs.cwd().openFile("Test/teapot_v1.hxa", .{ .read = true }));
    defer hxa.free(allocator, teapot_v1);
    try hxa.save(teapot_v1, &try std.fs.cwd().createFile("Test/teapot_v1_test.hxa", .{ .read = true }));

    // Read and compare
    try checkFileEql("Test/teapot_v1.hxa", "Test/teapot_v1_test.hxa");
}

test "Load, save v3" {
    // Load and Save
    const teapot_v3 = try hxa.load(allocator, &try std.fs.cwd().openFile("Test/teapot_v3.hxa", .{ .read = true }));
    defer hxa.free(allocator, teapot_v3);
    try hxa.save(teapot_v3, &try std.fs.cwd().createFile("Test/teapot_v3_test.hxa", .{ .read = true }));

    // Read and compare
    try checkFileEql("Test/teapot_v3.hxa", "Test/teapot_v3_test.hxa");
}

test "Load and convert HxA file v1 to v3" {
    // Load and free
    const teapot = try hxa.load(allocator, &try std.fs.cwd().openFile("Test/teapot_v1.hxa", .{ .read = true }));
    defer hxa.free(allocator, teapot);

    try hxa.upgradeVersion(allocator, teapot, 3);
    try hxa.save(teapot, &try std.fs.cwd().createFile("Test/teapot_converted_v1_v3.hxa", .{ .read = true }));

    try checkFileEql("Test/teapot_v3.hxa", "Test/teapot_converted_v1_v3.hxa");
}

test "Load and print HxA file v1" {
    const file = try std.fs.cwd().createFile("Test/teapot_v1_print_test.txt", .{});
    defer file.close();

    const writer = &file.writer();

    // Load and free
    const teapot_v1 = try hxa.load(allocator, &try std.fs.cwd().openFile("Test/teapot_v1.hxa", .{ .read = true }));
    defer hxa.free(allocator, teapot_v1);

    try hxa.print(teapot_v1, writer, .data);

    try checkFileEql("Test/teapot_v1_print.txt", "Test/teapot_v1_print_test.txt");
}

test "Load and print HxA file v3" {
    const file = try std.fs.cwd().createFile("Test/teapot_v3_print_test.txt", .{});
    defer file.close();

    const writer = &file.writer();

    // Load and free
    const teapot_v3 = try hxa.load(allocator, &try std.fs.cwd().openFile("Test/teapot_v3.hxa", .{ .read = true }));
    defer hxa.free(allocator, teapot_v3);

    try hxa.print(teapot_v3, writer, .data);

    try checkFileEql("Test/teapot_v3_print.txt", "Test/teapot_v3_print_test.txt");
}

fn checkFileEql(filepath1: []const u8, filepath2: []const u8) !void {

    // Read and compare
    const file1 = &try std.fs.cwd().openFile(filepath1, .{ .read = true });
    defer file1.close();
    const file2 = &try std.fs.cwd().openFile(filepath2, .{ .read = true });
    defer file2.close();

    const file1_stat = try file1.stat();
    const file2_stat = try file2.stat();

    if (file1_stat.size != file2_stat.size) {
        std.debug.print("Files are of different sizes.\n\t{s}: {}\n{s}: {}\n", .{ filepath1, file1_stat.size, filepath2, file2_stat.size });
        try std.testing.expect(false);
    }

    const contents1 = try allocator.alloc(u8, file1_stat.size);
    defer allocator.free(contents1);

    const contents2 = try allocator.alloc(u8, file2_stat.size);
    defer allocator.free(contents2);

    _ = try file1.read(contents1);
    _ = try file2.read(contents2);

    var i: usize = 0;
    var diffs: usize = 0;
    while (i < contents1.len) : (i += 1) {
        if (contents1[i] != contents2[i]) {
            if (diffs == 0)
                std.debug.print("Differences were detected.\n\tFirst Diff at: {X}\n", .{ i });
            diffs += 1;
        }
    }
    if (diffs != 0) {
        std.debug.print("\tTotal Differences: {}\n", .{ i });
        try std.testing.expect(false);
    }
}
