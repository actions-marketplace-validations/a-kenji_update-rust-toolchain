#!/usr/bin/env bash
set -euo pipefail
# dependencies: bash, curl, jq
#
# Updates a rust-toolchain file in relation to the official rust releases.


# reads the channel version from the rust-toolchain.toml file
function _curr_toolchain_version() {
local RUST_TOOLCHAIN_FILE="$1"
RUST_TOOLCHAIN_VERSION=$(grep -oP \
    'channel[[:space:]]*=[[:space:]]*"\K[^"]+' \
    "${RUST_TOOLCHAIN_FILE}")
echo "${RUST_TOOLCHAIN_VERSION:-false}"
}
# update with new version number
function _update_channel(){
local RUST_TOOLCHAIN_VERSION="$1"
sed -e "/channel/s/\".*\"/\"${RUST_TOOLCHAIN_VERSION}\"/" "${RUST_TOOLCHAIN_FILE}"
}
function _get_last_no_releases() {
    RELEASES=$(curl --silent "https://api.github.com/repos/rust-lang/rust/releases")
    retVal=$?
if [ $retVal -ne 0 ]; then
    echo "Curl couldn't get the releases"
    exit 1
fi
echo "${RELEASES}" | jq '.[range(50)].tag_name' | sed -e 's/\"//g'
}
function _parse_semver() {
    local token="$1"
    local major=0
    local minor=0
    local patch=0

    if grep -E '^[0-9]+\.[0-9]+\.[0-9]+' <<<"$token" >/dev/null 2>&1 ; then
        local versions=${token//[!0-9]/ }
        local semver=()
        for version in $versions; do
            semver+=("$version")
        done

        major=${semver[0]}
        minor=${semver[1]}
        patch=${semver[2]}
    fi

    echo "$major $minor $patch"
}
function _find_minor_version() {
local MINOR_DELTA="$1"
local RELEASES="$2"
local LATEST=0
for i in $RELEASES;do
    local SEMVER=()
    for version in $(_parse_semver "$i");do
        SEMVER+=("$version")
    done
    if [ "$LATEST" != "${SEMVER[1]}" ];then
        MINOR_DELTA=$((MINOR_DELTA - 1))
    fi
    LATEST="${SEMVER[1]}"
    if [ -1 == "${MINOR_DELTA}" ];then
        echo "$i"
    fi
done
}
function _find_patch_version() {
local MINOR_VERSION="$1"
local RELEASES="$2"
for i in $RELEASES;do
    local SEMVER=()
    for version in $(_parse_semver "$i");do
        SEMVER+=("$version")
    done
    if [ "$MINOR_VERSION" == "${SEMVER[1]}" ];then
        echo "$i"
    fi
done
}
function _get_first_version() {
	# Word splitting is desired here, to split the individual patch and minor version up
	# shellcheck disable=2206
	local VERSIONS=($1)
	echo "${VERSIONS[0]}"
}

_main() {
# Path to the rust-toolchain file
RUST_TOOLCHAIN_FILE="$TOOLCHAIN_FILE"
echo RUST_TOOLCHAIN_FILE "$TOOLCHAIN_FILE"
# How many minor versions delta there should be,
# will automatically advance patch versions.
MINOR_DELTA="$MINOR_VERSION_DELTA"
echo MINOR_DELTA "$MINOR_DELTA"
UPDATE_PATCH="$INPUTS_UPDATE_PATCH"
echo UPDATE_PATCH "$UPDATE_PATCH"
UPDATE_MINOR="$INPUTS_UPDATE_MINOR"
echo UPDATE_MINOR "$UPDATE_MINOR"

# Try to read the current toolchain version from the toolchain file
# If we can read the version directly, then it is still the non toml version
RUST_TOOLCHAIN_VERSION=$(_parse_semver "$(cat "$RUST_TOOLCHAIN_FILE")")
# 0 0 0 means we can't parse it, so either it is a toml file, or malformed
if [[ $RUST_TOOLCHAIN_VERSION == "0 0 0" ]]; then
    TOML=true
    RUST_TOOLCHAIN_VERSION="$(_curr_toolchain_version "$RUST_TOOLCHAIN_FILE")"
    echo RUST_TOOLCHAIN_VERSION "${RUST_TOOLCHAIN_VERSION}"
    # if we can't parse it here either, it is malformed
    if [[ $RUST_TOOLCHAIN_VERSION == "false" ]]; then
        echo "Can't parse the toolchain file : ${RUST_TOOLCHAIN_FILE}"
        exit
    fi
else
    TOML=false
fi


echo CURRENT_RUST_TOOLCHAIN_VERSION "$RUST_TOOLCHAIN_VERSION"
RUST_TOOLCHAIN_VERSION_SEMVER=()
    for version in $(_parse_semver "$RUST_TOOLCHAIN_VERSION");do
        RUST_TOOLCHAIN_VERSION_SEMVER+=("$version")
    done
echo RUST_TOOLCHAIN_VERSION_SEMVER "${RUST_TOOLCHAIN_VERSION_SEMVER[@]}"


RELEASES="$(_get_last_no_releases)"

if [[ $UPDATE_PATCH == "true" ]]; then
    VERSION=$(_find_patch_version "${RUST_TOOLCHAIN_VERSION_SEMVER[1]}" "$RELEASES")
    VERSION=$(_get_first_version "$VERSION")
fi

if [[ $UPDATE_MINOR == "true" ]]; then
    VERSION=$(_find_minor_version "${MINOR_DELTA}" "$RELEASES")
    VERSION=$(_get_first_version "$VERSION")
fi

if [[ $TOML == "true" ]]; then
    NEW_CHANNEL=$(_update_channel "$VERSION")
    echo "$NEW_CHANNEL" > "${RUST_TOOLCHAIN_FILE}"
else
    echo "$VERSION" > "${RUST_TOOLCHAIN_FILE}"
fi
echo "$VERSION"
echo TOML $TOML
cat "${RUST_TOOLCHAIN_FILE}"
}


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
   _main "$@"
fi
