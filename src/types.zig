//
// HxA is a interchangeable graphics asset format. Written by Eskil Steenberg. @quelsolaar / eskil 'at' obsession 'dot' se / www.quelsolaar.com
//

//
// TODO: Structure
//
// HxA is designed to be extremely simple to parse, and is therefore based around conventions.
// It has a few basic structures, and depending on how they are used they mean different things.
// This means that you can implement a tool that loads the entire file, modifies the parts it cares about and leaves the rest intact.
// It is also possible to write a tool that makes all data in the file editable without the need to understand its use.
// It is also possible for anyone to use the format to store axillary data.
// Anyone who wants to store data not covered by a convention can submit a convention to extend the format.
// There should never be a convention for storing the same data in two differed ways.

// The data is story in a number of nodes that are stored in an array.
// Each node stores an array of meta data.
// Meta data can describe anything you want, and a lot of conventions will use meta data to store additional information, for things like transforms, lights, shaders and animation.
// Data for Vertices, Corners, Faces, and Pixels are stored in named layer stacks. Each stack consists of a number of named layers. All layers in the stack have the same number of elements.
// Each layer describes one property of the primitive. Each layer can have multiple channels and each layer can store data of a different type.

// HxA stores 3 kinds of nodes
// -Pixel data.
// -Polygon geometry data.
// -Meta data only.

// Pixel Nodes stores pixels in a layer stack. A layer may store things like Albedo, Roughness, Reflectance, Light maps, Masks, Normal maps, and Displacements.
// Layers use the channels of the layers to store things like color.

// Geometry data is stored in 3 separate layer stacks for: vertex data, corner data and face data.
// The vertex data stores things like veritices, blend shapes, weight maps, and vertex colors.
// The first layer in a vertex stack has to be a 3 channel layer named "position" describing the base position of the vertices.
// The corner stack describes data per corner or edge of the polygons. It can be used for things like UV, normals, and adjacency.
// The first layer in a corner stack has to be a 1 channel integer layer named "index" describing the vertices used to form polygons.
// The last value in each polygon has a negative - 1 index to indicate the end of the polygon.

// Example:
// 	A quad and a tri with the vertex index:
// 		[0, 1, 2, 3] [1, 4, 2]
// 	are stored as:
// 		[0, 1, 2, -4, 1, 4, -3]

// The face stack stores values per face. the length of the face stack has to match the number of negative values in the index layer in the corner stack.
// The face stack can be used to store things like material index.

//
// Storage
//
// All data is stored in little endian byte order with no padding. The layout mirrors the struct defined below with a few exceptions.
// All names are stored as u8 indicating the lenght of the name followed by that many characters. Termination is not stored in the file.
// Text strings stored in meta data are stored the same way as names, but inseatd of u8 for size a u32 is used.

pub const MAGIC_NUMBER = @ptrCast(*const u32, "HxA").*;
pub const VERSION: u32 = 3;
pub const NAME_MAX_LENGHT: u8 = 255;

//
// HxA stores 3 types of nodes
//
pub const NodeType = enum(u8) {
    meta,       // Node only containing meta data
    geometry,   // Node containing a geometry mesh and meta data
    image,      // Node containing a 1D, 2D, 3D, or Cube image and meta data
};

//
// Pixel data is arranged in the followign configurations
//
pub const ImageType = enum(u8) {
    cube,       // 6-sided cube in the order: +x, -x, +y, -y, +z, -z
    @"1d",      // One dimensional pixel data
    @"2d",      // Two dimensional pixel data
    @"3d",      // Three dimensional pixel data
};

pub const MetaType = enum(u8) {
    u64,
    f64,
    node,
    text,
    binary,
    meta,
};

pub const Meta = struct {
    name: []u8,                 // Name of meta data value
    type: MetaType,             // Type of values - stored in the file as a u8
    len: u32,                   // How many values are stored / The length of the stored text string (excluding termination)
    values: extern union {
        u64: []u64,
        f64: []f64,
        node: []Node,           // A reference to another Node
        text: []u8,
        binary: []u8,
        meta: []Meta,
    },
};

//
// HxA stores layer data in the following types
//
pub const LayerType = enum(u8) {
    u8,
    i32,
    f32,
    f64,
};

