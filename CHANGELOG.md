# Changelog

All notable changes to TESS are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.9.2-beta] — 2026-10-30

### Changed
- Installer: the names under TESS and Applications now sit on light pills, so they match and are easy to read (Finder always draws them in dark text on the installer's picture background, whatever the Mac's appearance)
- Installer window opens tall enough to show the whole artwork

### Fixed
- The installer script works with the Python that comes with Apple's Command Line Tools (3.9)

## [0.9.1-beta] — 2026-10-30

### Added
- Automatic updates: TESS checks GitHub for new versions shortly after launch and every few hours, shows what's new, and installs with one click (**Install and Relaunch**, **Remind Me Later** or **Skip This Version**)
- Updates are only installed when they match the published checksum and are signed with the same certificate, so settings, memory and permissions are kept
- **Updates** page in Settings with the current version and build, a **Check for updates** button, and switches for automatic checks and beta versions
- An "update available" banner in the menu bar panel, and a **Check for updates** button on the About page

### Changed
- Installer window redesigned in TESS's navy and cyan, with HUD rings and glowing chevrons
- API keys are kept in a single keychain item, so macOS asks for the keychain password at most once after an install or update (it moves your existing keys over automatically)

## [0.9.0-beta] — 2026-10-30

First public beta.

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
- Mail: check, search and read your inbox, and draft new emails and replies (read back before sending)
- Protocols: your own routines that open and quit apps, set the volume and appearance, play music, open links, run Apple Shortcuts, wait and speak
- Reading and summarising the current page in Safari, Chrome, Edge, Arc and Brave
- Currency conversion (rates by [Exchange Rate API](https://www.exchangerate-api.com)), stock and crypto prices, and football and US sports results
- Long-term memory and conversation history

### App
- Menu bar panel and animated HUD orb
- Dark sidebar settings: General, Brain, Voice, Skills, Protocols, Memory, History, Usage, Permissions and About
- Skills page with example phrases, the permissions each skill needs and a **Try** button
- Usage statistics with per-provider tokens, a daily trend chart and live memory use
- One-click permission setup, with hints when Dictation, a restart or a System Settings switch is still needed
- Recent conversations in the menu bar panel

### Install
- Drag-to-Applications disk image, universal for Apple silicon and Intel
- Every release is signed with the same certificate, so permissions survive updates
- `build.sh` builds and installs with only the Command Line Tools, signing with a stable local identity

[Unreleased]: https://github.com/juanknowit/TESS/compare/v0.9.2-beta...HEAD
[0.9.2-beta]: https://github.com/juanknowit/TESS/compare/v0.9.1-beta...v0.9.2-beta
[0.9.1-beta]: https://github.com/juanknowit/TESS/compare/v0.9.0-beta...v0.9.1-beta
[0.9.0-beta]: https://github.com/juanknowit/TESS/releases/tag/v0.9.0-beta
