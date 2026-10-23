-- Clean views over the read-only Marketplace share. Negative remittance amounts are deductions;
-- provision lines (incl. -R reversals) are accounting entries and are excluded from deductions.
CREATE OR REPLACE VIEW AMAZON_FINANCE_APP.STAGING.REMITTANCE_LINES AS
SELECT
  "id"                    AS LINE_ID,
  "payment_number"        AS PAYMENT_NUMBER,
  "invoice_number"        AS INVOICE_NUMBER,
  "invoice_date"::DATE    AS INVOICE_DATE,
  "description"           AS DESCRIPTION,
  "invoice_amount"        AS AMOUNT,
  "amount_paid"           AS AMOUNT_PAID,
  "remaining_amount"      AS REMAINING_AMOUNT,
  "description" ILIKE 'PROVISION_FOR_%'  AS IS_PROVISION,
  "description" = 'Shortage Claim'       AS IS_SHORTAGE,
  ("invoice_amount" < 0 AND NOT "description" ILIKE 'PROVISION_FOR_%') AS IS_DEDUCTION,
  CASE
    WHEN "description" ILIKE 'PROVISION_FOR_%' THEN 'PROVISION'
    WHEN "description" = 'Shortage Claim' THEN 'SHORTAGE'
    WHEN "description" = '-____-' THEN 'UNCATEGORIZED'
    WHEN "description" IN ('/____/', '____-', 'Payment made to vendor') THEN 'INVOICE_PAYMENT'
    WHEN "description" = 'Damage Allowance' THEN 'DAMAGE_ALLOWANCE'
    WHEN "description" = 'AVS - SVS' THEN 'AVS_SVS'
    WHEN "description" = 'Missed Adjustment Claim' THEN 'MISSED_ADJUSTMENT'
    WHEN "description" IN ('RETURNS', 'RETURN FREIGHT CHARGES') THEN 'RETURNS'
    WHEN "description" ILIKE 'Coop%' THEN 'COOP'
    WHEN "description" IN ('PREP', 'Ship In Own Container', 'Oversized Carton', 'Overweight Carton',
                           'No carton/package', 'Carton Content Accuracy', 'Pickup Accuracy', 'Rejected PO Rate', 'PC')
      THEN 'OPERATIONAL_FEES'
    ELSE 'OTHER'
  END AS DEDUCTION_CATEGORY
FROM AMAZON_VENDOR_PL_FINANCE_REMITTANCE_AND_INVOICES_DEMO_DATASET.PUBLIC."payments_invoices";

CREATE OR REPLACE VIEW AMAZON_FINANCE_APP.STAGING.INVOICES AS
SELECT
  "invoice_number"         AS INVOICE_NUMBER,
  "invoice_date"::DATE     AS INVOICE_DATE,
  "payment_due_date"::DATE AS PAYMENT_DUE_DATE,
  "invoice_status"         AS INVOICE_STATUS,
  "invoice_amount"         AS INVOICE_AMOUNT,
  "actual_paid_amount"     AS PAID_AMOUNT,
  COALESCE("invoice_amount", 0) - COALESCE("actual_paid_amount", 0) AS UNPAID_AMOUNT,
  "in_progress"            AS IN_PROGRESS_AMOUNT,
  "queued_for_payment"     AS QUEUED_FOR_PAYMENT_AMOUNT,
  "quantity_variance"      AS QUANTITY_VARIANCE,
  "price_variance"         AS PRICE_VARIANCE,
  "list_of_pos"            AS LIST_OF_POS
FROM AMAZON_VENDOR_PL_FINANCE_REMITTANCE_AND_INVOICES_DEMO_DATASET.PUBLIC."invoices_summaryv2";

CREATE OR REPLACE VIEW AMAZON_FINANCE_APP.STAGING.PAYMENTS AS
SELECT
  "payment_number"             AS PAYMENT_NUMBER,
  "payment_date"::DATE         AS PAYMENT_DATE,
  "amount_in_payment_currency" AS PAYMENT_AMOUNT,
  "payment_type"               AS PAYMENT_TYPE,
  "payment_status"             AS PAYMENT_STATUS
FROM AMAZON_VENDOR_PL_FINANCE_REMITTANCE_AND_INVOICES_DEMO_DATASET.PUBLIC."payments_payments";

CREATE OR REPLACE VIEW AMAZON_FINANCE_APP.STAGING.COOP AS
SELECT
  "id"                 AS COOP_ID,
  "invoice_id"         AS INVOICE_ID,
  "invoice_date"::DATE AS INVOICE_DATE,
  "agreement_id"       AS AGREEMENT_ID,
  "agreement_title"    AS AGREEMENT_TITLE,
  "funding_type"       AS FUNDING_TYPE,
  "original_balance"   AS COOP_AMOUNT
FROM AMAZON_VENDOR_PL_FINANCE_REMITTANCE_AND_INVOICES_DEMO_DATASET.PUBLIC."payments_coop";

CREATE OR REPLACE VIEW AMAZON_FINANCE_APP.STAGING.DISPUTES AS
SELECT
  "id"                 AS DISPUTE_LINE_ID,
  "dispute_id"         AS DISPUTE_ID,
  "dispute_date"::DATE AS DISPUTE_DATE,
  "invoice_number"     AS INVOICE_NUMBER,
  "invoice_date"::DATE AS INVOICE_DATE,
  "po"                 AS PO,
  "asin"               AS ASIN,
  "shortage_amount"    AS SHORTAGE_AMOUNT,
  "dispute_amount"     AS DISPUTE_AMOUNT,
  "resolved_amount"    AS RESOLVED_AMOUNT,
  COALESCE(NULLIF("dispute_decision", ''), 'PENDING') AS DISPUTE_DECISION
FROM AMAZON_VENDOR_PL_FINANCE_REMITTANCE_AND_INVOICES_DEMO_DATASET.PUBLIC."payments_dispute_management_details";
