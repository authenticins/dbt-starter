{#
  Lists the raw Attio tables you can read, with row counts.
  Usage:  dbt run-operation list_attio_tables
#}
{% macro list_attio_tables() %}
  {% set query %}
    select table_name, table_type, row_count, last_altered
    from {{ var('attio_database') }}.information_schema.tables
    where table_schema = upper('{{ var('attio_schema') }}')
    order by table_name
  {% endset %}

  {% set results = run_query(query) %}
  {% if execute %}
    {{ log("Tables in " ~ var('attio_database') ~ "." ~ var('attio_schema') ~ ":", info=True) }}
    {% for row in results.rows %}
      {{ log("  " ~ row[0] ~ "  (" ~ row[1] ~ ", " ~ row[2] ~ " rows, last altered " ~ row[3] ~ ")", info=True) }}
    {% endfor %}
  {% endif %}
{% endmacro %}
