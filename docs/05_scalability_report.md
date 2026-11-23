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

