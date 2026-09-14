# BaToHub

BaToHub یک مرکز مدیریت ماژولار و مبتنی بر رابط ت extant است که با Bash نوشته شده و برای پنل‌های VPN و پروکسی طراحی شده است.

## BaToHub چیست و چیست نیست

BaToHub یک رابط واحد برای مدیریت چندین پنل از یک سرور است.

BaToHub:
- نصب‌کننده پنل نیست
- خود یک پنل نیست
- سرویس پردرآمد نیست
- سیستمی برایの施行 مجوز نیست
- نرم‌افزار نظارت نیست
- پلتفرمی برای اجرای کد از راه دور نیست

BaToHub فقط تغییرات خود را مدیریت می‌کند. پنل‌ها را حذف یا داده‌های پنلی را پاک نمی‌کند.

## پنل‌های پشتیبانی‌شده

پنل‌های پشتیبانی‌شده در این انتشار:
- Rebecca
- PasarGuard
- 3X-UI (Sanaei)

Marzban پشتیبانی نمی‌شود.

## ویژگی‌ها

هسته:
- انتخاب اولیه متح Fred-panel
- persist کردن پنل در `/etc/batohub/panel.conf`
- منوی اصلی وابسته به پنل
- اطلاعات سرور
- بروزرسانی خودکارBaToHub از GitHub
- بررسی‌های تمامیت برای فایل‌های مدیریت‌شده
- پشتیبان، بازیابی و درج
- حذف نصب که پنل‌ها را سالم نگه می‌دارد
- دسترسی‌های امن برای ذخیره‌ی حالت

مدیریت پنل:
- کارت legend پنل و گزارش نسخه
- وضعیت پنل
- مدیریت SSL اختصاصی پنل
- قالب‌های اشتراک اختصاصی پنل
- لاگ‌های پنل
- بروزرسانی و وضعیت پنل

امنیت و کیفیت:
- `set -euo pipefail` در کل منابعシェล
- انباردن‌های متغیر عطف‌القاعده
- فایل‌های موقت از `mktemp`
- قفل کردن حالت مشترک در جای‌جای مناسب
- هیچ اشاره‌کننده تماس در کد منبع
- بدون نظارت یا فراخوانی شبکه در هسته

## معماری

```
/opt/BaToHub/
  bin/
    batohub
    uninstall
  core/
    main.sh
    module_loader.sh
    panel_manager.sh
    ssl_manager.sh
    template_manager.sh
    backup_manager.sh
    update.sh
  lib/
    common.sh
  security/
    integrity.sh
  panels/
    <panel>/
      panel.json
      module.sh
      ssl/module.sh
      templates/module.sh
      templates/subscription/index.html
      update/module.sh
      menu/module.sh
  templates/
  VERSION
  manifest.json
```

مسیرهای سیستم:
```
/etc/batohub/
  panel.conf
  batohub.conf
  integrity.sha256
/var/lib/batohub/
/var/log/batohub/
/usr/local/bin/BaToHub -> /opt/BaToHub/bin/batohub
```

جریان کاری:
1. اجرای `BaToHub` منجر به اجرای `bin/batohub` می‌شود.
2. `bin/batohub` `core/main.sh` را اجرا می‌کند.
3. `main.sh` کشف پنل را از `panels/` بارگذاری می‌کند.
4. اگر پنلی پیکربندی نشده باشد، انتخاب اولیه متح Fred-panel نمایش داده می‌شود.
5. انتخاب پنل در `panel.conf` persist می‌شود.
6. منوی وابسته به پنل بارگذاری می‌شود.
7. عملیات از طریق ماژول‌های پنل مسیر می‌یابند.

## پیش‌نیازها

سیستم‌عامل:
- Ubuntu 22.04 LTS
- Ubuntu 24.04 LTS

معماری:
- amd64
- arm64

پیش‌نیازها:
- bash
- curl
- ca-certificates
- openssl
- unzip
- rsync
- python3
- jq
- certbot برای SSL Rebecca

