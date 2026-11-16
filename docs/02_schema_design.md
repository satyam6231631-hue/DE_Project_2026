# Phase 2: Schema Design

**Project:** Duolingo Language Learning Database  
**Team:** Mudit Jindal (Lead), Satyam, Shirsh, Nilesh Saini

---

## 1. Source Files

| CSV File | Rows | Tables Created |
|---|---:|---|
| `languages.csv` | 10 | `languages` |
| `courses.csv` | 11 | `courses` |
| `units.csv` | 220 | `units` |
| `lessons.csv` | 1,760 | `lessons` |
| `learners.csv` | 30,000 | `learners` |
| `enrollments.csv` | 37,500 | `enrollments` |
| `lesson_attempts.csv` | 188,300 | `lesson_attempts` |
| `daily_activity.csv` | 189,109 | `daily_activity` |
| `league_memberships.csv` | 28,598 | `league_memberships` |
| `achievements.csv` | 10 | `achievements` |
| `learner_achievements.csv` | 38,860 | `learner_achievements` |

All tables are created inside the schema `duolingo` (`CREATE SCHEMA duolingo; SET search_path TO duolingo;`).

---

## 2. Data Dictionary

### 2.1 `languages`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `language_code` | `VARCHAR(5)` | **PK** | Fixed/short ISO 639-1 code (e.g. `en`, `es`) |
| `language_name` | `VARCHAR(50)` | NOT NULL, UNIQUE | Human-readable; unique across the catalog |

**Indexes auto-created:** PK on `language_code`; UNIQUE on `language_name`.

---

### 2.2 `courses`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `course_id` | `INT` | **PK** | Surrogate identifier for language course |
| `from_lang` | `VARCHAR(5)` | NOT NULL, FK → `languages(language_code)` ON DELETE RESTRICT | Native language of learner |
| `learning_lang` | `VARCHAR(5)` | NOT NULL, FK → `languages(language_code)` ON DELETE RESTRICT | Language being learnt |
| `title` | `VARCHAR(100)` | NOT NULL, UNIQUE | Course display name |
| `launched_on` | `DATE` | NOT NULL | Date only — no time component in data |

**CHECK:** `chk_courses_different_languages CHECK (from_lang <> learning_lang)` — a course cannot teach a language in itself.  
**Indexes auto-created:** PK on `course_id`; UNIQUE on `title`.

---

### 2.3 `units`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `unit_id` | `INT` | **PK** | Surrogate identifier for unit |
| `course_id` | `INT` | NOT NULL, FK → `courses(course_id)` ON DELETE CASCADE | Deleting a course deletes its units |
| `unit_no` | `INT` | NOT NULL, CHECK > 0 | Sequential ordering within course |
| `title` | `VARCHAR(100)` | NOT NULL | Unit display name |
| `cefr_level` | `VARCHAR(10)` | NOT NULL, CHECK IN ('A1','A2','B1','B2','C1') | CEFR standard language levels only |

**UNIQUE:** `uq_units_course_unit_no UNIQUE (course_id, unit_no)` — unit number is unique within a course.  
**Indexes auto-created:** PK on `unit_id`; UNIQUE on `(course_id, unit_no)`.

---

### 2.4 `lessons`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `lesson_id` | `INT` | **PK** | Surrogate identifier for lesson |
| `unit_id` | `INT` | NOT NULL, FK → `units(unit_id)` ON DELETE CASCADE | Deleting a unit deletes its lessons |
| `lesson_no` | `INT` | NOT NULL, CHECK > 0 | Sequential ordering within unit |
| `lesson_type` | `VARCHAR(20)` | NOT NULL, CHECK IN ('LEARN','PRACTICE','STORY','LEGENDARY') | Only these lesson types exist |
| `xp_value` | `INT` | NOT NULL, CHECK ≥ 0 | XP awarded on completion; non-negative |

**UNIQUE:** `uq_lessons_unit_lesson_no UNIQUE (unit_id, lesson_no)` — lesson number is unique within a unit.  
**Indexes auto-created:** PK on `lesson_id`; UNIQUE on `(unit_id, lesson_no)`.

---

