#!/bin/bash
#
# Send a Mac mini status report (uptime, disk space, IP addresses) via Pushover.
# Designed to run from cron.

set -u

# cron runs with a minimal PATH; ipconfig lives in /usr/sbin
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

TOKENS_FILE="/Users/avteam/Tokens.sh"
HOME_DIR="/Users/avteam"
BACKUP_VOLUME="/Volumes/VideoBackup"
LOG_FILE="/Users/avteam/Library/Logs/mac-status.log"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
}

# --------------------------------------------------------------- credentials
# Use the tokens from the environment if already set, otherwise load them
if [ -z "${PUSHOVER_TOKEN:-}" ] || [ -z "${PUSHOVER_USER:-}" ]; then
	if [ -f "$TOKENS_FILE" ]; then
		# shellcheck source=/dev/null
		source "$TOKENS_FILE"
	fi
fi
if [ -z "${PUSHOVER_TOKEN:-}" ] || [ -z "${PUSHOVER_USER:-}" ]; then
	log "ERROR: PUSHOVER_TOKEN and PUSHOVER_USER not set (checked $TOKENS_FILE)"
	exit 1
fi

# ------------------------------------------------------------------- helpers
free_space() {
	df -h "$1" 2>/dev/null | awk 'NR==2 {print $4 " free of " $2}'
}

ip_for() {
	local ip
	ip=$(ipconfig getifaddr "$1" 2>/dev/null)
	echo "${ip:-not connected}"
}

# ----------------------------------------------------------- collect status
UPTIME=$(uptime | sed -E 's/^ *//; s/, *[0-9]+ users?.*//')

HOME_SPACE=$(free_space "$HOME_DIR")

# A real mount point is on a different device from /Volumes. Without this
# check, df would quietly report the internal disk if the drive is missing.
if [ -d "$BACKUP_VOLUME" ] && \
   [ "$(stat -f %d "$BACKUP_VOLUME")" != "$(stat -f %d /Volumes)" ]; then
	BACKUP_SPACE=$(free_space "$BACKUP_VOLUME")
else
	BACKUP_SPACE="NOT MOUNTED"
fi

MESSAGE="$(hostname -s) status
Uptime: $UPTIME
Home directory: ${HOME_SPACE:-unknown}
Backup drive: $BACKUP_SPACE
en0 (wired): $(ip_for en0)
en1 (wireless): $(ip_for en1)"

# --------------------------------------------------------------------- send
RESPONSE=$(curl -s -m 30 --retry 3 \
	--form-string "token=$PUSHOVER_TOKEN" \
	--form-string "user=$PUSHOVER_USER" \
	--form-string "message=$MESSAGE" \
	https://api.pushover.net/1/messages.json)

if echo "$RESPONSE" | grep -q '"status":1'; then
	log "Sent: $(echo "$MESSAGE" | tr '\n' '|')"
else
	log "ERROR: Pushover send failed. Response: ${RESPONSE:-no response}"
	log "Message was: $(echo "$MESSAGE" | tr '\n' '|')"
	exit 2
fi
