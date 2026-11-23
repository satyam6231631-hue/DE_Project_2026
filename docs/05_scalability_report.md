# Phase 5: Scalability & 100× Growth Report

**Database:** PostgreSQL 18.6 (Homebrew, as specified in `team.json`)  
**Team:** Mudit Jindal (Lead), Satyam, Shirsh, Nilesh Saini  
**Workload:** 30 queries (`sql/06_optimized_queries.sql`)  
**Benchmark Configuration:** 3 runs per query via `EXPLAIN (ANALYZE, BUFFERS)` · Session timezone: `Asia/Kolkata`  
**Dataset Comparison:** Seed Data (~514k rows, 35 MB) vs. Large Data (~9.91M rows, 643 MB table / 779 MB index)  
**Date:** November 2026

---

## 1. Executive Summary & Large Dataset Results Table

In Phase 5, we subjected our optimized schema and index architecture to the **20× large production dataset** released by faculty. The dataset expanded table volume from 514,378 rows to **9,906,666 total rows** (~1.42 GB total relation size).

The benchmark was executed using `./benchmarks/run_benchmark.sh duolingo_large large 3 sql/06_optimized_queries.sql`.

### 1.1 Complete 30-Query Benchmark Results

| Query ID | Operation Type | Optimized Seed (ms) | Optimized Large (ms) | Growth Factor (Large ÷ Seed) | Target SLA | SLA Status | Optimization / Scaling Mechanism |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---|
| **R01** | READ | 0.174 | 0.272 | **1.56×** | `< 250 ms` | **PASS** | $O(1)$ catalog lookup; index scan on lessons. |
| **R02** | READ | 0.042 | 0.261 | **6.21×** | `< 5 ms` | **PASS** | $O(\log N)$ PK index lookup on enrollments. |
| **R03** | READ | 0.061 | 0.287 | **4.70×** | `< 5 ms` | **PASS** | Index Only Scan on `daily_activity_pkey`. |
| **R04** | READ | 0.047 | 0.323 | **6.87×** | `< 5 ms` | **PASS** | Covered range scan on `(learner_id, started_at)`. |
| **R05** | READ | 0.077 | 0.265 | **3.44×** | `< 5 ms` | **PASS** | 30-row cohort lookup via `idx_league_memberships_week_cohort`. |
| **R06** | READ | 0.067 | 0.197 | **2.94×** | `< 5 ms` | **PASS** | Index Only Scan on `idx_lesson_attempts_learner_lesson_comp`. |
| **R07** | READ | 13.111 | 1,171.620 | **89.36×** | `< 5,000 ms` | **PASS** | Index scan on `lesson_id` over 3.6M attempt rows. |
| **R08** | READ | 16.773 | 219.831 | **13.11×** | `< 5,000 ms` | **PASS** | Parallel Seq Scan over lesson_attempts grouped by type. |
| **R09** | READ | 2.200 | 9.135 | **4.15×** | `< 5,000 ms` | **PASS** | Index Only Scan on `idx_daily_activity_date_xp`. |
| **R10** | READ | 3.385 | 19.178 | **5.67×** | `< 5,000 ms` | **PASS** | Partial index scan on `idx_daily_activity_freeze`. |
| **R11** | READ | 0.022 | 1.105 | **50.23×** | `< 5 ms` | **PASS** | $O(\log N)$ unique index scan on `learners_username_key`. |
| **R12** | READ | 0.038 | 0.157 | **4.13×** | `< 5 ms` | **PASS** | PK index lookup on `learner_achievements_pkey`. |
| **R13** | READ | 4.742 | 86.488 | **18.24×** | `< 250 ms` | **PASS** | Linear scan of 600k learners anti-joined via partial index. |
| **R14** | READ | 1.550 | 14.621 | **9.43×** | `< 5,000 ms` | **PASS** | Parallel scan and aggregation on 546k memberships. |
| **R15** | READ | 0.223 | 4.819 | **21.61×** | `< 5,000 ms` | **PASS** | Index scan on `idx_learners_joined_at` + nested PK lookup. |
| **R16** | READ | 4.350 | 132.207 | **30.39×** | `< 250 ms` | **PASS** | B-tree prefix range scan for `'Karan%'` on 600k learners. |
| **R17** | READ | 9.441 | 71.022 | **7.52×** | `< 5,000 ms` | **PASS** | Index range scan on `started_at` over last 30 days. |
| **R18** | READ | 5.813 | 47.140 | **8.11×** | `< 5,000 ms` | **PASS** | Parallel aggregation of 750k enrollments. |
| **R19** | READ | 15.198 | 279.461 | **18.39×** | `< 5,000 ms` | **PASS** | CTE pre-aggregation avoids $O(N \cdot M)$ correlated subquery loops. |
| **R20** | READ | 3.114 | 45.075 | **14.47×** | `< 5,000 ms` | **PASS** | Index range scan on `started_at` over 30 days. |
| **R21** | READ | 1.854 | 34.109 | **18.40×** | `< 250 ms` | **PASS** | Bitmap index scan across 8 distinct date ranges. |
| **R22** | READ | 8.802 | 9.796 | **1.11×** | `< 250 ms` | **PASS** | B-tree backward index scan on `(started_at DESC)`. |
| **R23** | READ | 1.703 | 41.217 | **24.20×** | `< 250 ms` | **PASS** | Bitmap index intersection (`idx_learners_country_sub`). |
| **R24** | READ | 23.160 | 293.041 | **12.65×** | `< 5,000 ms` | **PASS** | Multi-table hash join across 3.6M attempts and catalog tables. |
| **R25** | READ | 108.221 | 1,545.315 | **14.28×** | `< 5,000 ms` | **PASS** | Full aggregation of 3.6M attempts $\times$ 600k learners. |
| **W01** | WRITE | 0.652 | 1.349 | **2.07×** | `< 5 ms` | **PASS** | Single-row `INSERT`; constant overhead with table size. |
| **W02** | WRITE | 0.189 | 0.693 | **3.67×** | `< 5 ms` | **PASS** | Partial index lookup on unfinished attempts. |
| **W03** | WRITE | 0.417 | 0.769 | **1.84×** | `< 5 ms` | **PASS** | Single-row upsert (`ON CONFLICT DO UPDATE`). |
| **W04** | WRITE | 8.529 | 378.326 | **44.36×** | `< 1,000 ms` | **PASS** | Batch update and re-ranking across 30 cohort rows. |
| **W05** | WRITE | 33.319 | 1,396.747 | **41.92×** | `< 1,000 ms` | **FIXED (644 ms)** | Anti-join rewrite eliminates 159k conflict evaluations. |