### 2.5 `learners`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `learner_id` | `INT` | **PK** | Surrogate identifier for learner |
| `username` | `VARCHAR(50)` | NOT NULL, UNIQUE | Login handle; R11/R16 search by this |
| `email` | `VARCHAR(100)` | NOT NULL, UNIQUE | Sign-in identifier; must be unique |
| `country_code` | `VARCHAR(5)` | NOT NULL | Country code (e.g. `IN`, `US`) |
| `daily_goal_xp` | `INT` | NOT NULL, CHECK IN (10,20,30,50) | Only these goal values are offered in the app |
| `subscription` | `VARCHAR(20)` | NOT NULL, CHECK IN ('FREE','SUPER','MAX') | Three subscription tiers |
| `referred_by` | `INT` | NULL, FK → `learners(learner_id)` ON DELETE SET NULL | Self-referential; NULL = not referred. SET NULL so referrer deletion doesn't cascade |
| `joined_at` | `TIMESTAMPTZ` | NOT NULL | Account creation timestamp with timezone |

**CHECK:** `chk_learners_no_self_referral CHECK (referred_by IS NULL OR referred_by <> learner_id)` — a learner cannot refer themselves.  
**Indexes auto-created:** PK on `learner_id`; UNIQUE on `username`; UNIQUE on `email`.

**NULL reasoning:** `referred_by` is NULL for the majority of learners (most joined organically). This is intentional and must be handled with `IS NOT NULL` in R13 — see Phase 1, Assumption 5.

---

### 2.6 `enrollments`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `learner_id` | `INT` | **PK** (part), FK → `learners(learner_id)` ON DELETE CASCADE | Deleting a learner removes their enrollments |
| `course_id` | `INT` | **PK** (part), FK → `courses(course_id)` ON DELETE RESTRICT | Courses shouldn't disappear while learners are enrolled |
| `enrolled_at` | `TIMESTAMPTZ` | NOT NULL | When the learner enrolled |
| `total_xp` | `INT` | NOT NULL DEFAULT 0, CHECK ≥ 0 | Denormalized XP cache (see note below) |
| `is_active` | `BOOLEAN` | NOT NULL DEFAULT TRUE | Whether the learner is currently active in this course |

**PK:** `(learner_id, course_id)` — M:N junction table. A learner can enrol in multiple courses; each course has many learners.

**Denormalization note:** `total_xp` could be derived from `SUM(lesson_attempts.xp_earned)` per course per learner. It is kept as a cached column to avoid scanning 188k attempts on every home-screen load (R02). Its correctness is verified in integrity checks.

---

### 2.7 `lesson_attempts`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `attempt_id` | `BIGINT` | **PK** | 188,300 rows; sparse IDs up to 11M+, W01 inserts 90M+; BIGINT safe for 20× scale |
| `learner_id` | `INT` | NOT NULL, FK → `learners(learner_id)` ON DELETE CASCADE | GDPR: learner deletion removes their data |
| `lesson_id` | `INT` | NOT NULL, FK → `lessons(lesson_id)` ON DELETE RESTRICT | Historical records; don't silently delete |
| `started_at` | `TIMESTAMPTZ` | NOT NULL | When the attempt began |
| `completed_at` | `TIMESTAMPTZ` | NULL | NULL = abandoned/quit before finishing |
| `mistakes` | `INT` | NOT NULL DEFAULT 0, CHECK ≥ 0 | Errors made during attempt |
| `hearts_lost` | `INT` | NOT NULL DEFAULT 0, CHECK ≥ 0 | Hearts deducted |
| `xp_earned` | `INT` | NOT NULL DEFAULT 0, CHECK ≥ 0 | XP awarded |
| `is_perfect` | `BOOLEAN` | NOT NULL DEFAULT FALSE | Whether attempt is marked perfect |
| `device` | `VARCHAR(20)` | NOT NULL, CHECK IN ('WEB','ANDROID','IOS') | Platform used |

**CHECKs:**
- `chk_attempts_hearts_le_mistakes CHECK (hearts_lost <= mistakes)` — can't lose more hearts than mistakes made
- `chk_attempts_started_before_completed CHECK (completed_at IS NULL OR started_at <= completed_at)` — can't finish before starting
- `chk_attempts_quit_zero_xp CHECK (completed_at IS NOT NULL OR xp_earned = 0)` — quit attempts earn 0 XP
- `chk_attempts_perfect_mistakes CHECK (NOT is_perfect OR (mistakes = 0 AND completed_at IS NOT NULL))` — chosen one-sided (perfect must be justified) rather than iff, so a legitimately unflagged zero-mistake attempt can never break a future load.

