# Phase 3: Baseline Timings Report (CP2)

**Project:** Duolingo Language Learning Database  
**Team:** Mudit Jindal (Lead), Satyam, Shirsh, Nilesh Saini  
**Database:** PostgreSQL 18.6 (Homebrew) · **Hardware:** MacBook Pro M4 (as specified in `team.json`)  
**Workload:** 30 queries (`queries/workload_30.sql`) · **Method:** 3 runs per query via `EXPLAIN (ANALYZE, BUFFERS)`

---

## 1. Executive Summary

Baseline performance measurements were gathered against the unindexed schema (only constraints PK, FK, UNIQUE, CHECK).

- **Total Queries Measured:** 30 (25 Read queries `R01`–`R25`, 5 Write queries `W01`–`W05`).
- **Fastest Query:** `R11` (Sign-in by username) at **0.025 ms** (leveraging unique index `learners_username_key`).
- **Slowest Query:** `R19` (Curriculum lesson report) at **1,437.911 ms** (~1.44 seconds) due to repeated subquery executions scanning 188,300 attempts.
- **Critical Real-Time Hotspots:** Customer-facing queries `R04` (5.315 ms) and `R06` (5.805 ms) exceed the strict `< 5 ms` real-time SLA due to sequential scans on `lesson_attempts`.
- **Heaviest Batch Write:** `W05` (Achievements catch-up) takes **39.685 ms** due to full scans on `enrollments` and `achievements`.

---

