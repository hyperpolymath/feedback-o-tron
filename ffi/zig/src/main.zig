// feedback-o-tron FFI Implementation
//
// This module implements the C-compatible FFI declared in src/abi/Foreign.idr
// All types and layouts must match the Idris2 ABI definitions.
//
// SPDX-License-Identifier: PMPL-1.0-or-later

const std = @import("std");

// Version information (keep in sync with project)
const VERSION = "1.0.0";
const BUILD_INFO = "feedback-o-tron built with Zig " ++ @import("builtin").zig_version_string;

/// Thread-local error storage
threadlocal var last_error: ?[]const u8 = null;

/// Set the last error message
fn setError(msg: []const u8) void {
    last_error = msg;
}

/// Clear the last error
fn clearError() void {
    last_error = null;
}

//==============================================================================
// Core Types (must match src/abi/Types.idr)
//==============================================================================

/// Result codes (must match Idris2 Result type)
pub const Result = enum(c_int) {
    ok = 0,
    @"error" = 1,
    invalid_param = 2,
    out_of_memory = 3,
    null_pointer = 4,
};

/// Library handle (opaque to prevent direct access)
pub const Handle = opaque {
    // Internal state hidden from C
    allocator: std.mem.Allocator,
    initialized: bool,
    // Add your fields here
};

//==============================================================================
// Library Lifecycle
//==============================================================================

/// Initialize the library
/// Returns a handle, or null on failure
export fn feedback_o_tron_init() ?*Handle {
    const allocator = std.heap.c_allocator;

    const handle = allocator.create(Handle) catch {
        setError("Failed to allocate handle");
        return null;
    };

    // Initialize handle
    handle.* = .{
        .allocator = allocator,
        .initialized = true,
    };

    clearError();
    return handle;
}

/// Free the library handle
export fn feedback_o_tron_free(handle: ?*Handle) void {
    const h = handle orelse return;
    const allocator = h.allocator;

    // Clean up resources
    h.initialized = false;

    allocator.destroy(h);
    clearError();
}

//==============================================================================
// Core Operations
//==============================================================================

/// Process data (example operation)
export fn feedback_o_tron_process(handle: ?*Handle, input: u32) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    // Example processing logic
    _ = input;

    clearError();
    return .ok;
}

//==============================================================================
// String Operations
//==============================================================================

/// Get a string result (example)
/// Caller must free the returned string
export fn feedback_o_tron_get_string(handle: ?*Handle) ?[*:0]const u8 {
    const h = handle orelse {
        setError("Null handle");
        return null;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return null;
    }

    // Example: allocate and return a string
    const result = h.allocator.dupeZ(u8, "Example result") catch {
        setError("Failed to allocate string");
        return null;
    };

    clearError();
    return result.ptr;
}

/// Free a string allocated by the library
export fn feedback_o_tron_free_string(str: ?[*:0]const u8) void {
    const s = str orelse return;
    const allocator = std.heap.c_allocator;

    const slice = std.mem.span(s);
    allocator.free(slice);
}

//==============================================================================
// Array/Buffer Operations
//==============================================================================

/// Process an array of data
export fn feedback_o_tron_process_array(
    handle: ?*Handle,
    buffer: ?[*]const u8,
    len: u32,
) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    const buf = buffer orelse {
        setError("Null buffer");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    // Access the buffer
    const data = buf[0..len];
    _ = data;

    // Process data here

    clearError();
    return .ok;
}

//==============================================================================
// Error Handling
//==============================================================================

/// Get the last error message
/// Returns null if no error
export fn feedback_o_tron_last_error() ?[*:0]const u8 {
    const err = last_error orelse return null;

    // Return C string (static storage, no need to free)
    const allocator = std.heap.c_allocator;
    const c_str = allocator.dupeZ(u8, err) catch return null;
    return c_str.ptr;
}

//==============================================================================
// Version Information
//==============================================================================

/// Get the library version
export fn feedback_o_tron_version() [*:0]const u8 {
    return VERSION.ptr;
}