**NULL reasoning:**
- `completed_at` is NULL for abandoned attempts (~quit rate). This is by design.
- All other columns are NOT NULL with sensible defaults.

**Denormalization note:** `is_perfect` is derivable (`mistakes = 0 AND completed_at IS NOT NULL`) but stored explicitly for query simplicity in R17 and analytics filters.

---

### 2.8 `daily_activity`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `learner_id` | `INT` | **PK** (part), FK → `learners(learner_id)` ON DELETE CASCADE | Activity tied to learner |
| `activity_date` | `DATE` | **PK** (part) | Calendar date (no time needed) |
| `xp` | `INT` | NOT NULL DEFAULT 0, CHECK ≥ 0 | Total XP earned on this date |
| `lessons_completed` | `INT` | NOT NULL DEFAULT 0, CHECK ≥ 0 | Lessons finished on this date |
| `used_streak_freeze` | `BOOLEAN` | NOT NULL DEFAULT FALSE | Whether a streak freeze was used |

**PK:** `(learner_id, activity_date)` — one row per learner per day.  
**CHECK:** `chk_daily_freeze_zero_xp CHECK (NOT used_streak_freeze OR xp = 0)` — a streak freeze day has no lesson XP.

**Denormalization note:** `xp` could be summed from `lesson_attempts.xp_earned` per learner per day. Stored here for fast streak calculation (R03) and daily goal ring (R04) without scanning 188k attempts.

---

### 2.9 `league_memberships`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `learner_id` | `INT` | **PK** (part), FK → `learners(learner_id)` ON DELETE CASCADE | Membership tied to learner |
| `week_start` | `DATE` | **PK** (part) | Week identifier; always a Monday |
| `tier` | `VARCHAR(20)` | NOT NULL, CHECK IN ('BRONZE','SILVER','GOLD','SAPPHIRE','RUBY','EMERALD','AMETHYST','DIAMOND') | Valid 8 league tiers present in data |
| `cohort_id` | `BIGINT` | NOT NULL | Group of ~30 learners competing together |
| `weekly_xp` | `INT` | NOT NULL DEFAULT 0, CHECK ≥ 0 | XP earned in this league week |
| `final_rank` | `INT` | NULL | NULL until W04 closes the week |
| `result` | `VARCHAR(20)` | NULL, CHECK IN ('PROMOTED','DEMOTED','STAYED') | NULL until W04 closes the week |

**PK:** `(learner_id, week_start)` — one league entry per learner per week.  
**CHECKs:**
- `chk_leagues_week_start_monday CHECK (EXTRACT(ISODOW FROM week_start) = 1)` — always a Monday (ISODOW=1 in PostgreSQL)
- `chk_leagues_rank_result_together CHECK ((final_rank IS NULL AND result IS NULL) OR (final_rank IS NOT NULL AND result IS NOT NULL))` — rank and result are set together by W04
- `chk_leagues_final_rank_range CHECK (final_rank IS NULL OR (final_rank >= 1 AND final_rank <= 30))` — cohort rank bounds

**NULL reasoning:** `final_rank` and `result` are NULL for the current (open) week and become NOT NULL after W04 runs. This is by design.

---

### 2.10 `achievements`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `achievement_id` | `INT` | **PK** | Surrogate identifier for badge |
| `code` | `VARCHAR(50)` | NOT NULL, UNIQUE | Machine-readable key (e.g. `XP_100`, `FIRST_LESSON`) |
| `name` | `VARCHAR(100)` | NOT NULL, UNIQUE | Display name (e.g. "First Lesson") |

**Indexes auto-created:** PK on `achievement_id`; UNIQUE on `code`; UNIQUE on `name`.

---

### 2.11 `learner_achievements`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `learner_id` | `INT` | **PK** (part), FK → `learners(learner_id)` ON DELETE CASCADE | Tied to learner |
| `achievement_id` | `INT` | **PK** (part), FK → `achievements(achievement_id)` ON DELETE RESTRICT | Don't delete achievement definitions |
| `earned_at` | `TIMESTAMPTZ` | NOT NULL | When the badge was awarded |

**PK:** `(learner_id, achievement_id)` — a learner earns each badge at most once (enforced by PK; W05 uses `ON CONFLICT DO NOTHING`).

---

## 3. CHECK Constraints Summary (27 Named CHECK Constraints)

