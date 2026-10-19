import os
import getpass
import urllib.parse
import numpy as np
import pandas as pd
from sqlalchemy import create_engine
from sklearn.preprocessing import StandardScaler
from sklearn.cluster import KMeans
from sklearn.metrics import silhouette_score, adjusted_rand_score

pwd = urllib.parse.quote_plus(os.environ.get("MYSQL_PWD") or getpass.getpass("MySQL password: "))
engine = create_engine(f"mysql+pymysql://retail_user:{pwd}@127.0.0.1:3306/retail_seg")

df = pd.read_sql("SELECT recency_days, frequency, monetary FROM rfm_segments", engine).astype(float)
X = StandardScaler().fit_transform(np.log1p(df))
rng = np.random.default_rng(42)

rows = []
for k in [3, 4, 5, 6]:
    full = KMeans(n_clusters=k, n_init=10, random_state=42).fit(X)
    aris = []
    for b in range(20):
        idx = rng.choice(len(X), size=int(0.8 * len(X)), replace=False)
        sub = KMeans(n_clusters=k, n_init=10, random_state=b).fit(X[idx])
        # everyone is assigned to the subsample's nearest centroid, then compared with the full-data clusters
        aris.append(adjusted_rand_score(full.labels_, sub.predict(X)))
    rows.append({"k": k, "silhouette": silhouette_score(X, full.labels_),
                 "subsample_ARI_mean": np.mean(aris), "subsample_ARI_min": np.min(aris)})
print(pd.DataFrame(rows).round(3).to_string(index=False))