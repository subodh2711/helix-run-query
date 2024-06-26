CREATE OR REPLACE FUNCTION helix_rum.CLUSTER_FILTERCLASS(user_agent STRING, device STRING) 
  RETURNS BOOLEAN
  AS (
    device = "all" OR 
    (device = "desktop" AND user_agent LIKE "desktop%") OR 
    (device = "nobot" AND user_agent NOT LIKE "bot%") OR
    (device = "mobile" AND user_agent LIKE "mobile%") OR
    (device = "bot" AND user_agent LIKE "bot%"));

CREATE OR REPLACE FUNCTION helix_rum.CLEAN_TIMEZONE(intimezone STRING)
  RETURNS STRING
  AS (
    CASE
      WHEN intimezone = "undefined" THEN "GMT"
      WHEN intimezone = "" THEN "GMT"
      ELSE intimezone 
    END
  );

CREATE OR REPLACE TABLE FUNCTION helix_rum.CLUSTER_EVENTS(filterurl STRING, days_offset INT64, days_count INT64, day_min STRING, day_max STRING, timezone STRING, deviceclass STRING, filtergeneration STRING)
AS
  SELECT 
    *
  FROM `helix-225321.helix_rum.cluster` 
  WHERE IF(filterurl = '-', TRUE, (url LIKE CONCAT('https://', filterurl, '%')) OR (filterurl LIKE 'localhost%' AND url LIKE CONCAT('http://', filterurl, '%')))
  AND   IF(filterurl = '-', TRUE, (hostname = SPLIT(filterurl, '/')[OFFSET(0)]) OR (filterurl LIKE 'localhost:%' AND hostname = 'localhost'))
  AND   IF(days_offset >= 0, DATETIME_SUB(TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), DAY, helix_rum.CLEAN_TIMEZONE(timezone)), INTERVAL days_offset DAY),                TIMESTAMP(day_max, helix_rum.CLEAN_TIMEZONE(timezone))) >= time
  AND   IF(days_count >= 0,  DATETIME_SUB(TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), DAY, helix_rum.CLEAN_TIMEZONE(timezone)), INTERVAL (days_offset + days_count) DAY), TIMESTAMP(day_min, helix_rum.CLEAN_TIMEZONE(timezone))) <= time
  AND   helix_rum.CLUSTER_FILTERCLASS(user_agent, deviceclass)
  AND   IF(filtergeneration = '-', TRUE, generation = filtergeneration)
;

CREATE OR REPLACE TABLE FUNCTION helix_rum.CLUSTER_PAGEVIEWS(filterurl STRING, days_offset INT64, days_count INT64, day_min STRING, day_max STRING, timezone STRING, deviceclass STRING, filtergeneration STRING)
AS
  SELECT
    ANY_VALUE(hostname) AS hostname,
    ANY_VALUE(host) AS host,
    MAX(time) AS time,
    MAX(weight) AS pageviews,
    MAX(LCP) AS LCP,
    MAX(CLS) AS CLS,
    MAX(FID) AS FID,
    ANY_VALUE(generation) AS generation,
    ANY_VALUE(url) AS url,
    ANY_VALUE(referer) AS referer,
    ANY_VALUE(user_agent) AS user_agent,
    id
  FROM helix_rum.CLUSTER_EVENTS(filterurl, days_offset, days_count, day_min, day_max, timezone, deviceclass, filtergeneration)
  GROUP BY id;

CREATE OR REPLACE TABLE FUNCTION helix_rum.CLUSTER_CHECKPOINTS(filterurl STRING, days_offset INT64, days_count INT64, day_min STRING, day_max STRING, timezone STRING, deviceclass STRING, filtergeneration STRING)
AS
  SELECT
    ANY_VALUE(hostname) AS hostname,
    ANY_VALUE(host) AS host,
    MAX(time) AS time,
    checkpoint,
    source,
    target,
    MAX(weight) AS pageviews,
    ANY_VALUE(generation) AS generation,
    id,
    ANY_VALUE(url) AS url,
    ANY_VALUE(referer) AS referer,
    ANY_VALUE(user_agent) AS user_agent,
  FROM helix_rum.CLUSTER_EVENTS(filterurl, days_offset, days_count, day_min, day_max, timezone, deviceclass, filtergeneration)
  GROUP BY id, checkpoint, target, source;

