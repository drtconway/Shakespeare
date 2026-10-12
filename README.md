# Shakespeare

Perform the plays of Shakespeare with your friends in World of Warcraft: Forever.

Shakespeare gives each actor a teleprompter showing the script. When it's your turn, your line is
highlighted. Click **Speak** and your character says it aloud in /say, so anyone standing nearby
can watch the performance. Every actor's teleprompter moves on together. Lines can come with
emotes and spells: bow, kiss, swoon, or Feign Death when someone dies. Ghosts shimmer with Fade
and vanish with Invisibility or Stealth, and characters drink from your bags when the play
calls for a toast or a poisoned cup.

## Putting on a play

1. **Install.** In WowUp, choose *Get Addons → Install from URL* and enter
   `https://github.com/drtconway/Shakespeare`. Or download the zip from the
   [releases page](https://github.com/drtconway/Shakespeare/releases) and unzip it into your
   `Interface\AddOns` folder. Every actor needs the addon, and the same version of it.
2. **Form a group.** Everyone in the play joins the same party or raid. This is how the actors'
   teleprompters keep in step. Your audience doesn't need to be in the group, or have the addon.
3. **Open the teleprompter** with the harp button on the minimap, or type `/bard`.
4. **Choose the play.** Click the title at the top of the teleprompter.
5. **Cast it.** Click **Cast** and pick your roles. Your character announces "I will play the role
   of Benedick!" Players can take several roles. If nobody takes a role, anyone can read its lines.
6. **Perform.** When your line is highlighted in gold, click **Speak**. If an actor misses their
   cue, after five seconds everyone else's **Prompt** button lights up to give them a poke.

Someone who joins the group mid-play picks up the play, the place and the cast from the group
leader.

## Controls

| Control | What it does |
| --- | --- |
| Play title | Choose a different play. This starts it from the top and clears the cast for everyone. |
| **Cast** | Show the roles. Click one to take it or give it up; shift-click to take a role from someone else. |
| **Speak** / **Perform** | Deliver your line, or perform your stage business (e.g. *Hero swoons*). Bindable to a key under Key Bindings → AddOns → Shakespeare. |
| **Emote** | Do the emote or spell for your line: the one you've just spoken (until the next line is delivered), or the one you're about to speak. Aimed emotes target the other actor automatically. |
| **Auto emotes** | When ticked, **Speak** does the emote too. |
| **Use items** | Ticked by default. Lets a few drinking scenes use a drink from your bags: Juliet's potion and Romeo's poison (Refreshing Spring Water), Macbeth's toast and Sir Toby's carousing (wine or ale if you have some, else water). Items are used up, so untick it to keep yours. |
| **Troll speak** / **Dwarf speak** | Shown to trolls and dwarves. When ticked, your lines are spoken in your race's dialect ("Is dis a dagger…", "Aye, lad"). Your lines on the teleprompter show how they'll sound. |
| **Prompt** | Lights up when an actor is five seconds late. Pokes, coughs or sighs at them (hover to see who). |
| `<<` `>>` | Go to the start or end of the scene. Click again for the previous or next scene. |
| `<` `>` | Step back or forward one line, to recover from a mistake. |
| **Reset** | Clear the cast and go back to the start of the play (asks first). |
| Minimap button | Click to show or hide the teleprompter, right-click to reset, drag to move. |

The navigation buttons and **Reset** affect everyone in the group.

Slash commands: `/bard` (or `/shakespeare`) shows or hides the teleprompter. `/bard plays` lists the
plays, `/bard play <id>` starts one, `/bard scene <act> <scene>` jumps to a scene, and `/bard reset`
resets.

## Plays

- *Much Ado About Nothing* (`muchado`)
- *A Midsummer Night's Dream* (`midsummer`)
- *Twelfth Night* (`twelfthnight`)
- *Macbeth* (`macbeth`): Banquo's ghost and the apparitions shimmer and vanish if their actors
  have the spells.
- *Romeo and Juliet* (`romeo`): the Chorus's prologues are scenes of their own.
- *Hamlet* (`hamlet`): the Ghost shimmers, beckons and vanishes if its actor has the spells.

The texts come from Project Gutenberg.

---

## For developers

### Files

```
Shakespeare.toc          addon manifest; lists the files WoW loads
Core.lua                 play state, casting, sync over addon messages, slash commands
UI.lua                   teleprompter window and its buttons, cast list, play chooser
Minimap.lua              minimap button
Bindings.xml             key binding for the Speak button
.pkgmeta                 what the release zip leaves out
.github/workflows/       builds and publishes a release when a version tag is pushed
media/harp.tga           minimap icon, drawn by tools/make_icon.py
plays/<id>.lua           generated play data, one file per play
plays/<id>.actions       hand-written emotes, spells and targets for lines
plays/<id>.txt           Project Gutenberg source text (not in git)
tools/convert_play.py    converts plays/<id>.txt (+ .actions) to plays/<id>.lua
tools/make_icon.py       draws media/harp.tga
```

### Releasing

Work happens on `dev`; `main` is protected and only changes through pull requests. To release:

1. Open a pull request from `dev` to `main` on GitHub and merge it.
2. Tag the merged `main`:
   `git switch main && git pull && git tag -a v1.1.0 -m "Shakespeare 1.1.0" && git push origin v1.1.0`,
   then `git switch dev` to carry on.

Pushing the tag does the rest:
- **The workflow:** `.github/workflows/release.yml` runs the BigWigs packager.
- **The zip:** the packager builds `Shakespeare-<tag>.zip`, leaving out what `.pkgmeta` lists (the
  tools, emotes files and play texts).
- **The version:** it replaces `@project-version@` in the `.toc` with the tag.
- **The release:** it publishes a GitHub release with the zip and a `release.json` for WowUp.

### Adding a play

1. Put the Gutenberg text in `plays/<id>.txt`.
2. Add an entry for it (title, and aliases for speakers with more than one heading, e.g.
   `DUKE` → `ORSINO`) to `PLAYS` in `tools/convert_play.py`.
3. Run `python3 tools/convert_play.py <id>` and check its warnings.
4. Add `plays\<id>.lua` to `Shakespeare.toc`.
5. Restart the game; WoW only notices new files on a restart.

Regenerating a play changes its data. Every actor needs the same generated file. Otherwise, clients
with different files ignore each other's messages and say so.

### Emotes, spells and targets

Stage directions such as *Kisses her*, *Dies*, *Sleeps* and *Hero swoons* get an emote
automatically (see `ACTION_RULES` in the converter). Add others in `plays/<id>.actions`, one per
line:

```
ROLE      | first words of the line | action
BEATRICE  | I wonder that you will  | /sigh @Benedick
THISBE    | Dies                    | Feign Death /lie
GHOST     | (enters)                | Fade, Invisibility, Shadowmeld, Stealth
```

- **Action:** an emote, one or more spells, or both.
  - **Spells:** comma-separated. The first one the player knows is cast, so the ghost above fades
    if played by a priest and shadowmelds if played by a night elf.
  - **Fallback:** the emote is used if they know none of the spells.
- **`wield dagger`:** if the player has the Daggers skill and a dagger they can use, the addon
  equips it in the main hand (unless one is already there) and draws it. Daggers are the only
  weapon supported so far; others go in `WEAPONS` in `Core.lua` and `WIELDABLE` in the converter.
- **`use <items>`:** uses the first of these items (comma-separated) the player has in their bags,
  e.g. `use Flask of Port, Refreshing Spring Water`. Players can turn this off with **Use items**.
- **`@Role`:** aims it at whoever plays that role.
- **Matching:** lines are matched ignoring punctuation and case. A stage direction can be matched
  too, e.g. `Enter Ghost`; if nobody performs it yet, it becomes a cue that role performs.
- **`(enters)`:** matches every entrance that names the role. Use it to make a ghost appear.
- **Errors:** the converter stops with an error if a line or role doesn't match.

### Play data

Each play is a list of *cues*. A cue is one click of the Speak button:

```lua
{ r = {"BEATRICE"}, t = "I wonder that you will still be talking, ...", e = "/sigh", at = "BENEDICK" }
{ r = {"CLAUDIO"}, t = "Bait the hook well: this fish will bite.", d = "Aside" }
{ r = {"BORACHIO", "CONRADE"}, t = "Yea, sir, we hope." }      -- "BOTH."; either may speak it
{ r = {"HERO"}, d = "Hero swoons", e = "/lie" }                -- stage business, no speech
{ r = {"THISBE"}, d = "Dies", e = "/lie", s = {"Feign Death"} } -- spell if known, else emote
{ d = "Enter Don John and Conrade" }                           -- direction, shown only
{ d = "Act 1, Scene 2. A room in Leonato's house.", h = true } -- scene heading
```

- `r`: the roles who may perform the cue.
- `t`: one /say.
  - Verse is delivered a line at a time.
  - Prose is delivered a sentence at a time, because its line breaks in the source are only where
    the printed text wrapped. A line counts as prose when the next line starts in lower case, or
    when the line is long and doesn't end a sentence.
  - Nothing exceeds 255 bytes, the limit for one chat message. Longer sentences are split at
    clauses.
- `d`: a stage direction. It is shown on the teleprompter and never spoken.
- `e` and `s`: an emote, and a list of spells (the first known is cast).
- `w`: a kind of weapon to equip and draw, if the player has one.
- `u`: items to use; the first the player has is used.
- `at`: the role they are aimed at. The addon targets that role's player, performs the action, and
  restores your previous target. If nobody has the role, it isn't aimed at anyone.
- `h`: marks a scene heading.

Each play also has `roles` (every speaking part, largest first, with a cue count for the cast list)
and `scenes` (the index of each scene's first cue).

### Design

**Teleprompter.** It shows the last line spoken, the current cue in a box, and the next few cues.
- The box is gold when you can deliver the cue: it's yours, or nobody has the role. When a role is
  open, the first click wins.
- Directions are skipped automatically. Business cues (`r` but no `t`) wait for the performer's
  click like any other line.
- Saved variables keep the current play, cast and position, so an interrupted rehearsal can resume.

These WoW API constraints shape the rest:

- **Speaking needs a click.** Outside instances, `SendChatMessage` to SAY/YELL only works during
  a hardware event (a real mouse click or key press). Lines cannot be spoken automatically, which
  is why there is a Speak button.
- **Spells and targeting are protected.** Addon code can't call `CastSpellByName` or `TargetUnit`.
  - **Secure buttons:** Speak, Emote and Prompt are `SecureActionButtonTemplate` buttons with
    `type = "macro"`. Their `macrotext` is updated whenever the cue or cast changes, e.g.
    `/target Aldric\n/kiss\n/targetlasttarget`.
  - **Combat:** attributes can't change in combat, so the buttons catch up afterwards.
  - **Speaking:** Speak sends the line from `PreClick`, and advances in `PostClick` after its macro
    has run.
- **Chat is unreliable for keeping in sync.** /say only reaches about 25 yards. Text can be garbled
  across factions or changed by the profanity filter, and short lines like "Ay, my lord." recur.
  So each delivery also sends an addon message to the party or raid, and that is what moves
  everyone's teleprompter on. Matching /say text against the next few cues is a fallback for actors
  without the addon. So is recognising "I will play the role of …!".

### Addon messages

Prefix `Shakespeare`. Each message starts with a play key, `<id>:<number of cues>`, so clients with
different play data ignore each other.

| Message                 | Meaning                                                         |
| ----------------------- | --------------------------------------------------------------- |
| `CAST <role>`           | sender takes a role                                             |
| `UNCAST <role>`         | sender gives up a role                                          |
| `CUE <n>`               | sender delivered cue n; everyone moves to the next actionable cue |
| `GOTO <n>`              | sender moved the group to cue n (navigation buttons)            |
| `PLAY`                  | sender starts this play from the top with an empty cast         |
| `SYNC?`                 | a newcomer to the group asks for the current state              |
| `POS <n>`               | leader's reply to `SYNC?`: the play (from the key) and position |
| `HOLD <player>;<roles>` | leader's reply to `SYNC?`: comma-separated roles one player holds |

`CUE n` sets the position to the later of where it is now and just after cue n, so duplicate or
late messages are harmless.
