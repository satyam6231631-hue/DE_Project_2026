-- =====================================================================
-- Duolingo Language Learning Database: Schema Definition
-- Course: Database Management Systems (Phase 2: Track A)
-- Database: PostgreSQL 15+
-- Schema: duolingo
--
-- Notes:
--   * Only constraints (PK, FK, UNIQUE, NOT NULL, CHECK) are defined.
--   * No secondary / performance indexes are created here (reserved for Phase 4).
--   * All table and column names exactly match seed_data CSV files and workload queries.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS duolingo;
SET search_path TO duolingo;

-- Clean existing tables if script is re-run (in reverse dependency order)
DROP TABLE IF EXISTS learner_achievements CASCADE;
DROP TABLE IF EXISTS achievements CASCADE;
DROP TABLE IF EXISTS league_memberships CASCADE;
DROP TABLE IF EXISTS daily_activity CASCADE;
DROP TABLE IF EXISTS lesson_attempts CASCADE;
DROP TABLE IF EXISTS enrollments CASCADE;
DROP TABLE IF EXISTS learners CASCADE;
DROP TABLE IF EXISTS lessons CASCADE;
DROP TABLE IF EXISTS units CASCADE;
DROP TABLE IF EXISTS courses CASCADE;
DROP TABLE IF EXISTS languages CASCADE;

-- ---------------------------------------------------------------------
-- 1. languages
-- Master catalog of supported languages (e.g. en, es, fr, de, hi).
-- ---------------------------------------------------------------------
CREATE TABLE languages (
    language_code VARCHAR(5) PRIMARY KEY,
    language_name VARCHAR(50) NOT NULL
);

-- ---------------------------------------------------------------------
-- 2. courses
-- Language learning pairings (source language -> target language).
-- ---------------------------------------------------------------------
CREATE TABLE courses (
    course_id     INT PRIMARY KEY,
    from_lang     VARCHAR(5) NOT NULL REFERENCES languages(language_code) ON DELETE RESTRICT,
    learning_lang VARCHAR(5) NOT NULL REFERENCES languages(language_code) ON DELETE RESTRICT,
    title         VARCHAR(100) NOT NULL,
    launched_on   DATE NOT NULL,
    CONSTRAINT chk_courses_different_languages CHECK (from_lang <> learning_lang)
);

-- ---------------------------------------------------------------------
-- 3. units
-- Curriculum units within each course with CEFR proficiency levels.
-- ---------------------------------------------------------------------
CREATE TABLE units (
    unit_id    INT PRIMARY KEY,
    course_id  INT NOT NULL REFERENCES courses(course_id) ON DELETE CASCADE,
    unit_no    INT NOT NULL,
    title      VARCHAR(100) NOT NULL,
    cefr_level VARCHAR(10) NOT NULL,
    CONSTRAINT chk_units_unit_no_positive CHECK (unit_no > 0),
    CONSTRAINT chk_units_cefr_level CHECK (cefr_level IN ('A1', 'A2', 'B1', 'B2', 'C1')),
    CONSTRAINT uq_units_course_unit_no UNIQUE (course_id, unit_no)
);

-- ---------------------------------------------------------------------
-- 4. lessons
-- Individual lessons within a unit.
-- ---------------------------------------------------------------------
CREATE TABLE lessons (
    lesson_id   INT PRIMARY KEY,
    unit_id     INT NOT NULL REFERENCES units(unit_id) ON DELETE CASCADE,
    lesson_no   INT NOT NULL,
    lesson_type VARCHAR(20) NOT NULL,
    xp_value    INT NOT NULL,
    CONSTRAINT chk_lessons_lesson_no_positive CHECK (lesson_no > 0),
    CONSTRAINT chk_lessons_lesson_type CHECK (lesson_type IN ('LEARN', 'PRACTICE', 'STORY', 'LEGENDARY')),
    CONSTRAINT chk_lessons_xp_value_non_negative CHECK (xp_value >= 0),
    CONSTRAINT uq_lessons_unit_lesson_no UNIQUE (unit_id, lesson_no)
);

-- ---------------------------------------------------------------------
-- 5. learners
-- Registered Duolingo learners, subscription status, and referral tree.
-- ---------------------------------------------------------------------
CREATE TABLE learners (
    learner_id    INT PRIMARY KEY,
    username      VARCHAR(50) NOT NULL UNIQUE,
    email         VARCHAR(100) NOT NULL UNIQUE,
    country_code  VARCHAR(5) NOT NULL,
    daily_goal_xp INT NOT NULL,
    subscription  VARCHAR(20) NOT NULL,
    referred_by   INT REFERENCES learners(learner_id) ON DELETE SET NULL,
    joined_at     TIMESTAMPTZ NOT NULL,
    CONSTRAINT chk_learners_daily_goal_xp CHECK (daily_goal_xp > 0),
    CONSTRAINT chk_learners_subscription CHECK (subscription IN ('FREE', 'SUPER', 'MAX')),
    CONSTRAINT chk_learners_no_self_referral CHECK (referred_by IS NULL OR referred_by <> learner_id)
);

-- ---------------------------------------------------------------------
-- 6. enrollments
-- Tracks which courses a learner is actively or passively enrolled in.
-- ---------------------------------------------------------------------
CREATE TABLE enrollments (
    learner_id  INT NOT NULL REFERENCES learners(learner_id) ON DELETE CASCADE,
    course_id   INT NOT NULL REFERENCES courses(course_id) ON DELETE RESTRICT,
    enrolled_at TIMESTAMPTZ NOT NULL,
    total_xp    INT NOT NULL DEFAULT 0,
    is_active   BOOLEAN NOT NULL DEFAULT true,
    PRIMARY KEY (learner_id, course_id),
    CONSTRAINT chk_enrollments_total_xp_non_negative CHECK (total_xp >= 0)
);

