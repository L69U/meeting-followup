# Verification record

## Verified on Windows

- Python standard-library gateway tests: authentication before provider invocation; missing server configuration fails closed; UTF-8 JSON responses; malformed requests; audio multipart contains English language and segment timestamps; empty/no-speech audio response; summary schema checks; unknown owner/date retained; unsupported evidence flagged; provider rate-limit mapping; invalid/non-finite timestamps rejected.
- These tests mock the external provider. They do not establish real speech recognition quality or real Groq connectivity.

## Implemented but not compiled or device-tested

- SwiftUI meeting list, file import, editable transcript, TXT export, summary editing and export, follow-up confirmation/completion.
- AVAudioPlayer playback, seeking, timestamp playback, playback shutdown when leaving meeting.
- Local JSON persistence, protected audio files, Keychain gateway token.
- Device-side five-minute M4A conversion, upload size checks, per-part saved checkpoints, resume from completed parts, absolute transcript timestamp offsets. Old transcript remains until all parts succeed.
- Four XCTest cases for old-record decoding, checkpoint persistence without replacing edits, stale-summary export warning and unconfirmed-task export. Authored but NOT run on this Windows machine.

## Required next evidence

1. Xcode compile against an iOS SDK; resolve compiler/API issues if found.
2. iPhone: import a real Voice Memos M4A; listen/seek, lock/unlock, interrupt with a call; inspect persistence after relaunch.
3. Configured HTTPS gateway and provider credentials: process an authorized English test recording; audit prices, quantities, units, dates and task source quotes against audio.
4. Test network failure, app backgrounding, retry, oversized files and quota exhaustion on device.
   Include a recording over 24 MB and a meeting spanning several five-minute parts; audit boundary words, seek accuracy after offsets, interruption after one saved part, and resumption after relaunch. Pure-silence parts currently produce a no-speech error and require user review rather than silently skipping content.
5. Production service authentication/quota design and final privacy/data-retention policy.
6. English UI, icon, screenshots, App Store listing, signing, TestFlight and actual App Store review.

Available equipment confirmed by user: Windows and iPhone; no Mac currently. No cloud deployment, developer subscription purchase, repository publication or App Store submission has been performed.
