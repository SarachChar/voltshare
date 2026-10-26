# Charging Session – Setup (Supabase)

ขั้นตอนตั้งค่าครั้งแรกสำหรับระบบ Charging Session (OCPP mock) บน Supabase project ใหม่หรือ project ที่ยังไม่เคยตั้ง

## ภาพรวม

```
Flutter ──▶ ocpp-remote-start / ocpp-remote-stop / pay-charging-session ──▶ SQL functions ──▶ ตาราง
pg_cron (30s) ─▶ trigger_mock_charger() ─▶ mock-charger ─▶ ocpp-meter-values ─▶ session_streams
Flutter ◀── Realtime (charging_sessions, session_streams)
```

| ส่วน | ที่อยู่ใน repo |
|---|---|
| ตาราง | `supabase/sql/tables/charging_sessions.sql`, `session_streams.sql`, `session_payments.sql` |
| RLS + Realtime | `supabase/policies/charging_policies.sql` |
| SQL functions | `supabase/sql/functions/ocpp_*.sql`, `mock_charger_active_sessions.sql`, `charging_payment_*.sql`, `trigger_mock_charger.sql` |
| Cron | `supabase/sql/cron/mock_charger_tick.sql` |
| Edge functions | `supabase/functions/` (`_shared/` = โค้ดร่วม) |
| Deploy config | `supabase/config.toml` |

## สิ่งที่ต้องมี

- สิทธิ์เข้า Supabase Dashboard ของ project
- Supabase CLI: `brew install supabase/tap/supabase`
- service_role key แบบ **legacy** (JWT ขึ้นต้น `eyJ...`)
  - Project Settings → API Keys → tab **Legacy API keys** → `service_role` → Reveal

> service_role key ข้าม RLS ได้ทั้งหมด ห้ามใส่ในแอป / ห้าม commit / ห้ามวางในไฟล์ SQL ที่เซฟ

## วิธีรันไฟล์ SQL

Dashboard → **SQL Editor** → **+ New query** → วางเนื้อหาทั้งไฟล์ → **Run** (Cmd+Enter) → ต้องได้ `Success`
ถ้าเตือน "destructive operation" (มี `revoke`) กด confirm ได้

---

## ขั้นที่ 1 – เปิด extension

Dashboard → **Database → Extensions** → เปิด `pg_cron` และ `pg_net` (`supabase_vault` ปกติเปิดอยู่แล้ว)

## ขั้นที่ 2 – ตาราง (ตามลำดับ เพราะมี FK)

1. `sql/tables/charging_sessions.sql`
2. `sql/tables/session_streams.sql`
3. `sql/tables/session_payments.sql`

ต้องมี `set_updated_at()` อยู่แล้ว (`sql/functions/set_updated_at.sql`)

## ขั้นที่ 3 – RLS + Realtime

4. `policies/charging_policies.sql`

เช็ค:
```sql
select tablename from pg_publication_tables where pubname = 'supabase_realtime';
-- ต้องมี charging_sessions, session_streams
```

## ขั้นที่ 4 – SQL functions (ลำดับไหนก็ได้)

5. `sql/functions/ocpp_start_session.sql`
6. `sql/functions/ocpp_record_meter_value.sql`
7. `sql/functions/ocpp_stop_session.sql`
8. `sql/functions/mock_charger_active_sessions.sql`
9. `sql/functions/charging_payment_prepare.sql`
10. `sql/functions/charging_payment_finish.sql`

เช็ค (ต้องได้ 6 แถว):
```sql
select proname from pg_proc
where proname in ('ocpp_start_session','ocpp_record_meter_value','ocpp_stop_session',
                  'mock_charger_active_sessions','charging_payment_prepare','charging_payment_finish');
```

## ขั้นที่ 5 – Vault secrets

รันใน SQL Editor (อย่าเซฟ query นี้):
```sql
select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
select vault.create_secret('<legacy service_role key>', 'service_role_key');
```

เช็ค (ไม่แสดงค่าจริง):
```sql
select left(decrypted_secret, 8) as prefix,
       length(decrypted_secret) as len,
       decrypted_secret <> trim(decrypted_secret) as has_whitespace
from vault.decrypted_secrets where name = 'service_role_key';
-- ต้องได้ prefix = eyJhbGci, len ≈ 200–230, has_whitespace = false
```

แก้ค่าทีหลัง:
```sql
select vault.update_secret(
  (select id from vault.secrets where name = 'service_role_key'),
  '<legacy service_role key>');
```

## ขั้นที่ 6 – Deploy edge functions

```bash
cd <repo>/voltshare_app
supabase login
supabase link --project-ref <project-ref>     # ถ้าถาม database password กด Enter ข้ามได้

supabase functions deploy ocpp-remote-start    --use-api
supabase functions deploy ocpp-remote-stop     --use-api
supabase functions deploy pay-charging-session --use-api
supabase functions deploy ocpp-meter-values    --use-api
supabase functions deploy mock-charger         --use-api
```

