# Nationwide Individual Partisan Clustering Analysis
## Introduction

The CGA worked with professor Ryan Enos and graduate student Jacob Brown to develope a large-scale geospatial processing and analytic capability to support an investigation into the effect of geography on partisanship in the United States which takes a new, more detailed look at the well-known phenomenon of partisan geographic sorting.  

A consensus is building among scholars that even if sorting itself is not driven by partisanship, partisans in the United States—and some other countries—are increasingly geographically segregated.  This project takes advantage of a new, individual-level, dataset to explore micro-patterns of segregation across the entire United States: a breadth of coverage and level of detail not previously possible with the study of social segregation using other groups. 

For this project a detailed voter dataset was used to construct individual levels of partisan exposure at several approximated geographies for each voter in US, by calculating aggregate measures of partisan segregation at the individual voter level.   This was accomplished by performing k-means clustering on a voter dataset of 180 million,  with k=1000.  To support the hundreds of billions of calculations required, the CGA built a custom platform consisting of several m4.xlarge Amazon EC2 instances running PostGIS and launched using a special AMI. 

Several optimization techniques were used to make the problem tractable, including geo-hashing and indexing, to enable the normally slow nearest neighbor distance calculations to be scaled up to 100,000 distance calculations per second, resulting in an output dataset of 180 billion records.  Despite the high level of performance and the large data storage requirements, costs were kept low by building the platform from scratch just-in-time, and by using creative compression techniques.


## KNN Calculations 

## Introduction

Finding K nearest neighbors (KNN) is a complex problem because unlike search within a specific radius or distance, K nearest neighbors search is not restricted to a distance. The naive way to carry out a nearest neighbor query is to order the candidate table by distance from the query geometry, and then take the records with the smallest distances. The trouble with this approach is that it forces the database to calculate the distance between the query geometry and every feature in the table of candidate features, then sort them all. For a large table of candidate features, it is not a reasonable approach. One way to improve performance is to add an index constraint to the search, but that would mean finding the magic number for a very large database that defines the smallest box to search for any of the (in this case 180 million) query geometries.

We tackled this problem for the our dataset of 180 million US voters by combining multiple innvotive techinques in PostGIS as described below:  

Databases can only retrieve information as fast as they can get it off disk. Small databases will float up entirely into RAM cache, and so get away from physical disk limitations, but for large databases such as this one, speed of access to the physical disk becomes a limitation. Data is written to disk opportunistically, so there is not necessarily any optimization between the organization of data on disk and the access needs of downstream applications. One way to speed up access is to ensure that records which are likely to be retrieved together in the same query result are located in similar physical locations on the hard disk platters. This technique is called Clustering and is utilized in this project for fast retrieval of nearest neighbor records. 

Determining the right clustering scheme to use can be tricky, but a general rule applies: indexes define a natural ordering scheme for data that is similar to the access pattern that will be used in retrieving the data. Because of this, ordering the data on the disk in the same order as the index can provide a speed advantage. Spatial data tends to be accessed in spatially correlated windows: think of the map window in a web or desktop application. All the data in the windows has similar location value. So, clustering based on a spatial index makes sense for spatial data that is going to be accessed with spatial queries: similar things tend to have similar locations. One of the surprises of the R-Tree is that an R-Tree built incrementally on spatial data might not have high spatial coherence of the leaves. However, there is a useful concept that puts spatial data into a spatially auto-correlated order, and that is called Geohash.  

There is not a balanced R-Tree algorithm available in PostGIS, but there is a useful proxy that puts spatial data into a spatially autocorrelated order, the ST_GeoHash() function.

A Geohash encodes a point into a text form that is sortable and searchable based on prefixing. It divides space into buckets of grid shape. We have used Geohash to cluster the data such that spatially coherent records lie close to each other on the disk. To cluster on the Geohash function, we first created a Geohash index on the data and then applied the CLUSTER function available in PostGIS. An important aspect of this technique is choosing the length of the Geohash string. The precision increases with the length. A shorter Geohash is a less precise representation of a point. It can also be thought of as a box, that contains the actual point. It turns out that 10 characters is ideal, being 5% faster than the full length Geohash of 12 characters. Using 10 chars also doesn’t impact the quality of the resulting order, since 12 characters have only 0.02% more unique hashes on a planet-wide dataset. Shorter lengths have fewer hashes; for example 8 characters have 23% fewer hashes. This made our SQL about 15% faster. 


Once the data was clustered by Geohash, our KNN script could start the nearest neighbor computation. The script works by evaluating distances between bounding boxes inside the PostGIS R-Tree index. It is a pure index based nearest neighbor search. By walking up and down the index, the search can find the nearest candidate geometries without using any magical search radius numbers, so the technique is suitable and high performance even for very large tables with highly variable data densities. The distance operator is used in the ORDER BY clause to make use of the DB indexes. Between putting the operator in the ORDER BY and using a LIMIT to truncate the result set, we can very quickly get the KNN points to our test point. Because it is traversing the index, which is made of bounding boxes, the distance operator only works with bounding boxes. For point data, the bounding boxes are equivalent to the points, so the answers are exact. Using the distance operator, one gets the nearest neighbor using the centers of the bounding boxes to calculate the inter-object distances. It works only on PostGIS 2.0 with PostgreSQL 9.1 or greater.

