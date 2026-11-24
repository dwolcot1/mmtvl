#!/bin/zsh
# M15 step 5: tests scripts/release-checks.zsh (the checks scripts/release.sh runs on the archive and the export),
# with fixture plists, a fixture app bundle signed ad hoc in a temp dir, and stand-in generate_keys scripts.
#
#   zsh scripts/test_release_checks.sh
#
# Prints "release-checks: N checks passed", or each failed check and exits 1. Signs only files in its temp dir, ad hoc;
# never uses a signing identity or the Keychain.
set -euo pipefail

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { print -u2 -- "release.sh: $*"; exit 1; }
team=H846CY8RB4
source "${0:A:h}/release-checks.zsh"

passed=0 failed=0
check() {  # $1: description, $2: actual, $3: expected
    if [[ $2 == "$3" ]]; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        print -u2 -- "FAIL: $1: got \"$2\", expected \"$3\""
    fi
}
# Runs "$@" in a subshell (fail exits it); sets $rc and $err (its stderr) and $output (its stdout).
run() {
    rc=0
    output=$( ( "$@" ) 2> "$tmp/err" ) || rc=$?
    err=$(< "$tmp/err")
}

# --- check_updater_keys: fixture Info.plists -------------------------------------------------------------------
key=$(printf 'A%.0s' {1..43})=   # a made-up 44-character base64 key
other=$(printf 'B%.0s' {1..43})=
plist() {  # $1: file, then key type value triples (type: string, bool)
    local file=$1; shift
    plutil -create xml1 "$file"
    while (( $# >= 3 )); do plutil -insert "$1" "-$2" "$3" "$file"; shift 3; done
}
good=(SUPublicEDKey string "$key" SURequireSignedFeed bool YES SUVerifyUpdateBeforeExtraction bool YES
      SUFeedURL string "$feed_url")
plist "$tmp/good.plist" "${good[@]}"
run check_updater_keys "$tmp/good.plist" "$key"
check "good plist passes" "$rc" 0

plist "$tmp/other-key.plist" SUPublicEDKey string "$other" "${good[@]:3}"
run check_updater_keys "$tmp/other-key.plist" "$key"
check "another key fails" "$rc" 1
check "another key: says so" "$([[ $err == *"SUPublicEDKey is not the public key"* ]] && echo yes)" yes

plist "$tmp/no-key.plist" "${good[@]:3}"
run check_updater_keys "$tmp/no-key.plist" "$key"
check "no SUPublicEDKey fails" "$rc" 1
check "no SUPublicEDKey: points to step 4" "$([[ $err == *"no SUPublicEDKey"*"step 4"* ]] && echo yes)" yes

plist "$tmp/empty-key.plist" SUPublicEDKey string '' "${good[@]:3}"
run check_updater_keys "$tmp/empty-key.plist" "$key"
check "empty SUPublicEDKey fails" "$rc" 1

plist "$tmp/unsigned-feed.plist" SUPublicEDKey string "$key" SURequireSignedFeed bool NO \
    SUVerifyUpdateBeforeExtraction bool YES SUFeedURL string "$feed_url"
run check_updater_keys "$tmp/unsigned-feed.plist" "$key"
check "SURequireSignedFeed false fails" "$rc" 1
check "SURequireSignedFeed false: says so" "$([[ $err == *"SURequireSignedFeed is not true"* ]] && echo yes)" yes

plist "$tmp/string-true.plist" SUPublicEDKey string "$key" SURequireSignedFeed string true \
    SUVerifyUpdateBeforeExtraction bool YES SUFeedURL string "$feed_url"
run check_updater_keys "$tmp/string-true.plist" "$key"
check "SURequireSignedFeed as a string fails" "$rc" 1

plist "$tmp/no-verify.plist" SUPublicEDKey string "$key" SURequireSignedFeed bool YES SUFeedURL string "$feed_url"
run check_updater_keys "$tmp/no-verify.plist" "$key"
check "no SUVerifyUpdateBeforeExtraction fails" "$rc" 1
check "no SUVerifyUpdateBeforeExtraction: says so" \
    "$([[ $err == *"SUVerifyUpdateBeforeExtraction is not true"* ]] && echo yes)" yes

plist "$tmp/test-feed.plist" "${good[@]:0:9}" SUFeedURL string \
    https://github.com/dwolcot1/mmtvl/releases/download/v1.4.0-update-test/appcast.xml
run check_updater_keys "$tmp/test-feed.plist" "$key"
check "another feed URL fails" "$rc" 1
check "another feed URL: says so" "$([[ $err == *"SUFeedURL is not $feed_url"* ]] && echo yes)" yes

run check_updater_keys "$tmp/good.plist" not-a-key
check "a malformed expected key fails" "$rc" 1

run check_updater_keys "$tmp/missing.plist" "$key"
check "a missing plist fails" "$rc" 1

# --- sparkle_public_key: stand-in generate_keys ---------------------------------------------------------------
fake_keys() {  # $1: folder, $2: what generate_keys -p prints, $3: its exit status
    mkdir -p "$1"
    print -r -- "#!/bin/zsh
[[ \$1 == -p && \$# == 1 ]] || { echo 'called without -p'; exit 2; }
print -r -- '$2'
exit $3" > "$1/generate_keys"
    chmod +x "$1/generate_keys"
}
fake_keys "$tmp/keys-ok" "$key" 0
run sparkle_public_key "$tmp/keys-ok"
check "public key: printed" "$rc $output" "0 $key"
fake_keys "$tmp/keys-none" "ERROR: No existing signing key found!" 1
run sparkle_public_key "$tmp/keys-none"
check "no key in the Keychain fails" "$rc" 1
check "no key: points to step 4" "$([[ $err == *"No existing signing key found"*"step 4"* ]] && echo yes)" yes
fake_keys "$tmp/keys-junk" "something else" 0
run sparkle_public_key "$tmp/keys-junk"
check "not a key fails" "$rc" 1

# --- check_source_updater_keys: the pre-bump check on Config/Updater-Info.plist ---------------------------------
run check_updater_keys "$tmp/good.plist" -
check "'-' (not compared) on a good plist passes" "$rc" 0
run check_updater_keys "$tmp/good.plist" ''
check "an empty expected key fails" "$rc" 1
plist "$tmp/short-key.plist" SUPublicEDKey string short "${good[@]:3}"
run check_updater_keys "$tmp/short-key.plist" -
check "'-' still refuses a malformed SUPublicEDKey" "$rc" 1

# The real source plist without its key (as it is until step 4), so this keeps working once the key is in.
source_plist=${0:A:h:h}/Config/Updater-Info.plist
cp "$source_plist" "$tmp/source-no-key.plist"
/usr/libexec/PlistBuddy -c 'Delete SUPublicEDKey' "$tmp/source-no-key.plist" 2> /dev/null || true
run check_source_updater_keys "$tmp/source-no-key.plist" "$tmp/no-tools"
check "source plist without a key, no tools: fails" "$rc" 1
check "source plist without a key: step 4, no build number spent" \
    "$([[ $err == *"no SUPublicEDKey"*"step 4"*"No build number was spent"* ]] && echo yes)" yes
run check_source_updater_keys "$tmp/source-no-key.plist" "$tmp/keys-ok"
check "source plist without a key, with the Keychain's key: fails" "$rc" 1
cp "$source_plist" "$tmp/source-with-key.plist"
/usr/libexec/PlistBuddy -c 'Delete SUPublicEDKey' "$tmp/source-with-key.plist" 2> /dev/null || true
/usr/libexec/PlistBuddy -c "Add SUPublicEDKey string $key" "$tmp/source-with-key.plist"
run check_source_updater_keys "$tmp/source-with-key.plist" "$tmp/no-tools"
check "the real source plist with a key, no tools: passes" "$rc" 0
check "no tools: says the comparison comes after the archive" \
    "$([[ $output == *"compared with the login Keychain's key after the archive"* ]] && echo yes)" yes
run check_source_updater_keys "$tmp/source-with-key.plist" "$tmp/keys-ok"
check "the real source plist with the Keychain's key: passes" "$rc" 0
run check_source_updater_keys "$tmp/other-key.plist" "$tmp/keys-ok"
check "another key than the Keychain's: fails" "$rc" 1
run check_source_updater_keys "$tmp/source-with-key.plist" "$tmp/keys-none"
check "no key in the Keychain: fails" "$rc" 1
run check_source_updater_keys "$tmp/unsigned-feed.plist" "$tmp/no-tools"
check "SURequireSignedFeed false, no tools: fails" "$rc" 1
# In release.sh the pre-bump check runs before the build number is bumped and before the archive.
release=${0:A:h}/release.sh
line_of() { grep -n -m1 -F -- "$1" "$release" | cut -d: -f1; }
pre=$(line_of 'check_source_updater_keys Config/Updater-Info.plist')
bump=$(line_of "sed -i '' \"s/CURRENT_PROJECT_VERSION")
archive_line=$(line_of '-archivePath "$archive" archive')
check "release.sh: the pre-bump check comes before the bump and the archive" \
    "$([[ -n $pre && -n $bump && -n $archive_line ]] && (( pre < bump && bump < archive_line )) && echo yes)" yes

# --- code_items: a fixture app ---------------------------------------------------------------------------------
app=$tmp/Fixture.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks/Lib.framework/Versions/A"
plist "$app/Contents/Info.plist" CFBundleExecutable string Fixture CFBundleIdentifier string test.fixture
cp /usr/bin/true "$app/Contents/MacOS/Fixture"
cp /usr/bin/true "$app/Contents/Resources/tool"
cp /usr/bin/true "$app/Contents/.hidden"
cp /usr/bin/true "$app/Contents/Frameworks/Lib.framework/Versions/A/Lib"
ln -s Versions/A/Lib "$app/Contents/Frameworks/Lib.framework/Lib"
ln -s A "$app/Contents/Frameworks/Lib.framework/Versions/Current"
print -r -- '#!/bin/sh' > "$app/Contents/Resources/run.sh"
chmod +x "$app/Contents/Resources/run.sh"
print -r -- "data" > "$app/Contents/Resources/data.txt"
run code_items "$app"
listed=$(print -r -- "$output" | sed "s|^$app/||" | sort)
expected=$(print -l Contents/.hidden Contents/Frameworks/Lib.framework Contents/Frameworks/Lib.framework/Versions/A/Lib \
    Contents/Resources/run.sh Contents/Resources/tool | sort)
check "code_items: rc" "$rc" 0
check "code_items: a dotfile Mach-O, a Resources Mach-O, the framework, a script; not the main executable, data or links" \
    "$listed" "$expected"

# --- check_entitlements, strip_entitlements, check_signature: ad hoc signatures in the temp dir ----------------
entitlements() {  # $1: file, $2: true or false
    print -r -- "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\"><dict><key>com.apple.security.automation.apple-events</key><$2/></dict></plist>" > "$1"
}
entitlements "$tmp/false.plist" false
entitlements "$tmp/true.plist" true
bin=$tmp/bin
mkdir -p "$bin"
cp /usr/bin/true "$bin/events-false"
cp /usr/bin/true "$bin/events-true"
cp /usr/bin/true "$bin/none"
codesign --force --sign - -o runtime --entitlements "$tmp/false.plist" "$bin/events-false" 2> /dev/null
codesign --force --sign - -o runtime --entitlements "$tmp/true.plist" "$bin/events-true" 2> /dev/null
codesign --force --sign - -o runtime "$bin/none" 2> /dev/null

run check_entitlements "$bin/events-true" app "${app_entitlements[@]}"
check "apple-events=True passes" "$rc" 0
run check_entitlements "$bin/events-false" app "${app_entitlements[@]}"
check "apple-events=False fails" "$rc" 1
run check_entitlements "$bin/none" app "${app_entitlements[@]}"
check "the app without entitlements fails" "$rc" 1
run check_entitlements "$bin/none" item
check "an item without entitlements passes" "$rc" 0
run check_entitlements "$bin/events-true" item
check "an item with an entitlement fails" "$rc" 1

cp /usr/bin/true "$bin/autoupdate"
codesign --force --sign - -o runtime -i test.fixture.Autoupdate --entitlements "$tmp/true.plist" "$bin/autoupdate" \
    2> /dev/null
run strip_entitlements "$bin/autoupdate" Autoupdate
check "strip_entitlements: rc" "$rc" 0
check "strip_entitlements: no entitlements left" "$(entitlements_of "$bin/autoupdate" Autoupdate)" ""
info=$(codesign -dvv "$bin/autoupdate" 2>&1)
check "strip_entitlements: identifier kept" "$([[ $info == *$'\n'Identifier=test.fixture.Autoupdate$'\n'* ]] && echo yes)" yes
check "strip_entitlements: hardened runtime" "$([[ $info == *'flags=0x10002(adhoc,runtime)'* ]] && echo yes)" yes

run check_signature "$bin/none" none
check "check_signature: ad hoc fails" "$rc" 1
check "check_signature: says not Developer ID" "$([[ $err == *"not Developer ID Application (${team})"* ]] && echo yes)" yes
run check_app_code "$app"
check "check_app_code: an unsigned app fails" "$rc" 1

if (( failed )); then
    print -u2 -- "release-checks: ${failed} of $((passed + failed)) checks failed"
    exit 1
fi
echo "release-checks: ${passed} checks passed"
