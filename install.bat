@echo off
perl Makefile.PL
dmake
dmake install
pause
dmake clean
