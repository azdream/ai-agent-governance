#!/bin/bash
# summarize-meeting.sh - 전사 내용을 회의록으로 정리
# Usage: ./summarize-meeting.sh <transcript_file> [--output <path>] [--title <title>]

set -e

TRANSCRIPT_FILE="$1"
OUTPUT=""
TITLE=""
DATE=$(date +"%Y-%m-%d")
TIME=$(date +"%H:%M")

# Parse arguments
shift
while [[ $# -gt 0 ]]; do
    case $1 in
        --output)
            OUTPUT="$2"
            shift 2
            ;;
        --title)
            TITLE="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Validate input
if [[ -z "$TRANSCRIPT_FILE" ]] || [[ ! -f "$TRANSCRIPT_FILE" ]]; then
    echo "Error: Transcript file not found: $TRANSCRIPT_FILE" >&2
    exit 1
fi

TRANSCRIPT=$(cat "$TRANSCRIPT_FILE")

# Generate title if not provided
if [[ -z "$TITLE" ]]; then
    TITLE="Meeting $DATE"
fi

# Create prompt for LLM
PROMPT="다음 회의 전사 내용을 분석해서 회의록을 작성해주세요.

## 출력 형식 (Markdown)

# 회의록: [적절한 제목]
📅 $DATE | ⏱️ [회의 길이 추정]

## 📋 요약
(회의 핵심 내용 3-5문장)

## 💬 주요 논의
- (논의된 주제들을 bullet point로)

## ✅ 결정 사항
- (확정된 것들)

## 📌 액션 아이템
| 담당자 | 내용 | 마감일 |
|--------|------|--------|
| ... | ... | ... |

## 🔜 다음 단계
- (후속 조치 사항)

---

## 전사 내용:
$TRANSCRIPT"

# Call LLM (using oracle or similar)
if command -v oracle &> /dev/null; then
    MEETING_NOTE=$(echo "$PROMPT" | oracle --no-stream 2>/dev/null)
elif command -v llm &> /dev/null; then
    MEETING_NOTE=$(echo "$PROMPT" | llm 2>/dev/null)
else
    # Fallback: just format the transcript
    MEETING_NOTE="# 회의록: $TITLE
📅 $DATE | ⏱️ $TIME

## 📋 전사 내용
$TRANSCRIPT

---
*자동 생성 by Meeting Voice Skill*
*LLM 요약 도구가 없어 원본 전사만 포함됨*"
fi

# Add footer
MEETING_NOTE="$MEETING_NOTE

---
*자동 생성 by Meeting Voice Skill 🎙️*"

# Output
if [[ -n "$OUTPUT" ]]; then
    echo "$MEETING_NOTE" > "$OUTPUT"
    echo "Meeting note saved to: $OUTPUT" >&2
else
    echo "$MEETING_NOTE"
fi
