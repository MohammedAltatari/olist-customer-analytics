"""
export_query_results.py
Runs a .sql file against OlistDB and saves ALL result sets
into one text file: data/output/<script_name>_results.txt

Usage (from the project folder):
    python tools/export_query_results.py sql/06_analysis_queries.sql
"""
import re
import sys
from pathlib import Path

import pandas as pd
import pyodbc

# Connection settings - change SERVER if your instance name is different
CONN_STR = (
    "DRIVER={ODBC Driver 18 for SQL Server};"
    "SERVER=localhost\\SQLEXPRESS;"
    "DATABASE=OlistDB;"
    "Trusted_Connection=yes;"
    "TrustServerCertificate=yes;"
)


def split_batches(sql_text: str) -> list[str]:
    """Split a script on lines containing only GO (like SSMS does)."""
    parts = re.split(r"^\s*GO\s*$", sql_text, flags=re.IGNORECASE | re.MULTILINE)
    return [p.strip() for p in parts if p.strip()]


def main() -> None:
    if len(sys.argv) != 2:
        print("Usage: python tools/export_query_results.py <file.sql>")
        sys.exit(1)

    sql_file = Path(sys.argv[1])
    out_dir = Path("data/output")
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / f"{sql_file.stem}_results.txt"

    batches = split_batches(sql_file.read_text(encoding="utf-8"))
    pd.set_option("display.width", 250)
    pd.set_option("display.max_columns", 50)
    pd.set_option("display.max_rows", 500)

    lines = []
    result_no = 0
    with pyodbc.connect(CONN_STR, autocommit=True) as conn:
        cur = conn.cursor()
        for batch in batches:
            cur.execute(batch)
            while True:
                if cur.description:  # this statement returned rows
                    result_no += 1
                    cols = [c[0] for c in cur.description]
                    df = pd.DataFrame.from_records(cur.fetchall(), columns=cols)
                    lines.append(f"===== Result {result_no} ({len(df)} rows) =====")
                    lines.append(df.to_string(index=False))
                    lines.append("")
                if not cur.nextset():
                    break

    out_file.write_text("\n".join(lines), encoding="utf-8")
    print(f"Saved {result_no} result sets to {out_file}")


if __name__ == "__main__":
    main()
