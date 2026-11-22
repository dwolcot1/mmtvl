#!/usr/bin/env python3
"""M12 L2: sends MMTVL's Live TV settings to MMTVL Live TV on a Roku, once.

Reads the playlist and guide addresses from the login Keychain (service dev.mmtvl.launcher, accounts
iptv-playlist-url and iptv-guide-urls; macOS may ask to allow it) and the Live TV files in
~/Library/Application Support/MMTVL (settings.json, iptv-state.json, iptv-channels.json, epg-overrides.json), and
builds bundle v1:

  {version: 1, playlistURL, guideURLs[], usePlaylistGuide, favorites[], hiddenChannels[], hiddenGroups[], teams[],
   overrides{}, lastChannelID, lastGroup, recentChannelIDs[], channelUpMovesUpList, teamMatchInitials,
   teamMatchNicknames, antennaEnabled, antennaGuide}

Nothing else is read or sent: iptv-state.json's guideImports, antennaGuideDue and multiview (Swift dates on the 2001
epoch, Multiview's windows) are never read into the bundle. Values the Roku would refuse are left out and counted
(the Roku's limits: addresses http or https, at most 2 KB; at most 6 guides; ids and names at most 256 characters;
at most 500 entries per list, 10 recent channels; the bundle at most 64 KB).

Then it finds the Rokus on the network (SSDP, ST roku:ecp; or takes --roku <address>) and lists them by name, the
last 4 characters of the serial number and the IP address. The user checks the address against the TV's Settings >
Network > About: any LAN host can answer SSDP as a Roku and copy its name and serial, but not its address (security
M-1); answers that share a name or a serial get a warning. For the one
chosen (a private IPv4 address only), serves the bundle once over plain HTTP on this Mac's address on
that network, on a free port, at /<32 lowercase hex> (128 random bits). It asks the Roku to open the sideloaded
app with contentId mmtvl-import:<this Mac's address>:<port>:<32 hex> (ECP launch/dev, mediaType special). The Roku
fetches the bundle and asks on the TV before it replaces anything. One GET of the right path from the Roku's
address is answered; any other path or a second GET gets 404, and a connection from another address is closed
before it is read. Every connection has an absolute deadline. The script exits after that one GET, or after 10
minutes.

It never prints an address with a path, a token, the secret or the contentId: hosts and counts only.

Usage (from the repo root):
  python3 -I scripts/roku-export-settings.py               find the Rokus and choose one
  python3 -I scripts/roku-export-settings.py --roku 192.168.1.20
  python3 -I scripts/roku-export-settings.py --dry-run     only show what would be sent
Tests: python3 -I scripts/test_roku_export_settings.py
Python 3 standard library only. Plain HTTP on the LAN (D11's trust level), one GET, 10 minutes.
"""

import argparse
import hmac
import html
import http.client
import http.server
import json
import os
import re
import secrets
import socket
import subprocess
import sys
import threading
import time
import unicodedata
import urllib.parse

SERVICE = "dev.mmtvl.launcher"
PLAYLIST_ACCOUNT = "iptv-playlist-url"
GUIDES_ACCOUNT = "iptv-guide-urls"
# M4's single guide, read only when the list is missing (as MMTVL's IPTVSourceStore.guideURLs).
LEGACY_GUIDE_ACCOUNT = "iptv-guide-url"
SECURITY_TOOL = "/usr/bin/security"
SECURITY_NOT_FOUND = 44  # security's exit status for "The specified item could not be found in the keychain."

CONFIG_DIR = os.path.expanduser("~/Library/Application Support/MMTVL")

BUNDLE_VERSION = 1
MAX_BUNDLE_BYTES = 64 * 1024
MAX_URL_LENGTH = 2048
MAX_GUIDES = 6
MAX_ID_LENGTH = 256
MAX_LIST_ENTRIES = 500
MAX_RECENTS = 10

