CREATE OR REPLACE AGENT AMAZON_FINANCE_APP.APP.AMAZON_VENDOR_FINANCE_AGENT
  COMMENT = 'Amazon 1P vendor finance agent: deductions, shortage recovery, cash collection, co-op, action items'
  PROFILE = '{"display_name": "Amazon Vendor Finance"}'
  FROM SPECIFICATION
$$
models:
  orchestration: claude-sonnet-4-5
instructions:
  orchestration: >-
    Use FinanceAnalyst for every number (invoiced, paid, unpaid, deductions, shortages, recovery, disputes, co-op).
    Never calculate figures yourself beyond what FinanceAnalyst returns.
    Use RemittanceSearch to explain what an Amazon remittance description or deduction type means.
    PROVISION lines are accounting entries: never count them as deductions.
    Shortage recovery rate = recovered / total shortage deducted (not / disputed).
    Deductions with category UNCATEGORIZED have no description from Amazon; the recommended action is classify_deduction (ask Amazon for backup).
    Before calling CreateActionItem or UpdateActionItem, show the user exactly what you will write and ask for confirmation; only call the tool after the user confirms.
    Use ListActionItems when the user asks about open work or action items.
    For "what should I do", priorities, insights or recommendations, call ListRecommendations and present the top items by estimated value with their recommendation_id; explain any insight using its stored metric, values and evidence_sql.
    AcceptRecommendation and DismissRecommendation also require explicit user confirmation first; dismiss requires a reason from the user.
  response: >-
    Be concise. Put numbers in tables. State the source of each answer (semantic view, search, or action items).
    Deduction amounts are negative in raw data; present them as positive dollars deducted. Reply in the user's language.
  sample_questions:
    - question: "What is our shortage recovery rate?"
    - question: "Show deductions by category"
    - question: "What is the unpaid invoice aging?"
    - question: "What does Missed Adjustment Claim mean and how much did it cost us?"
    - question: "What action items are open?"
    - question: "What should I do this week?"
skills:
  - name: deduction-playbook
    source:
      type: STAGE
      path: "@AMAZON_FINANCE_APP.OPS.SKILL_STAGE/skills/deduction_playbook"
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: FinanceAnalyst
      description: "Amazon vendor finance metrics: invoices, remittance deductions by category, shortages, disputes and recoveries, payments, co-op charges."
  - tool_spec:
      type: cortex_search
      name: RemittanceSearch
      description: "Glossary of Amazon remittance descriptions with their deduction category, line count and total amount."
  - tool_spec:
      type: generic
      name: CreateActionItem
      description: "Create an action item in Snowflake. Only call after the user confirms."
      input_schema:
        type: object
        properties:
          p_type:
            type: string
            description: "One of dispute_shortage, classify_deduction, chase_payment, coop_review, price_fix"
          p_entity_type:
            type: string
            description: "invoice, asin, po, payment or category"
          p_entity_id:
            type: string
            description: "Identifier of the entity, e.g. invoice number or category name"
          p_amount:
            type: number
            description: "Dollar amount at stake (positive)"
          p_priority:
            type: string
            description: "low, medium or high"
          p_notes:
            type: string
            description: "Short description of what needs to be done"
        required: [p_type, p_entity_type, p_entity_id, p_amount, p_priority, p_notes]
  - tool_spec:
      type: generic
      name: UpdateActionItem
      description: "Update status, owner, notes or recovered amount of an action item. Only call after the user confirms."
      input_schema:
        type: object
        properties:
          p_id:
            type: number
            description: "Action item id"
          p_status:
            type: string
            description: "open, in_progress, done or dismissed (empty to keep)"
          p_owner:
            type: string
            description: "Owner (empty to keep)"
          p_notes:
            type: string
            description: "Note to append (empty to keep)"
          p_outcome_amount:
            type: number
            description: "Amount recovered (0 to keep)"
        required: [p_id, p_status, p_owner, p_notes, p_outcome_amount]
  - tool_spec:
      type: generic
      name: ListActionItems
      description: "List up to 50 action items, optionally filtered by status (open, in_progress, done, dismissed; empty for all)."
      input_schema:
        type: object
        properties:
          p_status:
            type: string
            description: "Status filter, empty string for all"
        required: [p_status]
  - tool_spec:
      type: generic
      name: ListRecommendations
      description: "List open recommended actions with their insight, estimated dollar value, confidence and evidence SQL, sorted by value."
      input_schema:
        type: object
        properties: {}
  - tool_spec:
      type: generic
      name: AcceptRecommendation
      description: "Accept a recommendation; creates a linked action item. Only call after the user confirms."
      input_schema:
        type: object
        properties:
          p_id:
            type: number
            description: "recommendation_id"
        required: [p_id]
  - tool_spec:
      type: generic
      name: DismissRecommendation
      description: "Dismiss a recommendation with a reason. Only call after the user confirms and gives a reason."
      input_schema:
        type: object
        properties:
          p_id:
            type: number
            description: "recommendation_id"
          p_reason:
            type: string
            description: "Why it is dismissed"
        required: [p_id, p_reason]
tool_resources:
  FinanceAnalyst:
    semantic_view: AMAZON_FINANCE_APP.SEMANTIC.AMAZON_VENDOR_FINANCE_SV
    execution_environment:
      type: warehouse
      warehouse: AMZ_FIN_WH
  RemittanceSearch:
    search_service: AMAZON_FINANCE_APP.OPS.AMZ_TEXT_SEARCH
    max_results: 5
    title_column: DESCRIPTION
    id_column: DESCRIPTION
  CreateActionItem:
    type: procedure
    identifier: AMAZON_FINANCE_APP.OPS.CREATE_ACTION_ITEM
    execution_environment:
      type: warehouse
      warehouse: AMZ_FIN_WH
  UpdateActionItem:
    type: procedure
    identifier: AMAZON_FINANCE_APP.OPS.UPDATE_ACTION_ITEM
    execution_environment:
      type: warehouse
      warehouse: AMZ_FIN_WH
  ListActionItems:
    type: procedure
    identifier: AMAZON_FINANCE_APP.OPS.LIST_ACTION_ITEMS
    execution_environment:
      type: warehouse
      warehouse: AMZ_FIN_WH
  ListRecommendations:
    type: procedure
    identifier: AMAZON_FINANCE_APP.OPS.LIST_RECOMMENDATIONS
    execution_environment:
      type: warehouse
      warehouse: AMZ_FIN_WH
  AcceptRecommendation:
    type: procedure
    identifier: AMAZON_FINANCE_APP.OPS.ACCEPT_RECOMMENDATION
    execution_environment:
      type: warehouse
      warehouse: AMZ_FIN_WH
  DismissRecommendation:
    type: procedure
    identifier: AMAZON_FINANCE_APP.OPS.DISMISS_RECOMMENDATION
    execution_environment:
      type: warehouse
      warehouse: AMZ_FIN_WH
$$;
