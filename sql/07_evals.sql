-- Evaluation set: ground truth computed with direct SQL against STAGING/MARTS on 2026-10-23.
CREATE OR REPLACE TABLE AMAZON_FINANCE_APP.OPS.EVAL_QUESTIONS (INPUT_QUERY VARCHAR, EXPECTED_OUTPUT VARIANT);

INSERT INTO AMAZON_FINANCE_APP.OPS.EVAL_QUESTIONS
SELECT q, OBJECT_CONSTRUCT('ground_truth_output', a) FROM VALUES
 ('What is our shortage recovery rate?',
  'The shortage recovery rate is about 1.09%: $43,654.41 recovered out of $3,988,995.16 of shortage deducted.'),
 ('How much was deducted for shortage claims in total?',
  'Shortage claims deducted a total of $3,988,995.16.'),
 ('Which ASIN has the most unrecovered shortage?',
  'ASIN B7AA89EDFF has the most unrecovered shortage, $40,439.25.'),
 ('What are total deductions excluding provisions?',
  'Total deductions excluding provisions are $8,745,049.67.'),
 ('How much of our deductions have no description from Amazon?',
  '$3,980,640.31 of deductions (594 lines) have no description from Amazon, about 45.5% of total deductions.'),
 ('What is the total invoiced, paid and unpaid amount?',
  'Invoiced $10,294,904.08, paid $10,000,791.94, unpaid $294,112.14.'),
 ('How much is unpaid more than 60 days past due?',
  '$297,468.89 is unpaid on 180 invoices more than 60 days past due.'),
 ('What does Missed Adjustment Claim mean and how much did it cost us?',
  'Missed Adjustment Claim is an Amazon remittance deduction in the MISSED_ADJUSTMENT category; it deducted $114,919.91 across 839 lines.')
AS t(q, a);
