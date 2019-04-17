Create table OK as (select id,pid,geom,state from us_voters where state= 'OK');

Alter table OK Add column row_id Serial primary key;

Create index OK_gix on OK using gist(geom);

Create index OK_id on OK(id);

Create table knn_1000_OK (source_id character varying(255), neighbor_id character varying(255), neighbor_pid character varying(255),dist float);


DO $$
BEGIN
FOR counter IN 1..(Select count(*) from OK)
LOOP
INSERT INTO knn_1000_OK(
SELECT a.id as source_id, b.id as neighbor_id, b.pid as neighbor_pid,ST_DistanceSphere((SELECT geom FROM OK WHERE row_id = counter), b.geom) AS dist
FROM OK a, us_voters b
WHERE a.id <> b.id
AND a.row_id = counter
ORDER BY (SELECT geom FROM OK WHERE row_id = counter) <-> b.geom
LIMIT 1000)
;
END LOOP;
END; $$
;

Drop table OK; 
