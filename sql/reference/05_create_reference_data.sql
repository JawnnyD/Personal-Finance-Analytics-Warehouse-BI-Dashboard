-- Reference tables define the valid values used by the V2 transaction pipeline

-- transaction type unique identifier, valid seeded values found in CONSTRAINT
CREATE TABLE IF NOT EXISTS reference.transaction_types
       (
        transaction_type text PRIMARY KEY,
        signed_amount_multiplier smallint NOT NULL,
        is_income boolean NOT NULL,
        is_expense boolean NOT NULL,
        is_refund boolean NOT NULL,

        CONSTRAINT transaction_types_valid_combination CHECK
            (
             (transaction_type = 'Expense'
                AND signed_amount_multiplier = -1
                AND is_income = FALSE
                AND is_expense = TRUE
                AND is_refund = FALSE)
             OR
             (transaction_type = 'Income'
                AND signed_amount_multiplier = 1
                AND is_income = TRUE
                AND is_expense = FALSE
                AND is_refund = FALSE)
             OR
             (transaction_type = 'Refund'
                AND signed_amount_multiplier = 1
                AND is_income = FALSE
                AND is_expense = FALSE
                AND is_refund = TRUE)
            )

       );

-- simple lookup table
CREATE TABLE IF NOT EXISTS reference.people (
       person text PRIMARY KEY
);

-- simple lookup table
CREATE TABLE IF NOT EXISTS reference.payment_methods (
       payment_method text PRIMARY KEY
);

-- main reporting classification table
CREATE TABLE IF NOT EXISTS reference.category_subcategories (
       category text NOT NULL
     , subcategory text NOT NULL
     , expense_group text NOT NULL
     , is_fixed_expense boolean
     
       -- pair must be unique
     , PRIMARY KEY (category, subcategory)

     , CONSTRAINT category_subcategories_expense_group_check
            CHECK (expense_group IN ('Needs', 'Wants', 'Income', 'Unclassified'))
);

-- defines valid account combinations
CREATE TABLE IF NOT EXISTS reference.person_payment_accounts (
       person text NOT NULL
     , payment_method text NOT NULL
     , account_name text NOT NULL
     
     , PRIMARY KEY (person, payment_method, account_name)
     
       -- foreign keys ensure each mapping uses and existing person
     , CONSTRAINT person_payment_accounts_person_fkey
            FOREIGN KEY (person)
            REFERENCES reference.people (person)
        
       -- foreign keys ensure each mapping uses and existing payment method
     , CONSTRAINT person_payment_accounts_payment_method_fkey
            FOREIGN KEY (payment_method)
            REFERENCES reference.payment_methods (payment_method)
);

-- standardizes merchant/source variations
CREATE TABLE IF NOT EXISTS reference.source_mappings (
       source_match_key text PRIMARY KEY
     , source_clean text NOT NULL
);

-- Transaction types determine reporting signs and flags.
INSERT INTO reference.transaction_types (
       transaction_type
     , signed_amount_multiplier
     , is_income
     , is_expense
     , is_refund
)
VALUES ('Expense', -1, FALSE, TRUE, FALSE)
     , ('Income', 1, TRUE, FALSE, FALSE)
     , ('Refund', 1, FALSE, FALSE, TRUE)
    -- on conflict means postgresql found an existing row whose pk matches new row
    ON CONFLICT (transaction_type) DO UPDATE
   -- excluded means "the row postgresql attempted to insert" / replace existing value with proposed new value
   SET signed_amount_multiplier = EXCLUDED.signed_amount_multiplier
     , is_income = EXCLUDED.is_income
     , is_expense = EXCLUDED.is_expense
     , is_refund = EXCLUDED.is_refund;

INSERT INTO reference.people (person)
VALUES ('John')
     , ('Julia')
    ON CONFLICT (person) DO NOTHING;

INSERT INTO reference.payment_methods (payment_method)
VALUES ('Card')
     , ('Cash')
     , ('Venmo')
     , ('Zelle')
     , ('Bank Transfer')
     , ('Other')
    ON CONFLICT (payment_method) DO NOTHING;

