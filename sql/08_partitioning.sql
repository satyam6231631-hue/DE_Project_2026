-- =====================================================================
-- Duolingo Language Learning Database: Partitioning Architecture
-- Course: Database Management Systems (Phase 5: Scalability & 100x Growth)
-- Deliverable: sql/08_partitioning.sql
-- Database: PostgreSQL 18.6
-- Schema: duolingo
-- =====================================================================
--
-- ARCHITECTURAL RATIONALE:
-- ---------------------------------------------------------------------
-- 1. Table Selection:
--    `lesson_attempts` is by far the largest, fastest-growing table in the
--    system (~3.61 million rows on the 20x dataset, projected to reach 
--    360+ million rows at 100x scale, consuming ~30+ GB). It accounts for 
--    over 70% of total database write traffic and disk footprint.
--
-- 2. Partition Strategy: RANGE (started_at)
--    - Queries in the workload frequently filter by date/timestamp:
--        * R04: Filter by today's date (e.g. '2026-06-30')
--        * R09: Filter by June 2026 date range
--        * R17: Filter by recent 30-day activity window
--        * R20: Hourly and daily trend aggregation
--        * R22: Paginated reverse chronological feed (ORDER BY started_at DESC)
--    - Data Lifecycle & Archiving: Historical lesson attempts (> 1 year old)
--      transition from active OLTP to cold analytical storage. With RANGE 
--      partitioning, old partitions can be detached (ALTER TABLE DETACH PARTITION),
--      archived to cold compressed tablespaces, or dropped in O(1) time without
--      triggering massive DELETE operations or generating VACUUM table bloat.
--
-- 3. Primary Key Rule for Partitioned Tables:
--    PostgreSQL requires that any UNIQUE or PRIMARY KEY constraint on a 
--    partitioned table MUST include all partition key columns. Therefore:
--        PRIMARY KEY (attempt_id, started_at)
--    This ensures uniqueness can be enforced locally within each partition
--    without requiring an expensive cross-partition global index.
-- =====================================================================

SET search_path TO duolingo;
SET timezone = 'Asia/Kolkata';

-- ---------------------------------------------------------------------
-- 1. Partitioned Table DDL
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS lesson_attempts_partitioned CASCADE;

CREATE TABLE lesson_attempts_partitioned (
    attempt_id   BIGINT NOT NULL,
    learner_id   INT NOT NULL REFERENCES learners(learner_id) ON DELETE CASCADE,
    lesson_id    INT NOT NULL REFERENCES lessons(lesson_id) ON DELETE RESTRICT,
    started_at   TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    mistakes     INT NOT NULL DEFAULT 0,
    hearts_lost  INT NOT NULL DEFAULT 0,
    xp_earned    INT NOT NULL DEFAULT 0,
    is_perfect   BOOLEAN NOT NULL DEFAULT false,
    device       VARCHAR(20) NOT NULL,
    
    -- Composite PK required by PostgreSQL for partitioned tables:
    CONSTRAINT pk_lesson_attempts_partitioned PRIMARY KEY (attempt_id, started_at),
    CONSTRAINT chk_part_mistakes_non_negative CHECK (mistakes >= 0),
    CONSTRAINT chk_part_hearts_lost_non_negative CHECK (hearts_lost >= 0),
    CONSTRAINT chk_part_xp_earned_non_negative CHECK (xp_earned >= 0),
    CONSTRAINT chk_part_device CHECK (device IN ('WEB', 'ANDROID', 'IOS'))
) PARTITION BY RANGE (started_at);

-- ---------------------------------------------------------------------
-- 2. Quarterly Partitions (Covering Active Production Data & Growth)
-- ---------------------------------------------------------------------

-- 2025 Q4 Partition (Seed & Historical Attempts)
CREATE TABLE lesson_attempts_2025_q4 PARTITION OF lesson_attempts_partitioned
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');

-- 2026 Q1 Partition (Winter Academic Term)
CREATE TABLE lesson_attempts_2026_q1 PARTITION OF lesson_attempts_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');

-- 2026 Q2 Partition (Spring & Summer Term)
CREATE TABLE lesson_attempts_2026_q2 PARTITION OF lesson_attempts_partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');

-- 2026 Q3 Partition (Active Production Quarter)
CREATE TABLE lesson_attempts_2026_q3 PARTITION OF lesson_attempts_partitioned
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30') TO ('2026-10-01 00:00:00+05:30');

-- Default Partition (Safety Net for Out-of-Range Future Data)
CREATE TABLE lesson_attempts_default PARTITION OF lesson_attempts_partitioned DEFAULT;

-- ---------------------------------------------------------------------
-- 3. Partitioned Table Supporting Indexes
-- Indexes defined on the parent table are automatically propagated to 
-- all current and future child partitions as local partition indexes.
-- ---------------------------------------------------------------------

-- Accelerates R04, R06 (learner attempts lookup)
CREATE INDEX idx_part_attempts_learner_started 
    ON lesson_attempts_partitioned (learner_id, started_at);

-- Accelerates R07, R19 (curriculum lesson analysis)
CREATE INDEX idx_part_attempts_lesson_id 
    ON lesson_attempts_partitioned (lesson_id);

-- Accelerates R22 (feed pagination)
CREATE INDEX idx_part_attempts_started_desc 
    ON lesson_attempts_partitioned (started_at DESC, attempt_id);

-- ---------------------------------------------------------------------
-- 4. Demonstration of Partition Pruning (EXPLAIN Output)
-- ---------------------------------------------------------------------
-- When querying a specific date (e.g. June 30, 2026 for R04), PostgreSQL's
-- planner uses static/dynamic partition pruning to scan ONLY partition
-- `lesson_attempts_2026_q2`, completely eliminating the other 4 partitions.

EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) 
FROM lesson_attempts_partitioned
WHERE started_at >= '2026-06-30 00:00:00+05:30' 
  AND started_at < '2026-07-01 00:00:00+05:30';

-- =====================================================================
-- End of sql/08_partitioning.sql
-- =====================================================================