دسترسی root برای نصب و بیشتر عملیات مدیریتی لازم است.

## نصب سریع

این دستور را به عنوان root_exec کنید:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/isAsli/BaTo-Hub/main/install.sh)
```

این کار موارد زیر را انجام می‌دهد:
- بررسی دسترسی root
- نصب بسته‌های سیستم لازم
- ایجاد دایرکتوری‌های اصلی زیر `/opt/BaToHub`
- تنظیم دسترسی‌ها
- نصب دستور جهانی
- نوشتن منmanifest تمامیت

بعد از نصب، این دستور را اجرا کنید:

```bash
BaToHub
```

## نصب دستی

1. منبع را در محل موقتی روی سرور دانلود کنید.
2. `install.sh` را به عنوان root_exec کنید.
3. وجود دستور جهانی را تأیید کنید.
4. `BaToHub` را اجرا کنید و در صورت نیاز یک پنل را انتخاب کنید.

مثال:

```bash
apt-get update
apt-get install -y curl ca-certifications openssl unzip rsync python3 jq certbot
bash ./install.sh
BaToHub
```

## تأیید پس از نصب

بعد از نصب، بررسی کنید:
- `BaToHub` شروع می‌شود
- نسخه با `VERSION` همخوانی دارد
- `/etc/batohub/panel.conf` برای همه قابل خواندن نیست
- `/etc/batohub/batohub.conf` برای همه قابل خواندن نیست
- `/etc/batohub/integrity.sha256` وجود دارد
- `/var/lib/batohub` و `/var/log/batohub` دسترسی‌های صحیح دارند

## شروع سریع

1. `BaToHub` را اجرا کنید.
2. اگر تقاضا شده، یک پنل را انتخاب کنید.
3. از منوی پنل برای SSL، قالب‌ها، بروزرسانی، لاگ، پشتیبان، بازیابی یا درج استفاده کنید.

## مرجع دستورها

| دستور | کاربرد |
| --- | --- |
| `BaToHub` | باز کردن منوی مرکزی |
| `install.sh` | نصبBaToHub به عنوان root |
| `bin/uninstall` | حذف فایل‌های مدیریت‌شدهBaToHub با تأیید |
| `sha256sum -c /etc/batohub/integrity.sha256` | بررسی تمامیت فایل‌های مدیریت‌شده |

اقدامات منویی شکلی هستند.-action‌های تخریب‌کاران نیاز به عبارت تأیید صریح دارند.

## سیستم پنل

هر پنل دایرکتوری‌ای تحت `panels/<name>` با حداقل موارد زیر است:
- `panel.json`
- `module.sh`

`panel.json` پنل را توصیف می‌کند:

```json
{
  "name": "example",
  "display_name": "Example",
  "version": "0.0.2",
  "description": "Example panel",
  "service_name": "example",
  "default_port": "80",
  "default_path": "/opt/example",
  "config_paths": ["/opt/example/.env"],
  "requirements": ["curl", "ca-certificates", "openssl"],
  "ssl_method": "manual",
  "template_method": "disabled"
}
```

`module.sh` رابط پنل را exporse می‌کند:
- `panel_detect`
- `panel_version`
- `panel_status`
- `panel_install`
- `panel_uninstall`
- `panel_ssl_issue`
- `panel_ssl_renew`
- `panel_template_apply`
- `panel_template_remove`
- `panel_logs`
- `panel_update`
- `panel_menu`

مثال نوشتن یک پنل جدید:

1. `panels/<name>/panel.json` را ایجاد کنید.
2. `panels/<name>/module.sh` را ایجاد کنید.
3. توابع لازم را پیاده‌سازی کنید.
4. اگر پنل از SSL یا قالب پشتیبانی کند، `ssl/module.sh` و `templates/module.sh` را اضافه کنید.
5. پس از اضافه کردن پنل، `install.sh` را اجرا کنید.

## مرجع پیکربندی

### batohub.conf

| کلید | توضیح | پیش‌فرض |
| --- | --- | --- |
| `APP_NAME` | نام برنامه | `BaToHub` |
| `APP_VERSION` | نسخه برنامه | `0.0.2` |
| `GITHUB_REPO` | مخزنGitHub | `isAsli/BaTo-Hub` |
| `GITHUB_BRANCH` | شاخه مورد استفاده برای بروزرسانی | `main` |
| `UPDATE_MANIFEST` | URLmanifest استفاده‌شده برای بررسی‌های بروزرسانی | به‌صورت مرکزی پیکربندی‌شده |
| `INSTALL_DIR` | دایرکتوری اصلی برنامه | `/opt/batohub` |
| `CONFIG_DIR` | دایرکتوری پیکربندی | `/etc/batohub` |
| `STATE_DIR` | دایرکتوری حالت پایدار | `/var/lib/batohub` |
| `LOG_DIR` | دایرکتوری لاگ | `/var/log/batohub` |
| `STATE_DIR_MODE` | حالت برای دایرکتوری‌های حالت | `750` |
| `BACKUP_DIR` | دایرکتوری پشتیبان | `/var/lib/batohub/backups` |
| `BACKUP_KEEP` | تعداد پشتیبان‌های نگهداری‌شده | `5` |
| `GLOBAL_CMD_NAME` | مسیر دستور جهانی | `/usr/local/bin/BaToHub` |

### panel.conf

| کلید | توضیح | مثال |
| --- | --- | --- |
| `PANEL` | نام پنل انتخاب‌شده | `rebecca` |
| `PANEL_PORT` | پورت پنل | `8080` |
| `PANEL_PATH` | مسیر پنل | `/opt/rebecca` |
| `PANEL_DOMAIN` | دامنه پنل اگر شناخته شده باشد | `example.test` |
| `INSTALLED_AT` | زمان نصب | `2026-09-14 10:00:00` |

## پشتیبان، بازیابی و درج

پشتیبان شامل:
- `/etc/batohub`
- `/var/lib/batohub`
- `/var/log/batohub`
- مسیرهای پیکربندی اختصاصی پنل
- فایل‌های گواهی و کلید SSL استفاده‌شده توسط پنل
- قالب‌های اعمال‌شده توسطBaToHub
- metadata با نسخه، نام پنل، نسخه پنل، timestamp و فایل‌های مدیریت‌شده

فرمت پشتیبان:
- بستarette.gzip فشرده
- در `/var/lib/batohub/backups/<timestamp>.tar.gz` ذخیره می‌شود
- فایل checksum در کنار آن
- دسترسی‌ها 600، مالک root:root
- چرخش تعداد پشتیبان‌های پیکربندی‌شده را نگه می‌دارد

بازیابی:
- پشتیبان‌ها را با تاریخ و اندازه لیست کنید
- قبل از بازیابی checksum را تأیید کنید
- به یک دایرکتوری موقت استخراج کنید
- فایل‌ها را به صورت تراکنش‌ای در جای خود بگذارید
- قبل از بازیابی یک پشتیبان ایمنی بسازید
- فایل‌های خارج از مسیرهای اعلامی را بازنویسی نکنید

درج:
- یک فایل پشتیبان را از مسیر خارجی درج کنید
- اگر checksum موجود باشد، آن را تأیید کنید
- از همان جریان بازیابی تراکنش‌ای استفاده کنید

## بروزرسانی خود

منبع حقیقت مخزنGitHub `isAsli/BaTo-Hub`، شاخه `main` است.

رفتار بروزرسانی:
- در صورت موجودی از git استفاده کنید، در غیر این صورت به بررسی‌های HTTPS 回落 کنید
- قبل از بروزرسانی یک پشتیبان کامل بسازید
- فایل‌های محلی را در مقابل از راه دور مقایسه کنید
- فایل‌های جدید از راه دور را اضافه کنید
- فایل‌های حذف‌شده از راه دور را تنها در صورتی حذف کنید که مدیریت‌شده توسط کاربر نباشند
- فایل‌های تغییر یافته را جایگزین کنید
- فایل‌های غیر تغییر یافته را دست‌نخورده بگذارید

فایل‌هایی که هرگز نباید توسط بروزرسانی بازنویسی شوند:
- `/etc/batohub/panel.conf`
- `/etc/batohub/batohub.conf`
- `/var/lib/batohub`
- `/var/log/batohub`
- هر مسیری که در پیکربندی پنل به عنوان مدیریت‌شده توسط کاربر اعلامی شده باشد

بعد از بروزرسانی:
- روی فایل‌هایシェล`bash -n` را اجرا کنید
- تأیید کنید کشف پنل هنوز کار می‌کند
- خلاصه تفاوت چاپ کنید
- در صورت شکست تأیید، به‌صورت خودکار برگردید

## مدل امنیتی

BaToHub از موارد زیر استفاده می‌کند:
- پیکربندی مرکزی با دسترسی‌های محدود
- منmanifest تمامیت برای فایل‌های مدیریت‌شده
- نوشتارهای قفل‌شده برای حالت مشترک در جای‌جای مناسب
- `mktemp` برای فایل‌های موقت
- انباردن‌های عطف‌القاعده و حالتシェل سخت
- دسترسی‌های محدود بر روی کلیدهای خصوصی و پیکربندی حساس
- گزارش‌گیری متن ساده بدون escapes ترمینال

محدودیت‌ها:
- دسترسی root می‌تواند فایل‌های محلی را تغییر یا حذف کند
- SSL برای Rebecca به Certbot و دسترسی به پورت 80 وابسته است
- اعتماد به بروزرسانی به شاخه مخزن و وجود git وابسته است
- پنل‌های شخص ثالث خارج از کنترلBaToHub هستند، مگر اینکه خود کد یکپارچه‌سازی درگیر باشد

## گزارش‌گیری و عیب‌یابی

لاگ‌ها در مسیر زیر نوشته می‌شوند:
`/var/log/batohub/batohub.log`

بررسی‌های رایج:
- دسترسی‌های `/etc/batohub`، `/var/lib/batohub` و `/var/log/batohub` را تأیید کنید
- `panel.conf` و `batohub.conf` را تأیید کنید
- بررسی تمامیت را اجرا کنید
- لاگ‌ها را برای خطاهای اخیر بررسی کنید
- بررسی کنید که دستورات لازم موجود هستند
- برای SSL Rebecca، دسترسی به پورت 80 را بررسی کنید

## حذف نصب

دستور حذف را از منوی یا مستقیماً اجرا کنید:

```bash
/opt/BaToHub/bin/uninstall
```

نصب‌کننده حذف:
- نشان می‌دهد چه چیزی حذف شود
- تقاضای تأیید دارد
- فایل‌های مالکیتBaToHub را حذف می‌کند
- پنل‌ها و داده‌های پنلی را سالم نگه می‌دارد

## مجوز

BaToHub نرم‌افزار رایگان و متن‌باز است که تحت GNU General Public License نسخه 3 منتشر شده است.

برای متن کامل مجوز به `LICENSE` مراجعه کنید.

https://www.gnu.org/licenses/gpl-3.0.html

## سیاست تغییر و انتشار مجدد

هر استفاده، تغییر، 포크 یا انتشار مجدد باید باGPL-3.0 به‌طور کامل هماهنگ باشد و باید اشاره کپی‌رایت اصلی، نام پروژهBaToHub و آدرس مخزن اصلی را حفظ کند.

نسخه‌های سفارشی یا مالکیتی تحت این مجوز مجاز نیستند. هر کس به نسخه سفارشی نیاز دارد با @DatPHP تماس بگیرد.

## پشتیبانی و تماس

برای پشتیبانی، گزارش باگ و ایده‌ها، با @DatPHP تماس بگیرید.

## سازمان‌دهی

کپی‌رایت (C) BaToHub