| # | Table | Constraint Name | SQL Expression | Business Rule Enforced |
|---|---|---|---|---|
| 1 | `courses` | `chk_courses_different_languages` | `from_lang <> learning_lang` | Source and target languages must differ |
| 2 | `units` | `chk_units_unit_no_positive` | `unit_no > 0` | Unit number must be positive |
| 3 | `units` | `chk_units_cefr_level` | `cefr_level IN ('A1', 'A2', 'B1', 'B2', 'C1')` | Standard CEFR levels only |
| 4 | `lessons` | `chk_lessons_lesson_no_positive` | `lesson_no > 0` | Lesson number must be positive |
| 5 | `lessons` | `chk_lessons_lesson_type` | `lesson_type IN ('LEARN', 'PRACTICE', 'STORY', 'LEGENDARY')` | Only valid lesson types allowed |
| 6 | `lessons` | `chk_lessons_xp_value_non_negative` | `xp_value >= 0` | XP values cannot be negative |
| 7 | `learners` | `chk_learners_daily_goal_xp` | `daily_goal_xp IN (10, 20, 30, 50)` | Allowed daily goals supported by UI |
| 8 | `learners` | `chk_learners_subscription` | `subscription IN ('FREE', 'SUPER', 'MAX')` | Valid subscription tiers |
| 9 | `learners` | `chk_learners_no_self_referral` | `referred_by IS NULL OR referred_by <> learner_id` | Learner cannot refer themselves |
| 10 | `enrollments` | `chk_enrollments_total_xp_non_negative` | `total_xp >= 0` | Cumulative course XP cannot be negative |
| 11 | `lesson_attempts` | `chk_attempts_mistakes_non_negative` | `mistakes >= 0` | Mistakes count must be non-negative |
| 12 | `lesson_attempts` | `chk_attempts_hearts_lost_non_negative` | `hearts_lost >= 0` | Hearts lost must be non-negative |
| 13 | `lesson_attempts` | `chk_attempts_xp_earned_non_negative` | `xp_earned >= 0` | XP earned must be non-negative |
| 14 | `lesson_attempts` | `chk_attempts_hearts_le_mistakes` | `hearts_lost <= mistakes` | Hearts lost cannot exceed mistake count |
| 15 | `lesson_attempts` | `chk_attempts_device` | `device IN ('WEB', 'ANDROID', 'IOS')` | Supported device platforms only |
| 16 | `lesson_attempts` | `chk_attempts_perfect_mistakes` | `NOT is_perfect OR (mistakes = 0 AND completed_at IS NOT NULL)` | Perfect attempt implies 0 mistakes and completed |
| 17 | `lesson_attempts` | `chk_attempts_quit_zero_xp` | `completed_at IS NOT NULL OR xp_earned = 0` | Quit/abandoned attempts cannot award XP |
| 18 | `lesson_attempts` | `chk_attempts_started_before_completed` | `completed_at IS NULL OR started_at <= completed_at` | Completion cannot precede start time |
| 19 | `daily_activity` | `chk_daily_xp_non_negative` | `xp >= 0` | Daily XP cannot be negative |
| 20 | `daily_activity` | `chk_daily_lessons_completed_non_negative` | `lessons_completed >= 0` | Completed lessons count cannot be negative |
| 21 | `daily_activity` | `chk_daily_freeze_zero_xp` | `NOT used_streak_freeze OR xp = 0` | Streak freeze day has 0 lesson XP |
| 22 | `league_memberships` | `chk_leagues_tier` | `tier IN ('BRONZE', 'SILVER', 'GOLD', 'SAPPHIRE', 'RUBY', 'EMERALD', 'AMETHYST', 'DIAMOND')` | Valid 8 Duolingo league tiers |
| 23 | `league_memberships` | `chk_leagues_weekly_xp_non_negative` | `weekly_xp >= 0` | Weekly XP cannot be negative |
| 24 | `league_memberships` | `chk_leagues_result` | `result IS NULL OR result IN ('PROMOTED', 'DEMOTED', 'STAYED')` | Valid outcome results |
| 25 | `league_memberships` | `chk_leagues_rank_result_together` | `(final_rank IS NULL AND result IS NULL) OR (final_rank IS NOT NULL AND result IS NOT NULL)` | Rank and result must be assigned together |
| 26 | `league_memberships` | `chk_leagues_final_rank_range` | `final_rank IS NULL OR (final_rank >= 1 AND final_rank <= 30)` | Cohort rank within valid bounds (1–30) |
| 27 | `league_memberships` | `chk_leagues_week_start_monday` | `EXTRACT(ISODOW FROM week_start) = 1` | League week must start on a Monday |

