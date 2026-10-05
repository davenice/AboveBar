#!/bin/bash
#
# Process new service recordings in $VIDEO_LOCATION:
#   1. Back up each new MP4 to the external drive and verify the copy
#   2. Convert the MP4 to MP3
#   3. Copy MP4 and MP3 to OneDrive and verify the copies
#   4. Only then remove the originals from $VIDEO_LOCATION
#
# Any file that fails is left in place and retried on the next run.
# Designed to run from cron; everything is logged to $LOG_FILE.
#
# Exit codes:
#   0  success          10 video folder missing     11 backup drive problem
#   12 OneDrive problem 16 lock problem             17 ffmpeg missing
#   18 marker problem   20 one or more files failed

set -u
set -o pipefail

# cron runs with a minimal PATH, so set one explicitly
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# ---------------------------------------------------------------- settings
VIDEO_LOCATION="/Users/avteam/Movies"
BACKUP_VOLUME="/Volumes/VideoBackup"
BACKUP_LOCATION="$BACKUP_VOLUME/ABC Service Videos Backup"
ONEDRIVE_LOCATION="/Users/avteam/OneDrive - Recordings"
ONEDRIVE_VIDEO_LOCATION="$ONEDRIVE_LOCATION/Raw Video"
ONEDRIVE_AUDIO_LOCATION="$ONEDRIVE_LOCATION/Raw Audio"
FFMPEG="/Users/avteam/bin/ffmpeg"

MARKER_FILE="$VIDEO_LOCATION/DoNotDelete-ProcessedToHere.mp4"
LOG_FILE="/Users/avteam/Library/Logs/process-videos.log"
LOCK_DIR="/tmp/process-videos.lock"

# Ignore files modified in the last N minutes (they may still be recording
# or copying). They will be picked up on a later run.
MIN_AGE_MINUTES=10

# ----------------------------------------------------------------- logging
mkdir -p "$(dirname "$LOG_FILE")"

# Keep the log from growing forever: roll it over at ~5 MB
if [ -f "$LOG_FILE" ] && [ "$(stat -f %z "$LOG_FILE")" -gt 5000000 ]; then
	mv -f "$LOG_FILE" "$LOG_FILE.old"
fi

log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
}

fail() {
	log "ERROR: $2"
	exit "$1"
}

# Check a folder exists and can actually be written to (catches read-only
# drives and macOS privacy blocks, which a simple existence test misses)
check_writable() {
	local dir="$1" test_file="$1/.write-test-$$"
	[ -d "$dir" ] || return 1
	touch "$test_file" 2>>"$LOG_FILE" || return 1
	rm -f "$test_file"
}

# ------------------------------------------------------------ single run lock
# Prevent two runs overlapping if one takes longer than the cron interval
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
	OLD_PID=$(cat "$LOCK_DIR/pid" 2>/dev/null)
	if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
		log "Another run (PID $OLD_PID) is still in progress - exiting."
		exit 0
	fi
	log "Removing stale lock left by PID ${OLD_PID:-unknown}"
	rm -rf "$LOCK_DIR"
	mkdir "$LOCK_DIR" || fail 16 "Could not create lock $LOCK_DIR"
fi
echo $$ > "$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR"' EXIT

# --------------------------------------------------------- pre-flight checks
[ -d "$VIDEO_LOCATION" ] || fail 10 "Cannot access source videos at $VIDEO_LOCATION"
[ -x "$FFMPEG" ] || fail 17 "ffmpeg not found or not executable at $FFMPEG"

# Make sure the backup drive is really mounted, and that /Volumes/VideoBackup
# isn't just an empty folder on the internal disk. A real mount point sits on
# a different device from its parent folder.
[ -d "$BACKUP_VOLUME" ] || fail 11 "Backup drive not mounted at $BACKUP_VOLUME"
if [ "$(stat -f %d "$BACKUP_VOLUME")" = "$(stat -f %d "$(dirname "$BACKUP_VOLUME")")" ]; then
	fail 11 "$BACKUP_VOLUME is a plain folder, not the backup drive. Check the drive is connected (it may have mounted as 'VideoBackup 1')."
fi
check_writable "$BACKUP_LOCATION" || fail 11 "Cannot write to $BACKUP_LOCATION (drive read-only, folder missing, or cron lacks Full Disk Access)"
check_writable "$ONEDRIVE_VIDEO_LOCATION" || fail 12 "Cannot write to $ONEDRIVE_VIDEO_LOCATION"
check_writable "$ONEDRIVE_AUDIO_LOCATION" || fail 12 "Cannot write to $ONEDRIVE_AUDIO_LOCATION"

