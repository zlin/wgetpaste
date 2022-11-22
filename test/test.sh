#! /bin/bash

# wgetpaste test script
# Exit code: number of mismatched downloads or 1 for general failure
# Copyright (C) 2021  xxc3nsoredxx

# Don't assume the test is being run from the same directory as the script
TEST_DIR="$(dirname "$0")"
TEST_FILE="$TEST_DIR/test.txt"
DL_DIR="$(mktemp -q --tmpdir -d wgetpaste_test.XXXXX)"
# Services to hard skip
# Pre-declare as map to maintain type even if empty
# key -> value := service -> reason
declare -A HARD_SKIPS
HARD_SKIPS=(['codepad']='always times out')
HARD_SKIP_COUNT=0
# Services expected to require an authorization token
AUTH_SKIPS=('gists' 'snippets')
AUTH_SKIP_COUNT=0
FAIL_SKIP_COUNT=0
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
for serv in $("$TEST_DIR"/../wgetpaste -S --completions); do
    # Hard skips
    for hs in "${!HARD_SKIPS[@]}"; do
        if [ "$serv" == "$hs" ]; then
            echo "HARD SKIP on $serv -- reason: ${HARD_SKIPS[$serv]}"
            HARD_SKIP_COUNT=$((HARD_SKIP_COUNT + 1))
            continue 2
        fi
    done

    # Log errors to analyze the reason
    # Use verbose output to get more meaningful errors
    # Log deleted at the end of each loop unless error other than 401
    echo -n "Posting to $serv: "
    ERROR_LOG="$DL_DIR/$serv-error.log"
    URL="$("$TEST_DIR"/../wgetpaste -r -s "$serv" -v "$TEST_FILE" 2>"$ERROR_LOG")"
    STATUS="$?"

    # Skip failed posts (eg, not authorized for GitHub/GitLab, service error)
    if [ "$STATUS" -ne 0 ]; then
        if (grep -iq "HTTP.*401.*Unauthorized" "$ERROR_LOG"); then
            # Check if a 401 is expected behavior. If it isn't, mark as fail
            for as in "${AUTH_SKIPS[@]}"; do
                if [ "$serv" == "$as" ]; then
                    echo "SKIPPING, needs authorization..."
                    AUTH_SKIP_COUNT=$((AUTH_SKIP_COUNT + 1))
                    rm "$ERROR_LOG"
                    continue 2
                fi
            done
            echo "UNEXPECTED 401, skipping..."
            FAIL_SKIP_COUNT=$((FAIL_SKIP_COUNT + 1))
        else
            echo "SKIPPING, failed to post..."
            FAIL_SKIP_COUNT=$((FAIL_SKIP_COUNT + 1))
        fi

        continue
    fi
    echo "SUCCESS!"

    echo -n "Downloading from $serv: "
    if ! (wget -q "$URL" -O "$DL_DIR/$serv.txt" 2>>"$ERROR_LOG"); then
        echo "FAILED, skipping..."
        FAIL_SKIP_COUNT=$((FAIL_SKIP_COUNT + 1))
        continue
    fi
    echo "SUCCESS!"
    DL_COUNT=$((DL_COUNT + 1))
    rm "$ERROR_LOG"
done

# Test if any files were downloaded
if [ "$DL_COUNT" -eq 0 ]; then
    echo "No files downloaded!"
    rm -rf "$DL_DIR"
    exit 1
fi

# Compare downloaded files
for dl_file in "$DL_DIR"/*.txt; do
    echo -n "Testing file $dl_file: "
    # Ignore missing trailing newline in downloaded file
    if (diff -q -Z "$TEST_FILE" "$dl_file" &>/dev/null); then
        echo "SUCCESS!"
    else
        echo "FAILED!"
        DL_MISMATCH=$((DL_MISMATCH + 1))
    fi
done

echo "Total mismatches: $DL_MISMATCH"
echo "Total skips: $((HARD_SKIP_COUNT + AUTH_SKIP_COUNT + FAIL_SKIP_COUNT))"

# Print non-auth failure logs
if [ "$FAIL_SKIP_COUNT" -ne 0 ]; then
    for log in "$DL_DIR"/*.log; do
        echo "$(basename "$log"):"
        cat "$log"
    done
fi

# Delete download directory if all tests succeeded
if [ "$DL_MISMATCH" -eq 0 ]; then
    echo "Deleting download directory"
    rm -rf "$DL_DIR"
fi

exit "$DL_MISMATCH"
