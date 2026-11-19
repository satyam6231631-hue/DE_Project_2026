# Phase 4: Query Optimization & Benchmarking Report (CP3)

**Project:** Duolingo Language Learning Database  
**Team:** Mudit Jindal (Lead), Satyam, Shirsh, Nilesh Saini  
**Author / Deliverable Owner:** Nilesh Saini (Track 3: Benchmark Execution & Optimization Report)  
**Co-Contributors:** Satyam (Track 1: Index Architecture & Storage), Shirsh (Track 2: Query Refactoring & Verification)  
**Database:** PostgreSQL 18.6 (Postgres.app) · **Hardware:** MacBook Pro M4 (as specified in `team.json`)  
**Workload:** 30 queries (`sql/06_optimized_queries.sql`) · **Method:** 5 runs per query via `EXPLAIN (ANALYZE, BUFFERS)` · Session timezone: Asia/Kolkata  
**Date:** November 2026

---

## 1. Executive Summary

In Phase 4 (Checkpoint 3), the team targeted the critical latency hotspots, sequential table scans, and correctness issues uncovered during baseline profiling (Phase 3). By combining a targeted **secondary and composite index architecture** (`sql/05_indexes.sql`), **query refactoring** to eliminate correlated subquery loops and non-sargable predicates (`sql/06_optimized_queries.sql`), and fixing a critical **three-valued SQL logic bug** in `R13`, we achieved massive performance gains across the Duolingo workload.

### Key Milestones & Results:
- **Total Workload Execution Time:** Dropped from **1,757.466 ms** to **267.274 ms**, achieving an overall platform latency reduction of **84.79%** (saving **~1.49 seconds** per workload execution cycle).
- **The R19 Bottleneck Smashed:** The worst query in the system dropped from **1,437.911 ms** to **15.198 ms** — a **98.94% reduction** (**94.6× speedup**) — by eliminating 320 repeated full sequential scans over 188,300 attempts through CTE pre-aggregation.
- **Strict Real-Time SLAs Met (< 5.0 ms):** Customer-facing queries `R04` (daily goal ring) improved from **5.315 ms** to **0.047 ms** (**99.12% speedup**), and `R06` ("Start" button next lesson) improved from **5.805 ms** to **0.067 ms** (**98.85% speedup**), bringing 100% of learner-facing queries well within the strict 5.0 ms SLA.
- **Deep Pagination Accelerated:** `R22` (Support console page 4,001 at OFFSET 100,000) dropped from **30.842 ms** to **8.802 ms** (**71.46% speedup**), eliminating a 7 MB external merge sort spill to temporary disk.
- **R13 Correctness Bug Resolved:** Replaced `NOT IN` with `NOT EXISTS` to bypass the 21,102 NULL trap, transforming the result set from **0 incorrect rows** to **24,268 correct learners** who have not yet referred anyone.
- **Write Overhead Held Minimal:** Real-time transactional writes `W01`, `W02`, and `W03` all execute in **< 0.66 ms** despite maintaining secondary indexes. `W02` actually sped up by **71.96%** due to a partial index on unfinished attempts.

---

## 2. Complete 30-Query Before vs. After Optimization Table

Timings reflect the mean execution time across benchmark runs (3 runs for baseline, 5 runs for optimized).  
$$\text{Improvement \%} = \frac{\text{Baseline (ms)} - \text{Optimized (ms)}}{\text{Baseline (ms)}} \times 100$$

