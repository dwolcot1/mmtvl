#!/bin/zsh
# Installs a test build on the Mac mini over SSH and relaunches MMTVL there.
#
# Copies the zip from scripts/test-build.sh (default: the newest ~/Desktop/MMTVL-*-build*.zip) to the mini's
# ~/Downloads, unzips and checks it there (signature, build number), stops the running MMTVL, replaces
# /Applications/MMTVL.app and opens it. Afterwards only the last 3 builds' zips are kept, on the mini (~/Downloads)
# and on this Mac (~/Desktop); older ones are deleted. The zips on the mini are what --rollback installs.
#
# Usage (from the repo root):
#   scripts/deploy-mm.sh                 the newest build zip on the Desktop
#   scripts/deploy-mm.sh <zip>           a given zip
#   scripts/deploy-mm.sh --rollback      install the newest kept build older than the installed one
#
# Needs SSH key login to the mini (Remote Login on). The mini is the host alias "mm" in ~/.ssh/config, which holds its
# HostName, User and IdentityFile. Override with MM_HOST=user@host and MM_KEY=<private key> (with MM_KEY set, only that
# key is offered). The key is used through macOS's SSH agent, found even when SSH_AUTH_SOCK isn't set (a Claude Code
# shell). Load it in Terminal: once ever, ssh-add --apple-use-keychain <your key> (saves the passphrase in the Keychain);
# after each restart of this Mac, ssh-add --apple-load-keychain (no passphrase asked).
set -euo pipefail

host=${MM_HOST:-mm}
key=${MM_KEY:-}
keep=3
opts=(-o ConnectTimeout=5 -o UseKeychain=yes)
if [[ -n $key ]]; then opts=(-i "$key" -o IdentitiesOnly=yes "${opts[@]}"); fi
if [[ -z ${SSH_AUTH_SOCK:-} ]]; then
    sock=$(launchctl print "gui/$(id -u)/com.openssh.ssh-agent" 2>/dev/null | awk '/SSH_AUTH_SOCK =>/ {print $3; exit}')
    if [[ -S ${sock:-} ]]; then export SSH_AUTH_SOCK=$sock; fi
fi

