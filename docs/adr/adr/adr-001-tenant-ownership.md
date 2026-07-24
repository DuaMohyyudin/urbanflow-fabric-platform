# ADR-001: Build on an independent tenant

**Status:** Accepted · **Date:** 2026-07-24

## Context
Two Fabric environments were immediately available, both belonging to
clients. A third option was the employer's internal tenant.

## Options
1. Client tenant — free, instant, no admin rights
2. Employer tenant — free, requires approval, no admin rights
3. Independent tenant — $0, ~1 hour setup, full Global Administrator

## Decision
Option 3.

## Consequences
- Positive: admin portal, tenant settings, capacity settings, OneLake
  access roles are all reachable. Roughly half of DP-600 and DP-700
  cannot be demonstrated without them.
- Positive: artefacts survive employment changes and trial expiry.
- Negative: no pre-provisioned licences; every capability must be
  configured from zero. This is a cost in time and a gain in learning.
- Rejected 1 and 2 because portfolio work consuming client capacity and
  appearing in client audit logs is not authorised, regardless of price.