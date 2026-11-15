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
| `language_code` | `CHAR(2)` | **PK** | Fixed-length ISO 639-1 code (e.g. `en`, `es`) |
| `language_name` | `VARCHAR(50)` | NOT NULL, UNIQUE | Human-readable; unique across the table |

**Indexes auto-created:** PK on `language_code`.

---

### 2.2 `courses`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `course_id` | `SMALLINT` | **PK** | Only 11 courses; SMALLINT sufficient |
| `from_lang` | `CHAR(2)` | NOT NULL, FK → `languages(language_code)` ON DELETE RESTRICT | Native language of learner |
| `learning_lang` | `CHAR(2)` | NOT NULL, FK → `languages(language_code)` ON DELETE RESTRICT | Language being learnt |
| `title` | `VARCHAR(100)` | NOT NULL, UNIQUE | Course display name |
| `launched_on` | `DATE` | NOT NULL | Date only — no time component in data |

**CHECK:** `from_lang <> learning_lang` — a course cannot teach a language in itself.  
**Indexes auto-created:** PK on `course_id`; UNIQUE on `title`.

---

### 2.3 `units`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `unit_id` | `SMALLINT` | **PK** | 220 rows; SMALLINT sufficient |
| `course_id` | `SMALLINT` | NOT NULL, FK → `courses(course_id)` ON DELETE CASCADE | Deleting a course deletes its units |
| `unit_no` | `SMALLINT` | NOT NULL, CHECK ≥ 1 | Sequential ordering within course |
| `title` | `VARCHAR(100)` | NOT NULL | Unit display name |
| `cefr_level` | `VARCHAR(2)` | NOT NULL, CHECK IN ('A1','A2','B1','B2','C1') | CEFR standard language levels only |

**UNIQUE:** `(course_id, unit_no)` — unit number is unique within a course.  
**Indexes auto-created:** PK on `unit_id`; UNIQUE on `(course_id, unit_no)`.

---

### 2.4 `lessons`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `lesson_id` | `SMALLINT` | **PK** | 1,760 rows; SMALLINT sufficient |
| `unit_id` | `SMALLINT` | NOT NULL, FK → `units(unit_id)` ON DELETE CASCADE | Deleting a unit deletes its lessons |
| `lesson_no` | `SMALLINT` | NOT NULL, CHECK ≥ 1 | Sequential ordering within unit |
| `lesson_type` | `VARCHAR(10)` | NOT NULL, CHECK IN ('LEARN','PRACTICE','STORY','LEGENDARY') | Only these lesson types exist |
| `xp_value` | `SMALLINT` | NOT NULL, CHECK ≥ 0 | XP awarded on completion; cannot be negative |

**UNIQUE:** `(unit_id, lesson_no)` — lesson number is unique within a unit.  
**Indexes auto-created:** PK on `lesson_id`; UNIQUE on `(unit_id, lesson_no)`.

---

### 2.5 `learners`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `learner_id` | `INTEGER` | **PK** | 30,000 rows; INTEGER needed |
| `username` | `VARCHAR(50)` | NOT NULL, UNIQUE | Login handle; R11/R16 search by this |
| `email` | `VARCHAR(100)` | NOT NULL, UNIQUE | Sign-in identifier; must be unique |
| `country_code` | `CHAR(2)` | NOT NULL | ISO 3166-1 alpha-2 (e.g. `IN`, `US`) |
| `daily_goal_xp` | `SMALLINT` | NOT NULL, CHECK IN (10,20,30,50) | Only these goal values are offered in the app |
| `subscription` | `VARCHAR(10)` | NOT NULL, CHECK IN ('FREE','SUPER','MAX') | Three subscription tiers |
| `referred_by` | `INTEGER` | NULL, FK → `learners(learner_id)` ON DELETE SET NULL | Self-referential; NULL = not referred. SET NULL so referrer deletion doesn't cascade |
| `joined_at` | `TIMESTAMPTZ` | NOT NULL | Account creation timestamp with timezone |

**CHECK:** `referred_by <> learner_id` — a learner cannot refer themselves.  
**Indexes auto-created:** PK on `learner_id`; UNIQUE on `username`; UNIQUE on `email`.

**NULL reasoning:** `referred_by` is NULL for the majority of learners (most joined organically). This is intentional and must be handled with `IS NOT NULL` in R13 — see Phase 1, Assumption 5.

---

