import os
import getpass
import urllib.parse
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from sqlalchemy import create_engine
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import make_pipeline
from sklearn.inspection import permutation_importance
from sklearn.metrics import (roc_auc_score, average_precision_score, precision_score,
                             recall_score, f1_score, accuracy_score, roc_curve)

# ---------- 1. MySQL se data ----------
pwd = urllib.parse.quote_plus(os.environ.get("MYSQL_PWD") or getpass.getpass("MySQL password: "))
engine = create_engine(f"mysql+pymysql://retail_user:{pwd}@127.0.0.1:3306/retail_seg")

NUM = ["recency_days", "frequency", "monetary", "tenure_days", "avg_order_value",
       "avg_gap_days", "orders_last_90d", "revenue_last_90d"]

def load(table):
    d = pd.read_sql(f"SELECT * FROM {table}", engine)
    d["snapshot_date"] = pd.to_datetime(d["snapshot_date"])
    for c in NUM + (["churned"] if "churned" in d.columns else []):
        d[c] = d[c].astype(float)
    return d

def prep(d, gap_median):
    X = pd.DataFrame(index=d.index)
    X["recency_days"] = d["recency_days"]
    X["frequency"] = d["frequency"]
    X["tenure_days"] = d["tenure_days"]
    X["orders_last_90d"] = d["orders_last_90d"]
    for c in ["monetary", "avg_order_value", "revenue_last_90d"]:
        X[c] = np.log1p(d[c].clip(lower=0))          # paisa wale features skewed hain
    X["is_single_order"] = d["avg_gap_days"].isna().astype(float)
    X["avg_gap_days"] = d["avg_gap_days"].fillna(gap_median)
    return X

def make_models():
    return {
        "Logistic Regression": make_pipeline(StandardScaler(), LogisticRegression(max_iter=1000)),
        "Gradient Boosting": HistGradientBoostingClassifier(
            max_depth=3, learning_rate=0.05, max_iter=200, random_state=42),
    }

def evaluate(y, p, thr):
    pred = (np.asarray(p) >= thr).astype(int)
    return {"auc": roc_auc_score(y, p), "ap": average_precision_score(y, p),
            "precision": precision_score(y, pred, zero_division=0),
            "recall": recall_score(y, pred, zero_division=0),
            "f1": f1_score(y, pred, zero_division=0),
            "accuracy": accuracy_score(y, pred)}

df = load("churn_dataset")
print("Rows:", len(df))                                   # 22441 aana chahiye
snaps = sorted(df["snapshot_date"].unique())

# ---------- 2. Walk-forward: har snapshot ko test, usse pehle ke sab train ----------
rows, store = [], {}
BASE = "Baseline (recency > 90)"
for i in range(1, len(snaps)):
    tr = df[df["snapshot_date"] < snaps[i]]
    te = df[df["snapshot_date"] == snaps[i]]
    med = tr["avg_gap_days"].median()                      # median sirf train se (leakage nahi)
    Xtr, Xte = prep(tr, med), prep(te, med)
    snap = str(pd.Timestamp(snaps[i]).date())
    rows.append({"snapshot": snap, "model": BASE, **evaluate(te["churned"], te["recency_days"], 91)})
    for name, mdl in make_models().items():
        mdl.fit(Xtr, tr["churned"])
        p = mdl.predict_proba(Xte)[:, 1]
        rows.append({"snapshot": snap, "model": name, **evaluate(te["churned"], p, 0.5)})
        if i == len(snaps) - 1:
            store[name] = (mdl, p, Xte, te["churned"].values)
res = pd.DataFrame(rows)
cols = ["auc", "ap", "precision", "recall", "f1", "accuracy"]
last = str(pd.Timestamp(snaps[-1]).date())

print("\n--- ROC-AUC, har test snapshot par ---")
print(res.pivot(index="snapshot", columns="model", values="auc").round(3).to_string())
print("\n--- Average (4 test snapshots) ---")
print(res.groupby("model")[cols].mean().round(3).to_string())
print(f"\n--- Final test ({last}) ---")
print(res[res["snapshot"] == last].set_index("model")[cols].round(3).to_string())

# ---------- 3. Best model aur feature importance ----------
best = res[res["model"] != BASE].groupby("model")["auc"].mean().idxmax()
print("\nBest model (average AUC):", best)
mdl, p_best, Xte_last, y_last = store[best]
imp = permutation_importance(mdl, Xte_last, y_last, scoring="roc_auc",
                             n_repeats=10, random_state=42)
imp_s = pd.Series(imp.importances_mean, index=Xte_last.columns).sort_values(ascending=False)
print("\n--- Feature importance (AUC kitna girta hai agar feature shuffle karein) ---")
print(imp_s.round(4).to_string())

# ---------- 4. Charts ----------
fig, ax = plt.subplots(1, 2, figsize=(11, 4))
for name, (m_, p_, _, y_) in store.items():
    fpr, tpr, _ = roc_curve(y_, p_)
    ax[0].plot(fpr, tpr, label=f"{name} ({roc_auc_score(y_, p_):.3f})")
ld = df[df["snapshot_date"] == snaps[-1]]
fpr, tpr, _ = roc_curve(ld["churned"], ld["recency_days"])
ax[0].plot(fpr, tpr, label=f"Recency only ({roc_auc_score(ld['churned'], ld['recency_days']):.3f})")
ax[0].plot([0, 1], [0, 1], "k--", lw=0.8)
ax[0].set_title(f"ROC curve, test {last}")
ax[0].set_xlabel("False positive rate")
ax[0].set_ylabel("True positive rate")
ax[0].legend()
imp_s.sort_values().plot.barh(ax=ax[1])
ax[1].set_title(f"Feature importance ({best})")
plt.tight_layout()
plt.savefig("outputs/churn_model.png", dpi=150)
plt.close()

# ---------- 5. Final model (sab labelled data par) se aaj ki date ka scoring ----------
med_all = df["avg_gap_days"].median()
final = make_models()[best]
final.fit(prep(df, med_all), df["churned"])
sc = load("scoring_dataset")
sc["churn_prob"] = final.predict_proba(prep(sc, med_all))[:, 1]
sc["risk_band"] = pd.cut(sc["churn_prob"], [-0.01, 0.4, 0.7, 1.01],
                         labels=["Low", "Medium", "High"]).astype(str)
out = sc[["customer_id", "churn_prob", "risk_band"]].copy()
out["churn_prob"] = out["churn_prob"].round(4)
print("\n--- Risk bands (scoring date 2011-12-10) ---")
print(out["risk_band"].value_counts().to_string())
out.to_csv("data/processed/churn_scores.csv", index=False)
out.to_sql("churn_scores", engine, if_exists="replace", index=False)
print("\nSaved: churn_model.png, churn_scores.csv, aur MySQL table churn_scores")