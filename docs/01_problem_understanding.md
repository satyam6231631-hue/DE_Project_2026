# Phase 1: Problem Understanding

**Project:** Duolingo Language Learning Database  
**Team:** Mudit Jindal (Lead), Satyam, Shirsh, Nilesh Saini  
**Section:** B/E · B.Tech 2nd Year · DBMS Project 2026

---

## Context

Duolingo teaches languages through short **lessons** organised into **units** inside **courses**
(e.g. English → Spanish). **Learners** enrol in courses, make **lesson attempts** (earning XP,
losing hearts on mistakes, or quitting), and maintain daily **streaks**. Each week learners
compete in **leagues** of ~30 people. The platform supports **referrals** and **achievements**.

The current database was assembled quickly with no documented schema — only raw data exports
survive. Seven teams have reported performance and correctness problems.

---

## Problem Analysis

| # | Problem Reported | Business Need | Stakeholder | Queries | Classification |
|---|---|---|---|---|---|
| **P1** | Home screen (course path, XP, daily goal, next lesson, streak counter) loads slowly | Every learner sees this screen every session; it must respond in <100 ms | **Learner (end user)** | R01, R02, R03, R04, R06 | **Customer-facing / Real-time** |
| **P2** | Leagues tab and weekly league close take too long | Learners check standings mid-week; the weekly close batch job ranks ~30k learners into cohorts | **Gamification team + Learner** | R05, R14, W04 | Tab: **Customer-facing / Real-time** · Close job: **Batch** |
| **P3** | Starting/finishing a lesson and updating daily XP must be instant | These writes block the user mid-lesson; any lag breaks the experience | **Learner (end user)** | W01, W02, W03 | **Customer-facing / Real-time** |
| **P4** | Curriculum team needs mistake hotspots, quit rates, hearts lost, per-lesson reports | Curriculum designers use these reports to improve lesson content | **Curriculum / Product team** | R07, R08, R19, R24 | **Reporting / Analytics** |
| **P5** | Referral programme list of learners who haven't referred anyone is always **empty** | Growth team cannot identify targets for referral nudges | **Growth team** | R13 | **Bug / Data correctness** |
| **P6** | Growth & retention dashboards (DAU, cohort retention, streak reminders, XP trends, course popularity) time out | Retention dashboards drive re-engagement campaigns and product decisions | **Growth / Retention team** | R09, R15, R18, R20, R21, R25 | **Reporting / Analytics** |
| **P7** | Sign-in, friend search, achievements, support console slow; activity will grow 20× | Platform reliability affects every user; volume will increase 20× next year | **Platform / Monetisation / Support** | R10, R11, R12, R16, R17, R22, R23, W05 | **Customer-facing / Real-time** + **Scalability risk** |

---

## Performance Targets (set now, measured in Phase 5)

| Classification | Queries | Target on large dataset (20× volume) |
|---|---|---|
| Real-time / learner-facing | R02, R03, R04, R05, R06, R11, R12, W01, W02, W03 | **< 5 ms** |
| Interactive tools | R01, R13, R16, R21, R22, R23 | **< 250 ms** |
| Reports and analytics | R07, R08, R09, R10, R14, R15, R17, R18, R19, R20, R24, R25 | **< 5,000 ms** |
| Batch jobs | W04, W05 | **< 1,000 ms** |

---

## Assumptions

1. **Timestamps** — All `*_at` columns and `started_at`/`completed_at` are stored as
   `TIMESTAMPTZ` and carry an IST (`+05:30`) offset in the seed data.
2. **Streak logic** — A streak day is any calendar day where `daily_activity.xp > 0`
   OR `used_streak_freeze = TRUE`. Both count toward consecutive-day streaks (R03).
3. **Quit = abandoned** — An attempt with `completed_at IS NULL` is considered quit/abandoned.
   Quit attempts always have `xp_earned = 0`.
4. **League weeks start on Monday** — `league_memberships.week_start` is always a Monday
   (`EXTRACT(DOW ...) = 1`). `final_rank` and `result` are NULL until the week closes
   (W04 sets them).
5. **Referral NULL issue (P5)** — `learners.referred_by` is NULL for learners who were not
   referred. The original R13 query uses `NOT IN (SELECT referred_by FROM learners)`. Because
   `referred_by` contains NULLs, the subquery returns a set that includes NULL, causing
   `NOT IN` to return no rows for any learner (SQL three-valued logic: `x NOT IN {…, NULL}`
   is UNKNOWN, not TRUE). This is the root cause of P5. It will be fixed in Phase 4 using
   `NOT EXISTS` or `WHERE referred_by IS NOT NULL` in the subquery.
6. **Denormalized columns** — `enrollments.total_xp`, `lesson_attempts.is_perfect`, and
   `league_memberships.weekly_xp` are derived/redundant but kept intentionally for query
   performance. This is a justified trade-off documented in Phase 2.
7. **Dataset scope** — Seed data covers 1 Jan 2025 – 30 Jun 2026. All date-based queries
   reference this window.

