#!/bin/zsh
# MR: a public release of MMTVL, signed Developer ID, notarized and stapled.
#
# Bumps CURRENT_PROJECT_VERSION by 1 in all four configurations (project.pbxproj), like scripts/test-build.sh: the
# bumped number is never reused, even when a later stage fails. Then archives Release, exports it signed Developer ID
# (scripts/ExportOptions.plist; Sparkle's Autoupdate is first re-signed in the archive without its entitlement),
# checks the updater keys in the exported Info.plist (SUPublicEDKey = the login Keychain's key, signed feed, feed URL),
# the signature and the hardened runtime of the app and of every code item in it (each framework, nested app, XPC
# service, Mach-O and executable file under Contents, Sparkle's helpers included) and the entitlements of each (an
# exact list per item; scripts/release-checks.zsh), notarizes, staples, checks Gatekeeper's verdict, zips the app to
# build/release/MMTVL-<version>-build<N>.zip, printing its SHA-256 (for the release notes), and writes the signed
# Sparkle appcast build/release/appcast.xml for it (scripts/make-appcast.sh; the release tag is MMTVL_RELEASE_TAG,
# default v<version>; the EdDSA key is read from the login Keychain). Everything it makes is in build/release/ (logs
# too). The archive uses only the package versions in Package.resolved. The version (MARKETING_VERSION) is changed by
# hand. The bump is left uncommitted.
# It never tags, pushes or publishes anything: those steps are done by hand once the release is confirmed.
#
# Needs the "Developer ID Application" certificate of the team in ExportOptions.plist in the login keychain, and a
# notarytool keychain profile (default "mmtvl-notary"; another with NOTARY_PROFILE=<name>), saved once with
#   xcrun notarytool store-credentials mmtvl-notary --apple-id <Apple ID> --team-id <team>
# which asks for an app-specific password. Credentials stay in the Keychain; this script never reads or prints them.
#
# Refuses to run with uncommitted changes or when HEAD isn't on master. For dry runs only:
#   MMTVL_RELEASE_ALLOW_BRANCH=1   allow a branch other than master
#   MMTVL_RELEASE_ALLOW_DIRTY=1    allow uncommitted changes (the build is then not the committed state)
#
# Usage: scripts/release.sh            (from the repo root)
#        MMTVL_RELEASE_TAG=v1.4.0-update-test scripts/release.sh   (an appcast for another release tag)
set -euo pipefail

cd "$(dirname "$0")/.."
project=MMTVL.xcodeproj/project.pbxproj
export_options=scripts/ExportOptions.plist
out=build/release
archive=$out/MMTVL.xcarchive
app=$out/export/MMTVL.app
profile=${NOTARY_PROFILE:-mmtvl-notary}
sparkle_bin=build/SourcePackages/artifacts/sparkle/Sparkle/bin
# The checks on the archive and the exported app (check_app_code, check_updater_keys, strip_entitlements, …).
source scripts/release-checks.zsh

fail() { print -u2 -- "release.sh: $*"; exit 1; }

team=$(/usr/libexec/PlistBuddy -c 'Print teamID' "$export_options") || fail "Can't read teamID from ${export_options}."
# Checked before the bump, so a bad tag or version can't spend a build number and a notarization (make-appcast.sh
# checks them too). Release tags are v<version>… only (D58).
if [[ -n ${MMTVL_RELEASE_TAG:-} && ! $MMTVL_RELEASE_TAG =~ '^v[0-9][A-Za-z0-9._-]*$' ]]; then
    fail "Bad MMTVL_RELEASE_TAG: ${MMTVL_RELEASE_TAG} (a tag like v1.4.0 or v1.4.0-update-test)."
fi
marketing=$({ grep -o 'MARKETING_VERSION = [^;]*;' "$project" || true; } | sed 's/^MARKETING_VERSION = //; s/;$//' | sort -u)
[[ $marketing =~ '^[0-9]+(\.[0-9]+)*$' ]] || fail "MARKETING_VERSION must be one version like 1.4.0 in every" \
    "configuration; ${project} has: ${${marketing//$'\n'/, }:-none}"
check_source_updater_keys Config/Updater-Info.plist "$sparkle_bin"