ECP_PORT = 8060
CONTENT_PREFIX = "mmtvl-import"
LIFETIME_SECONDS = 600
SSDP_ADDRESS = ("239.255.255.250", 1900)
SSDP_WAIT_SECONDS = 3.0
HTTP_TIMEOUT = 10
MAX_DEVICE_INFO_BYTES = 64 * 1024
DEVICE_INFO_SECONDS = 5  # the whole device-info exchange

# MMTVL's defaults (App/AppSettings.swift).
SETTING_DEFAULTS = [
    ("channelUpMovesUpList", True),
    ("usePlaylistGuide", False),
    ("teamMatchInitials", False),
    ("teamMatchNicknames", False),
    ("antennaEnabled", True),
    ("antennaGuide", True),
]

BUNDLE_FIELDS = [
    "version", "playlistURL", "guideURLs", "usePlaylistGuide", "favorites", "hiddenChannels", "hiddenGroups",
    "teams", "overrides", "lastChannelID", "lastGroup", "recentChannelIDs", "channelUpMovesUpList",
    "teamMatchInitials", "teamMatchNicknames", "antennaEnabled", "antennaGuide",
]


class ExportError(Exception):
    """A reason to stop, printed as is: never holds a URL, token or secret."""


# --- the Keychain ----------------------------------------------------------------------------------------------

def read_keychain(account):
    """The item's text, or None when there is none. Raises ExportError (no value in it) when security fails."""
    try:
        done = subprocess.run(
            [SECURITY_TOOL, "find-generic-password", "-s", SERVICE, "-a", account, "-w"],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=120,
        )
    except (OSError, subprocess.TimeoutExpired):
        raise ExportError("Couldn't run macOS's security tool to read %s from the Keychain." % account)
    if done.returncode == SECURITY_NOT_FOUND:
        return None
    if done.returncode != 0:
        raise ExportError("Couldn't read %s from the Keychain (security exit %d): access was denied, or the login "
                          "keychain is locked." % (account, done.returncode))
    text = done.stdout.decode("utf-8", "replace")
    if text.endswith("\n"):
        text = text[:-1]
    return text


# --- reading MMTVL's files -------------------------------------------------------------------------------------

