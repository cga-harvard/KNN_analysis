# Nationwide Individual Partisan Clustering Analysis
## Introduction

The CGA worked with professor Ryan Enos and graduate student Jake Brown to develope a large-scale geospatial processing and analytic capability to support an investigation into the effect of geography on partisanship in the United States by, which takes a new more detailed look at the well-known phenomenon of partisan geographic sorting.  

A consensus is building among scholars that even if sorting itself is not driven by partisanship, partisans in the United States—and some other countries—are increasingly geographically segregated.  This project takes advantage of a new, individual-level, dataset to explore micro-patterns of segregation across the entire United States: a breadth of coverage and level of detail not previously possible with the study of social segregation using other groups. 

For this project a detailed voter dataset was used to construct individual levels of partisan exposure at several approximated geographies for each voter in US, by calculating aggregate measures of partisan segregation at the individual voter level.   This was accomplished by performing k-means clustering on a voter dataset of 180 million,  with k=1000.  To support the hundreds of billions of calculations required, the CGA built a custom platform consisting of several m4.xlarge Amazon EC2 instances running PostGIS and launched using a special AMI. 

Several optimization techniques were used to make the problem tractable, including geo-hashing and indexing, to enable the normally slow nearest neighbor distance calculations to be scaled up to 100,000 distance calculations per second on a dataset , resulting in a k-means dataset of 180 billion records.  Despite the high level of performance and the large data storage requirements, costs were kept low by building the platform from scratch just-in-time, and by using creative compression techniques.


## KNN Calculations 

A commonly encountered problem in spatial world is finding the KNN of the point of interest. Unlike a distance search, the “nearest neighbour” search doesn’t include any measurement restricting how far away candidate geometries might be. This poses a problem for traditional index-assisted queries, that require a search box, and therefore need some kind of measurement value to build the box. The naive way to carry out a nearest neighbour query is to order the candidate table by distance from the query geometry, and then take the record with the smallest distance. The trouble with this approach is that it forces the database to calculate the distance between the query geometry and every feature in the table of candidate features, then sort them all. For a large table of candidate features, it is not a reasonable approach. One way to improve performance is to add an index constraint to the search. The trouble is finding the magic number for a very large database that defines the smallest box to search around the query geometry.

Our system works by evaluating distances between bounding boxes inside the PostGIS R-Tree index. It is a pure index based nearest neighbour search. By walking up and down the index, the search can find the nearest candidate geometries without using any magical search radius numbers, so the technique is suitable and high performance even for very large tables with highly variable data densities. The distance operator is used in the ORDER BY clause to make use of the DB indexes. Between putting the operator in the ORDER BY and using a LIMIT to truncate the result set, we can very very quickly get the KNN points to our test point. Because it is traversing the index, which is made of bounding boxes, the distance operator only works with bounding boxes. For point data, the bounding boxes are equivalent to the points, so the answers are exact. Using the distance operator, ones get the nearest neighbour using the centers of the bounding boxes to calculate the inter-object distances. The script works only on PostGIS 2.0 with PostgreSQL 9.1 or greater. The calculation was done in chunks of 2 million voters to enable stage II calculation of weighted aggregates in R. For states with population greater than 2 million voters, the dataset is divided into smaller chunks of 2 million using group id. 

One key compoonent was storage and compression of the resultant 180 billion dataset to minimize cost. Several optimization techiniques were used and 87% compression in PostGIS dump was obtained using the pg_dump method with "-FC" as the optimization parameter. The compressed dump were stored on Amazon S3 under the knn-1000 bucket:

https://s3.console.aws.amazon.com/s3/home?region=us-east-1

An Amazon AMI was built to facilitate firing of multiple EC2 instances to run the computation in parallel for 180 million voters. The AMI enables replication of the entire computation enevironment. Whenthe AMI is launced, the instance is ready to be used with the DB indexed, scripts loaded and libraries pre-installed. The following steps should be followed in using the AMI:

1. Go the AMI tab on the AWS dashboard
2. Click on Lauch
3. Select EC2 instance type as "m4.xlarge"
4. Select the pem key as "map_post_parseg.pem"
5. Once the EC2 instance is launched connect to the pre-existing and pre-indexed DB using:                                                                                                                                                    ```                                                                                                                                            psql -h localhost -U brownenos partisan_data
                                                                                                                                                          ```
6. Enter the DB password when prompted to enter the DB
7. The us_voters table is pre-exists and is indexed approriately to run the script
8. Run the SQL by changing the state abbreviation by appropriate state for which the calculation is done.
9. Run the export script to export and compress the DB and transfer to S3


## Using OmniSci for weight calculations

- Log onto SQL Editor on Immerse: http://52.168.111.218:6273/#/sql-editor?_k=zboapp

- Log on the backend server: ssh -i mapd-azure.pem mapdadmin@52.168.111.218

- Pem file mapd-azure.pem send on email

- After login, Issue the following command on the terminal:

** Activate the conda environment for the project ```conda activate foss4gsandiego```

** Go to script directory: ``` cd Partisan-Analysis ```

** Run the python script to load data from AWS S3 to OmniSci table: ```time python partisan.py {file name of data to be uploaded} ``` e.g. ```time python partisan.py knn_1000_ca1```

This command will get the knn_1000_ca1.tar.gz from S3 and upoload the data in table named "knn_1000_ca1" in Omnisci. 
Once the  script has completed the table can be  viewed in the Omnisci datamanager at http://52.168.111.218:6273/#/data-manager?_k=uctahy

This step is done once and then the analysis can be run several times on this loaded data.

Note: "time" in the command will give the total time taken to run the script

** Run the analysis script: ``` time python analysis.py {name of result table} {value of parameter c} {value of parameter a} {name of input table}``` e.g. `` time python analysis.py knn_results_ca1 2 4 knn_1000_ca1 ```

This command will take the input table knn_1000_ca1 and output the weight average for Republic and democrats using c=2 and a=4 in output table knn_results_ca1 in columns weightedAverage_republican and weightedAverage_democrat. 























