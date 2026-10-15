"""
db_utils.py
Shared database helpers for all Olist notebooks (EDA, RFM, Churn).

Usage inside a notebook (kernel running from the notebooks/ folder):
    from db_utils import run_query, read_view
    df = read_view("vw_CustomerSummary")
"""
from functools import lru_cache
from urllib.parse import quote_plus

import pandas as pd
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

# Connection settings - same values as tools/export_query_results.py
SERVER = r"localhost\SQLEXPRESS"
DATABASE = "OlistDB"
DRIVER = "ODBC Driver 18 for SQL Server"


@lru_cache(maxsize=1)  # build the engine once, reuse it on every call
def get_engine() -> Engine:
    """Return a SQLAlchemy engine for OlistDB (Windows Authentication)."""
    odbc_str = (
        f"DRIVER={{{DRIVER}}};"
        f"SERVER={SERVER};"
        f"DATABASE={DATABASE};"
        "Trusted_Connection=yes;"       # Windows Authentication, no password
        "TrustServerCertificate=yes;"   # Driver 18 encrypts by default; local self-signed cert
    )
    return create_engine(f"mssql+pyodbc:///?odbc_connect={quote_plus(odbc_str)}")


def run_query(sql: str) -> pd.DataFrame:
    """Run any SELECT statement and return the result as a DataFrame."""
    with get_engine().connect() as conn:
        return pd.read_sql(text(sql), conn)


def read_view(view_name: str, schema: str = "rpt") -> pd.DataFrame:
    """Read a whole reporting view, e.g. read_view('vw_CustomerSummary')."""
    return run_query(f"SELECT * FROM {schema}.{view_name}")
