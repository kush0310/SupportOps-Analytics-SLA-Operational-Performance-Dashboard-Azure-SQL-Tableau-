/* =========================================================
   04_DATAMART: Dimensions (dm)
   ========================================================= */

IF OBJECT_ID('dm.DimDate','U') IS NOT NULL DROP TABLE dm.DimDate;
IF OBJECT_ID('dm.DimAgent','U') IS NOT NULL DROP TABLE dm.DimAgent;
IF OBJECT_ID('dm.DimCustomer','U') IS NOT NULL DROP TABLE dm.DimCustomer;
GO

CREATE TABLE dm.DimDate (
    DateKey        INT           NOT NULL PRIMARY KEY, -- yyyymmdd
    [Date]         DATE          NOT NULL,
    [Year]         INT           NOT NULL,
    [Month]        INT           NOT NULL,
    MonthName      NVARCHAR(20)  NOT NULL,
    [Quarter]      INT           NOT NULL,
    YearMonth      CHAR(7)       NOT NULL -- YYYY-MM
);

CREATE TABLE dm.DimAgent (
    AgentKey     INT IDENTITY(1,1) PRIMARY KEY,
    AgentID      INT           NOT NULL,
    AgentName    NVARCHAR(100) NOT NULL,
    TeamName     NVARCHAR(100) NOT NULL,
    Location     NVARCHAR(50)  NULL,
    IsActive     BIT           NOT NULL,
    PullDate     DATE          NOT NULL
);

CREATE TABLE dm.DimCustomer (
    CustomerKey   INT IDENTITY(1,1) PRIMARY KEY,
    CustomerID    INT            NOT NULL,
    CustomerName  NVARCHAR(150)  NOT NULL,
    Segment       NVARCHAR(50)   NOT NULL,
    Region        NVARCHAR(50)   NULL,
    PullDate      DATE           NOT NULL
);
GO

/* Build DimDate for a range */
DECLARE @StartDate DATE = '2025-01-01';
DECLARE @EndDate   DATE = '2026-12-31';

;WITH d AS (
    SELECT @StartDate AS dt
    UNION ALL
    SELECT DATEADD(DAY, 1, dt)
    FROM d
    WHERE dt < @EndDate
)
INSERT INTO dm.DimDate (DateKey,[Date],[Year],[Month],MonthName,[Quarter],YearMonth)
SELECT
    CONVERT(INT, FORMAT(dt,'yyyyMMdd')) AS DateKey,
    dt AS [Date],
    DATEPART(YEAR, dt) AS [Year],
    DATEPART(MONTH, dt) AS [Month],
    DATENAME(MONTH, dt) AS MonthName,
    DATEPART(QUARTER, dt) AS [Quarter],
    FORMAT(dt,'yyyy-MM') AS YearMonth
FROM d
OPTION (MAXRECURSION 32767);
GO

/* Load dim slices (type 1 demo: rebuild per PullDate) */
DECLARE @PullDate DATE = (SELECT MAX(PullDate) FROM trn.Ticket);

DELETE FROM dm.DimAgent    WHERE PullDate = @PullDate;
DELETE FROM dm.DimCustomer WHERE PullDate = @PullDate;

INSERT INTO dm.DimAgent (AgentID, AgentName, TeamName, Location, IsActive, PullDate)
SELECT AgentID, AgentName, TeamName, Location, IsActive, PullDate
FROM trn.Agent
WHERE PullDate = @PullDate;

INSERT INTO dm.DimCustomer (CustomerID, CustomerName, Segment, Region, PullDate)
SELECT CustomerID, CustomerName, Segment, Region, PullDate
FROM trn.Customer
WHERE PullDate = @PullDate;
GO


/* =========================================================
   04_DATAMART: Fact table for ticket KPIs
   ========================================================= */

IF OBJECT_ID('dm.FactTicket','U') IS NOT NULL DROP TABLE dm.FactTicket;
GO

CREATE TABLE dm.FactTicket (
    TicketID        BIGINT       NOT NULL PRIMARY KEY,
    CreatedDateKey  INT          NOT NULL,
    CustomerKey     INT          NOT NULL,
    AgentKey        INT          NULL,

    Channel         NVARCHAR(30) NOT NULL,
    Priority        NVARCHAR(10) NOT NULL,
    Status          NVARCHAR(30) NOT NULL,

    FRT_Minutes     INT          NULL,
    TTR_Minutes     INT          NULL,
    SLA_Met_Flag    BIT          NULL,
    IsOverdue_Flag  BIT          NOT NULL,
    ReopenCount     INT          NOT NULL,
    CSATScore       INT          NULL,

    PullDate        DATE         NOT NULL
);
GO

DECLARE @PullDate DATE = (SELECT MAX(PullDate) FROM trn.Ticket);

DELETE FROM dm.FactTicket WHERE PullDate = @PullDate;

INSERT INTO dm.FactTicket
(
 TicketID, CreatedDateKey, CustomerKey, AgentKey,
 Channel, Priority, Status,
 FRT_Minutes, TTR_Minutes, SLA_Met_Flag, IsOverdue_Flag, ReopenCount, CSATScore,
 PullDate
)
SELECT
    t.TicketID,
    CONVERT(INT, FORMAT(CAST(t.CreatedAt AS DATE), 'yyyyMMdd')) AS CreatedDateKey,
    c.CustomerKey,
    a.AgentKey,
    t.Channel,
    t.Priority,
    t.Status,
    t.FRT_Minutes,
    t.TTR_Minutes,
    t.SLA_Met_Flag,
    t.IsOverdue_Flag,
    t.ReopenCount,
    t.CSATScore,
    t.PullDate
FROM trn.Ticket t
JOIN dm.DimCustomer c
  ON c.CustomerID = t.CustomerID
 AND c.PullDate   = t.PullDate
LEFT JOIN dm.DimAgent a
  ON a.AgentID   = t.OwnerAgentID
 AND a.PullDate  = t.PullDate
WHERE t.PullDate = @PullDate;
GO



/* =========================================================
   04_DATAMART: KPI-friendly views for Tableau
   ========================================================= */

IF OBJECT_ID('dm.vw_TicketKPI','V') IS NOT NULL DROP VIEW dm.vw_TicketKPI;
GO

CREATE VIEW dm.vw_TicketKPI AS
SELECT
    f.TicketID,
    dd.[Date]        AS CreatedDate,
    dd.[Year],
    dd.[Quarter],
    dd.[Month],
    dd.MonthName,
    dd.YearMonth,

    c.CustomerName,
    c.Segment,
    c.Region,

    a.AgentName,
    a.TeamName,
    a.Location,

    f.Channel,
    f.Priority,
    f.Status,

    f.FRT_Minutes,
    f.TTR_Minutes,
    f.SLA_Met_Flag,
    f.IsOverdue_Flag,
    f.ReopenCount,
    f.CSATScore,
    f.PullDate
FROM dm.FactTicket f
JOIN dm.DimDate dd
  ON dd.DateKey = f.CreatedDateKey
JOIN dm.DimCustomer c
  ON c.CustomerKey = f.CustomerKey
LEFT JOIN dm.DimAgent a
  ON a.AgentKey = f.AgentKey;
GO