const std = @import("std");
const Types = @import("types.zig");

pub const MAGIC_NUMBER = Types.MAGIC_NUMBER;
pub const VERSION = Types.VERSION;

const NodeType = Types.NodeType;
const ImageType = Types.ImageType;
const MetaType = Types.MetaType;
const Meta = Types.Meta;
const LayerType = Types.LayerType;
const Layer = Types.Layer;
const LayerStack = Types.LayerStack;
const Node = Types.Node;
const File = Types.File;

pub const Conventions = Types.Conventions {};

const Error = error {
    UnexpectedEOF,
    NoHxaFile,
    NodeTypeNotRecognized,
    MetaTypeNotRecognized,
    LayerTypeNotRecognized,
    UnexpectedPointerType,
    InvalidComponents,
} || std.mem.Allocator.Error || std.fs.File.OpenError || std.os.ReadError || std.os.WriteError;


// TODO: The function relies on that alloc cannot fail (If it does an errdefer will trie to free unallocated memory)
// Read a HxA file and close it afterwards
pub fn load(allocator: std.mem.Allocator, file: *std.fs.File) Error!*File {

    // close file when done
    defer file.close();

    // temporary variables are used to make the free function work on error and avoid dirty memory
    var len: u32 = undefined;
    var version: u32 = undefined;

    //  check magic number
    var magic_number: @TypeOf(MAGIC_NUMBER) = undefined;
    try loadData(file, &magic_number);

    if (magic_number != MAGIC_NUMBER) {
        return Error.NoHxaFile;
    }

    // allocate hxa object
    const hxa = try allocator.create(File);
    errdefer {
        // std.debug.print("Error while reading file {s} at location {X}", .{ file., BYTES_READ });
        free(allocator, hxa);
    }

    // get version
    hxa.version = 0; hxa.len = 0;

    try loadData(file, &version);
    hxa.version =  version;

    // get node_count
    try loadData(file, &len);
    hxa.len = len;

    // allocate nodes
    hxa.nodes = try allocator.alloc(Node, hxa.len);

    for (hxa.nodes) |*node| {
        node.len = 0;

        try loadData(file, &node.type);
        if (@enumToInt(node.type) >= @typeInfo(NodeType).Enum.fields.len) {
            return Error.NodeTypeNotRecognized;
        }

        // set zero defaults (needed for free to avoid dirty memory)
        switch (node.type) {
            .geometry => {
                node.content.geometry.vertex_len = 0;
                node.content.geometry.edge_corner_len = 0;
                node.content.geometry.face_len = 0;
                node.content.geometry.vertex_stack.len = 0;
                node.content.geometry.edge_stack.len = 0;
                node.content.geometry.face_stack.len = 0;
            },
            .image => {
                node.content.image.type = .cube;
                node.content.image.resolution = [_]u32 {1, 1, 1};
                node.content.image.image_stack.len = 0;
            },
            else => {},
        }

        // get number of nodes
        try loadData(file, &len);
        node.len = len;

        node.meta = try allocator.alloc(Meta, node.len);
        try loadMeta(allocator, file, &node.meta);

        switch (node.type) {
            .geometry => {
                try loadData(file, &node.content.geometry.vertex_len);
                try loadStack(allocator, file, &node.content.geometry.vertex_stack, node.content.geometry.vertex_len);
                try loadData(file, &node.content.geometry.edge_corner_len);
                try loadStack(allocator, file, &node.content.geometry.corner_stack, node.content.geometry.edge_corner_len);
                if (hxa.version > 2)
                    try loadStack(allocator, file, &node.content.geometry.edge_stack, node.content.geometry.edge_corner_len);
                try loadData(file, &node.content.geometry.face_len);
                try loadStack(allocator, file, &node.content.geometry.face_stack, node.content.geometry.face_len);
            },
            .image => {
                try loadData(file, &node.content.image.type);
                var dimensions = @enumToInt(node.content.image.type);
                if (node.content.image.type == .cube)
                    dimensions = 2;
                try loadData(file, node.content.image.resolution[0..dimensions]);

                var size: u32 = node.content.image.resolution[0] * node.content.image.resolution[1] * node.content.image.resolution[2];
                if (node.content.image.type == .cube)
                    size *= 6;
                try loadStack(allocator, file, &node.content.image.image_stack, size);
            },
            else => {},
        }
    }

    return hxa;
}

