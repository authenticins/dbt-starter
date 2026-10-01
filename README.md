# Attio Analytics: dbt take-home

You have:

| | |
|---|---|
| **Read-only source** | `FIVETRAN_DATABASE.ATTIO`: raw Attio CRM data, synced by Fivetran |
| **Your sandbox** | `PLAYGROUND_DB.DE_INTERVIEW`: dbt builds everything here |
| **Role / warehouse** | `ATTIO_CANDIDATE_ROLE` / `ATTIO_CANDIDATE_WH` (XSMALL) |
| **Users** | `ATTIO_CANDIDATE` for Snowsight (password + MFA); `ATTIO_CANDIDATE_SVC` for dbt (key pair, no MFA) |

Your role can't create other schemas, so this project puts every model in your
sandbox schema (`macros/generate_schema_name.sql`). Name prefixes show which
layer a model belongs to.

## The task

**Build a semantic layer on the Attio CRM data in `FIVETRAN_DATABASE.ATTIO`.**
Turn the raw tables into clean, tested dbt models. Then define MetricFlow
semantic models and metrics that let someone answer business questions about
the CRM without writing SQL.

Most of Attio's data is generic. Records and their attribute values are stored
as key/value rows (`RECORD` + `RECORD_VALUE`), not as one table per object. A
large part of the work is turning that into models a business user understands,
such as companies, people and deals.

### What to deliver

1. **Staging models** (`models/staging/attio/`): one model for each raw table
   you use, with columns renamed and cast, and soft-deleted rows removed.
2. **Object models** (`models/intermediate/` or `models/marts/`): pivot
   `RECORD_VALUE` into one wide model for each Attio object in the workspace,
   e.g. `companies`, `people`, `deals`, plus any custom objects. Use `OBJECT`
   and `OBJECT_ATTRIBUTE` to find the objects and attributes. Replace select
   and status IDs with their titles from `OBJECT_ATTRIBUTE_OPTION` and
   `OBJECT_ATTRIBUTE_STATUS`.
3. **Marts** (`models/marts/`): facts and dimensions to build the semantic
   layer on, e.g. `dim_companies`, `dim_people`, `dim_workspace_members`,
   `fct_deals`, `fct_list_entries`, `fct_notes`.
4. **Semantic layer** (`models/semantic/`): semantic models with entities,
   dimensions and measures, and metrics built on them. All of it must pass
   `mf validate-configs`. The metrics should answer questions like:
   - How many deals were created each month, and what are they worth?
   - What is the pipeline value by stage today?
   - What is the win rate, and how long do deals take to close?
   - Which companies and people have the most activity (notes, list entries)?
   - How is work distributed across workspace members?

   Use the objects and attributes that actually exist in this workspace. If a
   question can't be answered from the data, say so in your write-up.
5. **Tests and docs**: test primary keys and relationships, plus any
   assumptions you rely on. Describe each model and its important columns.
6. **Write-up**: add a short `NOTES.md` covering your modeling decisions, the
   trade-offs you made, data quality issues you found, and what you would do
   next with more time. Include 2–3 example `mf query` commands with their
   output.

## Setup

### 1. Install

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
dbt deps
```

### 2. Authenticate

You have two users with the same access:

- **`ATTIO_CANDIDATE`** is for Snowsight. Log in once with the temporary password
  you were given, then set a new password and enroll in MFA.
- **`ATTIO_CANDIDATE_SVC`** is for dbt. It signs in only with a key pair, so it
  never prompts for MFA. Generate one:

```bash
openssl genrsa 2048 | openssl pkcs8 -topk8 -v2 des3 -inform PEM -out ~/.ssh/snowflake_rsa_key.p8
openssl rsa -in ~/.ssh/snowflake_rsa_key.p8 -pubout -out ~/.ssh/snowflake_rsa_key.pub
```

Keep the `.p8` private key to yourself. Don't share it with anyone. Attach the
public key to the service user yourself: print it without the header and
footer lines,

```bash
grep -v "PUBLIC KEY" ~/.ssh/snowflake_rsa_key.pub | tr -d '\n'
```

then log in to Snowsight as `ATTIO_CANDIDATE` and run:

```sql
ALTER USER ATTIO_CANDIDATE_SVC SET RSA_PUBLIC_KEY = '<paste output here>';
```

### 3. Configure

```bash
cp .env.example .env      # fill in account and key path/passphrase
set -a && source .env && set +a
dbt debug                 # should end with "All checks passed!"
```

To run dbt as your Snowsight user (password + MFA) instead, add `--target dev_password` to each dbt command.

## Workflow

```bash
# See what raw data is available
dbt run-operation list_attio_tables

