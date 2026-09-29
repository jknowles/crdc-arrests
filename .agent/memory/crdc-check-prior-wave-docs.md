---
name: crdc-check-prior-wave-docs
description: "Before calling a CRDC data pattern \"new\", compare against the prior wave's User's Manual, Appendix Workbook and school form"
metadata:
  node_type: memory
  type: feedback
  originSessionId: e3b91a8f-0cd2-4067-a12f-4f5da848c38e
  modified: 2026-09-29T14:26:35.045Z
---

Before claiming a CRDC wave changed its coding (reserve codes, skip logic, items), check the prior wave's documentation, not just the data.

**Why:** In the 2023-24 scoping (2026-09-29) I called the flood of `-9` codes in Referrals and Arrests a "new skip pattern / methods change". Jared pushed back that `-9` skip logic was documented in earlier waves. The docs showed he was right: `-9` and the tool's NA autofill are documented in both waves. What actually changed was that ARRS-1/ARRS-4 instance items went from optional (restricted-use only) to required, so the autofill fired far more often. I also over-counted "inconsistent" schools by testing only the male total column.

**How to apply:** For each wave, diff the Appendix Workbook sheet B (Optional/Required, Availability columns) and the school form module text before characterizing a change. Test consistency across all disaggregated cells, not a single `TOT_` column (calculated totals take the most negative reserve code when every cell is reserved). Docs live at `/mnt/smb/civilytics/datasets/ED/CRDC/<year>-crdc-data/`; forms can be fetched from `civilrightsdata.ed.gov/assets/downloads/<year>-crdc-school-form.pdf`. See [[crdc-nyc-missing-from-models]].
