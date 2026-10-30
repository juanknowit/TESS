# Changelog

All notable changes to TESS are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-10-30

First release.

### Voice
- On-device “Hey Tess” wake word with a customisable name and language
- Follow-up questions without the wake word, and interrupting TESS mid-sentence
- TESS ignores her own voice, and keeps the mic off during her greeting and alerts
- macOS voices (including Premium voices) or OpenAI text-to-speech

### Brain
- Claude (with built-in web search), OpenAI, or a local Ollama model
- Ollama status check with automatic model selection, and fallbacks for models without tool or image support

### Skills
- Mac control: apps, volume, dark mode, screen lock, file search, screenshots, timers, system status
- Weather, web search, and news focused on your home city and country, in English or the local language
- Calendar and reminders
- Apple Music and Spotify playback
- Morning briefing, on request or automatically on the first unlock of the day
- “What am I looking at?” screen understanding
- Reading PDFs, Word, RTF, text and images, including the document you have open
- Typing into the current app
- Messages with a mandatory read-back before sending, and Apple Notes
- Long-term memory

### App
- Menu bar panel and animated HUD orb
- Dark sidebar settings: General, Brain, Voice, Memory, Usage, Permissions and About
- Usage statistics with per-provider tokens, a daily trend chart and live memory use
- One-click permission setup
- `build.sh` builds and installs with only the Command Line Tools

[1.0.0]: https://github.com/juanknowit/TESS/releases/tag/v1.0.0
