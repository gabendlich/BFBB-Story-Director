# Story Director

Play dialogue and cutscenes from **SpongeBob SquarePants: Battle for Bikini Bottom – Rehydrated** directly in the game. Pick a scene from the list and the player loads its location.

[Download for Windows](https://github.com/gabendlich/BFBB-Story-Director/releases/latest) · [Deutsche Anleitung](README.de.md)

## Getting started

1. Download the Windows ZIP and extract it.
2. Open **StoryDirector.exe**. If the game wasn't found automatically, select its installation folder.
3. Click **Start game**, choose a scene, then **Play scene**.

The player stops after that scene. Turn on **Continue playback** to keep going through the list. You can search by name and filter by location or type.

Close the game before starting it through Story Director. Once it's running, you can switch between the game and the player with Alt+Tab.

## Requirements

- Windows 10/11, 64-bit
- The Steam Windows version of the game
- .NET Framework 4.8

The ZIP includes UE4SS, the mod loader. Story Director sets it up on first use. If setup reports that it can't write to the game folder, run Story Director as administrator for that setup. The executable isn't digitally signed.

The interface is available in English and German. Game dialogue currently plays in English.

## Your saves

Story Director uses a separate profile:
`%LOCALAPPDATA%/BFBBStoryDirector/<installation-id>/Profile`.

It copies your audio and display settings once, but leaves your regular saves alone. Before each launch, it also backs up your normal saves and checks that the copies match.

The player checks the game's actual save folder before allowing scene playback. If that check fails, it closes the game it just started. Starting the game normally through Steam leaves the scene controller inactive.

Setup won't overwrite an unknown mod loader. **Remove from game…** removes only unchanged files installed by Story Director. Saves, backups and the separate profile are kept.

## What's included

The list has 803 entries: 480 dialogue or information entries, 37 cutscenes and 286 reactions or announcer lines. Character variants appear as separate entries. Some general reactions have no fixed location; those play with the appropriate character in a loaded area.

This replays scenes; it doesn't play through the platforming or combat. If a conversation is interrupted, the player retries it up to twice, then stops with an error.

Live checks cover the opening, Bubble Buddy after a character change, Squidward's house, Sandy's dome, Rock Bottom, a reaction and a flythrough. Short recordings were also checked for stale captions and repeated room-entry dialogue. Normal saves kept their original file hashes. This isn't a full test of every entry or every game version.

Game content is read from your own installation. The download contains no game audio, levels, saves or dialogue transcripts.

## Building

Run this on Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

The source includes the tested UE4SS archive and its license in `third_party/`. The build checks its SHA-256, compiles the player and runs the backend tests. No download is needed when that archive is present.

The Windows ZIP, source ZIP and their checksums are written to `dist/`. Previous builds are kept under `.cache/previous-dist-...`. Profiles, logs and session files are excluded from the packages.

Use `-RuntimeArchive <path>` to supply another copy of the same archive. The checksum must match. If the bundled archive is missing, the build checks its cache, then tries the exact upstream download.

To run the packaging tests separately:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\Test-Packaging.ps1
```

[Third-party notices](THIRD-PARTY-NOTICES.md)
