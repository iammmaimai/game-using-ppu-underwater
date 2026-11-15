"""Rebuild the one-bit collision map whenever data/map.mem changes."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
tiles = [int(v, 16) for v in (root / 'data/map.mem').read_text().split()]
assert len(tiles) == 80 * 60
(root / 'data/collision.mem').write_text(''.join(f'{int(t == 128 or 192 <= t <= 207)}\n' for t in tiles))
