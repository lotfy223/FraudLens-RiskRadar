-- FraudLens | one page = every dashboard question saved as a view (source: dbo.vw_master from 03_Final_Fix_and_Questions.sql)
-- Run once. In Power BI: Get data > SQL Server > tick the vw_q* views. Each view is one visual, no DAX needed.
USE FraudAnalysisDB;
GO
------------------------------------------------------------------ PAGE 1: OVERVIEW
CREATE OR ALTER VIEW dbo.vw_q01_kpis AS             -- 4 KPI cards
SELECT COUNT(*) total_tx,
 SUM(CASE WHEN risk_tier='High' THEN 1 ELSE 0 END) high_risk_tx,
 CAST(100.0*SUM(CASE WHEN risk_tier='High' THEN 1 ELSE 0 END)/COUNT(*) AS DECIMAL(6,3)) high_risk_pct,
 SUM(CASE WHEN risk_tier='High' AND amount>0 THEN amount ELSE 0 END) high_risk_amount
FROM dbo.vw_master;
GO
CREATE OR ALTER VIEW dbo.vw_q02_monthly AS          -- line chart
SELECT [month],COUNT(*) tx,SUM(CASE WHEN risk_tier='High' THEN 1 ELSE 0 END) high_risk_tx
FROM dbo.vw_master GROUP BY [month];
GO
CREATE OR ALTER VIEW dbo.vw_q03_by_chip AS          -- column chart: online vs swipe
SELECT use_chip,COUNT(*) tx,CAST(100.0*SUM(CASE WHEN risk_tier<>'Low' THEN 1 ELSE 0 END)/COUNT(*) AS DECIMAL(5,2)) flagged_pct
FROM dbo.vw_master GROUP BY use_chip;
GO
CREATE OR ALTER VIEW dbo.vw_q04_by_mcc AS           -- bar chart: merchant categories (min 2000 tx)
SELECT TOP 8 mcc,
 CASE mcc WHEN 5815 THEN 'Digital goods' WHEN 4814 THEN 'Telecom' WHEN 4111 THEN 'Local transport' WHEN 4900 THEN 'Utilities'
  WHEN 4784 THEN 'Tolls & bridges' WHEN 5311 THEN 'Department stores' WHEN 5651 THEN 'Family clothing' WHEN 4829 THEN 'Money transfer'
  WHEN 5411 THEN 'Grocery' WHEN 5812 THEN 'Restaurants' WHEN 5541 THEN 'Gas stations' WHEN 5912 THEN 'Drug stores'
  ELSE 'MCC '+CAST(mcc AS VARCHAR(6)) END AS mcc_name,
 COUNT(*) tx,CAST(100.0*SUM(CASE WHEN risk_tier<>'Low' THEN 1 ELSE 0 END)/COUNT(*) AS DECIMAL(5,2)) flagged_pct
FROM dbo.vw_master WHERE amount>0 AND mcc IS NOT NULL GROUP BY mcc HAVING COUNT(*)>=2000 ORDER BY flagged_pct DESC;
GO
CREATE OR ALTER VIEW dbo.vw_q05_tiers AS            -- donut
SELECT risk_tier,MAX(risk_tier_order) tier_order,COUNT(*) tx FROM dbo.vw_master GROUP BY risk_tier;
GO
CREATE OR ALTER VIEW dbo.vw_q06_signals AS          -- column chart: which signals fire
SELECT v.signal,v.hits FROM dbo.vw_master m CROSS APPLY (VALUES('Online',m.sig_online),('Night 00-04',m.sig_night),('Card error',m.sig_error),
 ('Amount spike',m.sig_spike),('Impossible travel',m.sig_travel),('Dark web card',m.sig_darkweb)) v(signal,hits) WHERE v.hits=1;   -- dark web = 0 hits in this sample, so it simply has no rows
GO
-- Power BI: for vw_q06 use Count of signal (not Sum of hits) so each row = one hit.
------------------------------------------------------------------ PAGE 2: CUSTOMERS & CARDS
CREATE OR ALTER VIEW dbo.vw_q07_by_age AS
SELECT age_group,COUNT(*) tx,CAST(100.0*SUM(CASE WHEN risk_tier<>'Low' THEN 1 ELSE 0 END)/COUNT(*) AS DECIMAL(5,2)) flagged_pct FROM dbo.vw_master GROUP BY age_group;
GO
CREATE OR ALTER VIEW dbo.vw_q08_by_credit AS
SELECT credit_band,COUNT(*) tx,CAST(100.0*SUM(CASE WHEN risk_tier<>'Low' THEN 1 ELSE 0 END)/COUNT(*) AS DECIMAL(5,2)) flagged_pct FROM dbo.vw_master GROUP BY credit_band;
GO
CREATE OR ALTER VIEW dbo.vw_q09_by_card AS
SELECT card_brand,card_type,COUNT(*) tx,CAST(100.0*SUM(CASE WHEN risk_tier<>'Low' THEN 1 ELSE 0 END)/COUNT(*) AS DECIMAL(5,2)) flagged_pct FROM dbo.vw_master GROUP BY card_brand,card_type;
GO
CREATE OR ALTER VIEW dbo.vw_q10_by_area AS          -- US / International / Online
SELECT merchant_area,COUNT(*) tx,SUM(sig_travel) travel_hits,CAST(100.0*SUM(CASE WHEN risk_tier<>'Low' THEN 1 ELSE 0 END)/COUNT(*) AS DECIMAL(5,2)) flagged_pct FROM dbo.vw_master GROUP BY merchant_area;
GO
CREATE OR ALTER VIEW dbo.vw_q11_top_clients AS      -- table
SELECT TOP 10 client_id,MAX(client_age) age,MAX(client_credit_score) credit_score,COUNT(*) high_risk_tx,
 SUM(CASE WHEN amount>0 THEN amount ELSE 0 END) exposed_amount FROM dbo.vw_master WHERE risk_tier='High' GROUP BY client_id ORDER BY high_risk_tx DESC,exposed_amount DESC;
GO
CREATE OR ALTER VIEW dbo.vw_q12_by_hour AS          -- weekday x hour heatmap (behaviour hits)
SELECT [weekday],[hour],SUM(sig_travel+sig_spike+sig_error) hits,COUNT(*) tx FROM dbo.vw_master GROUP BY [weekday],[hour];
GO
-- Smoke test: each should return rows (q01 = 434252 | 336)
SELECT 'q01' v,total_tx,high_risk_tx FROM dbo.vw_q01_kpis
UNION ALL SELECT 'q05',COUNT(*),SUM(tx) FROM dbo.vw_q05_tiers
UNION ALL SELECT 'q06',COUNT(*),SUM(hits) FROM dbo.vw_q06_signals;