def load_json(config_dir, name, notes):
    """The file's JSON, or None when it's missing; a file that can't be read is noted and read as None."""
    path = os.path.join(config_dir, name)
    try:
        with open(path, "rb") as handle:
            data = handle.read()
    except FileNotFoundError:
        return None
    except OSError:
        notes.append("Couldn't read %s; using MMTVL's defaults for it." % name)
        return None
    try:
        return json.loads(data.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        notes.append("%s isn't valid JSON; using MMTVL's defaults for it." % name)
        return None


def is_web_url(value):
    """http or https with a host, at most 2 KB, no space or control character (what the Roku accepts)."""
    if not isinstance(value, str) or value == "" or len(value) > MAX_URL_LENGTH:
        return False
    if any(ord(c) <= 32 or ord(c) == 127 for c in value):
        return False
    lower = value.lower()
    if not (lower.startswith("http://") or lower.startswith("https://")):
        return False
    return host_of(value) != ""


def host_of(url):
    """The URL's host, lowercased, or "" when it has none this script will show (as the Roku's Log.host)."""
    if not isinstance(url, str) or "://" not in url:
        return ""
    try:
        name = urllib.parse.urlsplit(url).hostname or ""
    except ValueError:
        return ""
    if len(name) > 253 or any(ord(c) <= 32 or ord(c) >= 127 for c in name):
        return ""
    return name.lower()


def text_list(value, max_count, label, notes):
    """The non-empty strings of at most 256 characters, in order, at most max_count; the rest noted by count."""
    if not isinstance(value, list):
        return []
    kept = []
    dropped = 0
    for item in value:
        if isinstance(item, str) and 0 < len(item) <= MAX_ID_LENGTH and len(kept) < max_count:
            kept.append(item)
        else:
            dropped += 1
    if dropped:
        notes.append("Left out %d %s (over the Roku's limits)." % (dropped, label))
    return kept


def bounded_text(value):
    if isinstance(value, str) and len(value) <= MAX_ID_LENGTH:
        return value
    return ""


def guide_urls(keychain_reader, notes):
    """The pasted guides (iptv-guide-urls, a JSON array), else M4's single iptv-guide-url, as MMTVL reads them."""
    listed = keychain_reader(GUIDES_ACCOUNT)
    if listed is None:
        legacy = keychain_reader(LEGACY_GUIDE_ACCOUNT)
        candidates = [] if legacy is None else [legacy]
    else:
        try:
            candidates = json.loads(listed)
        except ValueError:
            notes.append("The guide list in the Keychain couldn't be read; no guides are sent.")
            candidates = []
        if not isinstance(candidates, list):
            candidates = []
    kept = []
    dropped = 0
    for url in candidates:
        if is_web_url(url) and len(kept) < MAX_GUIDES:
            kept.append(url)
        else:
            dropped += 1
    if dropped:
        notes.append("Left out %d guide(s): not an http or https address under 2 KB, or more than 6." % dropped)
    return kept


def build_bundle(config_dir, keychain_reader):
    """(bundle, notes): bundle v1 from the Keychain and MMTVL's files, within the Roku's limits."""
    notes = []
    playlist = keychain_reader(PLAYLIST_ACCOUNT)
    if playlist is None:
        playlist = ""
    elif not is_web_url(playlist):
        notes.append("Left out the playlist address: not an http or https address under 2 KB.")
        playlist = ""
    guides = guide_urls(keychain_reader, notes)

    settings = load_json(config_dir, "settings.json", notes)
    if not isinstance(settings, dict):
        settings = {}
    channels = load_json(config_dir, "iptv-channels.json", notes)
    if not isinstance(channels, dict):
        channels = {}
    state = load_json(config_dir, "iptv-state.json", notes)
    if not isinstance(state, dict):
        state = {}
    overrides_file = load_json(config_dir, "epg-overrides.json", notes)

    overrides = {}
    dropped = 0
    if isinstance(overrides_file, dict):
        for key, value in overrides_file.items():
            if (0 < len(key) <= MAX_ID_LENGTH and isinstance(value, str) and len(value) <= MAX_ID_LENGTH
                    and len(overrides) < MAX_LIST_ENTRIES):
                overrides[key] = value
            else:
                dropped += 1
    if dropped:
        notes.append("Left out %d guide match(es) (over the Roku's limits)." % dropped)

    bundle = {
        "version": BUNDLE_VERSION,
        "playlistURL": playlist,
        "guideURLs": guides,
        "favorites": text_list(channels.get("favorites"), MAX_LIST_ENTRIES, "favorite(s)", notes),
        "hiddenChannels": text_list(channels.get("hiddenChannels"), MAX_LIST_ENTRIES, "hidden channel(s)", notes),
        "hiddenGroups": text_list(channels.get("hiddenGroups"), MAX_LIST_ENTRIES, "hidden group(s)", notes),
        "teams": text_list(channels.get("teams"), MAX_LIST_ENTRIES, "team(s)", notes),
        "overrides": overrides,
        # Only these three fields of iptv-state.json: its dates (guideImports, antennaGuideDue) are never read.
        "lastChannelID": bounded_text(state.get("lastChannelID")),
        "lastGroup": bounded_text(state.get("lastGroup")),
        "recentChannelIDs": text_list(state.get("recentChannelIDs"), MAX_RECENTS, "recent channel(s)", notes),
    }
    for name, default in SETTING_DEFAULTS:
        value = settings.get(name)
        bundle[name] = value if isinstance(value, bool) else default
    return {field: bundle[field] for field in BUNDLE_FIELDS}, notes


def encode_bundle(bundle):
    return json.dumps(bundle, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def summary_lines(bundle, size):
    """What is sent, as counts and hosts only."""
    playlist = host_of(bundle["playlistURL"]) or "none"
    guide_hosts = [host_of(url) or "?" for url in bundle["guideURLs"]]
    guides = "%d" % len(guide_hosts)
    if guide_hosts:
        guides += " (" + ", ".join(guide_hosts) + ")"
    source = "the playlist's guide" if bundle["usePlaylistGuide"] else "the added guides"
    return [
        "  Playlist: " + playlist,
        "  Guides: " + guides,
        "  Guide source: " + source,
        "  Favorites: %d" % len(bundle["favorites"]),
        "  Hidden channels: %d" % len(bundle["hiddenChannels"]),
        "  Hidden groups: %d" % len(bundle["hiddenGroups"]),
        "  My Teams: %d" % len(bundle["teams"]),
        "  Guide matches: %d" % len(bundle["overrides"]),
        "  Last channel: " + ("set" if bundle["lastChannelID"] else "none"),
        "  Recent channels: %d" % len(bundle["recentChannelIDs"]),
        "  Size: %.1f KB" % (size / 1024.0),
    ]


# --- addresses ---------------------------------------------------------------------------------------------------

_DOTTED_QUAD = re.compile(r"(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})\Z")


def private_ipv4(text):
    """True for a dotted-quad IPv4 address (no leading zeros) in 10/8, 172.16/12 or 192.168/16."""
    if not isinstance(text, str):
        return False
    match = _DOTTED_QUAD.match(text)
    if not match:
        return False
    parts = [int(part) for part in match.groups()]
    if any(part > 255 for part in parts):
        return False
    return parts[0] == 10 or (parts[0] == 172 and 16 <= parts[1] <= 31) or (parts[0] == 192 and parts[1] == 168)


def local_address_for(roku_host):
    """This Mac's address on the interface that routes to the Roku (no packet is sent)."""
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect((roku_host, ECP_PORT))
        return probe.getsockname()[0]
    finally:
        probe.close()


# --- the secret and the contentId ------------------------------------------------------------------------------

def new_secret():
    """128 random bits as 32 lowercase hex characters (the Roku accepts lowercase only)."""
    return secrets.token_hex(16)


def content_id(mac_ip, port, secret):
    return "%s:%s:%d:%s" % (CONTENT_PREFIX, mac_ip, port, secret)


# --- the one-shot server ---------------------------------------------------------------------------------------

class OneShotServer:
    """Serves body once at /<secret> to allowed_client (None: any address), bound to bind_host on a free port.

    serve() returns "served" after the one 200, or "expired" after lifetime seconds (within about a second, even
    while a client is connected). A connection from any other address than allowed_client is closed at accept,
    before a byte is read (security L-1). Each connection runs in its own thread with an absolute deadline: at most
    CONNECTION_SECONDS, never past the server's own; its socket timeout is the time left, accepts() refuses after
    it, and serve() shuts down connections past theirs. Every other request (another path, another method, or any
    request after the 200) gets 404 or 501. Nothing is logged, not even errors.
    """

    CONNECTION_SECONDS = 10.0
    TICK_SECONDS = 0.25

    def __init__(self, bind_host, body, secret, allowed_client=None, lifetime=LIFETIME_SECONDS, clock=time.monotonic):
        self.body = body
        self.expected_path = ("/" + secret).encode("ascii")
        self.allowed_client = allowed_client
        self.lifetime = lifetime
        self.clock = clock
        self.deadline = None
        self.served = False
        self.expired = False  # set by outcome() under the lock: after it, claim() always refuses
        self.finished = threading.Event()  # set once the 200 has been written (or its write failed)
        self.lock = threading.Lock()
        self.connections = {}  # socket -> its deadline
        self.httpd = _Server((bind_host, 0), _make_handler(self), self)
        self.port = self.httpd.server_address[1]

    def allows_address(self, client):
        return self.allowed_client is None or client == self.allowed_client

    def connection_deadline(self):
        now = self.clock()
        limit = now + self.CONNECTION_SECONDS
        if self.deadline is not None:
            limit = min(limit, self.deadline)
        return limit

    def claim(self, client, path, deadline):
        """True once: the right path, from the allowed address, before the connection's deadline."""
        if not self.allows_address(client) or self.clock() >= deadline:
            return False
        if not hmac.compare_digest(path.encode("utf-8", "replace"), self.expected_path):
            return False
        with self.lock:
            if self.served or self.expired:
                return False
            self.served = True
            return True

    def outcome(self):
        """"served", "expired" or None (keep serving), decided under the lock, so a claim and the expiry can't both
        win: once this says "expired", claim() refuses; a claim that came first makes it say "served"."""
        with self.lock:
            if self.served:
                return "served"
            if self.deadline is not None and self.clock() >= self.deadline:
                self.expired = True
                return "expired"
            return None

    def track(self, connection, deadline):
        with self.lock:
            self.connections[connection] = deadline

    def untrack(self, connection):
        with self.lock:
            self.connections.pop(connection, None)

    def reap(self, everything=False):
        """Shuts down connections past their deadline (all of them when everything)."""
        now = self.clock()
        with self.lock:
            late = [c for c, limit in self.connections.items() if everything or now >= limit]
        for connection in late:
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

    def serve(self):
        self.deadline = self.clock() + self.lifetime
        try:
            while True:
                result = self.outcome()
                if result == "served":
                    # The 200 is written by its connection's thread: wait for it (at most its own deadline).
                    self.finished.wait(self.CONNECTION_SECONDS)
                    return "served"
                if result == "expired":
                    return "expired"
                remaining = max(0.01, self.deadline - self.clock())
                self.httpd.timeout = min(self.TICK_SECONDS, remaining)
                self.httpd.handle_request()
                self.reap()
        finally:
            self.close()

    def close(self):
        try:
            self.httpd.server_close()
        except OSError:
            pass
        self.reap(everything=True)


class _Server(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, handler, owner):
        self.owner = owner
        super().__init__(address, handler)

    def verify_request(self, request, client_address):
        return self.owner.allows_address(client_address[0])

    def handle_error(self, request, client_address):  # never print a traceback or an address
        pass


def _make_handler(owner):
    class Handler(http.server.BaseHTTPRequestHandler):
        server_version = "MMTVL-export"
        sys_version = ""
        protocol_version = "HTTP/1.0"

        def setup(self):
            self.deadline = owner.connection_deadline()
            owner.track(self.request, self.deadline)
            self.timeout = max(0.01, self.deadline - owner.clock())
            super().setup()

        def finish(self):
            try:
                super().finish()
            finally:
                owner.untrack(self.request)

        def do_GET(self):
            if owner.claim(self.client_address[0], self.path, self.deadline):
                try:
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(owner.body)))
                    self.send_header("Cache-Control", "no-store")
                    self.send_header("Connection", "close")
                    self.end_headers()
                    self.wfile.write(owner.body)
                    self.wfile.flush()
                finally:
                    owner.finished.set()
            else:
                self.send_error(404)

        def log_message(self, format, *args):  # never print a request line: it holds the secret
            pass

    return Handler


