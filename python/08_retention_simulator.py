import os
import getpass
import urllib.parse
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from sqlalchemy import create_engine

# ---------- ASSUMPTIONS (data mein inka koi record nahi, yahan badal sakte hain) ----------
CONTACT_COST = 1.0                 # har contacted customer par kharcha (email/SMS), dataset ki currency mein
DISCOUNT = 0.10                    # offer: revenue par 10% discount
GROSS_MARGIN = 0.30                # ASSUMPTION: data mein cost nahi hai
SAVE_RATES = [0.05, 0.10, 0.20]    # contacted customer ke inactive hone ke chance ka kitna hissa campaign bacha leta hai

pwd = urllib.parse.quote_plus(os.environ.get("MYSQL_PWD") or getpass.getpass("MySQL password: "))
engine = create_engine(f"mysql+pymysql://retail_user:{pwd}@127.0.0.1:3306/retail_seg")

# ---------- 1. Data ----------
churn = pd.read_sql("SELECT customer_id, churn_prob, risk_band FROM churn_scores", engine)
seg = pd.read_sql("SELECT customer_id, segment FROM rfm_segments", engine)
base = pd.read_sql("SELECT customer_id, monetary, tenure_days FROM clv_dataset "
                   "WHERE snapshot_date = '2011-12-10'", engine)
for c in ["monetary", "tenure_days"]:
    base[c] = base[c].astype(float)
d = churn.merge(seg, on="customer_id").merge(base, on="customer_id")
d["churn_prob"] = d["churn_prob"].astype(float)
# V = customer ka average 90-din ka spend (churn label ka horizon bhi 90 din hai)
d["value_90d"] = d["monetary"] * 90 / np.maximum(d["tenure_days"], 90)
d["expected_loss"] = d["churn_prob"] * d["value_90d"]
print("Customers:", len(d))                                   # 5852 aana chahiye
print("Total value_90d:", round(d["value_90d"].sum()), "| total expected loss:", round(d["expected_loss"].sum()))

# ---------- 2. Economics ----------
# saved_revenue   = save_rate x p x V              (campaign se bacha hua extra revenue)
# discount_leak   = DISCOUNT x (1 - p) x V         (jo customers waise bhi kharidte, unhe diya gaya discount)
# net_profit      = saved_revenue x (margin - discount) - discount_leak - contact_cost
def economics(sub, s):
    p, V = sub["churn_prob"], sub["value_90d"]
    saved = s * p * V
    leak = DISCOUNT * (1 - p) * V
    profit = saved * (GROSS_MARGIN - DISCOUNT) - leak - CONTACT_COST
    return saved, leak, profit

def breakeven(sub):
    p, V = sub["churn_prob"], sub["value_90d"]
    a = (p * V).sum() * (GROSS_MARGIN - DISCOUNT)
    b = (DISCOUNT * (1 - p) * V).sum() + CONTACT_COST * len(sub)
    return b / a if a > 0 else np.nan

strategies = {
    "All High-risk": lambda s: d[d["risk_band"] == "High"],
    "High + Medium risk": lambda s: d[d["risk_band"].isin(["High", "Medium"])],
    "RFM: At Risk + Cannot Lose Them": lambda s: d[d["segment"].isin(["At Risk", "Cannot Lose Them"])],
    "Top 500 by expected loss": lambda s: d.nlargest(500, "expected_loss"),
    "Only net-positive customers": lambda s: d[economics(d, s)[2] > 0],
}

rows = []
for name, pick in strategies.items():
    for s in SAVE_RATES:
        sub = pick(s)
        saved, leak, profit = economics(sub, s)
        cost = CONTACT_COST * len(sub) + leak.sum()
        rows.append({"strategy": name, "save_rate": s, "contacted": len(sub),
                     "saved_revenue": saved.sum(), "total_cost": cost,
                     "net_profit": profit.sum(),
                     "roi_pct": 100 * profit.sum() / cost if cost > 0 else np.nan})
res = pd.DataFrame(rows)
pd.set_option("display.width", 220)
print("\n--- Scenarios ---")
print(res.round(1).to_string(index=False))

print("\n--- Break-even save rate (isse kam save rate par campaign loss mein) ---")
for name in list(strategies)[:4]:
    print(f"{name}: {breakeven(strategies[name](0)):.3f}")

# ---------- 3. Chart aur save ----------
pv = res.pivot(index="strategy", columns="save_rate", values="net_profit")
ax = pv.plot.barh(figsize=(9, 4))
ax.axvline(0, color="k", lw=0.8)
ax.set_xlabel("Net profit (assumptions ke saath)")
ax.set_title("Retention campaign scenarios")
plt.tight_layout()
plt.savefig("outputs/simulator.png", dpi=150)
plt.close()

res.round(2).to_csv("data/processed/simulator_scenarios.csv", index=False)
res.round(2).to_sql("simulator_scenarios", engine, if_exists="replace", index=False)
d[["customer_id", "value_90d", "expected_loss"]].round(2).to_sql(
    "customer_value_at_risk", engine, if_exists="replace", index=False)
print("\nSaved: simulator.png, simulator_scenarios.csv, aur MySQL tables simulator_scenarios, customer_value_at_risk")