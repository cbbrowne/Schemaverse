-- Deploy view-players
-- requires: table-player

BEGIN;

CREATE OR REPLACE VIEW players AS 
 SELECT p.id, p.username, p.created, p.symbol, p.rgb
   FROM player p;

COMMIT;
