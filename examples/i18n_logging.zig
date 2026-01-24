// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2024-2025 CodePros

//! Internationalization (i18n) logging example.
//!
//! Demonstrates message translation using the i18n catalog.
//! Message IDs are used for lookup while translated messages
//! appear in the log output.

const std = @import("std");
const slog = @import("slog");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Define translations as JSON
    // In production, load from a file or embedded resource
    const translations_json =
        \\{
        \\  "es": {
        \\    "app.started": "Aplicacion iniciada",
        \\    "app.stopped": "Aplicacion detenida",
        \\    "user.login": "Usuario ha iniciado sesion",
        \\    "user.logout": "Usuario ha cerrado sesion",
        \\    "error.not_found": "Recurso no encontrado"
        \\  },
        \\  "de": {
        \\    "app.started": "Anwendung gestartet",
        \\    "app.stopped": "Anwendung gestoppt",
        \\    "user.login": "Benutzer angemeldet",
        \\    "user.logout": "Benutzer abgemeldet",
        \\    "error.not_found": "Ressource nicht gefunden"
        \\  },
        \\  "fr": {
        \\    "app.started": "Application demarree",
        \\    "app.stopped": "Application arretee",
        \\    "user.login": "Utilisateur connecte",
        \\    "user.logout": "Utilisateur deconnecte",
        \\    "error.not_found": "Ressource non trouvee"
        \\  }
        \\}
    ;

    // Load translation catalog
    var catalog = try slog.i18n.Catalog.fromJson(allocator, translations_json);
    defer catalog.deinit();

    // Create base handler
    var text_ctx = slog.text.Context.init(
        std.io.getStdErr().writer().any(),
        .info,
        slog.Clock.system(),
    );
    const handler = slog.text.init(&text_ctx);
    const base_logger = slog.Logger.init(handler, .info, slog.Clock.system())
        .named("i18n-example");

    std.debug.print("=== i18n Logging Example ===\n\n", .{});

    // Log in different locales
    const locales = [_][]const u8{ "en", "es", "de", "fr" };

    for (locales) |locale| {
        std.debug.print("--- Locale: {s} ---\n", .{locale});

        // Create logger with translator for this locale
        const logger = base_logger.withTranslator(locale, catalog.translator());

        // These message IDs will be translated
        try logger.info("app.started", &.{
            slog.Attr.string("version", "1.0.0"),
        });

        try logger.info("user.login", &.{
            slog.Attr.string("username", "alice"),
            slog.Attr.string("ip", "192.168.1.50"),
        });

        try logger.warn("error.not_found", &.{
            slog.Attr.string("resource", "/api/users/999"),
        });

        std.debug.print("\n", .{});
    }

    std.debug.print("Note: 'en' locale shows message IDs (no translation defined)\n", .{});
}