if [ ! -e "$MARKER_FILE" ]; then
	log "Marker file missing - creating $MARKER_FILE"
	touch "$MARKER_FILE" || fail 18 "Could not create marker file"
fi

# Work out now what the marker will be set to at the end. Any file too new
# to process this run will still be newer than the marker next time.
MARKER_TIME=$(date -v-"$((MIN_AGE_MINUTES + 1))"M '+%Y%m%d%H%M.%S')

# ---------------------------------------------------------------- functions

# copy_and_verify SOURCE DEST_DIR EXPECTED_MD5
# Copies SOURCE into DEST_DIR and checks the copy matches. If an identical
# file is already there (e.g. from a previous partial run) that counts as
# success. Never overwrites a different file with the same name.
copy_and_verify() {
	local src="$1" dest="$2/$(basename "$1")" expected="$3" actual

	if [ -e "$dest" ]; then
		actual=$(md5 -q "$dest" 2>>"$LOG_FILE")
		if [ "$actual" = "$expected" ]; then
			log "  Already present and verified: $dest"
			return 0
		fi
		log "  ERROR: $dest already exists with different contents - not overwriting"
		return 1
	fi

	if ! cp "$src" "$dest" 2>>"$LOG_FILE"; then
		log "  ERROR: copy failed: $src -> $dest"
		rm -f "$dest"
		return 1
	fi

	actual=$(md5 -q "$dest" 2>>"$LOG_FILE")
	if [ "$actual" != "$expected" ]; then
		log "  ERROR: copy at $dest does not match the original - removing it"
		rm -f "$dest"
		return 1
	fi

	log "  Copied and verified: $dest"
}

process_file() {
	local mp4="$1" mp3 mp4_hash mp3_hash
	mp3="${mp4%.mp4}.mp3"

	log "Processing $mp4"
	mp4_hash=$(md5 -q "$mp4" 2>>"$LOG_FILE") || { log "  ERROR: could not read $mp4"; return 1; }
	log "  MD5 $mp4_hash"

	# Back up first, so the MP4 is safe even if the conversion fails
	copy_and_verify "$mp4" "$BACKUP_LOCATION" "$mp4_hash" || return 1

	log "  Converting to $mp3"
	# -nostdin stops ffmpeg swallowing the file list; -y overwrites any
	# partial MP3 from a previous failed run
	if ! "$FFMPEG" -nostdin -hide_banner -loglevel warning -y \
		-i "$mp4" -vn -codec:a libmp3lame -q:a 3 "$mp3" >>"$LOG_FILE" 2>&1; then
		log "  ERROR: ffmpeg conversion failed"
		rm -f "$mp3"
		return 1
	fi
	if [ ! -s "$mp3" ]; then
		log "  ERROR: MP3 was not created or is empty"
		return 1
	fi
	mp3_hash=$(md5 -q "$mp3" 2>>"$LOG_FILE") || return 1

	copy_and_verify "$mp4" "$ONEDRIVE_VIDEO_LOCATION" "$mp4_hash" || return 1
	copy_and_verify "$mp3" "$ONEDRIVE_AUDIO_LOCATION" "$mp3_hash" || return 1

	# Every copy is verified, so the originals can go
	if ! rm -f "$mp4" "$mp3"; then
		log "  WARNING: copies are fine but could not remove originals"
	fi
	log "  Done"
}

# ---------------------------------------------------------------- main loop
log "=== Run started ==="
COUNT=0
FAILURES=0

# -print0 / read -d '' handles spaces and odd characters in file names.
# The list is read on file descriptor 3 so nothing inside the loop can eat it.
while IFS= read -r -d '' FILE <&3; do
	COUNT=$((COUNT + 1))
	if ! process_file "$FILE"; then
		FAILURES=$((FAILURES + 1))
		log "  Leaving $FILE in place to retry next run"
	fi
done 3< <(find "$VIDEO_LOCATION" -type f -name '*.mp4' \
	-newer "$MARKER_FILE" -mmin +"$MIN_AGE_MINUTES" \
	! -path "$MARKER_FILE" -print0)

if [ "$FAILURES" -gt 0 ]; then
	log "=== Finished with $FAILURES failure(s) out of $COUNT file(s). Marker not updated. ==="
	exit 20
fi

touch -t "$MARKER_TIME" "$MARKER_FILE" || fail 18 "Could not update marker file"
log "=== Finished: $COUNT file(s) processed ==="
exit 0
