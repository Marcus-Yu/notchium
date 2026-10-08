#!/bin/bash
# Local-only release. No certificates, uploads, security overrides, or installers.
set -euo pipefail
umask 022
export PYTHONDONTWRITEBYTECODE=1

die() { printf 'Release stopped: %s\n' "$*" >&2; exit 1; }
usage() { printf 'Usage: %s VERSION [--preview] [--zip]\n' "$0"; }
[[ $# -ge 1 ]] || { usage; exit 2; }
version="$1"; shift
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || die "Use a semantic version such as 1.0.0."
preview=0; format=dmg
for option in "$@"; do
    case "$option" in
        --preview) preview=1 ;;
        --zip) format=zip ;;
        *) usage; die "Unknown option." ;;
    esac
done
[[ "$(uname -s)" == Darwin ]] || die "Run on macOS with Xcode installed."
root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$root"
for tool in git xcodebuild swift python3 codesign hdiutil ditto shasum; do
    command -v "$tool" >/dev/null || die "Missing tool: $tool"
done
revision="$(git rev-parse HEAD)"
suffix=""
if [[ "$preview" == 0 ]]; then
    [[ -z "$(git status --porcelain --untracked-files=all)" ]] || die "Commit reviewed source and release support files first; use --preview only for local validation."
    [[ "$(git rev-parse "refs/tags/v$version^{commit}" 2>/dev/null)" == "$revision" ]] || die "Tag v$version must already point to HEAD. No tag is created automatically."
else
    suffix=-preview
fi
[[ -f LICENSE && -f THIRD_PARTY_NOTICES.md ]] || die "Resolve project and third-party licensing first."
[[ -f "docs/releases/$version.md" ]] || die "Prepare release notes in docs/releases/$version.md first."
marketing="$(sed -n 's/^MARKETING_VERSION = //p' Config/Shared.xcconfig)"
build="$(sed -n 's/^CURRENT_PROJECT_VERSION = //p' Config/Shared.xcconfig)"
[[ "$marketing" == "$version" && "$build" =~ ^[1-9][0-9]{0,3}$ ]] || die "Version must match Config/Shared.xcconfig; build must be an integer from 1 to 9999."
if [[ "$preview" == 0 ]]; then
    while IFS= read -r tag; do
        [[ "$tag" == "v$version" ]] && continue
        old_build="$(git show "$tag:Config/Shared.xcconfig" | sed -n 's/^CURRENT_PROJECT_VERSION = //p')"
        [[ "$old_build" =~ ^[1-9][0-9]{0,3}$ ]] || die "Cannot verify build number in $tag."
        (( build > old_build )) || die "Build number must exceed every earlier semantic release tag."
    done < <(git tag --list | /usr/bin/grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true)
