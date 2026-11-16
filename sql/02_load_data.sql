-- =====================================================================
-- Duolingo Language Learning Database: Data Loading & Verification
-- Course: Database Management Systems (Phase 2: Track B)
-- Database: PostgreSQL 15+
-- Schema: duolingo
--
-- Instructions:
--   Run this file using psql from the project root:
--     psql -d <database_name> -f sql/02_load_data.sql
-- =====================================================================

SET search_path TO duolingo;
SET timezone = 'Asia/Kolkata';

-- ---------------------------------------------------------------------
-- 1. Load Data in FK-Safe Parent -> Child Order
-- ---------------------------------------------------------------------

-- Level 0 (Independent Catalog tables)
\copy languages FROM 'seed_data/languages.csv' WITH (FORMAT csv, HEADER true);
\copy achievements FROM 'seed_data/achievements.csv' WITH (FORMAT csv, HEADER true);

-- Level 1 (Dependent on languages)
\copy courses FROM 'seed_data/courses.csv' WITH (FORMAT csv, HEADER true);

-- Level 2 (Dependent on courses)
\copy units FROM 'seed_data/units.csv' WITH (FORMAT csv, HEADER true);

-- Level 3 (Dependent on units)
\copy lessons FROM 'seed_data/lessons.csv' WITH (FORMAT csv, HEADER true);

-- Level 1 (Self-referential, root learners first or load with deferred checks)
\copy learners FROM 'seed_data/learners.csv' WITH (FORMAT csv, HEADER true);

-- Level 4 (Dependent on learners and courses/lessons/achievements)
\copy enrollments FROM 'seed_data/enrollments.csv' WITH (FORMAT csv, HEADER true);
\copy lesson_attempts FROM 'seed_data/lesson_attempts.csv' WITH (FORMAT csv, HEADER true);
\copy daily_activity FROM 'seed_data/daily_activity.csv' WITH (FORMAT csv, HEADER true);
\copy league_memberships FROM 'seed_data/league_memberships.csv' WITH (FORMAT csv, HEADER true);
\copy learner_achievements FROM 'seed_data/learner_achievements.csv' WITH (FORMAT csv, HEADER true);

-- ---------------------------------------------------------------------
-- 2. Update Planner Statistics
-- ---------------------------------------------------------------------
ANALYZE;

-- ---------------------------------------------------------------------
-- 3. Row Count Verification
-- Expected counts:
--   languages:            10
--   courses:              11
--   units:               220
--   lessons:           1,760
--   learners:         30,000
--   enrollments:      37,500
--   lesson_attempts: 188,300
--   daily_activity:  189,109
--   league_memberships: 28,598
--   achievements:         10
--   learner_achievements: 38,860
-- ---------------------------------------------------------------------
SELECT 'languages' AS table_name, count(*) AS actual_rows, 10 AS expected_rows FROM languages
UNION ALL
SELECT 'courses', count(*), 11 FROM courses
UNION ALL
SELECT 'units', count(*), 220 FROM units
UNION ALL
SELECT 'lessons', count(*), 1760 FROM lessons
UNION ALL
SELECT 'learners', count(*), 30000 FROM learners
UNION ALL
SELECT 'enrollments', count(*), 37500 FROM enrollments
UNION ALL
SELECT 'lesson_attempts', count(*), 188300 FROM lesson_attempts
UNION ALL
SELECT 'daily_activity', count(*), 189109 FROM daily_activity
UNION ALL
SELECT 'league_memberships', count(*), 28598 FROM league_memberships
UNION ALL
SELECT 'achievements', count(*), 10 FROM achievements
UNION ALL
SELECT 'learner_achievements', count(*), 38860 FROM learner_achievements;

-- ---------------------------------------------------------------------
-- 4. Five Integrity Checks (All must return 0 violations)
-- ---------------------------------------------------------------------

-- Check 1: No league cohort exceeds the 30-member limit
-- Expected: 0 rows
SELECT cohort_id, week_start, count(*) AS cohort_size
FROM league_memberships
GROUP BY cohort_id, week_start
HAVING count(*) > 30;

-- Check 2: Learners only attempt lessons of courses they are enrolled in
-- Expected: 0 rows
SELECT count(*) AS attempts_without_enrollment
FROM lesson_attempts a
JOIN lessons l ON l.lesson_id = a.lesson_id
JOIN units u ON u.unit_id = l.unit_id
WHERE NOT EXISTS (
    SELECT 1 FROM enrollments e
    WHERE e.learner_id = a.learner_id AND e.course_id = u.course_id
);

-- Check 3: Daily activity XP matches the sum of XP earned from attempts on that date
-- Expected: 0 rows
WITH attempt_daily AS (
    SELECT learner_id, DATE(started_at) AS act_date, SUM(xp_earned) AS total_xp
    FROM lesson_attempts
    GROUP BY learner_id, DATE(started_at)
)
SELECT count(*) AS daily_xp_mismatches
FROM daily_activity d
JOIN attempt_daily a ON a.learner_id = d.learner_id AND a.act_date = d.activity_date
WHERE d.xp <> a.total_xp;

-- Check 4: No orphan referrals exist (every referred_by points to an existing learner)
-- Expected: 0 rows
SELECT count(*) AS invalid_referrals
FROM learners
WHERE referred_by IS NOT NULL 
  AND referred_by NOT IN (SELECT learner_id FROM learners);

-- Check 5: Perfect lessons have zero mistakes, a completion timestamp, and positive XP
-- Expected: 0 rows
SELECT count(*) AS inconsistent_perfect_attempts
FROM lesson_attempts
WHERE is_perfect = true AND (mistakes > 0 OR completed_at IS NULL OR xp_earned <= 0);
