// Run with: npm run migrate
// This reads 001_initial.sql and runs it against DATABASE_URL.
import fs from "fs";
import path from "path";
import sql from "./client";

async function migrate() {
  const migrationPath = path.join(__dirname, "migrations", "001_initial.sql");
  const migration = fs.readFileSync(migrationPath, "utf8");

  console.log("Running migration...");
  await sql.unsafe(migration);
  console.log("Migration complete.");
  await sql.end();
}

migrate().catch((err) => {
  console.error("Migration failed:", err);
  process.exit(1);
});