| SQL Query | Type | Baseline (ms) | Optimized (ms) | Improvement % | Primary Bottleneck Identified | Optimization Applied | Same Result? |
|:---|:---:|---:|---:|:---:|:---|:---|:---:|
| **R01**: Course path: Spanish units & lessons in order | READ | 0.135 | 0.174 | -28.89% | Small catalog tables; already sub-millisecond | Preserved; slight runtime jitter (+0.039 ms) | ✅ |
| **R02**: Home screen: learner 1042's courses with total XP | READ | 0.040 | 0.042 | -5.00% | Single-row PK lookup; already optimal | Preserved; runtime jitter (+0.002 ms) | ✅ |
| **R03**: Streak counter: learner 1042's streak up to 30 June | READ | 0.088 | 0.061 | +30.68% | Daily activity lookup | Index Only Scan on `daily_activity_pkey` | ✅ |
| **R04**: Daily goal ring: XP learner 1042 earned on 30 June | READ | 5.315 | 0.047 | **+99.12%** | Non-sargable `DATE(started_at)` forced 188k Seq Scan | Sargable timestamp range + `idx_lesson_attempts_learner_started` | ✅ |
| **R05**: Leagues tab: leaderboard of learner 1042's cohort | READ | 0.899 | 0.077 | **+91.43%** | Seq Scan on 28k memberships + in-memory sort | Composite index `idx_league_memberships_week_cohort` with XP DESC | ✅ |
| **R06**: "Start" button: first unfinished lesson | READ | 5.805 | 0.067 | **+98.85%** | Seq Scan on 188k attempts checking completion | Partial index `idx_lesson_attempts_learner_lesson_comp` | ✅ |
| **R07**: Lessons with most mistakes per attempt | READ | 15.144 | 13.111 | +13.42% | Missing FK index on `lesson_attempts(lesson_id)` | Created FK B-Tree index `idx_lesson_attempts_lesson_id` | ✅ |
| **R08**: Quit rate per lesson type | READ | 19.401 | 16.773 | +13.55% | Aggregating all 188k rows by lesson type | Parallel Seq Scan optimal for entire dataset; minor I/O caching win | ✅ |
| **R09**: Daily active learners in June 2026 | READ | 6.536 | 2.200 | **+66.34%** | Full Seq Scan of 189,109 daily activity rows | Composite index `idx_daily_activity_date_xp (activity_date, xp)` | ✅ |
| **R10**: Streak freezes used per tier in 2026 | READ | 4.901 | 3.385 | +30.93% | Full Seq Scan of daily activity for sparse boolean | Partial index `idx_daily_activity_freeze` WHERE `used_streak_freeze = true` | ✅ |
| **R11**: Sign-in by username | READ | 0.025 | 0.022 | +12.00% | Single-row lookup via unique constraint | Optimal Index Scan on `learners_username_key` | ✅ |
| **R12**: Profile: learner 1042's achievements | READ | 0.050 | 0.038 | +24.00% | PK lookup on learner_achievements | Optimal Index Scan on `learner_achievements_pkey` | ✅ |
| **R13**: Referral programme: unreferred learners | READ | 4.642 | 4.742 | -2.15% | **Bug:** `NOT IN` returned 0 rows due to 21k NULLs | Rewrote to `NOT EXISTS` + index `idx_learners_referred_by` | ⚠️ **Fixed** (0 $\rightarrow$ 24,268) |
| **R14**: Promotion / demotion rates per tier | READ | 1.845 | 1.550 | +15.99% | Seq Scan on 28k league memberships | Composite index `idx_league_memberships_week_tier (week_start, tier)` | ✅ |
| **R15**: January cohort retention in June 2026 | READ | 1.886 | 0.223 | **+88.18%** | Seq Scan of 30,000 learners on joined_at | B-Tree index `idx_learners_joined_at` | ✅ |
| **R16**: Search learners by username prefix "Karan%" | READ | 4.619 | 4.350 | +5.82% | Prefix index range scan with heap fetches | Index scan on `learners_username_key` | ✅ |
| **R17**: Perfect-lesson rate per device in 2026 | READ | 14.515 | 9.441 | +34.96% | Full table scan on 188k attempts | Index scan on `idx_lesson_attempts_started_at` | ✅ |
| **R18**: Course popularity & 2026 enrollments | READ | 5.729 | 5.813 | -1.47% | Grouping entire 37.5k enrollments table | Sequential scan is cost-optimal for whole-table aggregation | ✅ |
| **R19**: Spanish course completions & avg mistakes | READ | 1437.911 | 15.198 | **+98.94%** | Correlated subquery loop scanning 188k rows 160× | Rewrote to CTE pre-aggregation + single hash join | ✅ |
| **R20**: Daily XP growth in June 2026 | READ | 8.585 | 3.114 | **+63.73%** | `started_at::date` disabled B-tree index | Sargable range `[2026-06-01, 2026-07-01)` + `idx_lesson_attempts_started_at` | ✅ |
| **R21**: Streak reminders: 7-day active learners | READ | 2.225 | 1.854 | +16.67% | Checking activity across multiple date ranges | Bitmap Index Scan on `idx_daily_activity_date_xp` | ✅ |
| **R22**: Support console pagination (page 4,001) | READ | 30.842 | 8.802 | **+71.46%** | High OFFSET sort spilled 7 MB to disk | B-Tree index `idx_lesson_attempts_started_at (started_at DESC)` eliminates sort | ✅ |
| **R23**: Super & Max active learners in India | READ | 5.907 | 1.703 | **+71.17%** | Dual Seq Scans on daily_activity and learners | Bitmap scan on `idx_daily_activity_date_xp` & `idx_learners_country_sub` | ✅ |
| **R24**: Average hearts lost per lesson by CEFR | READ | 22.503 | 23.160 | -2.92% | Full 3-table join across 100% of attempts | Seq Scan optimal; cost-based planner correctly avoids random I/O | ✅ |
| **R25**: Lessons started per hour per country | READ | 110.603 | 108.221 | +2.15% | Heavy two-table aggregation on 188k rows | Whole-table scan is optimal for processing 100% of rows | ✅ |
| **W01**: Lesson start: learner starts lesson 1 | WRITE | 0.757 | 0.652 | +13.87% | INSERT row into `lesson_attempts` | Fast B-tree page inserts (<0.66 ms) | ✅ |
| **W02**: Lesson end: finish recent unfinished attempt | WRITE | 0.674 | 0.189 | **+71.96%** | Finding latest unfinished attempt filtered 8.3k rows | Partial index `idx_lesson_attempts_unfinished` makes lookup instant | ✅ |
| **W03**: Daily activity: upsert 20 XP | WRITE | 0.436 | 0.417 | +4.36% | Upsert into daily_activity | PK index lookup + insert (<0.42 ms) | ✅ |
| **W04**: Weekly league close: rank & promote | WRITE | 5.763 | 8.529 | -48.00% | Batch UPDATE on 30 cohort rows | Updates indexed columns in `idx_league_memberships_week_cohort` (+2.76 ms) | ✅ |
| **W05**: Achievements catch-up: 100 XP badge | WRITE | 39.685 | 33.319 | +16.04% | Batch insert over enrollments & achievements | Faster candidate identification | ✅ |
| **TOTAL** | — | **1,757.466** | **267.274** | **+84.79%** | **Entire 30-query workload execution** | **Overall reduction of 1,490.192 ms** | ✅ |

