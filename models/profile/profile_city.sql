{{ config(alias='city') }}

{# 市区町村ごとのよく使う指標を 1 行に並べた表。1 行が令和7年国勢調査の市区町村 1 つ。
   市・町村に加えて、政令指定都市の区と東京都の特別区、特別区部 (13100) の行もある。
   元の統計は表ごとに粒度と時点が違うので、値ごとに年の列を持つ。
   政令指定都市と特別区部の行が元の表に無い値 (医療施設・人口動態・店舗の数) は、区の値を足して埋める #}

with city as (
    select
        area as city_code,
        area_name as city_name,
        area_level,
        parent_area,
        population,
        households,
        population_2020,
        population_change_rate_5y,
        area_km2,
        population_density
    from e_stat.census.census_municipality_2025
    where area_level in ('city', 'ward', 'town_village')
),

-- 区から親の市 (政令指定都市・特別区部) への対応。区の値を足して親の行を埋めるときに使う
ward as (
    select city_code, parent_area as parent_code
    from city
    where area_level = 'ward'
),

age as (
    select
        area as city_code,
        sum(population) filter (where age_to <= 14) as under_15,
        sum(population) filter (where age_from >= 15 and age_to <= 64) as age_15_64,
        sum(population) filter (where age_from >= 65) as age_65_over,
        sum(population) filter (where age_from >= 75) as age_75_over
    from e_stat.census.census_municipality_age_2025
    where area_level in ('city', 'ward', 'town_village')
    group by area
),

-- 昼間人口は令和2年国勢調査 (location_code 1 = 従業地・通学地による人口、0 = 常住地による人口)
daytime as (
    select
        area as city_code,
        max(value) filter (where location_code = '1') as daytime_population,
        max(value) filter (where location_code = '0') as nighttime_population
    from e_stat.census.census_municipality_daytime_population
    where sex_code = '0' and location_code in ('0', '1')
    group by area
),

-- 社人研の令和5年推計。2020 年は国勢調査の実績値。特別区部の行は無いので区を足す。
-- 福島県の浜通り 13 市町村は個別の推計が無い (07999 にまとまっている) ので NULL
future_row as (
    select
        city_code,
        sum(population) filter (where year = 2020) as population_2020,
        sum(population) filter (where year = 2050) as population_2050
    from ipss.regional_projection.population
    where area_level <> 'prefecture'
    group by city_code
),

future as (
    {{ with_ward_sums('future_row', 'ward', ['population_2020', 'population_2050']) }}
),

-- 転入超過数は日本人と外国人の合計 (60000)。最新の年
migration as (
    select area as city_code, year, net_inflow
    from e_stat.migration.municipality_migration
    where sex_code = '0'
      and nationality_code = '60000'
      and area_level in ('municipality', 'ward')
      and year = (select max(year) from e_stat.migration.municipality_migration)
),

-- 人口動態は最新の年。特別区部の行は無いので区を足す
vital_row as (
    select area_code as city_code, year, births, deaths
    from e_stat.vital_statistics.vital_events
    where area_kind in ('municipality', 'designated_city', 'ward')
      and year = (select max(year) from e_stat.vital_statistics.vital_events)
),

vital as (
    {{ with_ward_sums('vital_row', 'ward', ['births', 'deaths'], maxes=['year']) }}
),

-- 財政力指数は市区町村 (特別区を含む) だけ。政令指定都市の区には無い。最新の年度
fiscal as (
    select area_code as city_code, fiscal_year, fiscal_capacity_index
    from e_stat.local_finance.fiscal_capacity
    qualify row_number() over (partition by area_code order by fiscal_year desc) = 1
),

-- 令和3年経済センサス‐活動調査の全産業 (公務を除く)・経営組織の総数
establishment as (
    select area as city_code, establishments, employees
    from e_stat.economic_census.establishment_industry
    where industry_code = 'AR'
      and organization_code = '0'
      and area_level in ('municipality', 'ward')
),

-- 医療施設調査の最新の年。政令指定都市は区の行だけなので区を足す
medical_row as (
    select area_code as city_code, survey_year, hospitals, hospital_beds, general_clinics, dental_clinics
    from e_stat.medical_facility.municipality_facility
    where area_level = 'municipality'
      and survey_year = (select max(survey_year) from e_stat.medical_facility.municipality_facility)
),

medical as (
    {{ with_ward_sums('medical_row', 'ward', ['hospitals', 'hospital_beds', 'general_clinics', 'dental_clinics'], maxes=['survey_year']) }}
),

-- 店舗の数は町丁目の表を足す。町丁目の city_code は政令指定都市では区なので、親の市は区を足す
facility_row as (
    select
        city_code,
        sum(facility_count) as facility_count,
        sum(food_count) as food_count,
        sum(grocery_count) as grocery_count,
        sum(shopping_count) as shopping_count,
        sum(medical_count) as medical_count,
        sum(education_count) as education_count
    from {{ ref('profile_small_area') }}
    group by city_code
),

-- 町丁目の表は令和2年の境界なので、区から親の市への対応も令和2年国勢調査のものを使う
-- (浜松市は 2024 年に区を 7 つから 3 つに再編したので、令和7年の区のコードでは町丁目を引けない)
ward_2020 as (
    select distinct area as city_code, parent_area as parent_code
    from e_stat.census.census_municipality_daytime_population
    where area_level = 'ward'
),

facility as (
    {{ with_ward_sums('facility_row', 'ward_2020', ['facility_count', 'food_count', 'grocery_count', 'shopping_count', 'medical_count', 'education_count']) }}
)

select
    c.city_code,
    -- 特別区部は全国地方公共団体コードを持たない
    case when c.city_code <> '13100' then {{ local_government_code('c.city_code') }} end as lg_code,
    left(c.city_code, 2) as prefecture_code,
    c.city_name,
    c.area_level,
    case when c.area_level = 'ward' then c.parent_area end as parent_city_code,
    c.area_km2,
    c.population,
    c.households,
    c.population_density,
    c.population_2020,
    c.population_change_rate_5y,
    cast(a.under_15 as bigint) as population_under_15,
    cast(a.age_15_64 as bigint) as population_15_64,
    cast(a.age_65_over as bigint) as population_65_over,
    cast(a.age_75_over as bigint) as population_75_over,
    -- 分母は年齢の分かる人 (3 区分の合計)
    round(100.0 * a.age_65_over / nullif(a.under_15 + a.age_15_64 + a.age_65_over, 0), 1) as aged_65_over_rate,
    d.daytime_population,
    round(100.0 * d.daytime_population / nullif(d.nighttime_population, 0), 1) as daytime_population_ratio,
    cast(f.population_2050 as bigint) as projected_population_2050,
    round(100.0 * (f.population_2050 - f.population_2020) / nullif(f.population_2020, 0), 1) as projected_change_rate_2050,
    m.net_inflow as net_migration,
    m.year as net_migration_year,
    cast(v.births as bigint) as births,
    cast(v.deaths as bigint) as deaths,
    v.year as vital_statistics_year,
    fc.fiscal_capacity_index,
    fc.fiscal_year,
    e.establishments,
    e.employees,
    cast(md.hospitals as bigint) as hospitals,
    cast(md.hospital_beds as bigint) as hospital_beds,
    cast(md.general_clinics as bigint) as general_clinics,
    cast(md.dental_clinics as bigint) as dental_clinics,
    md.survey_year as medical_facility_year,
    cast(fa.facility_count as bigint) as facility_count,
    cast(fa.food_count as bigint) as food_count,
    cast(fa.grocery_count as bigint) as grocery_count,
    cast(fa.shopping_count as bigint) as shopping_count,
    cast(fa.medical_count as bigint) as medical_count,
    cast(fa.education_count as bigint) as education_count
from city c
left join age a on a.city_code = c.city_code
left join daytime d on d.city_code = c.city_code
left join future f on f.city_code = c.city_code
left join migration m on m.city_code = c.city_code
left join vital v on v.city_code = c.city_code
left join fiscal fc on fc.city_code = c.city_code
left join establishment e on e.city_code = c.city_code
left join medical md on md.city_code = c.city_code
left join facility fa on fa.city_code = c.city_code
order by c.city_code
