#!/bin/bash

export VIDEO_LOCATION="/Users/avteam/Movies"
export BACKUP_LOCATION="/Volumes/VideoBackup/ABC Service Videos Backup"
export FORMER_ONEDRIVE_LOCATIONS="/Users/avteam/OneDrive - Above Bar Church/Recordings - Sundays/"
export ONEDRIVE_LOCATION="/Users/avteam/OneDrive - Recordings"
export ONEDRIVE_VIDEO_LOCATION="${ONEDRIVE_LOCATION}/Raw Video"
export ONEDRIVE_AUDIO_LOCATION="${ONEDRIVE_LOCATION}/Raw Audio"
export FFMPEG=/Users/avteam/bin/ffmpeg

export MARKER_FILE=DoNotDelete-ProcessedToHere.mp4

# check source and target locations exist, exit with error if not
if [ ! -e "$VIDEO_LOCATION" ]
then
	echo "Cannot access source videos at $VIDEO_LOCATION"
	exit 10
fi
if [ ! -e "$BACKUP_LOCATION" ]
then
	echo "Cannot backup - backup location $BACKUP_LOCATION doesn't exist."
	exit 11
fi
if [ ! -e "$ONEDRIVE_VIDEO_LOCATION" ]
then
	echo "Cannot access onedrive folder - $ONEDRIVE_VIDEO_LOCATION"
	exit 12
fi

# create a marker file if it doesn't exist, so the find command in the for loop doesn't fail
if [ ! -e "$VIDEO_LOCATION/$MARKER_FILE" ]
then
	echo "Updating marker file early - $VIDEO_LOCATION/$MARKER_FILE"
	touch "$VIDEO_LOCATION/$MARKER_FILE"
fi

cd $VIDEO_LOCATION
for INFILEMP4 in `find . -newer "$MARKER_FILE" -name "*.mp4"`
do
	cd $VIDEO_LOCATION
	if [ ! -e "$INFILEMP4" ]
	then
		echo "Cannot access file $INFILEMP4 - perhaps it had spaces in the file or path name."
		exit 13
	fi
	echo "Processing file $INFILEMP4"
	MP4HASH=`md5 -q "$INFILEMP4"`
	echo $MP4HASH
	# outfile mp3
	OUTFILEMP3=`echo "$INFILEMP4" | sed 's/mp4/mp3/'`
	echo "Generating MP3 to $OUTFILEMP3"
	$FFMPEG -i "$INFILEMP4" -codec:a libmp3lame -q:a 3 "$OUTFILEMP3"
	# check for mp3
	if [ ! -e "$OUTFILEMP3" ]
	then
		echo "MP3 file was not created at $OUTFILEMP3"
	fi

	# back up to external drive, check hash
# backup drive is read only currently
	echo "Backing up $INFILEMP4 to backup location $BACKUP_LOCATION"
	cp "$INFILEMP4" "$BACKUP_LOCATION"
	cd "$BACKUP_LOCATION"
	MP4HASH_BACKUP=`md5 -q "$INFILEMP4"`
	if test "$MP4HASH" != "$MP4HASH_BACKUP";
	then
		echo "MP4 backup file does not have the same hash as the original"
		exit 13
	fi

	# move to onedrive
	echo "Moving files to OneDrive"
	if [ -e "$VIDEO_LOCATION/$INFILEMP4" ]
	then
		echo "Moving $VIDEO_LOCATION/$INFILEMP4 to $ONEDRIVE_VIDEO_LOCATION"
		mv "$VIDEO_LOCATION/$INFILEMP4" "$ONEDRIVE_VIDEO_LOCATION"
	fi
	if [ -e "$VIDEO_LOCATION/$OUTFILEMP3" ]
	then
		echo "Moving $VIDEO_LOCATION/$OUTFILEMP3 to $ONEDRIVE_AUDIO_LOCATION"
		mv "$VIDEO_LOCATION/$OUTFILEMP3" "$ONEDRIVE_AUDIO_LOCATION"
	fi

	#check hash
	cd "$ONEDRIVE_VIDEO_LOCATION"
	MP4HASH_ONEDRIVE=`md5 -q "$INFILEMP4"`
	if test "$MP4HASH" != "$MP4HASH_ONEDRIVE";
	then
		echo "MP4 file moved to onedrive does not have the same hash as the original"
		exit 14
	fi

done

echo "Updating marker file late - $MARKER_FILE"
touch "$VIDEO_LOCATION/$MARKER_FILE"

exit 0