-- These are initial analytics classifications.
-- Adjust them later if your own definition of Needs, Wants, or fixed expenses changes.
INSERT INTO reference.category_subcategories (
       category
     , subcategory
     , expense_group
     , is_fixed_expense
)
VALUES ('Housing', 'Rent', 'Needs', TRUE)
     , ('Housing', 'Utilities', 'Needs', FALSE)
     , ('Housing', 'Internet & Phone', 'Needs', TRUE)
     , ('Housing', 'Home Supplies', 'Needs', FALSE)
     , ('Housing', 'Maintenance', 'Needs', FALSE)
     
     , ('Food & Dining', 'Groceries', 'Needs', FALSE)
     , ('Food & Dining', 'Restaurants', 'Wants', FALSE)
     , ('Food & Dining', 'Coffee & Snacks', 'Wants', FALSE)
     
     ,  ('Transportation', 'Fuel', 'Needs', FALSE)
     , ('Transportation', 'Rideshare & Transit', 'Needs', FALSE)
     , ('Transportation', 'Parking', 'Needs', FALSE)
     , ('Transportation', 'Maintenance', 'Needs', FALSE)
   
     , ('Shopping & Household', 'Household', 'Needs', FALSE)
     , ('Shopping & Household', 'Clothing', 'Wants', FALSE)
     , ('Shopping & Household', 'Electronics', 'Wants', FALSE)
     , ('Shopping & Household', 'General Retail', 'Wants', FALSE)
 
     , ('Entertainment', 'Events', 'Wants', FALSE)
     , ('Entertainment', 'Streaming', 'Wants', TRUE)
     , ('Entertainment', 'Hobbies & Games', 'Wants', FALSE)
   
     , ('Pets', 'Food & Supplies', 'Needs', FALSE)
     , ('Pets', 'Veterinary & Grooming', 'Needs', FALSE)
   
     , ('Health & Personal Care', 'Medical', 'Needs', FALSE)
     , ('Health & Personal Care', 'Pharmacy', 'Needs', FALSE)
     , ('Health & Personal Care', 'Personal Care', 'Needs', FALSE)
   
     , ('Travel', 'Lodging', 'Wants', FALSE)
     , ('Travel', 'Travel Transport', 'Wants', FALSE)
     ,  ('Travel', 'Activities', 'Wants', FALSE)
  
     , ('Technology & Subscriptions', 'Software', 'Wants', TRUE)
     , ('Technology & Subscriptions', 'Digital Services', 'Wants', TRUE)
     , ('Technology & Subscriptions', 'Hardware', 'Wants', FALSE)
  
     , ('Gifts & Giving', 'Gifts', 'Wants', FALSE)
     , ('Gifts & Giving', 'Donations', 'Wants', FALSE)
   
     , ('Income', 'Salary', 'Income', NULL)
     , ('Income', 'Freelance', 'Income', NULL)
     , ('Income', 'Interest', 'Income', NULL)
     , ('Income', 'Other Income', 'Income', NULL)
   
     , ('Other', 'Miscellaneous', 'Unclassified', NULL)
     , ('Other', 'To Review', 'Unclassified', NULL)
    ON CONFLICT (category, subcategory) DO UPDATE
   SET expense_group = EXCLUDED.expense_group
     , is_fixed_expense = EXCLUDED.is_fixed_expense;

-- Copy account names exactly as they appear in your Google Sheets Lists tab.
-- The "Other" payment method has no account mapping by design.
INSERT INTO reference.person_payment_accounts (
       person
     , payment_method
     , account_name
)
VALUES ('John', 'Card', 'Robinhood Gold')
     , ('John', 'Card', 'Capital One QS')
     , ('John', 'Card', 'Citizens Bank')
     , ('John', 'Cash', 'John''s Cash')
     , ('John', 'Venmo', 'JohnDaang')
     , ('John', 'Zelle', 'TD Checking')
     , ('John', 'Zelle', 'TD Savings')
     , ('John', 'Bank Transfer', 'TD Checking')
     , ('John', 'Bank Transfer', 'TD Savings')
   
     , ('Julia', 'Card', 'BoA')
     , ('Julia', 'Card', 'Chase')
     , ('Julia', 'Card', 'American Airlines')
     , ('Julia', 'Cash', 'Julia''s Cash')
     , ('Julia', 'Venmo', 'Jooliah3')
     , ('Julia', 'Zelle', 'BoA Checking')
     , ('Julia', 'Zelle', 'BoA Savings')
     , ('Julia', 'Bank Transfer', 'BoA Checking')
     , ('Julia', 'Bank Transfer', 'BoA Savings')
    ON CONFLICT (person, payment_method, account_name) DO NOTHING;

-- Source mappings preserve raw entry values while standardizing known variations.
INSERT INTO reference.source_mappings (
       source_match_key
     , source_clean
)
VALUES ('amazon', 'Amazon')
     , ('samsclub', 'Sam''s Club')
     , ('samscllulb', 'Sam''s Club')
     , ('walmart', 'Walmart')
    ON CONFLICT (source_match_key) DO UPDATE
   SET source_clean = EXCLUDED.source_clean;

-- Verification query: expect 3, 2, 6, 38, 18, and 4 rows respectively.
SELECT 'transaction_types' AS reference_table, COUNT(*) AS row_count
  FROM reference.transaction_types

 UNION ALL

SELECT 'people', COUNT(*)
  FROM reference.people

 UNION ALL

SELECT 'payment_methods', COUNT(*)
  FROM reference.payment_methods

 UNION ALL

SELECT 'category_subcategories', COUNT(*)
  FROM reference.category_subcategories

 UNION ALL

SELECT 'person_payment_accounts', COUNT(*)
  FROM reference.person_payment_accounts

 UNION ALL

SELECT 'source_mappings', COUNT(*)
  FROM reference.source_mappings

 ORDER BY reference_table;