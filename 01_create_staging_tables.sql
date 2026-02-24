/* =========================================================
   02_STAGING: Raw ingestion tables (as-received)
   Pattern: stag = raw/landing; minimal constraints
   ========================================================= */

-- Drop if rerunning
IF OBJECT_ID('stag.TicketRaw','U') IS NOT NULL DROP TABLE stag.TicketRaw;
IF OBJECT_ID('stag.TicketEventRaw','U') IS NOT NULL DROP TABLE stag.TicketEventRaw;
IF OBJECT_ID('stag.AgentRaw','U') IS NOT NULL DROP TABLE stag.AgentRaw;
IF OBJECT_ID('stag.CustomerRaw','U') IS NOT NULL DROP TABLE stag.CustomerRaw;
GO

CREATE TABLE stag.AgentRaw (
    AgentID         INT            NOT NULL,
    AgentName       NVARCHAR(100)   NULL,
    TeamName        NVARCHAR(100)   NULL,
    Location        NVARCHAR(50)    NULL,
    HireDate        DATE           NULL,
    IsActive        BIT            NULL,
    PullDate        DATE           NOT NULL
);

CREATE TABLE stag.CustomerRaw (
    CustomerID      INT            NOT NULL,
    CustomerName    NVARCHAR(150)  NULL,
    Segment         NVARCHAR(50)   NULL,  -- SMB, Mid-Market, Enterprise
    Region          NVARCHAR(50)   NULL,
    PullDate        DATE           NOT NULL
);

CREATE TABLE stag.TicketRaw (
    TicketID            BIGINT          NOT NULL,
    CustomerID          INT             NULL,
    CurrentOwnerAgentID INT             NULL,
    Channel             NVARCHAR(30)    NULL,  -- Email, Chat, Phone, Web
    Priority            NVARCHAR(20)    NULL,  -- P1..P4 or High/Med/Low
    Status              NVARCHAR(30)    NULL,  -- New, Open, Pending, Solved, Closed
    CreatedAt           DATETIME2(0)    NULL,
    FirstResponseAt     DATETIME2(0)    NULL,
    ResolvedAt          DATETIME2(0)    NULL,
    DueAt               DATETIME2(0)    NULL,  -- SLA deadline
    ReopenCount         INT             NULL,
    CSATScore           INT             NULL,  -- 1..5 optional
    PullDate            DATE            NOT NULL
);

-- Event stream example (optional but "senior"): actions over time
CREATE TABLE stag.TicketEventRaw (
    TicketEventID    BIGINT         NOT NULL,
    TicketID         BIGINT         NOT NULL,
    EventType        NVARCHAR(50)   NULL,  -- Created, Assigned, PublicReply, StatusChanged, Resolved
    EventAt          DATETIME2(0)   NULL,
    ActorAgentID     INT            NULL,
    NewStatus        NVARCHAR(30)   NULL,
    PullDate         DATE           NOT NULL
);

GO



/* =========================================================
   02_STAGING: Seed sample data for a working demo
   Notes:
   - PullDate lets you demo snapshotting / refresh logic
   - Dates span multiple months to support YoY/MoM
   ========================================================= */

DECLARE @PullDate DATE = CAST(GETDATE() AS DATE);

-- Agents
INSERT INTO stag.AgentRaw (AgentID, AgentName, TeamName, Location, HireDate, IsActive, PullDate)
VALUES
(101,'Aisha Khan','Tier 1','US-Central','2023-02-15',1,@PullDate),
(102,'Ben Carter','Tier 1','US-East','2022-09-01',1,@PullDate),
(201,'Carlos Diaz','Tier 2','US-West','2021-06-10',1,@PullDate),
(301,'Divya Patel','Escalations','US-Central','2020-01-20',1,@PullDate);

-- Customers
INSERT INTO stag.CustomerRaw (CustomerID, CustomerName, Segment, Region, PullDate)
VALUES
(1,'Northwind Co','SMB','Midwest',@PullDate),
(2,'Contoso LLC','Mid-Market','South',@PullDate),
(3,'Fabrikam Inc','Enterprise','Northeast',@PullDate),
(4,'Adventure Works','SMB','West',@PullDate);

-- Tickets (mix of met/missed SLA)
INSERT INTO stag.TicketRaw
(TicketID, CustomerID, CurrentOwnerAgentID, Channel, Priority, Status, CreatedAt, FirstResponseAt, ResolvedAt, DueAt, ReopenCount, CSATScore, PullDate)
VALUES
(10001,1,101,'Email','P2','Solved','2025-11-10 09:10','2025-11-10 09:35','2025-11-10 12:10','2025-11-10 13:10',0,5,@PullDate),
(10002,2,102,'Chat','P3','Solved','2025-11-12 14:00','2025-11-12 14:50','2025-11-13 11:00','2025-11-12 18:00',1,4,@PullDate),
(10003,3,201,'Web','P1','Solved','2025-12-01 08:05','2025-12-01 08:20','2025-12-01 10:30','2025-12-01 09:05',0,3,@PullDate),
(10004,4,301,'Phone','P2','Open','2025-12-14 16:10',NULL,NULL,'2025-12-14 20:10',0,NULL,@PullDate),
(10005,1,201,'Email','P4','Closed','2026-01-05 10:00','2026-01-05 12:30','2026-01-06 15:00','2026-01-05 18:00',2,2,@PullDate),
(10006,2,102,'Chat','P2','Solved','2026-01-17 09:20','2026-01-17 09:28','2026-01-17 10:05','2026-01-17 13:20',0,5,@PullDate),
(10007,3,301,'Web','P1','Solved','2026-02-02 11:10','2026-02-02 11:40','2026-02-02 16:00','2026-02-02 12:10',0,4,@PullDate),
(10008,4,101,'Email','P3','Pending','2026-02-10 15:00','2026-02-10 15:55',NULL,'2026-02-11 15:00',0,NULL,@PullDate);

-- Ticket Events (simple)
INSERT INTO stag.TicketEventRaw (TicketEventID, TicketID, EventType, EventAt, ActorAgentID, NewStatus, PullDate)
VALUES
(1,10001,'Created','2025-11-10 09:10',NULL,'New',@PullDate),
(2,10001,'PublicReply','2025-11-10 09:35',101,NULL,@PullDate),
(3,10001,'Resolved','2025-11-10 12:10',101,'Solved',@PullDate),

(4,10003,'Created','2025-12-01 08:05',NULL,'New',@PullDate),
(5,10003,'PublicReply','2025-12-01 08:20',201,NULL,@PullDate),
(6,10003,'Resolved','2025-12-01 10:30',201,'Solved',@PullDate);
GO