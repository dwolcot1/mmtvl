import Foundation

/// One component that ships inside MMTVL.app (MR step 3, D34), shown on Settings → Licenses.
/// Full notices and license texts are in the bundled `THIRD_PARTY_NOTICES.md`.
nonisolated struct ThirdPartyComponent: Identifiable, Hashable, Sendable {
    /// Stable id, e.g. "mpv", "ffmpeg", "grdb"; used in SettingsPage.license(id:) and row ids.
    var id: String
    /// Display name, e.g. "FFmpeg".
    var name: String
    /// The shipped version, e.g. "8.1.2".
    var version: String
    /// SPDX-style expression, e.g. "LGPL-3.0-or-later".
    var license: String
    /// One line, e.g. "Copyright © 2000–2026 the FFmpeg developers".
    var copyright: String
    /// https URL of the source / license (shown as a QR code).
    var url: String
    /// Embedded framework names without ".framework" that belong to this component; [] for static code.
    var frameworks: [String]
}

/// Every component MMTVL ships: MMTVL itself, GRDB, Sparkle, and what MPVKit 1.0.0 (the LGPL product) bundles.
///
/// Versions and licenses were read on 2026-11-16 from MPVKit's build script at tag 1.0.0, each
/// `mpvkit/<lib>-build` repo's build script at the release MPVKit names, and the upstream project's
/// license files at that version (see THIRD_PARTY_NOTICES.md); Sparkle's on 2026-11-23 from its `LICENSE`
/// at tag 2.10.1. All of MPVKit's libraries are static archives linked into MMTVL's executable; their
/// `.framework` folders Xcode embeds in `Contents/Frameworks` are empty placeholders, which `frameworks`
/// maps back to their component. `Sparkle.framework` is the one real dynamic framework there (M15).
nonisolated enum ThirdPartyLicenses {
    /// Bundled notices file (Contents/Resources/THIRD_PARTY_NOTICES.md).
    static let noticesResource = "THIRD_PARTY_NOTICES"
    static let noticesExtension = "md"

    /// MMTVL itself (MIT), listed first on the Licenses page.
    static let mmtvl = ThirdPartyComponent(
        id: "mmtvl",
        name: "MMTVL",
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        license: "MIT",
        copyright: "Copyright © 2026 Derek Wolcott",
        url: "https://github.com/dwolcot1/mmtvl",
        frameworks: []
    )

    /// MMTVL first, then the others sorted by name (case-insensitive).
    static let all: [ThirdPartyComponent] = [mmtvl] + others.sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }

    static func component(id: String) -> ThirdPartyComponent? {
        all.first { $0.id == id }
    }

    private static let others: [ThirdPartyComponent] = [
        ThirdPartyComponent(
            id: "grdb", name: "GRDB", version: "7.11.1", license: "MIT",
            copyright: "Copyright © 2015–2025 Gwendal Roué",
            url: "https://github.com/groue/GRDB.swift",
            frameworks: []
        ),
        // A dynamic framework (with its Autoupdate, Updater.app and XPC helpers). Its LICENSE also carries
        // bsdiff 4.3 (BSD-2-Clause), sais-lite (MIT), orlp/ed25519 (Zlib) and SUSignatureVerifier.m (BSD-2-Clause).
        ThirdPartyComponent(
            id: "sparkle", name: "Sparkle", version: "2.10.1", license: "MIT",
            copyright: "Copyright © 2006–2017 Andy Matuschak and others",
            url: "https://github.com/sparkle-project/Sparkle",
            frameworks: ["Sparkle"]
        ),
        // MPVKit's README: "MPVKit source alone is licensed under the LGPL v3.0" (no "or later"). Its
        // LICENSE file carries no copyright line, hence the generic holder.
        ThirdPartyComponent(
            id: "mpvkit", name: "MPVKit", version: "1.0.0", license: "LGPL-3.0-only",
            copyright: "Copyright © the MPVKit contributors",
            url: "https://github.com/mpvkit/MPVKit/tree/1.0.0",
            frameworks: []
        ),
        // Built with -Dgpl=false (the binary's own configuration string says so).
        ThirdPartyComponent(
            id: "mpv", name: "mpv", version: "0.41.0", license: "LGPL-2.1-or-later",
            copyright: "Copyright © 2000–2025 mpv/MPlayer/mplayer2 projects",
            url: "https://github.com/mpv-player/mpv/tree/v0.41.0",
            frameworks: ["Libmpv"]
        ),
        // Configured with --enable-version3 and without --enable-gpl: "libavcodec license: LGPL version 3 or later".
        ThirdPartyComponent(
            id: "ffmpeg", name: "FFmpeg", version: "8.1.2", license: "LGPL-3.0-or-later",
            copyright: "Copyright © 2000–2026 the FFmpeg developers",
            url: "https://github.com/FFmpeg/FFmpeg/tree/n8.1.2",
            frameworks: ["Libavcodec", "Libavdevice", "Libavfilter", "Libavformat", "Libavutil",
                         "Libswresample", "Libswscale"]
        ),
        ThirdPartyComponent(
            id: "openssl", name: "OpenSSL", version: "3.3.5", license: "Apache-2.0",
            copyright: "Copyright © 1998–2025 The OpenSSL Project Authors",
            url: "https://github.com/openssl/openssl/tree/openssl-3.3.5",
            frameworks: ["Libcrypto", "Libssl"]
        ),
        // Includes libtasn1 (LGPL-2.1-or-later) and libunistring (LGPL-3.0-or-later OR GPL-2.0-or-later),
        // built in with --with-included-libtasn1 --with-included-unistring.
        ThirdPartyComponent(
            id: "gnutls", name: "GnuTLS", version: "3.8.11", license: "LGPL-2.1-or-later",
            copyright: "Copyright © Free Software Foundation, Inc., Red Hat, Inc. and others",
            url: "https://github.com/gnutls/gnutls/tree/3.8.11",
            frameworks: ["gnutls"]
        ),
        // mpvkit/gnutls-build release 3.8.11 builds Nettle tag nettle_3.10_release_20240616.
        ThirdPartyComponent(
            id: "nettle", name: "Nettle", version: "3.10", license: "LGPL-3.0-or-later OR GPL-2.0-or-later",
            copyright: "Copyright © Niels Möller and others",
            url: "https://git.lysator.liu.se/nettle/nettle/-/tree/nettle_3.10_release_20240616",
            frameworks: ["nettle", "hogweed"]
        ),
        // mpvkit/gnutls-build release 3.8.11 builds GMP v6.2.1 from the alisw/GMP mirror on GitHub.
        ThirdPartyComponent(
            id: "gmp", name: "GMP", version: "6.2.1", license: "LGPL-3.0-or-later OR GPL-2.0-or-later",
            copyright: "Copyright © 1991–2020 Free Software Foundation, Inc.",
            url: "https://gmplib.org/",
            frameworks: ["gmp"]
        ),
        ThirdPartyComponent(
            id: "libass", name: "libass", version: "0.17.5", license: "ISC",
            copyright: "Copyright © 2006–2016 libass contributors",
            url: "https://github.com/libass/libass/tree/0.17.5",
            frameworks: ["Libass"]
        ),
        // mpvkit/libass-build release 0.17.5 builds tag libunibreak_6_1.
        ThirdPartyComponent(
            id: "libunibreak", name: "libunibreak", version: "6.1", license: "Zlib",
            copyright: "Copyright © Wu Yongwei, Tom Hacohen, Petr Filipsky, Andreas Röver",
            url: "https://github.com/adah1972/libunibreak/tree/libunibreak_6_1",
            frameworks: ["Libunibreak"]
        ),
        // Dual FTL / GPL-2.0-or-later; MMTVL uses it under the FTL. Year per the FTL's credit text
        // (2.14.3 was tagged 2026-03-22). mpvkit/libass-build release 0.17.5 builds tag VER-2-14-3.
        ThirdPartyComponent(
            id: "freetype", name: "FreeType", version: "2.14.3", license: "FTL",
            copyright: "Portions of this software are copyright © 2026 The FreeType Project",
            url: "https://freetype.org/",
            frameworks: ["Libfreetype"]
        ),
        ThirdPartyComponent(
            id: "fribidi", name: "FriBidi", version: "1.0.16", license: "LGPL-2.1-or-later",
            copyright: "Copyright © 1999–2004 Dov Grobgeld, Behdad Esfahbod, Sharif FarsiWeb, Inc.",
            url: "https://github.com/fribidi/fribidi/tree/v1.0.16",
            frameworks: ["Libfribidi"]
        ),
        // HarfBuzz's "Old MIT" text matches SPDX's MIT-Modern-Variant template.
        ThirdPartyComponent(
            id: "harfbuzz", name: "HarfBuzz", version: "14.2.0", license: "MIT-Modern-Variant",
            copyright: "Copyright © 2010–2022 Google, Inc., Behdad Esfahbod, Red Hat, Inc. and others",
            url: "https://github.com/harfbuzz/harfbuzz/tree/14.2.0",
            frameworks: ["Libharfbuzz"]
        ),
        // mpvkit/lcms2-build release 2.17.0 builds tag lcms2.17.
        ThirdPartyComponent(
            id: "lcms2", name: "Little CMS", version: "2.17", license: "MIT",
            copyright: "Copyright © 2023 Marti Maria Saguer",
            url: "https://github.com/mm2/Little-CMS/tree/lcms2.17",
            frameworks: ["lcms2"]
        ),
        // Its LICENSE file and headers carry no copyright line, hence the generic holder.
        ThirdPartyComponent(
            id: "libplacebo", name: "libplacebo", version: "7.360.1", license: "LGPL-2.1-or-later",
            copyright: "Copyright © the libplacebo contributors",
            url: "https://github.com/haasn/libplacebo/tree/v7.360.1",
            frameworks: ["Libplacebo"]
        ),
        ThirdPartyComponent(
            id: "dav1d", name: "dav1d", version: "1.5.3", license: "BSD-2-Clause",
            copyright: "Copyright © 2018–2025, VideoLAN and dav1d authors",
            url: "https://github.com/videolan/dav1d/tree/1.5.3",
            frameworks: ["Libdav1d"]
        ),
        // Rust; links the Rust standard library and a few crates (MIT, MIT OR Apache-2.0, Zlib OR Apache-2.0 OR MIT).
        ThirdPartyComponent(
            id: "libdovi", name: "libdovi", version: "3.3.2", license: "MIT",
            copyright: "Copyright © 2025 quietvoid",
            url: "https://github.com/quietvoid/dovi_tool/tree/libdovi-3.3.2/dolby_vision",
            frameworks: ["Libdovi"]
        ),
        // Libshaderc_combined also contains glslang (BSD-3-Clause and others) and SPIRV-Tools (Apache-2.0).
        ThirdPartyComponent(
            id: "shaderc", name: "shaderc", version: "2025.5", license: "Apache-2.0",
            copyright: "Copyright © 2015 The Shaderc Authors",
            url: "https://github.com/google/shaderc/tree/v2025.5",
            frameworks: ["Libshaderc_combined"]
        ),
        ThirdPartyComponent(
            id: "uchardet", name: "uchardet", version: "0.0.8",
            license: "MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later",
            copyright: "Portions copyright © 2001 Netscape Communications Corporation",
            url: "https://gitlab.freedesktop.org/uchardet/uchardet/-/tree/v0.0.8",
            frameworks: ["Libuchardet"]
        ),
        ThirdPartyComponent(
            id: "libbluray", name: "libbluray", version: "1.4.0", license: "LGPL-2.1-or-later",
            copyright: "Copyright © 2009–2019 Obliter0n, John Stebbins, Petri Hintukainen and others",
            url: "https://code.videolan.org/videolan/libbluray/-/tree/1.4.0",
            frameworks: ["Libbluray"]
        ),
        // The v2.1 rolling branch; the binary reports "LuaJIT 2.1.1784580905" = commit 2460b3ff93a1 (2026-07-20).
        ThirdPartyComponent(
            id: "luajit", name: "LuaJIT", version: "2.1.1784580905", license: "MIT",
            copyright: "Copyright © 2005–2026 Mike Pall",
            url: "https://luajit.org/",
            frameworks: ["Libluajit"]
        ),
        // mpvkit/libuavs3d-build builds uavs3d's master branch (no tag); master's last commit is 0e20d2c
        // (2025-12-13), before that release was built (2026-07-25). The exact commit is inferred, not recorded.
        ThirdPartyComponent(
            id: "uavs3d", name: "uavs3d", version: "1.2 (0e20d2c)", license: "BSD-3-Clause",
            copyright: "Copyright © 2018–2022 Peking University Shenzhen Graduate School, Peng Cheng Laboratory, "
                + "Guangdong Bohua UHD Innovation Corporation",
            url: "https://github.com/uavs3/uavs3d",
            frameworks: ["Libuavs3d"]
        ),
        // Not in Contents/Frameworks: MPVKit links MoltenVK as a plain static library (libMoltenVK.a). It also
        // contains SPIRV-Cross (Apache-2.0) and cereal (BSD-3-Clause).
        ThirdPartyComponent(
            id: "moltenvk", name: "MoltenVK", version: "1.4.2", license: "Apache-2.0",
            copyright: "Copyright © 2015–2026 The Brenwill Workshop Ltd.",
            url: "https://github.com/KhronosGroup/MoltenVK/tree/v1.4.2",
            frameworks: []
        ),
    ]
}
