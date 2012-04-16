begin;

update my_fleets set 
script_declarations = $$
  my_player integer;
  scout_fleet integer;
  miner_fleet integer;
  whenizit timestamptz;
  laststep timestamptz;
  timediff interval;
  numships integer;
  fuel integer;
  i integer;
  p_scout float;
  max_possible_speed integer;
  more_speed_spending integer;
$$, 
script = $$

laststep := clock_timestamp();
whenizit := laststep;
raise notice 'Starting up @ %', laststep;

--- Preparatory work: set up some frequently used variables
select id into my_player from my_player;
select id into scout_fleet from my_fleets where name = 'Scouts';
select id into miner_fleet from my_fleets where name = 'Prospectors';

--- Load ship data into a temporary table as we wind up using this data *heavily*
drop table if exists my_ship_data;
create temp table my_ship_data (
 id                integer,
 fleet_id          integer           ,
 player_id         integer           ,
 name              character varying ,
 last_action_tic   integer           ,
 last_move_tic     integer           ,
 last_living_tic   integer           ,
 current_health    integer           ,
 max_health        integer           ,
 current_fuel      integer           ,
 max_fuel          integer           ,
 max_speed         integer           ,
 range             integer           ,
 attack            integer           ,
 defense           integer           ,
 engineering       integer           ,
 prospecting       integer           ,
 location_x        integer           ,
 location_y        integer           ,
 direction         integer           ,
 speed             integer           ,
 destination_x     integer           ,
 destination_y     integer           ,
 repair_priority   integer           ,
 action            text     ,
 action_target_id  integer           ,
 location          point             ,
 destination       point             ,
 target_speed      integer           ,
 target_direction  integer);

insert into my_ship_data (id , fleet_id , player_id , name ,
 last_action_tic , last_move_tic , last_living_tic , current_health ,
 max_health , current_fuel , max_fuel , max_speed , range , attack ,
 defense , engineering , prospecting , location_x , location_y ,
 direction , speed , destination_x , destination_y , repair_priority ,
 action , action_target_id , location , destination , target_speed ,
 target_direction) 
select id , fleet_id , player_id , name ,
 last_action_tic , last_move_tic , last_living_tic , current_health ,
 max_health , current_fuel , max_fuel , max_speed , range , attack ,
 defense , engineering , prospecting , location_x , location_y ,
 direction , speed , destination_x , destination_y , repair_priority ,
 action , action_target_id , location , destination , target_speed ,
 target_direction from my_ships;

create index msd_id on my_ship_data(id);
create index msd_speed on my_ship_data(speed);
create index msd_fleet on my_ship_data(fleet_id);
create index msd_loc on my_ship_data using gist(location);
create index msd_dest on my_ship_data using gist(destination);

timediff := clock_timestamp() - laststep;
laststep := clock_timestamp();
raise notice 'Prep of my_ship_data took [%] (@%)', timediff, laststep;

drop table if exists t_planets;
create temp table t_planets  (id integer, name text, mine_limit integer, location_x integer, location_y integer, conqueror_id integer, location point);
insert into t_planets (id, name, mine_limit, location_x, location_y, conqueror_id, location)
select id, name, mine_limit, location_x, location_y, conqueror_id, location from planets;
create index t_p_id on t_planets(id);
create index t_p_conqueror_id on t_planets(conqueror_id);
create index t_p_point on t_planets using gist (location);

timediff := clock_timestamp() - laststep;
laststep := clock_timestamp();
raise notice 'Prep of t_planets took [%] (@%)', timediff, laststep;

-- Seize planets
drop table if exists planets_to_conquer;
create temp table planets_to_conquer (ship_id integer, planet_id integer);

insert into planets_to_conquer (ship_id, planet_id)
select s.id as ship, p.id as planet 
from t_planets p, my_ship_data s
where p.conqueror_id <> my_player and
      (s.location <-> p.location) < s.range and
      s.current_health > 0 and s.prospecting > 0;

timediff := clock_timestamp() - laststep;
laststep := clock_timestamp();
raise notice 'Prep of planets_to_conquer took [%] (@%)', timediff, laststep;

perform mine(ship_id, planet_id) from planets_to_conquer;

update planets set name = 'FunbusterLand' where id in (select planet_id from planets_to_conquer) and conqueror_id <> my_player;

timediff := clock_timestamp() - laststep;
laststep := clock_timestamp();
raise notice 'planet seizures took [%] (@%)', timediff, laststep;

-- Move scouts towards their desired locations
drop table if exists scout_locations;
create temp table scout_locations (ship_id integer, current_fuel integer, location point, speed integer, destination point);
insert into scout_locations (ship_id, current_fuel, location, speed, destination)
select id, current_fuel, location, speed, point(destination_x,
destination_y) as destination from my_ship_data s where
fleet_id = scout_fleet and
current_health > 0;