-- ---------------------------------------------------------------------
-- 7. lesson_attempts
-- Logs every lesson attempt with performance, mistakes, and outcomes.
-- ---------------------------------------------------------------------
CREATE TABLE lesson_attempts (
    attempt_id   BIGINT PRIMARY KEY,
    learner_id   INT NOT NULL REFERENCES learners(learner_id) ON DELETE CASCADE,
    lesson_id    INT NOT NULL REFERENCES lessons(lesson_id) ON DELETE RESTRICT,
    started_at   TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    mistakes     INT NOT NULL DEFAULT 0,
    hearts_lost  INT NOT NULL DEFAULT 0,
    xp_earned    INT NOT NULL DEFAULT 0,
    is_perfect   BOOLEAN NOT NULL DEFAULT false,
    device       VARCHAR(20) NOT NULL,
    CONSTRAINT chk_attempts_mistakes_non_negative CHECK (mistakes >= 0),
    CONSTRAINT chk_attempts_hearts_lost_non_negative CHECK (hearts_lost >= 0),
    CONSTRAINT chk_attempts_xp_earned_non_negative CHECK (xp_earned >= 0),
    CONSTRAINT chk_attempts_hearts_le_mistakes CHECK (hearts_lost <= mistakes),
    CONSTRAINT chk_attempts_device CHECK (device IN ('WEB', 'ANDROID', 'IOS')),
    CONSTRAINT chk_attempts_perfect_mistakes CHECK (NOT is_perfect OR (mistakes = 0 AND completed_at IS NOT NULL)),
    CONSTRAINT chk_attempts_quit_zero_xp CHECK (completed_at IS NOT NULL OR xp_earned = 0),
    CONSTRAINT chk_attempts_started_before_completed CHECK (completed_at IS NULL OR started_at <= completed_at)
);

-- ---------------------------------------------------------------------
-- 8. daily_activity
-- Daily XP aggregates and streak freeze usage for streak continuity.
-- ---------------------------------------------------------------------
CREATE TABLE daily_activity (
    learner_id         INT NOT NULL REFERENCES learners(learner_id) ON DELETE CASCADE,
    activity_date      DATE NOT NULL,
    xp                 INT NOT NULL DEFAULT 0,
    lessons_completed  INT NOT NULL DEFAULT 0,
    used_streak_freeze BOOLEAN NOT NULL DEFAULT false,
    PRIMARY KEY (learner_id, activity_date),
    CONSTRAINT chk_daily_xp_non_negative CHECK (xp >= 0),
    CONSTRAINT chk_daily_lessons_completed_non_negative CHECK (lessons_completed >= 0),
    CONSTRAINT chk_daily_freeze_zero_xp CHECK (NOT used_streak_freeze OR xp = 0)
);

-- ---------------------------------------------------------------------
-- 9. league_memberships
-- Weekly competitive league placements, ranks, and promotion outcomes.
-- ---------------------------------------------------------------------
CREATE TABLE league_memberships (
    learner_id INT NOT NULL REFERENCES learners(learner_id) ON DELETE CASCADE,
    week_start DATE NOT NULL,
    tier       VARCHAR(20) NOT NULL,
    cohort_id  BIGINT NOT NULL,
    weekly_xp  INT NOT NULL DEFAULT 0,
    final_rank INT,
    result     VARCHAR(20),
    PRIMARY KEY (learner_id, week_start),
    CONSTRAINT chk_leagues_tier CHECK (tier IN ('BRONZE', 'SILVER', 'GOLD', 'SAPPHIRE', 'RUBY', 'EMERALD', 'AMETHYST', 'DIAMOND')),
    CONSTRAINT chk_leagues_weekly_xp_non_negative CHECK (weekly_xp >= 0),
    CONSTRAINT chk_leagues_result CHECK (result IS NULL OR result IN ('PROMOTED', 'DEMOTED', 'STAYED')),
    CONSTRAINT chk_leagues_rank_result_together CHECK ((final_rank IS NULL AND result IS NULL) OR (final_rank IS NOT NULL AND result IS NOT NULL)),
    CONSTRAINT chk_leagues_final_rank_range CHECK (final_rank IS NULL OR (final_rank >= 1 AND final_rank <= 30)),
    CONSTRAINT chk_leagues_week_start_monday CHECK (EXTRACT(ISODOW FROM week_start) = 1)
);

-- ---------------------------------------------------------------------
-- 10. achievements
-- Master catalog of milestone badges.
-- ---------------------------------------------------------------------
CREATE TABLE achievements (
    achievement_id INT PRIMARY KEY,
    code           VARCHAR(50) NOT NULL UNIQUE,
    name           VARCHAR(100) NOT NULL
);

-- ---------------------------------------------------------------------
-- 11. learner_achievements
-- Badges unlocked by learners and timestamp of attainment.
-- ---------------------------------------------------------------------
CREATE TABLE learner_achievements (
    learner_id     INT NOT NULL REFERENCES learners(learner_id) ON DELETE CASCADE,
    achievement_id INT NOT NULL REFERENCES achievements(achievement_id) ON DELETE RESTRICT,
    earned_at      TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (learner_id, achievement_id)
);