//
// Layers are arrays of data used to store geometry and pixel data
//
pub const Layer = struct {
    name: []u8,                 // Name of the layer. List of predefined names for common usages like uv, reference, blendshapes, weights...
    components: u8,             // 2 for uv, 3 for xyz or rgb, 4 for rgba. From 1 - 255 is legal TODO: 0 check
    type: LayerType,            // stored in the file as a u8
    data: []u8,
};

pub const LayerStack = struct {
    len: u32,                   // Number of layers in a stack
    layers: []Layer,            // An array of layers
};

//
// A file consists of an array of nodes. All nodes have meta data. Geometry nodes have geometry. Image nodes have pixel data
//
pub const Node = struct {
    type: NodeType,                     // stored as u8 in file
    len: u32,                           // how many meta data key/values are stored in the node
    meta: []Meta,                       // array of key/values
    content: extern union {             // extern because zig includes extra fields for safety checking and that messes with later code (search: switch (node.type))
        geometry: Geometry,
        image: Image,

        const Geometry = struct {
            vertex_len: u32,            // Number of vertices
            vertex_stack: LayerStack,   // Stack of vertex arrays. The first layer is always the vertex positions
            edge_corner_len: u32,       // Number of corners
            corner_stack: LayerStack,   // Stack of corner arrays: The first layer is allways a reference array (see below) TODO: see below
            edge_stack: LayerStack,     // Stack of edge arrays // Version > 2
            face_len: u32,              // Number of polygons
            face_stack: LayerStack,     // Stack of per polygon data.
        };
        const Image = struct {
            type: ImageType = .cube,    // type of image
            resolution: [3]u32,         // resolytion i X, Y and Z dimention;
            image_stack: LayerStack,    // the number of values in the stack is equal to the number of pixels depending on resolution
        };
    },
};

pub const File = struct {
    //  The file begins with a file identifier. The first 4 bytes spell "HxA". See definition of MAGIC_NUMBER. Since the magic number is always the same we do not store it in this structure, even if it is always present in files.
    //	magic_number: u32
    version: u32,       // VERSION
    len: u32,           // number of nodes in the file
    nodes: []Node,      // array of nodes
};

//
// Conventions
//
// Much of HxA's use is based on conventions. HxA lets users store arbitrary data in its structure that can be parsed but who's semantic meaning does not need to be understood.
// A few conventions are hard, and some are soft.
//  Hard conventions HAVE to be followed by users in order to produce a valid file. Hard conventions simplify parsing because the parser can make some assumtions.
//  Soft conventions are basically recommendations of how to store sommon data.
pub const Conventions = struct {
    Hard: Hard = Hard {},
    Soft: Soft = Soft {},

    const Hard = struct {
        base_vertex_layer_name: []const u8 = "vertex",
        base_vertex_layer_id: u32 = 0,
        base_vertex_layer_components: u32 = 3,
        base_corner_layer_name: []const u8 = "reference",
        base_corner_layer_id: u32 = 0,
        base_corner_layer_components: u32 = 1,
        base_corner_layer_type: type = i32,
        edge_neighbour_layer_name: []const u8 = "neighbour",
        edge_neighbour_layer_type: type = i32,
    };

    const Soft = struct {
        Geometry: Geometry = Geometry {},
        Image: Image = Image {},
        Tags: Tags = Tags {},

        const Geometry = struct {
            sequence0: []const u8 = "sequence",
            uv0: []const u8 = "uv",
            normals: []const u8 = "normal",
            binormal: []const u8 = "binormal",
            tangent: []const u8 = "tangent",
            color: []const u8 = "color",
            creases: []const u8 = "creases",
            selection: []const u8 = "select",
            skin_weight: []const u8 = "skin_weight",
            skin_reference: []const u8 = "skin_reference",
            blendshape: []const u8 = "blendshape",
            add_blendshape: []const u8 = "addblendshape",
            material_id: []const u8 = "material",
            group_id: []const u8 = "group",
        };

        const Image = struct {
            albedo: []const u8 = "albedo",
            light: []const u8 = "light",
            displacement: []const u8 = "displacement",
            distortion: []const u8 = "distortion",
            ambient_occlusion: []const u8 = "ambient_occlusion",
        };

        const Tags = struct {
            name: []const u8 = "name",
            transform: []const u8 = "transform",
        };
    };
};