# Generate source YAML (paste the output into models/staging/attio/_attio__sources.yml)
dbt run-operation generate_source --args '{"schema_name": "ATTIO", "database_name": "FIVETRAN_DATABASE", "generate_columns": true}'

# Generate a staging model skeleton for a table
dbt run-operation generate_base_model --args '{"source_name": "attio", "table_name": "<TABLE>"}'

# Preview data
dbt show --inline "select * from {{ source('attio', '<TABLE>') }}" --limit 20

# Build and test everything
dbt build

# Semantic Layer (MetricFlow)
mf validate-configs
mf list metrics
mf query --metrics <metric> --group-by metric_time__month
```

## Project layout

```
models/
  staging/attio/     one view per raw table (rename, cast, remove soft-deletes)
  intermediate/      optional joins and reshaping
  marts/             facts and dimensions (tables)
  semantic/          time spine, semantic models and metrics (MetricFlow)
macros/              generate_schema_name override, list_attio_tables helper
analyses/            scratch exploration SQL
```

## Source data reference: Fivetran Attio connector

Official docs:

- [Attio connector overview](https://fivetran.com/docs/connectors/applications/attio)
  covers features, sync behavior and schema information.
- [Interactive schema ERD](https://fivetran.com/connector-erd/attio) shows every
  table, column, key and relationship.
- [Release notes](https://fivetran.com/docs/connectors/applications/attio/changelog)
- [Attio API reference](https://docs.attio.com/) explains objects, attributes,
  attribute types, and how values are structured.

The tables below come from Fivetran's ERD. Snowflake shows names in uppercase,
for example `RECORD_VALUE`. Fivetran may not sync every table, so check what
exists with `dbt run-operation list_attio_tables`.

### Tables

| Table | Grain (primary key) | Key columns | What it is |
|---|---|---|---|
| `OBJECT` | `id, workspace_id` | `api_slug`, `singular_noun`, `plural_noun`, `created_at` | Object types, both standard (companies, people, deals) and custom |
| `OBJECT_ATTRIBUTE` | `id, workspace_id, target_id` | `api_slug`, `title`, `type`, `is_multiselect`, `is_required`, `is_unique`, `is_archived`, `config_currency_*`, `config_record_reference_allowed_object_ids` | Attribute definitions for each object. `target_id` is the object |
| `OBJECT_ATTRIBUTE_OPTION` | `id, attribute_id, target_id, workspace_id` | `title`, `is_archived` | Options for select attributes |
| `OBJECT_ATTRIBUTE_STATUS` | `id, attribute_id, target_id, workspace_id` | `title`, `is_archived`, `target_time_in_status`, `celebration_enabled` | Options for status attributes, e.g. deal stages |
| `RECORD` | `id, object_id, workspace_id` | `created_at` | One row per record (one company, person, deal, …) |
| `RECORD_VALUE` | `name, record_id, record_object_id, record_workspace_id` | `value` | Attribute values for records, stored as key/value rows. `name` is the attribute |
| `LIST` | `id, workspace_id` | `api_slug`, `name`, `parent_object`, `workspace_access`, `created_by_actor_id`, `created_by_actor_type`, `created_at` | Lists (pipelines, boards) built on top of an object |
| `LIST_ATTRIBUTE` | `id, workspace_id, target_id` | same columns as `OBJECT_ATTRIBUTE` | Attribute definitions for each list. `target_id` is the list |
| `LIST_ATTRIBUTE_OPTION` | `id, attribute_id, target_id, workspace_id` | `title`, `is_archived` | Options for list select attributes |
| `LIST_ATTRIBUTE_STATUS` | `id, attribute_id, target_id, workspace_id` | `title`, `is_archived`, `target_time_in_status`, `celebration_enabled` | Options for list status attributes, e.g. pipeline stages |
| `LIST_WORKSPACE_MEMBER_ACCESS` | `list_id, workspace_id, workspace_member_id` | `level` | Each member's access level on each list |
| `ENTRIES` | `id, list_id, workspace_id` | `parent_object`, `parent_record_id`, `created_at` | A record's membership in a list. `parent_record_id` links to `RECORD` |
| `ENTRIES_VALUE` | `name, id, list_id, workspace_id` | `value` | List-level attribute values for each entry, stored as key/value rows |
| `NOTE` | `id, workspace_id` | `title`, `content_plaintext`, `object`, `record_id`, `created_by_actor_id`, `created_by_actor_type`, `created_at` | Notes attached to records |
| `WORKSPACE_MEMBER` | `id, workspace_id` | `first_name`, `last_name`, `email_address`, `access_level`, `created_at` | Users in the Attio workspace |

### How the tables relate

```
OBJECT ─┬─< OBJECT_ATTRIBUTE ─┬─< OBJECT_ATTRIBUTE_OPTION
        │   (target_id)       └─< OBJECT_ATTRIBUTE_STATUS
        └─< RECORD ──< RECORD_VALUE   (name = attribute api_slug)
              │
              ├──< NOTE              (record_id)
              └──< ENTRIES ──< ENTRIES_VALUE
                    (parent_record_id)