# 1. Only the committed state of master is released.
branch=$(git symbolic-ref --quiet --short HEAD || echo "(detached HEAD)")
if [[ $branch != master ]]; then
    if [[ ${MMTVL_RELEASE_ALLOW_BRANCH:-} == 1 ]]; then
        echo "Dry run: HEAD is on ${branch}, not master (MMTVL_RELEASE_ALLOW_BRANCH=1)."
    else
        fail "HEAD is on ${branch}, not master. Releases are made from master (dry runs: MMTVL_RELEASE_ALLOW_BRANCH=1)."
    fi
fi
dirty=$(git status --porcelain)
if [[ -n $dirty ]]; then
    if [[ ${MMTVL_RELEASE_ALLOW_DIRTY:-} == 1 ]]; then
        echo "Dry run: building with uncommitted changes (MMTVL_RELEASE_ALLOW_DIRTY=1):"
        print -r -- "$dirty"
    else
        print -u2 -r -- "$dirty"
        fail "The working tree has uncommitted changes (listed above). Commit or stash them first."
    fi
fi

# 2. The next build number (the counter scripts/test-build.sh uses; never reset or reused).
current=$(grep -m1 -o 'CURRENT_PROJECT_VERSION = [0-9]*;' "$project" | grep -o '[0-9]*') \
    || fail "No CURRENT_PROJECT_VERSION in ${project}."
next=$((current + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = ${next};/" "$project"
bumped=1
on_exit() {
    local rc=$?
    if (( rc != 0 && ${bumped:-0} )); then
        print -u2 -- "Stopped; the build number stays ${next} (never reused). Commit project.pbxproj: Build ${next}"
    fi
}
trap on_exit EXIT

settings=$(xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -configuration Release -derivedDataPath build \
    -disableAutomaticPackageResolution -showBuildSettings 2>/dev/null) || fail "xcodebuild -showBuildSettings failed."
version=$(print -r -- "$settings" | awk -F' = ' '/^ *MARKETING_VERSION = / && v == "" { v = $2 } END { print v }')
build=$(print -r -- "$settings" | awk -F' = ' '/^ *CURRENT_PROJECT_VERSION = / && v == "" { v = $2 } END { print v }')
[[ -n $version ]] || fail "No MARKETING_VERSION in the Release build settings."
[[ $version == "$marketing" ]] || fail "The Release build settings say version ${version}, ${project} says ${marketing}."
[[ $build == "$next" ]] || fail "The Release build settings say build ${build}, expected ${next}."
echo "Releasing MMTVL ${version} build ${next} (team ${team}, notary profile ${profile})"

# 3. Archive and export, signed Developer ID.
rm -rf "$out"
mkdir -p "$out"

# -disableAutomaticPackageResolution: only the versions in Package.resolved; a mismatch fails the release (M15 N2).
echo "Archiving (log: ${out}/archive.log)…"
if ! xcodebuild -project MMTVL.xcodeproj -scheme MMTVL -configuration Release -derivedDataPath build \
    -disableAutomaticPackageResolution -archivePath "$archive" archive > "$out/archive.log" 2>&1; then
    grep -E ' error:' "$out/archive.log" || tail -20 "$out/archive.log"
    print -u2 -- "If the packages were never resolved here (no build/SourcePackages), resolve them once from Package.resolved:"
    print -u2 -- "  xcodebuild -resolvePackageDependencies -project MMTVL.xcodeproj -scheme MMTVL -derivedDataPath build" \
        "-disableAutomaticPackageResolution"
    fail "Archive failed (log: ${out}/archive.log)."
fi
resolved=MMTVL.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
git diff --quiet --exit-code -- "$resolved" \
    || fail "The archive changed ${resolved}; the release must use the pinned package versions (git diff -- ${resolved})."
[[ -x $sparkle_bin/sign_update ]] || fail "No ${sparkle_bin}/sign_update after the archive (make-appcast.sh needs it)."
[[ -x $sparkle_bin/generate_keys ]] || fail "No ${sparkle_bin}/generate_keys after the archive."

# Sparkle's Autoupdate ships with com.apple.application-identifier, a restricted entitlement AMFI can't validate
# without a provisioning profile (M15 step 5). Re-signed here without it; the export then signs it Developer ID.
archived_autoupdate=$archive/Products/Applications/MMTVL.app/$autoupdate
[[ -f $archived_autoupdate ]] || fail "No ${autoupdate} in the archive (has Sparkle's layout changed?)."
strip_entitlements "$archived_autoupdate" "the archive's Autoupdate"
echo "Autoupdate in the archive: re-signed ad hoc without entitlements (the export signs it Developer ID)"

echo "Exporting with Developer ID (log: ${out}/export.log)…"
if ! xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$export_options" \
    -exportPath "$out/export" -allowProvisioningUpdates > "$out/export.log" 2>&1; then
    grep -E 'error|errSec' "$out/export.log" || tail -20 "$out/export.log"
    if grep -q errSecInternalComponent "$out/export.log"; then
        print -u2 -- "codesign can't use the Developer ID private key without asking. Sign anything once in Terminal with"
        print -u2 -- "the Developer ID identity and answer Always Allow (or allow codesign in the key's Access Control)."
    fi
    fail "Export failed (log: ${out}/export.log)."
fi
[[ -d $app ]] || fail "The export has no MMTVL.app (log: ${out}/export.log)."

# 4. Checks before anything goes to Apple.
built=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist")
[[ $built == "$next" ]] || fail "The exported app says build ${built}, expected ${next}."
built_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
[[ $built_version == "$version" ]] || fail "The exported app says version ${built_version}, expected ${version}."
echo "Info.plist: version ${built_version}, build ${built}"
public_key=$(sparkle_public_key "$sparkle_bin") || exit 1
check_updater_keys "$app/Contents/Info.plist" "$public_key"
echo "Updater keys: SUPublicEDKey is the login Keychain's key, signed feed and verify before extraction on, ${feed_url}"

echo "codesign --verify --deep --strict:"
verify=$(codesign --verify --deep --strict --verbose=2 "$app" 2>&1) || { print -r -- "$verify"; fail "The signature doesn't verify."; }
print -r -- "$verify"

# Developer ID + runtime for every code item in the app; exact entitlements per item (release-checks.zsh).
check_app_code "$app"

# 5. Notarize (uploads the app to Apple's notary service) and staple.
ditto -c -k --keepParent "$app" "$out/notarize.zip"
echo "Notarizing (waits for Apple's answer)…"
started=$SECONDS
xcrun notarytool submit "$out/notarize.zip" --keychain-profile "$profile" --wait --output-format json \
    > "$out/notary.json" 2> "$out/notary.err" || true
took=$((SECONDS - started))
json_field() {
    python3 -I -c 'import json, sys
try:
    print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))
except Exception:
    print("")' "$out/notary.json" "$1"
}
submission=$(json_field id)
notary_status=$(json_field status)
echo "Notarization: id ${submission:-?}, status ${notary_status:-?}, $((took / 60)) min $((took % 60)) s"
if [[ $notary_status != Accepted ]]; then
    [[ -s $out/notary.err ]] && cat "$out/notary.err" >&2
    [[ -n $submission ]] && print -u2 -- "Why: xcrun notarytool log ${submission} --keychain-profile ${profile}"
    fail "Notarization wasn't accepted."
