# ALOQA

**Video qo'ng'iroq, konferensiya, webinar va korporativ muloqot super-platformasi**
(Zoom-uslubidagi, ko'p tilli, mahalliy bozorga mos — Web, Android, iOS, Windows, macOS, Linux).

> To'liq spetsifikatsiya: [`TZ.md`](TZ.md) · Loyiha konteksti: [`CLAUDE.md`](CLAUDE.md) ·
> Ish jurnali: [`vazifa.txt`](vazifa.txt)

## Monorepo tuzilishi
| Papka | Nima | Stack | Holat |
|---|---|---|---|
| [`backend/`](backend/) | API + signaling | Laravel 12 (PHP 8.3), JWT, LiveKit token, OTA i18n | ✅ ishlaydi (end-to-end test) |
| [`web/`](web/) | Web ilova | React + TS + Vite + Tailwind + livekit-client | ✅ qurilgan |
| [`admin/`](admin/) | Admin panel | React + TS + Vite + Tailwind + recharts | ✅ build o'tadi |
| `lib/` + platformalar | Mobil + Desktop | Flutter 3.22.2 + livekit_client 2.2.6 | ✅ analyze 0 xato |
| [`devops/`](devops/) | Infra | Docker Compose: postgres/redis/minio/livekit/coturn/nginx | ✅ tayyor (deploy) |

## Asosiy imkoniyatlar (qurilgan poydevor)
- **Google OAuth** + email/parol + JWT (access + refresh rotation)
- **Uchrashuv** yaratish/qo'shilish + **LiveKit** video/audio token (SFU)
- **OTA ko'p tillilik** (TZ §5): adminkadan til qo'shilsa — barcha platformaga qayta deploysiz
- **Admin panel:** foydalanuvchilar, uchrashuvlar, tariflar, **lokalizatsiya (USP)**
- Mehmon (guest) link orqali qo'shilish

## Lokal ishga tushirish (dasturlash)
```bash
# Backend (MySQL/MariaDB lokalda; prod = Postgres)
cd backend && composer install
php artisan migrate:fresh --seed
php artisan serve            # http://127.0.0.1:8000/api/v1/ping

# Web
cd web && npm install && npm run dev      # :5173

# Admin
cd admin && npm install && npm run dev    # :5174

# Flutter (mobil/desktop)
flutter pub get && flutter run
```
Admin demo: foydalanuvchi `admin@aloqa.uz`. Boshlang'ich parol seed paytida `ADMIN_PASSWORD`
env orqali beriladi — birinchi kirishdayoq DARHOL o'zgartiring (parolni hujjatga yozmang).

## Deploy (server)
Domen ma'lumotlari kelgach: [`devops/README.md`](devops/README.md) — `docker compose up -d --build`.

## Logo / brending
Manba: `img/logo.png` → `assets/images/logo.png`. Barcha yuzaga qo'yilgan
(app icon, splash, web/admin favicon, login, sidebar).
