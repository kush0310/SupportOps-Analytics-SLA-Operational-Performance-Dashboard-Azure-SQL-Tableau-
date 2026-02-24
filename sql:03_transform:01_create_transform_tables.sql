/* =========================================================
   03_TRANSFORM: Cleaned, conformed layer (trn)
   - Standardize priority, status, channel
   - Compute durations and SLA flags
   ========================================================= */

IF OBJECT_ID('trn.Ticket','U') IS NOT NULL DROP TABLE trn.Ticket;
IF OBJECT_ID('trn.Agent','U')  IS NOT NULL DROP TABLE trn.Agent;
IF OBJECT_ID('trn.Customer','U') IS NOT NULL DROP TABLE trn.Customer;
GO

CREATE TABLE trn.Agent (
    AgentID     INT           NOT NULL PRIMARY KEY,
    AgentName   NVARCHAR(100) NOT NULL,
    TeamName    NVARCHAR(100) NOT NULL,
    Location    NVARCHAR(50)  NULL,
    HireDate    DATE          NULL,
    IsActive    BIT           NOT NULL,
    PullDate    DATE          NOT NULL
);

CREATE TABLE trn.Customer (
    CustomerID    INT            NOT NULL PRIMARY KEY,
    CustomerName  NVARCHAR(150)  NOT NULL,
    Segment       NVARCHAR(50)   NOT NULL,
    Region        NVARCHAR(50)   NULL,
    PullDate      DATE           NOT NULL
);

CREATE TABLE trn.Ticket (
    TicketID            BIGINT        NOT NULL PRIMARY KEY,
    CustomerID          INT           NOT NULL,
    OwnerAgentID        INT           NULL,
    Channel             NVARCHAR(30)  NOT NULL,
    Priority            NVARCHAR(10)  NOT NULL,  -- P1..P4
    Status              NVARCHAR(30)  NOT NULL,
    CreatedAt           DATETIME2(0)  NOT NULL,
    FirstResponseAt     DATETIME2(0)  NULL,
    ResolvedAt          DATETIME2(0)  NULL,
    DueAt               DATETIME2(0)  NULL,

    -- Derived metrics
    FRT_Minutes         INT           NULL,      -- First response time in minutes
    TTR_Minutes         INT           NULL,      -- Time to resolve in minutes
    SLA_Met_Flag        BIT           NULL,      -- 1 if resolved <= DueAt (or responded <= DueAt depending on policy)
    IsOverdue_Flag      BIT           NOT NULL,  -- 1 if open and now > DueAt
    ReopenCount         INT           NOT NULL,
    CSATScore           INT           NULL,

    PullDate            DATE          NOT NULL
);

GO


/* =========================================================
   03_TRANSFORM: Load from stag -> trn with standardization
   ========================================================= */

DECLARE @PullDate DATE = (SELECT MAX(PullDate) FROM stag.TicketRaw);

-- Upsert-ish pattern (demo friendly): wipe current PullDate slice
DELETE FROM trn.Ticket   WHERE PullDate = @PullDate;
DELETE FROM trn.Agent    WHERE PullDate = @PullDate;
DELETE FROM trn.Customer WHERE PullDate = @PullDate;

-- Agents
INSERT INTO trn.Agent (AgentID, AgentName, TeamName, Location, HireDate, IsActive, PullDate)
SELECT
    AgentID,
    COALESCE(NULLIF(LTRIM(RTRIM(AgentName)),'') ,'Unknown') AS AgentName,
    COALESCE(NULLIF(LTRIM(RTRIM(TeamName)),'') ,'Unassigned') AS TeamName,
    NULLIF(LTRIM(RTRIM(Location)),'') AS Location,
    HireDate,
    COALESCE(IsActive, 1) AS IsActive,
    PullDate
FROM stag.AgentRaw
WHERE PullDate = @PullDate;

-- Customers
INSERT INTO trn.Customer (CustomerID, CustomerName, Segment, Region, PullDate)
SELECT
    CustomerID,
    COALESCE(NULLIF(LTRIM(RTRIM(CustomerName)),'') ,'Unknown') AS CustomerName,
    CASE
        WHEN Segment IN ('SMB','Mid-Market','Enterprise') THEN Segment
        ELSE 'SMB'
    END AS Segment,
    NULLIF(LTRIM(RTRIM(Region)),'') AS Region,
    PullDate
FROM stag.CustomerRaw
WHERE PullDate = @PullDate;

-- Tickets
INSERT INTO trn.Ticket
(
 TicketID, CustomerID, OwnerAgentID, Channel, Priority, Status,
 CreatedAt, FirstResponseAt, ResolvedAt, DueAt,
 FRT_Minutes, TTR_Minutes, SLA_Met_Flag, IsOverdue_Flag,
 ReopenCount, CSATScore, PullDate
)
SELECT
    t.TicketID,
    COALESCE(t.CustomerID, -1) AS CustomerID,
    t.CurrentOwnerAgentID AS OwnerAgentID,
    CASE
        WHEN t.Channel IN ('Email','Chat','Phone','Web') THEN t.Channel
        ELSE 'Other'
    END AS Channel,
    CASE
        WHEN t.Priority IN ('P1','P2','P3','P4') THEN t.Priority
        WHEN t.Priority IN ('High') THEN 'P1'
        WHEN t.Priority IN ('Medium') THEN 'P2'
        WHEN t.Priority IN ('Low') THEN 'P3'
        ELSE 'P3'
    END AS Priority,
    COALESCE(NULLIF(LTRIM(RTRIM(t.Status)),''),'Unknown') AS Status,
    CAST(t.CreatedAt AS DATETIME2(0)) AS CreatedAt,
    CAST(t.FirstResponseAt AS DATETIME2(0)) AS FirstResponseAt,
    CAST(t.ResolvedAt AS DATETIME2(0)) AS ResolvedAt,
    CAST(t.DueAt AS DATETIME2(0)) AS DueAt,

    -- Derived
    CASE
        WHEN t.FirstResponseAt IS NULL THEN NULL
        ELSE DATEDIFF(MINUTE, t.CreatedAt, t.FirstResponseAt)
    END AS FRT_Minutes,

    CASE
        WHEN t.ResolvedAt IS NULL THEN NULL
        ELSE DATEDIFF(MINUTE, t.CreatedAt, t.ResolvedAt)
    END AS TTR_Minutes,

    -- SLA policy for demo: met if ResolvedAt <= DueAt (requires both)
    CASE
        WHEN t.ResolvedAt IS NULL OR t.DueAt IS NULL THEN NULL
        WHEN t.ResolvedAt <= t.DueAt THEN 1 ELSE 0
    END AS SLA_Met_Flag,

    CASE
        WHEN t.ResolvedAt IS NULL AND t.DueAt IS NOT NULL AND SYSUTCDATETIME() > t.DueAt THEN 1
        ELSE 0
    END AS IsOverdue_Flag,

    COALESCE(t.ReopenCount,0) AS ReopenCount,
    t.CSATScore,
    t.PullDate
FROM stag.TicketRaw t
WHERE t.PullDate = @PullDate;
GO