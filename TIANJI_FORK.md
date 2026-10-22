# TianJi OpenProject Source Fork

## Purpose

This branch records TianJi-specific OpenProject source changes in the
`liugang926/openproject` fork. Production continues to use the pinned upstream
image until the research plugin is separately reviewed and approved.

## Provenance

- Upstream repository: `https://github.com/opf/openproject`
- Verified fork: `https://github.com/liugang926/openproject`
- Production baseline: `v17.9.2`
- Baseline commit: `a87c835d12d337bf1402e4e822fd57042f7510ef`
- TianJi branch: `tianji/17.9.2`

The fork keeps the upstream commit history. Changes must remain traceable to a
commit on the TianJi branch and must not be represented as an upstream release
or as an approved production deployment.

## Current change set

The branch imports, without deployment changes, the unapproved research
candidate under:

`plugins/openproject-tianji-workflow-guard/`

The candidate is intentionally fail-closed. Its entry point and Rails engine
raise `TIANJI_RESEARCH_CANDIDATE_NOT_APPROVED_FOR_LOADING`. It must not be added
to a production `Gemfile`, image, or deployment manifest before a separately
approved PRD exception and verification.

## Ownership and review

- Source maintainer: TianJi DevOps
- Upstream compatibility baseline: OpenProject `17.9.2`
- Required review before any production use: application security, platform
  owner, and the business process owner
- Required tests before any production use: isolated Ruby policy tests, real
  OpenProject contract/service tests, and an approved production-like E2E
- Exit condition: move the behavior to an officially supported extension point
  or remove the patch when the upstream baseline changes or the exception
  expires

## Safety boundary

This branch does not include credentials, production configuration, runtime
secrets, customer data, workflow records, or deployment cutover instructions.
The production image digest and deployment manifests remain unchanged.

## Local verification limitation

The source workbench used for this import does not provide Ruby or Bundler.
Ruby tests therefore must run in a dedicated OpenProject build/test environment
before the candidate is considered for approval.
