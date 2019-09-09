-- noinspection SqlNoDataSourceInspectionForFile
-- Use this for clean reset.
-- USE defaultdb; DROP DATABASE globalstripe CASCADE;

SET CLUSTER SETTING cluster.organization = 'Cockroach Labs - Production Testing'; SET CLUSTER SETTING enterprise.license = 'crl-0-EJL04ukFGAEiI0NvY2tyb2FjaCBMYWJzIC0gUHJvZHVjdGlvbiBUZXN0aW5n';

CREATE DATABASE IF NOT EXISTS globalstripe;

CREATE USER IF NOT EXISTS globalstripe WITH PASSWORD '5B57E9F2-A7E9-46DA-B1D2-448334CC6233';
GRANT ALL ON DATABASE globalstripe TO globalstripe;

USE globalstripe;

CREATE TABLE IF NOT EXISTS accounts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    email STRING NOT NULL,
    secret_key_digest STRING NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    UNIQUE INDEX secret_key_index (secret_key_digest ASC) STORING (email, created_at)
) REPLICATE BY LOCALITY;

GRANT ALL ON TABLE accounts TO globalstripe;

INSERT INTO accounts (email, secret_key_digest) VALUES ('andyk@cockroachlabs.com', 'SIvNOv4nwinsxajJKlIMyo5UvA0NVUlCNx2De6eRvtg=');
INSERT INTO accounts (email, secret_key_digest) VALUES ('jordan@cockroachlabs.com', 'YhEmg2NAcsHhpedc3nOhJzI_XX8qUHYwKlpUT-p_TFM=');

CREATE TABLE IF NOT EXISTS charges (
    account_id UUID NOT NULL,
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    amount DECIMAL NOT NULL,
    currency STRING NOT NULL,
    last4 STRING(4) NOT NULL,
    outcome STRING CHECK (outcome IN ('authorized', 'manual_review', 'issuer_declined', 'blocked', 'invalid')),
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    PRIMARY KEY (account_id, id),
    INDEX charges_by_created_at (account_id, created_at) STORING (amount, currency, last4, outcome)
) PARTITION BY LOCALITY;

GRANT ALL ON TABLE charges TO globalstripe;