---

## 3. Deep-Dive: Top 5 Execution Plan Improvements

### 3.1 Win #1: R19 — Spanish Curriculum Report (1,437.911 ms $\rightarrow$ 15.198 ms, 98.94% Speedup)

#### The Problem:
In the baseline query, two correlated subqueries appeared in the `SELECT` clause:
```sql
(SELECT count(*) FROM lesson_attempts a WHERE a.lesson_id = l.lesson_id AND a.completed_at IS NOT NULL) AS completions,
(SELECT round(avg(a.mistakes), 2) FROM lesson_attempts a WHERE a.lesson_id = l.lesson_id) AS avg_mistakes
```
Because `lesson_id` was unindexed and PostgreSQL executed each subquery for every Spanish lesson (160 lessons), it performed $160 \times 2 = 320$ full sequential scans over the 188,300-row `lesson_attempts` table. This generated **637,506 buffer hits** and consumed ~1.44 seconds.

#### The Query Rewrite:
We refactored `R19` in `sql/06_optimized_queries.sql` to pre-filter lessons belonging to Course 1 in a CTE and aggregate `lesson_attempts` grouped by `lesson_id` in a single pass before joining:
```sql
WITH course_lessons AS (
    SELECT l.lesson_id, u.unit_no, l.lesson_no
    FROM lessons l
    JOIN units u ON u.unit_id = l.unit_id
    WHERE u.course_id = 1
),
attempt_stats AS (
    SELECT a.lesson_id,
           count(*) FILTER (WHERE a.completed_at IS NOT NULL) AS completions,
           round(avg(a.mistakes), 2) AS avg_mistakes
    FROM lesson_attempts a
    JOIN course_lessons cl ON cl.lesson_id = a.lesson_id
    GROUP BY a.lesson_id
)
SELECT cl.lesson_id, cl.unit_no, cl.lesson_no,
       coalesce(s.completions, 0) AS completions,
       s.avg_mistakes
FROM course_lessons cl
LEFT JOIN attempt_stats s ON s.lesson_id = cl.lesson_id
ORDER BY cl.unit_no, cl.lesson_no;
```

#### Execution Plan Comparison:
**Baseline Plan (`benchmarks/results/baseline/R19.txt`):**
```
Incremental Sort  (cost=106986.67..1390823.90 rows=160 width=52) (actual time=296.352..1436.159 rows=160.00 loops=1)
  Sort Key: u.unit_no, l.lesson_no
  Buffers: shared hit=637506
  ->  Nested Loop  (cost=0.42..1390818.74 rows=160 width=52) (actual time=9.665..1436.068 rows=160.00 loops=1)
        SubPlan 1
          ->  Aggregate  (actual time=5.001..5.001 rows=1.00 loops=160)
                Buffers: shared hit=318720
                ->  Seq Scan on lesson_attempts a  (cost=0.00..4345.75 rows=95) (loops=160)
                      Filter: ((completed_at IS NOT NULL) AND (lesson_id = l.lesson_id))
                      Rows Removed by Filter: 188036
        SubPlan 2
          ->  Aggregate  (actual time=3.973..3.973 rows=1.00 loops=160)
                Buffers: shared hit=318720
                ->  Seq Scan on lesson_attempts a  (cost=0.00..4345.75 rows=95) (loops=160)
                      Filter: (lesson_id = l.lesson_id)
                      Rows Removed by Filter: 188036
Execution Time: 1436.567 ms
```