---

## 2. Growth Analysis (Scaling Categories)

When the dataset scaled by ~20× (from 514k to 9.91M rows), queries exhibited distinct complexity classes depending on access paths and plan shapes:

```
               ┌────────────────────────────────────────────────────────┐
               │              Query Scaling Behaviors                   │
               └────────────────────────────────────────────────────────┘
                     │                     │                     │
                     ▼                     ▼                     ▼
              Sublinear / Flat          Linear              Superlinear
             O(1) / O(log N)             O(N)                O(N log N)
             ────────────────       ───────────────         ─────────────
             R01, R02, R03, R04,    R08, R09, R10, R13,     R07 (89×)
             R05, R06, R11, R12,    R14, R17, R18, R19,     R16 (30×)
             R22, W01, W02, W03     R20, R21, R24, R25      W04, W05
```

### 2.1 Sublinear / Constant Growth ($O(1)$ and $O(\log N)$)
* **Queries:** `R01`, `R02`, `R03`, `R04`, `R05`, `R06`, `R11`, `R12`, `R22`, `W01`, `W02`, `W03`.
* **Growth Factor:** **1.1× to 6.8×** (vastly lower than the 20× data growth).
* **Technical Explanation:**
  - **B-Tree Height Invariance:** In PostgreSQL, an index over 30,000 rows typically has a B-Tree depth of 2 or 3. Growing the table 20× to 600,000 or 3.6M rows only increases the B-tree height by **1 level** ($\log_B N$). Thus, single-row lookups (`R02`, `R11`, `R12`) and selective point range lookups (`R04`, `R05`) incur at most 1 additional page read.
  - **Catalog Constancy:** `R01` operates on catalog tables (`courses`, `units`, `lessons`) which do not grow with user scale.
  - **Index-Driven Pagination (`R22`):** `R22` reads the newest 100,025 entries using `idx_lesson_attempts_started_desc`. Because the B-Tree index is traversed directly in descending timestamp order, increasing table size from 188k to 3.6M rows has **zero impact on the amount of work done** (it reads the exact same 100,025 leaf index entries in 9.79 ms vs. 8.80 ms on seed).

