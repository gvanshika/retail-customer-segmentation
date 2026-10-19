import pandas as pd

src = "data/raw/online_retail_II.xlsx"

sheets = pd.read_excel(src, sheet_name=None, dtype=str)

frames = []
for name, df in sheets.items():
    df["source_sheet"] = name
    print(name, "->", len(df), "rows")
    frames.append(df)

df = pd.concat(frames, ignore_index=True)

df.columns = ["invoice", "stock_code", "description", "quantity",
              "invoice_date", "price", "customer_id", "country", "source_sheet"]

df["customer_id"] = df["customer_id"].str.replace(r"\.0$", "", regex=True)

print("Total rows:", len(df))
df.to_csv("data/raw/online_retail_II.csv", index=False, lineterminator="\n")
print("CSV ban gayi")