**Optimized Plan (`benchmarks/results/optimized/R19.txt`):**
```
Sort  (cost=4990.46..4990.86 rows=160 width=52) (actual time=15.393..15.397 rows=160.00 loops=1)
  Sort Key: cl.unit_no, cl.lesson_no
  Buffers: shared hit=2011
  CTE course_lessons
    ->  Hash Join  (cost=5.00..41.31 rows=160 width=12) (actual time=0.017..0.108 rows=160.00 loops=1)
  ->  Hash Right Join  (cost=4891.09..4943.29 rows=160 width=52) (actual time=15.329..15.371 rows=160.00 loops=1)
        ->  HashAggregate  (cost=4885.89..4912.29 rows=1760 width=44) (actual time=15.200..15.226 rows=160.00 loops=1)
              Group Key: a.lesson_id
              Buffers: shared hit=1992
              ->  Hash Join  (cost=5.20..4757.51 rows=17118 width=16) (actual time=0.015..12.569 rows=47737.00 loops=1)
                    ->  Seq Scan on lesson_attempts a  (cost=0.00..3875.00 rows=188300 width=16)
Execution Time: 15.198 ms
```
- **Buffers:** Decreased from **637,506** to **2,011** (a **99.68% reduction in buffer I/O**).
- **Latency:** Decreased from **1,437.911 ms** to **15.198 ms** (**94.6× faster**).

---

### 3.2 Win #2: R04 — Daily Goal Ring (5.315 ms $\rightarrow$ 0.047 ms, 99.12% Speedup)

#### The Problem:
`R04` powers the learner's home screen daily progress ring. The baseline query wrapped `started_at` in the `DATE()` function:
```sql
LEFT JOIN lesson_attempts a ON a.learner_id = l.learner_id AND date(a.started_at) = '2026-06-30'
```
Wrapping an indexed column in a function prevents B-Tree index range scans (non-sargable). PostgreSQL launched a parallel sequential scan across all 188,300 attempts, inspecting 94,150 rows per worker.

#### The Optimization:
1. Converted the predicate into an explicit sargable half-open timestamp range:
   ```sql
   AND a.started_at >= '2026-06-30 00:00:00+05:30' 
   AND a.started_at < '2026-07-01 00:00:00+05:30'
   ```
2. Created composite index `idx_lesson_attempts_learner_started ON lesson_attempts(learner_id, started_at)` obeying the Equality-First rule.

#### Execution Plan Comparison:
**Baseline Plan (`benchmarks/results/baseline/R04.txt`):**
```
Nested Loop Left Join  (cost=1000.29..4938.80 rows=1 width=8) (actual time=4.344..5.384 rows=1.00 loops=1)
  Buffers: shared hit=1995
  ->  Index Scan using learners_pkey on learners l (buffers: 3)
  ->  Gather  (cost=1000.00..4930.48 rows=1 width=8) (actual time=4.335..5.374 rows=1.00 loops=1)
        Workers Planned: 1, Launched: 1
        Buffers: shared hit=1992
        ->  Parallel Seq Scan on lesson_attempts a  (cost=0.00..3930.38 rows=1 width=8)
              Filter: ((learner_id = 1042) AND (date(started_at) = '2026-06-30'::date))
              Rows Removed by Filter: 94150
Execution Time: 5.421 ms
```

**Optimized Plan (`benchmarks/results/optimized/R04.txt`):**
```
Nested Loop Left Join  (cost=0.71..16.76 rows=1 width=8) (actual time=0.019..0.019 rows=1.00 loops=1)
  Buffers: shared hit=7
  ->  Index Scan using learners_pkey on learners l (buffers: 3)
  ->  Index Scan using idx_lesson_attempts_learner_started on lesson_attempts a (cost=0.42..8.44)
        Index Cond: ((learner_id = 1042) AND (started_at >= '2026-06-30 00:00:00+05:30') AND (started_at < '2026-07-01 00:00:00+05:30'))
        Buffers: shared hit=4
Execution Time: 0.047 ms
```
- **Buffers:** Dropped from **1,998** to **7**.
- **Latency:** Dropped from **5.315 ms** to **0.047 ms** (**113× faster**, easily surpassing the <5.0 ms SLA).

---

### 3.3 Win #3: R06 — "Start" Button Next Unfinished Lesson (5.805 ms $\rightarrow$ 0.067 ms, 98.85% Speedup)

#### The Problem:
When a learner taps "Start", Duolingo finds the first lesson in the active course that the learner has not yet completed. The baseline anti-join performed a full sequential scan of 188,300 attempts, filtering out 188,261 rows for every lookup.

#### The Optimization:
Created a partial composite index targeting only completed attempts:
```sql
CREATE INDEX idx_lesson_attempts_learner_lesson_comp 
ON lesson_attempts (learner_id, lesson_id) 
WHERE completed_at IS NOT NULL;
```
This partial index excludes incomplete attempts, keeping the index small (3.5 MB) and cache-resident.

