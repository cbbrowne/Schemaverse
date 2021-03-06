-- Deploy trigger-destroy_ship
-- requires: table-ship

BEGIN;

CREATE OR REPLACE FUNCTION destroy_ship()
  RETURNS trigger AS
$BODY$
BEGIN
	IF ( NOT OLD.destroyed = NEW.destroyed ) AND NEW.destroyed='t' THEN
	        UPDATE player SET balance=balance+(select cost from price_list where code='SHIP') WHERE id=OLD.player_id;
		
		INSERT INTO event(action, player_id_1, ship_id_1, location, public, tic)
			VALUES('EXPLODE',NEW.player_id, NEW.id, NEW.location, 't',(SELECT last_value FROM tic_seq));

	END IF;
	RETURN NULL;
END
$BODY$
  LANGUAGE plpgsql VOLATILE SECURITY DEFINER
  COST 100;

drop trigger if exists destroy_ship on ship;
CREATE TRIGGER destroy_ship
  AFTER UPDATE
  ON ship
  FOR EACH ROW
  EXECUTE PROCEDURE destroy_ship();

COMMIT;
