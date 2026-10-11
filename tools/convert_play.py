#!/usr/bin/env python3
"""Convert a Project Gutenberg Shakespeare text into a Lua data file for the addon.

Usage:
    python3 tools/convert_play.py muchado

Reads plays/<id>.txt and writes plays/<id>.lua.

The output is a list of "cues". A cue is one click of the teleprompter button:
either a chunk of a speech small enough to send as a single chat message
(WoW limits chat messages to 255 *bytes*), or a stage direction, which is
shown on the teleprompter but never spoken.
"""

import json
import re
import sys
from pathlib import Path

# Hard limit for SendChatMessage is 255 bytes. Leave a little headroom.
MAX_BYTES = 250

ROOT = Path(__file__).resolve().parent.parent

# Per-play configuration. "aliases" maps a speech heading to the role(s) that
# speak it; a list means any of those roles may deliver the line.
PLAYS = {
    "muchado": {
        "title": "Much Ado About Nothing",
        "aliases": {
            "FRIAR": "FRIAR FRANCIS",
            "BOTH": ["BORACHIO", "CONRADE"],
        },
    },
    "midsummer": {
        "title": "A Midsummer Night's Dream",
        "aliases": {},
    },
    "twelfthnight": {
        "title": "Twelfth Night",
        "aliases": {
            "DUKE": "ORSINO",
            "SIR TOBY": "SIR TOBY BELCH",
            "SIR ANDREW": "SIR ANDREW AGUECHEEK",
            "AGUECHEEK": "SIR ANDREW AGUECHEEK",
            "CAPTAIN": "SEA CAPTAIN",
        },
    },
}

ROMAN = {"I": 1, "II": 2, "III": 3, "IV": 4, "V": 5}

# Stage directions that imply an emote (e) and/or spell (s). The spell is
# used if the player knows it, otherwise the emote is the fallback.
ACTION_RULES = [
    (r"\bdies\b", {"e": "/lie", "s": "Feign Death"}),
    (r"\bswoons\b", {"e": "/lie"}),
    (r"\bsleeps?\b|\blies down\b", {"e": "/sleep"}),
    (r"\bwaking\b", {"e": "/stand"}),
    (r"\bkisses\b", {"e": "/kiss"}),
    (r"\bkneels\b", {"e": "/kneel"}),
    (r"\bweeps\b", {"e": "/cry"}),
    (r"\bdance\b", {"e": "/dance"}),
]


def actions_for(direction):
    for pattern, action in ACTION_RULES:
        if re.search(pattern, direction, re.I):
            return dict(action)
    return {}


def parse_action(spec):
    """'/laugh' -> emote; 'Feign Death /lie' -> spell with emote fallback."""
    words = spec.split()
    emotes = [w for w in words if w.startswith("/")]
    spell = " ".join(w for w in words if not w.startswith("/"))
    out = {}
    if emotes:
        out["e"] = emotes[0]
    if spell:
        out["s"] = spell
    return out


def normalise(s):
    return re.sub(r"[^a-z ]", "", s.lower().replace("’", "'").replace("\n", " "))


def apply_overlay(play_id, cues):
    """Apply hand-written actions from plays/<id>.actions.

    Each non-comment line is:  ROLE | first words of the line | action
    """
    path = Path(ROOT, "plays", f"{play_id}.actions")
    if not path.exists():
        return
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        try:
            role, prefix, spec = (p.strip() for p in line.split("|"))
        except ValueError:
            sys.exit(f"{path.name}:{n}: expected ROLE | text | action")
        target = next((c for c in cues if role in c.get("r", [])
                       and normalise(c.get("t", "")).startswith(normalise(prefix))), None)
        if target is None:
            sys.exit(f"{path.name}:{n}: no {role} line starting {prefix!r}")
        target.update(parse_action(spec))

