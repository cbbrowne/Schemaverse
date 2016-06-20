#!/usr/bin/perl
#############################
# 	Ref v0.1	    #
# Created by Josh McDougall #
#############################

# This should be run inside a screen/tmux session
# Ref.pl makes sure no player has a query over ~1 minute. 
# Logging could be added here to monitor players trying to cuase problems and disable their accounts


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
if ($sleeptime < 1) {
	print "No value provided for SCHEMAVERSESLEEP - using 30 to sleep 30s between rounds\n";
	$sleeptime = 30;
}

my $masteruser = $pguser;
my $db_uri = "dbi:Pg:dbname=${pgdatabase}";

printf ("Schemaverse: Launching ref.pl\n");
printf ("    URI being used: %s\n", $db_uri);
printf ("    PGPORT: %d  PGHOST: %s  PGDATABASE: %s  PGUSER: %s\n", $pgport, $pghost, $pgdatabase, $pguser);
printf ("    SCHEMAVERSESLEEP: %d \n", $sleeptime);

while (1){ 
	# Make the master database connection
	my $master_connection = DBI->connect($db_uri, $db_username);
	my $sql = "
select 
	pid as pid, 
	pg_notify(get_player_error_channel(usename::character varying), 'The following query was canceled due to timeout: ' ||query ),
	disable_fleet(CASE WHEN application_name ~ '^[0-9]+\$' THEN application_name::integer ELSE 0 END) as disabled,
	usename as username, 
	query as current_query,  
	pg_cancel_backend(pid)  as canceled
from 
	pg_stat_activity 
where 
	datname = '${db_name}' 
	AND usename <> '${db_username}' 
	AND usename <> 'postgres'
        AND 
        (	 
		(
		query LIKE '%FLEET_SCRIPT_%' 
		AND (now() - query_start) > COALESCE(
						GET_FLEET_RUNTIME(CASE WHEN application_name ~ '^[0-9]+\$' THEN application_name::integer ELSE 0 END, usename::character varying), 
						'60 seconds'::interval)
		)
         OR
		(
		query NOT LIKE '<IDLE>%' 
		AND query NOT LIKE '%FLEET_SCRIPT_%' 
		AND now() - query_start > interval '60 seconds'
		)
	);";
	my $rs = $master_connection->prepare($sql);
	$rs->execute();
	my ($pid, $note, $disabled, $usename, $query, $canres);
	while (($pid, $note, $disabled, $usename, $query, $canres)=$rs->fetchrow()) {
		$fleetcount++;
		printf ("PID:%d Note:%s Disabled:%s User:%s Query:%s Cancelled:%d\n", $pid, $note, $disabled, $usename, $query, $canres);
	}

	$rs->finish;
	printf("Cancelled excessively long queries\n");
	$master_connection->disconnect();
	sleep($sleeptime);
}
