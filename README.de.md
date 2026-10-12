# Story Director

Mit Story Director kannst du Dialoge und Zwischensequenzen aus **SpongeBob SquarePants: Battle for Bikini Bottom – Rehydrated** direkt im Spiel abspielen. Du wählst eine Szene aus, und der Player lädt den passenden Schauplatz.

[Windows-Version herunterladen](https://github.com/gabendlich/BFBB-Story-Director/releases/latest)

## Loslegen

1. Das Windows-ZIP herunterladen und entpacken.
2. **StoryDirector.exe** öffnen. Falls das Spiel nicht automatisch gefunden wird, den Installationsordner auswählen.
3. Auf **Spiel starten** klicken, eine Szene auswählen und **Szene abspielen** drücken.

Nach der Szene hält der Player an. Mit **Danach weiterspielen** läuft die Liste weiter. Du kannst nach Namen suchen oder die Auswahl nach Ort und Typ filtern.

Schließe das Spiel, bevor du es über Story Director startest. Danach kannst du mit Alt+Tab zwischen Spiel und Player wechseln.

## Voraussetzungen

- Windows 10/11, 64 Bit
- Die Steam-Version des Spiels für Windows
- .NET Framework 4.8

Der Mod-Loader UE4SS liegt dem ZIP bei und wird beim ersten Start eingerichtet. Meldet die Einrichtung fehlende Schreibrechte für den Spielordner, starte Story Director dafür als Administrator. Das Programm ist nicht digital signiert.

Die Oberfläche gibt es auf Deutsch und Englisch. Die Spielstimmen werden derzeit auf Englisch abgespielt.

## Deine Spielstände

Story Director legt ein eigenes Profil an:
`%LOCALAPPDATA%/BFBBStoryDirector/<Installations-ID>/Profile`.

Deine Ton- und Bildeinstellungen werden einmal übernommen. Deine normalen Spielstände werden weder importiert noch überschrieben. Vor jedem Start sichert der Player sie zusätzlich und prüft, ob die Kopien übereinstimmen.

Bevor eine Szene abgespielt werden kann, prüft der Player, ob das Spiel wirklich den separaten Speicherordner verwendet. Schlägt die Prüfung fehl, wird die gerade gestartete Spielinstanz beendet. Beim normalen Start über Steam bleibt die Szenensteuerung inaktiv.

Ein unbekannter Mod-Loader wird nicht überschrieben. **Aus dem Spiel entfernen…** entfernt nur unveränderte Dateien, die Story Director selbst angelegt hat. Spielstände, Sicherungen und das separate Profil bleiben erhalten.

## Enthaltene Szenen

Die Liste enthält 803 Einträge: 480 Dialog- oder Informationseinträge, 37 Zwischensequenzen und 286 Reaktionen oder Ansagen. Varianten für verschiedene Figuren stehen einzeln in der Liste. Manche allgemeinen Reaktionen haben keinen festen Schauplatz; sie laufen mit der passenden Figur in einem geladenen Gebiet.

Der Player spielt Szenen ab, übernimmt aber keine Sprungpassagen oder Kämpfe. Wird ein Gespräch unterbrochen, versucht er es höchstens zweimal erneut. Danach hält er mit einer Fehlermeldung an.

Im Spiel geprüft wurden das Intro, Bubble Buddy nach einem Figurenwechsel, Thaddäus' Haus, Sandys Kuppel, Rock Bottom, eine Reaktion und ein Kameraflug. Kurze Aufnahmen wurden außerdem auf hängen gebliebene Untertitel und doppelte Dialogstarts beim Ortswechsel geprüft. Die normalen Spielstände hatten danach dieselben Prüfsummen. Nicht jeder Eintrag und nicht jede Spielversion wurde damit geprüft.

Die Spielinhalte werden aus deiner Installation geladen. Im Download sind keine Spielaufnahmen, Audiodateien, Level, Spielstände oder Dialogtranskripte enthalten.

## Selbst bauen

Unter Windows ausführen:

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

Das getestete UE4SS-Archiv liegt mit seiner Lizenz unter `third_party/`. Der Build prüft die SHA-256-Prüfsumme, kompiliert den Player und führt die Backend-Tests aus. Solange das Archiv vorhanden ist, ist kein Download nötig.

Windows-ZIP, Quellcode-ZIP und Prüfsummen landen in `dist/`. Vorherige Builds bleiben unter `.cache/previous-dist-...` erhalten. Profile, Protokolle und Sitzungsdateien werden nicht mit eingepackt.

Mit `-RuntimeArchive <Pfad>` kannst du eine andere Kopie desselben Archivs verwenden. Die Prüfsumme muss stimmen. Fehlt das mitgelieferte Archiv, sucht der Build erst im Cache und versucht danach den Download der festgelegten Version.

[English README](README.md) · [Lizenzen und verwendete Software](THIRD-PARTY-NOTICES.md)
