# Keep raw diagnostic logs separate from diagnostic reports

## Status

Accepted.

The diagnostic log view may expose raw wrapper `agent.log` text and raw GUI event detail only through an explicit view/copy action, while a diagnostic report is built exclusively from safe diagnostic facts and allowlisted, field-cleaned event projections. Reports never include raw logs, the configuration catalog, server addresses or remarks, credential references, URLs or tokens, runtime JSON, paths, or free-form failure detail. This preserves useful local troubleshooting without turning user-shared export files into an uncontrolled disclosure channel.

## Considered options

- Include the raw log tail in the exported report: rejected because wrapper output and future event details are not guaranteed to satisfy the report's sensitive-information policy.
- Remove raw log viewing entirely: rejected because explicit local viewing and copying is useful for troubleshooting and is a narrower exposure than an exported report.

## Consequences

- Diagnostics must maintain separate raw-log and safe-report projections.
- Adding a new event field does not automatically make it eligible for export; the report allowlist must be updated deliberately.
- Export completion is recorded only after the user-selected report file is successfully written.
