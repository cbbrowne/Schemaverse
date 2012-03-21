update my_fleets set script = '

-- Seize planets
perform mine(ship, planet) from planets_in_range pr, planets p
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

drop table if exists scout_movement;
create temp table scout_movement (ship_id integer, max_speed integer, direction integer, x integer, y integer, distance integer);
insert into scout_movement (ship_id, max_speed, x, y, distance)
  select ship_id, s.max_speed, l.destination[0]::integer, l.destination[1]::integer, s.location<->s.destination from scout_locations l, my_ships s where s.id = l.ship_id;

update scout_movement set max_speed = distance / 20 where distance between 5000 and 15000;
update scout_movement set max_speed = 150 where distance between 1000 and 5000;
update scout_movement set max_speed = 80 where distance between 200 and 1000;
update scout_movement set max_speed = 10 where distance between 2 and 200;
update scout_movement set max_speed = 0 where distance < 2;

perform move(ship_id, max_speed, NULL::integer, x, y) from scout_movement;

-- Prospectors should mine
drop table if exists prospectors_in_range;
create temp table prospectors_in_range (ship_id integer, planet_id integer);
insert into prospectors_in_range (ship_id, planet_id)
 select s.id, p.planet from my_ships s, planets_in_range p, planets pl 
  where p.ship = s.id and 
       pl.id = p.planet and pl.mine_limit > 0 and s.prospecting > 0;

select mine(ship_id, planet_id) from prospectors_in_range;

-- Refuel scouts
perform id, current_fuel, refuel_ship(id) from my_ships where current_fuel < max_fuel and fleet_id = 231;

-- Speed up scouts
drop table if exists speediness;
create temp table speediness (ship_id integer, want_speed integer);
insert into speediness (ship_id, want_speed)
  select id, (2000-max_speed)/20+5 from my_ships where fleet_id = 231 and max_speed < 1995 and current_health > 0
  order by random() limit 5;

select convert_resource(''FUEL'', (select sum(want_speed) from speediness));

perform upgrade(ship_id, ''MAX_SPEED'', ship_id) from speediness;

drop table if exists want_ships;
create temp table want_ships (fleet_id integer, name text, attack integer, defense integer, engineering integer, prospecting integer, location_x integer, location_y integer);

-- Expand the fleet
if (select fuel_reserve from my_player) > 5000 then

   -- Build a scout and a prospector
   insert into want_ships (fleet_id, name, attack, defense, engineering, prospecting,location_x,location_y)
      select 231, ''Scout'', 5,4,4,7, p.location_x, p.location_y, from planets p where conqueror_id = 231 
      order by random() limit 1;

   insert into want_ships (fleet_id, name, attack, defense, engineering, prospecting,location_x,location_y)
      select 234, ''Miner'', 0,2,2,16, p.location_x, p.location_y, from planets p where conqueror_id = 231 
      order by random() limit 1;

elsif (select fuel_reserve from my_player > 1500) then
   if random() > 0.8 then
     insert into want_ships (fleet_id, name, attack, defense, engineering, prospecting,location_x,location_y)
       select 231, ''Scout'', 5,4,4,7, p.location_x, p.location_y, from planets p where conqueror_id = 231 
       order by random() limit 1;
   else
     insert into want_ships (fleet_id, name, attack, defense, engineering, prospecting,location_x,location_y)
       select 234, ''Miner'', 4,2,1,13, p.location_x, p.location_y, from planets p where conqueror_id = 231 
       order by random() limit 1;
   end if;

   insert into my_ships (fleet_id, name, attack, defense, engineering, prospecting, location_x, location_y) 
      select fleet_id, name, attack, defense, engineering, prospecting, location_x, location_y
        from want_ships;
end if;

select convert_resource(''FUEL'', (select count(*) from want_ships) * 1000);

insert into my_ships (fleet_id, name, attack, defense, engineering, prospecting, location_x, location_y) 
      select fleet_id, name, attack, defense, engineering, prospecting, location_x, location_y
        from want_ships;

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

-- Attack where possible
perform attack(r.id, r.ship_in_range_of) from my_ships s, ships_in_range r where s.id = r.id and s.current_health > 0 and r.health > 0 and s.attack > 0 and r.player_id <> 2663;

drop table if exists attack_targets;
create temp table attack_targets (cause text, location point, as_at timestamptz);
insert into attack_targets (cause, location, as_at)
   select ''RECENT CONQUER'', location, toc from my_events
   where action = ''CONQUER'' and toc > (now() - ''8 hours''::interval);
insert into attack_targets (cause, location, as_at)
   select ''RECENT ATTACK'', location, toc from my_events
   where action = ''ATTACK'' and toc > (now() - ''8 hours''::interval);
insert into attack_targets (cause, location, as_at)
   select ''IN RANGE'', enemy_location, now()
   from ships_in_range;

drop table if exists attack_missions;



' where name = 'Scouts';


-- update my_fleets set enabled = 't' where name = 'Scouts';


