# Shakespeare

This addon enables a group of players to perform the plays of Shakespeare
in World of Warcraft: Forever.

## How it works

The basic interface of the addon functions as a teleprompter with a button that
a player can click to recite the next line from the play.

The addon monitors the chat so that it can recognise lines as they are delivered.

Internally, the teleprompter has a list of <person, line> tuples, and a table recording
which player is reading each person in the play (players may take multiple roles).

Before the play begins, players can nominate for roles. When a player nominates for a role,
the addon will say in to the chat: `I will play the role of <person>!` which can be monitored by
the addon.

When the addon sees that a line has been delivered, it can advance on to the next line in the play.
If the player has the next line, then the teleprompter should put a highlight box around the line
it indicate that the player should click the button to deliver the line.

If a player has not delivered their line 5 seconds since the last line was delivered, the interface
should highlight a "prompt" button in the interface for the other players participating in the play.

If clicked, the player should target the player who should be delivering the line and use an emote
such as poke, cough, etc.

Lines may optionally have emotes or spells attached to them, such as `/sleep` or `/laugh`, or
casting `Feign Death` when someone dies.

## Usage

- `/bard` (or `/shakespeare`) or the harp button on the minimap shows or hides the teleprompter.
  Drag the minimap button to move it. Right-click it to reset.
- Click the play's title at the top of the teleprompter to choose a different play. This starts it
  from the top and clears the cast for everyone in the group.
- **Cast** opens the list of roles. Click a role to take it or give it up. Shift-click takes a role
  from someone else.
- **Speak** / **Perform** delivers your cue. It can also be bound to a key under
  Key Bindings → AddOns → Shakespeare.
- **Emote** does the emote or spell attached to your line. It works for the line you've just spoken,
  until someone delivers the next line, or for the line you're about to speak. Tick **Auto emotes**
  to have **Speak** do it for you. Actions with no words (e.g. *Hero swoons*) always happen when
  you click **Perform**.
- **Prompt** appears when another actor is more than 5 seconds late. It pokes them.
- `<<` and `>>` go to the start or end of the scene. Click again to go on to the previous or next scene.
  `<` and `>` step back or forward one line. These move the whole group.
- **Reset** (after confirming) clears the cast and returns to the start of the play for everyone.
- `/bard plays`, `/bard play <id>`, `/bard scene <act> <scene>` and `/bard reset` do what they say.
  Choosing a play or resetting clears the cast for everyone.

Players in the same party or raid stay in sync. Joining the group mid-play picks up the play,
position and cast from the group leader.

## Implementation

### Files

```
Shakespeare.toc          addon manifest (lists the files below)
Core.lua                 play state, casting, sync over addon messages
UI.lua                   teleprompter frame, deliver and prompt buttons
Minimap.lua              minimap button
Bindings.xml             key binding for the deliver button
media/harp.tga           minimap icon, drawn by tools/make_icon.py
plays/muchado.lua        generated play data (one file per play)
plays/muchado.txt        Project Gutenberg source text (not loaded by WoW)
plays/muchado.actions    hand-written emotes/spells for lines
tools/convert_play.py    converts plays/<id>.txt (+ .actions) to plays/<id>.lua
```

Regenerate a play with `python3 tools/convert_play.py muchado`.

To add a play:
1. Put the Gutenberg text in `plays/<id>.txt`.
2. Add an entry for it (title and any heading aliases) to `PLAYS` in `tools/convert_play.py`.
3. Run the converter, and check its warnings.
4. Add `plays\<id>.lua` to `Shakespeare.toc`.
5. Restart the game; WoW only notices new files on a restart.

Everyone in the group needs the same generated file.

### Play data

Each play is a list of *cues*. A cue is one click of the deliver button:

```lua
{ r = {"BEATRICE"}, t = "I wonder that you will still be talking, ...", e = "/sigh" }
{ r = {"CLAUDIO"}, t = "Bait the hook well: this fish will bite.", d = "Aside" }
{ r = {"BORACHIO", "CONRADE"}, t = "Yea, sir, we hope." }      -- "BOTH."; either may speak it
{ r = {"HERO"}, d = "Hero swoons", e = "/lie" }                -- stage business, no speech
{ r = {"THISBE"}, d = "Dies", e = "/lie", s = "Feign Death" }  -- spell if known, else emote
{ d = "Enter Don John and Conrade" }                           -- direction, shown only
{ d = "Act 1, Scene 2. A room in Leonato's house.", h = true } -- scene heading
```

