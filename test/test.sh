#! /bin/bash

# wgetpaste test script
# Exit code: number of mismatched downloads or 1 for general failure
# Copyright (C) 2021  xxc3nsoredxx

# Don't assume the test is being run from the same directory as the script
TEST_DIR="$(dirname "$0")"
TEST_FILE="$TEST_DIR/test.txt"
DL_DIR="$(mktemp -q -d /tmp/wgetpaste_test.XXXXX)"
DL_COUNT=0
DL_MISMATCH=0

# Test that temp directory was created
if [ ! -d "$DL_DIR" ]; then
    echo "Failed to create temporary download directory: $DL_DIR"
    exit 1
fi
echo "Using download directory: $DL_DIR"

# Post test file into each service (if possible)
# Download the resulting paste into /tmp/wgetpaste_test.XXXXX/<service>.txt
for s in $("$TEST_DIR"/../wgetpaste -S --completions); do
    # Ignore codepad (timing out)
    if [ "$s" == 'codepad' ]; then
        continue
    fi

    # Discard stderr output
    echo -n "Posting to $s: "
    URL="$("$TEST_DIR"/../wgetpaste -r -s "$s" "$TEST_FILE" 2>/dev/null)"
    STATUS="$?"

    # Skip failed posts (eg, not authorized for GitHub or GitLab)
    if [ "$STATUS" -ne 0 ]; then
        echo "FAILED, skipping..."
        continue
    fi
    echo "SUCCESS!"

    echo -n "Downloading from $s: "
    if ! (wget -q "$URL" -O "$DL_DIR/$s.txt" 2>/dev/null); then
        echo "FAILED, skipping..."
        continue
    fi
    echo "SUCCESS!"
    DL_COUNT=$((DL_COUNT + 1))
done

# Test if any files were downloaded
if [ "$DL_COUNT" -eq 0 ]; then
    echo "No files downloaded!"
    rm -rf "$DL_DIR"
    exit 1
fi

# Compare downloaded files
for f in "$DL_DIR"/*; do
    echo -n "Testing file $f: "
    # Ignore missing trailing newline in downloaded file
    if ! (diff -q -Z "$TEST_FILE" "$f" &>/dev/null); then
        echo "FAILED!"
        DL_MISMATCH=$((DL_MISMATCH + 1))
    else
        echo "SUCCESS!"
    fi
done

echo "Total mismatches: $DL_MISMATCH"

# Delete download directory if all tests succeeded
if [ "$DL_MISMATCH" -eq 0 ]; then
    echo "Deleting download directory"
    rm -rf "$DL_DIR"
fi

exit "$DL_MISMATCH"