# prune <dir> <n>: deletes all but the newest n MMTVL-*-build<N>.zip in dir, by build number. Used here and on the mini.
prune_fn=$(cat <<'FN'
prune() {
    local dir=$1 keep=$2 f n
    local -a lines old
    for f in "$dir"/MMTVL-*-build*.zip(N); do
        n=${f:t}; n=${n##*build}; n=${n%.zip}
        [[ "$n" == <-> ]] && lines+=("$n $f")
    done
    (( ${#lines} > keep )) || return 0
    old=("${(@f)$(print -rl -- "${lines[@]}" | sort -n | head -n $(( ${#lines} - keep )) | cut -d' ' -f2-)}")
    for f in "${old[@]}"; do
        echo "Removing ${f:t}"
        rm -f -- "$f"
    done
}
FN
)

# The steps on the mini. $1: "install" <zip name> <build> | "rollback". KEEP: how many zips to keep.
remote="$prune_fn"$'\n'$(cat <<'REMOTE'
set -euo pipefail
app=/Applications/MMTVL.app
downloads=~/Downloads

installed_build() {
    if [[ -d "$app" ]]; then
        /usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist"
    else
        echo 0
    fi
}

stop_mmtvl() {
    pgrep -x MMTVL >/dev/null || return 0
    # SIGTERM, not a quit request: with the kiosk lock on, a quit request asks for the PIN on the TV.
    pkill -TERM -x MMTVL || true
    for _ in {1..50}; do pgrep -x MMTVL >/dev/null || return 0; sleep 0.2; done
    echo "MMTVL didn't stop; killing it"
    pkill -KILL -x MMTVL || true
    sleep 0.5
}

# M15 step 9: Sparkle installs a staged update whenever MMTVL exits, SIGTERM included, which could replace the build
# being deployed. So before MMTVL is stopped, its jobs are booted out and the deploy stops if any of them, or its
# installer, is still there. From Sparkle 2.10.1's InstallerLauncher/SUInstallerLauncher.m:
#   jobs: "<bundle id>-sparkle-updater" (:259, Autoupdate) and "<bundle id>-sparkle-progress" (:60, Updater.app),
#         submitted to kSMDomainUserLaunchd (:258, :59), so both gui/<uid> and user/<uid> are tried;
#   processes: Autoupdate runs from the app's own Sparkle.framework (:483, not copied) with the arguments
#         <bundle id> <home> <user> (:129, Autoupdate/main.m:11-18); Updater.app with <host bundle path> <0|1> (:55).
sparkle_jobs=(dev.mmtvl.launcher-sparkle-updater dev.mmtvl.launcher-sparkle-progress)
# The updater job goes to the system domain only for installs that need authorization (:258), which the silent path
# never uses. A user can't boot it out, so it is only checked: if it's there, the deploy stops.
sparkle_system_job=dev.mmtvl.launcher-sparkle-updater
# Extended regexes for pgrep -f: MMTVL's own copies only, never another app's Sparkle.
sparkle_procs=('/Autoupdate dev\.mmtvl\.launcher ' '/Updater\.app/Contents/MacOS/Updater /Applications/MMTVL\.app ')

# job_loaded <domain/label>: true while launchd still has the job, waiting up to 2 s for a bootout to finish.
job_loaded() {
    for _ in {1..10}; do
        launchctl print "$1" >/dev/null 2>&1 || return 1
        sleep 0.2
    done
    return 0
}

remove_sparkle_jobs() {
    local uid domain label
    local -a removed
    uid=$(id -u)
    for label in "${sparkle_jobs[@]}"; do
        for domain in gui user; do
            launchctl print "$domain/$uid/$label" >/dev/null 2>&1 || continue
            launchctl bootout "$domain/$uid/$label" >/dev/null 2>&1 || true
            if job_loaded "$domain/$uid/$label"; then
                echo "Sparkle job ${label} (${domain} domain) is still loaded after bootout; not deploying; MMTVL wasn't stopped"
                exit 1
            fi
            removed+=("$label")
        done
    done
    if launchctl print "system/$sparkle_system_job" >/dev/null 2>&1; then
        echo "Sparkle job ${sparkle_system_job} is in the system domain (needs an admin to remove); not deploying; MMTVL wasn't stopped"
        exit 1
    fi
    if (( ${#removed} )); then echo "Sparkle jobs: removed ${(@u)removed}"; else echo "Sparkle jobs: none"; fi
    sparkle_procs_gone "is still running; not deploying; MMTVL wasn't stopped"
}

# sparkle_procs_gone <rest of the message>: fails the deploy while MMTVL's Sparkle installer runs (waits up to 2 s).
sparkle_procs_gone() {
    local pattern
    for pattern in "${sparkle_procs[@]}"; do
        for _ in {1..10}; do pgrep -f "$pattern" >/dev/null || continue 2; sleep 0.2; done
        echo "A Sparkle installer for MMTVL $1"
        exit 1
    done
}

# sparkle_still_gone: after MMTVL has stopped, only checks (never removes, never reports) that no Sparkle job or
# installer appeared between remove_sparkle_jobs and the stop, e.g. from a check that finished just then.
sparkle_still_gone() {
    local uid domain label
    local -a where
    uid=$(id -u)
    for label in "${sparkle_jobs[@]}"; do where+=("gui/$uid/$label" "user/$uid/$label"); done
    where+=("system/$sparkle_system_job")
    for domain in "${where[@]}"; do
        if launchctl print "$domain" >/dev/null 2>&1; then
            label=${domain:t}
            echo "Sparkle job ${label} (${domain%%/*} domain) appeared after MMTVL stopped; the app wasn't replaced, MMTVL is stopped"
            exit 1
        fi
    done
    sparkle_procs_gone "started after MMTVL stopped; the app wasn't replaced, MMTVL is stopped"
}

# check_build_holds <build>: reads the installed build every 0.5 s for 5 s; a late Sparkle swap would change it.
check_build_holds() {
    local now
    for _ in {1..10}; do
        now=$(installed_build 2>/dev/null) || now=unreadable
        [[ "$now" == "$1" ]] || { echo "The installed app is build ${now}, expected $1; MMTVL is running, check /Applications/MMTVL.app"; exit 1; }
        sleep 0.5
    done
}

start_mmtvl() {
    # Right after the swap, LaunchServices can refuse the new bundle (error -600, build 34); a second open works.
    local try
    for try in 1 2 3; do
        open "$app" && break
        echo "open failed (try $try of 3); trying again in 2 s"
        sleep 2
    done
    for _ in {1..25}; do
        if pgrep -x MMTVL >/dev/null; then
            echo "MMTVL $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist") build $(installed_build) is running"
            return 0
        fi
        sleep 0.2
    done
    echo "MMTVL didn't start (is someone logged in on the mini?)"
    exit 1
}

# install_zip <zip> <build>: unzips, checks the signature and the build number, and swaps the app in.
install_zip() {
    local zip=$1 expected=$2 built
    stage=$(mktemp -d "$downloads/mmtvl-deploy.XXXXXX")
    trap 'rm -rf "$stage"' EXIT
    ditto -x -k "$zip" "$stage"
    codesign --verify --deep --strict "$stage/MMTVL.app"
    built=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$stage/MMTVL.app/Contents/Info.plist")
    [[ "$built" == "$expected" ]] || { echo "The unzipped app is build ${built}, expected ${expected}"; exit 1; }
    remove_sparkle_jobs
    stop_mmtvl
    sparkle_still_gone
    rm -rf "$app"
    mv "$stage/MMTVL.app" "$app"
    start_mmtvl
    check_build_holds "$expected"
}

current=$(installed_build)
case "$1" in
install)
    # Keep the installed build's zip for --rollback if it isn't there yet (e.g. installed by hand).
    kept=("$downloads"/MMTVL-*-build"$current".zip(N))
    if [[ "$current" != 0 && "$current" != "$3" && ${#kept} -eq 0 ]]; then
        version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
        echo "Keeping the installed build ${current} as MMTVL-${version}-build${current}.zip"
        ditto -c -k --keepParent "$app" "$downloads/MMTVL-${version}-build${current}.zip"
    fi
    install_zip "$downloads/$2" "$3"
    prune "$downloads" "$KEEP"
    ;;
rollback)
    best=0; best_zip=""
    for f in "$downloads"/MMTVL-*-build*.zip(N); do
        n=${f:t}; n=${n##*build}; n=${n%.zip}
        if [[ "$n" == <-> ]] && (( n < current && n > best )); then best=$n; best_zip=$f; fi
    done
    [[ -n "$best_zip" ]] || { echo "No kept build older than build ${current} on the mini"; exit 1; }
    echo "Rolling back from build ${current} to ${best_zip:t}"
    install_zip "$best_zip" "$best"
    ;;
esac
REMOTE
)

if ! ssh "${opts[@]}" -o BatchMode=yes "$host" true 2>/dev/null; then
    echo "Can't log in to ${host} with an SSH key. Is the mini awake? Is the key in the SSH agent?"
    echo "In Terminal: ssh-add --apple-load-keychain (or, the first time: ssh-add --apple-use-keychain ${key:-<your key>})"
    exit 1
fi

if [[ "${1:-}" == "--rollback" ]]; then
    ssh "${opts[@]}" "$host" "KEEP=$keep zsh -s rollback" <<< "$remote"
    exit 0
fi

zip=${1:-$(ls -t ~/Desktop/MMTVL-*-build*.zip 2>/dev/null | head -1)}
[[ -n "$zip" && -f "$zip" ]] || { echo "No build zip found (run scripts/test-build.sh first)"; exit 1; }
name=${zip:t}
[[ "$name" =~ 'build([0-9]+)\.zip$' ]] || { echo "Can't read the build number from ${name}"; exit 1; }
build=${match[1]}

echo "Installing ${name} on ${host}"
scp -q "${opts[@]}" "$zip" "${host}:Downloads/${name}"
ssh "${opts[@]}" "$host" "KEEP=$keep zsh -s install '${name}' '${build}'" <<< "$remote"

# This Mac: keep the last $keep build zips on the Desktop.
eval "$prune_fn"
prune ~/Desktop "$keep"
