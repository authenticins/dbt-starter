{#
  Puts every model in the target schema (PLAYGROUND_DB.DE_INTERVIEW).
  By default dbt adds "+schema" configs to the end of the schema name
  (e.g. DE_INTERVIEW_MARTS). Your role isn't allowed to create new schemas,
  so this macro turns that off.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ target.schema }}
{%- endmacro %}
