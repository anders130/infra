#!/bin/bash
# reset_terrain.sh — Reset mined planet/asteroid terrain in SE save
#
# How it works:
#   Space Engineers planet terrain is stored in gzip-compressed .vx2 files.
#   Each file embeds a short "type name" (e.g. "Moon", "EarthLike") as a
#   length-prefixed string after the material list.  The file on disk is named
#   after the planet's full StorageName (type + seed + diameter).
#   An empty/unmodified .vx2 is ~400 bytes; anything larger has player digs.
#   This script regenerates the large files from a small template, swapping
#   only the embedded type name so SE sees "empty terrain" for each planet.
#
# Usage:
#   sudo bash reset_terrain.sh <world_dir>
#   e.g.  sudo bash reset_terrain.sh \
#           /var/lib/space-engineers/instances/default/Saves/NewWorld

set -euo pipefail

WORLD="${1:?Usage: $0 <world_dir>}"
[[ -d "$WORLD" ]] || { echo "ERROR: Not a directory: $WORLD"; exit 1; }

PYTMP=$(mktemp /tmp/se_reset_XXXXXX.py)
trap 'rm -f "$PYTMP"' EXIT

cat > "$PYTMP" << 'PY'
import gzip, pathlib, re, sys, xml.etree.ElementTree as ET

world = pathlib.Path(sys.argv[1])

# Unmodified planet .vx2 files compress to ~400-530 bytes.
# Anything significantly larger has been modified by players.
EMPTY_THRESHOLD = 600

def load_vx2(path):
    return gzip.decompress(path.read_bytes())

def find_embedded_name(data, search_from=400):
    """Return (pos, name) of the LAST length-prefixed ASCII identifier string
    after `search_from`.  Material/biome names appear first; the planet type
    name (e.g. "Moon", "EarthLike") is the last such string in the header."""
    last_pos, last_name = -1, ''
    for pos in range(search_from, min(search_from + 300, len(data) - 2)):
        n = data[pos]
        if not (2 <= n <= 50):
            continue
        try:
            s = data[pos + 1 : pos + 1 + n].decode('ascii')
        except (UnicodeDecodeError, ValueError):
            continue
        if re.match(r'^[A-Za-z][A-Za-z0-9_\-]*$', s):
            last_pos, last_name = pos, s
    return last_pos, last_name

def make_fresh_vx2(tmpl_data, tmpl_embedded, target_embedded, out_path):
    """Write a fresh (empty-terrain) .vx2 to out_path by replacing the embedded
    type name in tmpl_data."""
    pos = tmpl_data.rfind(
        bytes([len(tmpl_embedded)]) + tmpl_embedded.encode('ascii'),
        400
    )
    if pos == -1:
        raise ValueError(f"Embedded name '{tmpl_embedded}' not found after byte 400")

    old = bytes([len(tmpl_embedded)]) + tmpl_embedded.encode('ascii')
    new = bytes([len(target_embedded)]) + target_embedded.encode('ascii')
    result = tmpl_data[:pos] + new + tmpl_data[pos + len(old):]
    compressed = gzip.compress(result, compresslevel=9)
    out_path.write_bytes(compressed)
    return len(compressed)

# ── Planet files — restore from original game files ───────────────────────────

game_dir = pathlib.Path("/var/lib/space-engineers/SpaceEngineersDedicated/Content")

# Find all planet storage names from the save file + existing large .vx2 files
sandbox_sbc = world / "Sandbox.sbc"
planet_stems = set()
if sandbox_sbc.exists():
    try:
        tree = ET.parse(sandbox_sbc)
        for elem in tree.iter():
            sn = elem.findtext("StorageName")
            if sn and not any(sn.startswith(p) for p in ("GE_Voxel", "Asteroid", "Boulder")):
                planet_stems.add(sn)
    except ET.ParseError as e:
        print(f"WARNING: Could not parse Sandbox.sbc: {e}")

for vx2 in world.glob("*.vx2"):
    s = vx2.stem
    if not any(s.startswith(p) for p in ("GE_Voxel", "Asteroid", "Boulder")):
        if vx2.stat().st_size > EMPTY_THRESHOLD:
            planet_stems.add(s)

print(f"[Planet terrain reset]  {len(planet_stems)} planet(s) found\n")

reset_count = 0
for stem in sorted(planet_stems):
    vx2 = world / f"{stem}.vx2"
    size = vx2.stat().st_size if vx2.exists() else 0
    if size <= EMPTY_THRESHOLD and vx2.exists():
        continue  # already fresh

    # Find matching original in game content — prefer smallest (freshest) copy
    originals = sorted(game_dir.rglob(f"{stem}.vx2"), key=lambda f: f.stat().st_size)
    if not originals:
        print(f"  SKIP  {stem}.vx2 — no original found in game content")
        continue

    import shutil
    shutil.copy2(originals[0], vx2)
    new_size = vx2.stat().st_size
    status = f"{size} → {new_size} bytes" if size else f"created ({new_size} bytes)"
    print(f"  Restored  {stem}.vx2  {status}  (from {originals[0].parent.name})")
    reset_count += 1

if reset_count == 0:
    print("  Nothing to restore — all planet .vx2 files are already fresh.")

# ── GE_Voxel files (MES mod asteroids) — find smallest as template ───────────

ge_small = sorted(
    [f for f in world.glob("GE_Voxel_*.vx2") if f.stat().st_size <= EMPTY_THRESHOLD],
    key=lambda f: f.stat().st_size,
)

if ge_small:
    ge_tmpl      = ge_small[0]
    ge_tmpl_data = load_vx2(ge_tmpl)
    _, ge_embedded = find_embedded_name(ge_tmpl_data)
    print(f"\n[GE_Voxel terrain reset]  template: {ge_tmpl.stem!r}, embedded: '{ge_embedded}'\n")

    for vx2 in sorted(world.glob("GE_Voxel_*.vx2")):
        size = vx2.stat().st_size
        if size <= EMPTY_THRESHOLD or vx2 == ge_tmpl:
            continue
        try:
            # MES mod uses the full stem as the embedded type name
            new_size = make_fresh_vx2(ge_tmpl_data, ge_embedded, vx2.stem, vx2)
            print(f"  Reset  {vx2.stem}.vx2   {size} → {new_size} bytes")
        except Exception as e:
            print(f"  ERROR  {vx2.stem}: {e}")

print("\nTerrain reset complete.  Restart the server to apply changes.")
PY

nix shell nixpkgs#python3 --command python3 "$PYTMP" "$WORLD"
