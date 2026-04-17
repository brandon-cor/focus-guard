import type { FastifyInstance } from "fastify";
import { requireAuth, getAuthUser } from "../middleware/auth";
import sql from "../db/client";

// shape of a schedule as stored in the DB / returned by the API
interface Schedule {
  id: string;
  user_id: string;
  name: string;
  is_active: boolean;
  days_of_week: number[];   // 1=Sun … 7=Sat
  start_time: string;       // "HH:MM:SS"
  end_time: string;
  timezone: string;
  pomodoro_enabled: boolean;
  work_minutes: number;
  short_break_min: number;
  long_break_min: number;
  sessions_before_long_break: number;
  created_at: string;
  updated_at: string;
}

interface BlockedApps {
  id: string;
  schedule_id: string;
  ios_activity_selection: string | null;
  blocked_domains: string[];
}

export async function scheduleRoutes(app: FastifyInstance) {
  // all routes in here require a valid JWT
  app.addHook("preHandler", requireAuth);

  // GET /schedules — list all schedules for the authenticated user
  app.get("/schedules", async (request) => {
    const { userId } = getAuthUser(request);
    const schedules = await sql<Schedule[]>`
      select * from schedules
      where user_id = ${userId}
      order by created_at asc
    `;
    return schedules;
  });

  // POST /schedules — create a new schedule
  app.post<{ Body: Omit<Schedule, "id" | "user_id" | "created_at" | "updated_at"> }>(
    "/schedules",
    async (request, reply) => {
      const { userId } = getAuthUser(request);
      const {
        name,
        is_active = true,
        days_of_week,
        start_time,
        end_time,
        timezone = "UTC",
        pomodoro_enabled = false,
        work_minutes = 25,
        short_break_min = 5,
        long_break_min = 15,
        sessions_before_long_break = 4,
      } = request.body;

      if (!name || !days_of_week || !start_time || !end_time) {
        return reply
          .status(400)
          .send({ error: "name, days_of_week, start_time, and end_time are required" });
      }

      const [schedule] = await sql<Schedule[]>`
        insert into schedules (
          user_id, name, is_active, days_of_week, start_time, end_time,
          timezone, pomodoro_enabled, work_minutes, short_break_min,
          long_break_min, sessions_before_long_break
        ) values (
          ${userId}, ${name}, ${is_active}, ${days_of_week}, ${start_time},
          ${end_time}, ${timezone}, ${pomodoro_enabled}, ${work_minutes},
          ${short_break_min}, ${long_break_min}, ${sessions_before_long_break}
        )
        returning *
      `;

      return reply.status(201).send(schedule);
    }
  );

  // PUT /schedules/:id — update a schedule (full replacement of mutable fields)
  app.put<{
    Params: { id: string };
    Body: Partial<Omit<Schedule, "id" | "user_id" | "created_at" | "updated_at">>;
  }>("/schedules/:id", async (request, reply) => {
    const { userId } = getAuthUser(request);
    const { id } = request.params;
    const updates = request.body;

    // make sure this schedule belongs to the requesting user before updating
    const [existing] = await sql<{ id: string }[]>`
      select id from schedules where id = ${id} and user_id = ${userId}
    `;
    if (!existing) {
      return reply.status(404).send({ error: "Schedule not found" });
    }

    const [updated] = await sql<Schedule[]>`
      update schedules set
        name                        = coalesce(${updates.name ?? null}, name),
        is_active                   = coalesce(${updates.is_active ?? null}, is_active),
        days_of_week                = coalesce(${updates.days_of_week ?? null}, days_of_week),
        start_time                  = coalesce(${updates.start_time ?? null}, start_time),
        end_time                    = coalesce(${updates.end_time ?? null}, end_time),
        timezone                    = coalesce(${updates.timezone ?? null}, timezone),
        pomodoro_enabled            = coalesce(${updates.pomodoro_enabled ?? null}, pomodoro_enabled),
        work_minutes                = coalesce(${updates.work_minutes ?? null}, work_minutes),
        short_break_min             = coalesce(${updates.short_break_min ?? null}, short_break_min),
        long_break_min              = coalesce(${updates.long_break_min ?? null}, long_break_min),
        sessions_before_long_break  = coalesce(${updates.sessions_before_long_break ?? null}, sessions_before_long_break)
      where id = ${id}
      returning *
    `;

    return updated;
  });

  // DELETE /schedules/:id
  app.delete<{ Params: { id: string } }>("/schedules/:id", async (request, reply) => {
    const { userId } = getAuthUser(request);
    const { id } = request.params;

    const result = await sql`
      delete from schedules where id = ${id} and user_id = ${userId}
    `;

    if (result.count === 0) {
      return reply.status(404).send({ error: "Schedule not found" });
    }

    return reply.status(204).send();
  });

  // GET /schedules/:id/apps — get blocked app config for a schedule
  app.get<{ Params: { id: string } }>("/schedules/:id/apps", async (request, reply) => {
    const { userId } = getAuthUser(request);
    const { id } = request.params;

    // verify ownership
    const [schedule] = await sql<{ id: string }[]>`
      select id from schedules where id = ${id} and user_id = ${userId}
    `;
    if (!schedule) {
      return reply.status(404).send({ error: "Schedule not found" });
    }

    const [apps] = await sql<BlockedApps[]>`
      select * from blocked_apps where schedule_id = ${id}
    `;

    // return empty config if not set yet — simplifies client-side handling
    return apps ?? { id: null, schedule_id: id, ios_activity_selection: null, blocked_domains: [] };
  });

  // PUT /schedules/:id/apps — set (upsert) blocked apps for a schedule
  app.put<{
    Params: { id: string };
    Body: { ios_activity_selection?: string; blocked_domains?: string[] };
  }>("/schedules/:id/apps", async (request, reply) => {
    const { userId } = getAuthUser(request);
    const { id } = request.params;
    const { ios_activity_selection = null, blocked_domains = [] } = request.body;

    const [schedule] = await sql<{ id: string }[]>`
      select id from schedules where id = ${id} and user_id = ${userId}
    `;
    if (!schedule) {
      return reply.status(404).send({ error: "Schedule not found" });
    }

    const [apps] = await sql<BlockedApps[]>`
      insert into blocked_apps (schedule_id, ios_activity_selection, blocked_domains)
      values (${id}, ${ios_activity_selection}, ${blocked_domains})
      on conflict (schedule_id)
      do update set
        ios_activity_selection = excluded.ios_activity_selection,
        blocked_domains        = excluded.blocked_domains
      returning *
    `;

    return apps;
  });
}
