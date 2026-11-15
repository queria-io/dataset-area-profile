# dataset-area-profile

Queria のデータセット `area_profile`（地域カルテ）のリポジトリです。データセットの説明は [docs/index.md](docs/index.md) にあります。

## ビルド

```bash
uv sync
scripts/build.sh   # dbt で作って fdl commit
```

GitHub Actions の Sync が毎月 4 日（area_stats の翌日）に作り直します。
