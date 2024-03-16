# DNS Setup Example

## Docs
https://docs.controlplane.com/guides/configure-domain#dns-records

## Example

About reactrails.com DNS, steps:
1. create CNAME or ALIAS record pointing to rails-xxxx.cpln.app
1. go to CPLN Domains -> create
1. add reactrails.com copy code from there
1. add TXT record with code as _cpln.reactrails.com
1. hit ok on CPLN, route to rails workload when asked
1. wait domain check and certificates created
