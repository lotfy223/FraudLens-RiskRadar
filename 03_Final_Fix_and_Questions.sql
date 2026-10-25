-- FraudLens | FINAL script for FraudAnalysisDB (table already imported as dbo.fraudlens_master). Safe to re-run.
USE FraudAnalysisDB;
GO
-- 0) Quick check on the imported table
SELECT COUNT(*) AS rows_loaded FROM dbo.fraudlens_master;   -- expect 434252
GO
-- 1) Speed up queries
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name='ix_fm_client') CREATE INDEX ix_fm_client ON dbo.fraudlens_master(client_id);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE name='ix_fm_tier')   CREATE INDEX ix_fm_tier   ON dbo.fraudlens_master(risk_tier);
GO
-- 2) Clean view for Power BI. Fixes: bit -> int (so SUM works), mcc 0 -> NULL (1 unknown row),
--    zip back to 5 digits with leading zeros, empty text -> NULL, plus ready-made bands.
CREATE OR ALTER VIEW dbo.vw_master AS
SELECT id,[date],CAST([date] AS DATE) AS tx_date,[month],[weekday],[hour],
 client_id,client_age,gender,retirement_age,client_credit_score,yearly_income,per_capita_income,total_debt,client_num_cards,client_lat,client_lon,
 card_id,card_brand,card_type,card_has_chip,card_dark_web,card_credit_limit,card_open_date,card_expires,card_num_issued,card_pin_year,
 amount,use_chip,merchant_id,NULLIF(merchant_city,'') AS merchant_city,NULLIF(merchant_state,'') AS merchant_state,merchant_area,
 RIGHT('00000'+CAST(zip AS VARCHAR(10)),5) AS zip,
 NULLIF(mcc,0) AS mcc,NULLIF(errors,'') AS errors,
 CAST(sig_night AS INT) AS sig_night,CAST(sig_online AS INT) AS sig_online,CAST(sig_error AS INT) AS sig_error,
 CAST(sig_spike AS INT) AS sig_spike,CAST(sig_darkweb AS INT) AS sig_darkweb,CAST(sig_travel AS INT) AS sig_travel,
 risk_score,risk_tier,
 CASE WHEN risk_tier='High' THEN 3 WHEN risk_tier='Medium' THEN 2 ELSE 1 END AS risk_tier_order,
 CASE WHEN client_age<30 THEN '<30' WHEN client_age<45 THEN '30-44' WHEN client_age<60 THEN '45-59' ELSE '60+' END AS age_group,
 CASE WHEN client_credit_score<580 THEN '1 Poor' WHEN client_credit_score<670 THEN '2 Fair' WHEN client_credit_score<740 THEN '3 Good' ELSE '4 Very good+' END AS credit_band,
 CASE WHEN amount<0 THEN '0 Refund' WHEN amount<20 THEN '1 <20' WHEN amount<50 THEN '2 20-50' WHEN amount<100 THEN '3 50-100' WHEN amount<250 THEN '4 100-250' ELSE '5 250+' END AS amount_band,
 CASE WHEN amount<0 THEN 1 ELSE 0 END AS is_refund
FROM dbo.fraudlens_master;
GO
SELECT COUNT(*) AS view_rows, SUM(CASE WHEN risk_tier='High' THEN 1 ELSE 0 END) AS high_risk FROM dbo.vw_master;  -- 434252 | 336
GO
-- 3) Questions (all on vw_master)
-- Q1 headline
SELECT COUNT(*) tx, SUM(CASE WHEN amount>0 THEN amount END) volume, SUM(CASE WHEN risk_tier='High' THEN 1 ELSE 0 END) high_risk FROM dbo.vw_master;
-- Q2 per month
SELECT [month],COUNT(*) tx,SUM(CASE WHEN risk_tier='High' THEN 1 ELSE 0 END) high_risk FROM dbo.vw_master GROUP BY [month] ORDER BY [month];
-- Q3 online vs swipe
SELECT use_chip,COUNT(*) tx,CAST(100.0*SUM(CASE WHEN risk_tier<>'Low' THEN 1 ELSE 0 END)/COUNT(*) AS DECIMAL(5,2)) pct_flagged FROM dbo.vw_master GROUP BY use_chip;
-- Q4 merchant categories, highest flagged share (min 2000 tx)
SELECT TOP 10 mcc,COUNT(*) tx,CAST(100.0*SUM(CASE WHEN risk_tier<>'Low' THEN 1 ELSE 0 END)/COUNT(*) AS DECIMAL(5,2)) pct_flagged FROM dbo.vw_master WHERE amount>0 AND mcc IS NOT NULL GROUP BY mcc HAVING COUNT(*)>=2000 ORDER BY pct_flagged DESC;
-- Q5 card errors
SELECT errors,COUNT(*) n FROM dbo.vw_master WHERE errors IS NOT NULL GROUP BY errors ORDER BY n DESC;
-- Q6 top clients
SELECT TOP 10 client_id,client_credit_score,COUNT(*) high_risk_tx,SUM(CASE WHEN amount>0 THEN amount ELSE 0 END) exposed FROM dbo.vw_master WHERE risk_tier='High' GROUP BY client_id,client_credit_score ORDER BY high_risk_tx DESC;
-- Q7 age group / Q8 credit band / Q9 card brand+type
SELECT age_group,COUNT(*) tx,CAST(100.0*SUM(CASE WHEN risk_tier<>'Low' THEN 1 ELSE 0 END)/COUNT(*) AS DECIMAL(5,2)) pct_flagged FROM dbo.vw_master GROUP BY age_group ORDER BY age_group;
SELECT credit_band,COUNT(*) tx,CAST(100.0*SUM(CASE WHEN risk_tier<>'Low' THEN 1 ELSE 0 END)/COUNT(*) AS DECIMAL(5,2)) pct_flagged FROM dbo.vw_master GROUP BY credit_band ORDER BY credit_band;
SELECT card_brand,card_type,COUNT(*) tx,CAST(100.0*SUM(CASE WHEN risk_tier<>'Low' THEN 1 ELSE 0 END)/COUNT(*) AS DECIMAL(5,2)) pct_flagged FROM dbo.vw_master GROUP BY card_brand,card_type ORDER BY pct_flagged DESC;
-- Q10 US / International / Online
SELECT merchant_area,COUNT(*) tx,SUM(sig_travel) travel_hits FROM dbo.vw_master GROUP BY merchant_area;
-- Q11 impossible travel examples
SELECT TOP 20 id,[date],client_id,merchant_city,merchant_state,amount FROM dbo.vw_master WHERE sig_travel=1 ORDER BY [date];
-- Q12 single transaction above the card limit
SELECT TOP 10 client_id,card_id,amount,card_credit_limit FROM dbo.vw_master WHERE amount>card_credit_limit ORDER BY amount DESC;
GO
