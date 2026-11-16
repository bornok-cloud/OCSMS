-- ============================================================================
-- CSMS (Cafe Sales & Management System) - Complete Local Database SQL Script
-- Compatible with SQLite / Room / Drift for Offline Access
-- ============================================================================

-- Enable foreign keys
PRAGMA foreign_keys = ON;

-- 1. Users & Authentication
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    full_name TEXT NOT NULL,
    first_name TEXT,
    last_name TEXT,
    email TEXT UNIQUE NOT NULL,
    phone TEXT,
    role TEXT NOT NULL, -- 'admin', 'employee', 'customer'
    status TEXT NOT NULL DEFAULT 'Active', -- 'Active', 'Disabled', 'Pending Verification'
    date_registered DATETIME NOT NULL,
    password TEXT NOT NULL,
    position TEXT,
    employee_id TEXT,
    profile_image TEXT, -- Base64 encoded image
    otp_code TEXT,
    otp_expiry DATETIME,
    loyal_toggle INTEGER NOT NULL DEFAULT 1 -- 1 for true, 0 for false
);

CREATE TABLE IF NOT EXISTS pending_registrations (
    id TEXT PRIMARY KEY,
    full_name TEXT NOT NULL,
    first_name TEXT,
    last_name TEXT,
    email TEXT UNIQUE NOT NULL,
    phone TEXT,
    role TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'Pending Verification',
    date_registered DATETIME NOT NULL,
    password TEXT NOT NULL
);

-- 2. Products & Menu Management
CREATE TABLE IF NOT EXISTS products (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    category TEXT NOT NULL,
    price REAL NOT NULL,
    description TEXT,
    emoji TEXT,
    image_base64 TEXT,
    stock_quantity INTEGER NOT NULL DEFAULT 0,
    is_best_seller INTEGER NOT NULL DEFAULT 0, -- 1 for true, 0 for false
    add_ons TEXT, -- JSON string representing List<MenuAddOn>
    procurement_items TEXT -- JSON string representing List<String>
);

CREATE TABLE IF NOT EXISTS addons_config (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    price REAL NOT NULL,
    allow_quantity INTEGER NOT NULL DEFAULT 0
);

-- 3. Inventory & Procurement
CREATE TABLE IF NOT EXISTS inventory (
    id TEXT PRIMARY KEY,
    product_name TEXT NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 0,
    unit TEXT NOT NULL,
    minimum_stock INTEGER NOT NULL DEFAULT 0,
    expiration DATETIME,
    item_type TEXT NOT NULL -- 'Inventory Item' or 'Kitchen Item'
);

CREATE TABLE IF NOT EXISTS procurement (
    id TEXT PRIMARY KEY,
    product_name TEXT NOT NULL,
    supplier TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    cost REAL NOT NULL,
    date DATETIME NOT NULL,
    status TEXT NOT NULL,
    item_type TEXT NOT NULL,
    expiration DATETIME
);

CREATE TABLE IF NOT EXISTS petty_cash (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    amount REAL NOT NULL,
    category TEXT NOT NULL,
    date DATETIME NOT NULL,
    cashier TEXT NOT NULL,
    receipt_base64 TEXT
);

-- 4. Orders & Transactions
CREATE TABLE IF NOT EXISTS kiosk_orders (
    id TEXT PRIMARY KEY,
    items TEXT NOT NULL, -- JSON string representing List<CartItem>
    source TEXT NOT NULL, -- 'Kiosk', 'POS'
    status TEXT NOT NULL DEFAULT 'Pending', -- 'Pending', 'Preparing', 'Ready', 'Declined', 'Cancelled', 'Expired'
    created_at DATETIME NOT NULL,
    customer_name TEXT,
    discount REAL DEFAULT 0.0,
    customer_id TEXT,
    payment_method TEXT NOT NULL, -- 'Pay at Counter', 'GCash', 'Multi Payment'
    order_number TEXT,
    proof_of_payment_base64 TEXT,
    decline_reason TEXT,
    expires_at DATETIME,
    order_type TEXT NOT NULL, -- 'Dine In', 'Take Out', 'Pickup'
    verified_total REAL,
    extracted_amount REAL,
    extracted_reference_id TEXT,
    receipt TEXT -- JSON string representing ReceiptRecord
);

CREATE TABLE IF NOT EXISTS transactions (
    id TEXT PRIMARY KEY,
    items TEXT NOT NULL, -- JSON string representing List<CartItem>
    total REAL NOT NULL,
    timestamp DATETIME NOT NULL,
    cashier TEXT NOT NULL,
    customer_id TEXT,
    customer_name TEXT,
    payment_method TEXT NOT NULL,
    order_type TEXT NOT NULL,
    linked_receipt TEXT -- JSON string representing ReceiptRecord
);

-- 5. Employee & Payroll Management
CREATE TABLE IF NOT EXISTS employees (
    id TEXT PRIMARY KEY,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL,
    phone TEXT,
    position TEXT,
    employee_id TEXT,
    status TEXT NOT NULL,
    date_registered DATETIME NOT NULL
);

CREATE TABLE IF NOT EXISTS payroll_history (
    id TEXT PRIMARY KEY,
    employee_id TEXT NOT NULL,
    employee_name TEXT NOT NULL,
    period_start DATETIME NOT NULL,
    period_end DATETIME NOT NULL,
    base_pay REAL NOT NULL,
    overtime REAL NOT NULL,
    deductions REAL NOT NULL,
    net_pay REAL NOT NULL,
    status TEXT NOT NULL, -- 'Paid', 'Pending'
    date DATETIME NOT NULL
);

-- 6. Attendance, Feedback & Messaging
CREATE TABLE IF NOT EXISTS attendance (
    id TEXT PRIMARY KEY,
    employee_id TEXT NOT NULL,
    employee_name TEXT NOT NULL,
    date TEXT NOT NULL,
    time_in DATETIME,
    time_out DATETIME,
    status TEXT NOT NULL -- 'Present', 'Late'
);

CREATE TABLE IF NOT EXISTS feedbacks (
    id TEXT PRIMARY KEY,
    customer_name TEXT NOT NULL,
    customer_id TEXT,
    rating INTEGER NOT NULL,
    comment TEXT,
    category TEXT NOT NULL,
    date DATETIME NOT NULL,
    status TEXT NOT NULL, -- 'New', 'Reviewed'
    reply TEXT,
    order_id TEXT
);

CREATE TABLE IF NOT EXISTS groups (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    is_group INTEGER NOT NULL,
    members TEXT -- JSON string representing List<String>
);

CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    conversation_id TEXT NOT NULL,
    sender TEXT NOT NULL,
    text TEXT NOT NULL,
    timestamp DATETIME NOT NULL,
    is_read INTEGER NOT NULL DEFAULT 0,
    deleted_for TEXT -- JSON string representing List<String>
);

-- 7. Promotions, Notifications & Archive
CREATE TABLE IF NOT EXISTS promotions (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    code TEXT NOT NULL,
    discount REAL NOT NULL,
    active INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS notifications (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    timestamp DATETIME NOT NULL,
    is_read INTEGER NOT NULL DEFAULT 0,
    recipient_role TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS archive (
    id TEXT PRIMARY KEY,
    record_id TEXT NOT NULL,
    category TEXT NOT NULL,
    name TEXT NOT NULL,
    details TEXT,
    date_archived DATETIME NOT NULL
);