# --- the Roku ------------------------------------------------------------------------------------------------

def ecp_launch(roku_host, content, port=ECP_PORT):
    """Asks the Roku to open the sideloaded app with the contentId. Raises ExportError (host only).

    http.client: no proxy (an environment proxy would see the contentId), no redirect. A reply http.client can't
    read (http.client.HTTPException, e.g. a status line with escape characters) is an ExportError naming the host
    only: no reply text is ever printed (security L-2).
    """
    query = urllib.parse.urlencode({"contentId": content, "mediaType": "special"}, safe=":")
    connection = http.client.HTTPConnection(roku_host, port, timeout=HTTP_TIMEOUT)
    try:
        connection.request("POST", "/launch/dev?" + query, body=b"")
        status = connection.getresponse().status
    except http.client.HTTPException:
        raise ExportError("The Roku at %s sent a reply this script couldn't read." % roku_host) from None
    except (OSError, ValueError):
        raise ExportError("Couldn't reach the Roku at %s." % roku_host) from None
    finally:
        connection.close()
    if status == 403:
        raise ExportError("The Roku at %s refused (HTTP 403). On the Roku, allow control by mobile apps "
                          "(Settings > System > Advanced system settings > Control by mobile apps)." % roku_host)
    if status == 404:
        raise ExportError("The Roku at %s has no sideloaded app (HTTP 404). Sideload MMTVL Live TV first." % roku_host)
    if not 200 <= status < 300:
        raise ExportError("The Roku at %s didn't open the app (HTTP %d)." % (roku_host, status))


