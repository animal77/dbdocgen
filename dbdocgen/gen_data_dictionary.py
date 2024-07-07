import os

from sqlalchemy import create_engine, text


def execute_sql(connection_string, sql_file, output_file):
    # Get the directory of the current script
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # Construct the full file path relative to the script directory
    file_path = os.path.join(script_dir, sql_file)

    engine = create_engine(connection_string)
    with engine.connect() as connection:
        with open(file_path, "r", encoding="utf-8") as file:
            sql = text(file.read())
            result = connection.execute(sql)
            with open(output_file, "w", encoding="utf-8") as outfile:
                for row in result:
                    outfile.write(",".join(str(value) for value in row) + "\n")


if __name__ == "__main__":
    # oracle, postgres, mssql, db2
    DATABASE_TYPE = "mssql"
    CONN_STRING = "mssql+pyodbc://SA:Pa55word!@localhost:1433/MyDatabase?driver=ODBC+Driver+18+for+SQL+Server&trustServerCertificate=yes"
    SQL_FILE = "sql/genDataDictionary_" + DATABASE_TYPE + ".sql"
    OUTPUT_FILE = "out.txt"
    execute_sql(CONN_STRING, SQL_FILE, OUTPUT_FILE)

# CONN_STRING = postgresql://username:password@hostname:port/db_name
# CONN_STRING = mssql+pyodbc://SA:Pa55word!@localhost:1433/MyDatabase?driver=ODBC+Driver+18+for+SQL+Server&trustServerCertificate=yes
# CONN_STRING = oracle+cx_oracle://username:password@hostname:port/db_name
# CONN_STRING = db2+ibm_db://username:password@hostname:port/db_name
