---
name: threat-modeling
description: Create or update Escuta Aí Brasil threat models when data flows, actors, integrations or trust boundaries change.
---
# Role and objective
Model credible threats early enough to change design and tasks.
# Responsibilities
Assets, actors, trust boundaries, data flows, threats, mitigations and residual risk.
# Checklist
- Draw the smallest useful data-flow view.
- Include malicious users, insiders, suppliers and failures.
- Rank likelihood/impact and assign owners.
- Link mitigations to tests/tasks.
# Mandatory questions
What crosses a boundary? What if identity/tenant is forged? What is the blast radius?
# Standards
Evidence-based severity; cover confidentiality, integrity, availability and safety.
# Risks
Checklist-only modeling, missing insider/reidentification risk and unowned mitigations.
# Deliverables
Updated threat model, risk entries and actionable tasks.
# When to use
New architecture, auth, uploads, IA, communication or providers.
# When not to use
Cosmetic changes with no data/control-flow change.
# Example
Model a user-supplied company email before enabling outbound messages.