One key compoonent of the system is storage and compression of the resultant 180 billion dataset to minimize cost. Several optimization techiniques were used and 87% compression in PostGIS dump was obtained using the pg_dump method with "-FC" as the optimization parameter. The compressed dump were stored on Amazon S3 under the knn-1000 bucket:

https://s3.console.aws.amazon.com/s3/home?region=us-east-1

An Amazon AMI was built to facilitate the firing up of multiple EC2 instances to run the computation in parallel for 180 million voters. The AMI enables replication of the entire computation enevironment. Whenthe AMI is launched, the instance is ready to be used with the DB indexed, the scripts loaded, and the libraries pre-installed. 

Here are the steps for using the AMI:

1. Go the AMI tab on the AWS dashboard
2. Click on Launch
3. Select EC2 instance type as "m4.xlarge"
4. Select the pem key as "map_post_parseg.pem"
5. Once the EC2 instance is launched connect to the pre-existing and pre-indexed DB using:                                                                                                                                                    ```                                                                                                                                            psql -h localhost -U brownenos partisan_data
                                                                                                                                                          ```
6. Enter the DB password when prompted to enter the DB
7. The us_voters table pre-exists and is indexed approriately to run the script
8. Run the SQL by changing the state abbreviation by appropriate state for which the calculation is done.
9. Run the export script to export and compress the DB and transfer to S3

## Using OmniSci for weight calculations

## Introduction

Initially the calculation of partisan weights was done in R. The application was scaled using parallel processing with each process calculating chiunks of 2 billion. It took about 10-12 mins to load the data and another 8 minutes to calculate the weights for every chunk.

The idea was to reduce this time using the GPU based processing power of OmniSci in order to facilitate fast tuning of model paramters as wells as quick comaprison between various models. To do this, we initially used the CUDF library to upload the data to GPU dataframes using pymapd and then process them on OmniSci server. However, loading the data to CUDF is a time consuming process and since our analysis could be done directly using database tables so we decided to skip python altogether and calculate the weight directly on Omnisci server by using Mapdql. The data uploads takes about 10-12 minutes for every 2 billion which is same as R but the trade-off here is the computation speed Omnisci provides over R which is about 2.5 seconds comapred to 8 min in R. Moreover, The data upload is a one time process in Omnisci compared to multiple loadings in R and after the upload in OmniSci the user can test various model parameters and compare different model at an incredibly fast rate. 


## Procedure

- Log onto SQL Editor on Immerse: http://52.168.111.218:6273/#/sql-editor?_k=zboapp

- Log on the backend server: ssh -i mapd-azure.pem mapdadmin@52.168.111.218

- Pem file mapd-azure.pem send on email

- After login, Issue the following command on the terminal:

  ** Activate the conda environment for the project ```conda activate foss4gsandiego```

  ** Go to script directory: ``` cd Partisan-Analysis ```

  ** Run the python script to load data from AWS S3 to OmniSci table: ```time python partisan.py {file name of data to be uploaded} ``` e.g. ```time python partisan.py knn_1000_ca1```

  This command will get the **knn_1000_ca1.tar.gz** from S3 and upoload the data in table named **knn_1000_ca1** in Omnisci. 
  Once the  script has completed the table can be  viewed in the Omnisci datamanager at http://52.168.111.218:6273/#/data-manager?_k=uctahy
  This step is done once and then the analysis can be run several times on this loaded data. 
  Note: "time" in the command will give the total time taken to run the script

  ** Run the analysis script: ``` time python analysis.py {name of result table} {value of parameter c} {value of parameter a} {name of input table}``` e.g. `` time python analysis.py knn_results_ca1 2 4 knn_1000_ca1 ```

  This command will take the input table **knn_1000_ca1** and output the weight average for Republic and democrats using **c=2** and **a=4** in output table **knn_results_ca1** in columns **weightedAverage_republican** & **weightedAverage_democrat**. 

References:

- For more on Clustering in PostGIS see https://postgis.net/workshops/postgis-intro/clusterindex.html. 

- For more on KNN in PostGIS see  https://postgis.net/workshops/postgis-intro/knn.html

- For more on Geohash see https://postgis.net/docs/ST_GeoHash.html

- For more on Omnisci - https://www.omnisci.com


## PostGIS commands

## Create table of US voters
- Create table partisan(id varchar(255), state varchar(255), party varchar(255), lat varchar(255), lon varchar(255));
- Copy partisan from '/n/scratchssdlfs/cga/partisan_analysis/project_data/Script_41099709.csv' WITH (FORMAT csv);
- update partisan set lat1 = cast(lat as double precision) ;



















