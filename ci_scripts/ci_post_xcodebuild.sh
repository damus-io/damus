#!/bin/sh

set -eu

if ! command -v sentry-cli >/dev/null 2>&1; then
  echo "Installing sentry-cli on Xcode Cloud builder"
  SENTRY_CLI_VERSION="3.4.2"
  export SENTRY_CLI_VERSION
  curl -fsSL https://sentry.io/get-cli/ | SENTRY_CLI_VERSION="$SENTRY_CLI_VERSION" sh
fi

if ! command -v sentry-cli >/dev/null 2>&1; then
  echo "warning: sentry-cli not installed, skipping Sentry dSYM upload"
  exit 0
fi

if [ -z "${CI_ARCHIVE_PATH:-}" ]; then
  echo "warning: CI_ARCHIVE_PATH is not set, skipping Sentry dSYM upload"
  exit 0
fi

DSYM_PATH="${CI_ARCHIVE_PATH}/dSYMs"
if [ ! -d "${DSYM_PATH}" ]; then
  echo "warning: No dSYMs directory found at ${DSYM_PATH}, skipping Sentry dSYM upload"
  exit 0
fi

if [ -z "${SENTRY_AUTH_TOKEN:-}" ]; then
  echo "warning: SENTRY_AUTH_TOKEN is not set, skipping Sentry dSYM upload"
  exit 0
fi

if ! error_output=$(sentry-cli debug-files upload --auth-token "${SENTRY_AUTH_TOKEN}" --org damus-nostr-inc --project apple-ios --include-sources "${DSYM_PATH}" 2>&1); then
  echo "warning: sentry-cli failed to upload dSYMs with sources from ${DSYM_PATH}: ${error_output}"
  if ! error_output=$(sentry-cli debug-files upload --auth-token "${SENTRY_AUTH_TOKEN}" --org damus-nostr-inc --project apple-ios "${DSYM_PATH}" 2>&1); then
    echo "warning: sentry-cli failed to upload dSYMs from ${DSYM_PATH}: ${error_output}"
  fi
fi
