-- Use this for clean reset.
-- USE defaultdb; DROP DATABASE globalstripe CASCADE;

SET CLUSTER SETTING cluster.organization = 'Cockroach Labs - Production Testing'; SET CLUSTER SETTING enterprise.license = 'crl-0-EJL04ukFGAEiI0NvY2tyb2FjaCBMYWJzIC0gUHJvZHVjdGlvbiBUZXN0aW5n';

CREATE DATABASE IF NOT EXISTS globalstripe;

CREATE USER IF NOT EXISTS globalstripe WITH PASSWORD '5B57E9F2-A7E9-46DA-B1D2-448334CC6233';

GRANT ALL ON DATABASE globalstripe TO globalstripe;

USE globalstripe;

-- Create REPLICATED accounts table.
-- The contents of a REPLICATED table are copied to every locality.
--   Advantages   : O(1ms) reads for all data in every region
--   Disadvantages: O(100ms) writes, N copies of data (where N=#regions)
-- Use Ruby ActiveRecord conventions (e.g. the timestamp fields).
CREATE TABLE IF NOT EXISTS accounts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    email STRING NOT NULL,
    secret_key_digest STRING NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    UNIQUE INDEX accounts_on_email (email ASC)
);

CREATE UNIQUE INDEX IF NOT EXISTS secret_key_us ON accounts (secret_key_digest ASC) STORING (email, created_at);
ALTER INDEX accounts@secret_key_us CONFIGURE ZONE USING lease_preferences='[[+region=us-east-2]]';

CREATE UNIQUE INDEX IF NOT EXISTS secret_key_europe ON accounts (secret_key_digest ASC) STORING (email, created_at);
ALTER INDEX accounts@secret_key_europe CONFIGURE ZONE USING lease_preferences='[[+region=eu-west-3]]';

CREATE UNIQUE INDEX IF NOT EXISTS secret_key_asia ON accounts (secret_key_digest ASC) STORING (email, created_at);
ALTER INDEX accounts@secret_key_asia CONFIGURE ZONE USING lease_preferences='[[+region=ap-northeast-2]]';

GRANT ALL ON TABLE accounts TO globalstripe;

-- Create some test accounts.
-- Digest is derived from this secret key: sk_test_L1K7x6igR9CBDGMkEcyvZJRf.
INSERT INTO accounts (email, secret_key_digest) VALUES ('andyk@cockroachlabs.com', 'SIvNOv4nwinsxajJKlIMyo5UvA0NVUlCNx2De6eRvtg=');

-- Digest is derived from this secret key: sk_test_5QqJZz3BQRRYcvJqW7FchfIG.
INSERT INTO accounts (email, secret_key_digest) VALUES ('jordan@cockroachlabs.com', 'YhEmg2NAcsHhpedc3nOhJzI_XX8qUHYwKlpUT-p_TFM=');

-- Create PARTITIONED charges table.
-- A PARTITIONED table stores each row in the locality that matches its "region" column.
--   Advantages   : O(1ms) reads and and writes for local data (in same region)
--   Disadvantages: O(100ms) reads and writes for remote data (in another region)
-- Use Ruby ActiveRecord conventions (e.g. the timestamp fields).
CREATE TABLE IF NOT EXISTS charges (
    region STRING DEFAULT (crdb_internal.locality_value('region')) NOT NULL CHECK (region IN ('us-east-2', 'eu-west-3', 'ap-northeast-2')),
    id UUID DEFAULT gen_random_uuid() NOT NULL,
    amount DECIMAL NOT NULL,
    currency STRING NOT NULL,
    last4 STRING(4) NOT NULL,
    outcome STRING CHECK (outcome IN ('authorized', 'manual_review', 'issuer_declined', 'blocked', 'invalid')),
    account_id UUID NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT now(),
    PRIMARY KEY (region, id),
    UNIQUE INDEX charges_by_created_at (region, account_id, created_at, id) STORING (amount, currency, last4, outcome)
);

-- Partition primary index by available regions.
ALTER TABLE charges PARTITION BY LIST (region) (
    PARTITION us VALUES IN ('us-east-2'),
    PARTITION europe VALUES IN ('eu-west-3'),
    PARTITION asia VALUES IN ('ap-northeast-2')
);

-- Pin table and all its indexes to corresponding data centers.
-- Use 1x replication, since assumption is that EBS/EFS has enough redundancy.
ALTER PARTITION us OF TABLE charges CONFIGURE ZONE USING constraints='[+region=us-east-2]', lease_preferences='[[+region=us-east-2]]', num_replicas=1;
ALTER PARTITION europe OF TABLE charges CONFIGURE ZONE USING constraints='[+region=eu-west-3]', lease_preferences='[[+region=eu-west-3]]', num_replicas=1;
ALTER PARTITION asia OF TABLE charges CONFIGURE ZONE USING constraints='[+region=ap-northeast-2]', lease_preferences='[[+region=ap-northeast-2]]', num_replicas=1;

-- Partition charges_by_created_at index by available regions.
ALTER INDEX charges@charges_by_created_at PARTITION BY LIST (region) (
    PARTITION created_at_us VALUES IN ('us-east-2'),
    PARTITION created_at_europe VALUES IN ('eu-west-3'),
    PARTITION created_at_asia VALUES IN ('ap-northeast-2')
);

-- Pin leaseholder of each charges_by_created_at index range to corresponding data center.
-- NOTE: This should use 1x replication in future so that writes are fast.
ALTER PARTITION created_at_us OF INDEX charges@charges_by_created_at CONFIGURE ZONE USING constraints='[+region=us-east-2]', lease_preferences='[[+region=us-east-2]]', num_replicas=1;
ALTER PARTITION created_at_europe OF INDEX charges@charges_by_created_at CONFIGURE ZONE USING constraints='[+region=eu-west-3]', lease_preferences='[[+region=eu-west-3]]', num_replicas=1;
ALTER PARTITION created_at_asia OF INDEX charges@charges_by_created_at CONFIGURE ZONE USING constraints='[+region=ap-northeast-2]', lease_preferences='[[+region=ap-northeast-2]]', num_replicas=1;

GRANT ALL ON TABLE charges TO globalstripe;
