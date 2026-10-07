#!/bin/sh
# Cria os dois bancos da instância "postgres-app" e aplica o schema de cada um.
# Executado automaticamente pelo entrypoint do Postgres na primeira inicialização.
set -e

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE flags_db;"
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d flags_db -f /sql/flag-init.sql

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE targeting_db;"
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d targeting_db -f /sql/targeting-init.sql