## 2. Complete 30-Query Timing Table

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Scan Type |
|---|:---:|---:|---:|---:|---:|---|
| **R01**: Course path: units and lessons of the Spanish course for English speakers, in order | READ | 0.197 | 0.098 | 0.110 | **0.135** | `Seq Scan on units | Seq Scan on courses | Index Scan using uq_lessons_unit_lesson_no on lessons` |
| **R02**: Home screen: learner 1042's courses with total XP | READ | 0.044 | 0.039 | 0.037 | **0.040** | `Index Scan using enrollments_pkey on enrollments | Seq Scan on courses` |
| **R03**: Streak counter: learner 1042's current streak (consecutive days up to 30 June 2026, freezes count) | READ | 0.089 | 0.086 | 0.088 | **0.088** | `Index Only Scan using daily_activity_pkey on daily_activity` |
| **R04**: Daily goal ring: XP learner 1042 earned on 30 June 2026 vs their daily goal | READ | 5.434 | 5.421 | 5.091 | **5.315** | `Index Scan using learners_pkey on learners | Seq Scan on lesson_attempts` |
| **R05**: Leagues tab: leaderboard of learner 1042's cohort for the week starting 29 June 2026 | READ | 0.945 | 0.947 | 0.804 | **0.899** | `Index Scan using league_memberships_pkey on league_memberships | Seq Scan on league_memberships | Index Scan using learners_pkey on learners` |
| **R06**: "Start" button: the first lesson of learner 1042's Spanish course they have not completed yet | READ | 6.154 | 5.716 | 5.546 | **5.805** | `Index Scan using uq_units_course_unit_no on units | Index Scan using uq_lessons_unit_lesson_no on lessons | Seq Scan on lesson_attempts` |
| **R07**: Curriculum team: lessons of the Spanish course with the most mistakes per attempt (100+ attempts) | READ | 15.138 | 15.145 | 15.150 | **15.144** | `Seq Scan on lesson_attempts | Seq Scan on lessons | Seq Scan on units` |
| **R08**: Product analytics: quit rate per lesson type | READ | 17.985 | 20.188 | 20.031 | **19.401** | `Seq Scan on lesson_attempts | Seq Scan on lessons` |
| **R09**: Growth: daily active learners in June 2026 | READ | 7.060 | 6.598 | 5.951 | **6.536** | `Seq Scan on daily_activity` |
| **R10**: Monetisation: streak freezes used per subscription tier in 2026 | READ | 4.826 | 4.709 | 5.167 | **4.901** | `Seq Scan on daily_activity | Index Scan using learners_pkey on learners` |
| **R11**: Sign-in by username | READ | 0.030 | 0.022 | 0.023 | **0.025** | `Index Scan using learners_username_key on learners` |
| **R12**: Profile: learner 1042's achievements, newest first | READ | 0.050 | 0.052 | 0.048 | **0.050** | `Index Scan using learner_achievements_pkey on learner_achievements | Seq Scan on achievements` |
| **R13**: Referral programme: learners who have not referred anyone yet | READ | 4.890 | 4.652 | 4.383 | **4.642** | `Seq Scan on learners` |
| **R14**: Leagues team: promotion and demotion rates per tier over the last 4 completed weeks | READ | 1.820 | 1.781 | 1.934 | **1.845** | `Seq Scan on league_memberships` |
| **R15**: Retention: learners who joined in January 2026 and were still active in June 2026 | READ | 1.621 | 2.278 | 1.759 | **1.886** | `Seq Scan on learners | Index Scan using daily_activity_pkey on daily_activity` |
| **R16**: Friends: search learners by username starting with "Karan" | READ | 4.994 | 4.669 | 4.194 | **4.619** | `Index Scan using learners_username_key on learners` |
| **R17**: Product analytics: perfect-lesson rate per device in 2026 | READ | 14.831 | 14.424 | 14.291 | **14.515** | `Seq Scan on lesson_attempts` |
| **R18**: Course popularity: enrollments per course, and how many started in 2026 | READ | 5.673 | 5.865 | 5.649 | **5.729** | `Seq Scan on enrollments | Seq Scan on courses` |
| **R19**: Curriculum report: completions and average mistakes of every lesson in the Spanish course | READ | 1436.567 | 1443.374 | 1433.791 | **1437.911** | `Index Scan using uq_units_course_unit_no on units | Index Scan using uq_lessons_unit_lesson_no on lessons | Seq Scan on lesson_attempts` |
| **R20**: Growth: XP earned per day across the platform and running total, June 2026 | READ | 8.715 | 8.643 | 8.396 | **8.585** | `Seq Scan on lesson_attempts` |
| **R21**: Streak reminders: learners active every day from 23 to 29 June but not yet on 30 June | READ | 2.449 | 2.094 | 2.133 | **2.225** | `Index Only Scan using daily_activity_pkey on daily_activity` |
| **R22**: Support console: all lesson attempts, newest first, page 4,001 (25 per page) | READ | 30.512 | 31.148 | 30.867 | **30.842** | `Seq Scan on lesson_attempts` |
| **R23**: Monetisation: Super and Max learners in India who were active in the last 7 days of June 2026 | READ | 5.873 | 6.125 | 5.724 | **5.907** | `Seq Scan on daily_activity | Seq Scan on learners` |
| **R24**: Curriculum team: average hearts lost per lesson, by CEFR level | READ | 22.226 | 22.597 | 22.686 | **22.503** | `Seq Scan on lesson_attempts | Seq Scan on lessons | Seq Scan on units` |
| **R25**: Notifications team: lessons started per hour of the day, per country | READ | 111.110 | 109.342 | 111.356 | **110.603** | `Seq Scan on lesson_attempts | Seq Scan on learners` |
| **W01**: Lesson start: learner 1042 starts lesson 1 | WRITE | 1.186 | 0.545 | 0.541 | **0.757** | `(no scan)` |
| **W02**: Lesson end: finish the most recent unfinished attempt of 30 June 2026 with 2 mistakes | WRITE | 0.852 | 0.600 | 0.569 | **0.674** | `Index Scan using lesson_attempts_pkey on lesson_attempts` |
| **W03**: Daily activity: add 20 XP to learner 1042's 1 July 2026 (creating the row if needed) | WRITE | 0.499 | 0.397 | 0.411 | **0.436** | `(no scan)` |
| **W04**: Weekly league close (week of 29 June 2026): rank everyone in their cohort and set promotion results | WRITE | 7.090 | 4.942 | 5.256 | **5.763** | `Seq Scan on league_memberships` |
| **W05**: Achievements catch-up: award the "100 XP" badge to every learner who has 100+ XP but not the badge | WRITE | 45.943 | 39.348 | 33.764 | **39.685** | `Seq Scan on achievements | Seq Scan on enrollments` |

---

## 3. Performance vs Targets (Defined in Phase 1)

