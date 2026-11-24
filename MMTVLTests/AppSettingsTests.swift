import Foundation
import Testing
@testable import MMTVL

struct AppSettingsTests {
    @Test func emptyObjectDecodesToDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        var expected = AppSettings()
        expected.keyBindingsRevision = 1   // M7 L7: a file without the key predates the revision
        #expect(settings == expected)
        #expect(settings.globalInputEnabled)
        #expect(settings.controllersEnabled)
        #expect(settings.cursorAutoHide)
        #expect(!settings.launchAtLogin)
    }

    @Test func partialObjectKeepsOtherDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"launchAtLogin": true}"#.utf8))
        var expected = AppSettings()
        expected.launchAtLogin = true
        expected.keyBindingsRevision = 1
        #expect(settings == expected)
    }

    @Test func youtubeUserAgentIsOptional() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.youtubeUserAgent == nil)
        let encoded = try String(decoding: JSONEncoder().encode(settings), as: UTF8.self)
        #expect(!encoded.contains("youtubeUserAgent"))
    }

    @Test func youtubeUserAgentRoundTrips() throws {
        var settings = AppSettings()
        settings.youtubeUserAgent = "Custom/1.0"
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test func phoneRemoteDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"launchAtLogin": true}"#.utf8))
        #expect(settings.phoneRemoteEnabled)
        #expect(settings.phoneRemotePort == 8765)
        #expect(settings.phoneRemoteVolume == "auto")
        #expect(settings.volumeMode == .auto)
    }

    @Test func phoneRemoteHandEdits() throws {
        let json = #"{"phoneRemoteVolume": "bogus", "phoneRemotePort": 80, "phoneRemoteEnabled": false}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.volumeMode == .auto)
        #expect(settings.validatedPhoneRemotePort == 8765)
        #expect(!settings.phoneRemoteEnabled)

        let custom = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"phoneRemoteVolume": "app", "phoneRemotePort": 9000}"#.utf8))
        #expect(custom.volumeMode == .app)
        #expect(custom.validatedPhoneRemotePort == 9000)
    }

    // MARK: M7 L7

    @Test func keyBindingsRevisionMissingIsOne() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.keyBindingsRevision == 1)
    }

    @Test func freshSettingsHaveCurrentRevision() {
        #expect(AppSettings().keyBindingsRevision == 3)   // M7h: revision 3
        #expect(KeyBindings.currentRevision == 3)
    }

    @Test func keyBindingsRevisionRoundTrips() throws {
        var settings = AppSettings()
        settings.keyBindingsRevision = 2
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }
    @Test func channelUpMovesUpListDefaultsToTrue() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.channelUpMovesUpList)
        let flipped = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"channelUpMovesUpList": false}"#.utf8))
        #expect(!flipped.channelUpMovesUpList)
    }

    @Test func castingDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.youtubeCastEnabled)
        #expect(settings.castDeviceID == nil)
        let custom = try JSONDecoder().decode(AppSettings.self,
                                              from: Data(#"{"youtubeCastEnabled": false, "castDeviceID": "abc"}"#.utf8))
        #expect(!custom.youtubeCastEnabled)
        #expect(custom.castDeviceID == "abc")
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(custom))
        #expect(decoded == custom)
    }

    @Test func reflectorAutoStartDefaultsToTrue() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.reflectorAutoStart)
        let off = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"reflectorAutoStart": false}"#.utf8))
        #expect(!off.reflectorAutoStart)
    }

    @Test func homeLivePreviewDefaultsToTrue() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.homeLivePreview)
        let off = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"homeLivePreview": false}"#.utf8))
        #expect(!off.homeLivePreview)
    }

    /// M7c L28.
    @Test func showVersionOnHomeDefaultsToTrue() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.showVersionOnHome)
        let off = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"showVersionOnHome": false}"#.utf8))
        #expect(!off.showVersionOnHome)
    }

    /// M7c L32.
    @Test func homeStartTileDefaultsToPlex() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.homeStartTile == "plex")
        let other = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"homeStartTile": "iptv"}"#.utf8))
        #expect(other.homeStartTile == "iptv")
    }

    @Test func appVersionReadsInfoPlistKeys() {
        let version = AppVersion(info: ["CFBundleShortVersionString": "1.1.0", "CFBundleVersion": "2"])
        #expect(version.label == "Version 1.1.0 Build 2")
        #expect(AppVersion(info: [:]).label == "Version ? Build ?")
    }

    @Test func kioskLockDefaultsToTrue() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.kioskLock)
        let off = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"kioskLock": false}"#.utf8))
        #expect(!off.kioskLock)
    }

    /// M7h D43.
    @Test func siriRemoteEnabledDefaultsToTrue() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.siriRemoteEnabled)
        let off = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"siriRemoteEnabled": false}"#.utf8))
        #expect(!off.siriRemoteEnabled)
        let encoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(off))
        #expect(!encoded.siriRemoteEnabled)
    }

    /// M7h D44, L11.
    @Test func receiverKeysDefault() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.receiverBrand == .none)
        #expect(settings.receiverConnection == .serial)
        #expect(settings.receiverSerialPort == nil)
        let encoded = try String(decoding: JSONEncoder().encode(settings), as: UTF8.self)
        #expect(encoded.contains(#""receiverBrand":"none""#))
        #expect(!encoded.contains("receiverSerialPort"))
    }

    @Test func receiverKeysDecodeAndRoundTrip() throws {
        let json = #"{"receiverBrand": "pioneer", "receiverConnection": "network", "receiverSerialPort": "/dev/cu.test"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.receiverBrand == .pioneer)
        #expect(settings.receiverConnection == .network)
        #expect(settings.receiverSerialPort == "/dev/cu.test")
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        for brand in ReceiverBrand.allCases {
            let one = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"receiverBrand": "\#(brand.rawValue)"}"#.utf8))
            #expect(one.receiverBrand == brand)
        }
    }

    @Test func unknownReceiverValuesReadAsDefaults() throws {
        let json = #"{"receiverBrand": "sony", "receiverConnection": "usb", "launchAtLogin": true}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.receiverBrand == .none)
        #expect(settings.receiverConnection == .serial)
        #expect(settings.launchAtLogin)
    }

    /// M7h L17.
    @Test func receiverNetworkKeys() throws {
        let missing = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(missing.receiverHost == nil)
        #expect(missing.receiverNetworkPort == nil)
        #expect(missing.validatedReceiverNetworkPort == nil)
        let encoded = try String(decoding: JSONEncoder().encode(missing), as: UTF8.self)
        #expect(!encoded.contains("receiverHost"))
        #expect(!encoded.contains("receiverNetworkPort"))

        let json = #"{"receiverConnection": "network", "receiverHost": "192.168.1.20", "receiverNetworkPort": 60128}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.receiverHost == "192.168.1.20")
        #expect(settings.receiverNetworkPort == 60128)
        #expect(settings.validatedReceiverNetworkPort == 60128)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)) == settings)

        for bad in [0, -1, 65536, 100_000] {
            let one = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"receiverNetworkPort": \#(bad)}"#.utf8))
            #expect(one.validatedReceiverNetworkPort == nil, "\(bad)")
        }
    }

    /// QA minor 6: a hand-edited `receiverNetworkPort` of the wrong type reads as nil; the rest of the file is kept.
    @Test func receiverNetworkPortOfTheWrongTypeIsIgnored() throws {
        for value in [#""abc""#, #""60128""#, "23.5", "true", "null", "[23]"] {
            let json = #"{"receiverNetworkPort": \#(value), "launchAtLogin": true, "receiverHost": "avr.local"}"#
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            #expect(settings.receiverNetworkPort == nil, "\(value)")
            #expect(settings.launchAtLogin, "\(value)")
            #expect(settings.receiverHost == "avr.local", "\(value)")
        }
    }

    /// M7h step 10 (user decision): the volume cap, tolerant of hand edits.
    @Test func receiverMaxDBDecodes() throws {
        let missing = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(missing.receiverMaxDB == 0)
        #expect(missing.validatedReceiverMaxDB == 0)
        for (value, expected) in [("-10", -10.0), ("-12.5", -12.5), ("6", 6.0), ("-100", -100.0), ("30", 30.0)] {
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"receiverMaxDB": \#(value)}"#.utf8))
            #expect(settings.receiverMaxDB == expected, "\(value)")
            #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)) == settings)
        }
        // Out of range, another type, or not a number: the default, and the rest of the file is kept.
        for value in ["1e18", "-1e300", "31", "-101", #""-10""#, "true", "null", "[0]"] {
            let json = #"{"receiverMaxDB": \#(value), "launchAtLogin": true}"#
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            #expect(settings.receiverMaxDB == 0, "\(value)")
            #expect(settings.launchAtLogin, "\(value)")
        }
        var edited = AppSettings()
        edited.receiverMaxDB = .infinity
        #expect(edited.validatedReceiverMaxDB == 0)
        edited.receiverMaxDB = .nan
        #expect(edited.validatedReceiverMaxDB == 0)
    }

    /// M7h L18. Made-up address and MAC only.
    @Test func tvKeysDefault() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.tvBrand == .none)
        #expect(settings.tvHost == nil)
        #expect(settings.tvMAC == nil)
        let encoded = try String(decoding: JSONEncoder().encode(settings), as: UTF8.self)
        #expect(encoded.contains(#""tvBrand":"none""#))
        #expect(!encoded.contains("tvHost"))
        #expect(!encoded.contains("tvMAC"))
    }

    @Test func tvKeysDecodeAndRoundTrip() throws {
        let json = #"{"tvBrand": "panasonic", "tvHost": "192.168.1.30", "tvMAC": "02:00:5e:00:10:ab"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.tvBrand == .panasonic)
        #expect(settings.tvHost == "192.168.1.30")
        #expect(settings.tvMAC == "02:00:5e:00:10:ab")
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)) == settings)
        for brand in TVBrand.allCases {
            let one = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"tvBrand": "\#(brand.rawValue)"}"#.utf8))
            #expect(one.tvBrand == brand)
        }
    }

    /// Step 9 (reopened).
    @Test func cecTVBrandDecodesAndRoundTrips() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"tvBrand": "cec"}"#.utf8))
        #expect(settings.tvBrand == .cec)
        let encoded = try String(decoding: JSONEncoder().encode(settings), as: UTF8.self)
        #expect(encoded.contains(#""tvBrand":"cec""#))
        for unknown in [#""CEC""#, #""hdmi-cec""#, #""""#, "null"] {
            let one = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"tvBrand": \#(unknown)}"#.utf8))
            #expect(one.tvBrand == .none, "\(unknown)")
        }
    }

    @Test func unknownTVBrandAndWrongTypedMACReadAsDefaults() throws {
        let json = #"{"tvBrand": "sony", "launchAtLogin": true, "tvHost": "tv.local"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.tvBrand == .none)
        #expect(settings.launchAtLogin)
        for value in ["12", "true", "null", "[1]", #"{"a": 1}"#] {
            let one = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"tvMAC": \#(value), "tvHost": "tv.local"}"#.utf8))
            #expect(one.tvMAC == nil, "\(value)")
            #expect(one.tvHost == "tv.local", "\(value)")
        }
    }

    /// M7h step 13e: Swipes; missing or of another type reads as false, and the rest of the file is kept.
    @Test func siriRemoteSwipesDecodes() throws {
        let missing = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!missing.siriRemoteSwipes)
        #expect(!AppSettings().siriRemoteSwipes)
        let on = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"siriRemoteSwipes": true}"#.utf8))
        #expect(on.siriRemoteSwipes)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(on)) == on)
        let encoded = try String(decoding: JSONEncoder().encode(on), as: UTF8.self)
        #expect(encoded.contains(#""siriRemoteSwipes":true"#))
        for value in ["1", #""true""#, "null", "[true]"] {
            let json = #"{"siriRemoteSwipes": \#(value), "launchAtLogin": true}"#
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            #expect(!settings.siriRemoteSwipes, "\(value)")
            #expect(settings.launchAtLogin, "\(value)")
        }
    }

    /// M7m L29: Match Initials and Match Nicknames Alone; missing or of another type reads as false, and the rest of
    /// the file is kept.
    @Test func teamMatchSwitchesDecode() throws {
        let missing = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!missing.teamMatchInitials)
        #expect(!missing.teamMatchNicknames)
        #expect(missing.teamMatchOptions == .off)
        #expect(AppSettings().teamMatchOptions == .off)
        let on = try JSONDecoder().decode(AppSettings.self,
                                          from: Data(#"{"teamMatchInitials": true, "teamMatchNicknames": true}"#.utf8))
        #expect(on.teamMatchOptions == TeamMatchOptions(initials: true, nicknames: true))
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(on)) == on)
        let encoded = try String(decoding: JSONEncoder().encode(on), as: UTF8.self)
        #expect(encoded.contains(#""teamMatchInitials":true"#))
        #expect(encoded.contains(#""teamMatchNicknames":true"#))
        #expect(!encoded.contains("teamMatchOptions"))
        let one = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"teamMatchNicknames": true}"#.utf8))
        #expect(one.teamMatchOptions == TeamMatchOptions(nicknames: true))
        for value in ["1", #""true""#, "null", "[true]"] {
            let json = #"{"teamMatchInitials": \#(value), "teamMatchNicknames": \#(value), "launchAtLogin": true}"#
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            #expect(settings.teamMatchOptions == .off, "\(value)")
            #expect(settings.launchAtLogin, "\(value)")
        }
    }

    /// M7h step 13b: Show Volume; missing or of another type reads as true, and the rest of the file is kept.
    @Test func volumeToastDecodes() throws {
        let missing = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(missing.volumeToast)
        #expect(AppSettings().volumeToast)
        let off = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"volumeToast": false}"#.utf8))
        #expect(!off.volumeToast)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(off)) == off)
        let encoded = try String(decoding: JSONEncoder().encode(off), as: UTF8.self)
        #expect(encoded.contains(#""volumeToast":false"#))
        for value in ["0", "1", #""false""#, "null", "[false]", #"{"a": false}"#] {
            let json = #"{"volumeToast": \#(value), "launchAtLogin": true, "kioskLock": false}"#
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            #expect(settings.volumeToast, "\(value)")
            #expect(settings.launchAtLogin, "\(value)")
            #expect(!settings.kioskLock, "\(value)")
        }
    }

    /// Step 9b S6 / QA minor 4: a TV or receiver key of the wrong type reads as its default; the rest of the file
    /// is kept (no `.bak`).
    @Test func wrongTypedTVAndReceiverKeysKeepTheFile() throws {
        let one = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"tvHost": 12, "youtubeCastEnabled": false}"#.utf8))
        #expect(one.tvHost == nil)
        #expect(!one.youtubeCastEnabled)
        let json = #"{"tvBrand": 1, "tvHost": [1], "receiverBrand": true, "receiverConnection": 2, "receiverHost": {"a": 1}, "receiverSerialPort": 5, "youtubeCastEnabled": false, "launchAtLogin": true}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.tvBrand == .none)
        #expect(settings.tvHost == nil)
        #expect(settings.receiverBrand == .none)
        #expect(settings.receiverConnection == .serial)
        #expect(settings.receiverHost == nil)
        #expect(settings.receiverSerialPort == nil)
        #expect(!settings.youtubeCastEnabled)
        #expect(settings.launchAtLogin)
    }

    /// M7h step 9c: `receiverConnection` `cec` and `tvVolumeEnabled`; unknown or wrong-typed values read as the
    /// defaults, and the rest of the file is kept (no `.bak`).
    @Test func cecReceiverAndTVVolumeDecode() throws {
        let missing = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!missing.tvVolumeEnabled)
        #expect(!AppSettings().tvVolumeEnabled)
        #expect(missing.receiverConnection == .serial)
        let cec = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"receiverConnection": "cec", "tvVolumeEnabled": true}"#.utf8))
        #expect(cec.receiverConnection == .cec)
        #expect(cec.tvVolumeEnabled)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(cec)) == cec)
        let encoded = try String(decoding: JSONEncoder().encode(cec), as: UTF8.self)
        #expect(encoded.contains(#""receiverConnection":"cec""#))
        #expect(encoded.contains(#""tvVolumeEnabled":true"#))
        for value in ["1", #""true""#, "null", "[true]", #"{"a": true}"#] {
            let json = #"{"tvVolumeEnabled": \#(value), "receiverConnection": "CEC", "launchAtLogin": true, "kioskLock": false}"#
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            #expect(!settings.tvVolumeEnabled, "\(value)")
            #expect(settings.receiverConnection == .serial, "\(value)")
            #expect(settings.launchAtLogin, "\(value)")
            #expect(!settings.kioskLock, "\(value)")
        }
        let tvMode = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"phoneRemoteVolume": "tv"}"#.utf8))
        #expect(tvMode.volumeMode == .tv)
    }

    /// M7l step 2: `glassStyle`; missing, unknown or of another type reads as `clear`, and the rest of the file is
    /// kept (no `.bak`).
    @Test func glassStyleDecodes() throws {
        let missing = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(missing.glassStyle == .clear)
        #expect(AppSettings().glassStyle == .clear)
        let frosted = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"glassStyle": "frosted"}"#.utf8))
        #expect(frosted.glassStyle == .frosted)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(frosted)) == frosted)
        let encoded = try String(decoding: JSONEncoder().encode(frosted), as: UTF8.self)
        #expect(encoded.contains(#""glassStyle":"frosted""#))
        for style in GlassStyle.allCases {
            let one = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"glassStyle": "\#(style.rawValue)"}"#.utf8))
            #expect(one.glassStyle == style)
        }
        for value in [#""bogus""#, #""Frosted""#, "12", "true", "null", #"["frosted"]"#, #"{"a": "frosted"}"#] {
            let json = #"{"glassStyle": \#(value), "launchAtLogin": true, "kioskLock": false}"#
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            #expect(settings.glassStyle == .clear, "\(value)")
            #expect(settings.launchAtLogin, "\(value)")
            #expect(!settings.kioskLock, "\(value)")
        }
    }

    /// M7j L14: Use Antenna and Guide from SiliconDust; missing or of another type reads as true, and the rest of the
    /// file is kept.
    @Test func antennaKeysDecode() throws {
        let missing = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(missing.antennaEnabled)
        #expect(missing.antennaGuide)
        #expect(AppSettings().antennaEnabled)
        #expect(AppSettings().antennaGuide)
        let off = try JSONDecoder().decode(AppSettings.self,
                                           from: Data(#"{"antennaEnabled": false, "antennaGuide": false}"#.utf8))
        #expect(!off.antennaEnabled)
        #expect(!off.antennaGuide)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(off)) == off)
        let encoded = try String(decoding: JSONEncoder().encode(off), as: UTF8.self)
        #expect(encoded.contains(#""antennaEnabled":false"#))
        #expect(encoded.contains(#""antennaGuide":false"#))
        for value in ["0", #""false""#, "null", "[false]"] {
            let json = #"{"antennaEnabled": \#(value), "antennaGuide": \#(value), "launchAtLogin": true}"#
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            #expect(settings.antennaEnabled, "\(value)")
            #expect(settings.antennaGuide, "\(value)")
            #expect(settings.launchAtLogin, "\(value)")
        }
    }

    /// M15 L5: Check for Updates (default true) and Automatic Updates (default off); an unknown mode or a value of
    /// another type reads as the default, and the rest of the file is kept.
    @Test func updateSettingsDefaultAndDecode() throws {
        let missing = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(missing.updateChecks)
        #expect(missing.automaticUpdates == .off)
        #expect(AppSettings().updateChecks)
        #expect(AppSettings().automaticUpdates == .off)
        let whenIdle = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"automaticUpdates": "whenIdle"}"#.utf8))
        #expect(whenIdle.automaticUpdates == .whenIdle)
        let atNight = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"automaticUpdates": "atNight"}"#.utf8))
        #expect(atNight.automaticUpdates == .atNight)
        let checksOff = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"updateChecks": false}"#.utf8))
        #expect(!checksOff.updateChecks)
        #expect(checksOff.automaticUpdates == .off)
        var both = AppSettings()
        both.updateChecks = false
        both.automaticUpdates = .atNight
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(both)) == both)
        let encoded = try String(decoding: JSONEncoder().encode(both), as: UTF8.self)
        #expect(encoded.contains(#""updateChecks":false"#))
        #expect(encoded.contains(#""automaticUpdates":"atNight""#))
        for value in [#""weekly""#, #""WhenIdle""#, "12", "true", "null", #"["atNight"]"#] {
            let json = #"{"automaticUpdates": \#(value), "launchAtLogin": true}"#
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            #expect(settings.automaticUpdates == .off, "\(value)")
            #expect(settings.launchAtLogin, "\(value)")
        }
        for value in ["0", #""false""#, "null", "[false]"] {
            let json = #"{"updateChecks": \#(value), "launchAtLogin": true}"#
            let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
            #expect(settings.updateChecks, "\(value)")
            #expect(settings.launchAtLogin, "\(value)")
        }
    }
}