def parse_ssdp_response(data, source_ip):
    """The Roku's address from an SSDP answer: its LOCATION must be http://<source_ip>:8060/ on a private IPv4
    address, and it must name roku:ecp; else None."""
    try:
        text = data.decode("latin-1")
    except (AttributeError, UnicodeDecodeError):
        return None
    headers = {}
    for line in text.split("\r\n")[1:]:
        name, sep, value = line.partition(":")
        if sep:
            headers[name.strip().lower()] = value.strip()
    if "roku:ecp" not in headers.get("st", "").lower() and "roku:ecp" not in headers.get("usn", "").lower():
        return None
    try:
        location = urllib.parse.urlsplit(headers.get("location", ""))
        port = location.port
    except ValueError:
        return None
    if location.scheme != "http" or location.hostname != source_ip or port != ECP_PORT:
        return None
    return source_ip if private_ipv4(source_ip) else None


def discover_rokus(wait=SSDP_WAIT_SECONDS):
    """The private IPv4 addresses of the Rokus that answer an SSDP search for roku:ecp, in answer order."""
    search = ("M-SEARCH * HTTP/1.1\r\nHost: 239.255.255.250:1900\r\nMan: \"ssdp:discover\"\r\n"
              "ST: roku:ecp\r\nMX: 2\r\n\r\n").encode("ascii")
    found = []
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
        sock.sendto(search, SSDP_ADDRESS)
        deadline = time.monotonic() + wait
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            sock.settimeout(remaining)
            try:
                data, (address, _port) = sock.recvfrom(2048)
            except socket.timeout:
                break
            host = parse_ssdp_response(data, address)
            if host and host not in found:
                found.append(host)
    finally:
        sock.close()
    return found


