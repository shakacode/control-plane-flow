#!/bin/sh

cpl run:detached -a $APP_NAME --image latest -- bundle exec rake db:prepare
