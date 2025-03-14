# CI Automation, Review Apps, Staging, and Promoting to Production

## Setting up Tokens for CI Automation

The examples uses Github Actions as an example. The same applies to Circle CI and other similar CI/CD tools.

1. Ensure that you have two orgs:
  1. `company-staging` (for staging deployments, developers have access)
  2. `company-production` (for production deployments, limited access)
2. Create the token for staging org and set on Github repository secrets and variables:
  1. Go to the Control Plane UI for your organization's staging org
  2. Make a new service account called `github-actions-staging`
  3. Assign to the group `superusers`
  4. Click "Keys" and create a one with description "Github Actions" and copy the token (or download it).
  5. Add this key to your Github repository **secrets** as `CPLN_TOKEN_STAGING`
  6. Add another key to your Github repository **variables** as `CPLN_ORG_STAGING` with the name of the staging org, like `company-staging`
3. Create the token for production org, and set on Github repository secrets and variables.
  1. Go to the Control Plane UI for your organization's production org
  2. Make a new service account called `github-actions-production`
  3. Assign to the group `superusers`
  4. Click "Keys" and create a one with description "Github Actions" and copy the token (or download it).
  5. Add this key to your Github repository **secrets** as `CPLN_TOKEN_PRODUCTION`
  6. Add another key to your Github repository **variables** as `CPLN_ORG_PRODUCTION` with the name of the production org, like `company-production`
4. Create a few more ENV **variables** for the app name and the app prefix:
  1. `STAGING_APP_NAME` - the name of the app in Control Plane for staging, which is the GVC name, like `app-name-staging`
  2. `PRODUCTION_APP_NAME` - the name of the app in Control Plane for production, which is the GVC name, like `app-name-production`
  3. `REVIEW_APP_PREFIX` - the prefix for the review apps in Control Plane. The Review apps are named `$REVIEW_APP_PREFIX-pr-$PR_NUMBER`
5. All in all, you should have 7 secrets set in your Github repository



3. Go to the Control Plane UI for your organization's staging org
3. and make a new service account