### 2.6 `enrollments`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `learner_id` | `INTEGER` | **PK** (part), FK → `learners(learner_id)` ON DELETE CASCADE | Deleting a learner removes their enrollments |
| `course_id` | `SMALLINT` | **PK** (part), FK → `courses(course_id)` ON DELETE RESTRICT | Courses shouldn't disappear while learners are enrolled |
| `enrolled_at` | `TIMESTAMPTZ` | NOT NULL | When the learner enrolled |
| `total_xp` | `INTEGER` | NOT NULL DEFAULT 0, CHECK ≥ 0 | Denormalized XP cache (see note below) |
| `is_active` | `BOOLEAN` | NOT NULL DEFAULT TRUE | Whether the learner is currently active in this course |

**PK:** `(learner_id, course_id)` — M:N junction table. A learner can enrol in multiple courses; each course has many learners.

**Denormalization note:** `total_xp` could be derived from `SUM(lesson_attempts.xp_earned)` per course per learner. It is kept as a cached column to avoid scanning 188k attempts on every home-screen load (R02). Its correctness is verified in integrity checks.

---

### 2.7 `lesson_attempts`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `attempt_id` | `INTEGER` | **PK** | 188,300 rows; INTEGER required |
| `learner_id` | `INTEGER` | NOT NULL, FK → `learners(learner_id)` ON DELETE CASCADE | GDPR: learner deletion removes their data |
| `lesson_id` | `SMALLINT` | NOT NULL, FK → `lessons(lesson_id)` ON DELETE RESTRICT | Historical records; don't silently delete |
| `started_at` | `TIMESTAMPTZ` | NOT NULL | When the attempt began |
| `completed_at` | `TIMESTAMPTZ` | NULL | NULL = abandoned/quit before finishing |
| `mistakes` | `SMALLINT` | NOT NULL DEFAULT 0, CHECK ≥ 0 | Errors made during attempt |
| `hearts_lost` | `SMALLINT` | NOT NULL DEFAULT 0, CHECK ≥ 0 | Hearts deducted |
| `xp_earned` | `SMALLINT` | NOT NULL DEFAULT 0, CHECK ≥ 0 | XP awarded |
| `is_perfect` | `BOOLEAN` | NOT NULL DEFAULT FALSE | Derived: true iff `mistakes = 0` and completed |
| `device` | `VARCHAR(10)` | NOT NULL, CHECK IN ('ANDROID','IOS','WEB') | Platform used |

**CHECKs:**
- `hearts_lost <= mistakes` — can't lose more hearts than mistakes made
- `(completed_at IS NULL) OR (completed_at >= started_at)` — can't finish before starting
- `(completed_at IS NOT NULL) OR (xp_earned = 0)` — quit attempts earn 0 XP
- `(mistakes = 0) = is_perfect` — perfect if and only if zero mistakes

**NULL reasoning:**
- `completed_at` is NULL for abandoned attempts (~quit rate). This is by design.
- All other columns are NOT NULL with sensible defaults.

**Denormalization note:** `is_perfect` is derivable (`mistakes = 0 AND completed_at IS NOT NULL`) but stored explicitly for query simplicity in R17 and analytics filters.

---

### 2.8 `daily_activity`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `learner_id` | `INTEGER` | **PK** (part), FK → `learners(learner_id)` ON DELETE CASCADE | Activity tied to learner |
| `activity_date` | `DATE` | **PK** (part) | Calendar date (no time needed) |
| `xp` | `INTEGER` | NOT NULL DEFAULT 0, CHECK ≥ 0 | Total XP earned on this date |
| `lessons_completed` | `SMALLINT` | NOT NULL DEFAULT 0, CHECK ≥ 0 | Lessons finished on this date |
| `used_streak_freeze` | `BOOLEAN` | NOT NULL DEFAULT FALSE | Whether a streak freeze was used |

**PK:** `(learner_id, activity_date)` — one row per learner per day.  
**CHECK:** `(used_streak_freeze = FALSE) OR (xp = 0)` — a streak freeze day has no lesson XP.

**Denormalization note:** `xp` could be summed from `lesson_attempts.xp_earned` per learner per day. Stored here for fast streak calculation (R03) and daily goal ring (R04) without scanning 188k attempts.

---

