import Fastify from "fastify";
import cors from "@fastify/cors";
import jwt from "@fastify/jwt";
import { authRoutes } from "./routes/auth";
import { scheduleRoutes } from "./routes/schedules";

const app = Fastify({
  logger: {
    level: process.env.LOG_LEVEL ?? "info",
  },
});

// allow requests from any origin — in production you can restrict this to
// your app's domain if you add a web client later
app.register(cors, { origin: true });

// JWT plugin — signs and verifies our own tokens (not Apple's)
// JWT_SECRET must be a long random string set in Railway env vars
app.register(jwt, {
  secret: process.env.JWT_SECRET!,
});

// routes
app.register(authRoutes);
app.register(scheduleRoutes);

// simple health check for Railway deployment
app.get("/health", async () => ({ status: "ok" }));

const port = parseInt(process.env.PORT ?? "3000", 10);

app.listen({ port, host: "0.0.0.0" }, (err) => {
  if (err) {
    app.log.error(err);
    process.exit(1);
  }
});
