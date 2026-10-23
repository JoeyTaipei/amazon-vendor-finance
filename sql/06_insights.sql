-- Phase 4b: rule-based insights + recommended actions. Numbers come from SQL rules; AI_COMPLETE only writes the wording.


create or replace TABLE AMAZON_FINANCE_APP.MARTS.INSIGHTS (
	ID NUMBER(38,0) NOT NULL autoincrement start 1 increment 1 noorder,
	GENERATED_AT TIMESTAMP_LTZ(9) DEFAULT CURRENT_TIMESTAMP(),
	RULE_ID VARCHAR(16777216),
	PROBLEM_AREA VARCHAR(16777216),
	SEVERITY VARCHAR(16777216),
	TITLE VARCHAR(16777216),
	SUMMARY VARCHAR(16777216),
	METRIC VARCHAR(16777216),
	CURRENT_VALUE FLOAT,
	COMPARISON_VALUE FLOAT,
	CHANGE_PCT FLOAT,
	EVIDENCE_SQL VARCHAR(16777216),
	ENTITY_TYPE VARCHAR(16777216),
	ENTITY_ID VARCHAR(16777216),
	primary key (ID)
);

create or replace TABLE AMAZON_FINANCE_APP.MARTS.RECOMMENDED_ACTIONS (
	ID NUMBER(38,0) NOT NULL autoincrement start 1 increment 1 noorder,
	INSIGHT_ID NUMBER(38,0),
	ACTION_TYPE VARCHAR(16777216),
	ENTITY_TYPE VARCHAR(16777216),
	ENTITY_ID VARCHAR(16777216),
	ESTIMATED_VALUE_USD FLOAT,
	CONFIDENCE VARCHAR(16777216),
	RATIONALE VARCHAR(16777216),
	STATUS VARCHAR(16777216) DEFAULT 'new',
	CREATED_AT TIMESTAMP_LTZ(9) DEFAULT CURRENT_TIMESTAMP(),
	EXPIRES_AT TIMESTAMP_LTZ(9),
	DISMISS_REASON VARCHAR(16777216),
	ACTION_ITEM_ID NUMBER(38,0),
	primary key (ID)
);

create or replace view AMAZON_FINANCE_APP.OPS.INSIGHT_RULES_V(
	RULE_ID,
	PROBLEM_AREA,
	SEVERITY,
	METRIC,
	CURRENT_VALUE,
	COMPARISON_VALUE,
	CHANGE_PCT,
	EVIDENCE_SQL,
	ENTITY_TYPE,
	ENTITY_ID,
	ACTION_TYPE,
	ESTIMATED_VALUE_USD,
	CONFIDENCE,
	RATIONALE
) as
WITH sr AS (SELECT * FROM AMAZON_FINANCE_APP.MARTS.SHORTAGE_RECOVERY WHERE SHORTAGE_DEDUCTED > 0),
latest AS (SELECT MAX(MONTH) AS M FROM sr),
spike AS (
  SELECT (SELECT SHORTAGE_DEDUCTED FROM sr, latest WHERE sr.MONTH = latest.M) AS cur,
         (SELECT AVG(SHORTAGE_DEDUCTED) FROM sr, latest WHERE sr.MONTH < latest.M AND sr.MONTH >= DATEADD('month', -6, latest.M)) AS avg6,
         (SELECT TO_CHAR(M, 'YYYY-MM') FROM latest) AS m),
k AS (SELECT * FROM AMAZON_FINANCE_APP.MARTS.KPI_SUMMARY),
asins AS (
  SELECT ASIN, COUNT(*) AS n, SUM(SHORTAGE_AMOUNT) AS shortage, SUM(RESOLVED_AMOUNT) AS recovered
  FROM AMAZON_FINANCE_APP.STAGING.DISPUTES WHERE ASIN IS NOT NULL GROUP BY 1 HAVING COUNT(*) >= 3
  QUALIFY ROW_NUMBER() OVER (ORDER BY SUM(SHORTAGE_AMOUNT) - SUM(RESOLVED_AMOUNT) DESC) <= 5),