| Category | Target SLA | Queries in Category | Compliance Status | Key Bottlenecks Identified |
|---|:---:|---|:---:|---|
| **Real-time / Learner-facing** | `< 5.0 ms` | R02, R03, R04, R05, R06, R11, R12, W01, W02, W03 | ⚠️ **Partial** | `R04` (5.315 ms) & `R06` (5.805 ms) exceed 5 ms due to `Seq Scan on lesson_attempts`. |
| **Interactive Tools** | `< 250.0 ms` | R01, R13, R16, R21, R22, R23 | ✅ **Met** | All under 35 ms. `R22` (30.842 ms) slowest due to high OFFSET deep scan. |
| **Reports & Analytics** | `< 5,000.0 ms` | R07, R08, R09, R10, R14, R15, R17, R18, R19, R20, R24, R25 | ✅ **Met** | `R19` (1,437.91 ms) and `R25` (110.60 ms) are slowest, within 5s batch target but ripe for 50x speedup. |
| **Batch Maintenance** | `< 1,000.0 ms` | W04, W05 | ✅ **Met** | `W04` (5.763 ms), `W05` (39.685 ms) well within 1s limit. |

---

## 4. Deep-Dive Bottleneck Analysis

### 4.1 The Intentionally Slow Query: R19 (1,437.911 ms)
`R19` calculates completions and average mistakes for every lesson in the Spanish course. In the baseline schema, the query executes correlated aggregations over `lesson_attempts` for each lesson. With 188,300 attempts and no index on `(lesson_id)`, PostgreSQL performs repeated sequential scans over the table, generating millions of buffer hits and taking ~1.44 seconds.

### 4.2 Sequential Scan Bottlenecks on Large Tables
PostgreSQL relies on full sequential scans for queries filtering on foreign keys or dates because secondary indexes are intentionally absent in Phase 2/3:
1. **`lesson_attempts` (188,300 rows):** Scanned sequentially in `R04`, `R06`, `R07`, `R08`, `R17`, `R19`, `R20`, `R22`, `R24`, `R25`. This is the single biggest performance drag.
2. **`daily_activity` (189,109 rows):** Scanned sequentially in `R09`, `R10`, `R23` when filtering on `activity_date` or `xp`.
3. **`learners` (30,000 rows):** `R13` scans all 30k learners with `Seq Scan` (coupled with the SQL NULL subquery trap).
4. **`league_memberships` (28,598 rows):** `R05`, `R14`, `W04` scan league memberships sequentially when grouping by `cohort_id` and `week_start`.

### 4.3 High-Offset Pagination: R22 (30.842 ms)
`R22` fetches page 4,001 with `OFFSET 100000 LIMIT 25 ORDER BY started_at DESC`. PostgreSQL must read and sort 100,025 tuples sequentially before discarding 100,000 of them, consuming significant CPU and memory.

---

## 5. Strategic Optimization Roadmap for Phase 4

To achieve 10× to 100× speedups in Phase 4 (`sql/05_indexes.sql` and `sql/06_optimized_queries.sql`), the following indexing and rewrite strategies will be implemented:

1. **Secondary B-Tree Indexes on Foreign Keys:**
   - `CREATE INDEX idx_lesson_attempts_lesson_id ON lesson_attempts(lesson_id);` (Directly targets R07, R08, R19, R24).
   - `CREATE INDEX idx_lesson_attempts_learner_date ON lesson_attempts(learner_id, started_at);` (Targets R04, R06).
   - `CREATE INDEX idx_daily_activity_date_xp ON daily_activity(activity_date, xp);` (Targets R09, R10, R20).
   - `CREATE INDEX idx_league_memberships_cohort ON league_memberships(week_start, cohort_id);` (Targets R05, W04).
2. **Covering / Composite Indexes:**
   - Include frequently selected columns (`mistakes`, `xp_earned`, `completed_at`) to enable Index-Only Scans.
3. **Query Refactoring:**
   - **Fix R13 NULL Bug:** Rewrite `NOT IN (SELECT referred_by ...)` to `NOT EXISTS` or filter `WHERE referred_by IS NOT NULL`.
   - **Keyset Pagination for R22:** Replace high `OFFSET` with cursor-based pagination (`WHERE started_at < :last_seen ORDER BY started_at DESC LIMIT 25`).
   - **R19 Aggregation Rewrite:** Pre-aggregate lesson attempts using CTE or join instead of correlated subqueries.