*Note: In addition to the 27 CHECK constraints above, the schema defines 8 natural UNIQUE candidate keys (`languages.language_name`, `courses.title`, `units(course_id, unit_no)`, `lessons(unit_id, lesson_no)`, `learners.username`, `learners.email`, `achievements.code`, `achievements.name`).*

---

## 4. Foreign Keys and ON DELETE Rules

| FK (child → parent) | ON DELETE | Rationale |
|---|---|---|
| `courses.from_lang` → `languages` | RESTRICT | Deleting a language is rare and catastrophic |
| `courses.learning_lang` → `languages` | RESTRICT | Same |
| `units.course_id` → `courses` | CASCADE | Units have no meaning without their course |
| `lessons.unit_id` → `units` | CASCADE | Lessons have no meaning without their unit |
| `learners.referred_by` → `learners` | SET NULL | Referrer can leave; don't delete the referred learner |
| `enrollments.learner_id` → `learners` | CASCADE | Learner leaves → remove their enrollments |
| `enrollments.course_id` → `courses` | RESTRICT | Course shouldn't vanish with active learners |
| `lesson_attempts.learner_id` → `learners` | CASCADE | GDPR right-to-erasure |
| `lesson_attempts.lesson_id` → `lessons` | RESTRICT | Historical records; don't silently delete |
| `daily_activity.learner_id` → `learners` | CASCADE | Activity is tied to the learner |
| `league_memberships.learner_id` → `learners` | CASCADE | Membership is tied to the learner |
| `learner_achievements.learner_id` → `learners` | CASCADE | Achievements tied to learner |
| `learner_achievements.achievement_id` → `achievements` | RESTRICT | Don't delete badge definitions |

---

## 5. Relationships and Cardinalities

| Relationship | Type | Note |
|---|---|---|
| `languages` → `courses` | 1:N (via from_lang & learning_lang) | One language appears in many courses |
| `courses` → `units` | 1:N | One course has many units |
| `units` → `lessons` | 1:N | One unit has many lessons |
| `learners` ↔ `courses` (via `enrollments`) | M:N | One learner enrols in many courses; one course has many learners |
| `learners` → `lesson_attempts` | 1:N | One learner makes many attempts |
| `lessons` → `lesson_attempts` | 1:N | One lesson is attempted many times |
| `learners` → `daily_activity` | 1:N | One activity row per learner per day |
| `learners` → `league_memberships` | 1:N | One membership per learner per week |
| `learners` ↔ `achievements` (via `learner_achievements`) | M:N | A learner earns many badges; each badge earned by many learners |
| `learners` → `learners` (via `referred_by`) | Self-referential 0..1:N | Optional; a learner can refer many others |

---

## 6. Normal Form Analysis

All tables are in **3NF / BCNF**. For each table, every non-key attribute depends on the **whole** primary key and nothing else.

| Table | Primary Key | Functional Dependencies | Normal Form |
|---|---|---|---|
| `languages` | `language_code` | `language_code → language_name` | BCNF |
| `courses` | `course_id` | `course_id → {from_lang, learning_lang, title, launched_on}`; also `(from_lang, learning_lang) → course_id` (candidate key) | BCNF |
| `units` | `unit_id` | `unit_id → {course_id, unit_no, title, cefr_level}`; `(course_id, unit_no) → unit_id` (candidate key) | BCNF |
| `lessons` | `lesson_id` | `lesson_id → {unit_id, lesson_no, lesson_type, xp_value}`; `(unit_id, lesson_no) → lesson_id` (candidate key) | BCNF |
| `learners` | `learner_id` | `learner_id → {username, email, country_code, daily_goal_xp, subscription, referred_by, joined_at}`; `username → learner_id`; `email → learner_id` (candidate keys) | BCNF |
| `enrollments` | `(learner_id, course_id)` | `(learner_id, course_id) → {enrolled_at, total_xp, is_active}` | BCNF |
| `lesson_attempts` | `attempt_id` | `attempt_id → {learner_id, lesson_id, started_at, completed_at, mistakes, hearts_lost, xp_earned, is_perfect, device}` | BCNF |
| `daily_activity` | `(learner_id, activity_date)` | `(learner_id, activity_date) → {xp, lessons_completed, used_streak_freeze}` | BCNF |
| `league_memberships` | `(learner_id, week_start)` | `(learner_id, week_start) → {tier, cohort_id, weekly_xp, final_rank, result}` | BCNF |
| `achievements` | `achievement_id` | `achievement_id → {code, name}`; `code → achievement_id`; `name → achievement_id` (candidate keys) | BCNF |
| `learner_achievements` | `(learner_id, achievement_id)` | `(learner_id, achievement_id) → earned_at` | BCNF |

