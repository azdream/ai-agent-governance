---
name: meeting-voice
description: 음성 인식 기반 회의록 자동 생성. 마이크/파일 오디오 → 전사 → 요약/액션아이템 추출.
user-invocable: true
metadata: {"clawdbot":{"emoji":"🎙️","requires":{"bins":["ffmpeg"],"anyBins":["whisper","summarize"]},"primaryEnv":"OPENAI_API_KEY"}}
---

# Meeting Voice Skill

회의 내용을 음성으로 녹음하고 자동으로 정리합니다.

## 사용법

### 파일에서 회의록 생성
```
/meeting <파일경로>
/meeting ~/recordings/standup.mp3
/meeting /tmp/meeting.wav
```

### 옵션
- `--lang ko` : 언어 지정 (기본: 자동 감지)
- `--speakers` : 화자 분리 (지원 시)
- `--output <path>` : 출력 파일 경로 지정

## 지원 형식
- 오디오: mp3, wav, m4a, ogg, flac
- 비디오: mp4, mov, webm (오디오 추출)

## 출력
회의록에 포함되는 내용:
1. **📋 요약** - 회의 핵심 내용 3-5문장
2. **💬 주요 논의** - 논의된 주제들
3. **✅ 결정 사항** - 확정된 것들
4. **📌 액션 아이템** - 담당자, 마감일 포함
5. **🔜 다음 단계** - 후속 조치

## 예시

```
사용자: /meeting ~/Downloads/sprint-planning.m4a

트램: 🎙️ 회의록 생성 중...
     ✅ 전사 완료 (12분 32초)
     ✅ 요약 완료

     # 회의록: Sprint Planning
     📅 2026-01-29 | ⏱️ 12:32

     ## 📋 요약
     이번 스프린트에서 사용자 인증 시스템 구현을 
     최우선으로 진행하기로 결정했습니다...

     ## 📌 액션 아이템
     | 담당자 | 내용 | 마감일 |
     |--------|------|--------|
     | Chris | OAuth 설계 | 2/3 |
     | 트램 | API 문서화 | 2/5 |
```

## 내부 처리 흐름

```
1. 파일 형식 확인 → 필요시 오디오 추출 (ffmpeg)
2. 음성 → 텍스트 전사 (whisper 또는 summarize)
3. 전사 내용 → LLM 요약/구조화
4. Markdown 회의록 생성
5. 결과 전송
```

## 스크립트 위치
- `{baseDir}/scripts/transcribe.sh` - 전사 스크립트
- `{baseDir}/scripts/summarize-meeting.sh` - 요약 스크립트
- `{baseDir}/templates/meeting-note.md` - 출력 템플릿
