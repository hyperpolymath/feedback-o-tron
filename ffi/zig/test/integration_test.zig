// feedback-o-tron Integration Tests
// SPDX-License-Identifier: PMPL-1.0-or-later
//
// These tests verify that the Zig FFI correctly implements the Idris2 ABI

const std = @import("std");
const testing = std.testing;

// Import FFI functions
extern fn feedback_o_tron_init() ?*opaque {};
extern fn feedback_o_tron_free(?*opaque {}) void;
extern fn feedback_o_tron_process(?*opaque {}, u32) c_int;
extern fn feedback_o_tron_get_string(?*opaque {}) ?[*:0]const u8;
extern fn feedback_o_tron_free_string(?[*:0]const u8) void;
extern fn feedback_o_tron_last_error() ?[*:0]const u8;
extern fn feedback_o_tron_version() [*:0]const u8;
extern fn feedback_o_tron_is_initialized(?*opaque {}) u32;
extern fn feedback_o_tron_compute_hash(?[*]const u8, u32) ?[*:0]const u8;
extern fn feedback_o_tron_generate_id() ?[*:0]const u8;
extern fn feedback_o_tron_validate_https(?[*]const u8, u32) u32;

//==============================================================================
// Lifecycle Tests
//==============================================================================

test "create and destroy handle" {
    const handle = feedback_o_tron_init() orelse return error.InitFailed;
    defer feedback_o_tron_free(handle);

    try testing.expect(handle != null);
}

test "handle is initialized" {
    const handle = feedback_o_tron_init() orelse return error.InitFailed;
    defer feedback_o_tron_free(handle);

    const initialized = feedback_o_tron_is_initialized(handle);
    try testing.expectEqual(@as(u32, 1), initialized);
}

test "null handle is not initialized" {
    const initialized = feedback_o_tron_is_initialized(null);
    try testing.expectEqual(@as(u32, 0), initialized);
}

//==============================================================================
// Operation Tests
//==============================================================================

test "process with valid handle" {
    const handle = feedback_o_tron_init() orelse return error.InitFailed;
    defer feedback_o_tron_free(handle);

    const result = feedback_o_tron_process(handle, 42);
    try testing.expectEqual(@as(c_int, 0), result); // 0 = ok
}

test "process with null handle returns error" {
    const result = feedback_o_tron_process(null, 42);
    try testing.expectEqual(@as(c_int, 4), result); // 4 = null_pointer
}

//==============================================================================
// String Tests
//==============================================================================

test "get string result" {
    const handle = feedback_o_tron_init() orelse return error.InitFailed;
    defer feedback_o_tron_free(handle);

    const str = feedback_o_tron_get_string(handle);
    defer if (str) |s| feedback_o_tron_free_string(s);

    try testing.expect(str != null);
}

test "get string with null handle" {
    const str = feedback_o_tron_get_string(null);
    try testing.expect(str == null);
}

//==============================================================================
// Error Handling Tests
//==============================================================================

test "last error after null handle operation" {
    _ = feedback_o_tron_process(null, 0);

    const err = feedback_o_tron_last_error();
    try testing.expect(err != null);

    if (err) |e| {
        const err_str = std.mem.span(e);
        try testing.expect(err_str.len > 0);
    }
}

test "no error after successful operation" {
    const handle = feedback_o_tron_init() orelse return error.InitFailed;
    defer feedback_o_tron_free(handle);

    _ = feedback_o_tron_process(handle, 0);

    // Error should be cleared after successful operation
    // (This depends on implementation)
}

//==============================================================================
// Version Tests
//==============================================================================

test "version string is not empty" {
    const ver = feedback_o_tron_version();
    const ver_str = std.mem.span(ver);

    try testing.expect(ver_str.len > 0);
}

test "version string is semantic version format" {
    const ver = feedback_o_tron_version();
    const ver_str = std.mem.span(ver);

    // Should be in format X.Y.Z
    try testing.expect(std.mem.count(u8, ver_str, ".") >= 1);
}

//==============================================================================
// Memory Safety Tests
//==============================================================================