- `t` is one /say.
  - Verse is delivered a line at a time.
  - Prose is delivered a sentence at a time, because its line breaks in the source are only where
    the printed text wrapped. A line counts as prose when the next line starts in lower case, or
    when the line is long and doesn't end a sentence.
  - Nothing exceeds 255 bytes, the limit for one chat message. Longer sentences are split at
    clauses.
- `d` is a stage direction. It is shown on the teleprompter and never spoken.
- `e` and `s` are an emote and a spell. Directions such as *Kisses her*, *Dies*, *Sleeps* and
  *Hero swoons* are mapped automatically. Add any others in `plays/<id>.actions`.
- `at` is the role an emote or spell is aimed at, written `/kiss @Beatrice` in the actions file.
  When the line is delivered, the addon targets the player cast in that role, does the emote, then
  restores your previous target. If nobody has the role, the emote isn't aimed at anyone.
- `scenes` gives the index of each scene's first cue, so a rehearsal can start mid-play.
- `roles` lists every speaking part, largest first, with a cue count for the casting screen.

### WoW API constraints that shape the design

- **Speaking needs a click.** Outside instances, `SendChatMessage` to SAY/YELL only works during
  a hardware event (a real mouse click or key press). The deliver button is therefore required,
  not just a convenience. Lines cannot be spoken automatically.
- **Spells and targeting are protected.** Addon code cannot call `CastSpellByName` or `TargetUnit`.
  The deliver and prompt buttons should be `SecureActionButtonTemplate` buttons with
  `type = "macro"`. Their `macrotext` is updated whenever the current cue changes, e.g.
  `/cast Feign Death` or `/target Aldric\n/poke`. Attributes can't be changed in combat (check
  `InCombatLockdown()`), which shouldn't matter on stage.
  The chat line itself is sent from the button's `PreClick` handler, which runs within the click.
- **Chat is unreliable for keeping in sync.** /say only reaches about 25 yards. Text can be garbled
  across factions or altered by the profanity filter. Short lines like "Ay, my lord." also
  appear many times in the play. So when a line is delivered, the addon also sends
  `C_ChatInfo.SendAddonMessage("SHAKESPEARE", ..., "RAID" or "PARTY")`, and that is what
  advances everyone's teleprompter. Matching the SAY text against the next few cues
  (`CHAT_MSG_SAY`) remains a fallback, e.g. for a player who doesn't have the addon.

### Addon messages

All messages are prefixed with the play id. Clients with different play data ignore each other.

| Message                 | Meaning                                                         |
| ----------------------- | --------------------------------------------------------------- |
| `CAST <role>`           | sender takes a role (also says "I will play the role of …!")    |
| `UNCAST <role>`         | sender gives up a role                                          |
| `CUE <n>`               | sender delivered cue n; everyone moves to the next spoken cue   |
| `GOTO <n>`              | director jumps to cue n (start of a scene, or after a mistake)  |
| `PLAY`                  | sender starts this play from the top with an empty cast         |
| `SYNC?`                 | a newcomer to the group asks for the current state              |
| `POS <n>`               | leader's reply to `SYNC?`: the play (from the prefix) and position |
| `HOLD <player> <roles>` | leader's reply to `SYNC?`: comma-separated roles one player holds |

On `CUE n`, set the position to `max(position, n + 1)`, so duplicate or late messages are harmless.
Directions are skipped automatically. Business cues (`r` but no `t`) wait for the performer's click
like any other line.

### Teleprompter behaviour

- Show the previous line, the current cue (highlighted when it's yours) and the next few cues.
  Upcoming lines of your own are marked.
- A cue whose role nobody has taken is open: anyone's deliver button lights up, and the first click wins.
- Five seconds after the last delivery, if the current cue belongs to a player who hasn't delivered it, the other
  players see the prompt button. Its macrotext is `/target <player>` followed by a random choice of
  `/poke`, `/cough` or `/sigh`.
- Saved variables keep the cast and position per play, so an interrupted rehearsal can resume.
