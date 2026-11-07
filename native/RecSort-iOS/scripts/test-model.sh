#!/bin/sh
set -eu
BASE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_OUTPUT=$(mktemp -d "${TMPDIR:-/tmp}/recsort-ios-tests.XXXXXX")
trap 'rm -rf "$TEST_OUTPUT"' EXIT
xcrun swiftc -module-cache-path "$TEST_OUTPUT/cache" "$BASE_DIR/RecSort/VideoRecord.swift" "$BASE_DIR/Tests/main.swift" -o "$TEST_OUTPUT/model-tests"
"$TEST_OUTPUT/model-tests"
