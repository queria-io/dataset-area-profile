# 地域カルテ

町丁目ごとのよく使う指標を 1 行に並べたデータセットです。人口・年齢構成・店舗の種類別の数・最寄り駅・地価を、町丁目どうしを比べたり地図で塗ったりするときに 1 つの表で引けます。

元のデータセットは区分ごとの行（縦長）や地点 1 件 1 行で持っています。ここではよく使う数字だけを町丁目 1 行に写しています。細かい区分（5 歳階級など）が要るときは元のデータセットを読んでください。

## 出典と利用条件

Queria の公開データセット e_stat・nlftp・overturemaps・area_stats を読んで作ります。

| 原典 | 使うテーブル |
| --- | --- |
| [国勢調査](https://www.e-stat.go.jp/gis)（総務省統計局、令和2年） | `e_stat.boundary.small_area`、`e_stat.census.census_small_area_age` |
| [国土数値情報 駅別乗降客数データ](https://nlftp.mlit.go.jp/ksj/)（国土交通省） | `nlftp.railway.station_passenger` |
| [Overture Maps Foundation Places](https://overturemaps.org/) | `overturemaps.places.place`、`overturemaps.places.category` |
| [不動産情報ライブラリ](https://www.reinfolib.mlit.go.jp/)（国土交通省）、[アドレス・ベース・レジストリ](https://dataset.address-br.digital.go.jp/)（デジタル庁） | `area_stats.land_price.small_area` |

- 元データの利用規約に従います
- 店舗の数は Overture Places（CDLA-Permissive-2.0 ほか）から数えています
- 不動産情報ライブラリ: 「このサービスは、国土交通省の不動産情報ライブラリのAPI機能を使用していますが、提供情報の最新性、正確性、完全性等が保証されたものではありません。」

## テーブル

| テーブル | 内容 |
| --- | --- |
| `profile.small_area` | 町丁目ごとの指標。1 行が国勢調査の小地域 1 つ |

## 使い方

つくば市の町丁目を人口の多い順に、高齢化率・飲食店の数・最寄り駅と並べる:

```sql
SELECT area_name, population, aged_65_over_rate, food_count,
       nearest_station_name, nearest_station_distance_m
FROM area_profile.profile.small_area
WHERE city_code = '08220'
ORDER BY population DESC;
```

## 作り方と注意

- 1 行は `e_stat.boundary.small_area` の 1 行（9 桁の町丁・字等か、11 桁の内訳）です。`key_code` で国勢調査の小地域集計と結合できます
- 年齢 4 区分は国勢調査の小地域集計の値です。秘匿の町丁目は NULL で、人数は合算先の町丁目に含まれます。高齢化率の分母は年齢不詳を除いた 3 区分の合計です
- 店舗・施設は Overture Places の位置で町丁目に入れます。閉店・重複・確からしさの低いもの（`exclude_reason` のある行）と、ATM など人のいない設備は数えません。種類は日本標準産業分類の中分類でまとめます。Overture に登録の無い店は数えられないので、実際の店舗数より少ない地域があります
- 最寄り駅は町丁目の代表点から直線距離で一番近い駅です。10 km 以内に駅が無い町丁目は NULL です。廃止された駅は含めません。乗降客数は路線ごとに値のある最新の年（直近 3 年まで）の値で、乗り換え駅は路線をまとめた値です
- 地価は `area_stats.land_price.small_area` の、住宅地・商業地それぞれ値のある最新の年（直近 3 年まで）の値です
- 時点が列ごとに違います（人口は 2020 年、店舗は取り込み時点、乗降客数と地価はそれぞれの年の列のとおり）

## ビルド

```bash
uv sync
scripts/build.sh   # dbt で作って fdl commit
```

GitHub Actions の Sync が毎月 4 日（area_stats の翌日）に作り直します。
