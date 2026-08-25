"""Tiny inline-SVG charts.

Kept out of main.py so it can be imported and tested without FastAPI — the
rendering logic produces markup the operator actually looks at, and "it
imported cleanly" is not evidence that the polyline is in the right place.

No chart library and no CDN: one series, no interaction, and the webapp was
already cleaned of external script dependencies once.
"""
from __future__ import annotations


def sparkline(values: list[int], width: int = 560, height: int = 48) -> str:
    """A polyline scaled to the series' own peak.

    Returns "" for an empty series rather than a degenerate <svg>, so the
    template can simply drop it in.
    """
    if not values:
        return ""
    peak = max(values) or 1
    step = width / max(len(values) - 1, 1)
    points = " ".join(
        f"{i * step:.1f},{height - (v / peak) * (height - 4):.1f}"
        for i, v in enumerate(values))
    return (f'<svg viewBox="0 0 {width} {height}" preserveAspectRatio="none" '
            f'class="spark" role="img" aria-label="messages per day">'
            f'<polyline points="{points}" fill="none" stroke="currentColor" '
            f'stroke-width="2" stroke-linejoin="round"/></svg>')