dm AS (SELECT MAX(MONTH) AS M FROM AMAZON_FINANCE_APP.MARTS.DEDUCTIONS_BY_CATEGORY),
unexp AS (
  SELECT SUM(IFF(d.MONTH > DATEADD('month', -3, dm.M), d.DEDUCTION_AMOUNT, 0)) AS last3,
         SUM(IFF(d.MONTH <= DATEADD('month', -3, dm.M) AND d.MONTH > DATEADD('month', -6, dm.M), d.DEDUCTION_AMOUNT, 0)) AS prior3
  FROM AMAZON_FINANCE_APP.MARTS.DEDUCTIONS_BY_CATEGORY d, dm WHERE d.IS_UNEXPLAINED),
aged AS (SELECT COUNT(*) AS n, SUM(UNPAID_AMOUNT) AS amt FROM AMAZON_FINANCE_APP.MARTS.UNPAID_INVOICE_AGING WHERE AGING_BUCKET = '60+'),
coop AS (SELECT * FROM AMAZON_FINANCE_APP.MARTS.COOP_BY_AGREEMENT QUALIFY ROW_NUMBER() OVER (ORDER BY ABS(COOP_AMOUNT) DESC) <= 3)
SELECT 'R1_SHORTAGE_SPIKE' AS RULE_ID, 'shortage' AS PROBLEM_AREA, IFF(cur > 1.5 * avg6, 'high', 'medium') AS SEVERITY,
       'Shortage deducted in ' || m || ' vs prior 6-month average' AS METRIC, cur AS CURRENT_VALUE, avg6 AS COMPARISON_VALUE, (cur - avg6) / NULLIF(avg6, 0) AS CHANGE_PCT,
       'SELECT * FROM AMAZON_FINANCE_APP.MARTS.SHORTAGE_RECOVERY ORDER BY MONTH DESC LIMIT 7' AS EVIDENCE_SQL, 'month' AS ENTITY_TYPE, m AS ENTITY_ID,
       'dispute_shortage' AS ACTION_TYPE, cur AS ESTIMATED_VALUE_USD, 'medium' AS CONFIDENCE,
       'Shortages in the latest month are above the recent average; dispute the latest month''s shortage lines.' AS RATIONALE
FROM spike WHERE cur > 1.2 * avg6
UNION ALL
SELECT 'R2_LOW_RECOVERY', 'shortage', 'high', 'Shortage recovery rate (recovered / shortage deducted) vs 10% target',
       SHORTAGE_RECOVERY_RATE, 0.10, (SHORTAGE_RECOVERY_RATE - 0.10) / 0.10,
       'SELECT SHORTAGE_DEDUCTED, RECOVERED, SHORTAGE_RECOVERY_RATE FROM AMAZON_FINANCE_APP.MARTS.KPI_SUMMARY', 'kpi', 'SHORTAGE_RECOVERY_RATE',
       'dispute_shortage', SHORTAGE_DEDUCTED * 0.10 - RECOVERED, 'low',
       'Raising recovery to 10% of shortage deducted would recover this additional amount.'