drop table if exists scout_movement;
create temp table scout_movement (ship_id integer, target_speed integer, direction integer, x integer, y integer, distance integer);
insert into scout_movement (ship_id, target_speed, x, y, distance)
  select ship_id, s.max_speed, l.destination[0]::integer, l.destination[1]::integer, s.location<->s.destination from scout_locations l, my_ship_data s where s.id = l.ship_id;

--- whoah, nelly!!!
update scout_movement 
set target_speed = 100 
where 
      ((target_speed*target_speed)/200.0+1.5*target_speed+100) > distance;

perform move(ship_id, target_speed, NULL::integer, x, y) from scout_movement;

timediff := clock_timestamp() - laststep;
laststep := clock_timestamp();
raise notice 'Scout motion took [%] (@%)', timediff, laststep;

---  Need to add some code that causes scouts to land on the planet that they claimed, and become a prospector
--- In effect, if:
---     destination is This Planet
---     location is This Planet
---     I own... This Planet
--- Then
---     Shift from scout fleet to mining fleet
---     STOP the ship
---     Ideally, add a few points worth of prospecting

-- Prospectors should mine
drop table if exists prospectors_in_range;
create temp table prospectors_in_range (ship_id integer, planet_id integer);
insert into prospectors_in_range (ship_id, planet_id)
 select s.id, p.planet from my_ship_data s, planets_in_range p, t_planets pl 
  where p.ship = s.id and 
       pl.id = p.planet and pl.mine_limit > 0 and s.prospecting > 0;

perform mine(ship_id, planet_id) from prospectors_in_range;

timediff := clock_timestamp() - laststep;
laststep := clock_timestamp();
raise notice 'mining took [%] (@%)', timediff, laststep;

-- Refuel scouts
perform id, current_fuel, refuel_ship(id) from 
(select id, current_fuel, location <->destination as distance from my_ship_data where current_fuel < max_fuel and target_speed <> speed and fleet_id = scout_fleet order by location<->destination) 
  as ships_in_order_of_criticality;

timediff := clock_timestamp() - laststep;
laststep := clock_timestamp();
raise notice 'scout refueling took [%] (@%)', timediff, laststep;

-- Speed up scouts
drop table if exists speediness;
create temp table speediness (ship_id integer, current_speed integer, want_speed integer);
select numeric_value into max_possible_speed from public_variable where name = 'MAX_SHIP_SPEED';

select fuel_reserve into fuel from my_player;
if fuel_reserve < 5000 then
   more_speed_spending := 0;
elsif fuel_reserve < 10000 then
   more_speed_spending := 1000;
elsif fuel_reserve < 25000 then
   more_speed_spending := 2000;
elsif fuel_reserve < 50000 then
   more_speed_spending := 4000;
elsif fuel_reserve < 100000 then
   more_speed_spending := 6000;
elsif fuel_reserve < 250000 then
   more_speed_spending := 10000;
elsif fuel_reserve < 1000000 then
   more_speed_spending := 50000;
else
   more_speed_spending := 100000;
end if;

