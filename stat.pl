#!/usr/bin/perl
#############################
#       Stat v1.0           #
# Created by Josh McDougall #
#############################
# This should be run inside a screen/tmux session
# stat.pl keeps player_round_stats up to date

# use module
use DBI;
use DateTime;

my ($pgport, $pghost, $pgdatabase, $pguser, $sleeptime) =
	($ENV{"PGPORT"}, $ENV{"PGHOST"}, $ENV{"PGDATABASE"}, $ENV{"PGUSER"}, $ENV{"SCHEMAVERSESLEEP"});

if (length($pgdatabase) < 1) {
	die "Database not specified via environment variable PGDATABASE\n";
}
if (length($pguser) < 1) {
	die "Master user not specified via environment variable PGUSER\n";
}
if (length($pghost) < 1) {
	die "Database host not specified via environment variable PGHOST\n";
}
if ($sleeptime < 1) {
	print "No value provided for SCHEMAVERSESLEEP - using 60 to sleep 60s between rounds\n";
	$sleeptime = 60;
}

my $db_uri = "dbi:Pg:dbname=${pgdatabase};host=${pghost}";

printf ("Schemaverse: Launching stato.pl\n");
printf ("    URI being used: %s\n", $db_uri);
printf ("    PGPORT: %d  PGHOST: %s  PGDATABASE: %s  PGUSER: %s\n", $pgport, $pghost, $pgdatabase, $pguser);
printf ("    SCHEMAVERSESLEEP: %d \n", $sleeptime);

# Make the master database connection
my $master_connection = DBI->connect($db_uri, $pguser);

while (1){
	my $sql = "SELECT player_id, round_id FROM player_round_stats ORDER BY round_id DESC, last_updated ASC LIMIT 1;";

	my ($player_id, $round_id);
	my $rs = $master_connection->prepare($sql);
	$rs->execute();
	my ($player_count)=(0);
	while (($player_id, $round_id) = $rs->fetchrow()) {
		$player_count++;
		my $sql = "
		UPDATE player_round_stats SET
			damage_taken = current_player_stats.damage_taken,
			damage_done = current_player_stats.damage_done,
			planets_conquered = least(current_player_stats.planets_conquered,32767),
			planets_lost = least(current_player_stats.planets_lost,32767),
			ships_built = LEAST(current_player_stats.ships_built,32767),
			ships_lost = least(current_player_stats.ships_lost,32767),
			ship_upgrades = current_player_stats.ship_upgrades,
			fuel_mined = current_player_stats.fuel_mined,
			distance_travelled = current_player_stats.distance_travelled,
			last_updated=NOW()
			FROM current_player_stats
			WHERE player_round_stats.player_id=current_player_stats.player_id
			AND current_player_stats.player_id=${player_id} AND player_round_stats.round_id=${round_id};";


			$master_connection->do($sql);

		if ($player_id % 100 == 0) {
			$sql = "UPDATE round_stats SET
				avg_damage_taken = current_round_stats.avg_damage_taken,
				avg_damage_done = current_round_stats.avg_damage_done,
				avg_planets_conquered = current_round_stats.avg_planets_conquered,
				avg_planets_lost = current_round_stats.avg_planets_lost,
				avg_ships_built = current_round_stats.avg_ships_built,
				avg_ships_lost = current_round_stats.avg_ships_lost,
				avg_ship_upgrades =current_round_stats.avg_ship_upgrades,
				avg_fuel_mined = current_round_stats.avg_fuel_mined,
				avg_distance_travelled = current_round_stats.avg_distance_travelled
                FROM current_round_stats
                WHERE round_stats.round_id=${round_id};";

				$master_connection->do($sql);
		}
	}
	$rs->finish;

	my $tnow = DateTime->now(time_zone=>'local');
	printf ("Stats updated for round %d, with %d players at %s\n", $round_id, $player_count, $tnow->datetime);
	
	sleep($sleeptime);
}
$master_connection->disconnect();