def clean_name(text, limit=64):
    """Printable text only (no control or escape characters reach the terminal), at most limit characters."""
    cleaned = "".join(c for c in html.unescape(text) if c.isprintable()).strip()
    return cleaned[:limit]


def parse_device_info(xml_text):
    """('<name> (<model>)', serial suffix) from query/device-info: the name 'Roku' when it names none, the suffix the
    serial number's last 4 letters and digits, or "" (security M-1: the user compares it with the TV's)."""
    def field(tag):
        match = re.search(r"<%s>([^<]{0,200})</%s>" % (tag, tag), xml_text)
        return clean_name(match.group(1)) if match else ""
    name = field("user-device-name") or field("friendly-device-name") or field("default-device-name") or "Roku"
    model = field("model-name")
    if model and model != name:
        name = "%s (%s)" % (name, model)
    serial = "".join(c for c in field("serial-number") if c.isascii() and c.isalnum())
    return name, serial[-4:]


_STATUS_LINE = re.compile(rb"\AHTTP/1\.[01] ([0-9]{3})[ \r]")


def device_info(host, port=ECP_PORT, limit=DEVICE_INFO_SECONDS):
    """(name, serial suffix) of the Roku at host, or ('Roku', '') when it doesn't answer a readable 200 in time.

    A plain socket rather than http.client, so the whole exchange has one deadline (limit seconds; every receive
    waits only for the time left) and a trickled reply can't stall the script (security L-2). At most
    MAX_DEVICE_INFO_BYTES are read; the reply is only ever printed through clean_name.
    """
    fallback = ("Roku", "")
    deadline = time.monotonic() + limit
    request = ("GET /query/device-info HTTP/1.0\r\nHost: %s:%d\r\nConnection: close\r\n\r\n" % (host, port))
    try:
        sock = socket.create_connection((host, port), timeout=max(0.01, deadline - time.monotonic()))
    except (OSError, ValueError):
        return fallback
    data = b""
    try:
        sock.settimeout(max(0.01, deadline - time.monotonic()))
        sock.sendall(request.encode("ascii"))
        while len(data) < MAX_DEVICE_INFO_BYTES:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return fallback
            sock.settimeout(remaining)
            chunk = sock.recv(min(4096, MAX_DEVICE_INFO_BYTES - len(data)))
            if not chunk:
                break
            data += chunk
    except (OSError, ValueError):
        return fallback
    finally:
        sock.close()
    match = _STATUS_LINE.match(data)
    if not match or match.group(1) != b"200":
        return fallback
    head, sep, body = data.partition(b"\r\n\r\n")
    if not sep:
        return fallback
    return parse_device_info(body.decode("utf-8", "replace"))


