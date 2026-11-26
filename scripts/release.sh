#!/usr/bin/env bash
# Makes a release of RunwayLeft on this Mac: tests, a universal build signed with
# the "Developer ID Application" certificate, Apple's check (notarization), a
# .dmg and a .zip, and after a question the tag and the GitHub release.
#
#   scripts/release.sh --notes "<what changed>"   build, show what was made, ask, publish
#   scripts/release.sh --build-only               build, sign and pack; nothing leaves this Mac
#   scripts/release.sh --build-only --notarize    the same, and the app goes to Apple for its
#                                                 check (nothing is published)
#
# The release runs here and not in GitHub Actions because the certificate and
# the login for Apple's check live in this Mac's keychain only. Needed once:
#   the certificate, from developer.apple.com (Certificates > Developer ID
#   Application), with its private key in the login keychain
#   xcrun notarytool store-credentials <profile> --apple-id <Apple ID> --team-id <team>
# The profile name is read from RUNWAYLEFT_NOTARY_PROFILE (default below); the
# login belongs to the whole Apple account, so one profile serves every app.
#
# Apple's check uploads the app, so a release asks for it only after its
# question. The version is the one in build_app.sh; raise it there and commit
# before a release. Afterwards the cask in the tap gets the new version and the
# checksum of the .zip, which this script prints at the end.
set -euo pipefail

GH_REPO="${RUNWAYLEFT_GH_REPO:-pezzking/runwayleft}"
NOTARY="${RUNWAYLEFT_NOTARY_PROFILE:-kubedog-notary}"
APP_NAME="RunwayLeft"

BUILD_ONLY=0
NOTARIZE=0
NOTES=""
while [ $# -gt 0 ]; do
    case "$1" in
        --build-only) BUILD_ONLY=1 ;;
        --notarize) NOTARIZE=1 ;;
        --notes) shift; NOTES="${1:-}" ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done
[ "$BUILD_ONLY" = 1 ] || NOTARIZE=0   # a release asks Apple after its question

cd "$(dirname "$0")/.."
ROOT="$PWD"
say() { printf '\n== %s\n' "$*"; }
stop() { printf '\nStopped: %s\n' "$*" >&2; exit 1; }

V="$(grep -A1 CFBundleShortVersionString build_app.sh | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')"
[ -n "$V" ] || stop "no version found in build_app.sh"
TAG="v$V"
APP="$ROOT/build/$APP_NAME.app"
DIST="$ROOT/build/dist"
WORK="$ROOT/build/release-work"
DMG="$DIST/$APP_NAME-$V.dmg"
ZIP="$DIST/$APP_NAME-$V.zip"
trap 'rm -rf "$WORK"' EXIT

for tool in swift codesign hdiutil ditto xcrun spctl shasum lipo gh; do
    command -v "$tool" >/dev/null || stop "$tool isn't installed"
done
# The certificate is found by its kind, so no name is written here.
SIGN_ID="${RUNWAYLEFT_SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/^ *[0-9]*) \([0-9A-F]*\) "Developer ID Application: .*/\1/p' | head -1)}"
[ -n "$SIGN_ID" ] || stop "no 'Developer ID Application' certificate in the keychain (see the top of this script)"
if [ "$BUILD_ONLY" = 0 ] || [ "$NOTARIZE" = 1 ]; then
    xcrun notarytool history --keychain-profile "$NOTARY" >/dev/null 2>&1 \
        || stop "the login for Apple's check ($NOTARY) isn't in the keychain or isn't accepted (see the top of this script)"
fi

