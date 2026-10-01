{#
  TEMPLATE: copy this file once for each raw table you need, e.g.
  stg_attio__companies.sql, then delete this example.

  Staging conventions:
    - one model per source table, select only from source()
    - rename columns to snake_case and clear names (id -> company_id)
    - cast types and parse timestamps, with no joins or business logic
    - remove rows Fivetran has soft-deleted
#}
{{ config(enabled=false) }}

with source as (

    select * from {{ source('attio', 'REPLACE_WITH_TABLE_NAME') }}

),

renamed as (

    select
        id                as example_id,
        -- name           as example_name,
        -- created_at::timestamp_ntz as created_at,
        _fivetran_synced  as _loaded_at

    from source
    where not coalesce(_fivetran_deleted, false)

)

select * from renamed
