const { readFileSync } = require('node:fs');
const path = require('node:path');
const { PGlite } = require('@electric-sql/pglite');

async function main() {
  const db = new PGlite();
  let passed = 0;
  try {
    const suite = readFileSync(path.join(__dirname, 'no-school.sql'), 'utf8');
    const sections = suite.split(/^\\ir (.+)$/m);
    for (const [index, section] of sections.entries()) {
      const sql = index % 2 ? readFileSync(path.resolve(__dirname, section), 'utf8') : section;
      for (const result of await db.exec(sql)) {
        for (const row of result.rows) {
          if (row.check_case) {
            console.log(row.check_case);
            passed++;
          }
        }
      }
    }
    console.log(`SQL: ${passed} passed, 0 failed`);
  } finally {
    await db.close();
  }
}
main().catch(error => {
  console.error('SQL: 1 failure, stopped at first error.', error.message);
  process.exitCode = 1;
});