#### Execution Plan Comparison:
**Baseline Plan (`benchmarks/results/baseline/R06.txt`):**
```
Nested Loop Anti Join  (cost=0.42..4454.11 rows=159 width=18) (actual time=6.104..6.120 rows=7.00 loops=1)
  Buffers: shared hit=2000
  ->  Materialize  (cost=0.00..4345.78 rows=6 width=4)
        Buffers: shared hit=1992
        ->  Seq Scan on lesson_attempts a  (cost=0.00..4345.75 rows=6 width=4)
              Filter: ((completed_at IS NOT NULL) AND (learner_id = 1042))
              Rows Removed by Filter: 188261
Execution Time: 5.716 ms
```

**Optimized Plan (`benchmarks/results/optimized/R06.txt`):**
```
Nested Loop Anti Join  (cost=4.89..141.66 rows=159 width=18) (actual time=0.034..0.046 rows=7.00 loops=1)
  Buffers: shared hit=19
  ->  Materialize  (cost=4.47..27.58 rows=6 width=4)
        Buffers: shared hit=11
        ->  Bitmap Heap Scan on lesson_attempts a  (cost=4.47..27.55 rows=6 width=4)
              Recheck Cond: ((learner_id = 1042) AND (completed_at IS NOT NULL))
              ->  Bitmap Index Scan on idx_lesson_attempts_learner_lesson_comp
Execution Time: 0.067 ms
```
- **Buffers:** Dropped from **2,003** to **19**.
- **Latency:** Dropped from **5.805 ms** to **0.067 ms** (**86× faster**).

---

### 3.4 Win #4: R05 — Cohort Leaderboard (0.899 ms $\rightarrow$ 0.077 ms, 91.43% Speedup)

#### The Problem:
`R05` displays the live leaderboard of 30 learners in a weekly league cohort, ranked by `weekly_xp DESC`. In baseline profiling, PostgreSQL sequentially scanned all 28,598 memberships in `league_memberships` and sorted the 30 cohort rows using an explicit quicksort node.

#### The Optimization:
Created composite index:
```sql
CREATE INDEX idx_league_memberships_week_cohort 
ON league_memberships (week_start, cohort_id, weekly_xp DESC);
```
Putting `week_start` and `cohort_id` first provides fast B-Tree equality lookups. Adding `weekly_xp DESC` stores matching rows in pre-sorted order, allowing the `WindowAgg` node to stream ranked rows directly without an explicit sort node.

#### Execution Plan Comparison:
**Baseline Plan (`benchmarks/results/baseline/R05.txt`):**
```
Sort  (cost=701.29..701.29 rows=1 width=25) (actual time=0.896..0.897 rows=30.00 loops=1)
  Sort Key: lm.weekly_xp DESC
  Sort Method: quicksort  Memory: 26kB
  Buffers: shared hit=360
  ->  Seq Scan on league_memberships lm  (cost=0.00..692.97 rows=1 width=8)
        Filter: ((week_start = '2026-06-29'::date) AND (cohort_id = 482))
        Rows Removed by Filter: 28568
        Buffers: shared hit=267
Execution Time: 0.945 ms
```

**Optimized Plan (`benchmarks/results/optimized/R05.txt`):**
```
WindowAgg  (cost=0.57..16.63 rows=1 width=33) (actual time=0.021..0.045 rows=30.00 loops=1)
  Buffers: shared hit=107
  ->  Index Scan using idx_league_memberships_week_cohort on league_memberships lm (cost=0.29..8.31)
        Index Cond: ((week_start = '2026-06-29'::date) AND (cohort_id = 482))
        Buffers: shared hit=14
Execution Time: 0.077 ms
```
- **Buffers:** Dropped from **363** to **107**.
- **Latency:** Dropped from **0.899 ms** to **0.077 ms** (**11.6× faster**).

---

### 3.5 Win #5: R22 — Deep Support Console Pagination (30.842 ms $\rightarrow$ 8.802 ms, 71.46% Speedup)

#### The Problem:
`R22` models customer support pagination into past lesson attempts: `OFFSET 100000 LIMIT 25 ORDER BY started_at DESC`. In baseline execution, PostgreSQL scanned all 188,300 attempts sequentially and attempted an in-memory sort. Because 188,300 tuples exceeded `work_mem`, it spilled **7,032 kB (7 MB)** of intermediate records to temporary files on disk via external merge sort.

#### The Optimization:
Created single-column descending B-tree index:
```sql
CREATE INDEX idx_lesson_attempts_started_at ON lesson_attempts (started_at DESC);
```
PostgreSQL can now traverse the B-tree in index order and stop as soon as it reaches row 100,025, completely eliminating the sort node and disk spill.