def describe_roku(name, serial, host):
    """'Living Room (Roku Ultra) · serial …1A2B · 192.168.1.20' (the name already cleaned)."""
    suffix = ("…" + serial) if serial else "unknown"
    return "%s · serial %s · %s" % (name, suffix, host)


# Security M-1: any LAN host can answer SSDP as a Roku and copy a real one's name and serial, but not its address.
COMPARE_ADDRESS = ("Check the IP address against the TV: on the Roku, Settings > Network > About shows it. Use only "
                   "the entry with that address (the serial, from Settings > System > About, is extra information).\n")
LOOKALIKE_WARNING = ("Warning: two or more answers share a name or a serial, so at least one of them isn't your Roku. "
                     "Pick the entry whose IP address matches the TV's Settings > Network > About, or run the script "
                     "with --roku <that address>.\n")


def name_key(name):
    """A name as compared for lookalikes: NFKC and case folded (Cyrillic letters stay distinct; the serial check
    catches those)."""
    return unicodedata.normalize("NFKC", name).casefold()


def lookalikes(infos):
    """True when two entries share a name (name_key) or a non-empty serial suffix."""
    names = [name_key(name) for name, _ in infos]
    serials = [serial.casefold() for _, serial in infos if serial]
    return len(set(names)) < len(names) or len(set(serials)) < len(serials)


def choose_roku(hosts, infos, input_fn, out):
    """The host the user picks from the numbered list; None if they pick none. infos: host -> (name, serial)."""
    for index, host in enumerate(hosts, 1):
        name, serial = infos[host]
        out.write("  %d. %s\n" % (index, describe_roku(name, serial, host)))
    out.write(COMPARE_ADDRESS)
    if lookalikes([infos[host] for host in hosts]):
        out.write(LOOKALIKE_WARNING)
    while True:
        answer = input_fn("Choose a Roku (1-%d, or Return to stop): " % len(hosts)).strip()
        if answer == "":
            return None
        if answer.isdigit() and 1 <= int(answer) <= len(hosts):
            return hosts[int(answer) - 1]
        out.write("Type a number from the list.\n")


# --- main ------------------------------------------------------------------------------------------------------

class Network:
    """What main reaches outside the Mac with; tests replace these."""

    def __init__(self):
        self.discover = discover_rokus
        self.device_info = device_info
        self.local_address = local_address_for
        self.launch = ecp_launch
        # The address the server binds to, for this Mac's address on the Roku's network (tests bind to loopback).
        self.bind_address = lambda mac_ip: mac_ip
        # The address the one GET must come from, for the Roku's address (tests send it from loopback).
        self.allowed_client = lambda roku_host: roku_host


