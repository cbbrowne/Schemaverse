#!/bin/sh
PGDATABASE=schemaverse

# Recreate environment from scratch
dropdb $PGDATABASE
dropuser players
createdb $PGDATABASE
psql -d $PGDATABASE -U postgres -f create_schemaverse.sql > create_schemaverse.log 2>& create_schemaverse.errors

for file in test*.sql; do
    psql -d $PGDATABASE -U postgres -f $file > ${file}.log 2>& ${file}.errors
done
