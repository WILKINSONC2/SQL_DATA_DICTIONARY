pip install pyinstaller
del build /q /s
del dist /q /s
pyinstaller sql_dict.py
del build /q /s
xcopy input dist\sql_dict\input\
xcopy temp dist\sql_dict\temp\
xcopy output dist\sql_dict\output\
xcopy pandoc.css dist\sql_dict\
pause
