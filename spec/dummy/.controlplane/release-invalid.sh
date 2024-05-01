#!/bin/sh

cpl run -a $APP_NAME --image latest -- bundle exec rake db:nonexistent