fn loadData(file: *std.fs.File, buffer: anytype) Error!void {

    // represent passed value as slice of bytes
    var bytes: []u8 = undefined;

    const info = @typeInfo(@TypeOf(buffer)).Pointer;
    switch (info.size) {
        .Slice => bytes = @ptrCast([*]u8, buffer)[0 .. @sizeOf(info.child) * buffer.len],
        .One => bytes = @ptrCast([*]u8, buffer)[0 .. @sizeOf(info.child)],
        else => {
            return Error.UnexpectedPointerType;
        },
    }

    // read file bytes into buffer
    const read = try file.read(bytes);

    // if file read less than bytes than buffer - return error
    if (read != bytes.len) {
        return Error.UnexpectedEOF;
    }
}

fn loadName(allocator: std.mem.Allocator, file: *std.fs.File, name: *[]u8) !void {
    var len: u8 = undefined;
    try loadData(file, &len);

    name.* = try allocator.alloc(u8, len);
    try loadData(file, name.*);
}

fn loadMeta(allocator: std.mem.Allocator, file: *std.fs.File, meta: *[]Meta) Error!void {
    for (meta.*) |*data| {
        data.len = 0;
        var len: u32 = undefined;

        try loadName(allocator, file, &data.name);
        try loadData(file, &data.type);
        if (@enumToInt(data.type) >= @typeInfo(MetaType).Enum.fields.len)
            return Error.MetaTypeNotRecognized;

        try loadData(file, &len);
        data.len = len;

        switch (data.type) {
            .u64 => {
                data.values.u64 = try allocator.alloc(u64, data.len);
                try loadData(file, data.values.u64);
            },
            .f64 => {
                data.values.f64 = try allocator.alloc(f64, data.len);
                try loadData(file, data.values.f64);
            },
            .node => {
                data.values.node = try allocator.alloc(Node, data.len);
                try loadData(file, data.values.node);
            },
            .text => {
                data.values.text = try allocator.alloc(u8, data.len);
                try loadData(file, data.values.text);
            },
            .binary => {
                data.values.binary = try allocator.alloc(u8, data.len);
                try loadData(file, data.values.binary);
            },
            .meta => {
                data.values.meta = try allocator.alloc(Meta, data.len);
                try loadMeta(allocator, file, &data.values.meta);
            },
        }
    }
}

fn loadStack(allocator: std.mem.Allocator, file: *std.fs.File, stack: *LayerStack, layer_len: u32) Error!void {
    const type_sizes = [_]u32 { @sizeOf(u8), @sizeOf(u32), @sizeOf(f32), @sizeOf(f64) };    
    stack.len = 0;
    var len: u32 = undefined;

    try loadData(file, &len);
    stack.len = len;

    stack.layers = try allocator.alloc(Layer, stack.len);

    for (stack.layers) |*layer| {
        layer.components = 0;

        try loadName(allocator, file, &layer.name);
        try loadData(file, &layer.components);
        if (layer.components == 0)
            return Error.InvalidComponents;
        try loadData(file, &layer.type);

        if (@enumToInt(layer.type) >= @typeInfo(LayerType).Enum.fields.len) {
            return Error.LayerTypeNotRecognized;
        }

        layer.data = try allocator.alloc(u8, type_sizes[@enumToInt(layer.type)] * layer.components * layer_len);

        try loadData(file, layer.data);
    }
}

// Frees a HxA object
pub fn free(allocator: std.mem.Allocator, hxa: *File) void {

    for (hxa.nodes) |*node|
        freeNode(allocator, node, hxa.version);
    allocator.free(hxa.nodes);

    allocator.destroy(hxa);
}

fn freeNode(allocator: std.mem.Allocator, node: *Node, version: u32) void {
    for (node.meta) |*data| {
        freeMeta(allocator, data);
    }

    allocator.free(node.meta);

    switch (node.type) {
        .geometry => {
            freeStack(allocator, &node.content.geometry.corner_stack);
            freeStack(allocator, &node.content.geometry.vertex_stack);
            freeStack(allocator, &node.content.geometry.face_stack);
            if (version > 2)
                freeStack(allocator, &node.content.geometry.edge_stack);
        },
        .image => {
            freeStack(allocator, &node.content.image.image_stack);
        },
        else => {},
    }
}

fn freeMeta(allocator: std.mem.Allocator, meta: *Meta) void {
    allocator.free(meta.name);

    switch (meta.type) {
        .u64 => allocator.free(meta.values.u64),
        .f64 => allocator.free(meta.values.f64),
        .node => allocator.free(meta.values.node),
        .text => allocator.free(meta.values.text),
        .binary => allocator.free(meta.values.binary),
        .meta => {
            for (meta.values.meta) |*data|
                freeMeta(allocator, data);
            allocator.free(meta.values.meta);
        },
    }
}

fn freeStack(allocator: std.mem.Allocator, stack: *LayerStack) void {
    for (stack.layers) |*layer| {
        allocator.free(layer.name);
        allocator.free(layer.data);
    }

    allocator.free(stack.layers);
}

