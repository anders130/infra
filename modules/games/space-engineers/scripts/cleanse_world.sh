#!/bin/bash
# cleanse_world.sh — Strip player progress from SE dedicated server save
# Keeps: world settings, mods, NPC factions, NPC stations, planets, asteroids
# Removes: player identities, player factions, respawn ships, player characters,
#          player-owned grids
#
# Usage (copy mode — no backup needed, recommended):
#   ./cleanse_world.sh <source_world> <dest_world>
#   Example: sudo bash ~/cleanse_world.sh "Star System" NewWorld
#
# Usage (in-place — requires <world>.backup):
#   ./cleanse_world.sh <world_dir>

set -euo pipefail

if [[ $# -eq 2 ]]; then
    SRC="$1"; DST="$2"
    [[ -d "$SRC" ]] || { echo "ERROR: Source not found: $SRC"; exit 1; }
    echo "=== SE World Cleanser (copy mode) ==="
    echo "Source : $SRC"
    echo "Dest   : $DST"
    [[ -d "$DST" ]] && { echo "Removing existing $DST..."; rm -rf "$DST"; }
    cp -a "$SRC" "$DST"
    WORLD="$DST"
elif [[ $# -eq 1 ]]; then
    WORLD="$1"
    [[ -d "${WORLD}.backup" ]] || {
        echo "ERROR: No backup at ${WORLD}.backup"
        echo "  Or use: $0 <source> <dest>"
        exit 1
    }
    echo "=== SE World Cleanser (in-place) ==="
    echo "World  : $WORLD"
else
    echo "Usage: $0 <source_world> <dest_world>"
    echo "       $0 <world_dir>    (requires <world>.backup)"
    exit 1
fi

SANDBOX="$WORLD/Sandbox.sbc"
SECTOR="$WORLD/SANDBOX_0_0_0_.sbs"
[[ -f "$SANDBOX" ]] || { echo "ERROR: Not found: $SANDBOX"; exit 1; }
[[ -f "$SECTOR"  ]] || { echo "ERROR: Not found: $SECTOR";  exit 1; }

# Remove SE rolling backups so the server cannot fall back to old saves
echo "Removing SE backup files..."
rm -f  "$WORLD"/SANDBOX_0_0_0_.sbsB*
rm -rf "$WORLD/Backup"
echo ""

PYTMP=$(mktemp /tmp/se_cleanse_XXXXXX.py)
trap 'rm -f "$PYTMP"' EXIT

cat > "$PYTMP" <<'PY'
import sys, re, xml.etree.ElementTree as ET
from pathlib import Path

sb  = Path(sys.argv[1])
sec = Path(sys.argv[2])


# ── helpers ──────────────────────────────────────────────────────────────────

def clear_section(txt, tag):
    """Clear content inside the OUTERMOST <tag>…</tag>, handling nested same-name tags.
    Preserves the outer open/close tags; removes everything between them."""
    open_tag  = f'<{tag}>'
    close_tag = f'</{tag}>'
    pos = txt.find(open_tag)
    if pos == -1:
        return txt
    depth = 0
    i = pos
    while i < len(txt):
        o = txt.find(open_tag,  i)
        c = txt.find(close_tag, i)
        if o != -1 and (c == -1 or o < c):
            depth += 1
            i = o + len(open_tag)
        elif c != -1:
            depth -= 1
            if depth == 0:
                return txt[:pos + len(open_tag)] + txt[c:]
            i = c + len(close_tag)
        else:
            break
    return txt  # no matching close tag found — leave untouched


# ── Sandbox.sbc (regex — preserves original XML format exactly) ──────────────

print("[Sandbox.sbc]")
txt = sb.read_text('utf-8')

# 1. Extract player identity IDs from within Identities section only.
#    We search between the FIRST <Identities> and FIRST </Identities> which
#    covers the inner list (even if the outer container wraps it).
ids_start = txt.find('<Identities>')
ids_end   = txt.find('</Identities>', ids_start) if ids_start != -1 else -1
if ids_start != -1 and ids_end != -1:
    player_ids = set(re.findall(r'<IdentityId>(\d+)</IdentityId>',
                                txt[ids_start:ids_end]))
else:
    player_ids = set()
print(f"  Player identities: {len(player_ids)}")

# 2. Clear sections (handles nested same-name tags correctly)
for tag, label in [('Identities',    'Identities'),
                   ('Players',       'Players'),
                   ('AllPlayersData','AllPlayersData')]:
    before = len(txt)
    txt = clear_section(txt, tag)
    if len(txt) < before:
        print(f"  {label} cleared")

# 3. Remove factions whose Members contain a player identity ID.
removed_factions = []

def faction_filter(m):
    x = m.group(0)
    members_m = re.search(r'<Members>(.*?)</Members>', x, re.DOTALL)
    if members_m:
        member_ids = set(re.findall(r'<PlayerId>(\d+)</PlayerId>',
                                    members_m.group(1)))
        if member_ids & player_ids:
            name = re.search(r'<Name>(.*?)</Name>', x)
            tag  = re.search(r'<Tag>(.*?)</Tag>',  x)
            removed_factions.append(
                f"{name.group(1) if name else '?'} [{tag.group(1) if tag else '?'}]")
            return ''
    return x

txt = re.sub(r'<MyObjectBuilder_Faction\b.*?</MyObjectBuilder_Faction>',
             faction_filter, txt, flags=re.DOTALL)

if removed_factions:
    for f in removed_factions: print(f"  Faction removed: {f}")
else:
    print("  No player factions found")

sb.write_text(txt, 'utf-8')
print("  Written.\n")


# ── SANDBOX_0_0_0_.sbs (line-by-line — file too large for ET) ────────────────

print("[SANDBOX_0_0_0_.sbs]  (large file, please wait...)")
lines = sec.read_text('utf-8').splitlines(keepends=True)
print(f"  Lines: {len(lines):,}")

OPEN  = '<MyObjectBuilder_EntityBase '
CLOSE = '</MyObjectBuilder_EntityBase>'

def is_player_owned(xml):
    m = re.search(r'<BigOwners>(.*?)</BigOwners>', xml, re.DOTALL)
    if m:
        if set(re.findall(r'<long>(\d+)</long>', m.group(1))) & player_ids:
            return True
    if set(re.findall(r'<Owner>(\d+)</Owner>', xml)) & player_ids:
        return True
    return False

out = []; i = 0; kept = removed = 0

while i < len(lines):
    line = lines[i]

    if OPEN not in line:
        out.append(line); i += 1; continue

    # Self-closing entity on one line — not a grid, keep it
    if line.rstrip().endswith('/>'):
        out.append(line); i += 1; continue

    # Multi-line entity: collect until depth returns to 0
    buf = [line]; depth = 1; i += 1
    while i < len(lines) and depth > 0:
        l = lines[i]; buf.append(l)
        depth += l.count(OPEN) - l.count(CLOSE)
        i += 1

    xml   = ''.join(buf)
    etype_m = re.search(r'xsi:type="([^"]+)"', buf[0])
    etype   = etype_m.group(1) if etype_m else ''

    drop = False; reason = ''

    if etype == 'MyObjectBuilder_Character':
        drop, reason = True, 'player character'
    elif etype == 'MyObjectBuilder_CubeGrid':
        if re.search(r'<IsRespawnShip>true</IsRespawnShip>', xml, re.IGNORECASE):
            drop, reason = True, 'respawn ship'
        elif is_player_owned(xml):
            drop, reason = True, 'player-owned'

    if drop:
        name = re.search(r'<DisplayName>(.*?)</DisplayName>', xml)
        print(f"  Remove [{etype.split('_')[-1]}] "
              f"'{name.group(1) if name else '?'}' — {reason}")
        removed += 1
    else:
        out.extend(buf)
        if etype == 'MyObjectBuilder_CubeGrid': kept += 1

sec.write_text(''.join(out), 'utf-8')
print(f"  Grids kept: {kept} | Entities removed: {removed}\n")


# ── Validate output XML ───────────────────────────────────────────────────────

print("[Validation]")
ok = True
for path in [sb, sec]:
    try:
        ET.parse(str(path))
        print(f"  {path.name}: OK")
    except ET.ParseError as e:
        print(f"  {path.name}: BROKEN — {e}")
        ok = False

if not ok:
    print("\nERROR: output XML is invalid — do NOT start server.")
    sys.exit(1)

print("\nCleanse complete. Start the server to load the clean world.")
PY

nix shell nixpkgs#python3 --command python3 "$PYTMP" "$SANDBOX" "$SECTOR"