ACT_RE = re.compile(r"^ACT ([IVX]+)\.?$")
SCENE_RE = re.compile(r"^(?:SCENE|Scene) ([IVX]+)\.\s*(.*)$")
# "BENEDICK."  "DON PEDRO. Yea, marry..."  "BALTHASAR [sings.]"
HEADING_RE = re.compile(
    r"^([A-Z][A-Z’' &]*[A-Z])(?:\.\s*(.*)|\s*\[([^\]]*)\]\.?\s*(.*))$"
)
ENTRANCE_RE = re.compile(r"^(Enter|Re-enter)\b")
# Unbracketed song cues: "Clown sings."  "The Clown’s song."
SONG_RE = re.compile(r"^(?:The )?([A-Z][a-z]+)(?:’s song| sings)\.?$")


def nbytes(s):
    return len(s.encode("utf-8"))


def clean(line):
    """Strip Gutenberg italics markers and surrounding whitespace."""
    return line.replace("_", "").strip()


def title_case(role_id):
    return " ".join(w.capitalize() for w in role_id.split())


def read_blocks(lines):
    """Group lines into paragraphs separated by blank lines."""
    block = []
    for line in lines:
        if line.strip():
            block.append(clean(line))
        elif block:
            yield block
            block = []
    if block:
        yield block


def parse_personae(lines):
    """Return {ROLE_ID: description} from the Dramatis Personae list."""
    out = {}
    try:
        start = next(i for i, l in enumerate(lines) if l.strip().startswith("Dramatis Person"))
    except StopIteration:
        return out
    for line in lines[start + 1:]:
        line = clean(line)
        if line.startswith("SCENE") or line.startswith("ACT "):
            break
        m = re.match(r"^([A-Z][A-Z ’']+[A-Z])\b[,.]?\s*(.*)$", line)
        if m:
            out[m.group(1)] = m.group(2).rstrip(".")
    return out


def split_long(text):
    """Split text that is too long for one chat message into pieces.

    Prefers sentence boundaries, then clause boundaries, then word boundaries.
    Line breaks (verse) are kept so the teleprompter can show them.
    """
    if nbytes(text) <= MAX_BYTES:
        return [text]
    for pattern in (r"(?<=[.!?])\s+", r"(?<=[;:—])\s*", r"(?<=,)\s+", r"\s+"):
        parts = [p for p in re.split(pattern, text) if p]
        if len(parts) > 1:
            break
    # Recursively break any part that is still too long, then pack greedily.
    pieces = [q for p in parts for q in split_long(p)]
    chunks, cur = [], ""
    for p in pieces:
        candidate = f"{cur} {p}" if cur else p
        if nbytes(candidate) <= MAX_BYTES:
            cur = candidate
        else:
            chunks.append(cur)
            cur = p
    if cur:
        chunks.append(cur)
    return chunks


# End of a sentence: . ! or ? plus any closing quotes, followed by a space and
# a capital letter (so "O! he is returned" stays together).
SENTENCE_END_RE = re.compile(r"[.!?][’'”\")]*(?=\s+[‘'“\"(]*[A-Z])")


def sentences(text):
    out, start = [], 0
    for m in SENTENCE_END_RE.finditer(text):
        out.append(text[start:m.end()].strip())
        start = m.end()
    out.append(text[start:].strip())
    return [s for s in out if s]


def starts_with_capital(line):
    line = line.lstrip("‘’'“\"(—- ")  # ’ as in ’Tis
    return line[:1].isupper()


def continues(line, next_line):
    """True if next_line carries on line as prose rather than starting a verse line.

    Verse lines start with capitals. Prose wraps wherever the printer ran out
    of room: the next line often starts in lower case, and the wrapped line is
    long and doesn't end a sentence.
    """
    if not starts_with_capital(next_line):
        return True
    return len(line) > 62 and not re.search(r"[.!?][’'”\")]*$", line)


def split_speech(text):
    """Break a passage into the units delivered one /say at a time.

    Verse: one per line. Prose: one per sentence, since its line breaks are
    just where the printed text wrapped. Anything over the chat limit is split
    further.
    """
    lines = [l.strip() for l in text.split("\n") if l.strip()]
    runs = [[lines[0]]] if lines else []
    for prev, line in zip(lines, lines[1:]):
        if continues(prev, line):
            runs[-1].append(line)
        else:
            runs.append([line])
    units = []
    for run in runs:
        units += sentences(" ".join(run)) if len(run) > 1 else run
    return [chunk for unit in units for chunk in split_long(unit)]


