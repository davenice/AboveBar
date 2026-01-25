#! /bin/bash

if [[ -z "$PUSHOVER_TOKEN" ]] || [[ -z "$PUSHOVER_USER" ]]; then
    echo "Error: PUSHOVER_TOKEN and PUSHOVER_USER must be set." >&2
    echo "Please source the Tokens.sh file to set them." >&2
    exit 1
fi

MESSAGE=""
RETCODE=0

if [[ -z "$YOUTUBE_API_KEY" ]] || [[ -z "$YOUTUBE_CHANNEL_ID" ]]; then
    # The YOUTUBE_API_KEY should be added to a file like Tokens.sh and sourced.
    MESSAGE="Error: YOUTUBE_API_KEY or YOUTUBE_CHANNEL_ID environment variables must be set."
    echo "$MESSAGE" >&2
    RETCODE=1
elif ! command -v jq &> /dev/null; then
    MESSAGE="Error: The 'jq' command is not installed. Please install it to parse API responses (e.g., 'brew install jq')."
    echo "$MESSAGE" >&2
    RETCODE=2
else
    # Use the YouTube API to check for upcoming streams.
    # If a video is found via the public search API, its visibility is implicitly public.
    API_URL="https://www.googleapis.com/youtube/v3/search?part=snippet&channelId=${YOUTUBE_CHANNEL_ID}&eventType=upcoming&type=video&maxResults=5&key=${YOUTUBE_API_KEY}"

    API_RESPONSE=$(curl -s "$API_URL")

    # Check for API errors first
    API_ERROR=$(echo "$API_RESPONSE" | jq -r '.error.message')

    if [[ "$API_ERROR" != "null" ]]; then
        MESSAGE="YouTube API Error: $API_ERROR"
        RETCODE=3
    else
        # We've got as far as making a request which has worked. We won't exit with an error.
        # Check for any upcoming stream.
        echo "Querying $API_URL"
        FOUND_STREAM_TITLE=$(echo "$API_RESPONSE" | jq -r '.items[0].snippet.title')
        FOUND_CHANNEL_TITLE=$(echo "$API_RESPONSE" | jq -r '.items[0].snippet.channelTitle')

        if [[ "$FOUND_STREAM_TITLE" != "null" ]]; then
            MESSAGE="✅ YouTube OK: Upcoming stream found - \"$FOUND_STREAM_TITLE\" ($FOUND_CHANNEL_TITLE)"
        else
            MESSAGE="⚠️ YouTube WARNING: No public upcoming stream scheduled."
        fi
    fi
fi
echo $MESSAGE
# Send the result via Pushover
curl -s --form-string "token=$PUSHOVER_TOKEN" --form-string "user=$PUSHOVER_USER" --form-string "message=$MESSAGE" https://api.pushover.net/1/messages.json
exit $RETCODE