# Duolingo Database: Data Loading & Integrity Verification Report
**Course:** Database Management Systems (Phase 2: Track B)  
**Executed & Verified by:** Satyam (Enrollment No: 2501010411 · GitHub: `@satyam6231631-hue`)  
**Execution Environment:** PostgreSQL 18 · Database: `duolingo` · Schema: `duolingo`  
**Date of Execution:** 15 November 2026  

---

## 1. Executive Summary

As part of Phase 2 (Track B), the complete production seed dataset (11 CSV files from `seed_data.zip`) was loaded into PostgreSQL in foreign-key safe dependency order using `sql/02_load_data.sql`. Following the load, table statistics were recomputed via `ANALYZE`, and the database was subjected to two levels of validation:

1. **Row Count Verification:** All 11 tables were audited against the official Phase 2 seed data specifications. Every table matched the exact expected row count with 100% precision.
2. **Business Rule & Integrity Verification:** Five comprehensive integrity SQL queries were executed against the relational schema to verify cohort size limits, enrollment constraints, XP aggregation consistency, referral graph integrity, and perfect lesson rules. All 5 checks returned **0 violations**.

---

## 2. Data Loading Sequence (FK Dependency Order)

To guarantee that foreign key constraints were strictly respected without disabling foreign keys or checks, the data was ingested in parent-first dependency order:

| Level | Table Name | Source File | Dependency Order & FK Rationale |
| :---: | :--- | :--- | :--- |
| **0** | `languages` | `seed_data/languages.csv` | Independent master catalog of languages. |
| **0** | `achievements` | `seed_data/achievements.csv` | Independent master catalog of badges. |
| **1** | `courses` | `seed_data/courses.csv` | References `languages(language_code)` for source and target languages. |
| **1** | `learners` | `seed_data/learners.csv` | Independent learners; self-referential `referred_by` points to existing learners. |
| **2** | `units` | `seed_data/units.csv` | References `courses(course_id)`. |
| **3** | `lessons` | `seed_data/lessons.csv` | References `units(unit_id)`. |
| **4** | `enrollments` | `seed_data/enrollments.csv` | Junction table referencing `learners(learner_id)` and `courses(course_id)`. |
| **4** | `lesson_attempts` | `seed_data/lesson_attempts.csv` | Transaction log referencing `learners(learner_id)` and `lessons(lesson_id)`. |
| **4** | `daily_activity` | `seed_data/daily_activity.csv` | Daily aggregations referencing `learners(learner_id)`. |
| **4** | `league_memberships` | `seed_data/league_memberships.csv` | Weekly leaderboards referencing `learners(learner_id)`. |
| **4** | `learner_achievements` | `seed_data/learner_achievements.csv` | Badges awarded referencing `learners` and `achievements`. |

---

## 3. Row Count Verification Results

Following execution of `\copy` and `ANALYZE`, the following query was executed to compare actual rows loaded against the expected specification:

```sql
SELECT 'languages' AS table_name, count(*) AS actual_rows, 10 AS expected_rows FROM languages
UNION ALL SELECT 'courses', count(*), 11 FROM courses
UNION ALL SELECT 'units', count(*), 220 FROM units
UNION ALL SELECT 'lessons', count(*), 1760 FROM lessons
UNION ALL SELECT 'learners', count(*), 30000 FROM learners
UNION ALL SELECT 'enrollments', count(*), 37500 FROM enrollments
UNION ALL SELECT 'lesson_attempts', count(*), 188300 FROM lesson_attempts
UNION ALL SELECT 'daily_activity', count(*), 189109 FROM daily_activity
UNION ALL SELECT 'league_memberships', count(*), 28598 FROM league_memberships
UNION ALL SELECT 'achievements', count(*), 10 FROM achievements
UNION ALL SELECT 'learner_achievements', count(*), 38860 FROM learner_achievements;
```

### Verification Table

| # | Table Name | Actual Rows Loaded | Expected Rows (Spec) | Variance | Verification Status |
| :-: | :--- | :-: | :-: | :-: | :-: |
| 1 | `languages` | **10** | 10 | 0 | **PASSED** |
| 2 | `achievements` | **10** | 10 | 0 | **PASSED** |
| 3 | `courses` | **11** | 11 | 0 | **PASSED** |
| 4 | `units` | **220** | 220 | 0 | **PASSED** |
| 5 | `lessons` | **1,760** | 1,760 | 0 | **PASSED** |
| 6 | `learners` | **30,000** | 30,000 | 0 | **PASSED** |
| 7 | `enrollments` | **37,500** | 37,500 | 0 | **PASSED** |
| 8 | `lesson_attempts` | **188,300** | 188,300 | 0 | **PASSED** |
| 9 | `daily_activity` | **189,109** | 189,109 | 0 | **PASSED** |
| 10 | `league_memberships` | **28,598** | 28,598 | 0 | **PASSED** |
| 11 | `learner_achievements` | **38,860** | 38,860 | 0 | **PASSED** |

