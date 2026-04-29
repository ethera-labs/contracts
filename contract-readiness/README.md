# Santander Contract Readiness

This folder tracks the contract-side work needed to move the Santander PoC toward production readiness.

The source notes were copied from `002-ethera` research folder so they can be reviewed and updated inside `ethera-contracts`.

## Files

- [contracts/contract-production-readiness.md](contracts/contract-production-readiness.md) - prioritized readiness backlog
- [security/solidity-auditor-report.md](security/solidity-auditor-report.md) - original AI-assisted Solidity audit report
- [security/solidity-auditor-triage.md](security/solidity-auditor-triage.md) - manual triage of the audit report
- [overview/current-state.md](overview/current-state.md) - current project state and context

## Workflow

Use this branch for review and planning. The intended flow is:

1. Review and adjust the tasks.
2. Keep `develop` as the progress-tracking branch once the team confirms it can be used for this purpose.
3. For each implementation PR, mark the related task as done when the PR is merged to `develop`.
