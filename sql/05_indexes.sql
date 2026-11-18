-- =====================================================================
-- Duolingo DBMS Project: Secondary & Composite Index Definitions (CP3 / Phase 4)
-- Member 1: Satyam (Track 1: Index Architecture & Storage)
-- Database: PostgreSQL 18.6+
-- Schema: duolingo
--
-- Optimization Principles Applied:
--   1. Column Ordering Rule: Equality columns FIRST, followed by Range/Sort columns.
--   2. Partial Indexes: Used for skewed boolean predicates (used_streak_freeze, completed_at IS NULL)
--      to save disk space and cache lines while keeping writes fast.
--   3. Foreign Key Coverage: Covers unindexed FK joins (lesson_id, course_id, referred_by)
--      eliminating O(N) sequential scans on 188k+ rows.
-- =====================================================================

SET search_path TO duolingo;

-- ---------------------------------------------------------------------
-- 1. Table: lesson_attempts (188,300 rows) - Highest I/O bottleneck
-- ---------------------------------------------------------------------

-- Accelerates R07, R08, R19, R24
-- Why: Eliminates repeated 188k full table sequential scans during joins and aggregations on lesson_id.
CREATE INDEX IF NOT EXISTS idx_lesson_attempts_lesson_id 
    ON lesson_attempts (lesson_id);

-- Accelerates R04, R06, R25
-- Why: Equality on learner_id followed by range scan on started_at. Enables index range scans for user activity.
CREATE INDEX IF NOT EXISTS idx_lesson_attempts_learner_started 
    ON lesson_attempts (learner_id, started_at);

-- Accelerates R06 ("Start" button next unfinished lesson)
-- Why: Partial index targeting only completed attempts; extremely compact and speeds up NOT EXISTS subquery.
CREATE INDEX IF NOT EXISTS idx_lesson_attempts_learner_lesson_comp 
    ON lesson_attempts (learner_id, lesson_id) 
    WHERE completed_at IS NOT NULL;

-- Accelerates R17 (Device analytics in 2026)
-- Why: Groups by device with started_at range filter.
CREATE INDEX IF NOT EXISTS idx_lesson_attempts_device_started 
    ON lesson_attempts (device, started_at);

-- Accelerates R20 (Daily XP growth) and R22 (Support console pagination)
-- Why: Provides pre-sorted ordering on started_at DESC, avoiding expensive sort nodes on large offsets.
CREATE INDEX IF NOT EXISTS idx_lesson_attempts_started_at 
    ON lesson_attempts (started_at DESC);

-- Accelerates W02 (Find most recent unfinished attempt)
-- Why: Tiny partial index on unfinished attempts (<5% of rows), making subquery max(attempt_id) instant.
CREATE INDEX IF NOT EXISTS idx_lesson_attempts_unfinished 
    ON lesson_attempts (started_at) 
    WHERE completed_at IS NULL;


-- ---------------------------------------------------------------------
-- 2. Table: daily_activity (189,109 rows)
-- ---------------------------------------------------------------------

-- Accelerates R09, R15, R21, R23
-- Why: Primary key is (learner_id, activity_date), which cannot be used when filtering by date first.
-- Indexing activity_date and xp enables fast B-tree range scans for active days.
CREATE INDEX IF NOT EXISTS idx_daily_activity_date_xp 
    ON daily_activity (activity_date, xp);

-- Accelerates R10 (Streak freezes used by tier in 2026)
-- Why: Partial index filtering only the small subset where used_streak_freeze = true.
CREATE INDEX IF NOT EXISTS idx_daily_activity_freeze 
    ON daily_activity (activity_date, learner_id) 
    WHERE used_streak_freeze = true;


-- ---------------------------------------------------------------------
-- 3. Table: league_memberships (28,598 rows)
-- ---------------------------------------------------------------------

-- Accelerates R05 (Leaderboard lookup) and W04 (Weekly league close ranking)
-- Why: Composite index on equality columns (week_start, cohort_id) with weekly_xp DESC
-- to eliminate in-memory sorting during window ranking.
CREATE INDEX IF NOT EXISTS idx_league_memberships_week_cohort 
    ON league_memberships (week_start, cohort_id, weekly_xp DESC);

-- Accelerates R14 (Promotion/demotion rates over completed weeks)
-- Why: Range scan on week_start followed by grouping on tier.
CREATE INDEX IF NOT EXISTS idx_league_memberships_week_tier 
    ON league_memberships (week_start, tier);


-- ---------------------------------------------------------------------
-- 4. Table: enrollments (37,500 rows)
-- ---------------------------------------------------------------------

-- Accelerates R18 (Course popularity & 2026 new enrollments)
-- Why: Primary key is (learner_id, course_id). Queries grouping by course_id need an index
-- starting with course_id and covering enrolled_at for filtering.
CREATE INDEX IF NOT EXISTS idx_enrollments_course_enrolled 
    ON enrollments (course_id, enrolled_at);


-- ---------------------------------------------------------------------
-- 5. Table: learners (30,000 rows)
-- ---------------------------------------------------------------------

-- Accelerates R15 (January 2026 cohort retention)
-- Why: B-Tree index on joined_at turns full sequential scan of 30k learners into an Index Scan.
CREATE INDEX IF NOT EXISTS idx_learners_joined_at 
    ON learners (joined_at);

-- Accelerates R23 (Super and Max active learners in India)
-- Why: Equality filter on country_code followed by subscription IN ('SUPER', 'MAX').
CREATE INDEX IF NOT EXISTS idx_learners_country_sub 
    ON learners (country_code, subscription);

-- Accelerates R13 (Referral programme NOT EXISTS rewrite)
-- Why: Partial index on referred_by foreign key allows instantaneous lookup of whether a learner referred someone.
CREATE INDEX IF NOT EXISTS idx_learners_referred_by 
    ON learners (referred_by) 
    WHERE referred_by IS NOT NULL;


-- ---------------------------------------------------------------------
-- 6. Table: units (220 rows)
-- ---------------------------------------------------------------------

-- Accelerates R01, R06, R07, R19, R24
-- Why: Foreign key index on course_id for fast joins from courses to units.
CREATE INDEX IF NOT EXISTS idx_units_course_id 
    ON units (course_id);