#### Execution Plan Comparison:
**Baseline Plan (`benchmarks/results/baseline/R22.txt`):**
```
Limit  (cost=25130.60..25130.66 rows=25 width=28) (actual time=29.226..29.228 rows=25.00 loops=1)
  Buffers: shared hit=1995, temp read=677 written=883
  ->  Sort  (cost=24880.60..25351.35 rows=188300 width=28)
        Sort Key: started_at DESC
        Sort Method: external merge  Disk: 7032kB
        ->  Seq Scan on lesson_attempts  (cost=0.00..3875.00 rows=188300 width=28)
Execution Time: 30.512 ms
```

**Optimized Plan (`benchmarks/results/optimized/R22.txt`):**
```
Limit  (cost=3666.15..3667.06 rows=25 width=28) (actual time=9.034..9.036 rows=25.00 loops=1)
  Buffers: shared hit=10105
  ->  Index Scan using idx_lesson_attempts_started_at on lesson_attempts  (cost=0.42..6902.98)
        Index Searches: 1
Execution Time: 8.802 ms
```
- **Disk Spill:** Completely eliminated (**7,032 kB $\rightarrow$ 0 kB**).
- **Latency:** Decreased from **30.842 ms** to **8.802 ms** (**3.5× faster**).

---

## 4. The R13 Bug: Three-Valued SQL Logic & Resolution

### 4.1 Root Cause Analysis (The 21,102 NULL Trap)
In Phase 3 baseline profiling, `R13` returned **0 rows**, despite the database containing 30,000 learners:
```sql
-- Original R13 Query
SELECT l.learner_id, l.username
FROM learners l
WHERE l.learner_id NOT IN (
    SELECT referred_by FROM learners
);
```

#### SQL Three-Valued Logic Explanation:
In SQL, boolean expressions evaluate to one of three truth values: `TRUE`, `FALSE`, or `UNKNOWN` (represented by `NULL`).
The expression `x NOT IN (y1, y2, ..., yn)` is semantically equivalent to:
$$\text{NOT } (x = y_1 \lor x = y_2 \lor \dots \lor x = y_n)$$
In our database, `referred_by` is nullable because users can sign up independently without a referral code. Specifically:
- **Total Learners:** 30,000
- **Learners with `referred_by IS NULL`:** 21,102
- **Distinct Non-Null Referrers:** 5,732

When `x` is evaluated against the subquery containing NULLs:
1. If `x` matches an existing non-null referrer, $(x = y_k)$ is `TRUE`, so the `OR` chain evaluates to `TRUE`, and `NOT (TRUE)` is `FALSE`.
2. If `x` does **not** match any known referrer, all comparisons against known values are `FALSE`. However, the comparison against the NULL element $(x = \text{NULL})$ evaluates to `UNKNOWN`.
3. The chain becomes:
   $$\text{NOT } (\text{FALSE} \lor \text{FALSE} \lor \dots \lor \text{UNKNOWN}) \implies \text{NOT } (\text{UNKNOWN}) \implies \text{UNKNOWN}$$
4. A SQL `WHERE` clause filters out any row unless its predicate evaluates strictly to `TRUE`. Because the result is always either `FALSE` or `UNKNOWN`, **every single learner was filtered out**, resulting in an empty table (0 rows).

### 4.2 The Solution: `NOT EXISTS`
We refactored `R13` in `sql/06_optimized_queries.sql` to use a correlated `NOT EXISTS` clause supported by a partial index on referrers:
```sql
-- Optimized R13 Query
SELECT l.learner_id, l.username
FROM learners l
WHERE NOT EXISTS (
    SELECT 1 FROM learners r WHERE r.referred_by = l.learner_id
);
```

`NOT EXISTS` checks for set cardinality:
- If a learner's ID matches at least one referred user, the subquery produces at least 1 row, `EXISTS` is `TRUE`, and `NOT EXISTS` evaluates to `FALSE` (correctly excluded).
- If a learner's ID has never been used as a referral, the subquery produces 0 rows, `EXISTS` evaluates to `FALSE`, and `NOT EXISTS` evaluates to `TRUE` (correctly included).
- NULL values in `r.referred_by` never equate to `l.learner_id` because `NULL = integer` evaluates to `UNKNOWN` and is excluded by the subquery `WHERE` clause.

### 4.3 Result Verification:
- **Baseline Returned:** 0 rows (incorrect)
- **Optimized Returned:** **24,268 rows** (correct)
- **Mathematical Check:**
  $$\text{Total Learners (30,000)} - \text{Distinct Referrers (5,732)} = 24,268 \text{ unreferred learners}$$
  The row count matches the exact expected ground truth.

---

## 5. Write Overhead Analysis (W01–W05)

