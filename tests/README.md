# No School Day tests

Run from the repository root with Node.js and npm.

```sh
npm ci --prefix tests
node --test tests/no-school.test.cjs
node tests/run-sql.cjs
```

The install downloads the pinned PGlite dependency. The tests run locally without credentials or network calls. Client tests exercise code from the inline script with mocked data. SQL tests create a fresh in-memory PostgreSQL database with fixture tables and run the migration and rollback.
