-- One merged table (fraudlens_master.csv) -> SQL Server -> quick questions. Edit the path first.
CREATE DATABASE FraudLens; GO
USE FraudLens; GO
CREATE TABLE dbo.master(id INT,[date] DATETIME2,[month] CHAR(7),[weekday] VARCHAR(10),[hour] INT,
 client_id INT,client_age INT,gender VARCHAR(10),retirement_age INT,client_credit_score INT,yearly_income DECIMAL(12,2),per_capita_income DECIMAL(12,2),total_debt DECIMAL(12,2),client_num_cards INT,client_lat FLOAT,client_lon FLOAT,
 card_id INT,card_brand VARCHAR(20),card_type VARCHAR(20),card_has_chip VARCHAR(3),card_dark_web VARCHAR(3),card_credit_limit DECIMAL(12,2),card_open_date VARCHAR(10),card_expires VARCHAR(10),card_num_issued INT,card_pin_year INT,
 amount DECIMAL(12,2),use_chip VARCHAR(30),merchant_id INT,merchant_city VARCHAR(60),merchant_state VARCHAR(40),merchant_area VARCHAR(15),zip VARCHAR(10),mcc INT,errors VARCHAR(100),
 sig_night BIT,sig_online BIT,sig_error BIT,sig_spike BIT,sig_darkweb BIT,sig_travel BIT,risk_score INT,risk_tier VARCHAR(8));
BULK INSERT dbo.master FROM 'C:\data\fraudlens_master.csv' WITH(FORMAT='CSV',FIRSTROW=2,FIELDQUOTE='"',KEEPNULLS);
GO
SELECT COUNT(*) AS rows_loaded FROM dbo.master;                       -- expect 434252
-- Q1 headline numbers
SELECT COUNT(*) tx, SUM(CASE WHEN amount>0 THEN amount END) volume, SUM(CASE WHEN risk_tier='High' THEN 1 END) high_risk FROM dbo.master;
-- Q2 high-risk per month
SELECT [month],COUNT(*) tx,SUM(CASE WHEN risk_tier='High' THEN 1 ELSE 0 END) high_risk FROM dbo.master GROUP BY [month] ORDER BY [month];
-- Q3 online vs swipe: share rated Medium/High
SELECT use_chip,COUNT(*) tx,CAST(100.0*SUM(CASE WHEN risk_tier<>'Low' THEN 1 ELSE 0 END)/COUNT(*) AS DECIMAL(5,2)) pct_flagged FROM dbo.master GROUP BY use_chip;
-- Q4 merchant categories with the highest flagged share (min 2000 tx)
SELECT TOP 10 mcc,COUNT(*) tx,CAST(100.0*SUM(CASE WHEN risk_tier<>'Low' THEN 1 ELSE 0 END)/COUNT(*) AS DECIMAL(5,2)) pct_flagged FROM dbo.master WHERE amount>0 GROUP BY mcc HAVING COUNT(*)>=2000 ORDER BY pct_flagged DESC;
-- Q5 which card errors are most common
SELECT errors,COUNT(*) n FROM dbo.master WHERE errors IS NOT NULL GROUP BY errors ORDER BY n DESC;
-- Q6 top 10 clients by high-risk exposure
SELECT TOP 10 client_id,client_credit_score,COUNT(*) high_risk_tx,SUM(CASE WHEN amount>0 THEN amount ELSE 0 END) exposed FROM dbo.master WHERE risk_tier='High' GROUP BY client_id,client_credit_score ORDER BY high_risk_tx DESC;
-- Q7 flagged share by age group
SELECT CASE WHEN client_age<30 THEN '<30' WHEN client_age<45 THEN '30-44' WHEN client_age<60 THEN '45-59' ELSE '60+' END age_group,COUNT(*) tx,CAST(100.0*SUM(CASE WHEN risk_tier<>'Low' THEN 1 ELSE 0 END)/COUNT(*) AS DECIMAL(5,2)) pct_flagged FROM dbo.master GROUP BY CASE WHEN client_age<30 THEN '<30' WHEN client_age<45 THEN '30-44' WHEN client_age<60 THEN '45-59' ELSE '60+' END ORDER BY 1;
-- Q8 flagged share by credit-score band
SELECT CASE WHEN client_credit_score<580 THEN 'Poor' WHEN client_credit_score<670 THEN 'Fair' WHEN client_credit_score<740 THEN 'Good' ELSE 'Very good+' END band,COUNT(*) tx,CAST(100.0*SUM(CASE WHEN risk_tier<>'Low' THEN 1 ELSE 0 END)/COUNT(*) AS DECIMAL(5,2)) pct_flagged FROM dbo.master GROUP BY CASE WHEN client_credit_score<580 THEN 'Poor' WHEN client_credit_score<670 THEN 'Fair' WHEN client_credit_score<740 THEN 'Good' ELSE 'Very good+' END ORDER BY 3 DESC;
-- Q9 card brand x type
SELECT card_brand,card_type,COUNT(*) tx,CAST(100.0*SUM(CASE WHEN risk_tier<>'Low' THEN 1 ELSE 0 END)/COUNT(*) AS DECIMAL(5,2)) pct_flagged FROM dbo.master GROUP BY card_brand,card_type ORDER BY pct_flagged DESC;
-- Q10 US vs international vs online
SELECT merchant_area,COUNT(*) tx,SUM(CAST(sig_travel AS INT)) travel_hits FROM dbo.master GROUP BY merchant_area;
-- Q11 impossible-travel cases to inspect
SELECT TOP 20 id,[date],client_id,merchant_city,merchant_state,amount FROM dbo.master WHERE sig_travel=1 ORDER BY [date];
-- Q12 clients who are over their card limit in a single transaction
SELECT TOP 10 client_id,card_id,amount,card_credit_limit FROM dbo.master WHERE amount>card_credit_limit ORDER BY amount DESC;
