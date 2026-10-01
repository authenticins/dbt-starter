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

> _Hiring manager: describe the exercise here, e.g. "Model Attio companies,
> people and deals, then expose pipeline metrics (deal count, pipeline value,
> win rate by month) through the dbt Semantic Layer."_

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

## Notes on Fivetran data

- `_FIVETRAN_SYNCED` is the time the row was loaded. Use it for source freshness.
- `_FIVETRAN_DELETED = TRUE` marks soft-deleted rows. Filter them out in staging.
- Attio's data model is flexible. Custom object attributes may be stored as
  key/value rows or as `VARIANT`/JSON columns. Look at the raw data before you
  design marts. `LATERAL FLATTEN` and `:`-path access will help.

## What we look for

- Clear layers: sources → staging → marts → semantic models
- Tests on keys and important assumptions (`unique`, `not_null`, `relationships`)
- Documented models and columns
- Semantic models and metrics that pass `mf validate-configs` and answer real business questions
- A short write-up (in this README or a PR description) of decisions and trade-offs
