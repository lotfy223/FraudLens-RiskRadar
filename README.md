# FraudLens Risk Radar
An explainable transaction-risk engine: **SQL Server → Power BI**. Every flagged transaction shows *why* it was flagged.

**Data:** 434,252 card transactions (Jan 1 – May 11, 2010), 6,146 cards, 2,000 clients.

## How it works
SQL view `vw_tx_risk` scores each transaction 0–100 from six signals, then tiers it (High ≥ 45, Medium ≥ 20):

| Signal | Points |
|---|---|
| Impossible travel (different state ≤ 60 min after previous transaction) | 40 |
| Card error (Bad PIN, CVV, balance…) | 25 |
| Amount spike (> 3σ above the client's own average) | 20 |
| Card found on dark web | 15 |
| Online transaction | 10 |
| Night time (00:00–04:59) | 10 |

## Result
336 transactions (0.08%) land in High risk, about $106K exposed. 2,506 impossible-travel hits. No card in this sample is on the dark web, so that signal fires 0 times.

## Limits (read before you quote numbers)
- The files have **no fraud label**, so this is a risk score, not confirmed fraud. Weights are hand-set; validate them against labels (e.g. `train_fraud_labels.json` from the original Kaggle dataset) before any real use.
- Only part 1 of the transactions file is loaded.

## Run it
1. `01_FraudLens_RiskRadar.sql` (edit the CSV paths first).
2. Power BI: Get Data → SQL Server → `vw_kpis`, `vw_signals`, `vw_monthly`, `vw_top_clients`.
3. Live demo: see `dashboard.html`.

Author: Ahmed Mohammed Lotfy · [LinkedIn](https://www.linkedin.com/in/ahmed-mohamed-lotfy/)
