#!/bin/bash
# Mock UI fixtures use a separate application identity from the user's Notchium.
set -euo pipefail

die() { printf 'UI tests stopped: %s\n' "$*" >&2; exit 2; }
usage() {
    cat <<'USAGE'
Usage: scripts/run-ui-tests.sh [options]
  -only-testing:NotchiumUITests[/CLASS[/TEST]]   Select UI tests (repeatable)
  -skip-testing:NotchiumUITests[/CLASS[/TEST]]   Skip UI tests (repeatable)
  --derived-data PATH                         Keep build products at PATH
  --result-bundle PATH                        Write a new Xcode result bundle
  --log PATH                                  Also save build/test output at PATH
USAGE
}

project_root="$(cd "$(dirname "$0")/.." && pwd -P)"
derived_data_path="$project_root/.build/ui-tests-isolated"
result_bundle_path=""
log_path=""
selectors=()
has_selection=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        -only-testing:NotchiumUITests|-only-testing:NotchiumUITests/*)
            selectors+=("$1"); has_selection=1; shift ;;
        -skip-testing:NotchiumUITests|-skip-testing:NotchiumUITests/*)
            selectors+=("$1"); shift ;;
        --derived-data|--result-bundle|--log)
            [[ $# -ge 2 && -n "$2" ]] || die "Missing path after $1."
            case "$1" in
                --derived-data) derived_data_path="$2" ;;
                --result-bundle) result_bundle_path="$2" ;;
                --log) log_path="$2" ;;
            esac
            shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; die "Unsupported option: $1" ;;
    esac
done

[[ "$(uname -s)" == Darwin ]] || die "Run on macOS with Xcode installed."
command -v xcodebuild >/dev/null || die "Missing xcodebuild."
if [[ "$has_selection" == 0 ]]; then selectors+=("-only-testing:NotchiumUITests"); fi

arguments=(
    -workspace "$project_root/Notchium.xcworkspace"
    -scheme Notchium -configuration Debug -destination 'platform=macOS'
    -derivedDataPath "$derived_data_path"
    -parallel-testing-enabled NO
    "${selectors[@]}"
    'NOTCHIUM_APP_BUNDLE_IDENTIFIER=com.marcusyu.notchium.uitesting'
    'CODE_SIGN_IDENTITY=-' 'CODE_SIGN_STYLE=Manual' 'DEVELOPMENT_TEAM='
    'CODE_SIGN_ENTITLEMENTS='
)
if [[ -n "$result_bundle_path" ]]; then arguments+=(-resultBundlePath "$result_bundle_path"); fi
arguments+=(test)

printf 'UI fixture app: com.marcusyu.notchium.uitesting\nDerived data: %s\n' "$derived_data_path"
if [[ -n "$log_path" ]]; then
    mkdir -p "$(dirname "$log_path")"
    xcodebuild "${arguments[@]}" 2>&1 | tee "$log_path"
else
    exec xcodebuild "${arguments[@]}"
fi
