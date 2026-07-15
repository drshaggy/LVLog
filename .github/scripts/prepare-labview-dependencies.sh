#!/usr/bin/env bash

set -euo pipefail

readonly REPOSITORY_ROOT="$(git rev-parse --show-toplevel)"
readonly DEPENDENCY_ROOT="${REPOSITORY_ROOT}/.ci/dependencies"
readonly DOWNLOAD_ROOT="${DEPENDENCY_ROOT}/downloads"

readonly GCLI_URL="https://github.com/G-CLI/G-CLI/releases/download/v3.0.1/wiresmith_technology_lib_g_cli-3.0.1.98.vip"
readonly GCLI_SHA256="89c77ac86efb6d88bbc4c02658f76ddc23bbedc194cdbaae837771192503991b"
readonly LUNIT_URL="https://github.com/astemes/astemes-lunit/releases/download/v2.0.13/astemes_lib_lunit-2.0.13.6.vip"
readonly LUNIT_SHA256="8c747d9fd57ef7fb21d3e3d9c3a59fed3d201843ef7d19daac54e3f564908d46"
readonly LUNIT_CLI_URL="https://github.com/astemes/astemes-lunit-cli/releases/download/v1.6.2/astemes_lib_lunit_cli-1.6.2.23.vip"
readonly LUNIT_CLI_SHA256="fbffd4fbffea99348723f221dbeaf70d47af680de930cc0006a19012a62737c1"
readonly LUNIT_CLI_SYSTEM_PACKAGE="astemes_lib_lunit_cli_system-1.6.2.23.vip"

download_and_verify() {
  local name="$1"
  local url="$2"
  local checksum="$3"
  local destination="${DOWNLOAD_ROOT}/${name}.vip"

  echo "Downloading ${name}"
  curl --fail --location --silent --show-error \
    --retry 5 --retry-all-errors \
    --output "$destination" \
    "$url"

  printf '%s  %s\n' "$checksum" "$destination" | sha256sum --check --strict
}

extract_package() {
  local package="$1"
  local destination="$2"

  rm -rf "$destination"
  mkdir -p "$destination"
  unzip -q "$package" -d "$destination"
}

rm -rf "$DEPENDENCY_ROOT"
mkdir -p "$DOWNLOAD_ROOT"

download_and_verify "g-cli" "$GCLI_URL" "$GCLI_SHA256"
download_and_verify "lunit" "$LUNIT_URL" "$LUNIT_SHA256"
download_and_verify "lunit-cli" "$LUNIT_CLI_URL" "$LUNIT_CLI_SHA256"

extract_package "${DOWNLOAD_ROOT}/g-cli.vip" "${DEPENDENCY_ROOT}/g-cli"
extract_package "${DOWNLOAD_ROOT}/lunit.vip" "${DEPENDENCY_ROOT}/lunit"
extract_package "${DOWNLOAD_ROOT}/lunit-cli.vip" "${DEPENDENCY_ROOT}/lunit-cli"

unzip -p "${DOWNLOAD_ROOT}/lunit-cli.vip" \
  "Packages/${LUNIT_CLI_SYSTEM_PACKAGE}" \
  > "${DOWNLOAD_ROOT}/lunit-cli-system.vip"
extract_package \
  "${DOWNLOAD_ROOT}/lunit-cli-system.vip" \
  "${DEPENDENCY_ROOT}/lunit-cli-system"

echo "Prepared G CLI, LUnit, and LUnit CLI payloads in ${DEPENDENCY_ROOT}"
