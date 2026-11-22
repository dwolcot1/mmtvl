#!/usr/bin/env python3
"""Tests for roku-export-settings.py (M12 step 14). No Keychain, no real MMTVL files, no Roku: a fake Keychain
reader, fixture files in a temporary folder, and the one-shot server on loopback.
Run from the repo root: python3 -I scripts/test_roku_export_settings.py"""

import contextlib
import importlib.util
import io
import json
import os
import re
import socket
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request

sys.dont_write_bytecode = True  # no __pycache__ in scripts/
_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "roku-export-settings.py")
_spec = importlib.util.spec_from_file_location("roku_export_settings", _path)
export = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(export)

PLAYLIST = "https://user:pa55@iptv.example:8080/get.php?username=alice&password=s3cretTOKEN&type=m3u_plus"
GUIDE_A = "https://epg.example/xmltv.php?username=alice&password=s3cretTOKEN"
GUIDE_B = "http://guides.example/path/to/guide.xml.gz?key=GUIDEKEY123"
SECRET_FRAGMENTS = ["s3cretTOKEN", "GUIDEKEY123", "pa55", "alice", "get.php", "xmltv.php", "guide.xml.gz", "?"]

L2_FIELDS = {
    "version", "playlistURL", "guideURLs", "usePlaylistGuide", "favorites", "hiddenChannels", "hiddenGroups",
    "teams", "overrides", "lastChannelID", "lastGroup", "recentChannelIDs", "channelUpMovesUpList",
    "teamMatchInitials", "teamMatchNicknames", "antennaEnabled", "antennaGuide",
}


def fake_keychain(items):
    calls = []

    def read(account):
        calls.append(account)
        return items.get(account)

    read.calls = calls
    return read


def write(folder, name, value):
    with open(os.path.join(folder, name), "w", encoding="utf-8") as handle:
        if isinstance(value, str):
            handle.write(value)
        else:
            json.dump(value, handle)


def standard_keychain():
    return fake_keychain({
        "iptv-playlist-url": PLAYLIST,
        "iptv-guide-urls": json.dumps([GUIDE_A, GUIDE_B]),
    })