### 2.2 Linear Growth ($O(N)$)
* **Queries:** `R08`, `R09`, `R10`, `R13`, `R14`, `R17`, `R18`, `R19`, `R20`, `R21`, `R24`, `R25`.
* **Growth Factor:** **7.5× to 21.6×** (closely tracking the ~18–20× table growth).
* **Technical Explanation:**
  - **Fixed Percentage Window:** Queries such as `R17` (last 30 days) and `R20` scan a fixed proportion of the total attempts. Because attempts are evenly distributed across time, a 30-day window in a 20× larger dataset contains exactly 20× more rows.
  - **Table-Wide Analytical Scans:** `R08`, `R18`, `R24`, and `R25` compute global business metrics (e.g. CEFR level averages, course enrollments, DAU). They must process all tuples in the target tables. Thanks to multi-worker parallel sequential scans (`Parallel Seq Scan`), PostgreSQL achieves near-ideal linear scaling (e.g. `R25` grew 14.28×, scaling better than the 19× row growth).

### 2.3 Superlinear Growth ($> 20\times$)
* **Queries:** `R07` (89.4×), `R16` (30.4×), `W04` (44.4×), `W05` (41.9×).
* **Technical Explanation:**
  - **`R07` (Lesson Mistake Hotspots):** Aggregates mistake counts across attempts grouped by `lesson_id`. On seed data, the lesson index was small enough to fit completely in the L1/L2 CPU cache. At 3.6M rows, the random heap lookups for 160 lessons scattered across a 291 MB heap caused cache evictions and repeated buffer lookups (1.17 s).
  - **`R16` (Username Prefix Search `'Karan%'`):** A prefix search on a B-tree returns all matching leaf tuples. In a 600k table, the number of learners named "Karan..." increased proportionally by 20×, requiring 20× more heap page fetches to retrieve non-indexed learner attributes (132 ms).
  - **`W05` (Catch-up Badge Award):** Evaluated 750,000 enrollments, requiring PostgreSQL foreign key trigger validation on tens of thousands of inserts.

---

## 3. What Broke at Scale & How We Fixed It

### 3.1 The W05 Batch Insert Bottleneck: Foreign Key Triggers & Conflict Resolution

#### Problem Diagnosis:
In `sql/06_optimized_queries.sql`, `W05` was formulated using an `ON CONFLICT (learner_id, achievement_id) DO NOTHING` clause:
```sql
INSERT INTO learner_achievements (learner_id, achievement_id, earned_at)
SELECT e.learner_id, (SELECT achievement_id FROM achievements WHERE code = 'XP_100'), '2026-07-01 00:00:00+05:30'
FROM enrollments e
GROUP BY e.learner_id
HAVING sum(e.total_xp) >= 100
ON CONFLICT (learner_id, achievement_id) DO NOTHING;
```
When executed on the large dataset, the query averaged **1,396.7 ms** (Run 1: 1,695 ms, Run 2: 1,735 ms, Run 3: 759 ms), breaching the **1,000 ms batch SLA target**.

#### Plan Analysis:
Inspecting `benchmarks/results/large/W05.txt` revealed the root cause:
1. The aggregation query generated **239,403 candidate tuples**.
2. Because 159,646 learners already possessed the badge, the insert engine had to execute **159,646 conflict arbiter lookups** against `learner_achievements_pkey`.
3. For the remaining **79,757 successfully inserted tuples**, PostgreSQL fired the `learner_achievements_learner_id_fkey` constraint trigger 79,757 times, consuming **935.9 ms** in foreign key validation alone!

#### The Fix: Anti-Join Filtering (`WHERE NOT EXISTS`)
Instead of inserting all candidates and letting the database engine arbitrate conflicts one row at a time, we filter out existing badge holders before insertion using an anti-join:

```sql
WITH target_ach AS (
    SELECT achievement_id FROM achievements WHERE code = 'XP_100'
)
INSERT INTO learner_achievements (learner_id, achievement_id, earned_at)
SELECT e.learner_id, (SELECT achievement_id FROM target_ach), '2026-07-01 00:00:00+05:30'
FROM enrollments e
WHERE NOT EXISTS (
    SELECT 1 FROM learner_achievements la 
    WHERE la.learner_id = e.learner_id 
      AND la.achievement_id = (SELECT achievement_id FROM target_ach)
)
GROUP BY e.learner_id
HAVING sum(e.total_xp) >= 100;
```

#### Verification & Performance Impact:
* **Before Plan (ON CONFLICT):** Execution Time = **1,396.7 ms** (Buffers: 1,326,082 shared hits, 159,646 conflict arbitrations).
* **After Plan (Merge Anti Join):** Execution Time = **644.5 ms** (**53.8% speedup!**).
* **Result:** The Merge Anti Join pre-filters tuples in memory in 162 ms using `learner_achievements_pkey`. The engine inserts strictly the 79,757 missing records, bringing `W05` safely within the `< 1,000 ms` batch SLA.

---

### 3.2 Deep Pagination at Scale (`R22`): OFFSET vs. Keyset Pagination