LIST ─┬─< ENTRIES   (list_id)
      ├─< LIST_ATTRIBUTE ─┬─< LIST_ATTRIBUTE_OPTION
      │                   └─< LIST_ATTRIBUTE_STATUS
      └─< LIST_WORKSPACE_MEMBER_ACCESS >── WORKSPACE_MEMBER
```

### Things to know about this data

- **Values are stored as key/value rows.** In `RECORD_VALUE` and
  `ENTRIES_VALUE`, each row holds one attribute of one record or entry. Look at
  the raw `value` column first: it may be a plain string or JSON (record
  references, currency, multiselect). To turn the rows into columns, use
  `dbt_utils.pivot` or conditional aggregation, plus `PARSE_JSON`, `:` path
  access, or `LATERAL FLATTEN`.
- **Composite keys.** Almost every table's key includes `workspace_id`.
  Attribute and option tables are also scoped by `target_id`, the object or
  list. Join on all key columns, or build a surrogate key with
  `dbt_utils.generate_surrogate_key`.
- **Choose attribute metadata by attribute type.** Use `OBJECT_ATTRIBUTE.type`
  and `is_multiselect` to decide how to parse each value.
- **Full re-import.** Fivetran re-imports these tables and their child tables
  on every sync to pick up updates and deletes. There is no change history, so
  you see the current state only.
- **Deletes.** `_FIVETRAN_DELETED = TRUE` marks rows that were deleted in Attio.
  Filter them out in staging.
- **Freshness.** `_FIVETRAN_SYNCED` is the time the row was loaded. Use it for
  source freshness.

## What we look for

- **Modeling:** clear layers (sources → staging → objects/marts → semantic
  models) and a sensible way of turning the key/value data into columns that
  works for custom objects too, not only the ones you can see today
- **Semantic layer:** correct entities and joins, measures with the right
  aggregation, metrics that pass `mf validate-configs` and answer the questions
  above
- **Quality:** tests on keys, relationships and important assumptions;
  documented models and columns
- **Communication:** a clear `NOTES.md` covering decisions, trade-offs and data
  issues