- **ห้ามใช้ `--no-verify-jwt`** – ทุก function ต้องเปิด verify JWT (กำหนดไว้ใน `supabase/config.toml`) ดูเหตุผลที่หัวข้อ [Auth ของ mock-charger](#auth-ของ-mock-charger--ocpp-meter-values)
- `--use-api` = bundle บน server ไม่ต้องมี Docker
- `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` ใน edge runtime มีให้อัตโนมัติ ไม่ต้องตั้ง secret เพิ่ม

เช็ค:
```bash
supabase functions list
```
ยิงแบบไม่มี header ทุกตัวต้องได้ **401** `Missing authorization header`:
```bash
curl -s -X POST "https://<project-ref>.supabase.co/functions/v1/mock-charger" -d '{}'
```

## ขั้นที่ 7 – Cron (ทำหลัง deploy แล้ว)

11. `sql/functions/trigger_mock_charger.sql`
12. `sql/cron/mock_charger_tick.sql`
13. `sql/cron/cleanup_cron_run_details.sql` – ล้าง log ของ cron ทุกวัน 23:59 เวลาไทย

## ขั้นที่ 8 – Reviews

14. `sql/tables/reviews.sql` – ตาราง + RLS (รีวิวได้ครั้งเดียวต่อ reservation ที่ `completed`, แก้/ลบไม่ได้)

ต้องรันก่อนใช้แอปเวอร์ชันที่มีรีวิว เพราะหน้า Bookings ดึง `reviews(*)` มาด้วย ถ้ายังไม่มีตารางหน้า Bookings จะโหลดไม่ขึ้น

15. `sql/functions/charger_review_summary.sql` – คะแนนเฉลี่ย + จำนวนรีวิวของ charger
16. `sql/functions/charger_reviews.sql` – รายการรีวิวของ charger (ชื่อคนรีวิวถูก censor ฝั่ง server เช่น `P***`)

## ขั้นที่ 9 – Host revenue

17. `sql/functions/host_revenue.sql` – รายได้ของ host (tab Revenue, header และการ์ดใน My Chargers) นับเฉพาะบิล `paid` (เดือนนับจาก `charging_sessions.ended_at` เวลาไทย) ส่วนค่าจองแสดงแยกในกล่อง Reservation Fee: `booking_fee` ที่ `paid` รวม booking ที่ถูกยกเลิก host ได้เต็มจำนวน เดือนนับจาก `reservations.start_time` เวลาไทย

---

ฟังก์ชันรีวิวทั้งสองเป็น `security definer` เพราะต้อง join `reviews → reservations → profiles` ซึ่ง user อ่านของคนอื่นไม่ได้ และคืนเฉพาะข้อมูลที่แสดงได้ (ไม่คืนชื่อจริง / user id)

เช็ค:
```sql
select jobname, schedule, active from cron.job;
-- mock-charger-tick | 30 seconds | true
```

---

## ทดสอบ end-to-end

1. ในแอป จองช่วงที่เริ่มภายใน 30 นาทีจากตอนนี้ (หรือเริ่มไปแล้วไม่เกิน 15 นาที)
2. Bookings → Start → Plug In → **Start Charging** → `charging_sessions` มีแถว `charging`
3. รอ ~30 วินาที → `session_streams` มีแถวเพิ่ม, ตัวเลขในแอปขยับ
4. **Stop Charging** → หน้า Summary → `session_payments` แถว `unpaid`
5. **Pay** → Payment Complete → `session_payments.status = paid`

สั่ง tick ทันที (ไม่รอ cron):
```sql
select public.trigger_mock_charger();
```
หรือข้ามกฎ 20 วินาที:
```bash
curl -X POST "https://<project-ref>.supabase.co/functions/v1/mock-charger" \
  -H "Authorization: Bearer <legacy service_role key>" \
  -H "Content-Type: application/json" -d '{"force":true}'
```

## Troubleshooting

```sql
-- cron รันไหม
select status, return_message, start_time from cron.job_run_details
order by start_time desc limit 5;

-- ผลที่ pg_net ได้จาก mock-charger
select status_code, content, created from net._http_response
order by created desc limit 5;
```

| อาการ | สาเหตุ / วิธีแก้ |
|---|---|
| ไม่มีแถวใหม่ใน `net._http_response` | ไม่มี session `charging` (ปกติ – function ไม่ยิง) หรือ cron ไม่ได้ตั้ง |
| 401 `Invalid JWT` | key ใน Vault ไม่ใช่ legacy service_role JWT / copy ไม่ครบ |
| 403 `Scheduler only.` | JWT ถูกต้องแต่ role ไม่ใช่ `service_role` (เช่นใส่ anon key) |
| 404 | ยังไม่ deploy `mock-charger` หรือ `project_url` ผิด |
| 200 แต่แอปไม่ขยับ | ตาราง ยังไม่อยู่ใน publication `supabase_realtime` (ขั้นที่ 3) |

Log ของ function: Dashboard → Edge Functions → เลือก function → **Logs**

หยุด / เปิด cron ชั่วคราว (ค่า job ยังอยู่):
```sql
select cron.alter_job((select jobid from cron.job where jobname = 'mock-charger-tick'), active := false);  -- ปิด
select cron.alter_job((select jobid from cron.job where jobname = 'mock-charger-tick'), active := true);   -- เปิด
```
หรือ Dashboard → **Integrations → Cron** → toggle

ลบ job ทิ้ง: `select cron.unschedule('mock-charger-tick');` (ใช้ใหม่ = รัน `sql/cron/mock_charger_tick.sql`)

ถ้าปิดตอนมี session ชาร์จค้าง: ค่าในแอปจะไม่ขยับ และไม่ auto-stop แต่ user ยังกด Stop ได้และบิลถูกต้อง

### ล้าง log ของ cron

pg_cron เก็บ log ทุกครั้งที่ job รันใน `cron.job_run_details` (mock-charger-tick ≈ 2,880 แถว/วัน) และไม่ลบเอง
รัน `sql/cron/cleanup_cron_run_details.sql` ครั้งเดียว → ทุกวัน 23:59 เวลาไทย (`'59 16 * * *'` UTC) ลบ log ที่เก่ากว่า 1 วัน

ล้างทันที:
```sql
delete from cron.job_run_details where end_time < now() - interval '1 hour';
```
`net._http_response` ไม่ต้องล้าง – pg_net ลบแถวเก่ากว่า 6 ชั่วโมงเอง

---

## Auth ของ mock-charger / ocpp-meter-values

สอง function นี้เป็นฝั่ง "charger" ห้ามแอปเรียกได้ (ไม่งั้นแอปปลอมค่ามิเตอร์ได้) จึงรับเฉพาะ service role

### ปัญหาที่เจอตอนแรก

เวอร์ชันแรก deploy ด้วย `--no-verify-jwt` แล้วในโค้ดเทียบ string ตรงๆ:

```ts
token === Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
```

ผลคือ cron ยิงถึง `mock-charger` แต่ได้ **403 `Scheduler only.`** ทั้งที่ key ใน Vault เป็น legacy service_role JWT ที่ถูกต้อง แปลว่าค่า `SUPABASE_SERVICE_ROLE_KEY` ที่ edge runtime ฉีดให้ **ไม่ใช่ string เดียวกับ** legacy key ใน Dashboard (Supabase อาจใส่ key คนละรูปแบบ/คนละตัวใน runtime) วิธีเทียบ string จึงพึ่งพาไม่ได้

### สิ่งที่เปลี่ยน

1. **เปิด verify JWT ที่ gateway** สำหรับทุก function (`supabase/config.toml` → `verify_jwt = true`, เลิกใช้ `--no-verify-jwt`)
   Gateway ของ Supabase ตรวจ signature ของ JWT ก่อนเข้าโค้ด – token ที่ไม่ได้ออกโดย project นี้ถูกปฏิเสธ 401
2. **ในโค้ดเช็ค role ใน JWT** แทนการเทียบ string (`_shared/supabase.ts` → `isServiceRequest`)
   ```ts
   if (SERVICE_ROLE_KEY && token === SERVICE_ROLE_KEY) return true;  // ยังรับถ้าตรงพอดี
   return jwtPayload(token)?.role === "service_role";
   ```
   decode payload อย่างเดียว (ไม่ verify) ได้อย่างปลอดภัย **เพราะ** gateway verify signature ไปแล้วในข้อ 1 – ถ้าปิด verify JWT ข้อนี้จะไม่ปลอดภัยทันที
3. **mock-charger ส่ง header ต่อ** – ตอนเรียก `ocpp-meter-values` ใช้ `Authorization` เดิมที่ cron ส่งมา (`authorizationHeader(req)`) แทนการอ่าน `SUPABASE_SERVICE_ROLE_KEY` จาก env ซึ่งอาจไม่ผ่าน gateway
4. คอมเมนต์ใน `trigger_mock_charger.sql` ระบุให้ใช้ **legacy** service_role key

### ผลทดสอบหลังแก้

| request | ผล |
|---|---|
| ไม่มี header | 401 `Missing authorization header` (gateway) |
| JWT ปลอมที่ใส่ `"role":"service_role"` เอง | 401 `Invalid JWT` (gateway – signature ไม่ถูก) |
| anon / user JWT | 403 `Scheduler only.` / `Chargers only.` (โค้ด – role ไม่ใช่ service_role) |
| legacy service_role JWT จาก Vault (cron) | 200 |

### ข้อควรระวัง

- ต้อง deploy `mock-charger` / `ocpp-meter-values` **โดยไม่มี** `--no-verify-jwt` เสมอ
- ถ้าวันหนึ่ง project ปิด legacy API keys ต้องเปลี่ยนวิธี auth ของ cron (เช่นใช้ shared secret ผ่าน `supabase secrets set` + Vault) เพราะ gateway จะไม่รับ legacy JWT แล้ว
