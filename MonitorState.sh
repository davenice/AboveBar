#! /bin/bash

if [[ -z "$PUSHOVER_TOKEN" || -z "$PUSHOVER_USER" ]]; then
    echo "Error: PUSHOVER_TOKEN and PUSHOVER_USER must be set." >&2
    echo "Please source the Tokens.sh file to set them." >&2
    exit 1
fi

echo "Failed to collect Mac Mini data at "`date` > tmp.data
(echo `uptime` | cut -d, -f1; echo "Home directory space: "`df -h /Users/avteam | awk '{print $4}' | tr '\n' ' '`; echo "Backup drive space: "`df -h /Volumes/VideoBackup/ | awk '{print $4}' | tr '\n' ' '`; echo "en0 (wired):" `ipconfig getifaddr en0`; echo "en1 (wireless): "`ipconfig getifaddr en1`) > tmp.data
curl -s --form-string "token=$PUSHOVER_TOKEN" --form-string "user=$PUSHOVER_USER" --form-string "message=`cat tmp.data`" https://api.pushover.net/1/messages.json