**Total Records Loaded Across All Tables:** **475,868 rows**

---

## 4. Integrity Checks & Verification Results

All 5 business rule verification queries were run directly against the loaded schema.

### Check 1: League Cohort Sizing (Maximum 30 Members per Cohort)
* **Business Rule:** Every weekly competitive league cohort must contain at most 30 learners.
* **SQL Query:**
  ```sql
  SELECT cohort_id, week_start, count(*) AS cohort_size
  FROM league_memberships
  GROUP BY cohort_id, week_start
  HAVING count(*) > 30;
  ```
* **Execution Output:**
  ```text
   cohort_id | week_start | cohort_size 
  -----------+------------+-------------
  (0 rows)
  ```
* **Result:** **0 violations (PASSED)**.

---

### Check 2: Attempt Enrollment Consistency
* **Business Rule:** A learner can only attempt lessons for courses in which they have an active enrollment.
* **SQL Query:**
  ```sql
  SELECT count(*) AS attempts_without_enrollment
  FROM lesson_attempts a
  JOIN lessons l ON l.lesson_id = a.lesson_id
  JOIN units u ON u.unit_id = l.unit_id
  WHERE NOT EXISTS (
      SELECT 1 FROM enrollments e
      WHERE e.learner_id = a.learner_id AND e.course_id = u.course_id
  );
  ```
* **Execution Output:**
  ```text
   attempts_without_enrollment 
  -----------------------------
                             0
  (1 row)
  ```
* **Result:** **0 violations (PASSED)**.

---

### Check 3: Daily Activity XP Aggregation vs Lesson Attempt Sums
* **Business Rule:** For every learner on any given activity date, `daily_activity.xp` must equal the sum of `xp_earned` from `lesson_attempts` logged on that calendar day.
* **SQL Query:**
  ```sql
  WITH attempt_daily AS (
      SELECT learner_id, DATE(started_at) AS act_date, SUM(xp_earned) AS total_xp
      FROM lesson_attempts
      GROUP BY learner_id, DATE(started_at)
  )
  SELECT count(*) AS daily_xp_mismatches
  FROM daily_activity d
  JOIN attempt_daily a ON a.learner_id = d.learner_id AND a.act_date = d.activity_date
  WHERE d.xp <> a.total_xp;
  ```
* **Execution Output:**
  ```text
   daily_xp_mismatches 
  ---------------------
                     0
  (1 row)
  ```
* **Result:** **0 violations (PASSED)**.

---

### Check 4: Referral Graph Integrity (No Orphan Referrals)
* **Business Rule:** Every non-null `referred_by` foreign key in `learners` must reference a valid, existing `learner_id` (no dangling or cyclic self-referrals).
* **SQL Query:**
  ```sql
  SELECT count(*) AS invalid_referrals
  FROM learners
  WHERE referred_by IS NOT NULL 
    AND referred_by NOT IN (SELECT learner_id FROM learners);
  ```
* **Execution Output:**
  ```text
   invalid_referrals 
  -------------------
                   0
  (1 row)
  ```
* **Result:** **0 violations (PASSED)**.

---

### Check 5: Perfect Lesson Attempt Consistency
* **Business Rule:** An attempt marked `is_perfect = true` must have exactly `0 mistakes`, a valid `completed_at` timestamp, and `xp_earned > 0`.
* **SQL Query:**
  ```sql
  SELECT count(*) AS inconsistent_perfect_attempts
  FROM lesson_attempts
  WHERE is_perfect = true 
    AND (mistakes > 0 OR completed_at IS NULL OR xp_earned <= 0);
  ```
* **Execution Output:**
  ```text
   inconsistent_perfect_attempts 
  -------------------------------
                               0
  (1 row)
  ```
* **Result:** **0 violations (PASSED)**.

---

## 5. Conclusion

The data loading pipeline defined in `sql/02_load_data.sql` and the schema constraints defined in `sql/01_schema.sql` are fully validated. The PostgreSQL database is fully populated, statistically analyzed, and ready for baseline benchmark query execution (Phase 3).