### 2.9 `league_memberships`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `learner_id` | `INTEGER` | **PK** (part), FK → `learners(learner_id)` ON DELETE CASCADE | Membership tied to learner |
| `week_start` | `DATE` | **PK** (part) | Week identifier; always a Monday |
| `tier` | `VARCHAR(10)` | NOT NULL, CHECK IN ('BRONZE','SILVER','GOLD','SAPPHIRE','RUBY','EMERALD','AMETHYST','PEARL','OBSIDIAN','DIAMOND') | Valid Duolingo league tiers |
| `cohort_id` | `INTEGER` | NOT NULL | Group of ~30 learners competing together |
| `weekly_xp` | `INTEGER` | NOT NULL DEFAULT 0, CHECK ≥ 0 | XP earned in this league week |
| `final_rank` | `SMALLINT` | NULL | NULL until W04 closes the week |
| `result` | `VARCHAR(10)` | NULL, CHECK IN ('PROMOTED','DEMOTED','STAYED') | NULL until W04 closes the week |

**PK:** `(learner_id, week_start)` — one league entry per learner per week.  
**CHECKs:**
- `EXTRACT(DOW FROM week_start) = 1` — always a Monday (DOW=1 in PostgreSQL)
- `(final_rank IS NULL) = (result IS NULL)` — rank and result are set together by W04

**NULL reasoning:** `final_rank` and `result` are NULL for the current (open) week and become NOT NULL after W04 runs. This is by design.

---

### 2.10 `achievements`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `achievement_id` | `SMALLINT` | **PK** | 10 rows; SMALLINT sufficient |
| `code` | `VARCHAR(20)` | NOT NULL, UNIQUE | Machine-readable key (e.g. `XP_100`, `FIRST_LESSON`) |
| `name` | `VARCHAR(50)` | NOT NULL, UNIQUE | Display name (e.g. "First Lesson") |

---

### 2.11 `learner_achievements`

| Column | Type | Constraints | Why |
|---|---|---|---|
| `learner_id` | `INTEGER` | **PK** (part), FK → `learners(learner_id)` ON DELETE CASCADE | Tied to learner |
| `achievement_id` | `SMALLINT` | **PK** (part), FK → `achievements(achievement_id)` ON DELETE RESTRICT | Don't delete achievement definitions |
| `earned_at` | `TIMESTAMPTZ` | NOT NULL | When the badge was awarded |

**PK:** `(learner_id, achievement_id)` — a learner earns each badge at most once (enforced by PK; W05 uses `ON CONFLICT DO NOTHING`).

---

## 3. CHECK Constraints Summary

| # | Table | Constraint | Rule |
|---|---|---|---|
| 1 | `courses` | `from_lang <> learning_lang` | Can't learn same language you speak |
| 2 | `units` | `cefr_level IN ('A1','A2','B1','B2','C1')` | Standard CEFR levels only |
| 3 | `units` | `unit_no >= 1` | Positive ordering |
| 4 | `lessons` | `lesson_type IN ('LEARN','PRACTICE','STORY','LEGENDARY')` | Valid lesson types only |
| 5 | `lessons` | `xp_value >= 0` | No negative XP |
| 6 | `learners` | `daily_goal_xp IN (10, 20, 30, 50)` | App only offers these values |
| 7 | `learners` | `subscription IN ('FREE','SUPER','MAX')` | Three valid tiers |
| 8 | `learners` | `referred_by <> learner_id` | Self-referral not allowed |
| 9 | `lesson_attempts` | `device IN ('ANDROID','IOS','WEB')` | Valid device types |
| 10 | `lesson_attempts` | `hearts_lost <= mistakes` | Can't lose more hearts than mistakes |
| 11 | `lesson_attempts` | `(completed_at IS NULL) OR (completed_at >= started_at)` | Completion after start |
| 12 | `lesson_attempts` | `(completed_at IS NOT NULL) OR (xp_earned = 0)` | Quit = 0 XP |
| 13 | `lesson_attempts` | `(mistakes = 0) = is_perfect` | Perfect iff zero mistakes |
| 14 | `daily_activity` | `xp >= 0` | Non-negative XP |
| 15 | `daily_activity` | `(used_streak_freeze = FALSE) OR (xp = 0)` | Freeze day has 0 lesson XP |
| 16 | `league_memberships` | `EXTRACT(DOW FROM week_start) = 1` | Weeks start on Monday |
| 17 | `league_memberships` | `(final_rank IS NULL) = (result IS NULL)` | Set together by W04 |
| 18 | `league_memberships` | `result IN ('PROMOTED','DEMOTED','STAYED')` | Valid outcomes only |

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

See [`diagrams/er_diagram.png`](../diagrams/er_diagram.png) for the visual ER diagram.

