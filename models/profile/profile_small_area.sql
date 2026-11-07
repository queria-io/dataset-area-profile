{{ config(alias='small_area') }}

{# 町丁目ごとのよく使う指標を 1 行に並べた表。1 行が国勢調査の小地域 (e_stat.boundary.small_area) 1 つ。
   元のデータセットは縦長 (区分 × 値) や地点 1 件 1 行で持っているので、町丁目どうしを比べたり
   地図で塗ったりするときに 1 回で引けるよう、よく使う数字だけを写して横に並べる。
   細かい区分が要るときは元のデータセットを読む #}

with small_area as materialized (
    select
        key_code,
        prefecture_code,
        prefecture_code || city_code as city_code,
        city_name,
        area_name,
        x_code as longitude,
        y_code as latitude,
        area_m2,
        jinko,
        setai,
        geometry
    from e_stat.boundary.small_area
    where length(key_code) in (9, 11)
),

-- 年齢 4 区分。cat01 の 0170〜0200 が総数の 15 歳未満・15〜64 歳・65 歳以上・75 歳以上。
-- 秘匿 (cat02 = 3) の町丁目は 0 が入る (実数は合算先の町丁目に含まれる) ので NULL にする
age as (
    select
        area as key_code,
        bool_or(cat02 = '3') as is_suppressed,
        sum(value) filter (where cat01 = '0170') as under_15,
        sum(value) filter (where cat01 = '0180') as age_15_64,
        sum(value) filter (where cat01 = '0190') as age_65_over,
        sum(value) filter (where cat01 = '0200') as age_75_over
    from e_stat.census.census_small_area_age
    where length(area) in (9, 11)
      and cat01 in ('0170', '0180', '0190', '0200')
    group by area
),

-- 店舗・施設。数えるときに除く行 (閉店・重複・確からしさが低い) と、人のいない設備は数えない。
-- 種類は日本標準産業分類の中分類でまとめる (queria.io のエリア分析と同じ分け方)
place as (
    select
        p.longitude,
        p.latitude,
        coalesce(t.industry_code, d.industry_code) as industry_code
    from overturemaps.places.place p
    left join overturemaps.places.category t
        on t.basic_category = p.basic_category and t.taxonomy_primary = p.taxonomy_primary
    left join overturemaps.places.category d
        on d.basic_category = p.basic_category and d.taxonomy_primary is null
    where p.exclude_reason is null
      and coalesce(t.is_unattended, d.is_unattended) is not true
),

-- 位置で町丁目に入れる
place_area as (
    select s.key_code, p.industry_code
    from place p
    join small_area s on st_contains(s.geometry, st_point(p.longitude, p.latitude))
),

facility as (
    select
        key_code,
        count(*) as facility_count,
        count(*) filter (where industry_code in ('76', '77')) as food_count,
        count(*) filter (where industry_code in ('56', '58')) as grocery_count,
        count(*) filter (where industry_code in ('57', '59', '60')) as shopping_count,
        count(*) filter (where industry_code in ('83', '84', '85')) as medical_count,
        count(*) filter (where industry_code in ('81', '82')) as education_count
    from place_area
    group by key_code
),

-- 駅。乗降客数は路線ごとの駅に入っていて、乗り換え駅は束ねたコード (station_group_code) でまとめる。
-- 他の路線の駅に記載された行 (duplicate_code = 2) は二重に数えないよう除く
station_year as (
    select max(year) as year
    from nlftp.railway.station_passenger
    where passenger_count is not null
),

station as materialized (
    select
        sp.station_group_code,
        min(sp.station_name) as station_name,
        avg(st_x(st_centroid(sp.geometry))) as longitude,
        avg(st_y(st_centroid(sp.geometry))) as latitude,
        sum(sp.passenger_count) filter (where sp.duplicate_code = '1') as passenger_count
    from nlftp.railway.station_passenger sp
    join station_year y using (year)
    group by sp.station_group_code
),

-- 町丁目の代表点から一番近い駅。経緯度で 0.1 度 (約 10 km) の箱に入る駅だけと比べる
nearest_station as (
    select
        s.key_code,
        st.station_name,
        st.passenger_count,
        st_distance_sphere(st_point(s.latitude, s.longitude), st_point(st.latitude, st.longitude)) as distance_m
    from small_area s
    join station st
        on st.longitude between s.longitude - 0.1 and s.longitude + 0.1
       and st.latitude between s.latitude - 0.1 and s.latitude + 0.1
    qualify row_number() over (partition by s.key_code order by distance_m) = 1
),

-- 地価は町丁目ごとに、値のある最新の年。地点の無くなった町に古い値が残らないよう、直近 3 年に限る
land_price_row as (
    select key_code, year, residential_price_median, commercial_price_median
    from area_stats.land_price.small_area
    where residential_price_median is not null or commercial_price_median is not null
),

land_price as (
    select *
    from land_price_row
    where year >= (select max(year) - 2 from land_price_row)
    qualify row_number() over (partition by key_code order by year desc) = 1
)

select
    s.key_code,
    s.prefecture_code,
    s.city_code,
    s.city_name,
    s.area_name,
    round(s.area_m2 / 1e6, 3) as area_km2,
    s.jinko as population,
    s.setai as households,
    cast(round(s.jinko / nullif(s.area_m2 / 1e6, 0)) as bigint) as population_density,
    cast(a.under_15 as bigint) as population_under_15,
    cast(a.age_15_64 as bigint) as population_15_64,
    cast(a.age_65_over as bigint) as population_65_over,
    cast(a.age_75_over as bigint) as population_75_over,
    -- 分母は年齢の分かる人 (3 区分の合計)。国勢調査の高齢化率と同じ
    round(100.0 * a.age_65_over / nullif(a.under_15 + a.age_15_64 + a.age_65_over, 0), 1) as aged_65_over_rate,
    coalesce(f.facility_count, 0) as facility_count,
    coalesce(f.food_count, 0) as food_count,
    coalesce(f.grocery_count, 0) as grocery_count,
    coalesce(f.shopping_count, 0) as shopping_count,
    coalesce(f.medical_count, 0) as medical_count,
    coalesce(f.education_count, 0) as education_count,
    ns.station_name as nearest_station_name,
    cast(round(ns.distance_m) as integer) as nearest_station_distance_m,
    ns.passenger_count as nearest_station_passenger_count,
    (select year from station_year) as station_passenger_year,
    lp.year as land_price_year,
    lp.residential_price_median,
    lp.commercial_price_median
from small_area s
left join age a on a.key_code = s.key_code and not a.is_suppressed
left join facility f on f.key_code = s.key_code
left join nearest_station ns on ns.key_code = s.key_code
left join land_price lp on lp.key_code = s.key_code
order by s.key_code