A common danger when adding secondary indexes to accelerate read workloads is index maintenance overhead during write operations (DML). Every `INSERT`, `UPDATE`, and `DELETE` on an indexed table must update each secondary B-Tree node, which can degrade write throughput.

We evaluated the execution times of write operations `W01`–`W05` inside transactional `BEGIN ... ROLLBACK` blocks before and after adding the indexes:

| Write Query | Operation / Target Table | Baseline (ms) | Optimized (ms) | Overhead Diff (ms) | Impact & Justification |
|:---|:---|:---:|:---:|:---:|:---|
| **W01** | `INSERT` into `lesson_attempts` | 0.757 | 0.652 | -0.105 ms | **No negative impact.** Even though `lesson_attempts` now maintains 6 indexes, single-row B-tree leaf page inserts take only **0.65 ms** (well within the < 5 ms SLA). |
| **W02** | `UPDATE` latest unfinished attempt | 0.674 | 0.189 | **-0.485 ms (+71.96% faster)** | **Major speedup!** Updating an unfinished attempt requires finding it first. The partial index `idx_lesson_attempts_unfinished` dropped the lookup time from 0.47 ms to 0.01 ms, outweighing index update costs. |
| **W03** | `INSERT ... ON CONFLICT UPDATE` (daily_activity) | 0.436 | 0.417 | -0.019 ms | **Negligible.** Single-row upsert overhead remains virtually identical at **0.42 ms**. |
| **W04** | `UPDATE` 30 league cohort memberships | 5.763 | 8.529 | +2.766 ms (-48.00%) | **Expected batch overhead.** Updating `result` and sorting ranks across 30 rows requires updating `idx_league_memberships_week_cohort`. The +2.76 ms cost is negligible for a scheduled weekly batch job that runs once per week. |
| **W05** | Batch `INSERT` into `learner_achievements` | 39.685 | 33.319 | -6.366 ms (+16.04%) | **Slight speedup.** The multi-row insert benefited from faster candidate filtering on enrollments. |

### Conclusion on Write Overhead:
The measured write overhead is minimal. Real-time transactional writes (`W01`, `W02`, `W03`) remain sub-millisecond (< 0.7 ms). The modest +2.76 ms overhead on `W04` is an acceptable trade-off for accelerating high-frequency read queries (`R04`, `R05`, `R06`) by up to **99%**.

---

## 6. Physical Index Storage & Footprint Analysis

To ensure our indexing strategy remains memory- and storage-efficient, we measured the disk footprint of each table and its associated indexes using PostgreSQL's `pg_relation_size()` and `pg_indexes_size()`.

### 6.1 Table vs. Index Footprint Summary

| Table Name | Row Count | Table Heap Size | Indexes Size | Total Footprint | Index % of Table |
|:---|---:|---:|---:|---:|---:|
| `lesson_attempts` | 188,300 | 16 MB | 25 MB | 40 MB | 156.2% |
| `daily_activity` | 189,109 | 9.9 MB | 5.4 MB | 15 MB | 55.1% |
| `learners` | 30,000 | 3.1 MB | 5.0 MB | 8.2 MB | 161.5% |
| `enrollments` | 37,500 | 1.9 MB | 2.0 MB | 3.9 MB | 104.6% |
| `league_memberships` | 28,598 | 2.1 MB | 1.3 MB | 3.4 MB | 64.0% |
| `learner_achievements` | 38,860 | 1.8 MB | 0.9 MB | 2.7 MB | 48.7% |
| `lessons` | 1,760 | 112 kB | 112 kB | 248 kB | 100.0% |
| `units` | 220 | 16 kB | 48 kB | 88 kB | 300.0% |
| `achievements` | 10 | 8 kB | 48 kB | 56 kB | 600.0% |
| `courses` | 11 | 8 kB | 32 kB | 40 kB | 400.0% |
| `languages` | 10 | 8 kB | 32 kB | 40 kB | 400.0% |
| **TOTALS** | **474,278** | **34.8 MB** | **39.8 MB** | **74.6 MB** | **114.4%** |

### 6.2 Secondary Indexes Created in `sql/05_indexes.sql`

