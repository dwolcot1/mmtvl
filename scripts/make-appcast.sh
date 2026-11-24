#!/bin/zsh
# M15 step 5 (L9, L10): writes MMTVL's one-item Sparkle appcast for a release zip, and signs it.
#
#   scripts/make-appcast.sh <zip> <tag> <version> <build> <out.xml>
#
# The item: title "MMTVL <version>", pubDate (now, RFC 822), sparkle:version = <build> (CFBundleVersion),
# sparkle:shortVersionString = <version>, sparkle:minimumSystemVersion 26.0.0, a link to the release page
# (https://github.com/dwolcot1/mmtvl/releases/tag/<tag>) and the enclosure
# https://github.com/dwolcot1/mmtvl/releases/download/<tag>/<zip name>, with its length and sparkle:edSignature from
# Sparkle's sign_update. Then sign_update signs the feed itself (SURequireSignedFeed). No release notes (no
# description, no releaseNotesLink: L10), no deltas (L9), and only a .zip (never a .pkg or .dmg, and never
# sparkle:installationType: GHSA-gcjm-h3jh-p2vc, N5), holding MMTVL.app with that version and build, and only a
# v<version>… tag (D58). Checks: xmllint --noout, sign_update --verify on the zip and the feed. The private key is
# read from the login Keychain by sign_update; this script never reads or prints it.
#
# The tools: MMTVL_SPARKLE_BIN, else build/SourcePackages/artifacts/sparkle/Sparkle/bin (the derived data that
# scripts/release.sh archives with, -derivedDataPath build).
# MMTVL_APPCAST_UNSIGNED=1 skips both signatures and their checks, for scripts/test_make_appcast.sh only.
set -euo pipefail

fail() { print -u2 -- "make-appcast.sh: $*"; exit 1; }

(( $# == 5 )) || fail "usage: make-appcast.sh <zip> <tag> <version> <build> <out.xml>"
zip=$1 tag=$2 version=$3 build=$4 out=$5
repo=https://github.com/dwolcot1/mmtvl
unsigned=${MMTVL_APPCAST_UNSIGNED:-}
bin=${MMTVL_SPARKLE_BIN:-"${0:A:h:h}/build/SourcePackages/artifacts/sparkle/Sparkle/bin"}

# Every value that goes into the XML is checked against a plain pattern, so nothing needs escaping.
name=${zip:t}
[[ $name == *.zip ]] || fail "${name} isn't a .zip (only zip updates are published)."
[[ $name =~ '^[A-Za-z0-9._-]+$' ]] || fail "The zip's name may only have letters, digits, '.', '_' and '-'."
[[ -f $zip ]] || fail "No such file: ${zip}"
magic=$(head -c 4 "$zip" | xxd -p)
[[ $magic == 504b0304 ]] || fail "${name} isn't a zip archive."
[[ $tag =~ '^v[0-9][A-Za-z0-9._-]*$' ]] || fail "Bad tag: ${tag} (release tags are v<version>…, D58)."
[[ $version =~ '^[0-9]+(\.[0-9]+)*$' ]] || fail "Bad version: ${version}"
[[ $build =~ '^[0-9]+$' ]] || fail "Bad build number: ${build}"
[[ $out == *.xml ]] || fail "The appcast must be an .xml file (sign_update signs feeds by their extension)."
[[ -d ${out:h} ]] || fail "No such directory: ${out:h}"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The zip must hold the app the item describes: its CFBundleVersion and CFBundleShortVersionString.
unzip -p "$zip" MMTVL.app/Contents/Info.plist > "$tmp/Info.plist" 2> /dev/null && [[ -s $tmp/Info.plist ]] \
    || fail "${name} has no MMTVL.app/Contents/Info.plist."
zip_build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$tmp/Info.plist" 2> /dev/null) || zip_build=''
zip_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$tmp/Info.plist" 2> /dev/null) \
    || zip_version=''
[[ $zip_build == "$build" ]] || fail "${name} holds build ${zip_build:-?}, not ${build}."
[[ $zip_version == "$version" ]] || fail "${name} holds version ${zip_version:-?}, not ${version}."

length=$(stat -f %z "$zip")
signature=''
if [[ $unsigned == 1 ]]; then
    print -u2 -- "make-appcast.sh: MMTVL_APPCAST_UNSIGNED=1, the appcast and the zip are NOT signed (tests only)."
else
    [[ -x $bin/sign_update ]] || fail "No sign_update in ${bin} (set MMTVL_SPARKLE_BIN, or resolve the packages)."
    # Prints: sparkle:edSignature="<base64>" length="<bytes>"
    signed=$("$bin/sign_update" "$zip") || fail "sign_update couldn't sign ${name}."
    if [[ $signed =~ 'sparkle:edSignature="([A-Za-z0-9+/=]+)" length="([0-9]+)"' ]]; then
        signature=${match[1]}
        [[ ${match[2]} == "$length" ]] || fail "sign_update says length ${match[2]}, the file has ${length} bytes."
    else
        fail "Can't read sign_update's output."
    fi
    "$bin/sign_update" --verify "$zip" "$signature" > /dev/null || fail "The zip's signature doesn't verify."
fi

pub_date=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')
enclosure_signature=''
[[ -n $signature ]] && enclosure_signature=" sparkle:edSignature=\"${signature}\""

feed=$tmp/appcast.xml
cat > "$feed" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>MMTVL</title>
        <link>${repo}/releases</link>
        <item>
            <title>MMTVL ${version}</title>
            <link>${repo}/releases/tag/${tag}</link>
            <pubDate>${pub_date}</pubDate>
            <sparkle:version>${build}</sparkle:version>
            <sparkle:shortVersionString>${version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>26.0.0</sparkle:minimumSystemVersion>
            <enclosure url="${repo}/releases/download/${tag}/${name}" length="${length}" type="application/octet-stream"${enclosure_signature}/>
        </item>
    </channel>
</rss>
EOF

if [[ $unsigned != 1 ]]; then
    # Appends the feed's signature as a <!-- sparkle-signatures: … --> comment.
    "$bin/sign_update" "$feed" > /dev/null || fail "sign_update couldn't sign the appcast."
    "$bin/sign_update" --verify "$feed" > /dev/null || fail "The appcast's signature doesn't verify."
fi
xmllint --noout "$feed" || fail "The appcast isn't well-formed XML."
mv "$feed" "$out"
echo "make-appcast: ${out} (MMTVL ${version} build ${build}, ${name}, ${length} bytes$([[ $unsigned == 1 ]] && print -n ', UNSIGNED'))"
