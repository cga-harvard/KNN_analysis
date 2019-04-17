Create table NY5 as (select id,pid,geom,grp from us_voters_grp where grp= 'NY5');

Alter table NY5 Add column row_id Serial primary key;

Create index NY5_gix on NY5 using gist(geom);

Create index NY5_id on NY5(id);

Create table knn_1000_NY5 (source_id character varying(255), neighbor_id character varying(255), neighbor_pid character varying(255),dist float);


DO $$
BEGIN
FOR counter IN 1..(Select count(*) from NY5)
LOOP
INSERT INTO knn_1000_NY5(
SELECT a.id as source_id, b.id as neighbor_id, b.pid as neighbor_pid,ST_DistanceSphere((SELECT geom FROM NY5 WHERE row_id = counter), b.geom) AS dist
FROM NY5 a, us_voters_grp b
WHERE a.id <> b.id
AND a.row_id = counter
ORDER BY (SELECT geom FROM NY5 WHERE row_id = counter) <-> b.geom
LIMIT 1000)
;
END LOOP;
END; $$
;

Drop table NY5; 
