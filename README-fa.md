<div dir="rtl">

# MoaV

**[English](README.md)** | فارسی

استک عبور از سانسور چند پروتکلی بهینه‌سازی شده برای محیط‌های شبکه‌ای خصمانه.

## ویژگی‌ها

- **پروتکل‌های متعدد** - Reality (VLESS)، Trojan، Hysteria2، TrustTunnel، WireGuard (مستقیم و wstunnel)، تونل DNS
- **اولویت پنهان‌کاری** - تمام ترافیک شبیه HTTPS معمولی، WebSocket، یا DNS به نظر می‌رسد
- **اعتبارنامه‌های جداگانه برای هر کاربر** - ایجاد، لغو و مدیریت کاربران به صورت مستقل
- **نصب آسان** - مبتنی بر Docker Compose، راه‌اندازی با یک دستور
- **سازگار با موبایل** - کدهای QR و لینک‌ها برای وارد کردن آسان در کلاینت
- **وب‌سایت پوششی** - ارائه محتوای بی‌خطر به بازدیدکنندگان احراز هویت نشده
- **قابل نصب در خانه** - اجرا روی Raspberry Pi یا هر سیستم لینوکس ARM64/x64 به عنوان VPN شخصی
- **[Psiphon Conduit](https://github.com/Psiphon-Inc/conduit)** - اهدای پهنای باند اختیاری برای کمک به دیگران در عبور از سانسور
- **[Tor Snowflake](https://snowflake.torproject.org/)** - اهدای پهنای باند اختیاری برای کمک به کاربران Tor در عبور از سانسور
- **مانیتورینگ** - Grafana + Prometheus برای نظارت بر عملکرد سرور (اختیاری)

## شروع سریع

**نصب با یک دستور** (پیشنهادی):

<div dir="ltr">

```bash
curl -fsSL moav.sh/install.sh | bash
```

</div>

این کار:
- پیش‌نیازها را نصب می‌کند (Docker، git، qrencode) در صورت نیاز
- MoaV را در `/opt/moav` کلون می‌کند
- دامنه، ایمیل و رمز عبور ادمین را درخواست می‌کند
- پیشنهاد نصب سراسری دستور `moav` را می‌دهد
- نصب تعاملی را راه‌اندازی می‌کند

**نصب دستی** (جایگزین):

<div dir="ltr">

```bash
git clone https://github.com/shayanb/MoaV.git
cd MoaV
cp .env.example .env
nano .env  # تنظیم DOMAIN، ACME_EMAIL، ADMIN_PASSWORD
./moav.sh
```

</div>

<img src="docs/assets/moav.sh.png" alt="منوی تعاملی MoaV" width="400">

**پس از نصب، از هر مکانی از `moav` استفاده کنید:**

<div dir="ltr">

```bash
moav                      # منوی تعاملی
moav help                 # نمایش تمام دستورات
moav start                # شروع تمام سرویس‌ها
moav stop                 # توقف تمام سرویس‌ها
moav logs                 # مشاهده لاگ‌ها
moav update               # به‌روزرسانی MoaV (git pull)
moav user add joe         # افزودن کاربر
```

</div>

**دستورات docker به صورت دستی** (جایگزین):

<div dir="ltr">

```bash
docker compose --profile all build                 # ساخت تمام ایمیج‌ها
docker compose --profile setup run --rm bootstrap  # مقداردهی اولیه
docker compose --profile all up -d                 # شروع تمام سرویس‌ها
```

</div>

برای دستورالعمل‌های کامل نصب به [docs/SETUP.md](docs/SETUP.md) مراجعه کنید.

### راه‌اندازی سرور خود

[![Deploy on Hetzner](https://img.shields.io/badge/نصب%20روی-Hetzner-d50c2d?style=for-the-badge&logo=hetzner&logoColor=white)](docs/DEPLOY.md#hetzner)
[![Deploy on Linode](https://img.shields.io/badge/نصب%20روی-Linode-00a95c?style=for-the-badge&logo=linode&logoColor=white)](docs/DEPLOY.md#linode)
[![Deploy on Vultr](https://img.shields.io/badge/نصب%20روی-Vultr-007bfc?style=for-the-badge&logo=vultr&logoColor=white)](docs/DEPLOY.md#vultr)
[![Deploy on DigitalOcean](https://img.shields.io/badge/نصب%20روی-DigitalOcean-0080ff?style=for-the-badge&logo=digitalocean&logoColor=white)](docs/DEPLOY.md#digitalocean)


## معماری

<div dir="ltr">

```

       ┌───────────────┐           ┌───────────────┐           ┌───────────────┐
       │  Your Clients │           │ Psiphon Users │           │   Tor Users   │
       │   (private)   │           │  (worldwide)  │           │  (worldwide)  │
       └───────┬───────┘           └───────┬───────┘           └───────┬───────┘
               │                           │                           │
┌──────────────╪───────────────────────────╪───────────────────────────╪───────────┐
│              |                 Restricted Internet                   |           │
└──────────────╪───────────────────────────╪───────────────────────────╪───────────┘
               │                           │                           │
╔══════════════╪═══════════════════════════╪═══════════════════════════╪═══════════╗
║              │                           │                           │           ║
║     ┌────────┼──────────┐                │                           │           ║
║     │        │          │                │                           │           ║
║     ▼        ▼          ▼                ▼                           ▼           ║
║ ┌─────────┐┌─────────┐┌─────────┐   ┌───────────────┐          ┌───────────────┐ ║
║ │ Reality ││WireGuard││  DNS    │   │               │          │               │ ║
║ │ 443/tcp ││51820/udp││ 53/udp  │   │    Conduit    │          │   Snowflake   │ ║
║ │ Trojan  ││wstunnel │├─────────┤   │   (donate)    │          │   (donate)    │ ║
║ │8443/tcp ││8080/tcp ││  dnstt  │   │   bandwidth   │          │   bandwidth   │ ║
║ │Hysteria2│└────┬────┘└────┬────┘   └───────┬───────┘          └───────┬───────┘ ║
║ │ 443/udp │     │          │                │                          │         ║
║ ├─────────┤     │          │                │                          │         ║
║ │ sing-box│     │          │                │                          │      M  ║
║ └────┬────┘     │          │                │                          │      O  ║
║      │          │          │                │                          │      A  ║
║      │          │          │                │                          │      V  ║
╚══════╪══════════╪══════════╪════════════════╪══════════════════════════╪═════════╝
       │          │          │                │                          │
       ▼          ▼          ▼                ▼                          ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│                                Open Internet                                     │
└──────────────────────────────────────────────────────────────────────────────────┘
```

</div>

## پروتکل‌ها

| پروتکل | پورت | پنهان‌کاری | سرعت | کاربرد |
|--------|------|---------|-------|--------|
| Reality (VLESS) | 443/tcp | ★★★★★ | ★★★★☆ | اصلی، قابل اعتمادترین |
| Hysteria2 | 443/udp | ★★★★☆ | ★★★★★ | سریع، کار می‌کند وقتی TCP محدود است |
| Trojan | 8443/tcp | ★★★★☆ | ★★★★☆ | پشتیبان، از دامنه شما استفاده می‌کند |
| CDN (VLESS+WS) | 443 از Cloudflare | ★★★★★ | ★★★☆☆ | وقتی IP سرور مسدود است |
| TrustTunnel | 4443/tcp+udp | ★★★★★ | ★★★★☆ | HTTP/2 و QUIC، شبیه HTTPS |
| WireGuard (مستقیم) | 51820/udp | ★★★☆☆ | ★★★★★ | VPN کامل، نصب ساده |
| WireGuard (wstunnel) | 8080/tcp | ★★★★☆ | ★★★★☆ | VPN وقتی UDP مسدود است |
| تونل DNS | 53/udp | ★★★☆☆ | ★☆☆☆☆ | آخرین راه‌حل، سخت برای مسدود کردن |
| Psiphon | - | ★★★★☆ | ★★★☆☆ | مستقل، نیازی به سرور ندارد |
| Tor (Snowflake) | - | ★★★★☆ | ★★☆☆☆ | مستقل، از شبکه Tor استفاده می‌کند |

## مدیریت کاربران

<div dir="ltr">

```bash
# استفاده از moav (توصیه شده)
moav user list            # لیست تمام کاربران (یا: moav users)
moav user add joe         # افزودن کاربر به تمام سرویس‌ها
moav user revoke joe      # لغو دسترسی کاربر از تمام سرویس‌ها
moav user package joe     # ایجاد فایل zip قابل توزیع
```

</div>

### دانلود بسته‌ها

**از داشبورد ادمین (آسان‌ترین روش):**
1. به `https://آی‌پی-سرور:9443` بروید
2. با رمز ادمین وارد شوید
3. از بخش "User Bundles" بسته‌ها را دانلود کنید

**از طریق SCP:**

<div dir="ltr">

```bash
# دانلود فایل zip
scp root@YOUR_SERVER_IP:/opt/moav/outputs/bundles/joe.zip ./

# دانلود پوشه کاربر
scp -r root@YOUR_SERVER_IP:/opt/moav/outputs/bundles/joe ./joe-bundle/
```

</div>

**اسکریپت‌های دستی** (برای استفاده پیشرفته):

<div dir="ltr">

```bash
# افزودن فقط به سرویس‌های خاص
./scripts/singbox-user-add.sh joe     # Reality، Trojan، Hysteria2
./scripts/wg-user-add.sh joe          # فقط WireGuard

# لغو از سرویس‌های خاص
./scripts/singbox-user-revoke.sh joe
./scripts/wg-user-revoke.sh joe
```

</div>

بسته‌های کاربری در `outputs/bundles/<username>/` تولید می‌شوند و شامل:
- فایل‌های پیکربندی برای هر پروتکل
- کدهای QR برای وارد کردن در موبایل
- README با دستورالعمل‌های اتصال

## مدیریت سرویس‌ها

<div dir="ltr">

```bash
moav status               # نمایش وضعیت تمام سرویس‌ها
moav start                # شروع تمام سرویس‌ها
moav start proxy admin    # شروع پروفایل‌های خاص
moav stop                 # توقف تمام سرویس‌ها
moav stop conduit         # توقف سرویس خاص
moav restart sing-box     # راه‌اندازی مجدد سرویس خاص
moav logs                 # مشاهده تمام لاگ‌ها (حالت دنبال کردن)
moav logs conduit         # مشاهده لاگ‌های سرویس خاص
moav build                # ساخت/بازسازی تمام کانتینرها
```

</div>

**پروفایل‌ها:** `proxy`، `wireguard`، `dnstt`، `trusttunnel`، `admin`، `conduit`، `snowflake`، `monitoring`، `all`

**نام مستعار سرویس‌ها:** `conduit`←psiphon-conduit، `singbox`←sing-box، `wg`←wireguard، `dns`←dnstt

## مهاجرت سرور

خروجی گرفتن و انتقال MoaV به سرور جدید:

<div dir="ltr">

```bash
# خروجی کامل (کلیدها، کاربران، تنظیمات)
moav export                        # ایجاد moav-backup-TIMESTAMP.tar.gz

# در سرور جدید: وارد کردن و به‌روزرسانی IP
moav import moav-backup-*.tar.gz   # بازیابی تنظیمات
moav migrate-ip 1.2.3.4            # به‌روزرسانی همه تنظیمات با IP جدید
moav start                         # شروع سرویس‌ها
```

</div>

برای جزئیات بیشتر به [docs/SETUP.md](docs/SETUP.md#server-migration) مراجعه کنید.

## تست و کلاینت

MoaV شامل یک کانتینر کلاینت داخلی برای تست اتصال و اتصال از طریق سرور شماست.

### حالت تست

تأیید اینکه تمام پروتکل‌ها برای یک کاربر کار می‌کنند:

<div dir="ltr">

```bash
moav test user1           # تست تمام پروتکل‌ها برای user1
moav test user1 --json    # خروجی نتایج به صورت JSON
```

</div>

تست Reality، Trojan، Hysteria2، WireGuard، و dnstt. گزارش pass/fail/skip برای هر پروتکل.

### حالت کلاینت

استفاده از MoaV به عنوان کلاینت برای اتصال از طریق سرور (اجرای پراکسی SOCKS5/HTTP به صورت محلی):

<div dir="ltr">

```bash
moav client connect user1              # تشخیص خودکار بهترین پروتکل
moav client connect user1 --protocol reality   # انتخاب پروتکل خاص
moav client connect user1 --protocol hysteria2
```

</div>

کلاینت ارائه می‌دهد:
- پراکسی SOCKS5 روی پورت 1080 (قابل تنظیم با `CLIENT_SOCKS_PORT`)
- پراکسی HTTP روی پورت 8080 (قابل تنظیم با `CLIENT_HTTP_PORT`)

پروتکل‌های موجود: `reality`، `trojan`، `hysteria2`، `wireguard`، `dnstt`، `psiphon`، `tor`

ساخت ایمیج کلاینت به صورت جداگانه:

<div dir="ltr">

```bash
moav client build
```

</div>

## مدیریت Conduit

اگر Psiphon Conduit برای اهدای پهنای باند اجرا می‌کنید:

<div dir="ltr">

```bash
moav logs conduit             # مشاهده لاگ‌های conduit
./scripts/conduit-stats.sh    # مشاهده آمار ترافیک زنده بر اساس کشور
./scripts/conduit-info.sh     # دریافت لینک عمیق Ryve برای وارد کردن در موبایل
```

</div>

## اپلیکیشن‌های کلاینت

| پلتفرم | اپلیکیشن‌های توصیه شده |
|--------|----------------------|
| iOS | Shadowrocket، Hiddify، WireGuard، TrustTunnel، Psiphon، Streisand |
| Android | v2rayNG، Hiddify، WireGuard، TrustTunnel، Psiphon، NekoBox |
| macOS | Hiddify، Streisand، WireGuard، TrustTunnel، Psiphon |
| Windows | v2rayN، Hiddify، WireGuard، TrustTunnel، Psiphon |
| Linux | Hiddify، sing-box، WireGuard، TrustTunnel |

برای دستورالعمل‌های راه‌اندازی به [docs/CLIENTS.md](docs/CLIENTS.md) مراجعه کنید.

## مستندات

- [راهنمای نصب](docs/SETUP.md) - دستورالعمل‌های کامل نصب
- [مرجع CLI](docs/CLI.md) - تمام دستورات و گزینه‌های moav
- [پیکربندی DNS](docs/DNS.md) - تنظیم رکوردهای DNS
- [راه‌اندازی کلاینت](docs/CLIENTS.md) - نحوه اتصال از دستگاه‌ها
- [نصب روی VPS](docs/DEPLOY.md) - نصب یک‌کلیکی روی سرور ابری
- [مانیتورینگ](docs/MONITORING.md) - Grafana + Prometheus برای نظارت
- [عیب‌یابی](docs/TROUBLESHOOTING.md) - مشکلات رایج و راه‌حل‌ها
- [راهنمای امنیت عملیاتی](docs/OPSEC.md) - بهترین روش‌های امنیتی

## پیش‌نیازها

**سرور:**
- Debian 12، Ubuntu 22.04/24.04
- حداقل 1 vCPU، 1 GB RAM (2 vCPU، 2 GB RAM برای مانیتورینگ)
- IPv4 عمومی
- نام دامنه (اختیاری - حالت بدون دامنه را ببینید)

**پورت‌ها (در صورت نیاز باز کنید):**

| پورت | پروتکل | سرویس | نیاز به دامنه |
|------|--------|-------|---------------|
| 443/tcp | TCP | Reality (VLESS) | بله |
| 443/udp | UDP | Hysteria2 | بله |
| 8443/tcp | TCP | Trojan | بله |
| 4443/tcp+udp | TCP+UDP | TrustTunnel | بله |
| 2082/tcp | TCP | CDN WebSocket | بله (Cloudflare) |
| 51820/udp | UDP | WireGuard | خیر |
| 8080/tcp | TCP | wstunnel | خیر |
| 9443/tcp | TCP | داشبورد ادمین | خیر |
| 9444/tcp | TCP | Grafana (مانیتورینگ) | خیر |
| 53/udp | UDP | تونل DNS | بله |
| 80/tcp | TCP | Let's Encrypt | بله (هنگام نصب) |

### حالت بدون دامنه

دامنه ندارید؟ MoaV می‌تواند در **حالت بدون دامنه** با سرویس‌های زیر اجرا شود:
- **WireGuard** (UDP مستقیم + تونل WebSocket)
- **داشبورد ادمین** (با گواهی خودامضا)
- **Conduit** (اهدای پهنای باند Psiphon)
- **Snowflake** (اهدای پهنای باند Tor)

دستور `moav` را اجرا کنید و وقتی پرسیده شد "بدون دامنه" را انتخاب کنید، یا از `moav domainless` استفاده کنید.

**VPS توصیه شده:**
- VPS Price Trackers: [VPS-PRICES](https://vps-prices.com/)، [VPS Price Tracker](https://vpspricetracker.com/), [Cheap VPS Price Cheat Sheet](https://docs.google.com/spreadsheets/d/e/2PACX-1vTOC_THbM2RZzfRUhFCNp3SDXKdYDkfmccis4vxr7WtVIcPmXM-2lGKuZTBr8o_MIJ4XgIUYz1BmcqM/pubhtml)
- [Time4VPS](https://www.time4vps.com/?affid=8471): 1 vCPU، 1GB RAM، IPv4، 3.99€/ماه 

## ساختار پروژه

<div dir="ltr">

```
MoaV/
├── moav.sh                 # ابزار مدیریت CLI (نصب با: ./moav.sh install)
├── docker-compose.yml      # فایل compose اصلی
├── .env.example            # قالب متغیرهای محیطی
├── Dockerfile.*            # تعاریف کانتینر
├── configs/                # پیکربندی‌های سرویس‌ها
│   ├── sing-box/
│   ├── wireguard/
│   └── dnstt/
├── scripts/                # اسکریپت‌های مدیریت
│   ├── bootstrap.sh
│   ├── user-add.sh
│   ├── user-revoke.sh
│   └── lib/
├── outputs/                # پیکربندی‌های تولید شده (gitignore شده)
│   └── bundles/
├── web/                    # وب‌سایت پوششی
├── admin/                  # داشبورد آمار
└── docs/                   # مستندات
```

</div>

## امنیت

- تمام پروتکل‌ها نیاز به احراز هویت دارند
- وب‌سایت پوششی برای ترافیک احراز هویت نشده
- اعتبارنامه‌های جداگانه برای هر کاربر با قابلیت لغو فوری
- حداقل لاگ‌گیری (بدون URL، بدون محتوا)
- TLS 1.3 همه جا

برای راهنمای امنیتی به [docs/OPSEC.md](docs/OPSEC.md) مراجعه کنید.

## مجوز

MIT

## سلب مسئولیت

این پروژه **فقط نرم‌افزار شبکه متن‌باز با کاربرد عمومی** ارائه می‌دهد.

این یک سرویس، پلتفرم، یا شبکه عملیاتی نیست.

نویسندگان و مشارکت‌کنندگان:
- زیرساختی را اداره نمی‌کنند
- دسترسی ارائه نمی‌دهند
- اعتبارنامه توزیع نمی‌کنند
- کاربران را مدیریت نمی‌کنند
- استقرارها را هماهنگ نمی‌کنند

تمام استفاده، استقرار و بهره‌برداری مسئولیت کامل اشخاص ثالث است.

این نرم‌افزار **«همانطور که هست»** ارائه می‌شود، بدون هیچ گونه ضمانتی.
نویسندگان و مشارکت‌کنندگان **هیچ مسئولیتی** در قبال هرگونه استفاده یا سوء استفاده از این نرم‌افزار نمی‌پذیرند.

کاربران مسئول رعایت تمام قوانین و مقررات قابل اعمال هستند.

</div>
