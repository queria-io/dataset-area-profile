"""町丁目ごとのよく使う指標を 1 行に並べる。

元は Queria の公開データセット（e_stat・overturemaps・nlftp・area_stats）で、取得はしない。dbt だけを回す。
"""

import logging

from dbt.cli.main import dbtRunner

# dbt を読み込むとルートロガーが先に設定されるので、force で上書きする
logging.basicConfig(level=logging.INFO, format="%(message)s", force=True)


def main():
    dbt = dbtRunner()
    for args in (["deps"], ["run"], ["docs", "generate"]):
        if not dbt.invoke(args).success:
            raise SystemExit(f"dbt {args[0]} failed")


if __name__ == "__main__":
    main()
