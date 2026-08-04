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
