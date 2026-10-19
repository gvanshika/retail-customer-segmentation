import os
import getpass
import urllib.parse
import pandas as pd
from sqlalchemy import create_engine

pwd = urllib.parse.quote_plus(os.environ.get("MYSQL_PWD") or getpass.getpass("MySQL password: "))
engine = create_engine(f"mysql+pymysql://retail_user:{pwd}@127.0.0.1:3306/retail_seg")

TABLES = ["customer_360", "cohort_retention_pct", "monthly_summary",
          "cleaning_waterfall", "simulator_scenarios", "segment_actions"]
os.makedirs("data/powerbi", exist_ok=True)
for t in TABLES:
    d = pd.read_sql(f"SELECT * FROM {t}", engine)
    d.to_csv(f"data/powerbi/{t}.csv", index=False)
    print(f"{t}: {len(d)} rows, {d.shape[1]} columns")
print("Saved CSVs in data/powerbi")