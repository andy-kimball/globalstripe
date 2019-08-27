# README

GlobalStripe shows how to build a global version of Stripe using CRDB.

## How to Setup

#### Application ####
* Install Node v6 or higher
* npm install -g serverless
serverless create -t aws-go -p globalstripe

#### Local cluster ####
* ./cockroach start --insecure --locality="cloud=aws,region=us-east-2,zone=us-east-2a" --store=node1 --listen-addr=localhost:26257 --http-addr=localhost:8080
* ./cockroach start --insecure --locality="cloud=aws,region=eu-west-3,zone=eu-west-3a" --store=node2 --listen-addr=localhost:26258 --http-addr=localhost:8081 --join=localhost:26257
* ./cockroach start --insecure --locality="cloud=aws,region=ap-northeast-2,zone=ap-northeast-2a" --store=node3 --listen-addr=localhost:26259 --http-addr=localhost:8082 --join=localhost:26257

#### Cloud cluster (mimics future entry-level MSO cluster) ####
* export CLUSTER=andyk-test
* roachprod create $CLUSTER -n 3 --aws-zones="us-east-2a,eu-west-3a,ap-northeast-2a" --geo --clouds=aws

* roachprod stage $CLUSTER cockroach
* or for custom build:
* roachprod put $CLUSTER cockroach-linux; roachprod run $CLUSTER "cp cockroach-linux cockroach"

* roachprod start $CLUSTER --secure

#### Create schema ####
Run schema.sql on the newly created cluster: roachprod sql $CLUSTER:1 --secure

#### Create and deploy Ruby libraries and application using Serverless ####
* Install Node v6 or higher
* npm install -g serverless
* ./build.sh
* sls deploy

## How to Run
Some default accounts are already populated by the SQL script.

#### List accounts ####

curl https://globalstripe.demo.cockroachdb.dev/accounts -u sk_test_L1K7x6igR9CBDGMkEcyvZJRf: 2>/dev/null | json_pp | pygmentize -l json -f terminal256 -O style=emacs

curl https://globalstripe.demo.cockroachdb.dev/accounts -u sk_test_5QqJZz3BQRRYcvJqW7FchfIG: -w "\n\n%{time_starttransfer} seconds\n" 2>/dev/null

#### Create some charges ####

curl https://globalstripe.demo.cockroachdb.dev/charges -u sk_test_L1K7x6igR9CBDGMkEcyvZJRf: -d amount=100.00 -d currency=USD -d card_number=4242424242424242 2>/dev/null | json_pp | pygmentize -l json -f terminal256 -O style=emacs

curl https://globalstripe.demo.cockroachdb.dev/charges -u sk_test_5QqJZz3BQRRYcvJqW7FchfIG: -d amount=25.39 -d currency=USD -d card_number=4242424242424242 2>/dev/null | json_pp | pygmentize -l json -f terminal256 -O style=emacs

curl https://globalstripe.demo.cockroachdb.dev/charges -u sk_test_5QqJZz3BQRRYcvJqW7FchfIG: -d amount=10.00 -d currency=USD -d card_number=4242424242424242 -w "\n\n%{time_starttransfer} seconds\n" 2>/dev/null

#### List all charges for a user ####
curl https://globalstripe.demo.cockroachdb.dev/charges -u sk_test_5QqJZz3BQRRYcvJqW7FchfIG: 2>/dev/null | json_pp | pygmentize -l json -f terminal256 -O style=emacs

curl https://globalstripe.demo.cockroachdb.dev/charges -u sk_test_L1K7x6igR9CBDGMkEcyvZJRf: -w "\n\n%{time_starttransfer} seconds\n" 2>/dev/null 2>/dev/null

#### List one charge for a user ####
curl https://globalstripe.demo.cockroachdb.dev/charges/38687a86-628f-4358-8f5f-bbb2c1849b27 -u sk_test_L1K7x6igR9CBDGMkEcyvZJRf: 2>/dev/null | json_pp | pygmentize -l json -f terminal256 -O style=emacs

curl https://globalstripe.demo.cockroachdb.dev/charges/38687a86-628f-4358-8f5f-bbb2c1849b27 -u sk_test_L1K7x6igR9CBDGMkEcyvZJRf: -w "\n\n%{time_starttransfer} seconds\n" 2>/dev/null
