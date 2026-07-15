#!/usr/bin/env bash

set -Eeuo pipefail

readonly WORKSPACE="${WORKSPACE:-/workspace}"
readonly LABVIEW_PATH="/usr/local/natinst/LabVIEW-2026-64/labview"
readonly LABVIEW_ROOT="$(dirname "$LABVIEW_PATH")"
readonly DEPENDENCY_ROOT="${WORKSPACE}/.ci/dependencies"
readonly BUILD_LOG_ROOT="${WORKSPACE}/build-logs"
readonly TEST_RESULT_ROOT="${WORKSPACE}/test-results"

mkdir -p "$BUILD_LOG_ROOT" "$TEST_RESULT_ROOT"

exec > >(tee "${BUILD_LOG_ROOT}/labview-ci.log") 2>&1

collect_labview_logs() {
  local source

  shopt -s nullglob
  for source in \
    /tmp/lvtemporary_*.log \
    /tmp/LabVIEW*.log \
    /root/natinst/.config/LabVIEW-*/*.log; do
    cp -f "$source" "${BUILD_LOG_ROOT}/$(basename "$source")" || true
  done
  shopt -u nullglob
}

close_labview() {
  timeout 60s LabVIEWCLI \
    -LogToConsole TRUE \
    -OperationName CloseLabVIEW \
    -LabVIEWPath "$LABVIEW_PATH" \
    -Headless || true
}

cleanup() {
  local exit_code=$?

  close_labview
  collect_labview_logs
  exit "$exit_code"
}
trap cleanup EXIT

install_application_payload() {
  local package_name="$1"
  local payload="${DEPENDENCY_ROOT}/${package_name}/File Group 0"

  if [[ ! -d "$payload" ]]; then
    echo "Missing ${package_name} application payload: ${payload}" >&2
    return 1
  fi

  cp -a "${payload}/." "${LABVIEW_ROOT}/"
}

install_lunit_cli_operation() {
  local core_operation
  local operations_root
  local cli_root
  local ni_shared_root
  local payload

  core_operation="$(find /usr/local/natinst -type f \
    -path '*/Operations/CoreOperation/CoreOperation.lvclass' \
    -print -quit)"
  if [[ -z "$core_operation" ]]; then
    echo "Could not locate the LabVIEWCLI CoreOperation class" >&2
    return 1
  fi

  operations_root="$(dirname "$(dirname "$core_operation")")"
  cli_root="$(dirname "$operations_root")"
  ni_shared_root="$(dirname "$cli_root")"
  payload="$(find "${DEPENDENCY_ROOT}/lunit-cli-system/File Group 0" \
    -type d -path '*/LabVIEW CLI/Operations/LUnitCLI' \
    -print -quit)"

  if [[ -z "$payload" ]]; then
    echo "Could not locate the LUnit CLI operation payload" >&2
    return 1
  fi

  mkdir -p "${operations_root}/LUnitCLI"
  cp -a "${payload}/." "${operations_root}/LUnitCLI/"

  # LUnit's source uses the portable <nishared>/LabVIEW CLI path. NI's Linux
  # package stores the same files under nilvcli, so provide the expected alias.
  if [[ "$(basename "$cli_root")" == "nilvcli" ]]; then
    ln -sfn "$cli_root" "${ni_shared_root}/LabVIEW CLI"
  fi

  echo "Installed LUnit CLI operation in ${operations_root}/LUnitCLI"
}

run_labview_cli() {
  local title="$1"
  shift

  echo "::group::${title}"
  LabVIEWCLI \
    -LogToConsole TRUE \
    "$@" \
    -LabVIEWPath "$LABVIEW_PATH" \
    -Headless
  echo "::endgroup::"
}

if [[ ! -x "$LABVIEW_PATH" ]]; then
  echo "LabVIEW executable not found: ${LABVIEW_PATH}" >&2
  exit 1
fi

install_application_payload "g-cli"
install_application_payload "lunit"
install_lunit_cli_operation

run_labview_cli "Mass compile source" \
  -OperationName MassCompile \
  -DirectoryToCompile "${WORKSPACE}/Source" \
  -LogFilePath "${BUILD_LOG_ROOT}/mass-compile-source.log"

run_labview_cli "Mass compile tests" \
  -OperationName MassCompile \
  -DirectoryToCompile "${WORKSPACE}/Testing" \
  -LogFilePath "${BUILD_LOG_ROOT}/mass-compile-tests.log"

run_labview_cli "Build LVLog packed project library" \
  -OperationName ExecuteBuildSpec \
  -ProjectPath "${WORKSPACE}/LV Logging.lvproj" \
  -TargetName "My Computer" \
  -BuildSpecName "LVLog PPL" \
  -LogFilePath "${BUILD_LOG_ROOT}/build-ppl.log"

if ! find "${WORKSPACE}/builds" -type f -name 'LVLog.lvlibp' -print -quit | grep -q .; then
  echo "The LVLog PPL build completed without producing LVLog.lvlibp" >&2
  exit 1
fi

run_labview_cli "Run LUnit tests" \
  -OperationName LUnit \
  -Path "${WORKSPACE}/Testing/Testing.lvproj" \
  -Parallel False \
  -ClearIndex True \
  -CustomReports "XML Report" \
  -ReportPath "${TEST_RESULT_ROOT}/lunit.xml" \
  -LogFilePath "${BUILD_LOG_ROOT}/lunit-cli.log"

if [[ ! -s "${TEST_RESULT_ROOT}/lunit.xml" ]]; then
  echo "LUnit completed without producing a test report" >&2
  exit 1
fi

echo "LabVIEW CI completed successfully"