class FixtureCase(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.folder = self._dir.name
        write(self.folder, "settings.json", {
            "channelUpMovesUpList": False, "usePlaylistGuide": True, "teamMatchInitials": True,
            "teamMatchNicknames": False, "antennaEnabled": False, "antennaGuide": True,
            "glassStyle": "clear", "kioskLock": True, "homeStartTile": "plex",
        })
        write(self.folder, "iptv-channels.json", {
            "favorites": ["id:espn.us", "name:metro news 24"], "hiddenChannels": ["id:shop.us"],
            "hiddenGroups": ["Adult", "Antenna"], "teams": ["nba.lal", "ncaaf.michigan-wolverines"],
        })
        write(self.folder, "iptv-state.json", {
            "lastChannelID": "name:metro news 24", "lastGroup": "Sports",
            "guideImports": {"a" * 64: 785000000.25, "b" * 64: 785123456.5},
            "antennaGuideDue": 785200000.75,
            "multiview": {"layout": "quad", "channelIDs": ["id:a", None], "highlighted": 1, "wasOpen": False},
            "recentChannelIDs": ["name:metro news 24", "id:espn.us"],
        })
        write(self.folder, "epg-overrides.json", {"Metro News 24": "metro.news.us", "Local 5": ""})

    def tearDown(self):
        self._dir.cleanup()


class BundleTests(FixtureCase):
    def test_builds_bundle_v1_from_the_files_and_the_keychain(self):
        reader = standard_keychain()
        bundle, notes = export.build_bundle(self.folder, reader)
        self.assertEqual(notes, [])
        self.assertEqual(bundle, {
            "version": 1,
            "playlistURL": PLAYLIST,
            "guideURLs": [GUIDE_A, GUIDE_B],
            "usePlaylistGuide": True,
            "favorites": ["id:espn.us", "name:metro news 24"],
            "hiddenChannels": ["id:shop.us"],
            "hiddenGroups": ["Adult", "Antenna"],
            "teams": ["nba.lal", "ncaaf.michigan-wolverines"],
            "overrides": {"Metro News 24": "metro.news.us", "Local 5": ""},
            "lastChannelID": "name:metro news 24",
            "lastGroup": "Sports",
            "recentChannelIDs": ["name:metro news 24", "id:espn.us"],
            "channelUpMovesUpList": False,
            "teamMatchInitials": True,
            "teamMatchNicknames": False,
            "antennaEnabled": False,
            "antennaGuide": True,
        })
        self.assertEqual(list(bundle.keys()), export.BUNDLE_FIELDS)
        self.assertEqual(set(bundle.keys()), L2_FIELDS)
        self.assertEqual(reader.calls, ["iptv-playlist-url", "iptv-guide-urls"])

    def test_the_2001_epoch_dates_and_multiview_are_never_in_the_bundle(self):
        bundle, _ = export.build_bundle(self.folder, standard_keychain())
        text = export.encode_bundle(bundle).decode("utf-8")
        for absent in ["guideImports", "antennaGuideDue", "multiview", "785000000", "785123456", "785200000",
                       "quad", "a" * 64, "glassStyle", "kioskLock"]:
            self.assertNotIn(absent, text)

        def walk(value):
            if isinstance(value, dict):
                for item in value.values():
                    walk(item)
            elif isinstance(value, list):
                for item in value:
                    walk(item)
            else:
                self.assertNotIsInstance(value, float)
        walk(bundle)

    def test_missing_files_and_keychain_items_give_mmtvls_defaults(self):
        empty = tempfile.TemporaryDirectory()
        self.addCleanup(empty.cleanup)
        reader = fake_keychain({})
        bundle, notes = export.build_bundle(empty.name, reader)
        self.assertEqual(notes, [])
        self.assertEqual(bundle["playlistURL"], "")
        self.assertEqual(bundle["guideURLs"], [])
        for field in ["favorites", "hiddenChannels", "hiddenGroups", "teams", "recentChannelIDs"]:
            self.assertEqual(bundle[field], [])
        self.assertEqual(bundle["overrides"], {})
        self.assertEqual(bundle["lastChannelID"], "")
        self.assertEqual(bundle["lastGroup"], "")
        self.assertEqual((bundle["channelUpMovesUpList"], bundle["usePlaylistGuide"], bundle["teamMatchInitials"],
                          bundle["teamMatchNicknames"], bundle["antennaEnabled"], bundle["antennaGuide"]),
                         (True, False, False, False, True, True))
        # M4's single guide is read only when the list is missing (as MMTVL's IPTVSourceStore).
        self.assertEqual(reader.calls, ["iptv-playlist-url", "iptv-guide-urls", "iptv-guide-url"])

    def test_the_legacy_single_guide_is_used_without_a_list(self):
        reader = fake_keychain({"iptv-guide-url": GUIDE_B})
        bundle, _ = export.build_bundle(self.folder, reader)
        self.assertEqual(bundle["guideURLs"], [GUIDE_B])

    def test_wrong_types_read_as_defaults(self):
        write(self.folder, "settings.json", {"channelUpMovesUpList": "no", "antennaGuide": 0})
        write(self.folder, "iptv-channels.json", {"favorites": "id:x", "teams": [1, None, "nba.bos"]})
        write(self.folder, "iptv-state.json", {"lastChannelID": 5, "lastGroup": None, "recentChannelIDs": {}})
        write(self.folder, "epg-overrides.json", ["not", "a", "map"])
        bundle, notes = export.build_bundle(self.folder, standard_keychain())
        self.assertTrue(bundle["channelUpMovesUpList"])
        self.assertTrue(bundle["antennaGuide"])
        self.assertEqual(bundle["favorites"], [])
        self.assertEqual(bundle["teams"], ["nba.bos"])
        self.assertEqual(bundle["lastChannelID"], "")
        self.assertEqual(bundle["lastGroup"], "")
        self.assertEqual(bundle["recentChannelIDs"], [])
        self.assertEqual(bundle["overrides"], {})
        self.assertEqual(notes, ["Left out 2 team(s) (over the Roku's limits)."])

    def test_a_corrupt_file_is_noted_and_read_as_defaults(self):
        write(self.folder, "iptv-channels.json", "{not json")
        bundle, notes = export.build_bundle(self.folder, standard_keychain())
        self.assertEqual(bundle["favorites"], [])
        self.assertEqual(notes, ["iptv-channels.json isn't valid JSON; using MMTVL's defaults for it."])

    def test_the_rokus_limits_are_applied_and_counted(self):
        long_id = "x" * 257
        write(self.folder, "iptv-channels.json", {
            "favorites": ["f%d" % i for i in range(503)],
            "hiddenChannels": ["", long_id, "ok"],
        })
        write(self.folder, "iptv-state.json", {"recentChannelIDs": ["r%d" % i for i in range(12)]})
        overrides = {"k%03d" % i: "v" for i in range(501)}
        overrides[long_id] = "v"
        overrides["bad value"] = "y" * 257
        write(self.folder, "epg-overrides.json", overrides)
        guides = [GUIDE_A] * 5 + ["ftp://epg.example/x", "https://", "https://ok.example/" + "p" * 2048, GUIDE_B, GUIDE_B]
        reader = fake_keychain({"iptv-playlist-url": "file:///etc/passwd", "iptv-guide-urls": json.dumps(guides)})
        bundle, notes = export.build_bundle(self.folder, reader)
        self.assertEqual(bundle["playlistURL"], "")
        self.assertEqual(bundle["guideURLs"], [GUIDE_A] * 5 + [GUIDE_B])
        self.assertEqual(len(bundle["favorites"]), 500)
        self.assertEqual(bundle["hiddenChannels"], ["ok"])
        self.assertEqual(bundle["recentChannelIDs"], ["r%d" % i for i in range(10)])
        self.assertEqual(len(bundle["overrides"]), 500)
        self.assertNotIn(long_id, bundle["overrides"])
        self.assertNotIn("bad value", bundle["overrides"])
        self.assertIn("Left out the playlist address: not an http or https address under 2 KB.", notes)
        self.assertIn("Left out 4 guide(s): not an http or https address under 2 KB, or more than 6.", notes)
        self.assertIn("Left out 3 favorite(s) (over the Roku's limits).", notes)
        self.assertIn("Left out 2 hidden channel(s) (over the Roku's limits).", notes)
        self.assertIn("Left out 2 recent channel(s) (over the Roku's limits).", notes)
        self.assertIn("Left out 3 guide match(es) (over the Roku's limits).", notes)

    def test_summary_shows_counts_and_hosts_only(self):
        bundle, _ = export.build_bundle(self.folder, standard_keychain())
        text = "\n".join(export.summary_lines(bundle, 2048))
        self.assertIn("Playlist: iptv.example", text)
        self.assertIn("Guides: 2 (epg.example, guides.example)", text)
        self.assertIn("Favorites: 2", text)
        self.assertIn("Guide matches: 2", text)
        self.assertIn("Size: 2.0 KB", text)
        for fragment in SECRET_FRAGMENTS + ["metro", "espn", "Sports"]:
            self.assertNotIn(fragment, text)


class AddressTests(unittest.TestCase):
    def test_private_ipv4_only(self):
        for good in ["10.0.0.5", "10.255.255.254", "172.16.0.1", "172.31.255.255", "192.168.1.20", "192.168.0.0"]:
            self.assertTrue(export.private_ipv4(good), good)
        for bad in ["172.15.0.1", "172.32.0.1", "8.8.8.8", "127.0.0.1", "169.254.1.1", "100.64.0.1", "0.0.0.0",
                    "192.168.01.2", "192.168.1.256", "192.168.1", "192.168.1.2.3", " 192.168.1.2", "192.168.1.2 ",
                    "192.168.1.2\n", "roku.local", "", "::1", "fd00::1", "0x0a.0.0.1", "10.0.0.1:8060", None, 10]:
            self.assertFalse(export.private_ipv4(bad), repr(bad))

    def test_ssdp_answers(self):
        good = (b"HTTP/1.1 200 OK\r\nCache-Control: max-age=3600\r\nST: roku:ecp\r\n"
                b"LOCATION: http://192.168.1.134:8060/\r\nUSN: uuid:roku:ecp:X00000000000\r\n\r\n")
        self.assertEqual(export.parse_ssdp_response(good, "192.168.1.134"), "192.168.1.134")
        self.assertIsNone(export.parse_ssdp_response(good, "192.168.1.99"), "LOCATION names another host")
        public = good.replace(b"192.168.1.134", b"8.8.8.8")
        self.assertIsNone(export.parse_ssdp_response(public, "8.8.8.8"))
        other_port = good.replace(b":8060/", b":9000/")
        self.assertIsNone(export.parse_ssdp_response(other_port, "192.168.1.134"))
        not_roku = good.replace(b"roku:ecp", b"upnp:rootdevice")
        self.assertIsNone(export.parse_ssdp_response(not_roku, "192.168.1.134"))
        self.assertIsNone(export.parse_ssdp_response(b"garbage", "192.168.1.134"))

    def test_device_names_and_serials_are_cleaned(self):
        xml = ("<device-info><user-device-name>Living\x1b[31m Room &amp; Den</user-device-name>"
               "<model-name>Roku Ultra</model-name><serial-number>X0\x1b0Y-1a2B</serial-number></device-info>")
        self.assertEqual(export.parse_device_info(xml), ("Living[31m Room & Den (Roku Ultra)", "1a2B"))
        self.assertEqual(export.parse_device_info("<device-info></device-info>"), ("Roku", ""))
        self.assertEqual(export.parse_device_info("<default-device-name>Roku Express - X</default-device-name>"
                                                  "<serial-number>YH00AB</serial-number>"),
                         ("Roku Express - X", "00AB"))
        self.assertEqual(export.describe_roku("Den", "1A2B", "192.168.1.20"), "Den · serial …1A2B · 192.168.1.20")
        self.assertEqual(export.describe_roku("Den", "", "192.168.1.20"), "Den · serial unknown · 192.168.1.20")


class SecretTests(unittest.TestCase):
    def test_the_secret_is_32_lowercase_hex_from_128_random_bits(self):
        seen = set()
        for _ in range(200):
            secret = export.new_secret()
            self.assertRegex(secret, r"\A[0-9a-f]{32}\Z")
            seen.add(secret)
        self.assertEqual(len(seen), 200)

    def test_the_content_id(self):
        secret = "0123456789abcdef0123456789abcdef"
        self.assertEqual(export.content_id("192.168.1.10", 49152, secret),
                         "mmtvl-import:192.168.1.10:49152:" + secret)


def get(port, path, timeout=5):
    """(status, body) of a GET to the loopback server."""
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open("http://127.0.0.1:%d%s" % (port, path), timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, b""


class ServerTests(unittest.TestCase):
    SECRET = "fedcba9876543210fedcba9876543210"

    def start(self, lifetime=10, allowed="127.0.0.1"):
        server = export.OneShotServer("127.0.0.1", b'{"version":1}', self.SECRET, allowed, lifetime)
        outcome = {}
        thread = threading.Thread(target=lambda: outcome.setdefault("result", server.serve()))
        thread.daemon = True
        thread.start()
        return server, thread, outcome

    def test_serves_once_at_the_secret_path_then_404(self):
        server, thread, outcome = self.start()
        self.assertEqual(get(server.port, "/")[0], 404)
        self.assertEqual(get(server.port, "/" + self.SECRET.upper())[0], 404)
        self.assertEqual(get(server.port, "/" + self.SECRET + "?x=1")[0], 404)
        self.assertEqual(get(server.port, "/" + self.SECRET[:-1])[0], 404)
        self.assertEqual(get(server.port, "/" + self.SECRET), (200, b'{"version":1}'))
        thread.join(5)
        self.assertEqual(outcome.get("result"), "served")
        self.assertNotEqual(self.status_after_exit(server.port), 200)

    def test_a_second_get_while_still_running_is_404(self):
        server = export.OneShotServer("127.0.0.1", b"{}", self.SECRET, None, 10)
        server.served = True  # as after the first GET
        thread = threading.Thread(target=server.httpd.handle_request)
        thread.start()
        self.assertEqual(get(server.port, "/" + self.SECRET)[0], 404)
        thread.join(5)
        server.close()

    def test_another_address_is_closed_at_accept_and_doesnt_use_it_up(self):
        # Allowed: an address this test never connects from; the loopback GET must get nothing.
        server, thread, outcome = self.start(lifetime=1.5, allowed="10.255.255.1")
        self.assertNotEqual(self.status_or_none(server.port), 200)
        thread.join(5)
        self.assertEqual(outcome.get("result"), "expired")

    def test_a_slow_client_doesnt_hold_up_the_roku(self):
        server, thread, outcome = self.start(lifetime=10)
        slow = socket.create_connection(("127.0.0.1", server.port))
        self.addCleanup(slow.close)
        slow.sendall(b"GET /")  # and nothing more
        time.sleep(0.3)
        started = time.monotonic()
        self.assertEqual(get(server.port, "/" + self.SECRET, timeout=2), (200, b'{"version":1}'))
        self.assertLess(time.monotonic() - started, 2)
        thread.join(5)
        self.assertEqual(outcome.get("result"), "served")

    def test_expires_on_time_while_a_slow_client_is_connected(self):
        started = time.monotonic()
        server, thread, outcome = self.start(lifetime=1.0)
        slow = socket.create_connection(("127.0.0.1", server.port))
        self.addCleanup(slow.close)
        slow.sendall(b"GET /" + self.SECRET.encode("ascii"))  # the right path, never finished
        thread.join(5)
        self.assertEqual(outcome.get("result"), "expired")
        self.assertLess(time.monotonic() - started, 2.0, "within lifetime + 1 s")
        slow.settimeout(2)
        try:
            leftover = slow.recv(1024)
        except OSError:
            leftover = b""
        self.assertNotIn(b"200", leftover, "the half-sent request never got the bundle")
        self.assertNotIn(b"version", leftover)

    def test_a_connection_past_its_deadline_is_refused(self):
        server = export.OneShotServer("127.0.0.1", b"{}", self.SECRET, None, 10)
        self.addCleanup(server.close)
        past = server.clock() - 1
        self.assertFalse(server.claim("127.0.0.1", "/" + self.SECRET, past))
        self.assertTrue(server.claim("127.0.0.1", "/" + self.SECRET, server.clock() + 5))
        self.assertFalse(server.claim("127.0.0.1", "/" + self.SECRET, server.clock() + 5), "only once")

    def test_a_claim_and_the_expiry_never_disagree(self):
        now = [100.0]
        clock = lambda: now[0]
        path = "/" + self.SECRET
        # The expiry decides first: a claim that arrives after it is refused.
        first = export.OneShotServer("127.0.0.1", b"{}", self.SECRET, None, 10, clock=clock)
        self.addCleanup(first.close)
        first.deadline = 110.0
        self.assertIsNone(first.outcome())
        now[0] = 110.0
        self.assertEqual(first.outcome(), "expired")
        self.assertFalse(first.claim("127.0.0.1", path, 200.0))
        self.assertEqual(first.outcome(), "expired")
        # A claim that lands first, even with the deadline already passed for the server: the outcome is "served".
        now[0] = 100.0
        second = export.OneShotServer("127.0.0.1", b"{}", self.SECRET, None, 10, clock=clock)
        self.addCleanup(second.close)
        second.deadline = 110.0
        self.assertTrue(second.claim("127.0.0.1", path, 105.0))
        now[0] = 111.0
        self.assertEqual(second.outcome(), "served")

    def status_or_none(self, port):
        try:
            return get(port, "/" + self.SECRET, timeout=2)[0]
        except OSError:
            return None

    def test_expires_after_its_lifetime(self):
        started = time.monotonic()
        server, thread, outcome = self.start(lifetime=1.0)
        thread.join(5)
        self.assertEqual(outcome.get("result"), "expired")
        self.assertLess(time.monotonic() - started, 4)
        self.assertNotEqual(self.status_after_exit(server.port), 200)

    def status_after_exit(self, port):
        """The server has exited: the port refuses (None), or whatever answers there isn't the bundle."""
        try:
            return get(port, "/" + self.SECRET, timeout=2)[0]
        except OSError:
            return None

    def test_the_default_lifetime_is_ten_minutes(self):
        self.assertEqual(export.LIFETIME_SECONDS, 600)

    def test_requests_are_never_logged(self):
        server, thread, outcome = self.start()
        captured = io.StringIO()
        with contextlib.redirect_stderr(captured):
            get(server.port, "/wrong")
            get(server.port, "/" + self.SECRET)
            thread.join(5)
        self.assertEqual(captured.getvalue(), "")


class FakeNetwork(export.Network):
    """The script's network, with no Roku: launch records the contentId and does the Roku's GET on loopback."""

    def __init__(self, hosts=None):
        super().__init__()
        self.content = None
        self.fetched = None
        self.discover = lambda: list(hosts or [])
        self.device_info = lambda host: ("Den (Roku Express)", "1A2B")
        self.local_address = lambda roku: "192.168.1.10"
        self.bind_address = lambda mac_ip: "127.0.0.1"
        self.allowed_client = lambda roku: "127.0.0.1"
        self.launch = self.fake_launch

    def fake_launch(self, roku, content):
        self.content = content
        match = re.match(r"\Ammtvl-import:192\.168\.1\.10:(\d+):([0-9a-f]{32})\Z", content)
        if not match:
            raise AssertionError("bad contentId")
        port, secret = int(match.group(1)), match.group(2)

        def fetch():
            time.sleep(0.2)
            self.fetched = get(port, "/" + secret)
        self.thread = threading.Thread(target=fetch, daemon=True)
        self.thread.start()


class OutputTests(FixtureCase):
    def run_main(self, argv, network=None, answers=()):
        out = io.StringIO()
        replies = list(answers)
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            code = export.main(argv, config_dir=self.folder, keychain_reader=standard_keychain(),
                               network=network or FakeNetwork(), input_fn=lambda prompt: replies.pop(0),
                               lifetime=10)
        return code, out.getvalue()

    def assert_nothing_secret(self, text, network=None):
        for fragment in SECRET_FRAGMENTS + [PLAYLIST, GUIDE_A, GUIDE_B, "http", "mmtvl-import"]:
            self.assertNotIn(fragment, text)
        if network is not None and network.content:
            content = network.content
            secret = content.rsplit(":", 1)[1]
            port = content.split(":")[2]
            self.assertNotIn(secret, text)
            self.assertNotIn(content, text)
            self.assertNotIn(port, text)

    def test_dry_run_prints_the_summary_only(self):
        network = FakeNetwork()
        network.launch = lambda roku, content: self.fail("dry run launched")
        network.discover = lambda: self.fail("dry run searched")
        code, text = self.run_main(["--dry-run"], network)
        self.assertEqual(code, 0)
        self.assertIn("Playlist: iptv.example", text)
        self.assertIn("Dry run: nothing was sent.", text)
        self.assert_nothing_secret(text)

    def test_sending_to_a_given_roku(self):
        network = FakeNetwork()
        code, text = self.run_main(["--roku", "192.168.1.50"], network)
        self.assertEqual(code, 0, text)
        self.assertIn("Roku: Den (Roku Express) · serial …1A2B · 192.168.1.50", text)
        self.assertLess(text.index("Roku: Den"), text.index("Opened MMTVL Live TV"), "named before the launch")
        self.assertLess(text.index(export.COMPARE_ADDRESS), text.index("Opened MMTVL Live TV"))
        network.thread.join(5)
        self.assertEqual(network.fetched[0], 200)
        sent = json.loads(network.fetched[1].decode("utf-8"))
        self.assertEqual(sent["playlistURL"], PLAYLIST)
        self.assertEqual(set(sent), L2_FIELDS)
        self.assertIn("The Roku has the settings.", text)
        self.assertIn("192.168.1.50", text)
        self.assert_nothing_secret(text, network)

    def test_sending_to_a_discovered_roku(self):
        network = FakeNetwork(hosts=["192.168.1.60", "192.168.1.61"])
        launched = []
        original = network.launch
        network.launch = lambda roku, content: (launched.append(roku), original(roku, content))
        code, text = self.run_main([], network, answers=["9", "2"])
        self.assertEqual(code, 0, text)
        self.assertEqual(launched, ["192.168.1.61"])
        self.assertIn("1. Den (Roku Express) · serial …1A2B · 192.168.1.60", text)
        self.assertIn(export.COMPARE_ADDRESS, text)
        self.assert_nothing_secret(text, network)

    def test_refuses_a_roku_that_isnt_on_the_lan(self):
        for host in ["8.8.8.8", "127.0.0.1", "roku.example", "169.254.3.4"]:
            network = FakeNetwork()
            network.launch = lambda roku, content: self.fail("launched for a public host")
            code, text = self.run_main(["--roku", host], network)
            self.assertEqual(code, 1)
            self.assertIn("Refusing", text)
            self.assertNotIn("Playlist:", text, "refused before the Keychain is read")

    def test_a_failed_launch_says_so_with_the_host_only(self):
        network = FakeNetwork()

        def refuse(roku, content):
            network.content = content
            raise export.ExportError("Couldn't reach the Roku at %s." % roku)
        network.launch = refuse
        code, text = self.run_main(["--roku", "192.168.1.50"], network)
        self.assertEqual(code, 1)
        self.assertIn("Couldn't reach the Roku at 192.168.1.50.", text)
        self.assert_nothing_secret(text, network)

    def test_an_expired_offer_says_so(self):
        network = FakeNetwork()
        network.launch = lambda roku, content: setattr(network, "content", content)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = export.main(["--roku", "192.168.1.50"], config_dir=self.folder,
                               keychain_reader=standard_keychain(), network=network, lifetime=1)
        self.assertEqual(code, 1)
        self.assertIn("didn't fetch the settings in time", out.getvalue())
        self.assert_nothing_secret(out.getvalue(), network)

    def test_a_bundle_over_64_kb_is_refused(self):
        write(self.folder, "iptv-channels.json", {"hiddenChannels": ["c" * 250 + str(i) for i in range(400)]})
        network = FakeNetwork()
        network.launch = lambda roku, content: self.fail("sent an oversized bundle")
        code, text = self.run_main(["--roku", "192.168.1.50"], network)
        self.assertEqual(code, 1)
        self.assertIn("over the Roku's 64 KB", text)


    def test_answers_that_share_a_name_get_a_warning_with_both_serials(self):
        network = FakeNetwork(hosts=["192.168.1.60", "192.168.1.66"])
        serials = {"192.168.1.60": "1A2B", "192.168.1.66": "9Z8Y"}
        network.device_info = lambda host: ("Living Room (Roku Ultra)", serials[host])
        network.launch = lambda roku, content: self.fail("launched without a pick")
        code, text = self.run_main([], network, answers=[""])
        self.assertEqual(code, 0)
        self.assertIn(export.LOOKALIKE_WARNING, text)
        self.assertIn("Living Room (Roku Ultra) · serial …1A2B · 192.168.1.60", text)
        self.assertIn("Living Room (Roku Ultra) · serial …9Z8Y · 192.168.1.66", text)
        self.assertIn("Nothing was sent.", text)

    def test_different_names_get_no_warning(self):
        network = FakeNetwork(hosts=["192.168.1.60", "192.168.1.66"])
        network.device_info = lambda host: ("Roku " + host[-2:], "")
        code, text = self.run_main([], network, answers=[""])
        self.assertNotIn("Warning", text)
        self.assertIn("serial unknown", text)


    def test_lookalike_names_with_a_copied_serial_get_the_warning(self):
        network = FakeNetwork(hosts=["192.168.1.60", "192.168.1.66"])
        names = {"192.168.1.60": "Living Room (Roku Ultra)", "192.168.1.66": "Living R\u043e\u043em (Roku Ultra)"}
        network.device_info = lambda host: (names[host], "1A2B")
        code, text = self.run_main([], network, answers=[""])
        self.assertEqual(code, 0)
        self.assertIn(export.LOOKALIKE_WARNING, text)
        self.assertEqual(text.count("serial …1A2B"), 2)

    def test_names_that_differ_only_in_case_or_width_are_lookalikes(self):
        self.assertTrue(export.lookalikes([("Den", ""), ("DEN", "")]))
        self.assertTrue(export.lookalikes([("Den", ""), ("\uff24en", "")]), "a full-width D")
        self.assertTrue(export.lookalikes([("Den", "1a2b"), ("Bedroom", "1A2B")]), "a shared serial")
        self.assertFalse(export.lookalikes([("Den", ""), ("Bedroom", "")]), "no serials known")
        self.assertFalse(export.lookalikes([("Den", "1A2B"), ("Bedroom", "9Z8Y")]))

    def test_the_instruction_names_the_ip_address_and_the_network_page(self):
        for text in [export.COMPARE_ADDRESS, export.LOOKALIKE_WARNING]:
            self.assertIn("IP address", text)
            self.assertIn("Settings > Network > About", text)


class FakeReplyServer:
    """A loopback TCP server that sends each connection reply (bytes, or a list of (delay, bytes) pieces)."""

    def __init__(self, reply):
        self.reply = reply
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(4)
        self.port = self.listener.getsockname()[1]
        self.stopped = threading.Event()
        threading.Thread(target=self.run, daemon=True).start()

    def run(self):
        self.listener.settimeout(0.2)
        while not self.stopped.is_set():
            try:
                connection, _ = self.listener.accept()
            except OSError:
                continue
            threading.Thread(target=self.answer, args=(connection,), daemon=True).start()

    def answer(self, connection):
        try:
            connection.settimeout(1)
            try:
                connection.recv(4096)
            except OSError:
                pass
            pieces = self.reply if isinstance(self.reply, list) else [(0, self.reply)]
            for delay, piece in pieces:
                if self.stopped.is_set():
                    break
                time.sleep(delay)
                connection.sendall(piece)
        except OSError:
            pass
        finally:
            connection.close()

    def close(self):
        self.stopped.set()
        self.listener.close()


class MalformedReplyTests(FixtureCase):
    BAD_STATUS = b"HTTP/1.1 2\x1b[31m00 \x1b]0;owned\x07OK\r\nContent-Length: 0\r\n\r\n"

    def fake(self, reply):
        server = FakeReplyServer(reply)
        self.addCleanup(server.close)
        return server

    def test_a_bad_status_line_gives_the_fallback_name(self):
        server = self.fake(self.BAD_STATUS)
        self.assertEqual(export.device_info("127.0.0.1", port=server.port), ("Roku", ""))

    def test_a_bad_status_line_on_launch_is_an_export_error_naming_the_host(self):
        server = self.fake(self.BAD_STATUS)
        content = "mmtvl-import:192.168.1.10:5000:" + "a" * 32
        with self.assertRaises(export.ExportError) as caught:
            export.ecp_launch("127.0.0.1", content, port=server.port)
        message = str(caught.exception)
        self.assertEqual(message, "The Roku at 127.0.0.1 sent a reply this script couldn't read.")
        self.assertNotIn("\x1b", message)
        self.assertNotIn("a" * 32, message)

    def test_a_good_reply_with_escapes_in_its_name_prints_clean(self):
        body = (b"<device-info><user-device-name>Den\x1b[2J</user-device-name><serial-number>X00Y\x1b9Z8Y"
                b"</serial-number></device-info>")
        server = self.fake(b"HTTP/1.1 200 OK\r\nContent-Length: %d\r\n\r\n" % len(body) + body)
        self.assertEqual(export.device_info("127.0.0.1", port=server.port), ("Den[2J", "9Z8Y"))

    def test_a_trickled_reply_is_given_up_on_time(self):
        pieces = [(0, b"HTTP/1.1 200 OK\r\n")] + [(0.2, b"x")] * 40
        server = self.fake(pieces)
        started = time.monotonic()
        self.assertEqual(export.device_info("127.0.0.1", port=server.port, limit=1.0), ("Roku", ""))
        self.assertLess(time.monotonic() - started, 1.6)

    def test_stdout_holds_no_escape_from_a_malformed_roku(self):
        server = self.fake(self.BAD_STATUS)
        network = FakeNetwork()
        network.device_info = lambda host: export.device_info("127.0.0.1", port=server.port)
        network.launch = lambda roku, content: export.ecp_launch("127.0.0.1", content, port=server.port)
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            code = export.main(["--roku", "192.168.1.50"], config_dir=self.folder,
                               keychain_reader=standard_keychain(), network=network, lifetime=5)
        text = out.getvalue()
        self.assertEqual(code, 1)
        self.assertNotIn("\x1b", text)
        self.assertNotIn("\x07", text)
        self.assertIn("Roku: Roku · serial unknown · 192.168.1.50", text)
        self.assertIn("The Roku at 127.0.0.1 sent a reply this script couldn't read.", text)


if __name__ == "__main__":
    unittest.main(verbosity=1)
