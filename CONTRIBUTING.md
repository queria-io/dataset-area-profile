# ビルドと更新

データセットの概要は [README.md](README.md) にあります。ここにはこのリポジトリでデータセットをビルド・更新する手順を書きます。

## ビルド

```bash
uv sync
scripts/build.sh   # dbt で作って fdl commit
```

GitHub Actions の Sync が毎月 4 日（area_stats の翌日）に作り直します。