FROM k WHERE SHORTAGE_RECOVERY_RATE < 0.10
UNION ALL
SELECT 'R3_REPEAT_SHORTAGE_ASIN', 'shortage', IFF(shortage - recovered > 10000, 'high', 'medium'), 'Unrecovered shortage on ASIN with ' || n || ' disputes',
       shortage - recovered, shortage, NULL,
       'SELECT * FROM AMAZON_FINANCE_APP.STAGING.DISPUTES WHERE ASIN = ''' || ASIN || '''', 'asin', ASIN,
       'dispute_shortage', shortage - recovered, 'medium',
       'Repeated shortages on one ASIN suggest a receiving or carton-labelling issue; dispute open lines and fix labelling.'
FROM asins
UNION ALL
SELECT 'R4_UNEXPLAINED_DEDUCTIONS', 'deductions', 'high', 'Deductions with no Amazon description, last 3 months vs prior 3 months',
       last3, prior3, (last3 - prior3) / NULLIF(prior3, 0),
       'SELECT * FROM AMAZON_FINANCE_APP.MARTS.DEDUCTIONS_BY_CATEGORY WHERE IS_UNEXPLAINED ORDER BY MONTH DESC', 'category', 'UNCATEGORIZED',
       'classify_deduction', (SELECT UNEXPLAINED_DEDUCTIONS FROM k), 'medium',
       'Request backup from Amazon for every deduction without a description so it can be categorized or disputed.'
FROM unexp
UNION ALL
SELECT 'R5_AGED_UNPAID', 'cash', IFF(amt > 50000, 'high', 'medium'), 'Unpaid amount on invoices more than 60 days past due (' || n || ' invoices)',
       amt, NULL, NULL,
       'SELECT * FROM AMAZON_FINANCE_APP.MARTS.UNPAID_INVOICE_AGING WHERE AGING_BUCKET = ''60+'' ORDER BY UNPAID_AMOUNT DESC', 'aging_bucket', '60+',
       'chase_payment', amt, 'high', 'Follow up with Amazon on invoices unpaid more than 60 days past due.'
FROM aged WHERE n > 0
UNION ALL
SELECT 'R6_TOP_COOP', 'coop', 'low', 'Co-op charges on agreement ' || COALESCE(AGREEMENT_TITLE, AGREEMENT_ID),
       ABS(COOP_AMOUNT), NULL, NULL,
       'SELECT * FROM AMAZON_FINANCE_APP.MARTS.COOP_BY_AGREEMENT WHERE AGREEMENT_ID = ''' || AGREEMENT_ID || '''', 'agreement', AGREEMENT_ID,
       'coop_review', ABS(COOP_AMOUNT), 'low', 'Review this co-op agreement''s charges against the agreed terms and its sales impact.'
FROM coop;

create or replace view AMAZON_FINANCE_APP.OPS.INSIGHT_FACTS_V(
	RULE_ID,
	PROBLEM_AREA,
	SEVERITY,
	METRIC,
	CURRENT_VALUE,
	COMPARISON_VALUE,
	CHANGE_PCT,
	EVIDENCE_SQL,
	ENTITY_TYPE,
	ENTITY_ID,
	ACTION_TYPE,
	ESTIMATED_VALUE_USD,
	CONFIDENCE,
	RATIONALE,
	FACTS
) as
SELECT r.*,
  OBJECT_CONSTRUCT(
    'problem_area', PROBLEM_AREA,
    'metric', METRIC,
    'current_value', IFF(RULE_ID = 'R2_LOW_RECOVERY', TO_VARCHAR(ROUND(CURRENT_VALUE * 100, 2)) || '%', '$' || TO_VARCHAR(ROUND(CURRENT_VALUE, 0), 'FM999,999,999')),
    'comparison_label', CASE RULE_ID WHEN 'R1_SHORTAGE_SPIKE' THEN 'prior 6-month average' WHEN 'R2_LOW_RECOVERY' THEN 'target rate'
                                     WHEN 'R3_REPEAT_SHORTAGE_ASIN' THEN 'total shortage claimed on this ASIN (not a prior value)' WHEN 'R4_UNEXPLAINED_DEDUCTIONS' THEN 'prior 3 months' END,
    'comparison_value', IFF(RULE_ID = 'R2_LOW_RECOVERY', TO_VARCHAR(ROUND(COMPARISON_VALUE * 100, 0)) || '%', '$' || TO_VARCHAR(ROUND(COMPARISON_VALUE, 0), 'FM999,999,999')),
    'relative_change', IFF(CHANGE_PCT IS NULL, NULL, TO_VARCHAR(ROUND(CHANGE_PCT * 100, 1)) || '% relative to comparison'),
    'entity', ENTITY_TYPE || ' ' || ENTITY_ID,
    'recommended_action', ACTION_TYPE,
    'estimated_value', '$' || TO_VARCHAR(ROUND(ESTIMATED_VALUE_USD, 0), 'FM999,999,999'),
    'rationale', RATIONALE)::VARCHAR AS FACTS
FROM AMAZON_FINANCE_APP.OPS.INSIGHT_RULES_V r;

CREATE OR REPLACE PROCEDURE AMAZON_FINANCE_APP.OPS.GENERATE_INSIGHTS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
  run_ts TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP();
  n_ins NUMBER;
  n_rec NUMBER;
BEGIN
  -- Untouched recommendations from previous runs are stale; accepted/dismissed ones are kept for the feedback loop.
  DELETE FROM AMAZON_FINANCE_APP.MARTS.RECOMMENDED_ACTIONS WHERE STATUS = ''new'';
  DELETE FROM AMAZON_FINANCE_APP.MARTS.INSIGHTS
   WHERE ID NOT IN (SELECT INSIGHT_ID FROM AMAZON_FINANCE_APP.MARTS.RECOMMENDED_ACTIONS WHERE INSIGHT_ID IS NOT NULL);

  INSERT INTO AMAZON_FINANCE_APP.MARTS.INSIGHTS
    (GENERATED_AT, RULE_ID, PROBLEM_AREA, SEVERITY, TITLE, SUMMARY, METRIC, CURRENT_VALUE, COMPARISON_VALUE, CHANGE_PCT, EVIDENCE_SQL, ENTITY_TYPE, ENTITY_ID)
  SELECT :run_ts, RULE_ID, PROBLEM_AREA, SEVERITY, j:title::VARCHAR, j:summary::VARCHAR, METRIC, CURRENT_VALUE, COMPARISON_VALUE, CHANGE_PCT, EVIDENCE_SQL, ENTITY_TYPE, ENTITY_ID
  FROM (
    SELECT f.*,
      AI_COMPLETE(
        model => ''claude-sonnet-4-5'',
        prompt => ''You write insight cards for an Amazon vendor finance team. Use ONLY the facts below, copying numbers exactly as written. '' ||
                  ''Do not compute, convert or introduce any new number, percentage or date. Do not describe a comparison as a decrease or increase unless relative_change is given. '' ||
                  ''Write a title (max 10 words) and a 2-sentence summary: what happened, then what to do. Facts: '' || f.FACTS,
        response_format => TYPE OBJECT(title STRING, summary STRING)
      ) AS j
    FROM AMAZON_FINANCE_APP.OPS.INSIGHT_FACTS_V f);
  n_ins := SQLROWCOUNT;

  INSERT INTO AMAZON_FINANCE_APP.MARTS.RECOMMENDED_ACTIONS
    (INSIGHT_ID, ACTION_TYPE, ENTITY_TYPE, ENTITY_ID, ESTIMATED_VALUE_USD, CONFIDENCE, RATIONALE, STATUS, EXPIRES_AT)
  SELECT i.ID, r.ACTION_TYPE, r.ENTITY_TYPE, r.ENTITY_ID, r.ESTIMATED_VALUE_USD, r.CONFIDENCE, r.RATIONALE, ''new'', DATEADD(''day'', 7, :run_ts)
  FROM AMAZON_FINANCE_APP.OPS.INSIGHT_RULES_V r
  JOIN AMAZON_FINANCE_APP.MARTS.INSIGHTS i
    ON i.GENERATED_AT = :run_ts AND i.RULE_ID = r.RULE_ID AND i.ENTITY_ID = r.ENTITY_ID
  -- Skip recommendations already accepted or dismissed for the same entity.
  WHERE NOT EXISTS (SELECT 1 FROM AMAZON_FINANCE_APP.MARTS.RECOMMENDED_ACTIONS x
                     WHERE x.ACTION_TYPE = r.ACTION_TYPE AND x.ENTITY_ID = r.ENTITY_ID AND x.STATUS IN (''accepted'', ''dismissed''));
  n_rec := SQLROWCOUNT;

  RETURN ''Generated '' || :n_ins || '' insights and '' || :n_rec || '' recommendations'';
END;
';

CREATE OR REPLACE PROCEDURE AMAZON_FINANCE_APP.OPS.ACCEPT_RECOMMENDATION("P_ID" NUMBER(38,0))
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
  n NUMBER;
  new_id NUMBER;
BEGIN
  SELECT COUNT(*) INTO :n FROM AMAZON_FINANCE_APP.MARTS.RECOMMENDED_ACTIONS WHERE ID = :P_ID AND STATUS = ''new'';
  IF (:n = 0) THEN
    RETURN ''ERROR: recommendation '' || :P_ID || '' not found or already handled'';
  END IF;
  INSERT INTO AMAZON_FINANCE_APP.OPS.ACTION_ITEMS (TYPE, ENTITY_TYPE, ENTITY_ID, AMOUNT, PRIORITY, STATUS, CREATED_BY, SOURCE, NOTES, RECOMMENDATION_ID, DUE_DATE)
  SELECT r.ACTION_TYPE, r.ENTITY_TYPE, r.ENTITY_ID, ROUND(r.ESTIMATED_VALUE_USD, 2),
         CASE i.SEVERITY WHEN ''high'' THEN ''high'' WHEN ''low'' THEN ''low'' ELSE ''medium'' END,
         ''open'', CURRENT_USER(), ''recommendation'', i.TITLE || '' - '' || r.RATIONALE, r.ID, DATEADD(''day'', 14, CURRENT_DATE())
  FROM AMAZON_FINANCE_APP.MARTS.RECOMMENDED_ACTIONS r JOIN AMAZON_FINANCE_APP.MARTS.INSIGHTS i ON i.ID = r.INSIGHT_ID
  WHERE r.ID = :P_ID;
  SELECT MAX(ID) INTO :new_id FROM AMAZON_FINANCE_APP.OPS.ACTION_ITEMS WHERE RECOMMENDATION_ID = :P_ID;
  UPDATE AMAZON_FINANCE_APP.MARTS.RECOMMENDED_ACTIONS SET STATUS = ''accepted'', ACTION_ITEM_ID = :new_id WHERE ID = :P_ID;
  RETURN ''Accepted recommendation '' || :P_ID || ''; created action item '' || :new_id;
END;
';

CREATE OR REPLACE PROCEDURE AMAZON_FINANCE_APP.OPS.DISMISS_RECOMMENDATION("P_ID" NUMBER(38,0), "P_REASON" VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
  n NUMBER;
BEGIN
  IF (:P_REASON IS NULL OR TRIM(:P_REASON) = '''') THEN
    RETURN ''ERROR: a dismiss reason is required'';
  END IF;
  SELECT COUNT(*) INTO :n FROM AMAZON_FINANCE_APP.MARTS.RECOMMENDED_ACTIONS WHERE ID = :P_ID AND STATUS = ''new'';
  IF (:n = 0) THEN
    RETURN ''ERROR: recommendation '' || :P_ID || '' not found or already handled'';
  END IF;
  UPDATE AMAZON_FINANCE_APP.MARTS.RECOMMENDED_ACTIONS SET STATUS = ''dismissed'', DISMISS_REASON = :P_REASON WHERE ID = :P_ID;
  RETURN ''Dismissed recommendation '' || :P_ID;
