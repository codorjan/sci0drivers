; define a Pascal-style string with the size in front
%macro pstring 1+
    db %%end-$-1,%1
    %%end:
%endmacro