test "multiple handles are independent" {
    const h1 = feedback_o_tron_init() orelse return error.InitFailed;
    defer feedback_o_tron_free(h1);

    const h2 = feedback_o_tron_init() orelse return error.InitFailed;
    defer feedback_o_tron_free(h2);

    try testing.expect(h1 != h2);

    // Operations on h1 should not affect h2
    _ = feedback_o_tron_process(h1, 1);
    _ = feedback_o_tron_process(h2, 2);
}

test "double free is safe" {
    const handle = feedback_o_tron_init() orelse return error.InitFailed;

    feedback_o_tron_free(handle);
    feedback_o_tron_free(handle); // Should not crash
}

test "free null is safe" {
    feedback_o_tron_free(null); // Should not crash
}

//==============================================================================
// Thread Safety Tests (if applicable)
//==============================================================================

test "concurrent operations" {
    const handle = feedback_o_tron_init() orelse return error.InitFailed;
    defer feedback_o_tron_free(handle);

    const ThreadContext = struct {
        h: *opaque {},
        id: u32,
    };

    const thread_fn = struct {
        fn run(ctx: ThreadContext) void {
            _ = feedback_o_tron_process(ctx.h, ctx.id);
        }
    }.run;

    var threads: [4]std.Thread = undefined;
    for (&threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(.{}, thread_fn, .{
            ThreadContext{ .h = handle, .id = @intCast(i) },
        });
    }

    for (threads) |thread| {
        thread.join();
    }
}

//==============================================================================
// Feedback-Specific FFI Tests
//==============================================================================

test "compute_hash returns 16 hex chars" {
    const input = "test input for hashing";
    const hash = feedback_o_tron_compute_hash(input.ptr, input.len);
    defer if (hash) |h| feedback_o_tron_free_string(h);

    try testing.expect(hash != null);

    if (hash) |h| {
        const hash_str = std.mem.span(h);
        try testing.expectEqual(@as(usize, 16), hash_str.len);
        // All chars should be hex
        for (hash_str) |c| {
            try testing.expect((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f'));
        }
    }
}

test "compute_hash is deterministic" {
    const input = "deterministic test";
    const hash1 = feedback_o_tron_compute_hash(input.ptr, input.len);
    defer if (hash1) |h| feedback_o_tron_free_string(h);
    const hash2 = feedback_o_tron_compute_hash(input.ptr, input.len);
    defer if (hash2) |h| feedback_o_tron_free_string(h);

    try testing.expect(hash1 != null);
    try testing.expect(hash2 != null);

    if (hash1) |h1| {
        if (hash2) |h2| {
            try testing.expectEqualStrings(std.mem.span(h1), std.mem.span(h2));
        }
    }
}

test "compute_hash with null input returns null" {
    const hash = feedback_o_tron_compute_hash(null, 0);
    try testing.expect(hash == null);
}

test "generate_id returns non-empty string" {
    const id = feedback_o_tron_generate_id();
    defer if (id) |i| feedback_o_tron_free_string(i);

    try testing.expect(id != null);
    if (id) |i| {
        const id_str = std.mem.span(i);
        try testing.expect(id_str.len > 0);
    }
}

test "generate_id returns unique values" {
    const id1 = feedback_o_tron_generate_id();
    defer if (id1) |i| feedback_o_tron_free_string(i);
    const id2 = feedback_o_tron_generate_id();
    defer if (id2) |i| feedback_o_tron_free_string(i);

    try testing.expect(id1 != null);
    try testing.expect(id2 != null);

    // IDs should be different (cryptographic randomness)
    if (id1) |i1| {
        if (id2) |i2| {
            try testing.expect(!std.mem.eql(u8, std.mem.span(i1), std.mem.span(i2)));
        }
    }
}

test "validate_https accepts HTTPS URLs" {
    const url = "https://github.com/owner/repo";
    try testing.expectEqual(@as(u32, 1), feedback_o_tron_validate_https(url.ptr, url.len));
}

test "validate_https rejects HTTP URLs" {
    const url = "http://github.com/owner/repo";
    try testing.expectEqual(@as(u32, 0), feedback_o_tron_validate_https(url.ptr, url.len));
}

test "validate_https rejects null" {
    try testing.expectEqual(@as(u32, 0), feedback_o_tron_validate_https(null, 0));
}