| Index Name | Table | Columns / Definition | Index Size | Queries Accelerated |
|:---|:---|:---|---:|:---|
| `idx_lesson_attempts_learner_started` | `lesson_attempts` | `(learner_id, started_at)` | 5,824 kB | `R04`, `R06`, `R25` |
| `idx_lesson_attempts_device_started` | `lesson_attempts` | `(device, started_at)` | 5,776 kB | `R17` |
| `idx_lesson_attempts_started_at` | `lesson_attempts` | `(started_at DESC)` | 4,136 kB | `R20`, `R22` |
| `idx_lesson_attempts_learner_lesson_comp` | `lesson_attempts` | `(learner_id, lesson_id)` WHERE `completed_at IS NOT NULL` | 3,584 kB | `R06` (partial index) |
| `idx_daily_activity_date_xp` | `daily_activity` | `(activity_date, xp)` | 1,344 kB | `R09`, `R15`, `R21`, `R23` |
| `idx_lesson_attempts_lesson_id` | `lesson_attempts` | `(lesson_id)` | 1,320 kB | `R07`, `R08`, `R19`, `R24` |
| `idx_enrollments_course_enrolled` | `enrollments` | `(course_id, enrolled_at)` | 1,168 kB | `R18` |
| `idx_learners_joined_at` | `learners` | `(joined_at)` | 672 kB | `R15` |
| `idx_lesson_attempts_unfinished` | `lesson_attempts` | `(started_at)` WHERE `completed_at IS NULL` | 488 kB | `W02` (partial index) |
| `idx_league_memberships_week_cohort` | `league_memberships` | `(week_start, cohort_id, weekly_xp DESC)` | 480 kB | `R05`, `W04` |
| `idx_learners_country_sub` | `learners` | `(country_code, subscription)` | 224 kB | `R23` |
| `idx_league_memberships_week_tier` | `league_memberships` | `(week_start, tier)` | 224 kB | `R14`, `W04` |
| `idx_learners_referred_by` | `learners` | `(referred_by)` WHERE `referred_by IS NOT NULL` | 184 kB | `R13` (partial index) |
| `idx_daily_activity_freeze` | `daily_activity` | `(activity_date, learner_id)` WHERE `used_streak_freeze = true` | 64 kB | `R10` (partial index) |
| `idx_units_course_id` | `units` | `(course_id)` | 16 kB | `R01`, `R06`, `R07`, `R19` |

### Key Storage Findings:
1. **Total secondary index footprint is only ~39.8 MB**, comfortably fitting in RAM cache on modern server and developer hardware.
2. **Partial Indexes Save Space:** By filtering `WHERE completed_at IS NOT NULL` and `WHERE used_streak_freeze = true`, partial indexes `idx_daily_activity_freeze` (64 kB) and `idx_lesson_attempts_unfinished` (488 kB) save substantial buffer cache while providing maximum query acceleration.

---

## 7. Queries That Could Not Be Sped Up (Honest Analysis)

In database optimization, not every query can or should be accelerated with an index. Attempting to force index scans on every query leads to index bloat and degraded write performance. We identified three categories of queries that showed little or no speedup:

1. **Already Sub-Millisecond Point Lookups (`R01`, `R02`, `R11`, `R12`):**
   - Queries like `R11` (0.022 ms) and `R02` (0.042 ms) were already operating at the physical hardware floor using existing Primary Key and Unique constraints. The small differences measured (-0.002 ms to -0.039 ms) represent routine CPU instruction cache jitter and OS context switching rather than algorithmic regression.
2. **Whole-Table Analytic Aggregations (`R24`, `R25`, `R18`):**
   - `R24` calculates average hearts lost across **all 188,300 attempts** grouped by CEFR level.
   - `R25` aggregates attempts across **all 24 hours of the day and all learner countries**.
   - Because these queries touch 100% of the tuples in `lesson_attempts`, a sequential scan is asymptotically and physically optimal. Forcing an index scan would introduce random disk I/O, which is significantly slower than sequential block reads. PostgreSQL's cost-based query optimizer correctly chose `Parallel Seq Scan`.
3. **High Cardinality Prefix Scans (`R16`):**
   - `R16` performs a prefix search `WHERE username LIKE 'Karan%'`. It already utilized the unique index `learners_username_key` in the baseline, taking 4.619 ms. Because it must fetch full user tuples from the heap for all matching records, performance remained virtually identical at 4.350 ms.

---

## 8. Final Compliance Against Rubric & SLAs

| SLA Tier | Target SLA | Baseline Status | Optimized Status | Verdict |
|:---|:---:|:---:|:---:|:---:|
| **Real-Time / Customer Facing** | `< 5.0 ms` | ⚠️ 2 Violations (`R04`: 5.3 ms, `R06`: 5.8 ms) | ✅ 100% Compliant (All $\le$ 0.65 ms) | **PASS (16/16)** |
| **Interactive Support & Admin** | `< 250.0 ms` | ✅ Compliant (Max 30.8 ms) | ✅ Compliant (Max 8.8 ms) | **PASS** |
| **Analytics & Curriculum Reports** | `< 5,000.0 ms` | ✅ Compliant (Max 1,437.9 ms) | ✅ Compliant (Max 108.2 ms) | **PASS** |
| **Batch Maintenance Jobs** | `< 1,000.0 ms` | ✅ Compliant (Max 39.7 ms) | ✅ Compliant (Max 33.3 ms) | **PASS** |

---
*Report prepared and submitted by Nilesh Saini on behalf of the DBMS Project Team.*