CREATE OR REPLACE TABLE
  FUNCTION `helix-225321.helix_rum.EVENTS_V3`(filterurl STRING,
    days_offset INT64,
    days_count INT64,
    day_min STRING,
    day_max STRING,
    timezone STRING,
    deviceclass STRING,
    domainkey STRING) AS (
  WITH
    validkeys AS (
    SELECT
      *
    FROM
      `helix-225321.helix_reporting.domain_keys`
    WHERE
      key_bytes = SHA512(domainkey)
      AND (revoke_date IS NULL
        OR revoke_date > CURRENT_DATE(timezone))
      AND (hostname_prefix = ""
        OR filterurl LIKE CONCAT("%.", hostname_prefix)
        OR filterurl LIKE CONCAT("%.", hostname_prefix, "/%")
        OR filterurl LIKE CONCAT(hostname_prefix)
        OR filterurl LIKE CONCAT(hostname_prefix, "/%")))
  SELECT
    hostname,
    host,
    user_agent,
    time,
    url,
    LCP,
    FID,
    INP,
    CLS,
    referer,
    id,
    SOURCE,
    TARGET,
    weight,
    checkpoint
  FROM
    `helix-225321.helix_rum.cluster` AS rumdata
  JOIN
    validkeys
  ON
    ( rumdata.url LIKE CONCAT("https://%.", validkeys.hostname_prefix, "/%")
      OR rumdata.url LIKE CONCAT("https://", validkeys.hostname_prefix, "/%")
      OR validkeys.hostname_prefix = "" )
  WHERE
    ( (filterurl = '-') # any URL goes
      OR (url LIKE CONCAT('https://', filterurl, '%')) # default behavior,
      OR (filterurl LIKE 'localhost%'
        AND url LIKE CONCAT('http://', filterurl, '%')) # localhost
      OR (ENDS_WITH(filterurl, '$')
        AND url = CONCAT('https://', REPLACE(filterurl, '$', ''))) # strict URL
      OR (ENDS_WITH(filterurl, '?')
        AND url = CONCAT('https://', REPLACE(filterurl, '?', ''))) # strict URL, but URL params are supported
      )
    AND
  IF
    (filterurl = '-', TRUE, (hostname = SPLIT(filterurl, '/')[
      OFFSET
        (0)])
      OR (filterurl LIKE 'localhost:%'
        AND hostname = 'localhost'))
    AND
  IF
    (days_offset >= 0, DATETIME_SUB(TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), DAY, helix_rum.CLEAN_TIMEZONE(timezone)), INTERVAL days_offset DAY), TIMESTAMP(day_max, helix_rum.CLEAN_TIMEZONE(timezone))) >= time
    AND
  IF
    (days_count >= 0, DATETIME_SUB(TIMESTAMP_TRUNC(CURRENT_TIMESTAMP(), DAY, helix_rum.CLEAN_TIMEZONE(timezone)), INTERVAL (days_offset + days_count) DAY), TIMESTAMP(day_min, helix_rum.CLEAN_TIMEZONE(timezone))) <= time
    AND helix_rum.CLUSTER_FILTERCLASS(user_agent,
      deviceclass) );
CREATE OR REPLACE TABLE
  FUNCTION helix_rum.PAGEVIEWS_V3(filterurl STRING,
    days_offset INT64,
    days_count INT64,
    day_min STRING,
    day_max STRING,
    timezone STRING,
    deviceclass STRING,
    domainkey STRING) AS
