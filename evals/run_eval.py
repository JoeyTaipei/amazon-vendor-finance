# Runs the eval set through the agent and grades each answer with Claude (AI_COMPLETE).
# Fallback for native Agent Evaluations, whose runs stayed in CREATED in this account.
# Usage: python3 evals/run_eval.py <run_name>
import json
import os
import sys

import snowflake.connector

run_name = sys.argv[1] if len(sys.argv) > 1 else "manual_run"
token = open(os.environ.get("SNOWFLAKE_TOKEN_FILE_PATH", "/snowflake/session/token")).read().strip()
conn = snowflake.connector.connect(
    host=os.environ.get("SNOWFLAKE_HOST"), account=os.environ.get("SNOWFLAKE_ACCOUNT"),
    authenticator="oauth", token=token, role="ATTENDEE_ROLE", warehouse="AMZ_FIN_WH",
)
cur = conn.cursor()
cur.execute("""CREATE TABLE IF NOT EXISTS AMAZON_FINANCE_APP.OPS.EVAL_RESULTS (
  RUN_NAME VARCHAR, RUN_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(), INPUT_QUERY VARCHAR, EXPECTED VARCHAR,
  AGENT_ANSWER VARCHAR, TOOLS_USED VARCHAR, SCORE FLOAT, JUDGE_REASON VARCHAR)""")

rows = cur.execute(
    "SELECT INPUT_QUERY, EXPECTED_OUTPUT:ground_truth_output::VARCHAR FROM AMAZON_FINANCE_APP.OPS.EVAL_QUESTIONS"
).fetchall()
for question, expected in rows:
    body = json.dumps({"messages": [{"role": "user", "content": [{"type": "text", "text": question}]}]})
    resp = json.loads(cur.execute(
        "SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('AMAZON_FINANCE_APP.APP.AMAZON_VENDOR_FINANCE_AGENT', %s)", (body,)
    ).fetchone()[0])
    content = resp.get("content", [])
    answer = "".join(x.get("text", "") for x in content if x.get("type") == "text").strip()
    tools = ",".join(x["tool_use"]["name"] for x in content if x.get("type") == "tool_use")
    cur.execute("""INSERT INTO AMAZON_FINANCE_APP.OPS.EVAL_RESULTS
        (RUN_NAME, INPUT_QUERY, EXPECTED, AGENT_ANSWER, TOOLS_USED, SCORE, JUDGE_REASON)
      SELECT %(r)s, %(q)s, %(e)s, %(a)s, %(t)s, j:score::FLOAT, j:reason::VARCHAR
      FROM (SELECT AI_COMPLETE(model => 'claude-sonnet-4-5',
        prompt => 'Grade the agent answer against the expected answer. Score 1 if all key figures in the expected answer appear in the agent answer '
               || '(rounding to the nearest dollar or 0.1 percentage point is fine, millions shorthand like $3.99M is fine), 0.5 if partially, 0 if wrong or missing. '
               || 'Question: ' || %(q)s || ' Expected: ' || %(e)s || ' Agent answer: ' || %(a)s,
        response_format => TYPE OBJECT(score FLOAT, reason STRING)) AS j)""",
        {"r": run_name, "q": question, "e": expected, "a": answer[:6000], "t": tools})
    print(question[:60], "|", tools)

print(cur.execute(
    "SELECT ROUND(AVG(SCORE), 3), COUNT(*) FROM AMAZON_FINANCE_APP.OPS.EVAL_RESULTS WHERE RUN_NAME = %s", (run_name,)
).fetchall())