fi
[[ ! -L "$root/dist" ]] || die "dist must not be a symlink."
available_kb="$(df -k "$root" | awk 'END { print $4 }')"
[[ "$available_kb" =~ ^[0-9]+$ ]] || die "Cannot determine available disk space."
(( available_kb >= 1572864 )) || die "At least 1.5 GiB of free disk space is required for sequential clean builds."
output="$root/dist/$version$suffix"
[[ ! -e "$output" && ! -L "$output" ]] || die "Output already exists; preserve or move it before rebuilding: $output"
mkdir -p "$output/logs"
work="$(mktemp -d /private/tmp/notchium-release.XXXXXX)"
mount="$work/mounted"
mounted=0
cleanup() {
    status=$?
    if [[ "$mounted" == 1 ]]; then /usr/bin/hdiutil detach "$mount" >/dev/null 2>&1 || true; fi
    # Only the private directory returned by mktemp is ever recursively removed.
    rm -rf "$work"
    if [[ "$status" != 0 ]]; then printf 'Failed. Private logs: %s/logs\n' "$output" >&2; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
source="$work/source"
mkdir "$source"
if [[ "$preview" == 0 ]]; then
    git archive "$revision" | tar -x -C "$source"
else
    python3 - "$root" "$source" <<'PY'
import pathlib, shutil, subprocess, sys
root, target = map(pathlib.Path, sys.argv[1:])
names = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z', '--cached', '--others', '--exclude-standard']).split(b'\0')
for raw in sorted(set(names) - {b''}):
    name = raw.decode()
    src = root / name
    if not src.exists():  # A tracked deletion in the working tree.
        continue
    if src.is_symlink() or not src.is_file():
        raise SystemExit('Preview source must contain only regular files.')
    dst = target / name
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
PY
fi
python3 "$source/scripts/verify-release.py" --source "$source" > "$output/logs/source-audit.txt"
printf 'Running the complete Swift package suite and release-tool safety tests…\n'
python3 "$source/scripts/tests/test_release_safety.py" > "$output/logs/release-safety-tests.txt" 2>&1
package_tests=passed
if ! swift test --package-path "$source/NotchiumPackage" --disable-sandbox \
    --scratch-path "$work/tests" > "$output/logs/package-tests.txt" 2>&1; then
    package_tests=failed
    [[ "$preview" == 1 ]] || die "Package tests failed; inspect logs."
    printf 'PREVIEW ONLY: package tests failed. Continuing independent packaging checks; publication is blocked.\n'
fi
# Each directory below is owned by this invocation's mktemp directory.
rm -rf "$work/tests"
printf 'Testing the free build profile…\n'
swift test --package-path "$source/NotchiumPackage" --disable-sandbox \
    --scratch-path "$work/free-tests" -Xswiftc -D -Xswiftc NOTCH_FREE_DISTRIBUTION \
    --filter FreeDistributionTests > "$output/logs/free-profile-tests.txt" 2>&1
rm -rf "$work/free-tests"
printf 'Building Debug…\n'
common=(-workspace "$source/Notchium.xcworkspace" -scheme Notchium -destination 'generic/platform=macOS'
    'ARCHS=arm64' 'ONLY_ACTIVE_ARCH=NO' 'CODE_SIGNING_ALLOWED=NO' 'CODE_SIGNING_REQUIRED=NO'
    'CODE_SIGN_IDENTITY=' 'DEVELOPMENT_TEAM=' 'CODE_SIGN_ENTITLEMENTS=' 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO')
xcodebuild "${common[@]}" -configuration Debug -derivedDataPath "$work/debug" build \
    > "$output/logs/debug-build.txt" 2>&1
rm -rf "$work/debug"
printf 'Building clean Release for Apple Silicon…\n'
xcodebuild "${common[@]}" -configuration Release -derivedDataPath "$work/release" \
    'ENABLE_CODE_COVERAGE=NO' 'GCC_GENERATE_TEST_COVERAGE_FILES=NO' 'GCC_INSTRUMENT_PROGRAM_FLOW_ARCS=NO' \
    'CLANG_ENABLE_CODE_COVERAGE=NO' 'CLANG_COVERAGE_MAPPING=NO' 'CLANG_INSTRUMENT_FOR_OPTIMIZATION_PROFILING=NO' \
    "OTHER_SWIFT_FLAGS=\$(inherited) -D NOTCH_FREE_DISTRIBUTION -debug-prefix-map $source=. -file-prefix-map $source=." \
    "OTHER_CFLAGS=\$(inherited) -fdebug-prefix-map=$source=. -ffile-prefix-map=$source=." build \
    > "$output/logs/release-build.txt" 2>&1
stage="$work/image"
mkdir "$stage"
app="$stage/Notchium.app"
/usr/bin/ditto "$work/release/Build/Products/Release/Notchium.app" "$app"
/usr/bin/install -m 644 "$source/LICENSE" "$app/Contents/Resources/LICENSE"
/usr/bin/install -m 644 "$source/THIRD_PARTY_NOTICES.md" "$app/Contents/Resources/THIRD_PARTY_NOTICES.md"
# build (rather than archive) can retain local debug symbols. Keep the dSYM
# separately; strip debugging symbols before sealing the user-facing bundle.
/usr/bin/strip -S "$app/Contents/MacOS/Notchium"
find "$app" -type d -exec chmod 755 {} +
find "$app" -type f -exec chmod go-w {} +
/usr/bin/codesign --force --sign - --timestamp=none --identifier com.marcusyu.notchium "$app" \
    > "$output/logs/signing.txt" 2>&1
python3 "$source/scripts/verify-release.py" --app "$app" --version "$version" --build "$build" \
    > "$output/logs/app-audit.txt"
filename="Notchium-$version$suffix.$format"
artifact="$work/$filename"
if [[ "$format" == dmg ]]; then
    ln -s /Applications "$stage/Applications"
    /usr/bin/hdiutil create -volname Notchium -srcfolder "$stage" -format UDZO "$artifact" \
        > "$output/logs/packaging.txt" 2>&1
    /usr/bin/hdiutil verify "$artifact" >> "$output/logs/packaging.txt" 2>&1
    mkdir "$mount"
    /usr/bin/hdiutil attach "$artifact" -readonly -nobrowse -mountpoint "$mount" \
        >> "$output/logs/packaging.txt" 2>&1
    mounted=1
    [[ "$(readlink "$mount/Applications")" == /Applications ]] || die "Applications link is invalid."
    verify_app="$mount/Notchium.app"
else
    /usr/bin/ditto -c -k --keepParent "$app" "$artifact"
    mkdir "$mount"
    /usr/bin/ditto -x -k "$artifact" "$mount"
    verify_app="$mount/Notchium.app"
fi
python3 "$source/scripts/verify-release.py" --app "$verify_app" --version "$version" --build "$build" \
    > "$output/logs/packaged-app-audit.txt"
/usr/bin/ditto "$verify_app" "$output/Notchium.app"
if [[ "$mounted" == 1 ]]; then /usr/bin/hdiutil detach "$mount" >/dev/null; mounted=0; fi
/usr/bin/install -m 644 "$artifact" "$output/$filename"
(cd "$output" && shasum -a 256 "$filename" > "$filename.sha256" && shasum -a 256 -c "$filename.sha256")
if [[ -d "$work/release/Build/Products/Release/Notchium.app.dSYM" ]]; then
    /usr/bin/ditto "$work/release/Build/Products/Release/Notchium.app.dSYM" "$output/symbols/Notchium.app.dSYM"
fi
python3 - "$source" "$output" "$filename" "$revision" "$preview" "$version" "$build" "$package_tests" <<'PY'
import hashlib, json, pathlib, subprocess, sys
source, output = map(pathlib.Path, sys.argv[1:3])
filename, revision, preview, version, build, package_tests = sys.argv[3:]
artifact = output / filename
digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
manifest = {
    'version': version, 'build': build, 'base_commit': revision, 'tag': None if preview == '1' else 'v' + version,
    'preview': preview == '1', 'artifact': filename, 'size_bytes': artifact.stat().st_size, 'sha256': digest,
    'package_tests': package_tests,
    'minimum_macos': '26.0', 'architectures': ['arm64'], 'signing': 'ad-hoc, no trusted identity',
    'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True).strip(),
    'macos': subprocess.check_output(['sw_vers', '-productVersion'], text=True).strip(),
    'source_files_sha256': {str(p.relative_to(source)): hashlib.sha256(p.read_bytes()).hexdigest()
                            for p in sorted(source.rglob('*')) if p.is_file()},
    'manual_acceptance': 'PENDING: packaged launch, fresh-user Gatekeeper override, permissions and regression checks',
}
(output / 'release-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
notes = (source / ('docs/releases/' + version + '.md')).read_text()
for key, value in {'ARTIFACT': filename, 'SHA256': digest, 'SIZE_BYTES': str(artifact.stat().st_size), 'COMMIT': revision}.items():
    notes = notes.replace('{{' + key + '}}', value)
if preview == '1':
    notes = 'LOCAL PREVIEW — DO NOT PUBLISH. Built from uncommitted source.\n\n' + notes
(output / 'release-notes.md').write_text(notes)
print(json.dumps({k: manifest[k] for k in ('artifact', 'size_bytes', 'sha256', 'preview')}, indent=2))
PY
printf 'Built and verified: %s/%s\nChecksum: %s/%s.sha256\nApp: %s/Notchium.app\n' "$output" "$filename" "$output" "$filename" "$output"
printf 'Complete the manual acceptance in docs/RELEASING.md before publishing. No upload or tag was performed.\n'
