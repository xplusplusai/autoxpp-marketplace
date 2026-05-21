# D365 F&O Form URL Reference

Direct navigation: `{baseUrl}/?cmp={company}&mi={menuItem}`

## URL Conventions

- `{baseUrl}` = environment-specific (e.g., `https://*.operations.dynamics.com`)
- `{company}` = legal entity / company code
- `{menuItem}` = the `mi=` value below
- Some forms require context (active record buffer) and cannot open via direct URL

## General Ledger — Journals

| Form | Menu Item | Journal Type | Notes |
|:-----|:----------|:-------------|:------|
| General journals list | `LedgerJournalTable` | Daily | Click into journal for trans form |
| Fixed asset journals list | `LedgerJournalTable5` | Assets | |
| AP journals list | `LedgerJournalTable6` | VendPaym / VendInvoice | Journal type determines trans form |
| AR journals list | `LedgerJournalTable7` | CustPaym | |

## Accounts Payable

| Form | Menu Item | Notes |
|:-----|:----------|:------|
| Vendor invoice entry | `VendEditInvoice` | Needs invoice data to verify |
| Vendor invoices list | `VendOpenInvoicesListPage` | |

## Accounts Receivable

| Form | Menu Item | Notes |
|:-----|:----------|:------|
| Customer open invoices | `CustOpenInvoicesListPage` | |
| Free text invoices | `FreeTextInvoiceListPage` | |
| Collections | `CustCollections` | |

## Sales

| Form | Menu Item | Notes |
|:-----|:----------|:------|
| Sales order list | `SalesTableListPage` | Filter by customer, status |
| Sales order details | `SalesTable` | Opens create/edit form |

## Fixed Assets

| Form | Menu Item | Direct URL? | Notes |
|:-----|:----------|:------------|:------|
| Fixed assets list | `AssetTable` | Yes | |
| Asset books | `AssetBook` | No — needs active buffer | Navigate from asset list > Books button |
| Depreciation profiles | `AssetProfile` | No — needs context | Navigate from asset book record |

## Cash & Bank Management

| Form | Menu Item | Direct URL? | Notes |
|:-----|:----------|:------------|:------|
| Bank account statements | `BankAccountStatement` | Yes | |
| Bank reconciliation | `BankReconciliation` | No — needs bank context | Navigate from bank account |
| Bank accounts | `BankAccountTable` | Yes | |

## Warehouse Management

| Form | Menu Item | Notes |
|:-----|:----------|:------|
| All work | `WHSWorkTableListPage` | Filter by Work status, Work order type |
| All loads | `WHSLoadTable` | |
| All waves | `WHSWaveTable` | |
| All shipments | `WHSShipmentTable` | |

## Inventory Management

| Form | Menu Item | Notes |
|:-----|:----------|:------|
| On-hand inventory | `InventOnhandItem` | Filter by item, site, warehouse |
| Movement journal | `InventJournalTableMovement` | |
| Batches | `InventBatch` | |
| Journal names | `InventJournalName` | Journal name setup |
| Counting journal | `InventJournalCount` | |

## Product Information

| Form | Menu Item | Notes |
|:-----|:----------|:------|
| Released products | `EcoResProductPerCompanyListPage` | Quick filter defaults to "Product name" column — use Ctrl+F3 Filter Pane to filter by "Item number" instead |

## Project Management

| Form | Menu Item | Notes |
|:-----|:----------|:------|
| All Projects | `ProjProjectsListPage` | Filter by Project ID |
| Item requirements | N/A | No direct mi= URL. Navigate from project: Plan tab → Item requirements button |

## Navigation Tips

- **Forms needing buffer**: Detail forms (AssetBook, BankReconciliation) require active record context. Navigate to parent list first, select record, use action pane button.
- **Journal trans forms**: Open inside journal header form. Navigate to journal list via `mi=`, click into specific journal.
- **Quick filter**: After landing on list page, use quick filter bar to find records.
- **Company switch**: Change `cmp=` parameter to switch legal entities.
