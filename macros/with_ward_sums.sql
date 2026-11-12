{# 市区町村の行 (rows) に、行の無い親の市 (政令指定都市・特別区部) の行を、区の値を足して加えた select。
   wards は区の city_code から親の市の parent_code への対応。sums の列は区の合計、maxes の列 (年など) は区の最大を取る #}

{% macro with_ward_sums(rows, wards, sums, maxes=[]) -%}
    select city_code{% for c in maxes + sums %}, {{ c }}{% endfor %}
    from {{ rows }}
    union all
    select w.parent_code{% for c in maxes %}, max(r.{{ c }}){% endfor %}{% for c in sums %}, sum(r.{{ c }}){% endfor %}
    from {{ rows }} r
    join {{ wards }} w using (city_code)
    where w.parent_code not in (select city_code from {{ rows }})
    group by w.parent_code
{%- endmacro %}
