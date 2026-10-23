---
name: deduction-playbook
description: Playbook for handling an Amazon vendor deduction or shortage - how to dispute, recover or resolve it, what evidence to gather, and which action item to create. Use when the user asks how to handle, dispute, recover, or fix a deduction, shortage, ASIN, chargeback or co-op charge, or wants a recovery plan.
---

# Deduction playbook

Follow these steps in order. Never invent numbers: every figure must come from a tool result.

## 1. Size the problem
Call FinanceAnalyst for the amount and line count of the deduction category, ASIN, PO or invoice the user named
(for ASINs, use the DISPUTES table: shortage, disputed and recovered amounts).
Exclude PROVISION lines; they are accounting entries, not money Amazon kept.

## 2. Check for existing work
Call ListActionItems with an empty status and look for an open item with the same entity_id.
If one exists, report it and suggest updating it instead of creating a new one.
Also call ListRecommendations; if a matching recommendation exists, suggest accepting it (AcceptRecommendation)
so the action item stays linked to its insight.

## 3. Pick the play

| Category | action_type | What to do | Evidence to gather |
|---|---|---|---|
| SHORTAGE | dispute_shortage | Dispute the shortage claim line by line in Vendor Central | Proof of delivery / carrier POD, BOL, ASN, packing list, carton labels |
| UNCATEGORIZED | classify_deduction | Ask Amazon for backup (the deduction reason and supporting document) before deciding to dispute | Remittance line, payment number, date, amount |
| DAMAGE_ALLOWANCE | coop_review | Check the allowance against the vendor agreement terms | Vendor agreement, damage allowance rate |
| AVS_SVS | coop_review | Confirm the vendor services charge was agreed | AVS/SVS agreement or order |
| MISSED_ADJUSTMENT | price_fix | Check whether a cost or price change was applied correctly | Cost change confirmation, invoice cost vs PO cost |
| RETURNS | coop_review | Confirm returns were authorized under the agreement | Return authorization, return allowance terms |
| OPERATIONAL_FEES (prep, carton, container, accuracy) | price_fix | Fix the operational cause (prep, carton size or labelling) and dispute fees charged in error | Routing and prep requirements, shipment records |
| COOP | coop_review | Compare charges with the co-op agreement and its sales impact | Co-op agreement, funding type |
| PROVISION | none | No action; explain it is an accounting provision | - |

Priority: high if the amount is above 10,000 USD, medium above 1,000 USD, otherwise low.
For an ASIN with repeated shortages, also recommend fixing the root cause (receiving, carton labelling, ASN accuracy).

Dispute deadlines depend on the vendor's Amazon terms and are not in the data. Tell the user to confirm the
window in Vendor Central; never state a number of days.

## 4. Propose, then confirm
Show a short table: entity, amount (positive dollars), action_type, priority, evidence list.
Ask the user to confirm. Only after an explicit yes, call CreateActionItem (or AcceptRecommendation) with
p_notes summarising the play and the evidence to gather. Report the returned action item id.
