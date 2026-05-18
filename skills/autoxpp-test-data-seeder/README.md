# AutoXPP Test Data Seeder

Background agent that pre-seeds test data in the D365 F&O environment via OData while the coding agent is still analyzing standard code and writing artifacts.

## Why This Skill Matters

Test data setup through the D365 UI takes 5-15 minutes per test case -- navigating forms, filling fields, posting documents, waiting for async processes. When done sequentially after coding finishes, this setup time sits directly on the critical path: the tester agent waits idle while data is created.

The test data seeder runs in parallel with the coding phase, using otherwise-idle environment time. While the coding agent reads standard code, designs extensions, and writes X++ artifacts, the seeder creates the records those test cases will need -- customers, vendors, sales orders, purchase orders, inventory journals, batch orders. By the time the build finishes and the tester starts, the test data is already in place.

This parallel execution saves 15-60 minutes per lifecycle depending on the number of test cases. The environment is idle during the coding phase anyway -- the seeder puts that time to use.

## How It Works

1. Reads `test_cases.md` to identify required test data (record types, field values, relationships)
2. Creates records via OData -- no browser interaction, no SQL writes
3. Handles entity dependencies in correct order (e.g., create customer before sales order)
4. Writes `system/test_data_manifest.md` listing all seeded records and their creation status

## When It Runs

Automatically by the lifecycle orchestrator after `test_cases.md` is ready. Runs in the background alongside `autoxpp-dev-v2`. Not invoked directly.