### Derived/Redundant Columns — Justified Denormalization

| Column | Derivable From | Why Kept |
|---|---|---|
| `enrollments.total_xp` | `SUM(lesson_attempts.xp_earned)` grouped by learner + course | Avoids scanning 188k attempts on every home-screen load (R02) |
| `lesson_attempts.is_perfect` | `mistakes = 0 AND completed_at IS NOT NULL` | Stored for fast filtering in analytics queries (R17); avoids computed expression in WHERE |
| `daily_activity.xp` | `SUM(lesson_attempts.xp_earned)` grouped by learner + date | Avoids daily join to 188k attempts for streak (R03) and daily goal (R04) |
| `league_memberships.weekly_xp` | `SUM(daily_activity.xp)` over the league week | Avoids cross-join to daily_activity for every leaderboard request (R05) |

---

## 7. ER Diagram

See [`diagrams/er_diagram.svg`](../diagrams/er_diagram.svg) for the visual ER diagram.

```mermaid
erDiagram
    languages {
        varchar5 language_code PK
        varchar50 language_name
    }
    courses {
        int course_id PK
        varchar5 from_lang FK
        varchar5 learning_lang FK
        varchar100 title
        date launched_on
    }
    units {
        int unit_id PK
        int course_id FK
        int unit_no
        varchar100 title
        varchar10 cefr_level
    }
    lessons {
        int lesson_id PK
        int unit_id FK
        int lesson_no
        varchar20 lesson_type
        int xp_value
    }
    learners {
        int learner_id PK
        varchar50 username
        varchar100 email
        varchar5 country_code
        int daily_goal_xp
        varchar20 subscription
        int referred_by FK
        timestamptz joined_at
    }
    enrollments {
        int learner_id PK-FK
        int course_id PK-FK
        timestamptz enrolled_at
        int total_xp
        boolean is_active
    }
    lesson_attempts {
        bigint attempt_id PK
        int learner_id FK
        int lesson_id FK
        timestamptz started_at
        timestamptz completed_at
        int mistakes
        int hearts_lost
        int xp_earned
        boolean is_perfect
        varchar20 device
    }
    daily_activity {
        int learner_id PK-FK
        date activity_date PK
        int xp
        int lessons_completed
        boolean used_streak_freeze
    }
    league_memberships {
        int learner_id PK-FK
        date week_start PK
        varchar20 tier
        bigint cohort_id
        int weekly_xp
        int final_rank
        varchar20 result
    }
    achievements {
        int achievement_id PK
        varchar50 code
        varchar100 name
    }
    learner_achievements {
        int learner_id PK-FK
        int achievement_id PK-FK
        timestamptz earned_at
    }

    languages ||--o{ courses : "from_lang"
    languages ||--o{ courses : "learning_lang"
    courses ||--o{ units : "has"
    units ||--o{ lessons : "contains"
    learners ||--o{ enrollments : "enrols"
    courses ||--o{ enrollments : "has learners"
    learners ||--o{ lesson_attempts : "makes"
    lessons ||--o{ lesson_attempts : "attempted via"
    learners ||--o{ daily_activity : "has"
    learners ||--o{ league_memberships : "placed in"
    learners ||--o{ learner_achievements : "earns"
    achievements ||--o{ learner_achievements : "awarded as"
    learners }o--o| learners : "referred_by"
```

---

## 8. Data Loading Order

Tables are loaded in dependency order (parents before children):

```
1.  languages              (no dependencies)
2.  achievements           (no dependencies)
3.  courses                (FK → languages)
4.  units                  (FK → courses)
5.  lessons                (FK → units)
6.  learners               (self-FK referred_by: defined inline)
7.  enrollments            (FK → learners, courses)
8.  lesson_attempts        (FK → learners, lessons)
9.  daily_activity         (FK → learners)
10. league_memberships     (FK → learners)
11. learner_achievements   (FK → learners, achievements)
```