```mermaid
erDiagram
    languages {
        char2 language_code PK
        varchar50 language_name
    }
    courses {
        smallint course_id PK
        char2 from_lang FK
        char2 learning_lang FK
        varchar100 title
        date launched_on
    }
    units {
        smallint unit_id PK
        smallint course_id FK
        smallint unit_no
        varchar100 title
        varchar2 cefr_level
    }
    lessons {
        smallint lesson_id PK
        smallint unit_id FK
        smallint lesson_no
        varchar10 lesson_type
        smallint xp_value
    }
    learners {
        integer learner_id PK
        varchar50 username
        varchar100 email
        char2 country_code
        smallint daily_goal_xp
        varchar10 subscription
        integer referred_by FK
        timestamptz joined_at
    }
    enrollments {
        integer learner_id PK-FK
        smallint course_id PK-FK
        timestamptz enrolled_at
        integer total_xp
        boolean is_active
    }
    lesson_attempts {
        integer attempt_id PK
        integer learner_id FK
        smallint lesson_id FK
        timestamptz started_at
        timestamptz completed_at
        smallint mistakes
        smallint hearts_lost
        smallint xp_earned
        boolean is_perfect
        varchar10 device
    }
    daily_activity {
        integer learner_id PK-FK
        date activity_date PK
        integer xp
        smallint lessons_completed
        boolean used_streak_freeze
    }
    league_memberships {
        integer learner_id PK-FK
        date week_start PK
        varchar10 tier
        integer cohort_id
        integer weekly_xp
        smallint final_rank
        varchar10 result
    }
    achievements {
        smallint achievement_id PK
        varchar20 code
        varchar50 name
    }
    learner_achievements {
        integer learner_id PK-FK
        smallint achievement_id PK-FK
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
2.  courses                (FK → languages)
3.  units                  (FK → courses)
4.  lessons                (FK → units)
5.  learners               (self-FK referred_by: added after bulk load)
6.  enrollments            (FK → learners, courses)
7.  lesson_attempts        (FK → learners, lessons)
8.  daily_activity         (FK → learners)
9.  league_memberships     (FK → learners)
10. achievements           (no dependencies)
11. learner_achievements   (FK → learners, achievements)
```

**Note on `learners.referred_by`:** The self-referential FK is added after all learner rows are loaded to avoid forward-reference violations during bulk insert.

---

## 9. Integrity Check Results

*To be filled in after `sql/02_load_data.sql` runs successfully.*

### 9.1 Row Count Verification

| Table | Expected | Actual | Match? |
|---|---:|---:|---|
| `languages` | 10 | — | — |
| `courses` | 11 | — | — |
| `units` | 220 | — | — |
| `lessons` | 1,760 | — | — |
| `learners` | 30,000 | — | — |
| `enrollments` | 37,500 | — | — |
| `lesson_attempts` | 188,300 | — | — |
| `daily_activity` | 189,109 | — | — |
| `league_memberships` | 28,598 | — | — |
| `achievements` | 10 | — | — |
| `learner_achievements` | 38,860 | — | — |

### 9.2 Business Rule Checks

| Check | Query Result | Pass? |
|---|---|---|
| Learners only attempt lessons in courses they're enrolled in | — bad attempts | — |
| League cohort size ≤ 30 per week | — cohorts > 30 | — |
| `completed_at >= started_at` for all completed attempts | — violations | — |
| Perfect attempts have `mistakes = 0` | — violations | — |
| Quit attempts (`completed_at IS NULL`) have `xp_earned = 0` | — violations | — |

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
| PK on `language_code` | `languages` | B-tree |
| PK on `course_id`; UNIQUE on `title` | `courses` | B-tree |
| PK on `unit_id`; UNIQUE on `(course_id, unit_no)` | `units` | B-tree |
| PK on `lesson_id`; UNIQUE on `(unit_id, lesson_no)` | `lessons` | B-tree |
| PK on `learner_id`; UNIQUE on `username`; UNIQUE on `email` | `learners` | B-tree |
| PK on `(learner_id, course_id)` | `enrollments` | B-tree |
| PK on `attempt_id` | `lesson_attempts` | B-tree |
| PK on `(learner_id, activity_date)` | `daily_activity` | B-tree |
| PK on `(learner_id, week_start)` | `league_memberships` | B-tree |
| PK on `achievement_id`; UNIQUE on `code`; UNIQUE on `name` | `achievements` | B-tree |
| PK on `(learner_id, achievement_id)` | `learner_achievements` | B-tree |

**No manual indexes are created in Phase 2.** Additional indexes will be added only in Phase 4 (`sql/05_indexes.sql`).