SELECT
  ANY_VALUE(hostname) AS hostname,
  ANY_VALUE(host) AS host,
  MAX(time) AS time,
  MAX(weight) AS pageviews,
  MAX(LCP) AS LCP,
  MAX(CLS) AS CLS,
  MAX(FID) AS FID,
  MAX(INP) AS INP,
  ANY_VALUE(url) AS url,
  ANY_VALUE(referer) AS referer,
  ANY_VALUE(user_agent) AS user_agent,
  id
FROM
  helix_rum.EVENTS_V3(filterurl,
    days_offset,
    days_count,
    day_min,
    day_max,
    timezone,
    deviceclass,
    domainkey)
GROUP BY
  id;
CREATE OR REPLACE TABLE
  FUNCTION helix_rum.CHECKPOINTS_V3(filterurl STRING,
    days_offset INT64,
    days_count INT64,
    day_min STRING,
    day_max STRING,
    timezone STRING,
    deviceclass STRING,
    domainkey STRING) AS
SELECT
  ANY_VALUE(hostname) AS hostname,
  ANY_VALUE(host) AS host,
  MAX(time) AS time,
  checkpoint,
  source,
  target,
  MAX(weight) AS pageviews,
  id,
  ANY_VALUE(url) AS url,
  ANY_VALUE(referer) AS referer,
  ANY_VALUE(user_agent) AS user_agent,
FROM
  helix_rum.EVENTS_V3(filterurl,
    days_offset,
    days_count,
    day_min,
    day_max,
    timezone,
    deviceclass,
    domainkey)
GROUP BY
  id,
  checkpoint,
  target,
  source;

CREATE OR REPLACE PROCEDURE
  helix_reporting.ROTATE_DOMAIN_KEYS( IN indomainkey STRING,
    IN inurl STRING,
    IN intimezone STRING,
    IN ingraceperiod INT64,
    IN inexpirydate STRING,
    IN innewkey STRING,
    IN inreadonly BOOL,
    IN innote STRING)
BEGIN
-- allow multiple domains to be passed in as comma-separated value
-- remove any trailing comma before splitting into array
-- because it would result in a global domain key
-- remove any space chars
DECLARE urls ARRAY<STRING>;
SET urls =  SPLIT(REGEXP_REPLACE(RTRIM(inurl, ','), ' ', ''), ',');

UPDATE `helix-225321.helix_reporting.domain_keys`
SET revoke_date = DATE_ADD(CURRENT_DATE(intimezone), INTERVAL ingraceperiod DAY)
WHERE
  # hostname prefix matches
  hostname_prefix IN (SELECT * from UNNEST(urls))
  # key is still valid
  AND (revoke_date IS NULL
    OR revoke_date > CURRENT_DATE(intimezone))
  AND ingraceperiod > 0;

INSERT INTO `helix-225321.helix_reporting.domain_keys` (
  hostname_prefix,
  key_bytes,
  revoke_date,
  readonly,
  create_date,
  parent_key_bytes,
  note
)
SELECT
  *,
  SHA512(innewkey),
  IF(inexpirydate = "-", NULL, DATE(inexpirydate)),
  inreadonly,
  CURRENT_DATE(intimezone),
  SHA512(indomainkey),
  innote
FROM UNNEST(urls);

END

CREATE OR REPLACE TABLE FUNCTION helix_reporting.DOMAINKEY_PRIVS_ALL(domainkey STRING, timezone STRING)
AS (
  WITH key AS (
    SELECT hostname_prefix, readonly
    FROM `helix-225321.helix_reporting.domain_keys`
    WHERE
      key_bytes = SHA512(domainkey)
      AND (
        revoke_date IS NULL
        OR revoke_date > CURRENT_DATE(timezone)
      )
  )
  SELECT COALESCE(
    (
      SELECT IF(hostname_prefix = '', true, false)
      FROM key
    ),
    false
  ) AS read,
  COALESCE(
    (
      SELECT IF(hostname_prefix = '' AND readonly = false, true, false)
      FROM key
    ),
    false
  ) AS write
)

