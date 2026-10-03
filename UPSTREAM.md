# Upstream provenance

BLML is a fork of [Tinode](https://github.com/tinode/chat). This project was
flattened into a single repository on 2026-08-04, so the original per-repo
git histories are no longer present. This file records exactly what each
directory was forked from, so upstream changes can still be diffed or
re-forked by hand later.

| Directory | Upstream | Commit | Tag |
|---|---|---|---|
| `server/` | https://github.com/tinode/chat.git | `22a7c18e9cd695e9a061bf1b8c84175196ef5a15` | v0.25.3 |
| `webapp/` | https://github.com/tinode/webapp.git | `14e1e6b5493f3f46450e59ec92b7fec96f4a22b6` | v0.25.3-1-g14e1e6b5 |
| `android/` | https://github.com/tinode/tindroid.git | `b60c3b8962ae235341141f5449a7fd7879043216` | v0.25.5 |
| `ios/` | https://github.com/tinode/ios.git | `a4db1251549c40b7aa4f269cd79234eb4c07baff` | v1.24.4 |

## Re-syncing with upstream later

```bash
# Example for the server; same pattern for the others.
git clone https://github.com/tinode/chat.git /tmp/upstream-chat
cd /tmp/upstream-chat && git diff <commit-above>..HEAD -- . > /tmp/upstream.patch
# then apply selectively to server/ in this repo
```

## Licensing

- `server/` — GPL-3.0 (see server/LICENSE). Publishing this repo distributes it,
  so the server directory and its modifications remain GPL-3.0.
- `webapp/`, `android/`, `ios/` — Apache-2.0 (see each LICENSE).
- Upstream copyright notices in source headers are retained.
- All four directories have been modified by BLML since the fork (2026); the
  git history of this repository records every change.

## What must stay, and where the credit is shown

Do not remove any of these — together they are what the two licenses ask for:

- The four `LICENSE` files and the `Copyright … Tinode` headers in source files.
- This file: it is the notice that the code is a modified version of Tinode,
  and from which date.
- The license entry each client shows to users, which names Tinode LLC as a
  copyright holder and carries the Apache 2.0 text:
  - Android: Settings → Help → Licenses (`license_notice` in `strings.xml`).
  - iOS: the Settings app → BLML → Acknowledgements
    (`ios/acknowledgement-blml.txt`, re-added after every `pod install`).
  - Web: `licenses.html`, linked from Settings → Help.

Nothing else has to mention Tinode: not the About screens, the README, the
store listings or the websites.