def main(argv=None, config_dir=CONFIG_DIR, keychain_reader=read_keychain, network=None, input_fn=input,
         lifetime=LIFETIME_SECONDS, out=None):
    out = out or sys.stdout
    network = network or Network()
    parser = argparse.ArgumentParser(description="Send MMTVL's Live TV settings to MMTVL Live TV on a Roku, once.")
    parser.add_argument("--dry-run", action="store_true", help="only show what would be sent (counts and hosts)")
    parser.add_argument("--roku", metavar="ADDRESS", help="the Roku's IPv4 address on this network (skips the search)")
    args = parser.parse_args(argv)

    if args.roku is not None and not private_ipv4(args.roku):
        out.write("Refusing %r: give the Roku's private IPv4 address on this network (10.x, 172.16-31.x or "
                  "192.168.x).\n" % clean_name(args.roku))
        return 1
    try:
        bundle, notes = build_bundle(config_dir, keychain_reader)
        body = encode_bundle(bundle)
        out.write("MMTVL Live TV settings to send:\n")
        for line in summary_lines(bundle, len(body)):
            out.write(line + "\n")
        for note in notes:
            out.write("Note: " + note + "\n")
        if len(body) > MAX_BUNDLE_BYTES:
            raise ExportError("These settings are %.1f KB, over the Roku's 64 KB. Remove some hidden channels, "
                              "favorites or guide matches in MMTVL and try again." % (len(body) / 1024.0))
        if args.dry_run:
            out.write("Dry run: nothing was sent.\n")
            return 0
        return _send(args, body, network, input_fn, lifetime, out)
    except ExportError as error:
        out.write(str(error) + "\n")
        return 1
    except KeyboardInterrupt:
        out.write("\nStopped; nothing was sent.\n")
        return 130


def _send(args, body, network, input_fn, lifetime, out):
    if args.roku is not None:
        roku = args.roku
        name, serial = network.device_info(roku)
        out.write("Roku: %s\n" % describe_roku(name, serial, roku))
        out.write(COMPARE_ADDRESS)
    else:
        out.write("Looking for Rokus on this network…\n")
        hosts = network.discover()
        if not hosts:
            raise ExportError("No Roku answered. Give its address with --roku <address> (on the Roku: Settings > "
                              "Network > About).")
        infos = {host: network.device_info(host) for host in hosts}
        roku = choose_roku(hosts, infos, input_fn, out)
        if roku is None:
            out.write("Nothing was sent.\n")
            return 0
    try:
        mac_ip = network.local_address(roku)
    except OSError:
        raise ExportError("This Mac has no route to the Roku at %s." % roku)
    if not private_ipv4(mac_ip):
        raise ExportError("This Mac's address toward the Roku (%s) isn't a private IPv4 address; the Roku only "
                          "imports from one." % mac_ip)
    secret = new_secret()
    try:
        server = OneShotServer(network.bind_address(mac_ip), body, secret, network.allowed_client(roku), lifetime)
    except OSError:
        raise ExportError("Couldn't open a port on %s." % mac_ip)
    content = content_id(mac_ip, server.port, secret)
    secret = None
    try:
        network.launch(roku, content)
    except BaseException:
        server.close()
        raise
    content = None
    out.write("Opened MMTVL Live TV on the Roku (%s); serving the settings from %s for up to %d minutes.\n"
              % (roku, mac_ip, max(1, int(lifetime // 60))))
    result = server.serve()
    if result == "served":
        out.write("The Roku has the settings. On the TV, choose Replace Settings to use them, or Cancel.\n")
        return 0
    out.write("The Roku didn't fetch the settings in time; nothing was sent. Run the script again.\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
