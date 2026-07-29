# Lessons

Things that went wrong, what they cost, and what changed as a result.
Kept because debugging judgement is the part of this work that transfers.

---

## Phase 0 — Foundation

**One browser profile, one identity.** Roughly 45 minutes were lost to an
`AADSTS16000` authentication loop: the Entra portal kept resolving sign-in
against the wrong tenant context because several Microsoft accounts shared
one browser profile. Every authentication failure in this phase traced back
to that. A dedicated browser profile should have been the first action taken,
not the fourth.

**Free is not the same as permitted.** Two Fabric environments were
immediately available, both belonging to clients. Using either would have
consumed client capacity, written to their audit logs under a shared service
account, and in one case burned a one-time trial capacity the client may
later need. The cost of building an independent tenant was zero dollars and
about an hour. Convenience is not authorisation.

**Rule out dead ends early.** The Microsoft 365 Developer Program was the
obvious route to a free tenant and no longer qualifies without a Visual
Studio subscription. Checking that first saved pursuing it.

**Shells are not interchangeable.** Directory-creation commands failed
because `cmd` syntax was run in PowerShell. The VS Code integrated terminal
is PowerShell by default. `git` behaves identically in both, which makes the
difference easy to forget.

**Read the release page, not the version number.** Python 3.12.13 is the
latest 3.12 patch and ships no Windows installer — it is source-only.
3.12.10 is the last release with binaries.

---

## Phase 1 — Bronze profiling

**Rate, not count.** The first zone breakdown ranked by raw count and
returned the busiest Manhattan zones — a volume ranking wearing a
quality-analysis costume. Ranking by percentage revealed a 40x spread across
zones, which is the actual finding. Count answers "where is the volume".
Only rate answers "where is the problem".

**Means lie on skewed data.** Mean trip distance of 11.69 mi versus 3.39 mi
suggested the null block was long airport runs. Percentiles showed the
opposite: shorter at p90 and p99, with the mean dragged up by rows recording
312,722 miles. The capped mean was 2.85 versus 3.39 for normal rows — the
null-block trips are *shorter*, not longer. The outliers had reversed the
direction of the finding, not merely exaggerated it.

**122 rows out of 9,554,778.** That is 0.0013% of the dataset, and it was
enough to distort the mean 4.1x and send three hypotheses in the wrong
direction. Check the distribution before building a rule on the average.

**Test the hypothesis before writing the rule.** Vendor-specific and
airport-related explanations were both plausible and both wrong. Had either
been accepted, the Silver layer would now encode a false assumption — and it
would have looked correct, because the rule would have been consistent with
the (misleading) mean that produced it.

**Geography can falsify a hypothesis outright.** Several dropoff zones showed
a 24-mile average inside an island 13 miles long. That is not a weak signal
or a matter of interpretation; it is impossible, and it killed the airport
hypothesis faster than any statistical test would have.

**Filenames are not partitions.** The March file contains April rows and rows
dated 2002, 2008 and 2009. Partitioning by source filename would have routed
data into the wrong period silently — the kind of error that surfaces months
later as an unexplained variance in a finance report.

**Save before running.** Twenty minutes were spent debugging a script that
had not been written to disk. The old version ran perfectly.

**Idempotence is cheap if built in first.** Adding an existence check to the
download script took one line and made every subsequent re-run safe. Adding
it after a partial download would have meant reasoning about which files were
complete.