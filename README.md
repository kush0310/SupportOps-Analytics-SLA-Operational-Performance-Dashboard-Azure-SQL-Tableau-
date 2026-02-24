# 📊 SupportOps Analytics Dashboard  
**Azure SQL + Tableau**

Executive-level support operations dashboard designed to monitor SLA compliance, response time performance, and backlog risk using a dimensional data model built in Azure SQL.

---

## 🖼 Dashboard Preview

![SupportOps Dashboard](images/dashboard.png)

---

## 🧠 Project Overview

This project simulates a production support analytics environment and delivers standardized KPIs through a structured data pipeline:

**stg (raw) → trn (business logic) → dm (star schema) → Tableau**

The dashboard enables leadership to quickly assess:

- SLA Compliance %
- Median First Response Time (FRT)
- Open Backlog Volume
- Overdue Ticket Risk
- Workload Distribution by Priority
- Team-Level Performance

---

## 🏗 Data Architecture

- Fact Table: `FactTicket`
- Dimensions: `DimDate`, `DimAgent`, `DimCustomer`
- Analytics View: `dm.vw_TicketKPI`

All SLA and response-time logic is centralized in SQL to ensure KPI consistency across reporting tools.

---

## 🛠 Tech Stack

- Azure SQL Database  
- T-SQL (ETL & dimensional modeling)  
- Tableau Desktop / Tableau Public  
- Star Schema Design  

---

## 🎯 Key Outcome

Built an end-to-end BI solution that transforms raw operational ticket data into governed executive insights, demonstrating dimensional modeling, metric standardization, and dashboard design best practices.