// Save a HxA object to the file and close it afterwards
pub fn save(hxa: *File, file: *std.fs.File) !void {

    defer file.close();

    _ = try file.write(std.mem.asBytes(&MAGIC_NUMBER));
    _ = try file.write(std.mem.asBytes(&hxa.version));
    _ = try file.write(std.mem.asBytes(&hxa.len));
    for (hxa.nodes) |*node| {
        _ = try file.write(std.mem.asBytes(&node.type));
        _ = try file.write(std.mem.asBytes(&node.len));

        for (node.meta) |*data|
            try saveMeta(file, data);

        switch (node.type) {
            .geometry => {
                _ = try file.write(std.mem.asBytes(&node.content.geometry.vertex_len));
                try saveStack(file, &node.content.geometry.vertex_stack);
                _ = try file.write(std.mem.asBytes(&node.content.geometry.edge_corner_len));
                try saveStack(file, &node.content.geometry.corner_stack);
                if (hxa.version > 2)
                    try saveStack(file, &node.content.geometry.edge_stack);
                _ = try file.write(std.mem.asBytes(&node.content.geometry.face_len));
                try saveStack(file, &node.content.geometry.face_stack);
            },
            .image => {
                _ = try file.write(std.mem.asBytes(&node.content.image.type));
                var dimension: u32 = @enumToInt(node.content.image.type);
                if (node.content.image.type == .cube)
                    dimension = 2;
                _ = try file.write(std.mem.sliceAsBytes(node.content.image.resolution[0..dimension]));
                try saveStack(file, &node.content.image.image_stack);
            },
            else => {},
        }
    }
}

fn saveMeta(file: *std.fs.File, meta: *Meta) Error!void {
    _ = try file.write(std.mem.asBytes(&@intCast(u8, meta.name.len)));
    _ = try file.write(meta.name);
    _ = try file.write(std.mem.asBytes(&meta.type));
    _ = try file.write(std.mem.asBytes(&meta.len));

    switch (meta.type) {
        .u64 => { _ = try file.write(std.mem.sliceAsBytes(meta.values.u64)); },
        .f64 => { _ = try file.write(std.mem.sliceAsBytes(meta.values.f64)); },
        .node => { _ = try file.write(std.mem.sliceAsBytes(meta.values.node)); },
        .text => { _ = try file.write(std.mem.sliceAsBytes(meta.values.text)); },
        .binary => { _ = try file.write(std.mem.sliceAsBytes(meta.values.binary)); },
        .meta => {
            for (meta.values.meta) |*data|
                try saveMeta(file, data);
        },
    }
}

fn saveStack(file: *std.fs.File, stack: *LayerStack) !void {
    _ = try file.write(std.mem.asBytes(&stack.len));

    for (stack.layers) |*layer| {
        _ = try file.write(std.mem.asBytes(&@intCast(u8, layer.name.len)));
        _ = try file.write(layer.name);
        _ = try file.write(std.mem.asBytes(&layer.components));
        _ = try file.write(std.mem.asBytes(&layer.type));
        _ = try file.write(layer.data);
    }
}

// Outline does not print layer data
const PrintOptions = enum { outline, data };

// Print a HxA file in human readable format to the writer object
pub fn print(hxa: *File, writer: *std.fs.File.Writer, option: PrintOptions) !void {

    try writer.print("HxA version: {}\n", .{ hxa.version });
    try writer.print("Node lenght: {}\n", .{ hxa.len });
    for (hxa.nodes) |*node, i| {
        try writer.print("-Node id: {}\n", .{ i });
        try writer.print("\t-Node type: {s}\n", .{ @tagName(node.type) });
        try writer.print("\t-Node meta length: {}\n", .{ node.len });
    
        try printMeta(writer, &node.meta, 2, option);

        switch (node.type) {
            .geometry => {
                try writer.print("\t-Geometry vertex length: {}\n", .{ node.content.geometry.vertex_len });
                try printStack(writer, &node.content.geometry.vertex_stack, "Vertex", option);
                try writer.print("\t-Geometry edge length: {}\n", .{ node.content.geometry.edge_corner_len });
                try printStack(writer, &node.content.geometry.corner_stack, "Corner", option);
                if (hxa.version > 2)
                    try printStack(writer, &node.content.geometry.edge_stack, "Edge", option);
                try writer.print("\t-Geometry face length: {}\n", .{ node.content.geometry.face_len });
                try printStack(writer, &node.content.geometry.face_stack, "Face", option);
            },
            .image => {
                try writer.print("\t-Pixel type: {s}\n", .{ @tagName(node.content.image.type) });
                switch (node.content.image.type) {
                    .cube => try writer.print("\t-Pixel resolution: {} x {} x 6", .{ node.content.image.resolution[0], node.content.image.resolution[1] }),
                    .@"1d" => try writer.print("\t-Pixel resolution: {}\n", .{ node.content.image.resolution[0] }),
                    .@"2d" => try writer.print("\t-Pixel resolution: {} x {}\n", .{ node.content.image.resolution[0], node.content.image.resolution[1] }),
                    .@"3d" => try writer.print("\t-Pixel resolution: {} x {} x {}\n", .{ node.content.image.resolution[0], node.content.image.resolution[1], node.content.image.resolution[2] }),
                }
            },
            else => {},
        }
    }
}

