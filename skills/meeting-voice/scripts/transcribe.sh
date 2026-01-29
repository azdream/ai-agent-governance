#!/bin/bash
# transcribe.sh - 오디오/비디오 파일을 텍스트로 전사
# Usage: ./transcribe.sh <input_file> [--lang <lang>] [--output <path>]

set -e

INPUT_FILE="$1"
LANG="auto"
OUTPUT=""

# Parse arguments
shift
while [[ $# -gt 0 ]]; do
    case $1 in
        --lang)
            LANG="$2"
            shift 2
            ;;
        --output)
            OUTPUT="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Validate input
if [[ -z "$INPUT_FILE" ]] || [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: Input file not found: $INPUT_FILE" >&2
    exit 1
fi

# Get file extension
EXT="${INPUT_FILE##*.}"
EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Extract audio if video file
AUDIO_FILE="$INPUT_FILE"
case "$EXT_LOWER" in
    mp4|mov|webm|mkv|avi)
        echo "Extracting audio from video..." >&2
        AUDIO_FILE="$TEMP_DIR/audio.wav"
        ffmpeg -i "$INPUT_FILE" -vn -acodec pcm_s16le -ar 16000 -ac 1 "$AUDIO_FILE" -y -loglevel error
        ;;
    mp3|m4a|ogg|flac)
        # Convert to wav for whisper
        echo "Converting audio format..." >&2
        AUDIO_FILE="$TEMP_DIR/audio.wav"
        ffmpeg -i "$INPUT_FILE" -acodec pcm_s16le -ar 16000 -ac 1 "$AUDIO_FILE" -y -loglevel error
        ;;
    wav)
        # Use as-is
        ;;
    *)
        echo "Error: Unsupported format: $EXT" >&2
        exit 1
        ;;
esac

# Transcribe using whisper or summarize
TRANSCRIPT=""

if command -v whisper &> /dev/null; then
    echo "Transcribing with Whisper..." >&2
    
    WHISPER_LANG=""
    if [[ "$LANG" != "auto" ]]; then
        WHISPER_LANG="--language $LANG"
    fi
    
    TRANSCRIPT=$(whisper "$AUDIO_FILE" --model base --output_format txt $WHISPER_LANG --output_dir "$TEMP_DIR" 2>/dev/null)
    
    # Read from output file
    TXT_FILE="$TEMP_DIR/audio.txt"
    if [[ -f "$TXT_FILE" ]]; then
        TRANSCRIPT=$(cat "$TXT_FILE")
    fi
    
elif command -v summarize &> /dev/null; then
    echo "Transcribing with summarize..." >&2
    TRANSCRIPT=$(summarize "$AUDIO_FILE" --extract-only 2>/dev/null)
    
else
    echo "Error: No transcription tool found (whisper or summarize required)" >&2
    exit 1
fi

# Output
if [[ -n "$OUTPUT" ]]; then
    echo "$TRANSCRIPT" > "$OUTPUT"
    echo "Transcript saved to: $OUTPUT" >&2
else
    echo "$TRANSCRIPT"
fi
