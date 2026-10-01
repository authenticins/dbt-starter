-- Scratch queries for exploring the raw data. Compile with `dbt compile` and
-- run the output in Snowsight, or use `dbt show --inline "..."`.

select table_name, row_count, last_altered
from {{ var('attio_database') }}.information_schema.tables
where table_schema = upper('{{ var('attio_schema') }}')
order by row_count desc