fn printMeta(writer: *std.fs.File.Writer, meta: *[]Meta, tab_len: usize, option: PrintOptions) Error!void {
    const tabs = [_]u8 {'\t'} ** 16;

    for (meta.*) |*data, i| {
        _ = i;

        try writer.print("{s}-Meta {s} \"{s}\" [{}]:", .{ tabs[0..tab_len % tabs.len], @tagName(data.type), data.name, data.len });

        // print data
        if (option == .data) {
            switch(data.type) {
                .u64 => try writer.print(" {any}", .{ data.values.u64[0..@minimum(tabs.len, data.values.u64.len)] }),
                .f64 => try writer.print(" {any}", .{ data.values.f64[0..@minimum(tabs.len, data.values.f64.len)] }),
                .node => try writer.print("{any}", .{ data.values.node[0..@minimum(tabs.len, data.values.text.len)] }),
                .text => try writer.print(" {s}", .{ data.values.text[0..@minimum(tabs.len, data.values.binary.len)] }),
                .binary => try writer.print(" {}", .{ std.fmt.fmtSliceHexUpper(data.values.binary) }),
                .meta => try printMeta(writer, &data.values.meta, tab_len + 1, option),
            }
        }

        if (data.type != .meta) {
            if (data.len > tabs.len and data.type != .text) {
                try writer.print(" ...\n", .{});
            } else {
                try writer.print("\n", .{});
            }
        }
    }

}

fn printStack(writer: *std.fs.File.Writer, stack: *LayerStack, name: []const u8, option: PrintOptions) !void {
    try writer.print("\t-{s} Layer length: {}\n", .{ name, stack.layers.len });

    for (stack.layers) |*layer| {
        try writer.print("\t\tLayer name: {s}\n", .{ layer.name });
        try writer.print("\t\tLayer components: {}\n", .{ layer.components });
        try writer.print("\t\tLayer type: {s}\n", .{ @tagName(layer.type) });

        if (option == .data) {
            switch (layer.type) {
                .u8 => {
                    var i: usize = 0;
                    while (i < layer.data.len) : (i += layer.components )
                        try writer.print("\t\t\t{d} \n", .{ layer.data[i..i + layer.components] });
                },
                .i32 => {
                    if (std.mem.eql(u8, layer.name, "reference" ) and layer.components == 1) {
                        const data = @ptrCast([*]align(1) i32, layer.data)[0 .. layer.data.len / @sizeOf(i32)];
                        var i: usize = 0;
                        for (data) |d, j| {
                            if (d < 0) {
                                try writer.print("\t\t\t{d}\n", .{ data[i..j+1] });
                                i = j+1;
                            }
                        }
                    } else {
                        var i: usize = 0;
                        const data = @ptrCast([*]align(1) i32, layer.data)[0 .. layer.data.len / @sizeOf(i32)];
                        while (i < data.len) : (i += layer.components )
                            try writer.print("\t\t\t{d} \n", .{ data[i..i + layer.components] });                        
                    }
                },
                .f32 => {
                    var i: usize = 0;
                    const data = @ptrCast([*]align(1) f32, layer.data)[0 .. layer.data.len / @sizeOf(f32)];
                    while (i < data.len) : (i += layer.components )
                        try writer.print("\t\t\t{d:.6} \n", .{ data[i..i + layer.components] });
                },
                .f64 => {
                    var i: usize = 0;
                    const data = @ptrCast([*]align(1) f64, layer.data)[0 .. layer.data.len / @sizeOf(f64)];
                    while (i < data.len) : (i += layer.components )
                        try writer.print("\t\t\t{d:.6} \n", .{ data[i..i + layer.components] });
                },
            }
        }
    }
}

// Upgrade old files to newer version
// Silent if hxa.version is newer than version
// Please upgrade right after loading, before working on the file
pub fn upgradeVersion(allocator: std.mem.Allocator, hxa: *File, version: u32) !void {
    if (hxa.version < version) {
        if (version > 2) {
            hxa.version = version;
            for (hxa.nodes) |*node| {
                if (node.type == .geometry)
                    node.content.geometry.edge_stack.layers = try allocator.alloc(Layer, 0);
            }
        }
    }
}
