#!/bin/bash

# Trying to deal with an error I get during load testing:
# [2019-07-16T01:50:29.406Z] [ERROR] [Database.swift:46 init(showStartupInfo:)] Failure connecting to mySQL server docker.for.mac.localhost: Failure: 2003 ' (110)
# It looks like this may be due to number of files that can be opened
# See https://www.percona.com/blog/2014/12/08/what-happens-when-your-application-cannot-open-yet-another-connection-to-mysql/
# https://superuser.com/questions/433746/is-there-a-fix-for-the-too-many-open-files-in-system-error-on-os-x-10-7-1

ulimit -n 4096
locust --host=http://localhost:8080