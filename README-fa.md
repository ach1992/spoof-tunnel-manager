# Spoof Tunnel Manager

یک منیجر ساده و تعاملی برای پروژه‌ی [`ParsaKSH/spoof-tunnel`](https://github.com/ParsaKSH/spoof-tunnel) که مخصوص **spoof-tunnel v1.0.3** نوشته شده است.

هدف این پروژه این است که نصب، نصب آفلاین، ساخت کانفیگ، تبادل کلید، ساخت سرویس systemd، مشاهده لاگ، health check و اتصال به X-UI ساده‌تر شود و کاربر مجبور نباشد فایل‌های JSON پیچیده را دستی ویرایش کند.

> فقط روی سرورها و شبکه‌هایی استفاده شود که مالک آن هستید یا مجوز استفاده دارید. Spoof Tunnel به raw socket و قابلیت IP spoofing روی دو سمت نیاز دارد.

## امکانات

- منوی تعاملی انگلیسی
- هدف‌گذاری فقط روی **spoof-tunnel v1.0.3**
- نصب کاملاً آفلاین
- نصب آنلاین از GitHub release
- عدم استفاده از package manager به‌صورت پیش‌فرض
- عدم اجرای `apt update`، `apt install` یا آپدیت پکیج‌ها
- عدم جایگزینی باینری موجود مگر با تأیید کاربر
- تولید خودکار کلیدهای سرور و کلاینت با `spoof keygen`
- Pairing block برای کپی/پیست راحت بین دو سرور
- تولید کانفیگ JSON برای client/server
- ساخت سرویس‌های systemd:
  - `spoof-client`
  - `spoof-server`
- مشاهده لاگ زنده با `journalctl`
- health check پایه
- راهنمای اتصال X-UI به SOCKS5 لوکال
- بکاپ و ریستور کانفیگ
- حذف کامل

## نام پیشنهادی ریپازیتوری

```bash
github.com/ach1992/spoof-tunnel-manager
```

## فایل‌ها

```text
st-manager.sh   اسکریپت اصلی
README.md       مستندات انگلیسی
README-fa.md    مستندات فارسی
assets/         پوشه اختیاری برای فایل‌های آفلاین
examples/       فایل‌های نمونه
```

## استفاده آنلاین

بعد از اینکه ریپازیتوری را روی GitHub خودت منتشر کردی:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ach1992/spoof-tunnel-manager/main/st-manager.sh)
```

بعد از منو انتخاب کن:

```text
3) Install spoof v1.0.3 from GitHub release (online)
```

اسکریپت تلاش می‌کند asset مناسب نسخه v1.0.3 را برای معماری سرور پیدا کند. اگر نشد، فقط در صورتی از سورس build می‌کند که `go` از قبل روی سرور نصب باشد. خودش Go یا هیچ پکیجی نصب نمی‌کند.

## استفاده آفلاین

این روش برای سرورهایی که دسترسی به GitHub ندارند پیشنهاد می‌شود.

روی یک سیستم دارای اینترنت، فایل manager و باینری سازگار **spoof-tunnel v1.0.3** را دانلود کن. سپس پوشه‌ای مثل زیر بساز:

```text
spoof-script/
├── st-manager.sh
└── spoof                 # یا spoof-linux-amd64 / spoof-linux-arm64 / .tar.gz / .zip
```

یا باینری را اینجا بگذار:

```text
spoof-script/assets/spoof
```

پوشه را به سرور منتقل کن و اجرا کن:

```bash
cd spoof-script
sudo bash st-manager.sh --install-offline
```

یا منوی تعاملی را باز کن:

```bash
sudo bash st-manager.sh
```

و انتخاب کن:

```text
2) Install spoof v1.0.3 from local files (offline)
```

## مسیرهای نصب

```text
/usr/local/bin/st-manager
/usr/local/bin/spoof
/etc/spoof-tunnel/client.json
/etc/spoof-tunnel/server.json
/etc/spoof-tunnel/client.keys
/etc/spoof-tunnel/server.keys
/etc/spoof-tunnel/server.pending
/etc/spoof-tunnel/server.pairing
/etc/spoof-tunnel/client.pairing
/etc/spoof-tunnel/backups/
/var/log/spoof-tunnel/
/etc/systemd/system/spoof-client.service
/etc/systemd/system/spoof-server.service
```

## روش پیشنهادی سه مرحله‌ای

این روش ساده‌ترین حالت است و دیگر لازم نیست public key را دستی پیدا کنی.

### ۱) سمت خارج / سرور: ساخت SERVER pairing

روی سرور خارج اجرا کن:

```bash
sudo st-manager
```

گزینه را انتخاب کن:

```text
4) Server Step 1: generate SERVER pairing
```

اسکریپت کلید سرور را خودکار می‌سازد یا کلید قبلی را reuse می‌کند، اطلاعات سمت سرور را می‌گیرد و خروجی‌ای شبیه این می‌دهد:

```text
-----BEGIN SPOOF-TUNNEL SERVER PAIRING-----
VERSION=v1.0.3
ROLE=server
TRANSPORT=udp
SERVER_REAL_IP=1.2.3.4
SERVER_PORT=8080
SERVER_SPOOF_IP=185.143.233.151
SERVER_PUBLIC_KEY=...
-----END SPOOF-TUNNEL SERVER PAIRING-----
```

این بلاک کامل را کپی کن و ببر روی سرور ایران / کلاینت.

### ۲) سمت ایران / کلاینت: ساخت کانفیگ از SERVER pairing

روی سرور ایران اجرا کن:

```bash
sudo st-manager
```

گزینه را انتخاب کن:

```text
5) Client Step 2: configure from SERVER pairing
```

بلاک SERVER pairing را paste کن. اسکریپت خودش IP سرور، پورت تونل، spoof IP سرور و public key سرور را پر می‌کند. بعد کلید کلاینت را خودکار می‌سازد، `client.json` و سرویس `spoof-client` را ایجاد می‌کند و خروجی‌ای شبیه این می‌دهد:

```text
-----BEGIN SPOOF-TUNNEL CLIENT PAIRING-----
VERSION=v1.0.3
ROLE=client
TRANSPORT=udp
CLIENT_REAL_IP=91.223.116.96
CLIENT_SPOOF_IP=2.188.21.151
CLIENT_PUBLIC_KEY=...
LOCAL_SOCKS=127.0.0.1:1080
-----END SPOOF-TUNNEL CLIENT PAIRING-----
```

این بلاک کامل را کپی کن و برگردان روی سرور خارج.

### ۳) سمت خارج / سرور: نهایی‌سازی از CLIENT pairing

روی سرور خارج اجرا کن:

```bash
sudo st-manager
```

گزینه را انتخاب کن:

```text
6) Server Step 3: finalize from CLIENT pairing
```

بلاک CLIENT pairing را paste کن. اسکریپت `server.json` و سرویس `spoof-server` را ایجاد می‌کند.

### ۴) اجرای سرویس‌ها

روی سرور خارج:

```bash
sudo systemctl restart spoof-server
sudo systemctl status spoof-server --no-pager
```

روی سرور ایران:

```bash
sudo systemctl restart spoof-client
sudo systemctl status spoof-client --no-pager
```

یا از منو استفاده کن:

```text
9) Start service
12) Service status
13) Live logs
14) Health check
```

## حالت دستی

برای کاربران حرفه‌ای حالت دستی هم وجود دارد:

```text
7) Manual configure as Client
8) Manual configure as Server
```

در حالت دستی باید public key طرف مقابل را از قبل داشته باشی. برای اکثر کاربران همان روش سه مرحله‌ای بهتر است.

## اتصال به X-UI

روی سرور ایران / کلاینت، X-UI باید به SOCKS5 لوکال ساخته‌شده توسط spoof-tunnel وصل شود:

```text
Protocol: SOCKS5
Address : 127.0.0.1
Port    : 1080
Username: empty
Password: empty
```

برای دیدن endpoint فعلی:

```bash
sudo st-manager --xui-helper
```

## نکات و محدودیت‌ها

- اسکریپت عمداً `apt update`، `apt install`، آپدیت پکیج یا نصب اجباری dependency انجام نمی‌دهد.
- نصب آنلاین به `curl` یا `wget` از قبل نصب‌شده نیاز دارد.
- build از سورس فقط وقتی انجام می‌شود که `go` از قبل نصب باشد.
- برای محیط‌های محدود، نصب آفلاین بهترین گزینه است.
- raw socket به root یا capability مناسب نیاز دارد.
- هر دو سرور باید بتوانند spoofed packet ارسال کنند، وگرنه تونل کار نمی‌کند.

## انتشار روی GitHub

از داخل پوشه پروژه:

```bash
git init
git add .
git commit -m "Initial Spoof Tunnel Manager"
git branch -M main
git remote add origin https://github.com/ach1992/spoof-tunnel-manager.git
git push -u origin main
```

یا با GitHub CLI:

```bash
gh repo create ach1992/spoof-tunnel-manager --public --source=. --remote=origin --push
```
