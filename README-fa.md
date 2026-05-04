# Spoof Tunnel Manager

یک منیجر ساده و تعاملی برای پروژه‌ی [`ParsaKSH/spoof-tunnel`](https://github.com/ParsaKSH/spoof-tunnel) که مخصوص **spoof-tunnel v1.0.3** نوشته شده است.

هدف این پروژه این است که نصب، نصب آفلاین، ساخت کانفیگ، ساخت سرویس systemd، مشاهده لاگ، health check و اتصال به X-UI ساده‌تر شود و کاربر مجبور نباشد فایل‌های JSON پیچیده را دستی ویرایش کند.

> فقط روی سرورها و شبکه‌هایی استفاده کنید که مالک آن هستید یا مجوز مدیریت آن‌ها را دارید. Spoof Tunnel برای کار کردن به raw socket و قابلیت ارسال packet اسپوف‌شده در هر دو سمت نیاز دارد.

## قابلیت‌ها

- منوی انگلیسی و قابل فهم
- هدف‌گذاری فقط روی **spoof-tunnel v1.0.3**
- نصب کاملاً آفلاین
- نصب آنلاین از GitHub release
- بدون استفاده از package manager به‌صورت پیش‌فرض
- بدون آپدیت کردن پکیج‌های موجود سیستم
- اگر باینری از قبل نصب باشد، بدون اجازه جایگزین نمی‌شود
- ساخت کانفیگ JSON کلاینت و سرور
- ساخت یا استفاده مجدد از key pair با دستور `spoof keygen`
- ساخت سرویس‌های systemd:
  - `spoof-client`
  - `spoof-server`
- مشاهده لاگ زنده با `journalctl`
- health check پایه
- راهنمای اتصال X-UI به SOCKS5 لوکال
- بکاپ و ریستور کانفیگ
- حذف کامل نصب‌شده‌ها

## نام پیشنهادی ریپازیتوری

پیشنهاد برای GitHub شما:

```bash
github.com/ach1992/spoof-tunnel-manager
```

## فایل‌ها

```text
st-manager.sh   اسکریپت اصلی منیجر
README.md       مستندات انگلیسی
README-fa.md    مستندات فارسی
assets/         پوشه اختیاری برای فایل‌های نصب آفلاین
examples/       پوشه اختیاری برای نمونه‌ها
```

## اجرای آنلاین سریع

بعد از اینکه ریپازیتوری را روی GitHub خودتان منتشر کردید:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ach1992/spoof-tunnel-manager/main/st-manager.sh)
```

سپس از منو انتخاب کنید:

```text
3) Install spoof v1.0.3 from GitHub release (online)
```

منیجر تلاش می‌کند asset مناسب نسخه v1.0.3 را برای معماری سرور پیدا کند. اگر پیدا نشد، فقط در صورتی سراغ build از سورس می‌رود که `go` از قبل روی سیستم وجود داشته باشد. اسکریپت Go نصب نمی‌کند و پکیج‌ها را آپدیت نمی‌کند.

## اجرای آفلاین

این روش برای سرورهایی که به GitHub دسترسی ندارند مناسب‌تر است.

1. روی یک سیستم دارای اینترنت، این ریپازیتوری را دانلود کنید.
2. باینری یا آرشیو سازگار با **spoof-tunnel v1.0.3** را دستی دانلود کنید.
3. یک پوشه بسازید، مثلاً:

```bash
mkdir spoof-script
```

4. فایل‌ها را داخل پوشه قرار دهید:

```text
spoof-script/
├── st-manager.sh
└── spoof                 # یا spoof-linux-amd64 / spoof-linux-arm64 / .tar.gz / .zip
```

یا می‌توانید باینری را اینجا بگذارید:

```text
spoof-script/assets/spoof
```

5. پوشه را به سرور منتقل کنید.
6. اجرا کنید:

```bash
cd spoof-script
sudo bash st-manager.sh --install-offline
```

یا منوی تعاملی را اجرا کنید:

```bash
sudo bash st-manager.sh
```

سپس انتخاب کنید:

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
/etc/spoof-tunnel/backups/
/var/log/spoof-tunnel/
/etc/systemd/system/spoof-client.service
/etc/systemd/system/spoof-server.service
```

## جریان معمول راه‌اندازی

### سمت سرور

```bash
sudo st-manager
```

گزینه زیر را انتخاب کنید:

```text
5) Configure as Server
```

اطلاعاتی که می‌گیرد:

- transport: مقدار `udp` یا `icmp`
- آدرس listen تونل، معمولاً `0.0.0.0`
- پورت تونل، معمولاً `8080`
- IP اسپوف‌شده سمت سرور
- IP اسپوف‌شده مورد انتظار از سمت کلاینت
- IP واقعی کلاینت
- public key کلاینت

در پایان، منیجر اطلاعات pairing سمت سرور را نمایش می‌دهد. آن را به سمت کلاینت بدهید.

### سمت کلاینت

```bash
sudo st-manager
```

گزینه زیر را انتخاب کنید:

```text
4) Configure as Client
```

اطلاعاتی که می‌گیرد:

- transport: باید با سرور یکی باشد
- آدرس SOCKS لوکال، معمولاً `127.0.0.1`
- پورت SOCKS لوکال، معمولاً `1080`
- IP واقعی سرور
- پورت تونل سرور
- IP اسپوف‌شده سمت کلاینت
- IP اسپوف‌شده مورد انتظار از سمت سرور
- public key سرور

در سمت کلاینت یک SOCKS5 لوکال ساخته می‌شود، مثلاً:

```text
127.0.0.1:1080
```

از همین endpoint می‌توانید در X-UI به‌عنوان outbound/proxy از نوع SOCKS5 استفاده کنید.

## مدیریت سرویس‌ها

```bash
sudo st-manager
```

گزینه‌های مهم:

```text
6) Start service
7) Stop service
8) Restart service
9) Service status
10) Live logs
11) Health check
12) X-UI helper
```

دستورات دستی هم قابل استفاده هستند:

```bash
sudo systemctl restart spoof-client
sudo systemctl status spoof-client --no-pager
sudo journalctl -u spoof-client -f
```

سمت سرور:

```bash
sudo systemctl restart spoof-server
sudo systemctl status spoof-server --no-pager
sudo journalctl -u spoof-server -f
```

## اتصال به X-UI

روی سرور مبدأ/کلاینت، در X-UI خروجی یا proxy را به SOCKS5 لوکال وصل کنید:

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

- اسکریپت عمداً از `apt update`، `apt install`، آپگرید پکیج‌ها و نصب اجباری dependency استفاده نمی‌کند.
- نصب آنلاین فقط وقتی ممکن است که `curl` یا `wget` از قبل روی سیستم وجود داشته باشد.
- build از سورس فقط وقتی انجام می‌شود که `go` از قبل روی سیستم نصب باشد.
- برای محیط‌های محدود، نصب آفلاین بهترین حالت است.
- raw socket نیاز به root یا capability مناسب دارد.
- هر دو سرور باید توانایی ارسال packet اسپوف‌شده داشته باشند، وگرنه تونل کار نمی‌کند.

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

یا اگر GitHub CLI دارید:

```bash
gh repo create ach1992/spoof-tunnel-manager --public --source=. --remote=origin --push
```

## لایسنس

MIT
