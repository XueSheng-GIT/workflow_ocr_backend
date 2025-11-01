#!/bin/bash

# Healthcheck script to verify age of a main.py process (not PID 1)

# Configuration
PROCESS_NAME="main.py"
MAX_AGE_SECONDS=600  # Maximum age in seconds (10 minutes)

# Get the PID of the process
PIDS=$(pgrep -f "$PROCESS_NAME")

# Loop through each PID and check its status
for PID in $PIDS; do
    # Skip PID 1
    if [[ "$PID" == "1" ]]; then
        continue
    fi 
    # Get the elapsed time (etime) from ps output
    ETIME=$(ps -p "$PID" -o etimes= | awk '{print $1}')

    # Check if ETIME exceeds the threshold
    if (( ETIME > MAX_AGE_SECONDS )); then
        echo "ERROR: $PROCESS_NAME (PID $PID) has been running for too long: $ETIME seconds."
	# Send SIGTERM to the process
        kill "$PID"
        echo "Sending SIGTERM to process $PID"
        exit 1
    else
        echo "OK: $PROCESS_NAME (PID $PID) is healthy (age: $ETIME seconds)."
    fi
done

exit 0
