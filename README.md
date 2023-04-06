# Apache Kafka and Apache Flink

## Prerequisites

Flink SQL is a module in the Apache Flink stream processing framework that allows users to write 
SQL queries on streaming data. It provides a unified programming model for both batch and stream 
processing, which enables developers to use SQL queries to process data in real-time.

Flink SQL supports a wide range of data sources, including Kafka, HDFS, Amazon S3, and others.
In this example, we will demonstrate how to integrate Apache Flink with Kafka to enable real-time stream processing.

In this tutorial, we'll demonstrate how to develop a program that processes events related to book titles 
and purchase orders from Kafka topics, calculates the total number of purchases, and enriches the result.

```shell
mvn spring-boot:run -Dmaven.test.skip=true -Dstart-class=io.confluent.admin.BasicAdminApplication \
-Dspring-boot.run.profiles=local-plaintext

mvn spring-boot:run -Dmaven.test.skip=true -Dstart-class=io.confluent.producer.BasicProducerApplication \
-Dspring-boot.run.profiles=local-plaintext

mvn spring-boot:run -Dmaven.test.skip=true -Dstart-class=io.confluent.producer.BasicConsumerApplication \
-Dspring-boot.run.profiles=local-plaintext
```

```shell
kafka-topics --bootstrap-server localhost:9092 --list

kafka-topics --bootstrap-server localhost:9092 --describe --topic plaintext-books
kafka-topics --bootstrap-server localhost:9092 --describe --topic plaintext-orders

kafka-avro-console-consumer --bootstrap-server localhost:9092 --topic plaintext-books --from-beginning
kafka-avro-console-consumer --bootstrap-server localhost:9092 --topic plaintext-orders --from-beginning
```

## The Flink SQL Client

Run docker compose (`./docker-kafka-flink/start.sh`), wait for a few seconds and your clusters should be up and running.

Let’s start the Flink SQL CLI by running `docker exec -it flink-jobmanager ./bin/sql-client.sh` and execute the following commands:

```roomsql
SHOW DATABASES;

CREATE DATABASE bookstore;

USE bookstore;

SHOW TABLES;
```

### Create Books Table

```roomsql
DROP TABLE books;

CREATE TABLE books (

  -- one column mapped to the Kafka raw UTF-8 key
  book_id STRING,
  
  -- a few columns mapped to the Avro fields of the Kafka value
  book_title STRING,
  event_offset INT METADATA FROM 'offset',
  event_partition STRING METADATA FROM 'partition',
  
  -- proc_time AS PROCTIME(),
  ts TIMESTAMP_LTZ(3) METADATA FROM 'timestamp',
  WATERMARK FOR ts AS ts - INTERVAL '30' SECONDS,
  
  PRIMARY KEY (book_id) NOT ENFORCED

) WITH (

  'connector' = 'upsert-kafka',
  'topic' = 'plaintext-books',
  'properties.bootstrap.servers' = 'kafka-broker:9292',
  'properties.group.id' = 'group.books',

  -- UTF-8 string as Kafka keys, using the 'book_id' table column
  'key.format' = 'raw',

  'value.format' = 'avro-confluent',
  'value.avro-confluent.url' = 'http://schema-registry:8081',
  'value.fields-include' = 'EXCEPT_KEY'
);

SELECT * FROM books;
```

### Create Orders Table

```roomsql
DROP TABLE orders;

CREATE TABLE orders (

  -- one column mapped to the Kafka raw UTF-8 key
  order_id STRING,
  
  -- a few columns mapped to the Avro fields of the Kafka value
  book_id STRING,
  quantity INT,
  card_number STRING,
  event_offset INT METADATA FROM 'offset',
  event_partition STRING METADATA FROM 'partition',
  
  -- proc_time AS PROCTIME(),
  ts TIMESTAMP_LTZ(3) METADATA FROM 'timestamp',
  WATERMARK FOR ts AS ts - INTERVAL '30' SECONDS

) WITH (

  'connector' = 'kafka',
  'topic' = 'plaintext-orders',
  'properties.bootstrap.servers' = 'kafka-broker:9292',
  'properties.group.id' = 'group.orders',
  'scan.startup.mode' = 'earliest-offset',
  
  -- UTF-8 string as Kafka keys, using the 'order_id' table column
  'key.format' = 'raw',
  'key.fields' = 'order_id',

  'value.format' = 'avro-confluent',
  'value.avro-confluent.url' = 'http://schema-registry:8081',
  'value.fields-include' = 'EXCEPT_KEY'
);

SELECT * FROM orders;
```

### Processing

```roomsql
SELECT *
FROM orders
WHERE quantity = 10;
```

```roomsql
SELECT
    book_id AS id,
    SUM(quantity) AS total
FROM orders
GROUP BY book_id;
```

```roomsql
SELECT b.book_title AS book_title, COUNT(o.order_id) as orders_count, SUM(o.quantity) AS orders_total
FROM orders AS o
JOIN books AS b
ON o.book_id = b.book_id
GROUP BY b.book_title;
```