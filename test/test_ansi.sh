#! /bin/bash

# wgetpaste test script (stripping ANSI codes)
# Based on test/test.sh
# Exit code: number of mismatched downloads or 1 for general failure
# Copyright (C) 2022  Oskari Pirhonen <xxc3ncoredxx@gmail.com>

# Don't assume the test is being run from the same directory as the script
TEST_DIR="$(dirname "$0")"
ANSI_FILE="$TEST_DIR/red.txt"
NOANSI_FILE="$TEST_DIR/red_no_ansi.txt"
DL_DIR="$(mktemp -q -d /tmp/wgetpaste_test_ansi.XXXXX)"
# Services to hard skip
# Pre-declare as map to maintain type even if empty
# key -> value := service -> reason
declare -A HARD_SKIPS
HARD_SKIPS=(['codepad']='always times out')
# Services expected to require an authorization token
AUTH_SKIPS=('gists' 'snippets')
# Used to save the first working service
WORKING=
FAILED_PASTE=0
DL_MISMATCH=0

# Test that temp directory was created
if [ ! -d "$DL_DIR" ]; then
    echo "Failed to create temporary download directory: $DL_DIR"
    exit 1
fi
echo "Using download directory: $DL_DIR"

# Post test file into each service until one succeeds
for serv in $("$TEST_DIR"/../wgetpaste -S --completions); do
    # Hard skips
    for hs in "${!HARD_SKIPS[@]}"; do
        if [ "$serv" == "$hs" ]; then
            echo "HARD SKIP on $serv -- reason: ${HARD_SKIPS[$serv]}"
            continue 2
        fi
    done

    # Log errors to analyze the reason
    # Use verbose output to get more meaningful errors
    # Log deleted at the end of each loop unless error other than 401
    echo -n "Posting to $serv: "
    ERROR_LOG="$DL_DIR/$serv-error.log"
    URL="$("$TEST_DIR"/../wgetpaste -r -s "$serv" -v "$ANSI_FILE" 2>"$ERROR_LOG")"
    STATUS="$?"

    # Skip failed posts (eg, not authorized for GitHub/GitLab, service error)
    if [ "$STATUS" -ne 0 ]; then
        if (grep -iq "HTTP.*401.*Unauthorized" "$ERROR_LOG"); then
            # Check if a 401 is expected behavior. If it isn't, mark as fail
            for as in "${AUTH_SKIPS[@]}"; do
                if [ "$serv" == "$as" ]; then
                    echo "SKIPPING, needs authorization..."
                    rm "$ERROR_LOG"
                    continue 2
                fi
            done
            echo "UNEXPECTED 401, skipping..."
        else
            echo "SKIPPING, failed to post..."
        fi

        continue
    fi
    echo "SUCCESS!"

    echo -n "Downloading from $serv: "
    if ! (wget -q "$URL" -O "/dev/null" 2>>"$ERROR_LOG"); then
        echo "FAILED, skipping..."
        continue
    fi
    echo "SUCCESS!"
    rm "$ERROR_LOG"

    # This is the service we want to use
    echo "Using service $serv"
    WORKING="$serv"
    break
done

# Test if we have a working service
if [ -z "$WORKING" ]; then
    echo "No working service found!"
    for log in "$DL_DIR"/*.log; do
        echo "$(basename "$log"):"
        cat "$log"
    done
    rm -rf "$DL_DIR"
    exit 1
fi

# Paste stuff. Use a short timeout between requests (we're friendly after all!)
sleep 1
echo -n "Pasting command output (cat): "
ERROR_LOG="$DL_DIR/command-error.log"
URL="$("$TEST_DIR"/../wgetpaste -N -r -s "$WORKING" -v -c "cat $ANSI_FILE" 2>"$ERROR_LOG")"
if [ $? -ne 0 ]; then
    echo "FAILED!"
    FAILED_PASTE=$((FAILED_PASTE + 1))
else
    echo "SUCCESS!"

    echo -n "Downloading: "
    if ! (wget -q "$URL" -O "$DL_DIR/command.txt" 2>>"$ERROR_LOG"); then
        echo "FAILED!"
        FAILED_PASTE=$((FAILED_PASTE + 1))
    else
        echo "SUCCESS"
        rm "$ERROR_LOG"

        echo "Removing 'command run' header"
        sed -i -e '1d' "$DL_DIR/command.txt"
    fi
fi

sleep 1
echo -n "Pasting stdin (cat | wgetpaste): "
ERROR_LOG="$DL_DIR/stdin-error.log"
URL="$(cat "$ANSI_FILE" | "$TEST_DIR"/../wgetpaste -N -r -s "$WORKING" -v 2>"$ERROR_LOG")"
if [ $? -ne 0 ]; then
    echo "FAILED!"
    FAILED_PASTE=$((FAILED_PASTE + 1))
else
    echo "SUCCESS!"

    echo -n "Downloading: "
    if ! (wget -q "$URL" -O "$DL_DIR/stdin.txt" 2>>"$ERROR_LOG"); then
        echo "FAILED!"
        FAILED_PASTE=$((FAILED_PASTE + 1))
    else
        echo "SUCCESS!"
        rm "$ERROR_LOG"
    fi
fi

sleep 1
echo -n "Pasting a file: "
ERROR_LOG="$DL_DIR/file-error.log"
URL="$("$TEST_DIR"/../wgetpaste -N -r -s "$WORKING" -v "$ANSI_FILE" 2>"$ERROR_LOG")"
if [ $? -ne 0 ]; then
    echo "FAILED!"
    FAILED_PASTE=$((FAILED_PASTE + 1))
else
    echo "SUCCESS!"

    echo -n "Downloading: "
    if ! (wget -q "$URL" -O "$DL_DIR/file.txt" 2>>"$ERROR_LOG"); then
        echo "FAILED!"
        FAILED_PASTE=$((FAILED_PASTE + 1))
    else
        echo "SUCCESS!"
        rm "$ERROR_LOG"
    fi
fi

# Compare downloaded files
for dl_file in "$DL_DIR"/*.txt; do
    echo -n "Testing file $dl_file: "
    # Ignore missing trailing newline and extra empty lines in downloaded file
    if (diff -q -Z -B "$NOANSI_FILE" "$dl_file" &>/dev/null); then
        echo "SUCCESS!"
    else
        echo "FAILED!"
        DL_MISMATCH=$((DL_MISMATCH + 1))
    fi
done

echo "Total failed pastes: $FAILED_PASTE"
echo "Total mismatches: $DL_MISMATCH"

# Print failure logs
if [ $FAILED_PASTE -ne 0 ]; then
    for log in "$DL_DIR"/*.log; do
        echo "$(basename "$log"):"
        cat "$log"
    done
# Delete download directory if all tests succeeded
elif [ $DL_MISMATCH -eq 0 ]; then
    echo "Deleting download directory"
    rm -rf "$DL_DIR"
fi

exit "$DL_MISMATCH"
