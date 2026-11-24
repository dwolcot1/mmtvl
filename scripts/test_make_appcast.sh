#!/bin/zsh
# M15 step 5: tests scripts/make-appcast.sh, unsigned (MMTVL_APPCAST_UNSIGNED=1), on a dummy zip in a temp dir.
#
#   zsh scripts/test_make_appcast.sh
#
# Prints "make-appcast: N checks passed", or each failed check and exits 1.
set -euo pipefail

script=${0:A:h}/make-appcast.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MMTVL_APPCAST_UNSIGNED=1

passed=0 failed=0
check() {  # $1: description, $2: actual, $3: expected
    if [[ $2 == "$3" ]]; then
        passed=$((passed + 1))
    else
        failed=$((failed + 1))
        print -u2 -- "FAIL: $1: got \"$2\", expected \"$3\""
    fi
}
xpath() { xmllint --xpath "$1" "$feed" 2>/dev/null || true; }

# A real zip, like release.sh makes (ditto), of a dummy app whose Info.plist says 1.4.0 build 45.
mkdir -p "$tmp/src/MMTVL.app/Contents"
plutil -create xml1 "$tmp/src/MMTVL.app/Contents/Info.plist"
plutil -insert CFBundleVersion -string 45 "$tmp/src/MMTVL.app/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string 1.4.0 "$tmp/src/MMTVL.app/Contents/Info.plist"
zip=$tmp/MMTVL-1.4.0-build45.zip
ditto -c -k --sequesterRsrc --keepParent "$tmp/src/MMTVL.app" "$zip"
size=$(stat -f %z "$zip")
feed=$tmp/appcast.xml

rc=0
zsh "$script" "$zip" v1.4.0 1.4.0 45 "$feed" > "$tmp/out.txt" 2> "$tmp/err.txt" || rc=$?
check "runs unsigned" "$rc" 0
check "well-formed" "$(xmllint --noout "$feed" > /dev/null 2>&1 && echo ok)" ok
check "one item" "$(xpath 'count(/rss/channel/item)')" 1
check "title" "$(xpath 'string(/rss/channel/item/title)')" "MMTVL 1.4.0"
check "version (build)" "$(xpath 'string(/rss/channel/item/*[local-name()="version"])')" 45
check "shortVersionString" "$(xpath 'string(/rss/channel/item/*[local-name()="shortVersionString"])')" 1.4.0
check "minimumSystemVersion" "$(xpath 'string(/rss/channel/item/*[local-name()="minimumSystemVersion"])')" 26.0.0
check "link" "$(xpath 'string(/rss/channel/item/link)')" "https://github.com/dwolcot1/mmtvl/releases/tag/v1.4.0"
check "enclosure url" "$(xpath 'string(/rss/channel/item/enclosure/@url)')" \
    "https://github.com/dwolcot1/mmtvl/releases/download/v1.4.0/MMTVL-1.4.0-build45.zip"
check "enclosure length = file size" "$(xpath 'string(/rss/channel/item/enclosure/@length)')" "$size"
check "enclosure type" "$(xpath 'string(/rss/channel/item/enclosure/@type)')" application/octet-stream
check "unsigned: no edSignature" "$(xpath 'count(//@*[local-name()="edSignature"])')" 0
check "unsigned: no feed signature" "$(grep -c 'sparkle-signatures' "$feed" || true)" 0
check "the sparkle namespace" "$(xpath 'namespace-uri(/rss/channel/item/*[local-name()="version"])')" \
    "http://www.andymatuschak.org/xml-namespaces/sparkle"
check "pubDate is RFC 822" \
    "$([[ $(xpath 'string(/rss/channel/item/pubDate)') =~ '^[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} \+0000$' ]] && echo ok)" ok
check "no description" "$(xpath 'count(//description)')" 0
check "no releaseNotesLink" "$(xpath 'count(//*[local-name()="releaseNotesLink" or local-name()="fullReleaseNotesLink"])')" 0
check "no installationType" "$(grep -c 'installationType' "$feed" || true)" 0
check "no deltas" "$(xpath 'count(//*[local-name()="deltas"])')" 0
check "says it's unsigned" "$(grep -c 'NOT signed' "$tmp/err.txt" || true)" 1

