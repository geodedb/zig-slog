// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Internationalization catalog for message translation.
//!
//! Supports loading translations from JSON and looking up messages by ID.

const std = @import("std");
const json = @import("json");

/// Translator function interface.
pub const Translator = struct {
    ctx: ?*anyopaque,
    translateFn: *const fn (ctx: ?*anyopaque, locale: []const u8, msg_id: []const u8) ?[]const u8,

    pub fn translate(self: Translator, locale: []const u8, msg_id: []const u8) ?[]const u8 {
        return self.translateFn(self.ctx, locale, msg_id);
    }
};

/// A catalog of message translations.
pub const Catalog = struct {
    allocator: std.mem.Allocator,
    /// Map of locale -> (msg_id -> translation)
    translations: std.StringHashMap(std.StringHashMap([]const u8)),
    /// Owned strings for cleanup
    owned_strings: std.ArrayListUnmanaged([]u8),

    pub fn init(allocator: std.mem.Allocator) Catalog {
        return .{
            .allocator = allocator,
            .translations = std.StringHashMap(std.StringHashMap([]const u8)).init(allocator),
            .owned_strings = .empty,
        };
    }

    pub fn deinit(self: *Catalog) void {
        var locale_iter = self.translations.valueIterator();
        while (locale_iter.next()) |msg_map| {
            msg_map.deinit();
        }
        self.translations.deinit();

        for (self.owned_strings.items) |s| {
            self.allocator.free(s);
        }
        self.owned_strings.deinit(self.allocator);
    }

    /// Load translations from JSON.
    /// JSON format: { "locale": { "msg_id": "translation", ... }, ... }
    pub fn fromJson(allocator: std.mem.Allocator, json_bytes: []const u8) !Catalog {
        var catalog = Catalog.init(allocator);
        errdefer catalog.deinit();

        var parse_err = json.ParseError.init();
        var doc = json.parse(allocator, json_bytes, .{}, &parse_err) catch return error.InvalidFormat;
        defer doc.deinit();

        const root = doc.root;
        if (root != .obj) return error.InvalidFormat;

        for (root.obj) |locale_entry| {
            const locale = locale_entry.k;
            const msg_obj = locale_entry.v;

            if (msg_obj != .obj) continue;

            // Copy locale string
            const locale_copy = try allocator.dupe(u8, locale);
            try catalog.owned_strings.append(allocator, locale_copy);

            var msg_map = std.StringHashMap([]const u8).init(allocator);

            for (msg_obj.obj) |msg_entry| {
                const msg_id = msg_entry.k;
                const translation_val = msg_entry.v;

                if (translation_val != .str) continue;
                const translation = translation_val.str;

                // Copy strings
                const msg_id_copy = try allocator.dupe(u8, msg_id);
                try catalog.owned_strings.append(allocator, msg_id_copy);
                const trans_copy = try allocator.dupe(u8, translation);
                try catalog.owned_strings.append(allocator, trans_copy);

                try msg_map.put(msg_id_copy, trans_copy);
            }

            try catalog.translations.put(locale_copy, msg_map);
        }

        return catalog;
    }

    /// Get a translation for a message ID in the given locale.
    pub fn get(self: *const Catalog, locale: []const u8, msg_id: []const u8) ?[]const u8 {
        if (self.translations.get(locale)) |msg_map| {
            return msg_map.get(msg_id);
        }
        return null;
    }

    /// Get a translator interface for this catalog.
    pub fn translator(self: *const Catalog) Translator {
        return .{
            .ctx = @ptrCast(@constCast(self)),
            .translateFn = catalogTranslate,
        };
    }
};

fn catalogTranslate(ctx: ?*anyopaque, locale: []const u8, msg_id: []const u8) ?[]const u8 {
    if (ctx) |c| {
        const catalog: *const Catalog = @ptrCast(@alignCast(c));
        return catalog.get(locale, msg_id);
    }
    return null;
}

/// A null translator that returns null for all lookups.
pub fn nullTranslator() Translator {
    return .{
        .ctx = null,
        .translateFn = nullTranslateFn,
    };
}

fn nullTranslateFn(_: ?*anyopaque, _: []const u8, _: []const u8) ?[]const u8 {
    return null;
}

test "Catalog.fromJson" {
    const json_data =
        \\{
        \\  "es": {
        \\    "app.started": "aplicación iniciada",
        \\    "app.stopped": "aplicación detenida"
        \\  },
        \\  "de": {
        \\    "app.started": "Anwendung gestartet"
        \\  }
        \\}
    ;

    var catalog = try Catalog.fromJson(std.testing.allocator, json_data);
    defer catalog.deinit();

    try std.testing.expectEqualStrings("aplicación iniciada", catalog.get("es", "app.started").?);
    try std.testing.expectEqualStrings("Anwendung gestartet", catalog.get("de", "app.started").?);
    try std.testing.expect(catalog.get("fr", "app.started") == null);
}

test "Catalog.translator" {
    const json_data =
        \\{ "es": { "hello": "hola" } }
    ;

    var catalog = try Catalog.fromJson(std.testing.allocator, json_data);
    defer catalog.deinit();

    const t = catalog.translator();
    try std.testing.expectEqualStrings("hola", t.translate("es", "hello").?);
    try std.testing.expect(t.translate("en", "hello") == null);
}