END;
';

CREATE OR REPLACE PROCEDURE AMAZON_FINANCE_APP.OPS.LIST_RECOMMENDATIONS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
  out VARCHAR;
BEGIN
  SELECT COALESCE(ARRAY_AGG(OBJECT_CONSTRUCT_KEEP_NULL(''recommendation_id'', r.ID, ''action_type'', r.ACTION_TYPE, ''entity'', r.ENTITY_TYPE || '' '' || r.ENTITY_ID,
           ''estimated_value_usd'', ROUND(r.ESTIMATED_VALUE_USD, 0), ''confidence'', r.CONFIDENCE, ''severity'', i.SEVERITY,
           ''insight_title'', i.TITLE, ''insight_summary'', i.SUMMARY, ''metric'', i.METRIC, ''current_value'', i.CURRENT_VALUE,
           ''comparison_value'', i.COMPARISON_VALUE, ''evidence_sql'', i.EVIDENCE_SQL))
           WITHIN GROUP (ORDER BY r.ESTIMATED_VALUE_USD DESC), ARRAY_CONSTRUCT())::VARCHAR
    INTO :out
    FROM AMAZON_FINANCE_APP.MARTS.RECOMMENDED_ACTIONS r
    JOIN AMAZON_FINANCE_APP.MARTS.INSIGHTS i ON i.ID = r.INSIGHT_ID
   WHERE r.STATUS = ''new'';
  RETURN :out;
END;
';

create or replace task AMAZON_FINANCE_APP.OPS.DAILY_INSIGHTS_TASK
	warehouse=AMZ_FIN_WH
	schedule='USING CRON 0 6 * * * UTC'
	as CALL AMAZON_FINANCE_APP.OPS.GENERATE_INSIGHTS();

ALTER TASK AMAZON_FINANCE_APP.OPS.DAILY_INSIGHTS_TASK RESUME;
