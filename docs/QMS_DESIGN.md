# QMS and SOP document-control design

Redmine+DMSF can provide versioned documents, permissions, configurable approval workflows, locks, activity/audit information, and historical revisions. It does **not** by itself certify a QMS or guarantee compliance with a regulation. Validate configured behavior against the organization's procedures and applicable requirements.

## Information architecture

Create a dedicated private `QMS` project with DMSF enabled and a controlled folder taxonomy:

```text
QMS/
├── Policies/
├── SOPs/
│   ├── IT/
│   ├── HR/
│   ├── Finance/
│   └── Operations/
├── Work Instructions/
├── Forms/
└── Superseded/
```

Use DMSF custom fields/tags and naming conventions for:

| Field | Example / rule |
|---|---|
| Document ID | `SOP-IT-001`, unique and immutable |
| Title | User Access Management Procedure |
| Department | IT (controlled list) |
| Owner | IT Manager |
| Version | 1.0; DMSF revision is the authoritative stored revision |
| Status | Draft / In Review / Approved / Effective / Superseded / Archived |
| Reviewer | Security Manager |
| Approver | CTO |
| Approval Date | system/workflow evidence plus controlled metadata |
| Effective Date | ISO date, not before approval |
| Next Review Date | ISO date; drives a scheduled review query |
| Classification | Public / Internal / Confidential / Restricted |

Avoid relying only on editable file contents for control metadata. Maintain an approved document register (a Redmine issue/query or externally controlled register) keyed by Document ID and linked to the exact DMSF revision.

## Lifecycle

```text
Draft → Review → Approval → Effective/Published → Locked
  ↑         ↘ rejected to Draft              |
  └──────── new revision request ←────────────┘
                         ↓
              Superseded / Archived
```

1. Author creates a draft with required metadata and a revision comment.
2. Reviewer verifies technical/process content and records approve/reject through a named DMSF workflow step.
3. Approver independently authorizes the exact revision.
4. Document Controller confirms metadata/effective date, publishes to the approved area, and locks the approved revision.
5. Department Users receive read-only access to effective documents.
6. Change begins as a new revision/draft; never unlock and silently replace the effective file. The former effective revision remains in history and is marked/moved as superseded according to the controlled procedure.
7. Periodic queries identify approaching review dates; the owner records review outcome even when no content change is required.

Configure and test whether DMSF workflow completion itself applies the desired lock. If not, make lock/publish a mandatory Document Controller step and audit it. Folder movement alone is not approval evidence.

## Proposed RBAC

| Role | Intended access |
|---|---|
| Document Author | Create/edit draft and submit; no approval or destructive history changes |
| Reviewer | Read drafts, comment, review/reject; no final approval unless separately authorized |
| Approver | Read and approve/reject exact revision; no routine draft editing |
| Document Controller | Manage metadata, versions, workflow templates, locks, publishing and superseding |
| Department User | Read/download only approved/effective documents for authorized department |
| Auditor | Read documents, revisions, workflow/audit history and registers; no changes |
| Administrator | Technical administration; not automatically a business approver |

Use separate accounts, deny anonymous access, minimize delete/permanent-delete permissions, and test every role with representative users. Segregate Reviewer and Approver where policy requires independence. Administrative capability can bypass application controls, so audit and tightly limit administrators.

## Evidence and review

For every controlled document, demonstrate who created each revision, who reviewed and approved it, timestamps, the exact effective revision, replacement/supersession date, authorized readers, previous versions, and lock/change history. Periodically export/review user-role membership and perform restore tests so evidence remains available after a failure.

## Known gaps requiring separate evaluation

- regulated/formal electronic signatures and identity re-authentication at signature;
- employee “read and understood” acknowledgements and overdue escalation;
- training assignment, competency, and training records;
- advanced CAPA, nonconformance, risk, and validation workflows;
- immutable/WORM audit storage, legal retention holds, and independent audit-log export;
- malware/DLP controls and document classification enforcement;
- regulation-specific validation, reporting, and record-retention controls.

Address gaps with controlled procedures or purpose-built validated systems after a formal requirements/risk assessment. Do not describe this deployment as regulatory certification.
