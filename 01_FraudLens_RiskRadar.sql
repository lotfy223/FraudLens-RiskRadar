-- FraudLens Risk Radar | SQL Server (T-SQL) | run in order. Logic validated in pandas; run once on your server to confirm.
CREATE DATABASE FraudLens; GO
USE FraudLens; GO
CREATE TABLE dbo.tx(id INT,[date] DATETIME2,client_id INT,card_id INT,amount DECIMAL(12,2),use_chip VARCHAR(30),merchant_id INT,
  merchant_city VARCHAR(60),merchant_state VARCHAR(40),zip VARCHAR(10),mcc INT,errors VARCHAR(100));
CREATE TABLE dbo.cards(id INT,client_id INT,card_brand VARCHAR(20),card_type VARCHAR(20),card_number VARCHAR(20),expires VARCHAR(10),cvv VARCHAR(5),
  has_chip VARCHAR(3),num_cards_issued INT,credit_limit VARCHAR(20),acct_open_date VARCHAR(10),year_pin_last_changed INT,card_on_dark_web VARCHAR(3));
CREATE TABLE dbo.users(id INT,current_age INT,retirement_age INT,birth_year INT,birth_month INT,gender VARCHAR(10),address VARCHAR(100),latitude FLOAT,
  longitude FLOAT,per_capita_income VARCHAR(20),yearly_income VARCHAR(20),total_debt VARCHAR(20),credit_score INT,num_credit_cards INT);
-- Change the paths to where your CSVs are
BULK INSERT dbo.tx    FROM 'C:\data\transactions_part1.csv' WITH(FORMAT='CSV',FIRSTROW=2,FIELDQUOTE='"');
BULK INSERT dbo.cards FROM 'C:\data\cards_data.csv'         WITH(FORMAT='CSV',FIRSTROW=2,FIELDQUOTE='"');
BULK INSERT dbo.users FROM 'C:\data\users_data.csv'         WITH(FORMAT='CSV',FIRSTROW=2,FIELDQUOTE='"');
GO
-- 1) Risk engine: 6 explainable signals -> score 0-100 -> tier
CREATE VIEW dbo.vw_tx_risk AS
WITH x AS(
 SELECT t.*,c.card_on_dark_web,
  LAG(t.merchant_state) OVER(PARTITION BY t.client_id ORDER BY t.[date],t.id) AS prev_state,
  LAG(t.[date])         OVER(PARTITION BY t.client_id ORDER BY t.[date],t.id) AS prev_date,
  AVG(t.amount)   OVER(PARTITION BY t.client_id) AS mu,
  STDEV(t.amount) OVER(PARTITION BY t.client_id) AS sd
 FROM dbo.tx t LEFT JOIN dbo.cards c ON c.id=t.card_id),
s AS(
 SELECT *,
  IIF(DATEPART(HOUR,[date])<=4,1,0)                          AS sig_night,
  IIF(use_chip='Online Transaction',1,0)                     AS sig_online,
  IIF(errors IS NOT NULL,1,0)                                AS sig_error,
  IIF(amount>0 AND sd>0 AND (amount-mu)/sd>3,1,0)            AS sig_spike,
  IIF(card_on_dark_web='Yes',1,0)                            AS sig_darkweb,
  IIF(prev_state IS NOT NULL AND merchant_state IS NOT NULL
      AND prev_state<>merchant_state AND DATEDIFF(MINUTE,prev_date,[date])<=60,1,0) AS sig_travel
 FROM x),
r AS(SELECT *,10*sig_night+10*sig_online+25*sig_error+20*sig_spike+15*sig_darkweb+40*sig_travel AS raw FROM s)
SELECT id,[date],client_id,card_id,amount,use_chip,merchant_state,mcc,errors,
 sig_night,sig_online,sig_error,sig_spike,sig_darkweb,sig_travel,
 IIF(raw>100,100,raw) AS risk_score,
 CASE WHEN raw>=45 THEN 'High' WHEN raw>=20 THEN 'Medium' ELSE 'Low' END AS risk_tier
FROM r;
GO
-- 2) Power BI views
CREATE VIEW dbo.vw_kpis AS SELECT COUNT(*) total_tx,
  SUM(IIF(amount>0,amount,0)) total_volume, SUM(IIF(risk_tier='High',1,0)) high_risk_tx,
  SUM(IIF(risk_tier='High' AND amount>0,amount,0)) high_risk_amount,
  100.0*SUM(IIF(risk_tier='High',1,0))/COUNT(*) high_risk_pct FROM dbo.vw_tx_risk;
GO
CREATE VIEW dbo.vw_signals AS
SELECT s.signal,s.hits FROM(SELECT 'Online' signal,SUM(sig_online) hits FROM dbo.vw_tx_risk UNION ALL
 SELECT 'Night 00-04',SUM(sig_night) FROM dbo.vw_tx_risk UNION ALL SELECT 'Card error',SUM(sig_error) FROM dbo.vw_tx_risk UNION ALL
 SELECT 'Amount spike',SUM(sig_spike) FROM dbo.vw_tx_risk UNION ALL SELECT 'Impossible travel',SUM(sig_travel) FROM dbo.vw_tx_risk UNION ALL
 SELECT 'Dark web card',SUM(sig_darkweb) FROM dbo.vw_tx_risk) s;
GO
CREATE VIEW dbo.vw_monthly AS SELECT FORMAT([date],'yyyy-MM') month,COUNT(*) tx,
  SUM(IIF(risk_tier='High',1,0)) high_risk_tx FROM dbo.vw_tx_risk GROUP BY FORMAT([date],'yyyy-MM');
GO
CREATE VIEW dbo.vw_top_clients AS SELECT TOP 20 r.client_id,u.credit_score,u.current_age,COUNT(*) high_risk_tx,
  SUM(IIF(r.amount>0,r.amount,0)) exposed_amount FROM dbo.vw_tx_risk r JOIN dbo.users u ON u.id=r.client_id
  WHERE r.risk_tier='High' GROUP BY r.client_id,u.credit_score,u.current_age ORDER BY high_risk_tx DESC;
GO
