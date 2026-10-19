import os
import getpass
import urllib.parse
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from sqlalchemy import create_engine
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.metrics import mean_absolute_error

pwd = urllib.parse.quote_plus(os.environ.get("MYSQL_PWD") or getpass.getpass("MySQL password: "))
engine = create_engine(f"mysql+pymysql://retail_user:{pwd}@127.0.0.1:3306/retail_seg")

# ---------- 1. Data ----------
df = pd.read_sql("SELECT * FROM clv_dataset", engine)
df["snapshot_date"] = pd.to_datetime(df["snapshot_date"])
for c in df.columns:
    if c not in ("snapshot_date", "customer_id"):
        df[c] = df[c].astype(float)
# Jun-Sep ke snapshots ka 180-din ka window Oct-Nov (gift season) cover karta hai
df["peak_window"] = df["snapshot_date"].dt.month.isin([6, 7, 8, 9]).astype(float)

FEATS = ["recency_days", "frequency", "monetary", "tenure_days", "avg_order_value",
         "avg_gap_days", "orders_last_90d", "revenue_last_90d",
         "orders_last_180d", "revenue_last_180d", "peak_window"]
TARGET = "future_rev_180d"

lab = df[df[TARGET].notna()].copy()
snaps = sorted(lab["snapshot_date"].unique())
print("Rows:", len(df), "| labelled:", len(lab))
print("Actual 180-din revenue (sab customers), har snapshot par:")
print(lab.groupby("snapshot_date")[TARGET].sum().round(0).to_string())

def make_model():
    return HistGradientBoostingRegressor(loss="poisson", max_depth=3, learning_rate=0.05,
                                         max_iter=200, random_state=42)

def report(y, pred, rank=True):
    y, pred = np.asarray(y, dtype=float), np.asarray(pred, dtype=float)
    out = {"MAE": mean_absolute_error(y, pred), "sum_pred_vs_actual": pred.sum() / y.sum()}
    if rank:
        k = max(1, int(len(y) * 0.10))
        out["spearman"] = pd.Series(pred).corr(pd.Series(y), method="spearman")
        out["top10_capture"] = y[np.argsort(-pred)[:k]].sum() / y.sum()
        out["best_possible"] = y[np.argsort(-y)[:k]].sum() / y.sum()
    return out

# ---------- 2. Walk-forward validation ----------
rows, store = [], {}
for i in range(1, len(snaps)):
    tr = lab[lab["snapshot_date"] < snaps[i]]
    te = lab[lab["snapshot_date"] == snaps[i]]
    snap = str(pd.Timestamp(snaps[i]).date())
    m = make_model().fit(tr[FEATS], tr[TARGET])
    p = m.predict(te[FEATS])
    rows.append({"snapshot": snap, "method": "Gradient boosting model", **report(te[TARGET], p)})
    rows.append({"snapshot": snap, "method": "Last 180d revenue (persistence)",
                 **report(te[TARGET], te["revenue_last_180d"])})
    rows.append({"snapshot": snap, "method": "Global average",
                 **report(te[TARGET], np.full(len(te), tr[TARGET].mean()), rank=False)})
    store[snap] = (te[TARGET].values, p)
res = pd.DataFrame(rows)
pd.set_option("display.width", 220)
print("\n--- Validation: predicted vs actual 180-din revenue ---")
print(res.round(3).to_string(index=False))

# ---------- 3. Decile table (aakhri test snapshot) ----------
last = list(store)[-1]
y_l, p_l = store[last]
dec = pd.DataFrame({"pred": p_l, "actual": y_l})
dec["decile"] = pd.qcut(dec["pred"].rank(method="first", ascending=False), 10,
                        labels=list(range(1, 11)))
t = dec.groupby("decile", observed=True).agg(
    customers=("pred", "size"), avg_pred=("pred", "mean"),
    avg_actual=("actual", "mean"), actual_revenue=("actual", "sum"))
t["pct_actual_revenue"] = 100 * t["actual_revenue"] / t["actual_revenue"].sum()
print(f"\n--- Decile table (test {last}): decile 1 = model ke hisaab se sabse valuable ---")
print(t.round(1).to_string())

fig, ax = plt.subplots(figsize=(7, 4))
x = np.arange(len(t))
ax.bar(x - 0.2, t["avg_pred"], 0.4, label="Predicted")
ax.bar(x + 0.2, t["avg_actual"], 0.4, label="Actual")
ax.set_xticks(x)
ax.set_xticklabels(t.index)
ax.set_xlabel("Decile (1 = highest predicted)")
ax.set_ylabel("Avg 180-day revenue per customer")
ax.set_title(f"Predicted vs actual, test {last}")
ax.legend()
plt.tight_layout()
plt.savefig("outputs/clv_validation.png", dpi=150)
plt.close()

# ---------- 4. Final model: sab labelled data par, aaj ki date (2011-12-10) ka scoring ----------
final = make_model().fit(lab[FEATS], lab[TARGET])
sc = df[df[TARGET].isna()].copy()
sc["clv_6m"] = final.predict(sc[FEATS]).round(2)
seg = pd.read_sql("SELECT customer_id, segment FROM rfm_segments", engine)
sc = sc.merge(seg, on="customer_id", how="left")
print("\nScored customers:", len(sc), "| total predicted 6-month revenue:", round(sc["clv_6m"].sum()))
summ = sc.groupby("segment").agg(customers=("customer_id", "count"),
                                 total_clv=("clv_6m", "sum"), avg_clv=("clv_6m", "mean"))
summ["pct_of_total"] = 100 * summ["total_clv"] / summ["total_clv"].sum()
print("\n--- Predicted 6-month CLV, RFM segment ke hisaab se ---")
print(summ.sort_values("total_clv", ascending=False).round(1).to_string())

sc[["customer_id", "clv_6m"]].to_csv("data/processed/customer_clv.csv", index=False)
sc[["customer_id", "clv_6m"]].to_sql("customer_clv", engine, if_exists="replace", index=False)
print("\nSaved: clv_validation.png, customer_clv.csv, aur MySQL table customer_clv")