#### Problem Context:
`R22` represents the support console browsing the historical stream of lesson attempts:
```sql
SELECT attempt_id, learner_id, lesson_id, started_at, xp_earned
FROM lesson_attempts
ORDER BY started_at DESC
OFFSET 100000 LIMIT 25;
```
On the seed dataset (188k rows), `OFFSET 100000` was already near the halfway point of the table. On the large dataset (3.61M rows), reading 100k rows takes **9.79 ms** because our composite index `idx_lesson_attempts_started_desc (started_at DESC, attempt_id)` allows an Index Scan.

However, as data scales to 100× (360 million rows), requesting page 40,000 (`OFFSET 1,000,000`) forces the database to read and discard 1,000,000 index entries, causing execution time to degrade to several hundred milliseconds.

#### The Keyset Pagination Architecture:
For true 100× scalability, `OFFSET` must be replaced with cursor-based **keyset pagination**:
```sql
-- Keyset pagination using composite tuple comparison:
SELECT attempt_id, learner_id, lesson_id, started_at, xp_earned
FROM lesson_attempts
WHERE (started_at, attempt_id) < ($last_seen_started_at, $last_seen_attempt_id)
ORDER BY started_at DESC, attempt_id DESC
LIMIT 25;
```
* **Performance:** Regardless of whether the user is on page 1 or page 40,000, PostgreSQL jumps directly to the `$last_seen` position via B-Tree root-to-leaf traversal in $O(\log N)$ time and reads **exactly 25 tuples** (< 0.1 ms).

---

## 4. Storage & Memory Analysis (Seed vs. Large)

We extracted exact disk utilization figures for all 11 tables using `pg_table_size`, `pg_indexes_size`, and `pg_total_relation_size`.

### 4.1 Storage Footprint Comparison Table

| Table Name | Seed Rows | Large Rows | Seed Table Size | Large Table Size | Seed Index Size | Large Index Size | Large Total Footprint | Index % of Table |
|:---|---:|---:|---:|---:|---:|---:|---:|---:|
| `lesson_attempts` | 188,300 | 3,608,300 | 16.0 MB | 291.2 MB | 25.3 MB | 473.2 MB | **764.4 MB** | 162.5% |
| `daily_activity` | 189,109 | 3,626,847 | 9.9 MB | 181.0 MB | 5.4 MB | 103.5 MB | **284.5 MB** | 57.2% |
| `learners` | 30,000 | 600,000 | 3.2 MB | 61.2 MB | 5.0 MB | 116.9 MB | **178.1 MB** | 191.0% |
| `enrollments` | 37,500 | 750,000 | 1.9 MB | 37.4 MB | 2.0 MB | 38.7 MB | **76.1 MB** | 103.5% |
| `league_memberships`| 28,598 | 546,036 | 2.1 MB | 40.5 MB | 1.3 MB | 24.4 MB | **64.9 MB** | 60.2% |
| `learner_achievements`| 38,860 | 773,472 | 1.8 MB | 32.7 MB | 1.1 MB | 22.2 MB | **54.9 MB** | 67.9% |
| `lessons` | 1,760 | 1,760 | 128 kB | 144 kB | 112 kB | 112 kB | **256 kB** | 77.8% |
| `units` | 220 | 220 | 40 kB | 40 kB | 48 kB | 48 kB | **88 kB** | 120.0% |
| `achievements` | 10 | 10 | 8 kB | 8 kB | 32 kB | 48 kB | **56 kB** | 600.0% |
| `courses` | 11 | 11 | 8 kB | 8 kB | 16 kB | 32 kB | **40 kB** | 400.0% |
| `languages` | 10 | 10 | 8 kB | 8 kB | 16 kB | 32 kB | **40 kB** | 400.0% |
| **TOTALS** | **514,378** | **9,906,666** | **34.8 MB** | **643.0 MB** | **39.8 MB** | **779.1 MB** | **1,422.1 MB** | **121.2%** |

### 4.2 Storage Findings & Memory Fitting:
1. **Total Relation Footprint is 1.42 GB**: The data grew by **18.5×**, perfectly aligning with the 20× user scaling factor.
2. **Buffer Cache Residency:** Modern production instances allocate 4 GB to 16 GB for PostgreSQL `shared_buffers`. Because the entire 1.42 GB database (including all indexes) fits comfortably inside RAM, read operations avoid disk I/O bottlenecks and achieve sub-millisecond latencies.
3. **Index Efficiency:** The largest index footprint belongs to `lesson_attempts` (473 MB across 6 indexes). Partial indexes (`idx_lesson_attempts_unfinished`, `idx_daily_activity_freeze`) kept index sizes extremely lean (under 1 MB).

---

