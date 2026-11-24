# M15 step 5: the checks scripts/release.sh runs on the archive and the exported app, sourced by it and by
# scripts/test_release_checks.sh. Defines functions and constants only. The caller defines fail() (prints its
# arguments and exits 1) and, for check_signature and check_app_code, $team (the Developer ID team).

# The app's own entitlements, as key=value (values too: apple-events=False fails).
app_entitlements=("com.apple.security.automation.apple-events=True")
# The only feed MMTVL reads (Config/Updater-Info.plist).
feed_url=https://github.com/dwolcot1/mmtvl/releases/latest/download/appcast.xml
# Sparkle's installer, relative to the app. It ships with com.apple.application-identifier, a restricted entitlement
# AMFI can't validate without a provisioning profile; release.sh strips it in the archive (strip_entitlements).
autoupdate=Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate

# Developer ID Application of the team, with the hardened runtime. $1: path, $2: name in messages.
check_signature() {
    local info line authority='' team_ok=0 runtime=0 flags=''
    info=$(codesign -dvv "$1" 2>&1) || fail "codesign can't read the signature of $2."
    for line in "${(@f)info}"; do
        if [[ -z $authority && $line == Authority=* ]]; then authority=${line#Authority=}; fi
        if [[ $line == "TeamIdentifier=${team}" ]]; then team_ok=1; fi
        if [[ $line == CodeDirectory* && $line =~ 'flags=0x[0-9a-f]+\(([a-z-]+,)*runtime(,[a-z-]+)*\)' ]]; then
            runtime=1
            flags=${MATCH}
        fi
    done
    [[ $authority == "Developer ID Application: "*"(${team})" ]] \
        || fail "$2 is signed by \"${authority:-nobody}\", not Developer ID Application (${team})."
    (( team_ok )) || fail "$2 isn't signed with TeamIdentifier=${team}."
    (( runtime )) || fail "$2 doesn't have the hardened runtime (flags runtime)."
    echo "  $2: Authority=${authority}, TeamIdentifier=${team}, ${flags}"
}

# The entitlements of $1 as sorted key=value lines (nothing: none). $2: name in messages.
entitlements_of() {
    local xml
    xml=$(codesign -d --entitlements - --xml "$1" 2>/dev/null) || fail "codesign can't read the entitlements of $2."
    print -rn -- "$xml" | python3 -I -c '
import plistlib, sys
data = sys.stdin.buffer.read()
for key, value in sorted((plistlib.loads(data) if data.strip() else {}).items()):
    print(f"{key}={value!r}")
' || fail "Can't parse the entitlements of $2."
}

# $1 must have exactly the entitlements $3… (key=value lines; none when none are given). $2: name in messages.
# Prints the entitlements it has, one "  <name>: key=value" line each.
check_entitlements() {
    local got want shown
    got=$(entitlements_of "$1" "$2") || exit 1
    want=''
    if (( $# > 2 )); then want=$(print -l -- "${@:3}" | sort); fi
    if [[ -n $got ]]; then print -r -- "$got" | sed "s|^|  $2: |"; fi
    if [[ $got != "$want" ]]; then
        shown=${got//$'\n'/, }
        want=${want//$'\n'/, }
        fail "$2 must have ${want:-no entitlements}; it has: ${shown:-none}"
    fi
}

# Every code item in the app except its main executable (check_signature "$app" covers that), one path per line:
# each .framework, .app and .xpc bundle, each Mach-O file and each other executable file (a script must be signed
# too), anywhere under Contents, dotfiles included. ** doesn't follow symlinks, so Versions/Current and a
# framework's top-level links aren't listed twice.
code_items() {
    local app=$1 main f
    local -a items
    main=$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$app/Contents/Info.plist" 2>/dev/null) \
        || fail "No CFBundleExecutable in ${app:t}/Contents/Info.plist."
    items=("$app"/Contents/**/*.framework(ND/) "$app"/Contents/**/*.app(ND/) "$app"/Contents/**/*.xpc(ND/))
    for f in "$app"/Contents/**/*(ND.); do
        [[ $f == "$app/Contents/MacOS/$main" ]] && continue
        if [[ -x $f || $(file -b "$f") == *Mach-O* ]]; then items+=("$f"); fi
    done
    if (( ${#items} )); then print -rl -- "${items[@]}"; fi
}

# The exported app's code: Developer ID + runtime for the app and every item code_items lists; the app's
# entitlements exactly $app_entitlements, every other item none. $1: the app.
check_app_code() {
    local app=$1 list item
    local -a items
    list=$(code_items "$app") || exit 1
    items=(${(f)list})
    echo "Signatures:"
    check_signature "$app" "${app:t}"
    for item in "${items[@]}"; do
        check_signature "$item" "${item#$app/}"
    done
    echo "  $(( ${#items} + 1 )) code items checked"
    echo "Entitlements:"
    check_entitlements "$app" "${app:t}" "${app_entitlements[@]}"
    for item in "${items[@]}"; do
        check_entitlements "$item" "${item#$app/}"
    done
    echo "  the other ${#items} code items: none"
}

# Re-signs the Mach-O $1 ad hoc with the hardened runtime and its own identifier, and no entitlements (never --deep).
# Used on the archive's Autoupdate before the export, which then signs it Developer ID. $2: name in messages.
strip_entitlements() {
    local log
    log=$(codesign --force --sign - -o runtime --preserve-metadata=identifier "$1" 2>&1) \
        || { print -u2 -r -- "$log"; fail "codesign couldn't re-sign $2."; }
    check_entitlements "$1" "$2"
}

# Prints the public EdDSA key of the login Keychain's Sparkle key: generate_keys -p prints only the public key (it
# never creates a key). $1: Sparkle's bin folder.
sparkle_public_key() {
    local key
    key=$("$1/generate_keys" -p 2>&1) || fail "No Sparkle EdDSA key in the login Keychain (generate_keys -p:" \
        "${key//$'\n'/ }). Do step 4 of docs/plans/M15-software-updates.md first (generate_keys, backup, public key)."
    [[ $key =~ '^[A-Za-z0-9+/]{43}=$' ]] || fail "generate_keys -p didn't print a public key."
    print -r -- "$key"
}

# The updater keys in the Info.plist $1: SUPublicEDKey equal to $2 (the Keychain's public key; "-": a well-formed key,
# not compared, for the pre-bump check before Sparkle's tools exist), SURequireSignedFeed and
# SUVerifyUpdateBeforeExtraction true, SUFeedURL exactly $feed_url. Fails with every problem found.
check_updater_keys() {
    local problems
    problems=$(python3 -I -c '
import plistlib, re, sys
path, expected, feed = sys.argv[1:4]
with open(path, "rb") as f:
    info = plistlib.load(f)
edkey = r"[A-Za-z0-9+/]{43}="
if expected != "-" and not re.fullmatch(edkey, expected):
    print("the expected public key is not a 44-character base64 EdDSA key")
key = info.get("SUPublicEDKey")
if not isinstance(key, str) or not key:
    print("there is no SUPublicEDKey (until step 4 of docs/plans/M15-software-updates.md puts the public key in"
          " Config/Updater-Info.plist, every release stops here)")
elif not re.fullmatch(edkey, key):
    print("SUPublicEDKey is not a 44-character base64 EdDSA key")
elif expected != "-" and key != expected:
    print("SUPublicEDKey is not the public key of the Sparkle key in the login Keychain (generate_keys -p)")
for name in ("SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction"):
    if info.get(name) is not True:
        print(f"{name} is not true")
if info.get("SUFeedURL") != feed:
    print(f"SUFeedURL is not {feed}")
' "$1" "$2" "$feed_url") || fail "Can't read the Info.plist ${1}."
    [[ -z $problems ]] || fail "The updater keys in ${1:t} are wrong: ${problems//$'\n'/; }."
}

# Before the bump, so a missing or wrong key spends no build number: the source plist $1 (Config/Updater-Info.plist)
# must have SUPublicEDKey (read with PlistBuddy) and the other updater keys (check_updater_keys). SUPublicEDKey is
# compared with the login Keychain's key when Sparkle's tools are in $2; before the first resolve they aren't, and the
# comparison runs only after the export (on the exported Info.plist, which is what ships).
check_source_updater_keys() {
    local plist=$1 bin=$2 key
    /usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$plist" > /dev/null 2>&1 \
        || fail "${plist} has no SUPublicEDKey: do step 4 of docs/plans/M15-software-updates.md first (put the" \
            "public key from generate_keys -p there). No build number was spent."
    if [[ -x $bin/generate_keys ]]; then
        key=$(sparkle_public_key "$bin") || exit 1
        check_updater_keys "$plist" "$key"
        echo "Updater keys in ${plist}: SUPublicEDKey is the login Keychain's key; signed feed, verify before" \
            "extraction, ${feed_url}"
    else
        check_updater_keys "$plist" -
        echo "Updater keys in ${plist}: signed feed, verify before extraction, ${feed_url}; SUPublicEDKey is compared" \
            "with the login Keychain's key after the archive (no ${bin}/generate_keys yet)"
    fi
}