fi

xcrun stapler staple "$app" || fail "Stapling failed."
xcrun stapler validate "$app" || fail "The stapled ticket doesn't validate."
assessment=$(spctl -a -vvv -t exec "$app" 2>&1) || { print -r -- "$assessment"; fail "Gatekeeper rejects the app."; }
print -r -- "$assessment"
[[ $assessment == *"source=Notarized Developer ID"* ]] || fail "Gatekeeper doesn't say Notarized Developer ID."

# 6. The release zip (only the app; --sequesterRsrc as Sparkle's docs advise for update archives).
zip=$out/MMTVL-${version}-build${next}.zip
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
sha=$(shasum -a 256 "$zip" | awk '{ print $1 }')
echo
echo "Release zip: ${zip}"
echo "SHA-256: ${sha}"

# 7. The Sparkle appcast for that zip, always signed here (MMTVL_APPCAST_UNSIGNED is for the script's test only).
tag=${MMTVL_RELEASE_TAG:-v$version}
appcast=$out/appcast.xml
MMTVL_APPCAST_UNSIGNED= MMTVL_SPARKLE_BIN=$sparkle_bin \
    zsh scripts/make-appcast.sh "$zip" "$tag" "$version" "$next" "$appcast" \
    || fail "No appcast. The zip is ready; once fixed: MMTVL_APPCAST_UNSIGNED= MMTVL_SPARKLE_BIN=${sparkle_bin}" \
        "zsh scripts/make-appcast.sh ${zip} ${tag} ${version} ${next} ${appcast}"
echo "Appcast: ${appcast} (tag ${tag})"
echo "Not tagged, pushed or published. Commit project.pbxproj: Build ${next}"