say "$APP_NAME $V: checks"
if [ "$BUILD_ONLY" = 0 ]; then
    [ -n "$NOTES" ] || stop "a release needs --notes \"<what changed>\" (it becomes the tag message and the release notes)"
    [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || stop "not on main"
    [ -z "$(git status --porcelain)" ] || stop "there are changes that aren't committed"
    git fetch -q origin main
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || stop "main here and on the server differ; push or pull first"
    git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && stop "the tag $TAG exists already; raise the version in build_app.sh"
    gh release view "$TAG" --repo "$GH_REPO" >/dev/null 2>&1 && stop "$GH_REPO has a release $TAG already"
elif [ -n "$(git status --porcelain)" ]; then
    echo "Note: there are changes that aren't committed (fine for --build-only)."
fi
swift test 2>&1 | tail -3
[ "${PIPESTATUS[0]}" = 0 ] || stop "the tests fail"

# Asks Apple to check what's in a .zip or .dmg, and waits for the answer.
apple_checks() {
    local out
    out="$(xcrun notarytool submit "$1" --keychain-profile "$NOTARY" --wait 2>&1)" \
        || { echo "$out"; stop "Apple's check of $(basename "$1") couldn't be asked for"; }
    echo "$out" | grep -q "status: Accepted" \
        || { echo "$out"; stop "Apple didn't accept $(basename "$1"); see: xcrun notarytool log <id> --keychain-profile $NOTARY"; }
}

# Stops unless macOS itself says it would open this without a warning. spctl
# writes its verdict to stderr, and its exit code alone doesn't say "notarized".
gatekeeper() { # gatekeeper <what for the message> <spctl arguments...>
    local what="$1" out; shift
    out="$(spctl -a -vv "$@" 2>&1)" || { echo "$out"; stop "macOS wouldn't open $what without a warning"; }
    echo "$out"
    echo "$out" | grep -q "accepted" && echo "$out" | grep -q "source=Notarized Developer ID" \
        || stop "$what isn't accepted as 'Notarized Developer ID'"
}

# Builds, signs and packs the two downloads: RunwayLeft.app in a disk image
# (the main one) and the same app in a .zip (what the Homebrew cask fetches).
mac_pack() { # mac_pack <time from Apple: none|apple> <ask Apple to check: 0|1>
    rm -rf "$WORK" "$DIST"
    mkdir -p "$WORK/dmg" "$DIST"

    RUNWAYLEFT_UNIVERSAL=1 RUNWAYLEFT_SIGN_ID="$SIGN_ID" RUNWAYLEFT_TIMESTAMP="$1" ./build_app.sh
    lipo -info "$APP/Contents/MacOS/$APP_NAME"
    codesign --verify --strict --deep "$APP" || stop "the signature of $APP_NAME.app isn't right"
    # Paths of this computer (the home folder, the user's name) must not end up inside the program.
    local leaks
    leaks="$(strings -a "$APP/Contents/MacOS/$APP_NAME" | grep -F -e "$HOME" -e "/Users/$USER/" | head -3 || true)"
    [ -z "$leaks" ] || { echo "$leaks"; stop "the program holds a path of this computer"; }

    if [ "$2" = 1 ]; then
        ditto -c -k --keepParent "$APP" "$WORK/ask.zip"
        apple_checks "$WORK/ask.zip"
        # The answer is fixed to the app, so it's also known on a Mac without internet.
        xcrun stapler staple -q "$APP" || stop "Apple's answer couldn't be fixed to $APP_NAME.app"
    fi

    # Packed after stapling, so both downloads carry Apple's answer.
    ditto -c -k --keepParent "$APP" "$ZIP"
    ditto "$APP" "$WORK/dmg/$APP_NAME.app"
    ln -s /Applications "$WORK/dmg/Applications"
    hdiutil create -quiet -volname "$APP_NAME $V" -srcfolder "$WORK/dmg" -fs HFS+ -format UDZO -ov "$DMG"
    codesign --force "--timestamp$([ "$1" = apple ] || echo "=none")" -s "$SIGN_ID" "$DMG"
    if [ "$2" = 1 ]; then
        apple_checks "$DMG"
        xcrun stapler staple -q "$DMG" || stop "Apple's answer couldn't be fixed to the disk image"
        gatekeeper "$APP_NAME.app" -t exec "$APP"
        gatekeeper "the disk image" -t open --context context:primary-signature "$DMG"
    fi

    (cd "$DIST" && for f in "$APP_NAME-$V.dmg" "$APP_NAME-$V.zip"; do shasum -a 256 "$f" > "$f.sha256"; done)
    rm -rf "$WORK"
}

say "Build, sign and pack"
if [ "$NOTARIZE" = 1 ]; then mac_pack apple 1; else mac_pack none 0; fi

say "Made, in build/dist"
(cd "$DIST" && ls -lh "$APP_NAME-$V.dmg" "$APP_NAME-$V.zip" | awk '{print "  " $5 "\t" $9}' && echo && cat ./*.sha256)

if [ "$BUILD_ONLY" = 1 ]; then
    echo
    if [ "$NOTARIZE" = 1 ]; then
        echo "Build only: the app was checked by Apple; nothing was published."
    else
        echo "Build only: nothing was uploaded. The files are signed but not checked by Apple (--notarize does that)."
    fi
    exit 0
fi

echo
echo "Next: the app goes to Apple for its check (the files and their checksums change with that),"
echo "then: the tag $TAG and a release $TAG on github.com/$GH_REPO."
printf 'Type the version (%s) to go on, anything else to stop: ' "$V"
read -r answer
[ "$answer" = "$V" ] || stop "nothing was uploaded"

say "Signed and checked by Apple"
mac_pack apple 1

say "Tag and release"
git tag -a "$TAG" -m "$NOTES"
git push -q origin "$TAG"   # this tag alone, never --tags
gh release create "$TAG" --repo "$GH_REPO" --title "$APP_NAME $V" --notes "$NOTES" \
    "$DMG" "$DMG.sha256" "$ZIP" "$ZIP.sha256"

say "Done"
echo "For Casks/runwayleft.rb in the tap:"
echo "  version \"$V\""
echo "  sha256 \"$(cut -d' ' -f1 "$ZIP.sha256")\""