# Another tag (MMTVL_RELEASE_TAG in release.sh) changes only the link and the enclosure's folder.
zsh "$script" "$zip" v1.4.0-update-test 1.4.0 45 "$feed" > /dev/null 2>&1
check "test tag: link" "$(xpath 'string(/rss/channel/item/link)')" \
    "https://github.com/dwolcot1/mmtvl/releases/tag/v1.4.0-update-test"
check "test tag: enclosure url" "$(xpath 'string(/rss/channel/item/enclosure/@url)')" \
    "https://github.com/dwolcot1/mmtvl/releases/download/v1.4.0-update-test/MMTVL-1.4.0-build45.zip"

# Refusals (N5: zip only), each leaving no feed behind.
refuses() {  # $1: description, then make-appcast's arguments
    local what=$1; shift
    rm -f "$tmp/refused.xml"
    if zsh "$script" "$@" > /dev/null 2>&1; then
        check "$what: refused" accepted refused
    else
        check "$what: refused" refused refused
    fi
    check "$what: no feed written" "$([[ -e $tmp/refused.xml ]] && echo written || echo none)" none
}
mkdir -p "$tmp/bare/MMTVL.app/Contents"
print -r -- "no Info.plist" > "$tmp/bare/MMTVL.app/Contents/README"
ditto -c -k --sequesterRsrc --keepParent "$tmp/bare/MMTVL.app" "$tmp/bare.zip"
cp "$zip" "$tmp/MMTVL-1.4.0-build45.pkg"
cp "$zip" "$tmp/MMTVL-1.4.0-build45.dmg"
print -r -- "not a zip" > "$tmp/fake.zip"
refuses ".pkg" "$tmp/MMTVL-1.4.0-build45.pkg" v1.4.0 1.4.0 45 "$tmp/refused.xml"
refuses ".dmg" "$tmp/MMTVL-1.4.0-build45.dmg" v1.4.0 1.4.0 45 "$tmp/refused.xml"
refuses "a .zip that isn't a zip" "$tmp/fake.zip" v1.4.0 1.4.0 45 "$tmp/refused.xml"
refuses "a missing zip" "$tmp/missing.zip" v1.4.0 1.4.0 45 "$tmp/refused.xml"
refuses "a bad version" "$zip" v1.4.0 '1.4.0<x>' 45 "$tmp/refused.xml"
refuses "a bad build" "$zip" v1.4.0 1.4.0 45a "$tmp/refused.xml"
refuses "a bad tag" "$zip" 'v1.4.0"/>' 1.4.0 45 "$tmp/refused.xml"
refuses "a tag without v" "$zip" 1.4.0 1.4.0 45 "$tmp/refused.xml"
refuses "a Roku tag" "$zip" roku-v0.1-build6 1.4.0 45 "$tmp/refused.xml"
refuses "the zip holds another build" "$zip" v1.4.0 1.4.0 46 "$tmp/refused.xml"
refuses "the zip holds another version" "$zip" v1.4.1 1.4.1 45 "$tmp/refused.xml"
refuses "a zip without MMTVL.app's Info.plist" "$tmp/bare.zip" v1.4.0 1.4.0 45 "$tmp/refused.xml"
refuses "too few arguments" "$zip" v1.4.0 1.4.0 45

# Signed mode without the tools fails before writing anything.
rm -f "$tmp/refused.xml"
if MMTVL_APPCAST_UNSIGNED= MMTVL_SPARKLE_BIN=$tmp/no-such-bin zsh "$script" "$zip" v1.4.0 1.4.0 45 "$tmp/refused.xml" \
    > /dev/null 2>&1; then
    check "signed without sign_update: refused" accepted refused
else
    check "signed without sign_update: refused" refused refused
fi
check "signed without sign_update: no feed written" "$([[ -e $tmp/refused.xml ]] && echo written || echo none)" none

if (( failed )); then
    print -u2 -- "make-appcast: ${failed} of $((passed + failed)) checks failed"
    exit 1
fi
echo "make-appcast: ${passed} checks passed"
