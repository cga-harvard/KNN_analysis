### Initial data processing

Create table partisan(id varchar(255), lat double precision, lon double precision, pid varchar(255), state varchar(255), grp varchar(255));
\copy partisan from '$location' delimiter ',' CSV HEADER ;
Create extension postgis;                                                                                                                                     
                                                                                                                                     
                                                                                                                                     
ALTER TABLE partisan ADD COLUMN geom geometry(Point, 4326);
UPDATE partisan SET geom = ST_SetSRID(ST_MakePoint(lon, lat), 4326);                                                                                                                                      
                                                                                                                                     
Create index US_geom_gix on partisan  using gist(geom);
Alter table partisan Add column row_id Serial primary key;
                                                                                                                                     
CREATE INDEX us_geohash ON partisan (ST_GeoHash(ST_Transform(geom,4326)));                                                                                                                                     
                                                                                     
CLUSTER partisan using us_geohash;
                                                      
pg_dump -h localhost -p 7584 -Fc partisandb > /n/scratchlfs02/cga/dkakkar/partisan/partisandb.pgsql                                                      
                                                                                                                                     
### KNN cacluation begin here

Create table RI as (select id,geom,grp from partisan where grp= 'RI');


Alter table RI Add column row_id Serial primary key;

Create index RI_gix onRI using gist(geom);

CREATE INDEX RI ON ri_geohash_idx (ST_GeoHash(ST_Transform(geom,4326)));

CLUSTER RI USING ri_geohash_idx;

Create table knn_1000_RI (source_id character varying(255), neighbor_id character varying(255),dist float);


DO $$
BEGIN
FOR counter IN 1..(Select count(*) from RI)
LOOP
INSERT INTO knn_1000_RI(
SELECT a.id as source_id, b.id as neighbor_id, ST_DistanceSphere((SELECT geom FROM RI WHERE row_id = counter), b.geom) AS dist
FROM RI a, us_voters_grp b
WHERE a.id <> b.id
AND a.row_id = counter
ORDER BY (SELECT geom FROM RI WHERE row_id = counter) <-> b.geom
LIMIT 1000)
;
END LOOP;
END; $$
;

Drop table RI; 
