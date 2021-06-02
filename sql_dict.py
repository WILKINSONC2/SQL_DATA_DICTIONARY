import os, sys
from time import sleep
import re
from shutil import copyfile

import pandas as pd
import pyodbc
from bs4 import BeautifulSoup


def screen_clear():
    # for mac and linux(here, os.name is 'posix')
    if os.name == 'posix':
        os.system('clear')
        print()
        print("SQL DATA DICTIONARY")
        print("===================")
        print("")
    else:
        # for windows platform
        os.system('cls')
        print()
        print("SQL DATA DICTIONARY")
        print("===================")
        print("")


try:
    screen_clear()

    print("Current Working Directory ", os.getcwd())

    if os.getcwd().find('\\dist\\') >= 0 \
            or os.getcwd().find('\\build\\') >= 0:
        os.chdir(os.getcwd().replace('\\dist\\Make_Markdown', ''))
        os.chdir(os.getcwd().replace('\\build\\Make_Markdown', ''))
        print("Set Working Directory ", os.getcwd())

    screen_clear()

    print(os.getcwd())
    sleep(5)
    screen_clear()

    server = input("Enter server name: ")
    database = input("Enter database name: ")

    authentication_method = input("Enter authentication type (WIN,AD,USER): ")
    authentication = ''

    username = input("Enter username (leave blank if using AD or WIN): ")
    password = input("Enter password (leave blank if using AD or WIN): ")
    hash_password = password[-1:].rjust(len(password), "*")[:-1] + '*'

    sleep(5)
    screen_clear()
    print("Making database connection...")

    if authentication_method.upper() == 'WIN':
        authentication = "Trusted_Connection=yes"
        authentication_method = "Trusted Connection (Windows)"
    elif authentication_method.upper() == 'AD':
        authentication = "Authentication=ActiveDirectoryIntegrated"
        authentication_method = "Azure Integrated AD"
    else:
        authentication = 'UID=' + username + '; ' \
                                             'PWD=' + password
        authentication_method = "None / SQL username and password (username:" + username + "" \
                                                            " / password: " + hash_password + ")"

    try:
        connection = pyodbc.connect(
            'DRIVER={ODBC Driver 17 for SQL Server};SERVER=' + server +
                     ';DATABASE=' + database + ';' + authentication, timeout=7200)
        connection.timeout = 7200
        connection.setencoding('utf-8')
        connection.setdecoding(pyodbc.SQL_CHAR, 'utf-8')
        connection.setdecoding(pyodbc.SQL_WCHAR, 'utf-8')
        connection.setdecoding(pyodbc.SQL_WMETADATA, 'utf-8')

    except Exception as e:
        print(e)

    sql_connection = connection.cursor()

    sql = "DECLARE @enable_tables BIT = 1;" \
          "DECLARE @enable_views BIT = 1;" \
          "DECLARE @enable_triggers BIT = 1;" \
          "DECLARE @enable_procs BIT = 1;" \
          ""
    sql = sql + open("./input/dd_query.sql", "r", encoding="utf-8").read()

    print("Opening connection to server[" + server.replace("[", "").replace("]", "")
          + "], database[" + database.replace("[", "").replace("]", "") + "]...")
    print("Authentication mode: " + authentication_method)

    try:
        sql_connection.execute(sql)
    except Exception as e:
        print(e)

    print("Fetching metadata...")

    df = pd.DataFrame(sql_connection.fetchall())

    # print(df)
    df.to_csv('./temp/dd_output.csv', header=None, index=None, encoding="utf-8")

    # Clean up

    sql_connection.close()

    l = ''

    print("Creating markdown document...")

    with open("./temp/dd_output.csv", "r") as fp:
        line = fp.readline()
        while line:
            l = l + (re.sub(r'^...', '', line.strip())[:-5]) + '\n'
            line = fp.readline()
    # print(l)

    o = open("./output/data_dictionary.md", "w")
    l = l.replace("```sql <br/>", "```sql \n")
    l = l.replace("\"```sql", "```sql \n")
    l = l.replace("\\r ```<br/>```", "\n")
    l = l.replace("\\t", "    ")
    l = l.replace("```<br/>", "``` \n")
    l = l.replace("``` \r\"", "``` \n")
    l = l.replace("``` \n\"", "``` \n")

    o.write(l)
    o.close()

    print("Creating html document...")

    pan_args = 'pandoc output/data_dictionary.md -f gfm -t html -F mermaid-filter.cmd -o temp/dd_output.html '  ##-- toc --standalone

    os.system(pan_args)

    stylesheet = "./data_dictionary.css"
    htmlin = "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\"" \
             "   \"http://www.w3.org/TR/html4/strict.dtd\">" \
             "<HTML>" \
             "<HEAD>" \
             "<LINK href=\"" + stylesheet + "\" rel=\"stylesheet\" type=\"text/css\">" \
             "</HEAD>" \
             "<BODY> "
    htmlin = htmlin + open("./temp/dd_output.html", "r", encoding="utf-8").read()
    htmlin = htmlin + " </BODY> </HTML>"
    htmlpretty = BeautifulSoup(htmlin, features="html.parser")
    htmlout = htmlpretty.prettify()

    o = open("./output/data_dictionary.html", "w")
    o.write(htmlout)
    o.close()

    print("...Attaching CSS...")

    copyfile('./pandoc.css', './output/data_dictionary.css')

    print('')
    input("Press Enter to continue...")
    print("...Goodbye!")
    sleep(5)

except:
    print("Unexpected error:", sys.exc_info()[0])
    input("Press Enter to continue...")
    print("...Goodbye!")
    sleep(5)