/// Get build information
export fn feedback_o_tron_build_info() [*:0]const u8 {
    return BUILD_INFO.ptr;
}

//==============================================================================
// Callback Support
//==============================================================================

/// Callback function type (C ABI)
pub const Callback = *const fn (u64, u32) callconv(.C) u32;

/// Register a callback
export fn feedback_o_tron_register_callback(
    handle: ?*Handle,
    callback: ?Callback,
) Result {
    const h = handle orelse {
        setError("Null handle");
        return .null_pointer;
    };

    const cb = callback orelse {
        setError("Null callback");
        return .null_pointer;
    };

    if (!h.initialized) {
        setError("Handle not initialized");
        return .@"error";
    }

    // Store callback for later use
    _ = cb;

    clearError();
    return .ok;
}

//==============================================================================
// Utility Functions
//==============================================================================

/// Check if handle is initialized
export fn feedback_o_tron_is_initialized(handle: ?*Handle) u32 {
    const h = handle orelse return 0;
    return if (h.initialized) 1 else 0;
}

//==============================================================================
// Feedback-Specific Operations
//==============================================================================

/// Compute SHA-256 hash for deduplication (matches Elixir Deduplicator)
/// Returns first 16 hex chars of SHA-256(input), or null on error.
/// Caller must free the returned string via feedback_o_tron_free_string.
export fn feedback_o_tron_compute_hash(
    input: ?[*]const u8,
    len: u32,
) ?[*:0]const u8 {
    const buf = input orelse {
        setError("Null input buffer");
        return null;
    };

    const data = buf[0..len];
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});

    // Encode first 8 bytes as 16 hex chars
    const allocator = std.heap.c_allocator;
    const hex = allocator.alloc(u8, 17) catch {
        setError("Failed to allocate hash string");
        return null;
    };

    const hex_chars = "0123456789abcdef";
    for (0..8) |i| {
        hex[i * 2] = hex_chars[digest[i] >> 4];
        hex[i * 2 + 1] = hex_chars[digest[i] & 0x0f];
    }
    hex[16] = 0; // null terminator

    clearError();
    return @ptrCast(hex.ptr);
}

/// Generate a cryptographically random submission ID (11 chars, URL-safe base64).
/// Caller must free the returned string via feedback_o_tron_free_string.
export fn feedback_o_tron_generate_id() ?[*:0]const u8 {
    var bytes: [8]u8 = undefined;
    std.crypto.random.bytes(&bytes);

    const allocator = std.heap.c_allocator;
    const encoder = std.base64.url_safe_no_pad;
    const encoded_len = encoder.calcSize(8);
    const result = allocator.alloc(u8, encoded_len + 1) catch {
        setError("Failed to allocate ID string");
        return null;
    };

    _ = encoder.encode(result[0..encoded_len], &bytes);
    result[encoded_len] = 0;

    clearError();
    return @ptrCast(result.ptr);
}

/// Validate that a URL uses HTTPS (security requirement).
/// Returns 1 if valid HTTPS, 0 otherwise.
export fn feedback_o_tron_validate_https(
    url: ?[*]const u8,
    len: u32,
) u32 {
    const buf = url orelse return 0;
    const data = buf[0..len];

    if (data.len >= 8 and std.mem.eql(u8, data[0..8], "https://")) {
        return 1;
    }
    return 0;
}

//==============================================================================
// Tests
//==============================================================================

test "lifecycle" {
    const handle = feedback_o_tron_init() orelse return error.InitFailed;
    defer feedback_o_tron_free(handle);

    try std.testing.expect(feedback_o_tron_is_initialized(handle) == 1);
}

test "error handling" {
    const result = feedback_o_tron_process(null, 0);
    try std.testing.expectEqual(Result.null_pointer, result);

    const err = feedback_o_tron_last_error();
    try std.testing.expect(err != null);
}

test "version" {
    const ver = feedback_o_tron_version();
    const ver_str = std.mem.span(ver);
    try std.testing.expectEqualStrings(VERSION, ver_str);
}