def speech_cues(roles, text, lead_direction=None):
    """Turn one speech (possibly with embedded [directions]) into cues."""
    cues = []
    direction = lead_direction
    # Split on bracketed directions, keeping them.
    for part in re.split(r"(\[[^\]]*\])", text):
        part = part.strip(" \n—")
        if not part:
            continue
        if part.startswith("["):
            d = part[1:-1].strip().rstrip(".").replace("\n", " ")
            direction = f"{direction}; {d}" if direction else d
            continue
        for i, chunk in enumerate(split_speech(part)):
            cue = {"r": roles, "t": chunk}
            if direction and i == 0:
                cue["d"] = direction
                cue.update(actions_for(direction))
            cues.append(cue)
        direction = None
    if direction:
        # Trailing direction such as "[Kisses her.]" or "[Exit.]". If it is
        # something the speaker does, make it an unspoken cue for them.
        action = actions_for(direction)
        cues.append({"r": roles, "d": direction, **action} if action else {"d": direction})
    return cues


def convert(play_id):
    cfg = PLAYS[play_id]
    aliases = cfg["aliases"]
    lines = Path(ROOT, "plays", f"{play_id}.txt").read_text(encoding="utf-8").splitlines()

    personae = parse_personae(lines)

    # The play proper starts at the first "ACT I" after the Dramatis Personae.
    dp = next((i for i, l in enumerate(lines) if l.strip().startswith("Dramatis Person")), 0)
    start = next(i for i in range(dp, len(lines)) if ACT_RE.match(lines[i].strip()))
    end = next((i for i, l in enumerate(lines) if l.startswith("*** END OF")), len(lines))
    body = lines[start:end]

    def resolve(heading):
        r = aliases.get(heading, heading)
        return r if isinstance(r, list) else [r]

    cues, scenes = [], []
    act = 0
    speaker = None  # list of role ids
    lead = None     # direction to attach to the next speech, e.g. "sings"
    unknown = set()

    for block in read_blocks(body):
        first = block[0]

        m = ACT_RE.match(first)
        if m:
            act = ROMAN[m.group(1)]
            continue

        m = SCENE_RE.match(first)
        if m:
            setting = " ".join([m.group(2)] + block[1:]).strip()
            scenes.append({"act": act, "scene": ROMAN[m.group(1)], "title": setting,
                           "start": len(cues) + 1})
            cues.append({"d": f"Act {act}, Scene {ROMAN[m.group(1)]}. {setting}", "h": 1})
            speaker = None
            continue

        if ENTRANCE_RE.match(first) or (first.startswith("[") and " ".join(block).endswith("]")
                                        and block[-1].endswith("]")
                                        and "]" not in " ".join(block)[:-1]):
            d = " ".join(block).strip("[] ").rstrip(".")
            cues.append({"d": d, "_speaker": speaker})
            continue

        m = SONG_RE.match(first)
        if m and len(block) == 1:
            speaker, lead = resolve(m.group(1).upper()), "sings"
            continue

        m = HEADING_RE.match(first)
        if m and first.split(".")[0].split()[0] not in ("ACT", "SCENE"):
            heading = m.group(1)
            speaker = resolve(heading)
            if m.group(3) is not None:  # BALTHASAR [sings.]
                lead, rest = m.group(3).rstrip("."), m.group(4)
            else:
                lead, rest = None, m.group(2)
            text_lines = ([rest] if rest else []) + block[1:]
            if not text_lines:
                continue
            cues.extend(speech_cues(speaker, "\n".join(text_lines), lead))
            continue

        # Continuation of the previous speaker after a stage direction.
        if speaker is None:
            unknown.add(first)
            cues.append({"d": " ".join(block)})
            continue
        cues.extend(speech_cues(speaker, "\n".join(block), lead))
        lead = None

    # Standalone directions such as "Hero swoons" or "Dies" become unspoken cues
    # for the character named at the start of the sentence, or failing that the
    # character who was speaking.
    role_ids = {r for c in cues for r in c.get("r", [])}
    for c in cues:
        speaker = c.pop("_speaker", None)
        if "d" not in c or "r" in c:
            continue
        for sentence in re.split(r"\.\s*", c["d"]):
            action = actions_for(sentence)
            if not action:
                continue
            subject = [r for r in role_ids if sentence.startswith(title_case(r) + " ")]
            if subject:
                c.update(r=subject, **action)
            elif re.match(r"[A-Z][a-z]+s\b", sentence) and speaker:  # "Dies", "Sleeps"
                c.update(r=speaker, **action)
            break

    apply_overlay(play_id, cues)

    # Role table, ordered by number of cues (largest parts first).
    counts = {}
    for c in cues:
        for r in c.get("r", []):
            counts[r] = counts.get(r, 0) + 1
    roles = []
    for rid, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        desc = personae.get(rid) or personae.get("A " + rid) or ""
        roles.append({"id": rid, "name": title_case(rid), "desc": desc, "cues": n})

    for rid in counts:
        if rid not in personae and "A " + rid not in personae:
            print(f"note: role {rid!r} not in Dramatis Personae", file=sys.stderr)
    for u in sorted(unknown):
        print(f"warning: text with no speaker treated as direction: {u!r}", file=sys.stderr)

    return {"id": play_id, "title": cfg["title"], "roles": roles, "scenes": scenes, "cues": cues}