CREATE OR REPLACE PROCEDURE `helix-225321.helix_external_data.ADD_LHS_DATA`(
  IN inurl STRING,
  IN perf_score FLOAT64,
  IN acc_score FLOAT64,
  IN bp_score FLOAT64,
  IN seo_score FLOAT64,
  IN perf_tti_score FLOAT64,
  IN perf_speed_idx FLOAT64,
  IN seo_crawl_score FLOAT64,
  IN seo_crawl_anchors_score FLOAT64,
  IN net_servr_time FLOAT64,
  IN net_nl FLOAT64,
  IN net_mainthread_work_score FLOAT64,
  IN net_total_blocking_score FLOAT64,
  IN net_img_optimization_score FLOAT64,
  IN third_party_score FLOAT64,
  IN device_type STRING,
  IN time STRING,
  IN audit_ref STRING
)
BEGIN
  INSERT INTO `helix-225321.helix_external_data.lhs_spacecat` ( 
    url,
    perf_score,
    acc_score,
    bp_score,
    seo_score,
    perf_tti_score,
    perf_speed_idx,
    seo_crawl_score,
    seo_crawl_anchors_score,
    net_servr_time,
    net_nl,
    net_mainthread_work_score,
    net_total_blocking_score,
    net_img_optimization_score,
    third_party_score,
    device_type,
    time,
    audit_ref 
  )
  VALUES (
    inurl,
    perf_score,
    acc_score,
    bp_score,
    seo_score,
    perf_tti_score,
    perf_speed_idx,
    seo_crawl_score,
    seo_crawl_anchors_score,
    net_servr_time,
    net_nl,
    net_mainthread_work_score,
    net_total_blocking_score,
    net_img_optimization_score,
    third_party_score,
    device_type,
    time,
    audit_ref
  );
END;

CREATE OR REPLACE TABLE FUNCTION helix_rum.URLS_FROM_LIST(inurls STRING) AS (
  SELECT * FROM UNNEST(SPLIT(REGEXP_REPLACE(RTRIM(inurls, ','), ' ', ''), ',')) AS url
);

--- description: Calculate Margin of Error for Binomial Distribution.
--- sampling_rate: the sampling rate
--- successes: the number of successful tries
--- zscore: 1.96
CREATE OR REPLACE FUNCTION helix_rum.MARGIN_OF_ERROR(
  sampling_rate NUMERIC, successes NUMERIC, zscore NUMERIC
)
RETURNS NUMERIC
AS (
  --- Formula for Binomial Distribution: σ= √(npq)
  --- Binomial distribution represents the probability for 'x' successes of an experiment in 'n' trials, 
  --- given a success probability 'p' and a non-success probability 'q'

  --- Margin of Error
  --- Formula: Z-score * Standard Deviation
  --- The z-score for the confidence level: 
  --- With a 95 percent confidence interval, you have a 5 percent chance of being wrong.
  --- Standard Deviation: Measure of the amount of variation of a random variable expected about its mean
  CAST(
    COALESCE(
      zscore,
      CASE
        --- no sampling, no margin of error
        WHEN sampling_rate = 1 THEN 0
        --- 95% confidence level - industry standard
        ELSE 1.96
      END
    )
    *
    (
      sampling_rate * SQRT(successes)
    ) AS NUMERIC
  )
);

# SELECT * FROM helix_rum.CLUSTER_PAGEVIEWS('blog.adobe.com', 1, 7, '', '', 'GMT', 'desktop', '-')
# ORDER BY time DESC
# LIMIT 10;

SELECT hostname, url, time FROM helix_rum.CLUSTER_CHECKPOINTS('localhost:3000/drafts', -1, -7, '2022-02-01', '2022-05-28', 'GMT', 'all', '-')
ORDER BY time DESC
LIMIT 10;
