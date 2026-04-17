import postgres from "postgres";

// Neon requires SSL in production; the DATABASE_URL from Neon includes
// the ?sslmode=require param automatically when copied from the dashboard.
// We pass ssl: "require" explicitly as a fallback.
const sql = postgres(process.env.DATABASE_URL!, {
  ssl: process.env.NODE_ENV === "production" ? "require" : false,
  max: 10,
});

export default sql;
