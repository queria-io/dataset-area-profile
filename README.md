# 地域カルテ

町丁目と市区町村ごとのよく使う指標を 1 行に並べたデータセットです。町丁目は人口・年齢構成・店舗の種類別の数・最寄り駅・地価を、市区町村は人口・年齢構成・昼間人口・将来推計人口・人口動態・財政力指数・事業所・医療施設・店舗の数を、地域どうしを比べたり地図で塗ったりするときに 1 つの表で引けます。

元のデータセットは区分ごとの行（縦長）や地点 1 件 1 行で持っています。ここではよく使う数字だけを町丁目 1 行に写しています。細かい区分（5 歳階級など）が要るときは元のデータセットを読んでください。

## 出典と利用条件

Queria の公開データセット e_stat・nlftp・overturemaps・area_stats を読んで作ります。

| 原典 | 使うテーブル |
| --- | --- |
| [国勢調査](https://www.e-stat.go.jp/gis)（総務省統計局、令和2年・令和7年） | `e_stat.boundary.small_area`、`e_stat.census.census_small_area_age`、`e_stat.census.census_municipality_2025`、`e_stat.census.census_municipality_age_2025`、`e_stat.census.census_municipality_daytime_population` |
| [住民基本台帳人口移動報告](https://www.stat.go.jp/data/idou/)（総務省統計局） | `e_stat.migration.municipality_migration` |
| [人口動態統計](https://www.mhlw.go.jp/toukei/list/81-1.html)（厚生労働省） | `e_stat.vital_statistics.vital_events` |
| [地方財政状況調査](https://www.soumu.go.jp/iken/jokyo_chousa_shiryo.html)（総務省） | `e_stat.local_finance.fiscal_capacity` |
| [経済センサス‐活動調査](https://www.stat.go.jp/data/e-census/)（総務省・経済産業省、令和3年） | `e_stat.economic_census.establishment_industry` |
| [医療施設調査](https://www.mhlw.go.jp/toukei/list/79-1.html)（厚生労働省） | `e_stat.medical_facility.municipality_facility` |
| [日本の地域別将来推計人口（令和5年推計）](https://www.ipss.go.jp/pp-shicyoson/j/shicyoson23/t-page.asp)（国立社会保障・人口問題研究所） | `ipss.regional_projection.population` |
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
| `profile.city` | 市区町村ごとの指標。1 行が令和7年国勢調査の市区町村 1 つ（政令指定都市の区・特別区・特別区部を含む） |

## 使い方

つくば市の町丁目を人口の多い順に、高齢化率・飲食店の数・最寄り駅と並べる:

```sql
SELECT area_name, population, aged_65_over_rate, food_count,
       nearest_station_name, nearest_station_distance_m
FROM area_profile.profile.small_area
WHERE city_code = '08220'
ORDER BY population DESC;
```

茨城県の市町村を将来推計人口の増減率の順に、財政力指数と並べる:

```sql
SELECT city_name, population, aged_65_over_rate,
       projected_change_rate_2050, fiscal_capacity_index
FROM area_profile.profile.city
WHERE prefecture_code = '08' AND area_level <> 'ward'
ORDER BY projected_change_rate_2050;
```

## 作り方と注意

- 1 行は `e_stat.boundary.small_area` の 1 行（9 桁の町丁・字等か、11 桁の内訳）です。`key_code` で国勢調査の小地域集計と結合できます
- 年齢 4 区分は国勢調査の小地域集計の値です。秘匿の町丁目は NULL で、人数は合算先の町丁目に含まれます。高齢化率の分母は年齢不詳を除いた 3 区分の合計です
- 店舗・施設は Overture Places の位置で町丁目に入れます。閉店・重複・確からしさの低いもの（`exclude_reason` のある行）と、ATM など人のいない設備は数えません。種類は日本標準産業分類の中分類でまとめます。Overture に登録の無い店は数えられないので、実際の店舗数より少ない地域があります
- 最寄り駅は町丁目の代表点から直線距離で一番近い駅です。10 km 以内に駅が無い町丁目は NULL です。廃止された駅は含めません。乗降客数は路線ごとに値のある最新の年（直近 3 年まで）の値で、乗り換え駅は路線をまとめた値です
- 地価は `area_stats.land_price.small_area` の、住宅地・商業地それぞれ値のある最新の年（直近 3 年まで）の値です
- 時点が列ごとに違います（人口は 2020 年、店舗は取り込み時点、乗降客数と地価はそれぞれの年の列のとおり）

市区町村の表（`profile.city`）:

- 行は令和7年国勢調査の市・町村・政令指定都市の区・特別区と特別区部（13100）です。`area_level` が ward の行は親の市（`parent_city_code`）の内訳なので、市と一緒に合計すると二重に数えます。日本全域を 1 回ずつ覆うのは city と town_village の組です
- 人口・世帯・年齢 4 区分は令和7年国勢調査、昼間人口は令和2年国勢調査、事業所は令和3年経済センサス‐活動調査です。転入超過数・出生数と死亡数・財政力指数・医療施設は、それぞれ最新の年の値で、年は `*_year` の列にあります
- 政令指定都市と特別区部の行が元の表に無い値（医療施設・出生数と死亡数・将来推計人口・店舗の数）は、区の値を足しています
- 財政力指数は市区町村（特別区を含む）だけで、政令指定都市の区と特別区部は NULL です。福島県の浜通り 13 市町村は将来推計人口が個別に無いので NULL です
- 店舗の数は町丁目の表を市区町村ごとに足した値です

## ファイルの分け方

DuckLake のカタログを読まずに Parquet を直接読んでキーで 1 行を引けるよう、表は毎回まるごと作り直し、行グループを 2,048 行にしています。町丁目の表は都道府県コード（`prefecture_code`）ごとのファイルに分けています。

## ビルド

```bash
uv sync
scripts/build.sh   # dbt で作って fdl commit
```

GitHub Actions の Sync が毎月 4 日（area_stats の翌日）に作り直します。
