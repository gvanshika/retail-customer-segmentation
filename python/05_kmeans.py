import os
import getpass
import urllib.parse
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from sqlalchemy import create_engine
from sklearn.preprocessing import StandardScaler
from sklearn.cluster import KMeans
from sklearn.metrics import (silhouette_score, adjusted_rand_score,
                             normalized_mutual_info_score)

# ---------- Settings ----------
K_OVERRIDE = None    # None = silhouette se k auto-pick (3 se 6 ke beech); kisi number par fix karna ho to e.g. 4
RANDOM_STATE = 42

# ---------- 1. MySQL se data ----------
# Password file mein nahi likha, run karte waqt maangega (GitHub par safe rahega)
pwd = urllib.parse.quote_plus(os.environ.get("MYSQL_PWD") or getpass.getpass("MySQL password: "))
engine = create_engine(f"mysql+pymysql://retail_user:{pwd}@127.0.0.1:3306/retail_seg")
df = pd.read_sql(
    "SELECT customer_id, recency_days, frequency, monetary, segment FROM rfm_segments",
    engine)
for c in ["recency_days", "frequency", "monetary"]:
    df[c] = df[c].astype(float)
print("Rows:", len(df))   # 5852 aana chahiye

# ---------- 2. Features: log + scale ----------
# Monetary bahut skewed hai (max 580,987, average 2,875), isliye pehle log, phir scale
X = np.log1p(df[["recency_days", "frequency", "monetary"]])
X_scaled = StandardScaler().fit_transform(X)

# ---------- 3. K chunna (elbow + silhouette) ----------
rows = []
for k in range(2, 9):
    km = KMeans(n_clusters=k, n_init=10, random_state=RANDOM_STATE).fit(X_scaled)
    rows.append((k, km.inertia_, silhouette_score(X_scaled, km.labels_)))
k_table = pd.DataFrame(rows, columns=["k", "inertia", "silhouette"])
print("\n--- K selection ---")
print(k_table.round(3).to_string(index=False))

cand = k_table[(k_table.k >= 3) & (k_table.k <= 6)]
k_final = int(K_OVERRIDE) if K_OVERRIDE else int(cand.loc[cand.silhouette.idxmax(), "k"])
print("Chosen k:", k_final)

fig, ax = plt.subplots(1, 2, figsize=(10, 4))
ax[0].plot(k_table.k, k_table.inertia, marker="o")
ax[0].set_title("Elbow (inertia)")
ax[0].set_xlabel("k")
ax[1].plot(k_table.k, k_table.silhouette, marker="o")
ax[1].set_title("Silhouette score")
ax[1].set_xlabel("k")
plt.tight_layout()
plt.savefig("outputs/kmeans_k_selection.png", dpi=150)
plt.close()

# ---------- 4. Final K-means ----------
km = KMeans(n_clusters=k_final, n_init=10, random_state=RANDOM_STATE).fit(X_scaled)
df["cluster"] = km.labels_

# ---------- 5. Cluster profile (asli values mein) ----------
profile = df.groupby("cluster").agg(
    customers=("customer_id", "count"),
    avg_recency=("recency_days", "mean"),
    avg_frequency=("frequency", "mean"),
    avg_spend=("monetary", "mean"),
    revenue=("monetary", "sum"),
).round(1)
profile["pct_customers"] = (100 * profile.customers / len(df)).round(1)
profile["pct_revenue"] = (100 * profile.revenue / df.monetary.sum()).round(1)
print("\n--- Cluster profile ---")
print(profile.to_string())

# ---------- 6. K-means vs RFM segments ----------
print("\n--- Cluster x RFM segment (customers ki ginti) ---")
print(pd.crosstab(df.cluster, df.segment).to_string())
print("\n--- Cluster x RFM segment (row %, har cluster mein segment ka hissa) ---")
print((pd.crosstab(df.cluster, df.segment, normalize="index") * 100).round(0).to_string())

ari = adjusted_rand_score(df.segment, df.cluster)
nmi = normalized_mutual_info_score(df.segment, df.cluster)
print("\nAgreement with RFM segments -> ARI:", round(ari, 3), "| NMI:", round(nmi, 3))

# ---------- 7. Stability: alag seeds par same clusters aate hain? ----------
aris = []
for seed in range(1, 11):
    other = KMeans(n_clusters=k_final, n_init=10, random_state=seed).fit(X_scaled).labels_
    aris.append(adjusted_rand_score(km.labels_, other))
print("Stability (10 seeds) -> min ARI:", round(min(aris), 3),
      "| mean ARI:", round(float(np.mean(aris)), 3))
print("Silhouette (final k):", round(silhouette_score(X_scaled, km.labels_), 3))

# ---------- 8. Chart ----------
plt.figure(figsize=(7, 5))
plt.scatter(X["recency_days"], X["monetary"], c=df.cluster, s=6, cmap="tab10")
plt.xlabel("log(1 + recency days)")
plt.ylabel("log(1 + monetary)")
plt.title(f"K-means clusters (k={k_final})")
plt.savefig("outputs/kmeans_clusters.png", dpi=150)
plt.close()

# ---------- 9. Save ----------
df[["customer_id", "cluster", "segment"]].to_csv(
    "data/processed/customer_clusters.csv", index=False)
(df[["customer_id", "cluster"]]
   .rename(columns={"cluster": "kmeans_cluster"})
   .to_sql("customer_clusters", engine, if_exists="replace", index=False))
print("\nSaved: CSV, 2 charts, aur MySQL table customer_clusters")