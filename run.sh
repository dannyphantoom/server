#!/bin/sh

# Script to run the assembly server and user-space chat application.
# This script is intended to be called by 'sudo' from the Makefile.

# Exit immediately if a command exits with a non-zero status.
set -e

PID_PYTHON=""

# Cleanup function for traps
cleanup() {
    SIGNAL_TYPE=$1
    echo # Newline for readability
    echo "INFO: run.sh received signal: $SIGNAL_TYPE. Cleaning up..."
    if [ -n "$PID_PYTHON" ]; then
        echo "Attempting to stop Python app (PID $PID_PYTHON)..."
        # Use kill -0 to check if process exists before trying to kill
        if kill -0 "$PID_PYTHON" 2>/dev/null; then
            kill "$PID_PYTHON"
            echo "Python app (PID $PID_PYTHON) terminated."
        else
            echo "Python app (PID $PID_PYTHON) already stopped or not found."
        fi
    else
        echo "Python app PID not set or not started by this script."
    fi

    # Exit with 130 for INT/TERM (Ctrl+C behavior)
    if [ "$SIGNAL_TYPE" = "INT" ] || [ "$SIGNAL_TYPE" = "TERM" ]; then
        exit 130
    fi
    # For EXIT trap, the script will exit with the last command's status (SERVER_EXIT_CODE)
}

# Set traps
trap 'cleanup INT' INT
trap 'cleanup TERM' TERM
trap 'cleanup EXIT' EXIT

# 1. Start the user-space Python chat app in the background
# Since this script is run with sudo, the Python app also runs as root.
echo "Starting user-space chat app in the background (as root)..."
python3 userspace_chat_app/chat_app_receiver.py &
PID_PYTHON=$!
echo "User-space chat app started with PID $PID_PYTHON."

# 2. Wait a moment for the Python app to initialize
echo "Waiting 2 seconds for the chat app to initialize FIFO..."
sleep 2

# 3. Start the assembly server in the foreground
# Already running as root because the script is called with sudo.
echo "Starting assembly server from ./build/server (as root)..."
./build/server  # No 'sudo' needed here. Assumes server is in ./build/
SERVER_EXIT_CODE=$?
echo "Assembly server has finished with exit code $SERVER_EXIT_CODE."

# 4. Optionally, open Firefox
# This will also run as root. Consider if this is desired.
# If firefox is not essential, you might remove this or make it conditional.
OPEN_BROWSER=${OPEN_BROWSER:-true} # Set OPEN_BROWSER=false in env to skip
if [ "$OPEN_BROWSER" = "true" ]; then
    echo "Attempting to open Firefox (as root) to http://localhost:8080/ ..."
    (firefox http://localhost:8080/ &) # Run in a subshell and background to detach
fi

# The EXIT trap will handle the final cleanup of PID_PYTHON.
# Explicitly exit with the server's exit code.
exit $SERVER_EXIT_CODE