**Note on `learners.referred_by`:** The self-referential FK on `learners.referred_by` is defined inline. This loads without errors because every referral points backward (0 forward references among 8,898 referral rows) and the CSV is sorted ascending by `learner_id`, so referenced rows are always inserted before the rows referring to them.

---

## 9. Integrity Check Results

Executed on PostgreSQL 18.6 via `sql/02_load_data.sql`.

### 9.1 Row Count Verification

| Table | Expected | Actual | Match? |
|---|---:|---:|:---:|
| `languages` | 10 | 10 | ✅ |
| `courses` | 11 | 11 | ✅ |
| `units` | 220 | 220 | ✅ |
| `lessons` | 1,760 | 1,760 | ✅ |
| `learners` | 30,000 | 30,000 | ✅ |
| `enrollments` | 37,500 | 37,500 | ✅ |
| `lesson_attempts` | 188,300 | 188,300 | ✅ |
| `daily_activity` | 189,109 | 189,109 | ✅ |
| `league_memberships` | 28,598 | 28,598 | ✅ |
| `achievements` | 10 | 10 | ✅ |
| `learner_achievements` | 38,860 | 38,860 | ✅ |

### 9.2 Business Rule & Integrity Checks

All date-based checks and benchmarks run with `SET timezone = 'Asia/Kolkata';` to match the seed data's `+05:30` offset.

| Check | Query Result | Status |
|---|---|:---:|
| **Check 1: League cohort size** (No cohort exceeds 30 members) | `0 rows` (max cohort size ≤ 30) | ✅ PASS |
| **Check 2: Valid enrollments** (Learners only attempt lessons in courses they are enrolled in) | `0` attempts without enrollment | ✅ PASS |
| **Check 3: XP integrity** (Daily activity XP equals sum of attempt `xp_earned` per date) | `0` daily XP mismatches | ✅ PASS |
| **Check 4: Referral integrity** (No orphan referrals; all point to existing learners) | `0` invalid referrals | ✅ PASS |
| **Check 5: Perfect attempt validity** (Perfect lessons have `mistakes = 0`, `completed_at` NOT NULL, `xp > 0`) | `0` inconsistent perfect attempts | ✅ PASS |
| **Check 6: Temporal consistency** (`completed_at >= started_at` for all completed attempts) | `0` time ordering violations | ✅ PASS |
| **Check 7: Abandoned attempt XP** (Quit attempts with `completed_at IS NULL` have `xp_earned = 0`) | `0` violations | ✅ PASS |

---

## 10. Data Problems Found

| Problem | Table | Column | Description | Decision |
|---|---|---|---|---|
| NULLs in `referred_by` | `learners` | `referred_by` | ~majority of rows; not referred organically | Expected; FK is nullable; documented in Phase 1 |
| NULLs in `completed_at` | `lesson_attempts` | `completed_at` | Abandoned/quit attempts | Expected; R08 uses this to compute quit rate |
| NULLs in `final_rank`, `result` | `league_memberships` | `final_rank`, `result` | Open/current week not yet closed | Expected; W04 sets them when week closes |

---

## 11. Indexes Created by Constraints

PostgreSQL automatically creates B-tree indexes for every `PRIMARY KEY` and `UNIQUE` constraint:

| Index (auto-created) | Table | Type |
|---|---|---|
| PK on `language_code`; UNIQUE on `language_name` | `languages` | B-tree |
| PK on `course_id`; UNIQUE on `title` | `courses` | B-tree |
| PK on `unit_id`; UNIQUE on `(course_id, unit_no)` (`uq_units_course_unit_no`) | `units` | B-tree |
| PK on `lesson_id`; UNIQUE on `(unit_id, lesson_no)` (`uq_lessons_unit_lesson_no`) | `lessons` | B-tree |
| PK on `learner_id`; UNIQUE on `username`; UNIQUE on `email` | `learners` | B-tree |
| PK on `(learner_id, course_id)` | `enrollments` | B-tree |
| PK on `attempt_id` | `lesson_attempts` | B-tree |
| PK on `(learner_id, activity_date)` | `daily_activity` | B-tree |
| PK on `(learner_id, week_start)` | `league_memberships` | B-tree |
| PK on `achievement_id`; UNIQUE on `code`; UNIQUE on `name` | `achievements` | B-tree |
| PK on `(learner_id, achievement_id)` | `learner_achievements` | B-tree |

**No manual indexes are created in Phase 2.** Additional indexes will be added only in Phase 4 (`sql/05_indexes.sql`).