if more_speed_spending > 0 then
--- Find all the ships that are nearing their maximum speed
  insert into speediness (ship_id, current_speed)
    select id, max_speed from my_ship_data where fleet_id = scout_fleet and max_speed < max_possible_speed and current_health > 0 and (max_speed - speed) < 2 * current_fuel;

  perform convert_resource('FUEL', more_speed_spending);
  perform upgrade(ship_id, 'MAX_SPEED', 100) from
    (select ship_id from speediness order by random() limit (more_speed_spending / 125);

  perform upgrade(ship_id, 'MAX_SHIP_FUEL', 100) from
    (select ship_id from speediness order by random() limit (more_speed_spending / 500);

end if;

timediff := clock_timestamp() - laststep;
laststep := clock_timestamp();
raise notice 'scout respeeding took [%] (@%)', timediff, laststep;

drop table if exists want_ships;
create temp table want_ships (fleet_id integer, name text, attack integer, defense integer, engineering integer, prospecting integer, location_x integer, location_y integer);

-- Expand the fleet
select fuel_reserve into fuel from my_player;
if fuel > 100000 then
   numships := 10;
elsif fuel > 50000 then
   numships := 5;
elsif fuel > 25000 then
   numships := 3;
elsif fuel > 5000 then
   numships := 1;
else
   numships := 0;
end if;

numships := 0;

if numships > 0 then
   drop table if exists t_planetary_defenses;
   create temp table t_planetary_defenses (planet_id integer, location point, health integer);
   insert into t_planetary_defenses (planet_id, health)
      select p.id, sum(current_health)
       from t_planets p, my_ship_data s
       where p.conqueror_id = my_player and
             (s.location <-> p.location) < s.range and
             s.speed < 100 and s.prospecting > 10 and current_health > 0
       group by p.id;
   insert into t_planetary_defenses (planet_id, health)
   select id, 0 from t_planets where conqueror_id = my_player and id not in (select planet_id from t_planetary_defenses);
   update t_planetary_defenses set location = (select location from t_planets where id = planet_id);
   create index t_planet_count on t_planetary_defenses (health);

   -- Notional probability of building a scout is 15%, to ensure they are well fueled
   p_scout := 0.15;
   
   -- But we might drop the probability if we have too many scouts
   if (select count(*) from my_ships where speed = 0) < (7 * (select count(*) from my_ships where speed > 0)) then
      p_scout := 0.05;
   end if;
   
   for i in 1..numships loop
        if random() < p_scout then
	  -- Build a scout, at low probability
	  insert into want_ships (fleet_id, name, attack, defense, engineering, prospecting,location_x,location_y)
	        select scout_fleet, 'Scout', 5,4,4,7, p.location_x, p.location_y from t_planets p where conqueror_id = my_player
		     and id = (select planet_id from t_planetary_defenses order by health desc limit 1);
	else
          -- Build a prospector, on my least built up planet
   	  insert into want_ships (fleet_id, name, attack, defense, engineering, prospecting,location_x,location_y)
	    select miner_fleet, 'Miner', 0,2,2,16, p.location_x, p.location_y 
	    from t_planets p where id = (select planet_id from t_planetary_defenses order by health desc limit 1);
	end if;
   end loop;
   perform convert_resource('FUEL', (select count(*) from want_ships)::integer * 1000);

   insert into my_ships (fleet_id, name, attack, defense, engineering, prospecting, location_x, location_y) 
      select fleet_id, name, attack, defense, engineering, prospecting, location_x, location_y
        from want_ships;
end if;

timediff := clock_timestamp() - laststep;
laststep := clock_timestamp();
raise notice 'fleet expansion took [%] (@%)', timediff, laststep;

drop table if exists directed_scouts;
create temp table directed_scouts (ship_id integer, planet_id integer);
insert into directed_scouts (ship_id, planet_id)
  select s.id as ship_id, p.id as planet_id 
    from my_ship_data s, t_planets p
    where s.fleet_id = scout_fleet and (p.location <->s.destination) < 1;

drop table if exists undirected_scouts;
create temp table undirected_scouts (ship_id integer);

insert into undirected_scouts (ship_id)
select s.id from my_ship_data s
where 
 s.fleet_id = scout_fleet and
 (s.destination is null or exists (select 1 from t_planets p where (p.location <-> s.destination) < 100 and conqueror_id = my_player));

drop table if exists possible_destinations;
create temp table possible_destinations (ship_id integer, ship_location point, planet_id integer, planet_location point, distance double precision);

insert into possible_destinations (ship_id, ship_location, planet_id, planet_location, distance)
select s.id as ship_id, s.location as ship_location, p.id as
planet_id, point(p.location_x, p.location_y) as planet_location,
s.location <->point(p.location_x, p.location_y) as distance 
from my_ship_data s, t_planets p, undirected_scouts u
where  s.current_health > 0 and s.id = u.ship_id
and s.current_fuel > 0 and (p.conqueror_id <> my_player or p.conqueror_id is null) and s.destination is null and
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

perform move(s.ship_id, 50, NULL::integer, p.location_x, p.location_y) from scouting_missions s, t_planets p where p.id = s.planet_id ;

timediff := clock_timestamp() - laststep;
laststep := clock_timestamp();
raise notice 'scout direction [%] (@%)', timediff, laststep;

-- Attack where possible
perform attack(r.id, r.ship_in_range_of) from my_ship_data s, ships_in_range r where s.id = r.id and s.current_health > 0 and r.health > 0 and s.attack > 0 and r.player_id <> my_player;

timediff := clock_timestamp() - laststep;
laststep := clock_timestamp();
raise notice 'Attacking stuff [%] (@%)', timediff, laststep;

drop table if exists attack_missions;

timediff := clock_timestamp() - whenizit;
raise notice 'Total function time: [%] (@%)', timediff, laststep;

$$ where name = 'Scouts';

select fleet_script_231();
update my_fleets set enabled = 't' where name = 'Scouts';

select upgrade(id, 'FLEET_RUNTIME', 1) from
(select id from my_fleets where name = 'Scouts' and enabled = 't' and
runtime ='00:00:00'::interval) as fleet_to_activate;

commit;


