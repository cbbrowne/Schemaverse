update my_fleets set script = '
-- Seize planets
select mine(ship, planet) from planets_in_range pr, planets p
where pr.planet = p.id and p.conqueror_id <> 2663;

update planets set name = ''FunbusterLand'' where id in (select planet from planets_in_range) and conqueror_id <> (select id from my_player);

-- Move scouts towards their desired locations
drop table if exists scout_locations;
create temp table scout_locations (ship_id integer, current_fuel integer, location point, speed integer, destination point);
insert into scout_locations (ship_id, current_fuel, location, speed, destination)
select id, current_fuel, location, speed, point(destination_x,
destination_y) as destination from my_ships s where
fleet_id = 231 and
current_health > 0;

perform move(ship_id, s.max_speed, NULL::integer, l.destination[0]::integer, l.destination[1]::integer) from scout_locations l, my_ships s where s.id = l.ship_id and (s.location <-> s.destination) > 15000 ;

perform move(ship_id, (s.location<->s.destination)/20, NULL::integer, l.destination[0]::integer, l.destination[1]::integer) from scout_locations l, my_ships s where s.id = l.ship_id and (s.location <-> s.destination) between 5000 and 15000 ;

perform move(ship_id, 150, NULL::integer, l.destination[0]::integer, l.destination[1]::integer) from scout_locations l, my_ships s where s.id = l.ship_id and (s.location <-> s.destination) between 1000 and 5000 ;

perform move(ship_id, 80, NULL::integer, l.destination[0]::integer, l.destination[1]::integer) from scout_locations l, my_ships s where s.id = l.ship_id and (s.location <-> s.destination) between 200 and 1000 ;

perform move(ship_id, 50, NULL::integer, l.destination[0]::integer, l.destination[1]::integer) from scout_locations l, my_ships s where s.id = l.ship_id and (s.location <-> s.destination) < 200 ;

perform move(ship_id, 0, NULL::integer, l.destination[0]::integer, l.destination[1]::integer) from scout_locations l, my_ships s where s.id = l.ship_id and (s.location <-> s.destination) < 2 ;

-- Prospectors should mine
perform s.id as ship_id, s.name, mine(s.id, p.planet) from my_ships s,
my_fleets f, planets_in_range p, planets pl where s.fleet_id = f.id
and f.id = 234 and p.ship = s.id and p.distance = 0 and
pl.id = p.planet and pl.mine_limit > 0;

-- Refuel
perform id, current_fuel, refuel_ship(id) from my_ships where current_fuel < max_fuel;

-- Get a bit of money
perform convert_resource(''FUEL'', 150);
perform convert_resource(''FUEL'', (select count(*) from planets where conqueror_id = (select id from my_player))::integer * 1000 * 3 + 150);

-- Enhance speediness of my scouts
perform upgrade(id, ''MAX_SPEED'', (2000-max_speed)/20 + 5) from 
   (select id, max_speed from my_ships where fleet_id = 231 and max_speed < 1995 and current_health > 0 order by random() limit 10) as unspeedy;

-- Expand the fleet

-- Create a scout on each planet I own
insert into my_ships (fleet_id, name, attack, defense, engineering, prospecting, location_x, location_y) select f.id, ''Scout'', 15,4,0,1, p.location_x, p.location_y from my_fleets f, planets p, my_player pl where f.name = ''Scouts'' and p.conqueror_id = pl.id;

-- Create a prospector on each planet I own
insert into my_ships (fleet_id, name, attack, defense, engineering, prospecting, location_x, location_y) select f.id, ''Prospector'', 0,5,0,15, p.location_x, p.location_y from my_fleets f, planets p, my_player pl where f.name = ''Prospectors'' and p.conqueror_id = pl.id;

drop table if exists directed_scouts;
create temp table directed_scouts (ship_id integer, planet_id integer);
insert into directed_scouts (ship_id, planet_id)
select s.id as ship_id, p.id as planet_id from my_ships s, planets p, my_fleets f where s.fleet_id = f.id and f.name = ''Scouts'' and (p.location <->s.destination) < 1;

drop table if exists undirected_scouts;
create temp table undirected_scouts (ship_id integer);

insert into undirected_scouts (ship_id)
select s.id from my_ships s, my_fleets f 
where 
 f.id = s.fleet_id and f.name = ''Scouts'' and
 (destination is null or exists (select 1 from planets p where (p.location <-> s.destination) < 10 and conqueror_id = (select id from my_player)));

drop table if exists possible_destinations;
create temp table possible_destinations (ship_id integer, ship_location point, planet_id integer, planet_location point, distance double precision);

insert into possible_destinations (ship_id, ship_location, planet_id, planet_location, distance)
select s.id as ship_id, s.location as ship_location, p.id as
planet_id, point(p.location_x, p.location_y) as planet_location,
s.location <->point(p.location_x, p.location_y) as distance 
from my_ships s, planets p, undirected_scouts u
where  s.current_health > 0 and s.id = u.ship_id
and s.current_fuel > 0 and (p.conqueror_id <> 2663 or p.conqueror_id is null) and s.destination is null and
p.id not in (select planet_id from directed_scouts);

update possible_destinations set distance = distance + 2000000 * random();   -- Breaks things up a bit...
drop table if exists fave_scout_dests;
create temp table fave_scout_dests (ship_id integer, distance double precision);
insert into fave_scout_dests (ship_id, distance)
select ship_id, min(distance) from possible_destinations group by 1;

drop table if exists scouting_missions;
create temp table scouting_missions (ship_id integer, planet_id integer);

insert into scouting_missions (ship_id, planet_id)
select p.ship_id, planet_id from possible_destinations p, fave_scout_dests f where p.ship_id = f.ship_id and p.distance = f.distance;

perform move(s.ship_id, 50, NULL::integer, p.location_x, p.location_y) from scouting_missions s, planets p where p.id = s.planet_id ;

perform attack(r.id, r.ship_in_range_of) from my_ships s, ships_in_range r where s.id = r.id and s.current_health > 0 and r.health > 0 and s.attack > 0 and r.player_id <> 2663;

' where name = 'Scouts';


-- update my_fleets set enabled = 't' where name = 'Scouts';