def lua_str(s):
    # JSON string escapes (\" \\ \n) are valid Lua 5.1 escapes; keep UTF-8 as-is.
    return json.dumps(s, ensure_ascii=False)


def to_lua(play):
    out = [
        "-- Generated by tools/convert_play.py. Do not edit by hand.",
        "local _, ns = ...",
        "ns.plays = ns.plays or {}",
        f"ns.plays[{lua_str(play['id'])}] = {{",
        f"  id = {lua_str(play['id'])},",
        f"  title = {lua_str(play['title'])},",
        "  -- Roles, largest parts first.",
        "  roles = {",
    ]
    for r in play["roles"]:
        out.append(f"    {{ id = {lua_str(r['id'])}, name = {lua_str(r['name'])}, "
                   f"desc = {lua_str(r['desc'])}, cues = {r['cues']} }},")
    out += ["  },", "  -- start = index into cues of the scene heading.", "  scenes = {"]
    for s in play["scenes"]:
        out.append(f"    {{ act = {s['act']}, scene = {s['scene']}, "
                   f"title = {lua_str(s['title'])}, start = {s['start']} }},")
    out += [
        "  },",
        "  -- r = roles who may speak it, t = text (<= 255 bytes, one chat message),",
        "  -- d = stage direction (shown, never spoken), h = scene heading,",
        "  -- e = emote slash command, s = spell to cast if known (else e is used).",
        "  -- A cue with r but no t is stage business the role performs without speaking.",
        "  cues = {",
    ]
    for c in play["cues"]:
        fields = []
        if "r" in c:
            fields.append("r = {" + ", ".join(lua_str(r) for r in c["r"]) + "}")
        if "t" in c:
            fields.append(f"t = {lua_str(c['t'])}")
        if "d" in c:
            fields.append(f"d = {lua_str(c['d'])}")
        if "e" in c:
            fields.append(f"e = {lua_str(c['e'])}")
        if "s" in c:
            fields.append(f"s = {lua_str(c['s'])}")
        if "h" in c:
            fields.append("h = true")
        out.append("    { " + ", ".join(fields) + " },")
    out += ["  },", "}", ""]
    return "\n".join(out)


def main():
    play_id = sys.argv[1] if len(sys.argv) > 1 else "muchado"
    play = convert(play_id)
    dest = Path(ROOT, "plays", f"{play_id}.lua")
    dest.write_text(to_lua(play), encoding="utf-8", newline="\n")
    spoken = [c for c in play["cues"] if "t" in c]
    longest = max(nbytes(c["t"]) for c in spoken)
    print(f"{play['title']}: {len(play['roles'])} roles, {len(play['scenes'])} scenes, "
          f"{len(spoken)} spoken cues, {len(play['cues']) - len(spoken)} directions, "
          f"longest cue {longest} bytes -> {dest.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
